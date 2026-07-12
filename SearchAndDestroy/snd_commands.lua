--[[
    Search and Destroy - Commands Module
    Mudlet Port
    
    Original MUSHclient plugin by Crowley
    Ported to Mudlet
    
    This module contains all user command handlers (aliases)
]]

snd = snd or {}
snd.commands = snd.commands or {}

local function getScopedActivity()
    if snd and snd.getActiveTab then
        local tab = snd.getActiveTab()
        if tab == "quest" or tab == "gq" or tab == "cp" then
            return tab
        end
    end
    if snd.targets and snd.targets.current and snd.targets.current.activity then
        return snd.targets.current.activity
    end
    return nil
end

local function ensureQuickWhereScopes()
    snd.nav = snd.nav or {}
    snd.nav.quickWhere = snd.nav.quickWhere or {}
    snd.nav.quickWhereByActivity = snd.nav.quickWhereByActivity or {}
    for _, activity in ipairs({"quest", "gq", "cp"}) do
        local slot = snd.nav.quickWhereByActivity[activity]
        if type(slot) ~= "table" then
            slot = {}
            snd.nav.quickWhereByActivity[activity] = slot
        end
        slot.rooms = slot.rooms or {}
        slot.index = tonumber(slot.index) or 1
        slot.active = slot.active == true
        slot.targetKey = tostring(slot.targetKey or "")
    end
end

local function persistQuickWhereScope(activity)
    ensureQuickWhereScopes()
    if activity ~= "quest" and activity ~= "gq" and activity ~= "cp" then
        return
    end
    local qw = snd.nav.quickWhere or {}
    snd.nav.quickWhereByActivity[activity] = {
        rooms = snd.utils.deepcopy(qw.rooms or {}),
        index = tonumber(qw.index) or 1,
        active = qw.active == true and type(qw.rooms) == "table" and #qw.rooms > 0,
        targetKey = tostring(qw.targetKey or ""),
    }
end

local function activateQuickWhereScope(activity)
    ensureQuickWhereScopes()
    local slot = snd.nav.quickWhereByActivity[activity]
    if type(slot) ~= "table" then
        return
    end
    snd.nav.quickWhere.rooms = snd.utils.deepcopy(slot.rooms or {})
    snd.nav.quickWhere.index = tonumber(slot.index) or 1
    snd.nav.quickWhere.active = slot.active == true and #snd.nav.quickWhere.rooms > 0
    snd.nav.quickWhere.scope = activity
    snd.nav.quickWhere.targetKey = tostring(slot.targetKey or "")
    snd.nav.quickWhere.pendingMatches = snd.nav.quickWhere.pendingMatches or {}
end

local function clearNxOverride()
    snd.nav = snd.nav or {}
    snd.nav.nxOverride = nil
end

local function setScopedCurrent(activity, target)
    if not snd.targets then return end
    snd.targets.scoped = snd.targets.scoped or {quest = nil, gq = nil, cp = nil}
    if activity == "quest" or activity == "gq" or activity == "cp" then
        snd.targets.scoped[activity] = target and snd.utils.deepcopy(target) or nil
    end
end

local function activateTabTarget(activity)
    if not activity or not snd.targets then
        return false
    end

    snd.targets.scoped = snd.targets.scoped or {quest = nil, gq = nil, cp = nil}
    local scoped = snd.targets.scoped[activity]
    if scoped then
        snd.targets.current = snd.utils.deepcopy(scoped)
        activateQuickWhereScope(activity)
        return true
    end

    if activity == "quest" then
        if snd.commands.selectQuestTarget then
            snd.commands.selectQuestTarget()
        end
        return snd.targets.current and snd.targets.current.activity == "quest"
    elseif activity == "cp" and snd.cp and snd.cp.getNextTarget then
        local first = snd.cp.getNextTarget()
        if first then
            snd.cp.selectTarget(1)
            return snd.targets.current and snd.targets.current.activity == "cp"
        end
    elseif activity == "gq" and snd.gq and snd.gq.getNextTarget then
        local first = snd.gq.getNextTarget()
        if first then
            snd.gq.selectTarget(1)
            return snd.targets.current and snd.targets.current.activity == "gq"
        end
    end

    return false
end

local function normalizeXcpActionMode(mode)
    local normalized = tostring(mode or "qw"):lower()
    if normalized == "off" then
        return "db"
    end
    if normalized ~= "db" and normalized ~= "qw" and normalized ~= "ht" then
        return "qw"
    end
    return normalized
end

local function getCharacterState()
    local state = snd.char and snd.char.state
    if (state == nil or tostring(state) == "") and gmcp and gmcp.char and gmcp.char.status then
        state = gmcp.char.status.state
    end
    return tostring(state or "0")
end

local function quickWhereBlockedReason()
    local state = getCharacterState()
    if state == "8" then
        return "combat"
    elseif state == "9" then
        return "sleeping"
    end
    return nil
end

local function canStartQuickWhere()
    local reason = quickWhereBlockedReason()
    if reason then
        snd.utils.infoNote("Quick where skipped while " .. reason .. ".")
        snd.utils.qwDebugNote("QW DEBUG: blocked by char.status.state=" .. getCharacterState())
        return false
    end
    return true
end

local xcpModeDescriptions = {
    db = "db - use stored DB/mapped rooms only",
    qw = "qw - live where, exact-match selected target",
    ht = "ht - live hunt, then exact live where",
}

local function collectKnownMobNames(activity, options)
    local opts = options or {}
    local names = {}

    if snd.targets and snd.targets.list then
        for _, target in ipairs(snd.targets.list) do
            if (not activity or target.activity == activity) and not target.dead then
                local name = snd.utils.trim(target.mob or target.name or "")
                if name ~= "" then
                    table.insert(names, name)
                end
            end
        end
    end

    if opts.includeConwin and snd.conwin and snd.conwin.mobs then
        for _, mob in ipairs(snd.conwin.mobs) do
            if not mob.dead then
                local name = snd.utils.trim(mob.name or "")
                if name ~= "" then
                    table.insert(names, name)
                end
            end
        end
    end

    return names
end

local function commandSelectorForTarget(target, mode, options)
    if not target then return "", "none" end
    local name = snd.utils.trim(target.name or target.mob or "")
    local areaKey = snd.utils.trim(target.area or target.arid or "")
    if name == "" then
        local keyword = snd.utils.trim(target.keyword or "")
        return keyword, keyword ~= "" and "stored-keyword" or "empty"
    end

    local knownNames = collectKnownMobNames(target.activity, {
        includeConwin = mode == "kill",
    })
    local selectorName = name
    if mode == "kill" and snd.conwin and snd.conwin.visibleNameForActivityTarget then
        local visibleName = snd.utils.trim(snd.conwin.visibleNameForActivityTarget(name, target.activity) or "")
        if visibleName ~= "" then
            selectorName = visibleName
        end
    end

    local selector, reason = snd.utils.buildMobCommandSelector(selectorName, knownNames, {
        mode = mode,
        areaKey = areaKey,
    })

    if selector == "" then
        if selectorName ~= name then
            selector = snd.utils.trim(snd.utils.findKeyword(selectorName))
        else
            selector = snd.utils.trim(target.keyword or target.matchedMobName or snd.utils.findKeyword(name))
        end
        reason = "fallback-keyword"
    end

    if options and options.debugContext then
        snd.utils.debugNote(string.format(
            "%s selector for '%s': '%s' (%s)",
            options.debugContext,
            selectorName,
            selector,
            tostring(reason)
        ))
    end

    return selector, reason
end

-------------------------------------------------------------------------------
-- Module Loading Helpers
-------------------------------------------------------------------------------

function snd.commands.ensureGuiLoaded()
    if snd.gui and snd.gui.toggle then
        return true
    end

    local guiPath = getMudletHomeDir() .. "/SearchAndDestroy/snd_gui.lua"
    if io.exists(guiPath) then
        dofile(guiPath)
    else
        snd.utils.errorNote("GUI module not found at: " .. guiPath)
        snd.utils.errorNote("Run 'sndreload' after copying snd_gui.lua to that path.")
        return false
    end

    if snd.gui and snd.gui.toggle then
        return true
    end

    snd.utils.errorNote("GUI module failed to load. Try 'sndreload' for a full reload.")
    return false
end

function snd.commands.showWindow()
    if snd.commands.ensureGuiLoaded() then
        snd.gui.show()
    end
end

function snd.commands.sendGameCommand(cmd, echo)
    if not cmd or cmd == "" then
        return false
    end

    local noEcho = (echo == false)

    -- Mudlet-native send(cmd, echo) is the most reliable route for aliases and
    -- server command dispatch. Keep legacy Send*/SendNoEcho fallbacks for
    -- compatibility with older helper layers.
    if type(send) == "function" then
        local ok = pcall(send, cmd, not noEcho)
        if ok then return true end
    end

    if noEcho and type(SendNoEcho) == "function" then
        local ok = pcall(SendNoEcho, cmd)
        if ok then return true end
    end

    if type(Send) == "function" then
        local ok = pcall(Send, cmd)
        if ok then return true end
    end

    snd.utils.errorNote("Unable to send command to game: '" .. tostring(cmd) .. "'")
    return false
end

-- Route all movement through command aliases so S&D stays mapper-independent.
function snd.commands.gotoRoomViaAlias(roomId)
    roomId = tonumber(roomId)
    if not roomId or roomId <= 0 then
        return false
    end

    local travelAlias = (snd.config and snd.config.speed == "walk") and "walkto" or "xrt"
    local cmd = travelAlias .. " " .. tostring(roomId)
    if type(extendedAlias) == "function" then
        extendedAlias(cmd)
    elseif type(expandAlias) == "function" then
        expandAlias(cmd)
    else
        send(cmd, false)
    end
    return true
end

-------------------------------------------------------------------------------
-- Main Command: snd
-------------------------------------------------------------------------------

function snd.commands.snd(args)
    args = snd.utils.trim(args or "")
    
    if args == "" or args == "help" then
        snd.commands.showHelp()
    elseif args:match("^help%s+") then
        snd.commands.xhelp(args:match("^help%s+(.+)$") or "")
    elseif args == "version" then
        snd.utils.infoNote(snd.fullVersion)
    elseif args == "status" then
        snd.commands.showStatus()
    elseif args == "targets" then
        snd.commands.showTargets()
    elseif args:match("^stats") then
        snd.commands.showStats(args:gsub("^stats", "", 1))
    elseif args == "save" then
        snd.saveState()
        snd.utils.infoNote("State saved.")
    elseif args == "reload" then
        snd.loadState()
        snd.utils.infoNote("State reloaded.")
    elseif args == "debug" or args:match("^debug%s+") then
        local mode = snd.utils.trim(args:match("^debug%s+(.+)$") or ""):lower()
        local nextValue
        if mode == "" then
            if snd.debug and snd.debug.toggle then
                nextValue = snd.debug.toggle()
            else
                snd.config.debugMode = not snd.config.debugMode
                nextValue = snd.config.debugMode
                snd.utils.infoNote("Debug mode: " .. (nextValue and "ON" or "OFF"))
            end
        elseif mode == "on" or mode == "true" or mode == "1" then
            nextValue = true
            if snd.debug and snd.debug.setEnabled then
                snd.debug.setEnabled(true)
            else
                snd.config.debugMode = true
            end
            snd.utils.infoNote("Debug mode: ON")
        elseif mode == "off" or mode == "false" or mode == "0" then
            nextValue = false
            if snd.debug and snd.debug.setEnabled then
                snd.debug.setEnabled(false)
            else
                snd.config.debugMode = false
            end
            snd.utils.infoNote("Debug mode: OFF")
        else
            snd.utils.infoNote("Usage: snd debug [on|off]")
            return
        end
        snd.config.debugMode = nextValue
        snd.saveState()
    elseif args:match("^window%s+font%s+%d+$") then
        local size = tonumber(args:match("^window%s+font%s+(%d+)$"))
        if size and size >= 6 then
            snd.config.window.fontSize = size
            if snd.commands.ensureGuiLoaded() then
                snd.gui.applyFontSize()
            end
            snd.saveState()
            snd.utils.infoNote("Window font size set to " .. size)
        else
            snd.utils.infoNote("Usage: snd window font <number>")
        end
    elseif args == "window" then
        if snd.commands.ensureGuiLoaded() then
            snd.gui.toggle()
        end
    elseif args == "show" then
        snd.commands.showWindow()
    elseif args == "db" then
        snd.commands.showDbInfo()
    elseif args:match("^conwin") then
        snd.commands.conwin(args:gsub("^conwin", "", 1))
    elseif args:match("^channel") then
        snd.commands.channel(args:gsub("^channel", "", 1))
    elseif args:match("^history") then
        snd.commands.history(args:gsub("^history", "", 1))
    elseif args:match("^db%s+") then
        local dbPath = args:match("^db%s+(.+)$")
        if dbPath then
            snd.db.setFile(dbPath)
            snd.db.initialize()
        end
    else
        snd.utils.infoNote("Unknown command: " .. args)
        snd.commands.showHelp()
    end
end

-------------------------------------------------------------------------------
-- snd conwin - Consider Window Commands
-------------------------------------------------------------------------------

function snd.commands.conwin(args)
    args = snd.utils.trim(args or "")
    if not snd.conwin then
        snd.utils.infoNote("ConWin module not loaded.")
        return
    end

    if args == "" or args == "help" then
        snd.commands.showConwinHelp()
    elseif args == "on" then
        snd.conwin.setEnabled(true)
        snd.utils.infoNote("ConWin enabled.")
    elseif args == "off" then
        snd.conwin.setEnabled(false)
        snd.utils.infoNote("ConWin disabled.")
    elseif args == "toggle" then
        snd.conwin.toggle()
        snd.utils.infoNote("ConWin " .. ((snd.config.conwin and snd.config.conwin.enabled) and "enabled." or "disabled."))
    elseif args == "refresh" then
        snd.conwin.refresh()
    elseif args == "clear" then
        snd.conwin.clear("manual")
    elseif args == "consider" then
        snd.conwin.setMode(args)
        snd.utils.infoNote("ConWin room-action mode set to: " .. args)
    elseif args:match("^mode%s+") then
        local mode = snd.utils.trim(args:match("^mode%s+(.+)$") or "")
        if snd.conwin.setMode(mode) then
            snd.utils.infoNote("ConWin room-action mode set to: " .. mode)
        else
            snd.utils.infoNote("Usage: snd conwin mode <consider|off>")
        end
    elseif args:match("^fontsize%s+%d+$") then
        local n = tonumber(args:match("^fontsize%s+(%d+)$"))
        if snd.conwin.setFontSize(n) then
            snd.utils.infoNote("ConWin font size set to " .. tostring(n))
        else
            snd.utils.infoNote("Usage: snd conwin fontsize <6-24>")
        end
    elseif args:match("^killcommand%s+") then
        local command = snd.utils.trim(args:match("^killcommand%s+(.+)$") or "")
        if snd.conwin.setKillCommand and snd.conwin.setKillCommand(command) then
            snd.utils.infoNote("ConWin kill command set to: " .. command)
        else
            snd.utils.infoNote("Usage: snd conwin killcommand <command>")
        end
    elseif args == "killcommand" then
        local current = (snd.config and snd.config.conwin and snd.config.conwin.killCommand) or "kill"
        snd.utils.infoNote("ConWin kill command: " .. tostring(current))
    elseif args:match("^repopulate%s+%d+$") then
        local count = tonumber(args:match("^repopulate%s+(%d+)$"))
        if snd.conwin.setRepopulate and snd.conwin.setRepopulate(count) then
            snd.utils.infoNote("ConWin repopulate threshold set to: " .. tostring(count) .. " kills (0=off)")
        else
            snd.utils.infoNote("Usage: snd conwin repopulate <0-999>")
        end
    elseif args:match("^focusid%s+") then
        local mode = snd.utils.trim(args:match("^focusid%s+(.+)$") or ""):lower()
        if snd.conwin.setFocusIdMode and snd.conwin.setFocusIdMode(mode) then
            snd.utils.infoNote("ConWin focus-id mode set to: " .. mode)
        else
            snd.utils.infoNote("Usage: snd conwin focusid <strict|fallback>")
        end
    elseif args == "focusid" then
        local focusMode = ((snd.config and snd.config.conwin and snd.config.conwin.strictFocusIdOnly) and "strict" or "fallback")
        snd.utils.infoNote("ConWin focus-id mode: " .. focusMode)
    elseif args:match("^aligntags%s+") then
        local mode = snd.utils.trim(args:match("^aligntags%s+(.+)$") or ""):lower()
        if snd.conwin.setAlignTagsEnabled and snd.conwin.setAlignTagsEnabled(mode) then
            snd.utils.infoNote("ConWin alignment tags: " .. mode)
        else
            snd.utils.infoNote("Usage: snd conwin aligntags <on|off>")
        end
    elseif args == "aligntags" then
        local alignState = (snd.config and snd.config.conwin and snd.config.conwin.alignTags == false) and "off" or "on"
        snd.utils.infoNote("ConWin alignment tags: " .. alignState)
    else
        snd.utils.infoNote("Unknown conwin command: " .. args)
        snd.commands.showConwinHelp()
    end
end

-------------------------------------------------------------------------------
-- xcp - Select Target
-------------------------------------------------------------------------------

function snd.commands.xcp(args)
    args = snd.utils.trim(args or "")

    local modeArg = nil
    if args == "mode" then
        modeArg = ""
    else
        modeArg = args:match("^mode%s+(.+)$")
    end
    if modeArg ~= nil then
        local normalized = snd.utils.trim(modeArg or ""):lower()
        if normalized == "off" then
            normalized = "db"
        end
        if normalized == "" then
            local currentMode = normalizeXcpActionMode(snd.config.xcpActionMode or "qw")
            snd.utils.infoNote("Current 'xcp' mode: " .. (xcpModeDescriptions[currentMode] or xcpModeDescriptions.qw) .. ".")
            snd.utils.infoNote("Syntax: xcp mode <db|qw|ht>")
            snd.utils.infoNote("  db: use stored DB/mapped rooms; no live where/hunt after arrival.")
            snd.utils.infoNote("  qw: live where selected target, accepting only exact returned mob names.")
            snd.utils.infoNote("  ht: live hunt selected target, then exact live where.")
        elseif xcpModeDescriptions[normalized] then
            snd.config.xcpActionMode = normalized
            snd.utils.infoNote("Set 'xcp' mode to: " .. xcpModeDescriptions[normalized] .. ".")
            snd.saveState()
        else
            snd.utils.infoNote("Invalid xcp mode. Syntax: xcp mode <db|qw|ht>")
        end
        return
    end
    
    if args == "" then
        -- Show current target and list
        snd.commands.showTargets()
        return
    end
    
    local index = tonumber(args)
    if not index then
        snd.utils.infoNote("Usage: xcp <number>")
        return
    end
    
    local scopedActivity = getScopedActivity()

    if scopedActivity == "quest" then
        if index ~= 1 then
            snd.utils.infoNote("Quest tab has a single target (use xcp 1)")
            return
        end
        clearNxOverride()
        snd.commands.selectQuestTarget()
        return
    end

    -- Prefer active tab context first, then fallback
    local success = false

    if scopedActivity == "cp" and snd.campaign.active then
        success = snd.cp.selectTarget(index)
    elseif scopedActivity == "gq" and snd.gquest.active then
        success = snd.gq.selectTarget(index)
    end

    if not success and snd.campaign.active then
        success = snd.cp.selectTarget(index)
    end

    if not success and snd.gquest.active then
        success = snd.gq.selectTarget(index)
    end
    
    if success then
        clearNxOverride()
    end

    if not success then
        snd.utils.infoNote("No target at index " .. index)
    end
end

function snd.commands.selectQuickWhereRoom(index, activity)
    local roomIndex = tonumber(index)
    if not roomIndex then
        snd.utils.infoNote("Invalid room index: " .. tostring(index))
        return false
    end

    local scope = tostring(activity or ""):lower()
    if scope ~= "quest" and scope ~= "gq" and scope ~= "cp" then
        scope = getScopedActivity() or "quest"
    end

    if scope and scope ~= "" then
        activateQuickWhereScope(scope)
        if activateTabTarget(scope) and snd.setActiveTab then
            snd.setActiveTab(scope, {save = true, refresh = false})
        end
    end

    local quickWhere = snd.nav and snd.nav.quickWhere or nil
    if not quickWhere or not quickWhere.rooms or #quickWhere.rooms == 0 then
        snd.utils.infoNote("No room list available for " .. tostring(scope) .. " target")
        return false
    end

    local roomId = tonumber(quickWhere.rooms[roomIndex])
    if not roomId or roomId <= 0 then
        snd.utils.infoNote("No room at index " .. tostring(roomIndex))
        return false
    end

    quickWhere.index = roomIndex
    persistQuickWhereScope(scope or quickWhere.scope)

    if snd.targets and snd.targets.current then
        snd.targets.current.roomId = roomId
    end

    snd.utils.infoNote("Going to room " .. tostring(roomId))
    snd.commands.gotoRoomViaAlias(roomId)
    return true
