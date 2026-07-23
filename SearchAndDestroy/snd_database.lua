--[[
    Search and Destroy - Database Module
    Mudlet Port
    
    Original MUSHclient plugin by Crowley
    Ported to Mudlet
    
    This module handles SQLite database operations using LuaSQL directly
    to read/write the existing MUSHclient database file.
    
    Tables (from original schema v6):
    - mobs: mob locations and kill counts
    - area: area information and start rooms
    - mob_keyword_exceptions: custom keywords
    - history: campaign/quest history
]]

snd = snd or {}
snd.db = snd.db or {}

-- Load LuaSQL
local luasql = require "luasql.sqlite3"

-- Database environment and connection
snd.db.env = nil
snd.db.conn = nil
snd.db.isOpen = false
snd.db.seenCache = snd.db.seenCache or {}
snd.db.seenCacheLastPrune = snd.db.seenCacheLastPrune or 0
snd.db.seenCooldownSeconds = 300       -- 5 minutes
snd.db.seenCacheMaxAgeSeconds = 3600   -- 1 hour
snd.db.killCache = snd.db.killCache or {}
snd.db.killCacheLastPrune = snd.db.killCacheLastPrune or 0
snd.db.killCooldownSeconds = 3          -- dedupe duplicate kill events for same mob+room
snd.db.killCacheMaxAgeSeconds = 30      -- short-lived kill dedupe cache
snd.db.schemaVersion = 6
snd.db.createdEmpty = false

-- Default database path: directly inside the active Mudlet profile.
snd.db.file = getMudletHomeDir() .. "/SnDdb.db"

local SND_CORE_TABLES = { "area", "mobs", "mob_keyword_exceptions", "history" }
local SND_REQUIRED_COLUMNS = {
    area = { "name", "key", "minlvl", "maxlvl", "lock", "startRoom", "noquest", "vidblain", "userKey" },
    mobs = { "mob", "room", "roomid", "zone", "seen_count", "kill_count" },
    mob_keyword_exceptions = { "area_name", "mob_name", "keyword" },
    history = { "id", "type", "level_taken", "start_time", "end_time", "status", "qp_rewards", "tp_rewards", "train_rewards", "prac_rewards", "gold_rewards" },
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
        UNIQUE(mob, roomid))]],
    [[CREATE TABLE IF NOT EXISTS mob_keyword_exceptions (
        area_name TEXT NOT NULL,
        mob_name TEXT NOT NULL,
        keyword TEXT NOT NULL,
        UNIQUE(area_name, mob_name))]],
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
    [[CREATE INDEX IF NOT EXISTS history_end_time_status_type ON history(end_time, status, type)]],
    [[CREATE INDEX IF NOT EXISTS history_start_time_type ON history(start_time, type)]],
    [[CREATE INDEX IF NOT EXISTS history_type_status ON history(type, status)]],
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
    if type(cursor) == "userdata" and type(cursor.close) == "function" then
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
    if type(cursor) ~= "userdata" or type(cursor.fetch) ~= "function" then
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
    local integrity = tostring(scalar_from_connection(conn, "PRAGMA quick_check") or "unknown")
    if integrity ~= "ok" then
        return false, "SQLite quick_check: " .. integrity
    end
    return true
end

-------------------------------------------------------------------------------
-- Database Connection
-------------------------------------------------------------------------------

--- Open database connection
function snd.db.open()
    if snd.db.isOpen then
        return true
    end
    
    -- Create environment
    snd.db.env = luasql.sqlite3()
    if not snd.db.env then
        snd.utils.errorNote("Failed to create LuaSQL environment")
        return false
    end
    
    -- Opening a missing SQLite path creates a new file.  Existing files are
    -- never removed, replaced, truncated, or recreated here.
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

--- Close database connection
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
end

--- Clear in-memory seen update cooldown cache.
-- This cache is session-only and intentionally never persisted.
function snd.db.clearSeenCache()
    snd.db.seenCache = {}
    snd.db.seenCacheLastPrune = os.time()
end

--- Clear in-memory kill dedupe cache.
function snd.db.clearKillCache()
    snd.db.killCache = {}
    snd.db.killCacheLastPrune = os.time()
