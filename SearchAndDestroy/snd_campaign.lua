--[[
    Search and Destroy - Campaign Module
    Mudlet Port
    
    Original MUSHclient plugin by Crowley
    Ported to Mudlet
    
    This module handles campaign (cp) tracking:
    - Parsing cp info / cp check output
    - Target list management
    - Campaign completion/failure
]]

snd = snd or {}
snd.cp = snd.cp or {}

-------------------------------------------------------------------------------
-- Campaign Info Parsing State
-------------------------------------------------------------------------------

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

local CP_COMPLETION_BONUS_WAIT = 0.5

-------------------------------------------------------------------------------
-- Campaign Check Request Throttling
-------------------------------------------------------------------------------

--- Request a cp check while suppressing duplicate sends in a short window.
-- @param delay number|nil Optional delay in seconds before sending
-- @param reason string|nil Optional debug reason for why check was requested
-- @param force boolean|nil Bypass the duplicate-send interval when a refresh is required
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

-------------------------------------------------------------------------------
-- Campaign History Session Tracking
-------------------------------------------------------------------------------

--- Normalize "Complete By" text so comparisons are stable.
-- @param value string Raw value captured from cp info.
-- @return string Normalized value
function snd.cp.normalizeCompleteBy(value)
    local normalized = snd.utils.trim(tostring(value or ""))
    normalized = normalized:gsub("^%[", ""):gsub("%]$", "")
    normalized = snd.utils.trim(normalized)
    return normalized
end

--- Parse normalized "Complete By" text into unix epoch.
-- Expected format: "03:27PM on 13 Apr 2026"
-- @param completeBy string
-- @return number|nil
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

--- Capture "Complete By" for the currently parsed cp info output.
-- @param value string Raw value captured from cp info.
function snd.cp.captureCompleteBy(value)
    local normalized = snd.cp.normalizeCompleteBy(value)
    if normalized == "" then
        return
    end
    snd.cp.parsing.capturedCompleteBy = normalized
    snd.utils.debugNote("CP complete-by captured: " .. normalized)
end

--- Parse cp info "Time Left" text into total seconds.
-- Example input: "6 days, 22 hours and 33 minutes"
-- @param value string
-- @return number|nil
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

--- Capture "Time Left" for the currently parsed cp info output.
-- @param value string Raw time-left text captured from cp info.
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

--- Persist the current campaign identity snapshot captured from cp info.
function snd.cp.persistCampaignIdentitySnapshot(completeBy)
    snd.campaign.persistedCompleteBy = snd.cp.normalizeCompleteBy(completeBy)
    snd.campaign.persistedQpReward = tonumber(snd.campaign.qpReward) or 0
    snd.campaign.persistedGoldReward = tonumber(snd.campaign.goldReward) or 0
    snd.campaign.persistedTpReward = tonumber(snd.campaign.tpReward) or 0
    snd.campaign.persistedTrainReward = tonumber(snd.campaign.trainReward) or 0
    snd.campaign.persistedPracReward = tonumber(snd.campaign.pracReward) or 0
end

--- True when we have an open campaign history row.
function snd.cp.hasOpenHistorySession()
    return snd.campaign.completeBy ~= nil and snd.campaign.completeBy ~= ""
end

--- Resolve history id for currently tracked Complete-By identity.
-- @return number|nil
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

--- Close currently tracked campaign history row if present.
-- For reset/undocumented closures, if we cannot resolve a history id from Complete-By,
-- force one last reattach attempt by sending "cp info" and waiting 2 seconds before retry.
-- @param status number
-- @param rewards table|nil
-- @param reason string|nil
-- @param opts table|nil {skipReattachProbe=true, forceHistoryId=number} internal guard/override
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

            snd.utils.debugNote("closeHistorySession: unresolved campaign history id, sending 'cp info' and retrying in 2s")
            send("cp info", false)
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

--- Open a campaign history row/session if none exists.
-- @param levelTaken number Character level when campaign was taken.
-- @param completeBy string|nil Normalized "Complete By" identity captured from cp info.
function snd.cp.openHistorySession(levelTaken, completeBy)
    if not snd.db then
        return
    end

    local normalizedCompleteBy = snd.cp.normalizeCompleteBy(completeBy)
    if normalizedCompleteBy == "" then
        snd.utils.debugNote("openHistorySession skipped: Complete-By not captured yet")
        snd.campaign.completeBy = ""
        send("cp info", false)
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

