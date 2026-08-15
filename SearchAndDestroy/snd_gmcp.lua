if type(mm) ~= "table" or type(mm.canonical_room_uid) ~= "function" or type(mm.nav) ~= "table" then
    error("Search and Destroy requires MMapper to be fully loaded first (missing mm.canonical_room_uid or mm.nav).")
end

snd = snd or {}
snd.gmcp = snd.gmcp or {}

local function clearQuestQuickWhereCache()
    if snd.nav and snd.nav.clearActivityQuickWhere then
        snd.nav.clearActivityQuickWhere("quest")
    end
end

local function startQuestReadyReminder()
    if snd.quest and snd.quest.startReadySoundReminder then
        snd.quest.startReadySoundReminder()
    end
end

local function stopQuestReadyReminder()
    if snd.quest and snd.quest.stopReadySoundReminder then
        snd.quest.stopReadySoundReminder()
    end
end

snd.gmcp.handlers = snd.gmcp.handlers or {}

function snd.gmcp.registerHandlers()
    snd.utils.debugNote("Registering GMCP handlers...")
    
    snd.gmcp.unregisterHandlers()
    
    snd.gmcp.handlers.charStatus = registerAnonymousEventHandler(
        "gmcp.char.status",
        snd.gmcp.onCharStatus
    )
    
    snd.gmcp.handlers.charBase = registerAnonymousEventHandler(
        "gmcp.char.base",
        snd.gmcp.onCharBase
    )

    snd.gmcp.handlers.charVitals = registerAnonymousEventHandler(
        "gmcp.char.vitals",
        snd.gmcp.onCharVitals
    )
    
    snd.gmcp.handlers.roomInfo = registerAnonymousEventHandler(
        "gmcp.room.info",
        snd.gmcp.onRoomInfo
    )
    
    snd.gmcp.handlers.commQuest = registerAnonymousEventHandler(
        "gmcp.comm.quest",
        snd.gmcp.onCommQuest
    )
    
    snd.gmcp.handlers.config = registerAnonymousEventHandler(
        "gmcp.config",
        snd.gmcp.onConfig
    )
    
    snd.utils.debugNote("GMCP handlers registered")
end

function snd.gmcp.unregisterHandlers()
    for name, handler in pairs(snd.gmcp.handlers) do
        if handler then
            killAnonymousEventHandler(handler)
        end
    end
    snd.gmcp.handlers = {}
end

function snd.gmcp.onCharStatus()
    if not gmcp or not gmcp.char or not gmcp.char.status then
        return
    end
    
    local status = gmcp.char.status
    
    local oldState = snd.char.state
    local oldLevel = snd.char.level
    snd.char.state = tostring(status.state or "0")
    snd.char.level = tonumber(status.level) or 0
    snd.char.tnl = tonumber(status.tnl) or snd.char.tnl or 0

    if oldLevel ~= nil and tonumber(oldLevel) ~= tonumber(snd.char.level) then
        snd.char.autoNoexpCampaignStatus = "unknown"
    end
    
    if snd.char.state == "3" then
        if oldState ~= "3" then
            if snd.db and snd.db.clearSeenCache then
                snd.db.clearSeenCache()
            end
        end
        if snd.onPlayerActive then
            snd.onPlayerActive()
        end
    end
    
    if oldState ~= snd.char.state then
        snd.onStateChange()
    end

    if snd.char.state == "3" and snd.tryAutoOpenWindow then
        snd.tryAutoOpenWindow()
    end
    
    if snd.char.level < 200 and snd.config.anex.automatic then
        snd.gmcp.checkAutoNoexp()
    end
    
    snd.utils.debugNote("char.status - state: " .. snd.char.state .. ", level: " .. snd.char.level)
end

function snd.gmcp.onCharBase()
    if not gmcp or not gmcp.char or not gmcp.char.base then
        return
    end
    
    local base = gmcp.char.base
    
    snd.char.name = base.name or ""
    snd.char.class = base.class or ""
    snd.char.tier = tonumber(base.tier) or 0
    snd.char.remorts = tonumber(base.remorts) or 0

    
    snd.utils.debugNote("char.base - name: " .. snd.char.name .. ", class: " .. snd.char.class)
end


