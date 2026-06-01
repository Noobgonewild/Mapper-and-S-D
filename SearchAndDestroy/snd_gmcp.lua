--[[
    Search and Destroy - GMCP Module
    Mudlet Port
    
    Original MUSHclient plugin by Crowley
    Ported to Mudlet
    
    This module handles all GMCP events:
    - char.status (player state)
    - room.info (room changes)
    - comm.quest (quest events)
    - config (noexp settings)
]]

snd = snd or {}
snd.gmcp = snd.gmcp or {}

local function clearQuestQuickWhereCache()
    if snd.nav and snd.nav.clearActivityQuickWhere then
        snd.nav.clearActivityQuickWhere("quest")
    end
end

local function sanitizeNomapPart(value)
    local cleaned = tostring(value or "?")
    cleaned = cleaned:gsub("\27%[[0-9;]*m", "")
    cleaned = cleaned:gsub("[%z\1-\8\11\12\14-\31]", "")
    cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then
        cleaned = "?"
    end
    return cleaned
end

local function buildNomapRoomId(name, zone)
    return "nomap_" .. sanitizeNomapPart(name) .. "_" .. sanitizeNomapPart(zone)
end

-- Store event handler IDs so we can unregister them
snd.gmcp.handlers = snd.gmcp.handlers or {}

-------------------------------------------------------------------------------
-- GMCP Handler Registration
-------------------------------------------------------------------------------

--- Register all GMCP event handlers
function snd.gmcp.registerHandlers()
    snd.utils.debugNote("Registering GMCP handlers...")
    
    -- Unregister any existing handlers first
    snd.gmcp.unregisterHandlers()
    
    -- char.status - player state changes
    snd.gmcp.handlers.charStatus = registerAnonymousEventHandler(
        "gmcp.char.status",
        snd.gmcp.onCharStatus
    )
    
    -- char.base - base character info (name, class, etc)
    snd.gmcp.handlers.charBase = registerAnonymousEventHandler(
        "gmcp.char.base",
        snd.gmcp.onCharBase
    )

    -- char.vitals - live vitals (hp/mana/moves), useful login-ready signal
    snd.gmcp.handlers.charVitals = registerAnonymousEventHandler(
        "gmcp.char.vitals",
        snd.gmcp.onCharVitals
    )
    
    -- room.info - room changes
    snd.gmcp.handlers.roomInfo = registerAnonymousEventHandler(
        "gmcp.room.info",
        snd.gmcp.onRoomInfo
    )
    
    -- comm.quest - quest events
    snd.gmcp.handlers.commQuest = registerAnonymousEventHandler(
        "gmcp.comm.quest",
        snd.gmcp.onCommQuest
    )
    
    -- config - configuration changes (like noexp)
    snd.gmcp.handlers.config = registerAnonymousEventHandler(
        "gmcp.config",
        snd.gmcp.onConfig
    )
    
    snd.utils.debugNote("GMCP handlers registered")
end

--- Unregister all GMCP event handlers
function snd.gmcp.unregisterHandlers()
    for name, handler in pairs(snd.gmcp.handlers) do
        if handler then
            killAnonymousEventHandler(handler)
        end
    end
    snd.gmcp.handlers = {}
end

-------------------------------------------------------------------------------
-- char.status Handler
-------------------------------------------------------------------------------

function snd.gmcp.onCharStatus()
    if not gmcp or not gmcp.char or not gmcp.char.status then
        return
    end
    
    local status = gmcp.char.status
    
    -- Update character state
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
    
    -- Check for state change
    if oldState ~= snd.char.state then
        snd.onStateChange()
    end

    if snd.char.state == "3" and snd.tryAutoOpenWindow then
        snd.tryAutoOpenWindow()
    end
    
    -- Auto noexp check (if below level 200)
    if snd.char.level < 200 and snd.config.anex.automatic then
        snd.gmcp.checkAutoNoexp()
    end
    
    snd.utils.debugNote("char.status - state: " .. snd.char.state .. ", level: " .. snd.char.level)
end

-------------------------------------------------------------------------------
-- char.base Handler
-------------------------------------------------------------------------------

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


-------------------------------------------------------------------------------
-- char.vitals Handler
-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------
-- room.info Handler
-------------------------------------------------------------------------------

