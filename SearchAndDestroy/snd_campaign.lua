snd = snd or {}
snd.cp = snd.cp or {}

snd.cp.parsing = {
    infoActive = false,
    checkActive = false,
    tempTargets = {},
    capturedCompleteBy = "",
    capturedTimeLeftSeconds = nil,
    completionPending = false,
    completionSeparatorsSeen = 0,
    completionTimer = nil,
    completionStartCompletedToday = nil,
}
snd.cp.pendingResetClose = snd.cp.pendingResetClose or nil
snd.cp.pendingResetCloseTimer = snd.cp.pendingResetCloseTimer or nil
snd.cp.forceResolveNextCheck = snd.cp.forceResolveNextCheck or false

local CP_COMPLETION_BONUS_WAIT = 0.5

function snd.cp.requestCheck(delay, reason, force)
    local now = os.clock()
    local minInterval = 0.75

    if not force and snd.cp.lastCheckRequestAt and (now - snd.cp.lastCheckRequestAt) < minInterval then
        return false
    end

    if snd.cp.pendingCheckTimer then
        pcall(function() killTimer(snd.cp.pendingCheckTimer) end)
        snd.cp.pendingCheckTimer = nil
    end

    local wait = tonumber(delay) or 0
    local debugReason = reason or "unspecified"
    snd.cp.pendingCheckTimer = tempTimer(wait, function()
        snd.cp.pendingCheckTimer = nil
        snd.cp.lastCheckRequestAt = os.clock()
        snd.utils.debugNote(string.format("Sending 'cp check' (reason: %s, delay: %.2f)", debugReason, wait))
        send("cp check", false)
    end)
    return true
end

function snd.cp.requestResolveCheck(delay, reason)
    snd.cp.forceResolveNextCheck = true
    return snd.cp.requestCheck(delay, reason or "forced CP resolution", true)
end

-- Reattach paths share one request to avoid duplicate full campaign tables.
function snd.cp.requestInfo(delay, reason, force)
    local now = os.clock()
    local minInterval = 2.0

    if not force and snd.cp.lastInfoRequestAt and (now - snd.cp.lastInfoRequestAt) < minInterval then
        return false
    end
    if not force and snd.cp.pendingInfoTimer then
        return false
    end
    if force and snd.cp.pendingInfoTimer then
        pcall(function() killTimer(snd.cp.pendingInfoTimer) end)
        snd.cp.pendingInfoTimer = nil
    end

    local wait = tonumber(delay) or 0
    local debugReason = reason or "unspecified"
    if wait <= 0 then
        snd.cp.lastInfoRequestAt = now
        snd.utils.debugNote(string.format("Sending 'cp info' (reason: %s, delay: %.2f)", debugReason, wait))
        send("cp info", false)
        return true
    end
    snd.cp.pendingInfoTimer = tempTimer(wait, function()
        snd.cp.pendingInfoTimer = nil
        snd.cp.lastInfoRequestAt = os.clock()
        snd.utils.debugNote(string.format("Sending 'cp info' (reason: %s, delay: %.2f)", debugReason, wait))
        send("cp info", false)
    end)
    return true
end

function snd.cp.normalizeCompleteBy(value)
    local normalized = snd.utils.trim(tostring(value or ""))
    normalized = normalized:gsub("^%[", ""):gsub("%]$", "")
    normalized = snd.utils.trim(normalized)
    return normalized
end

function snd.cp.parseCompleteByEpoch(completeBy)
    local text = snd.cp.normalizeCompleteBy(completeBy)
    if text == "" then
        return nil
    end

    local hour12, minute, ampm, day, monthAbbr, year = text:match("^(%d%d?):(%d%d)%s*([AP]M)%s+on%s+(%d%d?)%s+([A-Za-z]+)%s+(%d%d%d%d)$")
    if not hour12 then
        return nil
    end

    local months = {
        jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
        jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12,
    }
    local month = months[(monthAbbr or ""):sub(1, 3):lower()]
    if not month then
        return nil
    end

    local h = tonumber(hour12) or 0
    local m = tonumber(minute) or 0
    local d = tonumber(day) or 0
    local y = tonumber(year) or 0
    local period = tostring(ampm or ""):upper()

    if h < 1 or h > 12 or m < 0 or m > 59 or d < 1 or d > 31 or y < 1970 then
        return nil
    end

    if period == "PM" and h < 12 then
        h = h + 12
    elseif period == "AM" and h == 12 then
        h = 0
    end

    return os.time({
        year = y,
        month = month,
        day = d,
        hour = h,
        min = m,
        sec = 0,
    })
end

function snd.cp.captureCompleteBy(value)
    local normalized = snd.cp.normalizeCompleteBy(value)
    if normalized == "" then
        return
    end
    snd.cp.parsing.capturedCompleteBy = normalized
    snd.utils.debugNote("CP complete-by captured: " .. normalized)
end

function snd.cp.parseTimeLeftSeconds(value)
    local text = tostring(value or ""):lower()
    if text == "" then
        return nil
    end

    local days = tonumber(text:match("(%d+)%s+day")) or 0
    local hours = tonumber(text:match("(%d+)%s+hour")) or 0
    local minutes = tonumber(text:match("(%d+)%s+minute")) or 0
    local seconds = tonumber(text:match("(%d+)%s+second")) or 0

    local total = (days * 86400) + (hours * 3600) + (minutes * 60) + seconds
    if total <= 0 then
        return nil
    end
    return total
end

function snd.cp.captureTimeLeft(value)
    local totalSeconds = snd.cp.parseTimeLeftSeconds(value)
    if not totalSeconds then
        return
    end
    snd.cp.parsing.capturedTimeLeftSeconds = totalSeconds
    snd.utils.debugNote("CP time-left captured (seconds): " .. tostring(totalSeconds))
end

local function statusIsInProgress(status)
    local s = tonumber(status) or 0
    return s == snd.db.HISTORY_STATUS_INPROGRESS or s == 0
end

local function persistedRewardsSnapshot()
    return {
        qp = tonumber(snd.campaign.persistedQpReward) or 0,
        gold = tonumber(snd.campaign.persistedGoldReward) or 0,
        tp = tonumber(snd.campaign.persistedTpReward) or 0,
        trains = tonumber(snd.campaign.persistedTrainReward) or 0,
        pracs = tonumber(snd.campaign.persistedPracReward) or 0,
    }
end

local function rowRewardsMatch(row, rewards)
    if not row then return false end
    rewards = rewards or {}
    return (tonumber(row.qp_rewards) or 0) == (tonumber(rewards.qp) or 0) and
        (tonumber(row.gold_rewards) or 0) == (tonumber(rewards.gold) or 0) and
        (tonumber(row.tp_rewards) or 0) == (tonumber(rewards.tp) or 0) and
        (tonumber(row.train_rewards) or 0) == (tonumber(rewards.trains) or 0) and
        (tonumber(row.prac_rewards) or 0) == (tonumber(rewards.pracs) or 0)
end

local function cancelCompletionTimer()
    if snd.cp.parsing.completionTimer and type(killTimer) == "function" then
        pcall(function() killTimer(snd.cp.parsing.completionTimer) end)
    end
    snd.cp.parsing.completionTimer = nil
end

local function rewardValue(currentValue, row, rowField)
    local value = tonumber(currentValue) or 0
    if value <= 0 and row then
        value = tonumber(row[rowField]) or value
    end
    return value
end

local function buildCompletionRewards(row)
    local baseQp = rewardValue(snd.campaign.qpReward, row, "qp_rewards")
    local dailyQpBonus = tonumber(snd.campaign.dailyQpBonus) or 0

    return {
        qp = baseQp + dailyQpBonus,
        baseQp = baseQp,
        dailyQpBonus = dailyQpBonus,
        gold = rewardValue(snd.campaign.goldReward, row, "gold_rewards"),
        tp = rewardValue(snd.campaign.tpReward, row, "tp_rewards"),
        trains = rewardValue(snd.campaign.trainReward, row, "train_rewards"),
        pracs = rewardValue(snd.campaign.pracReward, row, "prac_rewards"),
    }
end

