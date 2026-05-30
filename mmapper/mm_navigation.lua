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

local function build_nomap_uid(name, zone)
    local clean_name = (mm and mm.strip_ansi) and mm.strip_ansi(name) or tostring(name or "")
    local clean_zone = (mm and mm.strip_ansi) and mm.strip_ansi(zone) or tostring(zone or "")
    clean_name = tostring(clean_name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    clean_zone = tostring(clean_zone or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if clean_name == "" then clean_name = "?" end
    if clean_zone == "" then clean_zone = "?" end
    return "nomap_" .. clean_name .. "_" .. clean_zone
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
    end
    cecho("<dim_gray>[MMAPPER:DEBUG]<reset> <gray>" .. text .. "<reset>\n")
end
if type(snd.utils.trim) ~= "function" then
    snd.utils.trim = function(s)
        return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
end

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

-------------------------------------------------------------------------------
-- Portal Configuration
-------------------------------------------------------------------------------

snd.mapper.config = {
    usePortals = true,          -- Use portal exits
    useRecall = true,           -- Use recall-based portals
    maxSearchDepth = 100,       -- Max BFS depth for pathfinding
    bouncePortal = nil,         -- Fallback portal for norecall rooms
    bounceRecall = nil,         -- Fallback recall for noportal rooms
}

snd.mapper.pendingRestrictionMarks = snd.mapper.pendingRestrictionMarks or {}
snd.mapper.restrictionTriggerIds = snd.mapper.restrictionTriggerIds or {}
snd.mapper.pendingBlockedTravel = snd.mapper.pendingBlockedTravel or nil

local mapperDirectionAliases = {
    n = "n", north = "n",
    s = "s", south = "s",
    e = "e", east = "e",
    w = "w", west = "w",
    u = "u", up = "u",
    d = "d", down = "d",
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
          AND touid IN (
              SELECT touid
              FROM exits
              WHERE fromuid = %s
                AND LOWER(dir) IN (%s, %s)
          )
    ]],
        lockLevel,
        snd.mapper.db.escape(roomKey),
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
          AND touid IN (
              SELECT touid
              FROM exits
              WHERE fromuid = %s
                AND LOWER(dir) IN (%s, %s)
          )
    ]],
        snd.mapper.db.escape(roomKey),
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
        SELECT dir, level
        FROM exits
        WHERE fromuid = %s
          AND LOWER(dir) IN ('n','north','s','south','e','east','w','west','u','up','d','down')
          AND level > 0
        ORDER BY dir
    ]], snd.mapper.db.escape(roomKey))
    return snd.mapper.db.query(sql) or {}
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

--- Persist a discovered room + exits from GMCP room.info into Aardwolf.db
-- @param roomInfo GMCP room.info table
function snd.mapper.persistDiscoveredRoom(roomInfo)
    if not roomInfo or not roomInfo.num then
        return false
    end
    if not snd.mapper.db.open() then
        return false
    end

    local roomId = tostring(roomInfo.num)
    local areaKey = tostring(roomInfo.zone or "")
    local roomName = tostring(roomInfo.name or "")
    local terrain = tostring(roomInfo.terrain or "")

    local insertRoomSql = string.format(
        "INSERT OR IGNORE INTO rooms (uid, name, area, terrain, norecall, noportal) VALUES (%s, %s, %s, %s, 0, 0)",
        snd.mapper.db.escape(roomId),
        snd.mapper.db.escape(roomName),
        snd.mapper.db.escape(areaKey),
        snd.mapper.db.escape(terrain)
    )
    snd.mapper.db.conn:execute(insertRoomSql)

    local updateRoomSql = string.format(
        "UPDATE rooms SET name = %s, area = %s, terrain = %s WHERE uid = %s",
        snd.mapper.db.escape(roomName),
        snd.mapper.db.escape(areaKey),
        snd.mapper.db.escape(terrain),
        snd.mapper.db.escape(roomId)
    )
    snd.mapper.db.conn:execute(updateRoomSql)

    local exits = roomInfo.exits
    if type(exits) == "table" then
        for dir, toUid in pairs(exits) do
            local toRoom = tonumber(toUid)
            if toRoom and toRoom > 0 then
                -- Preserve any existing manual lock level when refreshing discovered exits.
                local insertExitSql = string.format(
                    "INSERT OR IGNORE INTO exits (dir, fromuid, touid, level) VALUES (%s, %s, %s, 0)",
                    snd.mapper.db.escape(tostring(dir)),
                    snd.mapper.db.escape(roomId),
                    snd.mapper.db.escape(tostring(toRoom))
                )
                snd.mapper.db.conn:execute(insertExitSql)

                local updateExitSql = string.format(
                    "UPDATE exits SET touid = %s WHERE fromuid = %s AND dir = %s",
                    snd.mapper.db.escape(tostring(toRoom)),
                    snd.mapper.db.escape(roomId),
                    snd.mapper.db.escape(tostring(dir))
                )
                snd.mapper.db.conn:execute(updateExitSql)
            end
        end
    end

    return true
end

snd.mapper.pendingPersists = snd.mapper.pendingPersists or {}

function snd.mapper.bufferRoomPersist(ri)
    if not ri or not ri.num then return end
    snd.mapper.pendingPersists[tostring(ri.num)] = ri
