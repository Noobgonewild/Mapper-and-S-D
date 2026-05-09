--[[
    Search and Destroy - Global Quest Module
    Mudlet Port
    
    Original MUSHclient plugin by Crowley
    Ported to Mudlet
    
    This module handles global quest (gq) tracking:
    - Parsing gq info / gq check output
    - Target list management
    - GQ completion/failure
]]

snd = snd or {}
snd.gq = snd.gq or {}

-------------------------------------------------------------------------------
-- GQuest Parsing State
-------------------------------------------------------------------------------

snd.gq.parsing = {
    infoActive = false,
    checkActive = false,
    tempTargets = {},
    currentGqId = nil,
    extended = false,
    finished = false,
    effectiveLevel = 0,
    infoEndTimer = nil,
}

-------------------------------------------------------------------------------
-- GQuest Info Processing
-------------------------------------------------------------------------------

--- Start processing gq info output
-- @param gqId The global quest ID
function snd.gq.startGqInfo(gqId)
    snd.gq.parsing.infoActive = true
    snd.gq.parsing.tempTargets = {}
    snd.gq.parsing.currentGqId = gqId
    snd.gq.parsing.extended = false
    snd.gq.parsing.finished = false
    if snd.gq.parsing.infoEndTimer then
        pcall(function() killTimer(snd.gq.parsing.infoEndTimer) end)
        snd.gq.parsing.infoEndTimer = nil
    end
    snd.utils.debugNote("Started parsing gq info for GQ #" .. tostring(gqId))
end

--- Process gq info level range line
-- @param minLvl Minimum level
-- @param maxLvl Maximum level
function snd.gq.processLevelRange(minLvl, maxLvl)
    local min = tonumber(minLvl) or 0
    local max = tonumber(maxLvl) or 0
    snd.gq.parsing.effectiveLevel = math.floor((min + max) / 2)
end

--- Mark gq as extended
function snd.gq.markExtended()
    snd.gq.parsing.extended = true
end

--- Mark gq as finished
function snd.gq.markFinished()
    snd.gq.parsing.finished = true
end

--- Process a gq info target line
-- @param qty Number to kill
-- @param targetStr The target string
function snd.gq.processGqInfoLine(qty, targetStr)
    if not snd.gq.parsing.infoActive then return end
    
    local mob, loc = snd.cp.parseMobTarget(targetStr)
    if not mob then return end

    local areaKey = ""
    if loc and loc ~= "" and snd.db and snd.db.getAreaKeyFromName then
        areaKey = snd.db.getAreaKeyFromName(loc) or ""
    end
    
    local target = {
        mob = mob,
        loc = loc,
        arid = areaKey,
        qty = tonumber(qty) or 1,
        remaining = tonumber(qty) or 1,
        dead = false,
        index = #snd.gq.parsing.tempTargets + 1,
        keyword = snd.gmcp.guessMobKeyword(mob, ""),
    }
    
    table.insert(snd.gq.parsing.tempTargets, target)
    snd.utils.debugNote("GQ target: " .. mob .. " x" .. qty .. " in " .. loc)
end

--- End processing gq info output
function snd.gq.endGqInfo()
    if not snd.gq.parsing.infoActive then return end
    
    snd.gq.parsing.infoActive = false
    snd.gq.parsing.infoEndTimer = nil
    
    -- Check if this is a finished gquest we're just looking at
    if snd.gq.parsing.finished then
        snd.utils.debugNote("GQ info was for a finished quest, ignoring")
        return
    end
    
    -- Transfer targets to main list
    snd.gquest.targets = snd.gq.parsing.tempTargets
    snd.gquest.active = #snd.gquest.targets > 0
    snd.gquest.joined = snd.gq.parsing.currentGqId or "-1"
    snd.gquest.started = snd.gq.parsing.currentGqId or "-1"
    snd.gquest.effectiveLevel = snd.gq.parsing.effectiveLevel
    
    if snd.gq.parsing.extended then
        snd.gquest.extended = snd.gq.parsing.currentGqId
    end
    
    -- Determine target type and update main target list
    if #snd.gquest.targets > 0 then
        snd.gquest.targetType = snd.cp.determineTargetType(snd.gquest.targets)
        snd.targets.type = snd.gquest.targetType
        snd.targets.activity = "gq"
        
        -- Build main target list
        snd.gq.buildMainTargetList()
    end
    
    snd.utils.debugNote("GQ info complete. " .. #snd.gquest.targets .. " targets")
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
    if snd.gquest.active and snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "gq", {save = true, refresh = false})
    end