function snd.gmcp.onCharVitals()
    if not gmcp or not gmcp.char or not gmcp.char.vitals then
        return
    end

    local vitals = gmcp.char.vitals

    snd.char.hp = tonumber(vitals.hp) or 0
    snd.char.mana = tonumber(vitals.mana) or 0
    snd.char.moves = tonumber(vitals.moves) or 0

    if snd.onCharVitalsReady then
        snd.onCharVitalsReady(vitals)
    end

    snd.utils.debugNote(
        "char.vitals - hp: " .. tostring(snd.char.hp) ..
        ", mana: " .. tostring(snd.char.mana) ..
        ", moves: " .. tostring(snd.char.moves)
    )
end

function snd.gmcp.onRoomInfo()
    if not gmcp or not gmcp.room or not gmcp.room.info then
        return
    end
    
    local ri = gmcp.room.info
    
    snd.room.previous = snd.utils.deepcopy(snd.room.current)
    
    local isMaze = 0
    if ri.details and type(ri.details) == "string" then
        if ri.details:match("maze") then
            isMaze = 1
        end
    end
    
    snd.room.current = {
        rmid = mm.canonical_room_uid(ri) or "-1",
        arid = ri.zone or "",
        exits = ri.exits or {},
        maze = isMaze,
        name = ri.name or "",
        terrain = ri.terrain or "",
    }

    local roomChanged = snd.room.current.rmid ~= snd.room.previous.rmid

    if snd.mapper then
        local navigating = snd.mapper.persistenceNavigationActive
            and snd.mapper.persistenceNavigationActive()
        if navigating then
            if snd.mapper.bufferRoomPersist then
                snd.mapper.bufferRoomPersist(ri)
            end
        else
            -- Manual arrival joins any orphaned nav buffer for one commit/notification.
            if snd.mapper.bufferRoomPersist and snd.mapper.flushPendingPersists then
                local hadOrphanedBuffer = snd.mapper.hasPendingPersistence
                    and snd.mapper.hasPendingPersistence()
                snd.mapper.bufferRoomPersist(ri)
                snd.mapper.flushPendingPersists({ bulk_compare = hadOrphanedBuffer == true })
            elseif snd.mapper.persistDiscoveredRoom then
                snd.mapper.persistDiscoveredRoom(ri)
            end
        end
    end

    if roomChanged then
        snd.room.history = snd.room.history or {}
        snd.onRoomChange()
        
        snd.utils.debugNote("room.info - room: " .. snd.room.current.rmid .. 
                          ", area: " .. snd.room.current.arid ..
                          ", name: " .. snd.room.current.name)
    end
end

function snd.gmcp.onCommQuest()
    if not gmcp or not gmcp.comm or not gmcp.comm.quest then
        return
    end
    
    local q = gmcp.comm.quest
    local action = type(q.action) == "string" and q.action:lower() or q.action
    local actionAliases = {
        complete = "comp",
        completed = "comp",
        completion = "comp",
    }
    if type(action) == "string" and actionAliases[action] then
        action = actionAliases[action]
    end
    
    snd.utils.debugNote("comm.quest - action: " .. tostring(action))

    local questTimerActions = {
        start = true,
        killed = true,
        warning = true,
    }
    local isActiveStatusPayload = (action == "status" and (q.targ or q.target == "killed"))
    local shouldTrackQuestCountdown = questTimerActions[action] or isActiveStatusPayload

    if shouldTrackQuestCountdown then
        local timerMinutes = tonumber(q.timer)
        if action == "killed" or q.target == "killed" then
            timerMinutes = tonumber(q.time) or timerMinutes
        elseif action == "warning" then
            timerMinutes = tonumber(q.time) or timerMinutes
        end

        if timerMinutes and timerMinutes > 0 then
            snd.quest.timerEndTime = os.time() + (timerMinutes * 60)
            if snd.gui and snd.gui.startQuestTimer then
                snd.gui.startQuestTimer()
            end
        end
    end

    local status = type(q.status) == "string" and q.status:lower() or q.status
    if status == "available" or status == "ready" then
        snd.quest.available = true
    elseif action == "start" or action == "killed" or action == "comp" or action == "fail" or action == "timeout" then
        snd.quest.available = false
    end
    
    if action == "start" then
        snd.gmcp.onQuestStart(q)
        
    elseif action == "killed" then
        snd.gmcp.onQuestKilled(q)
        
    elseif action == "comp" then
        snd.gmcp.onQuestComplete(q)
        
    elseif action == "fail" then
        snd.gmcp.onQuestFail(q)
        
    elseif action == "timeout" then
        snd.gmcp.onQuestTimeout(q)
        
    elseif action == "ready" then
        snd.gmcp.onQuestReady(q)
        
    elseif action == "reset" then
        snd.gmcp.onQuestReset(q)
        
    elseif action == "status" then
        snd.gmcp.onQuestStatus(q)
        
    elseif action == "warning" then
        snd.gmcp.onQuestWarning(q)

    elseif status == "available" or status == "ready" then
        snd.gmcp.onQuestReady(q)
    end