end

-------------------------------------------------------------------------------
-- nx - Next Target / Go to Target
-------------------------------------------------------------------------------

function snd.commands.buildTargetKeyFromEntry(target)
    if not target then return "" end
    return table.concat({
        tostring(target.activity or ""),
        tostring(target.mob or ""),
        tostring(target.roomName or ""),
        tostring(target.arid or target.loc or ""),
    }, "|")
end

function snd.commands.buildTargetKeyFromCurrent(target)
    if not target then return "" end
    return table.concat({
        tostring(target.activity or ""),
        tostring(target.name or ""),
        tostring(target.roomName or ""),
        tostring(target.area or ""),
    }, "|")
end

-- Quick-where lists should stick to the selected target identity only.
-- Room fields are intentionally excluded so moving between matched rooms does
-- not invalidate the active quick-where cycle.
function snd.commands.buildQuickWhereTargetKeyFromCurrent(target)
    if not target then return "" end
    return table.concat({
        tostring(target.activity or ""),
        tostring(target.name or ""),
        tostring(target.area or ""),
    }, "|")
end

local function targetMatchesCurrent(entry, current)
    if not entry or not current then return false end
    if entry.activity ~= current.activity then return false end
    if entry.mob ~= current.name then return false end
    if current.roomId and current.roomId ~= "" then
        return tostring(entry.rmid) == tostring(current.roomId)
    end
    if current.roomName and current.roomName ~= "" then
        return entry.roomName == current.roomName
    end
    return true
end

local function getNxTargets()
    local targets = {}
    for _, t in ipairs(snd.targets.list) do
        if t.activity ~= "quest" and not t.dead then
            table.insert(targets, t)
        end
    end
    return targets
end

local function selectTargetEntry(target)
    if not target then return false end

    snd.setTarget({
        keyword = target.keyword,
        name = target.mob,
        roomName = target.roomName or "",
        roomId = target.rmid,
        area = target.arid or target.loc,
        index = target.index,
        activity = target.activity,
    })
    snd.utils.infoNote("Target: " .. target.mob)
    if target.roomName == nil or target.roomName == "" then
        if target.activity == "cp" or target.activity == "gq" then
            local results = snd.mapper.searchMobLocations(target.mob, target.arid)
            if not results or #results == 0 then
                snd.commands.qw("")
            end
        elseif target.keyword then
            snd.commands.qw("")
        end
    end
    return true
end

