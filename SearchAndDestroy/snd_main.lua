--[[
    Search and Destroy - Main Module
    Mudlet Port
    
    Original MUSHclient plugin by Crowley
    Ported to Mudlet
    
    This module contains:
    - Global state variables
    - Configuration
    - Initialization
    - Save/Load state
]]

snd = snd or {}

-------------------------------------------------------------------------------
-- Version Information
-------------------------------------------------------------------------------

snd.version = "7.0.0"
snd.schemaVersion = 6
snd.fullVersion = "Search & Destroy v" .. snd.version

-------------------------------------------------------------------------------
-- Configuration
-------------------------------------------------------------------------------

snd.config = snd.config or {
    -- Debug mode
    debugMode = true,
    
    -- Silent mode - suppress some messages
    silentMode = false,
    
    -- Speed for navigation (run or walk)
    speed = "run",
    
    -- Kill command for xkill (default: "kill", can be set with xcmd)
    killCommand = "kill",
    
    -- Auto-noexp settings
    anex = {
        automatic = true,
        tnlCutoff = 0,
    },
    
    -- Vidblain navigation
    vidblain = {
        enabled = false,
        level = 300,
    },
    
    -- GQ extra aliases
    gqExtraAliases = true,
    
    -- Next action after arriving at target (smartscan, con, scan, qs, none)
    nxAction = "qs",
    
    -- xcp post-arrival action mode: db|qw|ht (legacy "off" loads as db)
    xcpActionMode = "qw",
    
    -- Overwrite con data
    overwriteCon = true,
    
    -- Sound notifications
    soundEnabled = false,
    soundVolume = 100,
    
    -- Express mode (skip targets with enough kills)
    express = {
        enabled = true,
        minKillCount = 2,
    },
    
    -- Auto check behavior after kills: on|smart|off
    autocheck = {
        mode = "on",
        smartKills = 3,
        cpKillCounter = 0,
        gqKillCounter = 0,
    },

    -- Mobdetect behavior on room arrival after target confirmation: off|on|always
    mobdetect = "off",

    -- Table display settings
    tableNotes = false,
    tableWidth = 80,
    
    -- Window settings
    window = {
        enabled = true,
        posX = 0,
        posY = 0,
        width = 325,
        height = 280,
        font = "Lucida Sans Unicode",
        fontSize = 8,
    },
    
    -- Automatic update checks
    autoUpdateCheck = true,

    -- Area color banding for target list location labels
    areaColors = true,

    -- Reporting channel for S&D event/history output ("default" = local echo)
    reportChannel = "default",

    -- Mapper portal/bounce preferences used by xrt pathing helpers
    mapper = {
        bouncePortalId = nil,
        bounceRecallId = nil,
        bouncePortalCommand = nil,
        bounceRecallCommand = nil,
    },

    -- Mapper/S&D interactive text styling preferences
    mapperUI = {
        links = true,
        hover = true,
        visited = true,
        chips = true,
    },
}

-------------------------------------------------------------------------------
-- Room State
-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------
-- Room Characters Tag State
-------------------------------------------------------------------------------

snd.roomChars = snd.roomChars or {
    active = false,
    triggerIds = nil,
}

-------------------------------------------------------------------------------
-- Character State
-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------
-- Campaign State
-------------------------------------------------------------------------------

snd.campaign = snd.campaign or {
    active = false,
    levelTaken = 0,
    historyId = 0,
    completeBy = "",
    completedToday = 0,
    completedTodayDate = "",
    targets = {},      -- Full target list from cp info
    checkList = {},    -- Current check list from cp check
    canGetNew = nil,
    lastCheck = 0,
    -- Rewards tracking
    qpReward = 0,
    goldReward = 0,
    tpReward = 0,
    trainReward = 0,
    pracReward = 0,
    persistedCompleteBy = "",
    persistedQpReward = 0,
    persistedGoldReward = 0,
    persistedTpReward = 0,
    persistedTrainReward = 0,
    persistedPracReward = 0,
}

-------------------------------------------------------------------------------
-- Global Quest State
-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------
-- Quest State
-------------------------------------------------------------------------------

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
    blessingBonus = 0,
    pendingReward = nil,
    rewardTimer = nil,
    targetTriggerId = nil,
}