end

function snd.mapper.flushPendingPersists()
    local pending = snd.mapper.pendingPersists
    if not pending or next(pending) == nil then return end
    if not snd.mapper.db.open() then return end

    snd.mapper.db.conn:execute("BEGIN")
    for _, ri in pairs(pending) do
        snd.mapper.persistDiscoveredRoom(ri)
    end
    snd.mapper.db.conn:execute("COMMIT")

    snd.mapper.pendingPersists = {}
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
        })
    end

    for _, result in ipairs(results) do
        if totalSeen > 0 then
            result.percentage = (result.seen_count or 0) / totalSeen
        else
            result.percentage = 0
        end
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
        local countByRoom = {}
        local sum = 0
        local select = string.format(
            "SELECT roomid, seen_count FROM mobs WHERE mob = %s AND roomid in (%s);",
            snd.db.escape(mobName),
            table.concat(roomidList, ",")
        )

        local rowsSeen = snd.db.query(select) or {}
        for _, row in ipairs(rowsSeen) do
            local roomId = tonumber(row.roomid)
            local seen = tonumber(row.seen_count) or 0
            if roomId then
                countByRoom[roomId] = seen
                sum = sum + seen
            end
        end

        for _, result in ipairs(results) do
            result.seen_count = countByRoom[result.rmid] or 0
            if sum > 0 then
                result.percentage = result.seen_count / sum
            else
                result.percentage = 0
            end
        end

        table.sort(results, function(a, b)
            if (a.seen_count or 0) > (b.seen_count or 0) then
                return true
            elseif (a.seen_count or 0) < (b.seen_count or 0) then
                return false
            else
                return (a.rmid or 0) < (b.rmid or 0)
            end
        end)
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

    local quickWhere = snd.nav and snd.nav.quickWhere or nil
    local qwTargetLabel = ""
    if quickWhere then
        qwTargetLabel = snd.utils and snd.utils.trim and snd.utils.trim(quickWhere.requestedKeyword or quickWhere.lookupKeyword or "")
            or tostring(quickWhere.requestedKeyword or quickWhere.lookupKeyword or "")
    end
    if qwTargetLabel == "" and snd.targets and snd.targets.current and snd.targets.current.name then
        qwTargetLabel = snd.targets.current.name
    end

    cecho(string.format("\n<gray>XCP  %-38s  %-7s  %-6s", "Location", "(uid)", ""))
    if hasChance then
        noteWidth = noteWidth - 11
        cecho(string.format("  %-9s", "(chance)"))
    end
    cecho("  Notes<reset>\n")
    if chipsEnabled then
        local showQuickWhereChip = false
        if quickWhere then
            showQuickWhereChip = (quickWhere.active == true)
                or (type(quickWhere.rooms) == "table" and #quickWhere.rooms > 0)
                or (qwTargetLabel ~= "")
        end
        if showQuickWhereChip then
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
function snd.mapper.setBouncePortal(portalDir, portalDestUid)
    snd.mapper.config.bouncePortal = {
        dir = portalDir,
        uid = portalDestUid
    }
    snd.utils.infoNote("Bounce portal set: " .. portalDir)
end

--- Set bounce recall (for noportal rooms)
-- @param recallDir Recall command
-- @param recallDestUid Destination room uid
function snd.mapper.setBounceRecall(recallDir, recallDestUid)
    snd.mapper.config.bounceRecall = {
        dir = recallDir,
        uid = recallDestUid
    }
    snd.utils.infoNote("Bounce recall set: " .. recallDir)
end

-------------------------------------------------------------------------------
-- Pathfinding
-------------------------------------------------------------------------------

--- Find path between two rooms with portal support
-- @param src Source room uid
-- @param dst Destination room uid
-- @param noPortals If true, don't use portals
-- @param noRecalls If true, don't use recall
-- @return Path table, depth, or nil if no path
function snd.mapper.findPath(src, dst, noPortals, noRecalls, ignoreLockedExits)
    if not snd.mapper.db.open() then
        return nil
    end
    
    src = tostring(src)
    dst = tostring(dst)
    snd.utils.debugNote(string.format(
        "findPath start src=%s dst=%s noPortals=%s noRecalls=%s ignoreLocked=%s",
        src,
        dst,
        tostring(noPortals == true),
        tostring(noRecalls == true),
        tostring(ignoreLockedExits == true)
    ))
    
    if src == dst then
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
    local chaosWhere = gqActive and "(fromuid <> '*' OR ifnull(chaos, 'no') <> 'yes')" or "1=1"
    
    -- Check for direct one-room path first
    local directPath = snd.mapper.checkDirectPath(src, dst, myLevel, ignoreLockedExits)
    if directPath then
        snd.utils.debugNote("findPath direct one-room path found.")
        return directPath, 1
    end
    
    -- BFS pathfinding (backwards from destination)
    local depth = 0
    local maxDepth = snd.mapper.config.maxSearchDepth
    local roomSets = {}
    local roomsList = {snd.mapper.db.escape(dst)}
    local visited = ""
    local found = false
    local foundDepth = 0
    local foundFrom = nil
    local srcRoomInfo = snd.mapper.getRoomInfo(src)
    
    -- Build initial visited set
    if noPortals then
        visited = snd.mapper.db.escape("*") .. ","
    end
    if noRecalls then
        visited = visited .. snd.mapper.db.escape("**") .. ","
    end
    visited = visited .. table.concat(roomsList, ",")
    
    while not found and depth < maxDepth do
        depth = depth + 1
        
        if depth > 1 then
            local prevSet = roomSets[depth - 1] or {}
            roomsList = {}
            for _, v in pairs(prevSet) do
                table.insert(roomsList, snd.mapper.db.escape(v.fromuid))
            end
        end
        
        if #roomsList == 0 then
            break
        end
        
        -- Update visited
        visited = visited .. "," .. table.concat(roomsList, ",")
        
        -- Query exits leading to rooms in our current set
        local sql = string.format([[
            SELECT fromuid, touid, dir FROM exits 
            WHERE touid IN (%s) 
            AND fromuid NOT IN (%s) 
            AND %s
            AND %s
            ORDER BY %s
        ]], table.concat(roomsList, ","), visited, levelWhere, chaosWhere, snd.mapper.exitPreferenceOrderSql("dir"))
        
        local results = snd.mapper.db.query(sql) or {}
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
                    dir = row.dir
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

        if depthCandidates.src then
            foundFrom = src
            found = true
            foundDepth = depth
            snd.utils.debugNote(string.format("findPath connected from source at depth=%d", depth))
        elseif depthCandidates.portal or depthCandidates.recall then
            local srcNoPortal = srcRoomInfo and tonumber(srcRoomInfo.noportal) == 1 or false
            local srcNoRecall = srcRoomInfo and tonumber(srcRoomInfo.norecall) == 1 or false

            local portalAllowed = depthCandidates.portal and not srcNoPortal
            local recallAllowed = depthCandidates.recall and not srcNoRecall
            snd.utils.debugNote(string.format(
                "findPath jump candidates depth=%d portal=%s recall=%s srcNoPortal=%s srcNoRecall=%s",
                depth,
                tostring(depthCandidates.portal ~= nil),
                tostring(depthCandidates.recall ~= nil),
                tostring(srcNoPortal),
                tostring(srcNoRecall)
            ))

            if portalAllowed and recallAllowed then
                if depthCandidates.portal.dirLen < depthCandidates.recall.dirLen then
                    foundFrom = "*"
                elseif depthCandidates.recall.dirLen < depthCandidates.portal.dirLen then
                    foundFrom = "**"
                elseif depthCandidates.portal.order < depthCandidates.recall.order then
                    foundFrom = "*"
                else
                    foundFrom = "**"
                end
            elseif portalAllowed then
                foundFrom = "*"
            elseif recallAllowed then
                foundFrom = "**"
            end

            if foundFrom then
                found = true
                foundDepth = depth
                snd.utils.debugNote("findPath selected jump origin from '" .. tostring(foundFrom) .. "'")
            end
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
            
            if (foundFrom == "*" and srcNoPortal) or (foundFrom == "**" and srcNoRecall) then
                -- Need to use bounce portal/recall
                if not srcNoRecall and snd.mapper.config.bounceRecall then
                    table.insert(path, snd.mapper.config.bounceRecall)
                    if tostring(dst) == tostring(snd.mapper.config.bounceRecall.uid) then
                        return path, foundDepth
                    end
                elseif not srcNoPortal and snd.mapper.config.bouncePortal then
                    table.insert(path, snd.mapper.config.bouncePortal)
                    if tostring(dst) == tostring(snd.mapper.config.bouncePortal.uid) then
                        return path, foundDepth
                    end
                else
                    -- Need to walk to nearest portalable/recallable room
                    local jumpRoom = snd.mapper.findNearestJumpRoom(src, dst, foundFrom, ignoreLockedExits)
                    if jumpRoom then
                        snd.utils.debugNote("findPath restricted source: nearest jump room candidate " .. tostring(jumpRoom))
                        local walkPath = snd.mapper.findPath(src, jumpRoom, true, true, ignoreLockedExits)
                        if walkPath then
                            for _, step in ipairs(walkPath) do
                                table.insert(path, step)
                            end
                            local portalPath = snd.mapper.findPath(jumpRoom, dst, nil, nil, ignoreLockedExits)
                            if portalPath then
                                for _, step in ipairs(portalPath) do
                                    table.insert(path, step)
                                end
                            end
                            snd.utils.debugNote(string.format(
                                "findPath restricted source resolved via jump room=%s walkSteps=%d",
                                tostring(jumpRoom),
                                #walkPath
                            ))
                            return path, foundDepth
                        end
                    end
                    snd.utils.debugNote("findPath restricted source failed: no jump room route.")
                    return nil  -- Can't find path from restricted room
                end
            end
        end
    end
    
    -- Build path from found room to destination
    local firstStep = {dir = currentRoom.dir, uid = currentRoom.touid}
    if foundFrom == "*" then
        firstStep.travelType = "portal"
    elseif foundFrom == "**" then
        firstStep.travelType = "recall"
    end
    table.insert(path, firstStep)
    
    local nextRoom = currentRoom.touid
    while foundDepth > 1 do
        foundDepth = foundDepth - 1
        currentRoom = roomSets[foundDepth][nextRoom]
        if currentRoom then
            nextRoom = currentRoom.touid
            table.insert(path, {dir = currentRoom.dir, uid = currentRoom.touid})
        end
    end
    snd.utils.debugNote(string.format("findPath success steps=%d searchDepth=%d", #path, depth))
    
    return path, depth
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

    snd.utils.infoNote(string.format("Marked room %s as %s.", roomKey, safeFlag))
    return true, true
end

function snd.mapper.onPortalBlocked()
    if snd.mapper.isInCombat and snd.mapper.isInCombat() then
        snd.mapper.consumeRestrictionMark("portal")
        snd.utils.debugNote("Ignoring portal blocked trigger while in combat.")
        return
    end
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
end

function snd.mapper.onRecallBlocked()
    if snd.mapper.isInCombat and snd.mapper.isInCombat() then
        snd.mapper.consumeRestrictionMark("recall")
        snd.utils.debugNote("Ignoring recall blocked trigger while in combat.")
        return
    end
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
end

function snd.mapper.handleBlockedTravel(blockedType)
    local destination = snd.mapper.goingToRoom or (snd.nav and snd.nav.goingToRoom)
    if not destination then
        return
    end

    local currentRoom = snd.room and snd.room.current and snd.room.current.rmid
    if (not currentRoom or currentRoom == "-1") and gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.num then
        currentRoom = tostring(gmcp.room.info.num)
    end
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

    -- If both flags are set, find nearest room that does NOT have both flags
    -- at the same time, then continue to destination in this same xrt.
    if currentNoPortal and currentNoRecall then
        snd.utils.debugNote("current room is both norecall/noportal; trying outward jump-room expansion first.")
        local combined, chosenType, closestRoom = snd.mapper.buildOutwardJumpRoute(currentRoom, destination, nil)
        if not combined or #combined == 0 then
            snd.utils.infoNote("You couldn't find a nearby room that allows recall or portal from " .. currentRoom .. ".")
            snd.utils.debugNote("outward jump-room expansion failed from room " .. currentRoom .. ".")
            return false
        end
        snd.utils.infoNote("Rerouting via closest viable room " .. tostring(closestRoom) .. " using " .. tostring(chosenType) .. ".")
        snd.mapper.executePath(combined)
        return true
    end

    local bounceStep = nil
    if blockedType == "recall" then
        local roomInfo = snd.mapper.getRoomInfo(currentRoom)
        local blockedPortal = roomInfo and tonumber(roomInfo.noportal) == 1 or false
        if not blockedPortal then
            bounceStep = snd.mapper.config.bouncePortal
        end
    elseif blockedType == "portal" then
        local roomInfo = snd.mapper.getRoomInfo(currentRoom)
        local blockedRecall = roomInfo and tonumber(roomInfo.norecall) == 1 or false
        if not blockedRecall then
            bounceStep = snd.mapper.config.bounceRecall
        end
    end

    local reroutePath = nil
    if bounceStep and bounceStep.dir and bounceStep.uid then
        local nextLeg = nil
        if tostring(bounceStep.uid) ~= destination then
            nextLeg = snd.mapper.findPath(tostring(bounceStep.uid), destination, nil, nil)
        else
            nextLeg = {}
        end

        if nextLeg then
            reroutePath = {
                {
                    dir = bounceStep.dir,
                    uid = bounceStep.uid,
                    travelType = (blockedType == "recall") and "portal" or "recall",
                }
            }
            for _, step in ipairs(nextLeg) do
                table.insert(reroutePath, step)
            end
            snd.utils.debugNote("Blocked " .. blockedType .. " - rerouting via configured bounce " .. ((blockedType == "recall") and "portal" or "recall") .. ".")
        end
    end

    if not reroutePath then
        local forceNoPortals = (blockedType == "portal")
        local forceNoRecalls = (blockedType == "recall")
        reroutePath = snd.mapper.findPath(currentRoom, destination, forceNoPortals, forceNoRecalls, nil)
    end

    if not reroutePath then
        local reroute, viaRoom, mode = snd.mapper.findNearestAlternateRoute(currentRoom, destination, blockedType, nil)
        if reroute and #reroute > 0 then
            reroutePath = reroute
            if mode == "preferred" then
                snd.utils.infoNote("Rerouting via nearby room " .. tostring(viaRoom) .. " to use " .. ((blockedType == "recall") and "portal" or "recall") .. ".")
            else
                snd.utils.infoNote("Rerouting via nearby room " .. tostring(viaRoom) .. " (alternate jump unavailable there, using best available route).")
            end
        end
    end

    if not reroutePath then
        reroutePath = snd.mapper.findPath(currentRoom, destination, nil, nil)
    end

    if reroutePath and #reroutePath > 0 then
        snd.mapper.executePath(reroutePath)
        return true
    else
        snd.utils.infoNote("You couldn't find a path to " .. destination .. " from here.")
        snd.utils.infoNote("Blocked " .. blockedType .. " and no alternate route found from room " .. currentRoom .. ".")
        return false
    end
end

--- Check for direct one-room path
function snd.mapper.checkDirectPath(src, dst, level, ignoreLockedExits)
    local where = ignoreLockedExits and "" or string.format(" AND level <= %d", level)
    local sql = string.format([[
        SELECT dir FROM exits 
        WHERE fromuid = %s AND touid = %s%s
        ORDER BY %s LIMIT 1
    ]], snd.mapper.db.escape(src), snd.mapper.db.escape(dst), where, snd.mapper.exitPreferenceOrderSql("dir"))
    
    local results = snd.mapper.db.query(sql)
    if results and #results > 0 then
        return {{dir = results[1].dir, uid = dst}}
    end
    return nil
end

function snd.mapper.buildOutwardJumpRoute(sourceRoom, destination, ignoreLockedExits)
    sourceRoom = tostring(sourceRoom or "")
    destination = tostring(destination or "")
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

    local closestRoom, walkPath = snd.mapper.findNearestRoomWithoutBothFlags(sourceRoom, ignoreLockedExits)
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

    local recallLeg = nil
    local portalLeg = nil
    if not closestNoRecall then
        recallLeg = snd.mapper.findPath(tostring(closestRoom), destination, true, nil, ignoreLockedExits) -- recall only
    end
    if not closestNoPortal then
        portalLeg = snd.mapper.findPath(tostring(closestRoom), destination, nil, true, ignoreLockedExits) -- portal only
    end

    local chosenLeg = nil
    local chosenType = nil
    if recallLeg and #recallLeg > 0 and portalLeg and #portalLeg > 0 then
        if (#walkPath + #recallLeg) <= (#walkPath + #portalLeg) then
            chosenLeg, chosenType = recallLeg, "recall"
        else
            chosenLeg, chosenType = portalLeg, "portal"
        end
    elseif recallLeg and #recallLeg > 0 then
        chosenLeg, chosenType = recallLeg, "recall"
    elseif portalLeg and #portalLeg > 0 then
        chosenLeg, chosenType = portalLeg, "portal"
    else
        chosenLeg = snd.mapper.findPath(tostring(closestRoom), destination, nil, nil, ignoreLockedExits)
        chosenType = "fallback"
    end

    if not chosenLeg or #chosenLeg == 0 then
        snd.utils.debugNote("outward jump-route: no continuation from candidate room " .. tostring(closestRoom))
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
function snd.mapper.findNearestJumpRoom(src, dst, targetType, ignoreLockedExits)
    local depth = 0
    local maxDepth = snd.mapper.config.maxSearchDepth
    local roomsList = {snd.mapper.db.escape(src)}
    local visited = table.concat(roomsList, ",")
    local myLevel = snd.char.level or 201
    local levelWhere = ignoreLockedExits and "1=1" or string.format("exits.level <= %d", myLevel)
    
    while depth < maxDepth do
        depth = depth + 1
        
        local sql = string.format([[
            SELECT exits.fromuid, exits.touid, exits.dir, rooms.norecall, rooms.noportal 
            FROM exits 
            JOIN rooms ON rooms.uid = exits.touid 
            WHERE exits.fromuid IN (%s) 
            AND exits.touid NOT IN (%s) 
            AND %s
            ORDER BY %s
        ]], table.concat(roomsList, ","), visited, levelWhere, snd.mapper.exitPreferenceOrderSql("exits.dir"))
        
        local results = snd.mapper.db.query(sql) or {}
        roomsList = {}
        
        for _, row in ipairs(results) do
            local touid = tostring(row.touid or "")
            if touid ~= "" and touid ~= "-1" then
                table.insert(roomsList, snd.mapper.db.escape(touid))
            end
            
            local canUse = false
            if touid == "-1" then
                canUse = false
            elseif targetType == "*" and tonumber(row.noportal) ~= 1 then
                canUse = true
            elseif targetType == "**" and tonumber(row.norecall) ~= 1 then
                canUse = true
            elseif touid == dst then
                canUse = true
            end
            
            if canUse then
                return touid
            end
        end
        
        if #roomsList == 0 then
            break
        end
        
        visited = visited .. "," .. table.concat(roomsList, ",")
    end
    
    return nil
end

function snd.mapper.findNearestRoomWithoutFlag(src, restrictionFlag, ignoreLockedExits)
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
    local maxDepth = snd.mapper.config.maxSearchDepth
    local queue = {{room = source, depth = 0}}
    local head = 1
    local visited = {[source] = true}
    local parents = {}

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
                ORDER BY %s
            ]], snd.mapper.db.escape(node.room), levelWhere, snd.mapper.exitPreferenceOrderSql("dir"))
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

function snd.mapper.findNearestRoomWithoutBothFlags(src, ignoreLockedExits)
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
    local maxDepth = snd.mapper.config.maxSearchDepth
    local queue = {{room = source, depth = 0}}
    local head = 1
    local visited = {[source] = true}
    local parents = {}

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
                ORDER BY %s
            ]], snd.mapper.db.escape(node.room), levelWhere, snd.mapper.exitPreferenceOrderSql("dir"))
            local exits = snd.mapper.db.query(sql) or {}
            for _, ex in ipairs(exits) do
                local nextRoom = tostring(ex.touid or "")
                if nextRoom ~= "" and nextRoom ~= "-1" and not visited[nextRoom] then
                    visited[nextRoom] = true
                    parents[nextRoom] = {prev = node.room, dir = ex.dir}

                    local roomInfo = snd.mapper.getRoomInfo(nextRoom)
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

