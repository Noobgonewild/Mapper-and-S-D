snd = snd or {}
snd.db = snd.db or {}

local luasql = require "luasql.sqlite3"

snd.db.env = nil
snd.db.conn = nil
snd.db.isOpen = false
snd.db.schemaReady = false
snd.db.mobTagsBaseReady = false
snd.db.areaCache = nil
snd.db.seenCache = snd.db.seenCache or {}
snd.db.seenCacheLastPrune = snd.db.seenCacheLastPrune or 0
snd.db.seenCooldownSeconds = 300       -- 5 minutes
snd.db.seenCacheMaxAgeSeconds = 3600   -- 1 hour
snd.db.killCache = snd.db.killCache or {}
snd.db.killCacheLastPrune = snd.db.killCacheLastPrune or 0
snd.db.killCooldownSeconds = 3          -- dedupe duplicate kill events for same mob+room
snd.db.killCacheMaxAgeSeconds = 30      -- short-lived kill dedupe cache
snd.db.schemaVersion = 7
snd.db.createdEmpty = false

snd.db.file = getMudletHomeDir() .. "/SnDdb.db"

local SND_CORE_TABLES = { "area", "mobs", "mob_keyword_exceptions", "history" }
local SND_REQUIRED_COLUMNS = {
    area = { "name", "key", "minlvl", "maxlvl", "lock", "startRoom", "noquest", "vidblain", "userKey" },
    mobs = { "mob", "room", "roomid", "zone", "seen_count", "kill_count", "last_seen", "last_killed" },
    mob_keyword_exceptions = { "area_name", "mob_name", "keyword" },
    history = { "id", "type", "level_taken", "start_time", "end_time", "status", "qp_rewards", "tp_rewards", "train_rewards", "prac_rewards", "gold_rewards" },
}
local SND_PRE_TIMESTAMP_REQUIRED_COLUMNS = {
    area = SND_REQUIRED_COLUMNS.area,
    mobs = { "mob", "room", "roomid", "zone", "seen_count", "kill_count" },
    mob_keyword_exceptions = SND_REQUIRED_COLUMNS.mob_keyword_exceptions,
    history = SND_REQUIRED_COLUMNS.history,
}
local SND_HISTORY_SCHEMA_SQL = {
    [[CREATE TABLE IF NOT EXISTS history (
        id INTEGER PRIMARY KEY,
        type INTEGER NOT NULL,
        level_taken INTEGER NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        status INTEGER DEFAULT 1,
        qp_rewards INTEGER DEFAULT 0,
        tp_rewards INTEGER DEFAULT 0,
        train_rewards INTEGER DEFAULT 0,
        prac_rewards INTEGER DEFAULT 0,
        gold_rewards INTEGER DEFAULT 0)]],
    [[CREATE INDEX IF NOT EXISTS history_end_time_status_type ON history(end_time, status, type)]],
    [[CREATE INDEX IF NOT EXISTS history_start_time_type ON history(start_time, type)]],
    [[CREATE INDEX IF NOT EXISTS history_type_status ON history(type, status)]],
}
local SND_SCHEMA_SQL = {
    [[CREATE TABLE IF NOT EXISTS area (
        name TEXT NOT NULL,
        key TEXT NOT NULL,
        minlvl INTEGER NOT NULL,
        maxlvl INTEGER NOT NULL,
        lock INTEGER NOT NULL,
        startRoom INTEGER,
        noquest TEXT,
        vidblain TEXT,
        userKey TEXT)]],
    [[CREATE TABLE IF NOT EXISTS mobs (
        mob TEXT NOT NULL COLLATE NOCASE,
        room TEXT NOT NULL COLLATE NOCASE,
        roomid INTEGER NOT NULL,
        zone TEXT NOT NULL,
        seen_count INTEGER NOT NULL DEFAULT 0,
        kill_count INTEGER NOT NULL DEFAULT 0,
        last_seen INTEGER,
        last_killed INTEGER,
        UNIQUE(mob, roomid))]],
    [[CREATE TABLE IF NOT EXISTS mob_keyword_exceptions (
        area_name TEXT NOT NULL,
        mob_name TEXT NOT NULL,
        keyword TEXT NOT NULL,
        UNIQUE(area_name, mob_name))]],
    SND_HISTORY_SCHEMA_SQL[1],
    [[CREATE TABLE IF NOT EXISTS campaign_history_identity (
        id INTEGER PRIMARY KEY,
        complete_by TEXT NOT NULL UNIQUE,
        history_id INTEGER NOT NULL UNIQUE)]],
    [[CREATE TABLE IF NOT EXISTS mob_tags (
        id INTEGER PRIMARY KEY,
        mob TEXT NOT NULL COLLATE NOCASE,
        zone TEXT NOT NULL COLLATE NOCASE,
        nowhere INTEGER NOT NULL DEFAULT 0,
        nohunt INTEGER NOT NULL DEFAULT 0,
        priority_room INTEGER DEFAULT NULL,
        UNIQUE(mob, zone))]],
    [[CREATE INDEX IF NOT EXISTS area_key ON area(key)]],
    [[CREATE INDEX IF NOT EXISTS mobs_zone_mob_room ON mobs(zone, mob, room)]],
    SND_HISTORY_SCHEMA_SQL[2],
    SND_HISTORY_SCHEMA_SQL[3],
    SND_HISTORY_SCHEMA_SQL[4],
    [[CREATE INDEX IF NOT EXISTS idx_campaign_identity_complete_by ON campaign_history_identity(complete_by)]],
    [[CREATE INDEX IF NOT EXISTS idx_campaign_identity_history_id ON campaign_history_identity(history_id)]],
    [[CREATE INDEX IF NOT EXISTS idx_mob_tags_zone ON mob_tags(zone)]],
    [[CREATE INDEX IF NOT EXISTS idx_mob_tags_mob ON mob_tags(mob)]],
    [[CREATE UNIQUE INDEX IF NOT EXISTS idx_mob_tags_key_nocase ON mob_tags(lower(mob), lower(zone))]],
}

local function database_file_exists(path)
    local ok, lfs = pcall(require, "lfs")
    if ok and lfs and type(lfs.attributes) == "function" then
        return lfs.attributes(path) ~= nil
    end
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function database_looks_like_sqlite(path)
    local file = io.open(path, "rb")
    if not file then return false end
    local header = file:read(16)
    file:close()
    return header == "SQLite format 3\0"
end

local function close_sql_cursor(cursor)
    local cursor_type = type(cursor)
    if (cursor_type == "userdata" or cursor_type == "table") and type(cursor.close) == "function" then
        pcall(function() cursor:close() end)
    end
end

local function execute_on_connection(conn, sql)
    local result, err = conn:execute(sql)
    if not result then return false, tostring(err) end
    close_sql_cursor(result)
    return true
end

local function table_set_from_connection(conn)
    local cursor, err = conn:execute("SELECT name FROM sqlite_master WHERE type='table'")
    if not cursor then return nil, tostring(err) end
    local tables = {}
    local row = cursor:fetch({}, "a")
    while row do
        tables[tostring(row.name)] = true
        row = cursor:fetch(row, "a")
    end
    close_sql_cursor(cursor)
    return tables
end

local function column_set_from_connection(conn, table_name)
    local safe_name = tostring(table_name):gsub("'", "''")
    local cursor, err = conn:execute("PRAGMA table_info('" .. safe_name .. "')")
    if not cursor then return nil, tostring(err) end
    local columns = {}
    local row = cursor:fetch({}, "a")
    while row do
        columns[tostring(row.name)] = true
        row = cursor:fetch(row, "a")
    end
    close_sql_cursor(cursor)
    return columns
end

local function scalar_from_connection(conn, sql)
    local cursor, err = conn:execute(sql)
    if not cursor then return nil, err end
    local cursor_type = type(cursor)
    if (cursor_type ~= "userdata" and cursor_type ~= "table") or type(cursor.fetch) ~= "function" then
        return cursor
    end
    local row = cursor:fetch({}, "n")
    close_sql_cursor(cursor)
    return row and row[1] or nil
end

local function create_empty_snd_schema(conn)
    local ok, err = execute_on_connection(conn, "BEGIN IMMEDIATE")
    if ok then
        for _, sql in ipairs(SND_SCHEMA_SQL) do
            ok, err = execute_on_connection(conn, sql)
            if not ok then break end
        end
    end
    if ok then
        ok, err = execute_on_connection(conn, "PRAGMA user_version = " .. tostring(snd.db.schemaVersion))
    end
    if ok then
        local committed, commit_err = execute_on_connection(conn, "COMMIT")
        if not committed then
            ok, err = false, commit_err
            pcall(function() conn:execute("ROLLBACK") end)
        end
    else
        pcall(function() conn:execute("ROLLBACK") end)
    end
    return ok, err
end

local function validate_existing_snd_database(conn)
    local tables, err = table_set_from_connection(conn)
    if not tables then return false, err end
    local missing = {}
    for _, name in ipairs(SND_CORE_TABLES) do
        if not tables[name] then table.insert(missing, name) end
    end
    if #missing > 0 then
        return false, "missing core tables: " .. table.concat(missing, ", ")
    end
    local missing_columns = {}
    for table_name, required_columns in pairs(SND_REQUIRED_COLUMNS) do
        local columns, columns_err = column_set_from_connection(conn, table_name)
        if not columns then
            table.insert(missing_columns, table_name .. ".? (" .. tostring(columns_err) .. ")")
        else
            for _, column_name in ipairs(required_columns) do
                if not columns[column_name] then
                    table.insert(missing_columns, table_name .. "." .. column_name)
                end
            end
        end
    end
    if #missing_columns > 0 then
        return false, "missing core columns: " .. table.concat(missing_columns, ", ")
    end
    local integrity, integrity_err = scalar_from_connection(conn, "PRAGMA quick_check")
    if integrity == nil then
        return false, "could not verify SQLite integrity: " .. tostring(integrity_err or "unknown error")
    end
    if tostring(integrity) ~= "ok" then
        return false, "SQLite quick_check: " .. tostring(integrity)
    end
    return true
end