end

--- Capture one of the global quest reward fields from gq info output.
-- @param rewardType string one of: qp, tp, trains, pracs, gold
-- @param value string|number reward value from regex capture
-- @param bonusPerKill string|number|nil optional qp bonus awarded per target kill
function snd.gq.captureInfoReward(rewardType, value, bonusPerKill)
    if snd.gq.parsing and not snd.gq.parsing.infoActive and snd.gq.startGqInfo then
        snd.gq.startGqInfo(snd.gquest.joined or snd.gquest.started or "0")
    end

    local amount = tonumber((tostring(value or ""):gsub(",", ""))) or 0
    if rewardType == "qp" then
        snd.gquest.qpReward = amount
        snd.gquest.qpPerKillBonus = tonumber(bonusPerKill) or snd.gquest.qpPerKillBonus or 0
    elseif rewardType == "tp" then
        snd.gquest.tpReward = amount
    elseif rewardType == "trains" then
        snd.gquest.trainReward = amount
    elseif rewardType == "pracs" then
        snd.gquest.pracReward = amount
    elseif rewardType == "gold" then
        snd.gquest.goldReward = amount
    end

    snd.gq.syncHistoryRewards()
end

--- Apply per-target-kill global quest bonus rewards as they are announced.
-- @param qpBonus number
function snd.gq.applyKillBonus(qpBonus)
    local bonus = tonumber(qpBonus) or 0
    if bonus <= 0 then
        return
    end
    snd.gquest.qpKillBonusTotal = (tonumber(snd.gquest.qpKillBonusTotal) or 0) + bonus
    snd.gq.syncHistoryRewards()
end

--- Sync currently captured global quest rewards into the open history row.
function snd.gq.syncHistoryRewards()
    if not snd.db or not snd.db.historyUpdateRewardsById then
        return
    end
    local historyId = tonumber(snd.gquest.historyId)
    if not historyId or historyId <= 0 then
        return
    end
    snd.db.historyUpdateRewardsById(historyId, {
        qp = (tonumber(snd.gquest.qpReward) or 0) + (tonumber(snd.gquest.qpKillBonusTotal) or 0),
        tp = tonumber(snd.gquest.tpReward) or 0,
        trains = tonumber(snd.gquest.trainReward) or 0,
        pracs = tonumber(snd.gquest.pracReward) or 0,
        gold = tonumber(snd.gquest.goldReward) or 0,
    })
end

-------------------------------------------------------------------------------
-- GQuest Check Processing
-------------------------------------------------------------------------------

--- Start processing gq check output
function snd.gq.startGqCheck()
    snd.gq.parsing.checkActive = true
    snd.gquest.checkList = {}
end

--- Process a gq check target line
-- @param qty Remaining quantity
-- @param targetStr The target string
function snd.gq.processGqCheckLine(qty, targetStr)
    if not snd.gq.parsing.checkActive then return end
    
    local mob, loc, isDead = snd.cp.parseMobTarget(targetStr)
    if not mob then return end
    
    table.insert(snd.gquest.checkList, {
        mob = mob,
        loc = loc,
        remaining = tonumber(qty) or 1,
        dead = isDead,
    })
end

--- End processing gq check output
function snd.gq.endGqCheck()
    snd.gq.parsing.checkActive = false
    snd.gquest.lastCheck = os.clock()

    if (#snd.gquest.targets == 0) and (#snd.gquest.checkList > 0) then
        snd.gquest.targets = {}
        for i, check in ipairs(snd.gquest.checkList) do
            local areaKey = ""
            if check.loc and check.loc ~= "" and snd.db and snd.db.getAreaKeyFromName then
                areaKey = snd.db.getAreaKeyFromName(check.loc) or ""
            end
            table.insert(snd.gquest.targets, {
                mob = check.mob,
                loc = check.loc,
                arid = areaKey,
                qty = check.remaining or 1,
                remaining = check.remaining or 1,
                dead = check.dead or (check.remaining == 0),
                index = i,
                keyword = snd.gmcp.guessMobKeyword(check.mob, ""),
            })
        end

        snd.gquest.active = #snd.gquest.targets > 0
        snd.gquest.targetType = snd.cp.determineTargetType(snd.gquest.targets)
        snd.targets.type = snd.gquest.targetType
        snd.targets.activity = "gq"
        snd.gq.buildMainTargetList()
    end
    
    -- Update target status
    snd.gq.updateTargetStatus()
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
    if snd.gquest.active and snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "gq", {save = true, refresh = false})
    end