function snd.mapper.findNearestAlternateRoute(src, dst, blockedType, ignoreLockedExits)
    local source = tostring(src or "")
    local destination = tostring(dst or "")
    if source == "" or destination == "" then
        return nil
    end

    local requiredFlag = (blockedType == "recall") and "noportal" or "norecall"
    local forceNoPortals = (blockedType == "portal")
    local forceNoRecalls = (blockedType == "recall")
    local myLevel = snd.char.level or 201
    local maxDepth = snd.mapper.config.maxSearchDepth
    local maxCandidates = 40
    local testedCandidates = 0

    local queue = {{room = source, depth = 0}}
    local head = 1
    local visited = {[source] = true}
    local parents = {}

    while head <= #queue do
        local node = queue[head]
        head = head + 1

        local roomInfo = snd.mapper.getRoomInfo(node.room)
        local canUseAlternate = roomInfo and tonumber(roomInfo[requiredFlag]) ~= 1
        if canUseAlternate then
            testedCandidates = testedCandidates + 1
            local leg = snd.mapper.findPath(node.room, destination, forceNoPortals, forceNoRecalls, ignoreLockedExits)
            if leg and #leg > 0 then
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

            -- If preferred jump type is not available from this room,
            -- still allow a general route so we can move out of the blocked room.
            local fallbackLeg = snd.mapper.findPath(node.room, destination, nil, nil, ignoreLockedExits)
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
                ORDER BY %s
            ]], snd.mapper.db.escape(node.room), levelWhere, snd.mapper.exitPreferenceOrderSql("dir"))
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