local SND_CLASSIC_AREA_IDENTITY_COLUMNS = {
    "name", "key", "minlvl", "maxlvl", "lock",
}
local SND_CLASSIC_MOB_IDENTITY_COLUMNS = { "mob", "room", "roomid", "zone" }
local SND_NORMALIZED_TABLE_COLUMNS = {
    areas = { "key", "name", "minlvl", "maxlvl", "lock", "start_room", "noquest", "vidblain" },
    mob_sightings = { "mob", "room_name", "roomid", "zone", "seen_count", "last_seen" },
    mob_kills = { "mob", "roomid", "zone", "kill_count", "last_killed" },
    mob_keywords = { "id", "char_id", "zone", "mob_name", "keyword" },
    history = { "id", "char_id", "type", "level_taken", "start_time", "end_time", "status", "qp_base", "qp_bonus", "tp_rewards", "train_rewards", "prac_rewards", "gold_rewards" },
}

local function missing_columns(columns, required)
    local missing = {}
    for _, column_name in ipairs(required) do
        if not columns[column_name] then table.insert(missing, column_name) end
    end
    return missing
end

local function verify_snd_integrity(conn)
    local integrity, integrity_err = scalar_from_connection(conn, "PRAGMA quick_check")
    if integrity == nil then
        return false, "could not verify SQLite integrity: " .. tostring(integrity_err or "unknown error")
    end
    if tostring(integrity) ~= "ok" then
        return false, "SQLite quick_check: " .. tostring(integrity)
    end
    return true
end

local function detect_snd_schema(conn)
    local integrity_ok, integrity_err = verify_snd_integrity(conn)
    if not integrity_ok then return nil, integrity_err end

    local tables, tables_err = table_set_from_connection(conn)
    if not tables then return nil, tables_err end
    local version = tonumber(scalar_from_connection(conn, "PRAGMA user_version")) or 0

    -- A current layout may still need a version stamp or extension tables.
    local current_core = true
    local current_columns = {}
    for table_name, required in pairs(SND_PRE_TIMESTAMP_REQUIRED_COLUMNS) do
        if not tables[table_name] then
            current_core = false
            break
        end
        local columns, columns_err = column_set_from_connection(conn, table_name)
        if not columns then return nil, columns_err end
        current_columns[table_name] = columns
        if #missing_columns(columns, required) > 0 then
            current_core = false
            break
        end
    end
    if current_core then
        local mobs = current_columns.mobs
        local extensions_missing = not tables.campaign_history_identity or not tables.mob_tags
        if tables.mob_tags then
            local tag_columns, columns_err = column_set_from_connection(conn, "mob_tags")
            if not tag_columns then return nil, columns_err end
            extensions_missing = extensions_missing
                or not tag_columns.nowhere
                or not tag_columns.nohunt
                or not tag_columns.priority_room
        end
        return {
            kind = "classic",
            from_version = version,
            tables = tables,
            area_columns = current_columns.area,
            mobs_columns = mobs,
            history_columns = current_columns.history,
            needs_migration = version < snd.db.schemaVersion
                or not mobs.last_seen
                or not mobs.last_killed
                or extensions_missing,
        }
    end

    -- Normalized MUSHclient layouts require data reshaping, not just new tables.
    local normalized = true
    local normalized_columns = {}
    for table_name, required in pairs(SND_NORMALIZED_TABLE_COLUMNS) do
        if not tables[table_name] then
            normalized = false
            break
        end
        local columns, columns_err = column_set_from_connection(conn, table_name)
        if not columns then return nil, columns_err end
        normalized_columns[table_name] = columns
        if #missing_columns(columns, required) > 0 then
            normalized = false
            break
        end
    end
    if normalized then
        if tables.area or tables.mobs or tables.mob_keyword_exceptions or tables._mush_normalized_history then
            return nil, "normalized MUSH schema has conflicting compatibility tables; existing file was left untouched"
        end
        return {
            kind = "normalized_mush",
            from_version = version,
            tables = tables,
            normalized_columns = normalized_columns,
            needs_migration = true,
        }
    end

    -- Classic v0-v5 layouts may safely add missing history and keyword tables.
    if tables.area and tables.mobs then
        local area_columns, area_err = column_set_from_connection(conn, "area")
        if not area_columns then return nil, area_err end
        local mobs_columns, mobs_err = column_set_from_connection(conn, "mobs")
        if not mobs_columns then return nil, mobs_err end
        local missing_area = missing_columns(area_columns, SND_CLASSIC_AREA_IDENTITY_COLUMNS)
        local missing_mobs = missing_columns(mobs_columns, SND_CLASSIC_MOB_IDENTITY_COLUMNS)
        local has_old_counts = mobs_columns.count ~= nil
        local has_split_counts = mobs_columns.seen_count ~= nil and mobs_columns.kill_count ~= nil
        if #missing_area == 0 and #missing_mobs == 0 and (has_old_counts or has_split_counts) then
            local history_columns = nil
            if tables.history then
                local history_err
                history_columns, history_err = column_set_from_connection(conn, "history")
                if not history_columns then return nil, history_err end
                local missing_history = missing_columns(history_columns, SND_PRE_TIMESTAMP_REQUIRED_COLUMNS.history)
                if #missing_history > 0 then
                    return nil, "unrecognized classic history schema; missing columns: " .. table.concat(missing_history, ", ")
                end
            end
            if tables.mob_keyword_exceptions then
                local keyword_columns, keyword_err = column_set_from_connection(conn, "mob_keyword_exceptions")
                if not keyword_columns then return nil, keyword_err end
                local missing_keywords = missing_columns(keyword_columns, SND_REQUIRED_COLUMNS.mob_keyword_exceptions)
                if #missing_keywords > 0 then
                    return nil, "unrecognized keyword schema; missing columns: " .. table.concat(missing_keywords, ", ")
                end
            end
            if tables.mobs_mudlet_v7 then
                return nil, "legacy migration staging table already exists; existing file was left untouched"
            end
            return {
                kind = "classic",
                from_version = version,
                tables = tables,
                area_columns = area_columns,
                mobs_columns = mobs_columns,
                history_columns = history_columns,
                needs_migration = true,
            }
        end
    end

    return nil, "unrecognized S&D schema; expected a supported classic or normalized MUSHclient database"
end

local function ensure_snd_backup_directory(path)
    local ok, lfs = pcall(require, "lfs")
    if ok and lfs and type(lfs.attributes) == "function" and type(lfs.mkdir) == "function" then
        if lfs.attributes(path, "mode") == "directory" then return true end
        if lfs.mkdir(path) or lfs.attributes(path, "mode") == "directory" then return true end
    end
    local is_windows = package.config:sub(1, 1) == "\\"
    local command = is_windows
        and string.format('mkdir "%s"', tostring(path))
        or string.format('mkdir -p "%s"', tostring(path))
    local result = os.execute(command)
    return result == true or result == 0
end

local function snd_sql_quote(value)
    return "'" .. tostring(value or ""):gsub("'", "''") .. "'"
end

local function create_snd_migration_backup(conn)
    local directory = getMudletHomeDir() .. "/db_backups"
    if not ensure_snd_backup_directory(directory) then
        return nil, "unable to create backup directory: " .. tostring(directory)
    end
    local base = tostring(snd.db.file or "SnDdb.db"):match("([^/\\]+)$") or "SnDdb.db"
    base = base:gsub("[/\\:*?\"<>|]", "_")
    local stamp = os.date("!%Y%m%d_%H%M%S")
    local path = string.format("%s/%s.pre-migration.%s.bak", directory, base, stamp)
    local suffix = 1
    while database_file_exists(path) do
        path = string.format("%s/%s.pre-migration.%s_%d.bak", directory, base, stamp, suffix)
        suffix = suffix + 1
    end
    local ok, err = execute_on_connection(conn, "VACUUM INTO " .. snd_sql_quote(path))
    if not ok then return nil, "transactional SQLite backup failed: " .. tostring(err) end
    return path
end

local function run_snd_schema_sql(conn)
    for _, sql in ipairs(SND_SCHEMA_SQL) do
        -- Delay this index until initialize() removes case-only duplicate tags.
        if not sql:find("idx_mob_tags_key_nocase", 1, true) then
            local ok, err = execute_on_connection(conn, sql)
            if not ok then return false, err end
        end
    end
    return true
end

local function add_column_if_missing(conn, table_name, columns, column_name, definition)
    if columns[column_name] then return true end
    local ok, err = execute_on_connection(conn,
        "ALTER TABLE " .. table_name .. " ADD COLUMN " .. definition)
    if ok then columns[column_name] = true end
    return ok, err
end

local function migrate_classic_snd(conn, plan)
    local ok, err = add_column_if_missing(conn, "area", plan.area_columns, "startRoom", "startRoom INTEGER")
    if ok then ok, err = add_column_if_missing(conn, "area", plan.area_columns, "noquest", "noquest TEXT") end
    if ok then ok, err = add_column_if_missing(conn, "area", plan.area_columns, "vidblain", "vidblain TEXT") end
    if ok then ok, err = add_column_if_missing(conn, "area", plan.area_columns, "userKey", "userKey TEXT") end
    if not ok then return false, err end

    if plan.mobs_columns.count and not plan.mobs_columns.seen_count then
        ok, err = execute_on_connection(conn, SND_SCHEMA_SQL[3])
        if ok and plan.mobs_columns.keyword then
            ok, err = execute_on_connection(conn, [[
                INSERT OR IGNORE INTO mob_keyword_exceptions(area_name, mob_name, keyword)
                SELECT zone, mob, keyword FROM mobs
                WHERE keyword IS NOT NULL AND trim(keyword) <> ''
                ORDER BY zone, mob]])
        end
        if ok then
            ok, err = execute_on_connection(conn, [[
                CREATE TABLE mobs_mudlet_v7 (
                    mob TEXT NOT NULL COLLATE NOCASE,
                    room TEXT NOT NULL COLLATE NOCASE,
                    roomid INTEGER NOT NULL,
                    zone TEXT NOT NULL,
                    seen_count INTEGER NOT NULL DEFAULT 0,
                    kill_count INTEGER NOT NULL DEFAULT 0,
                    last_seen INTEGER,
                    last_killed INTEGER,
                    UNIQUE(mob, roomid))]])
        end
        if ok then
            ok, err = execute_on_connection(conn, [[
                INSERT INTO mobs_mudlet_v7(mob, room, roomid, zone, seen_count, kill_count)
                SELECT mob COLLATE NOCASE, MAX(room) COLLATE NOCASE, roomid, MAX(zone),
                       SUM(COALESCE(count, 0)), 0
                FROM mobs GROUP BY lower(mob), roomid]])
        end
        if ok then ok, err = execute_on_connection(conn, "DROP TABLE mobs") end
        if ok then ok, err = execute_on_connection(conn, "ALTER TABLE mobs_mudlet_v7 RENAME TO mobs") end
    else
        ok, err = add_column_if_missing(conn, "mobs", plan.mobs_columns, "last_seen", "last_seen INTEGER")
        if ok then
            ok, err = add_column_if_missing(conn, "mobs", plan.mobs_columns, "last_killed", "last_killed INTEGER")
        end
    end
    if not ok then return false, err end
    return run_snd_schema_sql(conn)