end

-------------------------------------------------------------------------------
-- Target List Management
-------------------------------------------------------------------------------

--- Build the main target list from gquest targets
function snd.gq.buildMainTargetList()
    -- Remove any existing GQ targets first
    local newList = {}
    for _, t in ipairs(snd.targets.list) do
        if t.activity ~= "gq" then
            table.insert(newList, t)
        end
    end
    snd.targets.list = newList
    
    local duplicateCounts = {}
    for _, t in ipairs(snd.gquest.targets) do
        local k = string.format("%s|%s|%s", tostring(t.mob or ""):lower(), tostring(t.arid or ""):lower(), tostring(t.loc or ""):lower())
        duplicateCounts[k] = (duplicateCounts[k] or 0) + 1
    end
    local gqEntries = {}

    -- Build entries in display order first, then prepend as a block.
    for i, target in ipairs(snd.gquest.targets) do
        local roomName = ""
        if snd.gquest.targetType == "room" and target.loc and target.loc ~= "" then
            roomName = target.loc
        end
        local hasMobData = true
        if snd.gquest.targetType ~= "room" and snd.db and snd.db.getMobLocations then
            local locations = snd.db.getMobLocations(target.mob, target.arid)
            hasMobData = #locations > 0
        end

        local entry = {
            mob = target.mob,
            loc = target.loc,
            arid = target.arid or "",
            roomName = roomName,
            qty = target.qty,
            remaining = target.remaining or target.qty,
            dead = target.remaining == 0,
            index = i,
            sourceIndex = i,
            activity = "gq",
            keyword = target.keyword or snd.gmcp.guessMobKeyword(target.mob, ""),
            hasMobData = hasMobData,
        }
        local tags = snd.db and snd.db.getMobTags and snd.db.getMobTags(target.mob, target.arid) or nil
        if tags then
            entry.nowhere = tags.nowhere
            entry.nohunt = tags.nohunt
            entry.priority_room = tags.priority_room
        end
        if not entry.nowhere then
            local dk = string.format("%s|%s|%s", tostring(target.mob or ""):lower(), tostring(target.arid or ""):lower(), tostring(target.loc or ""):lower())
            entry._dupkey = dk
            entry.duplicates = duplicateCounts[dk] or 1
            if entry.priority_room and tonumber(entry.priority_room) and tonumber(entry.priority_room) > 0 then
                entry.rmid = tonumber(entry.priority_room)
            end
            table.insert(gqEntries, entry)
        end
    end

    local duplicateIndexSeen = {}
    for _, entry in ipairs(gqEntries) do
        local dk = entry._dupkey or ""
        duplicateIndexSeen[dk] = (duplicateIndexSeen[dk] or 0) + 1
        entry.index = duplicateIndexSeen[dk]
        entry._dupkey = nil
    end

    local currentArid = (snd.room and snd.room.current and tostring(snd.room.current.arid or "")) or ""
    local currentAreaHasAlive = false
    if currentArid ~= "" then
        for _, entry in ipairs(gqEntries) do
            if tostring(entry.arid or "") == currentArid and not entry.dead then
                currentAreaHasAlive = true
                break
            end
        end
    end

    local areaGroupSeen = {}
    local areaGroupCount = 0
    if currentAreaHasAlive then
        areaGroupSeen[currentArid] = 0
    end
    for _, entry in ipairs(gqEntries) do
        local arid = tostring(entry.arid or "")
        if not areaGroupSeen[arid] then
            areaGroupCount = areaGroupCount + 1
            areaGroupSeen[arid] = areaGroupCount
        end
        entry._areaGroup = areaGroupSeen[arid]
    end

    table.sort(gqEntries, function(a, b)
        if a.dead ~= b.dead then
            return not a.dead
        end
        if (a._areaGroup or 0) ~= (b._areaGroup or 0) then
            return (a._areaGroup or 0) < (b._areaGroup or 0)
        end
        if (a.sourceIndex or 0) ~= (b.sourceIndex or 0) then
            return (a.sourceIndex or 0) < (b.sourceIndex or 0)
        end
        return (a.index or 0) < (b.index or 0)
    end)

    for _, entry in ipairs(gqEntries) do
        entry._areaGroup = nil
    end

    -- Insert GQ targets at the BEGINNING (highest priority) preserving gqEntries order.
    for i = #gqEntries, 1, -1 do
        table.insert(snd.targets.list, 1, gqEntries[i])
    end
    
    snd.utils.debugNote("Built GQ target list: " .. #snd.gquest.targets .. " targets (priority)")
end

--- Update target status from gq check results
function snd.gq.updateTargetStatus()
    local consumedChecks = {}
    for _, target in ipairs(snd.targets.list) do
        if target.activity == "gq" then
            -- Check if this target is in the check list
            local found = false
            for idx, check in ipairs(snd.gquest.checkList) do
                if not consumedChecks[idx]
                    and target.mob == check.mob
                    and ((target.loc or "") == (check.loc or "") or (check.loc or "") == "" or (target.loc or "") == "") then
                    found = true
                    consumedChecks[idx] = true
                    target.remaining = check.remaining
                    target.dead = check.remaining == 0 or check.dead
                    break
                end
            end
            
            -- If not in check list, it's been completed
            if not found then
                target.remaining = 0
                target.dead = true
            end
        end
    end
end

-------------------------------------------------------------------------------
-- GQuest Events
-------------------------------------------------------------------------------

--- Handle joining a gquest
-- @param gqId The global quest ID
function snd.gq.onJoined(gqId)
    snd.utils.reportLine("Joined Global Quest #" .. gqId, "gquest")
    snd.gquest.joined = gqId

    if snd.config.autocheck then
        snd.config.autocheck.gqKillCounter = 0
    end

    if snd.char and not snd.char.noexp then
        sendGMCP("config noexp on")
        snd.utils.infoNote("Search and Destroy: Turning noexp ON (joined global quest)")
    end

    if snd.db then
        snd.gquest.historyId = snd.db.historyStart(snd.db.HISTORY_TYPE_GQUEST, snd.char.level or 0) or 0
    end
    
    -- Clear existing targets and request new info
    snd.gquest.targets = {}
    snd.gquest.active = true
    snd.gquest.qpReward = 0
    snd.gquest.tpReward = 0
    snd.gquest.trainReward = 0
    snd.gquest.pracReward = 0
    snd.gquest.goldReward = 0
    snd.gquest.qpPerKillBonus = 0
    snd.gquest.qpKillBonusTotal = 0
    
    -- Request gq info after joining
    tempTimer(0.5, function()
        send("gq info", false)
    end)
end

--- Handle gquest started
-- @param gqId The global quest ID
-- @param minLvl Minimum level
-- @param maxLvl Maximum level
function snd.gq.onStarted(gqId, minLvl, maxLvl)
    snd.utils.debugNote("GQ #" .. gqId .. " started (levels " .. minLvl .. "-" .. maxLvl .. ")")
    snd.gquest.started = gqId
    
    -- If we joined this GQ, request info
    if snd.gquest.joined == gqId then
        tempTimer(0.5, function()
            send("gq info", false)
        end)
    end
end

--- Handle gquest mob killed
function snd.gq.onMobKilled()
    snd.utils.debugNote("Global quest mob killed!")
    local confirmedKilledMob = ""
    if snd.conwin and snd.conwin.getRecentKilledMobName then
        confirmedKilledMob = snd.conwin.getRecentKilledMobName(3) or ""
        if confirmedKilledMob ~= "" and snd.conwin.clearRecentKilledMobName then
            snd.conwin.clearRecentKilledMobName()
        end
    end

    -- Fallback: when text trigger fires before GMCP clears, ConWin still sees the live enemy
    local activeCombatMob = ""
    if confirmedKilledMob == "" and snd.conwin and snd.conwin.getCurrentCombatMobName then
        activeCombatMob = snd.conwin.getCurrentCombatMobName() or ""
    end

    -- Update remaining count for current target
    if snd.targets.current and snd.targets.current.activity == "gq" then
        local roomId = snd.room and snd.room.current and snd.room.current.id or nil
        local killedMobName = confirmedKilledMob ~= "" and confirmedKilledMob or snd.targets.current.name or ""
        if type(raiseEvent) == "function" then
            -- Integration surface: external scripts can listen to "snd.kill.confirmed"
            raiseEvent("snd.kill.confirmed", killedMobName, roomId)
        end
        local bestIndex, bestScore = nil, -1
        local currentArea = snd.room and snd.room.current and tostring(snd.room.current.arid or "") or ""
        local currentRoom = snd.room and snd.room.current and tostring(snd.room.current.name or "") or ""
        for i, t in ipairs(snd.targets.list) do
            if t.activity == "gq" and not t.dead then
                local nameMatchesCurrent = (t.mob == snd.targets.current.name)
                local nameMatchesConfirmedKill = (confirmedKilledMob ~= "" and t.mob == confirmedKilledMob)
                local nameMatchesActiveCombat = (activeCombatMob ~= "" and t.mob == activeCombatMob)
                if nameMatchesCurrent or nameMatchesConfirmedKill or nameMatchesActiveCombat then
                    local score = 5
                    if nameMatchesConfirmedKill then score = score + 8 end
                    if nameMatchesActiveCombat then score = score + 4 end
                    if t.arid and currentArea ~= "" and tostring(t.arid) == currentArea then score = score + 3 end
                    if t.roomName and currentRoom ~= "" and tostring(t.roomName) == currentRoom then score = score + 2 end
                    if snd.targets.current.index and t.index and tonumber(snd.targets.current.index) == tonumber(t.index) then
                        score = score + 1
                    end
                    if score > bestScore then
                        bestScore = score
                        bestIndex = i
                    end
                end
            end
        end
        if bestIndex and snd.targets.list[bestIndex] then
            local t = snd.targets.list[bestIndex]
            t.remaining = math.max(0, (t.remaining or 1) - 1)
            if t.remaining == 0 then
                t.dead = true
            end
        end
    end
    
    -- Trigger gq check to update status (subject to AutoCheck mode)
    if not snd.shouldAutoCheckAfterKill or snd.shouldAutoCheckAfterKill("gq") then
        tempTimer(0.5, function()
            send("gq check", false)
        end)
    end

    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

--- Handle gquest winner
-- @param gqId The global quest ID
-- @param winner Name of the winner
function snd.gq.onWinner(gqId, winner)
    local myName = snd.char.name or ""
    
    if winner == myName then
        snd.utils.reportLine("You won Global Quest #" .. gqId .. "!", "gquest")
        
        -- Record as complete
        if snd.db then
            snd.db.historyEnd(
                snd.db.HISTORY_TYPE_GQUEST,
                snd.db.HISTORY_STATUS_COMPLETE,
                {
                    qp = (tonumber(snd.gquest.qpReward) or 0) + (tonumber(snd.gquest.qpKillBonusTotal) or 0),
                    tp = tonumber(snd.gquest.tpReward) or 0,
                    trains = tonumber(snd.gquest.trainReward) or 0,
                    pracs = tonumber(snd.gquest.pracReward) or 0,
                    gold = tonumber(snd.gquest.goldReward) or 0,
                }
            )
        end
    else
        snd.utils.infoNote("Global Quest #" .. gqId .. " won by " .. winner)
        if snd.db and (snd.gquest.joined == gqId or snd.gquest.started == gqId) then
            snd.db.historyEnd(snd.db.HISTORY_TYPE_GQUEST, snd.db.HISTORY_STATUS_FAILED)
        end
    end
end

--- Handle gquest ended
-- @param gqId The global quest ID
function snd.gq.onEnded(gqId)
    snd.utils.reportLine("Global Quest #" .. gqId .. " has ended", "gquest")
    
    -- Only clear if this was our gquest
    if snd.gquest.joined == gqId or snd.gquest.started == gqId then
        if snd.db then
            snd.db.historyEnd(snd.db.HISTORY_TYPE_GQUEST, snd.db.HISTORY_STATUS_FAILED)
        end
        snd.gq.clearGquest()
    end
end

--- Handle gquest quit message
-- @param gqId The global quest ID
function snd.gq.onQuit(gqId)
    snd.utils.reportLine("Left Global Quest #" .. gqId, "gquest")

    if snd.gquest.joined == gqId or snd.gquest.started == gqId then
        if snd.db then
            snd.db.historyEnd(snd.db.HISTORY_TYPE_GQUEST, snd.db.HISTORY_STATUS_FAILED)
        end
        snd.gq.clearGquest()
    end
end

--- Handle not on gquest message
function snd.gq.onNotOnGquest()
    snd.utils.debugNote("Not on global quest")
    snd.gq.clearGquest()
end

--- Clear gquest state
function snd.gq.clearGquest()
    snd.gquest.active = false
    snd.gquest.joined = "-1"
    snd.gquest.started = "-1"
    snd.gquest.extended = "-1"
    snd.gquest.effectiveLevel = 0
    snd.gquest.targets = {}
    snd.gquest.checkList = {}
    snd.gquest.targetType = nil
    snd.gquest.historyId = 0
    snd.gquest.qpReward = 0
    snd.gquest.tpReward = 0
    snd.gquest.trainReward = 0
    snd.gquest.pracReward = 0
    snd.gquest.goldReward = 0
    snd.gquest.qpPerKillBonus = 0
    snd.gquest.qpKillBonusTotal = 0
    
    -- Remove gq targets from main list
    local newList = {}
    for _, t in ipairs(snd.targets.list) do
        if t.activity ~= "gq" then
            table.insert(newList, t)
        end
    end
    snd.targets.list = newList
    
    -- Clear target if it was a gq target
    if snd.targets.current and snd.targets.current.activity == "gq" then
        snd.clearTarget()
    end

    -- Update activity type
    if snd.campaign.active then
        snd.targets.activity = "cp"
    else
        snd.targets.activity = "none"
        snd.targets.type = "none"
    end

    if snd.nav and snd.nav.clearActivityQuickWhere then
        snd.nav.clearActivityQuickWhere("gq")
    end

    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

--- Handle extended time
-- @param gqId The global quest ID
function snd.gq.onExtendedTime(gqId)
    snd.utils.infoNote("Global Quest #" .. gqId .. " extended for 5 more minutes!")
    snd.gquest.extended = gqId
end

-------------------------------------------------------------------------------
-- GQuest Target Selection
-------------------------------------------------------------------------------

--- Select a gquest target by index
-- @param index Target index (1-based)
function snd.gq.selectTarget(index)
    index = tonumber(index)
    if not index then return false end
    
    local target = nil
    local count = 0
    
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "gq" and not t.dead then
            count = count + 1
            if count == index then
                target = t
                break
            end
        end
    end
    
    if not target then
        snd.utils.infoNote("Invalid target index: " .. index)
        return false
    end
    
    snd.setTarget({
        keyword = target.keyword,
        name = target.mob,
        roomName = target.roomName or "",
        roomId = target.rmid,
        area = target.arid or target.loc,
        areaName = target.loc or "",
        index = index,
        activity = "gq",
    })
    if snd.gquest.targetType == "room" and target.roomName and target.roomName ~= "" then
        snd.mapper.searchRoomsExact(target.roomName, target.arid, target.mob, {
            activity = "gq",
            levelTaken = snd.gquest.effectiveLevel,
        })
    else
        local results = snd.mapper.searchMobLocations(target.mob, target.arid)
        if not results or #results == 0 then
            local keyword = target.keyword or snd.utils.findKeyword(target.mob)
            if keyword and keyword ~= "" then
                snd.commands.qw(keyword)
            end
        end
    end
    
    snd.utils.infoNote("Target: " .. target.mob .. " (x" .. target.remaining .. ")")
    return true
end

--- Get next available gquest target
function snd.gq.getNextTarget()
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "gq" and not t.dead then
            return t
        end
    end
    return nil
end

--- Count remaining gquest targets
function snd.gq.getRemainingCount()
    local count = 0
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "gq" and not t.dead then
            count = count + 1
        end
    end
    return count
end

--- Get total remaining kills for gquest
function snd.gq.getTotalRemainingKills()
    local count = 0
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "gq" and not t.dead then
            count = count + (t.remaining or 0)
        end
    end
    return count
end

-- Module loaded silently