--- Execute a path (send commands)
-- Handles cardinal directions with 'run', special exits with ';;', and wait() with tempTimer
-- @param path Path table from findPath
function snd.mapper.executePath(path)
    if not path or #path == 0 then
        return
    end

    snd.mapper.pathExecutionSerial = (tonumber(snd.mapper.pathExecutionSerial) or 0) + 1
    local executionSerial = snd.mapper.pathExecutionSerial

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
        local currentRoom = snd.room and snd.room.current and snd.room.current.rmid
        if (not currentRoom or currentRoom == "-1") and gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.num then
            currentRoom = tostring(gmcp.room.info.num)
        end
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
    local currentGroup = {commands = {}, delayAfter = 0, waitRoomId = nil, executeRoomId = nil}
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
        local stepHasWait = false
        local encounteredWait = false
        for _, token in ipairs(parts) do
            if tostring(token):match("^%s*wait%((%d+%.?%d*)%)%s*$") then
                stepHasWait = true
                break
            end
        end
        if stepHasWait then
            flushCardinals()
            if #currentGroup.commands > 0 then
                table.insert(groups, currentGroup)
                currentGroup = {commands = {}, delayAfter = 0, waitRoomId = nil, executeRoomId = nil}
            end
        end

		for _, dir in ipairs(parts) do
			local dirLower = dir:lower()

			-- Check if this is a wait() command
			local waitTime = dir:match("^wait%((%d+%.?%d*)%)$")
				if waitTime then
					flushCardinals()
					currentGroup.delayAfter = tonumber(waitTime)
                if not currentGroup.waitRoomId or currentGroup.waitRoomId == "-1" then
                    currentGroup.waitRoomId = tostring(stepSourceRoom or "-1")
                end
					table.insert(groups, currentGroup)
					currentGroup = {commands = {}, delayAfter = 0, waitRoomId = nil, executeRoomId = nil}
                    encounteredWait = true

			elseif cardinalDirs[dirLower] then
				-- cardinal movement token (n/s/e/w/u/d)
				table.insert(cardinalBuffer, dirLower)

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
                })
			end
		end
        if step.uid then
            simulatedRoom = tostring(step.uid)
        end
	end

    
    -- Flush remaining cardinals and add final group
    flushCardinals()
    if #currentGroup.commands > 0 then
        table.insert(groups, currentGroup)
    end
    
    -- Execute groups with proper timing
    if #groups == 0 then
        return
    end

    local function sendCommand(cmd, travelType)
        local currentRoom = snd.room and snd.room.current and snd.room.current.rmid
        if (not currentRoom or currentRoom == "-1") and gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.num then
            currentRoom = tostring(gmcp.room.info.num)
        end
        if (travelType == "portal" or travelType == "recall") and snd.mapper.isInCombat and snd.mapper.isInCombat() then
            snd.mapper.consumeRestrictionMark("portal")
            snd.mapper.consumeRestrictionMark("recall")
            snd.utils.infoNote("In combat (state=8). Stopping xrt before " .. travelType .. ".")
            snd.mapper.goingToRoom = nil
            snd.nav.goingToRoom = nil
            return false
        end
        if travelType and currentRoom and currentRoom ~= "-1" then
            snd.mapper.queueRestrictionMark(travelType, currentRoom)
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
            local ok = sendCommand(entry.text, entry.travelType)
            if ok == false then
                return false
            end
        end
        return true
    end
    
    -- Execute path groups sequentially so wait() never races ahead of queued actions.
    -- If a wait expires while in combat, hold execution until combat clears.
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
                return
            end

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
                    snd.utils.debugNote("Holding group until room " .. executeRoomId .. " (current " .. tostring(currentRoomId) .. ").")
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

