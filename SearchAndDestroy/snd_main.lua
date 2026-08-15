snd = snd or {}


snd.version = "7.1.0"
snd.schemaVersion = 7
snd.fullVersion = "Search & Destroy v" .. snd.version

local function sndFileExists(path)
    if type(io.exists) == "function" then
        return io.exists(path)
    end
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return true
end

local function sndSaveFilePath()
    return getMudletHomeDir() .. "/persistence/snd_state.lua"
end

local function mergeTables(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return target
    end
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            mergeTables(target[k], v)
        else
            target[k] = v
        end
    end
    return target
end

local function loadPersistedStateEarly()
    local path = sndSaveFilePath()
    if not sndFileExists(path) or type(table.load) ~= "function" then
        return nil
    end

    local success, state = pcall(function()
        local t = {}
        table.load(path, t)
        return t
    end)
    if success and type(state) == "table" then
        return state
    end
    return nil
end

local persistedStateEarly = loadPersistedStateEarly()
local existingConfig = type(snd.config) == "table" and snd.config or nil
local wasInitialized = snd.initialized == true


local defaultConfig = {
    debugMode = false,
    
    silentMode = false,
    
    speed = "run",

    areaGuard = {
        enabled = false,
        allowance = 30,
    },
    
    killCommand = "kill",
    -- Target syntax: auto, skill, cast, or legacy raw.
    killTargetMode = "auto",
    
    anex = {
        automatic = true,
        tnlCutoff = 0,
    },
    
    vidblain = {
        enabled = false,
        level = 300,
    },
    
    gqExtraAliases = true,
    
    nxAction = "qs",
    
    xcpActionMode = "qw",
    
    overwriteCon = true,
    
    soundEnabled = false,
    soundVolume = 100,
    
    express = {
        enabled = true,
        minKillCount = 2,
    },
    
    autocheck = {
        mode = "on",
        smartKills = 3,
        cpKillCounter = 0,
        gqKillCounter = 0,
    },

    mobTagDebug = false,

    tableNotes = false,
    tableWidth = 80,
    
    window = {
        enabled = true,
        posX = 0,
        posY = 0,
        width = 325,
        height = 280,
        font = "Lucida Sans Unicode",
        fontSize = 8,
    },
    
    autoUpdateCheck = true,

    areaColors = true,

    reportChannel = "default",

    mapper = {
        bouncePortalId = nil,
        bounceRecallId = nil,
        bouncePortalCommand = nil,
        bounceRecallCommand = nil,
    },

    mapperUI = {
        links = true,
        hover = true,
        visited = true,
        chips = true,
    },
}

snd.config = defaultConfig
if wasInitialized and existingConfig then
    mergeTables(snd.config, existingConfig)
end
if persistedStateEarly and type(persistedStateEarly.config) == "table" then
    mergeTables(snd.config, persistedStateEarly.config)
end

local removedNxActionFallbacks = {
    con = "none",
    scanhere = "none",
    scan = "smartscan",
}

local validNxActions = {
    smartscan = true,
    qs = true,
    none = true,
}

function snd.normalizeNxAction(action)
    local normalized = tostring(action or ""):lower()
    if validNxActions[normalized] then
        return normalized
    end
    return removedNxActionFallbacks[normalized] or "qs"
end

snd.config.nxAction = snd.normalizeNxAction(snd.config.nxAction)


snd.room = snd.room or {
    current = {
        rmid = "-1",
        arid = "-1",
        maze = 0,
        exits = {},
        name = "",
    },
    previous = {
        rmid = "-2",
        arid = "-2",
        maze = 0,
        exits = {},
        name = "",
    },
    history = {},
}


snd.roomChars = snd.roomChars or {
    active = false,
    triggerIds = nil,
}


snd.char = snd.char or {
    state = "0",
    level = 0,
    tier = 0,
    remorts = 0,
    name = "",
    class = "",
    hp = 0,
    mana = 0,
    moves = 0,
    tnl = 0,
    noexp = false,
    autoNoexpCampaignStatus = "unknown", -- unknown/pending/blocked/eligible
    autoNoexpCampaignLevel = 0,
    autoNoexpManaged = false,
    noexpPending = nil,
    noexpCommandEcho = nil,
    noexpCommandAt = 0,
}


snd.campaign = snd.campaign or {
    active = false,
    levelTaken = 0,
    historyId = 0,
    completeBy = "",
    acceptedAt = 0,
    completedToday = 0,
    completedTodayDate = "",
    targets = {},      -- Full target list from cp info
    checkList = {},    -- Current check list from cp check
    resolved = false,  -- Location/zone snapshot built for the current campaign
    canGetNew = nil,
    lastCheck = 0,
    qpReward = 0,
    goldReward = 0,
    tpReward = 0,
    trainReward = 0,
    pracReward = 0,
    dailyQpBonus = 0,
    persistedCompleteBy = "",
    persistedQpReward = 0,
    persistedGoldReward = 0,
    persistedTpReward = 0,
    persistedTrainReward = 0,
    persistedPracReward = 0,
}


snd.gquest = snd.gquest or {
    active = false,
    joined = "-1",
    started = "-1",
    extended = "-1",
    effectiveLevel = 0,
    targets = {},      -- Full target list from gq info
    checkList = {},    -- Current check list from gq check
    lastCheck = 0,
    historyId = 0,
    qpReward = 0,
    tpReward = 0,
    trainReward = 0,
    pracReward = 0,
    goldReward = 0,
    qpPerKillBonus = 0,
    qpKillBonusTotal = 0,
}


snd.quest = snd.quest or {
    active = false,
    available = false,
    target = {
        mob = "",
        area = "",
        room = "",
        keyword = "",
        status = "0",
    },
    timer = 0,
    timerEndTime = 0,
    timerTickerId = nil,
    nextQuestTime = 0,
    nextQuestRemaining = 0,
    cooldownStart = 0,
    cooldownDuration = 0,
    nextQuestLessThanMinute = false,
    nextQuestText = "",
    silentCooldownRequest = false,
    lastCooldownRequest = 0,
    readySoundTimerId = nil,
    readySoundLastPlayedAt = 0,
    blessingBonus = 0,
    pendingReward = nil,
    rewardTimer = nil,
    targetTriggerId = nil,
}


snd.history = snd.history or {
    lastRows = {},
    lastLimit = 20,
}

function snd.quest.setCooldown(waitMinutes, opts)
    local wait = tonumber(waitMinutes)
    local options = opts or {}
    if wait == nil and type(waitMinutes) == "string" then
        local normalized = waitMinutes:lower()
        wait = tonumber(normalized:match("(%d+)"))
        if wait == nil and normalized:find("less than a minute", 1, true) then
            wait = 1
            if options.lessThanMinute == nil then
                options.lessThanMinute = true
            end
            if options.text == nil then
                options.text = "Less than a minute remaining"
            end
        end
    end
    wait = wait or 0
    snd.quest.nextQuestLessThanMinute = options.lessThanMinute or false
    snd.quest.nextQuestText = options.text or ""
    if wait > 0 then
        snd.quest.cooldownStart = os.time()
        snd.quest.cooldownDuration = wait * 60
        snd.quest.nextQuestTime = snd.quest.cooldownStart + snd.quest.cooldownDuration
    else
        snd.quest.cooldownStart = 0
        snd.quest.cooldownDuration = 0
        snd.quest.nextQuestTime = 0
    end
    snd.quest.updateCooldownRemaining()
end

function snd.quest.updateCooldownRemaining()
    if not snd.quest.nextQuestTime or snd.quest.nextQuestTime <= 0 then
        snd.quest.nextQuestRemaining = 0
        return 0
    end
    local mins = math.max(0, math.ceil((snd.quest.nextQuestTime - os.time()) / 60))
    if mins <= 0 then
        snd.quest.cooldownStart = 0
        snd.quest.cooldownDuration = 0
        snd.quest.nextQuestTime = 0
        snd.quest.nextQuestRemaining = 0
        snd.quest.nextQuestLessThanMinute = false
        snd.quest.nextQuestText = "Quest Available"
        return 0
    end
    snd.quest.nextQuestRemaining = mins
    return mins
end

function snd.quest.getNextQuestMinutesRemaining()
    return snd.quest.updateCooldownRemaining()
end

function snd.quest.getNextQuestStatus()
    local mins = snd.quest.getNextQuestMinutesRemaining()
    if mins <= 0 then
        return 0, ""
    end
    if snd.quest.nextQuestLessThanMinute then
        local text = snd.quest.nextQuestText ~= "" and snd.quest.nextQuestText
            or "Less than a minute remaining"
        return mins, text
    end
    return mins, ""
end

function snd.quest.requestCooldownStatus(opts)
    if snd.quest.active then
        return
    end
    local options = opts or {}
    local silent = options.silent ~= false
    local now = os.time()
    if snd.quest.lastCooldownRequest and now - snd.quest.lastCooldownRequest < 2 then
        return
    end
    snd.quest.lastCooldownRequest = now
    snd.quest.silentCooldownRequest = silent
    send("quest time", false)
end

function snd.quest.consumeSilentCooldownRequest()
    if snd.quest.silentCooldownRequest then
        snd.quest.silentCooldownRequest = false
        return true
    end
    return false
end


snd.targets = snd.targets or {
    list = {},           -- Main target list
    ignored = {},        -- Ignored room targets
    type = "init",       -- "area" or "room" based campaign/gq
    activity = "init",   -- "cp", "gq", "quest", "none", "init"
    current = nil,       -- Current selected target
    scoped = {
        quest = nil,
        gq = nil,
        cp = nil,
    },
    lastAutoRefresh = 0, -- Timestamp for auto-refreshing target sources
    lineTriggerIds = nil, -- Target line triggers
}


snd.express = snd.express or {}

local function clearExpressTarget(target)
    if type(target) ~= "table" then return target end
    target.express = false
    target.expressRoomId = nil
    target.expressKillCount = 0
    target.expressRoomCount = 0
    return target
end

-- Express requires one proven S&D sighting room; mapper name matches do not qualify.
function snd.express.classifyTarget(target, evidenceRows)
    clearExpressTarget(target)
    if type(target) ~= "table" then return target end
    if not snd.config or not snd.config.express or snd.config.express.enabled ~= true then return target end
    if target.dead == true or target.killed == true or tonumber(target.remaining) == 0 then return target end

    local trim = snd.utils and snd.utils.trim or function(value)
        return tostring(value or ""):match("^%s*(.-)%s*$")
    end
    local mobName = trim(target.mob or target.name or "")
    local areaKey = trim(target.arid or target.area or "")
    if mobName == "" or areaKey == "" then return target end
    if not snd.db or type(snd.db.getMobLocations) ~= "function" then return target end

    local rows = evidenceRows
    if type(rows) ~= "table" then
        local ok, loadedRows = pcall(snd.db.getMobLocations, mobName, areaKey, { legacy = true })
        if not ok or type(loadedRows) ~= "table" then
            if snd.utils and snd.utils.debugNote then
                snd.utils.debugNote("Express classification failed for " .. mobName .. " in " .. areaKey)
            end
            return target
        end
        rows = loadedRows
    end

    local uniqueRooms = {}
    local roomCount = 0
    local onlyRow = nil
    local onlyRoomId = nil
    for _, row in ipairs(rows) do
        local rowArea = trim(row.zone or row.arid or "")
        if rowArea == "" or rowArea:lower() == areaKey:lower() then
            local roomId = tonumber(row.roomid or row.rmid)
            if roomId and roomId > 0 and not uniqueRooms[roomId] then
                uniqueRooms[roomId] = row
                roomCount = roomCount + 1
                onlyRow = row
                onlyRoomId = roomId
            elseif roomId and roomId > 0 and uniqueRooms[roomId] then
                local existingKills = tonumber(uniqueRooms[roomId].kill_count) or 0
                if (tonumber(row.kill_count) or 0) > existingKills then
                    uniqueRooms[roomId] = row
                    onlyRow = row
                end
            end
        end
    end

    target.expressRoomCount = roomCount
    if roomCount ~= 1 or not onlyRow then return target end

    local killCount = tonumber(onlyRow.kill_count) or 0
    target.expressKillCount = killCount
    local minimumKills = math.max(1, tonumber(snd.config.express.minKillCount) or 2)
    if killCount >= minimumKills then
        target.express = true
        target.expressRoomId = onlyRoomId
    end
    return target
end

function snd.express.reclassifyTargets()
    if snd.targets and type(snd.targets.list) == "table" then
        for _, target in ipairs(snd.targets.list) do
            snd.express.classifyTarget(target)
        end
    end
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

snd.tabs = snd.tabs or {
    active = "auto", -- auto|quest|gq|cp
}


snd.nav = snd.nav or {
    gotoArea = -1,
    gotoIndex = 0,
    gotoList = {},
    nextRoom = -1,
    goingToRoom = nil,
    nxState = nil,
    xcpLookup = nil,
    
    autoHunt = {
        direction = "",
        mob = "",
        data = {},
        active = false,
        keyword = "",
        throughPortal = false,
        lastDirection = "",
    },
    
    huntTrick = {
        index = 1,
        firstTarget = true,
    },
    
    quickWhere = {
        index = 1,
    },
    quickWhereByActivity = {
        quest = {rooms = {}, index = 1, active = false},
        gq = {rooms = {}, index = 1, active = false},
        cp = {rooms = {}, index = 1, active = false},
    },
}


snd.scan = snd.scan or {
    scannedMobs = {},
    consideredMobs = {},
    fullDisplay = {},
    mobsInRoom = {},
    doorsInRoom = {},
    
    activityTargetHere = false,
    questTargetHere = false,
    targetNearby = false,
    otherTargetHere = false,
    scanningCurrentRoom = false,
    runningSmartScan = false,
    conAfterScan = false,
    mobCountHere = 0,
    pendingNxAction = nil,
    
    lastMobDamaged = nil,
    lastMobKilled = nil,
}

local function hasNonEmptyText(value)
    return type(value) == "string" and value ~= ""
end

function snd.scan.hasActivityTarget()
    local current = snd.targets and snd.targets.current
    local hasCurrentKeyword = current and hasNonEmptyText(current.keyword)
    if hasCurrentKeyword then
        return true
    end

    local quest = snd.quest and snd.quest.target
    if quest and hasNonEmptyText(quest.mob) then
        return true
    end

    if snd.gq and snd.gq.targets and next(snd.gq.targets) ~= nil then
        return true
    end

    if snd.campaign and snd.campaign.targets and #snd.campaign.targets > 0 then
        return true
    end

    return false
end

function snd.scan.quickScan()
    send("scan", false)
end

function snd.scan.currentAreaKey()
    local area = snd.room and snd.room.current and snd.room.current.arid or ""
    if snd.utils and snd.utils.trim then
        return snd.utils.trim(area)
    end
    return tostring(area or "")
end

function snd.scan.targetAreaKey(target)
    local area = target and (target.arid or target.area) or ""
    if snd.utils and snd.utils.trim then
        return snd.utils.trim(area)
    end
    return tostring(area or "")
end

function snd.scan.targetIsAlive(target)
    if not target then return false end
    if target.dead or target.killed then return false end
    local status = tostring(target.status or ""):lower()
    if status == "dead" or status == "killed" then return false end
    if tostring(target.activity or ""):lower() == "quest" then
        local questStatus = tostring(
            snd.quest and snd.quest.target and snd.quest.target.status or ""
        ):lower()
        if questStatus == "dead" or questStatus == "killed" then return false end
    end
    if target.remaining ~= nil and tonumber(target.remaining) == 0 then return false end
    return true
end

function snd.scan.targetIsInCurrentArea(target)
    local currentArea = snd.scan.currentAreaKey()
    if currentArea == "" then return false end
    return snd.scan.targetAreaKey(target) == currentArea
end

function snd.scan.targetKeyword(target)
    if not target then return "" end
    local keyword = target.keyword or ""
    if snd.utils and snd.utils.trim then
        keyword = snd.utils.trim(keyword)
    else
        keyword = tostring(keyword or "")
    end
    if keyword ~= "" then return keyword end

    local name = target.name or target.mob or target.matchedMobName or ""
    if snd.gmcp and snd.gmcp.guessMobKeyword then
        local guessed = snd.gmcp.guessMobKeyword(name, snd.scan.targetAreaKey(target))
        if snd.utils and snd.utils.trim then
            guessed = snd.utils.trim(guessed)
        end
        if guessed and guessed ~= "" then return guessed end
    end
    if snd.utils and snd.utils.findKeyword then
        return snd.utils.findKeyword(name)
    end
    return tostring(name or ""):lower()
end

function snd.scan.currentTargetMatchesSmartScan(activeTab)
    local current = snd.targets and snd.targets.current or nil
    if not snd.scan.targetIsAlive(current) then return false end
    local quickWhere = snd.nav and snd.nav.quickWhere or nil
    local nxOverride = snd.nav and snd.nav.nxOverride or nil
    local ownsAdhocQuickWhere = current.activity == "qw"
        and ((quickWhere and quickWhere.isAdhoc == true)
            or (nxOverride and nxOverride.mode == "adhoc_qw"))
    if ownsAdhocQuickWhere then
        return true
    end
    if activeTab and activeTab ~= "" and current.activity ~= activeTab
    then
        return false
    end
    return snd.scan.targetIsInCurrentArea(current)
end

function snd.scan.currentTargetFromListEntry(target)
    if not target then return nil end
    return {
        keyword = snd.scan.targetKeyword(target),
        name = target.name or target.mob or "",
        roomName = target.roomName or "",
        roomId = target.roomId or target.rmid,
        area = target.arid or target.area or "",
        areaName = target.loc or target.areaName or "",
        index = target.displayIndex or target.index,
        activity = target.activity,
        matchedMobName = target.matchedMobName,
    }
end

function snd.scan.resolveSmartScanTarget(options)
    local opts = options or {}
    local activeTab = snd.getActiveTab and snd.getActiveTab() or nil
    if activeTab ~= "quest" and activeTab ~= "gq" and activeTab ~= "cp" then
        activeTab = nil
    end

    if snd.scan.currentTargetMatchesSmartScan(activeTab) then
        return snd.targets.current
    end

    local currentArea = snd.scan.currentAreaKey()
    if currentArea == "" or not snd.targets or not snd.targets.list then
        return nil
    end

    for _, target in ipairs(snd.targets.list) do
        if (not activeTab or target.activity == activeTab)
            and snd.scan.targetIsAlive(target)
            and snd.scan.targetAreaKey(target) == currentArea
        then
            local currentTarget = snd.scan.currentTargetFromListEntry(target)
            if opts.select ~= false and currentTarget then
                snd.setTarget(currentTarget)
            end
            return currentTarget or target
        end
    end

    return nil
end

function snd.scan.smartScan()
    local target = snd.scan.resolveSmartScanTarget({select = true})
    local keyword = ""
    if target and snd.commands and type(snd.commands.resolveTargetCommandSelector) == "function" then
        keyword = snd.commands.resolveTargetCommandSelector(target, "kill", {
            debugContext = "smartscan",
        }) or ""
    end
    if snd.utils and snd.utils.trim then
        keyword = snd.utils.trim(keyword)
    end
    if keyword == "" then
        keyword = snd.scan.targetKeyword(target)
    end
    -- Scan uses the shared logical selector without xkill quotes or ordinals.
    if snd.utils and type(snd.utils.parseMobCommandTarget) == "function" then
        keyword = select(1, snd.utils.parseMobCommandTarget(keyword))
    end
    if keyword ~= "" then
        send("scan " .. keyword, false)
        return true
    end
    return false
end

function snd.scan.currentRoomId()
    local roomId = snd.room and snd.room.current and snd.room.current.rmid or nil
    if roomId ~= nil and tostring(roomId) ~= "" then
        return tostring(roomId)
    end
    return ""
end

function snd.scan.runNxAction(action)
    action = snd.normalizeNxAction(action)
    if action == "smartscan" then
        return snd.scan.smartScan()
    elseif action == "qs" then
        snd.scan.quickScan()
        return true
    end
    return false
end

function snd.scan.clearPendingNxAction()
    local pending = snd.scan.pendingNxAction
    if pending and pending.timer then
        pcall(function() killTimer(pending.timer) end)
    end
    snd.scan.pendingNxAction = nil
end

function snd.scan.runPendingNxAction(roomId, reason)
    local pending = snd.scan.pendingNxAction
    if not pending then
        return false
    end
    if roomId and tostring(roomId) ~= tostring(pending.roomId) then
        return false
    end

    local action = pending.action
    local pendingRoomId = tostring(pending.roomId or "")
    snd.scan.clearPendingNxAction()

    local currentRoomId = snd.scan.currentRoomId()
    if pendingRoomId ~= "" and currentRoomId ~= "" and currentRoomId ~= pendingRoomId then
        snd.utils.debugNote("Dropping deferred nxAction after room changed.")
        return false
    end

    local ran = snd.scan.runNxAction(action)
    if ran then
        snd.utils.debugNote("Running deferred nxAction " .. action .. " (" .. tostring(reason or "resolved") .. ").")
    end
    return ran
end

function snd.scan.cancelPendingNxAction(roomId, reason)
    local pending = snd.scan.pendingNxAction
    if not pending then
        return false
    end
    if roomId and tostring(roomId) ~= tostring(pending.roomId) then
        return false
    end

    snd.utils.debugNote("Skipping deferred nxAction " .. tostring(pending.action) .. " (" .. tostring(reason or "cancelled") .. ").")
    snd.scan.clearPendingNxAction()
    return true
end

function snd.scan.conwinConsiderWillResolveRoom()
    local conwinConfig = snd.config and snd.config.conwin or nil
    if not snd.conwin or not conwinConfig or not conwinConfig.enabled then
        return false
    end
    return tostring(conwinConfig.mode or "consider"):lower() == "consider"
end

function snd.scan.deferNxActionUntilConwin(action, roomId)
    action = snd.normalizeNxAction(action)
    if action == "none" then
        return false
    end

    roomId = tostring(roomId or snd.scan.currentRoomId() or "")
    snd.scan.clearPendingNxAction()

    local pending = {
        action = action,
        roomId = roomId,
    }
    snd.scan.pendingNxAction = pending

    if type(tempTimer) == "function" then
        pending.timer = tempTimer(0.8, function()
            if snd.scan and snd.scan.pendingNxAction == pending then
                snd.scan.runPendingNxAction(roomId, "conwin-timeout")
            end
        end)
    end

    snd.utils.debugNote("Deferring nxAction " .. action .. " until ConWin consider resolves.")
    return true
end

function snd.scan.handleArrivalNxAction(action)
    action = snd.normalizeNxAction(action)
    if action == "none" then
        return false
    end

    if snd.scan.conwinConsiderWillResolveRoom() then
        return snd.scan.deferNxActionUntilConwin(action, snd.scan.currentRoomId())
    end

    return snd.scan.runNxAction(action)
end


snd.gui = snd.gui or {
    window = nil,
    initialized = false,
    hotspots = {},
    targetHotspots = {},
}


snd.timers = snd.timers or {
    executeInArea = {i = 0, j = 0, arid = "", f = "", stat = 1},
    executeInRoom = {i = 0, j = 0, rmid = "", f = "", stat = 1},
    vidblainNav = {i = 0, j = 0, rmid = "", f = "", stat = 1},
}


snd.mazeStartRooms = snd.mazeStartRooms or {}


snd.colors = snd.colors or {
    normal = "#E0E0E0",
    targeted = "#FF4000",
    dead = "#484848",
    unknown = "#FF0000",
    unknownDead = "#900000",
    unlikely = "#484848",
    unlikelyTag = "#0000CD",
    questAvailable = "#1E90FF",
    questComplete = "#7CFC00",
    questWaiting = "#FF7A7A",
    alternatingRow = "#000040",
}


snd.saveFile = sndSaveFilePath()


snd.initialized = false
snd.windowAutoOpenPending = false
snd.postLoginCpCheckDone = snd.postLoginCpCheckDone or false

function snd.initialize(silent)
    if snd.initialized then return end

    snd.windowAutoOpenPending = true
    
    if not silent then
        snd.utils.infoNote(snd.fullVersion .. " initializing...")
    end

    snd.utils.debugNote("Initializing Search & Destroy modules")
    
    snd.loadState()

    snd.utils.debugNote("State load complete, initializing database")
    
    if snd.db and snd.db.initialize then
        snd.db.initialize(silent)
    end

    snd.utils.debugNote("Database initialization complete, registering GMCP handlers")
    
    if snd.gmcp and snd.gmcp.registerHandlers then
        snd.gmcp.registerHandlers()
    end

    snd.requestGMCPData()

    snd.utils.debugNote("GMCP handler registration complete, registering temp aliases")

    if snd.commands and snd.commands.registerTempAliases then
        snd.commands.registerTempAliases()
    end

    if snd.triggers and snd.triggers.registerRoomCharsBoundaryTriggers then
        snd.triggers.registerRoomCharsBoundaryTriggers()
    end
    if snd.triggers and snd.triggers.registerQuestCooldownTriggers then
        snd.triggers.registerQuestCooldownTriggers()
    end
    if snd.triggers and snd.triggers.registerQuickWhereCommandTrigger then
        snd.triggers.registerQuickWhereCommandTrigger()
    end

    snd.utils.debugNote("Temp alias registration complete, checking GUI config")
    
    if snd.config.window.enabled and snd.gui and snd.gui.createWindow then
        snd.gui.createWindow()
    end
    if snd.conwin and snd.conwin.install then
        snd.conwin.install()
    end

    snd.utils.debugNote("Initialization steps complete, marking initialized")
    
    snd.initialized = true
    
    if not silent then
        snd.utils.infoNote(snd.fullVersion .. " loaded successfully!")
    end

    snd.gui.show()
end

function snd.initializeSilent()
    snd.initialize(true)
end

function snd.tryAutoOpenWindow()
    if not snd.initialized then return end
    if not snd.windowAutoOpenPending then return end

    -- Never send startup commands until GMCP confirms the player is active.
    if tostring(snd.char.state or "0") ~= "3" then return end

    snd.windowAutoOpenPending = false

    local isVisible = false
    if snd.gui and snd.gui.elements and snd.gui.elements.main and snd.gui.elements.main.isVisible then
        local ok, visible = pcall(function()
            return snd.gui.elements.main:isVisible()
        end)
        isVisible = ok and visible or false
    end

    if not isVisible then
        snd.commands.showWindow()
    end
end

function snd.onCharVitalsReady(_)
    snd.tryAutoOpenWindow()
end

function snd.onPlayerActive()
    if not snd.initialized then return end

    if not snd.tagsEnabled then
        snd.tagsEnabled = true
        send("tags scan on", false)
        send("tags roomchars on", false)
    end

    if not snd.announcedReady then
        snd.announcedReady = true
        snd.utils.infoNote(snd.fullVersion .. " ready. Type 'xhelp' for commands.")
    end

    if not snd.postLoginCpCheckDone then
        snd.postLoginCpCheckDone = true
        if snd.cp and snd.cp.requestCheck then
            snd.cp.requestCheck(0.8, "main.postLoginCpSync")
        else
            tempTimer(0.8, function()
                snd.utils.debugNote("Sending 'cp check' (reason: main.postLoginCpSync:fallback)")
                send("cp check", false)
            end)
        end
    end
end

function snd.requestGMCPData()
    if not snd.gmcp then return end
    
    tempTimer(0.5, function()
        sendGMCP("request char")
    end)
    
    tempTimer(1.0, function()
        sendGMCP("request room")
        sendGMCP("request quest")
    end)
end


function snd.saveState()
    if snd.conwin and snd.conwin.captureWindowState then
        snd.conwin.captureWindowState()
    end
    local state = {
        config = snd.config,
        colors = snd.colors,
        campaign = {
            levelTaken = snd.campaign.levelTaken,
            completeBy = snd.campaign.completeBy,
            persistedCompleteBy = snd.campaign.persistedCompleteBy,
            persistedQpReward = snd.campaign.persistedQpReward,
            persistedGoldReward = snd.campaign.persistedGoldReward,
            persistedTpReward = snd.campaign.persistedTpReward,
            persistedTrainReward = snd.campaign.persistedTrainReward,
            persistedPracReward = snd.campaign.persistedPracReward,
            completedToday = snd.campaign.completedToday,
            completedTodayDate = snd.campaign.completedTodayDate,
        },
        gquest = {
            joined = snd.gquest.joined,
            started = snd.gquest.started,
            extended = snd.gquest.extended,
            effectiveLevel = snd.gquest.effectiveLevel,
            historyId = snd.gquest.historyId,
            qpReward = snd.gquest.qpReward,
            tpReward = snd.gquest.tpReward,
            trainReward = snd.gquest.trainReward,
            pracReward = snd.gquest.pracReward,
            goldReward = snd.gquest.goldReward,
            qpPerKillBonus = snd.gquest.qpPerKillBonus,
            qpKillBonusTotal = snd.gquest.qpKillBonusTotal,
        },
        quest = {
            cooldownStart = snd.quest.cooldownStart,
            cooldownDuration = snd.quest.cooldownDuration,
            nextQuestTime = snd.quest.nextQuestTime,
            nextQuestLessThanMinute = snd.quest.nextQuestLessThanMinute,
            nextQuestText = snd.quest.nextQuestText,
        },
        mazeStartRooms = snd.mazeStartRooms,
        gui = {
            posX = snd.config.window.posX,
            posY = snd.config.window.posY,
            width = snd.config.window.width,
            height = snd.config.window.height,
        },
        tabs = {
            active = snd.tabs.active or "auto",
        },
    }
    
    local success, err = pcall(function()
        table.save(snd.saveFile, state)
    end)
    
    if not success then
        snd.utils.errorNote("Failed to save state: " .. tostring(err))
    else
        snd.utils.debugNote("State saved successfully")
    end
end

function snd.loadState()
    snd.utils.debugNote("Loading state from " .. snd.saveFile)
    if not sndFileExists(snd.saveFile) then
        snd.utils.debugNote("No saved state found, using defaults")
        return
    end
    
    local success, state = pcall(function()
        local t = {}
        table.load(snd.saveFile, t)
        return t
    end)
    
    if not success or not state then
        snd.utils.errorNote("Failed to load state: " .. tostring(state))
        return
    end
    
    if state.config then
        mergeTables(snd.config, state.config)
        snd.config.nxAction = snd.normalizeNxAction(snd.config.nxAction)
    end
    
    if state.colors then
        for k, v in pairs(state.colors) do
            snd.colors[k] = v
        end
    end
    
    if state.campaign then
        snd.campaign.levelTaken = state.campaign.levelTaken or 0
        snd.campaign.historyId = 0
        snd.campaign.completeBy = state.campaign.completeBy or state.campaign.sessionId or ""
        snd.campaign.persistedCompleteBy = state.campaign.persistedCompleteBy or snd.campaign.completeBy or ""
        snd.campaign.persistedQpReward = tonumber(state.campaign.persistedQpReward) or 0
        snd.campaign.persistedGoldReward = tonumber(state.campaign.persistedGoldReward) or 0
        snd.campaign.persistedTpReward = tonumber(state.campaign.persistedTpReward) or 0
        snd.campaign.persistedTrainReward = tonumber(state.campaign.persistedTrainReward) or 0
        snd.campaign.persistedPracReward = tonumber(state.campaign.persistedPracReward) or 0
        snd.campaign.completedToday = tonumber(state.campaign.completedToday) or 0
        snd.campaign.completedTodayDate = state.campaign.completedTodayDate or ""
    end
    
    if state.gquest then
        snd.gquest.joined = state.gquest.joined or "-1"
        snd.gquest.started = state.gquest.started or "-1"
        snd.gquest.extended = state.gquest.extended or "-1"
        snd.gquest.effectiveLevel = state.gquest.effectiveLevel or 0
        snd.gquest.historyId = state.gquest.historyId or 0
        snd.gquest.qpReward = state.gquest.qpReward or 0
        snd.gquest.tpReward = state.gquest.tpReward or 0
        snd.gquest.trainReward = state.gquest.trainReward or 0
        snd.gquest.pracReward = state.gquest.pracReward or 0
        snd.gquest.goldReward = state.gquest.goldReward or 0
        snd.gquest.qpPerKillBonus = state.gquest.qpPerKillBonus or 0
        snd.gquest.qpKillBonusTotal = state.gquest.qpKillBonusTotal or 0
    end

    if state.quest then
        snd.quest.cooldownStart = state.quest.cooldownStart or 0
        snd.quest.cooldownDuration = state.quest.cooldownDuration or 0
        snd.quest.nextQuestTime = state.quest.nextQuestTime or 0
        snd.quest.nextQuestLessThanMinute = state.quest.nextQuestLessThanMinute or false
        snd.quest.nextQuestText = state.quest.nextQuestText or ""
        snd.quest.updateCooldownRemaining()
    end
    
    if state.mazeStartRooms then
        snd.mazeStartRooms = state.mazeStartRooms
    end

    if state.tabs then
        snd.tabs.active = state.tabs.active or "auto"
    end
    
    snd.utils.debugNote("State loaded successfully")
end


function snd.isOnCampaign()
    return snd.campaign.active
end

function snd.isOnGquest()
    return snd.gquest.active
end

function snd.isOnQuest()
    return snd.quest.active
end

function snd.hasActivity()
    return snd.campaign.active or snd.gquest.active or snd.quest.active
end

function snd.getActivityType()
    if snd.campaign.active then return "cp" end
    if snd.gquest.active then return "gq" end
    if snd.quest.active then return "quest" end
    return "none"
end

function snd.hasActivityTarget()
    return snd.targets.current ~= nil and snd.targets.current.activity ~= nil
end

function snd.isCpOrGqTarget()
    if not snd.targets.current then return false end
    local act = snd.targets.current.activity
    return act == "cp" or act == "gq"
end


local activityPriority = {
    gq = 1,      -- Global Quest - highest priority (time-limited competition)
    quest = 2,   -- Quest - second priority (time-limited)
    cp = 3,      -- Campaign - third priority (no time limit)
}

-- Proximity is ordering metadata only; S&D never executes mapper steps here.
snd.proximity = snd.proximity or {
    dirty = true,
    generation = 0,
    source = nil,
    reason = "initial",
}

local function normalizedTargetArea(target)
    local value = snd.scan.targetAreaKey(target)
    return tostring(value or ""):lower()
end

local function proximityTargetRoom(target)
    local roomId = tonumber(target and (target.rmid or target.roomId))
    if roomId and roomId > 0 then
        return tostring(math.floor(roomId))
    end
    return nil
end

local function proximityNavigationActive()
    return (snd.nav and snd.nav.goingToRoom ~= nil)
        or (snd.mapper and snd.mapper.goingToRoom ~= nil)
        or (snd.mapper and snd.mapper.pathExecutionActive == true)
end

function snd.markTargetProximityDirty(reason)
    snd.proximity = snd.proximity or {}
    snd.proximity.dirty = true
    snd.proximity.reason = tostring(reason or "changed")
end

function snd.refreshTargetProximity(reason)
    snd.proximity = snd.proximity or {}
    snd.markTargetProximityDirty(reason or "refresh")

    if proximityNavigationActive() then
        return false, "navigation_active"
    end
    if not (snd.targets and type(snd.targets.list) == "table") then
        return false, "no_targets"
    end
    if not (snd.mapper and type(snd.mapper.findDistances) == "function") then
        return false, "mapper_api_unavailable"
    end

    local sourceNumber = tonumber(snd.room and snd.room.current and snd.room.current.rmid)
    if not sourceNumber or sourceNumber <= 0 then
        -- CP/GQ may arrive without a mapped Room.Info; do not reuse a prior source.
        snd.proximity.awaitingSource = true
        return false, "source_unmapped"
    end
    local source = tostring(math.floor(sourceNumber))
    local groups = {}
    local groupOrder = 0
    local destinations = {}
    local destinationSeen = {}

    for _, target in ipairs(snd.targets.list) do
        target._proximityGeneration = nil
        target._proximityDistance = nil
        target._proximityAreaDistance = nil
        target._proximityAreaOrdinal = nil
        target._proximityAreaKey = nil

        local activity = tostring(target.activity or ""):lower()
        if (activity == "cp" or activity == "gq") and snd.scan.targetIsAlive(target) then
            local areaKey = normalizedTargetArea(target)
            local confidence = (target.lowConfidence == true or target.unlikely == true) and "low" or "high"
            local groupKey = table.concat({activity, confidence, areaKey}, "|")
            local group = groups[groupKey]
            if not group then
                groupOrder = groupOrder + 1
                group = {
                    activity = activity,
                    areaKey = areaKey,
                    ordinal = groupOrder,
                    rooms = {},
                    roomSeen = {},
                    targets = {},
                }
                groups[groupKey] = group
            end
            table.insert(group.targets, target)
            local roomId = proximityTargetRoom(target)
            if roomId and not group.roomSeen[roomId] then
                group.roomSeen[roomId] = true
                table.insert(group.rooms, roomId)
            end
        end
    end

    -- Area starts are cache-backed fallbacks only when no target room is known.
    for _, group in pairs(groups) do
        if #group.rooms == 0 and group.areaKey ~= ""
            and snd.db and type(snd.db.getAreaStartRoom) == "function"
        then
            local ok, startRoom = pcall(snd.db.getAreaStartRoom, group.areaKey)
            local numeric = ok and tonumber(startRoom) or nil
            if numeric and numeric > 0 then
                table.insert(group.rooms, tostring(math.floor(numeric)))
                group.usesAreaStart = true
            end
        end
        for _, roomId in ipairs(group.rooms) do
            if not destinationSeen[roomId] then
                destinationSeen[roomId] = true
                table.insert(destinations, roomId)
            end
        end
    end

    local distances = {}
    local metadata = {source = source, requested = 0, found = 0}
    if #destinations > 0 then
        local ok, result, details = pcall(snd.mapper.findDistances, source, destinations, {
            usePortals = true,
            useRecall = true,
        })
        if not ok then
            if snd.utils and snd.utils.debugNote then
                snd.utils.debugNote("Target proximity failed: " .. tostring(result))
            end
            return false, "mapper_error"
        end
        distances = type(result) == "table" and result or {}
        metadata = type(details) == "table" and details or metadata
        if metadata.error then
            return false, metadata.error
        end
    end

    local generation = (tonumber(snd.proximity.generation) or 0) + 1
    for _, group in pairs(groups) do
        local areaDistance = nil
        for _, roomId in ipairs(group.rooms) do
            local distance = tonumber(distances[roomId])
            if distance and (areaDistance == nil or distance < areaDistance) then
                areaDistance = distance
            end
        end
        for _, target in ipairs(group.targets) do
            target._proximityGeneration = generation
            target._proximityDistance = tonumber(distances[proximityTargetRoom(target) or ""])
            target._proximityAreaDistance = areaDistance
            target._proximityAreaOrdinal = group.ordinal
            target._proximityAreaKey = group.areaKey
        end
    end

    snd.proximity.generation = generation
    snd.proximity.source = source
    snd.proximity.awaitingSource = false
    snd.proximity.dirty = false
    snd.proximity.reason = tostring(reason or "refresh")
    snd.proximity.metadata = metadata
    if snd.utils and snd.utils.debugNote then
        snd.utils.debugNote(string.format(
            "Target proximity: source=%s destinations=%d found=%d depth=%d cached=%s (%.2fms)",
            source,
            tonumber(metadata.requested) or #destinations,
            tonumber(metadata.found) or 0,
            tonumber(metadata.depth) or 0,
            tostring(metadata.cached == true),
            tonumber(metadata.elapsedMs) or 0
        ))
    end
    return true
end

function snd.getActivityPriority(activity)
    return activityPriority[activity] or 99
end

function snd.reindexTargetsAfterSort()
    if not snd.targets or not snd.targets.list then return end

    local cpDisplayIndex = 0
    local cpListIndex = 0
    for _, target in ipairs(snd.targets.list) do
        if target.activity == "cp" then
            cpListIndex = cpListIndex + 1
            target.cpListIndex = cpListIndex
            if snd.scan.targetIsAlive(target) then
                cpDisplayIndex = cpDisplayIndex + 1
                target.displayIndex = cpDisplayIndex
            else
                target.displayIndex = nil
            end
        end
    end
end

function snd.sortTargetsByPriority(options)
    if not snd.targets or not snd.targets.list then return end

    local opts = type(options) == "table" and options or {}
    if opts.recalculateProximity == true then
        snd.refreshTargetProximity(opts.reason or "target_sort")
    end

    for i, target in ipairs(snd.targets.list) do
        target._sortOrdinal = i
    end

    table.sort(snd.targets.list, function(a, b)
        local prioA = snd.getActivityPriority(a.activity)
        local prioB = snd.getActivityPriority(b.activity)
        
        if prioA ~= prioB then
            return prioA < prioB  -- Lower priority value = higher priority
        end

        local aliveA = snd.scan.targetIsAlive(a)
        local aliveB = snd.scan.targetIsAlive(b)
        if aliveA ~= aliveB then
            return aliveA
        end

        local currentAreaA = aliveA and snd.scan.targetIsInCurrentArea(a)
        local currentAreaB = aliveB and snd.scan.targetIsInCurrentArea(b)
        if currentAreaA ~= currentAreaB then
            return currentAreaA
        end

        local lowA = a.lowConfidence == true or a.unlikely == true
        local lowB = b.lowConfidence == true or b.unlikely == true
        if lowA ~= lowB then
            return not lowA
        end

        local proximityReady = snd.proximity and snd.proximity.dirty == false
        local generation = proximityReady and tonumber(snd.proximity.generation) or nil
        local proximityA = generation and tonumber(a._proximityGeneration) == generation
        local proximityB = generation and tonumber(b._proximityGeneration) == generation
        if proximityA and proximityB then
            local areaA = tostring(a._proximityAreaKey or "")
            local areaB = tostring(b._proximityAreaKey or "")
            if areaA ~= areaB then
                local areaDistanceA = tonumber(a._proximityAreaDistance)
                local areaDistanceB = tonumber(b._proximityAreaDistance)
                if (areaDistanceA ~= nil) ~= (areaDistanceB ~= nil) then
                    return areaDistanceA ~= nil
                end
                if areaDistanceA ~= nil and areaDistanceA ~= areaDistanceB then
                    return areaDistanceA < areaDistanceB
                end
                local areaOrdinalA = tonumber(a._proximityAreaOrdinal) or math.huge
                local areaOrdinalB = tonumber(b._proximityAreaOrdinal) or math.huge
                if areaOrdinalA ~= areaOrdinalB then
                    return areaOrdinalA < areaOrdinalB
                end
            else
                local distanceA = tonumber(a._proximityDistance)
                local distanceB = tonumber(b._proximityDistance)
                if (distanceA ~= nil) ~= (distanceB ~= nil) then
                    return distanceA ~= nil
                end
                if distanceA ~= nil and distanceA ~= distanceB then
                    return distanceA < distanceB
                end
            end
        elseif proximityA ~= proximityB then
            return proximityA
        end

        -- Preserve relative order for ties and unreachable rooms.
        return (a._sortOrdinal or 0) < (b._sortOrdinal or 0)
    end)

    for _, target in ipairs(snd.targets.list) do
        target._sortOrdinal = nil
    end
    snd.reindexTargetsAfterSort()
end

local function quickWhereTargetIdentity(target)
    if type(target) ~= "table" then return "" end
    return table.concat({
        tostring(target.activity or ""),
        tostring(target.name or target.mob or ""),
        tostring(target.area or target.arid or ""),
    }, "|")
end

local function emptyQuickWhereScope()
    return {
        rooms = {},
        index = 1,
        active = false,
        targetKey = "",
    }
end

-- Target selection serializes async QW replies and room lists so stale lookups
-- cannot replace the new target or make nx cycle old rooms.
function snd.nav.invalidateQuickWhereForTarget(nextTarget)
    local quickWhere = snd.nav and snd.nav.quickWhere or nil
    if type(quickWhere) ~= "table" then return false end

    local currentKey = quickWhereTargetIdentity(snd.targets and snd.targets.current)
    local nextKey = quickWhereTargetIdentity(nextTarget)
    local storedKey = tostring(quickWhere.targetKey or "")
    local changesIdentity = currentKey ~= nextKey
    local mismatchedStoredList = storedKey ~= "" and nextKey ~= "" and storedKey ~= nextKey
    if quickWhere.isAdhoc ~= true and not changesIdentity and not mismatchedStoredList then
        return false
    end

    for _, timerField in ipairs({"probeTimer", "processTimer", "disableTimer"}) do
        local timerId = quickWhere[timerField]
        if timerId ~= nil and type(killTimer) == "function" then
            pcall(killTimer, timerId)
        end
        quickWhere[timerField] = nil
    end

    if snd.triggers and type(snd.triggers.disableQuickWhereTriggers) == "function" then
        pcall(snd.triggers.disableQuickWhereTriggers)
    end

    local previousScope = tostring(quickWhere.scope or "")
    local nextActivity = tostring((type(nextTarget) == "table" and nextTarget.activity) or "")
    if previousScope ~= "" and previousScope == nextActivity then
        snd.nav.quickWhereByActivity = snd.nav.quickWhereByActivity or {}
        snd.nav.quickWhereByActivity[previousScope] = emptyQuickWhereScope()
    end

    quickWhere.rooms = {}
    quickWhere.index = 1
    quickWhere.active = false
    quickWhere.targetKey = ""
    quickWhere.lastMatch = nil
    quickWhere.pendingMatches = {}
    quickWhere.processed = true
    quickWhere.completed = true
    quickWhere.accepted = false
    quickWhere.awaitingCommandEcho = false
    quickWhere.probePending = false
    quickWhere.commandInFlight = false
    quickWhere.isAdhoc = false
    quickWhere.requestedKeyword = nil
    quickWhere.lookupKeyword = nil
    quickWhere.exact = false
    quickWhere.exactMatchText = nil
    quickWhere.exactTargetName = nil
    quickWhere.source = nil
    quickWhere.scope = nil

    snd.nav.nxOverride = nil
    snd.nav.nxState = nil
    snd.nav.xcpLookup = nil
    snd.nav.pendingTargetRoomFallback = nil
    snd.nav.targetAreaFallback = nil

    if snd.utils and type(snd.utils.debugNote) == "function" then
        snd.utils.debugNote("Invalidated quick-where state for target change")
    end
    return true
end

function snd.clearTarget(opts)
    local options = opts or {}
    local activity = snd.targets.current and snd.targets.current.activity or nil
    snd.nav.invalidateQuickWhereForTarget(nil)
    snd.targets.current = nil
    if activity and snd.targets.scoped then
        snd.targets.scoped[activity] = nil
    end
    if options.refresh ~= false and snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.nav.clearActivityQuickWhere(activity)
    if activity ~= "quest" and activity ~= "gq" and activity ~= "cp" then
        return
    end

    snd.nav.quickWhereByActivity = snd.nav.quickWhereByActivity or {}
    snd.nav.quickWhereByActivity[activity] = {
        rooms = {},
        index = 1,
        active = false,
        targetKey = "",
    }

    snd.nav.quickWhere = snd.nav.quickWhere or {}
    if snd.nav.quickWhere.scope == activity or snd.nav.quickWhere.scope == nil then
        snd.nav.quickWhere.rooms = {}
        snd.nav.quickWhere.index = 1
        snd.nav.quickWhere.active = false
        snd.nav.quickWhere.targetKey = ""
        snd.nav.quickWhere.pendingMatches = {}
    end

    local prefix = activity .. "|"
    if snd.nav.xcpLookup and type(snd.nav.xcpLookup.targetKey) == "string"
        and snd.nav.xcpLookup.targetKey:sub(1, #prefix) == prefix then
        snd.nav.xcpLookup = nil
    end
    if snd.nav.nxState and type(snd.nav.nxState.targetKey) == "string"
        and snd.nav.nxState.targetKey:sub(1, #prefix) == prefix then
        snd.nav.nxState = nil
    end

    if type(snd.nav.gotoListTargetKey) == "string"
        and snd.nav.gotoListTargetKey:sub(1, #prefix) == prefix then
        snd.nav.gotoList = {}
        snd.nav.gotoListTargetKey = ""
    end

    if snd.targets and snd.targets.scoped then
        snd.targets.scoped[activity] = nil
    end
end

function snd.setTarget(target)
    if target and snd.commands and type(snd.commands.bindTargetSelection) == "function" then
        snd.commands.bindTargetSelection(target)
    end
    snd.nav.invalidateQuickWhereForTarget(target)
    snd.targets.current = target
    if target and target.activity and snd.targets.scoped then
        snd.targets.scoped[target.activity] = snd.utils.deepcopy(target)
    end
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.getPreferredActiveActivity()
    if snd.gquest and snd.gquest.active then
        return "gq"
    end
    if snd.quest and snd.quest.active then
        return "quest"
    end
    if snd.campaign and snd.campaign.active then
        return "cp"
    end
    return nil
end

function snd.getAutocheckMode()
    local cfg = snd.config and snd.config.autocheck or {}
    local mode = tostring(cfg.mode or "on"):lower()
    if mode ~= "on" and mode ~= "smart" and mode ~= "off" then
        mode = "on"
    end
    return mode
end

function snd.shouldAutoCheckAfterKill(activity)
    local cfg = snd.config and snd.config.autocheck
    if not cfg then return true end

    local mode = snd.getAutocheckMode()
    if mode == "on" then
        return true
    end
    if mode == "off" then
        return false
    end

    local smartKills = tonumber(cfg.smartKills) or 1
    if smartKills <= 1 then
        snd.utils.infoNote("AutoCheck SMART with kills=1 is equivalent to ON; switching mode to ON.")
        if snd.commands and snd.commands.setAutocheckMode then
            snd.commands.setAutocheckMode("on")
        else
            cfg.mode = "on"
            if snd.saveState then snd.saveState() end
        end
        if snd.gui and snd.gui.refresh then snd.gui.refresh() end
        return true
    end

    local key = (activity == "gq") and "gqKillCounter" or "cpKillCounter"
    cfg[key] = (tonumber(cfg[key]) or 0) + 1
    if cfg[key] >= smartKills then
        cfg[key] = 0
        return true
    end
    return false
end

function snd.setActiveTab(activity, opts)
    local options = opts or {}
    local normalized = tostring(activity or "auto"):lower()
    if normalized ~= "auto" and normalized ~= "quest" and normalized ~= "gq" and normalized ~= "cp" then
        normalized = "auto"
    end
    local changed = tostring(snd.tabs.active or "auto"):lower() ~= normalized
    snd.tabs.active = normalized
    if changed then
        snd.markTargetProximityDirty("activity_changed")
        if options.sort ~= false then
            snd.sortTargetsByPriority({
                recalculateProximity = true,
                reason = "activity_changed",
            })
        end
    end
    if options.save ~= false and snd.saveState then
        snd.saveState()
    end
    if options.refresh ~= false and snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.getActiveTab()
    local active = tostring((snd.tabs and snd.tabs.active) or "auto"):lower()
    if active == "auto" then
        return snd.getPreferredActiveActivity() or "quest"
    end
    return active
end


function snd.onRoomChange()
    if snd.mapper and snd.mapper.onConfirmedRoomVisit then
        snd.mapper.onConfirmedRoomVisit(snd.room.current and snd.room.current.rmid)
    end

    local wasNavigating = (snd.nav.goingToRoom or snd.mapper.goingToRoom) ~= nil
        or snd.mapper.pathExecutionActive == true
    snd.markTargetProximityDirty("room_changed")
    if snd.triggers and snd.triggers.registerTargetLineTriggers then
        local area = snd.utils.trim(snd.room and snd.room.current and snd.room.current.arid or ""):lower()
        local matcherArea = snd.roomChars and tostring(snd.roomChars.targetMatcherArea or "") or ""
        if area ~= matcherArea then snd.triggers.registerTargetLineTriggers() end
    end

    local destination = snd.nav.goingToRoom or snd.mapper.goingToRoom
    if destination and tostring(snd.room.current.rmid) == tostring(destination) then
        snd.mapper.pathExecutionActive = false
        snd.mapper.pathExecutionHasPendingGroups = false
        if snd.mapper and snd.mapper.schedulePendingPersistFlush then
            snd.mapper.schedulePendingPersistFlush()
        elseif snd.mapper and snd.mapper.flushPendingPersists then
            snd.mapper.flushPendingPersists()
        end
        snd.onDestinationArrived()
        snd.nav.goingToRoom = nil
        snd.mapper.goingToRoom = nil
        if snd.mapper and snd.mapper.notifyBigmapNavigationState then
            snd.mapper.notifyBigmapNavigationState("destination_arrived")
        end
    end

    -- Mid-route room changes skip GUI refresh. Manual movement only dirties
    -- proximity; xcp/nx/tab refresh it synchronously at the next decision.
    local stillNavigating = (snd.nav.goingToRoom or snd.mapper.goingToRoom) ~= nil
        or snd.mapper.pathExecutionActive == true
    if not (wasNavigating and stillNavigating) then
        if snd.targets and snd.targets.list then
            local currentSource = tonumber(snd.room and snd.room.current and snd.room.current.rmid)
            local firstMappedSource = currentSource and currentSource > 0
                and (not snd.proximity
                    or snd.proximity.source == nil
                    or snd.proximity.awaitingSource == true)
            snd.sortTargetsByPriority({
                recalculateProximity = (wasNavigating and not stillNavigating) or firstMappedSource,
                reason = firstMappedSource and "initial_room_ready" or "navigation_arrived",
            })
        end
        if snd.gui and snd.gui.refresh then
            snd.gui.refresh()
        end
    end
end

local function roomDetailsContainSafe(details)
    local v = tostring(details or ""):lower()
    if v == "" then return false end
    for token in v:gmatch("[^,%s]+") do
        if token == "safe" then return true end
    end
    return false
end

local function gmcp_get(path)
    local node = gmcp
    for key in tostring(path or ""):gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return node
end

function snd.isCurrentRoomSafe()
    local details = gmcp_get("room.info.details")
    if details ~= nil and roomDetailsContainSafe(details) then return true end

    local roomId = tostring(gmcp_get("room.info.num") or "")
    if roomId ~= "" and snd.mapper and type(snd.mapper.isSafeRoom) == "function" then
        if snd.mapper.isSafeRoom(roomId) then return true end
    end
    return false
end

function snd.onDestinationArrived()
    snd.utils.debugNote("Arrived at destination room: " .. tostring(snd.room.current.rmid))

    if snd.nav.nxState and snd.nav.nxState.targetKey and snd.targets.current then
        if snd.commands and snd.commands.buildTargetKeyFromCurrent then
            local key = snd.commands.buildTargetKeyFromCurrent(snd.targets.current)
            if key == snd.nav.nxState.targetKey then
                snd.nav.nxState.arrived = true
            end
        end
    end

    -- Area-start fallback is an approach, not proof the target room was reached.
    if snd.commands and type(snd.commands.handleTargetAreaFallbackArrival) == "function"
        and snd.commands.handleTargetAreaFallbackArrival(snd.room.current.rmid) == true then
        return
    end

    -- QW/hybrid/HT approaches replace the ordinary nx action for this arrival.
    if snd.commands and type(snd.commands.handleXcpLookupArrival) == "function"
        and snd.commands.handleXcpLookupArrival(snd.room.current.rmid) == true then
        return
    end
    
    local action = snd.normalizeNxAction(snd.config.nxAction)
    snd.config.nxAction = action
    if snd.isCurrentRoomSafe() then
        snd.utils.debugNote("Skipping nxAction in safe room: " .. tostring(snd.room.current and snd.room.current.rmid))
    else
        snd.scan.handleArrivalNxAction(action)
    end

end

function snd.onStateChange()
    if tostring(snd.char and snd.char.state or "0") == "8"
        and snd.commands and snd.commands.abortQuickWhereForCombat
    then
        snd.commands.abortQuickWhereForCombat()
    end
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end


function snd.cleanup()
    snd.utils.infoNote("Saving state before unload...")
    snd.saveState()
    
    if snd.quest and snd.quest.stopReadySoundReminder then
        snd.quest.stopReadySoundReminder()
    end

    if snd.gui and snd.gui.cleanup then
        snd.gui.cleanup()
    end
end


registerAnonymousEventHandler("sysExitEvent", function()
    snd.cleanup()
end)

if snd.autoSaveTimer then
    killTimer(snd.autoSaveTimer)
end
snd.autoSaveTimer = tempTimer(300, function()
    snd.saveState()
end, true)