function snd.cp.persistCampaignIdentitySnapshot(completeBy)
    snd.campaign.persistedCompleteBy = snd.cp.normalizeCompleteBy(completeBy)
    snd.campaign.persistedQpReward = tonumber(snd.campaign.qpReward) or 0
    snd.campaign.persistedGoldReward = tonumber(snd.campaign.goldReward) or 0
    snd.campaign.persistedTpReward = tonumber(snd.campaign.tpReward) or 0
    snd.campaign.persistedTrainReward = tonumber(snd.campaign.trainReward) or 0
    snd.campaign.persistedPracReward = tonumber(snd.campaign.pracReward) or 0
end

function snd.cp.hasOpenHistorySession()
    return snd.campaign.completeBy ~= nil and snd.campaign.completeBy ~= ""
end

function snd.cp.resolveHistoryIdByCompleteBy()
    if not snd.db or not snd.db.getHistoryIdByCompleteBy then
        return nil
    end
    local completeBy = snd.cp.normalizeCompleteBy(snd.campaign.completeBy)
    if completeBy == "" then
        return nil
    end
    local historyId = snd.db.getHistoryIdByCompleteBy(completeBy)
    if historyId then
        snd.campaign.historyId = tonumber(historyId) or 0
    end
    return tonumber(historyId)
end

-- Unknown closures get one delayed cp-info reattach attempt before reset.
function snd.cp.closeHistorySession(status, rewards, reason, opts)
    if not snd.db then
        return nil
    end

    local options = opts or {}
    local historyId = tonumber(options.forceHistoryId) or snd.cp.resolveHistoryIdByCompleteBy()
    if not historyId then
        local s = tonumber(status) or 0
        local shouldProbe = (not options.skipReattachProbe) and
            (s == snd.db.HISTORY_STATUS_RESET or s == snd.db.HISTORY_STATUS_UNDOCUMENTED)

        if shouldProbe then
            snd.cp.pendingResetClose = {
                status = status,
                rewards = rewards,
                reason = reason,
            }

            if snd.cp.pendingResetCloseTimer then
                pcall(function() killTimer(snd.cp.pendingResetCloseTimer) end)
                snd.cp.pendingResetCloseTimer = nil
            end

            snd.utils.debugNote("closeHistorySession: unresolved campaign history id, requesting 'cp info' and retrying in 2s")
            snd.cp.requestInfo(0, "closeHistorySession:reattach", true)
            snd.cp.pendingResetCloseTimer = tempTimer(2, function()
                snd.cp.pendingResetCloseTimer = nil
                local pending = snd.cp.pendingResetClose
                snd.cp.pendingResetClose = nil
                if not pending then
                    return
                end
                snd.cp.closeHistorySession(pending.status, pending.rewards, pending.reason, {skipReattachProbe = true})
            end)
            return nil
        end

        snd.utils.debugNote("closeHistorySession skipped: no tracked campaign history id")
        return nil
    end

    snd.cp.pendingResetClose = nil
    if snd.cp.pendingResetCloseTimer then
        pcall(function() killTimer(snd.cp.pendingResetCloseTimer) end)
        snd.cp.pendingResetCloseTimer = nil
    end

    local endedHistory = nil
    if snd.db.historyEndById then
        endedHistory = snd.db.historyEndById(historyId, status, rewards)
        if reason and reason ~= "" then
            snd.utils.debugNote("Closed campaign history id " .. tostring(historyId) .. " (" .. reason .. ")")
        end
    end

    snd.campaign.historyId = 0
    snd.campaign.completeBy = ""
    snd.campaign.acceptedAt = 0
    if snd.saveState then
        snd.saveState()
    end
    return endedHistory
end

function snd.cp.openHistorySession(levelTaken, completeBy)
    if not snd.db then
        return
    end

    local normalizedCompleteBy = snd.cp.normalizeCompleteBy(completeBy)
    if normalizedCompleteBy == "" then
        snd.utils.debugNote("openHistorySession skipped: Complete-By not captured yet")
        snd.campaign.completeBy = ""
        snd.cp.requestInfo(0, "openHistorySession:missing-complete-by")
        return
    end

    local previousPersisted = snd.cp.normalizeCompleteBy(snd.campaign.persistedCompleteBy)
    if previousPersisted ~= "" and previousPersisted ~= normalizedCompleteBy and
        snd.db.getHistoryIdByCompleteBy and snd.db.getHistoryById and snd.db.historyEndById then
        local previousId = snd.db.getHistoryIdByCompleteBy(previousPersisted)
        local previousRow = previousId and snd.db.getHistoryById(previousId) or nil
        if previousRow and statusIsInProgress(previousRow.status) then
            snd.db.historyEndById(previousId, snd.db.HISTORY_STATUS_UNDOCUMENTED or snd.db.HISTORY_STATUS_RESET, nil)
            snd.utils.debugNote(
                "Closed in-progress campaign id " .. tostring(previousId) ..
                " due to Complete-By mismatch (persisted '" .. previousPersisted ..
                "' vs current '" .. normalizedCompleteBy .. "')"
            )
        end
    end

    snd.cp.persistCampaignIdentitySnapshot(normalizedCompleteBy)

    local historyId = nil
    if snd.db.getHistoryIdByCompleteBy then
        local mappedId = snd.db.getHistoryIdByCompleteBy(normalizedCompleteBy)
        if mappedId and snd.db.getHistoryById then
            local mappedRow = snd.db.getHistoryById(mappedId)
            if mappedRow and statusIsInProgress(mappedRow.status) then
                historyId = tonumber(mappedId)
            end
        end
    end

    if not historyId then
        local acceptedAt = tonumber(snd.campaign.acceptedAt) or 0
        historyId = snd.db.historyStart(
            snd.db.HISTORY_TYPE_CAMPAIGN,
            levelTaken or snd.char.level or 0,
            acceptedAt > 0 and acceptedAt or nil
        )
    end

    snd.campaign.historyId = tonumber(historyId) or 0
    snd.campaign.completeBy = normalizedCompleteBy
    if snd.campaign.historyId > 0 and snd.db.upsertCampaignIdentity then
        snd.db.upsertCampaignIdentity(normalizedCompleteBy, snd.campaign.historyId)
    end
    snd.cp.syncHistoryRewards()
    snd.utils.debugNote("Campaign identity persisted for Complete-By " .. tostring(normalizedCompleteBy))

    if snd.saveState then
        snd.saveState()
    end
end

function snd.cp.syncHistoryRewards()
    if not snd.db or not snd.db.historyUpdateRewardsById then
        return
    end
    local historyId = snd.cp.resolveHistoryIdByCompleteBy()
    if not historyId then
        return
    end
    snd.db.historyUpdateRewardsById(historyId, {
        qp = snd.campaign.qpReward,
        tp = snd.campaign.tpReward,
        trains = snd.campaign.trainReward,
        pracs = snd.campaign.pracReward,
        gold = snd.campaign.goldReward,
    })
end


function snd.cp.parseMobTarget(targetStr)
    if not targetStr then return nil, nil end
    
    local mob, loc = targetStr:match("^(.+) %((.+)%)$")
    
    if not mob then
        mob = targetStr
        loc = ""
    end
    
    mob = snd.utils.trim(mob)
    loc = snd.utils.trim(loc or "")
    
    local isDead = false
    if loc:match(" %- Dead$") then
        isDead = true
        loc = loc:gsub(" %- Dead$", "")
    end
    
    return mob, loc, isDead
end

function snd.cp.startCpInfo()
    snd.cp.parsing.infoActive = true
    snd.cp.parsing.tempTargets = {}
    snd.cp.parsing.capturedCompleteBy = ""
    snd.cp.parsing.capturedTimeLeftSeconds = nil
    snd.campaign.qpReward = 0
    snd.campaign.goldReward = 0
    snd.campaign.tpReward = 0
    snd.campaign.trainReward = 0
    snd.campaign.pracReward = 0
    snd.campaign.levelTaken = tonumber(snd.char and snd.char.level) or 0
    snd.utils.debugNote("Started parsing cp info")
end