--- Go to a room using portal-aware pathfinding
-- @param roomId Destination room uid
-- @param usePortals Whether to use portals (default: true)
function snd.mapper.gotoRoom(roomId, usePortals, ignoreLockedExits, iterativeMode)
    if not roomId then
        snd.utils.infoNote("No room specified")
        return false
    end
    
    roomId = tostring(roomId)
    usePortals = (usePortals ~= false)  -- Default true
    iterativeMode = (iterativeMode == true)

    -- Get current room
    local currentRoom = snd.room.current.rmid
    if not currentRoom or currentRoom == "-1" then
        -- Try to get from GMCP; uid=-1 means a clan/unmapped room.
        if gmcp and gmcp.room and gmcp.room.info then
            local n = tonumber(gmcp.room.info.num)
            if n == -1 then
                currentRoom = build_nomap_uid(gmcp.room.info.name, gmcp.room.info.zone or gmcp.room.info.area)
            else
                currentRoom = tostring(gmcp.room.info.num)
            end
        end
    end

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
        if snd.commands and snd.commands.handleAlreadyInRoom and snd.commands.handleAlreadyInRoom(roomId) then
            return true
        end

        snd.utils.infoNote("Already in room " .. roomId)
        if snd.onDestinationArrived then
            snd.onDestinationArrived()
        end
        return true
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
        if snd.mapper.handleBlockedTravel(pendingBlocked.blockedType) then
            return true
        end
    elseif pendingBlocked and tostring(pendingBlocked.destination or "") == roomId then
        snd.utils.debugNote("pending blocked travel cleared (room mismatch). current=" .. tostring(currentRoom) .. " expected=" .. tostring(pendingBlocked.roomId or "?"))
        snd.mapper.pendingBlockedTravel = nil
    end
    
    -- Try our pathfinding first
    local noPortals = not usePortals or not snd.mapper.config.usePortals
    local noRecalls = not snd.mapper.config.useRecall

    -- Clan rooms (nomap_ prefix) cannot use portals or recalls; walk-only via mapped cexits.
    if currentRoom and currentRoom:match("^nomap_") then
        noPortals = true
        noRecalls = true
    end

    if usePortals then
        local outwardPath, outwardType, outwardRoom = snd.mapper.buildOutwardJumpRoute(currentRoom, roomId, ignoreLockedExits)
        if outwardPath and #outwardPath > 0 then
            snd.utils.debugNote(string.format(
                "gotoRoom using outward expansion first: via room=%s mode=%s steps=%d",
                tostring(outwardRoom or "?"),
                tostring(outwardType or "?"),
                #outwardPath
            ))
            snd.mapper.goingToRoom = roomId
            snd.nav.goingToRoom = roomId
            snd.mapper.executePath(outwardPath)
            return true
        end
    end

    local path, depth = snd.mapper.findPath(currentRoom, roomId, noPortals, noRecalls, ignoreLockedExits)

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
                        local nowRoom = snd.room and snd.room.current and snd.room.current.rmid
                        if (not nowRoom or nowRoom == "-1") and gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.num then
                            nowRoom = tostring(gmcp.room.info.num)
                        end
                        nowRoom = tostring(nowRoom or "")
                        if nowRoom ~= "" and nowRoom ~= "-1" and nowRoom ~= expectedRoom then
                            snd.mapper.gotoRoom(roomId, usePortals, ignoreLockedExits, true)
                            return
                        end
                        if attempt < 2 then
                            snd.utils.debugNote("xrt iterative: room did not change after step; waiting before recompute (attempt " .. tostring(attempt + 1) .. ").")
                            continueIterative(attempt + 1)
                        else
                            snd.utils.infoNote("xrt iterative stopped: room did not change after command '" .. tostring(step.dir or "?") .. "'.")
                            snd.mapper.goingToRoom = nil
                            snd.nav.goingToRoom = nil
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
        snd.utils.infoNote("You couldn't find a path to " .. roomId .. " from here.")
        snd.mapper.goingToRoom = nil
        snd.nav.goingToRoom = nil
        return false
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
-- Command Integration
-------------------------------------------------------------------------------