end

local function migrate_normalized_snd(conn)
    local ok, err = execute_on_connection(conn, SND_SCHEMA_SQL[1])
    if ok then
        ok, err = execute_on_connection(conn, [[
            INSERT INTO area(name, key, minlvl, maxlvl, lock, startRoom, noquest, vidblain, userKey)
            SELECT name, key, minlvl, maxlvl, lock, start_room,
                   CASE WHEN CAST(noquest AS INTEGER) <> 0 THEN 'yes' ELSE '' END,
                   CASE WHEN CAST(vidblain AS INTEGER) <> 0 THEN 'yes' ELSE '' END,
                   NULL
            FROM areas]])
    end
    if ok then ok, err = execute_on_connection(conn, SND_SCHEMA_SQL[2]) end
    if ok then
        ok, err = execute_on_connection(conn, [[
            INSERT OR IGNORE INTO mobs(mob, room, roomid, zone, seen_count, kill_count, last_seen, last_killed)
            SELECT s.mob, s.room_name, s.roomid, s.zone, COALESCE(s.seen_count, 0),
                   COALESCE(k.kill_count, 0), s.last_seen, k.last_killed
            FROM mob_sightings AS s
            LEFT JOIN mob_kills AS k
              ON lower(k.mob) = lower(s.mob) AND k.roomid = s.roomid]])
    end
    if ok then
        ok, err = execute_on_connection(conn, [[
            INSERT OR IGNORE INTO mobs(mob, room, roomid, zone, seen_count, kill_count, last_seen, last_killed)
            SELECT k.mob, '', k.roomid, k.zone, 0, COALESCE(k.kill_count, 0), NULL, k.last_killed
            FROM mob_kills AS k
            WHERE NOT EXISTS (
              SELECT 1 FROM mob_sightings AS s
              WHERE lower(s.mob) = lower(k.mob) AND s.roomid = k.roomid)]])
    end
    if ok then ok, err = execute_on_connection(conn, SND_SCHEMA_SQL[3]) end
    if ok then
        ok, err = execute_on_connection(conn, [[
            INSERT OR IGNORE INTO mob_keyword_exceptions(area_name, mob_name, keyword)
            SELECT zone, mob_name, keyword FROM mob_keywords
            ORDER BY CASE WHEN char_id IS NULL THEN 0 ELSE 1 END, id]])
    end
    if ok then ok, err = execute_on_connection(conn, "ALTER TABLE history RENAME TO _mush_normalized_history") end
    if ok then ok, err = execute_on_connection(conn, SND_HISTORY_SCHEMA_SQL[1]) end
    if ok then
        ok, err = execute_on_connection(conn, [[
            INSERT INTO history(id, type, level_taken, start_time, end_time, status,
                                qp_rewards, tp_rewards, train_rewards, prac_rewards, gold_rewards)
            SELECT id, type, level_taken, start_time, end_time, status,
                   COALESCE(qp_base, 0) + COALESCE(qp_bonus, 0),
                   tp_rewards, train_rewards, prac_rewards, gold_rewards
            FROM _mush_normalized_history]])
    end
    if not ok then return false, err end
    return run_snd_schema_sql(conn)
end

local function ensure_mob_tag_columns(conn)
    local tables, tables_err = table_set_from_connection(conn)
    if not tables then return false, tables_err end
    if not tables.mob_tags then return true end
    local columns, columns_err = column_set_from_connection(conn, "mob_tags")
    if not columns then return false, columns_err end
    local ok, err = add_column_if_missing(conn, "mob_tags", columns, "nowhere", "nowhere INTEGER NOT NULL DEFAULT 0")
    if ok then ok, err = add_column_if_missing(conn, "mob_tags", columns, "nohunt", "nohunt INTEGER NOT NULL DEFAULT 0") end
    if ok then ok, err = add_column_if_missing(conn, "mob_tags", columns, "priority_room", "priority_room INTEGER DEFAULT NULL") end
    return ok, err
end

local function migrate_snd_database(conn, plan)
    local backup_path, backup_err = create_snd_migration_backup(conn)
    if not backup_path then
        return false, "automatic migration was not started because the backup failed: " .. tostring(backup_err)
    end

    local ok, err = execute_on_connection(conn, "BEGIN IMMEDIATE")
    if ok then
        if plan.kind == "normalized_mush" then
            ok, err = migrate_normalized_snd(conn)
        else
            ok, err = migrate_classic_snd(conn, plan)
        end
    end
    if ok then ok, err = ensure_mob_tag_columns(conn) end
    if ok then
        ok, err = execute_on_connection(conn, "PRAGMA user_version = " .. tostring(snd.db.schemaVersion))
    end
    if ok then ok, err = validate_existing_snd_database(conn) end
    if ok then
        local committed, commit_err = execute_on_connection(conn, "COMMIT")
        if not committed then
            ok, err = false, commit_err
            pcall(function() conn:execute("ROLLBACK") end)
        end
    else
        pcall(function() conn:execute("ROLLBACK") end)
    end

    if not ok then
        return false, "automatic S&D migration failed and was rolled back: " .. tostring(err) ..
            ". Pre-migration backup: " .. tostring(backup_path)
    end
    return true, backup_path
end

function snd.db.open()
    if snd.db.isOpen then
        return true
    end
    
    snd.db.env = luasql.sqlite3()
    if not snd.db.env then
        snd.utils.errorNote("Failed to create LuaSQL environment")
        return false
    end
    
    -- Opening SQLite creates missing files. Upgrade only recognized layouts,
    -- transactionally and with backup; never rewrite unrelated/corrupt files.
    local existed = database_file_exists(snd.db.file)
    if existed and not database_looks_like_sqlite(snd.db.file) then
        snd.db.env:close()
        snd.db.env = nil
        snd.utils.errorNote("Existing database file is not valid SQLite and was left untouched: " .. tostring(snd.db.file))
        return false
    end
    local err
    snd.db.conn, err = snd.db.env:connect(snd.db.file)
    if not snd.db.conn then
        snd.db.env:close()
        snd.db.env = nil
        snd.utils.errorNote("Failed to open database: " .. tostring(err))
        return false
    end

    if existed then
        local plan, detection_err = detect_snd_schema(snd.db.conn)
        if not plan then
            snd.db.conn:close()
            snd.db.env:close()
            snd.db.conn = nil
            snd.db.env = nil
            snd.utils.errorNote("Existing database was left untouched: " .. tostring(detection_err))
            snd.utils.infoNote("Expected S&D database path: " .. tostring(snd.db.file))
            return false
        end
        local migrated = false
        local migration_backup = nil
        if plan.needs_migration then
            local migration_ok, migration_result = migrate_snd_database(snd.db.conn, plan)
            if not migration_ok then
                snd.db.conn:close()
                snd.db.env:close()
                snd.db.conn = nil
                snd.db.env = nil
                snd.utils.errorNote(tostring(migration_result))
                snd.utils.infoNote("Expected S&D database path: " .. tostring(snd.db.file))
                return false
            end
            migrated = true
            migration_backup = migration_result
        end
        local valid, validation_err = validate_existing_snd_database(snd.db.conn)
        if not valid then
            snd.db.conn:close()
            snd.db.env:close()
            snd.db.conn = nil
            snd.db.env = nil
            snd.utils.errorNote("Existing database was left untouched: " .. tostring(validation_err))
            snd.utils.infoNote("Expected S&D database path: " .. tostring(snd.db.file))
            return false
        end
        snd.db.createdEmpty = false
        if migrated then
            local source_label = plan.kind == "normalized_mush"
                and "normalized MUSHclient schema"
                or ("schema v" .. tostring(plan.from_version or 0))
            snd.utils.infoNote("Automatically upgraded S&D database from " .. source_label ..
                " to schema v" .. tostring(snd.db.schemaVersion) .. ".")
            snd.utils.infoNote("Pre-migration backup: " .. tostring(migration_backup))
        end
    else
        local created, create_err = create_empty_snd_schema(snd.db.conn)
        if not created then
            snd.db.conn:close()
            snd.db.env:close()
            snd.db.conn = nil
            snd.db.env = nil
            snd.utils.errorNote("Could not initialize new S&D database at " .. tostring(snd.db.file) .. ": " .. tostring(create_err))
            snd.utils.infoNote("The failed database file was not deleted or replaced.")
            return false
        end
        snd.db.createdEmpty = true
    end

    snd.db.isOpen = true
    snd.utils.debugNote("Database opened: " .. snd.db.file)
    return true
end

function snd.db.close()
    if snd.db.conn then
        snd.db.conn:close()
        snd.db.conn = nil
    end
    if snd.db.env then
        snd.db.env:close()
        snd.db.env = nil
    end
    snd.db.isOpen = false
    snd.db.schemaReady = false
    snd.db.mobTagsBaseReady = false
    snd.db.areaCache = nil
end

-- Session-only by design.
function snd.db.clearSeenCache()
    snd.db.seenCache = {}
    snd.db.seenCacheLastPrune = os.time()