--- Sync currently captured campaign rewards into the open history row.
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

-------------------------------------------------------------------------------
-- Parse Mob Target String
-- Extracts mob name and location from strings like "a mob (Area Name)" or "a mob (Room Name)"
-------------------------------------------------------------------------------

function snd.cp.parseMobTarget(targetStr)
    if not targetStr then return nil, nil end
    
    -- Pattern: "mob name (location)"
    local mob, loc = targetStr:match("^(.+) %((.+)%)$")
    
    if not mob then
        -- No location, just mob name
        mob = targetStr
        loc = ""
    end
    
    -- Clean up mob name
    mob = snd.utils.trim(mob)
    loc = snd.utils.trim(loc or "")
    
    -- Check for " - Dead" suffix
    local isDead = false
    if loc:match(" %- Dead$") then
        isDead = true
        loc = loc:gsub(" %- Dead$", "")
    end
    
    return mob, loc, isDead
end

-------------------------------------------------------------------------------
-- Campaign Info Processing
-------------------------------------------------------------------------------

--- Start processing cp info output
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

--- Process a cp info target line
-- @param targetStr The target string (e.g., "a mob (Area Name)")
function snd.cp.processCpInfoLine(targetStr)
    if not snd.cp.parsing.infoActive then return end
    
    local mob, loc, isDead = snd.cp.parseMobTarget(targetStr)
    if not mob then return end
    
    -- loc contains the area NAME like "Artificer's Mayhem"
    -- We need to look up the area KEY for navigation
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

--- End processing cp info output
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

-------------------------------------------------------------------------------
-- Campaign Check Processing
-------------------------------------------------------------------------------

--- Start processing cp check output
function snd.cp.startCpCheck()
    snd.cp.parsing.checkActive = true
    snd.cp.parsing.tempTargets = {}
    snd.campaign.checkList = {}
    -- cp check output refreshes campaign status only; it should not inherit
    -- stale nx/xcp-mode state from prior navigation and accidentally fire qw/ht.
    if snd.nav then
        snd.nav.nxState = nil
    end
end

--- Process a cp check target line
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

--- End processing cp check output
function snd.cp.endCpCheck()
    snd.cp.parsing.checkActive = false
    snd.campaign.lastCheck = os.clock()
    local wasActive = snd.campaign.active
    
    if #snd.campaign.checkList > 0 then
        snd.utils.debugNote("Building target list from cp check results")
        snd.cp.buildTargetListFromCheck()
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

--- Build target list from cp check results (when cp info wasn't run first)
function snd.cp.buildTargetListFromCheck()
    -- Preserve player-killed flag across rebuilds. cp check can report a
    -- mob's location differently when alive vs dead (e.g. a room name while
    -- alive, an area name while dead), so a strict (mob, loc) match would
    -- drop killed=true after the rebuild. Use a two-tier match: exact
    -- (mob, loc) first, mob-only as fallback, with consumption counts so
    -- multiple campaign entries sharing a mob name don't all inherit the
    -- same killed flag.
    local killedExact = {}
    local killedByMob = {}
    for _, t in ipairs(snd.campaign.targets or {}) do
        if t.killed then
            local mob = t.mob or ""
            local key = mob .. "|" .. (t.loc or "")
            killedExact[key] = (killedExact[key] or 0) + 1
            killedByMob[mob] = (killedByMob[mob] or 0) + 1
        end
    end

    -- Identify mob names that have any alive entry in the new check. The
    -- mob-only fallback below is unsafe for these: the prior kill might be
    -- the now-alive (respawned) entry, and applying its leftover token to a
    -- different dead same-name duplicate would misattribute ownership.
    local aliveMobs = {}
    for _, check in ipairs(snd.campaign.checkList) do
        if not check.dead then
            aliveMobs[check.mob or ""] = true
        end
    end

    snd.campaign.targets = {}

    for i, check in ipairs(snd.campaign.checkList) do
        local areaKey = ""
        if check.loc and check.loc ~= "" then
            areaKey = snd.db.getAreaKeyFromName(check.loc) or ""
        end

        local mob = check.mob or ""
        local key = mob .. "|" .. (check.loc or "")

        -- Always consume an exact (mob, loc) token if one exists, regardless
        -- of the new dead state. If the mob respawned (check.dead == false),
        -- burning the token here keeps it from leaking into the fallback for
        -- a different same-name duplicate.
        local exactMatched = false
        if (killedExact[key] or 0) > 0 then
            killedExact[key] = killedExact[key] - 1
            killedByMob[mob] = (killedByMob[mob] or 1) - 1
            exactMatched = true
        end

        local killed = false
        if check.dead then
            if exactMatched then
                killed = true
            elseif (killedByMob[mob] or 0) > 0 and not aliveMobs[mob] then
                killedByMob[mob] = killedByMob[mob] - 1
                killed = true
            end
        end

        table.insert(snd.campaign.targets, {
            mob = check.mob,
            loc = check.loc,
            arid = areaKey,
            dead = check.dead or false,
            killed = killed,
            keyword = snd.gmcp.guessMobKeyword(check.mob, areaKey),
        })
    end
    
    snd.campaign.active = #snd.campaign.targets > 0
    
    if #snd.campaign.targets > 0 then
        snd.campaign.targetType = snd.cp.determineTargetType(snd.campaign.targets)
        snd.targets.type = snd.campaign.targetType
        snd.targets.activity = "cp"
        snd.cp.buildMainTargetList()
    end
    
    snd.utils.debugNote("Built " .. #snd.campaign.targets .. " targets from cp check")
    if snd.campaign.active and snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "cp", {save = true, refresh = false})
    end