function snd.gmcp.onRoomInfo()
    if not gmcp or not gmcp.room or not gmcp.room.info then
        return
    end
    
    local ri = gmcp.room.info
    
    -- Store previous room
    snd.room.previous = snd.utils.deepcopy(snd.room.current)
    
    -- Parse maze flag from details
    local isMaze = 0
    if ri.details and type(ri.details) == "string" then
        if ri.details:match("maze") then
            isMaze = 1
        end
    end
    
    -- Update current room
    snd.room.current = {
        rmid = (tonumber(ri.num) == -1)
                    and buildNomapRoomId(ri.name, ri.zone or ri.area)
                    or tostring(ri.num or "-1"),
        arid = ri.zone or "",
        exits = ri.exits or {},
        maze = isMaze,
        name = ri.name or "",
        terrain = ri.terrain or "",
    }

    -- Only process if room actually changed
    if snd.room.current.rmid ~= snd.room.previous.rmid then
        -- Defensive init in case state restore or load order omits room history.
        snd.room.history = snd.room.history or {}
        -- Room history tracking is intentionally disabled for now.
        -- Keep original logic commented so it can be re-enabled quickly if needed.
        -- if #snd.room.history >= 300 then
        --     table.remove(snd.room.history, 300)
        -- end
        -- table.insert(snd.room.history, 1, {
        --     rmid = snd.room.previous.rmid,
        --     arid = snd.room.previous.arid,
        -- })

        if snd.mapper then
            local navigating = (snd.nav.goingToRoom or snd.mapper.goingToRoom) ~= nil
            if navigating then
                if snd.mapper.bufferRoomPersist then
                    snd.mapper.bufferRoomPersist(ri)
                end
            else
                -- Not navigating: flush any orphaned buffer then persist immediately.
                if snd.mapper.flushPendingPersists then
                    snd.mapper.flushPendingPersists()
                end
                if snd.mapper.persistDiscoveredRoom then
                    snd.mapper.persistDiscoveredRoom(ri)
                end
            end
        end

        -- Notify main module of room change
        snd.onRoomChange()
        
        snd.utils.debugNote("room.info - room: " .. snd.room.current.rmid .. 
                          ", area: " .. snd.room.current.arid ..
                          ", name: " .. snd.room.current.name)
    end
end

-------------------------------------------------------------------------------
-- comm.quest Handler
-------------------------------------------------------------------------------

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
        -- New quest started
        snd.gmcp.onQuestStart(q)
        
    elseif action == "killed" then
        -- Quest target killed
        snd.gmcp.onQuestKilled(q)
        
    elseif action == "comp" then
        -- Quest completed
        snd.gmcp.onQuestComplete(q)
        
    elseif action == "fail" then
        -- Quest failed
        snd.gmcp.onQuestFail(q)
        
    elseif action == "timeout" then
        -- Quest timed out
        snd.gmcp.onQuestTimeout(q)
        
    elseif action == "ready" then
        -- Can quest again
        snd.gmcp.onQuestReady(q)
        
    elseif action == "reset" then
        -- Quest reset (qreset)
        snd.gmcp.onQuestReset(q)
        
    elseif action == "status" then
        -- Response to "request quest"
        snd.gmcp.onQuestStatus(q)
        
    elseif action == "warning" then
        -- Quest time warning
        snd.gmcp.onQuestWarning(q)
    end
end

--- Returns cooldown wait minutes from a quest payload if present.
-- @param q GMCP comm.quest payload table
-- @return number|nil wait minutes if present and valid
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

--- Quest started
function snd.gmcp.onQuestStart(q)
    if snd.db then
        snd.db.historyStart(snd.db.HISTORY_TYPE_QUEST, snd.char.level or 0)
    end

    snd.quest.active = true
    snd.quest.available = false
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
    
    -- Guess keyword for the target
    if snd.quest.target.mob ~= "" then
        snd.quest.target.keyword = snd.gmcp.guessMobKeyword(
            snd.quest.target.mob,
            snd.quest.target.area
        )
    end
    
    -- Add quest target to target list for xcp display
    snd.gmcp.addQuestToTargetList()
    snd.gmcp.registerQuestTargetTrigger()

    snd.gmcp.showQuestTargetDetails()
    
    snd.utils.infoNote("Quest started: " .. snd.quest.target.mob ..
                       " in " .. snd.quest.target.area)
    if snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "quest", {save = true, refresh = false})
    end
    
    -- Refresh GUI
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