end

function snd.db.clearKillCache()
    snd.db.killCache = {}
    snd.db.killCacheLastPrune = os.time()
end

function snd.db.pruneSeenCache(now)
    now = tonumber(now) or os.time()
    local maxAge = tonumber(snd.db.seenCacheMaxAgeSeconds) or 3600
    for key, ts in pairs(snd.db.seenCache or {}) do
        if (now - (tonumber(ts) or 0)) > maxAge then
            snd.db.seenCache[key] = nil
        end
    end
    snd.db.seenCacheLastPrune = now
end

function snd.db.pruneKillCache(now)
    now = tonumber(now) or os.time()
    local maxAge = tonumber(snd.db.killCacheMaxAgeSeconds) or 30
    for key, ts in pairs(snd.db.killCache or {}) do
        if (now - (tonumber(ts) or 0)) > maxAge then
            snd.db.killCache[key] = nil
        end
    end
    snd.db.killCacheLastPrune = now
end

-- Kept separate to avoid changing the shared history schema.
function snd.db.ensureCampaignIdentityTable()
    if not snd.db.isOpen then
        if not snd.db.open() then
            return false
        end
    end

    local ok = snd.db.execute([[
        CREATE TABLE IF NOT EXISTS campaign_history_identity (
            id INTEGER PRIMARY KEY,
            complete_by TEXT NOT NULL UNIQUE,
            history_id INTEGER NOT NULL UNIQUE
        )
    ]])
    if not ok then return false end

    snd.db.execute("CREATE INDEX IF NOT EXISTS idx_campaign_identity_complete_by ON campaign_history_identity (complete_by)")
    snd.db.execute("CREATE INDEX IF NOT EXISTS idx_campaign_identity_history_id ON campaign_history_identity (history_id)")
    return true
end

function snd.db.ensureMobTagsTable()
    if snd.db.schemaReady then
        return true
    end
    if not snd.db.isOpen then
        if not snd.db.open() then
            return false
        end
    end

    if not snd.db.mobTagsBaseReady then
        local ok = snd.db.execute([[
            CREATE TABLE IF NOT EXISTS mob_tags (
                id INTEGER PRIMARY KEY,
                mob TEXT NOT NULL COLLATE NOCASE,
                zone TEXT NOT NULL COLLATE NOCASE,
                nowhere INTEGER NOT NULL DEFAULT 0,
                nohunt INTEGER NOT NULL DEFAULT 0,
                priority_room INTEGER DEFAULT NULL,
                UNIQUE(mob, zone)
            )
        ]])
        if not ok then return false end
        local zoneIndexOk = snd.db.execute("CREATE INDEX IF NOT EXISTS idx_mob_tags_zone ON mob_tags(zone)")
        local mobIndexOk = snd.db.execute("CREATE INDEX IF NOT EXISTS idx_mob_tags_mob ON mob_tags(mob)")
        snd.db.mobTagsBaseReady = zoneIndexOk and mobIndexOk
    end
    if not snd.db.mobTagsBaseReady then return false end

    -- Older DBs may fail here until base readiness permits duplicate normalization.
    local keyIndexOk = snd.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_mob_tags_key_nocase ON mob_tags(lower(mob), lower(zone))")
    snd.db.schemaReady = keyIndexOk == true
    return true
end

function snd.db.initialize(silent)
    if not silent then
        snd.utils.debugNote("Initializing database...")
    end
    
    if not snd.db.open() then
        return false
    end
    snd.db.clearSeenCache()
    snd.db.clearKillCache()
    
    local tables = snd.db.getTables()
    if not silent then
        snd.utils.debugNote("Found tables: " .. table.concat(tables, ", "))
    end

    snd.db.ensureCampaignIdentityTable()
    snd.db.ensureMobTagsTable()
    snd.db.normalizeMobTagRows()
    snd.db.ensureMobTagsTable()
    if snd.db.loadAreaCache then
        snd.db.loadAreaCache()
    end
    
    local stats = snd.db.getStats()
    if not silent then
        if snd.db.createdEmpty then
            snd.utils.infoNote("Created new empty S&D database: " .. tostring(snd.db.file))
            snd.utils.errorNote("The new SnDdb.db has 0 mobs and 0 areas. Replace it manually with the supplied populated SnDdb.db if you want preloaded search data.")
        else
            snd.utils.infoNote(string.format("Database loaded: %d mobs, %d areas, %d keywords",
                stats.mobs, stats.areas, stats.keywords))
            if stats.mobs == 0 and stats.areas == 0 then
                snd.utils.errorNote("SnDdb.db is valid but empty. Replace it manually with the supplied populated SnDdb.db if you want preloaded search data.")
            end
        end
    end
    
    return true
end

local function normalizeMobTagZone(zone)
    local fallbackZone = (snd.room and snd.room.current and snd.room.current.arid) or ""
    return tostring(zone or fallbackZone):lower()
end

local function normalizeMobTagName(mobName)
    local raw = snd.utils and snd.utils.trim(tostring(mobName or "")) or tostring(mobName or "")
    return raw:lower()
end

function snd.db.normalizeMobTagRows()
    if not snd.db.ensureMobTagsTable() then return false end
    local rows = snd.db.query("SELECT id, mob, zone, nowhere, nohunt, priority_room FROM mob_tags ORDER BY id ASC") or {}
    if #rows == 0 then return true end

    local keptByKey = {}
    for _, row in ipairs(rows) do
        local mob = normalizeMobTagName(row.mob)
        local zone = normalizeMobTagZone(row.zone)
        local key = mob .. "|" .. zone
        local id = tonumber(row.id) or 0
        local nowhere = tonumber(row.nowhere) == 1
        local nohunt = tonumber(row.nohunt) == 1
        local priority = tonumber(row.priority_room)

        local keep = keptByKey[key]
        if not keep then
            keptByKey[key] = {
                id = id,
                mob = mob,
                zone = zone,
                nowhere = nowhere,
                nohunt = nohunt,
                priority_room = priority,
            }
        else
            keep.nowhere = keep.nowhere or nowhere
            keep.nohunt = keep.nohunt or nohunt
            if (not keep.priority_room or keep.priority_room <= 0) and priority and priority > 0 then
                keep.priority_room = priority
            end
            snd.db.execute(string.format("DELETE FROM mob_tags WHERE id = %d", id))
        end
    end

    for _, keep in pairs(keptByKey) do
        local sql = string.format(
            "UPDATE mob_tags SET mob=%s, zone=%s, nowhere=%d, nohunt=%d, priority_room=%s WHERE id=%d",
            snd.db.escape(keep.mob),
            snd.db.escape(keep.zone),
            keep.nowhere and 1 or 0,
            keep.nohunt and 1 or 0,
            (keep.priority_room and keep.priority_room > 0) and tostring(math.floor(keep.priority_room)) or "NULL",
            keep.id
        )
        snd.db.execute(sql)
    end

    return true
end

function snd.db.ensureMobTagRow(mobName, zone)
    if not snd.db.ensureMobTagsTable() then return false end
    local mob = normalizeMobTagName(mobName)
    local normalizedZone = normalizeMobTagZone(zone)
    if mob == "" or normalizedZone == "" then return false end
    local sql = string.format(
        "INSERT OR IGNORE INTO mob_tags (mob, zone) VALUES (%s, %s)",
        snd.db.escape(mob),
        snd.db.escape(normalizedZone)
    )
    return snd.db.execute(sql)
end

function snd.db.getMobTags(mobName, zone)
    if not snd.db.ensureMobTagsTable() then return nil end
    local mob = normalizeMobTagName(mobName)
    local normalizedZone = normalizeMobTagZone(zone)
    if mob == "" or normalizedZone == "" then return nil end
    local sql = string.format(
        "SELECT id, mob, zone, nowhere, nohunt, priority_room FROM mob_tags WHERE lower(mob)=lower(%s) AND lower(zone)=lower(%s) LIMIT 1",
        snd.db.escape(mob),
        snd.db.escape(normalizedZone)
    )
    local rows = snd.db.query(sql) or {}
    if #rows == 0 then return nil end
    local row = rows[1]
    return {
        id = tonumber(row.id),
        mob = row.mob,
        zone = row.zone,
        nowhere = tonumber(row.nowhere) == 1,
        nohunt = tonumber(row.nohunt) == 1,
        priority_room = tonumber(row.priority_room),
    }
end

function snd.db.toggleMobTag(mobName, zone, flag)
    if flag ~= "nowhere" and flag ~= "nohunt" then return nil end
    local mob = normalizeMobTagName(mobName)
    local normalizedZone = normalizeMobTagZone(zone)
    if mob == "" or normalizedZone == "" then return nil end
    snd.db.ensureMobTagRow(mob, normalizedZone)
    local current = snd.db.getMobTags(mob, normalizedZone) or {}
    local currentVal = current[flag] and 1 or 0
    local nextVal = (currentVal == 1) and 0 or 1
    local sql = string.format(
        "UPDATE mob_tags SET %s=%d WHERE lower(mob)=lower(%s) AND lower(zone)=lower(%s)",
        flag, nextVal, snd.db.escape(mob), snd.db.escape(normalizedZone)
    )
    if snd.db.execute(sql) then
        return nextVal == 1
    end
    return nil
end

function snd.db.setMobPriorityRoom(mobName, zone, roomId)
    local mob = normalizeMobTagName(mobName)
    local normalizedZone = normalizeMobTagZone(zone)
    if mob == "" or normalizedZone == "" then return false end
    snd.db.ensureMobTagRow(mob, normalizedZone)
    local rid = tonumber(roomId)
    local valueSql = rid and tostring(math.floor(rid)) or "NULL"
    local sql = string.format(
        "UPDATE mob_tags SET priority_room=%s WHERE lower(mob)=lower(%s) AND lower(zone)=lower(%s)",
        valueSql, snd.db.escape(mob), snd.db.escape(normalizedZone)
    )
    return snd.db.execute(sql)
end