end

function snd.gmcp.getQuestWaitMinutes(q)
    if not q then
        return nil
    end

    local wait = tonumber(q.wait)
    if wait and wait >= 0 then
        return wait
    end

    return nil
end

function snd.gmcp.onQuestStart(q)
    if snd.db then
        snd.db.historyStart(snd.db.HISTORY_TYPE_QUEST, snd.char.level or 0)
    end

    snd.quest.active = true
    snd.quest.available = false
    stopQuestReadyReminder()
    snd.quest.target = {
        mob = q.targ or "",
        area = q.area or "",
        room = q.room or "",
        arid = "",
        keyword = "",
        status = "active",
    }
    snd.quest.timer = tonumber(q.timer) or 0
    snd.quest.setCooldown(0)
    clearQuestQuickWhereCache()
    if snd.quest.target.area ~= "" then
        snd.quest.target.arid = snd.db.getAreaKeyFromName(snd.quest.target.area) or ""
    end
    
    if snd.quest.target.mob ~= "" then
        snd.quest.target.keyword = snd.gmcp.guessMobKeyword(
            snd.quest.target.mob,
            snd.quest.target.area
        )
    end
    
    snd.gmcp.addQuestToTargetList()
    snd.gmcp.registerQuestTargetTrigger()

    snd.gmcp.showQuestTargetDetails()
    
    snd.utils.infoNote("Quest started: " .. snd.quest.target.mob ..
                       " in " .. snd.quest.target.area)
    if snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "quest", {save = true, refresh = false})
    end
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.gmcp.addQuestToTargetList()
    if not snd.quest.active or not snd.quest.target.mob or snd.quest.target.mob == "" then
        return
    end
    
    snd.gmcp.removeQuestFromTargetList()
    
    local areaKey = snd.quest.target.arid or ""
    if areaKey == "" and snd.quest.target.area and snd.quest.target.area ~= "" then
        areaKey = snd.db.getAreaKeyFromName(snd.quest.target.area) or ""
        snd.quest.target.arid = areaKey
    end
    
    local target = {
        mob = snd.quest.target.mob,
        loc = snd.quest.target.area,
        arid = areaKey,
        keyword = snd.quest.target.keyword,
        roomName = snd.utils.stripColors(snd.quest.target.room or ""),
        activity = "quest",
        dead = (snd.quest.target.status == "killed"),
        remaining = 1,
    }
    if snd.express and snd.express.classifyTarget then
        snd.express.classifyTarget(target)
    end
    
    local insertPos = 1
    for i, t in ipairs(snd.targets.list) do
        if t.activity == "gq" then
            insertPos = i + 1  -- Insert after this GQ target
        else
            break  -- Found non-GQ target, insert here
        end
    end
    
    table.insert(snd.targets.list, insertPos, target)
    
    if not snd.gquest.active then
        if snd.nav and snd.nav.invalidateQuickWhereForTarget then
            snd.nav.invalidateQuickWhereForTarget(target)
        end
        snd.targets.current = target
    end
    
    snd.utils.debugNote("Added quest target to list at position " .. insertPos .. ": " .. target.mob)
end

function snd.gmcp.registerQuestTargetTrigger()
    snd.gmcp.unregisterQuestTargetTrigger()
    if not snd.quest or not snd.quest.target or snd.quest.target.mob == "" then
        return
    end

    local mob = snd.utils.stripColors(snd.quest.target.mob)
    local escaped = snd.utils.escapeRegex(mob)
    local pattern = ".*" .. escaped .. ".*"
    snd.quest.targetTriggerId = tempRegexTrigger(pattern, function()
        snd.triggers.questTargetLine()
    end)