end

--- Prune seen cache entries older than max age.
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

--- Prune kill cache entries older than max age.
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

--- Ensure campaign Complete-By identity mapping table exists.
-- Keeps compatibility by avoiding changes to the shared history table schema.
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

--- Ensure mob tag table exists.
function snd.db.ensureMobTagsTable()
    if not snd.db.isOpen then
        if not snd.db.open() then
            return false
        end
    end

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
    snd.db.execute("CREATE INDEX IF NOT EXISTS idx_mob_tags_zone ON mob_tags(zone)")
    snd.db.execute("CREATE INDEX IF NOT EXISTS idx_mob_tags_mob ON mob_tags(mob)")
    snd.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_mob_tags_key_nocase ON mob_tags(lower(mob), lower(zone))")
    return true
end

--- Initialize the database
function snd.db.initialize(silent)
    if not silent then
        snd.utils.debugNote("Initializing database...")
    end
    
    if not snd.db.open() then
        return false
    end
    snd.db.clearSeenCache()
    snd.db.clearKillCache()
    
    -- Verify tables exist
    local tables = snd.db.getTables()
    if not silent then
        snd.utils.debugNote("Found tables: " .. table.concat(tables, ", "))
    end

    snd.db.ensureCampaignIdentityTable()
    snd.db.ensureMobTagsTable()
    snd.db.normalizeMobTagRows()
    snd.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_mob_tags_key_nocase ON mob_tags(lower(mob), lower(zone))")
    
    -- Get stats
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

--- Get list of tables in database
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

-------------------------------------------------------------------------------
-- Query Helpers
-------------------------------------------------------------------------------

--- Execute a query and return all results
-- @param sql SQL query string
-- @return Table of rows, or nil on error
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
        -- Copy row to new table (cursor reuses the same table)
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

--- Execute a statement (INSERT, UPDATE, DELETE)
-- @param sql SQL statement
-- @return true on success, false on error
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

--- Escape a string for SQL
-- @param str String to escape
-- @return Escaped string (with quotes)
function snd.db.escape(str)
    if str == nil then
        return "NULL"
    end
    str = tostring(str)
    str = str:gsub("'", "''")
    return "'" .. str .. "'"
end

-------------------------------------------------------------------------------
-- Mob Functions
-------------------------------------------------------------------------------

--- Record seeing a mob in a room
-- @param mobName Full mob name
-- @param roomName Room name
-- @param roomId Room ID number
-- @param zone Area key
function snd.db.recordMobSeen(mobName, roomName, roomId, zone)
    if not mobName or mobName == "" then return end
    if not roomId then return end
    
    -- Skip certain mobs
    if mobName:match("%(wounded%)") or mobName:match("%(aimed%)") then
        return
    end
    
    roomName = roomName or ""
    zone = zone or snd.room.current.arid or ""
    roomId = tonumber(roomId) or 0

    local now = os.time()
    local cacheKey = string.format("%s|%d", tostring(mobName):lower(), roomId)
    local lastSeen = snd.db.seenCache and snd.db.seenCache[cacheKey] or nil
    local cooldown = tonumber(snd.db.seenCooldownSeconds) or 300

    if lastSeen and (now - lastSeen) < cooldown then
        return
    end

    local lastPrune = tonumber(snd.db.seenCacheLastPrune) or 0
    if (now - lastPrune) > 60 then
        snd.db.pruneSeenCache(now)
    end
    
    -- Ensure row exists before incrementing seen_count.
    local sql = string.format(
        "INSERT OR IGNORE INTO mobs (mob, room, roomid, zone, seen_count, kill_count) VALUES (%s, %s, %d, %s, 0, 0)",
        snd.db.escape(mobName),
        snd.db.escape(roomName),
        roomId,
        snd.db.escape(zone)
    )
    snd.db.execute(sql)

    -- Increment seen count when outside cooldown window.
    sql = string.format(
        "UPDATE mobs SET seen_count = seen_count + 1 WHERE mob = %s AND roomid = %d",
        snd.db.escape(mobName), roomId
    )
    snd.db.execute(sql)

    snd.db.seenCache[cacheKey] = now