function snd.db.clearMobTags(mobName, zone)
    local mob = normalizeMobTagName(mobName)
    local normalizedZone = normalizeMobTagZone(zone)
    if mob == "" or normalizedZone == "" then return false end
    local sql = string.format(
        "DELETE FROM mob_tags WHERE lower(mob)=lower(%s) AND lower(zone)=lower(%s)",
        snd.db.escape(mob), snd.db.escape(normalizedZone)
    )
    return snd.db.execute(sql)
end

function snd.db.listMobTags(zone, search)
    if not snd.db.ensureMobTagsTable() then return {} end
    local where = {}
    if zone and snd.utils.trim(zone) ~= "" then
        table.insert(where, "lower(zone)=lower(" .. snd.db.escape(normalizeMobTagZone(zone)) .. ")")
    end
    if search and snd.utils.trim(search) ~= "" then
        table.insert(where, "lower(mob) LIKE lower(" .. snd.db.escape("%" .. snd.utils.trim(search) .. "%") .. ")")
    end
    table.insert(where, "(nowhere=1 OR nohunt=1 OR priority_room IS NOT NULL)")
    local sql = "SELECT id, mob, zone, nowhere, nohunt, priority_room FROM mob_tags WHERE " .. table.concat(where, " AND ") .. " ORDER BY zone, mob"
    local rows = snd.db.query(sql) or {}
    local out = {}
    for _, row in ipairs(rows) do
        table.insert(out, {
            id = tonumber(row.id),
            mob = row.mob or "",
            zone = row.zone or "",
            nowhere = tonumber(row.nowhere) == 1,
            nohunt = tonumber(row.nohunt) == 1,
            priority_room = tonumber(row.priority_room),
        })
    end
    return out
end

function snd.db.deleteMobTagById(id)
    local n = tonumber(id)
    if not n then return false end
    local sql = string.format("DELETE FROM mob_tags WHERE id = %d", math.floor(n))
    return snd.db.execute(sql)
end

function snd.db.getTables()
    local tables = {}
    if not snd.db.isOpen then return tables end
    
    local cursor = snd.db.conn:execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    )
    if cursor then
        local row = cursor:fetch({}, "a")
        while row do
            table.insert(tables, row.name)
            row = cursor:fetch(row, "a")
        end
        cursor:close()
    end
    return tables
end

local function connection_scalar(sql)
    if not snd.db.isOpen or not snd.db.conn then return nil end
    return scalar_from_connection(snd.db.conn, sql)
end

function snd.db.getStatus()
    local status = {
        filename = "SnDdb.db",
        path = snd.db.file,
        exists = database_file_exists(snd.db.file),
        expectedSchema = snd.db.schemaVersion,
        createdEmpty = snd.db.createdEmpty == true,
    }
    if not status.exists then
        status.state = "NOT FOUND"
        return status
    end
    if not snd.db.isOpen and not snd.db.open() then
        status.state = "FOUND BUT CANNOT OPEN"
        return status
    end
    local valid, validation_err = validate_existing_snd_database(snd.db.conn)
    if not valid then
        status.state = "FOUND BUT INVALID"
        status.error = validation_err
        return status
    end
    status.schemaVersion = tonumber(connection_scalar("PRAGMA user_version")) or 0
    status.integrity = tostring(connection_scalar("PRAGMA quick_check") or "unknown")
    status.state = status.integrity == "ok" and "FOUND" or "FOUND BUT INVALID"
    if status.state ~= "FOUND" then
        status.error = "SQLite quick_check: " .. status.integrity
    end
    return status
end

function snd.db.query(sql)
    if not snd.db.isOpen then
        if not snd.db.open() then
            return nil
        end
    end
    
    local cursor, err = snd.db.conn:execute(sql)
    if not cursor then
        snd.utils.debugNote("Query error: " .. tostring(err))
        snd.utils.debugNote("SQL: " .. sql)
        return nil
    end
    
    local results = {}
    local row = cursor:fetch({}, "a")
    while row do
        -- Copy because the cursor reuses its row table.
        local newRow = {}
        for k, v in pairs(row) do
            newRow[k] = v
        end
        table.insert(results, newRow)
        row = cursor:fetch(row, "a")
    end
    cursor:close()
    
    return results
end

function snd.db.execute(sql)
    if not snd.db.isOpen then
        if not snd.db.open() then
            return false
        end
    end
    
    local result, err = snd.db.conn:execute(sql)
    if not result then
        snd.utils.debugNote("Execute error: " .. tostring(err))
        snd.utils.debugNote("SQL: " .. sql)
        return false
    end
    
    return true
end

function snd.db.escape(str)
    if str == nil then
        return "NULL"
    end
    str = tostring(str)
    str = str:gsub("'", "''")
    return "'" .. str .. "'"
end

local function prepareMobSeenWrite(mobName, roomName, roomId, zone, now)
    mobName = tostring(mobName or "")
    if mobName == "" or roomId == nil then return nil end
    if mobName:match("%(wounded%)") or mobName:match("%(aimed%)") then return nil end

    roomName = tostring(roomName or "")
    zone = tostring(zone or (snd.room.current and snd.room.current.arid) or "")
    roomId = tonumber(roomId) or 0
    now = tonumber(now) or os.time()
    local cacheKey = string.format("%s|%d", mobName:lower(), roomId)
    local lastSeen = snd.db.seenCache and snd.db.seenCache[cacheKey] or nil
    local cooldown = tonumber(snd.db.seenCooldownSeconds) or 300
    if lastSeen and (now - lastSeen) < cooldown then return nil end

    local sql = string.format(
        "INSERT INTO mobs (mob, room, roomid, zone, seen_count, kill_count, last_seen, last_killed) " ..
        "VALUES (%s, %s, %d, %s, 1, 0, %d, NULL) " ..
        "ON CONFLICT(mob, roomid) DO UPDATE SET " ..
        "room = excluded.room, zone = excluded.zone, " ..
        "seen_count = mobs.seen_count + 1, last_seen = excluded.last_seen",
        snd.db.escape(mobName),
        snd.db.escape(roomName),
        roomId,
        snd.db.escape(zone),
        now
    )
    return {sql = sql, cacheKey = cacheKey, now = now}
end

function snd.db.recordMobSeen(mobName, roomName, roomId, zone)
    local now = os.time()
    local lastPrune = tonumber(snd.db.seenCacheLastPrune) or 0
    if (now - lastPrune) > 60 then snd.db.pruneSeenCache(now) end
    local write = prepareMobSeenWrite(mobName, roomName, roomId, zone, now)
    if not write then return false end
    if snd.db.execute(write.sql) then
        snd.db.seenCache[write.cacheKey] = write.now
        return true
    end
    return false
end