end

function snd.gmcp.unregisterQuestTargetTrigger()
    if snd.quest and snd.quest.targetTriggerId then
        killTrigger(snd.quest.targetTriggerId)
        snd.quest.targetTriggerId = nil
    end
end

function snd.gmcp.removeQuestFromTargetList()
    local i = 1
    while i <= #snd.targets.list do
        if snd.targets.list[i].activity == "quest" then
            table.remove(snd.targets.list, i)
        else
            i = i + 1
        end
    end
end

-- Update copied current/scoped rows too, or mobdetect/xkill can retain a live quest target.
function snd.gmcp.markQuestTargetKilled()
    local canonical = snd.quest and snd.quest.target or nil
    if canonical then
        canonical.dead = true
        canonical.killed = true
        canonical.status = "killed"
        canonical.remaining = 0
    end

    for _, target in ipairs(snd.targets.list) do
        if target.activity == "quest" then
            target.dead = true
            target.killed = true
            target.status = "killed"
            target.remaining = 0
        end
    end

    local current = snd.targets.current
    if current and current.activity == "quest" then
        current.dead = true
        current.killed = true
        current.status = "killed"
        current.remaining = 0
    end

    local scoped = snd.targets.scoped and snd.targets.scoped.quest or nil
    if scoped then
        scoped.dead = true
        scoped.killed = true
        scoped.status = "killed"
        scoped.remaining = 0
    end
end

function snd.gmcp.onQuestKilled(q)
    snd.quest.available = false
    stopQuestReadyReminder()
    snd.quest.target.status = "killed"
    snd.quest.timer = tonumber(q.time) or 0
    
    snd.gmcp.markQuestTargetKilled()
    
    snd.utils.infoNote("Quest target killed!")

    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.gmcp.onQuestComplete(q)
    local qp = tonumber(q.qp) or 0
    local gold = tonumber(q.gold) or 0
    local tp = tonumber(q.tp) or 0
    local trains = tonumber(q.trains) or 0
    local pracs = tonumber(q.pracs) or 0

    snd.gmcp.queueQuestReward(qp, gold, tp, trains, pracs)
    
    snd.quest.active = false
    snd.quest.available = false
    stopQuestReadyReminder()
    snd.quest.timerEndTime = 0
    if snd.gui and snd.gui.stopQuestTimer then
        snd.gui.stopQuestTimer()
    end
    snd.quest.target = {mob = "", area = "", room = "", keyword = "", status = "0"}
    snd.quest.setCooldown(q.wait)
    clearQuestQuickWhereCache()
    
    snd.gmcp.removeQuestFromTargetList()
    
    if snd.targets.current and snd.targets.current.activity == "quest" then
        snd.clearTarget()
    end
    if snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "auto", {save = true, refresh = false})
    end

    snd.gmcp.unregisterQuestTargetTrigger()
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.gmcp.queueQuestReward(qp, gold, tp, trains, pracs)
    local tierBonus = snd.char and snd.char.tier or 0
    snd.quest.blessingBonus = 0
    snd.quest.extraBonus = 0

    local completedAt = os.time()

    snd.quest.pendingReward = {
        qp = qp + tierBonus,
        gold = gold,
        tp = tp,
        trains = trains,
        pracs = pracs,
        tierBonus = tierBonus,
        completedAt = completedAt,
    }

    if snd.quest.rewardTimer then
        killTimer(snd.quest.rewardTimer)
        snd.quest.rewardTimer = nil
    end

    snd.quest.rewardTimer = tempTimer(1, function()
        snd.gmcp.emitQuestReward()
    end)
end

