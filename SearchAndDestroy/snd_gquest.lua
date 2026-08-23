snd = snd or {}
snd.gq = snd.gq or {}

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

local function entryHasMobPriority(entry)
    local priorityRoom = tonumber(entry and entry.priority_room)
    return priorityRoom ~= nil and priorityRoom > 0
end

local function startGquestHistory()
    if tonumber(snd.gquest.historyId) and tonumber(snd.gquest.historyId) > 0 then
        return
    end
    if not snd.db or not snd.db.historyStart then
        return
    end

    snd.gquest.historyId = snd.db.historyStart(
        snd.db.HISTORY_TYPE_GQUEST,
        snd.char.level or 0
    ) or 0

    -- Rewards may already have been parsed when target data is the fallback
    -- that proves this queued GQ has actually started.
    if snd.gquest.historyId > 0 and snd.gq.syncHistoryRewards then
        snd.gq.syncHistoryRewards()
    end
end

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

function snd.gq.processLevelRange(minLvl, maxLvl)
    local min = tonumber(minLvl) or 0
    local max = tonumber(maxLvl) or 0
    snd.gq.parsing.effectiveLevel = math.floor((min + max) / 2)
end

function snd.gq.markExtended()
    snd.gq.parsing.extended = true
end

function snd.gq.markFinished()
    snd.gq.parsing.finished = true
end

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

function snd.gq.endGqInfo()
    if not snd.gq.parsing.infoActive then return end
    
    snd.gq.parsing.infoActive = false
    snd.gq.parsing.infoEndTimer = nil
    
    if snd.gq.parsing.finished then
        snd.utils.debugNote("GQ info was for a finished quest, ignoring")
        return
    end

    -- Activate only when onJoined set this ID; browse-only gq info must stay inactive.
    local currentId = tostring(snd.gq.parsing.currentGqId or "")
    local joinedId = tostring(snd.gquest.joined or "")
    if currentId == "" or currentId ~= joinedId then
        snd.utils.debugNote("GQ info browsed without joining (parsed=" .. currentId .. ", joined=" .. joinedId .. "), skipping activation")
        return
    end

    snd.gquest.targets = snd.gq.parsing.tempTargets
    snd.gquest.active = #snd.gquest.targets > 0
    -- Preserve joined/started state established by their event handlers.
    snd.gquest.effectiveLevel = snd.gq.parsing.effectiveLevel
    
    if snd.gq.parsing.extended then
        snd.gquest.extended = snd.gq.parsing.currentGqId
    end
    
    if #snd.gquest.targets > 0 then
        startGquestHistory()
        snd.gquest.targetType = snd.cp.determineTargetType(snd.gquest.targets)
        snd.targets.type = snd.gquest.targetType
        snd.targets.activity = "gq"
        
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

function snd.gq.captureInfoReward(rewardType, value, bonusPerKill)
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

function snd.gq.applyKillBonus(qpBonus)
    local bonus = tonumber(qpBonus) or 0
    if bonus <= 0 then
        return
    end
    snd.gquest.qpKillBonusTotal = (tonumber(snd.gquest.qpKillBonusTotal) or 0) + bonus
    snd.gq.syncHistoryRewards()
end

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

function snd.gq.startGqCheck()
    snd.gq.parsing.checkActive = true
    snd.gquest.checkList = {}
end

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
        startGquestHistory()
        snd.gq.buildMainTargetList()
    end
    
    snd.gq.updateTargetStatus()
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
    if snd.gquest.active and snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "gq", {save = true, refresh = false})
    end
end

