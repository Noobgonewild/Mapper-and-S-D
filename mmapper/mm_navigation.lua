--[[
    Search and Destroy - Navigation Module
    Mudlet Port
    
    This module provides portal-aware pathfinding by querying the
    Aardwolf.db mapper database directly.
    
    Features:
    - Portal navigation (fromuid='*' exits)
    - Recall navigation (fromuid='**' exits)
    - Norecall/noportal room flag handling
    - Bounce portal/recall for restricted rooms
    - Custom exit support
    - Integration with Mudlet's gotoRoom()
    
    Database: Aardwolf.db (mapper database, NOT snd.db)
    
    Schema used:
    - rooms: uid, name, area, norecall, noportal
    - exits: dir, fromuid, touid, level
    - Portals: fromuid='*' (any room) or '**' (recall-based)
]]

mm = mm or {}
snd = snd or {}
snd.mapper = snd.mapper or {}
snd.utils = snd.utils or {}
snd.commands = snd.commands or {}
snd.room = snd.room or { current = { rmid = "-1" } }
snd.char = snd.char or { level = 201, tier = 0 }
snd.nav = snd.nav or {}

if type(mm.canonical_room_uid) ~= "function" then
    error("MMapper navigation requires mm_core.lua to be loaded first (missing mm.canonical_room_uid).")
end

if type(snd.utils.infoNote) ~= "function" then
    snd.utils.infoNote = function(msg)
        if mm and type(mm.note) == "function" then
            mm.note(tostring(msg))
        else
            cecho("<CornflowerBlue>[MMAPPER]<reset> " .. tostring(msg) .. "\n")
        end
    end
end
if type(snd.utils.errorNote) ~= "function" then
    snd.utils.errorNote = function(msg)
        if mm and type(mm.warn) == "function" then
            mm.warn(tostring(msg))
        else
            cecho("<orange_red>[MMAPPER]<reset> " .. tostring(msg) .. "\n")
        end
    end
end
snd.utils.debugNote = function(msg)
    local mapperDebugOn = mm and mm.state and mm.state.debug
    if not mapperDebugOn then
        return
    end

    local text = tostring(msg)
    if type(mm.debug) == "function" then
        mm.debug(text)
        return
    end
    cecho("<dim_gray>[MMAPPER:DEBUG]<reset> <gray>" .. text .. "<reset>\n")
end
if type(snd.utils.trim) ~= "function" then
    snd.utils.trim = function(s)
        return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
end

local function ensureAreaReferencesLoaded()
    if mm.area_references and type(mm.area_references.get) == "function" then
        return true
    end

    local candidates = {}
    if mm.base_dir and mm.base_dir ~= "" then
        table.insert(candidates, tostring(mm.base_dir) .. "/mm_area_references.lua")
    end

    local source = debug.getinfo(1, "S").source or ""
    if source:sub(1, 1) == "@" then
        local path = source:sub(2):gsub("\\", "/")
        local dir = path:match("^(.*)/")
        if dir and dir ~= "" then
            table.insert(candidates, dir .. "/mm_area_references.lua")
        end
    end

    for _, path in ipairs(candidates) do
        local f = io.open(path, "rb")
        if f then
            f:close()
            local ok, err = pcall(dofile, path)
            if ok and mm.area_references then
                snd.utils.debugNote("Area references loaded from " .. tostring(path))
                return true
            end
            snd.utils.debugNote("Failed loading area references from " .. tostring(path) .. ": " .. tostring(err))
        end
    end

    snd.utils.debugNote("Area references unavailable; area guard will fail open.")
    return false
end

ensureAreaReferencesLoaded()

-- Load LuaSQL for Aardwolf.db access
local luasql = require "luasql.sqlite3"

mm.nav = snd.mapper

-------------------------------------------------------------------------------
-- Database Connection (Aardwolf.db - mapper database)
-------------------------------------------------------------------------------

snd.mapper.db = {
    env = nil,
    conn = nil,
    isOpen = false,
    file = nil,  -- Will be set to Aardwolf.db path
}

--- Get the Aardwolf.db path
-- Mudlet stores map data in the profile directory
function snd.mapper.db.getMapperDbPath()
    -- Try common locations
    local profile_dir = getMudletHomeDir()
    local possible_paths = {
        profile_dir .. "/Aardwolf.db",
        profile_dir .. "/map/Aardwolf.db",
        profile_dir .. "/../Aardwolf.db",
    }
    
    for _, path in ipairs(possible_paths) do
        local f = io.open(path, "r")
        if f then
            f:close()
            return path
        end
    end
    
    -- Default fallback
    return profile_dir .. "/Aardwolf.db"
end

--- Open connection to Aardwolf.db
function snd.mapper.db.open()
    if snd.mapper.db.isOpen then
        return true
    end
    
    -- Get database path
    if not snd.mapper.db.file then
        snd.mapper.db.file = snd.mapper.db.getMapperDbPath()
    end
    
    -- Check if file exists
    local f = io.open(snd.mapper.db.file, "r")
    if not f then
        snd.utils.debugNote("Mapper database not found: " .. snd.mapper.db.file)
        return false
    end
    f:close()
    
    -- Create environment
    snd.mapper.db.env = luasql.sqlite3()
    if not snd.mapper.db.env then
        snd.utils.errorNote("Failed to create LuaSQL environment for mapper DB")
        return false
    end
    
    -- Open connection
    local err
    snd.mapper.db.conn, err = snd.mapper.db.env:connect(snd.mapper.db.file)
    if not snd.mapper.db.conn then
        snd.utils.errorNote("Failed to open mapper database: " .. tostring(err))
        return false
    end
    
    snd.mapper.db.isOpen = true
    snd.utils.debugNote("Mapper database opened: " .. snd.mapper.db.file)
    return true
end

--- Close database connection
function snd.mapper.db.close()
    if snd.mapper.db.conn then
        snd.mapper.db.conn:close()
        snd.mapper.db.conn = nil
    end
    if snd.mapper.db.env then
        snd.mapper.db.env:close()
        snd.mapper.db.env = nil
    end
    snd.mapper.db.isOpen = false
    snd.mapper.db.columnCache = nil
    snd.mapper.db.roomsLookupReady = nil
    snd.mapper.committedSectorFingerprint = nil
    snd.mapper.clanAreaCache = nil
    snd.mapper.clanAreaList = nil
    if mm and mm.invalidate_room_notes_cache then mm.invalidate_room_notes_cache() end
end

--- Execute a query and return results
function snd.mapper.db.query(sql)
    if not snd.mapper.db.isOpen then
        if not snd.mapper.db.open() then
            return nil
        end
    end
    
    local cursor, err = snd.mapper.db.conn:execute(sql)
    if not cursor then
        snd.utils.debugNote("Mapper DB query error: " .. tostring(err))
        return nil
    end
    
    local results = {}
    local row = cursor:fetch({}, "a")
    while row do
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

--- Escape string for SQL
function snd.mapper.db.escape(str)
    if str == nil then return "NULL" end
    str = tostring(str)
    str = str:gsub("'", "''")
    return "'" .. str .. "'"
end

--- Execute a non-query mapper DB statement.
-- @param sql SQL statement
-- @return boolean, result_or_error
function snd.mapper.db.execute(sql)
    if not snd.mapper.db.isOpen then
        if not snd.mapper.db.open() then
            return false, "cannot open mapper database"
        end
    end

    local result, err = snd.mapper.db.conn:execute(sql)
    if not result then
        snd.utils.debugNote("Mapper DB execute error: " .. tostring(err))
        return false, tostring(err)
    end
    return true, result
end

function snd.mapper.db.tableColumns(tableName)
    snd.mapper.db.columnCache = snd.mapper.db.columnCache or {}
    local key = tostring(tableName or "")
    if key == "" then return {} end
    if snd.mapper.db.columnCache[key] then
        return snd.mapper.db.columnCache[key]
    end

    local rows = snd.mapper.db.query("PRAGMA table_info(" .. snd.mapper.db.escape(key) .. ")") or {}
    local cols = {}
    for _, row in ipairs(rows) do
        if row.name then cols[tostring(row.name)] = true end
    end
    snd.mapper.db.columnCache[key] = cols
    return cols
end

function snd.mapper.db.columnExists(tableName, columnName)
    local cols = snd.mapper.db.tableColumns(tableName)
    return cols[tostring(columnName or "")] == true
end

-------------------------------------------------------------------------------
-- Portal Configuration
-------------------------------------------------------------------------------

snd.mapper.config = {
    usePortals = true,          -- Use portal exits
    useRecall = true,           -- Use recall-based portals
    maxSearchDepth = 100,       -- Max BFS depth for pathfinding
    nearbyJumpRadius = 10,      -- Max walking radius before area-start fallback
    bouncePortal = nil,         -- Fallback portal for norecall rooms
    bounceRecall = nil,         -- Fallback recall for noportal rooms
}

snd.mapper.pendingRestrictionMarks = snd.mapper.pendingRestrictionMarks or {}
snd.mapper.restrictionTriggerIds = snd.mapper.restrictionTriggerIds or {}
snd.mapper.pendingBlockedTravel = snd.mapper.pendingBlockedTravel or nil
-- Discard continuation state left by builds that issued an unconfigured
-- default recall and waited for GMCP before replanning. Navigation now uses
-- only mapped recall/home commands and configured bounce recalls.
snd.mapper.pendingRecallReplan = nil

local mapperDirectionAliases = {
    n = "n", north = "n",
    s = "s", south = "s",
    e = "e", east = "e",
    w = "w", west = "w",
    u = "u", up = "u",
    d = "d", down = "d",
}

local mapperDirectionNames = {
    n = "north", s = "south", e = "east", w = "west", u = "up", d = "down",
}

local mapperNativeDirectionIds = {
    n = 1, e = 4, w = 5, s = 6, u = 9, d = 10,
}

function snd.mapper.normalizeDirection(dir)
    local key = tostring(dir or ""):lower():match("^%s*(.-)%s*$")
    return mapperDirectionAliases[key]
end

local mapperCardinalDirectionsSql = "'n','north','s','south','e','east','w','west','u','up','d','down'"

function snd.mapper.isCardinalExitDir(dir)
    return snd.mapper.normalizeDirection(dir) ~= nil
end

function snd.mapper.shouldPreferExitDir(candidateDir, currentDir)
    if currentDir == nil then
        return true
    end

    local candidateIsCardinal = snd.mapper.isCardinalExitDir(candidateDir)
    local currentIsCardinal = snd.mapper.isCardinalExitDir(currentDir)
    if candidateIsCardinal ~= currentIsCardinal then
        return not candidateIsCardinal
    end

    local candidateText = tostring(candidateDir or "")
    local currentText = tostring(currentDir or "")
    if #candidateText ~= #currentText then
        return #candidateText > #currentText
    end

    return candidateText:lower() < currentText:lower()
end

function snd.mapper.exitPreferenceOrderSql(dirColumn)
    dirColumn = dirColumn or "dir"
    return string.format(
        "CASE WHEN lower(trim(%s)) IN (%s) THEN 1 ELSE 0 END ASC, length(%s) DESC, lower(%s) ASC",
        dirColumn,
        mapperCardinalDirectionsSql,
        dirColumn,
        dirColumn
    )
end

function snd.mapper.isInCombat()
    local state
    if gmcp and gmcp.char and gmcp.char.status then
        state = tonumber(gmcp.char.status.state)
    end
    if state == nil and snd.char and snd.char.status then
        state = tonumber(snd.char.status.state)
    end
    return state == 8
end

function snd.mapper.canSendCommands()
    local state
    if gmcp and gmcp.char and gmcp.char.status then
        state = tonumber(gmcp.char.status.state)
    end
    if state == nil and snd.char and snd.char.status then
        state = tonumber(snd.char.status.state)
    end
    if state == nil and snd.char then
        state = tonumber(snd.char.state)
    end
    if state == nil then
        return true
    end
    if state == 1 or state == 2 or state == 5 or state == 6 or state == 7 then
        return false
    end
    return true
end

function snd.mapper.setExitLock(roomId, dir, level)
    local normalizedDir = snd.mapper.normalizeDirection(dir)
    if not normalizedDir then
        return false, "invalid direction; use n/s/e/w/u/d"
    end

    local roomKey = tostring(roomId or "")
    if roomKey == "" or roomKey == "-1" then
        return false, "current room unknown"
    end
    local lockLevel = tonumber(level) or 999

    if not snd.mapper.db.open() then
        return false, "cannot open mapper database"
    end

    local canonicalDir = ({n="north",s="south",e="east",w="west",u="up",d="down"})[normalizedDir]
    local sql = string.format([[
        UPDATE exits
        SET level = %d
        WHERE fromuid = %s
          AND (
            LOWER(dir) IN (%s, %s)
            OR (
              level = 0
              AND LOWER(dir) NOT IN (%s)
              AND touid IN (
                SELECT cardinal.touid
                FROM exits AS cardinal
                WHERE cardinal.fromuid = %s
                  AND LOWER(cardinal.dir) IN (%s, %s)
              )
            )
          )
    ]],
        lockLevel,
        snd.mapper.db.escape(roomKey),
        snd.mapper.db.escape(normalizedDir),
        snd.mapper.db.escape(canonicalDir),
        mapperCardinalDirectionsSql,
        snd.mapper.db.escape(roomKey),
        snd.mapper.db.escape(normalizedDir),
        snd.mapper.db.escape(canonicalDir)
    )
    local affected, err = snd.mapper.db.conn:execute(sql)
    if not affected then
        return false, "failed to lock exit: " .. tostring(err)
    end
    return true, tonumber(affected) or 0
end

function snd.mapper.clearExitLock(roomId, dir)
    local normalizedDir = snd.mapper.normalizeDirection(dir)
    if not normalizedDir then
        return false, "invalid direction; use n/s/e/w/u/d"
    end

    local roomKey = tostring(roomId or "")
    if roomKey == "" or roomKey == "-1" then
        return false, "current room unknown"
    end

    if not snd.mapper.db.open() then
        return false, "cannot open mapper database"
    end

    local canonicalDir = ({n="north",s="south",e="east",w="west",u="up",d="down"})[normalizedDir]
    local sql = string.format([[
        UPDATE exits
        SET level = 0
        WHERE fromuid = %s
          AND LOWER(dir) IN (%s, %s)
    ]],
        snd.mapper.db.escape(roomKey),
        snd.mapper.db.escape(normalizedDir),
        snd.mapper.db.escape(canonicalDir)
    )
    local affected, err = snd.mapper.db.conn:execute(sql)
    if not affected then
        return false, "failed to unlock exit: " .. tostring(err)
    end
    return true, tonumber(affected) or 0
end

function snd.mapper.getExitLock(roomId, dir)
    local normalizedDir = snd.mapper.normalizeDirection(dir)
    if not normalizedDir then return nil end

    local roomKey = tostring(roomId or "")
    if roomKey == "" or roomKey == "-1" then return nil end
    if not snd.mapper.db.open() then return nil end

    local sql = string.format(
        "SELECT MAX(level) AS level FROM exits WHERE fromuid = %s AND LOWER(dir) IN (%s, %s)",
        snd.mapper.db.escape(roomKey),
        snd.mapper.db.escape(normalizedDir),
        snd.mapper.db.escape(({n="north",s="south",e="east",w="west",u="up",d="down"})[normalizedDir])
    )
    local rows = snd.mapper.db.query(sql) or {}
    local lvl = rows[1] and tonumber(rows[1].level) or nil
    if lvl and lvl > 0 then
        return lvl
    end
    return nil
end

function snd.mapper.isExitLocked(roomId, dir, playerLevel)
    local lockLevel = snd.mapper.getExitLock(roomId, dir)
    if not lockLevel then
        return false
    end
    local lvl = tonumber(playerLevel) or 0
    return lvl < lockLevel
end

function snd.mapper.getRoomExitLocks(roomId)
    local roomKey = tostring(roomId or "")
    if roomKey == "" or roomKey == "-1" then return {} end
    if not snd.mapper.db.open() then return {} end

    local sql = string.format([[
        SELECT dir, touid, level
        FROM exits
        WHERE fromuid = %s
          AND level > 0
        ORDER BY LOWER(dir), touid
    ]], snd.mapper.db.escape(roomKey))
    return snd.mapper.db.query(sql) or {}
end

local nativeExitVisualColors = {
    restricted = {242, 184, 75},
    blocked = {255, 77, 93},
}

local function native_cardinal_is_stub(roomId, dir)
    local room = tonumber(roomId)
    local normalizedDir = snd.mapper.normalizeDirection(dir)
    if not room or not normalizedDir then return false end

    for _, apiName in ipairs({"getExitStubsNames", "getExitStubs"}) do
        local api = _G[apiName]
        if type(api) == "function" then
            local ok, stubs = pcall(api, room)
            if ok and type(stubs) == "table" then
                for key, value in pairs(stubs) do
                    local candidate = value
                    if type(value) == "boolean" then candidate = key end
                    local matches = tonumber(candidate) == mapperNativeDirectionIds[normalizedDir]
                    if not matches then
                        matches = snd.mapper.normalizeDirection(candidate) == normalizedDir
                    end
                    if matches then return true end
                end
            end
        end
    end
    return false
end

function snd.mapper.currentExitVisualLevel()
    local status = gmcp and gmcp.char and gmcp.char.status
    local level = status and tonumber(status.level) or nil
    if level == nil then level = tonumber(snd.char and snd.char.level) end
    return level or 0
end

function snd.mapper.exitLockVisualState(lockLevel, playerLevel)
    local required = tonumber(lockLevel) or 0
    if required <= 0 then return "normal" end
    local current = tonumber(playerLevel)
    if current == nil then current = snd.mapper.currentExitVisualLevel() end
    return current < required and "blocked" or "restricted"
end

local function native_cardinal_target(roomId, dir)
    if type(getRoomExits) ~= "function" then return nil end
    local room = tonumber(roomId)
    local normalizedDir = snd.mapper.normalizeDirection(dir)
    if not room or not normalizedDir then return nil end
    if native_cardinal_is_stub(room, normalizedDir) then return nil end

    local ok, exits = pcall(getRoomExits, room)
    if not ok or type(exits) ~= "table" then return nil end
    local nativeId = mapperNativeDirectionIds[normalizedDir]
    for rawDir, destination in pairs(exits) do
        local matches = tonumber(rawDir) == nativeId
        if not matches then
            matches = snd.mapper.normalizeDirection(rawDir) == normalizedDir
        end
        if matches then return tonumber(destination) end
    end
    return nil
end

local function native_visual_key(roomId, dir)
    local normalizedDir = snd.mapper.normalizeDirection(dir)
    if not normalizedDir then return nil end
    return tostring(roomId) .. ":" .. normalizedDir
end

local function remove_native_exit_visual(roomId, dir)
    local room = tonumber(roomId)
    local normalizedDir = snd.mapper.normalizeDirection(dir)
    if not room or not normalizedDir or type(removeCustomLine) ~= "function" then return false end
    local ok, result = pcall(removeCustomLine, room, normalizedDir)
    return ok and result ~= false
end

local function apply_native_exit_visual(row, playerLevel, force)
    local room = tonumber(row and row.fromuid)
    local destination = tonumber(row and row.touid)
    local dir = snd.mapper.normalizeDirection(row and row.dir)
    if not room or not dir then return false, false end

    mm.runtime = mm.runtime or {}
    mm.runtime.native_exit_lock_visuals = mm.runtime.native_exit_lock_visuals or {}
    local key = native_visual_key(room, dir)
    local lockLevel = tonumber(row and row.level) or 0
    if lockLevel <= 0 or not destination or destination <= 0 then
        local changed = remove_native_exit_visual(room, dir)
        mm.runtime.native_exit_lock_visuals[key] = nil
        return true, changed
    end

    -- A classified non-geometric cardinal is deliberately a Mudlet exit stub.
    -- Never bridge those pocket layouts with a custom line just for lock color.
    if native_cardinal_target(room, dir) ~= destination then
        local changed = remove_native_exit_visual(room, dir)
        mm.runtime.native_exit_lock_visuals[key] = nil
        return false, changed
    end
    if type(addCustomLine) ~= "function" then return false, false end

    local state = snd.mapper.exitLockVisualState(lockLevel, playerLevel)
    local previous = mm.runtime.native_exit_lock_visuals[key]
    if not force and previous and previous.state == state
        and tonumber(previous.touid) == destination
        and tonumber(previous.level) == lockLevel
    then
        return true, false
    end

    local color = nativeExitVisualColors[state]
    local ok, result = pcall(
        addCustomLine,
        room,
        destination,
        dir,
        "solid line",
        {color[1], color[2], color[3]},
        true
    )
    if not ok or result == false then return false, false end
    mm.runtime.native_exit_lock_visuals[key] = {
        state = state,
        fromuid = room,
        touid = destination,
        dir = dir,
        level = lockLevel,
    }
    return true, true
end

local function cardinal_exit_visual_rows(roomId, dir)
    if not snd.mapper.db.open() then return {} end
    local where = {
        "fromuid NOT IN ('*','**')",
        "LOWER(TRIM(dir)) IN (" .. mapperCardinalDirectionsSql .. ")",
    }
    local normalizedDir = snd.mapper.normalizeDirection(dir)
    if roomId ~= nil then
        table.insert(where, "fromuid = " .. snd.mapper.db.escape(tostring(roomId)))
    end
    if normalizedDir then
        table.insert(where, string.format(
            "LOWER(TRIM(dir)) IN (%s, %s)",
            snd.mapper.db.escape(normalizedDir),
            snd.mapper.db.escape(mapperDirectionNames[normalizedDir])
        ))
    else
        table.insert(where, "level > 0")
    end

    local rows = snd.mapper.db.query(
        "SELECT fromuid, touid, dir, level FROM exits WHERE " .. table.concat(where, " AND ")
    ) or {}
    local merged = {}
    for _, row in ipairs(rows) do
        local normalized = snd.mapper.normalizeDirection(row.dir)
        local from = tonumber(row.fromuid)
        local destination = tonumber(row.touid)
        if normalized and from and destination and destination > 0 then
            local key = native_visual_key(from, normalized)
            local existing = merged[key]
            local rowLevel = tonumber(row.level) or 0
            if not existing then
                merged[key] = {
                    fromuid = from,
                    touid = destination,
                    dir = normalized,
                    level = rowLevel,
                    canonical = tostring(row.dir):lower():match("^%s*(.-)%s*$") == normalized,
                }
            else
                existing.level = math.max(tonumber(existing.level) or 0, rowLevel)
                local canonical = tostring(row.dir):lower():match("^%s*(.-)%s*$") == normalized
                if canonical and not existing.canonical then
                    existing.touid = destination
                    existing.canonical = true
                end
            end
        end
    end

    local result = {}
    for _, row in pairs(merged) do table.insert(result, row) end
    table.sort(result, function(a, b)
        if a.fromuid ~= b.fromuid then return a.fromuid < b.fromuid end
        return tostring(a.dir) < tostring(b.dir)
    end)
    return result
end

function snd.mapper.refreshNativeExitLockVisuals(playerLevel, force)
    if type(getRoomExits) ~= "function" or type(addCustomLine) ~= "function" then
        return false, {applied = 0, removed = 0}
    end

    mm.runtime = mm.runtime or {}
    local previous = mm.runtime.native_exit_lock_visuals or {}
    local current = {}
    local applied, removed, changed = 0, 0, false
    for _, row in ipairs(cardinal_exit_visual_rows()) do
        local ok, didChange = apply_native_exit_visual(row, playerLevel, force)
        local key = native_visual_key(row.fromuid, row.dir)
        if ok and mm.runtime.native_exit_lock_visuals[key] then
            current[key] = mm.runtime.native_exit_lock_visuals[key]
            applied = applied + 1
        end
        changed = changed or didChange
    end

    for key in pairs(previous) do
        if not current[key] then
            local from, dir = key:match("^(.-):([^:]+)$")
            if from and dir and remove_native_exit_visual(from, dir) then
                removed = removed + 1
                changed = true
            end
        end
    end
    mm.runtime.native_exit_lock_visuals = current
    if changed and type(updateMap) == "function" then pcall(updateMap) end
    return true, {applied = applied, removed = removed}
end

function snd.mapper.syncExitLockVisual(roomId, dir)
    local normalizedDir = snd.mapper.normalizeDirection(dir)
    if not normalizedDir then return false end

    if mm and mm.import and mm.import.invalidate_layout_cache then
        mm.import.invalidate_layout_cache()
    end
    if mm and mm.minimap and mm.minimap.is_local_mode and mm.minimap.is_local_mode()
        and mm.minimap.update_local_map
    then
        mm.minimap.update_local_map(roomId, {force = true})
    end

    local nativeLoaded = mm and mm.runtime and mm.runtime.native_mapper_db_loaded_path
    if not nativeLoaded then return true end
    local rows = cardinal_exit_visual_rows(roomId, normalizedDir)
    local row = rows[1] or {
        fromuid = roomId,
        dir = normalizedDir,
        level = 0,
    }
    local _, changed = apply_native_exit_visual(row, snd.mapper.currentExitVisualLevel(), false)
    if changed and type(updateMap) == "function" then pcall(updateMap) end
    return true
end

function snd.mapper.restyleNativeExitLockVisuals(playerLevel)
    local cached = mm and mm.runtime and mm.runtime.native_exit_lock_visuals or nil
    if type(cached) ~= "table" or not next(cached) then return true end

    local rows = {}
    for _, visual in pairs(cached) do
        table.insert(rows, {
            fromuid = visual.fromuid,
            touid = visual.touid,
            dir = visual.dir,
            level = visual.level,
        })
    end
    local changed = false
    for _, row in ipairs(rows) do
        local _, didChange = apply_native_exit_visual(row, playerLevel, false)
        changed = changed or didChange
    end
    if changed and type(updateMap) == "function" then pcall(updateMap) end
    return true
end

function snd.mapper.refreshExitLockVisualStates()
    local level = snd.mapper.currentExitVisualLevel()
    if mm and mm.minimap and mm.minimap.refresh_exit_lock_styles then
        mm.minimap.refresh_exit_lock_styles()
    end
    if mm and mm.runtime and mm.runtime.native_mapper_db_loaded_path then
        snd.mapper.restyleNativeExitLockVisuals(level)
    end
    return true
end

-------------------------------------------------------------------------------
-- Room Information
-------------------------------------------------------------------------------

--- Get room info from mapper database
-- @param roomId Room UID
-- @return Table with room data or nil
function snd.mapper.getRoomInfo(roomId)
    if not roomId then return nil end
    
    local sql = string.format(
        "SELECT uid, name, area, norecall, noportal, info FROM rooms WHERE uid = %s",
        snd.mapper.db.escape(tostring(roomId))
    )
    
    local results = snd.mapper.db.query(sql)
    if results and #results > 0 then
        return results[1]
    end
    return nil
end

function snd.mapper.normalizeRoomInfoUid(roomInfo)
    return mm.canonical_room_uid(roomInfo)
end

function snd.mapper.getLiveRoomInfo()
    if mm and type(mm.get_room_info) == "function" then
        local ok, info = pcall(mm.get_room_info)
        if ok and type(info) == "table" then
            return info
        end
    end
    if gmcp and gmcp.room and type(gmcp.room.info) == "table" then
        return gmcp.room.info
    end
    if gmcp and gmcp.Room and type(gmcp.Room.Info) == "table" then
        return gmcp.Room.Info
    end
    return nil
end

-- GMCP is the source of truth at the moment a route is planned. A valid-looking
-- cached nomap UID must not override a newer mapped Room.Info packet.
function snd.mapper.currentRoomUid(syncCache)
    local liveInfo = snd.mapper.getLiveRoomInfo()
    local liveUid = liveInfo and mm.canonical_room_uid(liveInfo) or nil
    if liveUid ~= nil and tostring(liveUid) ~= "" then
        liveUid = tostring(liveUid)
        if syncCache and snd.room and snd.room.current then
            snd.room.current.rmid = liveUid
            snd.room.current.arid = liveInfo.zone or liveInfo.area or snd.room.current.arid or ""
            snd.room.current.name = liveInfo.name or snd.room.current.name or ""
        end
        return liveUid
    end

    local cached = snd.room and snd.room.current and snd.room.current.rmid or nil
    if cached ~= nil and tostring(cached) ~= "" then
        return tostring(cached)
    end
    return nil
end

local function room_info_details(roomInfo)
    if not roomInfo then return nil end
    if roomInfo.details ~= nil then return tostring(roomInfo.details or "") end
    if roomInfo.info ~= nil then return tostring(roomInfo.info or "") end
    return nil
end

function snd.mapper.refreshRoomLookup(roomId, roomName)
    if not roomId or tostring(roomId) == "" then return false, "missing room id" end
    if not snd.mapper.db.open() then return false, "cannot open mapper database" end

    if not snd.mapper.db.roomsLookupReady then
        local existing = snd.mapper.db.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'rooms_lookup'") or {}
        if #existing == 0 then
            local okCreate, createErr = snd.mapper.db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS rooms_lookup USING FTS3(uid, name)")
            if not okCreate then return false, createErr end
        end
        snd.mapper.db.roomsLookupReady = true
    end

    local uid = tostring(roomId)
    local name = tostring(roomName or "")
    local ok, err = snd.mapper.db.execute("DELETE FROM rooms_lookup WHERE uid = " .. snd.mapper.db.escape(uid))
    if not ok then return false, err end

    ok, err = snd.mapper.db.execute(string.format(
        "INSERT INTO rooms_lookup (uid, name) VALUES (%s, %s)",
        snd.mapper.db.escape(uid),
        snd.mapper.db.escape(name)
    ))
    if not ok then return false, err end
    return true
end

function snd.mapper.rebuildRoomsLookup()
    if not snd.mapper.db.open() then return false, "cannot open mapper database" end

    local existing = snd.mapper.db.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'rooms_lookup'") or {}
    if #existing == 0 then
        local okCreate, createErr = snd.mapper.db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS rooms_lookup USING FTS3(uid, name)")
        if not okCreate then return false, createErr end
    end

    local ok, err = snd.mapper.db.execute("BEGIN")
    if not ok then return false, err end

    ok, err = snd.mapper.db.execute("DELETE FROM rooms_lookup")
    if ok then ok, err = snd.mapper.db.execute("INSERT INTO rooms_lookup (uid, name) SELECT uid, COALESCE(name, '') FROM rooms") end

    if ok then
        snd.mapper.db.execute("COMMIT")
        snd.mapper.db.roomsLookupReady = true
        local roomCount = snd.mapper.db.query("SELECT COUNT(*) AS cnt FROM rooms") or {}
        local lookupCount = snd.mapper.db.query("SELECT COUNT(*) AS cnt FROM rooms_lookup") or {}
        return true, {
            rooms = tonumber(roomCount[1] and roomCount[1].cnt) or 0,
            lookup = tonumber(lookupCount[1] and lookupCount[1].cnt) or 0,
        }
    end

    snd.mapper.db.execute("ROLLBACK")
    return false, err
end

function snd.mapper.persistAreaInfo(areaInfo, opts)
    opts = opts or {}
    if type(areaInfo) ~= "table" then return false, "missing area info" end
    if not snd.mapper.db.open() then return false, "cannot open mapper database" end

    local uid = areaInfo.id or areaInfo.uid
    if uid == nil or tostring(uid) == "" then return false, "area info has no id" end
    local name = areaInfo.name or areaInfo.title or ""
    local texture = areaInfo.texture or ""
    local color = areaInfo.col or areaInfo.color or ""
    local flags = areaInfo.flags or ""

    local ok, err = snd.mapper.db.execute(string.format(
        "INSERT OR REPLACE INTO areas (uid, name, texture, color, flags) VALUES (%s, %s, %s, %s, %s)",
        snd.mapper.db.escape(uid),
        snd.mapper.db.escape(name),
        snd.mapper.db.escape(texture),
        snd.mapper.db.escape(color),
        snd.mapper.db.escape(flags)
    ))
    if not opts.defer_stats and mm and mm.bump_stats then
        mm.bump_stats(ok and "areas_updated" or "failed")
    end
    if ok then
        snd.mapper.clanAreaCache = nil
        snd.mapper.clanAreaList = nil
    end
    return ok, err
end