function snd.gmcp.emitQuestReward()
    if not snd.quest.pendingReward then
        return
    end

    local reward = snd.quest.pendingReward
    local totalQp = (reward.qp or 0) + (snd.quest.blessingBonus or 0) + (snd.quest.extraBonus or 0)
    local gold = reward.gold or 0
    local tp = reward.tp or 0
    local trains = reward.trains or 0
    local pracs = reward.pracs or 0
    local durationSeconds = nil
    local completedAt = tonumber(reward.completedAt) or os.time()

    if snd.db then
        local endedHistory = snd.db.historyEnd(snd.db.HISTORY_TYPE_QUEST, snd.db.HISTORY_STATUS_COMPLETE, {
            qp = totalQp,
            gold = gold,
            tp = tp,
            trains = trains,
            pracs = pracs,
        }, completedAt)
        if endedHistory then
            totalQp = tonumber(endedHistory.qp_rewards) or totalQp
            gold = tonumber(endedHistory.gold_rewards) or gold
            tp = tonumber(endedHistory.tp_rewards) or tp
            trains = tonumber(endedHistory.train_rewards) or trains
            pracs = tonumber(endedHistory.prac_rewards) or pracs
            durationSeconds = tonumber(endedHistory.duration_seconds) or durationSeconds
        end
    end

    snd.utils.reportQuestCompletion(totalQp, gold, durationSeconds, tp, trains, pracs)

    snd.quest.pendingReward = nil
    snd.quest.rewardTimer = nil
    snd.quest.blessingBonus = 0
    snd.quest.extraBonus = 0
end