end

-------------------------------------------------------------------------------
-- Target List Management
-------------------------------------------------------------------------------

--- Determine if targets are area-based or room-based
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

function snd.cp.resolveZonesForTarget(target, playerLevel)
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
    local areaCache = {}
    local function getAreaCached(zone)
        if areaCache[zone] == nil then
            areaCache[zone] = (snd.db.getArea and snd.db.getArea(zone)) or false
        end
        return areaCache[zone] or nil
    end
    local function levelOk(area)
        local minLvl = tonumber(area and area.minlvl) or 0
        local maxLvl = tonumber(area and area.maxlvl) or 0
        if not levelKnown then return true end
        if minLvl == 0 and maxLvl == 0 then return true end
        return playerLevel >= minLvl and playerLevel <= (maxLvl + 25)
    end
    local function rowMatchesPriority(row)
        if not row then return false end
        local priorityRoom = tonumber(row.priority_room)
        local roomId = tonumber(row.roomid)
        return tonumber(row.priority_match) == 1
            or (priorityRoom ~= nil and roomId ~= nil and priorityRoom == roomId)
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
                local area = getAreaCached(zone)
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
                    })
                end
            end
        end
        if #results == 0 then return nil end
        return results
    end

    if not snd.db or not snd.db.getMobLocations or not target.mob or target.mob == "" then
        return tryMapperFallback() or fallback
    end

    local rows = snd.db.getMobLocations(
        target.mob,
        "",
        (hint ~= "" and { roomHint = hint } or nil)
    ) or {}
    if #rows == 0 and hint ~= "" then
        rows = snd.db.getMobLocations(target.mob, "") or {}
    end
    if #rows == 0 then
        return tryMapperFallback() or fallback
    end

    if hint ~= "" then
        local hintLower = hint:lower()
        local primary = {}
        for _, row in ipairs(rows) do
            local zone = tostring(row.zone or "")
            if zone ~= "" and row.room and tostring(row.room):lower() == hintLower then
                local area = getAreaCached(zone)
                if levelOk(area) then
                    table.insert(primary, {
                        arid = zone,
                        areaName = (area and area.name) or hint,
                        roomName = row.room,
                        roomId = tonumber(row.roomid),
                        seenCount = tonumber(row.seen_count) or 0,
                        priorityMatch = rowMatchesPriority(row),
                        fromDb = true,
                    })
                end
            end
        end
        if #primary > 0 then
            table.sort(primary, function(a, b)
                if (a.priorityMatch == true) ~= (b.priorityMatch == true) then
                    return a.priorityMatch == true
                end
                return (a.seenCount or 0) > (b.seenCount or 0)
            end)
            return primary
        end
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
        return fallback
    end

    for _, zone in ipairs(zoneOrder) do
        local agg = byZone[zone]
        table.sort(agg.rooms, function(a, b)
            local aPriority = rowMatchesPriority(a)
            local bPriority = rowMatchesPriority(b)
            if aPriority ~= bPriority then
                return aPriority
            end
            return (tonumber(a.seen_count) or 0) > (tonumber(b.seen_count) or 0)
        end)
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
        local area = getAreaCached(zone)
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
            })
        end
    end

    if #kept == 0 then
        snd.utils.debugNote(string.format(
            "CP filter: dropped '%s' — no zone fits level %d (mob in %d zone(s) total)",
            tostring(target.mob), playerLevel, #zoneOrder
        ))
        return tryMapperFallback() or fallback
    end

    if hint ~= "" and #kept > 1 then
        local hintLower = hint:lower()
        for _, z in ipairs(kept) do
            if z.areaName and z.areaName:lower() == hintLower then
                return { z }
            end
        end
    end


    return kept