function snd.cp.processCpInfoLine(targetStr)
    if not snd.cp.parsing.infoActive then return end
    
    local mob, loc, isDead = snd.cp.parseMobTarget(targetStr)
    if not mob then return end
    
    local areaKey = ""
    if loc and loc ~= "" and snd.db and snd.db.getAreaKeyFromName then
        areaKey = snd.db.getAreaKeyFromName(loc) or ""
    end
    
    local target = {
        mob = mob,
        loc = loc,           -- Area display name
        arid = areaKey,      -- Area key for navigation
        roomName = "",
        dead = isDead,
        index = #snd.cp.parsing.tempTargets + 1,
        keyword = snd.gmcp.guessMobKeyword(mob, areaKey),
    }
    
    table.insert(snd.cp.parsing.tempTargets, target)
    snd.utils.debugNote("CP target: " .. mob .. " in " .. loc .. " (key: " .. areaKey .. ")")
end

function snd.cp.endCpInfo()
    if not snd.cp.parsing.infoActive then return end
    
    snd.cp.parsing.infoActive = false
    local wasActive = snd.campaign.active

    local hasCompleteBy = snd.cp.normalizeCompleteBy(snd.cp.parsing.capturedCompleteBy) ~= ""
    if snd.db and ((snd.campaign.active and not wasActive) or hasCompleteBy) then
        snd.cp.openHistorySession(snd.char.level or 0, snd.cp.parsing.capturedCompleteBy)
    end

    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end

    snd.utils.debugNote("CP info complete. Target list unchanged (cp check is sole S&D target source).")
    if snd.campaign.active and snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "cp", {save = true, refresh = false})
    end
end

function snd.cp.startCpCheck()
    snd.cp.parsing.checkActive = true
    snd.cp.parsing.tempTargets = {}
    snd.campaign.checkList = {}
    -- Do not inherit stale navigation state into a cp-check refresh.
    if snd.nav then
        snd.nav.nxState = nil
    end
end

function snd.cp.processCpCheckLine(targetStr)
    if not snd.cp.parsing.checkActive then return end
    
    local mob, loc, isDead = snd.cp.parseMobTarget(targetStr)
    if not mob then return end
    
    table.insert(snd.campaign.checkList, {
        mob = mob,
        loc = loc,
        dead = isDead,
    })
end

function snd.cp.endCpCheck()
    snd.cp.parsing.checkActive = false
    snd.campaign.lastCheck = os.clock()
    local wasActive = snd.campaign.active
    
    local forceResolve = snd.cp.forceResolveNextCheck == true
    snd.cp.forceResolveNextCheck = false
    if #snd.campaign.checkList > 0 then
        local statusOnlyApplied = false
        if snd.campaign.resolved and not forceResolve and snd.cp.applyCheckStatusOnly then
            local ok, reason = snd.cp.applyCheckStatusOnly()
            statusOnlyApplied = ok == true
            if not statusOnlyApplied then
                snd.utils.debugNote("CP status-only refresh fell back to full resolution: " .. tostring(reason or "unknown"))
            end
        end
        if not statusOnlyApplied then
            snd.utils.debugNote(forceResolve and "Force rebuilding CP target resolution" or "Building target list from cp check results")
            snd.cp.buildTargetListFromCheck()
        else
            snd.utils.debugNote("Updated CP target status without rebuilding location resolution")
        end
    end

    if snd.campaign.active and not wasActive and snd.db then
        snd.cp.openHistorySession(snd.char.level or 0)
    end

    if snd.campaign.active and not wasActive and snd.config.autocheck then
        snd.config.autocheck.cpKillCounter = 0
    end
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.cp.buildTargetListFromCheck()
    snd.campaign.targets = {}

    for i, check in ipairs(snd.campaign.checkList) do
        local areaKey = ""
        if check.loc and check.loc ~= "" then
            areaKey = snd.db.getAreaKeyFromName(check.loc) or ""
        end

        table.insert(snd.campaign.targets, {
            mob = check.mob,
            loc = check.loc,
            resolutionLoc = check.loc,
            lastCheckLoc = check.loc,
            arid = areaKey,
            dead = check.dead or false,
            -- A reported row is still required, so any local kill marker was stale.
            killed = false,
            campaignIndex = i,
            keyword = snd.gmcp.guessMobKeyword(check.mob, areaKey),
        })
    end
    
    snd.campaign.active = #snd.campaign.targets > 0
    
    if #snd.campaign.targets > 0 then
        snd.campaign.targetType = snd.cp.determineTargetType(snd.campaign.targets)
        snd.targets.type = snd.campaign.targetType
        snd.targets.activity = "cp"
        snd.cp.buildMainTargetList()
        snd.campaign.resolved = true
    else
        snd.campaign.resolved = false
    end
    
    snd.utils.debugNote("Built " .. #snd.campaign.targets .. " targets from cp check")
    if snd.campaign.active and snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "cp", {save = true, refresh = false})
    end
end

function snd.cp.determineTargetType(targets)
    if not targets or #targets == 0 then return "area" end

    for _, target in ipairs(targets) do
        if target.loc and target.loc ~= "" and snd.db and snd.db.getAreaKeyFromName then
            local areaKey = snd.db.getAreaKeyFromName(target.loc)
            if areaKey and areaKey ~= "" then
                return "area"
            end
        end
    end

    for _, target in ipairs(targets) do
        if target.loc and target.loc ~= "" then
            local locLower = target.loc:lower()
            if locLower:match("^the ") or
               locLower:match("^a ") or
               locLower:match("^an ") or
               locLower:match(" of ") then
                return "room"
            end
        end
    end

    return "area"
end

local function newResolutionContext()
    return {
        mobEvidence = {},
        areaByZone = {},
    }
end

local function resolutionMobKey(mobName)
    return snd.utils.trim(tostring(mobName or "")):lower()
end

local function getResolutionArea(context, zone)
    zone = tostring(zone or "")
    if zone == "" then return nil end
    context.areaByZone = context.areaByZone or {}
    if context.areaByZone[zone] == nil then
        context.areaByZone[zone] = (snd.db and snd.db.getArea and snd.db.getArea(zone)) or false
    end
    return context.areaByZone[zone] or nil
end

local function getMobEvidence(context, mobName)
    local key = resolutionMobKey(mobName)
    if key == "" then return {}, mobName end
    context.mobEvidence = context.mobEvidence or {}
    if context.mobEvidence[key] == nil then
        local rows, matchedName = {}, mobName
        if snd.db and snd.db.getMobLocations then
            rows, matchedName = snd.db.getMobLocations(mobName, "", { legacy = true })
            rows = rows or {}
        end
        local byZone = {}
        for _, row in ipairs(rows) do
            local zone = tostring(row.zone or row.arid or ""):lower()
            if zone ~= "" then
                byZone[zone] = byZone[zone] or {}
                table.insert(byZone[zone], row)
            end
        end
        context.mobEvidence[key] = {
            rows = rows,
            byZone = byZone,
            matchedName = matchedName or mobName,
        }
    end
    local evidence = context.mobEvidence[key]
    return evidence.rows or {}, evidence.matchedName or mobName
end

local function getMobZoneEvidence(context, mobName, zone)
    getMobEvidence(context, mobName)
    local evidence = context.mobEvidence and context.mobEvidence[resolutionMobKey(mobName)] or nil
    if not evidence then return {} end
    return evidence.byZone and evidence.byZone[tostring(zone or ""):lower()] or {}
end

local function rowMatchesPriority(row)
    if not row then return false end
    local priorityRoom = tonumber(row.priority_room)
    local roomId = tonumber(row.roomid or row.rmid)
    return tonumber(row.priority_match) == 1
        or (priorityRoom ~= nil and roomId ~= nil and priorityRoom == roomId)
end

local function rowRanksBefore(a, b)
    if not b then return true end
    local aPriority = rowMatchesPriority(a)
    local bPriority = rowMatchesPriority(b)
    if aPriority ~= bPriority then return aPriority end
    local aSeen = tonumber(a and a.seen_count) or 0
    local bSeen = tonumber(b and b.seen_count) or 0
    if aSeen ~= bSeen then return aSeen > bSeen end
    local aKills = tonumber(a and a.kill_count) or 0
    local bKills = tonumber(b and b.kill_count) or 0
    if aKills ~= bKills then return aKills > bKills end
    return (tonumber(a and (a.roomid or a.rmid)) or 0) < (tonumber(b and (b.roomid or b.rmid)) or 0)