local function sector_rows(sectorsPacket)
    local sectors = sectorsPacket
    if type(sectorsPacket) == "table" and type(sectorsPacket.sectors) == "table" then
        sectors = sectorsPacket.sectors
    end
    if type(sectors) ~= "table" then return nil, "missing sectors list" end

    local rows = {}
    for _, sector in pairs(sectors) do
        if type(sector) == "table" and sector.id ~= nil and sector.name ~= nil then
            table.insert(rows, {
                id = sector.id,
                name = sector.name,
                color = tonumber(sector.color) or 0,
            })
        end
    end
    if #rows == 0 then return nil, "sectors list has no usable entries" end
    return rows
end

local function sector_fingerprint(rows)
    local normalized = {}
    for _, row in ipairs(rows or {}) do
        table.insert(normalized, {
            id = tostring(row.id or row.uid or ""),
            name = tostring(row.name or ""),
            color = tonumber(row.color) or 0,
        })
    end
    table.sort(normalized, function(a, b)
        local aid, bid = tonumber(a.id), tonumber(b.id)
        if aid and bid and aid ~= bid then return aid < bid end
        if a.id ~= b.id then return a.id < b.id end
        if a.name ~= b.name then return a.name < b.name end
        return a.color < b.color
    end)
    local parts = {}
    for _, row in ipairs(normalized) do
        table.insert(parts, table.concat({ row.id, row.name, tostring(row.color) }, "\31"))
    end
    return table.concat(parts, "\30")
end

function snd.mapper.sectorPacketFingerprint(sectorsPacket)
    local rows, err = sector_rows(sectorsPacket)
    if not rows then return nil, err end
    return sector_fingerprint(rows), rows
end

function snd.mapper.loadCommittedSectorFingerprint()
    if snd.mapper.committedSectorFingerprint ~= nil then
        return snd.mapper.committedSectorFingerprint
    end
    if not snd.mapper.db.open() then return nil, "cannot open mapper database" end
    local rows = snd.mapper.db.query("SELECT uid, name, color FROM environments")
    if rows == nil then return nil, "cannot read environment metadata" end
    snd.mapper.committedSectorFingerprint = sector_fingerprint(rows)
    return snd.mapper.committedSectorFingerprint
end