end

--- Keep scoped/current CP target aligned with the rebuilt CP target list.
-- Clears stale selections so follow-up actions do not operate on removed mobs.
function snd.cp.reconcileSelectionAfterRebuild()
    local cpEntries = {}
    for _, entry in ipairs(snd.targets.list or {}) do
        if entry.activity == "cp" and not entry.dead then
            table.insert(cpEntries, entry)
        end
    end

    local function matchesEntry(selection, entry)
        if type(selection) ~= "table" or type(entry) ~= "table" then
            return false
        end

        local selMob = tostring(selection.name or selection.mob or ""):lower()
        local entryMob = tostring(entry.mob or ""):lower()
        if selMob == "" or entryMob == "" or selMob ~= entryMob then
            return false
        end

        local selArea = tostring(selection.areaName or selection.loc or selection.area or ""):lower()
        local entryArea = tostring(entry.loc or entry.areaName or entry.area or ""):lower()
        if selArea ~= "" and entryArea ~= "" and selArea ~= entryArea then
            return false
        end

        return true
    end

    local function selectionStillValid(selection)
        if type(selection) ~= "table" then
            return false
        end
        if selection.activity ~= "cp" then
            return true
        end
        for _, entry in ipairs(cpEntries) do
            if matchesEntry(selection, entry) then
                return true
            end
        end
        return false
    end

    local clearedScoped = false
    local clearedCurrent = false

    if snd.targets and snd.targets.scoped and snd.targets.scoped.cp and not selectionStillValid(snd.targets.scoped.cp) then
        snd.targets.scoped.cp = nil
        clearedScoped = true
    end

    if snd.targets and snd.targets.current and snd.targets.current.activity == "cp"
        and not selectionStillValid(snd.targets.current) then
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