end

local function tagsFromEvidenceRow(row)
    if not row then return nil end
    local priorityRoom = tonumber(row.priority_room)
    local nowhere = row.nowhere == true or tonumber(row.nowhere) == 1
    local nohunt = row.nohunt == true or tonumber(row.nohunt) == 1
    if not priorityRoom and not nowhere and not nohunt then return nil end
    return {
        priority_room = priorityRoom,
        nowhere = nowhere,
        nohunt = nohunt,
    }
end

function snd.cp.resolveZonesForTarget(target, playerLevel, resolutionContext)
    local context = resolutionContext or newResolutionContext()
    local hint = tostring(target.loc or "")
    local fallback = {
        {
            arid = target.arid or "",
            areaName = hint,
            roomName = "",
            roomId = nil,
            fromDb = false,
        },
    }

    local levelKnown = playerLevel and playerLevel > 0
    local function levelOk(area)
        local minLvl = tonumber(area and area.minlvl) or 0
        local maxLvl = tonumber(area and area.maxlvl) or 0
        if not levelKnown then return true end
        if minLvl == 0 and maxLvl == 0 then return true end
        return playerLevel >= minLvl and playerLevel <= (maxLvl + 25)
    end
    local function tryMapperFallback()
        if hint == "" then return nil end
        if not (snd.mapper and snd.mapper.searchRoomsExact) then return nil end
        local ok, rows = pcall(snd.mapper.searchRoomsExact, hint, "", target.mob, { silent = true })
        if not ok or type(rows) ~= "table" or #rows == 0 then return nil end
        local seenZone = {}
        local results = {}
        for _, row in ipairs(rows) do
            local zone = tostring(row.arid or row.area or "")
            if zone ~= "" and not seenZone[zone] then
                local area = getResolutionArea(context, zone)
                if levelOk(area) then
                    seenZone[zone] = true
                    table.insert(results, {
                        arid = zone,
                        areaName = (area and area.name) or zone,
                        roomName = row.name or hint,
                        roomId = tonumber(row.rmid or row.uid),
                        seenCount = 0,
                        fromDb = false,
                        fromMapper = true,
                        tags = tagsFromEvidenceRow(row),
                    })
                end
            end
        end
        if #results == 0 then return nil end
        return results
    end

    if not target.mob or target.mob == "" then
        return tryMapperFallback() or fallback, {}
    end

    -- Share one sighting snapshot across matching, zone selection, tags, and Express.
    local rows = getMobEvidence(context, target.mob)
    if #rows == 0 then
        return tryMapperFallback() or fallback, rows
    end

    if hint ~= "" then
        local hintLower = hint:lower()
        local exactByZone = {}
        local exactZoneOrder = {}
        for _, row in ipairs(rows) do
            local zone = tostring(row.zone or "")
            if zone ~= "" and row.room and tostring(row.room):lower() == hintLower then
                local area = getResolutionArea(context, zone)
                if levelOk(area) then
                    if exactByZone[zone] == nil then
                        table.insert(exactZoneOrder, zone)
                    end
                    if rowRanksBefore(row, exactByZone[zone]) then
                        exactByZone[zone] = row
                    end
                end
            end
        end
        local primary = {}
        for _, zone in ipairs(exactZoneOrder) do
            local row = exactByZone[zone]
            local area = getResolutionArea(context, zone)
            table.insert(primary, {
                arid = zone,
                areaName = (area and area.name) or hint,
                roomName = row.room,
                roomId = tonumber(row.roomid),
                seenCount = tonumber(row.seen_count) or 0,
                priorityMatch = rowMatchesPriority(row),
                fromDb = true,
                tags = tagsFromEvidenceRow(row),
            })
        end
        if #primary > 0 then
            table.sort(primary, function(a, b)
                if (a.priorityMatch == true) ~= (b.priorityMatch == true) then
                    return a.priorityMatch == true
                end
                return (a.seenCount or 0) > (b.seenCount or 0)
            end)
            return primary, rows
        end
    end

    -- When the campaign location resolves to a real area, that area is the
    -- authoritative scope. Historical sightings elsewhere must not relocate
    -- the campaign target. Keep the exact-room match above this guard because
    -- some location text can legitimately be both an area and a room name.
    local campaignAreaKey = snd.utils.trim(target.arid or "")
    if campaignAreaKey ~= "" then
        local bestRow = nil
        local totalSeen = 0
        local priorityMatch = false
        for _, row in ipairs(getMobZoneEvidence(context, target.mob, campaignAreaKey)) do
            totalSeen = totalSeen + (tonumber(row.seen_count) or 0)
            if rowMatchesPriority(row) then priorityMatch = true end
            if rowRanksBefore(row, bestRow) then bestRow = row end
        end

        local area = getResolutionArea(context, campaignAreaKey)
        return {
            {
                arid = campaignAreaKey,
                areaName = (area and area.name) or hint,
                roomName = bestRow and bestRow.room or "",
                roomId = bestRow and tonumber(bestRow.roomid) or nil,
                seenCount = totalSeen,
                priorityMatch = priorityMatch,
                fromDb = bestRow ~= nil,
                tags = tagsFromEvidenceRow(bestRow),
            },
        }, rows
    end

    local byZone = {}
    local zoneOrder = {}
    for _, row in ipairs(rows) do
        local zone = tostring(row.zone or "")
        if zone ~= "" then
            local agg = byZone[zone]
            if not agg then
                agg = { rooms = {}, totalSeen = 0, priorityMatch = false }
                byZone[zone] = agg
                table.insert(zoneOrder, zone)
            end
            table.insert(agg.rooms, row)
            if rowMatchesPriority(row) then
                agg.priorityMatch = true
            end
            agg.totalSeen = agg.totalSeen + (tonumber(row.seen_count) or 0)
        end
    end

    if #zoneOrder == 0 then
        return fallback, rows
    end

    for _, zone in ipairs(zoneOrder) do
        local agg = byZone[zone]
        table.sort(agg.rooms, rowRanksBefore)
        agg.bestRow = agg.rooms[1]
    end

    table.sort(zoneOrder, function(a, b)
        local aPriority = byZone[a].priorityMatch == true
        local bPriority = byZone[b].priorityMatch == true
        if aPriority ~= bPriority then
            return aPriority
        end
        return (byZone[a].totalSeen or 0) > (byZone[b].totalSeen or 0)
    end)

    local kept = {}
    for _, zone in ipairs(zoneOrder) do
        local area = getResolutionArea(context, zone)
        if levelOk(area) then
            local agg = byZone[zone]
            local row = agg.bestRow
            table.insert(kept, {
                arid = zone,
                areaName = (area and area.name) or hint,
                roomName = row and row.room or "",
                roomId = row and tonumber(row.roomid) or nil,
                seenCount = agg.totalSeen,
                priorityMatch = agg.priorityMatch == true,
                fromDb = true,
                tags = tagsFromEvidenceRow(row),
            })
        end
    end

    if #kept == 0 then
        snd.utils.debugNote(string.format(
            "CP filter: dropped '%s' — no zone fits level %d (mob in %d zone(s) total)",
            tostring(target.mob), playerLevel, #zoneOrder
        ))
        return tryMapperFallback() or fallback, rows
    end

    if hint ~= "" and #kept > 1 then
        local hintLower = hint:lower()
        for _, z in ipairs(kept) do
            if z.areaName and z.areaName:lower() == hintLower then
                return { z }, rows
            end
        end
    end


    return kept, rows
end