function snd.gq.buildMainTargetList()
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

    for i, target in ipairs(snd.gquest.targets) do
        local roomName = ""
        if snd.gquest.targetType == "room" and target.loc and target.loc ~= "" then
            roomName = target.loc
        end
        local hasMobData = true
        local locations = {}
        if snd.gquest.targetType ~= "room" and snd.db and snd.db.getMobLocations then
            locations = snd.db.getMobLocations(target.mob, target.arid) or {}
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
        local dk = string.format("%s|%s|%s", tostring(target.mob or ""):lower(), tostring(target.arid or ""):lower(), tostring(target.loc or ""):lower())
        entry._dupkey = dk
        entry.duplicates = duplicateCounts[dk] or 1
        if entry.priority_room and tonumber(entry.priority_room) and tonumber(entry.priority_room) > 0 then
            entry.rmid = tonumber(entry.priority_room)
        elseif locations[1] and tonumber(locations[1].roomid or locations[1].rmid) then
            entry.rmid = tonumber(locations[1].roomid or locations[1].rmid)
            if entry.roomName == "" then
                entry.roomName = tostring(locations[1].room or locations[1].roomName or "")
            end
        end
        if snd.express and snd.express.classifyTarget then
            snd.express.classifyTarget(entry)
        end
        if snd.debug and snd.debug.mobTag and (entry.priority_room or entry.nowhere or entry.nohunt) then
            snd.debug.mobTag(string.format(
                "GQ build mob='%s' area=%s loc='%s' rmid=%s nowhere=%s nohunt=%s priority_room=%s",
                tostring(entry.mob or ""),
                tostring(entry.arid or ""),
                tostring(entry.loc or ""),
                tostring(entry.rmid or ""),
                tostring(entry.nowhere == true),
                tostring(entry.nohunt == true),
                tostring(entry.priority_room or "")
            ))
        end
        table.insert(gqEntries, entry)
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
        local aPriority = entryHasMobPriority(a)
        local bPriority = entryHasMobPriority(b)
        if aPriority ~= bPriority then
            return aPriority
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

    for i = #gqEntries, 1, -1 do
        table.insert(snd.targets.list, 1, gqEntries[i])
    end

    if snd.sortTargetsByPriority then
        snd.sortTargetsByPriority({
            recalculateProximity = true,
            reason = "gq_target_list_built",
        })
    end
    
    snd.utils.debugNote("Built GQ target list: " .. #snd.gquest.targets .. " targets (priority)")
end

function snd.gq.updateTargetStatus()
    local consumedChecks = {}
    for _, target in ipairs(snd.targets.list) do
        if target.activity == "gq" then
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
            
            if not found then
                target.remaining = 0
                target.dead = true
            end
        end
    end
    if snd.sortTargetsByPriority then
        snd.sortTargetsByPriority({
            recalculateProximity = true,
            reason = "gq_target_status_changed",
        })
    end
end

function snd.gq.onJoined(gqId)
    snd.utils.reportLine("Joined Global Quest #" .. gqId, "gquest")
    snd.gquest.joined = gqId

    if snd.config.autocheck then
        snd.config.autocheck.gqKillCounter = 0
    end

    if snd.gmcp and snd.gmcp.setNoexp then
        snd.gmcp.setNoexp(true, "Search and Destroy: Turning noexp ON (joined global quest)", true)
    elseif snd.char and not snd.char.noexp then
        sendGMCP("config noexp on")
        snd.char.noexp = true
        snd.utils.infoNote("Search and Destroy: Turning noexp ON (joined global quest)")
    end

    snd.gquest.targets = {}
    snd.gquest.active = true
    snd.gquest.historyId = 0
    snd.gquest.qpReward = 0
    snd.gquest.tpReward = 0
    snd.gquest.trainReward = 0
    snd.gquest.pracReward = 0
    snd.gquest.goldReward = 0
    snd.gquest.qpPerKillBonus = 0
    snd.gquest.qpKillBonusTotal = 0

    -- A numbered join message can mean either "queued" or "joined an already
    -- running GQ". Only the latter should begin elapsed-time history here.
    if tostring(snd.gquest.started) == tostring(gqId) then
        startGquestHistory()
    end
    
    tempTimer(0.5, function()
        send("gq info", false)
    end)
end

function snd.gq.onStarted(gqId, minLvl, maxLvl)
    snd.utils.debugNote("GQ #" .. gqId .. " started (levels " .. minLvl .. "-" .. maxLvl .. ")")
    snd.gquest.started = gqId
    
    if snd.gquest.joined == gqId then
        startGquestHistory()
        tempTimer(0.5, function()
            send("gq info", false)
        end)
    end
end

function snd.gq.onMobKilled()
    snd.utils.debugNote("Global quest mob killed!")
    local confirmedKilledMob = ""
    if snd.conwin and snd.conwin.getRecentKilledMobName then
        confirmedKilledMob = snd.conwin.getRecentKilledMobName(3) or ""
        if confirmedKilledMob ~= "" and snd.conwin.clearRecentKilledMobName then
            snd.conwin.clearRecentKilledMobName()
        end
    end

    -- Text may arrive before GMCP clears; ConWin can still identify the live enemy.
    local activeCombatMob = ""
    if confirmedKilledMob == "" and snd.conwin and snd.conwin.getCurrentCombatMobName then
        activeCombatMob = snd.conwin.getCurrentCombatMobName() or ""
    end

    if snd.targets.current and snd.targets.current.activity == "gq" then
        local roomId = snd.room and snd.room.current and snd.room.current.id or nil
        local killedMobName = confirmedKilledMob ~= "" and confirmedKilledMob or snd.targets.current.name or ""
        if type(raiseEvent) == "function" then
            raiseEvent("snd.kill.confirmed", killedMobName, roomId)
        end
        local bestIndex, bestScore = nil, -1
        local currentArea = snd.room and snd.room.current and tostring(snd.room.current.arid or "") or ""
        local currentRoom = snd.room and snd.room.current and tostring(snd.room.current.name or "") or ""
        for i, t in ipairs(snd.targets.list) do
            if t.activity == "gq" and not t.dead then
                -- ConWin lowercases names; GQ may preserve proper-name casing.
                local nameMatchesCurrent = snd.utils.mobIdentityMatches(t.mob, snd.targets.current.name)
                local nameMatchesConfirmedKill = snd.utils.mobIdentityMatches(t.mob, confirmedKilledMob)
                local nameMatchesActiveCombat = snd.utils.mobIdentityMatches(t.mob, activeCombatMob)
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
                if t.mob == snd.targets.current.name then
                    snd.clearTarget({refresh = false})
                end
            end
        end
    end

    if snd.sortTargetsByPriority then
        snd.sortTargetsByPriority({
            recalculateProximity = true,
            reason = "gq_kill",
        })
    end
    
    if not snd.shouldAutoCheckAfterKill or snd.shouldAutoCheckAfterKill("gq") then
        tempTimer(0.5, function()
            send("gq check", false)
        end)
    end

    if snd.gui then
        if snd.gui.requestRefresh then snd.gui.requestRefresh()
        elseif snd.gui.refresh then snd.gui.refresh() end
    end
end

function snd.gq.onPersonallyCompleted(gqId)
    snd.utils.reportLine("You won Global Quest #" .. (gqId or "?") .. "!", "gquest")
    if snd.db then
        snd.db.historyEnd(snd.db.HISTORY_TYPE_GQUEST, snd.db.HISTORY_STATUS_COMPLETE, {
            qp     = (tonumber(snd.gquest.qpReward) or 0) + (tonumber(snd.gquest.qpKillBonusTotal) or 0),
            tp     = tonumber(snd.gquest.tpReward) or 0,
            trains = tonumber(snd.gquest.trainReward) or 0,
            pracs  = tonumber(snd.gquest.pracReward) or 0,
            gold   = tonumber(snd.gquest.goldReward) or 0,
        })
    end
    snd.gq.clearGquest()
end

function snd.gq.onWinner(gqId, winner)
    local myName = snd.char.name or ""
    if winner == myName then
        if not snd.gquest.active then return end
        snd.gq.onPersonallyCompleted(gqId)
    else
        snd.utils.infoNote("Global Quest #" .. gqId .. " won by " .. winner)
        if snd.gquest.joined == gqId or snd.gquest.started == gqId then
            if snd.db then snd.db.historyEnd(snd.db.HISTORY_TYPE_GQUEST, snd.db.HISTORY_STATUS_FAILED) end
            snd.gq.clearGquest()
        end
    end
end

function snd.gq.onMayWinMore()
    if not snd.gquest.active then return end
    tempTimer(2, function()
        if not snd.gquest.active then return end
		if snd.gq.getTotalRemainingKills() > 0 then return end
        local gqId = snd.gquest.joined ~= "-1" and snd.gquest.joined or snd.gquest.started
        snd.gq.onPersonallyCompleted(gqId)
    end)
end

function snd.gq.onEnded(gqId)
    snd.utils.reportLine("Global Quest #" .. gqId .. " has ended", "gquest")
    
    if snd.gquest.joined == gqId or snd.gquest.started == gqId then
        if snd.db then
            snd.db.historyEnd(snd.db.HISTORY_TYPE_GQUEST, snd.db.HISTORY_STATUS_FAILED)
        end
        snd.gq.clearGquest()
    end
end

function snd.gq.onQuit(gqId)
    snd.utils.reportLine("Left Global Quest #" .. gqId, "gquest")

    if snd.gquest.joined == gqId or snd.gquest.started == gqId then
        if snd.db then
            snd.db.historyEnd(snd.db.HISTORY_TYPE_GQUEST, snd.db.HISTORY_STATUS_FAILED)
        end
        snd.gq.clearGquest()
    end
end

function snd.gq.onNotOnGquest()
    snd.utils.debugNote("Not on global quest")
    snd.gq.clearGquest()
end

function snd.gq.clearGquest()
    -- Cancel stale parsing timers before they can reactivate cleared GQ state.
    if snd.gq.parsing and snd.gq.parsing.infoEndTimer then
        pcall(function() killTimer(snd.gq.parsing.infoEndTimer) end)
        snd.gq.parsing.infoEndTimer = nil
    end
    if snd.gq.parsing then snd.gq.parsing.infoActive = false end

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
    
    local newList = {}
    for _, t in ipairs(snd.targets.list) do
        if t.activity ~= "gq" then
            table.insert(newList, t)
        end
    end
    snd.targets.list = newList
    
    if snd.targets.current and snd.targets.current.activity == "gq" then
        snd.clearTarget()
    end

    if snd.quest and snd.quest.active then
        snd.targets.activity = "quest"
    elseif snd.campaign.active then
        snd.targets.activity = "cp"
    else
        snd.targets.activity = "none"
        snd.targets.type = "none"
    end

    if snd.nav and snd.nav.clearActivityQuickWhere then
        snd.nav.clearActivityQuickWhere("gq")
    end

    if snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "quest", {save = true, refresh = false})
    end

    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.gq.onExtendedTime(gqId)
    snd.utils.infoNote("Global Quest #" .. gqId .. " extended for 5 more minutes!")
    snd.gquest.extended = gqId