end

--- Record killing a mob in a room
-- @param mobName Full mob name
-- @param roomId Room ID number
-- @param roomName Optional room name
-- @param zone Optional area key
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
        "UPDATE mobs SET kill_count = kill_count + 1 WHERE mob = %s AND roomid = %d",
        snd.db.escape(mobName), roomId
    )
    snd.db.execute(sql)

    sql = string.format(
        "INSERT OR IGNORE INTO mobs (mob, room, roomid, zone, seen_count, kill_count) VALUES (%s, %s, %d, %s, 1, 1)",
        snd.db.escape(mobName),
        snd.db.escape(roomName),
        roomId,
        snd.db.escape(zone)
    )
    snd.db.execute(sql)
    snd.db.killCache[cacheKey] = now
end

--- Search for mobs by name
-- @param searchTerm Partial mob name to search for
-- @param zone Optional area to limit search
-- @return Table of matching mobs
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

--- Get all rooms where a mob has been seen
-- @param mobName Mob name to search for
-- @param zone Optional area to limit search
-- @return Table of room records
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
                          ON lower(mt.mob) = lower(m.mob)
                         AND lower(mt.zone) = lower(m.zone)
                        WHERE lower(m.mob) = lower(%s) AND lower(m.zone) = lower(%s)
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
                                        PARTITION BY lower(m.mob), lower(m.zone)
                                        ORDER BY
                                            CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END DESC,
                                            m.seen_count DESC,
                                            m.kill_count DESC,
                                            m.roomid ASC
                                    ) AS rn
                            FROM mobs m
                            LEFT JOIN mob_tags mt
                              ON lower(mt.mob) = lower(m.mob)
                             AND lower(mt.zone) = lower(m.zone)
                            WHERE lower(m.mob) = lower(%s)
                              AND lower(m.zone) = lower(%s)
                              AND lower(m.room) = lower(%s)
                        ) ranked
                        WHERE rn = 1
                        ORDER BY priority_match DESC, seen_count DESC, kill_count DESC, roomid ASC
                    ]],
                        snd.db.escape(name),
                        snd.db.escape(zone),
                        snd.db.escape(roomHint)
                    )
                else
                    --[[
                    sql = string.format(
                        "SELECT * FROM mobs WHERE lower(mob) = lower(%s) AND zone = %s ORDER BY seen_count DESC, kill_count DESC",
                        snd.db.escape(name),
                        snd.db.escape(zone)
                    )
                    ]]
                    sql = string.format([[
                        SELECT * FROM (
                            SELECT m.*,
                                   mt.priority_room,
                                   mt.nowhere,
                                   mt.nohunt,
                                   CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END AS priority_match,
                                   ROW_NUMBER() OVER (
                                        PARTITION BY lower(m.mob), lower(m.zone)
                                        ORDER BY
                                            CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END DESC,
                                            m.seen_count DESC,
                                            m.kill_count DESC,
                                            m.roomid ASC
                                    ) AS rn
                            FROM mobs m
                            LEFT JOIN mob_tags mt
                              ON lower(mt.mob) = lower(m.mob)
                             AND lower(mt.zone) = lower(m.zone)
                            WHERE lower(m.mob) = lower(%s) AND lower(m.zone) = lower(%s)
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
                          ON lower(mt.mob) = lower(m.mob)
                         AND lower(mt.zone) = lower(m.zone)
                        WHERE lower(m.mob) = lower(%s)
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
                                        PARTITION BY lower(m.mob), lower(m.zone)
                                        ORDER BY
                                            CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END DESC,
                                            m.seen_count DESC,
                                            m.kill_count DESC,
                                            m.roomid ASC
                                    ) AS rn
                            FROM mobs m
                            LEFT JOIN mob_tags mt
                              ON lower(mt.mob) = lower(m.mob)
                             AND lower(mt.zone) = lower(m.zone)
                            WHERE lower(m.mob) = lower(%s)
                              AND lower(m.room) = lower(%s)
                        ) ranked
                        WHERE rn = 1
                        ORDER BY priority_match DESC, seen_count DESC, kill_count DESC, roomid ASC
                    ]],
                        snd.db.escape(name),
                        snd.db.escape(roomHint)
                    )
                else
                    --[[
                    sql = string.format(
                        "SELECT * FROM mobs WHERE lower(mob) = lower(%s) ORDER BY seen_count DESC, kill_count DESC",
                        snd.db.escape(name)
                    )
                    ]]
                    sql = string.format([[
                        SELECT * FROM (
                            SELECT m.*,
                                   mt.priority_room,
                                   mt.nowhere,
                                   mt.nohunt,
                                   CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END AS priority_match,
                                   ROW_NUMBER() OVER (
                                        PARTITION BY lower(m.mob), lower(m.zone)
                                        ORDER BY
                                            CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END DESC,
                                            m.seen_count DESC,
                                            m.kill_count DESC,
                                            m.roomid ASC
                                    ) AS rn
                            FROM mobs m
                            LEFT JOIN mob_tags mt
                              ON lower(mt.mob) = lower(m.mob)
                             AND lower(mt.zone) = lower(m.zone)
                            WHERE lower(m.mob) = lower(%s)
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

--- Get mob with highest kill count in a zone
-- @param mobName Mob name
-- @param zone Area key
-- @return Best room record or nil
function snd.db.getBestMobLocation(mobName, zone)
    local locations = snd.db.getMobLocations(mobName, zone)
    if #locations > 0 then
        return locations[1]  -- Sorted by priority match, then seen/kill counts.
    end
    return nil
end

-------------------------------------------------------------------------------
-- Area Functions
-------------------------------------------------------------------------------

--- Get area info by key
-- @param areaKey Area keyword
-- @return Area record or nil
function snd.db.getArea(areaKey)
    if not areaKey or areaKey == "" then return nil end
    
    local sql = string.format(
        "SELECT * FROM area WHERE key = %s",
        snd.db.escape(areaKey)
    )
    
    local results = snd.db.query(sql)
    if results and #results > 0 then
        return results[1]
    end
    
    return nil
end

--- Get area key from area name
-- @param areaName Full area name (e.g., "Artificer's Mayhem")
-- @return Area key (e.g., "artificer") or nil
function snd.db.getAreaKeyFromName(areaName)
    if not areaName or areaName == "" then return nil end

    local trimmed = snd.utils and snd.utils.trim and snd.utils.trim(areaName) or tostring(areaName)
    local sql = string.format(
        "SELECT key FROM area WHERE lower(name) = lower(%s)",
        snd.db.escape(trimmed)
    )

    local results = snd.db.query(sql)
    if results and #results > 0 then
        return results[1].key
    end

    -- Tolerate punctuation/spacing drift between campaign output and area table,
    -- e.g. "Necromancers' Guild" vs "Necromancer's Guild".
    local normalized = tostring(trimmed):lower():gsub("[^%w]", "")
    if normalized ~= "" then
        sql = string.format(
            "SELECT key FROM area " ..
            "WHERE lower(replace(replace(replace(replace(name, '''', ''), ' ', ''), '-', ''), '_', '')) = %s " ..
            "LIMIT 1",
            snd.db.escape(normalized)
        )
        results = snd.db.query(sql)
        if results and #results > 0 then
            return results[1].key
        end
    end

    -- Try partial match if exact match fails
    sql = string.format(
        "SELECT key FROM area WHERE lower(name) LIKE lower(%s)",
        snd.db.escape("%" .. trimmed .. "%")
    )

    results = snd.db.query(sql)
    if results and #results > 0 then
        return results[1].key
    end
    
    return nil
end

--- Get or create area record
-- @param areaKey Area keyword
-- @param areaName Full area name
-- @return Area record
function snd.db.getOrCreateArea(areaKey, areaName)
    local existing = snd.db.getArea(areaKey)
    if existing then
        return existing
    end
    
    -- Create new area with defaults
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
    
    return snd.db.getArea(areaKey)
end

--- Update area start room
-- @param areaKey Area keyword
-- @param roomId Room ID to set as start
function snd.db.setAreaStartRoom(areaKey, roomId)
    if not areaKey or areaKey == "" then return end
    
    roomId = tonumber(roomId) or -1
    
    -- Check if area exists
    local existing = snd.db.getArea(areaKey)
    if existing then
        local sql = string.format(
            "UPDATE area SET startRoom = %d WHERE key = %s",
            roomId,
            snd.db.escape(areaKey)
        )
        snd.db.execute(sql)
        snd.utils.infoNote("Updated start room for " .. areaKey .. " to " .. roomId)
    else
        -- Create new area record
        snd.db.getOrCreateArea(areaKey, areaKey)
        snd.db.setAreaStartRoom(areaKey, roomId)
    end
end

--- Get area start room
-- @param areaKey Area keyword
-- @return Room ID or -1
function snd.db.getAreaStartRoom(areaKey)
    if not areaKey or areaKey == "" then return -1 end
    
    -- First check database
    local area = snd.db.getArea(areaKey)
    if area and area.startRoom and tonumber(area.startRoom) > 0 then
        return tonumber(area.startRoom)
    end
    
    -- Fall back to hardcoded defaults
    local defaults = snd.data.areaDefaultStartRooms[areaKey]
    if defaults and defaults.start then
        return tonumber(defaults.start) or -1
    end
    
    return -1
end

-------------------------------------------------------------------------------
-- Mob Keyword Functions
-------------------------------------------------------------------------------

--- Get custom keyword for a mob
-- @param areaKey Area keyword
-- @param mobName Full mob name
-- @return Custom keyword or nil
function snd.db.getMobKeyword(areaKey, mobName)
    if not areaKey or not mobName then return nil end
    
    local sql = string.format(
        "SELECT keyword FROM mob_keyword_exceptions WHERE area_name = %s AND mob_name = %s",
        snd.db.escape(areaKey),
        snd.db.escape(mobName)
    )
    
    local results = snd.db.query(sql)
    if results and #results > 0 then
        return results[1].keyword
    end
    
    return nil
end

--- Set custom keyword for a mob
-- @param areaKey Area keyword
-- @param mobName Full mob name
-- @param keyword Keyword to use
function snd.db.setMobKeyword(areaKey, mobName, keyword)
    if not areaKey or not mobName or not keyword then return end
    
    -- Use INSERT OR REPLACE to handle both insert and update
    local sql = string.format(
        "INSERT OR REPLACE INTO mob_keyword_exceptions (area_name, mob_name, keyword) VALUES (%s, %s, %s)",
        snd.db.escape(areaKey),
        snd.db.escape(mobName),
        snd.db.escape(keyword)
    )
    
    if snd.db.execute(sql) then
        snd.utils.infoNote("Set keyword for '" .. mobName .. "' to '" .. keyword .. "' in " .. areaKey)
    end
end

-------------------------------------------------------------------------------
-- History Functions
-------------------------------------------------------------------------------

-- History type constants
snd.db.HISTORY_TYPE_QUEST = 1
snd.db.HISTORY_TYPE_GQUEST = 2
snd.db.HISTORY_TYPE_CAMPAIGN = 3

-- History status constants
snd.db.HISTORY_STATUS_INPROGRESS = 1
snd.db.HISTORY_STATUS_COMPLETE = 2
snd.db.HISTORY_STATUS_TIMEOUT = 3
snd.db.HISTORY_STATUS_FAILED = 4
snd.db.HISTORY_STATUS_RESET = 5
snd.db.HISTORY_STATUS_SKIPPED = 6
snd.db.HISTORY_STATUS_UNDOCUMENTED = 7

--- Purge stale in-progress quest history rows older than a maximum age.
-- Only affects quest history rows.
-- @param maxAgeSeconds Optional max age in seconds (default 3600)
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

--- Start tracking a new activity in history
-- @param historyType Type of activity (quest/gquest/campaign)
-- @param levelTaken Level when started
-- @param startTime number|nil Optional captured start time; defaults to os.time().
function snd.db.historyStart(historyType, levelTaken, startTime)
    -- Check if history table exists (it was added in schema v6)
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

    -- Return the inserted history id using SQLite's last_insert_rowid() for compatibility.
    local idRows = snd.db.query("SELECT last_insert_rowid() AS id")
    if idRows and idRows[1] then
        return tonumber(idRows[1].id)
    end
    return nil
end

--- End tracking an activity in history
-- @param historyType Type of activity
-- @param status Final status (complete/failed/skipped)
-- @param rewards Optional table of rewards {qp, tp, trains, pracs, gold}
--   Pass nil to preserve existing reward values.
-- @param endTime number|nil Optional captured completion time; defaults to os.time().
-- @return table|nil Updated history row with computed duration_seconds, or nil if no row was updated.
function snd.db.historyEnd(historyType, status, rewards, endTime)
    if tonumber(historyType) == snd.db.HISTORY_TYPE_QUEST then
        snd.db.purgeStaleQuestHistory(3600)
    end
    
    -- Find the most recent in-progress record of this type
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

--- End tracking for a specific history row id
-- @param historyId Primary key id in history table
-- @param status Final status (complete/failed/skipped/reset)
-- @param rewards Optional table of rewards {qp, tp, trains, pracs, gold}
--   Pass nil to preserve existing reward values.
-- @return table|nil Updated history row with computed duration_seconds, or nil if not updated.
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

--- Return mapped history id for a Complete-By identity.
-- @param completeBy string
-- @return number|nil
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

--- Return mapped Complete-By identity for a history row id.
-- @param historyId number
-- @return string
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

--- Create or update Complete-By <-> history id mapping.
-- @param completeBy string
-- @param historyId number
-- @return boolean
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

--- Return the latest campaign history row.
-- @return table|nil
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

--- Return a single history row by primary key id.
-- @param historyId number
-- @return table|nil
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

--- Update rewards for a specific history row id without changing status/timestamps.
-- @param historyId Primary key id in history table
-- @param rewards Table of rewards {qp, tp, trains, pracs, gold}
-- @return true if an update was attempted, false otherwise
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

--- Return recent history entries
-- @param opts Optional table {limit=20, type=nil}
-- @return Array of rows
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

--- Get a single history row by rowid
-- @param rowid number sqlite rowid
-- @return row table or nil
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

--- Get history statistics
-- @param historyType Optional type filter
-- @param days Number of days to look back (default 14)
-- @return Table of statistics
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
    
    -- Check if history table exists
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

-------------------------------------------------------------------------------
-- Utility Functions
-------------------------------------------------------------------------------

--- Execute a raw SQL query
-- @param sql SQL query string
-- @return Results table or nil
function snd.db.rawQuery(sql)
    return snd.db.query(sql)
end

--- Get database statistics
-- @return Table with counts
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
    
    -- Count mobs
    local result = snd.db.query("SELECT COUNT(*) as cnt FROM mobs")
    if result and #result > 0 then
        stats.mobs = tonumber(result[1].cnt) or 0
    end
    
    -- Count areas
    result = snd.db.query("SELECT COUNT(*) as cnt FROM area")
    if result and #result > 0 then
        stats.areas = tonumber(result[1].cnt) or 0
    end
    
    -- Count keywords
    result = snd.db.query("SELECT COUNT(*) as cnt FROM mob_keyword_exceptions")
    if result and #result > 0 then
        stats.keywords = tonumber(result[1].cnt) or 0
    end
    
    -- Count history (if table exists)
    result = snd.db.query("SELECT COUNT(*) as cnt FROM history")
    if result and #result > 0 then
        stats.history = tonumber(result[1].cnt) or 0
    end
    
    return stats
end

--- Set the database file path
-- @param path Full path to the .db file
function snd.db.setFile(path)
    -- Close existing connection if open
    if snd.db.isOpen then
        snd.db.close()
    end
    
    snd.db.file = path
    snd.utils.infoNote("Database path set to: " .. path)
end

-------------------------------------------------------------------------------
-- Cleanup on exit
-------------------------------------------------------------------------------

registerAnonymousEventHandler("sysExitEvent", function()
    snd.db.close()
end)

-- Module loaded silently
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