--- Add current quest to target list
function snd.gmcp.addQuestToTargetList()
    if not snd.quest.active or not snd.quest.target.mob or snd.quest.target.mob == "" then
        return
    end
    
    -- Remove any existing quest targets first
    snd.gmcp.removeQuestFromTargetList()
    
    -- Look up area key from area name
    local areaKey = snd.quest.target.arid or ""
    if areaKey == "" and snd.quest.target.area and snd.quest.target.area ~= "" then
        areaKey = snd.db.getAreaKeyFromName(snd.quest.target.area) or ""
        snd.quest.target.arid = areaKey
    end
    
    -- Create target entry
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
    
    -- Find insertion position: after GQ targets, before CP targets
    -- Priority: GQ > Quest > CP
    local insertPos = 1
    for i, t in ipairs(snd.targets.list) do
        if t.activity == "gq" then
            insertPos = i + 1  -- Insert after this GQ target
        else
            break  -- Found non-GQ target, insert here
        end
    end
    
    table.insert(snd.targets.list, insertPos, target)
    
    -- Auto-select quest target (unless GQ is active)
    if not snd.gquest.active then
        snd.targets.current = target
    end
    
    snd.utils.debugNote("Added quest target to list at position " .. insertPos .. ": " .. target.mob)
end

--- Register a trigger to tag quest target lines
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

--- Unregister quest target line trigger
function snd.gmcp.unregisterQuestTargetTrigger()
    if snd.quest and snd.quest.targetTriggerId then
        killTrigger(snd.quest.targetTriggerId)
        snd.quest.targetTriggerId = nil
    end
end

--- Remove quest targets from list
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

--- Quest target killed
function snd.gmcp.onQuestKilled(q)
    snd.quest.target.status = "killed"
    snd.quest.timer = tonumber(q.time) or 0
    
    -- Mark quest target as dead in target list
    for _, target in ipairs(snd.targets.list) do
        if target.activity == "quest" then
            target.dead = true
        end
    end
    
    snd.utils.infoNote("Quest target killed!")

    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

--- Quest completed
function snd.gmcp.onQuestComplete(q)
    local qp = tonumber(q.qp) or 0
    local gold = tonumber(q.gold) or 0
    local tp = tonumber(q.tp) or 0
    local trains = tonumber(q.trains) or 0
    local pracs = tonumber(q.pracs) or 0

    snd.gmcp.queueQuestReward(qp, gold, tp, trains, pracs)
    
    snd.quest.active = false
    snd.quest.available = false
    snd.quest.timerEndTime = 0
    if snd.gui and snd.gui.stopQuestTimer then
        snd.gui.stopQuestTimer()
    end
    snd.quest.target = {mob = "", area = "", room = "", keyword = "", status = "0"}
    snd.quest.setCooldown(q.wait)
    clearQuestQuickWhereCache()
    
    -- Remove quest from target list
    snd.gmcp.removeQuestFromTargetList()
    
    -- Clear current target if it was the quest
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

--- Queue quest completion reward output (accounts for tier/blessing bonuses)
function snd.gmcp.queueQuestReward(qp, gold, tp, trains, pracs)
    local tierBonus = snd.char and snd.char.tier or 0
    snd.quest.blessingBonus = 0
    snd.quest.extraBonus = 0

    snd.quest.pendingReward = {
        qp = qp + tierBonus,
        gold = gold,
        tp = tp,
        trains = trains,
        pracs = pracs,
        tierBonus = tierBonus,
    }

    if snd.quest.rewardTimer then
        killTimer(snd.quest.rewardTimer)
        snd.quest.rewardTimer = nil
    end

    snd.quest.rewardTimer = tempTimer(1, function()
        snd.gmcp.emitQuestReward()
    end)
end

--- Emit quest reward output with any pending bonuses
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

    if snd.db then
        local endedHistory = snd.db.historyEnd(snd.db.HISTORY_TYPE_QUEST, snd.db.HISTORY_STATUS_COMPLETE, {
            qp = totalQp,
            gold = gold,
            tp = tp,
            trains = trains,
            pracs = pracs,
        })
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