function snd.cp.reconcileSelectionAfterRebuild()
    local cpEntries = {}
    for _, entry in ipairs(snd.targets.list or {}) do
        if entry.activity == "cp" and not entry.dead then
            table.insert(cpEntries, entry)
        end
    end

    local function reconcileSelection(selection)
        if type(selection) ~= "table" then
            return false
        end
        if selection.activity ~= "cp" then
            return true
        end
        if not snd.commands or type(snd.commands.findTargetSelectionEntry) ~= "function" then
            local selectedMob = tostring(selection.name or selection.mob or ""):lower()
            local selectedArea = tostring(selection.area or selection.arid or ""):lower()
            for _, entry in ipairs(cpEntries) do
                local entryMob = tostring(entry.mob or entry.name or ""):lower()
                local entryArea = tostring(entry.arid or entry.area or ""):lower()
                if selectedMob ~= "" and selectedMob == entryMob
                    and (selectedArea == "" or entryArea == "" or selectedArea == entryArea)
                then
                    return true
                end
            end
            return false
        end
        local entry = snd.commands.findTargetSelectionEntry(selection, cpEntries)
        if not entry then return false end
        snd.commands.bindTargetSelection(selection, entry)
        return true
    end

    local clearedScoped = false
    local clearedCurrent = false

    if snd.targets and snd.targets.scoped and snd.targets.scoped.cp and not reconcileSelection(snd.targets.scoped.cp) then
        snd.targets.scoped.cp = nil
        clearedScoped = true
    end

    if snd.targets and snd.targets.current and snd.targets.current.activity == "cp"
        and not reconcileSelection(snd.targets.current) then
        if snd.nav and snd.nav.invalidateQuickWhereForTarget then
            snd.nav.invalidateQuickWhereForTarget(nil)
        end
        snd.targets.current = nil
        clearedCurrent = true
    end

    if (clearedScoped or clearedCurrent)
        and snd.nav and snd.nav.clearActivityQuickWhere then
        snd.nav.clearActivityQuickWhere("cp")
        snd.utils.debugNote("CP reconcile: cleared stale CP selection/navigation state")
    end
end

local function entryHasMobPriority(entry)
    local priorityRoom = tonumber(entry and entry.priority_room)
    return priorityRoom ~= nil and priorityRoom > 0
end

local function sortAndIndexCpEntries(cpEntries)
    local currentArid = (snd.room and snd.room.current and tostring(snd.room.current.arid or "")) or ""
    local currentAreaHasAlive = false
    if currentArid ~= "" then
        for _, entry in ipairs(cpEntries) do
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
    for _, entry in ipairs(cpEntries) do
        local arid = tostring(entry.arid or "")
        if areaGroupSeen[arid] == nil then
            areaGroupCount = areaGroupCount + 1
            areaGroupSeen[arid] = areaGroupCount
        end
        entry._areaGroup = areaGroupSeen[arid]
    end

    table.sort(cpEntries, function(a, b)
        if a.dead ~= b.dead then
            return not a.dead
        end
        local aPriority = entryHasMobPriority(a)
        local bPriority = entryHasMobPriority(b)
        if aPriority ~= bPriority then
            return aPriority
        end
        local aLow = a.lowConfidence == true
        local bLow = b.lowConfidence == true
        if aLow ~= bLow then
            return not aLow
        end
        if (a._areaGroup or 0) ~= (b._areaGroup or 0) then
            return (a._areaGroup or 0) < (b._areaGroup or 0)
        end
        if (a.campaignIndex or 0) ~= (b.campaignIndex or 0) then
            return (a.campaignIndex or 0) < (b.campaignIndex or 0)
        end
        return (a.dupIndex or 0) < (b.dupIndex or 0)
    end)

    local displayIndex = 0
    for listIndex, entry in ipairs(cpEntries) do
        entry._areaGroup = nil
        entry.cpListIndex = listIndex
        if not entry.dead then
            displayIndex = displayIndex + 1
            entry.displayIndex = displayIndex
        else
            entry.displayIndex = nil
        end
    end
end