--- Override snd.commands.gotoTarget to use portal navigation
local originalGotoTarget = snd.commands and snd.commands.gotoTarget

function snd.commands.gotoTarget()
    -- Use portal-aware navigation
    return snd.mapper.gotoTarget()
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
        uid = portal.touid
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
            snd.mapper.setBouncePortal(portal.dir, portal.touid)
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
        uid = portal.touid
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
    if (not currentRoom or currentRoom == "-1") and gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.num then
        currentRoom = tostring(gmcp.room.info.num)
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
function snd.mapper.xrt(dest)
    if not dest or dest == "" then
        cecho("<yellow>[MMAPPER]<reset> Usage: xrt <area|roomid>\n")
        cecho("<dim_gray>Examples: xrt aylor, xrt academy, xrt 32418<reset>\n")
        return false
    end
    
    dest = dest:lower():trim()
    
    -- Check if it's a room number
    local roomNum = tonumber(dest)
    if roomNum then
        cecho("<yellow>[MMAPPER]<reset> Going to room " .. roomNum .. "\n")
        snd.mapper.debugXrtDecision(dest, roomNum, "numeric destination")
        return snd.mapper.gotoRoom(roomNum)
    end
    
    -- Try exact match on area key first (prefer snd.db startRoom data)
    if snd.db and snd.db.getAreaStartRoom then
        local startRoom = tonumber(snd.db.getAreaStartRoom(dest)) or -1
        if startRoom > 0 then
            cecho("<yellow>[MMAPPER]<reset> Going to " .. dest .. " (room " .. startRoom .. ")\n")
            snd.mapper.debugXrtDecision(dest, startRoom, "area start room from snd.db.getAreaStartRoom")
            return snd.mapper.gotoRoom(startRoom)
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
                    return snd.mapper.gotoRoom(roomId)
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
            return snd.mapper.gotoRoom(areaData.start)
        end
        
        -- Try partial match on area names
        for areaKey, data in pairs(snd.data.areaDefaultStartRooms) do
            if areaKey:lower():find(dest, 1, true) and data.start then
                cecho("<yellow>[MMAPPER]<reset> Going to " .. areaKey .. " (room " .. data.start .. ")\n")
                snd.mapper.debugXrtDecision(dest, data.start, "bundled partial area match")
                return snd.mapper.gotoRoom(data.start)
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
            return snd.mapper.gotoRoom(roomId)
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
        cecho("<yellow>[MMAPPER]<reset> Force-going to room " .. roomNum .. " (ignoring exits.level locks)\n")
        return snd.mapper.gotoRoom(roomNum, true, true)
    end

    if snd.db and snd.db.getAreaStartRoom then
        local startRoom = tonumber(snd.db.getAreaStartRoom(dest)) or -1
        if startRoom > 0 then
            cecho("<yellow>[MMAPPER]<reset> Force-going to " .. dest .. " (room " .. startRoom .. ", ignoring exits.level locks)\n")
            return snd.mapper.gotoRoom(startRoom, true, true)
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
                    cecho("<yellow>[MMAPPER]<reset> Force-going to " .. areaKey .. " (room " .. roomId .. ", ignoring exits.level locks)\n")
                    return snd.mapper.gotoRoom(roomId, true, true)
                end
            end
        end
    end

    if snd.data and snd.data.areaDefaultStartRooms then
        local areaData = snd.data.areaDefaultStartRooms[dest]
        if areaData and areaData.start then
            cecho("<yellow>[MMAPPER]<reset> Force-going to " .. dest .. " (room " .. areaData.start .. ", ignoring exits.level locks)\n")
            return snd.mapper.gotoRoom(areaData.start, true, true)
        end

        for areaKey, data in pairs(snd.data.areaDefaultStartRooms) do
            if areaKey:lower():find(dest, 1, true) and data.start then
                cecho("<yellow>[MMAPPER]<reset> Force-going to " .. areaKey .. " (room " .. data.start .. ", ignoring exits.level locks)\n")
                return snd.mapper.gotoRoom(data.start, true, true)
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
            cecho("<yellow>[MMAPPER]<reset> Force-going to area matching '" .. dest .. "' (room " .. roomId .. ", ignoring exits.level locks)\n")
            return snd.mapper.gotoRoom(roomId, true, true)
        end
    end

    cecho("<red>[MMAPPER]<reset> Unknown area: " .. dest .. "\n")
    return false