function snd.mapper.persistSectors(sectorsPacket, opts)
    opts = opts or {}
    if not snd.mapper.db.open() then return false, "cannot open mapper database" end

    local rows, rows_err = sector_rows(sectorsPacket)
    if not rows then return false, rows_err end

    local incoming_fingerprint = sector_fingerprint(rows)
    local committed_fingerprint = opts.committed_fingerprint
    if committed_fingerprint == nil and opts.compare ~= false then
        committed_fingerprint = snd.mapper.loadCommittedSectorFingerprint()
    end
    if committed_fingerprint ~= nil and committed_fingerprint == incoming_fingerprint then
        return true, 0, false, incoming_fingerprint
    end

    local owns_transaction = opts.in_transaction ~= true
    local ok, err = true, nil
    if owns_transaction then
        ok, err = snd.mapper.db.execute("BEGIN")
        if not ok then return false, err end
    end
    ok, err = snd.mapper.db.execute("DELETE FROM environments")
    if ok then
        for _, row in ipairs(rows) do
            ok, err = snd.mapper.db.execute(string.format(
                "INSERT OR REPLACE INTO environments (uid, name, color) VALUES (%s, %s, %d)",
                snd.mapper.db.escape(row.id),
                snd.mapper.db.escape(row.name),
                row.color
            ))
            if not ok then break end
        end
    end

    if ok then
        if owns_transaction then
            local commit_ok, commit_err = snd.mapper.db.execute("COMMIT")
            if not commit_ok then
                pcall(snd.mapper.db.execute, "ROLLBACK")
                return false, commit_err
            end
            if not opts.defer_notify and snd.mapper.notifyMapperDbUpdated then
                local currentRoom = snd.room and snd.room.current and snd.room.current.rmid
                snd.mapper.notifyMapperDbUpdated(currentRoom, true)
            end
            snd.mapper.committedSectorFingerprint = incoming_fingerprint
        end
        if not opts.defer_stats and mm and mm.bump_stats then
            mm.bump_stats("env_rows_updated", #rows)
        end
        return true, #rows, true, incoming_fingerprint
    end

    if owns_transaction then snd.mapper.db.execute("ROLLBACK") end
    if not opts.defer_stats and mm and mm.bump_stats then
        mm.bump_stats("failed")
    end
    return false, err
end

-- Retained as a compatibility surface for older callers.  Live Room.Info is
-- not a metadata-discovery trigger: area and sector packets are consumed when
-- they arrive, while explicit map build/repair workflows own any requests.
function snd.mapper.requestMetadataForRoom(roomInfo)
    return false
end

-------------------------------------------------------------------------------
-- Area Level Guard
-------------------------------------------------------------------------------

local AREA_GUARD_DEFAULT_ALLOWANCE = 30

local function normalizeAreaKey(value)
    return tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

-- Clan membership is area metadata. Load it once so route validation does not
-- issue a room/area join for every step in every candidate path.
function snd.mapper.loadClanAreaCache()
    if type(snd.mapper.clanAreaCache) == "table"
        and type(snd.mapper.clanAreaList) == "table"
    then
        return snd.mapper.clanAreaCache, snd.mapper.clanAreaList
    end

    local cache = {}
    local list = {}
    local rows = snd.mapper.db.query([[
        SELECT uid
        FROM areas
        WHERE LOWER(COALESCE(flags, '')) LIKE '%clanarea%'
        ORDER BY uid
    ]]) or {}
    for _, row in ipairs(rows) do
        local key = normalizeAreaKey(row.uid)
        if key ~= "" and not cache[key] then
            cache[key] = true
            table.insert(list, key)
        end
    end

    snd.mapper.clanAreaCache = cache
    snd.mapper.clanAreaList = list
    return cache, list
end

function snd.mapper.isClanArea(areaKey)
    local key = normalizeAreaKey(areaKey)
    if key == "" then return false end
    local cache = snd.mapper.loadClanAreaCache()
    return cache[key] == true
end

function snd.mapper.isClanRoom(roomId, roomInfo)
    local info = roomInfo or snd.mapper.getRoomInfo(roomId)
    return info ~= nil and snd.mapper.isClanArea(info.area)
end

function snd.mapper.portalGuardEnabled()
    return mm and type(mm.portal_guard_entries) == "function"
        and #mm.portal_guard_entries() > 0
end

function snd.mapper.portalGuardBypassed(ignoreLockedExits)
    return ignoreLockedExits == true
end

function snd.mapper.portalGuardSql(dirExpression, levelExpression, effectiveLevel, ignoreLockedExits)
    if snd.mapper.portalGuardBypassed(ignoreLockedExits) then
        return "1=1"
    end

    local clauses = {}
    local entries = mm and type(mm.portal_guard_entries) == "function"
        and mm.portal_guard_entries()
        or {}
    for _, details in ipairs(entries) do
        local command = tostring(details.portal and details.portal.command or ""):lower()
        local guardLevel = tonumber(details.guard_level)
        if command ~= "" and guardLevel and guardLevel > 0 then
            table.insert(clauses, string.format(
                "(LOWER(%s) <> %s OR (%s + %d) <= %d)",
                dirExpression,
                snd.mapper.db.escape(command),
                levelExpression,
                math.floor(guardLevel),
                math.floor(tonumber(effectiveLevel) or 0)
            ))
        end
    end
    return #clauses > 0 and table.concat(clauses, " AND ") or "1=1"
end

function snd.mapper.portalStepAllowed(step, ignoreLockedExits)
    if snd.mapper.portalGuardBypassed(ignoreLockedExits) then
        return true
    end

    local portalLevel = tonumber(step and step.level) or 0
    local effectiveLevel = (tonumber(snd.char and snd.char.level) or 0)
        + ((tonumber(snd.char and snd.char.tier) or 0) * 10)
    local guardLevel = 0
    if mm and type(mm.portal_guard_details_for_command) == "function" then
        local details = mm.portal_guard_details_for_command(step and step.dir)
        guardLevel = details and (tonumber(details.guard_level) or 0) or 0
    end
    return (portalLevel + guardLevel) <= effectiveLevel
end

function snd.mapper.areaGuardConfig()
    local cfg = snd.config and snd.config.areaGuard or nil
    if type(cfg) ~= "table" then
        return {enabled = false, allowance = AREA_GUARD_DEFAULT_ALLOWANCE}
    end
    return cfg
end

function snd.mapper.areaGuardEnabled()
    return (tonumber(snd.mapper.areaGuardForceDepth) or 0) > 0
        or snd.mapper.areaGuardConfig().enabled == true
end

-- Temporarily force AreaGuard on for synchronous, read-only route planning.
-- The persisted setting is never changed, and the previous runtime depth is
-- restored even if the callback raises an error.
function snd.mapper.withAreaGuardForced(callback)
    if type(callback) ~= "function" then
        error("withAreaGuardForced expects a function", 2)
    end

    local previousDepth = tonumber(snd.mapper.areaGuardForceDepth) or 0
    snd.mapper.areaGuardForceDepth = previousDepth + 1
    local function packResults(...)
        return {count = select("#", ...), ...}
    end
    local results = packResults(pcall(callback))
    snd.mapper.areaGuardForceDepth = previousDepth

    if not results[1] then
        error(results[2], 0)
    end

    local unpackResults = table.unpack or unpack
    return unpackResults(results, 2, results.count)
end

function snd.mapper.areaGuardAllowance()
    return math.max(0, tonumber(snd.mapper.areaGuardConfig().allowance) or AREA_GUARD_DEFAULT_ALLOWANCE)
end

function snd.mapper.areaGuardPlayerLevel()
    return tonumber(snd.char and snd.char.level) or 0
end

function snd.mapper.areaGuardBypassed(ignoreLockedExits, ignoreAreaGuard)
    return ignoreLockedExits == true or ignoreAreaGuard == true or not snd.mapper.areaGuardEnabled()
end

function snd.mapper.evaluateAreaGuard(areaKey)
    local normalized = normalizeAreaKey(areaKey)
    if normalized == "" then
        return {known = false, allowed = true, area = tostring(areaKey or "")}
    end

    local refs = mm.area_references
    local ref = refs and type(refs.get) == "function" and refs.get(normalized) or nil
    if not ref then
        return {known = false, allowed = true, area = tostring(areaKey or "")}
    end

    local level = snd.mapper.areaGuardPlayerLevel()
    local allowance = snd.mapper.areaGuardAllowance()
    local required = refs.required_level(ref, allowance) or 0
    return {
        known = true,
        allowed = level >= required,
        area = ref.name or tostring(areaKey),
        keyword = ref.keyword or normalized,
        min = tonumber(ref.min) or 0,
        lock = tonumber(ref.lock) or 0,
        required = required,
        level = level,
        allowance = allowance,
    }
end

function snd.mapper.evaluateRoomAreaGuard(roomId)
    local room = snd.mapper.getRoomInfo(roomId)
    if not room then
        snd.utils.debugNote("Area guard: room " .. tostring(roomId) .. " is unknown; allowing destination.")
        return {known = false, allowed = true, roomId = tostring(roomId or "")}
    end

    local result = snd.mapper.evaluateAreaGuard(room.area)
    result.roomId = tostring(roomId or "")
    result.roomName = room.name
    result.mapperArea = room.area
    return result
end

function snd.mapper.echoAreaGuardOverride(destination)
    local dest = snd.utils.trim(tostring(destination or ""))
    if dest == "" then return end

    cecho("<yellow>[MMAPPER]<reset> Override: ")
    local label = "[xrtforce " .. dest .. "]"
    local command = string.format([[snd.mapper.xrtforce(%q)]], dest)
    if type(echoLink) == "function" then
        echoLink(label, command, "Navigate without area, portal, or exit-level guards", true)
    else
        echo(label)
    end
    echo("\n")
end

function snd.mapper.reportAreaGuardDestinationBlocked(result, destination)
    local lockText = ""
    if (tonumber(result.lock) or 0) > 0 then
        lockText = string.format("; entry lock %d", tonumber(result.lock))
    end
    cecho(string.format(
        "<orange_red>[MMAPPER]<reset> Navigation blocked: %s is rated level %d%s; your level is %d.\n",
        tostring(result.area or result.mapperArea or "That area"),
        tonumber(result.min) or 0,
        lockText,
        tonumber(result.level) or 0
    ))
    cecho(string.format(
        "<yellow>[MMAPPER]<reset> Area guard requires level %d with the %d-level allowance.\n",
        tonumber(result.required) or 0,
        tonumber(result.allowance) or AREA_GUARD_DEFAULT_ALLOWANCE
    ))
    snd.mapper.echoAreaGuardOverride(destination)
end

function snd.mapper.reportAreaGuardRouteBlocked(destination)
    cecho("<orange_red>[MMAPPER]<reset> No guarded route found; every known route crosses an area above your guarded level.\n")
    snd.mapper.echoAreaGuardOverride(destination)
end

function snd.mapper.checkAreaGuardDestination(currentRoom, destinationRoom, overrideDestination, ignoreLockedExits, ignoreAreaGuard)
    if snd.mapper.areaGuardBypassed(ignoreLockedExits, ignoreAreaGuard) then
        snd.utils.debugNote(string.format(
            "Area guard destination check bypassed: room=%s force=%s",
            tostring(destinationRoom),
            tostring(ignoreLockedExits == true or ignoreAreaGuard == true)
        ))
        return true
    end

    local result = snd.mapper.evaluateRoomAreaGuard(destinationRoom)
    if snd.mapper.isClanArea(result.mapperArea) then
        snd.utils.debugNote(string.format(
            "Area guard destination allowed: room=%s area='%s' is a clan area.",
            tostring(destinationRoom),
            tostring(result.mapperArea or "?")
        ))
        return true
    end
    if not result.known then
        snd.utils.debugNote(string.format(
            "Area guard destination allowed: room=%s area='%s' has no reference metadata.",
            tostring(destinationRoom),
            tostring(result.mapperArea or "?")
        ))
        return true
    end

    snd.utils.debugNote(string.format(
        "Area guard destination: room=%s area=%s level=%d min=%d lock=%d allowance=%d required=%d allowed=%s",
        tostring(destinationRoom),
        tostring(result.keyword or result.mapperArea or "?"),
        tonumber(result.level) or 0,
        tonumber(result.min) or 0,
        tonumber(result.lock) or 0,
        tonumber(result.allowance) or 0,
        tonumber(result.required) or 0,
        tostring(result.allowed)
    ))

    if result.allowed then
        return true
    end

    snd.mapper.reportAreaGuardDestinationBlocked(result, overrideDestination or destinationRoom)
    return false
end

function snd.mapper.areaGuardRoomSql(roomExpression, sourceRoom, ignoreLockedExits, ignoreAreaGuard)
    if snd.mapper.areaGuardBypassed(ignoreLockedExits, ignoreAreaGuard) then
        return "1=1", 0
    end

    local refs = mm.area_references
    if not refs or type(refs.areas) ~= "table" or type(refs.required_level) ~= "function" then
        snd.utils.debugNote("Area guard SQL filter unavailable because area references are not loaded; allowing route.")
        return "1=1", 0
    end

    local sourceInfo = snd.mapper.getRoomInfo(sourceRoom)
    local sourceArea = normalizeAreaKey(sourceInfo and sourceInfo.area or "")
    local level = snd.mapper.areaGuardPlayerLevel()
    local allowance = snd.mapper.areaGuardAllowance()
    local blocked = {}
    local seen = {}
    local blockedCount = 0

    for _, ref in ipairs(refs.areas) do
        local required = refs.required_level(ref, allowance) or 0
        local keyword = normalizeAreaKey(ref.keyword)
        local name = normalizeAreaKey(ref.name)
        local isSourceArea = sourceArea ~= "" and (sourceArea == keyword or sourceArea == name)
        if level < required and not isSourceArea then
            blockedCount = blockedCount + 1
            for _, alias in ipairs({keyword, name}) do
                if alias ~= "" and not seen[alias] then
                    seen[alias] = true
                    table.insert(blocked, snd.mapper.db.escape(alias))
                end
            end
        end
    end

    if #blocked == 0 then
        return "1=1", 0
    end

    local _, clanAreas = snd.mapper.loadClanAreaCache()
    local clanAreaSql = {}
    for _, areaKey in ipairs(clanAreas or {}) do
        table.insert(clanAreaSql, snd.mapper.db.escape(areaKey))
    end
    local nonClanWhere = #clanAreaSql > 0
        and " AND LOWER(area_guard_room.area) NOT IN (" .. table.concat(clanAreaSql, ",") .. ")"
        or ""

    local sql = string.format(
        "NOT EXISTS (SELECT 1 FROM rooms AS area_guard_room " ..
        "WHERE area_guard_room.uid = %s AND LOWER(area_guard_room.area) IN (%s)%s)",
        roomExpression,
        table.concat(blocked, ","),
        nonClanWhere
    )
    return sql, blockedCount
end

-- Validate a concrete route against the ordinary area policy. Clan rooms are
-- locally exempt, but that exemption never carries into the next non-clan
-- room. Thus a clan cexit landing in a dangerous area is still rejected.
-- The current source area remains escapable and unknown areas fail open,
-- matching areaGuardRoomSql.
function snd.mapper.pathMeetsAreaGuard(sourceRoom, path)
    if not snd.mapper.areaGuardEnabled() then return true, nil, false end

    local sourceInfo = snd.mapper.getRoomInfo(sourceRoom)
    local sourceArea = normalizeAreaKey(sourceInfo and sourceInfo.area or "")
    local usedClanExemption = false

    for _, step in ipairs(path or {}) do
        local roomId = tostring(step.uid or "")
        if roomId ~= "" and roomId ~= "-1" then
            local result = snd.mapper.evaluateRoomAreaGuard(roomId)
            local stepArea = normalizeAreaKey(result and result.mapperArea or "")
            local isSourceArea = sourceArea ~= "" and stepArea == sourceArea
            if snd.mapper.isClanArea(stepArea) then
                usedClanExemption = true
            elseif result and result.known and not result.allowed and not isSourceArea then
                return false, result, usedClanExemption
            end
        end
    end

    return true, nil, usedClanExemption
end

-- Inspect the ordinary shortest route with AreaGuard excluded from route
-- selection. Clan rooms are exempt only for their own room checks; they never
-- authorize earlier or later non-clan rooms. If this candidate is rejected,
-- gotoRoom performs the usual guarded search for the shortest valid fallback.
-- Since acceptance is now a room-local property, that filtered search is
-- equivalent to rejecting unsafe candidates in cost order; no clan-biased
-- pathfinder or Aylor anchor is required.
function snd.mapper.planAreaGuardRoute(
    currentRoom,
    destination,
    noPortals,
    noRecalls,
    ignoreLockedExits
)
    if snd.mapper.areaGuardBypassed(ignoreLockedExits, false) then
        return {active = false, directSafe = false}
    end

    local source = tostring(currentRoom or "")
    local target = tostring(destination or "")
    local directPath, directDepth = snd.mapper.findPath(
        source,
        target,
        noPortals,
        noRecalls,
        ignoreLockedExits,
        true
    )

    local directSafe = false
    local usedClanExemption = false
    local blockedDirect = nil
    if directPath and #directPath > 0 then
        directSafe, blockedDirect, usedClanExemption = snd.mapper.pathMeetsAreaGuard(source, directPath)
        if directSafe then
            local directCandidate = {
                kind = usedClanExemption and "direct_clan_exempt" or "direct_area_safe",
                path = directPath,
                depth = directDepth or #directPath,
            }
            snd.utils.debugNote(usedClanExemption
                and "Area guard: true shortest route is safe with a local clan-room exemption."
                or "Area guard: true shortest route already passes every safety check.")
            return {
                active = true,
                directSafe = true,
                directPath = directPath,
                candidate = directCandidate,
                candidates = {directCandidate},
            }
        else
            snd.utils.debugNote(string.format(
                "Area guard: true shortest route is blocked at room %s (%s).",
                tostring(blockedDirect and blockedDirect.roomId or "?"),
                tostring(blockedDirect and (blockedDirect.keyword or blockedDirect.mapperArea) or "unknown area")
            ))
        end
    end

    return {
        active = true,
        directSafe = false,
        directPath = directPath,
        blocked = blockedDirect,
        candidate = nil,
        candidates = {},
    }
end

--- Persist a discovered room + exits from GMCP room.info into Aardwolf.db
-- @param roomInfo GMCP room.info table
local PERSIST_STATS_FIELDS = { "rooms_updated", "exits_updated", "failed" }

local function new_persist_stats()
    return {
        rooms_updated = 0,
        exits_updated = 0,
        failed = 0,
        layout_changed = false,
    }
end

local function add_persist_stats(total, delta)
    total = total or new_persist_stats()
    if type(delta) ~= "table" then return total end
    for _, field in ipairs(PERSIST_STATS_FIELDS) do
        total[field] = (tonumber(total[field]) or 0) + (tonumber(delta[field]) or 0)
    end
    total.layout_changed = total.layout_changed or delta.layout_changed == true
    return total
end

local function publish_persist_stats(stats)
    if not (mm and mm.bump_stats) or type(stats) ~= "table" then return end
    for _, field in ipairs(PERSIST_STATS_FIELDS) do
        local amount = tonumber(stats[field]) or 0
        if amount > 0 then mm.bump_stats(field, amount) end
    end
end

function snd.mapper.notifyMapperDbUpdated(room_id, invalidate_layout)
    if invalidate_layout and snd.mapper.clearDistanceCache then
        snd.mapper.clearDistanceCache("mapper_db_updated")
    end
    if invalidate_layout and mm and mm.import and mm.import.invalidate_layout_cache then
        mm.import.invalidate_layout_cache()
    end
    local local_mode = not (mm and mm.minimap and mm.minimap.is_local_mode) or
        mm.minimap.is_local_mode()
    local room_already_rendered = mm and mm.runtime and
        tostring(mm.runtime.last_room_num or "") == tostring(room_id or "")
    -- Mudlet can invoke the S&D and MMapper Room.Info handlers in either order.
    -- If the normal render is still coming, invalidating the cache is enough;
    -- that render will consume the committed data. If it already ran, rebuild
    -- only when committed geometry made the active local view stale.
    if invalidate_layout and local_mode and room_already_rendered and
        mm and mm.minimap and mm.minimap.update_local_map then
        mm.minimap.update_local_map(room_id)
    end
    if type(raiseEvent) == "function" then
        raiseEvent("mm.mapper.db.updated", tostring(room_id or ""))
    end
end

function snd.mapper.persistDiscoveredRoom(roomInfo, opts)
    opts = opts or {}
    local statDelta = new_persist_stats()
    if not roomInfo or not roomInfo.num then
        return false, statDelta
    end
    if not snd.mapper.db.open() then
        statDelta.failed = statDelta.failed + 1
        if not opts.defer_stats then publish_persist_stats(statDelta) end
        return false, statDelta
    end

    local roomId = snd.mapper.normalizeRoomInfoUid(roomInfo)
    if not roomId or roomId == "" then
        return false, statDelta
    end
    if opts.layout_changed ~= nil then
        statDelta.layout_changed = opts.layout_changed == true
    elseif mm and mm.import and mm.import.layout_cache_matches_room then
        statDelta.layout_changed = not mm.import.layout_cache_matches_room(roomInfo)
    else
        statDelta.layout_changed = true
    end
    local areaKey = tostring(roomInfo.zone or roomInfo.area or "")
    local roomName = (mm and mm.strip_ansi) and mm.strip_ansi(roomInfo.name) or tostring(roomInfo.name or "")
    local terrain = tostring(roomInfo.terrain or "")
    local details = room_info_details(roomInfo)
    local writeRoom = opts.write_room ~= false
    local writeLookup = opts.write_lookup ~= false
    local writeExits = opts.write_exits ~= false
    local roomCols = writeRoom and snd.mapper.db.tableColumns("rooms") or {}

    if writeRoom then
        local insertCols = { "uid", "name", "area", "terrain" }
        local insertVals = {
            snd.mapper.db.escape(roomId),
            snd.mapper.db.escape(roomName),
            snd.mapper.db.escape(areaKey),
            snd.mapper.db.escape(terrain),
        }
        if roomCols.info and details ~= nil then
            table.insert(insertCols, "info")
            table.insert(insertVals, snd.mapper.db.escape(details))
        end
        if roomCols.norecall then
            table.insert(insertCols, "norecall")
            table.insert(insertVals, "0")
        end
        if roomCols.noportal then
            table.insert(insertCols, "noportal")
            table.insert(insertVals, "0")
        end

        local insertRoomSql = string.format(
            "INSERT OR IGNORE INTO rooms (%s) VALUES (%s)",
            table.concat(insertCols, ", "),
            table.concat(insertVals, ", ")
        )
        local insertRoomOk = snd.mapper.db.conn:execute(insertRoomSql)

        local updates = {
            "name = " .. snd.mapper.db.escape(roomName),
            "area = " .. snd.mapper.db.escape(areaKey),
            "terrain = " .. snd.mapper.db.escape(terrain),
        }
        if roomCols.info and details ~= nil then
            table.insert(updates, "info = " .. snd.mapper.db.escape(details))
        end
        local updateRoomSql = string.format(
            "UPDATE rooms SET %s WHERE uid = %s",
            table.concat(updates, ", "),
            snd.mapper.db.escape(roomId)
        )
        local updateRoomOk = snd.mapper.db.conn:execute(updateRoomSql)
        if insertRoomOk and updateRoomOk then
            statDelta.rooms_updated = statDelta.rooms_updated + 1
        else
            statDelta.failed = statDelta.failed + 1
        end
    end

    if writeLookup then
        local lookupOk, lookupErr = snd.mapper.refreshRoomLookup(roomId, roomName)
        if not lookupOk then
            snd.utils.debugNote("rooms_lookup refresh failed for " .. tostring(roomId) .. ": " .. tostring(lookupErr))
            statDelta.failed = statDelta.failed + 1
        end
    end

    local exits = roomInfo.exits
    if writeExits and type(exits) == "table" then
        local exitsUpdated = 0
        local exitFailures = 0
        -- Room.Info is authoritative for cardinal destinations, but mapper
        -- lock levels are local metadata. Reconcile the live cardinal set in
        -- place so surviving directions retain their levels. Only genuinely
        -- new directions start at level 0; custom, recall, and portal rows are
        -- never part of this reconciliation.
        local existingCardinals = snd.mapper.db.query(string.format([[
            SELECT dir, touid, level
            FROM exits
            WHERE fromuid = %s AND LOWER(dir) IN (%s)
        ]],
            snd.mapper.db.escape(roomId),
            mapperCardinalDirectionsSql
        ))
        if existingCardinals == nil then
            exitFailures = exitFailures + 1
        else
            local preservedLevels = {}
            local preservedFromCanonical = {}
            for _, row in ipairs(existingCardinals) do
                local normalizedDir = snd.mapper.normalizeDirection(row.dir)
                if normalizedDir then
                    local storedDir = tostring(row.dir or ""):lower():match("^%s*(.-)%s*$")
                    local isCanonical = storedDir == normalizedDir
                    if preservedLevels[normalizedDir] == nil
                        or (isCanonical and not preservedFromCanonical[normalizedDir])
                    then
                        preservedLevels[normalizedDir] = tonumber(row.level) or 0
                        preservedFromCanonical[normalizedDir] = isCanonical
                    end
                end
            end

            local liveCardinals = {}
            for dir, toUid in pairs(exits) do
                local toRoom = tonumber(toUid)
                local normalizedDir = snd.mapper.normalizeDirection(dir)
                if normalizedDir and toRoom and (toRoom > 0 or toRoom == -1) then
                    liveCardinals[normalizedDir] = tostring(toRoom)
                end
            end

            local liveDirections = {}
            for storedDir in pairs(liveCardinals) do
                table.insert(liveDirections, storedDir)
            end
            table.sort(liveDirections)

            for _, storedDir in ipairs(liveDirections) do
                local toRoom = liveCardinals[storedDir]
                local preservedLevel = tonumber(preservedLevels[storedDir]) or 0
                -- Preserve direction-only maze exits as -1 so map renderers can
                -- draw arrows even though navigation has no destination room.
                local insertExitSql = string.format(
                    "INSERT OR IGNORE INTO exits (dir, fromuid, touid, level) VALUES (%s, %s, %s, %d)",
                    snd.mapper.db.escape(storedDir),
                    snd.mapper.db.escape(roomId),
                    snd.mapper.db.escape(toRoom),
                    preservedLevel
                )
                local insertExitOk = snd.mapper.db.conn:execute(insertExitSql)

                local updateExitSql = string.format(
                    "UPDATE exits SET touid = %s WHERE fromuid = %s AND dir = %s",
                    snd.mapper.db.escape(toRoom),
                    snd.mapper.db.escape(roomId),
                    snd.mapper.db.escape(storedDir)
                )
                local updateExitOk = snd.mapper.db.conn:execute(updateExitSql)
                if insertExitOk and updateExitOk then
                    exitsUpdated = exitsUpdated + 1
                else
                    exitFailures = exitFailures + 1
                end
            end

            local staleWhere = ""
            if #liveDirections > 0 then
                local escapedDirections = {}
                for _, dir in ipairs(liveDirections) do
                    table.insert(escapedDirections, snd.mapper.db.escape(dir))
                end
                staleWhere = " AND LOWER(dir) NOT IN (" .. table.concat(escapedDirections, ",") .. ")"
            end
            local deleteOk, deleteResult = snd.mapper.db.execute(string.format(
                "DELETE FROM exits WHERE fromuid = %s AND LOWER(dir) IN (%s)%s",
                snd.mapper.db.escape(roomId),
                mapperCardinalDirectionsSql,
                staleWhere
            ))
            if deleteOk then
                exitsUpdated = exitsUpdated + (tonumber(deleteResult) or 0)
            else
                exitFailures = exitFailures + 1
            end
        end

        statDelta.exits_updated = statDelta.exits_updated + exitsUpdated
        statDelta.failed = statDelta.failed + exitFailures
    end

    if not opts.defer_stats then
        publish_persist_stats(statDelta)
    end
    if not opts.defer_notify then
        snd.mapper.notifyMapperDbUpdated(roomId, statDelta.layout_changed)
    end
    return statDelta.failed == 0, statDelta
end

local function pending_room_ids(pendingRooms)
    local ids = {}
    for _, roomInfo in pairs(pendingRooms or {}) do
        local uid = snd.mapper.normalizeRoomInfoUid(roomInfo)
        if uid and uid ~= "" then table.insert(ids, tostring(uid)) end
    end
    table.sort(ids)
    return ids
end

local function query_pending_chunks(ids, build_sql)
    local rows = {}
    local chunk_size = 400
    for first = 1, #ids, chunk_size do
        local escaped = {}
        for index = first, math.min(#ids, first + chunk_size - 1) do
            table.insert(escaped, snd.mapper.db.escape(ids[index]))
        end
        local result = snd.mapper.db.query(build_sql(table.concat(escaped, ", ")))
        if result == nil then return nil end
        for _, row in ipairs(result) do table.insert(rows, row) end
    end
    return rows
end

function snd.mapper.loadPendingRoomDbState(pendingRooms)
    local ids = pending_room_ids(pendingRooms)
    local state = {
        rooms = {},
        exits = {},
        exit_counts = {},
        room_columns = {},
    }
    if #ids == 0 then return state end
    state.room_columns = snd.mapper.db.tableColumns("rooms")

    local select_columns = { "uid", "name", "area", "terrain" }
    if state.room_columns.info then table.insert(select_columns, "info") end
    local room_rows = query_pending_chunks(ids, function(in_clause)
        return "SELECT " .. table.concat(select_columns, ", ") ..
            " FROM rooms WHERE uid IN (" .. in_clause .. ")"
    end)
    if room_rows == nil then return nil, "cannot load buffered room rows" end
    for _, row in ipairs(room_rows) do
        state.rooms[tostring(row.uid)] = row
    end

    local exit_rows = query_pending_chunks(ids, function(in_clause)
        return "SELECT fromuid, dir, touid FROM exits WHERE fromuid IN (" .. in_clause ..
            ") AND LOWER(dir) IN (" .. mapperCardinalDirectionsSql .. ")"
    end)
    if exit_rows == nil then return nil, "cannot load buffered cardinal exits" end
    for _, row in ipairs(exit_rows) do
        local uid = tostring(row.fromuid or "")
        local dir = snd.mapper.normalizeDirection(row.dir)
        local target = tonumber(row.touid)
        if uid ~= "" and dir and target and (target > 0 or target == -1) then
            state.exits[uid] = state.exits[uid] or {}
            state.exit_counts[uid] = state.exit_counts[uid] or {}
            state.exits[uid][dir] = target
            state.exit_counts[uid][dir] = (state.exit_counts[uid][dir] or 0) + 1
        end
    end
    return state
end

local function normalized_live_cardinal_exits(roomInfo)
    if type(roomInfo and roomInfo.exits) ~= "table" then return nil end
    local exits = {}
    for raw_dir, raw_target in pairs(roomInfo.exits) do
        local dir = snd.mapper.normalizeDirection(raw_dir)
        local target = tonumber(raw_target)
        if dir and target and (target > 0 or target == -1) then exits[dir] = target end
    end
    return exits
end

local function cardinal_exit_sets_match(live, stored, stored_counts)
    if live == nil then return true end
    stored = stored or {}
    stored_counts = stored_counts or {}
    for dir, target in pairs(live) do
        if tonumber(stored[dir]) ~= tonumber(target) then return false end
        if tonumber(stored_counts[dir]) and tonumber(stored_counts[dir]) > 1 then return false end
    end
    for dir in pairs(stored) do
        if live[dir] == nil then return false end
    end
    return true
end

function snd.mapper.planRoomPersist(roomInfo, dbState)
    local uid = snd.mapper.normalizeRoomInfoUid(roomInfo)
    local stored = uid and dbState and dbState.rooms[tostring(uid)] or nil
    local columns = dbState and dbState.room_columns or {}
    local roomName = (mm and mm.strip_ansi) and mm.strip_ansi(roomInfo.name) or tostring(roomInfo.name or "")
    local areaKey = tostring(roomInfo.zone or roomInfo.area or "")
    local terrain = tostring(roomInfo.terrain or "")
    local details = room_info_details(roomInfo)
    local isNew = stored == nil

    local nameChanged = isNew or tostring(stored.name or "") ~= roomName
    local areaChanged = isNew or tostring(stored.area or "") ~= areaKey
    local terrainChanged = isNew or tostring(stored.terrain or "") ~= terrain
    local detailsChanged = false
    if columns.info and details ~= nil then
        detailsChanged = isNew or tostring(stored.info or "") ~= tostring(details)
    end
    local liveExits = normalized_live_cardinal_exits(roomInfo)
    local exitsChanged = liveExits ~= nil and (isNew or not cardinal_exit_sets_match(
        liveExits,
        dbState and dbState.exits[tostring(uid)] or nil,
        dbState and dbState.exit_counts[tostring(uid)] or nil
    ))
    local roomChanged = isNew or nameChanged or areaChanged or terrainChanged or detailsChanged

    return {
        is_new = isNew,
        write_room = roomChanged,
        write_lookup = nameChanged,
        write_exits = exitsChanged,
        layout_changed = isNew or areaChanged or terrainChanged or exitsChanged,
        changed = roomChanged or exitsChanged,
    }
end

snd.mapper.pendingPersists = snd.mapper.pendingPersists or {}
snd.mapper.pendingAreaPersists = snd.mapper.pendingAreaPersists or {}
snd.mapper.pendingSectorsPersist = snd.mapper.pendingSectorsPersist or nil

local function persistence_snapshot(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[persistence_snapshot(key, seen)] = persistence_snapshot(item, seen)
    end
    return copy
end

function snd.mapper.persistenceNavigationActive()
    return (snd.nav and snd.nav.goingToRoom ~= nil)
        or snd.mapper.goingToRoom ~= nil
        or snd.mapper.pathExecutionActive == true
        or snd.mapper.persistenceArrivalSettling == true
end

function snd.mapper.bufferRoomPersist(ri)
    if not ri or not ri.num then return false end
    local key = snd.mapper.normalizeRoomInfoUid(ri) or tostring(ri.num)
    snd.mapper.pendingPersists[tostring(key)] = persistence_snapshot(ri)
    return true
end

function snd.mapper.bufferAreaPersist(areaInfo)
    if type(areaInfo) ~= "table" then return false end
    local uid = areaInfo.id or areaInfo.uid
    if uid == nil or tostring(uid) == "" then return false end
    snd.mapper.pendingAreaPersists[tostring(uid)] = persistence_snapshot(areaInfo)
    return true
end

function snd.mapper.bufferSectorsPersist(sectorsPacket)
    if type(sectorsPacket) ~= "table" then return false end
    snd.mapper.pendingSectorsPersist = persistence_snapshot(sectorsPacket)
    return true
end

local function has_pending_persistence()
    return next(snd.mapper.pendingPersists or {}) ~= nil
        or next(snd.mapper.pendingAreaPersists or {}) ~= nil
        or snd.mapper.pendingSectorsPersist ~= nil
end

function snd.mapper.hasPendingPersistence()
    return has_pending_persistence()
end

function snd.mapper.flushPendingPersists(opts)
    opts = opts or {}
    snd.mapper.persistenceFlushSerial = (tonumber(snd.mapper.persistenceFlushSerial) or 0) + 1
    snd.mapper.persistenceArrivalSettling = false
    if not has_pending_persistence() then return true, new_persist_stats() end
    if not snd.mapper.db.open() then return false, "cannot open mapper database" end

    local totals = new_persist_stats()
    local pendingRooms = snd.mapper.pendingPersists or {}
    local pendingAreas = snd.mapper.pendingAreaPersists or {}
    local pendingSectors = snd.mapper.pendingSectorsPersist
    local areaCount = 0
    local sectorCount = 0
    local sectorFingerprint = nil
    local redrawRoom = nil
    local databaseChanged = false

    local beginOk, beginErr = snd.mapper.db.execute("BEGIN")
    if not beginOk then return false, beginErr end

    local flushOk = true
    local flushErr = nil
    local dbState = nil
    if opts.bulk_compare ~= false then
        local stateErr
        dbState, stateErr = snd.mapper.loadPendingRoomDbState(pendingRooms)
        if not dbState then
            flushOk = false
            flushErr = stateErr
        end
    end
    if flushOk then
        for roomKey, ri in pairs(pendingRooms) do
            redrawRoom = snd.mapper.normalizeRoomInfoUid(ri) or redrawRoom
            local persistPlan = dbState and snd.mapper.planRoomPersist(ri, dbState) or nil
            if persistPlan then
                totals.layout_changed = totals.layout_changed or persistPlan.layout_changed
            end
            if not persistPlan or persistPlan.changed then
                databaseChanged = true
                local persistOpts = {
                    defer_stats = true,
                    defer_notify = true,
                }
                if persistPlan then
                    persistOpts.write_room = persistPlan.write_room
                    persistOpts.write_lookup = persistPlan.write_lookup
                    persistOpts.write_exits = persistPlan.write_exits
                    persistOpts.layout_changed = persistPlan.layout_changed
                end
                local ok, delta = snd.mapper.persistDiscoveredRoom(ri, persistOpts)
                add_persist_stats(totals, delta)
                if not ok then
                    flushOk = false
                    flushErr = "failed to persist room " .. tostring(roomKey)
                    break
                end
            end
        end
    end

    if flushOk then
        for areaKey, areaInfo in pairs(pendingAreas) do
            local ok, err = snd.mapper.persistAreaInfo(areaInfo, { defer_stats = true })
            if not ok then
                flushOk = false
                flushErr = "failed to persist area " .. tostring(areaKey) .. ": " .. tostring(err)
                break
            end
            areaCount = areaCount + 1
            databaseChanged = true
        end
    end

    if flushOk and pendingSectors then
        local ok, result, changed, fingerprint = snd.mapper.persistSectors(pendingSectors, {
            in_transaction = true,
            defer_stats = true,
        })
        if not ok then
            flushOk = false
            flushErr = "failed to persist sectors: " .. tostring(result)
        else
            sectorCount = tonumber(result) or 0
            sectorFingerprint = fingerprint
            databaseChanged = databaseChanged or changed == true
            -- Environment colors are visual, but an identical packet does not
            -- invalidate or redraw the local graph.
            totals.layout_changed = totals.layout_changed or changed == true
        end
    end

    if not flushOk then
        snd.mapper.db.execute("ROLLBACK")
        if mm and mm.bump_stats then mm.bump_stats("failed") end
        return false, flushErr
    end

    local commitOk, commitErr = snd.mapper.db.execute("COMMIT")
    if not commitOk then
        pcall(snd.mapper.db.execute, "ROLLBACK")
        if mm and mm.bump_stats then mm.bump_stats("failed") end
        return false, commitErr
    end

    -- Clear only after a successful commit so interrupted/failed routes can be
    -- retried by the existing orphan-buffer path.
    snd.mapper.pendingPersists = {}
    snd.mapper.pendingAreaPersists = {}
    snd.mapper.pendingSectorsPersist = nil
    if sectorFingerprint ~= nil then
        snd.mapper.committedSectorFingerprint = sectorFingerprint
    end

    publish_persist_stats(totals)
    if mm and mm.bump_stats then
        if areaCount > 0 then mm.bump_stats("areas_updated", areaCount) end
        if sectorCount > 0 then mm.bump_stats("env_rows_updated", sectorCount) end
    end
    local currentRoom = snd.room and snd.room.current and snd.room.current.rmid
    if databaseChanged then
        snd.mapper.notifyMapperDbUpdated(currentRoom or redrawRoom, totals.layout_changed)
    end
    return true, totals
end

function snd.mapper.schedulePendingPersistFlush()
    snd.mapper.persistenceFlushSerial = (tonumber(snd.mapper.persistenceFlushSerial) or 0) + 1
    local serial = snd.mapper.persistenceFlushSerial
    snd.mapper.persistenceArrivalSettling = true
    if type(tempTimer) ~= "function" then
        snd.mapper.persistenceArrivalSettling = false
        return snd.mapper.flushPendingPersists()
    end
    tempTimer(0, function()
        if serial ~= snd.mapper.persistenceFlushSerial then return end
        snd.mapper.persistenceArrivalSettling = false
        snd.mapper.flushPendingPersists()
    end)
    return true
end

local function tokenizeInfo(info)
    local tokens = {}
    local v = tostring(info or "")
    if v == "" then return tokens end
    for item in v:gmatch("[^,]+") do
        local clean = item:gsub("^%s+", ""):gsub("%s+$", "")
        if clean ~= "" then table.insert(tokens, clean) end
    end
    return tokens
end

function snd.mapper.infoContainsSafe(info)
    for _, token in ipairs(tokenizeInfo(info)) do
        if token:lower() == "safe" then return true end
    end
    return false
end

function snd.mapper.isSafeRoom(roomId)
    local room = snd.mapper.getRoomInfo(roomId)
    if not room then return false end
    return snd.mapper.infoContainsSafe(room.info)
end

function snd.mapper.markRoomSafe(roomId, value)
    if not roomId then return false end
    if not snd.mapper.db.open() then return false end
    local room = snd.mapper.getRoomInfo(roomId)
    if not room then return false end
    local tokens = tokenizeInfo(room.info)
    local has = false
    for _, t in ipairs(tokens) do
        if t:lower() == "safe" then has = true; break end
    end
    local newTokens = {}
    if value == false then
        if not has then return true end
        for _, t in ipairs(tokens) do
            if t:lower() ~= "safe" then table.insert(newTokens, t) end
        end
    else
        if has then return true end
        for _, t in ipairs(tokens) do table.insert(newTokens, t) end
        table.insert(newTokens, "safe")
    end
    local newInfo = table.concat(newTokens, ",")
    local ok, err = snd.mapper.db.conn:execute(string.format(
        "UPDATE rooms SET info = %s WHERE uid = %s",
        snd.mapper.db.escape(newInfo),
        snd.mapper.db.escape(tostring(roomId))
    ))
    if not ok then
        snd.utils.debugNote("Failed to update info flag: " .. tostring(err))
        return false
    end
    return true
end

--- Check if room allows portals
function snd.mapper.canPortalTo(roomId)
    local room = snd.mapper.getRoomInfo(roomId)
    if not room then return true end  -- Unknown room, assume ok
    return tonumber(room.noportal) ~= 1
end

--- Check if room allows recall
function snd.mapper.canRecallFrom(roomId)
    local room = snd.mapper.getRoomInfo(roomId)
    if not room then return true end
    return tonumber(room.norecall) ~= 1
end

-------------------------------------------------------------------------------
-- Room Search (Quest/XCP support)
-------------------------------------------------------------------------------

local function ellipsify(text, maxLen)
    if not text then return "" end
    if #text <= maxLen then
        return text
    end
    if maxLen <= 3 then
        return text:sub(1, maxLen)
    end
    return text:sub(1, maxLen - 3) .. "..."
end

local function mobRoomPercentageColor(percentage)
    local adjusted = math.min(1, math.max(0, math.sqrt(percentage or 0)))

    if adjusted >= 0.75 then
        return "lime_green"
    elseif adjusted >= 0.5 then
        return "yellow"
    elseif adjusted >= 0.25 then
        return "orange"
    end

    return "red"
end

local function buildRoomQuery(cleanedRoom, arid)
    if arid and (arid == "soh" or arid == "sohtwo") then
        return string.format(
            [[
                SELECT uid, name, area
                FROM rooms
                WHERE name = %s AND (area = %s OR area = %s)
                ORDER BY area
            ]],
            snd.mapper.db.escape(cleanedRoom),
            snd.mapper.db.escape("soh"),
            snd.mapper.db.escape("sohtwo")
        )
    elseif arid and arid ~= "" then
        return string.format(
            [[
                SELECT uid, name, area
                FROM rooms
                WHERE name = %s AND area = %s
                ORDER BY area
            ]],
            snd.mapper.db.escape(cleanedRoom),
            snd.mapper.db.escape(arid)
        )
    end

    return string.format(
        [[
            SELECT uid, name, area
            FROM rooms
            WHERE name = %s
            ORDER BY area
        ]],
        snd.mapper.db.escape(cleanedRoom)
    )
end

local function resolveSearchLevel(options)
    local explicit = options and tonumber(options.levelTaken)
    if explicit and explicit > 0 then
        return explicit
    end

    local activity = options and options.activity or ""
    if activity == "cp" then
        local cpLevel = snd.campaign and tonumber(snd.campaign.levelTaken) or 0
        if cpLevel > 0 then
            return cpLevel
        end
    elseif activity == "gq" then
        local gqLevel = snd.gquest and tonumber(snd.gquest.effectiveLevel) or 0
        if gqLevel > 0 then
            return gqLevel
        end
    end

    return tonumber(snd.char and snd.char.level) or 0
end

local function areaMatchesLevelRange(areaKey, levelTaken)
    if not snd.db or not snd.db.getArea then
        return true
    end
    if not areaKey or areaKey == "" then
        return true
    end

    local area = snd.db.getArea(areaKey)
    if not area then
        return true
    end

    local minLvl = tonumber(area.minlvl) or 0
    local maxLvl = tonumber(area.maxlvl) or 0
    if minLvl <= 0 and maxLvl <= 0 then
        return true
    end

    local level = tonumber(levelTaken) or 0
    return level >= minLvl and level <= (maxLvl + 25)
end

function snd.mapper.searchRoomsExact(room, arid, mobName, options)
    if not room or room == "" then return {} end

    local cleanedRoom = snd.utils.stripColors(room)
    if snd.debug and snd.debug.log then
        snd.debug.log(string.format(
            "searchRoomsExact: room='%s' cleaned='%s' arid='%s' mob='%s'",
            tostring(room),
            tostring(cleanedRoom),
            tostring(arid or ""),
            tostring(mobName or "")
        ))
    end
    local query = buildRoomQuery(cleanedRoom, arid)
    local rows = snd.mapper.db.query(query) or {}
    if snd.debug and snd.debug.recordSearch then
        snd.debug.recordSearch({
            room = room,
            cleanedRoom = cleanedRoom,
            arid = arid or "",
            mobName = mobName or "",
            initialCount = #rows,
            fallbackCount = 0,
            usedFallback = false,
        })
    end

    if arid and arid ~= "" and #rows == 0 then
        local fallbackQuery = buildRoomQuery(cleanedRoom, "")
        rows = snd.mapper.db.query(fallbackQuery) or {}
        if snd.debug and snd.debug.recordSearch then
            snd.debug.recordSearch({
                room = room,
                cleanedRoom = cleanedRoom,
                arid = arid or "",
                mobName = mobName or "",
                initialCount = 0,
                fallbackCount = #rows,
                usedFallback = true,
            })
        end
    end

    return snd.mapper.searchRoomsRows(rows, mobName, options)
end

function snd.mapper.searchMobLocations(mobName, areaKey)
    if not mobName or mobName == "" then
        return {}
    end

    local zone = areaKey or ""
    if snd.debug and snd.debug.log then
        snd.debug.log(string.format(
            "searchMobLocations: mob='%s' zone='%s'",
            tostring(mobName),
            tostring(zone)
        ))
    end

    local rows, matchedName = snd.db.getMobLocations(mobName, zone)
    rows = rows or {}
    local results = {}
    local totalSeen = 0

    for _, row in ipairs(rows) do
        local id = tonumber(row.roomid) or -1
        local seen = tonumber(row.seen_count) or 0
        totalSeen = totalSeen + seen
        table.insert(results, {
            rmid = id,
            name = row.room or "",
            arid = row.zone or zone,
            seen_count = seen,
            nowhere = tonumber(row.nowhere) == 1,
            nohunt = tonumber(row.nohunt) == 1,
            priority_room = tonumber(row.priority_room),
        })
    end

    for _, result in ipairs(results) do
        if totalSeen > 0 then
            result.percentage = (result.seen_count or 0) / totalSeen
        else
            result.percentage = 0
        end
    end

    if snd.debug and snd.debug.mobTag then
        local parts = {}
        for i, result in ipairs(results or {}) do
            if i > 8 then
                table.insert(parts, "...")
                break
            end
            table.insert(parts, string.format(
                "#%d rmid=%s area=%s seen=%s priority_room=%s nowhere=%s nohunt=%s",
                i,
                tostring(result.rmid or ""),
                tostring(result.arid or ""),
                tostring(result.seen_count or ""),
                tostring(result.priority_room or ""),
                tostring(result.nowhere == true),
                tostring(result.nohunt == true)
            ))
        end
        snd.debug.mobTag(string.format(
            "mapper.searchMobLocations mob='%s' zone='%s' matched='%s' results=%d %s",
            tostring(mobName or ""),
            tostring(zone or ""),
            tostring(matchedName or ""),
            #(results or {}),
            table.concat(parts, " | ")
        ))
    end

    if snd.targets and snd.targets.current then
        local current = snd.targets.current
        if current.mob == mobName or current.name == mobName or current.keyword == mobName then
            if #results > 0 then
                current.matchedMobName = matchedName
            else
                current.matchedMobName = nil
            end
        end
    end

    local reason = string.format(
        "searchMobLocations(mob='%s', zone='%s')",
        tostring(mobName or ""),
        tostring(zone or "")
    )
    snd.mapper.searchRoomsResults(results, { reason = reason })
    return results
end

function snd.mapper.searchRooms(query, mobName, options)
    local rows = snd.mapper.db.query(query) or {}
    return snd.mapper.searchRoomsRows(rows, mobName, options)
end

function snd.mapper.searchRoomsRows(rows, mobName, options)
    local results = {}
    local roomidList = {}
    local ignoredByLevel = {}
    local levelTaken = resolveSearchLevel(options)
    local activity = options and options.activity or ""
    local filterByLevel = (options and options.filterByLevel == true) or activity == "cp" or activity == "gq"

    for _, row in ipairs(rows) do
        local id = tonumber(row.uid) or -1
        local result = {
            rmid = id,
            name = row.name,
            arid = row.area,
        }
        local inLevelRange = areaMatchesLevelRange(result.arid, levelTaken)
        if filterByLevel and not inLevelRange then
            table.insert(ignoredByLevel, result)
        else
            table.insert(results, result)
        end
        if id > 0 and (not filterByLevel or inLevelRange) then
            table.insert(roomidList, tostring(id))
        end
    end

    if filterByLevel and #ignoredByLevel > 0 then
        snd.utils.debugNote(string.format(
            "Filtered %d room matches outside level range (level %d)",
            #ignoredByLevel,
            levelTaken
        ))
    end

    if mobName and #roomidList > 0 then
        if snd.db and snd.db.ensureMobTagsTable then
            snd.db.ensureMobTagsTable()
        end

        local countByRoom = {}
        local killsByRoom = {}
        local priorityByRoom = {}
        local priorityRoomByRoom = {}
        local nowhereByRoom = {}
        local nohuntByRoom = {}
        local sum = 0

        local function loadRoomStats(name)
            if not name or name == "" then
                return {}
            end

            local select = string.format(
                [[
                    SELECT m.roomid,
                           m.seen_count,
                           m.kill_count,
                           mt.priority_room,
                           mt.nowhere,
                           mt.nohunt,
                           CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END AS priority_match
                    FROM mobs m
                    LEFT JOIN mob_tags mt
                      ON mt.mob = m.mob
                     AND mt.zone = m.zone
                    WHERE m.mob = %s AND m.roomid in (%s);
                ]],
                snd.db.escape(name),
                table.concat(roomidList, ",")
            )

            return snd.db.query(select) or {}
        end

        local rowsSeen = loadRoomStats(mobName)
        if #rowsSeen == 0 and mobName:find("%-") then
            rowsSeen = loadRoomStats(mobName:gsub("%-", " "))
        end

        for _, row in ipairs(rowsSeen) do
            local roomId = tonumber(row.roomid)
            local seen = tonumber(row.seen_count) or 0
            local kills = tonumber(row.kill_count) or 0
            if roomId then
                countByRoom[roomId] = seen
                killsByRoom[roomId] = kills
                priorityByRoom[roomId] = tonumber(row.priority_match) == 1
                priorityRoomByRoom[roomId] = tonumber(row.priority_room)
                nowhereByRoom[roomId] = tonumber(row.nowhere) == 1
                nohuntByRoom[roomId] = tonumber(row.nohunt) == 1
                sum = sum + seen
            end
        end

        for _, result in ipairs(results) do
            local roomId = tonumber(result.rmid) or -1
            result.seen_count = countByRoom[roomId] or 0
            result.kill_count = killsByRoom[roomId] or 0
            result.priority_match = priorityByRoom[roomId] == true
            result.priority_room = priorityRoomByRoom[roomId]
            result.nowhere = nowhereByRoom[roomId] == true
            result.nohunt = nohuntByRoom[roomId] == true
            if sum > 0 then
                result.percentage = result.seen_count / sum
            else
                result.percentage = 0
            end
        end

        table.sort(results, function(a, b)
            local aPriority = a.priority_match == true
            local bPriority = b.priority_match == true
            if aPriority ~= bPriority then
                return aPriority
            end

            if (a.seen_count or 0) > (b.seen_count or 0) then
                return true
            elseif (a.seen_count or 0) < (b.seen_count or 0) then
                return false
            end

            if (a.kill_count or 0) > (b.kill_count or 0) then
                return true
            elseif (a.kill_count or 0) < (b.kill_count or 0) then
                return false
            end

            return (a.rmid or 0) < (b.rmid or 0)
        end)

        if snd.debug and snd.debug.mobTag then
            local parts = {}
            for i, result in ipairs(results or {}) do
                if i > 8 then
                    table.insert(parts, "...")
                    break
                end
                table.insert(parts, string.format(
                    "#%d rmid=%s area=%s seen=%s kills=%s priority_room=%s priority_match=%s nowhere=%s nohunt=%s",
                    i,
                    tostring(result.rmid or ""),
                    tostring(result.arid or ""),
                    tostring(result.seen_count or ""),
                    tostring(result.kill_count or ""),
                    tostring(result.priority_room or ""),
                    tostring(result.priority_match == true),
                    tostring(result.nowhere == true),
                    tostring(result.nohunt == true)
                ))
            end
            snd.debug.mobTag(string.format(
                "mapper.searchRoomsRows mob='%s' activity='%s' candidates=%d %s",
                tostring(mobName or ""),
                tostring(activity or ""),
                #(results or {}),
                table.concat(parts, " | ")
            ))
        end
    end

    if not (options and options.silent) then
        local reason = options and options.reason or nil
        if not reason or reason == "" then
            reason = "searchRoomsRows"
        end
        snd.mapper.searchRoomsResults(results, { reason = reason })
    end
    return results
end

function snd.mapper.searchRoomsResults(results, context)
    snd.nav.gotoArea = -1
    snd.nav.gotoIndex = 1
    snd.nav.nextRoom = -1
    snd.nav.gotoList = {}
    if snd.commands and snd.commands.buildQuickWhereTargetKeyFromCurrent and snd.targets and snd.targets.current then
        snd.nav.gotoListTargetKey = snd.commands.buildQuickWhereTargetKeyFromCurrent(snd.targets.current)
    else
        snd.nav.gotoListTargetKey = nil
    end
    local reason = context and context.reason or nil
    if snd.utils and snd.utils.debugNote then
        if reason and reason ~= "" then
            snd.utils.debugNote("QW list fired: " .. tostring(reason))
        else
            snd.utils.debugNote("QW list fired: reason unknown")
        end
    end

    local tableWidth = snd.config.tableWidth or 80
    local mapperAreaIndex = 0
    local lineNum = 0
    local noteWidth = tableWidth - 62
    local lastArea = ""
    local hasChance = #results > 0 and results[1].percentage ~= nil
    local ui = (snd.config and snd.config.mapperUI) or {}
    local linksEnabled = ui.links ~= false
    local chipsEnabled = ui.chips ~= false

    local isQuickWhereList = false
    local qwTargetLabel = ""
    if snd.commands and type(snd.commands.quickWhereListDisplay) == "function" then
        isQuickWhereList, qwTargetLabel = snd.commands.quickWhereListDisplay(context)
    elseif type(context) == "table" and context.quickWhere == true then
        isQuickWhereList = true
        qwTargetLabel = snd.utils and snd.utils.trim and snd.utils.trim(context.quickWhereLabel or "")
            or tostring(context.quickWhereLabel or "")
    end
    if isQuickWhereList and qwTargetLabel == "" and snd.targets and snd.targets.current and snd.targets.current.name then
        qwTargetLabel = snd.targets.current.name
    end

    cecho(string.format("\n<gray>XCP  %-38s  %-7s  %-6s", "Location", "(uid)", ""))
    if hasChance then
        noteWidth = noteWidth - 11
        cecho(string.format("  %-9s", "(chance)"))
    end
    cecho("  Notes<reset>\n")
    if chipsEnabled then
        if isQuickWhereList then
            if qwTargetLabel ~= "" then
                cecho(string.format("<dim_gray>[QW]<reset> <white>%s<reset>\n", qwTargetLabel))
            else
                cecho("<dim_gray>[QW]<reset>\n")
            end
        end
    end
    cecho("<gray>" .. string.rep("-", tableWidth) .. "<reset>\n")

    for _, entry in ipairs(results) do
        lineNum = lineNum + 1
        local rowColor = (lineNum % 2) == 0 and "light_grey" or "dim_gray"
        local areaKey = entry.arid or ""

        if lastArea ~= areaKey then
            local padding = string.rep(" ", math.max(0, tableWidth - 5 - #areaKey))
            if mapperAreaIndex == 0 then
                local areaLine = string.format("%3d  %s%s", mapperAreaIndex, areaKey, padding)
                echoLink(areaLine,
                    [[snd.commands.goToIndex(]] .. mapperAreaIndex .. [[)]],
                    "go to area " .. areaKey,
                    true
                )
                echo("\n")
                snd.nav.gotoList[mapperAreaIndex] = {type = "area", id = areaKey}
                snd.nav.gotoArea = areaKey
                mapperAreaIndex = mapperAreaIndex + 1
            else
                cecho(string.format("     %s%s\n", areaKey, padding))
            end
            lineNum = lineNum + 1
            lastArea = areaKey
        end

        local name = ellipsify(snd.utils.stripColors(entry.name or ""), 38)
        local roomId = entry.rmid or -1
        local displayId = roomId > 0 and tostring(roomId) or "?"
        local text = string.format("%3d  %-38s  %-7s ", mapperAreaIndex, name, string.format("(%s)", displayId))
        local roomColor = "white"

        cecho("<" .. roomColor .. ">")
        if roomId > 0 then
            if linksEnabled then
                echoLink(text,
                    [[snd.commands.goToIndex(]] .. mapperAreaIndex .. [[)]],
                    "go to item " .. mapperAreaIndex,
                    true
                )
            else
                cecho(text)
            end
            snd.nav.gotoList[mapperAreaIndex] = {type = "room", id = roomId}
        else
            cecho(text)
        end
        cecho("<reset>")
        cecho("       ")

        if hasChance and entry.percentage ~= nil then
            local pctString = string.format("%6.2f%%", (entry.percentage or 0) * 100)
            cecho("  (")
            cecho("<" .. mobRoomPercentageColor(entry.percentage or 0) .. ">" .. pctString .. "<reset>")
            cecho(")")
        end

        if entry.notes and entry.notes ~= "" then
            local textNote = ellipsify(snd.utils.stripColors(entry.notes), noteWidth)
            textNote = string.format("  %-" .. noteWidth .. "s", textNote)
            cecho(textNote)
        else
            cecho(string.rep(" ", noteWidth + 2))
        end

        echo("\n")
        mapperAreaIndex = mapperAreaIndex + 1
    end

    if snd.debug and snd.debug.mobTag then
        local parts = {}
        local firstRoomIndex = nil
        local firstRoomId = nil
        for i = 0, math.max(0, mapperAreaIndex - 1) do
            local entry = snd.nav.gotoList[i]
            if entry then
                if #parts < 9 then
                    table.insert(parts, string.format(
                        "%d:%s=%s",
                        i,
                        tostring(entry.type or ""),
                        tostring(entry.id or "")
                    ))
                elseif #parts == 9 then
                    table.insert(parts, "...")
                end
                if not firstRoomIndex and entry.type == "room" then
                    firstRoomIndex = i
                    firstRoomId = entry.id
                end
            end
        end
        snd.debug.mobTag(string.format(
            "mapper.searchRoomsResults reason='%s' goto_entries=%d first_room_index=%s first_room=%s %s",
            tostring(reason or ""),
            tonumber(mapperAreaIndex) or 0,
            tostring(firstRoomIndex or ""),
            tostring(firstRoomId or ""),
            table.concat(parts, " | ")
        ))
    end

    if mapperAreaIndex == 0 then
        snd.utils.infoNote("No matching rooms found.")
        if snd.debug and snd.debug.log then
            local ctx = snd.debug.lastSearch or {}
            snd.debug.log(string.format(
                "No matching rooms: room='%s' cleaned='%s' arid='%s' mob='%s' initial=%s fallback=%s",
                tostring(ctx.room or ""),
                tostring(ctx.cleanedRoom or ""),
                tostring(ctx.arid or ""),
                tostring(ctx.mobName or ""),
                tostring(ctx.initialCount or 0),
                tostring(ctx.fallbackCount or 0)
            ))
        end
        if snd.targets.current then
            snd.targets.current.roomId = nil
        end
    end

    cecho("<gray>" .. string.rep("-", tableWidth) .. "<reset>\n")
    cecho("<gray>Type 'go <index>' or click link to go to that room.<reset>\n")

    for i = 1, #results do
        local entry = results[i]
        if entry and entry.rmid and tonumber(entry.rmid) and tonumber(entry.rmid) > 0 then
            snd.nav.nextRoom = tonumber(entry.rmid)
            if snd.targets.current then
                snd.targets.current.roomId = tonumber(entry.rmid)
                snd.targets.current.roomName = entry.name
            end
            break
        end
    end
end

function snd.mapper.onConfirmedRoomVisit(roomId)
    return
end

-------------------------------------------------------------------------------
-- Portal Management
-------------------------------------------------------------------------------

--- Get all portals from database
-- @param filter Optional area filter
-- @return Table of portal records
function snd.mapper.getPortals(filter)
    filter = filter or "%"
    
    local sql = string.format([[
        SELECT rooms.area, rooms.name, exits.touid, exits.fromuid, exits.dir, exits.level 
        FROM exits 
        LEFT OUTER JOIN rooms ON rooms.uid = exits.touid 
        WHERE exits.fromuid IN ('*', '**') 
        AND rooms.area LIKE %s 
        ORDER BY rooms.area, exits.touid
    ]], snd.mapper.db.escape(filter))
    
    return snd.mapper.db.query(sql) or {}
end

--- Get portals to a specific room
-- @param roomId Destination room
-- @return Table of portal records
function snd.mapper.getPortalsToRoom(roomId)
    local sql = string.format([[
        SELECT dir, fromuid, touid, level 
        FROM exits 
        WHERE touid = %s AND fromuid IN ('*', '**')
    ]], snd.mapper.db.escape(tostring(roomId)))
    
    return snd.mapper.db.query(sql) or {}
end

--- Set bounce portal (for norecall rooms)
-- @param portalDir Portal command
-- @param portalDestUid Destination room uid
-- @param level Optional portal level
function snd.mapper.setBouncePortal(portalDir, portalDestUid, level)
    snd.mapper.config.bouncePortal = {
        dir = portalDir,
        uid = portalDestUid,
        level = tonumber(level) or 0,
        travelType = "portal"
    }
    snd.utils.infoNote("Bounce portal set: " .. portalDir)
end

--- Set bounce recall (for noportal rooms)
-- @param recallDir Recall command
-- @param recallDestUid Destination room uid
-- @param level Optional portal level
function snd.mapper.setBounceRecall(recallDir, recallDestUid, level)
    snd.mapper.config.bounceRecall = {
        dir = recallDir,
        uid = recallDestUid,
        level = tonumber(level) or 0,
        travelType = "recall"
    }
    snd.utils.infoNote("Bounce recall set: " .. recallDir)
end

-- Prefer the portal subsystem's persisted ID-based setting.  The config copy
-- remains as a compatibility fallback for standalone S&D use and tests.
function snd.mapper.getConfiguredBounce(travelType)
    if mm and type(mm.get_configured_bounce_step) == "function" then
        local resolved = mm.get_configured_bounce_step(travelType)
        if resolved then
            if travelType == "recall" then
                snd.mapper.config.bounceRecall = resolved
            else
                snd.mapper.config.bouncePortal = resolved
            end
            return resolved
        end

        -- When the portal subsystem owns a settings table, a missing result is
        -- authoritative (cleared, deleted, or invalid), not a stale config hit.
        if mm.portals and mm.portals.settings then
            if travelType == "recall" then
                snd.mapper.config.bounceRecall = nil
            else
                snd.mapper.config.bouncePortal = nil
            end
            return nil
        end
    end

    if travelType == "recall" then
        return snd.mapper.config.bounceRecall
    end
    return snd.mapper.config.bouncePortal
end

-------------------------------------------------------------------------------
-- Pathfinding
-------------------------------------------------------------------------------

-- Keep only the most recent multi-destination result. This is intentionally a
-- route-result cache, not a second copy of the mapper graph in Lua. The cache
-- key includes the source, destination set, and the generated policy clauses;
-- committed mapper changes invalidate it through notifyMapperDbUpdated().
snd.mapper.distanceCacheRevision = tonumber(snd.mapper.distanceCacheRevision) or 0
snd.mapper.distanceCache = snd.mapper.distanceCache or nil

function snd.mapper.clearDistanceCache(reason)
    snd.mapper.distanceCache = nil
    snd.mapper.distanceCacheRevision = (tonumber(snd.mapper.distanceCacheRevision) or 0) + 1
    if type(snd.markTargetProximityDirty) == "function" then
        snd.markTargetProximityDirty(reason or "mapper_distance_cache_cleared")
    end
    if reason and snd.utils and snd.utils.debugNote then
        snd.utils.debugNote("Cleared mapper distance cache: " .. tostring(reason))
    end
end

local function normalizeDistanceDestinations(destinations)
    local normalized = {}
    local seen = {}
    for _, value in ipairs(type(destinations) == "table" and destinations or {}) do
        local numeric = tonumber(value)
        if numeric and numeric > 0 then
            local roomId = tostring(math.floor(numeric))
            if not seen[roomId] then
                seen[roomId] = true
                table.insert(normalized, roomId)
            end
        end
    end
    table.sort(normalized, function(a, b)
        return tonumber(a) < tonumber(b)
    end)
    return normalized
end

--- Calculate shortest mapper distances from one source to many destinations.
-- One forward BFS answers the whole set and stops as soon as every reachable
-- requested room has been found (or maxSearchDepth is reached). It deliberately
-- returns distances only: route construction and movement remain mapper-owned.
-- @param src Source room uid
-- @param destinations Array of destination room uids
-- @param opts Optional policy overrides matching findPath semantics
-- @return table<string,number> distances, table metadata
function snd.mapper.findDistances(src, destinations, opts)
    opts = type(opts) == "table" and opts or {}
    local sourceNumber = tonumber(src)
    local source = sourceNumber and sourceNumber > 0 and tostring(math.floor(sourceNumber)) or ""
    local requested = normalizeDistanceDestinations(destinations)
    local metadata = {
        source = source,
        requested = #requested,
        found = 0,
        depth = 0,
        visited = 0,
        queries = 0,
        cached = false,
    }

    if source == "" then
        metadata.error = "invalid_source"
        return {}, metadata
    end
    if #requested == 0 then
        return {}, metadata
    end
    if not snd.mapper.db.open() then
        metadata.error = "database_unavailable"
        return {}, metadata
    end

    local myLevel = tonumber(snd.char and snd.char.level) or 201
    local myTier = tonumber(snd.char and snd.char.tier) or 0
    local effectiveLevel = myLevel + (myTier * 10)
    local ignoreLockedExits = opts.ignoreLockedExits == true
    local ignoreAreaGuard = opts.ignoreAreaGuard == true
    local ignoreTravelRestrictions = opts.ignoreTravelRestrictions == true
    local allowChaosPortals = opts.allowChaosPortals == true
    local noPortals = opts.noPortals == true
        or opts.usePortals == false
        or snd.mapper.config.usePortals == false
    local noRecalls = opts.noRecalls == true
        or opts.useRecall == false
        or snd.mapper.config.useRecall == false
    local sourceInfo = snd.mapper.getRoomInfo(source)
    if not ignoreTravelRestrictions then
        noPortals = noPortals or (sourceInfo and tonumber(sourceInfo.noportal) == 1 or false)
        noRecalls = noRecalls or (sourceInfo and tonumber(sourceInfo.norecall) == 1 or false)
    end

    local gqJoined = snd.gquest and tostring(snd.gquest.joined or "-1") or "-1"
    local gqActive = snd.gquest and (snd.gquest.active == true or gqJoined ~= "-1") or false
    local levelWhere = ignoreLockedExits and "1=1" or string.format(
        "((fromuid NOT IN ('*','**') AND level <= %d) OR (fromuid IN ('*','**') AND level <= %d))",
        myLevel,
        effectiveLevel
    )
    local randomLevelWhere = ignoreLockedExits and "1=1" or string.format("level <= %d", myLevel)
    local portalGuardWhere = snd.mapper.portalGuardSql("dir", "level", effectiveLevel, ignoreLockedExits)
    local chaosWhere = (gqActive and not allowChaosPortals)
        and "(fromuid <> '*' OR ifnull(chaos, 'no') <> 'yes')"
        or "1=1"
    local areaFromWhere = snd.mapper.areaGuardRoomSql(
        "exits.fromuid", source, ignoreLockedExits, ignoreAreaGuard
    )
    local areaToWhere = snd.mapper.areaGuardRoomSql(
        "exits.touid", source, ignoreLockedExits, ignoreAreaGuard
    )
    local randomAreaFromWhere = snd.mapper.areaGuardRoomSql(
        "random_cexits.fromuid", source, ignoreLockedExits, ignoreAreaGuard
    )
    local randomAreaToWhere = snd.mapper.areaGuardRoomSql(
        "random_cexits.touid", source, ignoreLockedExits, ignoreAreaGuard
    )

    local maxDepth = tonumber(snd.mapper.config.maxSearchDepth) or 100
    local requestedDepth = tonumber(opts.searchDepthLimit)
    if requestedDepth then
        maxDepth = math.max(0, math.min(maxDepth, math.floor(requestedDepth)))
    end

    local cacheKey = table.concat({
        tostring(snd.mapper.distanceCacheRevision or 0),
        source,
        table.concat(requested, ","),
        tostring(maxDepth),
        tostring(noPortals),
        tostring(noRecalls),
        tostring(ignoreLockedExits),
        tostring(ignoreAreaGuard),
        tostring(ignoreTravelRestrictions),
        tostring(allowChaosPortals),
        tostring(myLevel),
        tostring(myTier),
        tostring(gqActive),
        levelWhere,
        portalGuardWhere,
        chaosWhere,
        areaFromWhere,
        areaToWhere,
        randomAreaFromWhere,
        randomAreaToWhere,
    }, "|")
    local cached = snd.mapper.distanceCache
    if cached and cached.key == cacheKey then
        local cachedMetadata = {}
        for key, value in pairs(cached.metadata or {}) do cachedMetadata[key] = value end
        cachedMetadata.cached = true
        return cached.distances, cachedMetadata
    end

    local startedAt = os.clock()
    local distances = {}
    local remaining = {}
    local remainingCount = 0
    for _, roomId in ipairs(requested) do
        if roomId == source then
            distances[roomId] = 0
        else
            remaining[roomId] = true
            remainingCount = remainingCount + 1
        end
    end

    local visited = {[source] = true}
    local frontier = {source}
    if not noPortals then
        visited["*"] = true
        table.insert(frontier, "*")
    end
    if not noRecalls then
        visited["**"] = true
        table.insert(frontier, "**")
    end

    local randomBySource = {}
    local randomCexits = snd.mapper.db.query(string.format([[
        SELECT fromuid, touid, dir, level, 1 AS random_cexit
        FROM random_cexits
        WHERE %s AND %s AND %s
    ]], randomLevelWhere, randomAreaFromWhere, randomAreaToWhere)) or {}
    metadata.queries = metadata.queries + 1
    for _, row in ipairs(randomCexits) do
        local fromId = tostring(row.fromuid or "")
        randomBySource[fromId] = randomBySource[fromId] or {}
        table.insert(randomBySource[fromId], row)
    end

    local depth = 0
    while remainingCount > 0 and #frontier > 0 and depth < maxDepth do
        local escapedFrontier = {}
        for _, roomId in ipairs(frontier) do
            table.insert(escapedFrontier, snd.mapper.db.escape(roomId))
        end
        local results = snd.mapper.db.query(string.format([[
            SELECT fromuid, touid, dir, chaos
            FROM exits
            WHERE fromuid IN (%s)
              AND %s
              AND %s
              AND %s
              AND %s
              AND %s
        ]],
            table.concat(escapedFrontier, ","),
            levelWhere,
            portalGuardWhere,
            chaosWhere,
            areaFromWhere,
            areaToWhere
        )) or {}
        metadata.queries = metadata.queries + 1
        for _, fromId in ipairs(frontier) do
            for _, row in ipairs(randomBySource[fromId] or {}) do
                table.insert(results, row)
            end
        end

        depth = depth + 1
        local nextFrontier = {}
        for _, row in ipairs(results) do
            local roomId = tostring(row.touid or "")
            if roomId ~= "" and roomId ~= "-1" and not visited[roomId] then
                visited[roomId] = true
                table.insert(nextFrontier, roomId)
                if remaining[roomId] then
                    distances[roomId] = depth
                    remaining[roomId] = nil
                    remainingCount = remainingCount - 1
                end
            end
        end
        frontier = nextFrontier
    end

    local visitedCount = 0
    for roomId in pairs(visited) do
        if roomId ~= "*" and roomId ~= "**" then visitedCount = visitedCount + 1 end
    end
    local foundCount = 0
    for _ in pairs(distances) do foundCount = foundCount + 1 end
    metadata.found = foundCount
    metadata.depth = depth
    metadata.visited = visitedCount
    metadata.elapsedMs = (os.clock() - startedAt) * 1000
    metadata.unreachable = {}
    for _, roomId in ipairs(requested) do
        if distances[roomId] == nil then table.insert(metadata.unreachable, roomId) end
    end

    snd.mapper.distanceCache = {
        key = cacheKey,
        distances = distances,
        metadata = metadata,
    }
    return distances, metadata
end

--- Find path between two rooms with portal support
-- @param src Source room uid
-- @param dst Destination room uid
-- @param noPortals If true, don't use portals
-- @param noRecalls If true, don't use recall
-- @param ignoreLockedExits If true, ignore exit-level locks
-- @param ignoreAreaGuard If true, ignore only the area guard
-- @param ignoreTravelRestrictions If true, ignore source noportal/norecall flags
-- @param searchDepthLimit Optional per-call BFS depth cap
-- @param originMode Optional origin filter: "walk", "portal", "recall", or "jump"
-- @param allowChaosPortals If true, include chaos portals during a diagnostic-only search
-- @return Path table, depth, or nil if no path
function snd.mapper.findPath(
    src,
    dst,
    noPortals,
    noRecalls,
    ignoreLockedExits,
    ignoreAreaGuard,
    ignoreTravelRestrictions,
    searchDepthLimit,
    originMode,
    allowChaosPortals
)
    if not snd.mapper.db.open() then
        return nil
    end
    
    src = tostring(src)
    dst = tostring(dst)
    snd.utils.debugNote(string.format(
        "findPath start src=%s dst=%s noPortals=%s noRecalls=%s ignoreLocked=%s ignoreAreaGuard=%s depthLimit=%s originMode=%s allowChaos=%s",
        src,
        dst,
        tostring(noPortals == true),
        tostring(noRecalls == true),
        tostring(ignoreLockedExits == true),
        tostring(ignoreAreaGuard == true),
        tostring(searchDepthLimit or "default"),
        tostring(originMode or "any"),
        tostring(allowChaosPortals == true)
    ))
    
    if src == dst and (originMode == nil or originMode == "walk") then
        snd.utils.debugNote("findPath early return: source equals destination.")
        return {}, 0
    end
    
    -- Get player level for level-locked exits
    local myLevel = snd.char.level or 201
    local myTier = snd.char.tier or 0
    local gqJoined = snd.gquest and tostring(snd.gquest.joined or "-1") or "-1"
    local gqActive = snd.gquest and (snd.gquest.active == true or gqJoined ~= "-1")
    local levelWhere = ignoreLockedExits and "1=1" or string.format(
        "((fromuid NOT IN ('*','**') AND level <= %d) OR (fromuid IN ('*','**') AND level <= %d))",
        myLevel,
        myLevel + (myTier * 10)
    )
    local effectiveLevel = myLevel + (myTier * 10)
    local portalGuardWhere = snd.mapper.portalGuardSql("dir", "level", effectiveLevel, ignoreLockedExits)
    -- Chaos portals are excluded before BFS while a GQ is active. The only
    -- exception is an explicit diagnostic search whose path is never executed.
    -- Source-room travel restrictions are deliberately independent of this.
    local chaosWhere = (gqActive and allowChaosPortals ~= true)
        and "(fromuid <> '*' OR ifnull(chaos, 'no') <> 'yes')"
        or "1=1"
    local areaFromWhere, blockedAreaCount = snd.mapper.areaGuardRoomSql(
        "exits.fromuid",
        src,
        ignoreLockedExits,
        ignoreAreaGuard
    )
    local areaToWhere = snd.mapper.areaGuardRoomSql(
        "exits.touid",
        src,
        ignoreLockedExits,
        ignoreAreaGuard
    )
    local randomAreaFromWhere = snd.mapper.areaGuardRoomSql(
        "random_cexits.fromuid",
        src,
        ignoreLockedExits,
        ignoreAreaGuard
    )
    local randomAreaToWhere = snd.mapper.areaGuardRoomSql(
        "random_cexits.touid",
        src,
        ignoreLockedExits,
        ignoreAreaGuard
    )
    local randomLevelWhere = ignoreLockedExits and "1=1" or string.format("level <= %d", myLevel)
    local randomCexits = snd.mapper.db.query(string.format([[
        SELECT fromuid, touid, dir, level, 1 AS random_cexit
        FROM random_cexits
        WHERE %s AND %s AND %s
    ]], randomLevelWhere, randomAreaFromWhere, randomAreaToWhere)) or {}
    if blockedAreaCount > 0 then
        snd.utils.debugNote(string.format(
            "Area guard route filter active: level=%d allowance=%d blockedAreas=%d source=%s",
            myLevel,
            snd.mapper.areaGuardAllowance(),
            blockedAreaCount,
            tostring(src)
        ))
    end
    
    -- Check for direct one-room path first
    local directPath = snd.mapper.checkDirectPath(
        src, dst, myLevel, ignoreLockedExits, ignoreAreaGuard, randomCexits
    )
    if directPath and (originMode == nil or originMode == "walk") then
        snd.utils.debugNote("findPath direct one-room path found.")
        return directPath, 1
    end
    
    -- BFS pathfinding (backwards from destination)
    local depth = 0
    local maxDepth = tonumber(snd.mapper.config.maxSearchDepth) or 100
    local requestedDepth = tonumber(searchDepthLimit)
    if requestedDepth then
        maxDepth = math.max(0, math.min(maxDepth, math.floor(requestedDepth)))
    end
    local roomSets = {}
    local roomsList = {snd.mapper.db.escape(dst)}
    local frontierSet = {[dst] = true}
    local visited = ""
    local visitedSet = {}
    local found = false
    local foundDepth = 0
    local foundFrom = nil
    local srcRoomInfo = snd.mapper.getRoomInfo(src)
    
    -- Build initial visited set.
    local visitedList = {}
    if noPortals then
        table.insert(visitedList, snd.mapper.db.escape("*"))
        visitedSet["*"] = true
    end
    if noRecalls then
        table.insert(visitedList, snd.mapper.db.escape("**"))
        visitedSet["**"] = true
    end
    for _, room in ipairs(roomsList) do
        table.insert(visitedList, room)
    end
    visitedSet[dst] = true
    visited = table.concat(visitedList, ",")
    
    while not found and depth < maxDepth do
        depth = depth + 1
        
        if depth > 1 then
            local prevSet = roomSets[depth - 1] or {}
            roomsList = {}
            frontierSet = {}
            for _, v in pairs(prevSet) do
                table.insert(roomsList, snd.mapper.db.escape(v.fromuid))
                frontierSet[tostring(v.fromuid)] = true
            end
        end
        
        if #roomsList == 0 then
            break
        end
        
        -- Update visited.
        local newVisited = table.concat(roomsList, ",")
        if newVisited ~= "" then
            if visited == "" then
                visited = newVisited
            else
                visited = visited .. "," .. newVisited
            end
        end
        for roomId in pairs(frontierSet) do visitedSet[roomId] = true end
        
        -- Query exits leading to rooms in our current set
        local sql = string.format([[
            SELECT fromuid, touid, dir, chaos FROM exits
            WHERE touid IN (%s) 
            AND fromuid NOT IN (%s) 
            AND %s
            AND %s
            AND %s
            AND %s
            AND %s
            ORDER BY %s
        ]],
            table.concat(roomsList, ","),
            visited,
            levelWhere,
            portalGuardWhere,
            chaosWhere,
            areaFromWhere,
            areaToWhere,
            snd.mapper.exitPreferenceOrderSql("dir")
        )
        
        local results = snd.mapper.db.query(sql) or {}
        for _, row in ipairs(randomCexits) do
            if frontierSet[tostring(row.touid)] and not visitedSet[tostring(row.fromuid)] then
                table.insert(results, row)
            end
        end
        roomSets[depth] = {}
        snd.utils.debugNote(string.format(
            "findPath depth=%d frontier=%d results=%d",
            depth,
            #roomsList,
            #results
        ))
        
        local depthCandidates = {
            src = false,
            portal = nil,
            recall = nil,
        }

        for idx, row in ipairs(results) do
            -- Prefer custom cexit commands over bare cardinal exits from the same room.
            local existingStep = roomSets[depth][row.fromuid]
            if snd.mapper.shouldPreferExitDir(row.dir, existingStep and existingStep.dir) then
                roomSets[depth][row.fromuid] = {
                    fromuid = row.fromuid,
                    touid = row.touid,
                    dir = row.dir,
                    chaos = row.chaos,
                    randomCexit = tonumber(row.random_cexit) == 1,
                }
            end

            -- Track whether this depth can connect from source/portal/recall
            if row.fromuid == src then
                depthCandidates.src = true
            elseif row.fromuid == "*" then
                local dirLen = #(tostring(row.dir or ""))
                if (not depthCandidates.portal)
                    or dirLen < depthCandidates.portal.dirLen
                    or (dirLen == depthCandidates.portal.dirLen and idx < depthCandidates.portal.order)
                then
                    depthCandidates.portal = {dirLen = dirLen, order = idx}
                end
            elseif row.fromuid == "**" then
                local dirLen = #(tostring(row.dir or ""))
                if (not depthCandidates.recall)
                    or dirLen < depthCandidates.recall.dirLen
                    or (dirLen == depthCandidates.recall.dirLen and idx < depthCandidates.recall.order)
                then
                    depthCandidates.recall = {dirLen = dirLen, order = idx}
                end
            end
        end

        -- One backwards BFS sees walking, portal, and recall origins together.
        -- Do not launch a second walk-only search. At the same depth the real
        -- walking source wins; otherwise the first origin reached is already
        -- the strictly shorter route. Callers that require an immediate jump
        -- can filter the accepted origin without calculating a walking rival.
        if originMode == "walk" then
            foundFrom = depthCandidates.src and src or nil
        elseif originMode == "portal" then
            foundFrom = depthCandidates.portal and "*" or nil
        elseif originMode == "recall" then
            foundFrom = depthCandidates.recall and "**" or nil
        elseif originMode == "jump" then
            if depthCandidates.portal then
                foundFrom = "*"
            elseif depthCandidates.recall then
                foundFrom = "**"
            end
        elseif depthCandidates.src then
            foundFrom = src
        elseif depthCandidates.portal then
            foundFrom = "*"
        elseif depthCandidates.recall then
            foundFrom = "**"
        end

        if foundFrom then
            found = true
            foundDepth = depth
            snd.utils.debugNote(string.format(
                "findPath selected shortest origin=%s depth=%d (portal=%s recall=%s source=%s)",
                tostring(foundFrom),
                depth,
                tostring(depthCandidates.portal ~= nil),
                tostring(depthCandidates.recall ~= nil),
                tostring(depthCandidates.src == true)
            ))
        end
        
        if #results == 0 then
            break  -- No more paths to explore
        end
    end
    
    if not found then
        snd.utils.debugNote("findPath failed: no route found within depth " .. tostring(maxDepth))
        return nil
    end
    
    -- Reconstruct path
    local path = {}
    local currentRoom = roomSets[foundDepth][foundFrom]
    
    -- Handle portal/recall from restricted rooms
    if foundFrom == "*" or foundFrom == "**" then
        local srcRoom = srcRoomInfo
        if srcRoom then
            local srcNoPortal = tonumber(srcRoom.noportal) == 1
            local srcNoRecall = tonumber(srcRoom.norecall) == 1
            
            if not ignoreTravelRestrictions
                and ((foundFrom == "*" and srcNoPortal) or (foundFrom == "**" and srcNoRecall))
            then
                -- Repair the selected jump without replanning its suffix.  A
                -- bouncerecall is only a command prepended to a blocked '*'
                -- route; a bounceportal is only prepended to a blocked '**'
                -- route.
                local bounceRecall = (foundFrom == "*" and not srcNoRecall
                    and snd.mapper.getConfiguredBounce("recall")) or nil
                local bouncePortal = (foundFrom == "**" and not srcNoPortal
                    and snd.mapper.getConfiguredBounce("portal")) or nil
                if bounceRecall and not snd.mapper.portalStepAllowed(bounceRecall, ignoreLockedExits) then
                    bounceRecall = nil
                end
                if bouncePortal and not snd.mapper.portalStepAllowed(bouncePortal, ignoreLockedExits) then
                    bouncePortal = nil
                end

                if bounceRecall then
                    local bounceStep = {}
                    for key, value in pairs(bounceRecall) do bounceStep[key] = value end
                    bounceStep.travelType = "recall"
                    bounceStep.trustedLanding = bounceStep.uid ~= nil
                    table.insert(path, bounceStep)
                    if tostring(dst) == tostring(bounceRecall.uid) then
                        return path, foundDepth
                    end
                elseif bouncePortal then
                    local bounceStep = {}
                    for key, value in pairs(bouncePortal) do bounceStep[key] = value end
                    bounceStep.travelType = "portal"
                    bounceStep.trustedLanding = bounceStep.uid ~= nil
                    table.insert(path, bounceStep)
                    if tostring(dst) == tostring(bouncePortal.uid) then
                        return path, foundDepth
                    end
                elseif srcNoPortal and srcNoRecall then
                    -- Both-flags recovery is owned by the explicit bounded
                    -- nearby -> area-start ladder. Never start an implicit,
                    -- unbounded nearest-room search during reconstruction.
                    snd.utils.debugNote("findPath restricted source has both flags; deferring to bounded fallback policy.")
                    return nil
                else
                    -- A one-flag room must use the opposite jump where it is,
                    -- never walk outward implicitly. The caller may retry with
                    -- that legal origin forced; nearby probing is reserved for
                    -- rooms carrying both restrictions.
                    snd.utils.debugNote("findPath restricted source has no configured bounce; refusing implicit nearby search.")
                    return nil
                end
            end
        end
    end
    
    -- Build path from found room to destination
    local firstStep = {
        dir = currentRoom.dir,
        uid = currentRoom.touid,
        chaos = currentRoom.chaos,
        randomCexit = currentRoom.randomCexit == true,
    }
    if foundFrom == "*" then
        firstStep.travelType = "portal"
    elseif foundFrom == "**" then
        firstStep.travelType = "recall"
        -- Preserve the recorded landing metadata used by configured routes.
        -- Execution still requires live GMCP confirmation before the suffix.
        firstStep.trustedLanding = true
    end
    table.insert(path, firstStep)
    
    local nextRoom = currentRoom.touid
    while foundDepth > 1 do
        foundDepth = foundDepth - 1
        currentRoom = roomSets[foundDepth][nextRoom]
        if currentRoom then
            nextRoom = currentRoom.touid
            table.insert(path, {
                dir = currentRoom.dir,
                uid = currentRoom.touid,
                randomCexit = currentRoom.randomCexit == true,
            })
        end
    end
    snd.utils.debugNote(string.format("findPath success steps=%d searchDepth=%d", #path, depth))
    
    return path, depth
end

function snd.mapper.isGquestActive()
    local joined = snd.gquest and tostring(snd.gquest.joined or "-1") or "-1"
    return snd.gquest ~= nil and (snd.gquest.active == true or joined ~= "-1")
end

--- Find a route that differs from normal GQ routing only by allowing chaos
-- portals. This is explanation-only: callers must never execute the result.
function snd.mapper.findGqChaosDiagnosticPath(
    src,
    dst,
    noPortals,
    noRecalls,
    ignoreLockedExits,
    ignoreAreaGuard,
    searchDepthLimit,
    originMode
)
    if not snd.mapper.isGquestActive()
        or noPortals == true
        or (snd.mapper.config and snd.mapper.config.usePortals == false)
    then
        return nil
    end

    local path, depth = snd.mapper.findPath(
        src,
        dst,
        noPortals,
        noRecalls,
        ignoreLockedExits,
        ignoreAreaGuard,
        nil,
        searchDepthLimit,
        originMode,
        true
    )
    if not path then return nil end

    for _, step in ipairs(path) do
        if step.travelType == "portal" and tostring(step.chaos or "no") == "yes" then
            return path, depth
        end
    end
    return nil
end

function snd.mapper.queueRestrictionMark(travelType, roomId)
    local roomKey = tostring(roomId or "")
    if roomKey == "" or roomKey == "-1" then
        return
    end
    if travelType ~= "portal" and travelType ~= "recall" then
        return
    end

    snd.mapper.pendingRestrictionMarks[travelType] = {
        roomId = roomKey,
        at = os.time(),
    }
end

function snd.mapper.consumeRestrictionMark(travelType)
    local pending = snd.mapper.pendingRestrictionMarks[travelType]
    snd.mapper.pendingRestrictionMarks[travelType] = nil
    return pending
end

function snd.mapper.markRoomRestriction(roomId, flag)
    if not snd.mapper.db.open() then
        return false
    end
    local roomKey = tostring(roomId or "")
    local safeFlag = (flag == "norecall") and "norecall" or "noportal"
    local rows = snd.mapper.db.query(string.format(
        "SELECT noportal, norecall FROM rooms WHERE uid = %s LIMIT 1",
        snd.mapper.db.escape(roomKey)
    ))
    local row = rows and rows[1]
    if not row then
        return false
    end

    if tonumber(row[safeFlag]) == 1 then
        return true, false
    end

    local updated, err = snd.mapper.db.conn:execute(string.format(
        "UPDATE rooms SET %s = 1 WHERE uid = %s",
        safeFlag,
        snd.mapper.db.escape(roomKey)
    ))
    if not updated then
        snd.utils.debugNote("Failed to update room restriction flag: " .. tostring(err))
        return false, false
    end

    if snd.mapper.clearDistanceCache then
        snd.mapper.clearDistanceCache("room_restriction_updated")
    end

    snd.utils.infoNote(string.format("Marked room %s as %s.", roomKey, safeFlag))
    return true, true
end

function snd.mapper.hasActiveNavigation()
    return (snd.nav and snd.nav.goingToRoom ~= nil)
        or snd.mapper.goingToRoom ~= nil
        or snd.mapper.pathExecutionActive == true
end

-- A definitive server-side route failure must also flush commands already
-- queued by the MUD. This is deliberately separate from combat autostop,
-- which preserves navigation state by design.
function snd.mapper.abortFailedNavigation(reason)
    if not snd.mapper.hasActiveNavigation() then
        return false
    end

    if type(send) == "function" then
        send("stop", false)
    end
    snd.mapper.pathExecutionSerial = (tonumber(snd.mapper.pathExecutionSerial) or 0) + 1
    snd.mapper.pathExecutionActive = false
    snd.mapper.pathExecutionHasPendingGroups = false
    snd.mapper.goingToRoom = nil
    if snd.nav then
        snd.nav.goingToRoom = nil
        snd.nav.pendingManualApproachRequest = nil
        snd.nav.pendingTargetRoomFallback = nil
        snd.nav.targetAreaFallback = nil
    end
    snd.mapper.pendingBlockedTravel = nil
    snd.mapper.pendingRestrictionMarks.portal = nil
    snd.mapper.pendingRestrictionMarks.recall = nil
    if snd.scan then
        snd.scan.pendingNxAction = nil
    end

    if snd.conwin then
        if type(snd.conwin.cancelTravel) == "function" then
            snd.conwin.cancelTravel()
        else
            if type(snd.conwin.abortCapture) == "function" then
                snd.conwin.abortCapture()
            end
            snd.conwin.travelActive = false
        end
    end

    snd.mapper.notifyBigmapNavigationState(reason or "route_failed")
    snd.utils.infoNote("Navigation stopped after a definitive route failure.")
    return true
end

function snd.mapper.pathStartsWithJump(path, expectedType)
    local travelType = path and path[1] and path[1].travelType
    if expectedType then
        return travelType == expectedType
    end
    return travelType == "portal" or travelType == "recall"
end

function snd.mapper.roomsShareArea(firstRoom, secondRoom)
    local firstInfo = snd.mapper.getRoomInfo(firstRoom)
    local secondInfo = snd.mapper.getRoomInfo(secondRoom)
    local firstArea = firstInfo and snd.utils.trim(firstInfo.area or ""):lower() or ""
    local secondArea = secondInfo and snd.utils.trim(secondInfo.area or ""):lower() or ""
    return firstArea ~= "" and firstArea == secondArea
end

function snd.mapper.pathPortalCount(path)
    local count = 0
    for _, step in ipairs(path or {}) do
        if step.travelType == "portal" then count = count + 1 end
    end
    return count
end

function snd.mapper.pathStartsWithTravel(path)
    for _, step in ipairs(path or {}) do
        if step.travelType == "portal" or step.travelType == "recall" then
            return true
        end
    end
    return false
end

-- Returns true when the ordinary walking prefix crosses out of sourceArea
-- before its first recall/portal command. Post-jump rooms are intentionally
-- ignored: those are not evidence of a panic walk out of the source area.
function snd.mapper.pathLeavesAreaBeforeJump(path, sourceArea)
    local wantedArea = snd.utils.trim(sourceArea or ""):lower()
    if wantedArea == "" then return false end

    for _, step in ipairs(path or {}) do
        if step.travelType == "portal" or step.travelType == "recall" then
            return false
        end
        local info = step.uid and snd.mapper.getRoomInfo(step.uid) or nil
        local stepArea = info and snd.utils.trim(info.area or ""):lower() or ""
        if stepArea ~= "" and stepArea ~= wantedArea then
            return true
        end
    end
    return false
end

function snd.mapper.chooseShortestRoute(candidates, opts)
    local best = nil
    local bestPortalCount = math.huge
    local bestSteps = math.huge
    for _, candidate in ipairs(candidates or {}) do
        if candidate and candidate.path and #candidate.path > 0 then
            local candidatePortalCount = snd.mapper.pathPortalCount(candidate.path)
            local candidateSteps = #candidate.path
            if not best
                or candidateSteps < bestSteps
                or (candidateSteps == bestSteps and candidatePortalCount < bestPortalCount)
            then
                best = candidate
                bestPortalCount = candidatePortalCount
                bestSteps = candidateSteps
            end
        end
    end
    return best
end

function snd.mapper.resolveCurrentAreaStartRoom(sourceRoom)
    local candidates = {}
    local seen = {}

    local function addCandidate(value)
        local candidate = snd.utils.trim(value or "")
        local key = candidate:lower()
        if candidate ~= "" and candidate ~= "-1" and candidate ~= "-2" and not seen[key] then
            seen[key] = true
            table.insert(candidates, candidate)
        end
    end

    addCandidate(snd.room and snd.room.current and snd.room.current.arid)
    local sourceInfo = snd.mapper.getRoomInfo(sourceRoom)
    addCandidate(sourceInfo and sourceInfo.area)

    local function lookupStart(areaKey)
        local normalizedKey = snd.utils.trim(areaKey or ""):lower()
        if normalizedKey == "" then return nil end

        if snd.db and type(snd.db.getAreaStartRoom) == "function" then
            local ok, startRoom = pcall(snd.db.getAreaStartRoom, normalizedKey)
            startRoom = ok and tonumber(startRoom) or -1
            if startRoom and startRoom > 0 then
                return normalizedKey, tostring(startRoom)
            end
        end

        if snd.data and snd.data.areaDefaultStartRooms then
            local defaults = snd.data.areaDefaultStartRooms[normalizedKey]
            local startRoom = defaults and tonumber(defaults.start) or -1
            if startRoom and startRoom > 0 then
                return normalizedKey, tostring(startRoom)
            end
        end

        return nil
    end

    for _, candidate in ipairs(candidates) do
        local areaKey, startRoom = lookupStart(candidate)
        if areaKey then
            return areaKey, startRoom
        end

        if snd.db and type(snd.db.getAreaKeyFromName) == "function" then
            local ok, resolvedKey = pcall(snd.db.getAreaKeyFromName, candidate)
            if ok and resolvedKey and tostring(resolvedKey) ~= "" then
                areaKey, startRoom = lookupStart(resolvedKey)
                if areaKey then
                    return areaKey, startRoom
                end
            end
        end
    end

    return nil, nil
end

function snd.mapper.buildAreaStartFallbackRoute(sourceRoom, destination, blockedType, ignoreLockedExits, opts)
    sourceRoom = tostring(sourceRoom or "")
    destination = tostring(destination or "")
    opts = opts or {}
    local areaKey, startRoom = snd.mapper.resolveCurrentAreaStartRoom(sourceRoom)
    if not areaKey or not startRoom or startRoom == destination then
        return nil
    end

    local walkPath = {}
    if sourceRoom ~= startRoom then
        walkPath = snd.mapper.findPath(sourceRoom, startRoom, true, true, ignoreLockedExits)
        if not walkPath then
            snd.utils.debugNote("area-start fallback: no walk-only route to " .. tostring(areaKey) .. " start room " .. tostring(startRoom) .. ".")
            return nil
        end

        local sourceInfo = snd.mapper.getRoomInfo(sourceRoom)
        local sourceArea = sourceInfo and sourceInfo.area or areaKey
        if snd.mapper.pathLeavesAreaBeforeJump(walkPath, sourceArea) then
            snd.utils.debugNote("area-start fallback rejected a walk that leaves " .. tostring(areaKey) .. " before reaching start room " .. tostring(startRoom) .. ".")
            return nil
        end
    end

    local allowPortals = opts.allowPortals ~= false
    local allowRecalls = opts.allowRecalls ~= false
    local noPortals = not allowPortals
    local noRecalls = not allowRecalls
    local originMode
    if allowPortals and allowRecalls then
        originMode = "jump"
    elseif allowPortals then
        originMode = "portal"
    elseif allowRecalls then
        originMode = "recall"
    end

    -- The area start is already a late fallback. Find its first usable jump in
    -- the ordinary BFS instead of running separate portal and recall searches.
    local jumpLeg = originMode and snd.mapper.findPath(
        startRoom,
        destination,
        noPortals,
        noRecalls,
        ignoreLockedExits,
        nil,
        nil,
        nil,
        originMode
    ) or nil
    local jumpType = jumpLeg and jumpLeg[1] and jumpLeg[1].travelType or nil

    -- If the designated start has learned that both jump methods are blocked,
    -- make one bounded nearby attempt from the start itself. This remains part
    -- of the area-start fallback and therefore precedes a cross-area long walk.
    if not jumpLeg and type(snd.mapper.buildOutwardJumpRoute) == "function" then
        local outwardLeg, outwardType, outwardRoom = snd.mapper.buildOutwardJumpRoute(
            startRoom,
            destination,
            ignoreLockedExits,
            {
                allowPortals = allowPortals,
                allowRecalls = allowRecalls,
                searchDepthLimit = opts.nearbyJumpRadius,
            }
        )
        local outwardAllowed = (outwardType == "portal" and opts.allowPortals ~= false)
            or (outwardType == "recall" and opts.allowRecalls ~= false)
        if outwardLeg and #outwardLeg > 0 and outwardAllowed then
            jumpLeg = outwardLeg
            jumpType = outwardType
            snd.utils.debugNote(string.format(
                "area-start fallback: start room %s is restricted; continuing to jump room %s.",
                tostring(startRoom),
                tostring(outwardRoom or "?")
            ))
        end
    end

    if not jumpLeg then
        snd.utils.debugNote("area-start fallback: start room " .. tostring(startRoom) .. " has no direct recall/portal route to " .. destination .. ".")
        return nil
    end

    local combined = {}
    for _, step in ipairs(walkPath) do table.insert(combined, step) end
    for _, step in ipairs(jumpLeg) do table.insert(combined, step) end
    return combined, areaKey, startRoom, jumpType
end

function snd.mapper.onPortalBlocked()
    if snd.mapper.isInCombat and snd.mapper.isInCombat() then
        snd.mapper.consumeRestrictionMark("portal")
        snd.utils.debugNote("Ignoring portal blocked trigger while in combat.")
        return
    end
    if mm and mm.portal_usage and mm.portal_usage.mark_blocked then
        mm.portal_usage.mark_blocked("magic_walls_bounced_portal")
    end
    snd.mapper.pathExecutionSerial = (tonumber(snd.mapper.pathExecutionSerial) or 0) + 1
    local destination = snd.mapper.goingToRoom or (snd.nav and snd.nav.goingToRoom)
    local pending = snd.mapper.consumeRestrictionMark("portal")
    local wasUpdated = false
    local blockedRoomId = nil
    if pending and pending.roomId then
        blockedRoomId = tostring(pending.roomId)
        local ok, updated = snd.mapper.markRoomRestriction(pending.roomId, "noportal")
        if ok and updated then
            wasUpdated = true
        end
    end
    if wasUpdated and blockedRoomId then
        snd.utils.infoNote("Portal blocked. Room " .. blockedRoomId .. " is now marked noportal. Waiting for your next xrt command.")
    elseif blockedRoomId then
        snd.utils.infoNote("Portal blocked in room " .. blockedRoomId .. ". Waiting for your next xrt command.")
    else
        snd.utils.infoNote("Portal blocked, but no queued travel marker was available. Waiting for your next xrt command.")
    end
    if blockedRoomId and destination then
        snd.mapper.pendingBlockedTravel = {
            blockedType = "portal",
            roomId = blockedRoomId,
            destination = tostring(destination),
        }
    else
        snd.mapper.pendingBlockedTravel = nil
    end
    snd.mapper.goingToRoom = nil
    snd.nav.goingToRoom = nil
    snd.mapper.notifyBigmapNavigationState("portal_blocked")
end

function snd.mapper.onRecallBlocked()
    if snd.mapper.isInCombat and snd.mapper.isInCombat() then
        snd.mapper.consumeRestrictionMark("recall")
        snd.utils.debugNote("Ignoring recall blocked trigger while in combat.")
        return
    end
    snd.mapper.pathExecutionSerial = (tonumber(snd.mapper.pathExecutionSerial) or 0) + 1
    local destination = snd.mapper.goingToRoom or (snd.nav and snd.nav.goingToRoom)
    local pending = snd.mapper.consumeRestrictionMark("recall")
    local wasUpdated = false
    local blockedRoomId = nil
    if pending and pending.roomId then
        blockedRoomId = tostring(pending.roomId)
        local ok, updated = snd.mapper.markRoomRestriction(pending.roomId, "norecall")
        if ok and updated then
            wasUpdated = true
        end
    end
    if wasUpdated and blockedRoomId then
        snd.utils.infoNote("Recall blocked. Room " .. blockedRoomId .. " is now marked norecall. Waiting for your next xrt command.")
    elseif blockedRoomId then
        snd.utils.infoNote("Recall blocked in room " .. blockedRoomId .. ". Waiting for your next xrt command.")
    else
        snd.utils.infoNote("Recall blocked, but no queued travel marker was available. Waiting for your next xrt command.")
    end
    if blockedRoomId and destination then
        snd.mapper.pendingBlockedTravel = {
            blockedType = "recall",
            roomId = blockedRoomId,
            destination = tostring(destination),
        }
    else
        snd.mapper.pendingBlockedTravel = nil
    end
    snd.mapper.goingToRoom = nil
    snd.nav.goingToRoom = nil
    snd.mapper.notifyBigmapNavigationState("recall_blocked")
end

function snd.mapper.handleBlockedTravel(blockedType, ignoreLockedExits)
    local destination = snd.mapper.goingToRoom or (snd.nav and snd.nav.goingToRoom)
    if not destination then
        return
    end

    local currentRoom = snd.mapper.currentRoomUid(true)
    currentRoom = tostring(currentRoom or "")
    if currentRoom == "" or currentRoom == "-1" then
        return
    end

    destination = tostring(destination)
    if currentRoom == destination then
        return
    end

    local currentInfo = snd.mapper.getRoomInfo(currentRoom)
    local currentNoPortal = currentInfo and tonumber(currentInfo.noportal) == 1 or false
    local currentNoRecall = currentInfo and tonumber(currentInfo.norecall) == 1 or false
    snd.utils.debugNote(string.format(
        "blocked travel: room=%s dest=%s blockedType=%s noportal=%s norecall=%s",
        tostring(currentRoom),
        tostring(destination),
        tostring(blockedType),
        tostring(currentNoPortal),
        tostring(currentNoRecall)
    ))

    local expectedType = (blockedType == "portal") and "recall" or "portal"
    local expectedBlocked
    if expectedType == "portal" then
        expectedBlocked = currentNoPortal
    else
        expectedBlocked = currentNoRecall
    end

    -- The opposite jump is legal in the current room: calculate that jump once,
    -- execute it immediately, and do not look for walking, nearby, or area-start
    -- competitors. originMode prevents a shorter walking origin from replacing
    -- the explicitly requested recovery method.
    if not expectedBlocked then
        local directJump = snd.mapper.findPath(
            currentRoom,
            destination,
            false,
            false,
            ignoreLockedExits,
            nil,
            nil,
            nil,
            "jump"
        )
        if directJump and #directJump > 0 and snd.mapper.pathStartsWithJump(directJump, expectedType) then
            snd.utils.debugNote("Blocked " .. blockedType .. "; using immediate " .. expectedType .. " route.")
            snd.mapper.executePath(directJump)
            return true
        end

        -- Without a configured bounce, the combined jump search may reject a
        -- blocked winning origin. Retry only the legal opposite origin; never
        -- substitute walking or a nearby-room search.
        local forcedJump = snd.mapper.findPath(
            currentRoom,
            destination,
            expectedType == "recall",
            expectedType == "portal",
            ignoreLockedExits,
            nil,
            nil,
            nil,
            expectedType
        )
        if forcedJump and #forcedJump > 0 then
            snd.utils.debugNote("Blocked " .. blockedType .. "; using forced immediate " .. expectedType .. " route.")
            snd.mapper.executePath(forcedJump)
            return true
        end
        snd.utils.debugNote("Blocked " .. blockedType .. "; no immediate " .. expectedType .. " route was mapped from this room.")
        return false
    end

    -- Nearby and area-start recovery are only meaningful when neither jump can
    -- be used in the current room. The nearby probe has a hard walking radius;
    -- once exhausted, the designated area start is the next fallback.
    if currentNoPortal and currentNoRecall then
        local nearbyRadius = tonumber(snd.mapper.config.nearbyJumpRadius) or 10
        local nearbyPath, nearbyRoom = snd.mapper.findNearestAlternateRoute(
            currentRoom,
            destination,
            blockedType,
            ignoreLockedExits,
            false,
            nearbyRadius
        )
        if nearbyPath and #nearbyPath > 0 then
            snd.utils.infoNote(string.format(
                "Rerouting via nearby room %s to use %s (%d steps).",
                tostring(nearbyRoom or "?"),
                expectedType,
                #nearbyPath
            ))
            snd.mapper.executePath(nearbyPath)
            return true
        end

        local areaRoute, areaKey, startRoom, jumpType = snd.mapper.buildAreaStartFallbackRoute(
            currentRoom,
            destination,
            blockedType,
            ignoreLockedExits,
            {
                allowPortals = snd.mapper.config.usePortals ~= false,
                allowRecalls = snd.mapper.config.useRecall ~= false,
                nearbyJumpRadius = nearbyRadius,
            }
        )
        if areaRoute and #areaRoute > 0 then
            snd.utils.infoNote(string.format(
                "Nearby jump options exhausted. Rerouting through %s start room %s, then using %s.",
                tostring(areaKey or "area"),
                tostring(startRoom or "?"),
                tostring(jumpType or "a jump")
            ))
            snd.mapper.executePath(areaRoute)
            return true
        end

        -- A long walk is genuinely last: both immediate jumps, the bounded
        -- nearby search, and the area-start route have already failed.
        local walkingPath = snd.mapper.findPath(
            currentRoom,
            destination,
            true,
            true,
            ignoreLockedExits,
            nil,
            nil,
            nil,
            "walk"
        )
        if walkingPath and #walkingPath > 0 then
            snd.utils.infoNote("Nearby and area-start jump options failed; using the remaining walking route.")
            snd.mapper.executePath(walkingPath)
            return true
        end
    end

    snd.utils.infoNote("You couldn't find a path to " .. destination .. " from here.")
    snd.utils.infoNote("Blocked " .. blockedType .. " and no alternate route found from room " .. currentRoom .. ".")
    return false
end

--- Check for direct one-room path
function snd.mapper.checkDirectPath(src, dst, level, ignoreLockedExits, ignoreAreaGuard, randomCexits)
    local where = ignoreLockedExits and "" or string.format(" AND level <= %d", level)
    local areaFromWhere = snd.mapper.areaGuardRoomSql("exits.fromuid", src, ignoreLockedExits, ignoreAreaGuard)
    local areaToWhere = snd.mapper.areaGuardRoomSql("exits.touid", src, ignoreLockedExits, ignoreAreaGuard)
    local sql = string.format([[
        SELECT dir FROM exits 
        WHERE fromuid = %s AND touid = %s%s
          AND %s
          AND %s
        ORDER BY %s LIMIT 1
    ]],
        snd.mapper.db.escape(src),
        snd.mapper.db.escape(dst),
        where,
        areaFromWhere,
        areaToWhere,
        snd.mapper.exitPreferenceOrderSql("dir")
    )
    
    local results = snd.mapper.db.query(sql) or {}

    local chosen = results[1]
    for _, randomCandidate in ipairs(randomCexits or {}) do
        if tostring(randomCandidate.fromuid) == tostring(src)
            and tostring(randomCandidate.touid) == tostring(dst)
            and snd.mapper.shouldPreferExitDir(randomCandidate.dir, chosen and chosen.dir or nil)
        then
            chosen = randomCandidate
        end
    end
    if chosen then
        return {{
            dir = chosen.dir,
            uid = dst,
            randomCexit = tonumber(chosen.random_cexit) == 1,
        }}
    end
    return nil
end

function snd.mapper.buildOutwardJumpRoute(sourceRoom, destination, ignoreLockedExits, opts)
    sourceRoom = tostring(sourceRoom or "")
    destination = tostring(destination or "")
    opts = type(opts) == "table" and opts or {}
    if sourceRoom == "" or sourceRoom == "-1" or destination == "" then
        return nil
    end

    local sourceInfo = snd.mapper.getRoomInfo(sourceRoom)
    local srcNoPortal = sourceInfo and tonumber(sourceInfo.noportal) == 1 or false
    local srcNoRecall = sourceInfo and tonumber(sourceInfo.norecall) == 1 or false
    if not (srcNoPortal and srcNoRecall) then
        snd.utils.debugNote("outward jump-route skipped: source room already supports portal or recall.")
        return nil
    end

    local allowPortals = opts.allowPortals ~= false
    local allowRecalls = opts.allowRecalls ~= false
    local requiredType = opts.requiredType
    local searchDepthLimit = tonumber(opts.searchDepthLimit)
        or tonumber(snd.mapper.config.nearbyJumpRadius)
        or 10

    local closestRoom, walkPath
    if requiredType == "portal" then
        closestRoom, walkPath = snd.mapper.findNearestRoomWithoutFlag(
            sourceRoom,
            "noportal",
            ignoreLockedExits,
            searchDepthLimit
        )
    elseif requiredType == "recall" then
        closestRoom, walkPath = snd.mapper.findNearestRoomWithoutFlag(
            sourceRoom,
            "norecall",
            ignoreLockedExits,
            searchDepthLimit
        )
    else
        closestRoom, walkPath = snd.mapper.findNearestRoomWithoutBothFlags(
            sourceRoom,
            ignoreLockedExits,
            searchDepthLimit
        )
    end
    if not closestRoom or not walkPath then
        snd.utils.debugNote("outward jump-route: no nearby room with jump access found.")
        return nil
    end

    local closestInfo = snd.mapper.getRoomInfo(closestRoom)
    local closestNoPortal = closestInfo and tonumber(closestInfo.noportal) == 1 or false
    local closestNoRecall = closestInfo and tonumber(closestInfo.norecall) == 1 or false
    snd.utils.debugNote(string.format(
        "outward jump-route candidate room=%s walkSteps=%d noportal=%s norecall=%s",
        tostring(closestRoom),
        #walkPath,
        tostring(closestNoPortal),
        tostring(closestNoRecall)
    ))

    local canPortal = allowPortals and not closestNoPortal
    local canRecall = allowRecalls and not closestNoRecall
    local originMode
    if requiredType == "portal" and canPortal then
        originMode = "portal"
    elseif requiredType == "recall" and canRecall then
        originMode = "recall"
    elseif canPortal and canRecall then
        originMode = "jump"
    elseif canPortal then
        originMode = "portal"
    elseif canRecall then
        originMode = "recall"
    end

    local chosenLeg = originMode and snd.mapper.findPath(
        tostring(closestRoom),
        destination,
        not canPortal,
        not canRecall,
        ignoreLockedExits,
        nil,
        nil,
        nil,
        originMode
    ) or nil
    local chosenType = chosenLeg and chosenLeg[1] and chosenLeg[1].travelType or nil
    if not chosenLeg or #chosenLeg == 0 then
        snd.utils.debugNote("outward jump-route: candidate room has no recall or portal continuation.")
        return nil
    end

    local combined = {}
    for _, step in ipairs(walkPath) do table.insert(combined, step) end
    for _, step in ipairs(chosenLeg) do table.insert(combined, step) end
    snd.utils.debugNote(string.format(
        "outward jump-route selected via room=%s using=%s totalSteps=%d",
        tostring(closestRoom),
        tostring(chosenType),
        #combined
    ))
    return combined, chosenType, closestRoom
end

--- Find nearest room that allows portal/recall
function snd.mapper.findNearestRoomWithoutFlag(src, restrictionFlag, ignoreLockedExits, searchDepthLimit)
    if not src then return nil, nil end
    local safeFlag = (restrictionFlag == "norecall") and "norecall" or "noportal"
    local source = tostring(src)
    local sourceInfo = snd.mapper.getRoomInfo(source)
    if sourceInfo and tonumber(sourceInfo[safeFlag]) ~= 1 then
        snd.utils.debugNote(string.format(
            "findNearestRoomWithoutFlag(%s): source room %s already valid",
            safeFlag,
            source
        ))
        return source, {}
    end
    snd.utils.debugNote(string.format(
        "findNearestRoomWithoutFlag(%s): searching from %s",
        safeFlag,
        source
    ))

    local myLevel = snd.char.level or 201
    local configuredDepth = tonumber(snd.mapper.config.maxSearchDepth) or 100
    local requestedDepth = tonumber(searchDepthLimit)
    local maxDepth = requestedDepth
        and math.max(0, math.min(configuredDepth, math.floor(requestedDepth)))
        or configuredDepth
    local queue = {{room = source, depth = 0}}
    local head = 1
    local visited = {[source] = true}
    local parents = {}
    local areaWhere = snd.mapper.areaGuardRoomSql("exits.touid", source, ignoreLockedExits)

    while head <= #queue do
        local node = queue[head]
        head = head + 1
        if node.depth < maxDepth then
            local levelWhere = ignoreLockedExits and "1=1" or string.format("level <= %d", myLevel)
            local sql = string.format([[
                SELECT touid, dir
                FROM exits
                WHERE fromuid = %s
                  AND fromuid NOT IN ('*', '**')
                  AND touid NOT IN ('*', '**')
                  AND %s
                  AND %s
                ORDER BY %s
            ]],
                snd.mapper.db.escape(node.room),
                levelWhere,
                areaWhere,
                snd.mapper.exitPreferenceOrderSql("dir")
            )
            local exits = snd.mapper.db.query(sql) or {}
            for _, ex in ipairs(exits) do
                local nextRoom = tostring(ex.touid or "")
                if nextRoom ~= "" and nextRoom ~= "-1" and not visited[nextRoom] then
                    visited[nextRoom] = true
                    parents[nextRoom] = {prev = node.room, dir = ex.dir}

                    local roomInfo = snd.mapper.getRoomInfo(nextRoom)
                    if roomInfo and tonumber(roomInfo[safeFlag]) ~= 1 then
                        local walkPath = {}
                        local cursor = nextRoom
                        while cursor ~= source do
                            local p = parents[cursor]
                            if not p then break end
                            table.insert(walkPath, 1, {dir = p.dir, uid = cursor})
                            cursor = p.prev
                        end
                        snd.utils.debugNote(string.format(
                            "findNearestRoomWithoutFlag(%s): found room=%s walkSteps=%d",
                            safeFlag,
                            nextRoom,
                            #walkPath
                        ))
                        return nextRoom, walkPath
                    end

                    table.insert(queue, {room = nextRoom, depth = node.depth + 1})
                end
            end
        end
    end
    snd.utils.debugNote(string.format(
        "findNearestRoomWithoutFlag(%s): no room found from %s within depth=%d",
        safeFlag,
        source,
        maxDepth
    ))

    return nil, nil
end

function snd.mapper.findNearestRoomWithoutBothFlags(src, ignoreLockedExits, searchDepthLimit)
    local source = tostring(src or "")
    if source == "" or source == "-1" then
        return nil, nil
    end

    local srcInfo = snd.mapper.getRoomInfo(source)
    local srcNoPortal = srcInfo and tonumber(srcInfo.noportal) == 1 or false
    local srcNoRecall = srcInfo and tonumber(srcInfo.norecall) == 1 or false
    if not (srcNoPortal and srcNoRecall) then
        snd.utils.debugNote("findNearestRoomWithoutBothFlags: source room already has at least one jump option.")
        return source, {}
    end
    snd.utils.debugNote("findNearestRoomWithoutBothFlags: searching for nearest room with portal or recall access.")

    local myLevel = snd.char.level or 201
    local configuredDepth = tonumber(snd.mapper.config.maxSearchDepth) or 100
    local requestedDepth = tonumber(searchDepthLimit)
    local maxDepth = requestedDepth
        and math.max(0, math.min(configuredDepth, math.floor(requestedDepth)))
        or configuredDepth
    local queue = {{room = source, depth = 0}}
    local head = 1
    local visited = {[source] = true}
    local parents = {}
    local areaWhere = snd.mapper.areaGuardRoomSql("exits.touid", source, ignoreLockedExits)

    while head <= #queue do
        local node = queue[head]
        head = head + 1
        if node.depth < maxDepth then
            local levelWhere = ignoreLockedExits and "1=1" or string.format("level <= %d", myLevel)
            local sql = string.format([[
                SELECT touid, dir
                FROM exits
                WHERE fromuid = %s
                  AND fromuid NOT IN ('*', '**')
                  AND touid NOT IN ('*', '**')
                  AND %s
                  AND %s
                ORDER BY %s
            ]],
                snd.mapper.db.escape(node.room),
                levelWhere,
                areaWhere,
                snd.mapper.exitPreferenceOrderSql("dir")
            )
            local exits = snd.mapper.db.query(sql) or {}
            for _, ex in ipairs(exits) do
                local nextRoom = tostring(ex.touid or "")
                if nextRoom ~= "" and nextRoom ~= "-1" and not visited[nextRoom] then
                    local roomInfo = snd.mapper.getRoomInfo(nextRoom)
                    visited[nextRoom] = true
                    parents[nextRoom] = {prev = node.room, dir = ex.dir}

                    local nextNoPortal = roomInfo and tonumber(roomInfo.noportal) == 1 or false
                    local nextNoRecall = roomInfo and tonumber(roomInfo.norecall) == 1 or false
                    if not (nextNoPortal and nextNoRecall) then
                        local walkPath = {}
                        local cursor = nextRoom
                        while cursor ~= source do
                            local p = parents[cursor]
                            if not p then break end
                            table.insert(walkPath, 1, {dir = p.dir, uid = cursor})
                            cursor = p.prev
                        end
                        snd.utils.debugNote(string.format(
                            "findNearestRoomWithoutBothFlags: found room=%s walkSteps=%d flags(noportal=%s,norecall=%s)",
                            nextRoom,
                            #walkPath,
                            tostring(nextNoPortal),
                            tostring(nextNoRecall)
                        ))
                        return nextRoom, walkPath
                    end

                    table.insert(queue, {room = nextRoom, depth = node.depth + 1})
                end
            end
        end
    end
    snd.utils.debugNote("findNearestRoomWithoutBothFlags: no suitable room found.")

    return nil, nil
end

function snd.mapper.findNearestAlternateRoute(
    src,
    dst,
    blockedType,
    ignoreLockedExits,
    allowGeneralFallback,
    searchDepthLimit
)
    local source = tostring(src or "")
    local destination = tostring(dst or "")
    if source == "" or destination == "" then
        return nil
    end

    local requiredFlag = (blockedType == "recall") and "noportal" or "norecall"
    local forceNoPortals = (blockedType == "portal")
    local forceNoRecalls = (blockedType == "recall")
    local expectedType = (blockedType == "portal") and "recall" or "portal"
    local myLevel = snd.char.level or 201
    local configuredDepth = tonumber(snd.mapper.config.maxSearchDepth) or 100
    local requestedDepth = tonumber(searchDepthLimit)
    local maxDepth = requestedDepth
        and math.max(0, math.min(configuredDepth, math.floor(requestedDepth)))
        or configuredDepth
    local maxCandidates = 40
    local testedCandidates = 0

    local queue = {{room = source, depth = 0}}
    local head = 1
    local visited = {[source] = true}
    local parents = {}
    local areaWhere = snd.mapper.areaGuardRoomSql("exits.touid", source, ignoreLockedExits)

    while head <= #queue do
        local node = queue[head]
        head = head + 1

        local roomInfo = snd.mapper.getRoomInfo(node.room)
        local canUseAlternate = roomInfo and tonumber(roomInfo[requiredFlag]) ~= 1
        if canUseAlternate then
            testedCandidates = testedCandidates + 1
            local leg = snd.mapper.findPath(
                node.room,
                destination,
                forceNoPortals,
                forceNoRecalls,
                ignoreLockedExits,
                nil,
                nil,
                nil,
                expectedType
            )
            if leg and #leg > 0 and snd.mapper.pathStartsWithJump(leg, expectedType) then
                local walkPath = {}
                local cursor = node.room
                while cursor ~= source do
                    local p = parents[cursor]
                    if not p then break end
                    table.insert(walkPath, 1, {dir = p.dir, uid = cursor})
                    cursor = p.prev
                end

                local combined = {}
                for _, step in ipairs(walkPath) do
                    table.insert(combined, step)
                end
                for _, step in ipairs(leg) do
                    table.insert(combined, step)
                end
                return combined, node.room, "preferred"
            end

            -- Some callers may still opt into the legacy general-route fallback.
            local fallbackLeg = allowGeneralFallback
                and snd.mapper.findPath(node.room, destination, nil, nil, ignoreLockedExits)
                or nil
            if fallbackLeg and #fallbackLeg > 0 then
                local walkPath = {}
                local cursor = node.room
                while cursor ~= source do
                    local p = parents[cursor]
                    if not p then break end
                    table.insert(walkPath, 1, {dir = p.dir, uid = cursor})
                    cursor = p.prev
                end

                local combined = {}
                for _, step in ipairs(walkPath) do
                    table.insert(combined, step)
                end
                for _, step in ipairs(fallbackLeg) do
                    table.insert(combined, step)
                end
                return combined, node.room, "fallback"
            end
            if testedCandidates >= maxCandidates then
                break
            end
        end

        if node.depth < maxDepth then
            local levelWhere = ignoreLockedExits and "1=1" or string.format("level <= %d", myLevel)
            local sql = string.format([[
                SELECT touid, dir
                FROM exits
                WHERE fromuid = %s
                  AND fromuid NOT IN ('*', '**')
                  AND touid NOT IN ('*', '**')
                  AND %s
                  AND %s
                ORDER BY %s
            ]],
                snd.mapper.db.escape(node.room),
                levelWhere,
                areaWhere,
                snd.mapper.exitPreferenceOrderSql("dir")
            )
            local exits = snd.mapper.db.query(sql) or {}
            for _, ex in ipairs(exits) do
                local nextRoom = tostring(ex.touid or "")
                if nextRoom ~= "" and nextRoom ~= "-1" and not visited[nextRoom] then
                    visited[nextRoom] = true
                    parents[nextRoom] = {prev = node.room, dir = ex.dir}
                    table.insert(queue, {room = nextRoom, depth = node.depth + 1})
                end
            end
        end
    end

    return nil
end

-------------------------------------------------------------------------------
-- Navigation Execution
-------------------------------------------------------------------------------

function snd.mapper.notifyBigmapNavigationState(reason)
    if not (mm and mm.minimap and mm.minimap.on_navigation_state_changed) then return end
    local ok, err = pcall(mm.minimap.on_navigation_state_changed, reason)
    if not ok and snd.utils and snd.utils.debugNote then
        snd.utils.debugNote("Hybrid bigmap state update failed: " .. tostring(err))
    end
end

local function clone_path_slice(path, first, last)
    local sliced = {}
    for index = first, last do
        local original = path[index]
        if original then
            local copy = {}
            for key, value in pairs(original) do copy[key] = value end
            table.insert(sliced, copy)
        end
    end
    return sliced
end

--- Coordinate conditional cexits without resolving their DINV state early.
-- Normal segments use executePath unchanged. Before each conditional step, the
-- coordinator waits for its recorded source room, resolves the key, replaces
-- that one step's command, and releases the next segment.
function snd.mapper.executeConditionalPath(path, conditionalByIndex, opts)
    opts = opts or {}
    path = clone_path_slice(path, 1, #path)
    conditionalByIndex = conditionalByIndex or {}

    if not opts.preserveExecutionSerial then
        snd.mapper.pathExecutionSerial = (tonumber(snd.mapper.pathExecutionSerial) or 0) + 1
    end
    local executionSerial = snd.mapper.pathExecutionSerial
    snd.mapper.pathExecutionActive = true
    snd.mapper.pathExecutionHasPendingGroups = true

    local cursor = 1
    local function currentExecution()
        return snd.mapper.pathExecutionSerial == executionSerial
    end

    local runNextSegment
    runNextSegment = function()
        if not currentExecution() then return end

        local conditionalIndex
        for index = cursor, #path do
            if conditionalByIndex[index] then
                conditionalIndex = index
                break
            end
        end

        if not conditionalIndex then
            local finalSegment = clone_path_slice(path, cursor, #path)
            if #finalSegment == 0 then
                snd.mapper.pathExecutionHasPendingGroups = false
                return
            end
            snd.mapper.executePath(finalSegment, {
                preserveExecutionSerial = true,
                skipConditionalCexitResolution = true,
            })
            return
        end

        local config = conditionalByIndex[conditionalIndex]
        local prefix = clone_path_slice(path, cursor, conditionalIndex - 1)
        local function awaitConditionalSource()
            if not currentExecution() then return end
            local currentRoom = tostring(snd.mapper.currentRoomUid(false) or "-1")
            local wantedRoom = tostring(config.source_room or config.fromuid or "-1")
            if currentRoom ~= wantedRoom then
                snd.mapper.pathExecutionActive = true
                snd.mapper.pathExecutionHasPendingGroups = true
                tempTimer(0.1, awaitConditionalSource)
                return
            end

            local selected, branch = mm.choose_cexit_key_command(config, path[conditionalIndex].dir)
            path[conditionalIndex].cexitBaseDir = tostring(config.dir or path[conditionalIndex].dir or "")
            path[conditionalIndex].dir = selected
            conditionalByIndex[conditionalIndex] = nil
            cursor = conditionalIndex
            snd.utils.debugNote(string.format(
                "conditional cexit released at room %s using %s branch",
                wantedRoom, tostring(branch)
            ))
            runNextSegment()
        end

        if #prefix > 0 then
            snd.mapper.executePath(prefix, {
                preserveExecutionSerial = true,
                skipConditionalCexitResolution = true,
            })
            snd.mapper.pathExecutionActive = true
            snd.mapper.pathExecutionHasPendingGroups = true
        end
        awaitConditionalSource()
    end

    runNextSegment()
    return true
end

--- Execute a path (send commands)
-- Handles cardinal directions with 'run', special exits with ';;', and wait() with tempTimer
-- @param path Path table from findPath
-- @param opts Optional execution controls; preserveExecutionSerial keeps an outer path alive
function snd.mapper.executePath(path, opts)
    if snd.mapper.persistenceArrivalSettling and snd.mapper.flushPendingPersists then
        snd.mapper.flushPendingPersists()
    end
    if not path or #path == 0 then
        return
    end

    opts = opts or {}

    -- A random cexit is always terminal for this invocation. Its recorded
    -- destination is only a pathfinding possibility, never a landing promise.
    -- Drop the suffix before command groups are built so nothing can be queued
    -- after the random command.
    local terminalPath = {}
    for _, step in ipairs(path) do
        table.insert(terminalPath, step)
        if step.randomCexit == true then break end
    end
    path = terminalPath

    if not opts.skipConditionalCexitResolution
        and mm and type(mm.cexit_key_alternates_for_path) == "function"
    then
        local initialSource = snd.mapper.currentRoomUid(false)
        local configured = mm.cexit_key_alternates_for_path(path, initialSource)
        if type(configured) == "table" and next(configured) then
            return snd.mapper.executeConditionalPath(path, configured, opts)
        end
    end

    snd.mapper.notifyBigmapNavigationState("path_started")

    if not opts.preserveExecutionSerial then
        snd.mapper.pathExecutionSerial = (tonumber(snd.mapper.pathExecutionSerial) or 0) + 1
    end
    local executionSerial = snd.mapper.pathExecutionSerial
    snd.mapper.pathExecutionActive = true
    snd.mapper.pathExecutionHasPendingGroups = true
    if mm and type(mm.track_cexit_key_observation_path) == "function" then
        local trackOk, trackErr = pcall(
            mm.track_cexit_key_observation_path,
            path,
            snd.mapper.currentRoomUid(false),
            executionSerial
        )
        if not trackOk then
            snd.utils.debugNote("cexit key observation path tracking failed: " .. tostring(trackErr))
        end
    end
    if snd.conwin and type(snd.conwin.onTravelStarted) == "function" then
        snd.conwin.onTravelStarted("mapper-path-started")
    end

    local function isExecutionCurrent()
        return snd.mapper.pathExecutionSerial == executionSerial
    end
    
    -- Cardinal directions that can use 'run'
    local cardinalDirs = {
        n = true, s = true, e = true, w = true,
        u = true, d = true,
    }
    
    -- Helper: compress consecutive cardinal directions (s,s,e,e,e → 2s3e)
    local function compressCardinals(dirs)
        if #dirs == 0 then return "" end
        
        local compressed = {}
        local i = 1
        while i <= #dirs do
            local dir = dirs[i]
            local count = 1
            
            while i + count <= #dirs and dirs[i + count] == dir do
                count = count + 1
            end
            
            if count > 1 then
                table.insert(compressed, count .. dir)
            else
                table.insert(compressed, dir)
            end
            
            i = i + count
        end
        
        return table.concat(compressed, "")
    end
    
    local function getCurrentRoomId()
        local currentRoom = snd.mapper.currentRoomUid(false)
        return tostring(currentRoom or "-1")
    end

    local function enemyMatchesToken(token)
        local t = tostring(token or ""):lower():match("^%s*(.-)%s*$")
        if t == "" then return false end
        local enemy = ""
        if gmcp and gmcp.char and gmcp.char.status then
            enemy = tostring(gmcp.char.status.enemy or gmcp.char.status.opponent or ""):lower()
        end
        return enemy ~= "" and enemy:find(t, 1, true) ~= nil
    end

    -- Build command groups (separated by waits)
    -- Each group is {commands = {{text="cmd1", travelType=nil}, ...}, delayAfter = 0, waitRoomId = nil, executeRoomId = nil}
    local groups = {}
    local currentGroup = {commands = {}, delayAfter = 0, waitRoomId = nil, executeRoomId = nil, trustedSource = false}
    local cardinalBuffer = {}
    local simulatedRoom = getCurrentRoomId()
    
    local function flushCardinals()
        if #cardinalBuffer > 0 then
            if #cardinalBuffer == 1 then
                -- Single cardinal: no 'run' prefix needed
                table.insert(currentGroup.commands, {text = cardinalBuffer[1]})
            else
                -- Multiple cardinals: compress and use 'run'
                local compressed = compressCardinals(cardinalBuffer)
                table.insert(currentGroup.commands, {text = "run " .. compressed})
            end
            cardinalBuffer = {}
        end
    end
    
    -- Split a string on ';' (single semicolon), ignoring empty parts
	local function splitSemis(s)
	  local out = {}
	  -- treat one or more ';' as separators; ignore empty tokens
	  for part in tostring(s):gmatch("[^;]+") do
		part = part:match("^%s*(.-)%s*$") -- trim
		if part ~= "" then
		  table.insert(out, part)
		end
	  end
	  return out
	end

	for _, step in ipairs(path) do
		local raw = tostring(step.dir or "")
		local parts = raw:find(";", 1, true) and splitSemis(raw) or { raw }
        local stepSourceRoom = simulatedRoom
        local isTravelStep = step.travelType == "portal" or step.travelType == "recall"
        local isRandomCexit = step.randomCexit == true
        local stepHasWait = false
        local stepHasMapperWalkto = false
        local encounteredWait = false

        for _, token in ipairs(parts) do
            if tostring(token):match("^%s*wait%((%d+%.?%d*)%)%s*$") then
                stepHasWait = true
            end
            if mm and mm.mapper_walkto_target and mm.mapper_walkto_target(token) then
                stepHasMapperWalkto = true
            end
        end

        -- Unlike regular mapped cexits, never queue a random command behind a
        -- trusted prefix. Hold it until GMCP confirms its recorded source room.
        if isRandomCexit then
            flushCardinals()
            if #currentGroup.commands > 0 then
                table.insert(groups, currentGroup)
            end
            currentGroup = {
                commands = {},
                delayAfter = 0,
                waitRoomId = nil,
                executeRoomId = tostring(stepSourceRoom or "-1"),
                trustedSource = false,
                terminalRandomCexit = true,
            }
        end

        -- Keep jumps in their own command groups, but do not impose a GMCP
        -- barrier when the preceding mapped edge already declares its room ID.
        -- Restriction markers use the simulated mapped source room in that case.
        if isTravelStep then
            flushCardinals()
            if #currentGroup.commands > 0 then
                table.insert(groups, currentGroup)
            end
            local sourceIsTrusted = currentGroup.trustedSource == true
            local sourceExecuteRoom = tostring(stepSourceRoom or "-1")
            if sourceIsTrusted then
                sourceExecuteRoom = nil
            end
            currentGroup = {
                commands = {},
                delayAfter = 0,
                waitRoomId = nil,
                executeRoomId = sourceExecuteRoom,
                trustedSource = sourceIsTrusted,
            }
        end

        -- A cexit containing mapper walkto must itself wait until the outer
        -- path reaches the cexit source. Otherwise the nested walk would be
        -- calculated from the room occupied before the approach run finishes.
        if stepHasMapperWalkto then
            flushCardinals()
            if #currentGroup.commands > 0 then
                table.insert(groups, currentGroup)
            end
            currentGroup = {
                commands = {},
                delayAfter = 0,
                waitRoomId = nil,
                executeRoomId = tostring(stepSourceRoom or "-1"),
            }
        end

        if stepHasWait then
            flushCardinals()
            if #currentGroup.commands > 0 then
                table.insert(groups, currentGroup)
                currentGroup = {commands = {}, delayAfter = 0, waitRoomId = nil, executeRoomId = nil, trustedSource = false}
            end
        end

		for _, dir in ipairs(parts) do
			local dirLower = dir:lower()
			local walktoTarget = mm and mm.mapper_walkto_target and mm.mapper_walkto_target(dir) or nil

			-- Check if this is a wait() command
			local waitTime = dir:match("^wait%((%d+%.?%d*)%)$")
				if waitTime then
					flushCardinals()
					currentGroup.delayAfter = tonumber(waitTime)
                if not currentGroup.waitRoomId or currentGroup.waitRoomId == "-1" then
                    currentGroup.waitRoomId = tostring(stepSourceRoom or "-1")
                end
					table.insert(groups, currentGroup)
					currentGroup = {commands = {}, delayAfter = 0, waitRoomId = nil, executeRoomId = nil, trustedSource = false}
                    encounteredWait = true

			elseif cardinalDirs[dirLower] then
				-- cardinal movement token (n/s/e/w/u/d)
				table.insert(cardinalBuffer, dirLower)

                elseif walktoTarget then
                    -- A nested mapper walk starts its own asynchronous path.
                    -- End this group at the walk command and hold everything
                    -- after it until GMCP confirms the requested room.
					flushCardinals()
                    walktoTarget = tostring(walktoTarget)
                    table.insert(currentGroup.commands, {
                        text = dir,
                        embeddedWalkTarget = walktoTarget,
                    })
                    table.insert(groups, currentGroup)
                    currentGroup = {
                        commands = {},
                        delayAfter = 0,
                        waitRoomId = nil,
                        executeRoomId = walktoTarget,
                        trustedSource = false,
                    }

                else
                    -- normal command token (e.g. "open d", "kill hidden", "o n", "enter")
					flushCardinals()
                    if stepHasWait and (not encounteredWait)
                        and (not currentGroup.executeRoomId or currentGroup.executeRoomId == "-1") then
                        currentGroup.executeRoomId = tostring(stepSourceRoom or "-1")
                    end
                    if stepHasWait and (not encounteredWait) then
                        local verb, args = tostring(dir):match("^(%S+)%s+(.+)$")
                        local v = tostring(verb or ""):lower()
                        if (v == "k" or v == "ki" or v == "kil" or v == "kill")
                            and (not currentGroup.killTargetToken or currentGroup.killTargetToken == "")
                        then
                            local token = tostring(args or ""):match("^%s*(%S+)")
                            if token and token ~= "" then
                                currentGroup.killTargetToken = token:lower()
                            end
                        end
                    end
                table.insert(currentGroup.commands, {
                    text = dir,
                    travelType = step.travelType,
                    sourceRoom = stepSourceRoom,
                })
			end
        end
        local hasKnownLanding = step.uid ~= nil
            and tostring(step.uid) ~= ""
            and tostring(step.uid) ~= "-1"
        if hasKnownLanding then
            simulatedRoom = tostring(step.uid)
        end

        -- A mapped cardinal/cexit is a trusted graph edge. The next command can
        -- be queued against its recorded destination without waiting for GMCP.
        -- Nested mapper walkto remains asynchronous and keeps its explicit room
        -- barrier.
        if hasKnownLanding and not isTravelStep and not stepHasMapperWalkto then
            currentGroup.trustedSource = true
        end

        -- A registered recall/portal edge tells us where the jump should land,
        -- not whether the MUD accepted it. Hold every suffix until live GMCP
        -- confirms the expected room; a blocked-travel trigger invalidates the
        -- execution serial and prevents that suffix from ever being released.
        if isTravelStep then
            flushCardinals()
            if #currentGroup.commands > 0 then
                table.insert(groups, currentGroup)
            end
            currentGroup = {
                commands = {},
                delayAfter = 0,
                waitRoomId = nil,
                executeRoomId = tostring(simulatedRoom or "-1"),
                trustedSource = false,
            }
        end
	end

    
    -- Flush remaining cardinals and add final group
    flushCardinals()
    if #currentGroup.commands > 0 then
        table.insert(groups, currentGroup)
    end
    
    -- Execute groups with proper timing
    if #groups == 0 then
        snd.mapper.pathExecutionActive = false
        snd.mapper.pathExecutionHasPendingGroups = false
        snd.mapper.goingToRoom = nil
        snd.nav.goingToRoom = nil
        snd.mapper.notifyBigmapNavigationState("empty_path")
        return
    end

    local function sendCommand(cmd, travelType, embeddedWalkTarget, plannedSourceRoom)
        local currentRoom = snd.mapper.currentRoomUid(true)
        if (travelType == "portal" or travelType == "recall") and snd.mapper.isInCombat and snd.mapper.isInCombat() then
            snd.mapper.consumeRestrictionMark("portal")
            snd.mapper.consumeRestrictionMark("recall")
            snd.utils.infoNote("In combat (state=8). Stopping xrt before " .. travelType .. ".")
            snd.mapper.goingToRoom = nil
            snd.nav.goingToRoom = nil
            snd.mapper.notifyBigmapNavigationState("combat_abort")
            return false
        end
        local restrictionRoom = plannedSourceRoom or currentRoom
        if travelType and restrictionRoom and tostring(restrictionRoom) ~= "-1" then
            snd.mapper.queueRestrictionMark(travelType, restrictionRoom)
        end

        if travelType == "portal" and mm and mm.portal_usage
            and mm.portal_usage.note_mapper_portal_command then
            mm.portal_usage.note_mapper_portal_command(cmd)
        end

        if embeddedWalkTarget then
            local ok = snd.mapper.walkTo(tostring(embeddedWalkTarget), {embedded = true})
            if not ok then
                snd.utils.infoNote("Stopping path: embedded mapper walkto failed for room " .. tostring(embeddedWalkTarget) .. ".")
                snd.mapper.goingToRoom = nil
                snd.nav.goingToRoom = nil
                snd.mapper.notifyBigmapNavigationState("embedded_walk_failed")
                return false
            end
            return true
        end

        if type(expandAlias) == "function" then
            expandAlias(cmd)
        else
            send(cmd, false)
        end
        return true
    end

    local function sendCommands(commands)
        for _, entry in ipairs(commands) do
            local ok = sendCommand(entry.text, entry.travelType, entry.embeddedWalkTarget, entry.sourceRoom)
            if ok == false then
                return false
            end
        end
        return true
    end
    
    -- Execute path groups sequentially so wait() never races ahead of queued actions.
    -- If a wait expires while in combat, hold execution until combat clears.
    local heldGroupNotices = {}
    local function finishRandomCexit()
        snd.mapper.pathExecutionSerial = (tonumber(snd.mapper.pathExecutionSerial) or executionSerial) + 1
        snd.mapper.pathExecutionActive = false
        snd.mapper.pathExecutionHasPendingGroups = false
        snd.mapper.goingToRoom = nil
        snd.nav.goingToRoom = nil
        if snd.conwin and type(snd.conwin.cancelTravel) == "function" then
            snd.conwin.cancelTravel()
        end
        snd.mapper.notifyBigmapNavigationState("random_cexit_terminal")
    end

    local function runFrom(startIndex)
        if not isExecutionCurrent() then
            return
        end
        local index = startIndex
        while true do
            if not isExecutionCurrent() then
                return
            end
            local grp = groups[index]
            if not grp then
                snd.mapper.pathExecutionHasPendingGroups = false
                return
            end

            -- True means another client-side command group still has to be
            -- released. State 3 between groups is not a genuine travel stop.
            snd.mapper.pathExecutionHasPendingGroups = index < #groups

            if snd.mapper.canSendCommands and not snd.mapper.canSendCommands() then
                tempTimer(0.25, function()
                    if not isExecutionCurrent() then return end
                    runFrom(index)
                end)
                return
            end

            local executeRoomId = tostring(grp.executeRoomId or "-1")
            if executeRoomId ~= "" and executeRoomId ~= "-1" then
                local currentRoomId = getCurrentRoomId()
                if currentRoomId ~= executeRoomId then
                    local noticeKey = tostring(index) .. ":" .. executeRoomId
                    if not heldGroupNotices[noticeKey] then
                        heldGroupNotices[noticeKey] = true
                        snd.utils.debugNote("Holding group until room " .. executeRoomId .. " (current " .. tostring(currentRoomId) .. ").")
                    end
                    tempTimer(0.1, function()
                        if not isExecutionCurrent() then return end
                        runFrom(index)
                    end)
                    return
                end
            end

            if #grp.commands > 0 then
                local cmdTexts = {}
                for _, entry in ipairs(grp.commands) do
                    table.insert(cmdTexts, entry.text)
                end
                local cmdString = table.concat(cmdTexts, ";;")
                cecho("<dim_gray>[S&D Path] " .. cmdString .. "<reset>\n")
                local ok = sendCommands(grp.commands)
                if ok == false then
                    return
                end
            end

            if grp.terminalRandomCexit then
                finishRandomCexit()
                return
            end

            if grp.delayAfter > 0 then
                cecho(string.format("<dim_gray>[S&D Path] Waiting %.1f seconds...<reset>\n", grp.delayAfter))
                local function beginWaitTimer()
                    if not isExecutionCurrent() then return end
                    local nextIndex = index + 1
                    local delaySeconds = tonumber(grp.delayAfter) or 0
                    local observedTarget = false
                    local killToken = tostring(grp.killTargetToken or "")
                    local advanced = false
                    local statusHandlerId = nil

                    local function clearStatusHandler()
                        if statusHandlerId then
                            killAnonymousEventHandler(statusHandlerId)
                            statusHandlerId = nil
                        end
                    end

                    local function advance(reason)
                        if advanced then return end
                        advanced = true
                        clearStatusHandler()
                        if reason then snd.utils.debugNote(reason) end
                        runFrom(nextIndex)
                    end

                    local function isInCombatNow()
                        return snd.mapper.isInCombat and snd.mapper.isInCombat()
                    end

                    -- Early-exit listener: if this group followed a kill command
                    -- and we observed the enemy enter and leave combat, advance
                    -- the moment the gmcp.char.status event reports state != 8.
                    -- The handler is a no-op for non-combat waits (no kill
                    -- token), so those always run their full duration.
                    if killToken ~= "" then
                        local function onCharStatus()
                            if advanced then return end
                            if not isExecutionCurrent() then
                                clearStatusHandler()
                                return
                            end
                            if enemyMatchesToken(killToken) then
                                observedTarget = true
                            end
                            if observedTarget and not isInCombatNow()
                                and not enemyMatchesToken(killToken)
                            then
                                advance("wait() ended early: combat cleared before timeout.")
                            end
                        end
                        statusHandlerId = registerAnonymousEventHandler("gmcp.char.status", onCharStatus)
                        -- Catch a transition that already happened between sending
                        -- the kill and registering the handler.
                        onCharStatus()
                    end

                    -- Countdown timer: when the user's wait() expires, advance
                    -- unconditionally. Combat state is irrelevant at this point.
                    tempTimer(delaySeconds, function()
                        if advanced then return end
                        if not isExecutionCurrent() then
                            clearStatusHandler()
                            return
                        end
                        advance(nil)
                    end)
                end

                -- User intent: once wait() is reached/sent, the countdown must
                -- start immediately and release the next path group exactly when
                -- it expires, regardless of room/combat state.
                beginWaitTimer()
                return
            end

            index = index + 1
        end
    end

    runFrom(1)
end

-- Build the route used by gotoRoom. Ordinary navigation performs one combined
-- shortest-path search; restricted-room recovery follows the explicit nearby
-- then area-start hierarchy. This function only plans and never sends commands.
function snd.mapper.planNavigationRoute(currentRoom, roomId, usePortals, ignoreLockedExits)
    currentRoom = tostring(currentRoom or "")
    roomId = tostring(roomId or "")
    usePortals = (usePortals ~= false)

    local noPortals = not usePortals or not snd.mapper.config.usePortals
    local noRecalls = not snd.mapper.config.useRecall
    local sourceInfo = snd.mapper.getRoomInfo(currentRoom)
    local destinationInfo = snd.mapper.getRoomInfo(roomId)
    local sourceAreaValue = sourceInfo and sourceInfo.area
        or (snd.room and snd.room.current and snd.room.current.arid)
        or ""
    local sourceArea = snd.utils.trim(sourceAreaValue):lower()
    local destinationArea = destinationInfo and snd.utils.trim(destinationInfo.area or ""):lower() or ""
    local crossingAreas = sourceArea ~= "" and destinationArea ~= "" and sourceArea ~= destinationArea
    local currentNoPortal = sourceInfo and tonumber(sourceInfo.noportal) == 1 or false
    local currentNoRecall = sourceInfo and tonumber(sourceInfo.norecall) == 1 or false
    local nearbyRadius = tonumber(snd.mapper.config.nearbyJumpRadius) or 10

    local function details(areaGuardPlan, candidate)
        return {
            areaGuardPlan = areaGuardPlan or {active = false, directSafe = false},
            candidates = candidate and {candidate} or {},
            depth = candidate and (candidate.depth or #candidate.path) or nil,
            noPortals = noPortals,
            noRecalls = noRecalls,
            sourceArea = sourceArea,
        }
    end

    -- A room with both restrictions follows a strict recovery ladder. Do not
    -- calculate a global walking route until the bounded nearby search and the
    -- source-area start have both failed.
    if usePortals and currentNoPortal and currentNoRecall then
        local outwardPath, outwardType, outwardRoom = snd.mapper.buildOutwardJumpRoute(
            currentRoom,
            roomId,
            ignoreLockedExits,
            {
                allowPortals = not noPortals,
                allowRecalls = not noRecalls,
                searchDepthLimit = nearbyRadius,
            }
        )
        if outwardPath and #outwardPath > 0 then
            local nearbyCandidate = {
                kind = "nearby_" .. tostring(outwardType or "jump"),
                path = outwardPath,
                viaRoom = outwardRoom,
            }
            snd.utils.debugNote(string.format(
                "Selected nearby jump room %s within radius %d (%d steps).",
                tostring(outwardRoom or "?"),
                nearbyRadius,
                #outwardPath
            ))
            return nearbyCandidate, details(nil, nearbyCandidate)
        end

        if crossingAreas then
            local areaPath, areaKey, startRoom, jumpType = snd.mapper.buildAreaStartFallbackRoute(
                currentRoom,
                roomId,
                nil,
                ignoreLockedExits,
                {
                    allowPortals = not noPortals,
                    allowRecalls = not noRecalls,
                    nearbyJumpRadius = nearbyRadius,
                }
            )
            if areaPath and #areaPath > 0 then
                local areaCandidate = {
                    kind = "area_start_" .. tostring(jumpType or "jump"),
                    path = areaPath,
                    areaKey = areaKey,
                    startRoom = startRoom,
                }
                snd.utils.debugNote(string.format(
                    "Nearby jump radius exhausted; selected %s start room %s (%d steps).",
                    tostring(areaKey or sourceArea or "area"),
                    tostring(startRoom or "?"),
                    #areaPath
                ))
                return areaCandidate, details(nil, areaCandidate)
            end
        end

        local walkingPath, walkingDepth = snd.mapper.findPath(
            currentRoom,
            roomId,
            true,
            true,
            ignoreLockedExits,
            nil,
            nil,
            nil,
            "walk"
        )
        local walkingCandidate = walkingPath and #walkingPath > 0 and {
            kind = "walk_last_resort",
            path = walkingPath,
            depth = walkingDepth,
        } or nil
        return walkingCandidate, details(nil, walkingCandidate)
    end

    -- Ordinary xrt performs one combined shortest-path search. Walking is not
    -- searched separately; findPath itself prefers it only on an equal-depth tie.
    local areaGuardPlan = snd.mapper.planAreaGuardRoute(
        currentRoom,
        roomId,
        noPortals,
        noRecalls,
        ignoreLockedExits
    )
    local directAreaSafe = areaGuardPlan.active
        and areaGuardPlan.directSafe
        and areaGuardPlan.candidate
    local path, depth, selectedRoute
    if directAreaSafe then
        selectedRoute = areaGuardPlan.candidate
        path = selectedRoute.path
        depth = selectedRoute.depth
    else
        path, depth = snd.mapper.findPath(
            currentRoom,
            roomId,
            noPortals,
            noRecalls,
            ignoreLockedExits
        )
        -- If the globally shortest jump was blocked and no configured bounce
        -- could repair it, retry only the other jump that is legal in this room.
        -- This is not a walking comparison and never invokes nearby recovery.
        if (not path or #path == 0) and usePortals then
            if currentNoRecall and not currentNoPortal and not noPortals then
                path, depth = snd.mapper.findPath(
                    currentRoom,
                    roomId,
                    false,
                    true,
                    ignoreLockedExits,
                    nil,
                    nil,
                    nil,
                    "portal"
                )
            elseif currentNoPortal and not currentNoRecall and not noRecalls then
                path, depth = snd.mapper.findPath(
                    currentRoom,
                    roomId,
                    true,
                    false,
                    ignoreLockedExits,
                    nil,
                    nil,
                    nil,
                    "recall"
                )
            end
        end
        if path and #path > 0 then
            selectedRoute = {kind = "normal", path = path, depth = depth}
        end
    end

    local normalBypassesStart = path and snd.mapper.pathLeavesAreaBeforeJump(path, sourceArea) or false
    -- An immediate portal/recall never reaches this branch. If the only normal
    -- result walks out of the source area before jumping, try the designated
    -- start first; only use the long walking route when that fallback fails.
    if usePortals and crossingAreas and (not path or normalBypassesStart) then
        local areaPath, areaKey, startRoom, jumpType = snd.mapper.buildAreaStartFallbackRoute(
            currentRoom,
            roomId,
            nil,
            ignoreLockedExits,
            {
                allowPortals = not noPortals,
                allowRecalls = not noRecalls,
                nearbyJumpRadius = nearbyRadius,
            }
        )
        if areaPath and #areaPath > 0 then
            selectedRoute = {
                kind = "area_start_" .. tostring(jumpType or "jump"),
                path = areaPath,
                areaKey = areaKey,
                startRoom = startRoom,
            }
            path = areaPath
            depth = #areaPath
        end
    end

    if selectedRoute then
        if selectedRoute.kind == "direct_area_safe" then
            snd.utils.debugNote("Area guard selected the unchanged safe direct path with " .. #path .. " steps.")
        elseif selectedRoute.kind == "direct_clan_exempt" then
            snd.utils.debugNote("Area guard selected the shortest safe route with local clan-room exemptions (" .. #path .. " steps).")
        elseif selectedRoute.kind == "normal" then
            snd.utils.debugNote("Selected normal shortest path with " .. #path .. " steps.")
        else
            snd.utils.debugNote(string.format(
                "Selected %s start room %s before a cross-area walking route (%d steps).",
                tostring(selectedRoute.areaKey or sourceArea or "area"),
                tostring(selectedRoute.startRoom or "?"),
                #path
            ))
        end
    end

    return selectedRoute, details(areaGuardPlan, selectedRoute)
end

-- Preview gotoRoom's route with AreaGuard forced on for this calculation only.
-- Per-portal guards, locked exits, and portal/recall settings remain exactly as
-- they are for normal xrt navigation.
function snd.mapper.previewGuardedRoute(currentRoom, roomId, usePortals)
    local source = tostring(currentRoom or "")
    local destination = tostring(roomId or "")

    return snd.mapper.withAreaGuardForced(function()
        local destinationGuard = snd.mapper.evaluateRoomAreaGuard(destination)
        local destinationIsClan = snd.mapper.isClanArea(destinationGuard.mapperArea)
        if destinationGuard.known and not destinationGuard.allowed and not destinationIsClan then
            return nil, {
                reason = "destination_blocked",
                destinationGuard = destinationGuard,
            }
        end

        local selectedRoute, details = snd.mapper.planNavigationRoute(
            source,
            destination,
            usePortals,
            false
        )
        details = details or {}
        details.destinationGuard = destinationGuard
        if not selectedRoute then
            local rawPlan = details.areaGuardPlan
            details.reason = rawPlan and rawPlan.directPath
                and "area_guard_route_blocked"
                or "path_not_found"
            return nil, details
        end

        details.reason = "ok"
        return selectedRoute, details
    end)
end

--- Go to a room using portal-aware pathfinding
-- @param roomId Destination room uid
-- @param usePortals Whether to use portals (default: true)
-- @param guardDestination Original xrt destination for area-guard override links
function snd.mapper.gotoRoom(roomId, usePortals, ignoreLockedExits, iterativeMode, guardDestination, options)
    if not roomId then
        snd.utils.infoNote("No room specified")
        return false
    end
    
    roomId = tostring(roomId)
    usePortals = (usePortals ~= false)  -- Default true
    iterativeMode = (iterativeMode == true)
    options = type(options) == "table" and options or {}
    snd.mapper.lastRouteFailure = nil

    -- Get current room
    local currentRoom = snd.mapper.currentRoomUid(true)

    if not currentRoom or currentRoom == "-1" then
        snd.utils.infoNote("Current room unknown. Try 'look' first.")
        return false
    end

    if currentRoom:match("^nomap_") then
        -- Clan room: allow navigation only when cexit exits have been mapped from here.
        local hasClanExits = false
        if snd.mapper.db.open() then
            local rows = snd.mapper.db.query(string.format(
                "SELECT COUNT(*) AS cnt FROM exits WHERE fromuid = %s",
                snd.mapper.db.escape(currentRoom)
            )) or {}
            hasClanExits = rows[1] and (tonumber(rows[1].cnt) or 0) > 0
        end
        if not hasClanExits then
            snd.utils.infoNote("In a clan room with no mapped exits. Use 'mapper cexit <cmd>' to map one first.")
            return false
        end
    end

    if currentRoom == roomId then
        snd.mapper.goingToRoom = nil
        snd.nav.goingToRoom = nil
        snd.mapper.notifyBigmapNavigationState("already_at_destination")
        if snd.commands and snd.commands.handleAlreadyInRoom and snd.commands.handleAlreadyInRoom(roomId) then
            return true
        end

        snd.utils.infoNote("Already in room " .. roomId)
        if snd.onDestinationArrived then
            snd.onDestinationArrived()
        end
        return true
    end

    if not snd.mapper.checkAreaGuardDestination(
        currentRoom,
        roomId,
        guardDestination or roomId,
        ignoreLockedExits,
        false
    ) then
        snd.mapper.goingToRoom = nil
        snd.nav.goingToRoom = nil
        snd.mapper.notifyBigmapNavigationState("area_guard_rejected")
        local failure = {code = "area_guard_rejected", targetRoom = roomId}
        snd.mapper.lastRouteFailure = failure
        return false, failure
    end

    local pendingBlocked = snd.mapper.pendingBlockedTravel
    if pendingBlocked
        and tostring(pendingBlocked.destination or "") == roomId
        and tostring(pendingBlocked.roomId or "") == tostring(currentRoom)
        and (pendingBlocked.blockedType == "portal" or pendingBlocked.blockedType == "recall")
    then
        snd.utils.debugNote("pending blocked travel matched; attempting blocked reroute from room " .. tostring(currentRoom) .. " to " .. tostring(roomId) .. ".")
        snd.mapper.goingToRoom = roomId
        snd.nav.goingToRoom = roomId
        snd.mapper.pendingBlockedTravel = nil
        if snd.mapper.handleBlockedTravel(pendingBlocked.blockedType, ignoreLockedExits) then
            return true
        end
    elseif pendingBlocked and tostring(pendingBlocked.destination or "") == roomId then
        snd.utils.debugNote("pending blocked travel cleared (room mismatch). current=" .. tostring(currentRoom) .. " expected=" .. tostring(pendingBlocked.roomId or "?"))
        snd.mapper.pendingBlockedTravel = nil
    end
    
    local selectedRoute, routePlan = snd.mapper.planNavigationRoute(
        currentRoom,
        roomId,
        usePortals,
        ignoreLockedExits
    )
    routePlan = routePlan or {}
    local path = selectedRoute and selectedRoute.path or nil
    local depth = selectedRoute and (selectedRoute.depth or #path) or nil
    local noPortals = routePlan.noPortals
    local noRecalls = routePlan.noRecalls

    if path and #path > 0 then
        snd.utils.debugNote("Found path with " .. #path .. " steps (depth " .. depth .. ")")

        -- Store destination for arrival detection
        snd.mapper.goingToRoom = roomId
        snd.nav.goingToRoom = roomId

        -- Execute full path or one adaptive step (xrt iterative mode)
        if iterativeMode then
            local closestPortalRoom, portalWalk = snd.mapper.findNearestRoomWithoutFlag(currentRoom, "noportal", ignoreLockedExits)
            local closestRecallRoom, recallWalk = snd.mapper.findNearestRoomWithoutFlag(currentRoom, "norecall", ignoreLockedExits)
            snd.utils.debugNote(string.format(
                "xrt iterative: room=%s noportal-nearest=%s(%s) norecall-nearest=%s(%s) pathSteps=%d",
                tostring(currentRoom),
                tostring(closestPortalRoom or "none"),
                tostring(portalWalk and #portalWalk or -1),
                tostring(closestRecallRoom or "none"),
                tostring(recallWalk and #recallWalk or -1),
                #path
            ))

            local step = path[1]
            snd.utils.debugNote("xrt iterative: taking next step '" .. tostring(step and step.dir or "?") .. "'")
            if step then
                snd.mapper.executePath({step})
                local expectedRoom = tostring(currentRoom)
                local function continueIterative(attempt)
                    tempTimer(0.6, function()
                        if tostring(snd.mapper.goingToRoom or "") ~= roomId then
                            return
                        end
                        local nowRoom = snd.mapper.currentRoomUid(true)
                        nowRoom = tostring(nowRoom or "")
                        if nowRoom ~= "" and nowRoom ~= "-1" and nowRoom ~= expectedRoom then
                            snd.mapper.gotoRoom(roomId, usePortals, ignoreLockedExits, true, guardDestination, options)
                            return
                        end
                        if attempt < 2 then
                            snd.utils.debugNote("xrt iterative: room did not change after step; waiting before recompute (attempt " .. tostring(attempt + 1) .. ").")
                            continueIterative(attempt + 1)
                        else
                            snd.utils.infoNote("xrt iterative stopped: room did not change after command '" .. tostring(step.dir or "?") .. "'.")
                            snd.mapper.goingToRoom = nil
                            snd.nav.goingToRoom = nil
                            snd.mapper.notifyBigmapNavigationState("iterative_timeout")
                        end
                    end)
                end
                continueIterative(0)
                return true
            end
        end

        snd.mapper.executePath(path)
        return true
    else
        if snd.mapper.areaGuardEnabled() and not ignoreLockedExits then
            local unguardedPath = snd.mapper.findPath(
                currentRoom,
                roomId,
                noPortals,
                noRecalls,
                ignoreLockedExits,
                true
            )
            if unguardedPath and #unguardedPath > 0 then
                snd.utils.debugNote(string.format(
                    "Area guard rejected all routes to room %s; unguarded route has %d steps.",
                    tostring(roomId),
                    #unguardedPath
                ))
                snd.mapper.reportAreaGuardRouteBlocked(guardDestination or roomId)
                snd.mapper.goingToRoom = nil
                snd.nav.goingToRoom = nil
                snd.mapper.notifyBigmapNavigationState("area_guard_route_blocked")
                return false
            end
            snd.utils.debugNote("Area guard route retry found no unguarded route either.")
        end

        local failure = {
            code = "path_not_found",
            targetRoom = roomId,
            sourceRoom = tostring(currentRoom),
        }
        local chaosPath, chaosDepth
        if type(snd.mapper.findGqChaosDiagnosticPath) == "function" then
            chaosPath, chaosDepth = snd.mapper.findGqChaosDiagnosticPath(
                currentRoom,
                roomId,
                noPortals,
                noRecalls,
                ignoreLockedExits,
                false
            )
        end
        if chaosPath and #chaosPath > 0 then
            failure.code = "gq_chaos_portal_disabled"
            failure.chaosPathLength = #chaosPath
            failure.chaosPathDepth = tonumber(chaosDepth) or #chaosPath
        end
        snd.mapper.lastRouteFailure = failure

        if options.quietFailure ~= true then
            if failure.code == "gq_chaos_portal_disabled" then
                snd.utils.infoNote(
                    "No GQ-safe route to room " .. roomId
                    .. ". A route exists through a chaos portal, but chaos portals are disabled during GQ."
                )
            else
                snd.utils.infoNote("You couldn't find a path to " .. roomId .. " from here.")
            end
        end
        snd.mapper.goingToRoom = nil
        snd.nav.goingToRoom = nil
        snd.mapper.notifyBigmapNavigationState("path_not_found")

        local offeredManualApproach = false
        if snd.commands and type(snd.commands.offerManualApproach) == "function" then
            local ok, offered = pcall(snd.commands.offerManualApproach, roomId)
            offeredManualApproach = ok and offered == true
            if not ok then
                snd.utils.debugNote("Manual approach display failed: " .. tostring(offered))
            end
        end
        if offeredManualApproach then
            return false, failure
        end

        if snd.commands and type(snd.commands.fallbackToTargetAreaStart) == "function" then
            local ok, handled = pcall(snd.commands.fallbackToTargetAreaStart, roomId)
            if ok and handled == true then
                snd.mapper.lastRouteFailure = nil
                return true
            elseif not ok then
                snd.utils.debugNote("Target area-start fallback failed: " .. tostring(handled))
            end
        end

        local pendingAreaFallback = snd.nav and snd.nav.targetAreaFallback or nil
        local isFailedAreaStart = pendingAreaFallback
            and tostring(pendingAreaFallback.destinationRoom or "") == roomId
        if options.suppressXrtNear ~= true
            and failure.code ~= "gq_chaos_portal_disabled"
            and not isFailedAreaStart
        then
            snd.utils.infoNote("Try 'xrtnear " .. roomId .. "' to list reachable boundary rooms. The lookup may take a moment.")
        end
        return false, failure
    end
end

--- Go to current target's area/room
function snd.mapper.gotoTarget()
    if not snd.targets.current then
        snd.utils.infoNote("No target selected")
        return false
    end
    
    local target = snd.targets.current
    
    -- If we have a specific room, go there
    if target.roomId and target.roomId ~= "" then
        return snd.mapper.gotoRoom(target.roomId)
    end
    
    -- If we have an area, go to area start room
    local areaKey = target.area or target.arid
    if areaKey and areaKey ~= "" then
        -- Look up start room from snd.data
        local areaData = snd.data.areaDefaultStartRooms[areaKey]
        if areaData and areaData.start then
            snd.utils.infoNote("Going to " .. areaKey .. " (room " .. areaData.start .. ")")
            return snd.mapper.gotoRoom(areaData.start)
        end
        
        -- Try database lookup
        if snd.db and snd.db.getAreaStartRoom then
            local startRoom = snd.db.getAreaStartRoom(areaKey)
            if startRoom and startRoom > 0 then
                snd.utils.infoNote("Going to " .. areaKey .. " (room " .. startRoom .. ")")
                return snd.mapper.gotoRoom(startRoom)
            end
        end
        
        snd.utils.infoNote("No start room found for area: " .. areaKey)
        return false
    end
    
    snd.utils.infoNote("Target has no room or area information")
    return false
end

-------------------------------------------------------------------------------
-- Utility Commands
-------------------------------------------------------------------------------

--- List available portals
function snd.mapper.listPortals(filter)
    if not snd.mapper.db.open() then
        snd.utils.errorNote("Cannot open mapper database")
        return
    end
    
    local portals = snd.mapper.getPortals(filter)
    
    if #portals == 0 then
        snd.utils.infoNote("No portals found in database")
        cecho("\n<dim_gray>Portals are stored in Aardwolf.db exits table with fromuid='*' or '**'\n")
        cecho("Use 'snd portal <command>' to add a portal to current room<reset>\n")
        return
    end
    
    cecho("\n<yellow>═══ Mapper Portals ═══<reset>\n")
    
    for i, portal in ipairs(portals) do
        local ptype = portal.fromuid == "*" and "Portal" or "Recall"
        local cmdColor = (portal.fromuid == "**") and "light_sky_blue" or "green"
        local isBounce = ""
        if snd.mapper.config.bouncePortal and portal.dir == snd.mapper.config.bouncePortal.dir then
            isBounce = " <magenta>[BOUNCE]<reset>"
        elseif snd.mapper.config.bounceRecall and portal.dir == snd.mapper.config.bounceRecall.dir then
            isBounce = " <magenta>[BOUNCE]<reset>"
        end
        
        cecho(string.format("  <cyan>%2d.<reset> [%s] <%s>%s<reset> -> %s (%s)%s\n",
            i, ptype, cmdColor, portal.dir, portal.name or "?", portal.area or "?", isBounce))
    end
    
    cecho("<yellow>═══════════════════════<reset>\n")
    cecho("<dim_gray>Commands: mapper portal <cmd> level <n> | mapper bounceportal <#|cmd><reset>\n")
end

--- Search portals relative to current location
-- @param scope "here" (current room) or "area" (current room area)
function snd.mapper.searchPortals(scope)
    scope = snd.utils.trim((scope or "here"):lower())
    if scope ~= "here" and scope ~= "area" then
        snd.utils.infoNote("Usage: mapper searchportal <here|area>")
        return
    end

    local currentRoom = snd.room and snd.room.current and snd.room.current.rmid
    if not currentRoom or currentRoom == "-1" then
        snd.utils.errorNote("Current room unknown. Try 'look' first.")
        return
    end

    if not snd.mapper.db.open() then
        snd.utils.errorNote("Cannot open mapper database")
        return
    end

    local query
    if scope == "here" then
        query = string.format([[
            SELECT e.dir, e.fromuid, e.touid, e.level, r.name, r.area
            FROM exits e
            LEFT JOIN rooms r ON r.uid = e.touid
            WHERE (e.fromuid = '*' OR e.fromuid = '**')
              AND e.touid = %s
            ORDER BY e.dir
        ]], snd.mapper.db.escape(tostring(currentRoom)))
    else
        local areaInfo = snd.mapper.getRoomInfo(currentRoom)
        if not areaInfo or not areaInfo.area or areaInfo.area == "" then
            snd.utils.errorNote("Could not determine current area for room " .. tostring(currentRoom))
            return
        end
        query = string.format([[
            SELECT e.dir, e.fromuid, e.touid, e.level, r.name, r.area
            FROM exits e
            LEFT JOIN rooms r ON r.uid = e.touid
            WHERE (e.fromuid = '*' OR e.fromuid = '**')
              AND r.area = %s
            ORDER BY e.dir
        ]], snd.mapper.db.escape(areaInfo.area))
    end

    local rows = snd.mapper.db.query(query) or {}
    if #rows == 0 then
        snd.utils.infoNote(string.format("No portals found for '%s'.", scope))
        return
    end

    cecho(string.format("\n<yellow>═══ Portal Search (%s) ═══<reset>\n", scope))
    for i, portal in ipairs(rows) do
        local ptype = portal.fromuid == "**" and "Recall" or "Portal"
        cecho(string.format(
            "  <cyan>%2d.<reset> [%s] <green>%s<reset> -> %s (%s) <dim_gray>[lvl:%s uid:%s]<reset>\n",
            i,
            ptype,
            tostring(portal.dir or "?"),
            tostring(portal.name or "?"),
            tostring(portal.area or "?"),
            tostring(portal.level or 0),
            tostring(portal.touid or "?")
        ))
    end
    cecho("<yellow>══════════════════════════════<reset>\n")
end

--- Add a portal to current room
-- @param command Portal command (e.g., "hold amulet;enter")
-- @param level Optional minimum level (default 0)
function snd.mapper.addPortal(command, level)
    if not command or command == "" then
        snd.utils.infoNote("Usage: mapper portal <command> level <number>")
        return false
    end
    
    level = tonumber(level) or 0
    
    local currentRoom = snd.room.current.rmid
    if not currentRoom or currentRoom == "-1" then
        snd.utils.errorNote("Current room unknown. Try 'look' first.")
        return false
    end
    
    if not snd.mapper.db.open() then
        snd.utils.errorNote("Cannot open mapper database")
        return false
    end
    
    -- Check if room exists in database
    local roomInfo = snd.mapper.getRoomInfo(currentRoom)
    if not roomInfo then
        snd.utils.errorNote("Room " .. currentRoom .. " not found in mapper database")
        return false
    end
    
    -- Ensure special "from anywhere" room exists
    local sql = "SELECT uid FROM rooms WHERE uid = '*'"
    local result = snd.mapper.db.query(sql)
    if not result or #result == 0 then
        snd.mapper.db.conn:execute("INSERT OR REPLACE INTO rooms (uid, name, area) VALUES ('*', '___HERE___', '___EVERYWHERE___')")
    end
    
    -- Insert portal
    sql = string.format(
        "INSERT OR REPLACE INTO exits (dir, fromuid, touid, level) VALUES (%s, '*', %s, %d)",
        snd.mapper.db.escape(command),
        snd.mapper.db.escape(currentRoom),
        level
    )
    
    local success = snd.mapper.db.conn:execute(sql)
    if success then
        snd.utils.infoNote(string.format("Portal added: '%s' -> room %s (level %d)", command, currentRoom, level))
        return true
    else
        snd.utils.errorNote("Failed to add portal")
        return false
    end
end

--- Add a recall-based portal to current room
-- @param command Recall command (e.g., "recall" or "home")
-- @param level Optional minimum level (default 0)
function snd.mapper.addRecallPortal(command, level)
    if not command or command == "" then
        snd.utils.infoNote("Usage: mapper portal <command> level <number>")
        return false
    end
    
    level = tonumber(level) or 0
    
    local currentRoom = snd.room.current.rmid
    if not currentRoom or currentRoom == "-1" then
        snd.utils.errorNote("Current room unknown. Try 'look' first.")
        return false
    end
    
    if not snd.mapper.db.open() then
        snd.utils.errorNote("Cannot open mapper database")
        return false
    end
    
    -- Check if room exists
    local roomInfo = snd.mapper.getRoomInfo(currentRoom)
    if not roomInfo then
        snd.utils.errorNote("Room " .. currentRoom .. " not found in mapper database")
        return false
    end
    
    -- Ensure special "recall" room exists
    local sql = "SELECT uid FROM rooms WHERE uid = '**'"
    local result = snd.mapper.db.query(sql)
    if not result or #result == 0 then
        snd.mapper.db.conn:execute("INSERT OR REPLACE INTO rooms (uid, name, area) VALUES ('**', '___RECALL___', '___EVERYWHERE___')")
    end
    
    -- Insert recall portal
    sql = string.format(
        "INSERT OR REPLACE INTO exits (dir, fromuid, touid, level) VALUES (%s, '**', %s, %d)",
        snd.mapper.db.escape(command),
        snd.mapper.db.escape(currentRoom),
        level
    )
    
    local success = snd.mapper.db.conn:execute(sql)
    if success then
        snd.utils.infoNote(string.format("Recall portal added: '%s' -> room %s (level %d)", command, currentRoom, level))
        return true
    else
        snd.utils.errorNote("Failed to add recall portal")
        return false
    end
end

--- Delete a portal by index
-- @param index Portal index from listPortals
function snd.mapper.deletePortal(index)
    index = tonumber(index)
    if not index then
        snd.utils.infoNote("Usage: mapper delete portal #<index>")
        return false
    end
    
    local portals = snd.mapper.getPortals()
    if index < 1 or index > #portals then
        snd.utils.errorNote("Invalid portal index. Use 'snd portals' to see list.")
        return false
    end
    
    local portal = portals[index]
    local sql = string.format(
        "DELETE FROM exits WHERE dir = %s AND fromuid = %s AND touid = %s",
        snd.mapper.db.escape(portal.dir),
        snd.mapper.db.escape(portal.fromuid),
        snd.mapper.db.escape(portal.touid)
    )
    
    local success = snd.mapper.db.conn:execute(sql)
    if success then
        snd.utils.infoNote(string.format("Deleted portal #%d: %s", index, portal.dir))
        return true
    else
        snd.utils.errorNote("Failed to delete portal")
        return false
    end
end

--- Delete a portal by command string
-- @param command Portal command (exact match)
function snd.mapper.deletePortalByCommand(command)
    local portalCommand = snd.utils.trim(command or "")
    if portalCommand == "" then
        snd.utils.infoNote("Usage: mapper delete portal <command>")
        return false
    end

    if not snd.mapper.db.open() then
        snd.utils.errorNote("Cannot open mapper database")
        return false
    end

    local sql = string.format(
        "DELETE FROM exits WHERE dir = %s AND fromuid IN ('*', '**')",
        snd.mapper.db.escape(portalCommand)
    )

    local success, err = snd.mapper.db.conn:execute(sql)
    if not success then
        snd.utils.errorNote("Failed to delete portal '" .. portalCommand .. "': " .. tostring(err))
        return false
    end

    local deleted = tonumber(success) or 0
    if deleted < 1 then
        snd.utils.errorNote("Portal command not found: " .. portalCommand)
        return false
    end

    snd.utils.infoNote(string.format("Deleted %d portal entr%s for '%s'.", deleted, deleted == 1 and "y" or "ies", portalCommand))
    return true
end

--- Set bounce portal by index
-- @param index Portal index from listPortals
function snd.mapper.setBouncePortalByIndex(index)
    index = tonumber(index)
    if not index then
        snd.utils.infoNote("Usage: mapper bounceportal <index|command>")
        cecho("<dim_gray>Sets fallback portal for rooms that don't allow recall<reset>\n")
        return false
    end
    
    local portals = snd.mapper.getPortals()
    if index < 1 or index > #portals then
        snd.utils.errorNote("Invalid portal index. Use 'snd portals' to see list.")
        return false
    end
    
    local portal = portals[index]
    if portal.fromuid ~= "*" then
        snd.utils.errorNote("Portal #" .. index .. " is a recall portal. Bounce portal must be a regular portal (fromuid='*').")
        return false
    end
    
    snd.mapper.config.bouncePortal = {
        dir = portal.dir,
        uid = portal.touid,
        level = tonumber(portal.level) or 0,
        travelType = "portal"
    }
    snd.utils.infoNote("Bounce portal set to #" .. index .. ": " .. portal.dir)
    return true
end

--- Set bounce portal by command (regular portal only)
-- @param command Portal command
function snd.mapper.setBouncePortalByCommand(command)
    local portalCommand = snd.utils.trim(command or "")
    if portalCommand == "" then
        snd.utils.infoNote("Usage: mapper bounceportal <command>")
        return false
    end

    local portals = snd.mapper.getPortals()
    for i, portal in ipairs(portals) do
        if snd.utils.trim(portal.dir or "") == portalCommand then
            if portal.fromuid ~= "*" then
                snd.utils.errorNote("Portal '" .. portalCommand .. "' is a recall portal; choose a regular portal.")
                return false
            end
            snd.mapper.setBouncePortal(portal.dir, portal.touid, portal.level)
            snd.utils.infoNote("Bounce portal set to #" .. tostring(i) .. ": " .. portal.dir)
            return true
        end
    end

    snd.utils.errorNote("Portal command not found: " .. portalCommand)
    return false
end

--- Set bounce recall by index
-- @param index Portal index from listPortals
function snd.mapper.setBounceRecallByIndex(index)
    index = tonumber(index)
    if not index then
        snd.utils.infoNote("Usage: mapper bouncerecall <index>")
        cecho("<dim_gray>Sets fallback recall for rooms that don't allow portals<reset>\n")
        return false
    end
    
    local portals = snd.mapper.getPortals()
    if index < 1 or index > #portals then
        snd.utils.errorNote("Invalid portal index. Use 'snd portals' to see list.")
        return false
    end
    
    local portal = portals[index]
    if portal.fromuid ~= "**" then
        snd.utils.errorNote("Portal #" .. index .. " is not a recall portal. Bounce recall must be a recall portal (fromuid='**').")
        return false
    end
    
    snd.mapper.config.bounceRecall = {
        dir = portal.dir,
        uid = portal.touid,
        level = tonumber(portal.level) or 0,
        travelType = "recall"
    }
    snd.utils.infoNote("Bounce recall set to #" .. index .. ": " .. portal.dir)
    return true
end

--- Show navigation help (deprecated; use S&D help + mapper help)
function snd.mapper.help()
    cecho("\n<yellow>[MMAPPER]<reset> navhelp is deprecated.\n")
    cecho("<dim_gray>Use 'snd help' for xrt/xrtforce/walkto guidance, and 'mapper help' for mapper-owned portal/database commands.<reset>\n")
end

--- Show navigation database info
function snd.mapper.showDbInfo()
    cecho("\n<yellow>═══ Navigation Database Info ═══<reset>\n")
    
    cecho("  <cyan>Database path:<reset> " .. tostring(snd.mapper.db.file) .. "\n")
    cecho("  <cyan>Connection:<reset> " .. (snd.mapper.db.isOpen and "<green>Open" or "<red>Closed") .. "<reset>\n")
    
    if snd.mapper.db.open() then
        local result = snd.mapper.db.query("SELECT COUNT(*) as cnt FROM rooms")
        local rooms = result and result[1] and result[1].cnt or "?"
        
        result = snd.mapper.db.query("SELECT COUNT(*) as cnt FROM exits")
        local exits = result and result[1] and result[1].cnt or "?"
        
        result = snd.mapper.db.query("SELECT COUNT(*) as cnt FROM exits WHERE fromuid IN ('*', '**')")
        local portals = result and result[1] and result[1].cnt or "?"
        
        cecho("  <cyan>Rooms:<reset> " .. rooms .. "\n")
        cecho("  <cyan>Exits:<reset> " .. exits .. "\n")
        cecho("  <cyan>Portals:<reset> " .. portals .. "\n")
        
        if snd.mapper.config.bouncePortal then
            cecho("  <cyan>Bounce Portal:<reset> " .. snd.mapper.config.bouncePortal.dir .. "\n")
        end
        if snd.mapper.config.bounceRecall then
            cecho("  <cyan>Bounce Recall:<reset> " .. snd.mapper.config.bounceRecall.dir .. "\n")
        end
    end
    
    cecho("<yellow>════════════════════════════════<reset>\n")
end

--- Set database path manually
function snd.mapper.setMapperDb(path)
    snd.mapper.db.close()
    snd.mapper.db.file = path
    if snd.mapper.db.open() then
        if mm and mm.load_room_notes_cache then
            local loaded, load_err = mm.load_room_notes_cache()
            if not loaded then
                snd.utils.debugNote("Room-note cache reload failed after mapper DB switch: " .. tostring(load_err))
            end
        end
        snd.utils.infoNote("Mapper database set to: " .. path)
    end
end

-------------------------------------------------------------------------------
-- XRT Command - Quick Navigation
-------------------------------------------------------------------------------

function snd.mapper.debugXrtDecision(destInput, resolvedRoom, reason)
    if not (mm and mm.state and mm.state.debug) then
        return
    end

    local currentRoom = snd.room and snd.room.current and snd.room.current.rmid
    if (not currentRoom or currentRoom == "-1") and gmcp and gmcp.room and gmcp.room.info then
        currentRoom = mm.canonical_room_uid(gmcp.room.info)
    end
    currentRoom = tostring(currentRoom or "")

    local roomInfo = snd.mapper.getRoomInfo(currentRoom)
    local noportal = roomInfo and tonumber(roomInfo.noportal) == 1 or false
    local norecall = roomInfo and tonumber(roomInfo.norecall) == 1 or false

    local nearestGoodRoom, walkPath = snd.mapper.findNearestRoomWithoutBothFlags(currentRoom, nil)
    local walkSteps = walkPath and #walkPath or -1

    snd.utils.debugNote(string.format(
        "xrt decision: input='%s' resolvedRoom=%s reason=%s",
        tostring(destInput or ""),
        tostring(resolvedRoom or "?"),
        tostring(reason or "unknown")
    ))
    snd.utils.debugNote(string.format(
        "xrt source room=%s flags: noportal=%s norecall=%s",
        tostring(currentRoom ~= "" and currentRoom or "?"),
        tostring(noportal),
        tostring(norecall)
    ))
    if nearestGoodRoom then
        snd.utils.debugNote(string.format(
            "xrt nearest room without both flags: %s (walk steps=%d)",
            tostring(nearestGoodRoom),
            tonumber(walkSteps) or -1
        ))
    else
        snd.utils.debugNote("xrt nearest room without both flags: not found")
    end
end

--- Navigate to area or room by name/number
-- @param dest Destination - area name, partial name, or room number
function snd.mapper.xrt(dest, options)
    if not dest or dest == "" then
        cecho("<yellow>[MMAPPER]<reset> Usage: xrt <area|roomid>\n")
        cecho("<dim_gray>Examples: xrt aylor, xrt academy, xrt 32418<reset>\n")
        return false
    end
    
    options = type(options) == "table" and options or {}
    dest = dest:lower():trim()
    
    -- Check if it's a room number
    local roomNum = tonumber(dest)
    if roomNum then
        cecho("<yellow>[MMAPPER]<reset> Going to room " .. roomNum .. "\n")
        snd.mapper.debugXrtDecision(dest, roomNum, "numeric destination")
        return snd.mapper.gotoRoom(roomNum, nil, nil, nil, dest, options)
    end
    
    -- Try exact match on area key first (prefer snd.db startRoom data)
    if snd.db and snd.db.getAreaStartRoom then
        local startRoom = tonumber(snd.db.getAreaStartRoom(dest)) or -1
        if startRoom > 0 then
            cecho("<yellow>[MMAPPER]<reset> Going to " .. dest .. " (room " .. startRoom .. ")\n")
            snd.mapper.debugXrtDecision(dest, startRoom, "area start room from snd.db.getAreaStartRoom")
            return snd.mapper.gotoRoom(startRoom, nil, nil, nil, dest, options)
        end

        if snd.db.query then
            local areaRows = snd.db.query(string.format(
                "SELECT key, startRoom FROM area WHERE startRoom > 0 AND (key LIKE %s OR name LIKE %s) ORDER BY CASE WHEN key = %s THEN 0 ELSE 1 END, key LIMIT 1",
                snd.db.escape("%" .. dest .. "%"),
                snd.db.escape("%" .. dest .. "%"),
                snd.db.escape(dest)
            )) or {}
            if #areaRows > 0 then
                local areaKey = areaRows[1].key
                local roomId = tonumber(areaRows[1].startRoom) or -1
                if roomId > 0 then
                    cecho("<yellow>[MMAPPER]<reset> Going to " .. areaKey .. " (room " .. roomId .. ")\n")
                    snd.mapper.debugXrtDecision(dest, roomId, "area match from snd.db area query")
                    return snd.mapper.gotoRoom(roomId, nil, nil, nil, dest, options)
                end
            end
        end
    end

    -- Fall back to bundled defaults
    if snd.data and snd.data.areaDefaultStartRooms then
        local areaData = snd.data.areaDefaultStartRooms[dest]
        if areaData and areaData.start then
            cecho("<yellow>[MMAPPER]<reset> Going to " .. dest .. " (room " .. areaData.start .. ")\n")
            snd.mapper.debugXrtDecision(dest, areaData.start, "bundled default area start")
            return snd.mapper.gotoRoom(areaData.start, nil, nil, nil, dest, options)
        end
        
        -- Try partial match on area names
        for areaKey, data in pairs(snd.data.areaDefaultStartRooms) do
            if areaKey:lower():find(dest, 1, true) and data.start then
                cecho("<yellow>[MMAPPER]<reset> Going to " .. areaKey .. " (room " .. data.start .. ")\n")
                snd.mapper.debugXrtDecision(dest, data.start, "bundled partial area match")
                return snd.mapper.gotoRoom(data.start, nil, nil, nil, dest, options)
            end
        end
    end
    
    -- Try looking up in database by area name
    if snd.mapper.db.open() then
        local sql = string.format(
            "SELECT uid FROM rooms WHERE area LIKE %s LIMIT 1",
            snd.mapper.db.escape("%" .. dest .. "%")
        )
        local results = snd.mapper.db.query(sql)
        if results and #results > 0 then
            local roomId = results[1].uid
            cecho("<yellow>[MMAPPER]<reset> Going to area matching '" .. dest .. "' (room " .. roomId .. ")\n")
            snd.mapper.debugXrtDecision(dest, roomId, "mapper db area LIKE fallback")
            return snd.mapper.gotoRoom(roomId, nil, nil, nil, dest, options)
        end
    end
    
    cecho("<red>[MMAPPER]<reset> Unknown area: " .. dest .. "\n")
    return false
end

function snd.mapper.xrtforce(dest)
    if not dest or dest == "" then
        cecho("<yellow>[MMAPPER]<reset> Usage: xrtforce <area|roomid>\n")
        cecho("<dim_gray>Examples: xrtforce aylor, xrtforce academy, xrtforce 32418<reset>\n")
        return false
    end

    dest = dest:lower():trim()

    local roomNum = tonumber(dest)
    if roomNum then
        cecho("<yellow>[MMAPPER]<reset> Force-going to room " .. roomNum .. " (ignoring area, portal, and exit-level guards)\n")
        return snd.mapper.gotoRoom(roomNum, true, true, nil, dest)
    end

    if snd.db and snd.db.getAreaStartRoom then
        local startRoom = tonumber(snd.db.getAreaStartRoom(dest)) or -1
        if startRoom > 0 then
            cecho("<yellow>[MMAPPER]<reset> Force-going to " .. dest .. " (room " .. startRoom .. ", ignoring area, portal, and exit-level guards)\n")
            return snd.mapper.gotoRoom(startRoom, true, true, nil, dest)
        end

        if snd.db.query then
            local areaRows = snd.db.query(string.format(
                "SELECT key, startRoom FROM area WHERE startRoom > 0 AND (key LIKE %s OR name LIKE %s) ORDER BY CASE WHEN key = %s THEN 0 ELSE 1 END, key LIMIT 1",
                snd.db.escape("%" .. dest .. "%"),
                snd.db.escape("%" .. dest .. "%"),
                snd.db.escape(dest)
            )) or {}
            if #areaRows > 0 then
                local areaKey = areaRows[1].key
                local roomId = tonumber(areaRows[1].startRoom) or -1
                if roomId > 0 then
                    cecho("<yellow>[MMAPPER]<reset> Force-going to " .. areaKey .. " (room " .. roomId .. ", ignoring area, portal, and exit-level guards)\n")
                    return snd.mapper.gotoRoom(roomId, true, true, nil, dest)
                end
            end
        end
    end

    if snd.data and snd.data.areaDefaultStartRooms then
        local areaData = snd.data.areaDefaultStartRooms[dest]
        if areaData and areaData.start then
            cecho("<yellow>[MMAPPER]<reset> Force-going to " .. dest .. " (room " .. areaData.start .. ", ignoring area, portal, and exit-level guards)\n")
            return snd.mapper.gotoRoom(areaData.start, true, true, nil, dest)
        end

        for areaKey, data in pairs(snd.data.areaDefaultStartRooms) do
            if areaKey:lower():find(dest, 1, true) and data.start then
                cecho("<yellow>[MMAPPER]<reset> Force-going to " .. areaKey .. " (room " .. data.start .. ", ignoring area, portal, and exit-level guards)\n")
                return snd.mapper.gotoRoom(data.start, true, true, nil, dest)
            end
        end
    end

    if snd.mapper.db.open() then
        local sql = string.format(
            "SELECT uid FROM rooms WHERE area LIKE %s LIMIT 1",
            snd.mapper.db.escape("%" .. dest .. "%")
        )
        local results = snd.mapper.db.query(sql)
        if results and #results > 0 then
            local roomId = results[1].uid
            cecho("<yellow>[MMAPPER]<reset> Force-going to area matching '" .. dest .. "' (room " .. roomId .. ", ignoring area, portal, and exit-level guards)\n")
            return snd.mapper.gotoRoom(roomId, true, true, nil, dest)
        end
    end

    cecho("<red>[MMAPPER]<reset> Unknown area: " .. dest .. "\n")
    return false
end

--- Walk to a room or area WITHOUT using portals (pure walking)
-- Uses snd.db for area lookup and Aardwolf.db for pathfinding
-- Does NOT use Mudlet's internal map for navigation
-- @param dest Destination - room number or area name
-- @param opts Optional controls; embedded avoids replacing an outer route destination
function snd.mapper.walkTo(dest, opts)
    if not dest or dest == "" then
        cecho("<yellow>[MMAPPER]<reset> Usage: walkto <roomid|areaname>\n")
        cecho("<dim_gray>Examples: walkto 32418, walkto aylor, walkto farm<reset>\n")
        return false
    end
    
    opts = opts or {}
    local embedded = opts.embedded == true
    snd.mapper.lastRouteFailure = nil
    dest = dest:lower():trim()
    
    -- Get current room
    local currentRoom = nil
    if snd.room and snd.room.current and snd.room.current.rmid then
        currentRoom = snd.room.current.rmid
    end
    if not currentRoom or currentRoom == "-1" then
        if gmcp and gmcp.room and gmcp.room.info then
            currentRoom = mm.canonical_room_uid(gmcp.room.info)
        end
    end
    
    if not currentRoom or currentRoom == "-1" then
        cecho("<red>[MMAPPER]<reset> Current room unknown. Try 'look' first.\n")
        return false
    end
    
    local targetRoom = nil
    local displayName = dest
    
    -- Check if it's a room number
    local roomNum = tonumber(dest)
    if roomNum then
        targetRoom = tostring(roomNum)
        displayName = "room " .. roomNum
    else
        -- Look up area in snd.db first (the mob/area database)
        if snd.db and snd.db.getAreaStartRoom then
            local startRoom = snd.db.getAreaStartRoom(dest)
            if startRoom and startRoom > 0 then
                targetRoom = tostring(startRoom)
                displayName = dest .. " (room " .. startRoom .. ")"
            end
        end
        
        -- Try snd.data.areaDefaultStartRooms
        if not targetRoom and snd.data and snd.data.areaDefaultStartRooms then
            -- Exact match
            local areaData = snd.data.areaDefaultStartRooms[dest]
            if areaData and areaData.start then
                targetRoom = tostring(areaData.start)
                displayName = dest .. " (room " .. areaData.start .. ")"
            end
            
            -- Partial match
            if not targetRoom then
                for areaKey, data in pairs(snd.data.areaDefaultStartRooms) do
                    if areaKey:lower():find(dest, 1, true) and data.start then
                        targetRoom = tostring(data.start)
                        displayName = areaKey .. " (room " .. data.start .. ")"
                        break
                    end
                end
            end
        end
        
        -- Try database lookup by area name in Aardwolf.db
        if not targetRoom and snd.mapper.db.open() then
            local sql = string.format(
                "SELECT uid FROM rooms WHERE LOWER(area) LIKE %s LIMIT 1",
                snd.mapper.db.escape("%" .. dest .. "%")
            )
            local results = snd.mapper.db.query(sql)
            if results and #results > 0 then
                targetRoom = tostring(results[1].uid)
                displayName = dest .. " (room " .. targetRoom .. ")"
            end
        end
    end
    
    if not targetRoom then
        cecho("<red>[MMAPPER]<reset> Unknown destination: " .. dest .. "\n")
        return false
    end
    
    if currentRoom == targetRoom then
        cecho("<yellow>[MMAPPER]<reset> Already at " .. displayName .. "\n")
        return true
    end

    if not snd.mapper.checkAreaGuardDestination(currentRoom, targetRoom, dest, false, false) then
        return false
    end
    
    -- Use snd.mapper.findPath with portals DISABLED
    cecho("<yellow>[MMAPPER]<reset> Walking to " .. displayName .. " (no portals)...\n")
    
    local path, depth = snd.mapper.findPath(currentRoom, targetRoom, true, true)  -- noPortals=true, noRecalls=true
    
    if path and #path > 0 then
        cecho("<dim_gray>[MMAPPER] Found path with " .. #path .. " steps<reset>\n")
        if not embedded then
            snd.mapper.goingToRoom = targetRoom
            snd.nav.goingToRoom = targetRoom
        end
        snd.mapper.executePath(path, {preserveExecutionSerial = embedded})
        return true
    else
        if snd.mapper.areaGuardEnabled() then
            local unguardedPath = snd.mapper.findPath(currentRoom, targetRoom, true, true, false, true)
            if unguardedPath and #unguardedPath > 0 then
                snd.utils.debugNote(string.format(
                    "Area guard rejected walking route to room %s; unguarded route has %d steps.",
                    tostring(targetRoom),
                    #unguardedPath
                ))
                snd.mapper.reportAreaGuardRouteBlocked(dest)
                return false
            end
        end
        local failure = {
            code = "walking_path_not_found",
            targetRoom = tostring(targetRoom),
            sourceRoom = tostring(currentRoom),
        }
        snd.mapper.lastRouteFailure = failure
        if opts.quietFailure ~= true then
            cecho("<red>[MMAPPER]<reset> No walking path found to " .. displayName .. "\n")
            cecho("<dim_gray>The destination may not be reachable by walking alone.<reset>\n")
        end
        local offeredManualApproach = false
        if snd.commands and type(snd.commands.offerManualApproach) == "function" then
            local ok, offered = pcall(snd.commands.offerManualApproach, targetRoom)
            offeredManualApproach = ok and offered == true
            if not ok then
                snd.utils.debugNote("Manual approach display failed: " .. tostring(offered))
            end
        end
        if offeredManualApproach then
            return false, failure
        end

        if snd.commands and type(snd.commands.fallbackToTargetAreaStart) == "function" then
            local ok, handled = pcall(snd.commands.fallbackToTargetAreaStart, targetRoom)
            if ok and handled == true then
                snd.mapper.lastRouteFailure = nil
                return true
            elseif not ok then
                snd.utils.debugNote("Target area-start fallback failed: " .. tostring(handled))
            end
        end

        if opts.suppressXrtNear ~= true then
            snd.utils.infoNote("Try 'xrtnear " .. targetRoom .. "' to list reachable boundary rooms. The lookup may take a moment.")
        end
        return false, failure
    end
end

-------------------------------------------------------------------------------
-- Alias Registration
-------------------------------------------------------------------------------

-- Register xrt alias
if snd.mapper.xrtAlias then
    killAlias(snd.mapper.xrtAlias)
end
snd.mapper.xrtAlias = tempAlias("^xrt(?:\\s+(.*))?$", function()
    local dest = matches[2] or ""
    snd.mapper.xrt(dest)
    if mm and mm.minimap and mm.minimap.is_native_mode and mm.minimap.is_native_mode() then raiseWindow("mapper") end
end)

for _, triggerId in ipairs(snd.mapper.restrictionTriggerIds or {}) do
    killTrigger(triggerId)
end
snd.mapper.restrictionTriggerIds = {
    tempRegexTrigger("^Magic walls bounce you back\\.$", function()
        snd.mapper.onPortalBlocked()
    end),
    tempRegexTrigger("^You cannot (?:recall|return home) from this room\\.$", function()
        snd.mapper.onRecallBlocked()
    end),
}

for _, triggerId in ipairs(snd.mapper.routeFailureTriggerIds or {}) do
    killTrigger(triggerId)
end
snd.mapper.routeFailureTriggerIds = {
    tempRegexTrigger("^Too many run errors\\. Aborting speedwalk\\.$", function()
        snd.mapper.abortFailedNavigation("speedwalk_aborted")
    end),
    tempRegexTrigger("^Magical wards around .+ bounce you back\\.$", function()
        snd.mapper.abortFailedNavigation("ward_bounced")
    end),
}

for _, eventId in ipairs(snd.mapper.recallResumeEventIds or {}) do
    if type(killAnonymousEventHandler) == "function" then
        killAnonymousEventHandler(eventId)
    end
end
-- Older builds registered GMCP handlers for blind-recall continuation. Kill
-- those handlers during an upgrade, but do not register replacements.
snd.mapper.recallResumeEventIds = {}

if snd.mapper.xrtForceAlias then
    killAlias(snd.mapper.xrtForceAlias)
end
snd.mapper.xrtForceAlias = tempAlias("^xrtforce(?:\\s+(.*))?$", function()
    local dest = matches[2] or ""
    snd.mapper.xrtforce(dest)
end)

-- Register walkto alias (no portals)
if snd.mapper.walkToAlias then
    killAlias(snd.mapper.walkToAlias)
end
snd.mapper.walkToAlias = tempAlias("^walkto(?:\\s+(.*))?$", function()
    local dest = matches[2] or ""
    snd.mapper.walkTo(dest)
end)

-- Deprecated command aliases removed:
--   navhelp
--   mapper/snd portals
--   mapper portal
--   mapper searchportal
--   mapper/snd navdb
--   mapper/snd import

-------------------------------------------------------------------------------
-- Database Import - Import from Aardwolf.db to Mudlet Internal Map
-------------------------------------------------------------------------------

--- Import all data from Aardwolf.db into Mudlet's internal map
-- WARNING: This clears the existing Mudlet map first!
function snd.mapper.importFromDb()
    -- Retain the legacy API name, but always prefer the shared importer whose
    -- room positions are derived from cardinal exits.
    if mm and mm.import and type(mm.import.convert_sqlite_to_mudlet) == "function" then
        return mm.import.convert_sqlite_to_mudlet(mm.state and mm.state.map_db or "Aardwolf.db")
    end

    if not snd.mapper.db.open() then
        snd.utils.errorNote("Cannot open Aardwolf.db for import")
        return false
    end
    
    cecho("\n<yellow>═══ Starting Map Import from Aardwolf.db ═══<reset>\n")
    
    -- Step 1: Count what we're importing
    local roomCount = snd.mapper.db.query("SELECT COUNT(*) as cnt FROM rooms")
    local exitCount = snd.mapper.db.query("SELECT COUNT(*) as cnt FROM exits")
    local areaCount = snd.mapper.db.query("SELECT COUNT(DISTINCT area) as cnt FROM rooms")
    
    roomCount = roomCount and roomCount[1] and roomCount[1].cnt or 0
    exitCount = exitCount and exitCount[1] and exitCount[1].cnt or 0
    areaCount = areaCount and areaCount[1] and areaCount[1].cnt or 0
    
    cecho(string.format("  <cyan>Found:<reset> %d rooms, %d exits, %d areas\n", roomCount, exitCount, areaCount))
    
    if roomCount == 0 then
        snd.utils.errorNote("No rooms found in Aardwolf.db!")
        return false
    end
    
    -- Step 2: Clear existing Mudlet map
    cecho("  <yellow>Clearing existing Mudlet map...<reset>\n")
    
    local existingRooms = getRooms()
    local cleared = 0
    for roomId, _ in pairs(existingRooms) do
        deleteRoom(roomId)
        cleared = cleared + 1
    end
    cecho(string.format("  <dim_gray>Cleared %d rooms from Mudlet map<reset>\n", cleared))
    
    -- Also clear areas (except default -1)
    local existingAreas = getAreaTable()
    for name, id in pairs(existingAreas) do
        if id ~= -1 then
            deleteArea(id)
        end
    end
    
    -- Step 3: Create areas
    cecho("  <yellow>Creating areas...<reset>\n")
    
    local areaResults = snd.mapper.db.query("SELECT DISTINCT area FROM rooms WHERE area IS NOT NULL AND area != ''")
    local areaMap = {}  -- Maps area name -> Mudlet area ID
    local areasCreated = 0
    
    for _, row in ipairs(areaResults or {}) do
        local areaName = row.area
        if areaName and areaName ~= "" then
            local areaId = addAreaName(areaName)
            if areaId then
                areaMap[areaName] = areaId
                areasCreated = areasCreated + 1
            end
        end
    end
    cecho(string.format("  <green>Created %d areas<reset>\n", areasCreated))
    
    -- Step 4: Import rooms in batches
    cecho("  <yellow>Importing rooms...<reset>\n")
    
    local batchSize = 1000
    local offset = 0
    local roomsCreated = 0
    local roomErrors = 0
    
    while true do
        local sql = string.format(
            "SELECT uid, name, area, terrain, norecall, noportal FROM rooms LIMIT %d OFFSET %d",
            batchSize, offset
        )
        local rooms = snd.mapper.db.query(sql)
        
        if not rooms or #rooms == 0 then
            break
        end
        
        for _, room in ipairs(rooms) do
            local roomId = tonumber(room.uid)
            if roomId and roomId > 0 then
                local created = addRoom(roomId)
                if created then
                    -- Set room name
                    if room.name then
                        setRoomName(roomId, room.name)
                    end
                    
                    -- Set room area
                    if room.area and areaMap[room.area] then
                        setRoomArea(roomId, areaMap[room.area])
                    end
                    
                    -- Set room character for special flags
                    if tonumber(room.noportal) == 1 then
                        setRoomChar(roomId, "P")  -- Mark as no-portal
                    elseif tonumber(room.norecall) == 1 then
                        setRoomChar(roomId, "R")  -- Mark as no-recall
                    end
                    
                    roomsCreated = roomsCreated + 1
                else
                    roomErrors = roomErrors + 1
                end
            end
        end
        
        offset = offset + batchSize
        
        -- Progress update every batch
        if offset % 5000 == 0 then
            cecho(string.format("  <dim_gray>Progress: %d rooms...<reset>\n", roomsCreated))
        end
    end
    
    cecho(string.format("  <green>Created %d rooms<reset>", roomsCreated))
    if roomErrors > 0 then
        cecho(string.format(" <red>(%d errors)<reset>", roomErrors))
    end
    echo("\n")
    
    -- Step 5: Import exits in batches
    cecho("  <yellow>Importing exits...<reset>\n")
    
    offset = 0
    local exitsCreated = 0
    local exitErrors = 0
    
    -- Direction mapping for Mudlet
    local dirMap = {
        n = "north", s = "south", e = "east", w = "west",
        u = "up", d = "down",
    }
    
    while true do
        local sql = string.format(
            "SELECT fromuid, touid, dir FROM exits WHERE fromuid NOT IN ('*', '**') LIMIT %d OFFSET %d",
            batchSize, offset
        )
        local exits = snd.mapper.db.query(sql)
        
        if not exits or #exits == 0 then
            break
        end
        
        for _, exit in ipairs(exits) do
            local fromId = tonumber(exit.fromuid)
            local toId = tonumber(exit.touid)
            local dir = exit.dir
            
            if fromId and toId and dir then
                -- Check if it's a standard direction
                local mudletDir = dirMap[dir:lower()]
                if mudletDir then
                    -- Standard exit
                    local success = setExit(fromId, toId, mudletDir)
                    if success then
                        exitsCreated = exitsCreated + 1
                    else
                        exitErrors = exitErrors + 1
                    end
                else
                    -- Special exit (custom command)
                    local success = addSpecialExit(fromId, toId, dir)
                    if success then
                        exitsCreated = exitsCreated + 1
                    else
                        exitErrors = exitErrors + 1
                    end
                end
            end
        end
        
        offset = offset + batchSize
        
        -- Progress update
        if offset % 10000 == 0 then
            cecho(string.format("  <dim_gray>Progress: %d exits...<reset>\n", exitsCreated))
        end
    end
    
    cecho(string.format("  <green>Created %d exits<reset>", exitsCreated))
    if exitErrors > 0 then
        cecho(string.format(" <red>(%d errors)<reset>", exitErrors))
    end
    echo("\n")
    
    -- The compatibility fallback also derives room positions from exits. It
    -- must never copy Aardwolf's continent coordinates into Mudlet rooms.
    local layoutOk, layoutErr = snd.mapper.calculateCoordinates()
    if not layoutOk then
        snd.utils.errorNote("Cannot calculate native map layout: " .. tostring(layoutErr or "unknown error"))
        return false
    end

    -- Step 6: Save the map
    cecho("  <yellow>Saving map...<reset>\n")
    saveMap()
    
    -- Summary
    cecho("\n<green>═══ Import Complete ═══<reset>\n")
    cecho(string.format("  <cyan>Rooms:<reset> %d created\n", roomsCreated))
    cecho(string.format("  <cyan>Exits:<reset> %d created\n", exitsCreated))
    cecho(string.format("  <cyan>Areas:<reset> %d created\n", areasCreated))
    cecho("\n<yellow>NOTE:<reset> You may need to restart Mudlet for the visual map to update.\n")
    cecho("<yellow>TIP:<reset> Use 'lua centerview(32418)' to jump to Aylor.\n")
    
    return true
end

--- Quick check of import status
function snd.mapper.checkImport()
    local mudletRooms = 0
    local mudletAreas = 0
    local noAreaRooms = 0
    
    for roomId, _ in pairs(getRooms()) do
        mudletRooms = mudletRooms + 1
        if getRoomArea(roomId) == -1 then
            noAreaRooms = noAreaRooms + 1
        end
    end
    
    for _, _ in pairs(getAreaTable()) do
        mudletAreas = mudletAreas + 1
    end
    
    cecho("\n<yellow>═══ Map Status ═══<reset>\n")
    cecho(string.format("  <cyan>Mudlet rooms:<reset> %d\n", mudletRooms))
    cecho(string.format("  <cyan>Mudlet areas:<reset> %d\n", mudletAreas))
    cecho(string.format("  <cyan>Rooms with no area:<reset> %d\n", noAreaRooms))
    
    if snd.mapper.db.open() then
        local dbRooms = snd.mapper.db.query("SELECT COUNT(*) as cnt FROM rooms")
        dbRooms = dbRooms and dbRooms[1] and dbRooms[1].cnt or 0
        cecho(string.format("  <cyan>Aardwolf.db rooms:<reset> %d\n", dbRooms))
    end
    
    cecho("<yellow>══════════════════<reset>\n")
end

-- Deprecated command aliases removed:
--   mapper/snd checkimport
--   mapper/snd calccoords

-------------------------------------------------------------------------------
-- Coordinate Calculation - Build visual map from exits
-------------------------------------------------------------------------------

-- Direction to coordinate offset mapping
snd.mapper.dirOffsets = {
    n  = { x = 0,  y = 1,  z = 0 },
    s  = { x = 0,  y = -1, z = 0 },
    e  = { x = 1,  y = 0,  z = 0 },
    w  = { x = -1, y = 0,  z = 0 },
    u  = { x = 0,  y = 0,  z = 1 },
    d  = { x = 0,  y = 0,  z = -1 },
    north = { x = 0,  y = 1,  z = 0 },
    south = { x = 0,  y = -1, z = 0 },
    east  = { x = 1,  y = 0,  z = 0 },
    west  = { x = -1, y = 0,  z = 0 },
    up    = { x = 0,  y = 0,  z = 1 },
    down  = { x = 0,  y = 0,  z = -1 },
}

--- Calculate coordinates for all rooms using BFS from exits
-- @param startRoom Optional starting room (default: 32418 Aylor)
function snd.mapper.calculateCoordinates(startRoom)
    -- Keep the legacy API as a compatibility entry point, but route it through
    -- the shared database-driven, per-area layout engine used by mapper
    -- calccoords, mapper rebuild map, and mapper rebuild layout.
    if mm and mm.import and type(mm.import.recalculate_all_layouts) == "function" then
        return mm.import.recalculate_all_layouts(mm.state and mm.state.map_db or "Aardwolf.db")
    end

    startRoom = startRoom or 32418
    
    if not snd.mapper.db.open() then
        snd.utils.errorNote("Cannot open Aardwolf.db")
        return false
    end
    
    cecho("\n<yellow>═══ Calculating Room Coordinates ═══<reset>\n")
    cecho(string.format("  <cyan>Starting room:<reset> %d\n", startRoom))
    
    -- Check if start room exists
    if not roomExists(startRoom) then
        snd.utils.errorNote("Start room " .. startRoom .. " doesn't exist in Mudlet map")
        return false
    end
    
    -- Get all exits from database (excluding portals)
    cecho("  <yellow>Loading exits from database...<reset>\n")
    local exitQuery = snd.mapper.db.query([[
        SELECT fromuid, touid, dir FROM exits 
        WHERE fromuid NOT IN ('*', '**') 
        AND touid NOT IN ('*', '**')
        AND dir IN ('n','s','e','w','u','d',
                    'north','south','east','west','up','down')
    ]])
    
    if not exitQuery or #exitQuery == 0 then
        snd.utils.errorNote("No exits found in database")
        return false
    end
    
    cecho(string.format("  <cyan>Exits loaded:<reset> %d\n", #exitQuery))
    
    -- Build adjacency list
    local exits = {}  -- exits[fromuid] = { {touid, dir}, ... }
    for _, exit in ipairs(exitQuery) do
        local from = tonumber(exit.fromuid)
        local to = tonumber(exit.touid)
        local dir = exit.dir:lower()
        
        if from and to and snd.mapper.dirOffsets[dir] then
            exits[from] = exits[from] or {}
            table.insert(exits[from], { to = to, dir = dir })
        end
    end
    
    -- BFS to calculate coordinates
    cecho("  <yellow>Calculating coordinates via BFS...<reset>\n")
    
    local coords = {}  -- coords[roomid] = {x, y, z}
    local queue = {}
    local visited = {}
    local processed = 0
    local totalRooms = 0
    
    -- Count total rooms for progress
    for _ in pairs(getRooms()) do
        totalRooms = totalRooms + 1
    end
    
    -- Start BFS from startRoom at (0, 0, 0)
    coords[startRoom] = { x = 0, y = 0, z = 0 }
    table.insert(queue, startRoom)
    visited[startRoom] = true
    
    while #queue > 0 do
        local current = table.remove(queue, 1)
        local currentCoords = coords[current]
        processed = processed + 1
        
        -- Progress update
        if processed % 5000 == 0 then
            cecho(string.format("  <dim_gray>Progress: %d rooms processed...<reset>\n", processed))
        end
        
        -- Process all exits from current room
        if exits[current] then
            for _, exit in ipairs(exits[current]) do
                local nextRoom = exit.to
                local dir = exit.dir
                local offset = snd.mapper.dirOffsets[dir]
                
                if not visited[nextRoom] and offset and roomExists(nextRoom) then
                    visited[nextRoom] = true
                    coords[nextRoom] = {
                        x = currentCoords.x + offset.x,
                        y = currentCoords.y + offset.y,
                        z = currentCoords.z + offset.z
                    }
                    table.insert(queue, nextRoom)
                end
            end
        end
    end
    
    cecho(string.format("  <green>Calculated coordinates for %d rooms<reset>\n", processed))
    
    -- Find disconnected rooms (not reachable from start)
    local disconnected = 0
    for roomId, _ in pairs(getRooms()) do
        if not coords[roomId] then
            disconnected = disconnected + 1
        end
    end
    
    if disconnected > 0 then
        cecho(string.format("  <yellow>Disconnected rooms:<reset> %d (will process separately)\n", disconnected))
        
        -- Process disconnected areas - find clusters and position them
        local clusterOffset = 1000  -- Offset each cluster by 1000 to separate them
        local clusterCount = 0
        
        for roomId, _ in pairs(getRooms()) do
            if not coords[roomId] then
                -- Start a new cluster from this room
                clusterCount = clusterCount + 1
                local clusterBaseX = clusterCount * clusterOffset
                
                coords[roomId] = { x = clusterBaseX, y = 0, z = 0 }
                local clusterQueue = { roomId }
                visited[roomId] = true
                
                while #clusterQueue > 0 do
                    local current = table.remove(clusterQueue, 1)
                    local currentCoords = coords[current]
                    
                    if exits[current] then
                        for _, exit in ipairs(exits[current]) do
                            local nextRoom = exit.to
                            local dir = exit.dir
                            local offset = snd.mapper.dirOffsets[dir]
                            
                            if not visited[nextRoom] and offset and roomExists(nextRoom) then
                                visited[nextRoom] = true
                                coords[nextRoom] = {
                                    x = currentCoords.x + offset.x,
                                    y = currentCoords.y + offset.y,
                                    z = currentCoords.z + offset.z
                                }
                                table.insert(clusterQueue, nextRoom)
                            end
                        end
                    end
                end
            end
        end
        
        cecho(string.format("  <cyan>Found %d disconnected clusters<reset>\n", clusterCount))
    end
    
    -- Apply coordinates to Mudlet map
    cecho("  <yellow>Applying coordinates to Mudlet map...<reset>\n")
    
    local applied = 0
    local errors = 0
    
    for roomId, coord in pairs(coords) do
        local success = setRoomCoordinates(roomId, coord.x, coord.y, coord.z)
        if success then
            applied = applied + 1
        else
            errors = errors + 1
        end
        
        if applied % 5000 == 0 then
            cecho(string.format("  <dim_gray>Applied: %d rooms...<reset>\n", applied))
        end
    end
    
    -- Save the map
    cecho("  <yellow>Saving map...<reset>\n")
    saveMap()
    
    -- Summary
    cecho("\n<green>═══ Coordinate Calculation Complete ═══<reset>\n")
    cecho(string.format("  <cyan>Rooms processed:<reset> %d\n", processed))
    cecho(string.format("  <cyan>Coordinates applied:<reset> %d\n", applied))
    if errors > 0 then
        cecho(string.format("  <red>Errors:<reset> %d\n", errors))
    end
    if disconnected > 0 then
        cecho(string.format("  <yellow>Disconnected clusters:<reset> positioned separately\n"))
    end
    cecho("\n<yellow>TIP:<reset> Use 'lua centerview(32418)' to see Aylor.\n")
    cecho("<yellow>TIP:<reset> You may need to restart Mudlet for full visual update.\n")
    
    return true
end

-------------------------------------------------------------------------------
-- Room Color Update - Apply terrain colors from environments table
-------------------------------------------------------------------------------

-- Deprecated command alias removed:
--   mapper/snd updatecolors

--- Update room colors based on terrain → environment mapping
function snd.mapper.updateRoomColors()
    if not snd.mapper.db.open() then
        snd.utils.errorNote("Cannot open Aardwolf.db")
        return false
    end
    
    cecho("\n<yellow>═══ Updating Room Colors ═══<reset>\n")
    
    -- ANSI color codes to RGB mapping (matching MUSHclient)
    local ansiToRgb = {
        [1]  = {128, 0, 0},       -- Dark Red
        [2]  = {0, 128, 0},       -- Dark Green
        [3]  = {128, 128, 0},     -- Brown/Yellow
        [4]  = {0, 0, 128},       -- Dark Blue
        [5]  = {128, 0, 128},     -- Dark Magenta
        [6]  = {0, 128, 128},     -- Dark Cyan
        [7]  = {192, 192, 192},   -- Light Gray
        [8]  = {128, 128, 128},   -- Dark Gray
        [9]  = {255, 0, 0},       -- Light Red
        [10] = {0, 255, 0},       -- Light Green
        [11] = {255, 255, 0},     -- Yellow
        [12] = {0, 0, 255},       -- Light Blue
        [13] = {255, 0, 255},     -- Light Magenta
        [14] = {0, 255, 255},     -- Light Cyan
        [15] = {255, 255, 255},   -- White
    }
    
    -- Step 1: Load environment color mapping (column is uid, not id)
    cecho("  <yellow>Loading environment colors...<reset>\n")
    
    local envQuery = snd.mapper.db.query("SELECT uid, name, color FROM environments")
    if not envQuery or #envQuery == 0 then
        snd.utils.errorNote("No environments found in database")
        return false
    end
    
    -- Build terrain name → env id and color mapping
    local terrainToEnvId = {}
    local envColors = {}
    
    for _, env in ipairs(envQuery) do
        local envId = tonumber(env.uid)  -- Use uid, not id
        local name = env.name
        local color = tonumber(env.color)
        
        if envId and name then
            terrainToEnvId[name:lower()] = envId
            if color then
                envColors[envId] = color
            end
        end
    end
    
    cecho(string.format("  <cyan>Loaded %d environment types<reset>\n", #envQuery))
    
    -- Step 2: Register environment colors in Mudlet
    cecho("  <yellow>Registering environment colors in Mudlet...<reset>\n")
    
    local colorsSet = 0
    for envId, ansiColor in pairs(envColors) do
        local rgb = ansiToRgb[ansiColor]
        if rgb then
            setCustomEnvColor(envId, rgb[1], rgb[2], rgb[3], 255)
            colorsSet = colorsSet + 1
        else
            -- Fallback for unknown color codes
            setCustomEnvColor(envId, 192, 192, 192, 255)  -- Default gray
        end
    end
    
    cecho(string.format("  <cyan>Set %d environment colors<reset>\n", colorsSet))
    
    -- Step 3: Load rooms and update their environments
    cecho("  <yellow>Updating room environments...<reset>\n")
    
    local batchSize = 1000
    local offset = 0
    local updated = 0
    local skipped = 0
    local errors = 0
    
    while true do
        local sql = string.format(
            "SELECT uid, terrain FROM rooms WHERE terrain IS NOT NULL AND terrain != '' LIMIT %d OFFSET %d",
            batchSize, offset
        )
        local rooms = snd.mapper.db.query(sql)
        
        if not rooms or #rooms == 0 then
            break
        end
        
        for _, room in ipairs(rooms) do
            local roomId = tonumber(room.uid)
            local terrain = room.terrain
            
            if roomId and terrain and roomExists(roomId) then
                local envId = terrainToEnvId[terrain:lower()]
                if envId then
                    local success = setRoomEnv(roomId, envId)
                    if success then
                        updated = updated + 1
                    else
                        errors = errors + 1
                    end
                else
                    skipped = skipped + 1
                end
            end
        end
        
        offset = offset + batchSize
        
        if offset % 5000 == 0 then
            cecho(string.format("  <dim_gray>Progress: %d rooms...<reset>\n", updated))
        end
    end
    
    -- Step 4: Save the map
    cecho("  <yellow>Saving map...<reset>\n")
    saveMap()
    
    -- Summary
    cecho("\n<green>═══ Color Update Complete ═══<reset>\n")
    cecho(string.format("  <cyan>Rooms updated:<reset> %d\n", updated))
    if skipped > 0 then
        cecho(string.format("  <yellow>Skipped (unknown terrain):<reset> %d\n", skipped))
    end
    if errors > 0 then
        cecho(string.format("  <red>Errors:<reset> %d\n", errors))
    end
    cecho("\n<yellow>TIP:<reset> Restart Mudlet to see color changes.\n")
    
    return true
end

--- Show environment/terrain mapping
function snd.mapper.showEnvironments()
    if not snd.mapper.db.open() then
        snd.utils.errorNote("Cannot open Aardwolf.db")
        return
    end
    
    local envQuery = snd.mapper.db.query("SELECT uid, name, color FROM environments ORDER BY CAST(uid AS INTEGER)")
    if not envQuery or #envQuery == 0 then
        cecho("<red>No environments found<reset>\n")
        return
    end
    
    -- ANSI color names for display
    local ansiNames = {
        [1]  = "Dark Red",
        [2]  = "Dark Green",
        [3]  = "Brown",
        [4]  = "Dark Blue",
        [5]  = "Dark Magenta",
        [6]  = "Dark Cyan",
        [7]  = "Light Gray",
        [8]  = "Dark Gray",
        [9]  = "Light Red",
        [10] = "Light Green",
        [11] = "Yellow",
        [12] = "Light Blue",
        [13] = "Light Magenta",
        [14] = "Light Cyan",
        [15] = "White",
    }
    
    cecho("\n<yellow>═══ Environments ═══<reset>\n")
    for _, env in ipairs(envQuery) do
        local colorNum = tonumber(env.color) or 0
        local colorName = ansiNames[colorNum] or "Unknown"
        cecho(string.format("  <cyan>%3s<reset> %-20s color: %2d (%s)\n", 
            env.uid or "?", 
            env.name or "?", 
            colorNum,
            colorName))
    end
    cecho("<yellow>════════════════════<reset>\n")
end

-- Deprecated command alias removed:
--   mapper/snd showenv

-------------------------------------------------------------------------------
-- Cleanup
-------------------------------------------------------------------------------

registerAnonymousEventHandler("sysExitEvent", function()
    snd.mapper.db.close()
end)

-- Module loaded message
snd.utils.debugNote("Navigation module loaded")