function snd.gmcp.onQuestFail(q)
    snd.utils.infoNote("Quest failed!")
    if snd.db then
        snd.db.historyEnd(snd.db.HISTORY_TYPE_QUEST, snd.db.HISTORY_STATUS_FAILED)
    end
    
    snd.quest.active = false
    snd.quest.available = false
    stopQuestReadyReminder()
    snd.quest.timerEndTime = 0
    if snd.gui and snd.gui.stopQuestTimer then
        snd.gui.stopQuestTimer()
    end
    snd.quest.target = {mob = "", area = "", room = "", keyword = "", status = "0"}
    snd.quest.setCooldown(q.wait)
    clearQuestQuickWhereCache()
    
    snd.gmcp.removeQuestFromTargetList()
    
    if snd.targets.current and snd.targets.current.activity == "quest" then
        snd.clearTarget()
    end
    if snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "auto", {save = true, refresh = false})
    end

    snd.gmcp.unregisterQuestTargetTrigger()
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.gmcp.onQuestTimeout(q)
    snd.utils.infoNote("Quest timed out!")
    if snd.db then
        snd.db.historyEnd(snd.db.HISTORY_TYPE_QUEST, snd.db.HISTORY_STATUS_TIMEOUT)
    end
    
    snd.quest.active = false
    snd.quest.available = false
    stopQuestReadyReminder()
    snd.quest.timerEndTime = 0
    if snd.gui and snd.gui.stopQuestTimer then
        snd.gui.stopQuestTimer()
    end
    snd.quest.target = {mob = "", area = "", room = "", keyword = "", status = "0"}
    snd.quest.setCooldown(q.wait)
    clearQuestQuickWhereCache()
    
    snd.gmcp.removeQuestFromTargetList()
    
    if snd.targets.current and snd.targets.current.activity == "quest" then
        snd.clearTarget()
    end
    if snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "auto", {save = true, refresh = false})
    end

    snd.gmcp.unregisterQuestTargetTrigger()
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.gmcp.onQuestReady(q)
    snd.quest.setCooldown(0)
    snd.quest.nextQuestText = "Quest Available"
    snd.quest.active = false
    snd.quest.available = true
    snd.quest.timerEndTime = 0
    if snd.gui and snd.gui.stopQuestTimer then
        snd.gui.stopQuestTimer()
    end
    snd.gmcp.unregisterQuestTargetTrigger()
    startQuestReadyReminder()
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.gmcp.onQuestReset(q)
    if snd.db then
        snd.db.historyEnd(snd.db.HISTORY_TYPE_QUEST, snd.db.HISTORY_STATUS_RESET)
    end

    snd.quest.setCooldown(q.timer)
    snd.quest.available = false
    stopQuestReadyReminder()
    snd.quest.timerEndTime = 0
    if snd.gui and snd.gui.stopQuestTimer then
        snd.gui.stopQuestTimer()
    end
    clearQuestQuickWhereCache()
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.gmcp.onQuestStatus(q)
    local waitMinutes = snd.gmcp.getQuestWaitMinutes(q)
    local status = type(q.status) == "string" and q.status:lower() or q.status

    if waitMinutes and waitMinutes > 0 then
        snd.quest.active = false
        snd.quest.available = false
        stopQuestReadyReminder()
        snd.quest.timerEndTime = 0
        if snd.gui and snd.gui.stopQuestTimer then
            snd.gui.stopQuestTimer()
        end
        snd.quest.target.status = "0"
        snd.quest.setCooldown(waitMinutes)
        clearQuestQuickWhereCache()
        snd.gmcp.removeQuestFromTargetList()
        if snd.targets.current and snd.targets.current.activity == "quest" then
            snd.clearTarget()
        end
        if snd.setActiveTab and snd.getPreferredActiveActivity then
            snd.setActiveTab(snd.getPreferredActiveActivity() or "auto", {save = true, refresh = false})
        end
        snd.gmcp.unregisterQuestTargetTrigger()
    elseif status == "ready" or status == "available" then
        snd.quest.active = false
        snd.quest.setCooldown(0)
        snd.quest.nextQuestText = "Quest Available"
        snd.quest.available = true
        startQuestReadyReminder()
        snd.quest.timerEndTime = 0
        if snd.gui and snd.gui.stopQuestTimer then
            snd.gui.stopQuestTimer()
        end
        clearQuestQuickWhereCache()
        snd.gmcp.removeQuestFromTargetList()
        if snd.targets.current and snd.targets.current.activity == "quest" then
            snd.clearTarget()
        end
        if snd.setActiveTab and snd.getPreferredActiveActivity then
            snd.setActiveTab(snd.getPreferredActiveActivity() or "auto", {save = true, refresh = false})
        end
        snd.gmcp.unregisterQuestTargetTrigger()
    elseif q.targ == "missing" then
        snd.quest.active = true
        snd.quest.available = false
        stopQuestReadyReminder()
        snd.quest.target.status = "missing"
        snd.quest.timer = tonumber(q.timer) or 0
        snd.quest.setCooldown(0)
    elseif q.target == "killed" then
        snd.quest.active = true
        snd.quest.available = false
        stopQuestReadyReminder()
        snd.quest.target.status = "killed"
        snd.quest.timer = tonumber(q.time) or 0
        snd.quest.setCooldown(0)
        snd.gmcp.markQuestTargetKilled()
    elseif q.targ then
        snd.quest.active = true
        snd.quest.available = false
        stopQuestReadyReminder()
        snd.quest.target = {
            mob = q.targ or "",
            area = q.area or "",
            room = q.room or "",
            arid = "",
            keyword = "",
            status = "active",
        }
        snd.quest.timer = tonumber(q.timer) or 0
        snd.quest.setCooldown(0)
        if snd.quest.target.area ~= "" then
            snd.quest.target.arid = snd.db.getAreaKeyFromName(snd.quest.target.area) or ""
        end
        
        if snd.quest.target.mob ~= "" then
            snd.quest.target.keyword = snd.gmcp.guessMobKeyword(
                snd.quest.target.mob,
                snd.quest.target.area
            )
        end
        
        snd.gmcp.addQuestToTargetList()
        snd.gmcp.registerQuestTargetTrigger()
        snd.gmcp.showQuestTargetDetails()
        if snd.setActiveTab and snd.getPreferredActiveActivity then
            snd.setActiveTab(snd.getPreferredActiveActivity() or "quest", {save = true, refresh = false})
        end
    end
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.gmcp.onQuestWarning(q)
    local time = tonumber(q.time) or 5
    snd.utils.infoNote("Quest warning: " .. time .. " minutes remaining!")
end

function snd.gmcp.showQuestTargetDetails()
    if not snd.quest.active or not snd.quest.target.mob or snd.quest.target.mob == "" then
        return
    end

    local areaKey = snd.quest.target.arid or ""
    if areaKey == "" and snd.quest.target.area and snd.quest.target.area ~= "" then
        areaKey = snd.db.getAreaKeyFromName(snd.quest.target.area) or ""
        snd.quest.target.arid = areaKey
    end

    local roomName = snd.utils.stripColors(snd.quest.target.room or "")

    cecho("\n<magenta>Your quest mob is:<reset>\n")
    cecho(string.format("<dim_gray>mob :<reset> %s\n", snd.quest.target.mob))
    if snd.quest.target.area and snd.quest.target.area ~= "" then
        cecho(string.format("<dim_gray>area:<reset> %s", snd.quest.target.area))
        if areaKey ~= "" then
            cecho(string.format(" (%s)", areaKey))
        end
        cecho("\n")
    end
    if roomName ~= "" then
        cecho(string.format("<dim_gray>room:<reset> %s\n", roomName))
    end

    if snd.mapper and snd.mapper.searchRoomsExact and roomName ~= "" then
        snd.mapper.searchRoomsExact(roomName, areaKey, snd.quest.target.mob)
    end