--- Build the main target list from campaign targets
function snd.cp.buildMainTargetList()
    -- Remove existing CP targets but preserve GQ and Quest targets
    local newList = {}
    for _, t in ipairs(snd.targets.list) do
        if t.activity ~= "cp" then
            table.insert(newList, t)
        end
    end
    snd.targets.list = newList

    local playerLevel = tonumber(snd.char and snd.char.level) or 0
    local emittedAnyRoomTarget = false
    local highEntries = {}
    local lowEntries = {}

    for i, target in ipairs(snd.campaign.targets) do
        local resolved = snd.cp.resolveZonesForTarget(target, playerLevel)
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
            local arid = zone.arid or ""
            local tags = snd.db and snd.db.getMobTags and snd.db.getMobTags(target.mob, arid) or nil
            zone.tags = tags
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
        if not areaGroupSeen[arid] then
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

    for _, entry in ipairs(cpEntries) do
        entry._areaGroup = nil
    end

    local cpDisplayIndex = 0
    local cpListIndex = 0
    for _, entry in ipairs(cpEntries) do
        cpListIndex = cpListIndex + 1
        entry.cpListIndex = cpListIndex
        if not entry.dead then
            cpDisplayIndex = cpDisplayIndex + 1
            entry.displayIndex = cpDisplayIndex
        else
            entry.displayIndex = nil
        end
        table.insert(snd.targets.list, entry)
    end

    if emittedAnyRoomTarget then
        snd.campaign.targetType = "room"
        snd.targets.type = "room"
    end

    snd.utils.debugNote("Built main target list: " .. #snd.targets.list .. " CP targets (level " .. playerLevel .. ")")
    snd.cp.reconcileSelectionAfterRebuild()
end

--- Update target status from cp check results
function snd.cp.updateTargetStatus()
    -- Mark all as potentially alive first
    -- Then mark as dead based on check list

    local cpCampaignIndex = 0
    for _, campaignTarget in ipairs(snd.campaign.targets or {}) do
        cpCampaignIndex = cpCampaignIndex + 1
        local wasDead = campaignTarget.dead == true
        local wasKilled = campaignTarget.killed == true
        campaignTarget.dead = true
        for _, check in ipairs(snd.campaign.checkList) do
            if campaignTarget.mob == check.mob and (campaignTarget.loc or "") == (check.loc or "") then
                campaignTarget.dead = check.dead or wasDead
                break
            end
        end
        -- Preserve player-killed flag only while the mob is still dead in our state.
        -- If the mob is now alive (respawned or never died), clear the killed flag.
        campaignTarget.killed = (campaignTarget.dead and wasKilled) and true or false
    end

    local cpList = {}
    local nonCpList = {}
    local consumedChecks = {}
    for _, target in ipairs(snd.targets.list) do
        if target.activity == "cp" then
            local wasDead = target.dead == true
            local wasKilled = target.killed == true
            target.dead = false
            target.killed = false

            local found = false
            for idx, check in ipairs(snd.campaign.checkList) do
                if not consumedChecks[idx]
                    and target.mob == check.mob
                    and (target.loc or "") == (check.loc or "") then
                    found = true
                    consumedChecks[idx] = true
                    target.dead = check.dead or wasDead
                    break
                end
            end
            if not found then
                for idx, check in ipairs(snd.campaign.checkList) do
                    if not consumedChecks[idx] and target.mob == check.mob then
                        found = true
                        consumedChecks[idx] = true
                        target.dead = check.dead or wasDead
                        break
                    end
                end
            end

            -- If not in check list, mark the entry dead (matches the original
            -- behavior). Don't infer killed=true here: this branch also fires
            -- for duplicate zones whose sibling already consumed the matching
            -- check-list row, and those are not player kills. Real kills mark
            -- killed=true on the specific entry in onMobKilled, so preserving
            -- wasKilled is sufficient.
            if not found then
                target.dead = true
                target.killed = wasKilled
            else
                target.killed = (target.dead and wasKilled) and true or false
            end
            table.insert(cpList, target)
        else
            table.insert(nonCpList, target)
        end
    end

    local currentArid = (snd.room and snd.room.current and tostring(snd.room.current.arid or "")) or ""
    local currentAreaHasAlive = false
    if currentArid ~= "" then
        for _, entry in ipairs(cpList) do
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
    for _, entry in ipairs(cpList) do
        local arid = tostring(entry.arid or "")
        if not areaGroupSeen[arid] then
            areaGroupCount = areaGroupCount + 1
            areaGroupSeen[arid] = areaGroupCount
        end
        entry._areaGroup = areaGroupSeen[arid]
    end

    table.sort(cpList, function(a, b)
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

    for _, entry in ipairs(cpList) do
        entry._areaGroup = nil
    end

    local cpIndex = 0
    local cpListIndex = 0
    for _, target in ipairs(cpList) do
        cpListIndex = cpListIndex + 1
        target.cpListIndex = cpListIndex
        if not target.dead then
            cpIndex = cpIndex + 1
            target.displayIndex = cpIndex
        else
            target.displayIndex = nil
        end
    end

    snd.targets.list = {}
    for _, target in ipairs(nonCpList) do
        table.insert(snd.targets.list, target)
    end
    for _, target in ipairs(cpList) do
        table.insert(snd.targets.list, target)
    end
end

-------------------------------------------------------------------------------
-- Campaign Events
-------------------------------------------------------------------------------

--- Handle campaign mob killed
function snd.cp.onMobKilled()
    snd.utils.debugNote("Campaign mob killed!")
    local shouldSyncAfterKill = true
    local killedTargetsBefore = 0
    for _, target in ipairs(snd.targets.list or {}) do
        if target.activity == "cp" and target.killed then
            killedTargetsBefore = killedTargetsBefore + 1
        end
    end
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

    -- Record the kill if we have a current target
    if snd.targets.current and snd.targets.current.activity == "cp" then
        local roomId = snd.room and snd.room.current and snd.room.current.id or nil
        local killedMobName = confirmedKilledMob ~= "" and confirmedKilledMob or snd.targets.current.name or ""
        if type(raiseEvent) == "function" then
            -- Integration surface: external scripts can listen to "snd.kill.confirmed"
            raiseEvent("snd.kill.confirmed", killedMobName, roomId)
        end
        local target = snd.targets.current

        -- Mark as dead in target list
        local bestIndex, bestScore = nil, -1
        local currentArea = snd.room and snd.room.current and tostring(snd.room.current.arid or "") or ""
        local currentRoom = snd.room and snd.room.current and tostring(snd.room.current.name or "") or ""
        for i, t in ipairs(snd.targets.list) do
            if t.activity == "cp" and not t.dead then
                local nameMatchesCurrent = (t.mob == target.name)
                local nameMatchesConfirmedKill = (confirmedKilledMob ~= "" and t.mob == confirmedKilledMob)
                local nameMatchesActiveCombat = (activeCombatMob ~= "" and t.mob == activeCombatMob)
                if nameMatchesCurrent or nameMatchesConfirmedKill or nameMatchesActiveCombat then
                    local score = 5
                    if nameMatchesConfirmedKill then score = score + 8 end
                    if nameMatchesActiveCombat then score = score + 4 end
                    if t.arid and currentArea ~= "" and tostring(t.arid) == currentArea then score = score + 3 end
                    if t.roomName and currentRoom ~= "" and tostring(t.roomName) == currentRoom then score = score + 2 end
                    if target.index and t.displayIndex and tonumber(target.index) == tonumber(t.displayIndex) then
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
            local killedEntry = snd.targets.list[bestIndex]
            killedEntry.dead = true
            killedEntry.killed = true
            -- Mirror the killed flag onto snd.campaign.targets so it survives
            -- the next buildTargetListFromCheck rebuild. Match by campaignIndex
            -- rather than (mob, loc): buildMainTargetList rewrites entry.loc to
            -- zone.areaName, which won't equal the campaign target's original
            -- check-list location for room-based campaigns.
            local campaignIdx = tonumber(killedEntry.campaignIndex)
            local ct = campaignIdx and snd.campaign.targets and snd.campaign.targets[campaignIdx]
            if ct and ct.mob == killedEntry.mob then
                ct.dead = true
                ct.killed = true
            else
                for _, c in ipairs(snd.campaign.targets or {}) do
                    if c.mob == killedEntry.mob and not c.killed then
                        c.dead = true
                        c.killed = true
                        break
                    end
                end
            end
        end
        snd.cp.updateTargetStatus()
        if snd.cp.getRemainingCount and snd.cp.getRemainingCount() == 0 then
            -- The original skip exists to avoid racing the cp_complete trigger when
            -- the player just killed the final alive target. Only honor it when this
            -- kill is the only one pending refresh; otherwise prior killed-by-player
            -- mobs would stay in the list as [Killed] forever because no future cp
            -- check would ever fire to clear them.
            local killedPendingCount = 0
            for _, t in ipairs(snd.targets.list) do
                if t.activity == "cp" and t.killed then
                    killedPendingCount = killedPendingCount + 1
                end
            end
            if killedPendingCount <= 1 then
                shouldSyncAfterKill = false
                snd.utils.debugNote("Skipping post-kill cp check because last campaign target was just killed")
            end
        end
        
        -- Clear current target
        snd.clearTarget()
    end
    
    local killedTargetsAfter = 0
    for _, target in ipairs(snd.targets.list or {}) do
        if target.activity == "cp" and target.killed then
            killedTargetsAfter = killedTargetsAfter + 1
        end
    end
    local markedTargetKilled = killedTargetsAfter > killedTargetsBefore

    -- The server confirmed a campaign kill, but no CP entry gained the [Killed]
    -- state in S&D's target window. Force a refresh without waiting for AutoCheck.
    if not markedTargetKilled then
        snd.utils.debugNote("Campaign kill marked no CP target killed; forcing cp check")
        snd.cp.requestCheck(0.1, "cp.onMobKilled:no-target-marked-killed", true)

    -- Otherwise, trigger cp check according to the normal AutoCheck policy.
    -- Do not re-check immediately after the last kill; completion parsing/DB close
    -- should proceed without a terminal "not on campaign" sync race.
    elseif shouldSyncAfterKill and (not snd.shouldAutoCheckAfterKill or snd.shouldAutoCheckAfterKill("cp")) then
        snd.cp.requestCheck(0.1, "cp.onMobKilled")
    end
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
    if snd.setActiveTab and snd.getPreferredActiveActivity then
        snd.setActiveTab(snd.getPreferredActiveActivity() or "auto", {save = true, refresh = false})
    end
end

--- Handle campaign complete
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

--- Mark campaign completion as pending so the first-campaign daily bonus can arrive.
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

--- Finalize a pending campaign completion once the daily bonus is known or timed out.
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

--- Capture the first-campaign daily QP bonus and close the pending completion early.
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

--- Observe campaign completion footer separators. Completion waits for bonus or timer.
function snd.cp.onCompletionSeparator()
    return snd.cp.parsing.completionPending == true
end

--- Handle campaign quit/cleared
function snd.cp.onQuit()
    snd.utils.reportLine("Campaign cleared.", "campaign")
    
    -- Record as failed in history
    if snd.db then
        snd.cp.closeHistorySession(snd.db.HISTORY_STATUS_FAILED, nil, "campaign cleared")
    end
    
    snd.cp.clearCampaign()
end

--- Handle not on campaign message
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

--- Handle the first positive signal that a campaign has been accepted.
function snd.cp.onCampaignAccepted()
    snd.campaign.canGetNew = false
    snd.campaign.acceptedAt = os.time()

    if snd.gmcp and snd.gmcp.setCampaignActiveForAutoNoexp then
        snd.gmcp.setCampaignActiveForAutoNoexp()
    end
end

--- Clear campaign state
function snd.cp.clearCampaign()
    snd.campaign.active = false
    snd.campaign.levelTaken = 0
    snd.campaign.completeBy = ""
    snd.campaign.acceptedAt = 0
    snd.campaign.targets = {}
    snd.campaign.checkList = {}
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

    -- Clear targets if no gquest
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

--- Handle can get new campaign
function snd.cp.onCanGetNew()
    snd.campaign.canGetNew = true
    snd.utils.debugNote("Can get new campaign")

    if snd.cp.parsing.completionPending then
        snd.cp.finalizePendingCompletion("campaign eligibility arrived during completion wait")
        return
    end

    if snd.db and snd.cp.hasOpenHistorySession() and not snd.campaign.active then
        snd.cp.closeHistorySession(snd.db.HISTORY_STATUS_RESET, nil, "campaign eligibility indicates prior campaign ended")
    end
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

--- Return local-date key used for campaign "today" counters.
-- @return string
function snd.cp.getTodayDateKey()
    return os.date("%Y-%m-%d")
end

--- Ensure campaign "today" counter is scoped to the current local date.
function snd.cp.normalizeCampaignTodayCounter()
    local today = snd.cp.getTodayDateKey()
    if snd.campaign.completedTodayDate ~= today then
        snd.campaign.completedTodayDate = today
        snd.campaign.completedToday = 0
    end
end

--- Overwrite campaign completion count for today (from cp check/cp today output).
-- @param count number
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

--- Increment campaign completion count for today (when campaign completion is detected).
function snd.cp.incrementCampaignsCompletedToday()
    snd.cp.normalizeCampaignTodayCounter()
    snd.campaign.completedToday = (tonumber(snd.campaign.completedToday) or 0) + 1
    snd.campaign.completedTodayDate = snd.cp.getTodayDateKey()
    if snd.saveState then
        snd.saveState()
    end
end

--- Record a local campaign completion unless the server count already advanced.
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

-------------------------------------------------------------------------------
-- Campaign Target Selection
-------------------------------------------------------------------------------

--- Select a campaign target by index
-- @param index Target index (1-based)
function snd.cp.selectTarget(index)
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
    })
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
    
    local areaInfo = ""
    if target.loc and target.loc ~= "" then
        areaInfo = " in " .. target.loc
    end
    snd.utils.infoNote("Target: " .. target.mob .. areaInfo)
    return true
end

--- Get next available campaign target
function snd.cp.getNextTarget()
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "cp" and not t.dead then
            return t
        end
    end
    return nil
end

--- Count remaining campaign targets
function snd.cp.getRemainingCount()
    local count = 0
    for _, t in ipairs(snd.targets.list) do
        if t.activity == "cp" and not t.dead then
            count = count + 1
        end
    end
    return count
end

-- Module loaded silently