end

--- Walk to a room or area WITHOUT using portals (pure walking)
-- Uses snd.db for area lookup and Aardwolf.db for pathfinding
-- Does NOT use Mudlet's internal map for navigation
-- @param dest Destination - room number or area name
function snd.mapper.walkTo(dest)
    if not dest or dest == "" then
        cecho("<yellow>[MMAPPER]<reset> Usage: walkto <roomid|areaname>\n")
        cecho("<dim_gray>Examples: walkto 32418, walkto aylor, walkto farm<reset>\n")
        return false
    end
    
    dest = dest:lower():trim()
    
    -- Get current room
    local currentRoom = nil
    if snd.room and snd.room.current and snd.room.current.rmid then
        currentRoom = snd.room.current.rmid
    end
    if not currentRoom or currentRoom == "-1" then
        if gmcp and gmcp.room and gmcp.room.info then
            currentRoom = tostring(gmcp.room.info.num)
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
    
    -- Use snd.mapper.findPath with portals DISABLED
    cecho("<yellow>[MMAPPER]<reset> Walking to " .. displayName .. " (no portals)...\n")
    
    local path, depth = snd.mapper.findPath(currentRoom, targetRoom, true, true)  -- noPortals=true, noRecalls=true
    
    if path and #path > 0 then
        cecho("<dim_gray>[MMAPPER] Found path with " .. #path .. " steps<reset>\n")
        snd.mapper.goingToRoom = targetRoom
        snd.nav.goingToRoom = targetRoom
        snd.mapper.executePath(path)
        return true
    else
        cecho("<red>[MMAPPER]<reset> No walking path found to " .. displayName .. "\n")
        cecho("<dim_gray>The destination may not be reachable by walking alone.<reset>\n")
        return false
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
            "SELECT uid, name, area, terrain, x, y, z, norecall, noportal FROM rooms LIMIT %d OFFSET %d",
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
                    
                    -- Set coordinates if available
                    local x = tonumber(room.x) or 0
                    local y = tonumber(room.y) or 0
                    local z = tonumber(room.z) or 0
                    setRoomCoordinates(roomId, x, y, z)
                    
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