end

function snd.gmcp.onConfig()
    if not gmcp or not gmcp.config then
        return
    end
    
    local config = gmcp.config
    
    if config.noexp then
        snd.char.noexp = (config.noexp == "YES")
        snd.char.noexpPending = nil
        snd.utils.debugNote("config.noexp: " .. tostring(snd.char.noexp))
    end

    if snd.gui and snd.gui.updateNoexp then
        snd.gui.updateNoexp()
    end
end

-- Cutoff 0 intentionally leaves the player's manual noexp setting untouched.
function snd.gmcp.isAutoNoexpEnabled()
    local anex = snd.config and snd.config.anex
    return anex ~= nil
        and anex.automatic == true
        and (tonumber(anex.tnlCutoff) or 0) > 0
end

function snd.gmcp.setNoexp(enabled, message, managed)
    if not snd.char then
        return false
    end

    if not snd.gmcp.isAutoNoexpEnabled() then
        return false
    end

    local desired = enabled and "on" or "off"
    if snd.char.noexpPending or snd.char.noexp == enabled then
        return false
    end

    if managed ~= nil then
        snd.char.autoNoexpManaged = managed == true
    end
    snd.char.noexpPending = desired
    snd.char.noexpCommandEcho = desired
    snd.char.noexpCommandAt = os.clock()
    snd.char.noexp = enabled
    sendGMCP("config noexp " .. desired)

    if message and message ~= "" then
        snd.utils.infoNote(message)
    end
    if snd.gui and snd.gui.updateNoexp then
        snd.gui.updateNoexp()
    end
    return true
end

function snd.gmcp.checkAutoNoexp()
    if not snd.gmcp.isAutoNoexpEnabled() then
        return
    end

    local cutoff = tonumber(snd.config.anex.tnlCutoff) or 0
    local level = tonumber(snd.char.level) or 0
    local tnl = tonumber(snd.char.tnl) or 0
    local campaignStatus = tostring(snd.char.autoNoexpCampaignStatus or "unknown")
    local checkedLevel = tonumber(snd.char.autoNoexpCampaignLevel) or 0
    if campaignStatus == "active" then
        snd.char.autoNoexpCampaignStatus = "unknown"
        campaignStatus = "unknown"
    end

    -- GQ owns noexp; status updates must not undo it through the TNL cutoff.
    if snd.gquest and snd.gquest.active then
        snd.gmcp.setNoexp(true, "Search and Destroy: Turning noexp ON (global quest active)", true)
        return
    end

    if level >= 200 then
        snd.gmcp.setNoexp(false, "Search and Destroy: Turning noexp OFF (you have reached level " .. level .. ")", false)
        return
    end

    if campaignStatus == "blocked" and checkedLevel ~= level then
        snd.gmcp.requestCampaignEligibilityCheck()
        return
    end

    if campaignStatus == "unknown" then
        snd.gmcp.requestCampaignEligibilityCheck()
        return
    end

    if campaignStatus == "pending" then
        return
    end

    if campaignStatus ~= "eligible" then
        snd.gmcp.setNoexp(false, "Search and Destroy: Turning noexp OFF (you cannot take a campaign at this level yet)", false)
        return
    end

    if tnl < cutoff then
        snd.gmcp.setNoexp(true, "Search and Destroy: Turning noexp ON (your TNL is less than " .. cutoff .. ")", true)
    else
        snd.gmcp.setNoexp(false, "Search and Destroy: Turning noexp OFF (your TNL is greater than " .. cutoff .. ")", false)
    end
end

function snd.gmcp.setCampaignActiveForAutoNoexp()
    if not snd.char then
        return
    end

    snd.char.autoNoexpCampaignLevel = tonumber(snd.char.level) or 0
    snd.char.autoNoexpCampaignStatus = "unknown"

    if not snd.config.anex.automatic and not snd.char.autoNoexpManaged then
        return
    end

    snd.gmcp.setNoexp(false, "Search and Destroy: Turning noexp OFF (campaign accepted)", false)