function snd.cp.buildMainTargetList()
    local newList = {}
    for _, t in ipairs(snd.targets.list) do
        if t.activity ~= "cp" then
            table.insert(newList, t)
        end
    end
    snd.targets.list = newList

    local playerLevel = tonumber(snd.char and snd.char.level) or 0
    local resolutionContext = newResolutionContext()
    local emittedAnyRoomTarget = false
    local highEntries = {}
    local lowEntries = {}

    for i, target in ipairs(snd.campaign.targets) do
        local resolved = snd.cp.resolveZonesForTarget(target, playerLevel, resolutionContext)
        if type(resolved) ~= "table" or #resolved == 0 then
            resolved = {
                {
                    arid = target.arid or "",
                    areaName = target.loc or "",
                    roomName = "",
                    roomId = nil,
                    fromDb = false,
                    fromMapper = true,
                }
            }
            snd.utils.debugNote("CP fallback: unresolved target '" .. tostring(target.mob) .. "', using direct campaign hint")
        end
        local visible = {}
        for _, zone in ipairs(resolved) do
            table.insert(visible, zone)
        end
        local total = #visible
        for j, zone in ipairs(visible) do
            local arid = zone.arid or ""
            local roomName = ""
            if zone.fromDb and zone.roomName and zone.roomName ~= "" then
                roomName = zone.roomName
                emittedAnyRoomTarget = true
            elseif zone.fromMapper and zone.roomName and zone.roomName ~= "" then
                roomName = zone.roomName
                emittedAnyRoomTarget = true
            elseif snd.campaign.targetType == "room" and not zone.fromDb and target.loc and target.loc ~= "" then
                roomName = target.loc
            end

            local entry = {
                mob = target.mob,
                loc = zone.areaName or target.loc or "",
                arid = arid,
                roomName = roomName,
                dead = target.dead == true,
                killed = target.killed == true,
                index = j,
                campaignIndex = i,
                activity = "cp",
                keyword = target.keyword or snd.gmcp.guessMobKeyword(target.mob, arid),
                hasMobData = zone.fromDb == true,
                lowConfidence = zone.fromMapper == true,
                duplicates = total,
                dupIndex = j,
            }

            if zone.tags then
                entry.nowhere = zone.tags.nowhere
                entry.nohunt = zone.tags.nohunt
                entry.priority_room = zone.tags.priority_room
            end

            if entry.priority_room and tonumber(entry.priority_room) and tonumber(entry.priority_room) > 0 then
                entry.rmid = tonumber(entry.priority_room)
            elseif zone.roomId then
                entry.rmid = zone.roomId
            end

            if snd.express and snd.express.classifyTarget then
                snd.express.classifyTarget(entry, getMobZoneEvidence(resolutionContext, target.mob, arid))
            end

            if snd.debug and snd.debug.mobTag and (entry.priority_room or entry.nowhere or entry.nohunt) then
                snd.debug.mobTag(string.format(
                    "CP build mob='%s' area=%s roomName='%s' rmid=%s nowhere=%s nohunt=%s priority_room=%s sourceRoomId=%s seen=%s",
                    tostring(entry.mob or ""),
                    tostring(entry.arid or ""),
                    tostring(entry.roomName or ""),
                    tostring(entry.rmid or ""),
                    tostring(entry.nowhere == true),
                    tostring(entry.nohunt == true),
                    tostring(entry.priority_room or ""),
                    tostring(zone.roomId or ""),
                    tostring(zone.seenCount or "")
                ))
            end

            if zone.fromMapper then
                table.insert(lowEntries, entry)
            else
                table.insert(highEntries, entry)
            end
        end
    end

    local cpEntries = {}
    for _, entry in ipairs(highEntries) do
        table.insert(cpEntries, entry)
    end
    for _, entry in ipairs(lowEntries) do
        table.insert(cpEntries, entry)
    end
    sortAndIndexCpEntries(cpEntries)
    for _, entry in ipairs(cpEntries) do
        table.insert(snd.targets.list, entry)
    end

    if emittedAnyRoomTarget then
        snd.campaign.targetType = "room"
        snd.targets.type = "room"
    end

    snd.utils.debugNote("Built main target list: " .. #snd.targets.list .. " CP targets (level " .. playerLevel .. ")")
    if snd.sortTargetsByPriority then
        snd.sortTargetsByPriority({
            recalculateProximity = true,
            reason = "cp_target_list_built",
        })
    end
    snd.cp.reconcileSelectionAfterRebuild()
end

-- Location choices for one canonical target share status.
function snd.cp.updateTargetStatus()
    local canonicalByIndex = {}
    for i, campaignTarget in ipairs(snd.campaign.targets or {}) do
        campaignTarget.campaignIndex = tonumber(campaignTarget.campaignIndex) or i
        canonicalByIndex[campaignTarget.campaignIndex] = campaignTarget
    end

    local cpList = {}
    local nonCpList = {}
    for _, target in ipairs(snd.targets.list or {}) do
        if target.activity == "cp" then
            local canonical = canonicalByIndex[tonumber(target.campaignIndex)]
            if canonical then
                target.dead = canonical.dead == true
                target.killed = canonical.dead == true and canonical.killed == true
                table.insert(cpList, target)
            end
        else
            table.insert(nonCpList, target)
        end
    end

    sortAndIndexCpEntries(cpList)
    snd.targets.list = nonCpList
    for _, target in ipairs(cpList) do
        table.insert(snd.targets.list, target)
    end
    if snd.sortTargetsByPriority then
        snd.sortTargetsByPriority({
            recalculateProximity = true,
            reason = "cp_target_status_changed",
        })
    end
    snd.cp.reconcileSelectionAfterRebuild()
    if snd.conwin and snd.conwin.render then
        snd.conwin.render()
    end
end

-- Reject unexpected targets so the caller can safely rebuild the full roster.
function snd.cp.applyCheckStatusOnly()
    local targets = snd.campaign.targets or {}
    if not snd.campaign.resolved or #targets == 0 then
        return false, "no resolved campaign snapshot"
    end

    local matchedTargets = {}
    local assignments = {}

    local function targetLocationMatches(target, check)
        local checkLoc = tostring(check.loc or ""):lower()
        if checkLoc == "" then return false end
        return tostring(target.resolutionLoc or target.loc or ""):lower() == checkLoc
            or tostring(target.lastCheckLoc or ""):lower() == checkLoc
    end

    -- Exact mob+location identity preserves duplicate-name ownership.
    for checkIndex, check in ipairs(snd.campaign.checkList or {}) do
        for targetIndex, target in ipairs(targets) do
            if not matchedTargets[targetIndex]
                and tostring(target.mob or ""):lower() == tostring(check.mob or ""):lower()
                and targetLocationMatches(target, check) then
                matchedTargets[targetIndex] = true
                assignments[checkIndex] = targetIndex
                break
            end
        end
    end

    -- Dead lines may change location; fall back by same-name campaign order only.
    for checkIndex, check in ipairs(snd.campaign.checkList or {}) do
        if not assignments[checkIndex] then
            for targetIndex, target in ipairs(targets) do
                if not matchedTargets[targetIndex]
                    and tostring(target.mob or ""):lower() == tostring(check.mob or ""):lower() then
                    matchedTargets[targetIndex] = true
                    assignments[checkIndex] = targetIndex
                    break
                end
            end
        end
        if not assignments[checkIndex] then
            return false, "CP roster changed near '" .. tostring(check.mob or "") .. "'"
        end
    end

    -- The response is authoritative: remove omitted targets, but retain explicit
    -- -Dead rows because they remain required after respawn.
    local retainedTargets = {}
    local newIndexByOldCampaignIndex = {}
    for checkIndex, check in ipairs(snd.campaign.checkList or {}) do
        local targetIndex = assignments[checkIndex]
        local target = targets[targetIndex]
        local oldCampaignIndex = tonumber(target.campaignIndex) or targetIndex
        local newCampaignIndex = #retainedTargets + 1
        target.lastCheckLoc = check.loc
        target.dead = check.dead == true
        target.killed = false
        target.campaignIndex = newCampaignIndex
        retainedTargets[newCampaignIndex] = target
        newIndexByOldCampaignIndex[oldCampaignIndex] = newCampaignIndex
    end

    snd.campaign.targets = retainedTargets
    for _, target in ipairs(snd.targets.list or {}) do
        if target.activity == "cp" then
            target.campaignIndex = newIndexByOldCampaignIndex[tonumber(target.campaignIndex)]
        end
    end

    snd.cp.updateTargetStatus()
    return true
end

local function cpKillEvidence()
    if snd.conwin and type(snd.conwin.getActivityKillEvidence) == "function" then
        local evidence = snd.conwin.getActivityKillEvidence("cp", 3)
        if type(evidence) == "table" then
            return evidence
        end
    end

    -- Compatibility for ConWin versions that predate activity evidence.
    if snd.conwin and type(snd.conwin.getRecentKilledMobName) == "function" then
        local name = snd.conwin.getRecentKilledMobName(3) or ""
        if name ~= "" then
            return {status = "resolved", name = name, source = "legacy-death", keys = {}}
        end
    end
    if snd.conwin and type(snd.conwin.getCurrentCombatMobName) == "function" then
        local name = snd.conwin.getCurrentCombatMobName() or ""
        if name ~= "" then
            return {status = "resolved", name = name, source = "legacy-combat", keys = {}}
        end
    end
    return {status = "none", source = "none", keys = {}}
end

local function consumeCpKillEvidence(evidence)
    if snd.conwin and type(snd.conwin.consumeActivityKillEvidence) == "function" then
        snd.conwin.consumeActivityKillEvidence("cp", evidence)
    elseif evidence and evidence.source == "legacy-death"
        and snd.conwin and type(snd.conwin.clearRecentKilledMobName) == "function"
    then
        snd.conwin.clearRecentKilledMobName()
    end
end

local function currentCpSelectionIndex()
    local selection = snd.targets and snd.targets.current
    if type(selection) ~= "table" or selection.activity ~= "cp" then return nil end
    if tonumber(selection.campaignIndex) then return tonumber(selection.campaignIndex) end
    if snd.commands and type(snd.commands.findTargetSelectionEntry) == "function" then
        local entry = snd.commands.findTargetSelectionEntry(selection, snd.targets.list or {})
        if entry and entry.activity == "cp" then return tonumber(entry.campaignIndex) end
    end
    for _, entry in ipairs((snd.targets and snd.targets.list) or {}) do
        if entry.activity == "cp"
            and snd.utils.mobIdentityMatches(entry.mob, selection.name or selection.mob)
        then
            return tonumber(entry.campaignIndex)
        end
    end
    return nil
end

local function findCpKillEntry(name, preferredCampaignIndex)
    local candidates = {}
    for _, entry in ipairs((snd.targets and snd.targets.list) or {}) do
        if entry.activity == "cp" and not entry.dead and not entry.killed
            and snd.utils.mobIdentityMatches(entry.mob, name)
        then
            candidates[#candidates + 1] = entry
        end
    end
    if preferredCampaignIndex then
        for _, entry in ipairs(candidates) do
            if tonumber(entry.campaignIndex) == tonumber(preferredCampaignIndex) then return entry end
        end
    end

    local room = snd.room and snd.room.current or {}
    local roomId = tostring(room.rmid or room.id or "")
    local roomName = tostring(room.name or ""):lower()
    local area = tostring(room.arid or ""):lower()
    for _, entry in ipairs(candidates) do
        local sameRoomId = roomId ~= "" and entry.rmid ~= nil and tostring(entry.rmid) == roomId
        local entryRoomName = tostring(entry.roomName or ""):lower()
        local entryArea = tostring(entry.arid or ""):lower()
        local sameNamedRoom = roomName ~= "" and entryRoomName == roomName
            and (area == "" or entryArea == "" or entryArea == area)
        if sameRoomId or sameNamedRoom then return entry end
    end
    if area ~= "" then
        for _, entry in ipairs(candidates) do
            if tostring(entry.arid or ""):lower() == area then return entry end
        end
    end
    return candidates[1]
end

function snd.cp.onMobKilled()
    snd.utils.debugNote("Campaign mob killed!")
    local shouldSyncAfterKill = true
    local killedTargetsBefore = 0
    for _, target in ipairs(snd.campaign.targets or {}) do
        if target.killed then killedTargetsBefore = killedTargetsBefore + 1 end
    end

    local evidence = cpKillEvidence()
    local evidenceStatus = tostring(evidence.status or "none")
    local selectedCampaignIndex = currentCpSelectionIndex()
    local killedName = ""
    local preferredCampaignIndex = nil
    if evidenceStatus == "resolved" then
        killedName = tostring(evidence.name or "")
    elseif evidenceStatus == "none"
        and snd.targets.current and snd.targets.current.activity == "cp"
    then
        -- The selected target is only a fallback when ConWin observed no identity.
        killedName = tostring(snd.targets.current.name or snd.targets.current.mob or "")
        preferredCampaignIndex = selectedCampaignIndex
    end

    local killedEntry = killedName ~= "" and findCpKillEntry(killedName, preferredCampaignIndex) or nil
    local killedCampaignIndex = killedEntry and tonumber(killedEntry.campaignIndex) or nil
    local canonical = killedCampaignIndex and snd.campaign.targets
        and snd.campaign.targets[killedCampaignIndex] or nil
    if killedEntry and not canonical then
        for i, target in ipairs(snd.campaign.targets or {}) do
            if not target.killed and snd.utils.mobIdentityMatches(target.mob, killedEntry.mob) then
                canonical = target
                killedCampaignIndex = i
                break
            end
        end
    end

    if canonical and not canonical.killed then
        canonical.dead = true
        canonical.killed = true
        local killedWasSelected = selectedCampaignIndex ~= nil
            and tonumber(selectedCampaignIndex) == tonumber(killedCampaignIndex)
        snd.cp.updateTargetStatus()
        if killedWasSelected and snd.targets.current and snd.targets.current.activity == "cp" then
            snd.clearTarget({refresh = false})
        end
        if type(raiseEvent) == "function" then
            local roomId = snd.room and snd.room.current and snd.room.current.id or nil
            raiseEvent("snd.kill.confirmed", canonical.mob or killedName, roomId)
        end

        if snd.cp.getRemainingCount and snd.cp.getRemainingCount() == 0 then
            local killedPendingCount = 0
            for _, target in ipairs(snd.campaign.targets or {}) do
                if target.killed then killedPendingCount = killedPendingCount + 1 end
            end
            if killedPendingCount <= 1 then
                shouldSyncAfterKill = false
                snd.utils.debugNote("Skipping post-kill cp check because last campaign target was just killed")
            end
        end
    end
    consumeCpKillEvidence(evidence)

    local killedTargetsAfter = 0
    for _, target in ipairs(snd.campaign.targets or {}) do
        if target.killed then killedTargetsAfter = killedTargetsAfter + 1 end
    end
    local markedTargetKilled = killedTargetsAfter > killedTargetsBefore

    if not markedTargetKilled then
        snd.utils.debugNote(
            "Campaign kill evidence '" .. evidenceStatus .. "' marked no CP target; forcing cp check"
        )
        snd.cp.requestCheck(0.1, "cp.onMobKilled:no-target-marked-killed", true)
    elseif shouldSyncAfterKill
        and (not snd.shouldAutoCheckAfterKill or snd.shouldAutoCheckAfterKill("cp"))
    then
        snd.cp.requestCheck(0.1, "cp.onMobKilled")
    end

    if snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "auto", {save = false, refresh = false})
    end
    if snd.saveState then snd.saveState() end
    if snd.gui then
        if snd.gui.requestRefresh then snd.gui.requestRefresh()
        elseif snd.gui.refresh then snd.gui.refresh() end
    end
end

function snd.cp.onComplete()
    local endedHistory = nil
    local latest = nil
    local completionRewards = buildCompletionRewards(nil)
    if snd.db and snd.db.getLatestCampaignHistoryRow and snd.db.historyEndById then
        latest = snd.db.getLatestCampaignHistoryRow()
        local latestRewards = buildCompletionRewards(latest)
        local latestId = latest and tonumber(latest.id) or nil
        local latestStatus = latest and tonumber(latest.status) or nil
        local latestCompleteBy = (latestId and snd.db.getCompleteByByHistoryId) and
            snd.cp.normalizeCompleteBy(snd.db.getCompleteByByHistoryId(latestId)) or ""
        local expectedCompleteBy = snd.cp.normalizeCompleteBy(snd.campaign.persistedCompleteBy)
        if expectedCompleteBy == "" then
            expectedCompleteBy = snd.cp.normalizeCompleteBy(snd.campaign.completeBy)
        end

        if latestId and statusIsInProgress(latestStatus) then
            local canComplete = false
            if expectedCompleteBy ~= "" then
                canComplete = (latestCompleteBy == expectedCompleteBy)
                snd.utils.debugNote(
                    string.format(
                        "CP completion compare (CB): latest_id=%s latest_cb='%s' expected_cb='%s' match=%s",
                        tostring(latestId),
                        tostring(latestCompleteBy),
                        tostring(expectedCompleteBy),
                        tostring(canComplete)
                    )
                )
            else
                local rewards = persistedRewardsSnapshot()
                canComplete = rowRewardsMatch(latest, rewards)
                snd.utils.debugNote(
                    string.format(
                        "CP completion compare (rewards): latest_id=%s db={qp=%s,tp=%s,tr=%s,pr=%s,g=%s} persisted={qp=%s,tp=%s,tr=%s,pr=%s,g=%s} match=%s",
                        tostring(latestId),
                        tostring(latest.qp_rewards), tostring(latest.tp_rewards), tostring(latest.train_rewards), tostring(latest.prac_rewards), tostring(latest.gold_rewards),
                        tostring(rewards.qp), tostring(rewards.tp), tostring(rewards.trains), tostring(rewards.pracs), tostring(rewards.gold),
                        tostring(canComplete)
                    )
                )
            end

            if canComplete then
                completionRewards = latestRewards
                endedHistory = snd.cp.closeHistorySession(
                    snd.db.HISTORY_STATUS_COMPLETE,
                    completionRewards,
                    "campaign complete",
                    {forceHistoryId = latestId, skipReattachProbe = true}
                )
            else
                snd.utils.debugNote(
                    "Campaign completion ignored: latest in-progress row did not match persisted identity"
                )
            end
        else
            snd.utils.debugNote("Campaign completion ignored: latest campaign row missing or not in-progress")
        end
    end

    if endedHistory then
        snd.utils.reportCampaignCompletion({
            qp = tonumber(endedHistory.qp_rewards) or completionRewards.qp or 0,
            baseQp = completionRewards.baseQp,
            dailyQpBonus = completionRewards.dailyQpBonus,
            gold = tonumber(endedHistory.gold_rewards) or completionRewards.gold or 0,
            tp = tonumber(endedHistory.tp_rewards) or completionRewards.tp or 0,
            trains = tonumber(endedHistory.train_rewards) or completionRewards.trains or 0,
            pracs = tonumber(endedHistory.prac_rewards) or completionRewards.pracs or 0,
        }, tonumber(endedHistory.duration_seconds))
    else
        snd.utils.reportCampaignCompletion(completionRewards, nil)
    end

    snd.cp.recordCampaignCompletionToday()
    snd.cp.clearCampaign()
end

function snd.cp.startCompletionPending()
    cancelCompletionTimer()
    snd.cp.parsing.completionPending = true
    snd.cp.parsing.completionSeparatorsSeen = 0
    if snd.cp.normalizeCampaignTodayCounter then
        snd.cp.normalizeCampaignTodayCounter()
    end
    snd.cp.parsing.completionStartCompletedToday = tonumber(snd.campaign.completedToday) or 0
    snd.campaign.dailyQpBonus = 0

    if type(tempTimer) ~= "function" then
        snd.cp.finalizePendingCompletion("no completion timer available")
        return
    end

    snd.cp.parsing.completionTimer = tempTimer(CP_COMPLETION_BONUS_WAIT, function()
        snd.cp.parsing.completionTimer = nil
        snd.cp.finalizePendingCompletion("first campaign bonus wait expired")
    end)
end

function snd.cp.finalizePendingCompletion(reason)
    if not snd.cp.parsing.completionPending then
        return false
    end

    snd.cp.parsing.completionPending = false
    snd.cp.parsing.completionSeparatorsSeen = 0
    cancelCompletionTimer()

    if reason and reason ~= "" then
        snd.utils.debugNote("Finalizing campaign completion (" .. tostring(reason) .. ")")
    end

    snd.cp.onComplete()
    return true
end

function snd.cp.applyFirstDailyBonus(qpBonus)
    local bonus = tonumber(qpBonus) or 0
    if bonus <= 0 then
        return false
    end

    if not snd.cp.parsing.completionPending then
        snd.utils.debugNote("Ignoring first campaign daily bonus; no completion is pending")
        return false
    end

    snd.campaign.dailyQpBonus = bonus
    snd.utils.debugNote("First campaign daily bonus captured: " .. tostring(bonus) .. "qp")
    return snd.cp.finalizePendingCompletion("first campaign daily bonus captured")
end

function snd.cp.onCompletionSeparator()
    return snd.cp.parsing.completionPending == true
end

function snd.cp.onQuit()
    snd.utils.reportLine("Campaign cleared.", "campaign")
    
    if snd.db then
        snd.cp.closeHistorySession(snd.db.HISTORY_STATUS_FAILED, nil, "campaign cleared")
    end
    
    snd.cp.clearCampaign()
end

function snd.cp.onNotOnCampaign()
    snd.utils.debugNote(
        "Not on campaign (tracked completeBy='" .. tostring(snd.campaign.completeBy or "") ..
        "', historyId=" .. tostring(snd.campaign.historyId or 0) .. ")"
    )

    if snd.cp.parsing.completionPending then
        snd.cp.finalizePendingCompletion("not-on-campaign confirmation arrived during completion wait")
        return
    end

    if snd.db and snd.cp.hasOpenHistorySession() then
        snd.cp.closeHistorySession(snd.db.HISTORY_STATUS_RESET, nil, "verified not on campaign")
    end
    snd.cp.clearCampaign()
end

function snd.cp.onCampaignAccepted()
    snd.campaign.canGetNew = false
    snd.campaign.acceptedAt = os.time()
    snd.campaign.resolved = false
    snd.cp.forceResolveNextCheck = false

    if snd.gmcp and snd.gmcp.setCampaignActiveForAutoNoexp then
        snd.gmcp.setCampaignActiveForAutoNoexp()
    end
end

function snd.cp.clearCampaign()
    snd.campaign.active = false
    snd.campaign.levelTaken = 0
    snd.campaign.completeBy = ""
    snd.campaign.acceptedAt = 0
    snd.campaign.targets = {}
    snd.campaign.checkList = {}
    snd.campaign.resolved = false
    snd.cp.forceResolveNextCheck = false
    snd.campaign.qpReward = 0
    snd.campaign.goldReward = 0
    snd.campaign.tpReward = 0
    snd.campaign.trainReward = 0
    snd.campaign.pracReward = 0
    snd.campaign.dailyQpBonus = 0
    snd.campaign.targetType = nil
    cancelCompletionTimer()
    snd.cp.parsing.completionPending = false
    snd.cp.parsing.completionSeparatorsSeen = 0
    snd.cp.parsing.completionStartCompletedToday = nil

    if not snd.gquest.active then
        snd.targets.list = {}
        snd.targets.type = "none"
        snd.targets.activity = "none"

        if snd.isCpOrGqTarget() then
            snd.clearTarget()
        end
    end

    if snd.nav and snd.nav.clearActivityQuickWhere then
        snd.nav.clearActivityQuickWhere("cp")
    end

    if snd.gmcp and snd.gmcp.clearCampaignActiveForAutoNoexp then
        snd.gmcp.clearCampaignActiveForAutoNoexp()
    end

    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.cp.onCanGetNew()
    snd.campaign.canGetNew = true
    snd.utils.debugNote("Can get new campaign")

    if snd.cp.parsing.completionPending then
        snd.cp.finalizePendingCompletion("campaign eligibility arrived during completion wait")
        return
    end

    -- Eligibility does not prove a persisted campaign ended. Reattach through
    -- cp info; only an explicit not-on-campaign response may close it.
    if snd.db and snd.cp.hasOpenHistorySession() and not snd.campaign.active then
        snd.utils.debugNote("Campaign eligibility arrived before campaign reconciliation; requesting 'cp info'")
        snd.cp.requestInfo(0, "campaign-eligibility:history-reattach")
    end
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.cp.getTodayDateKey()
    return os.date("%Y-%m-%d")
end

function snd.cp.normalizeCampaignTodayCounter()
    local today = snd.cp.getTodayDateKey()
    if snd.campaign.completedTodayDate ~= today then
        snd.campaign.completedTodayDate = today
        snd.campaign.completedToday = 0
    end
end

function snd.cp.setCampaignsCompletedToday(count)
    snd.cp.normalizeCampaignTodayCounter()
    snd.campaign.completedToday = math.max(0, tonumber(count) or 0)
    snd.campaign.completedTodayDate = snd.cp.getTodayDateKey()
    if snd.saveState then
        snd.saveState()
    end
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.cp.incrementCampaignsCompletedToday()
    snd.cp.normalizeCampaignTodayCounter()
    snd.campaign.completedToday = (tonumber(snd.campaign.completedToday) or 0) + 1
    snd.campaign.completedTodayDate = snd.cp.getTodayDateKey()
    if snd.saveState then
        snd.saveState()
    end
end

function snd.cp.recordCampaignCompletionToday()
    snd.cp.normalizeCampaignTodayCounter()
    local startCount = tonumber(snd.cp.parsing.completionStartCompletedToday)
    local currentCount = tonumber(snd.campaign.completedToday) or 0

    if startCount == nil or currentCount <= startCount then
        snd.cp.incrementCampaignsCompletedToday()
    else
        snd.cp.parsing.completionStartCompletedToday = nil
        if snd.saveState then
            snd.saveState()
        end
    end
end

function snd.cp.selectTarget(index, options)
    local opts = type(options) == "table" and options or {}
    index = tonumber(index)
    if not index then return false end
    
    local target = nil
    local count = 0
    local deadTarget = nil
    
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "cp" and not t.dead then
            count = count + 1
            if count == index then
                target = t
                break
            end
        end
        if t.activity == "cp" and t.dead and tonumber(t.cpListIndex or 0) == index then
            deadTarget = t
        end
    end
    
    if not target then
        if deadTarget then
            snd.utils.infoNote("Target #" .. tostring(index) .. " is marked dead; requesting fresh cp check.")
            if snd.cp.requestCheck then
                snd.cp.requestCheck(0, "cp.selectTarget:dead-index")
            else
                send("cp check", false)
            end
            if snd.gui and snd.gui.refresh then
                snd.gui.refresh()
            end
            return true
        end
        snd.utils.infoNote("Invalid target index: " .. index)
        return false
    end

    if snd.debug and snd.debug.mobTag then
        snd.debug.mobTag(string.format(
            "CP select index=%s mob='%s' area=%s loc='%s' roomName='%s' rmid=%s priority_room=%s nowhere=%s nohunt=%s",
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
        area = target.arid or "",       -- Area key for navigation
        areaName = target.loc or "",    -- Area display name
        index = index,
        activity = "cp",
        express = target.express == true,
        expressRoomId = target.expressRoomId,
        expressKillCount = target.expressKillCount,
        expressRoomCount = target.expressRoomCount,
    })
    if not opts.skipLookup then
        if snd.campaign.targetType == "room" and target.roomName and target.roomName ~= "" then
            snd.mapper.searchRoomsExact(target.roomName, target.arid, target.mob, {
                activity = "cp",
                levelTaken = snd.campaign.levelTaken,
            })
        else
            local results = snd.mapper.searchMobLocations(target.mob, target.arid)
            if not results or #results == 0 then
                snd.commands.qw("")
            end
        end
    end
    
    local areaInfo = ""
    if target.loc and target.loc ~= "" then
        areaInfo = " in " .. target.loc
    end
    if not opts.skipLookup then
        snd.utils.infoNote("Target: " .. target.mob .. areaInfo)
    end
    return true
end

function snd.cp.getNextTarget()
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "cp" and not t.dead then
            return t
        end
    end
    return nil
end

function snd.cp.getRemainingCount()
    local count = 0
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "cp" and not t.dead then
            count = count + 1
        end
    end
    return count
end