-- Commit only completed consider rosters; existing cache/clearing policy remains authoritative.
function snd.db.recordMobSeenBatch(sightings)
    if type(sightings) ~= "table" or #sightings == 0 then return true, 0 end
    local now = os.time()
    local lastPrune = tonumber(snd.db.seenCacheLastPrune) or 0
    if (now - lastPrune) > 60 then snd.db.pruneSeenCache(now) end

    local writes, queued = {}, {}
    for _, sighting in ipairs(sightings) do
        local write = prepareMobSeenWrite(
            sighting.mob or sighting.name,
            sighting.roomName or sighting.room,
            sighting.roomId or sighting.rmid,
            sighting.zone or sighting.arid,
            now)
        if write and not queued[write.cacheKey] then
            queued[write.cacheKey] = true
            writes[#writes + 1] = write
        end
    end
    if #writes == 0 then return true, 0 end
    if not snd.db.isOpen and not snd.db.open() then return false, 0 end
    if not snd.db.execute("BEGIN IMMEDIATE") then return false, 0 end

    for _, write in ipairs(writes) do
        if not snd.db.execute(write.sql) then
            pcall(function() snd.db.conn:execute("ROLLBACK") end)
            return false, 0
        end
    end
    if not snd.db.execute("COMMIT") then
        pcall(function() snd.db.conn:execute("ROLLBACK") end)
        return false, 0
    end
    for _, write in ipairs(writes) do
        snd.db.seenCache[write.cacheKey] = write.now
    end
    return true, #writes
end

function snd.db.recordMobKill(mobName, roomId, roomName, zone)
    if not mobName or mobName == "" then return end
    if not roomId then return end
    
    roomId = tonumber(roomId) or 0

    roomName = roomName or (snd.room.current and snd.room.current.name) or ""
    zone = zone or (snd.room.current and snd.room.current.arid) or ""

    local now = os.time()
    local cacheKey = string.format("%s|%d", tostring(mobName):lower(), roomId)
    local lastKill = snd.db.killCache and snd.db.killCache[cacheKey] or nil
    local cooldown = tonumber(snd.db.killCooldownSeconds) or 3
    if lastKill and (now - lastKill) < cooldown then
        return
    end

    local lastPrune = tonumber(snd.db.killCacheLastPrune) or 0
    if (now - lastPrune) > 10 then
        snd.db.pruneKillCache(now)
    end

    local sql = string.format(
        "INSERT INTO mobs (mob, room, roomid, zone, seen_count, kill_count, last_seen, last_killed) " ..
        "VALUES (%s, %s, %d, %s, 1, 1, %d, %d) " ..
        "ON CONFLICT(mob, roomid) DO UPDATE SET " ..
        "room = excluded.room, zone = excluded.zone, " ..
        "kill_count = mobs.kill_count + 1, last_killed = excluded.last_killed",
        snd.db.escape(mobName),
        snd.db.escape(roomName),
        roomId,
        snd.db.escape(zone),
        now,
        now
    )
    if snd.db.execute(sql) then
        snd.db.killCache[cacheKey] = now
    end
end

function snd.db.searchMobs(searchTerm, zone)
    if not searchTerm or searchTerm == "" then
        return {}
    end
    
    local sql
    if zone and zone ~= "" then
        sql = string.format(
            "SELECT * FROM mobs WHERE mob LIKE %s AND zone = %s ORDER BY mob",
            snd.db.escape("%" .. searchTerm .. "%"),
            snd.db.escape(zone)
        )
    else
        sql = string.format(
            "SELECT * FROM mobs WHERE mob LIKE %s ORDER BY mob",
            snd.db.escape("%" .. searchTerm .. "%")
        )
    end
    
    return snd.db.query(sql) or {}
end

function snd.db.getMobLocations(mobName, zone, opts)
    if not mobName then return {} end
    opts = opts or {}
    local useLegacySql = opts.legacy == true
    local roomHint = snd.utils and snd.utils.trim and snd.utils.trim(opts.roomHint or "") or tostring(opts.roomHint or "")
    if snd.db.ensureMobTagsTable then
        snd.db.ensureMobTagsTable()
    end

    local function fetchLocations(name)
        local sql
        if zone and zone ~= "" then
            if useLegacySql then
                sql = string.format(
                    [[
                        SELECT m.*,
                               mt.priority_room,
                               mt.nowhere,
                               mt.nohunt,
                               CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END AS priority_match
                        FROM mobs m
                        LEFT JOIN mob_tags mt
                          ON mt.mob = m.mob
                         AND mt.zone = m.zone
                        WHERE m.mob = %s AND m.zone = %s
                        ORDER BY priority_match DESC, m.seen_count DESC, m.kill_count DESC, m.roomid ASC
                    ]],
                    snd.db.escape(name),
                    snd.db.escape(zone)
                )
            else
                if roomHint ~= "" then
                    sql = string.format([[
                        SELECT * FROM (
                            SELECT m.*,
                                   mt.priority_room,
                                   mt.nowhere,
                                   mt.nohunt,
                                   CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END AS priority_match,
                                    ROW_NUMBER() OVER (
                                        PARTITION BY m.mob, m.zone
                                        ORDER BY
                                            CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END DESC,
                                            m.seen_count DESC,
                                            m.kill_count DESC,
                                            m.roomid ASC
                                    ) AS rn
                            FROM mobs m
                            LEFT JOIN mob_tags mt
                              ON mt.mob = m.mob
                             AND mt.zone = m.zone
                            WHERE m.mob = %s
                              AND m.zone = %s
                              AND m.room = %s
                        ) ranked
                        WHERE rn = 1
                        ORDER BY priority_match DESC, seen_count DESC, kill_count DESC, roomid ASC
                    ]],
                        snd.db.escape(name),
                        snd.db.escape(zone),
                        snd.db.escape(roomHint)
                    )
                else
                    sql = string.format([[
                        SELECT * FROM (
                            SELECT m.*,
                                   mt.priority_room,
                                   mt.nowhere,
                                   mt.nohunt,
                                   CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END AS priority_match,
                                    ROW_NUMBER() OVER (
                                        PARTITION BY m.mob, m.zone
                                        ORDER BY
                                            CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END DESC,
                                            m.seen_count DESC,
                                            m.kill_count DESC,
                                            m.roomid ASC
                                    ) AS rn
                            FROM mobs m
                            LEFT JOIN mob_tags mt
                              ON mt.mob = m.mob
                             AND mt.zone = m.zone
                            WHERE m.mob = %s AND m.zone = %s
                        ) ranked
                        WHERE rn = 1
                        ORDER BY priority_match DESC, seen_count DESC, kill_count DESC, roomid ASC
                    ]],
                        snd.db.escape(name),
                        snd.db.escape(zone)
                    )
                end
            end
        else
            if useLegacySql then
                sql = string.format(
                    [[
                        SELECT m.*,
                               mt.priority_room,
                               mt.nowhere,
                               mt.nohunt,
                               CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END AS priority_match
                        FROM mobs m
                        LEFT JOIN mob_tags mt
                          ON mt.mob = m.mob
                         AND mt.zone = m.zone
                        WHERE m.mob = %s
                        ORDER BY priority_match DESC, m.seen_count DESC, m.kill_count DESC, m.roomid ASC
                    ]],
                    snd.db.escape(name)
                )
            else
                if roomHint ~= "" then
                    sql = string.format([[
                        SELECT * FROM (
                            SELECT m.*,
                                   mt.priority_room,
                                   mt.nowhere,
                                   mt.nohunt,
                                   CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END AS priority_match,
                                    ROW_NUMBER() OVER (
                                        PARTITION BY m.mob, m.zone
                                        ORDER BY
                                            CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END DESC,
                                            m.seen_count DESC,
                                            m.kill_count DESC,
                                            m.roomid ASC
                                    ) AS rn
                            FROM mobs m
                            LEFT JOIN mob_tags mt
                              ON mt.mob = m.mob
                             AND mt.zone = m.zone
                            WHERE m.mob = %s
                              AND m.room = %s
                        ) ranked
                        WHERE rn = 1
                        ORDER BY priority_match DESC, seen_count DESC, kill_count DESC, roomid ASC
                    ]],
                        snd.db.escape(name),
                        snd.db.escape(roomHint)
                    )
                else
                    sql = string.format([[
                        SELECT * FROM (
                            SELECT m.*,
                                   mt.priority_room,
                                   mt.nowhere,
                                   mt.nohunt,
                                   CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END AS priority_match,
                                    ROW_NUMBER() OVER (
                                        PARTITION BY m.mob, m.zone
                                        ORDER BY
                                            CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END DESC,
                                            m.seen_count DESC,
                                            m.kill_count DESC,
                                            m.roomid ASC
                                    ) AS rn
                            FROM mobs m
                            LEFT JOIN mob_tags mt
                              ON mt.mob = m.mob
                             AND mt.zone = m.zone
                            WHERE m.mob = %s
                        ) ranked
                        WHERE rn = 1
                        ORDER BY priority_match DESC, seen_count DESC, kill_count DESC, roomid ASC
                    ]],
                        snd.db.escape(name)
                    )
                end
            end
        end

        return snd.db.query(sql) or {}
    end

    local results = fetchLocations(mobName)
    local matchedName = mobName
    if #results == 0 and mobName:find("%-") then
        matchedName = mobName:gsub("%-", " ")
        results = fetchLocations(matchedName)
    end

    if snd.debug and snd.debug.mobTag then
        local parts = {}
        for i, row in ipairs(results or {}) do
            if i > 8 then
                table.insert(parts, "...")
                break
            end
            table.insert(parts, string.format(
                "#%d zone=%s roomid=%s seen=%s kills=%s priority_room=%s priority_match=%s nowhere=%s nohunt=%s",
                i,
                tostring(row.zone or ""),
                tostring(row.roomid or ""),
                tostring(row.seen_count or ""),
                tostring(row.kill_count or ""),
                tostring(row.priority_room or ""),
                tostring(row.priority_match or ""),
                tostring(row.nowhere or ""),
                tostring(row.nohunt or "")
            ))
        end
        snd.debug.mobTag(string.format(
            "getMobLocations mob='%s' matched='%s' zone='%s' legacy=%s roomHint='%s' rows=%d %s",
            tostring(mobName or ""),
            tostring(matchedName or ""),
            tostring(zone or ""),
            tostring(useLegacySql),
            tostring(roomHint or ""),
            #(results or {}),
            table.concat(parts, " | ")
        ))
    end

    return results, matchedName
end

function snd.db.getBestMobLocation(mobName, zone)
    local locations = snd.db.getMobLocations(mobName, zone)
    if #locations > 0 then
        return locations[1]  -- Sorted by priority match, then seen/kill counts.
    end
    return nil
end

local function normalize_area_lookup(value)
    return tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_area_loose(value)
    return normalize_area_lookup(value):gsub("[^%w]", "")
end

function snd.db.invalidateAreaCache()
    snd.db.areaCache = nil
end

function snd.db.loadAreaCache()
    local rows = snd.db.query("SELECT * FROM area ORDER BY key") or {}
    local cache = {
        rows = rows,
        byKey = {},
        byName = {},
        byLooseName = {},
    }
    for _, row in ipairs(rows) do
        local key = normalize_area_lookup(row.key)
        local name = normalize_area_lookup(row.name)
        local looseName = normalize_area_loose(row.name)
        if key ~= "" then cache.byKey[key] = row end
        if name ~= "" and not cache.byName[name] then cache.byName[name] = row end
        if looseName ~= "" and not cache.byLooseName[looseName] then
            cache.byLooseName[looseName] = row
        end
    end
    snd.db.areaCache = cache
    return cache
end

local function get_area_cache()
    return snd.db.areaCache or snd.db.loadAreaCache()
end

local function get_stored_area(areaKey)
    local cache = get_area_cache()
    return cache and cache.byKey[normalize_area_lookup(areaKey)] or nil
end

function snd.db.getArea(areaKey)
    if not areaKey or areaKey == "" then return nil end

    return get_stored_area(areaKey)
end

function snd.db.getAreaKeyFromName(areaName)
    if not areaName or areaName == "" then return nil end

    local trimmed = snd.utils and snd.utils.trim and snd.utils.trim(areaName) or tostring(areaName)
    local cache = get_area_cache()
    local exact = cache and cache.byName[normalize_area_lookup(trimmed)] or nil
    if exact then return exact.key end

    -- Tolerate punctuation drift such as Necromancers' vs Necromancer's Guild.
    local loose = normalize_area_loose(trimmed)
    local normalizedMatch = loose ~= "" and cache and cache.byLooseName[loose] or nil
    if normalizedMatch then return normalizedMatch.key end

    local needle = normalize_area_lookup(trimmed)
    if needle ~= "" and cache then
        for _, row in ipairs(cache.rows) do
            if normalize_area_lookup(row.name):find(needle, 1, true) then
                return row.key
            end
        end
    end

    return nil
end

function snd.db.getOrCreateArea(areaKey, areaName)
    local existing = get_stored_area(areaKey)
    if existing then
        return existing
    end
    
    local defaults = snd.data.areaDefaultStartRooms[areaKey] or {}
    local startRoom = tonumber(defaults.start) or -1
    local vidblain = defaults.vidblain and "yes" or ""
    
    local sql = string.format(
        "INSERT INTO area (name, key, minlvl, maxlvl, lock, startRoom, noquest, vidblain, userKey) " ..
        "VALUES (%s, %s, 0, 0, 0, %d, '', %s, %s)",
        snd.db.escape(areaName or areaKey),
        snd.db.escape(areaKey),
        startRoom,
        snd.db.escape(vidblain),
        snd.db.escape(areaKey)
    )
    snd.db.execute(sql)
    snd.db.invalidateAreaCache()
    return snd.db.getArea(areaKey)
end

function snd.db.setAreaStartRoom(areaKey, roomId)
    if not areaKey or areaKey == "" then return end
    
    roomId = tonumber(roomId) or -1
    
    local existing = get_stored_area(areaKey)
    if existing then
        local sql = string.format(
            "UPDATE area SET startRoom = %d WHERE key = %s",
            roomId,
            snd.db.escape(areaKey)
        )
        snd.db.execute(sql)
        snd.db.invalidateAreaCache()
        snd.utils.infoNote("Updated start room for " .. areaKey .. " to " .. roomId)
    else
        snd.db.getOrCreateArea(areaKey, areaKey)
        snd.db.setAreaStartRoom(areaKey, roomId)
    end
end

function snd.db.getAreaStartRoom(areaKey)
    if not areaKey or areaKey == "" then return -1 end
    
    local area = snd.db.getArea(areaKey)
    if area and area.startRoom and tonumber(area.startRoom) > 0 then
        return tonumber(area.startRoom)
    end
    
    local defaults = snd.data.areaDefaultStartRooms[areaKey]
    if defaults and defaults.start then
        return tonumber(defaults.start) or -1
    end
    
    return -1
end

local function normalizedKeywordMobIdentity(value, ignoreArticle)
    local text = tostring(value or ""):lower()
    text = text:gsub("\27%[[0-9;]*m", "")
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if ignoreArticle then
        text = text:gsub("^an%s+", ""):gsub("^a%s+", ""):gsub("^the%s+", "")
    end
    return text
end

local function keywordMobIdentityVariants(value)
    local full = normalizedKeywordMobIdentity(value, false)
    local loose = normalizedKeywordMobIdentity(value, true)
    local variants, seen = {}, {}
    local function add(candidate)
        if candidate ~= "" and not seen[candidate] then
            seen[candidate] = true
            table.insert(variants, candidate)
        end
    end
    add(full)
    add(loose)
    if loose ~= "" then
        add("a " .. loose)
        add("an " .. loose)
        add("the " .. loose)
    end
    return variants, full
end

local function findMobKeywordRow(areaKey, mobName)
    if not areaKey or not mobName then return nil end

    -- Prefer exact identity; article-free fallback supports aliases without
    -- turning the persisted key into a global override.
    local variants, exactIdentity = keywordMobIdentityVariants(mobName)
    if #variants == 0 then return nil end
    local escapedVariants = {}
    for _, variant in ipairs(variants) do
        table.insert(escapedVariants, snd.db.escape(variant))
    end
    local sql = string.format(
        "SELECT mob_name, keyword FROM mob_keyword_exceptions " ..
        "WHERE area_name = %s COLLATE NOCASE " ..
        "AND mob_name COLLATE NOCASE IN (%s) " ..
        "ORDER BY CASE WHEN mob_name = %s COLLATE NOCASE THEN 0 ELSE 1 END, mob_name LIMIT 1",
        snd.db.escape(areaKey),
        table.concat(escapedVariants, ", "),
        snd.db.escape(exactIdentity)
    )

    local results = snd.db.query(sql)
    if results and #results > 0 then
        return results[1]
    end
    return nil
end

function snd.db.getMobKeyword(areaKey, mobName)
    local row = findMobKeywordRow(areaKey, mobName)
    return row and row.keyword or nil
end

function snd.db.setMobKeyword(areaKey, mobName, keyword)
    areaKey = tostring(areaKey or ""):gsub("^%s+", ""):gsub("%s+$", "")
    mobName = tostring(mobName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    keyword = tostring(keyword or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if areaKey == "" or mobName == "" or keyword == "" then return false end

    -- Atomically replace case/article variants under the legacy UNIQUE constraint.
    local previous = findMobKeywordRow(areaKey, mobName)
    if not snd.db.execute("BEGIN IMMEDIATE") then return false end
    local deleteSql = string.format(
        "DELETE FROM mob_keyword_exceptions " ..
        "WHERE area_name = %s COLLATE NOCASE AND mob_name = %s COLLATE NOCASE",
        snd.db.escape(areaKey),
        snd.db.escape(previous and previous.mob_name or mobName)
    )
    if not snd.db.execute(deleteSql) then
        snd.db.execute("ROLLBACK")
        return false
    end

    local sql = string.format(
        "INSERT INTO mob_keyword_exceptions (area_name, mob_name, keyword) VALUES (%s, %s, %s)",
        snd.db.escape(areaKey),
        snd.db.escape(mobName),
        snd.db.escape(keyword)
    )

    if not snd.db.execute(sql) then
        snd.db.execute("ROLLBACK")
        return false
    end
    if snd.db.execute("COMMIT") then
        snd.utils.infoNote("Set keyword for '" .. mobName .. "' to '" .. keyword .. "' in " .. areaKey)
        return true
    end
    snd.db.execute("ROLLBACK")
    return false
end

function snd.db.deleteMobKeyword(areaKey, mobName)
    if not areaKey or not mobName then return false end
    local stored = findMobKeywordRow(areaKey, mobName)
    if not stored then return false end
    local sql = string.format(
        "DELETE FROM mob_keyword_exceptions " ..
        "WHERE area_name = %s COLLATE NOCASE AND mob_name = %s COLLATE NOCASE",
        snd.db.escape(areaKey),
        snd.db.escape(stored.mob_name)
    )
    return snd.db.execute(sql) == true
end

function snd.db.listMobKeywords(areaKey)
    local sql = "SELECT area_name, mob_name, keyword FROM mob_keyword_exceptions"
    local area = tostring(areaKey or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if area ~= "" then
        sql = sql .. " WHERE area_name = " .. snd.db.escape(area) .. " COLLATE NOCASE"
    end
    sql = sql .. " ORDER BY lower(area_name), lower(mob_name)"
    return snd.db.query(sql) or {}
end

snd.db.HISTORY_TYPE_QUEST = 1
snd.db.HISTORY_TYPE_GQUEST = 2
snd.db.HISTORY_TYPE_CAMPAIGN = 3

snd.db.HISTORY_STATUS_INPROGRESS = 1
snd.db.HISTORY_STATUS_COMPLETE = 2
snd.db.HISTORY_STATUS_TIMEOUT = 3
snd.db.HISTORY_STATUS_FAILED = 4
snd.db.HISTORY_STATUS_RESET = 5
snd.db.HISTORY_STATUS_SKIPPED = 6
snd.db.HISTORY_STATUS_UNDOCUMENTED = 7

function snd.db.purgeStaleQuestHistory(maxAgeSeconds)
    if not snd.db.isOpen then
        return
    end

    local cutoff = os.time() - (tonumber(maxAgeSeconds) or 3600)
    local sql = string.format(
        "DELETE FROM history WHERE type = %d AND status IN (%d, 0) AND start_time > 0 AND start_time <= %d",
        snd.db.HISTORY_TYPE_QUEST,
        snd.db.HISTORY_STATUS_INPROGRESS,
        cutoff
    )
    snd.db.execute(sql)
end

function snd.db.historyStart(historyType, levelTaken, startTime)
    -- History is optional on pre-v6 databases.
    local tables = snd.db.getTables()
    local hasHistory = false
    for _, t in ipairs(tables) do
        if t == "history" then
            hasHistory = true
            break
        end
    end
    
    if not hasHistory then
        snd.utils.debugNote("History table not found, skipping history tracking")
        return
    end

    if tonumber(historyType) == snd.db.HISTORY_TYPE_QUEST then
        snd.db.purgeStaleQuestHistory(3600)
    end
    
    local sql = string.format(
        "INSERT INTO history (type, status, level_taken, start_time, end_time, qp_rewards, tp_rewards, train_rewards, prac_rewards, gold_rewards) " ..
        "VALUES (%d, %d, %d, %d, 0, 0, 0, 0, 0, 0)",
        historyType,
        snd.db.HISTORY_STATUS_INPROGRESS,
        levelTaken or snd.char.level or 0,
        tonumber(startTime) or os.time()
    )
    local ok = snd.db.execute(sql)
    if not ok then
        return nil
    end

    local idRows = snd.db.query("SELECT last_insert_rowid() AS id")
    if idRows and idRows[1] then
        return tonumber(idRows[1].id)
    end
    return nil
end

-- Nil reward arguments intentionally preserve stored values.
function snd.db.historyEnd(historyType, status, rewards, endTime)
    if tonumber(historyType) == snd.db.HISTORY_TYPE_QUEST then
        snd.db.purgeStaleQuestHistory(3600)
    end
    
    local sql = string.format(
        "SELECT rowid AS history_rowid, * FROM history WHERE type = %d AND status IN (%d, 0) ORDER BY start_time DESC LIMIT 1",
        historyType,
        snd.db.HISTORY_STATUS_INPROGRESS
    )
    
    local results = snd.db.query(sql)
    if results and #results > 0 then
        local record = results[1]
        local rowid = tonumber(record.history_rowid or record.rowid or record.ROWID)
        if not rowid then
            snd.utils.debugNote("historyEnd: unable to resolve rowid for latest in-progress history row")
            return nil
        end
        local now = tonumber(endTime) or os.time()
        local updateSql
        if rewards == nil then
            updateSql = string.format(
                "UPDATE history SET status = %d, end_time = %d WHERE rowid = %d",
                status,
                now,
                rowid
            )
        else
            updateSql = string.format(
                "UPDATE history SET status = %d, end_time = %d, qp_rewards = %d, tp_rewards = %d, " ..
                "train_rewards = %d, prac_rewards = %d, gold_rewards = %d WHERE rowid = %d",
                status,
                now,
                rewards.qp or 0,
                rewards.tp or 0,
                rewards.trains or 0,
                rewards.pracs or 0,
                rewards.gold or 0,
                rowid
            )
        end
        local ok = snd.db.execute(updateSql)
        if not ok then
            return nil
        end

        local updatedRows = snd.db.query(string.format("SELECT * FROM history WHERE rowid = %d LIMIT 1", rowid))
        if updatedRows and updatedRows[1] then
            local updated = updatedRows[1]
            local startTime = tonumber(updated.start_time) or 0
            local endTime = tonumber(updated.end_time) or now
            updated.duration_seconds = math.max(0, endTime - startTime)
            return updated
        end
    end
    return nil
end

-- Nil reward arguments intentionally preserve stored values.
function snd.db.historyEndById(historyId, status, rewards)
    historyId = tonumber(historyId)
    if not historyId then
        return nil
    end

    local now = os.time()
    local updateSql
    if rewards == nil then
        updateSql = string.format(
            "UPDATE history SET status = %d, end_time = %d WHERE id = %d",
            status,
            now,
            historyId
        )
    else
        updateSql = string.format(
            "UPDATE history SET status = %d, end_time = %d, qp_rewards = %d, tp_rewards = %d, " ..
            "train_rewards = %d, prac_rewards = %d, gold_rewards = %d WHERE id = %d",
            status,
            now,
            rewards.qp or 0,
            rewards.tp or 0,
            rewards.trains or 0,
            rewards.pracs or 0,
            rewards.gold or 0,
            historyId
        )
    end
    local ok = snd.db.execute(updateSql)
    if not ok then
        return nil
    end

    local updatedRows = snd.db.query(string.format("SELECT * FROM history WHERE id = %d LIMIT 1", historyId))
    if updatedRows and updatedRows[1] then
        local updated = updatedRows[1]
        local startTime = tonumber(updated.start_time) or 0
        local endTime = tonumber(updated.end_time) or now
        updated.duration_seconds = math.max(0, endTime - startTime)
        return updated
    end
    return nil
end

function snd.db.getHistoryIdByCompleteBy(completeBy)
    completeBy = tostring(completeBy or "")
    if completeBy == "" then
        return nil
    end
    snd.db.ensureCampaignIdentityTable()
    local sql = string.format(
        "SELECT history_id FROM campaign_history_identity WHERE complete_by = %s LIMIT 1",
        snd.db.escape(completeBy)
    )
    local rows = snd.db.query(sql)
    if rows and rows[1] then
        return tonumber(rows[1].history_id)
    end
    return nil
end

function snd.db.getCompleteByByHistoryId(historyId)
    historyId = tonumber(historyId)
    if not historyId then
        return ""
    end
    snd.db.ensureCampaignIdentityTable()
    local sql = string.format(
        "SELECT complete_by FROM campaign_history_identity WHERE history_id = %d LIMIT 1",
        historyId
    )
    local rows = snd.db.query(sql)
    if rows and rows[1] then
        return tostring(rows[1].complete_by or "")
    end
    return ""
end

function snd.db.upsertCampaignIdentity(completeBy, historyId)
    completeBy = tostring(completeBy or "")
    historyId = tonumber(historyId)
    if completeBy == "" or not historyId then
        return false
    end
    snd.db.ensureCampaignIdentityTable()

    local sql = string.format(
        "INSERT OR REPLACE INTO campaign_history_identity (id, complete_by, history_id) " ..
        "VALUES ((SELECT id FROM campaign_history_identity WHERE complete_by = %s OR history_id = %d LIMIT 1), %s, %d)",
        snd.db.escape(completeBy),
        historyId,
        snd.db.escape(completeBy),
        historyId
    )
    return snd.db.execute(sql)
end

function snd.db.getLatestCampaignHistoryRow()
    local sql = string.format(
        "SELECT id, status, start_time, end_time, qp_rewards, tp_rewards, train_rewards, prac_rewards, gold_rewards " ..
        "FROM history WHERE type = %d ORDER BY start_time DESC LIMIT 1",
        snd.db.HISTORY_TYPE_CAMPAIGN
    )
    local rows = snd.db.query(sql)
    if rows and rows[1] then
        return rows[1]
    end
    return nil
end

function snd.db.getHistoryById(historyId)
    historyId = tonumber(historyId)
    if not historyId then
        return nil
    end

    local sql = string.format(
        "SELECT * FROM history WHERE id = %d LIMIT 1",
        historyId
    )
    local rows = snd.db.query(sql)
    if rows and rows[1] then
        return rows[1]
    end
    return nil
end

function snd.db.historyUpdateRewardsById(historyId, rewards)
    rewards = rewards or {}
    historyId = tonumber(historyId)
    if not historyId then
        return false
    end

    local updateSql = string.format(
        "UPDATE history SET qp_rewards = %d, tp_rewards = %d, train_rewards = %d, prac_rewards = %d, gold_rewards = %d WHERE id = %d",
        rewards.qp or 0,
        rewards.tp or 0,
        rewards.trains or 0,
        rewards.pracs or 0,
        rewards.gold or 0,
        historyId
    )
    return snd.db.execute(updateSql)
end

function snd.db.getHistoryEntries(opts)
    opts = opts or {}
    local limit = tonumber(opts.limit) or 20
    if limit < 1 then limit = 1 end
    if limit > 200 then limit = 200 end

    snd.db.purgeStaleQuestHistory(3600)

    local tables = snd.db.getTables()
    local hasHistory = false
    for _, t in ipairs(tables) do
        if t == "history" then
            hasHistory = true
            break
        end
    end
    if not hasHistory then
        return {}
    end

    local sql = [[
        SELECT
            rowid,
            type,
            level_taken,
            start_time,
            end_time,
            status,
            qp_rewards,
            tp_rewards,
            train_rewards,
            prac_rewards,
            gold_rewards
        FROM history
        WHERE 1=1
    ]]

    if opts.type then
        sql = sql .. string.format(" AND type = %d", tonumber(opts.type) or 0)
    end

    sql = sql .. string.format(" ORDER BY start_time DESC LIMIT %d", limit)
    return snd.db.query(sql) or {}
end

function snd.db.getHistoryByRowId(rowid)
    rowid = tonumber(rowid)
    if not rowid then
        return nil
    end

    local tables = snd.db.getTables()
    local hasHistory = false
    for _, t in ipairs(tables) do
        if t == "history" then
            hasHistory = true
            break
        end
    end
    if not hasHistory then
        return nil
    end

    local sql = string.format([[
        SELECT
            rowid,
            type,
            level_taken,
            start_time,
            end_time,
            status,
            qp_rewards,
            tp_rewards,
            train_rewards,
            prac_rewards,
            gold_rewards
        FROM history
        WHERE rowid = %d
        LIMIT 1
    ]], rowid)
    local rows = snd.db.query(sql) or {}
    return rows[1]
end

function snd.db.getHistoryStats(historyType, days)
    days = days or 14
    local cutoff = os.time() - (days * 24 * 60 * 60)
    
    local stats = {
        totalQuests = 0,
        totalGquests = 0,
        totalCampaigns = 0,
        totalQP = 0,
        totalTP = 0,
        totalTrains = 0,
        totalPracs = 0,
        totalGold = 0,
    }
    
    local tables = snd.db.getTables()
    local hasHistory = false
    for _, t in ipairs(tables) do
        if t == "history" then
            hasHistory = true
            break
        end
    end
    
    if not hasHistory then
        return stats
    end
    
    local sql = string.format(
        "SELECT * FROM history WHERE status = %d AND end_time >= %d",
        snd.db.HISTORY_STATUS_COMPLETE,
        cutoff
    )
    
    if historyType then
        sql = sql .. string.format(" AND type = %d", historyType)
    end
    
    local records = snd.db.query(sql) or {}
    
    for _, record in ipairs(records) do
        if record.type == snd.db.HISTORY_TYPE_QUEST then
            stats.totalQuests = stats.totalQuests + 1
        elseif record.type == snd.db.HISTORY_TYPE_GQUEST then
            stats.totalGquests = stats.totalGquests + 1
        elseif record.type == snd.db.HISTORY_TYPE_CAMPAIGN then
            stats.totalCampaigns = stats.totalCampaigns + 1
        end
        
        stats.totalQP = stats.totalQP + (tonumber(record.qp_rewards) or 0)
        stats.totalTP = stats.totalTP + (tonumber(record.tp_rewards) or 0)
        stats.totalTrains = stats.totalTrains + (tonumber(record.train_rewards) or 0)
        stats.totalPracs = stats.totalPracs + (tonumber(record.prac_rewards) or 0)
        stats.totalGold = stats.totalGold + (tonumber(record.gold_rewards) or 0)
    end
    
    return stats
end

function snd.db.rawQuery(sql)
    return snd.db.query(sql)
end

function snd.db.getStats()
    local stats = {
        mobs = 0,
        areas = 0,
        keywords = 0,
        history = 0,
    }
    
    if not snd.db.isOpen then
        if not snd.db.open() then
            return stats
        end
    end
    
    local result = snd.db.query("SELECT COUNT(*) as cnt FROM mobs")
    if result and #result > 0 then
        stats.mobs = tonumber(result[1].cnt) or 0
    end
    
    result = snd.db.query("SELECT COUNT(*) as cnt FROM area")
    if result and #result > 0 then
        stats.areas = tonumber(result[1].cnt) or 0
    end
    
    result = snd.db.query("SELECT COUNT(*) as cnt FROM mob_keyword_exceptions")
    if result and #result > 0 then
        stats.keywords = tonumber(result[1].cnt) or 0
    end
    
    result = snd.db.query("SELECT COUNT(*) as cnt FROM history")
    if result and #result > 0 then
        stats.history = tonumber(result[1].cnt) or 0
    end
    
    return stats
end

function snd.db.setFile(path)
    if snd.db.isOpen then
        snd.db.close()
    end
    
    snd.db.file = path
    snd.utils.infoNote("Database path set to: " .. path)
end


registerAnonymousEventHandler("sysExitEvent", function()
    snd.db.close()
end)

    local tables = snd.db.getTables()
    local hasHistory = false
    for _, t in ipairs(tables) do
        if t == "history" then
            hasHistory = true
            break
        end
    end
    if not hasHistory then
        return {}
    end

    local tables = snd.db.getTables()
    local hasHistory = false
    for _, t in ipairs(tables) do
        if t == "history" then
            hasHistory = true
            break
        end
    end
    if not hasHistory then
        return nil
    end