-------------------------------------------------------------------------------
-- History Display State
-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------
-- Main Target List (unified view of cp/gq targets)
-------------------------------------------------------------------------------

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
    --[[
        Current target structure:
        {
            keyword = "sinister vandal",
            name = "a sinister vandal",
            roomName = "In The Courtyard",  -- Only for room-based
            area = "diatz",
            index = 4,                       -- Index in target list
            activity = "cp",                 -- "cp", "gq", "quest", or nil
        }
    ]]
}

snd.tabs = snd.tabs or {
    active = "auto", -- auto|quest|gq|cp
}

-------------------------------------------------------------------------------
-- Navigation State
-------------------------------------------------------------------------------

snd.nav = snd.nav or {
    gotoArea = -1,
    gotoIndex = 0,
    gotoList = {},
    nextRoom = -1,
    goingToRoom = nil,
    nxState = nil,
    
    -- Auto-hunt state
    autoHunt = {
        direction = "",
        mob = "",
        data = {},
        active = false,
        keyword = "",
        throughPortal = false,
        lastDirection = "",
    },
    
    -- Hunt trick state
    huntTrick = {
        index = 1,
        firstTarget = true,
    },
    
    -- Quick where state
    quickWhere = {
        index = 1,
    },
    quickWhereByActivity = {
        quest = {rooms = {}, index = 1, active = false},
        gq = {rooms = {}, index = 1, active = false},
        cp = {rooms = {}, index = 1, active = false},
    },
}

-------------------------------------------------------------------------------
-- Combat/Scan State
-------------------------------------------------------------------------------

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
    local current = snd.targets and snd.targets.current
    if current and hasNonEmptyText(current.keyword) then
        send("scan " .. current.keyword, false)
    else
        send("scan", false)
    end
end

function snd.scan.smartScan()
    if snd.scan.hasActivityTarget() then
        snd.scan.runningSmartScan = true
        snd.utils.debugNote("Performing smart scan.")
        send("scan", false)
    else
        snd.scan.quickScan()
    end
end

-------------------------------------------------------------------------------
-- Window/GUI State
-------------------------------------------------------------------------------

snd.gui = snd.gui or {
    window = nil,
    initialized = false,
    hotspots = {},
    targetHotspots = {},
}

-------------------------------------------------------------------------------
-- Execute in Area/Room Timers
-------------------------------------------------------------------------------

snd.timers = snd.timers or {
    executeInArea = {i = 0, j = 0, arid = "", f = "", stat = 1},
    executeInRoom = {i = 0, j = 0, rmid = "", f = "", stat = 1},
    vidblainNav = {i = 0, j = 0, rmid = "", f = "", stat = 1},
}

-------------------------------------------------------------------------------
-- Maze Start Rooms (user-defined)
-------------------------------------------------------------------------------

snd.mazeStartRooms = snd.mazeStartRooms or {}

-------------------------------------------------------------------------------
-- Text Colors for Window
-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------
-- Save File Path
-------------------------------------------------------------------------------

snd.saveFile = getMudletHomeDir() .. "/persistence/snd_state.lua"
-- snd.dbFile = getMudletHomeDir() .. "/snd_database.db"

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

-- Flag to track if we've initialized
snd.initialized = false
snd.windowAutoOpenPending = false
snd.postLoginReconcileDone = snd.postLoginReconcileDone or false

function snd.initialize(silent)
    if snd.initialized then return end

    snd.windowAutoOpenPending = true
    
    if not silent then
        snd.utils.infoNote(snd.fullVersion .. " initializing...")
    end

    snd.utils.debugNote("Initializing Search & Destroy modules")
    
    -- Load saved state
    snd.loadState()

    snd.utils.debugNote("State load complete, initializing database")
    
    -- Initialize database
    if snd.db and snd.db.initialize then
        snd.db.initialize(silent)
    end

    snd.utils.debugNote("Database initialization complete, registering GMCP handlers")
    
    -- Register GMCP handlers
    if snd.gmcp and snd.gmcp.registerHandlers then
        snd.gmcp.registerHandlers()
    end

    -- Request character/room/quest GMCP data after handlers are attached
    snd.requestGMCPData()

    snd.utils.debugNote("GMCP handler registration complete, registering temp aliases")

    -- Register temp aliases for manual installs without XML
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
    
    -- Create GUI (if enabled)
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

-- Initialize silently on load, then announce when player is active
function snd.initializeSilent()
    snd.initialize(true)
end

function snd.tryAutoOpenWindow()
    if not snd.initialized then return end
    if not snd.windowAutoOpenPending then return end

    -- Hard login guard: never send commands unless GMCP state is active/in-game.
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
        expandAlias("snd window", false)
    end
end