function snd.commands.nx()
    local current = snd.targets.current
    local nxOverride = snd.nav and snd.nav.nxOverride or nil
    local useAdhocQuickWhere = nxOverride and nxOverride.mode == "adhoc_qw"
    local initialQuickWhere = snd.nav and snd.nav.quickWhere or nil
    if not useAdhocQuickWhere
        and initialQuickWhere
        and initialQuickWhere.isAdhoc == true
        and initialQuickWhere.active
        and initialQuickWhere.rooms
        and #initialQuickWhere.rooms > 0
    then
        useAdhocQuickWhere = true
    end

    local scopedActivity = getScopedActivity()
    if not useAdhocQuickWhere
        and scopedActivity
        and (not current or current.activity ~= scopedActivity)
    then
        activateTabTarget(scopedActivity)
    end

    current = snd.targets.current

    if not current then
        snd.utils.infoNote("No target selected. Use xcp to select a target first")
        return
    end

    local function currentQuickWhereList()
        local quickWhere = snd.nav and snd.nav.quickWhere or nil
        if not quickWhere or not quickWhere.active or not quickWhere.rooms or #quickWhere.rooms == 0 then
            return nil
        end

        if useAdhocQuickWhere or quickWhere.isAdhoc == true then
            return quickWhere
        end

        local quickWhereKey = tostring(quickWhere.targetKey or "")
        local currentQuickWhereKey = snd.commands.buildQuickWhereTargetKeyFromCurrent(current)
        if quickWhereKey == "" or currentQuickWhereKey == "" or quickWhereKey == currentQuickWhereKey then
            return quickWhere
        end

        return nil
    end

    local currentKey = snd.commands.buildTargetKeyFromCurrent(current)
    if not snd.nav.nxState or snd.nav.nxState.targetKey ~= currentKey then
        snd.nav.nxState = {
            targetKey = currentKey,
            arrived = false,
        }
        if currentQuickWhereList() then
            snd.nav.nxState.arrived = true
        else
            snd.commands.gotoTarget()
            return
        end
    end

    if not snd.nav.nxState.arrived then
        local targetRoom = current.roomId
        local currentRoom = snd.room and snd.room.current and snd.room.current.rmid or nil
        if currentQuickWhereList() then
            snd.nav.nxState.arrived = true
        end
        if targetRoom and currentRoom and tostring(targetRoom) == tostring(currentRoom) then
            snd.nav.nxState.arrived = true
        end
        if not snd.nav.nxState.arrived then
            snd.commands.gotoTarget()
            return
        end
    end

    local quickWhere = currentQuickWhereList()
    if quickWhere then
        if not useAdhocQuickWhere then
            local quickWhereKey = quickWhere.targetKey or ""
            local currentQuickWhereKey = snd.commands.buildQuickWhereTargetKeyFromCurrent(current)
            if quickWhereKey ~= "" and currentQuickWhereKey ~= "" and quickWhereKey ~= currentQuickWhereKey then
                quickWhere = nil
            end
        end
    end

    -- Campaign/GQ room searches populate snd.nav.gotoList for the displayed
    -- XCP table. If quick-where state was not built (or was stale), use this
    -- list as a fallback cycle source so nx can still advance through rooms.
    local currentQuickWhereKey = snd.commands.buildQuickWhereTargetKeyFromCurrent(current)
    local gotoListKey = snd.nav and snd.nav.gotoListTargetKey or ""
    local gotoListMatchesCurrent = (gotoListKey ~= "" and currentQuickWhereKey ~= "" and gotoListKey == currentQuickWhereKey)

    if (not quickWhere or not quickWhere.active or not quickWhere.rooms or #quickWhere.rooms == 0)
        and snd.nav.gotoList and gotoListMatchesCurrent
    then
        local fallbackRooms = {}
        local seen = {}

        for i = 1, #snd.nav.gotoList do
            local entry = snd.nav.gotoList[i]
            if entry and entry.type == "room" then
                local roomId = tonumber(entry.id) or -1
                if roomId > 0 and not seen[roomId] then
                    seen[roomId] = true
                    table.insert(fallbackRooms, roomId)
                end
            end
        end

        if #fallbackRooms > 0 and snd.nav.quickWhere then
            snd.nav.quickWhere.rooms = fallbackRooms
            snd.nav.quickWhere.index = 1
            snd.nav.quickWhere.active = true
            snd.nav.quickWhere.processed = true
            snd.nav.quickWhere.pendingMatches = {}
            snd.nav.quickWhere.scope = current and current.activity or snd.nav.quickWhere.scope
            snd.nav.quickWhere.targetKey = currentQuickWhereKey
            persistQuickWhereScope(snd.nav.quickWhere.scope)
            quickWhere = snd.nav.quickWhere
            snd.utils.debugNote("NX: seeded cycle list from current XCP results")
        end
    end

    if quickWhere and quickWhere.active and quickWhere.rooms and #quickWhere.rooms > 0 then
        local currentRoom = snd.room and snd.room.current and snd.room.current.rmid or nil
        local targetRoom = current and current.roomId or nil
        local foundIndex = nil

        -- Prioritize the room we are currently standing in; the selected target
        -- can still point at an earlier room from the quick-where result set.
        local function findRoomIndex(roomId)
            if not roomId then
                return nil
            end
            for i, candidate in ipairs(quickWhere.rooms) do
                if tostring(candidate) == tostring(roomId) then
                    return i
                end
            end
            return nil
        end

        local currentRoomIndex = findRoomIndex(currentRoom)
        foundIndex = currentRoomIndex
        if not foundIndex and (not currentRoom or tostring(currentRoom) == "") then
            foundIndex = findRoomIndex(targetRoom)
        end

        local nextIndex = nil
        local wrappingCycle = false
        if foundIndex then
            if foundIndex < #quickWhere.rooms then
                nextIndex = foundIndex + 1
            else
                nextIndex = 1
                -- Wrap when cycling a multi-room list, OR when standing in the
                -- only room of a single-room list (currentRoomIndex proves the
                -- player is physically here, not just targeting it).
                wrappingCycle = #quickWhere.rooms > 1 or currentRoomIndex ~= nil
            end
        else
            nextIndex = quickWhere.index or 1
        end
        quickWhere.index = nextIndex
        persistQuickWhereScope(quickWhere.scope or (current and current.activity))

        -- For cp/gq wrap, honor configured xcp mode (db|qw|ht) without
        -- forcing an extra move back to room #1 first.
        if wrappingCycle and current and (current.activity == "cp" or current.activity == "gq") then
            local wrapMode = normalizeXcpActionMode((snd.config and snd.config.xcpActionMode) or "qw")
            if wrapMode == "qw" and snd.commands and snd.commands.qw then
                snd.utils.debugNote("NX: wrap detected, refreshing quick-where without extra move")
                snd.commands.qw("")
                return
            elseif wrapMode == "ht" and snd.commands and snd.commands.ht then
                snd.utils.debugNote("NX: wrap detected, running hunt trick without extra move")
                snd.commands.ht("")
                return
            end
            -- wrapMode == "db": fall through to normal room movement.
        end

        local nextRoomId = quickWhere.rooms[nextIndex]
        if nextRoomId then
            snd.utils.infoNote("Going to room " .. nextRoomId)
            snd.commands.gotoRoomViaAlias(nextRoomId)
            return
        end
    end

    -- No active quick-where room list for this target: keep the selected target
    -- and simply retry going to its current mapped room.
    snd.commands.gotoTarget()
end

function snd.commands.handleAlreadyInRoom(roomId)
    local current = snd.targets.current
    if not current then
        return false
    end

    local cycleRooms = {}
    local seen = {}

    local quickWhere = snd.nav.quickWhere
    if quickWhere and quickWhere.active and quickWhere.rooms and #quickWhere.rooms > 0 then
        for _, candidate in ipairs(quickWhere.rooms) do
            local id = tonumber(candidate) or -1
            if id > 0 and not seen[id] then
                seen[id] = true
                table.insert(cycleRooms, id)
            end
        end
    end

    if #cycleRooms == 0 and snd.nav.gotoList then
        for i = 1, #snd.nav.gotoList do
            local entry = snd.nav.gotoList[i]
            if entry and entry.type == "room" then
                local id = tonumber(entry.id) or -1
                if id > 0 and not seen[id] then
                    seen[id] = true
                    table.insert(cycleRooms, id)
                end
            end
        end
    end

    if #cycleRooms <= 1 then
        return false
    end

    local currentId = tonumber(roomId) or tonumber(snd.room and snd.room.current and snd.room.current.rmid)
    if not currentId then
        return false
    end

    local foundIndex = nil
    for i, candidate in ipairs(cycleRooms) do
        if tonumber(candidate) == currentId then
            foundIndex = i
            break
        end
    end

    if not foundIndex then
        return false
    end

    local nextIndex = foundIndex < #cycleRooms and (foundIndex + 1) or 1
    local nextRoomId = cycleRooms[nextIndex]
    if not nextRoomId or tonumber(nextRoomId) == currentId then
        return false
    end

    snd.utils.infoNote("Already in room " .. tostring(currentId) .. ", moving to room " .. tostring(nextRoomId))
    snd.commands.gotoRoomViaAlias(nextRoomId)
    return true
end

-------------------------------------------------------------------------------
-- qw - Quick Where
-------------------------------------------------------------------------------

local function resolveSelectedTargetKeyword(mode)
    local function hasText(value)
        return snd.utils.trim(tostring(value or "")) ~= ""
    end

    local scopedActivity = getScopedActivity()
    if scopedActivity and (not snd.targets.current or snd.targets.current.activity ~= scopedActivity) then
        activateTabTarget(scopedActivity)
    end

    local keyword = ""
    local exactNameHint = ""
    if snd.targets.current and (hasText(snd.targets.current.name) or hasText(snd.targets.current.keyword)) then
        keyword = commandSelectorForTarget(snd.targets.current, mode or "where", {
            debugContext = "QW",
        })
        if hasText(snd.targets.current.name) then
            exactNameHint = snd.targets.current.name
        end
    elseif snd.quest and snd.quest.active and snd.quest.target
        and (hasText(snd.quest.target.keyword) or hasText(snd.quest.target.mob))
    then
        local questTarget = {
            name = snd.quest.target.mob or "",
            keyword = snd.quest.target.keyword or "",
            activity = "quest",
            area = snd.quest.target.arid or snd.quest.target.area or "",
        }
        keyword = commandSelectorForTarget(questTarget, mode or "where", {
            debugContext = "QW quest",
        })
        exactNameHint = questTarget.name
    end

    return keyword, exactNameHint
end

local function runQuickWhere(args, exact, options)
    args = snd.utils.trim(args or "")
    local opts = options or {}

    if not canStartQuickWhere() then
        return
    end

    local function hasText(value)
        return snd.utils.trim(tostring(value or "")) ~= ""
    end

    local keyword = args
    local rawKeyword = keyword
    local exactNameHint = ""
    local startIndex = 1
    local selectedTargetLookup = opts.forceTargetExact == true

    local prefixedIndex, prefixedKeyword = keyword:match("^(%d+)%.(.+)$")
    if prefixedIndex and prefixedKeyword then
        startIndex = tonumber(prefixedIndex) or 1
        keyword = snd.utils.trim(prefixedKeyword)
    end

    -- Support legacy placeholders that refer to the currently tracked target.
    -- Players commonly use `qw target`, which should behave like `qw`.
    local lowered = keyword:lower()
    if lowered == "target" or lowered == "current" then
        keyword = ""
        selectedTargetLookup = true
    elseif lowered == "cp_target" then
        for _, target in ipairs(snd.targets.list or {}) do
            if target.activity == "cp" and not target.dead then
                keyword = commandSelectorForTarget(target, "where", {
                    debugContext = "QW cp_target",
                })
                exactNameHint = target.mob or ""
                selectedTargetLookup = true
                break
            end
        end
    elseif lowered == "gq_target" then
        for _, target in ipairs(snd.targets.list or {}) do
            if target.activity == "gq" and not target.dead then
                keyword = commandSelectorForTarget(target, "where", {
                    debugContext = "QW gq_target",
                })
                exactNameHint = target.mob or ""
                selectedTargetLookup = true
                break
            end
        end
    elseif lowered == "quest_target" and snd.quest and snd.quest.target then
        local questTarget = {
            name = snd.quest.target.mob or "",
            keyword = snd.quest.target.keyword or "",
            activity = "quest",
            area = snd.quest.target.arid or snd.quest.target.area or "",
        }
        keyword = commandSelectorForTarget(questTarget, "where", {
            debugContext = "QW quest_target",
        })
        exactNameHint = questTarget.name
        selectedTargetLookup = true
    end

    local scopedActivity = getScopedActivity()
    local isAdhocQw = rawKeyword ~= ""
        and not selectedTargetLookup
        and lowered ~= "target"
        and lowered ~= "current"
        and lowered ~= "cp_target"
        and lowered ~= "gq_target"
        and lowered ~= "quest_target"

    -- If no args, use current target in active tab scope
    if keyword == "" then
        keyword, exactNameHint = resolveSelectedTargetKeyword("where")
        selectedTargetLookup = true
        if keyword == "" then
            snd.utils.infoNote("No target selected. Usage: qw <keyword>")
            return
        end
    end

    keyword = snd.utils.trim(keyword or "")
    if keyword:lower() == "target" or keyword:lower() == "current" then
        keyword, exactNameHint = resolveSelectedTargetKeyword("where")
        selectedTargetLookup = true
    end
    if keyword == "" then
        snd.utils.infoNote("No target keyword available. Usage: qw <keyword>")
        return
    end

    if hasText(opts.exactMatchText) then
        exactNameHint = opts.exactMatchText
        selectedTargetLookup = true
    end

    local requireExactTarget = exact == true or hasText(exactNameHint) or opts.forceTargetExact == true

    snd.triggers.enableQuickWhereTriggers()
    snd.nav = snd.nav or {}
    if isAdhocQw then
        snd.nav.nxOverride = {
            mode = "adhoc_qw",
            keyword = keyword,
        }
    else
        clearNxOverride()
    end
    if snd.nav.quickWhere then
        snd.nav.quickWhere.lastMatch = nil
        snd.nav.quickWhere.pendingMatches = {}
        snd.nav.quickWhere.processed = false
        snd.nav.quickWhere.isAdhoc = isAdhocQw
        snd.nav.quickWhere.requestedKeyword = keyword
        snd.nav.quickWhere.lookupKeyword = keyword
        snd.nav.quickWhere.index = startIndex
        snd.nav.quickWhere.exact = requireExactTarget
        snd.nav.quickWhere.completed = false
        snd.nav.quickWhere.accepted = false
        snd.nav.quickWhere.awaitingCommandEcho = true
        snd.nav.quickWhere.probePending = false
        snd.nav.quickWhere.exactTargetName = (selectedTargetLookup and hasText(exactNameHint)) and exactNameHint or nil
        if requireExactTarget then
            local exactText = ""
            if exactNameHint ~= "" then
                exactText = exactNameHint
            elseif isAdhocQw then
                exactText = keyword
            elseif snd.targets and snd.targets.current and snd.targets.current.name and snd.targets.current.name ~= "" then
                exactText = snd.targets.current.name
            else
                exactText = keyword
            end
            snd.nav.quickWhere.exactMatchText = exactText
            snd.utils.qwDebugNote(string.format(
                "QW DEBUG: exact live match required target='%s', selector='%s', start=%d",
                tostring(exactText),
                tostring(keyword),
                tonumber(startIndex) or 1
            ))
        else
            snd.nav.quickWhere.exactMatchText = nil
            snd.nav.quickWhere.exactTargetName = nil
        end
        snd.nav.quickWhere.source = opts.source or (selectedTargetLookup and "target" or "adhoc")
        snd.nav.quickWhere.scope = scopedActivity or (snd.targets.current and snd.targets.current.activity) or "unknown"
        if snd.nav.quickWhere.processTimer then
            killTimer(snd.nav.quickWhere.processTimer)
            snd.nav.quickWhere.processTimer = nil
        end
    end

    if startIndex > 1 then
        local cmd = string.format("where %d.%s", startIndex, keyword)
        snd.utils.qwDebugNote("QW DEBUG: start index=" .. tostring(startIndex) .. ", keyword='" .. keyword .. "', cmd='" .. cmd .. "'")
        snd.commands.sendGameCommand(cmd, false)
    else
        local cmd = "where " .. keyword
        snd.utils.qwDebugNote("QW DEBUG: start index=1, keyword='" .. keyword .. "', cmd='" .. cmd .. "'")
        snd.commands.sendGameCommand(cmd, false)
    end

    tempTimer(5, function()
        if snd.nav.quickWhere and snd.nav.quickWhere.processed == false then
            snd.triggers.disableQuickWhereTriggers()
        end
    end)
end

function snd.commands.qw(args)
    runQuickWhere(args, false)
end

function snd.commands.qwx(args)
    runQuickWhere(args, true)
end

local function resolveQuickWhereAreaKey()
    local areaKey = snd.room and snd.room.current and snd.utils.trim(snd.room.current.arid or "") or ""
    if areaKey ~= "" then
        return areaKey
    end

    local roomId = snd.room and snd.room.current and tonumber(snd.room.current.rmid)
    if roomId and roomId > 0 and snd.mapper and snd.mapper.getRoomInfo then
        local info = snd.mapper.getRoomInfo(roomId)
        local mappedArea = info and snd.utils.trim(info.area or "") or ""
        if mappedArea ~= "" then
            return mappedArea
        end
    end

    return ""
end

function snd.commands.processQuickWhereResult()
    local quickWhere = snd.nav.quickWhere
    if not quickWhere then
        return
    end

    local matchesToProcess = {}
    if quickWhere.pendingMatches and #quickWhere.pendingMatches > 0 then
        matchesToProcess = quickWhere.pendingMatches
    elseif quickWhere.lastMatch and quickWhere.lastMatch.room then
        matchesToProcess = {quickWhere.lastMatch}
    end

    if #matchesToProcess == 0 then
        snd.utils.qwDebugNote("QW DEBUG: process result received no captured matches")
        quickWhere.processed = true
        quickWhere.completed = true
        quickWhere.awaitingCommandEcho = false
        quickWhere.probePending = false
        snd.triggers.disableQuickWhereTriggers()
        return
    end

    local lastMatch = matchesToProcess[#matchesToProcess]

    snd.targets = snd.targets or {}
    snd.targets.current = snd.targets.current or {}
    local preservedActivity = snd.targets.current.activity
    local quickWhereScope = quickWhere.scope
    local isAdhocQuickWhere = quickWhere.isAdhoc == true
    local preservesSelectedIdentity = snd.utils.trim(quickWhere.exactTargetName or "") ~= ""
    local originalName = snd.utils.trim(snd.targets.current.name or "")
    local matchedName = snd.utils.trim(lastMatch.mob or "")
    -- whole-word token match: "tree" finds "red tree" and "a large tree", but not "pirate" for "rat"
    local qwKeyword = snd.utils.trim(
        quickWhere.requestedKeyword or quickWhere.lookupKeyword or ""
    ):lower()
    local function keywordTokensInName(lcKeyword, lcName)
        local nameWords = {}
        for w in lcName:gmatch("%a+") do nameWords[w] = true end
        for token in lcKeyword:gmatch("%a+") do
            if not nameWords[token] then return false end
        end
        return lcKeyword:find("%a") ~= nil
    end
    local lcOriginal = originalName:lower()
    local lcMatched  = matchedName:lower()
    local hasStableIdentity = (originalName == "" or matchedName == "")
        or snd.utils.mobIdentityMatches(lcOriginal, lcMatched, 30)
        or (qwKeyword ~= ""
            and keywordTokensInName(qwKeyword, lcOriginal)
            and keywordTokensInName(qwKeyword, lcMatched))
    local nextActivity = "qw"
    if hasStableIdentity and (not isAdhocQuickWhere) and (quickWhereScope == "cp" or quickWhereScope == "gq" or quickWhereScope == "quest") then
        nextActivity = quickWhereScope
    elseif hasStableIdentity and (not isAdhocQuickWhere) and (preservedActivity == "cp" or preservedActivity == "gq" or preservedActivity == "quest") then
        nextActivity = preservedActivity
    end

    if preservesSelectedIdentity then
        snd.utils.qwDebugNote("QW DEBUG: preserving selected target name/keyword after exact live match")
    else
        snd.targets.current.name = lastMatch.mob or snd.targets.current.name
        snd.targets.current.keyword = snd.utils.findKeyword(lastMatch.mob or snd.targets.current.name or "")
    end
    snd.targets.current.matchedMobName = lastMatch.mob or snd.targets.current.matchedMobName
    snd.targets.current.activity = nextActivity
    snd.targets.current.roomName = lastMatch.room or snd.targets.current.roomName

    local areaKey = resolveQuickWhereAreaKey()
    snd.targets.current.area = areaKey
    if areaKey ~= "" then
        snd.utils.qwDebugNote("QW DEBUG: restricting room lookup to current area '" .. tostring(areaKey) .. "'")
    else
        snd.utils.qwDebugNote("QW DEBUG: current area unknown, using global room lookup")
    end

    local roomRows = {}
    for _, matchEntry in ipairs(matchesToProcess) do
        local roomResults = snd.mapper.searchRoomsExact(matchEntry.room, areaKey, nil, { silent = true })
        for _, roomEntry in ipairs(roomResults) do
            local roomArea = tostring(roomEntry.arid or "")
            if areaKey == "" or roomArea == areaKey then
                table.insert(roomRows, {
                    uid = roomEntry.rmid,
                    name = roomEntry.name,
                    area = roomEntry.arid,
                })
            end
        end
    end

    local results = snd.mapper.searchRoomsRows(roomRows, nil, { silent = true })

    local seenRoomIds = {}
    local dedupedResults = {}
    for _, entry in ipairs(results) do
        local roomId = tonumber(entry.rmid) or -1
        -- Only dedupe by concrete room id.
        -- Do not collapse unknown-id rows by name/area, because distinct rooms
        -- can legitimately share the same name.
        if roomId > 0 then
            if not seenRoomIds[roomId] then
                seenRoomIds[roomId] = true
                table.insert(dedupedResults, entry)
            end
        else
            table.insert(dedupedResults, entry)
        end
    end
    results = dedupedResults

    local chanceMob = snd.utils.trim(quickWhere.exactTargetName or "")
    if chanceMob == "" then
        chanceMob = (lastMatch and lastMatch.mob) or (snd.targets.current and snd.targets.current.name) or nil
    end
    local roomidList = {}
    for _, entry in ipairs(results) do
        local roomId = tonumber(entry.rmid)
        if roomId and roomId > 0 then
            table.insert(roomidList, tostring(roomId))
        end
    end

    local countByRoom = {}
    local killsByRoom = {}
    local priorityByRoom = {}
    local priorityRoomByRoom = {}
    local sum = 0
    local function loadRoomStats(mobName)
        if not mobName or mobName == "" or #roomidList == 0 then
            return {}
        end

        local sql = string.format(
            [[
                SELECT m.roomid,
                       m.seen_count,
                       m.kill_count,
                       mt.priority_room,
                       CASE WHEN mt.priority_room IS NOT NULL AND mt.priority_room = m.roomid THEN 1 ELSE 0 END AS priority_match
                FROM mobs m
                LEFT JOIN mob_tags mt
                  ON lower(mt.mob) = lower(m.mob)
                 AND lower(mt.zone) = lower(m.zone)
                WHERE lower(m.mob) = lower(%s) AND m.roomid in (%s);
            ]],
            snd.db.escape(mobName),
            table.concat(roomidList, ",")
        )
        return snd.db.query(sql) or {}
    end

    local seenRows = loadRoomStats(chanceMob)
    if #seenRows == 0 and chanceMob and chanceMob:find("%-") then
        seenRows = loadRoomStats(chanceMob:gsub("%-", " "))
    end

    for _, row in ipairs(seenRows) do
        local roomId = tonumber(row.roomid)
        local seen = tonumber(row.seen_count) or 0
        local kills = tonumber(row.kill_count) or 0
        if roomId then
            countByRoom[roomId] = seen
            killsByRoom[roomId] = kills
            priorityByRoom[roomId] = tonumber(row.priority_match) == 1
            priorityRoomByRoom[roomId] = tonumber(row.priority_room)
            sum = sum + seen
        end
    end

    for _, entry in ipairs(results) do
        local roomId = tonumber(entry.rmid) or -1
        entry.seen_count = countByRoom[roomId] or 0
        entry.kill_count = killsByRoom[roomId] or 0
        entry.priority_match = priorityByRoom[roomId] == true
        entry.priority_room = priorityRoomByRoom[roomId]
        if sum > 0 then
            entry.percentage = entry.seen_count / sum
        else
            entry.percentage = 0
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
        for i, entry in ipairs(results or {}) do
            if i > 8 then
                table.insert(parts, "...")
                break
            end
            table.insert(parts, string.format(
                "#%d rmid=%s area=%s seen=%s kills=%s priority_room=%s priority_match=%s",
                i,
                tostring(entry.rmid or ""),
                tostring(entry.arid or ""),
                tostring(entry.seen_count or ""),
                tostring(entry.kill_count or ""),
                tostring(entry.priority_room or ""),
                tostring(entry.priority_match == true)
            ))
        end
        snd.debug.mobTag(string.format(
            "quickWhereResult mob='%s' area='%s' roomName='%s' candidates=%d %s",
            tostring(chanceMob or ""),
            tostring(areaKey or ""),
            tostring(lastMatch and lastMatch.room or ""),
            #(results or {}),
            table.concat(parts, " | ")
        ))
    end

    local firstRoomId = nil
    local quickWhereRooms = {}
    if results and #results > 0 then
        snd.utils.qwDebugNote("QW DEBUG: mapped " .. tostring(#results) .. " room candidates from where result")
        local quickWhere = snd.nav and snd.nav.quickWhere or nil
        local reason = string.format(
            "quickWhereResult(keyword='%s', scope='%s', matches=%d)",
            tostring((quickWhere and (quickWhere.lookupKeyword or quickWhere.requestedKeyword)) or ""),
            tostring((quickWhere and quickWhere.scope) or ""),
            #results
        )
        snd.mapper.searchRoomsResults(results, { reason = reason })
        for _, entry in ipairs(results) do
            local roomId = tonumber(entry.rmid) or -1
            if roomId > 0 then
                if not firstRoomId then
                    firstRoomId = roomId
                end
                table.insert(quickWhereRooms, roomId)
            end
        end
    end

    if firstRoomId and snd.targets and snd.targets.current then
        snd.targets.current.roomId = firstRoomId
        snd.targets.current.roomName = lastMatch.room

        if not isAdhocQuickWhere then
            local scopeForSync = quickWhereScope
            if scopeForSync ~= "cp" and scopeForSync ~= "gq" and scopeForSync ~= "quest" then
                scopeForSync = preservedActivity
            end
            local scoped = (scopeForSync == "cp" or scopeForSync == "gq" or scopeForSync == "quest")
                and snd.targets.scoped and snd.targets.scoped[scopeForSync] or nil
            if scoped then
                local scopedName = snd.utils.trim(scoped.name or "")
                local nameMatchesScoped = scopedName ~= "" and matchedName ~= ""
                    and snd.utils.mobIdentityMatches(scopedName, matchedName, 30)
                if nameMatchesScoped then
                    scoped.roomId = firstRoomId
                    scoped.roomName = lastMatch.room
                end
            end
        end
    end

    if snd.nav.quickWhere then
        snd.nav.quickWhere.rooms = quickWhereRooms
        snd.nav.quickWhere.index = 1
        snd.nav.quickWhere.active = #quickWhereRooms > 0
        if snd.targets and snd.targets.current then
            snd.nav.quickWhere.targetKey = snd.commands.buildQuickWhereTargetKeyFromCurrent(snd.targets.current)
        else
            snd.nav.quickWhere.targetKey = nil
        end
        snd.nav.quickWhere.processed = true
        snd.nav.quickWhere.completed = true
        snd.nav.quickWhere.awaitingCommandEcho = false
        snd.nav.quickWhere.probePending = false
        snd.nav.quickWhere.pendingMatches = {}
        persistQuickWhereScope(snd.nav.quickWhere.scope)
    end

    if (not isAdhocQuickWhere) and snd.nav.nxState and snd.targets.current and #quickWhereRooms > 0 then
        local newKey = snd.commands.buildTargetKeyFromCurrent(snd.targets.current)
        if newKey ~= "" then
            snd.nav.nxState.targetKey = newKey
        end
    end

    snd.triggers.disableQuickWhereTriggers()

end

function snd.commands.processQuickWhereNoMatch()
    local quickWhere = snd.nav and snd.nav.quickWhere or nil
    local current = snd.targets and snd.targets.current or nil
    if not quickWhere or not current then
        return false
    end

    local activity = tostring(current.activity or quickWhere.scope or "")
    if activity ~= "cp" and activity ~= "gq" and activity ~= "quest" then
        return false
    end

    local mobName = snd.utils.trim(current.name or "")
    if mobName == "" then
        return false
    end

    if not (snd.db and snd.db.getMobLocations) then
        return false
    end

    local areaKey = resolveQuickWhereAreaKey()
    local rows = snd.db.getMobLocations(mobName, areaKey, { legacy = true }) or {}
    if #rows == 0 and areaKey ~= "" then
        rows = snd.db.getMobLocations(mobName, "", { legacy = true }) or {}
    end
    if #rows == 0 then
        return false
    end

    local results = {}
    local totalSeen = 0
    for _, row in ipairs(rows) do
        local roomId = tonumber(row.roomid) or -1
        local seen = tonumber(row.seen_count) or 0
        totalSeen = totalSeen + seen
        table.insert(results, {
            rmid = roomId,
            name = row.room or "",
            arid = row.zone or areaKey,
            seen_count = seen,
            kill_count = tonumber(row.kill_count) or 0,
            nowhere = tonumber(row.nowhere) == 1,
            nohunt = tonumber(row.nohunt) == 1,
            priority_room = tonumber(row.priority_room),
        })
    end

    for _, entry in ipairs(results) do
        if totalSeen > 0 then
            entry.percentage = (entry.seen_count or 0) / totalSeen
        else
            entry.percentage = 0
        end
    end

    snd.utils.infoNote("\nMob not found. It might be dead, use a different keyword, or be flagged nowhere.")
    snd.utils.infoNote("You have previously seen " .. mobName .. " in:")
    if snd.mapper and snd.mapper.searchRoomsResults then
        snd.mapper.searchRoomsResults(results, {
            reason = string.format(
                "quickWhereNoMatch(keyword='%s', scope='%s', dbRooms=%d)",
                tostring(quickWhere.lookupKeyword or quickWhere.requestedKeyword or ""),
                tostring(quickWhere.scope or ""),
                #results
            )
        })
    end

    local quickWhereRooms = {}
    for _, entry in ipairs(results) do
        local roomId = tonumber(entry.rmid) or -1
        if roomId > 0 then
            table.insert(quickWhereRooms, roomId)
        end
    end

    if #quickWhereRooms > 0 then
        current.roomId = quickWhereRooms[1]
        current.area = areaKey ~= "" and areaKey or (results[1] and results[1].arid) or current.area
        current.matchedMobName = mobName
    end

    quickWhere.rooms = quickWhereRooms
    quickWhere.index = 1
    quickWhere.active = #quickWhereRooms > 0
    quickWhere.processed = true
    quickWhere.completed = true
    quickWhere.awaitingCommandEcho = false
    quickWhere.probePending = false
    quickWhere.pendingMatches = {}
    if snd.commands.buildQuickWhereTargetKeyFromCurrent then
        quickWhere.targetKey = snd.commands.buildQuickWhereTargetKeyFromCurrent(current)
    end
    persistQuickWhereScope(quickWhere.scope or activity)

    return #quickWhereRooms > 0
end

-------------------------------------------------------------------------------
-- ht - Hunt Trick
-------------------------------------------------------------------------------

local function ensureHuntTrickStore()
    snd.nav = snd.nav or {}
    snd.nav.huntTrick = snd.nav.huntTrick or {}
    snd.nav.huntTrick.tempTriggers = snd.nav.huntTrick.tempTriggers or {}
end

local function clearHuntTrickTriggers()
    if not snd.nav or not snd.nav.huntTrick or not snd.nav.huntTrick.tempTriggers then
        return
    end

    for _, id in ipairs(snd.nav.huntTrick.tempTriggers) do
        pcall(function() killTrigger(id) end)
    end
    snd.nav.huntTrick.tempTriggers = {}
end

local function addHuntTrickTrigger(regex, fn)
    ensureHuntTrickStore()
    if type(tempRegexTrigger) ~= "function" then
        return false
    end

    local id = tempRegexTrigger(regex, fn)
    if id then
        table.insert(snd.nav.huntTrick.tempTriggers, id)
        return true
    end
    return false
end

local function registerHuntTrickTriggers()
    clearHuntTrickTriggers()

    local added = 0
    local function add(regex, fn)
        if addHuntTrickTrigger(regex, fn) then
            added = added + 1
        end
    end

    add("^\\s*You are (?:almost )?certain that .+ is (north|south|east|west|up|down) from here\\.$", function()
        if snd.commands and snd.commands.huntTrickContinue then
            snd.commands.huntTrickContinue()
        end
    end)
    add("^\\s*You are confident that .+ passed through here, heading (north|south|east|west|up|down)\\.$", function()
        if snd.commands and snd.commands.huntTrickContinue then
            snd.commands.huntTrickContinue()
        end
    end)
    add("^.+ is here!$", function()
        if snd.commands and snd.commands.huntTrickContinue then
            snd.commands.huntTrickContinue()
        end
    end)
    add("^You seem unable to hunt that target for some reason\\.$", function()
        if snd.commands and snd.commands.huntTrickComplete then
            snd.commands.huntTrickComplete()
        end
    end)
    add("^No one in this area by the name '.+'\\.$|^You couldn't find a path to .+ from here\\.$|^No one in this area by that name\\.$", function()
        if snd.commands and snd.commands.huntTrickFail then
            snd.commands.huntTrickFail()
        end
    end)
    add("^Not while you are fighting!$|^You can't hunt while (?:resting|sitting)\\.$|^You dream about going on a nice hunting trip, with pony rides, and campfires too\\.$", function()
        if snd.commands and snd.commands.stopHunt then
            snd.commands.stopHunt()
        end
    end)

    return added > 0
end

local function markHuntTrickLineHandled()
    if not snd.nav or not snd.nav.huntTrick then
        return true
    end

    local line = ""
    if type(getCurrentLine) == "function" then
        line = getCurrentLine() or ""
    end
    if line == "" then
        return true
    end

    if snd.nav.huntTrick.lastHandledLine == line then
        return false
    end

    snd.nav.huntTrick.lastHandledLine = line
    if type(tempTimer) == "function" then
        local handledLine = line
        tempTimer(0, function()
            if snd.nav and snd.nav.huntTrick and snd.nav.huntTrick.lastHandledLine == handledLine then
                snd.nav.huntTrick.lastHandledLine = nil
            end
        end)
    end

    return true
end

function snd.commands.ht(args)
    args = snd.utils.trim(args or "")

    local lowered = args:lower()
    if lowered == "stop" or lowered == "abort" or lowered == "a" or lowered == "0" then
        snd.commands.stopHunt()
        return
    end

    local startIndex = 1
    local keyword = args
    local exactMatchText = ""
    local prefixedIndex, prefixedKeyword = keyword:match("^(%d+)%.(.+)$")
    if prefixedIndex and prefixedKeyword then
        startIndex = tonumber(prefixedIndex) or 1
        keyword = snd.utils.trim(prefixedKeyword)
    end

    -- If no args, use current target
    if keyword == "" then
        if snd.targets.current and (snd.targets.current.name or snd.targets.current.keyword) then
            keyword, exactMatchText = resolveSelectedTargetKeyword("where")
        else
            snd.utils.infoNote("No target selected. Usage: ht <keyword>")
            return
        end
    end
    keyword = snd.utils.trim(keyword or "")
    if keyword == "" then
        snd.utils.infoNote("No target keyword available. Usage: ht <keyword>")
        return
    end

    -- Initialize hunt trick state
    clearHuntTrickTriggers()
    if snd.commands.stopAutoHunt then
        snd.commands.stopAutoHunt(true)
    end
    snd.nav.huntTrick = {
        keyword = keyword,
        index = startIndex,
        firstTarget = true,
        active = true,
        exactMatchText = exactMatchText,
        tempTriggers = {},
    }

    -- Use command-owned temp triggers so ht works even when the imported
    -- SND_Hunt folder is stale or disabled in the live profile.
    snd.triggers.disableGroup("Hunt")
    if not registerHuntTrickTriggers() then
        snd.triggers.enableGroup("Hunt")
    end

    if startIndex > 1 then
        snd.commands.sendGameCommand(string.format("hunt %d.%s", startIndex, keyword), false)
    else
        snd.commands.sendGameCommand("hunt " .. keyword, false)
    end
end

function snd.commands.huntTrickContinue()
    if not snd.nav or not snd.nav.huntTrick or not snd.nav.huntTrick.active then
        return
    end
    if not markHuntTrickLineHandled() then
        return
    end

    snd.nav.huntTrick.index = (tonumber(snd.nav.huntTrick.index) or 1) + 1
    snd.nav.huntTrick.firstTarget = false

    local ix = snd.nav.huntTrick.index
    local keyword = snd.nav.huntTrick.keyword
    if not keyword or keyword == "" then
        snd.utils.debugNote("You no longer have a target. Stopping hunt trick.")
        snd.commands.stopHunt()
        return
    end

    snd.commands.sendGameCommand(string.format("hunt %d.%s", ix, keyword), false)
end

function snd.commands.huntTrickComplete()
    if not snd.nav or not snd.nav.huntTrick or not snd.nav.huntTrick.active then
        return
    end
    if not markHuntTrickLineHandled() then
        return
    end

    local ht = snd.nav.huntTrick
    local ix = tonumber(ht.index) or 1
    local keyword = ht.keyword
    local exactMatchText = ht.exactMatchText

    snd.commands.stopHunt(true)

    if keyword and keyword ~= "" then
        if ix > 1 then
            snd.utils.infoNote(string.format("Hunt trick: %d.%s cannot be hunted; running quick where.", ix, keyword))
        else
            snd.utils.infoNote("Hunt trick: " .. keyword .. " cannot be hunted; running quick where.")
        end

        local qwOptions = {
            source = "ht",
        }
        if exactMatchText and exactMatchText ~= "" then
            qwOptions.forceTargetExact = true
            qwOptions.exactMatchText = exactMatchText
        end
        if ix > 1 then
            runQuickWhere(string.format("%d.%s", ix, keyword), false, qwOptions)
        else
            runQuickWhere(keyword, false, qwOptions)
        end
    else
        snd.utils.debugNote("You no longer have a target. Stopping hunt trick.")
    end
end

function snd.commands.huntTrickFail()
    if not snd.nav or not snd.nav.huntTrick or not snd.nav.huntTrick.active then
        return
    end
    if not markHuntTrickLineHandled() then
        return
    end

    local firstTarget = snd.nav and snd.nav.huntTrick and snd.nav.huntTrick.firstTarget
    snd.commands.stopHunt(true)

    if firstTarget then
        snd.utils.infoNote("Hunt trick: no matching hunt target found; no quick-where fallback needed.")
    else
        snd.utils.infoNote("Hunt trick: all matching targets are huntable; no quick-where fallback needed.")
    end
end

--- Stop hunt trick
function snd.commands.stopHunt(silent)
    clearHuntTrickTriggers()
    if snd.nav.huntTrick then
        snd.nav.huntTrick.active = false
        snd.nav.huntTrick.index = 1
        snd.nav.huntTrick.firstTarget = true
        snd.nav.huntTrick.exactMatchText = nil
        snd.nav.huntTrick.lastHandledLine = nil
    end
    snd.triggers.disableGroup("Hunt")
    if not silent then
        snd.utils.infoNote("Hunt stopped")
    end
end

-------------------------------------------------------------------------------
-- ah - Auto Hunt
-------------------------------------------------------------------------------

local function ensureAutoHuntStore()
    snd.nav = snd.nav or {}
    snd.nav.autoHunt = snd.nav.autoHunt or {}
    snd.nav.autoHunt.tempTriggers = snd.nav.autoHunt.tempTriggers or {}
end

local function clearAutoHuntTriggers()
    ensureAutoHuntStore()
    for _, id in ipairs(snd.nav.autoHunt.tempTriggers) do
        pcall(killTrigger, id)
    end
    snd.nav.autoHunt.tempTriggers = {}
end

local function addAutoHuntTrigger(regex, fn)
    ensureAutoHuntStore()
    local id = tempRegexTrigger(regex, fn)
    if id then
        table.insert(snd.nav.autoHunt.tempTriggers, id)
    end
end

function snd.commands.stopAutoHunt(silent)
    ensureAutoHuntStore()
    snd.nav.autoHunt.active = false
    snd.nav.autoHunt.keyword = ""
    snd.nav.autoHunt.direction = ""
    snd.nav.autoHunt.lastDirection = ""
    snd.nav.autoHunt.awaitingHuntResult = false
    snd.nav.autoHunt.transitioning = false
    clearAutoHuntTriggers()
    if not silent then
        snd.utils.infoNote("Search and Destroy:  Auto-hunt cancelled.")
    end
end

function snd.commands.autoHuntNext(direction)
    if not (snd.nav and snd.nav.autoHunt and snd.nav.autoHunt.active) then
        return
    end
    if not snd.nav.autoHunt.awaitingHuntResult then
        return
    end
    if snd.nav.autoHunt.transitioning then
        return
    end
    local dir = snd.utils.trim(direction or ""):lower()
    if dir == "" then return end
    snd.nav.autoHunt.awaitingHuntResult = false
    snd.nav.autoHunt.transitioning = true
    snd.nav.autoHunt.direction = dir
    snd.nav.autoHunt.lastDirection = dir
    snd.commands.sendGameCommand(dir, false)
    if snd.nav.autoHunt.keyword and snd.nav.autoHunt.keyword ~= "" then
        tempTimer(0.15, function()
            if not (snd.nav and snd.nav.autoHunt and snd.nav.autoHunt.active) then
                return
            end
            snd.nav.autoHunt.transitioning = false
            snd.nav.autoHunt.awaitingHuntResult = true
            snd.commands.sendGameCommand("hunt " .. snd.nav.autoHunt.keyword, false)
        end)
    else
        snd.nav.autoHunt.transitioning = false
    end
end

function snd.commands.autoHuntDoor()
    if not (snd.nav and snd.nav.autoHunt and snd.nav.autoHunt.active) then
        return
    end
    local dir = snd.nav.autoHunt.lastDirection or snd.nav.autoHunt.direction
    if dir and dir ~= "" then
        snd.commands.sendGameCommand("open " .. dir, false)
        tempTimer(0.2, function()
            snd.commands.autoHuntNext(dir)
        end)
    end
end

function snd.commands.autoHuntComplete()
    snd.commands.stopAutoHunt(true)
    snd.utils.infoNote("Search and Destroy: Auto-hunt complete.")
end

function snd.commands.autoHuntLowskill()
    snd.utils.infoNote("Search and Destroy:  Autohunt not available - hunt skill is too low.")
    snd.commands.stopAutoHunt(true)
end

function snd.commands.autoHuntPortal()
    snd.utils.infoNote("Search and Destroy: Auto-hunt through portals not supported yet. Enter portal manually and retry.")
    snd.commands.stopAutoHunt(true)
end

function snd.commands.enableAutoHunt()
    clearAutoHuntTriggers()
    addAutoHuntTrigger("^\\s*You are (?:almost )?certain that .+ is (north|south|east|west|up|down) from here\\.$", function()
        local dir = matches and matches[2] or ""
        snd.commands.autoHuntNext(dir)
    end)
    addAutoHuntTrigger("^\\s*You are confident that .+ passed through here, heading (north|south|east|west|up|down)\\.$", function()
        local dir = matches and matches[2] or ""
        snd.commands.autoHuntNext(dir)
    end)
    addAutoHuntTrigger("^.+ is here!$", function() snd.commands.autoHuntComplete() end)
    addAutoHuntTrigger("^The trail of .+ is confusing, but you're reasonably sure .+ headed (?:north|south|east|west|up|down)\\.$|^There are traces of .+ having been here\\. Perhaps they lead (?:north|south|east|west|up|down)\\?$|^You have no idea what you're doing, but maybe .+ is (?:north|south|east|west|up|down)\\?$", function() snd.commands.autoHuntLowskill() end)
    addAutoHuntTrigger("^You are (?:almost )?certain that .+ is through .+\\.$|^You are confident that .+ passed through here, heading through .+\\.$|^The trail of .+ is confusing, but you're reasonably sure .+ headed through .+\\.$|^There are traces of .+ having been here\\. Perhaps they lead through .+\\?$|^You have no idea what you're doing, but maybe .+ is through .+\\?$", function() snd.commands.autoHuntPortal() end)
    addAutoHuntTrigger("^Magical wards around .+ bounce you back\\.$|^The .+ is closed\\.$", function() snd.commands.autoHuntDoor() end)
    addAutoHuntTrigger("^No one in this area by the name '.+'\\.$|^You couldn't find a path to .+ from here\\.$|^No one in this area by that name\\.$|^Not while you are fighting!$|^You can't hunt while (?:resting|sitting)\\.$|^You dream about going on a nice hunting trip, with pony rides, and campfires too\\.$|^You do not have a key for .+\\.$", function() snd.commands.stopAutoHunt(true) end)
end

function snd.commands.ah(args)
    args = snd.utils.trim(args or "")
    local lowered = args:lower()
    if lowered == "a" or lowered == "abort" or lowered == "cancel" or lowered == "stop" or lowered == "0" then
        snd.commands.stopAutoHunt()
        return
    end
    local explicitKeywordProvided = args ~= ""

    local keyword = args
    if keyword == "" then
        keyword = snd.targets and snd.targets.current and snd.targets.current.keyword or ""
    end
    if keyword == "" then
        snd.utils.infoNote("No target selected. Usage: ah <keyword>")
        return
    end

    ensureAutoHuntStore()
    if snd.targets and snd.targets.current and snd.targets.current.activity and (snd.targets.current.activity == "cp" or snd.targets.current.activity == "gq") then
        local currentKeyword = snd.utils.trim(snd.targets.current.keyword or ""):lower()
        local currentNameKeyword = snd.utils.trim(snd.utils.findKeyword(snd.targets.current.name or "") or ""):lower()
        local requestedKeyword = snd.utils.trim(keyword or ""):lower()
        local guardApplies = not explicitKeywordProvided
            or (requestedKeyword ~= "" and (requestedKeyword == currentKeyword or requestedKeyword == currentNameKeyword))
        if guardApplies then
            local zone = snd.utils.trim(snd.targets.current.area or "")
            if zone == "" then
                zone = snd.utils.trim(snd.targets.current.arid or "")
            end
            if zone == "" then
                zone = snd.utils.trim((snd.room and snd.room.current and snd.room.current.arid) or "")
            end
            local mobName = snd.targets.current.name or ""
            local tags = (snd.db and snd.db.getMobTags and mobName ~= "" and zone ~= "") and snd.db.getMobTags(mobName, zone) or nil
            if tags and tags.nohunt then
                snd.utils.infoNote("Auto-hunt skipped: current target is tagged 'nohunt' for this zone.")
                return
            end
        end
    end
    snd.commands.stopHunt(true)
    snd.commands.enableAutoHunt()
    snd.nav.autoHunt.active = true
    snd.nav.autoHunt.keyword = keyword
    snd.nav.autoHunt.direction = ""
    snd.nav.autoHunt.lastDirection = ""
    snd.nav.autoHunt.awaitingHuntResult = true
    snd.nav.autoHunt.transitioning = false
    snd.commands.sendGameCommand("hunt " .. keyword, false)
end

-------------------------------------------------------------------------------
-- xkill - Kill Current Target
-------------------------------------------------------------------------------

--- Kill current target using configured kill command
function snd.commands.xkill()
    local scopedActivity = getScopedActivity()
    if scopedActivity and (not snd.targets.current or snd.targets.current.activity ~= scopedActivity) then
        activateTabTarget(scopedActivity)
    end

    local currentTarget = snd.targets.current
    local keyword = ""

    -- xkill should always prioritize the selected current target and only
    -- consider quest fallback when no current target exists.
    if currentTarget then
        keyword = snd.utils.trim(commandSelectorForTarget(currentTarget, "kill", {
            debugContext = "xkill",
        }) or "")
        if keyword == "" and currentTarget.matchedMobName then
            keyword = snd.utils.trim(tostring(currentTarget.matchedMobName or ""))
        end
        if keyword == "" and currentTarget.name then
            keyword = snd.utils.findKeyword(currentTarget.name)
        end
        if keyword == "" then
            snd.utils.infoNote("No keyword for current target")
            return
        end
    else
        keyword = select(1, resolveSelectedTargetKeyword("kill"))
        if not keyword or keyword == "" then
            snd.utils.infoNote("No target selected. Use xcp to select a target first.")
            return
        end
    end

    if not keyword or keyword == "" then
        return
    end

    -- Reuse the shared GMCP keyword guesser when a stored keyword contains
    -- punctuation (such as hyphenated forms) that may not be command-safe.
    local normalizedKeyword = keyword
    if currentTarget and currentTarget.name and normalizedKeyword:find("%-") and snd.gmcp and snd.gmcp.guessMobKeyword then
        local arid = snd.room and snd.room.current and snd.room.current.arid
        local guessed = snd.utils.trim(snd.gmcp.guessMobKeyword(currentTarget.name, arid) or "")
        if guessed ~= "" then
            normalizedKeyword = guessed
        end
    end
    normalizedKeyword = snd.utils.trim((normalizedKeyword:gsub("%s+", " ")))

    -- Get the kill command (default: "kill")
    local killCmd = snd.config.killCommand or "kill"
    
    -- Send the kill command
    local fullCmd = killCmd .. " " .. normalizedKeyword
    snd.utils.debugNote("xkill: " .. fullCmd)
    if snd.conwin and snd.conwin.noteAttackByKeyword then
        snd.conwin.noteAttackByKeyword(normalizedKeyword, 1)
    end
    send(fullCmd)
end

-------------------------------------------------------------------------------
-- xcmd - Set Kill Command
-------------------------------------------------------------------------------

--- Set the kill command used by xkill
-- @param args The command to use (e.g., "cast 'lightning bolt'")
function snd.commands.xcmd(args)
    args = snd.utils.trim(args or "")
    
    if args == "" then
        -- Show current command
        cecho("\n<cyan>Current xkill command:<reset> " .. (snd.config.killCommand or "kill") .. "\n")
        cecho("<dim_gray>Usage: xcmd <command><reset>\n")
        cecho("<dim_gray>Examples:<reset>\n")
        cecho("  <yellow>xcmd kill<reset>                 - Use 'kill <target>'\n")
        cecho("  <yellow>xcmd cast 'lightning bolt'<reset> - Use 'cast 'lightning bolt' <target>'\n")
        cecho("  <yellow>xcmd backstab<reset>             - Use 'backstab <target>'\n")
        return
    end
    
    -- Set the new kill command
    snd.config.killCommand = args
    snd.utils.infoNote("Kill command set to: " .. args)
    
    -- Save config
    if snd.saveState then
        snd.saveState()
    end
end

-------------------------------------------------------------------------------
-- qref - Quest Refresh/Status
-------------------------------------------------------------------------------

--- Show quest status and refresh target
function snd.commands.qref()
    -- Request fresh quest data from server
    sendGMCP("request quest")
    
    -- Show current quest info
    tempTimer(0.2, function()
        if snd.quest.active and snd.quest.target.mob ~= "" then
            cecho("\n<magenta>Quest Target:<reset> " .. snd.quest.target.mob .. "\n")
            if snd.quest.target.area ~= "" then
                cecho("<dim_gray>Area:<reset> " .. snd.quest.target.area .. "\n")
            end
            if snd.quest.target.room ~= "" then
                cecho("<dim_gray>Room:<reset> " .. snd.quest.target.room .. "\n")
            end
            if snd.quest.target.keyword ~= "" then
                cecho("<dim_gray>Keyword:<reset> " .. snd.quest.target.keyword .. "\n")
            end
            if snd.quest.timer and snd.quest.timer > 0 then
                cecho("<dim_gray>Time:<reset> " .. snd.quest.timer .. " minutes\n")
            end
            if snd.quest.target.status == "killed" then
                cecho("<green>Status: Target killed - return to questor!<reset>\n")
            end
            
            -- Make sure quest is in target list
            snd.gmcp.addQuestToTargetList()
        else
            cecho("\n<yellow>No active quest.<reset>\n")
            if snd.quest.nextQuestTime and snd.quest.nextQuestTime > 0 then
                local mins, cooldownText = snd.quest.getNextQuestStatus()
                if mins > 0 then
                    local waitText = cooldownText ~= "" and cooldownText
                        or string.format("Next quest in: %d minutes", mins)
                    cecho("<dim_gray>" .. waitText .. "<reset>\n")
                end
            end
        end
    end)
end

-- Backward-compatible callable function name (no alias registration).
function snd.commands.qr()
    snd.commands.qref()
end

-------------------------------------------------------------------------------
-- goto - Navigate to Target
-------------------------------------------------------------------------------

function snd.commands.gotoTarget()
    local scopedActivity = getScopedActivity()
    if scopedActivity and (not snd.targets.current or snd.targets.current.activity ~= scopedActivity) then
        activateTabTarget(scopedActivity)
    end

    if not snd.targets.current then
        snd.utils.infoNote("No target selected")
        return
    end
    
    local target = snd.targets.current
    if snd.debug and snd.debug.mobTag then
        snd.debug.mobTag(string.format(
            "gotoTarget current activity=%s name='%s' area='%s' areaName='%s' roomName='%s' roomId=%s",
            tostring(target.activity or ""),
            tostring(target.name or ""),
            tostring(target.area or target.arid or ""),
            tostring(target.areaName or ""),
            tostring(target.roomName or ""),
            tostring(target.roomId or "")
        ))
    end
    if target.roomId and target.roomId ~= "" then
        if snd.debug and snd.debug.mobTag then
            snd.debug.mobTag("gotoTarget using existing roomId=" .. tostring(target.roomId))
        end
        snd.utils.infoNote("Going to room " .. target.roomId)
        snd.commands.gotoRoomViaAlias(target.roomId)
        return
    end

    if target.roomName and target.roomName ~= "" then
        snd.utils.infoNote("Finding rooms for " .. target.roomName)
        local results = snd.mapper.searchRoomsExact(target.roomName, target.area or target.arid, target.name, {
            activity = target.activity,
            levelTaken = (target.activity == "cp" and snd.campaign.levelTaken)
                or (target.activity == "gq" and snd.gquest.effectiveLevel)
                or (snd.char and snd.char.level),
        })
        local firstMatch = results and results[1] and tonumber(results[1].rmid) or nil
        local priorityRoom = nil
        if snd.db and snd.db.getMobTags then
            local tags = snd.db.getMobTags(target.name or "", target.area or target.arid or "")
            priorityRoom = tags and tonumber(tags.priority_room) or nil
        end
        if priorityRoom and results then
            for _, entry in ipairs(results) do
                local roomId = tonumber(entry.rmid)
                if roomId and roomId == priorityRoom then
                    firstMatch = priorityRoom
                    break
                end
            end
        end
        if snd.debug and snd.debug.mobTag then
            local parts = {}
            for i, entry in ipairs(results or {}) do
                if i > 8 then
                    table.insert(parts, "...")
                    break
                end
                table.insert(parts, string.format(
                    "#%d rmid=%s area=%s name='%s'",
                    i,
                    tostring(entry.rmid or ""),
                    tostring(entry.arid or ""),
                    tostring(entry.name or "")
                ))
            end
            snd.debug.mobTag(string.format(
                "gotoTarget roomName search priority_room=%s selected=%s candidates=%d %s",
                tostring(priorityRoom or ""),
                tostring(firstMatch or ""),
                #(results or {}),
                table.concat(parts, " | ")
            ))
        end

        -- Prime nx quick-where cycling from direct room-name searches too.
        -- This keeps `nx` cycling functional even when a fresh `qw` parse was
        -- not captured (or when users immediately press nx from a shown XCP list).
        if snd.nav.quickWhere then
            local roomIds = {}
            if results then
                for _, entry in ipairs(results) do
                    local roomId = tonumber(entry.rmid) or -1
                    if roomId > 0 then
                        if priorityRoom and roomId == priorityRoom then
                            table.insert(roomIds, 1, roomId)
                        else
                            table.insert(roomIds, roomId)
                        end
                    end
                end
            end
            snd.nav.quickWhere.rooms = roomIds
            snd.nav.quickWhere.index = 1
            snd.nav.quickWhere.active = #roomIds > 0
            snd.nav.quickWhere.processed = true
            snd.nav.quickWhere.pendingMatches = {}
            snd.nav.quickWhere.scope = (snd.targets.current and snd.targets.current.activity) or "unknown"
            persistQuickWhereScope(snd.nav.quickWhere.scope)
            if snd.targets.current then
                snd.nav.quickWhere.targetKey = snd.commands.buildQuickWhereTargetKeyFromCurrent(snd.targets.current)
            else
                snd.nav.quickWhere.targetKey = nil
            end
        end

        if firstMatch and firstMatch > 0 then
            target.roomId = firstMatch
            snd.utils.infoNote("Going to room " .. firstMatch)
            snd.commands.gotoRoomViaAlias(firstMatch)
        else
            snd.utils.infoNote("No matching rooms found for " .. target.roomName)
        end
        return
    end

    local areaKey = target.area or ""
    local areaName = target.areaName or ""
    
    if areaKey == "" then
        snd.utils.infoNote("Target has no area information")
        return
    end
    
    -- Get area start room
    local startRoom = snd.db.getAreaStartRoom(areaKey)
    
    if startRoom and startRoom > 0 then
        local displayName = areaName ~= "" and areaName or areaKey
        snd.utils.infoNote("Going to " .. displayName .. " (room " .. startRoom .. ")")
        -- Dispatch through xrt alias for navigation
        snd.commands.gotoRoomViaAlias(startRoom)
    else
        snd.utils.infoNote("No start room known for " .. areaKey)
    end
end

-------------------------------------------------------------------------------
-- go - Navigate to a search result index
-------------------------------------------------------------------------------

function snd.commands.goToIndex(args)
    local index
    if type(args) == "number" then
        index = args
    else
        index = tonumber(snd.utils.trim(args or ""))
    end
    if not index then
        snd.utils.infoNote("Usage: go <index>")
        return
    end

    local entry = snd.nav.gotoList and snd.nav.gotoList[index] or nil
    if not entry then
        snd.utils.infoNote("No target at index " .. index)
        return
    end

    if entry.type == "area" then
        snd.commands.gotoArea(entry.id)
    elseif entry.type == "room" then
        snd.utils.infoNote("Going to room " .. entry.id)
        snd.commands.gotoRoomViaAlias(entry.id)
    else
        snd.utils.infoNote("Invalid target entry at index " .. index)
    end
end

-------------------------------------------------------------------------------
-- xset - Configuration
-------------------------------------------------------------------------------

function snd.commands.xset(args)
    args = snd.utils.trim(args or "")
    
    if args == "" then
        snd.commands.showConfig()
        return
    end
    
    local parts = {}
    for part in args:gmatch("%S+") do
        table.insert(parts, part)
    end
    
    local setting = parts[1]:lower()
    local value = parts[2]
    local normalized = value and value:lower() or nil
    
    if setting == "help" or setting == "h" or setting == "?" then
        snd.commands.showConfigHelp()
        return

    elseif setting == "debug" then
        if not normalized or normalized == "" then
            snd.utils.infoNote("Debug mode: " .. (snd.config.debugMode and "ON" or "OFF"))
        elseif normalized == "on" or normalized == "true" or normalized == "1" then
            if snd.debug and snd.debug.setEnabled then
                snd.debug.setEnabled(true)
            else
                snd.config.debugMode = true
            end
            snd.utils.infoNote("Debug mode: ON")
        elseif normalized == "off" or normalized == "false" or normalized == "0" then
            if snd.debug and snd.debug.setEnabled then
                snd.debug.setEnabled(false)
            else
                snd.config.debugMode = false
            end
            snd.utils.infoNote("Debug mode: OFF")
        else
            snd.utils.infoNote("Usage: xset debug <on|off>")
            return
        end
        
    elseif setting == "mobdebug" then
        if not normalized or normalized == "" then
            snd.utils.infoNote("Mob tag debug: " .. (snd.config.mobTagDebug and "ON" or "OFF"))
        elseif normalized == "on" or normalized == "true" or normalized == "1" then
            snd.config.mobTagDebug = true
            snd.utils.infoNote("Mob tag debug: ON")
        elseif normalized == "off" or normalized == "false" or normalized == "0" then
            snd.config.mobTagDebug = false
            snd.utils.infoNote("Mob tag debug: OFF")
        else
            snd.utils.infoNote("Usage: xset mobdebug <on|off>")
            return
        end

    elseif setting == "silent" then
        if not normalized or normalized == "" then
            snd.utils.infoNote("Silent mode: " .. (snd.config.silentMode and "ON" or "OFF"))
        elseif normalized == "on" or normalized == "true" or normalized == "1" then
            snd.config.silentMode = true
            cecho("\n<orange>[S&D]<reset> <cyan>Silent mode: ON<reset>\n")
        elseif normalized == "off" or normalized == "false" or normalized == "0" then
            snd.config.silentMode = false
            snd.utils.infoNote("Silent mode: OFF")
        else
            snd.utils.infoNote("Usage: xset silent <on|off>")
            return
        end
        
    elseif setting == "speed" then
        if not normalized or normalized == "" then
            snd.utils.infoNote("Speed: " .. snd.config.speed)
        elseif normalized == "run" or normalized == "walk" then
            snd.config.speed = normalized
            snd.utils.infoNote("Speed: " .. snd.config.speed)
        else
            snd.utils.infoNote("Usage: xset speed <run|walk>")
            return
        end

    elseif setting == "areaguard" then
        snd.config.areaGuard = snd.config.areaGuard or {enabled = false, allowance = 30}
        local allowance = tonumber(snd.config.areaGuard.allowance) or 30
        if not normalized or normalized == "" then
            snd.utils.infoNote(string.format(
                "Area guard: %s (allows areas up to %d levels above you; area locks remain absolute)",
                snd.config.areaGuard.enabled and "ON" or "OFF",
                allowance
            ))
        elseif normalized == "on" or normalized == "true" or normalized == "1" then
            snd.config.areaGuard.enabled = true
            snd.utils.infoNote(string.format("Area guard: ON (%d-level allowance)", allowance))
        elseif normalized == "off" or normalized == "false" or normalized == "0" then
            snd.config.areaGuard.enabled = false
            snd.utils.infoNote("Area guard: OFF")
        else
            snd.utils.infoNote("Usage: xset areaguard <on|off>")
            return
        end
        
    elseif setting == "nxaction" then
        local valid = {smartscan = true, qs = true, none = true}
        if not normalized or normalized == "" then
            snd.config.nxAction = snd.normalizeNxAction and snd.normalizeNxAction(snd.config.nxAction) or snd.config.nxAction
            snd.utils.infoNote("Next action: " .. snd.config.nxAction)
        elseif valid[normalized] then
            snd.config.nxAction = normalized
            snd.utils.infoNote("Next action: " .. snd.config.nxAction)
        else
            snd.utils.infoNote("Usage: xset nxaction <smartscan|qs|none>")
            return
        end
        
    elseif setting == "express" then
        if not normalized or normalized == "" then
            snd.utils.infoNote("Express mode: " .. (snd.config.express.enabled and "ON" or "OFF"))
        elseif normalized == "on" or normalized == "true" or normalized == "1" then
            snd.config.express.enabled = true
            snd.utils.infoNote("Express mode: ON")
        elseif normalized == "off" or normalized == "false" or normalized == "0" then
            snd.config.express.enabled = false
            snd.utils.infoNote("Express mode: OFF")
        else
            snd.utils.infoNote("Usage: xset express <on|off>")
            return
        end
        
    elseif setting == "expressmin" then
        local num = tonumber(value)
        if not value or value == "" then
            snd.utils.infoNote("Express min kills: " .. tostring(snd.config.express.minKillCount))
        elseif num and num >= 1 then
            snd.config.express.minKillCount = num
            snd.utils.infoNote("Express min kills: " .. snd.config.express.minKillCount)
        else
            snd.utils.infoNote("Usage: xset expressmin <number>")
            return
        end
    elseif setting == "autocheck" then
        local sub = normalized or ""
        local smartKills = tonumber(parts[3])
        if sub == "" then
            local mode = snd.getAutocheckMode and snd.getAutocheckMode() or "on"
            local n = snd.config.autocheck and snd.config.autocheck.smartKills or 3
            snd.utils.infoNote(string.format("AutoCheck mode: %s (smart kills: %d)", string.upper(mode), tonumber(n) or 3))
        elseif sub == "on" or sub == "off" or sub == "smart" then
            if sub == "smart" and parts[3] ~= nil then
                if not smartKills or smartKills < 1 then
                    snd.utils.infoNote("Usage: xset autocheck smart <n> (n >= 1)")
                    return
                end
            end
            snd.commands.setAutocheckMode(sub)
            if sub == "smart" and smartKills then
                snd.commands.setAutocheckSmartKills(smartKills)
            end
        elseif sub == "kills" then
            snd.commands.setAutocheckSmartKills(tonumber(parts[3]))
        else
            snd.utils.infoNote("Usage: xset autocheck <on|smart|off|kills <n>>")
            return
        end
        
    elseif setting == "window" then
        snd.config.window.enabled = (value == "on" or value == "true" or value == "1")
        snd.utils.infoNote("Window: " .. (snd.config.window.enabled and "ON" or "OFF"))
        if snd.commands.ensureGuiLoaded() then
            if snd.config.window.enabled then
                snd.gui.show()
            else
                snd.gui.hide()
            end
        end

    elseif setting == "sound" then
        if not value or value == "" then
            snd.config.soundEnabled = not snd.config.soundEnabled
        elseif value == "on" or value == "true" or value == "1" then
            snd.config.soundEnabled = true
        elseif value == "off" or value == "false" or value == "0" then
            snd.config.soundEnabled = false
        elseif value == "volume" then
            local raw = parts[3]
            if not raw or raw == "" then
                snd.utils.infoNote(string.format("Sound volume: %d%%", tonumber(snd.config.soundVolume) or 100))
                return
            end
            local n = tonumber((raw:gsub("%%", "")))
            if not n then
                snd.utils.infoNote("Usage: xset sound volume <n%>")
                return
            end
            n = math.max(0, math.min(100, math.floor(n + 0.5)))
            snd.config.soundVolume = n
            snd.utils.infoNote(string.format("Sound volume set to %d%%", n))
            return
        else
            snd.utils.infoNote("Usage: xset sound [on|off|volume <n%>]")
            return
        end
        snd.utils.infoNote("Sound alerts: " .. (snd.config.soundEnabled and "ON" or "OFF") .. string.format(" (volume %d%%)", tonumber(snd.config.soundVolume) or 100))

    elseif setting == "areacolors" then
        if not normalized or normalized == "" then
            snd.utils.infoNote("S&D area colors: " .. (snd.config.areaColors ~= false and "on" or "off"))
            return
        elseif normalized == "on" or normalized == "true" or normalized == "1" then
            snd.config.areaColors = true
        elseif normalized == "off" or normalized == "false" or normalized == "0" then
            snd.config.areaColors = false
        else
            snd.utils.infoNote("Usage: xset areacolors <on|off>")
            return
        end
        snd.utils.infoNote("S&D area colors: " .. (snd.config.areaColors ~= false and "on" or "off"))
        if snd.gui and snd.gui.refresh then snd.gui.refresh() end
        
    elseif setting == "keyword" then
        -- Set custom keyword for current target
        if not snd.targets.current then
            snd.utils.infoNote("No target selected")
            return
        end
        
        local keyword = table.concat(parts, " ", 2)
        if keyword and keyword ~= "" then
            snd.targets.current.keyword = keyword
            snd.db.setMobKeyword(
                snd.room.current.arid or snd.targets.current.area,
                snd.targets.current.name,
                keyword
            )
        else
            snd.utils.infoNote("Usage: xset keyword <keyword>")
        end
        
    elseif setting == "startroom" then
        -- Set start room for current area
        local roomId = tonumber(value) or tonumber(snd.room.current.rmid)
        local area = parts[3] or snd.room.current.arid
        
        if roomId and area and area ~= "" then
            snd.db.setAreaStartRoom(area, roomId)
            snd.utils.infoNote("Set start room for " .. area .. " to " .. roomId)
        else
            snd.utils.infoNote("Usage: xset startroom <roomid> [area]")
        end
        
    elseif setting == "mob" then
        local sub = parts[2] and parts[2]:lower() or ""
        local zone = snd.room and snd.room.current and snd.room.current.arid or ""
        local mob = table.concat(parts, " ", 3)
        local function needMob()
            if mob == "" then
                snd.utils.infoNote("Usage: xset mob " .. sub .. " <mob name>")
                return false
            end
            return true
        end

        if sub == "help" then
            snd.commands.showMobHelp()
        elseif sub == "nowhere" then
            if not needMob() then return end
            local on = snd.db.toggleMobTag(mob, zone, "nowhere")
            snd.utils.infoNote("Mob '" .. mob .. "' nowhere flag: " .. ((on and "ON") or "OFF"))
        elseif sub == "nohunt" then
            if not needMob() then return end
            local on = snd.db.toggleMobTag(mob, zone, "nohunt")
            snd.utils.infoNote("Mob '" .. mob .. "' nohunt flag: " .. ((on and "ON") or "OFF"))
        elseif sub == "priority" then
            if not needMob() then return end
            local roomId = tonumber(snd.room and snd.room.current and snd.room.current.rmid)
            if not roomId or roomId <= 0 then
                snd.utils.infoNote("Current room id is unknown; cannot set priority.")
                return
            end
            snd.db.setMobPriorityRoom(mob, zone, roomId)
            snd.utils.infoNote("Mob '" .. mob .. "' priority room set to " .. tostring(roomId))
        elseif sub == "unpriority" then
            if not needMob() then return end
            snd.db.setMobPriorityRoom(mob, zone, nil)
            snd.utils.infoNote("Mob '" .. mob .. "' priority room cleared.")
        elseif sub == "clearflags" then
            if not needMob() then return end
            snd.db.clearMobTags(mob, zone)
            snd.utils.infoNote("Cleared all tags for '" .. mob .. "' in zone " .. tostring(zone))
        elseif sub == "tags" or sub == "tag" then
            local query = table.concat(parts, " ", 3)
            local rows = snd.db.listMobTags(nil, query ~= "" and query or nil)
            snd.commands._lastMobTagRows = rows
            if #rows == 0 then
                snd.utils.infoNote("No mob tags found.")
                return
            end
            cecho("\n<white>#   Zone       Mob                               nowhere nohunt priority<reset>\n")
            cecho("<gray>-------------------------------------------------------------------------------<reset>\n")
            for i, row in ipairs(rows) do
                cecho(string.format("<cyan>%-3d<reset> %-10s %-32s %-7s %-6s %s\n",
                    i,
                    tostring(row.zone or ""):sub(1, 10),
                    tostring(row.mob or ""):sub(1, 32),
                    row.nowhere and "yes" or "-",
                    row.nohunt and "yes" or "-",
                    row.priority_room and tostring(row.priority_room) or "-"
                ))
            end
        elseif sub == "delete" or sub == "del" then
            local idx = tonumber(parts[3] or "")
            if not idx then
                snd.utils.infoNote("Usage: xset mob delete <index> (use xset mob tags first)")
                return
            end
            local row = snd.commands._lastMobTagRows and snd.commands._lastMobTagRows[idx] or nil
            if not row then
                snd.utils.infoNote("No tag row cached at that index.")
                return
            end
            if snd.db.deleteMobTagById(row.id) then
                snd.utils.infoNote("Deleted mob tag #" .. tostring(idx) .. " (" .. tostring(row.mob) .. ")")
            else
                snd.utils.infoNote("Failed deleting mob tag #" .. tostring(idx))
            end
        else
            snd.utils.infoNote("Usage: xset mob <help|nowhere|nohunt|priority|unpriority|tags|clearflags|delete>")
            return
        end
    else
        snd.utils.infoNote("Unknown setting: " .. setting)
        snd.commands.showConfig()
    end
    
    -- Save config after changes
    snd.saveState()
end

function snd.commands.setAutocheckMode(mode)
    local m = tostring(mode or ""):lower()
    if m ~= "on" and m ~= "smart" and m ~= "off" then
        snd.utils.infoNote("AutoCheck mode must be on, smart, or off.")
        return false
    end
    snd.config.autocheck = snd.config.autocheck or {}
    snd.config.autocheck.mode = m
    snd.config.autocheck.cpKillCounter = 0
    snd.config.autocheck.gqKillCounter = 0
    snd.utils.infoNote("AutoCheck mode: " .. string.upper(m))
    if m == "off" then
        snd.utils.infoNote("WARNING: AutoCheck OFF can desync CP/GQ targets until you manually refresh (ref / cp check / gq check).")
    end
    if snd.gui and snd.gui.updateAutocheck then snd.gui.updateAutocheck() end
    if snd.saveState then snd.saveState() end
    return true
end

function snd.commands.setAutocheckSmartKills(value)
    local n = tonumber(value)
    if not n or n < 1 then
        snd.utils.infoNote("Usage: xset autocheck kills <n> (n >= 1)")
        return false
    end
    snd.config.autocheck = snd.config.autocheck or {}
    snd.config.autocheck.smartKills = math.floor(n)
    snd.config.autocheck.cpKillCounter = 0
    snd.config.autocheck.gqKillCounter = 0
    snd.utils.infoNote("AutoCheck SMART kills: " .. tostring(snd.config.autocheck.smartKills))
    if snd.config.autocheck.smartKills == 1 then
        snd.utils.infoNote("AutoCheck SMART kills set to 1; switching mode to ON.")
        snd.commands.setAutocheckMode("on")
    end
    if snd.gui and snd.gui.updateAutocheck then snd.gui.updateAutocheck() end
    if snd.saveState then snd.saveState() end
    return true
end

-------------------------------------------------------------------------------
-- xhelp - Help
-------------------------------------------------------------------------------

function snd.commands.xhelp(args)
    args = snd.utils.trim(args or "")
    
    if args == "" then
        snd.commands.showHelp()
    elseif args == "commands" then
        snd.commands.showCommandHelp()
    elseif args == "config" then
        snd.commands.showConfigHelp()
    else
        snd.commands.showHelp()
    end
end

-------------------------------------------------------------------------------
-- Display Functions
-------------------------------------------------------------------------------

local function urlEncode(s)
    s = tostring(s or "")
    return (s:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function emitHelpCommandLink(commandText, commandToSend, hint)
    local cmd = tostring(commandToSend or commandText or "")
    local text = tostring(commandText or "")
    local tooltip = tostring(hint or cmd)
    local function linkAction()
        local trimmed = snd.utils.trim(cmd)
        if trimmed == "" then
            return
        end

        -- Keep S&D help links local when possible; don't send addon commands to
        -- the game when we can call the command API directly.
        if trimmed == "snd" and snd and snd.commands and snd.commands.snd then
            snd.commands.snd("")
            return
        end
        if trimmed:match("^snd%s+") and snd and snd.commands and snd.commands.snd then
            snd.commands.snd(trimmed:gsub("^snd%s+", "", 1))
            return
        end
        if trimmed == "xhelp" and snd and snd.commands and snd.commands.xhelp then
            snd.commands.xhelp("")
            return
        end
        local xhelpArgs = trimmed:match("^xhelp%s+(.+)$")
        if xhelpArgs and snd and snd.commands and snd.commands.xhelp then
            snd.commands.xhelp(xhelpArgs)
            return
        end

        if type(expandAlias) == "function" then
            local ok = pcall(expandAlias, trimmed, false)
            if ok then return end
            pcall(expandAlias, trimmed)
            return
        end

        if type(send) == "function" then
            send(trimmed, false)
        end
    end
    -- Use classic Mudlet links (stable rendering across consoles / logs).
    if type(cechoLink) == "function" then
        cechoLink("<cyan>" .. text .. "<reset>", linkAction, tooltip, true)
    else
        cecho(text)
    end
end

local SND_HELP_COMMAND_WIDTH = 38
local SND_HELP_DESC_WIDTH = 76

local function helpWrapText(text, width)
    local words, lines, line = {}, {}, ""
    for word in tostring(text or ""):gmatch("%S+") do
        table.insert(words, word)
    end
    if #words == 0 then
        return {""}
    end
    for _, word in ipairs(words) do
        if line == "" then
            line = word
        elseif #line + 1 + #word <= width then
            line = line .. " " .. word
        else
            table.insert(lines, line)
            line = word
        end
    end
    if line ~= "" then
        table.insert(lines, line)
    end
    return lines
end

local function emitHelpTitle(title)
    cecho("\n<white>" .. tostring(title or "") .. "<reset>\n")
    cecho("<gray>----------------------------------------<reset>\n")
end

local function emitHelpSection(title)
    cecho("\n<yellow>" .. tostring(title or "") .. "<reset>\n")
end

local function emitPlainHelpRow(commandText, description, commandWidth, descWidth)
    commandWidth = commandWidth or SND_HELP_COMMAND_WIDTH
    descWidth = descWidth or SND_HELP_DESC_WIDTH
    local cmdLines = helpWrapText(commandText, commandWidth)
    local descLines = helpWrapText(description, descWidth)
    local total = math.max(#cmdLines, #descLines)
    for i = 1, total do
        local cmd = cmdLines[i] or ""
        local desc = descLines[i] or ""
        cecho(string.format("  <cyan>%-" .. commandWidth .. "s<reset>  <light_grey>%s<reset>\n", cmd, desc))
    end
end

local function emitLinkedHelpRow(commandText, commandToSend, hint, description, commandWidth, descWidth)
    commandWidth = commandWidth or SND_HELP_COMMAND_WIDTH
    descWidth = descWidth or SND_HELP_DESC_WIDTH
    local text = tostring(commandText or "")
    local descLines = helpWrapText(description, descWidth)
    cecho("  ")
    emitHelpCommandLink(text, commandToSend or text, hint)
    cecho(string.rep(" ", math.max(1, commandWidth - #text)) .. "  <light_grey>" .. descLines[1] .. "<reset>\n")
    for i = 2, #descLines do
        cecho(string.format("  <cyan>%-" .. commandWidth .. "s<reset>  <light_grey>%s<reset>\n", "", descLines[i]))
    end
end

function snd.commands.showHelp()
    emitHelpTitle("Search and Destroy - Mudlet Port")
    emitHelpSection("Targeting & Combat")
    emitLinkedHelpRow("xcp <n>", "xcp 1", "Select target by number", "Select target by number")
    emitLinkedHelpRow("xcp", "xcp", "Show clickable target list", "Show clickable target list")
    emitLinkedHelpRow("xcp mode <db|qw|ht>", "xcp mode", "Set post-xcp action mode", "Set post-xcp action")
    emitLinkedHelpRow("nx", "nx", "Go to next/current target", "Go to next/current target")
    emitLinkedHelpRow("xkill", "xkill", "Kill current target", "Kill current target with precise temporary selector")

    emitHelpSection("Navigation & Search")
    emitLinkedHelpRow("qw [mob]", "qw", "Quick where", "Live where + mapper room list")
    emitLinkedHelpRow("qwx [mob]", "qwx", "Quick where exact", "Quick where exact match")
    emitLinkedHelpRow("ht [mob]", "ht", "Hunt trick", "Hunt trick (track mob)")
    emitLinkedHelpRow("ah [mob]", "ah", "Auto hunt", "Auto-hunt loop")
    emitLinkedHelpRow("xrt <area|roomid>", "xhelp commands", "See xrt help", "Navigate via mapper pathing")
    emitLinkedHelpRow("walkto <area|roomid>", "xhelp commands", "See walkto help", "Walk only (no portals/recalls)")

    emitHelpSection("Mob Tags")
    emitLinkedHelpRow("xset mob help", "xset mob help", "Show mob tag commands", "Show mob tag commands")
    emitLinkedHelpRow("xset mob priority <mob>", "xset mob help", "Prefer current room for this mob", "Prefer current room for this mob")
    emitLinkedHelpRow("xset mob nohunt <mob>", "xset mob help", "Keep listed, skip auto-hunt", "Keep listed, skip auto-hunt")
    emitLinkedHelpRow("xset mob nowhere <mob>", "xset mob help", "Use stored DB rooms when where fails", "Use stored DB rooms when where fails")
    emitLinkedHelpRow("xset mob tags [filter]", "xset mob tags", "List tagged mobs", "List tagged mobs")

    emitHelpSection("Windows & UI")
    emitLinkedHelpRow("snd conwin", "snd conwin help", "Open ConWin commands", "Open conwin commands")
    emitLinkedHelpRow("snd window font <n>", "snd window font 10", "Set S&D window font size", "Set window font size")

    emitHelpSection("Data & Reporting")
    emitLinkedHelpRow("snd status", "snd status", "Show status", "Show current status")
    emitLinkedHelpRow("snd db", "snd db", "Show database info/path", "Show database info/path")
    emitLinkedHelpRow("snd channel", "snd channel", "Show/set report channel", "Show/set report channel")
    emitLinkedHelpRow("snd history", "snd history", "Show history", "Show last 20 history rows")
    emitLinkedHelpRow("snd stats cp/gq/quest", "snd stats help", "Show stats commands", "Stats by type (campaign/gq/quest)")

    emitHelpSection("Debug")
    emitLinkedHelpRow("xset debug <on|off>", "xset debug", "Toggle S&D debug", "General S&D debug notes")
    emitLinkedHelpRow("xset mobdebug <on|off>", "xset mobdebug", "Toggle mob tag debug", "Mob tag, priority, and go-list routing diagnostics")

    emitHelpSection("Help")
    emitLinkedHelpRow("xhelp", "xhelp", "Show this help", "Show this help")
    emitLinkedHelpRow("xhelp commands", "xhelp commands", "Detailed commands help", "Detailed command usage and examples")
    emitLinkedHelpRow("xhelp config", "xhelp config", "Configuration help", "Configuration help")
    cecho("<gray>----------------------------------------<reset>\n")
end

function snd.commands.showConwinHelp()
    local mode = (snd.config and snd.config.conwin and snd.config.conwin.mode) or "consider"
    local enabled = (snd.config and snd.config.conwin and snd.config.conwin.enabled) and "on" or "off"
    local repopulate = (snd.config and snd.config.conwin and snd.config.conwin.repopulate) or 3
    local focusMode = ((snd.config and snd.config.conwin and snd.config.conwin.strictFocusIdOnly) and "strict" or "fallback")
    emitHelpTitle("Search and Destroy - ConWin Commands")
    cecho(string.format("  <dim_gray>Status:<reset> enabled=<cyan>%s<reset>, mode=<cyan>%s<reset>, repopulate=<cyan>%s<reset>, focusid=<cyan>%s<reset>\n", enabled, mode, tostring(repopulate), focusMode))
    emitLinkedHelpRow("snd conwin help", "snd conwin help", "Show conwin help", "Show this help")
    emitLinkedHelpRow("snd conwin on|off|toggle", "snd conwin toggle", "Toggle ConWin", "Enable/disable/toggle ConWin")
    emitLinkedHelpRow("snd conwin refresh", "snd conwin refresh", "Run consider all now", "Run consider all and refresh list")
    emitLinkedHelpRow("snd conwin clear", "snd conwin clear", "Clear current ConWin list", "Clear current ConWin mob list")
    emitLinkedHelpRow("snd conwin mode <consider|off>", "snd conwin mode off", "Set room-action mode", "Action on room change")
    emitLinkedHelpRow("snd conwin fontsize <n>", "snd conwin fontsize 10", "Set ConWin font size", "Set ConWin font size (6-24)")
    emitLinkedHelpRow("snd conwin killcommand <command>", "snd conwin killcommand", "Show current kill command", "Show current kill command; append <command> to set")
    emitLinkedHelpRow("snd conwin repopulate <n>", "snd conwin repopulate 3", "Refresh list after N kills", "Refresh list after N kills; 0 disables")
    emitLinkedHelpRow("snd conwin focusid <strict|fallback>", "snd conwin focusid", "Show current focus-id mode", "Show focus-id mode; strict requires explicit duplicate selection")
    emitLinkedHelpRow("snd conwin aligntags <on|off>", "snd conwin aligntags", "Show alignment tag display setting", "Show alignment tags setting ((G)/(E) prefixes)")
    cecho("\n<dim_gray>Clicking a mob line sends kill command.\n")
    cecho("<dim_gray>ConWin chooses distinctive kill selectors; duplicate exact names use numbered form (e.g. kill 2.name).<reset>\n")
    cecho("<gray>----------------------------------------<reset>\n")
end

function snd.commands.showCommandHelp()
    emitHelpTitle("Search and Destroy - Commands")
    emitHelpSection("Target Selection")
    emitPlainHelpRow("xcp", "Show all targets")
    emitPlainHelpRow("xcp <n>", "Select target #n")
    emitPlainHelpRow("xcp mode <db|qw|ht>", "Post-arrival target mode (db=stored list, qw=exact live where, ht=hunt then exact where)")

    emitHelpSection("Navigation")
    emitPlainHelpRow("nx", "Go to current target")
    emitPlainHelpRow("xrt <area|roomid>", "Go to area or room (portal-aware)")
    emitPlainHelpRow("xrtforce <area|roomid>", "Go to area/room (ignores area, portal, and exit-level guards)")
    emitPlainHelpRow("walkto <area|roomid>", "Walk to area or room (no portals)")
    emitPlainHelpRow("qw [keyword]", "Live where + mapper room list; selected target uses exact returned-name matching")
    emitPlainHelpRow("ht [keyword]", "Hunt trick to mob; selected target follows with exact live where")

    emitHelpSection("Configuration")
    emitPlainHelpRow("xset", "Show all settings")
    emitPlainHelpRow("xset areaguard <on|off>", "Toggle persisted navigation area guard")
    emitPlainHelpRow("xset sound [on|off|volume <n%>]", "Toggle/query sound alerts")
    emitPlainHelpRow("xset keyword <kw>", "Set mob keyword")
    emitPlainHelpRow("xset startroom", "Set area start room")

    emitHelpSection("History & Reporting")
    emitPlainHelpRow("snd channel", "Show current S&D report channel")
    emitPlainHelpRow("snd channel default", "Use default colored echo output")
    emitPlainHelpRow("snd channel <cmd>", "Send history row reports via channel command")
    cecho("  <dim_gray>Examples: snd channel gt | snd channel ct | snd channel say<reset>\n")
    emitPlainHelpRow("snd history", "Show last 20 history rows (echo only)")
    emitPlainHelpRow("snd history last <n>", "Show last n rows (echo only)")
    emitPlainHelpRow("snd history <q|quest|cp|campaign|gq|gquest>", "Filter by run type")
    emitPlainHelpRow("snd history <type> last <n>", "Filtered rows + count (e.g. q/cp/gq)")
    emitPlainHelpRow("snd history report <n> [channel]", "Report one shown row (optional channel override)")
    cecho("  <dim_gray>Tip: left-click row number in snd history for configured channel; right-click for menu.<reset>\n")

    emitHelpSection("ConWin")
    emitPlainHelpRow("snd conwin help", "ConWin command family")
    emitPlainHelpRow("snd conwin on|off|toggle", "Toggle consider window")
    emitPlainHelpRow("snd conwin fontsize <n>", "Set ConWin font size")
    cecho("<gray>----------------------------------------<reset>\n")
end

function snd.commands.showConfigHelp()
    emitHelpTitle("Search and Destroy - Configuration")
    emitHelpSection("Settings (xset <name> <value>)")
    emitPlainHelpRow("debug <on|off>", "Show internal debug notes. Examples: xset debug on | xset debug off")
    emitPlainHelpRow("mobdebug <on|off>", "Show focused mob tag/priority routing diagnostics")
    emitPlainHelpRow("silent <on|off>", "Hide regular [S&D] info notes. Error notes still show.")
    emitPlainHelpRow("speed <run|walk>", "Default travel mode for nx/go. run=xrt (portal-aware), walk=walkto (no portals)")
    emitPlainHelpRow("areaguard <on|off>", "Avoid areas more than 30 levels above you. Area entry locks remain absolute. Default: off.")
    emitPlainHelpRow("nxaction <smartscan|qs|none>", "default=qs; smartscan scans selected current-area target; none does nothing on arrival")
    emitPlainHelpRow("express <on|off>", "Prefer known fixed-room targets")
    emitPlainHelpRow("expressmin <number>", "Min kills before express applies")
    emitPlainHelpRow("autocheck <on|smart|off>", "Post-kill CP/GQ recheck mode")
    emitPlainHelpRow("autocheck kills <number>", "SMART mode: run check every N kills")
    emitPlainHelpRow("xcp mode <db|qw|ht>", "Post-arrival CP/GQ target mode; db=stored DB rooms, qw=exact live where, ht=hunt then exact where")
    emitPlainHelpRow("mob tags", "xset mob help|tags|delete|nowhere|nohunt|priority")
    emitPlainHelpRow("window <on|off>", "GUI window")
    emitPlainHelpRow("sound <on|off|volume>", "Sound alerts and volume")
    emitPlainHelpRow("areacolors <on|off>", "Color-band area labels in target list")
    cecho("<gray>----------------------------------------<reset>\n")
end

function snd.commands.showMobHelp()
    emitHelpTitle("Search and Destroy - xset mob help")
    emitHelpSection("Mob Tagging Commands")
    emitPlainHelpRow("xset mob nowhere <mob>", "Toggle the nowhere flag for a mob in the current zone. For mobs that where/qw cannot find, SnD keeps them visible and falls back to stored DB rooms. Example: xset mob nowhere city guard")
    emitPlainHelpRow("xset mob nohunt <mob>", "Toggle the nohunt flag in the current zone. Still shows in results, but auto-hunt skips it. Example: xset mob nohunt aggressive sentinel")
    emitPlainHelpRow("xset mob priority <mob>", "Set this room as the mob's priority room. If multiple rooms match, this room is preferred first.")
    emitPlainHelpRow("xset mob unpriority <mob>", "Clear the mob's priority room assignment")
    emitPlainHelpRow("xset mob tags [zone]", "List tagged mobs for current or named zone; caches row numbers for indexed deletion")
    emitPlainHelpRow("xset mob clearflags <mob>", "Remove all mob flags for this zone. Example: xset mob clearflags city guard")
    emitPlainHelpRow("xset mob delete <index>", "Delete a tag row by index from your last 'xset mob tags' output. Workflow: run tags, then delete by #.")
    cecho("<gray>----------------------------------------<reset>\n")
end

-------------------------------------------------------------------------------
-- Temp Alias Registration (for manual installs without XML)
-------------------------------------------------------------------------------

local function sndHasAlias(name)
    if type(getAlias) == "function" then
        local ok, alias = pcall(getAlias, name)
        if ok and alias ~= nil then
            return true
        end
    end

    if type(getAliasList) == "function" then
        local ok, aliases = pcall(getAliasList)
        if ok and type(aliases) == "table" then
            for _, alias in ipairs(aliases) do
                if alias.name == name then
                    return true
                end
            end
        end
    end

    return false
end

function snd.commands.registerTempAliases()
    if type(tempAlias) ~= "function" then
        return
    end

    snd.commands.tempAliases = snd.commands.tempAliases or {}
    local tempAliases = snd.commands.tempAliases

    local function register(name, pattern, handler)
        if sndHasAlias(name) then
            return
        end
        if tempAliases[name] then
            killAlias(tempAliases[name])
        end
        tempAliases[name] = tempAlias(pattern, handler)
    end

	register("qs", "^qs$", function() snd.gui.quickScan() end)
    register("snd", "^snd(.*)$", function() snd.commands.snd(matches[2]) end)
    register("xhelp", "^xhelp(.*)$", function() snd.commands.xhelp(matches[2]) end)
    register("xcp", "^xcp(.*)$", function() snd.commands.xcp(matches[2]) end)
    register("qwx", "^qwx(?:\\s+(.*))?$", function() snd.commands.qwx(matches[2] or "") end)
    register("qw", "^qw(?:\\s+(.*))?$", function() snd.commands.qw(matches[2] or "") end)
    register("nx", "^nx$", function() snd.commands.nx() end)
    register("ht", "^ht(.*)$", function() snd.commands.ht(matches[2]) end)
    register("ah", "^ah(.*)$", function() snd.commands.ah(matches[2]) end)
    register("aha", "^(?:aha|ah0)$", function() snd.commands.stopAutoHunt() end)
    register("xset", "^xset(.*)$", function() snd.commands.xset(matches[2]) end)
    register("go", "^go(\\s+.*)?$", function() snd.commands.goToIndex(matches[2]) end)
    register("qref", "^qref$", function() snd.commands.qref() end)
    register("xkill", "^xkill$", function() snd.commands.xkill() end)
    register("xcmd", "^xcmd(.*)$", function() snd.commands.xcmd(matches[2]) end)
    register("__snd_hist_report", "^__snd_hist_report%s+(%d+)%s+(%S+)$", function()
        snd.commands.reportHistoryRow(matches[2], matches[3])
    end)
end

function snd.commands.showConfig()
    cecho("\n<white>Search and Destroy - Current Settings<reset>\n")
    cecho("<gray>----------------------------------------<reset>\n")
    cecho(string.format("  <cyan>debug<reset>       %s\n", snd.config.debugMode and "ON" or "OFF"))
    cecho(string.format("  <cyan>mobdebug<reset>    %s\n", snd.config.mobTagDebug and "ON" or "OFF"))
    cecho(string.format("  <cyan>silent<reset>      %s\n", snd.config.silentMode and "ON" or "OFF"))
    cecho(string.format("  <cyan>speed<reset>       %s\n", snd.config.speed))
    cecho(string.format("  <cyan>areaguard<reset>   %s (allowance=%d)\n",
        snd.config.areaGuard and snd.config.areaGuard.enabled and "ON" or "OFF",
        tonumber(snd.config.areaGuard and snd.config.areaGuard.allowance) or 30))
    cecho(string.format("  <cyan>nxaction<reset>    %s\n", snd.config.nxAction))
    cecho(string.format("  <cyan>xcpmode<reset>     %s\n", normalizeXcpActionMode(snd.config.xcpActionMode or "qw")))
    cecho(string.format("  <cyan>express<reset>     %s\n", snd.config.express.enabled and "ON" or "OFF"))
    cecho(string.format("  <cyan>expressmin<reset>  %d\n", snd.config.express.minKillCount))
    cecho(string.format("  <cyan>autocheck<reset>   %s (kills=%d)\n",
        string.upper(snd.getAutocheckMode and snd.getAutocheckMode() or "on"),
        tonumber(snd.config.autocheck and snd.config.autocheck.smartKills) or 3))
    cecho(string.format("  <cyan>window<reset>      %s\n", snd.config.window.enabled and "ON" or "OFF"))
    cecho(string.format("  <cyan>sound<reset>       %s (volume=%d%%)\n", snd.config.soundEnabled and "ON" or "OFF", tonumber(snd.config.soundVolume) or 100))
    cecho(string.format("  <cyan>areacolors<reset>  %s\n", snd.config.areaColors ~= false and "ON" or "OFF"))
    cecho("<gray>----------------------------------------<reset>\n")
end

function snd.commands.showStatus()
    cecho("\n<white>Search and Destroy - Status<reset>\n")
    cecho("<gray>----------------------------------------<reset>\n")
    
    -- Character info
    cecho(string.format("  <yellow>Character:<reset> %s (Level %d)\n", 
        snd.char.name or "Unknown", snd.char.level or 0))
    cecho(string.format("  <yellow>Room:<reset> %s (%s)\n",
        snd.room.current.name or "Unknown", snd.room.current.arid or "Unknown"))
    
    -- Campaign status
    if snd.campaign.active then
        local remaining = snd.cp.getRemainingCount()
        cecho(string.format("  <yellow>Campaign:<reset> <green>Active<reset> (%d remaining)\n", remaining))
    else
        cecho("  <yellow>Campaign:<reset> <gray>None<reset>\n")
    end
    
    -- GQuest status
    if snd.gquest.active then
        local remaining = snd.gq.getRemainingCount()
        local kills = snd.gq.getTotalRemainingKills()
        cecho(string.format("  <yellow>GQuest:<reset> <green>#%s<reset> (%d targets, %d kills)\n",
            snd.gquest.joined, remaining, kills))
    else
        cecho("  <yellow>GQuest:<reset> <gray>None<reset>\n")
    end
    
    -- Quest status
    if snd.quest.active then
        cecho(string.format("  <yellow>Quest:<reset> <green>%s<reset> in %s\n",
            snd.quest.target.mob, snd.quest.target.area))
    else
        cecho("  <yellow>Quest:<reset> <gray>None<reset>\n")
    end
    
    -- Current target
    if snd.targets.current then
        cecho(string.format("  <yellow>Target:<reset> %s [%s]\n",
            snd.targets.current.name or snd.targets.current.keyword,
            snd.targets.current.activity or "none"))
    else
        cecho("  <yellow>Target:<reset> <gray>None selected<reset>\n")
    end
    
    cecho("<gray>----------------------------------------<reset>\n")
end

function snd.commands.showTargets()
    cecho("\n<white>Search and Destroy - Target List<reset>\n")
    cecho("<dim_gray>----------------------------------------<reset>\n")
    
    local activityConfig = {
        {key = "gq", label = "Global Quest", color = "dodger_blue"},
        {key = "quest", label = "Quest", color = "magenta"},
        {key = "cp", label = "Campaign", color = "green"},
    }

    local activityHasTargets = {}
    for _, target in ipairs(snd.targets.list) do
        activityHasTargets[target.activity] = true
    end

    local hasAnyTargets = activityHasTargets.gq or activityHasTargets.quest or activityHasTargets.cp
    if not hasAnyTargets then
        local now = os.clock()
        if now - (snd.targets.lastAutoRefresh or 0) > 10 then
            snd.targets.lastAutoRefresh = now
            send("quest check", false)
            send("cp check", false)
            send("gq info", false)
        end
        cecho("  <dim_gray>No targets - refreshing quest check, cp check, and gq info...<reset>\n")
        cecho("<dim_gray>----------------------------------------<reset>\n")
        return
    end

    for _, activity in ipairs(activityConfig) do
        if activityHasTargets[activity.key] then
            cecho(string.format("  <%s>%s<reset>\n", activity.color or "white", activity.label))
            cecho("<dim_gray>----------------------------------------<reset>\n")

            local index = 0
            local cpAliveIndex = 0
            local cpListIndex = 0
            local gqAliveIndex = 0
            for _, target in ipairs(snd.targets.list) do
                if target.activity == activity.key then
                    index = index + 1
                    local selectIndex = index

                    if target.activity == "cp" then
                        cpListIndex = cpListIndex + 1
                        if target.dead then
                            selectIndex = tonumber(target.cpListIndex) or cpListIndex
                        else
                            cpAliveIndex = cpAliveIndex + 1
                            selectIndex = tonumber(target.displayIndex) or cpAliveIndex
                        end
                    elseif target.activity == "gq" and not target.dead then
                        gqAliveIndex = gqAliveIndex + 1
                        selectIndex = gqAliveIndex
                    end

                    local prefix = ""
                    local prefixColor = "gray"

                    if target.activity == "cp" then
                        prefix = "CP"
                        prefixColor = "green"
                    elseif target.activity == "gq" then
                        prefix = "GQ"
                        prefixColor = "dodger_blue"
                    elseif target.activity == "quest" then
                        prefix = "QT"
                        prefixColor = "magenta"
                    end

                    local status = ""
                    if target.dead then
                        status = " [DEAD]"
                    elseif target.remaining and target.remaining > 1 then
                        status = string.format(" (x%d)", target.remaining)
                    end
                    local isCurrent = snd.targets.current and targetMatchesCurrent(target, snd.targets.current)
                    local rowLead = (target.activity == "cp" and isCurrent) and "<orange_red>▶<reset> " or "  "

                    -- Build the line
                    if not target.dead then
                        -- Clickable index number
                        cecho(rowLead)
                        cecho(string.format(" <%s>%2d.<reset>", (target.activity == "cp" and isCurrent) and "orange_red" or "yellow", selectIndex))
                        cecho(string.format("<%s>[%s]<reset> ", prefixColor, prefix))

                        -- Clickable mob name
                        local areaKey = target.arid or ""
                        if target.hasMobData == false then
                            cecho("<red>")
                            setUnderline(true)
                            echoLink(target.mob,
                                [[snd.commands.selectAndQuickWhere(]] .. selectIndex .. [[, "]] .. target.activity .. [[")]],
                                "Select and exact quick where: " .. target.mob, true)
                            setUnderline(false)
                            cecho("<reset>")
                        else
                            setUnderline(true)
                            echoLink(target.mob,
                                [[snd.commands.selectTarget(]] .. selectIndex .. [[, "]] .. target.activity .. [[")]],
                                "Click to select target", true)
                            setUnderline(false)
                        end

                        cecho(status)

                        -- Area on same line
                        if target.loc and target.loc ~= "" then
                            cecho(" <dim_gray>in<reset> ")
                            if areaKey ~= "" then
                                setUnderline(true)
                                echoLink(target.loc,
                                    [[snd.commands.gotoArea("]] .. areaKey .. [[")]],
                                    "Click to go to " .. areaKey, true)
                                setUnderline(false)
                            else
                                cecho("<cyan>" .. target.loc .. "<reset>")
                            end
                        end

                        echo("  ")
                        echoLink("[goto]",
                            [[snd.commands.selectAndGo(]] .. selectIndex .. [[, "]] .. target.activity .. [[")]],
                            "Select and go to target", true)
                        echo("\n")
                    else
                        if target.activity == "cp" then
                            cecho(string.format("%s<tomato>%2d.<reset><%s>[%s]<reset> ",
                                rowLead, selectIndex, prefixColor, prefix))
                            setUnderline(true)
                            echoLink(target.mob,
                                [[snd.commands.selectTarget(]] .. selectIndex .. [[, "cp")]],
                                "Dead CP target: click to run cp check", true)
                            setUnderline(false)
                            cecho("<tomato> [DEAD]<reset>\n")
                        else
                            cecho(string.format("%s<dim_gray>%2d. [%s] %s%s<reset>\n",
                                rowLead, index, prefix, target.mob, " [DEAD]"))
                        end
                    end
                end
            end

            cecho("<dim_gray>----------------------------------------<reset>\n")

            if activity.key == "gq" then
                local remain = snd.gq.getRemainingCount()
                local kills = snd.gq.getTotalRemainingKills()
                cecho(string.format("  <dodger_blue>%d mobs remaining (%d kills)<reset>", remain, kills))
                echo("  ")
                echoLink("[check]", [[send("gq check", false)]], "Check GQ progress", true)
                echo("\n")
            elseif activity.key == "quest" then
                if snd.quest.target.status == "killed" then
                    cecho("  <green>Target killed - return to questor!<reset>\n")
                else
                    cecho(string.format("  <magenta>Time: %d min<reset>", snd.quest.timer or 0))
                    echo("  ")
                    echoLink("[goto]", [[snd.commands.nx()]], "Go to target", true)
                    echo("  ")
                    echoLink("[where]", [[snd.commands.qw(\"\")]], "Quick where", true)
                    echo("\n")
                end
            elseif activity.key == "cp" then
                local remain = snd.cp.getRemainingCount()
                cecho(string.format("  <green>%d mobs remaining<reset>", remain))
                echo("  ")
                echoLink("[check]", [[send("cp check", false)]], "Check CP progress", true)
                echo("  ")
                echoLink("[info]", [[send("cp info", false)]], "Refresh CP info", true)
                echo("\n")
            end
        end
    end
    
    -- Show current target
    if snd.targets.current then
        cecho("  <yellow>Current:<reset> " .. (snd.targets.current.name or snd.targets.current.keyword))
        if snd.targets.current.area and snd.targets.current.area ~= "" then
            cecho(" <dim_gray>in<reset> " .. snd.targets.current.area)
        end
        echo("  ")
        echoLink("[goto]", [[snd.commands.nx()]], "Go to target", true)
        echo("  ")
        echoLink("[where]", [[snd.commands.qw("")]], "Quick where", true)
        echo("\n")
    end
end

--- Select a target by index and activity type (for clickable links)
function snd.commands.selectTarget(index, activity)
    clearNxOverride()
    local previousCurrent = snd.targets and snd.targets.current or nil
    local didSelect = false

    if activity == "cp" then
        didSelect = snd.cp.selectTarget(index) == true
    elseif activity == "gq" then
        didSelect = snd.gq.selectTarget(index) == true
    elseif activity == "quest" then
        didSelect = snd.commands.selectQuestTarget() == true
    end

    if snd.targets and snd.targets.current and snd.targets.current.activity then
        setScopedCurrent(snd.targets.current.activity, snd.targets.current)
        activateQuickWhereScope(snd.targets.current.activity)
        if snd.setActiveTab then
            snd.setActiveTab(snd.targets.current.activity, {save = true, refresh = false})
        end
        if didSelect and snd.targets.current ~= previousCurrent and type(raiseEvent) == "function" then
            -- Integration surface: external scripts can listen to "snd.target.selected"
            raiseEvent("snd.target.selected", snd.targets.current)
        end
    end
end

--- Select quest target as current target
function snd.commands.selectQuestTarget()
    if not snd.quest.active or not snd.quest.target.mob or snd.quest.target.mob == "" then
        snd.utils.infoNote("No active quest")
        return false
    end
    
    -- Find quest target in list
    for _, target in ipairs(snd.targets.list) do
        if target.activity == "quest" then
            local roomName = target.roomName
            if not roomName or roomName == "" then
                roomName = snd.utils.stripColors(snd.quest.target.room or "")
            end
            snd.targets.current = {
                name = target.mob,
                keyword = target.keyword or snd.utils.findKeyword(target.mob),
                area = target.arid or "",
                areaName = target.loc or "",
                roomName = roomName or "",
                roomId = target.roomId,
                activity = "quest",
            }
            clearNxOverride()
            if snd.db and snd.db.getMobLocations and snd.nav and snd.nav.quickWhere then
                local rooms = {}
                local questRoomName = snd.utils.stripColors(roomName or "")
                local questAreaKey = target.arid or snd.quest.target.arid or ""
                if questAreaKey == "" and snd.quest.target.area and snd.quest.target.area ~= "" and snd.db.getAreaKeyFromName then
                    questAreaKey = snd.db.getAreaKeyFromName(snd.quest.target.area) or ""
                end

                local locations = snd.db.getMobLocations(target.mob, questAreaKey, { legacy = true }) or {}
                local filteredLocations = {}

                -- Quest cache fallback: if area key is missing, prefer rows that also match
                -- the quest room name to avoid cross-zone mob-name collisions.
                if questAreaKey == "" and questRoomName ~= "" then
                    for _, row in ipairs(locations) do
                        local rowRoom = snd.utils.stripColors(row.room or row.name or "")
                        if rowRoom == questRoomName then
                            table.insert(filteredLocations, row)
                        end
                    end
                else
                    filteredLocations = locations
                end

                for _, row in ipairs(filteredLocations) do
                    local roomId = tonumber(row.roomid or row.rmid)
                    if roomId and roomId > 0 then
                        table.insert(rooms, roomId)
                    end
                end

                -- If cache is empty but quest gives a concrete room+area, fall back to
                -- room-name mapping scoped to the quest area.
                if #rooms == 0 and questRoomName ~= "" and snd.mapper and snd.mapper.searchRoomsExact then
                    local mapped = snd.mapper.searchRoomsExact(questRoomName, questAreaKey, target.mob, {
                        activity = "quest",
                        silent = true,
                    }) or {}
                    for _, entry in ipairs(mapped) do
                        local roomId = tonumber(entry.rmid)
                        if roomId and roomId > 0 then
                            table.insert(rooms, roomId)
                        end
                    end
                end

                snd.nav.quickWhere.rooms = rooms
                snd.nav.quickWhere.index = 1
                snd.nav.quickWhere.active = #rooms > 0
                snd.nav.quickWhere.processed = true
                snd.nav.quickWhere.pendingMatches = {}
                snd.nav.quickWhere.scope = "quest"
                snd.nav.quickWhere.targetKey = snd.commands.buildQuickWhereTargetKeyFromCurrent(snd.targets.current)
                persistQuickWhereScope("quest")
            end
            setScopedCurrent("quest", snd.targets.current)
            activateQuickWhereScope("quest")
            if snd.setActiveTab then
                snd.setActiveTab("quest", {save = true, refresh = false})
            end
            snd.utils.infoNote("Quest target selected: " .. target.mob)
            return true
        end
    end
    return false
end

--- Select quest target, navigate to it, and execute xkill
function snd.commands.selectQuestTargetAndKill()
    snd.commands.selectQuestTarget()
    tempTimer(0.1, function()
        snd.commands.gotoTarget()
    end)
    tempTimer(0.2, function()
        snd.commands.xkill()
    end)
end

--- Select and immediately go to target (for clickable links)
function snd.commands.selectAndGo(index, activity)
    snd.commands.selectTarget(index, activity)
    tempTimer(0.1, function()
        snd.commands.gotoTarget()
    end)
end

--- Select a target and run exact quick where if selection did not already do it
function snd.commands.selectAndQuickWhere(index, activity)
    snd.commands.selectTarget(index, activity)
    local quickWhere = snd.nav and snd.nav.quickWhere or nil
    if quickWhere and quickWhere.processed == false then
        return
    end
    snd.commands.qw("")
end

--- Go to an area by key (for clickable links)
function snd.commands.gotoArea(areaKey)
    if not areaKey or areaKey == "" then
        snd.utils.infoNote("No area key provided")
        return
    end
    
    local startRoom = snd.db.getAreaStartRoom(areaKey)
    if startRoom and startRoom > 0 then
        snd.utils.infoNote("Going to " .. areaKey .. " (room " .. startRoom .. ")")
        -- Dispatch through xrt alias for navigation
        snd.commands.gotoRoomViaAlias(startRoom)
    else
        snd.utils.infoNote("No start room for " .. areaKey)
    end
end

local function statsTypeFromArg(arg)
    local map = {
        q = snd.db.HISTORY_TYPE_QUEST,
        quest = snd.db.HISTORY_TYPE_QUEST,
        gq = snd.db.HISTORY_TYPE_GQUEST,
        gquest = snd.db.HISTORY_TYPE_GQUEST,
        cp = snd.db.HISTORY_TYPE_CAMPAIGN,
        campaign = snd.db.HISTORY_TYPE_CAMPAIGN,
    }
    return map[tostring(arg or ""):lower()]
end

local function statsTypeTitle(historyType)
    if tonumber(historyType) == snd.db.HISTORY_TYPE_QUEST then return "Quest" end
    if tonumber(historyType) == snd.db.HISTORY_TYPE_GQUEST then return "GQ" end
    if tonumber(historyType) == snd.db.HISTORY_TYPE_CAMPAIGN then return "Campaign" end
    return "Unknown"
end

local echoReportChannelPopup

local function statsEmitReportRow(label, lineText, reportText, typeLabel)
    cecho("  ")
    if type(cechoPopup) == "function" then
        echoReportChannelPopup(
            "<cyan>[>>]<reset>",
            snd.config and snd.config.reportChannel or "default",
            function(channel)
                snd.commands.reportStatsLine(reportText, typeLabel, channel)
            end
        )
    else
        cecho("[>>]")
    end
    cecho(string.format("  <yellow>%-12s<reset> %s\n", label, lineText))
end

local function statsShowType(historyType)
    local title = statsTypeTitle(historyType)
    local typeLabel = string.lower(title == "GQ" and "gquest" or title)
    local statusRows = snd.db.query(string.format(
        "SELECT status, COUNT(*) as cnt FROM history WHERE type = %d GROUP BY status",
        historyType
    )) or {}
    local counts = {total = 0, complete = 0, failed = 0, timeout = 0, skipped = 0}
    for _, row in ipairs(statusRows) do
        local status = tonumber(row.status) or 0
        local cnt = tonumber(row.cnt) or 0
        counts.total = counts.total + cnt
        if status == snd.db.HISTORY_STATUS_COMPLETE then counts.complete = cnt end
        if status == snd.db.HISTORY_STATUS_FAILED then counts.failed = cnt end
        if status == snd.db.HISTORY_STATUS_TIMEOUT then counts.timeout = cnt end
        if status == snd.db.HISTORY_STATUS_SKIPPED then counts.skipped = cnt end
    end

    local durationRows = snd.db.query(string.format([[
        SELECT AVG(end_time - start_time) as avg_dur, MIN(end_time - start_time) as best_dur, MAX(end_time - start_time) as worst_dur
        FROM history WHERE type = %d AND status = %d AND end_time > 0 AND start_time > 0
    ]], historyType, snd.db.HISTORY_STATUS_COMPLETE)) or {}
    local d = durationRows[1] or {}
    local bestDuration = tonumber(d.best_dur) or 0
    local worstDuration = tonumber(d.worst_dur) or 0
    local bestRows = snd.db.query(string.format([[
        SELECT * FROM history
        WHERE type = %d AND status = %d AND end_time > 0 AND start_time > 0 AND (end_time - start_time) = %d
        ORDER BY end_time DESC LIMIT 1
    ]], historyType, snd.db.HISTORY_STATUS_COMPLETE, bestDuration)) or {}
    local worstRows = snd.db.query(string.format([[
        SELECT * FROM history
        WHERE type = %d AND status = %d AND end_time > 0 AND start_time > 0 AND (end_time - start_time) = %d
        ORDER BY end_time DESC LIMIT 1
    ]], historyType, snd.db.HISTORY_STATUS_COMPLETE, worstDuration)) or {}
    local bestRow = bestRows[1]
    local worstRow = worstRows[1]

    local rewardRows = snd.db.query(string.format([[
        SELECT SUM(qp_rewards) as total_qp, AVG(qp_rewards) as avg_qp, SUM(tp_rewards) as total_tp, AVG(tp_rewards) as avg_tp,
               SUM(train_rewards) as total_tr, SUM(prac_rewards) as total_pr, SUM(gold_rewards) as total_gold, AVG(gold_rewards) as avg_gold
        FROM history WHERE type = %d AND status = %d
    ]], historyType, snd.db.HISTORY_STATUS_COMPLETE)) or {}
    local r = rewardRows[1] or {}

    local streakRows = snd.db.query(string.format(
        "SELECT status FROM history WHERE type = %d AND end_time > 0 ORDER BY start_time DESC LIMIT 200",
        historyType
    )) or {}
    local streak = 0
    for _, row in ipairs(streakRows) do
        if tonumber(row.status) == snd.db.HISTORY_STATUS_COMPLETE then streak = streak + 1 else break end
    end

    local avgDur = snd.utils.formatSeconds(tonumber(d.avg_dur) or 0)
    local bestDur = snd.utils.formatSeconds(tonumber(d.best_dur) or 0)
    local worstDur = snd.utils.formatSeconds(tonumber(d.worst_dur) or 0)
    local totalLine = string.format("%d total  |  %d complete  |  %d failed  |  %d timeout  |  %d skipped", counts.total, counts.complete, counts.failed, counts.timeout, counts.skipped)
    local timeLine = string.format("avg %s  |  best %s  |  worst %s", avgDur, bestDur, worstDur)
    local streakLine = string.format("%d consecutive completions", streak)
    local qpLine = string.format("%s total  |  %.1f avg", snd.utils.readableNumber(tonumber(r.total_qp) or 0), tonumber(r.avg_qp) or 0)
    local tpLine = string.format("%s total  |  %.2f avg", snd.utils.readableNumber(tonumber(r.total_tp) or 0), tonumber(r.avg_tp) or 0)
    local goldLine = string.format("%s total  |  %.0f avg", snd.utils.readableNumber(tonumber(r.total_gold) or 0), tonumber(r.avg_gold) or 0)
    local trprLine = string.format("%s total  |  Pracs: %s total", snd.utils.readableNumber(tonumber(r.total_tr) or 0), snd.utils.readableNumber(tonumber(r.total_pr) or 0))

    cecho(string.format("\n<white>──── %s Statistics ────<reset>\n", title))
    statsEmitReportRow("Total", totalLine, string.format("%s Stats - Total: %s", title, totalLine), typeLabel)
    cecho("  ")
    if type(cechoPopup) == "function" then
        echoReportChannelPopup("<cyan>[>>]<reset>", snd.config and snd.config.reportChannel or "default", function(channel)
            snd.commands.reportStatsLine(string.format("%s Stats - Time: %s", title, timeLine), typeLabel, channel)
        end)
    else
        cecho("[>>]")
    end
    cecho("  <yellow>Time        <reset> ")
    cecho(string.format("avg %s  |  ", avgDur))
    if type(cechoPopup) == "function" then
        echoReportChannelPopup("<green>best<reset>", snd.config and snd.config.reportChannel or "default", function(channel)
            if bestRow then
                snd.commands.reportHistoryLikeRow(bestRow, channel, "BEST")
            else
                snd.commands.reportStatsLine(string.format("%s Stats - Time: best %s", title, bestDur), typeLabel, channel)
            end
        end, "Left-click: report BEST run via ")
    else
        cecho("best")
    end
    cecho(string.format(" %s  |  ", bestDur))
    if type(cechoPopup) == "function" then
        echoReportChannelPopup("<red>worst<reset>", snd.config and snd.config.reportChannel or "default", function(channel)
            if worstRow then
                snd.commands.reportHistoryLikeRow(worstRow, channel, "WORST")
            else
                snd.commands.reportStatsLine(string.format("%s Stats - Time: worst %s", title, worstDur), typeLabel, channel)
            end
        end, "Left-click: report WORST run via ")
    else
        cecho("worst")
    end
    cecho(string.format(" %s\n", worstDur))
    statsEmitReportRow("Streak", streakLine, string.format("%s Stats - Streak: %s", title, streakLine), typeLabel)
    statsEmitReportRow("QP earned", qpLine, string.format("%s Stats - QP earned: %s", title, qpLine), typeLabel)
    statsEmitReportRow("TP earned", tpLine, string.format("%s Stats - TP earned: %s", title, tpLine), typeLabel)
    statsEmitReportRow("Gold", goldLine, string.format("%s Stats - Gold: %s", title, goldLine), typeLabel)
    statsEmitReportRow("Trains", trprLine, string.format("%s Stats - Trains: %s", title, trprLine), typeLabel)
    cecho(string.format("<gray>Click [>>] to report that line to your configured channel (%s).<reset>\n", tostring(snd.config.reportChannel or "gt")))
end

function snd.commands.reportStatsLine(reportText, typeLabel, channelOverride)
    local channel = channelOverride and snd.utils.trim(tostring(channelOverride)) or "default"
    if channel:lower() == "group" then
        channel = "gtell"
    end
    local style = snd.utils.getReportTypeStyle(typeLabel)
    local payload = string.format("%s[%s]@W %s", snd.utils.getReportAardColor(typeLabel), style.label, reportText)
    if snd.utils.isDefaultReportChannel(channel) then
        snd.utils.aardEchoLine(payload)
        return
    end
    if snd.utils and snd.utils.dispatchReportChannel then
        snd.utils.dispatchReportChannel(channel, payload)
    else
        snd.commands.sendGameCommand(channel .. " " .. payload, false)
    end
end

function snd.commands.showStats(args)
    args = snd.utils.trim(args or "")
    local sub = tostring(args):match("^(%S+)$")
    if sub == "help" then
        cecho("\n<white>snd stats usage:<reset>\n")
        cecho("  snd stats\n  snd stats cp\n  snd stats quest\n  snd stats gq\n")
        cecho("  aliases: campaign=cp, q=quest, gquest=gq\n")
        return
    end
    local historyType = statsTypeFromArg(sub)
    if historyType then
        statsShowType(historyType)
        return
    elseif sub ~= nil and sub ~= "" then
        cecho("<red>Unknown stats type. Try: snd stats help<reset>\n")
        return
    end
    cecho("\n<white>Search and Destroy - Statistics<reset>\n")
    cecho("<gray>----------------------------------------<reset>\n")
    
    -- Database stats
    local dbStats = snd.db.getStats()
    cecho(string.format("  <yellow>Database:<reset>\n"))
    cecho(string.format("    Mobs tracked: %d\n", dbStats.mobs))
    cecho(string.format("    Areas: %d\n", dbStats.areas))
    cecho(string.format("    Custom keywords: %d\n", dbStats.keywords))
    cecho(string.format("    History entries: %d\n", dbStats.history))
    
    -- History stats (last 14 days)
    local histStats = snd.db.getHistoryStats(nil, 14)
    cecho(string.format("\n  <yellow>Last 14 days:<reset>\n"))
    cecho(string.format("    Campaigns: %d\n", histStats.totalCampaigns))
    cecho(string.format("    GQuests: %d\n", histStats.totalGquests))
    cecho(string.format("    Quests: %d\n", histStats.totalQuests))
    cecho(string.format("    Total QP: %s\n", snd.utils.readableNumber(histStats.totalQP)))
    cecho(string.format("    Total Gold: %s\n", snd.utils.readableNumber(histStats.totalGold)))
    
    cecho("<gray>----------------------------------------<reset>\n")
end

function snd.commands.showDbInfo()
    cecho("\n<white>Search and Destroy - Database Info<reset>\n")
    cecho("<gray>----------------------------------------<reset>\n")

    local status = snd.db.getStatus and snd.db.getStatus() or {
        state = "STATUS UNAVAILABLE",
        path = snd.db.file,
        expectedSchema = snd.schemaVersion or 6,
    }
    cecho("  <yellow>Required default filename:<reset> SnDdb.db\n")
    cecho("  <yellow>Resolved database path:<reset>\n")
    cecho("    " .. tostring(status.path) .. "\n")
    local statusColor = status.state == "FOUND" and "<green>" or "<red>"
    cecho("  <yellow>Status:<reset> " .. statusColor .. tostring(status.state) .. "<reset>\n")
    if status.error then
        cecho("  <yellow>Problem:<reset> <red>" .. tostring(status.error) .. "<reset>\n")
    end
    if status.schemaVersion ~= nil then
        cecho(string.format("  <yellow>Schema:<reset> %d (expected %d)\n",
            tonumber(status.schemaVersion) or 0, tonumber(status.expectedSchema) or 0))
    end
    if status.integrity then
        cecho("  <yellow>Integrity:<reset> " .. tostring(status.integrity) .. "\n")
    end
    cecho("  <yellow>Connection:<reset> " .. (snd.db.isOpen and "<green>Open" or "<red>Closed") .. "<reset>\n")

    if status.state == "FOUND" and snd.db.isOpen then
        local stats = snd.db.getStats()
        cecho(string.format("  <yellow>Contents:<reset> %d mobs, %d areas, %d keywords\n",
            stats.mobs, stats.areas, stats.keywords))
        if stats.mobs == 0 and stats.areas == 0 then
            cecho("  <orange_red>Database classification: EMPTY.<reset> No preloaded mob or area data.\n")
        end

        -- Show tables
        local tables = snd.db.getTables()
        cecho("  <yellow>Tables:<reset> " .. table.concat(tables, ", ") .. "\n")
    end

    if status.createdEmpty then
        cecho("  <orange_red>Created during this session as a new empty database.<reset>\n")
        cecho("  Replace it manually with the supplied populated SnDdb.db if desired.\n")
    end

    cecho("\n  <yellow>Mudlet profile dir:<reset>\n")
    cecho("    " .. getMudletHomeDir() .. "\n")
    
    cecho("\n  <cyan>To set a different path:<reset>\n")
    cecho("    snd db /path/to/your/snd.db\n")
    
    cecho("<gray>----------------------------------------<reset>\n")
end

local function historyTypeFromArg(arg)
    local map = {
        q = snd.db.HISTORY_TYPE_QUEST,
        quest = snd.db.HISTORY_TYPE_QUEST,
        gq = snd.db.HISTORY_TYPE_GQUEST,
        gquest = snd.db.HISTORY_TYPE_GQUEST,
        cp = snd.db.HISTORY_TYPE_CAMPAIGN,
        campaign = snd.db.HISTORY_TYPE_CAMPAIGN,
    }
    return map[tostring(arg or ""):lower()]
end

local function historyTypeLabel(v)
    if tonumber(v) == snd.db.HISTORY_TYPE_QUEST then return "quest" end
    if tonumber(v) == snd.db.HISTORY_TYPE_GQUEST then return "gquest" end
    if tonumber(v) == snd.db.HISTORY_TYPE_CAMPAIGN then return "campaign" end
    return "unknown"
end

function snd.commands.reportHistoryLikeRow(row, channelOverride, statsLabel)
    if not row then
        snd.utils.infoNote("No history row available to report.")
        return
    end
    local channel = channelOverride and snd.utils.trim(tostring(channelOverride)) or "default"
    if channel == "default" and snd.config and snd.config.reportChannel then
        channel = snd.utils.trim(snd.config.reportChannel)
    end
    if channel:lower() == "group" then
        channel = "gtell"
    end
    if statsLabel then
        local payload = snd.commands.buildStatsHistoryRowChannelText(row, statsLabel)
        if snd.utils.isDefaultReportChannel(channel) then
            snd.utils.aardEchoLine(payload)
            return
        end
        if snd.utils and snd.utils.dispatchReportChannel then
            snd.utils.dispatchReportChannel(channel, payload)
        else
            snd.commands.sendGameCommand(channel .. " " .. payload, false)
        end
        return
    end

    local payload = snd.commands.buildHistoryRowChannelText(row)
    if snd.utils.isDefaultReportChannel(channel) then
        snd.utils.aardEchoLine(payload)
        return
    end

    if snd.utils and snd.utils.dispatchReportChannel then
        snd.utils.dispatchReportChannel(channel, payload)
    else
        snd.commands.sendGameCommand(channel .. " " .. payload, false)
    end
end

local function historyStatusLabel(v)
    v = tonumber(v) or 0
    local map = {
        [snd.db.HISTORY_STATUS_INPROGRESS] = "in progress",
        [snd.db.HISTORY_STATUS_COMPLETE] = "complete",
        [snd.db.HISTORY_STATUS_TIMEOUT] = "timeout",
        [snd.db.HISTORY_STATUS_FAILED] = "failed",
        [snd.db.HISTORY_STATUS_RESET] = "reset",
        [snd.db.HISTORY_STATUS_SKIPPED] = "skipped",
        [snd.db.HISTORY_STATUS_UNDOCUMENTED] = "undocumented",
        [0] = "in progress",
    }
    return map[v] or "unknown"
end

local function historyTypeColor(v)
    if tonumber(v) == snd.db.HISTORY_TYPE_QUEST then return "red" end
    if tonumber(v) == snd.db.HISTORY_TYPE_GQUEST then return "dodger_blue" end
    if tonumber(v) == snd.db.HISTORY_TYPE_CAMPAIGN then return "green" end
    return "white"
end

local function historyTypeAardColor(v)
    if tonumber(v) == snd.db.HISTORY_TYPE_QUEST then return "@R" end
    if tonumber(v) == snd.db.HISTORY_TYPE_GQUEST then return "@C" end
    if tonumber(v) == snd.db.HISTORY_TYPE_CAMPAIGN then return "@G" end
    return "@W"
end

local function formatLocalDateTime(ts)
    ts = tonumber(ts)
    if not ts or ts <= 0 then
        return "n/a"
    end
    return os.date("%Y-%m-%d %H:%M", ts)
end

local function formatHistoryDate(row)
    if not row then
        return "n/a"
    end
    local endTs = tonumber(row.end_time) or 0
    local startTs = tonumber(row.start_time) or 0
    local ts = endTs > 0 and endTs or startTs
    if ts <= 0 then
        return "n/a"
    end
    return os.date("%Y-%m-%d", ts)
end

local function formatDuration(startTs, endTs, status)
    startTs = tonumber(startTs) or 0
    endTs = tonumber(endTs) or 0
    local s = tonumber(status) or 0
    if s == snd.db.HISTORY_STATUS_RESET or s == snd.db.HISTORY_STATUS_SKIPPED then
        return "n/a"
    end
    if startTs <= 0 or endTs <= 0 or endTs < startTs then
        return "in progress"
    end
    local total = endTs - startTs
    local hh = math.floor(total / 3600)
    local mm = math.floor((total % 3600) / 60)
    local ss = total % 60
    if hh > 0 then
        return string.format("%dh %02dm %02ds", hh, mm, ss)
    end
    return string.format("%dm %02ds", mm, ss)
end

local function formatRewardSummary(row)
    local qp = tonumber(row.qp_rewards) or 0
    local tp = tonumber(row.tp_rewards) or 0
    local tr = tonumber(row.train_rewards) or 0
    local pr = tonumber(row.prac_rewards) or 0
    local gold = tonumber(row.gold_rewards) or 0
    local parts = {}
    if qp > 0 then table.insert(parts, qp .. "qp") end
    if tp > 0 then table.insert(parts, tp .. "tp") end
    if tr > 0 then table.insert(parts, tr .. "tr") end
    if pr > 0 then table.insert(parts, pr .. "pr") end
    if gold > 0 then table.insert(parts, gold .. "g") end
    if #parts == 0 then
        return "-"
    end
    return table.concat(parts, " ")
end

local function buildRewardCecho(row)
    local qp = tonumber(row.qp_rewards) or 0
    local tp = tonumber(row.tp_rewards) or 0
    local tr = tonumber(row.train_rewards) or 0
    local pr = tonumber(row.prac_rewards) or 0
    local gold = tonumber(row.gold_rewards) or 0
    local parts = {}
    if qp > 0 then table.insert(parts, string.format("<red>%dqp<reset>", qp)) end
    if tp > 0 then table.insert(parts, string.format("<dodger_blue>%dtp<reset>", tp)) end
    if tr > 0 then table.insert(parts, string.format("<green>%dtr<reset>", tr)) end
    if pr > 0 then table.insert(parts, string.format("<magenta>%dpr<reset>", pr)) end
    if gold > 0 then table.insert(parts, string.format("<yellow>%dg<reset>", gold)) end
    if #parts == 0 then
        return "<dim_gray>-<reset>"
    end
    return table.concat(parts, " ")
end

function snd.commands.buildHistoryRowText(row)
    if not row then
        return ""
    end
    return string.format(
        "%s | lvl %s | %s -> %s | %s | %s | rewards: %s",
        historyTypeLabel(row.type),
        tostring(row.level_taken or 0),
        formatLocalDateTime(row.start_time),
        formatLocalDateTime(row.end_time),
        formatDuration(row.start_time, row.end_time, row.status),
        historyStatusLabel(row.status),
        formatRewardSummary(row)
    )
end

function snd.commands.buildStatsHistoryRowText(row, statsLabel)
    if not row then
        return ""
    end
    return string.format(
        "[%s] %s | %s | lvl %s | %s | rewards: %s",
        string.upper(historyTypeLabel(row.type)),
        string.upper(tostring(statsLabel or "run")),
        formatDuration(row.start_time, row.end_time, row.status),
        tostring(row.level_taken or 0),
        formatHistoryDate(row),
        formatRewardSummary(row)
    )
end

function snd.commands.buildHistoryRowChannelText(row)
    if not row then
        return ""
    end

    local typeColor = historyTypeAardColor(row.type)
    local typeLabel = string.upper(historyTypeLabel(row.type))
    local level = tostring(row.level_taken or 0)
    local dateText = formatHistoryDate(row)
    local durationText = formatDuration(row.start_time, row.end_time, row.status)
    local statusText = historyStatusLabel(row.status)

    local qp = tonumber(row.qp_rewards) or 0
    local tp = tonumber(row.tp_rewards) or 0
    local tr = tonumber(row.train_rewards) or 0
    local pr = tonumber(row.prac_rewards) or 0
    local gold = tonumber(row.gold_rewards) or 0
    local rewardParts = {}
    if qp > 0 then table.insert(rewardParts, string.format("@R%dqp@W", qp)) end
    if tp > 0 then table.insert(rewardParts, string.format("@C%dtp@W", tp)) end
    if tr > 0 then table.insert(rewardParts, string.format("@G%dtr@W", tr)) end
    if pr > 0 then table.insert(rewardParts, string.format("@M%dpr@W", pr)) end
    if gold > 0 then table.insert(rewardParts, string.format("@Y%dg@W", gold)) end
    local rewardsText = #rewardParts > 0 and table.concat(rewardParts, " ") or "@D-@W"

    return string.format(
        "%s[%s]@W @M%s@W | @C%s@W | @Wlvl %s@W | @D%s@W | rewards: %s",
        typeColor,
        typeLabel,
        statusText,
        durationText,
        level,
        dateText,
        rewardsText
    )
end

function snd.commands.buildStatsHistoryRowChannelText(row, statsLabel)
    if not row then
        return ""
    end

    local typeColor = historyTypeAardColor(row.type)
    local typeLabel = string.upper(historyTypeLabel(row.type))
    local label = string.upper(tostring(statsLabel or "RUN"))
    local labelColor = label == "BEST" and "@G" or (label == "WORST" and "@R" or "@W")
    local durationText = formatDuration(row.start_time, row.end_time, row.status)
    local level = tostring(row.level_taken or 0)
    local dateText = formatHistoryDate(row)

    local qp = tonumber(row.qp_rewards) or 0
    local tp = tonumber(row.tp_rewards) or 0
    local tr = tonumber(row.train_rewards) or 0
    local pr = tonumber(row.prac_rewards) or 0
    local gold = tonumber(row.gold_rewards) or 0
    local rewardParts = {}
    if qp > 0 then table.insert(rewardParts, string.format("@R%dqp@W", qp)) end
    if tp > 0 then table.insert(rewardParts, string.format("@C%dtp@W", tp)) end
    if tr > 0 then table.insert(rewardParts, string.format("@G%dtr@W", tr)) end
    if pr > 0 then table.insert(rewardParts, string.format("@M%dpr@W", pr)) end
    if gold > 0 then table.insert(rewardParts, string.format("@Y%dg@W", gold)) end
    local rewardsText = #rewardParts > 0 and table.concat(rewardParts, " ") or "@D-@W"

    return string.format(
        "%s[%s]@W %s%s@W | @C%s@W | @Wlvl %s@W | @D%s@W | rewards: %s",
        typeColor,
        typeLabel,
        labelColor,
        label,
        durationText,
        level,
        dateText,
        rewardsText
    )
end

local function historyChannelLabel(channel)
    channel = snd.utils.trim(tostring(channel or "default"))
    if channel == "" or channel == "default" then
        return "Echo"
    end
    if channel == "gtell" or channel == "group" then
        return "Group"
    end
    return channel:gsub("^%l", string.upper)
end

echoReportChannelPopup = function(triggerText, configuredChannel, reporter, tooltipPrefix)
    local channel = snd.utils.trim(tostring(configuredChannel or "default"))
    if channel == "" then
        channel = "default"
    end
    local defaultLabel = historyChannelLabel(channel)
    local label = tostring(triggerText or "")
    local plainLabel = label:gsub("<%a[^>]*>", "")
    local tip = tostring(tooltipPrefix or "Left-click: report this via ")
    cechoPopup(
        label,
        {
            function() reporter(channel) end,
            "",
            function() reporter(channel) end,
            "",
            function() reporter("clan") end,
            "",
            function() reporter("say") end,
            "",
            function() reporter("gtell") end,
        },
        {
            tip .. defaultLabel .. "\nRight-click for other channels",
            plainLabel,
            "",
            defaultLabel,
            "",
            "Clan",
            "",
            "Say",
            "",
            "Group",
        },
        true
    )
end

local function echoHistoryRowLink(index, configuredChannel)
    local rowNumber = tonumber(index) or 0
    echoReportChannelPopup(
        string.format("[%2d]", rowNumber),
        configuredChannel,
        function(channel) snd.commands.reportHistoryRow(index, channel) end,
        "Left-click: report this row via "
    )
end


function snd.commands.reportHistoryRow(index, channelOverride)
    index = tonumber(index)
    if not index then
        snd.utils.infoNote("Usage: snd history report <row-number>")
        return
    end
    local row = snd.history and snd.history.lastRows and snd.history.lastRows[index] or nil
    if not row then
        snd.utils.infoNote("No cached history row #" .. tostring(index) .. ". Run 'snd history' first.")
        return
    end
    local channel = channelOverride and snd.utils.trim(tostring(channelOverride)) or "default"
    if channel == "default" and snd.config and snd.config.reportChannel then
        channel = snd.utils.trim(snd.config.reportChannel)
    end
    if channel:lower() == "group" then
        channel = "gtell"
    end

    local payload = snd.commands.buildHistoryRowChannelText(row)
    if snd.utils.isDefaultReportChannel(channel) then
        snd.utils.aardEchoLine(payload)
        return
    end

    if snd.utils and snd.utils.dispatchReportChannel then
        snd.utils.dispatchReportChannel(channel, payload)
    elseif snd.commands and snd.commands.sendGameCommand then
        snd.commands.sendGameCommand(channel .. " " .. payload, false)
    else
        send(channel .. " " .. payload, false)
    end
end

function snd.commands.reportHistoryRowVia(index, channelOverride)
    index = tonumber(index)
    if not index then
        snd.utils.infoNote("Usage: snd history report <row-number>")
        return
    end

    local normalized = channelOverride and snd.utils.trim(tostring(channelOverride)) or "default"
    if normalized == "" then
        normalized = "default"
    end
    snd.commands.reportHistoryRow(index, normalized)
end

function snd.commands.history(args)
    args = snd.utils.trim(args or "")
    local limit = 20
    local typeFilter = nil

    if args ~= "" then
        local reportNum, reportChannel = args:match("^report%s+(%d+)%s*(%S*)$")
        if reportNum then
            if reportChannel == "" then
                reportChannel = nil
            end
            snd.commands.reportHistoryRow(reportNum, reportChannel)
            return
        end

        local lastNum = args:match("^last%s+(%d+)$")
        if lastNum then
            limit = tonumber(lastNum) or 20
        else
            local typeArg, maybeLast = args:match("^(%S+)%s+last%s+(%d+)$")
            if typeArg and maybeLast then
                typeFilter = historyTypeFromArg(typeArg)
                limit = tonumber(maybeLast) or 20
            else
                typeFilter = historyTypeFromArg(args)
                if not typeFilter then
                    snd.utils.infoNote("Usage: snd history [q|quest|cp|campaign|gq|gquest] [last <n>] | snd history report <n> [channel]")
                    return
                end
            end
        end
    end

    local rows = snd.db.getHistoryEntries({limit = limit, type = typeFilter})
    snd.history.lastRows = rows
    snd.history.lastLimit = limit

    cecho("\n<white>Search and Destroy - History<reset>\n")
    cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
    cecho(string.format("<dim_gray>Showing last %d rows%s. Left-click row number to report over configured snd channel; right-click for channel menu.\n<reset>",
        limit, typeFilter and (" for " .. historyTypeLabel(typeFilter)) or ""))
    cecho("<dim_gray>Format: [#] type | lvl | start -> end | duration | status | rewards<reset>\n")

    if #rows == 0 then
        cecho("<yellow>No history rows found.<reset>\n")
        cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
        return
    end

    for i, row in ipairs(rows) do
        local tColor = historyTypeColor(row.type)
        local rewardText = buildRewardCecho(row)
        cecho("  ")
        cecho("<white>")
        local configuredChannel = "default"
        if snd.config and snd.config.reportChannel then
            configuredChannel = snd.utils.trim(snd.config.reportChannel)
            if configuredChannel == "" then
                configuredChannel = "default"
            end
        end

        echoHistoryRowLink(i, configuredChannel)

        cecho("<reset>")
        cecho(string.format(" <%s>%-8s<reset> | ", tColor, historyTypeLabel(row.type)))
        cecho(string.format("<white>lvl %s<reset> | ", tostring(row.level_taken or 0)))
        cecho(string.format("<dim_gray>%s<reset> -> <dim_gray>%s<reset> | ",
            formatLocalDateTime(row.start_time), formatLocalDateTime(row.end_time)))
        cecho(string.format("<cyan>%s<reset> | ", formatDuration(row.start_time, row.end_time, row.status)))
        cecho(string.format("<magenta>%s<reset> | ", historyStatusLabel(row.status)))
        cecho(rewardText)
        cecho("\n")
    end

    cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
    cecho("<dim_gray>Whole-history reporting is echo-only by design. Use row click/right-click menu or 'snd history report <n>' for channel output.<reset>\n")
end

function snd.commands.channel(args)
    args = snd.utils.trim(args or "")
    if args == "" then
        snd.utils.infoNote("S&D report channel: " .. tostring(snd.config.reportChannel or "default"))
        snd.utils.infoNote("Usage: snd channel default | snd channel <channel-command>")
        return
    end

    if args:lower() == "default" then
        snd.config.reportChannel = "default"
        snd.saveState()
        snd.utils.infoNote("S&D report channel set to default echo.")
        return
    end

    snd.config.reportChannel = args
    snd.saveState()
    snd.utils.infoNote("S&D report channel set to: " .. args)
end

-- Module loaded silently