end

function snd.gmcp.clearCampaignActiveForAutoNoexp()
    if not snd.char then
        return
    end

    if tostring(snd.char.autoNoexpCampaignStatus or "") == "active" then
        snd.char.autoNoexpCampaignStatus = "unknown"
        snd.char.autoNoexpCampaignLevel = tonumber(snd.char.level) or 0
    end
end

function snd.gmcp.requestCampaignEligibilityCheck()
    snd.char.autoNoexpCampaignStatus = "pending"
    snd.char.autoNoexpCampaignLevel = tonumber(snd.char.level) or 0
    send("cp today", false)
end

function snd.gmcp.setCampaignEligibility(canTakeCampaign)
    local level = tonumber(snd.char.level) or 0
    snd.char.autoNoexpCampaignLevel = level
    snd.char.autoNoexpCampaignStatus = canTakeCampaign and "eligible" or "blocked"

    if not canTakeCampaign then
        snd.gmcp.setNoexp(false, "Search and Destroy: Turning noexp OFF (you cannot take a campaign at this level yet)", false)
    end

    if snd.gmcp and snd.gmcp.checkAutoNoexp then
        snd.gmcp.checkAutoNoexp()
    end
end

function snd.gmcp.guessMobKeyword(mobName, areaKey)
    if not mobName or mobName == "" then
        return ""
    end
    
    areaKey = areaKey or snd.room.current.arid

    -- Prefer proper-name prefixes: "Devlin, the ..." becomes "devlin".
    local prefix = mobName:match("^%s*([^,]+),")
    if prefix and prefix ~= "" then
        local prefixWords = {}
        for word in prefix:gmatch("%S+") do
            word = word:gsub("[^%w'%-]", "")
            word = word:gsub("'s$", "")
            word = word:gsub("^'+", "")
            word = word:gsub("'+$", "")
            word = word:lower()
            if word ~= "" and not snd.data.keywordOmitWords[word] then
                table.insert(prefixWords, word)
            end
        end
        if #prefixWords > 0 then
            return prefixWords[#prefixWords]
        end
    end
    
    if areaKey and snd.data.mobKeywordExceptions[areaKey] then
        local function findMobException(name)
            if not name or name == "" then
                return nil
            end

            local exceptions = snd.data.mobKeywordExceptions[areaKey]
            local direct = exceptions[name]
            if direct then
                return direct
            end

            local lowerName = name:lower()
            for key, value in pairs(exceptions) do
                if key:lower() == lowerName then
                    return value
                end
            end

            return nil
        end

        local exception = findMobException(mobName)
        if not exception and mobName:find("%-") then
            exception = findMobException(mobName:gsub("%-", " "))
        end

        if exception then
            snd.utils.debugNote("Found keyword exception for '" .. mobName .. "': " .. exception)
            return exception
        end
    end
    
    if areaKey and snd.data.mobKeywordFilters[areaKey] then
        for _, filter in ipairs(snd.data.mobKeywordFilters[areaKey]) do
            local result = mobName:lower():gsub(filter.f, filter.g)
            if result and result ~= mobName:lower() then
                snd.utils.debugNote("Applied filter for '" .. mobName .. "': " .. result)
                return snd.utils.trim(result)
            end
        end
    end
    
    local words = {}
    for word in mobName:gmatch("%S+") do
        word = word:gsub("[^%w'%-]", "")
        word = word:gsub("'s$", "")
        word = word:gsub("^'+", "")
        word = word:gsub("'+$", "")
        word = word:lower()
        
        if not snd.data.keywordOmitWords[word] and word ~= "" then
            table.insert(words, word)
        end
    end
    
    if #words >= 2 then
        return words[#words - 1] .. " " .. words[#words]
    elseif #words == 1 then
        return words[1]
    else
        return snd.utils.findKeyword(mobName)
    end
end

function snd.gmcp.requestChar()
    sendGMCP("request char")
end

function snd.gmcp.requestRoom()
    sendGMCP("request room")
end

function snd.gmcp.requestQuest()
    sendGMCP("request quest")
end