-- Called when GMCP char.vitals is received
function snd.onCharVitalsReady(_)
    snd.tryAutoOpenWindow()
end

-- Called when GMCP confirms player is logged in and active
function snd.onPlayerActive()
    if not snd.initialized then return end

    -- Enable tags only after we are confirmed active to avoid polluting login/password prompts.
    if not snd.tagsEnabled then
        snd.tagsEnabled = true
        send("tags scan on", false)
        send("tags roomchars on", false)
    end

    if not snd.announcedReady then
        snd.announcedReady = true
        snd.utils.infoNote(snd.fullVersion .. " ready. Type 'xhelp' for commands.")
    end

    -- Campaign state has no GMCP payload; reconcile any open campaign history session
    -- once per active-login transition.
    if not snd.postLoginReconcileDone then
        snd.postLoginReconcileDone = true
        if snd.cp and snd.cp.hasOpenHistorySession and snd.cp.hasOpenHistorySession() then
            if snd.cp.requestCheck then
                snd.cp.requestCheck(0.8, "main.postLoginHistoryReconcile")
            else
                tempTimer(0.8, function()
                    snd.utils.debugNote("Sending 'cp check' (reason: main.postLoginHistoryReconcile:fallback)")
                    send("cp check", false)
                end)
            end
        end
    end
end

--- Request initial GMCP data from the server
function snd.requestGMCPData()
    if not snd.gmcp then return end
    
    -- Small delay to ensure connection is ready
    tempTimer(0.5, function()
        sendGMCP("request char")
    end)
    
    tempTimer(1.0, function()
        sendGMCP("request room")
        sendGMCP("request quest")
    end)
end

-------------------------------------------------------------------------------
-- State Persistence
-------------------------------------------------------------------------------

--- Save current state to file
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

--- Load state from file
function snd.loadState()
    snd.utils.debugNote("Loading state from " .. snd.saveFile)
    if not io.exists(snd.saveFile) then
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
    
    -- Merge loaded state with defaults
    if state.config then
        for k, v in pairs(state.config) do
            if type(v) == "table" and type(snd.config[k]) == "table" then
                for k2, v2 in pairs(v) do
                    snd.config[k][k2] = v2
                end
            else
                snd.config[k] = v
            end
        end
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

-------------------------------------------------------------------------------
-- Helper Functions for Current Activity
-------------------------------------------------------------------------------

--- Check if player is on a campaign
function snd.isOnCampaign()
    return snd.campaign.active
end

--- Check if player is on a global quest
function snd.isOnGquest()
    return snd.gquest.active
end

--- Check if player is on a quest
function snd.isOnQuest()
    return snd.quest.active
end

--- Check if there's any active hunting activity
function snd.hasActivity()
    return snd.campaign.active or snd.gquest.active or snd.quest.active
end

--- Get current activity type
function snd.getActivityType()
    if snd.campaign.active then return "cp" end
    if snd.gquest.active then return "gq" end
    if snd.quest.active then return "quest" end
    return "none"
end

--- Check if we have an activity target selected
function snd.hasActivityTarget()
    return snd.targets.current ~= nil and snd.targets.current.activity ~= nil
end

--- Check if current target is a cp/gq mob
function snd.isCpOrGqTarget()
    if not snd.targets.current then return false end
    local act = snd.targets.current.activity
    return act == "cp" or act == "gq"
end

-------------------------------------------------------------------------------
-- Target List Priority Sorting
-------------------------------------------------------------------------------

-- Priority values: lower = higher priority
local activityPriority = {
    gq = 1,      -- Global Quest - highest priority (time-limited competition)
    quest = 2,   -- Quest - second priority (time-limited)
    cp = 3,      -- Campaign - third priority (no time limit)
}

--- Get priority value for an activity type
-- @param activity Activity type string
-- @return Priority value (lower = higher priority)
function snd.getActivityPriority(activity)
    return activityPriority[activity] or 99
end

--- Sort target list by priority (GQ > Quest > CP)
-- Call this to ensure targets are displayed in priority order
function snd.sortTargetsByPriority()
    table.sort(snd.targets.list, function(a, b)
        local prioA = snd.getActivityPriority(a.activity)
        local prioB = snd.getActivityPriority(b.activity)
        
        if prioA ~= prioB then
            return prioA < prioB  -- Lower priority value = higher priority
        end
        
        -- Same activity type, sort by index
        return (a.index or 0) < (b.index or 0)
    end)
end