--- Quest failed
function snd.gmcp.onQuestFail(q)
    snd.utils.infoNote("Quest failed!")
    if snd.db then
        snd.db.historyEnd(snd.db.HISTORY_TYPE_QUEST, snd.db.HISTORY_STATUS_FAILED)
    end
    
    snd.quest.active = false
    snd.quest.available = false
    snd.quest.timerEndTime = 0
    if snd.gui and snd.gui.stopQuestTimer then
        snd.gui.stopQuestTimer()
    end
    snd.quest.target = {mob = "", area = "", room = "", keyword = "", status = "0"}
    snd.quest.setCooldown(q.wait)
    clearQuestQuickWhereCache()
    
    -- Remove quest from target list
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

--- Quest timed out
function snd.gmcp.onQuestTimeout(q)
    snd.utils.infoNote("Quest timed out!")
    if snd.db then
        snd.db.historyEnd(snd.db.HISTORY_TYPE_QUEST, snd.db.HISTORY_STATUS_TIMEOUT)
    end
    
    snd.quest.active = false
    snd.quest.available = false
    snd.quest.timerEndTime = 0
    if snd.gui and snd.gui.stopQuestTimer then
        snd.gui.stopQuestTimer()
    end
    snd.quest.target = {mob = "", area = "", room = "", keyword = "", status = "0"}
    snd.quest.setCooldown(q.wait)
    clearQuestQuickWhereCache()
    
    -- Remove quest from target list
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

--- Can quest again
function snd.gmcp.onQuestReady(q)
    snd.quest.setCooldown(0)
    snd.quest.nextQuestText = "Quest Available"
    snd.quest.available = true
    snd.quest.timerEndTime = 0
    if snd.gui and snd.gui.stopQuestTimer then
        snd.gui.stopQuestTimer()
    end
    snd.gmcp.unregisterQuestTargetTrigger()
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

--- Quest reset
function snd.gmcp.onQuestReset(q)
    if snd.db then
        snd.db.historyEnd(snd.db.HISTORY_TYPE_QUEST, snd.db.HISTORY_STATUS_RESET)
    end

    snd.quest.setCooldown(q.timer)
    snd.quest.available = false
    snd.quest.timerEndTime = 0
    if snd.gui and snd.gui.stopQuestTimer then
        snd.gui.stopQuestTimer()
    end
    clearQuestQuickWhereCache()
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

--- Quest status (response to request quest)
function snd.gmcp.onQuestStatus(q)
    local waitMinutes = snd.gmcp.getQuestWaitMinutes(q)
    local status = type(q.status) == "string" and q.status:lower() or q.status

    if waitMinutes and waitMinutes > 0 then
        snd.quest.active = false
        snd.quest.available = false
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
    elseif status == "ready" then
        snd.quest.active = false
        snd.quest.setCooldown(0)
        snd.quest.nextQuestText = "Quest Available"
        snd.quest.available = true
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
        -- On quest but target is missing
        snd.quest.active = true
        snd.quest.available = false
        snd.quest.target.status = "missing"
        snd.quest.timer = tonumber(q.timer) or 0
        snd.quest.setCooldown(0)
    elseif q.target == "killed" then
        -- On quest, target killed, waiting to return
        snd.quest.active = true
        snd.quest.available = false
        snd.quest.target.status = "killed"
        snd.quest.timer = tonumber(q.time) or 0
        snd.quest.setCooldown(0)
        -- Mark as dead in list
        for _, target in ipairs(snd.targets.list) do
            if target.activity == "quest" then
                target.dead = true
            end
        end
    elseif q.targ then
        -- Currently on a quest
        snd.quest.active = true
        snd.quest.available = false
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
        
        -- Guess keyword
        if snd.quest.target.mob ~= "" then
            snd.quest.target.keyword = snd.gmcp.guessMobKeyword(
                snd.quest.target.mob,
                snd.quest.target.area
            )
        end
        
        -- Add quest to target list
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

--- Quest time warning
function snd.gmcp.onQuestWarning(q)
    local time = tonumber(q.time) or 5
    snd.utils.infoNote("Quest warning: " .. time .. " minutes remaining!")
end

-------------------------------------------------------------------------------
-- Quest Target Display
-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------
-- config Handler
-------------------------------------------------------------------------------