end

function snd.gq.selectTarget(index, options)
    local opts = type(options) == "table" and options or {}
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

    if snd.debug and snd.debug.mobTag then
        snd.debug.mobTag(string.format(
            "GQ select index=%s mob='%s' area=%s loc='%s' roomName='%s' rmid=%s priority_room=%s nowhere=%s nohunt=%s",
            tostring(index),
            tostring(target.mob or ""),
            tostring(target.arid or ""),
            tostring(target.loc or ""),
            tostring(target.roomName or ""),
            tostring(target.rmid or ""),
            tostring(target.priority_room or ""),
            tostring(target.nowhere == true),
            tostring(target.nohunt == true)
        ))
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
        express = target.express == true,
        expressRoomId = target.expressRoomId,
        expressKillCount = target.expressKillCount,
        expressRoomCount = target.expressRoomCount,
    })
    if not opts.skipLookup then
        if snd.gquest.targetType == "room" and target.roomName and target.roomName ~= "" then
            snd.mapper.searchRoomsExact(target.roomName, target.arid, target.mob, {
                activity = "gq",
                levelTaken = snd.gquest.effectiveLevel,
            })
        else
            local results = snd.mapper.searchMobLocations(target.mob, target.arid)
            if not results or #results == 0 then
                snd.commands.qw("")
            end
        end
    end
    
    if not opts.skipLookup then
        snd.utils.infoNote("Target: " .. target.mob .. " (x" .. target.remaining .. ")")
    end
    return true
end

function snd.gq.getNextTarget()
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "gq" and not t.dead then
            return t
        end
    end
    return nil
end

function snd.gq.getRemainingCount()
    local count = 0
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "gq" and not t.dead then
            count = count + 1
        end
    end
    return count
end

function snd.gq.getTotalRemainingKills()
    local count = 0
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "gq" and not t.dead then
            count = count + (t.remaining or 0)
        end
    end
    return count
end