--- Clear the current target
function snd.clearTarget()
    snd.targets.current = nil
    if snd.gui and snd.gui.refresh then
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

--- Set a new target
function snd.setTarget(target)
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
    snd.tabs.active = normalized
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

-------------------------------------------------------------------------------
-- Event Callbacks (to be called by GMCP module)
-------------------------------------------------------------------------------

--- Called when room changes
function snd.onRoomChange()
    if snd.mapper and snd.mapper.onConfirmedRoomVisit then
        snd.mapper.onConfirmedRoomVisit(snd.room.current and snd.room.current.rmid)
    end

    local wasNavigating = (snd.nav.goingToRoom or snd.mapper.goingToRoom) ~= nil

    -- Check if we arrived at destination
    local destination = snd.nav.goingToRoom or snd.mapper.goingToRoom
    if destination and tostring(snd.room.current.rmid) == tostring(destination) then
        if snd.mapper and snd.mapper.flushPendingPersists then
            snd.mapper.flushPendingPersists()
        end
        snd.onDestinationArrived()
        snd.nav.goingToRoom = nil
        snd.mapper.goingToRoom = nil
    end

    -- Skip per-room GUI refresh while mid-route; the 2s periodic timer covers updates during travel.
    -- Refresh on arrival (wasNavigating=true, now nil) or during manual movement.
    local stillNavigating = (snd.nav.goingToRoom or snd.mapper.goingToRoom) ~= nil
    if not (wasNavigating and stillNavigating) then
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

--- Called when we arrive at navigation destination
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
    
    local action = snd.config.nxAction
    if snd.isCurrentRoomSafe() then
        snd.utils.debugNote("Skipping nxAction in safe room: " .. tostring(snd.room.current and snd.room.current.rmid))
    else
        -- Execute next action based on config
        if action == "smartscan" then
            snd.scan.smartScan()
        elseif action == "con" then
            send("con", false)
        elseif action == "scan" then
            send("scan", false)
        elseif action == "scanhere" then
            send("scan here", false)
        elseif action == "qs" then
            snd.scan.quickScan()
        end
    end

    local current = snd.targets and snd.targets.current
    local mode = tostring((snd.config and snd.config.xcpActionMode) or "qw"):lower()
    if mode == "off" then
        mode = "db"
    elseif mode ~= "db" and mode ~= "qw" and mode ~= "ht" then
        mode = "qw"
    end
    local nxState = snd.nav and snd.nav.nxState or nil
    local shouldRunXcpModeAction = false
    if current and nxState and nxState.arrived and not nxState.xcpActionFired then
        if snd.commands and snd.commands.buildTargetKeyFromCurrent then
            local currentKey = snd.commands.buildTargetKeyFromCurrent(current)
            shouldRunXcpModeAction = (currentKey ~= "" and currentKey == nxState.targetKey)
        else
            shouldRunXcpModeAction = true
        end
    end

    if shouldRunXcpModeAction and (current.activity == "cp" or current.activity == "gq") then
        if mode == "ht" and snd.commands and snd.commands.ht then
            snd.utils.debugNote("xcp mode ht: running live hunt after arrival")
            nxState.xcpActionFired = true
            snd.commands.ht("")
        elseif mode == "qw" and snd.commands and snd.commands.qw then
            snd.utils.debugNote("xcp mode qw: running exact live where after arrival")
            nxState.xcpActionFired = true
            snd.commands.qw("")
        elseif mode == "db" then
            snd.utils.debugNote("xcp mode db: using existing DB/mapped room list after arrival")
            nxState.xcpActionFired = true
        end
    end

end

--- Called when character state changes
function snd.onStateChange()
    -- Could trigger GUI updates, check for combat, etc.
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

-------------------------------------------------------------------------------
-- Cleanup on Unload
-------------------------------------------------------------------------------

function snd.cleanup()
    snd.utils.infoNote("Saving state before unload...")
    snd.saveState()
    
    -- Kill any timers we created
    -- Cleanup GUI
    if snd.gui and snd.gui.cleanup then
        snd.gui.cleanup()
    end
end

-------------------------------------------------------------------------------
-- Register system events
-------------------------------------------------------------------------------

-- Save state when profile is saved
registerAnonymousEventHandler("sysExitEvent", function()
    snd.cleanup()
end)

-- Save state periodically (every 5 minutes)
if snd.autoSaveTimer then
    killTimer(snd.autoSaveTimer)
end
snd.autoSaveTimer = tempTimer(300, function()
    snd.saveState()
end, true)

-- Module loaded silently