function snd.gmcp.onConfig()
    if not gmcp or not gmcp.config then
        return
    end
    
    local config = gmcp.config
    
    -- Check noexp setting
    if config.noexp then
        snd.char.noexp = (config.noexp == "YES")
        snd.char.noexpPending = nil
        snd.utils.debugNote("config.noexp: " .. tostring(snd.char.noexp))
    end

    if snd.gui and snd.gui.updateNoexp then
        snd.gui.updateNoexp()
    end
end

-------------------------------------------------------------------------------
-- Auto Noexp Check
-------------------------------------------------------------------------------

function snd.gmcp.setNoexp(enabled, message, managed)
    if not snd.char then
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
    if not snd.config.anex.automatic then
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

    -- Levels 200+ should always have noexp off (mirrors original behavior).
    if level >= 200 then
        snd.gmcp.setNoexp(false, "Search and Destroy: Turning noexp OFF (you have reached level " .. level .. ")", false)
        return
    end

    -- Cutoff 0 means automatic noexp is disabled.
    if cutoff <= 0 then
        snd.gmcp.setNoexp(false, "Search and Destroy: Turning noexp OFF (auto noexp is disabled)", false)
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

--- Release noexp after a campaign is accepted and re-check eligibility next time.
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

--- Clear legacy active campaign eligibility state.
function snd.gmcp.clearCampaignActiveForAutoNoexp()
    if not snd.char then
        return
    end

    if tostring(snd.char.autoNoexpCampaignStatus or "") == "active" then
        snd.char.autoNoexpCampaignStatus = "unknown"
        snd.char.autoNoexpCampaignLevel = tonumber(snd.char.level) or 0
    end
end

--- Request campaign eligibility confirmation for auto-noexp logic.
function snd.gmcp.requestCampaignEligibilityCheck()
    snd.char.autoNoexpCampaignStatus = "pending"
    snd.char.autoNoexpCampaignLevel = tonumber(snd.char.level) or 0
    send("cp today", false)
end

--- Set campaign eligibility state used by auto-noexp logic.
-- @param canTakeCampaign boolean True when campaign can be taken at this level.
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

-------------------------------------------------------------------------------
-- Mob Keyword Guessing
-------------------------------------------------------------------------------

--- Guess the best keyword for a mob
-- @param mobName Full mob name
-- @param areaKey Area key (optional, for area-specific exceptions)
-- @return Best keyword to use
function snd.gmcp.guessMobKeyword(mobName, areaKey)
    if not mobName or mobName == "" then
        return ""
    end
    
    areaKey = areaKey or snd.room.current.arid

    -- Prefer proper-name prefix for titles like:
    -- "Devlin, the Queen's bodyguard" -> "devlin"
    -- "Meilath, the elven ranger" -> "meilath"
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
    
    -- Check for area-specific exceptions first
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
    
    -- Check for area-specific filters
    if areaKey and snd.data.mobKeywordFilters[areaKey] then
        for _, filter in ipairs(snd.data.mobKeywordFilters[areaKey]) do
            local result = mobName:lower():gsub(filter.f, filter.g)
            if result and result ~= mobName:lower() then
                snd.utils.debugNote("Applied filter for '" .. mobName .. "': " .. result)
                return snd.utils.trim(result)
            end
        end
    end
    
    -- Default keyword guessing
    local words = {}
    for word in mobName:gmatch("%S+") do
        -- Clean up the word (keep interior apostrophes)
        word = word:gsub("[^%w'%-]", "")
        word = word:gsub("'s$", "")
        word = word:gsub("^'+", "")
        word = word:gsub("'+$", "")
        word = word:lower()
        
        -- Skip common articles/words
        if not snd.data.keywordOmitWords[word] and word ~= "" then
            table.insert(words, word)
        end
    end
    
    -- Return last two significant words as keyword
    if #words >= 2 then
        return words[#words - 1] .. " " .. words[#words]
    elseif #words == 1 then
        return words[1]
    else
        -- Fallback to first significant part of name
        return snd.utils.findKeyword(mobName)
    end
end

-------------------------------------------------------------------------------
-- Request GMCP Data
-------------------------------------------------------------------------------

--- Request character data
function snd.gmcp.requestChar()
    sendGMCP("request char")
end

--- Request room data
function snd.gmcp.requestRoom()
    sendGMCP("request room")
end

--- Request quest status
function snd.gmcp.requestQuest()
    sendGMCP("request quest")
end

-- Module loaded silently
