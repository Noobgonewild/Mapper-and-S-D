--[[
    Search and Destroy - Triggers Module
    Mudlet Port
    
    Original MUSHclient plugin by Crowley
    Ported to Mudlet
    
    This module contains all trigger callback functions
]]

snd = snd or {}
snd.triggers = snd.triggers or {}


local function playConfiguredSound(soundFile, fallbackFile)
    if snd and snd.config and snd.config.soundEnabled == false then
        return
    end
    if type(playSoundFile) ~= "function" then
        return
    end

    local volume = tonumber(snd and snd.config and snd.config.soundVolume) or 100
    volume = math.max(0, math.min(100, math.floor(volume + 0.5)))

    local candidates = {}

    if type(getMudletHomeDir) == "function" then
        local base = getMudletHomeDir()
        if base and base ~= "" then
            table.insert(candidates, base .. "/" .. soundFile)
            if fallbackFile and fallbackFile ~= "" and fallbackFile ~= soundFile then
                table.insert(candidates, base .. "/" .. fallbackFile)
            end
        end
    end

    table.insert(candidates, soundFile)
    if fallbackFile and fallbackFile ~= "" and fallbackFile ~= soundFile then
        table.insert(candidates, fallbackFile)
    end

    for _, soundPath in ipairs(candidates) do
        local ok = pcall(playSoundFile, {name = soundPath, volume = volume})
        if ok then return end
        ok = pcall(playSoundFile, soundPath, volume)
        if ok then return end
    end
end

local function scheduleCpInfoEnd()
    if not (snd.cp and snd.cp.parsing and snd.cp.parsing.infoActive) then
        return
    end

    if snd.cp.parsing.infoEndTimer then
        killTimer(snd.cp.parsing.infoEndTimer)
    end

    snd.cp.parsing.infoEndTimer = tempTimer(0.75, function()
        if snd.cp and snd.cp.parsing and snd.cp.parsing.infoActive then
            snd.cp.endCpInfo()
        end
        if snd.cp and snd.cp.parsing then
            snd.cp.parsing.infoEndTimer = nil
        end
    end)
end

local function scheduleGqInfoEnd()
    if not (snd.gq and snd.gq.parsing and snd.gq.parsing.infoActive) then
        return
    end

    if snd.gq.parsing.infoEndTimer then
        pcall(function() killTimer(snd.gq.parsing.infoEndTimer) end)
    end

    snd.gq.parsing.infoEndTimer = tempTimer(0.75, function()
        if snd.gq and snd.gq.parsing and snd.gq.parsing.infoActive then
            snd.gq.endGqInfo()
        end
        if snd.gq and snd.gq.parsing then
            snd.gq.parsing.infoEndTimer = nil
        end
    end)
end

-------------------------------------------------------------------------------
-- Campaign Triggers
-------------------------------------------------------------------------------

--- Campaign info line trigger
-- Matches: "Find and kill 1 * mob name (Location)"
function snd.triggers.cpInfoLine(matches)
    if not matches or not matches[2] then return end
    
    -- Start parsing if not already
    if not snd.cp.parsing.infoActive then
        snd.cp.startCpInfo()
    end
    
    snd.cp.processCpInfoLine(matches[2])
    
    -- Reset end timer on each line (ends when lines stop coming)
    scheduleCpInfoEnd()
end

--- Campaign check line trigger
-- Matches: "You still have to kill * mob name (Location)"
function snd.triggers.cpCheckLine(matches)
    if not matches or not matches[2] then return end
    
    -- Start parsing if not already
    if not snd.cp.parsing.checkActive then
        snd.cp.startCpCheck()
    end
    
    snd.cp.processCpCheckLine(matches[2])
    
    -- Reset end timer on each line (ends when lines stop coming)
    if snd.cp.parsing.endTimer then
        killTimer(snd.cp.parsing.endTimer)
    end
    snd.cp.parsing.endTimer = tempTimer(0.5, function()
        if snd.cp.parsing.checkActive then
            snd.cp.endCpCheck()
        end
        snd.cp.parsing.endTimer = nil
    end)
end

--- Campaign time remaining trigger (explicit end marker for cp info/check)
-- Matches: "You have X days, Y hours..." 
function snd.triggers.cpTimeRemaining(matches)
    -- This signals end of cp info or cp check output
    if snd.cp.parsing.infoActive then
        if snd.cp.parsing.infoEndTimer then
            killTimer(snd.cp.parsing.infoEndTimer)
            snd.cp.parsing.infoEndTimer = nil
        end
        snd.cp.endCpInfo()
    end
    
    if snd.cp.parsing.checkActive then
        if snd.cp.parsing.endTimer then
            killTimer(snd.cp.parsing.endTimer)
            snd.cp.parsing.endTimer = nil
        end
        snd.cp.endCpCheck()
    end
end

--- Campaign info footer trigger
-- Matches: "Use 'cp check' to see only targets that you still need to kill."
function snd.triggers.cpInfoFooter()
    if snd.cp.parsing.infoActive then
        if snd.cp.parsing.infoEndTimer then
            killTimer(snd.cp.parsing.infoEndTimer)
            snd.cp.parsing.infoEndTimer = nil
        end
        snd.cp.endCpInfo()
    end
end

--- Campaign mob killed trigger
function snd.triggers.cpMobKilled()
    if snd.conwin and snd.conwin.confirmPendingCombatDeath then
        snd.conwin.confirmPendingCombatDeath("campaign-kill-message")
    end
    snd.cp.onMobKilled()
end

--- Campaign complete trigger
function snd.triggers.cpComplete()
    if snd.cp and snd.cp.startCompletionPending then
        snd.cp.startCompletionPending()
    end
end

--- First campaign of the day bonus trigger
-- Matches: "You receive 13 quest points bonus for your first campaign completed today."
function snd.triggers.cpFirstDailyBonus(matches)
    if not matches or not matches[2] then return end
    if snd.cp and snd.cp.applyFirstDailyBonus then
        snd.cp.applyFirstDailyBonus(matches[2])
    end
end

--- Campaign completion separator trigger
function snd.triggers.cpCompleteSeparator()
    -- Completion now finalizes from the daily-bonus trigger or a short timer.
    -- Keep this trigger as a harmless no-op for compatibility.
end

--- Campaign quit/cleared trigger
function snd.triggers.cpQuit()
    snd.cp.onQuit()
end

--- Can get new campaign trigger
function snd.triggers.cpCanGetNew()
    snd.cp.onCanGetNew()
    if snd.gmcp and snd.gmcp.setCampaignEligibility then
        snd.gmcp.setCampaignEligibility(true)
    end
    if snd.gmcp and snd.gmcp.checkAutoNoexp then
        snd.gmcp.checkAutoNoexp()
    end
end

function snd.triggers.cpAccepted()
    if snd.cp and snd.cp.onCampaignAccepted then
        snd.cp.onCampaignAccepted()
    end
end

--- Not on campaign trigger
function snd.triggers.cpNotOn()
    snd.cp.onNotOnCampaign()
end

--- Campaign completed-today count trigger
-- Matches: "You have completed 1 campaign today."
--          "You have completed 2 campaigns today."
function snd.triggers.cpCompletedToday(matches)
    if not matches or not matches[2] then return end
    local completedToday = tonumber(matches[2]) or 0
    if snd.cp and snd.cp.setCampaignsCompletedToday then
        snd.cp.setCampaignsCompletedToday(completedToday)
    end
end

--- Auto-noexp manual OFF trigger
function snd.triggers.noexpManualOff()
    local recentAutoEcho = snd.char
        and snd.char.noexpCommandEcho == "on"
        and ((os.clock() - (tonumber(snd.char.noexpCommandAt) or 0)) < 5)
    if snd.char and (snd.char.noexpPending == "on" or recentAutoEcho) then
        snd.char.noexp = true
        snd.char.noexpPending = nil
        snd.char.noexpCommandEcho = nil
        if snd.gui and snd.gui.updateNoexp then
            snd.gui.updateNoexp()
        end
        return
    end

    snd.config.anex.automatic = false
    snd.char.noexp = true
    snd.utils.infoNote("Search and Destroy: noexp is manually OFF. Type 'noexp' again to re-enable automatic mode.")
    if snd.gui and snd.gui.updateNoexp then
        snd.gui.updateNoexp()
    end
end

--- Auto-noexp manual ON trigger
function snd.triggers.noexpManualOn()
    local recentAutoEcho = snd.char
        and snd.char.noexpCommandEcho == "off"
        and ((os.clock() - (tonumber(snd.char.noexpCommandAt) or 0)) < 5)
    if snd.char and (snd.char.noexpPending == "off" or recentAutoEcho) then
        snd.char.noexp = false
        snd.char.noexpPending = nil
        snd.char.noexpCommandEcho = nil
        if snd.gui and snd.gui.updateNoexp then
            snd.gui.updateNoexp()
        end
        return
    end

    snd.config.anex.automatic = true
    snd.char.noexp = false
    if snd.gmcp and snd.gmcp.checkAutoNoexp then
        snd.gmcp.checkAutoNoexp()
    end
    if snd.gui and snd.gui.updateNoexp then
        snd.gui.updateNoexp()
    end
end

--- Auto-noexp xp gain trigger
function snd.triggers.noexpXpGain()
    if snd.gmcp and snd.gmcp.checkAutoNoexp then
        tempTimer(0.1, function()
            snd.gmcp.checkAutoNoexp()
        end)
    end
end

--- Auto-noexp must level trigger
function snd.triggers.noexpMustLevelBeforeCampaign()
    snd.campaign.canGetNew = false

    if snd.gmcp and snd.gmcp.setCampaignEligibility then
        snd.gmcp.setCampaignEligibility(false)
    elseif snd.char and snd.char.noexp then
        if snd.gmcp and snd.gmcp.setNoexp then
            snd.gmcp.setNoexp(false, "Search and Destroy: Turning noexp OFF (you cannot take a campaign at this level yet)", false)
        else
            sendGMCP("config noexp off")
            snd.utils.infoNote("Search and Destroy: Turning noexp OFF (you cannot take a campaign at this level yet)")
        end
    end
    if snd.gui and snd.gui.updateNoexp then
        snd.gui.updateNoexp()
    end
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

-------------------------------------------------------------------------------
-- Global Quest Triggers
-------------------------------------------------------------------------------

--- GQ joined trigger
-- Matches: "You have now joined Global Quest # 123..."
function snd.triggers.gqJoined(matches)
    if not matches or not matches[2] then return end
    snd.gq.onJoined(matches[2])
end

--- GQ started trigger
-- Matches: "Global Quest: Global quest # 123 for levels 1 to 201 has now started."
function snd.triggers.gqStarted(matches)
    if not matches or #matches < 4 then return end
    snd.gq.onStarted(matches[2], matches[3], matches[4])
end

--- GQ info line trigger
-- Matches: "Kill at least 3 * mob name (Location)."
function snd.triggers.gqInfoLine(matches)
    if not matches or #matches < 3 then return end
    
    -- Start parsing if not already
    if not snd.gq.parsing.infoActive then
        -- Try to get GQ ID from somewhere, or use a placeholder
        snd.gq.startGqInfo(snd.gquest.joined or "0")
    end
    
    snd.gq.processGqInfoLine(matches[2], matches[3])
    scheduleGqInfoEnd()
end

--- GQ details header line with explicit quest number.
-- Matches: "Quest Name.........: [ Global quest # 9554 ]"
function snd.triggers.gqQuestName(matches)
    if not matches or not matches[2] then return end
    local gqId = tostring(matches[2])
    if not snd.gq.parsing.infoActive then
        snd.gq.startGqInfo(gqId)
    else
        snd.gq.parsing.currentGqId = gqId
    end
    scheduleGqInfoEnd()
end

--- GQ level range line in details.
-- Matches: "Level range........: [ 109 ] - [ 120 ]"
function snd.triggers.gqLevelRange(matches)
    if not matches or #matches < 3 then return end
    if not snd.gq.parsing.infoActive then
        snd.gq.startGqInfo(snd.gquest.joined or "0")
    end
    snd.gq.processLevelRange(matches[2], matches[3])
    scheduleGqInfoEnd()
end

function snd.triggers.gqInfoRewardQP(matches)
    if not matches or not matches[2] then return end
    local perKill = matches[3]
    snd.gq.captureInfoReward("qp", matches[2], perKill)
    scheduleGqInfoEnd()
end

function snd.triggers.gqInfoRewardTP(matches)
    if not matches or not matches[2] then return end
    snd.gq.captureInfoReward("tp", matches[2])
    scheduleGqInfoEnd()
end

function snd.triggers.gqInfoRewardTrain(matches)
    if not matches or not matches[2] then return end
    snd.gq.captureInfoReward("trains", matches[2])
    scheduleGqInfoEnd()
end

function snd.triggers.gqInfoRewardPrac(matches)
    if not matches or not matches[2] then return end
    snd.gq.captureInfoReward("pracs", matches[2])
    scheduleGqInfoEnd()
end

function snd.triggers.gqInfoRewardGold(matches)
    if not matches or not matches[2] then return end
    snd.gq.captureInfoReward("gold", matches[2])
    scheduleGqInfoEnd()
end

--- GQ per-kill bonus line.
-- Matches: "3 quest points awarded."
function snd.triggers.gqKillBonus(matches)
    if not matches or not matches[2] then return end
    snd.gq.applyKillBonus(matches[2])
end

--- GQ completion reward lines.
-- Matches:
-- "Reward of 28 quest points added."
-- "Reward of 1 trivia point added."
-- "Reward of 2 practice sessions added."
-- "Reward of 10900 gold coins added."
function snd.triggers.gqCompletionRewardQp(matches)
    if not matches or not matches[2] then return end
    snd.gq.captureInfoReward("qp", matches[2])
end

function snd.triggers.gqCompletionRewardTp(matches)
    if not matches or not matches[2] then return end
    snd.gq.captureInfoReward("tp", matches[2])
end

function snd.triggers.gqCompletionRewardTrain(matches)
    if not matches or not matches[2] then return end
    snd.gq.captureInfoReward("trains", matches[2])
end

function snd.triggers.gqCompletionRewardPrac(matches)
    if not matches or not matches[2] then return end
    snd.gq.captureInfoReward("pracs", matches[2])
end

function snd.triggers.gqCompletionRewardGold(matches)
    if not matches or not matches[2] then return end
    snd.gq.captureInfoReward("gold", matches[2])
end

--- GQ check line trigger
-- Matches: "You still have to kill 3 * mob name (Location)"
function snd.triggers.gqCheckLine(matches)
    if not matches or #matches < 3 then return end
    
    -- Start parsing if not already
    if not snd.gq.parsing.checkActive then
        snd.gq.startGqCheck()
    end
    
    snd.gq.processGqCheckLine(matches[2], matches[3])

    if snd.gq.parsing.checkEndTimer then
        pcall(function() killTimer(snd.gq.parsing.checkEndTimer) end)
    end
    snd.gq.parsing.checkEndTimer = tempTimer(0.4, function()
        snd.gq.endGqCheck()
        snd.gq.parsing.checkEndTimer = nil
    end)
end

--- GQ mob killed trigger
function snd.triggers.gqMobKilled()
    if snd.conwin and snd.conwin.confirmPendingCombatDeath then
        snd.conwin.confirmPendingCombatDeath("gquest-kill-message")
    end
    snd.gq.onMobKilled()
end

--- GQ winner trigger
-- Matches: "Global Quest: Global Quest # 123 has been won by PlayerName - 1st win."
function snd.triggers.gqWinner(matches)
    if not matches or #matches < 3 then return end
    snd.gq.onWinner(matches[2], matches[3])
end

--- GQ may-win-more trigger
function snd.triggers.gqMayWinMore()
    snd.gq.onMayWinMore()
end

--- GQ ended trigger
function snd.triggers.gqEnded(matches)
    if not matches or not matches[2] then return end
    snd.gq.onEnded(matches[2])
end

--- GQ quit trigger
-- Matches: "You are no longer part of Global Quest # 123 and will be unable to rejoin."
function snd.triggers.gqQuit(matches)
    if not matches or not matches[2] then return end
    snd.gq.onQuit(matches[2])
end

--- Not on GQ trigger
function snd.triggers.gqNotOn()
    snd.gq.onNotOnGquest()
end

-------------------------------------------------------------------------------
-- Quest Triggers
-------------------------------------------------------------------------------

--- Quest blessing bonus trigger
-- Matches: "You receive 29 bonus quest points from your daily blessing."
function snd.triggers.questBlessing(matches)
    if not matches or not matches[2] then return end
    local bonus = tonumber(matches[2]) or 0
    snd.quest.blessingBonus = bonus

    if snd.quest.rewardTimer then
        killTimer(snd.quest.rewardTimer)
        snd.quest.rewardTimer = nil
    end

    snd.quest.rewardTimer = tempTimer(0.5, function()
        snd.gmcp.emitQuestReward()
    end)
end

--- Quest reward line fallback trigger
-- Matches: "An old MacBook tells you 'As a reward, I am giving you 10 quest points and 3175 gold.'"
-- Used when GMCP completion packets are missing; seeds pending reward so blessing/extra triggers can still emit.
function snd.triggers.questRewardLine(matches)
    if not matches or not matches[2] or not matches[3] then
        return
    end

    if snd.quest.pendingReward then
        return
    end

    local qp = tonumber(matches[2]) or 0
    local gold = tonumber(matches[3]) or 0

    snd.gmcp.onQuestComplete({
        qp = qp,
        gold = gold,
        tp = 0,
        trains = 0,
        pracs = 0,
    })
end

--- Quest extra qp trigger
-- Matches: "You get lucky and gain an extra 2 quest points."
function snd.triggers.questExtraQp(matches)
    if not matches or not matches[2] then return end
    local bonus = tonumber(matches[2]) or 0
    snd.quest.extraBonus = bonus

    if snd.quest.rewardTimer then
        killTimer(snd.quest.rewardTimer)
        snd.quest.rewardTimer = nil
    end

    snd.quest.rewardTimer = tempTimer(0.5, function()
        snd.gmcp.emitQuestReward()
    end)
end

function snd.triggers.questCooldownMinutes(matches)
    if not matches or not matches[2] then return end
    local minutes = tonumber(matches[2])
    if not minutes then return end
    if snd.quest and snd.quest.consumeSilentCooldownRequest and snd.quest.consumeSilentCooldownRequest() then
        if type(deleteLine) == "function" then
            deleteLine()
        end
    end
    snd.quest.active = false
    snd.quest.available = false
    snd.quest.target.status = "0"
    snd.quest.setCooldown(minutes, {lessThanMinute = false, text = ""})
    snd.quest.stopReadySoundReminder()
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

function snd.triggers.questCooldownLessThanMinute()
    if snd.quest and snd.quest.consumeSilentCooldownRequest and snd.quest.consumeSilentCooldownRequest() then
        if type(deleteLine) == "function" then
            deleteLine()
        end
    end
    snd.quest.active = false
    snd.quest.available = false
    snd.quest.target.status = "0"
    snd.quest.setCooldown(1, {lessThanMinute = true, text = "Less than a minute remaining"})
    snd.quest.stopReadySoundReminder()
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

local function playQuestReadyWarning()
    playConfiguredSound("SearchAndDestroy/quest_ready.wav", "sounds/quest_ready.wav")
end

function snd.quest.stopReadySoundReminder()
    if snd.quest.readySoundTimerId then
        killTimer(snd.quest.readySoundTimerId)
        snd.quest.readySoundTimerId = nil
    end
end

function snd.quest.playReadySoundReminder()
    if not (snd.quest and snd.quest.available and not snd.quest.active) then
        if snd.quest and snd.quest.stopReadySoundReminder then
            snd.quest.stopReadySoundReminder()
        end
        return
    end

    playQuestReadyWarning()
    snd.quest.readySoundLastPlayedAt = os.time()
end

function snd.quest.startReadySoundReminder(opts)
    local options = opts or {}
    if not (snd.quest and snd.quest.available and not snd.quest.active) then
        return
    end

    if snd.quest.readySoundTimerId then
        return
    end

    if options.playNow ~= false then
        local now = os.time()
        local lastPlayed = tonumber(snd.quest.readySoundLastPlayedAt) or 0
        if now - lastPlayed >= 2 then
            snd.quest.playReadySoundReminder()
        end
    end

    snd.quest.readySoundTimerId = tempTimer(60, function()
        if snd.quest and snd.quest.playReadySoundReminder then
            snd.quest.playReadySoundReminder()
        end
    end, true)
end

function snd.triggers.gqAboutToStart(matches)
    playConfiguredSound("SearchAndDestroy/GQ about to start.wav")

    -- Browse the announced quest's details without joining it.
    if matches and matches[2] then
        send("gq i " .. tostring(matches[2]), false)
    end
end

function snd.triggers.targetKilledSound()
    playConfiguredSound("SearchAndDestroy/target_killed.wav")
end

function snd.triggers.questReady()
    if snd.quest and snd.quest.consumeSilentCooldownRequest then
        snd.quest.consumeSilentCooldownRequest()
    end
    snd.quest.active = false
    snd.quest.available = true
    snd.quest.target.status = "0"
    snd.quest.setCooldown(0, {lessThanMinute = false, text = ""})
    snd.quest.startReadySoundReminder()
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

--- Quest target line tagger
function snd.triggers.questTargetLine()
    if not snd.quest or not snd.quest.target or snd.quest.target.mob == "" then
        return
    end

    return
end

-------------------------------------------------------------------------------
-- Current Target Line Tagger (CP)
-------------------------------------------------------------------------------

local function appendTargetTag(tag, color)
    if not snd.roomChars or not snd.roomChars.active then
        return
    end

    local line = getCurrentLine()
    if not line or line:find(tag, 1, true) then
        return
    end

    local tagText = " " .. color .. tag .. "<white>"

    -- Suffix the matched line in place so room-char colors stay intact.
    if type(suffix) == "function" and type(cecho) == "function" then
        suffix(tagText, cecho)
        return
    end

    -- Fallback for older Mudlet builds without suffix().
    if type(cecho) == "function" then
        cecho(tagText)
        return
    end

    -- Fallback if colored echo is unavailable.
    if type(replaceLine) == "function" then
        replaceLine(line .. " " .. tag)
    end
end

function snd.triggers.tagCpTargetLine()
    appendTargetTag("[CP]", "<ansiCyan>")
end

function snd.triggers.tagGqTargetLine()
    appendTargetTag("[GQ]", "<yellow>")
end

function snd.triggers.tagQuestTargetLine()
    -- The server already identifies the real quest instance with a trailing
    -- [QUEST]. Keep room output authoritative and reserve [Q] for ConWin.
    return false
end

local function currentRoomCharsRoomId()
    local roomInfo = gmcp and gmcp.room and gmcp.room.info or nil
    if type(roomInfo) == "table" and type(mm) == "table"
        and type(mm.canonical_room_uid) == "function"
    then
        local ok, roomId = pcall(mm.canonical_room_uid, roomInfo)
        if ok and roomId ~= nil and tostring(roomId) ~= "" then
            return tostring(roomId)
        end
    end

    local roomId = snd.room and snd.room.current and snd.room.current.rmid or nil
    if roomId ~= nil and tostring(roomId) ~= "" then
        return tostring(roomId)
    end
    return tostring(type(roomInfo) == "table" and roomInfo.num or "")
end

local function currentTargetTagArea()
    return snd.utils.trim(snd.room and snd.room.current and snd.room.current.arid or ""):lower()
end

local function resolvedTargetTagArea(target)
    local area = snd.utils.trim(target and target.arid or "")
    local needsResolution = area == ""
    if needsResolution and target then area = snd.utils.trim(target.area or target.loc or "") end
    if needsResolution and area ~= "" and snd.db and snd.db.getAreaKeyFromName then
        area = snd.db.getAreaKeyFromName(area) or area
    end
    return tostring(area or ""):lower()
end

local function targetActivityIsLive(target)
    if not target or target.dead or target.killed then return false end
    if target.activity == "cp" then return snd.campaign and snd.campaign.active == true end
    if target.activity == "gq" then return snd.gquest and snd.gquest.active == true end
    if target.activity == "quest" then
        local status = snd.quest and snd.quest.target and tostring(snd.quest.target.status or "") or ""
        return status == "2" or status == "active" or status == "missing"
    end
    return false
end

local function markerSetFromText(text)
    local tags = {}
    if tostring(text):find("[Q]", 1, true) then tags.quest = true end
    if tostring(text):find("[CP]", 1, true) then tags.cp = true end
    if tostring(text):find("[GQ]", 1, true) then tags.gq = true end
    return tags
end

function snd.triggers.tagCurrentRoomCharsLine()
    if not (snd.roomChars and snd.roomChars.active) then return end
    local line = snd.utils.stripColors(type(getCurrentLine) == "function" and getCurrentLine() or ""):lower()
    if line == "" or line == "{roomchars}" or line == "{/roomchars}" then return end

    -- RoomChars and `consider all` describe the same inhabitants in the same
    -- order, but they do not necessarily use the same visible description.
    -- Capture the server's [QUEST] marker by absolute row number so a line such
    -- as "a half-giant ... [QUEST]" can bind to "a driller" in consider output.
    local evidence = snd.roomChars.questTargetEvidence
    if evidence and not evidence.complete then
        evidence.characterCount = (tonumber(evidence.characterCount) or 0) + 1
        if line:match("%[quest%]%s*$") then
            evidence.markedOrdinal = evidence.characterCount
        end
    end

    local tags = {}
    for _, matcher in ipairs(snd.roomChars.targetMatchers or {}) do
        if matcher.name ~= "" and line:find(matcher.name, 1, true) then
            for activity in pairs(matcher.tags or {}) do tags[activity] = true end
        end
    end

    if tags.cp then snd.triggers.tagCpTargetLine() end
    if tags.gq then snd.triggers.tagGqTargetLine() end
end

function snd.triggers.registerTargetLineTriggers()
    snd.triggers.unregisterTargetLineTriggers()
    snd.roomChars = snd.roomChars or {}
    local currentArea = currentTargetTagArea()
    snd.roomChars.targetMatcherArea = currentArea
    if not snd.targets or not snd.targets.list or #snd.targets.list == 0 then
        return
    end

    local byName = {}
    local function addMatcher(rawName, activity)
        local name = snd.utils.trim(snd.utils.stripColors(rawName or "")):lower()
        if name == "" then return end
        local matcher = byName[name]
        if not matcher then
            matcher = {name = name, tags = {}}
            byName[name] = matcher
        end
        matcher.tags[activity] = true
    end

    for _, target in ipairs(snd.targets.list) do
        if targetActivityIsLive(target) and currentArea ~= ""
            and resolvedTargetTagArea(target) == currentArea
        then
            addMatcher(target.mob or target.name, target.activity)
            addMatcher(target.matchedMobName, target.activity)
        end
    end

    -- A successfully parsed consider roster can contribute the exact visible
    -- description when it already resolves unambiguously to an activity target.
    if snd.conwin and snd.conwin.activityMarkersForMob then
        for _, mob in ipairs(snd.conwin.mobs or {}) do
            local markerText = snd.conwin.activityMarkersForMob(mob.name or "")
            for activity in pairs(markerSetFromText(markerText)) do
                addMatcher(mob.name, activity)
            end
        end
    end

    snd.roomChars.targetMatchers = {}
    for _, matcher in pairs(byName) do
        snd.roomChars.targetMatchers[#snd.roomChars.targetMatchers + 1] = matcher
    end
    table.sort(snd.roomChars.targetMatchers, function(a, b) return a.name < b.name end)
    snd.roomChars.targetMatcherArea = currentArea
end

-------------------------------------------------------------------------------
-- Room Character Tag Boundaries
-------------------------------------------------------------------------------

function snd.triggers.roomCharsStart()
    snd.roomChars = snd.roomChars or {}
    snd.roomChars.active = true
    snd.roomChars.questTargetEvidence = {
        roomId = currentRoomCharsRoomId(),
        characterCount = 0,
        markedOrdinal = nil,
        complete = false,
    }
    -- Clean up a line-capture trigger left by an older plugin version. ConWin
    -- must only consume consider output, never the broad RoomChars stream.
    if snd.roomChars.lineCaptureId then
        pcall(killTrigger, snd.roomChars.lineCaptureId)
        snd.roomChars.lineCaptureId = nil
    end
    snd.roomChars.lineCaptureId = tempRegexTrigger("^.*$", snd.triggers.tagCurrentRoomCharsLine)
    if snd.conwin and snd.conwin.onMobdetectRoomcharsStart then
        snd.conwin.onMobdetectRoomcharsStart()
    end
end

function snd.triggers.roomCharsEnd()
    snd.roomChars = snd.roomChars or {}
    if snd.roomChars.lineCaptureId then
        pcall(killTrigger, snd.roomChars.lineCaptureId)
        snd.roomChars.lineCaptureId = nil
    end
    snd.roomChars.active = false
    if snd.roomChars.questTargetEvidence then
        snd.roomChars.questTargetEvidence.complete = true
    end
    if snd.conwin and snd.conwin.onRoomcharsEnd then
        snd.conwin.onRoomcharsEnd()
    end
    if snd.conwin and snd.conwin.onQuestTargetEvidenceUpdated then
        snd.conwin.onQuestTargetEvidenceUpdated(snd.roomChars.questTargetEvidence)
    end
end

function snd.triggers.registerRoomCharsBoundaryTriggers()
    snd.roomChars = snd.roomChars or {}
    if snd.roomChars.triggerIds then
        return
    end

    local startId = tempRegexTrigger("^\\{roomchars\\}$", snd.triggers.roomCharsStart)
    local endId = tempRegexTrigger("^\\{/roomchars\\}$", snd.triggers.roomCharsEnd)
    snd.roomChars.triggerIds = {startId, endId}
end

function snd.triggers.registerQuestCooldownTriggers()
    snd.quest = snd.quest or {}
    if snd.quest.cooldownTriggerIds then
        return
    end

    local ids = {}
    table.insert(ids, tempRegexTrigger(
        "^\\s*There (?:is|are) (\\d+) minute(?:s)? remaining until you can go on another quest\\.?\\s*$",
        snd.triggers.questCooldownMinutes
    ))
    table.insert(ids, tempRegexTrigger(
        "^There is less than a minute remaining until you can go on another quest\\.$",
        snd.triggers.questCooldownLessThanMinute
    ))
    table.insert(ids, tempRegexTrigger(
        "^QUEST: You may now quest again\\.$",
        snd.triggers.questReady
    ))
    table.insert(ids, tempRegexTrigger(
        "^You do not have to wait to go on another quest\\.$",
        snd.triggers.questReady
    ))
    snd.quest.cooldownTriggerIds = ids
end

function snd.triggers.onWhereCommandIssued()
    if not snd.nav.quickWhere then
        return
    end

    local quickWhere = snd.nav.quickWhere
    if quickWhere.completed == true and quickWhere.awaitingCommandEcho ~= true then
        snd.utils.qwDebugNote("QW DEBUG: ignoring where echo for completed quick-where lookup")
        return
    end

    if quickWhere.processed ~= false and quickWhere.awaitingCommandEcho ~= true then
        return
    end

    snd.utils.qwDebugNote("QW DEBUG: where command observed, enabling QuickWhere capture")
    quickWhere.lastMatch = nil
    quickWhere.pendingMatches = {}
    quickWhere.processed = false
    quickWhere.awaitingCommandEcho = false
    quickWhere.probePending = false
    quickWhere.commandInFlight = true

    if quickWhere.processTimer then
        killTimer(quickWhere.processTimer)
        quickWhere.processTimer = nil
    end

    snd.triggers.enableQuickWhereTriggers()

    if quickWhere.disableTimer then
        killTimer(quickWhere.disableTimer)
        quickWhere.disableTimer = nil
    end

    quickWhere.disableTimer = tempTimer(5, function()
        if snd.nav and snd.nav.quickWhere then
            snd.nav.quickWhere.disableTimer = nil
            if snd.nav.quickWhere.processed == false then
                snd.triggers.disableQuickWhereTriggers()
            end
        end
    end)
end

function snd.triggers.registerQuickWhereCommandTrigger()
    snd.nav = snd.nav or {}
    snd.nav.quickWhere = snd.nav.quickWhere or {}
    if snd.nav.quickWhere.commandTriggerId then
        return
    end

    snd.nav.quickWhere.commandTriggerId = tempRegexTrigger(
        "^You entered: where(?:\\s+.+)?$",
        snd.triggers.onWhereCommandIssued
    )
end


function snd.triggers.unregisterQuickWhereTempTriggers()
    if not snd.nav or not snd.nav.quickWhere or not snd.nav.quickWhere.tempTriggerIds then
        return
    end

    for _, id in ipairs(snd.nav.quickWhere.tempTriggerIds) do
        pcall(function() killTrigger(id) end)
    end
    snd.nav.quickWhere.tempTriggerIds = nil
end

function snd.triggers.registerQuickWhereTempTriggers()
    snd.nav = snd.nav or {}
    snd.nav.quickWhere = snd.nav.quickWhere or {}

    snd.triggers.unregisterQuickWhereTempTriggers()

    local ids = {}

    table.insert(ids, tempRegexTrigger('^.{30}.+$', function(...)
        local rawLine = getCurrentLine() or ""
        if rawLine == "" then
            return
        end
        if rawLine:match('^%[S&D') or rawLine:match('^%[') then
            return
        end

        local mobPart, roomPart
        if #rawLine >= 30 then
            mobPart = rawLine:sub(1, 30)
            roomPart = snd.utils.trim(rawLine:sub(31))
        end

        if not mobPart or not roomPart or roomPart == "" then
            mobPart, roomPart = rawLine:match('^(.-)%s%s+(.*)$')
        end

        if not mobPart or not roomPart or snd.utils.trim(roomPart) == "" then
            return
        end

        snd.utils.qwDebugNote("QW DEBUG: temp trigger captured where row")
        snd.triggers.qwMatch({rawLine, mobPart, roomPart})
    end))

    table.insert(ids, tempRegexTrigger('^There is no .+ around here\\.$', function(...)
        snd.utils.qwDebugNote("QW DEBUG: temp trigger captured no-match row")
        snd.triggers.qwNoMatch()
    end))

    snd.nav.quickWhere.tempTriggerIds = ids
    snd.utils.qwDebugNote('QW DEBUG: registered temp quick-where triggers (' .. tostring(#ids) .. ')')
end

function snd.triggers.unregisterTargetLineTriggers()
    if snd.targets and snd.targets.lineTriggerIds then
        for _, triggerId in ipairs(snd.targets.lineTriggerIds) do
            killTrigger(triggerId)
        end
        snd.targets.lineTriggerIds = nil
    end
    snd.roomChars = snd.roomChars or {}
    snd.roomChars.targetMatchers = {}
    snd.roomChars.targetMatcherArea = nil
end

-------------------------------------------------------------------------------
-- Quick Where Triggers
-------------------------------------------------------------------------------

--- Quick where match trigger
-- Matches formatted mob name and room
function snd.triggers.qwMatch(matches)
    if not matches then return end
    if not snd.nav.quickWhere or snd.nav.quickWhere.processed ~= false then
        return
    end

    local rawLine = matches[1] or ""
    if rawLine:match('^%[S&D') or rawLine:match('^%[') then
        return
    end

    local mobPart = matches[2]
    local roomPart = matches[3]

    if (not mobPart or not roomPart or snd.utils.trim(roomPart) == "") and rawLine ~= "" then
        if #rawLine >= 30 then
            mobPart = rawLine:sub(1, 30)
            roomPart = snd.utils.trim(rawLine:sub(31))
        end
    end

    if not mobPart or not roomPart or snd.utils.trim(roomPart) == "" then
        if rawLine == "" then return end
        mobPart, roomPart = rawLine:match("^(.-)%s%s+(.*)$")
        if not mobPart or not roomPart or snd.utils.trim(roomPart) == "" then
            snd.utils.qwDebugNote("QW DEBUG: unable to split where row: '" .. rawLine .. "'")
            return
        end
    end

    local mobName = snd.utils.trim(mobPart)
    local roomName = snd.utils.trim(roomPart)
    local quickWhere = snd.nav.quickWhere
    quickWhere.commandInFlight = false

    local function quickWhereBlockedReason()
        local state = nil
        if gmcp and gmcp.char and gmcp.char.status then
            state = gmcp.char.status.state
        end
        if state == nil or tostring(state) == "" then
            state = snd.char and snd.char.state
        end
        state = tostring(state or "0")
        if state == "8" then
            return "combat", state
        elseif state == "9" then
            return "sleeping", state
        end
        return nil, state
    end

    snd.utils.debugNote("QW match: " .. mobName .. " in " .. roomName)
    snd.utils.qwDebugNote("QW DEBUG: trigger matched line mob='" .. mobName .. "' room='" .. roomName .. "'")

    local function lineMatchesTarget()
        if quickWhere.exact then
            local exactSource = snd.utils.trim(quickWhere.exactMatchText or "")
            if exactSource == "" and snd.targets.current and snd.targets.current.name then
                exactSource = snd.utils.trim(snd.targets.current.name or "")
            end
            if snd.utils.mobIdentityMatches(mobName, exactSource, 30) then
                return true
            end
            snd.utils.qwDebugNote(string.format(
                "QW DEBUG: rejected live row mob='%s'; expected='%s'",
                tostring(mobName),
                tostring(exactSource)
            ))
            return false
        end

        -- Non-exact quick-where follows original addon flow: accept the first
        -- valid where row and process it immediately.
        return true
    end

    if not lineMatchesTarget() then
        if quickWhere.probePending == true then
            snd.utils.qwDebugNote("QW DEBUG: numbered where probe already pending; ignoring duplicate rejected row")
            return
        end
        local blockReason, blockState = quickWhereBlockedReason()
        if blockReason then
            snd.utils.infoNote("Quick where stopped while " .. blockReason .. ".")
            snd.utils.qwDebugNote("QW DEBUG: numbered probe blocked by char.status.state=" .. tostring(blockState))
            quickWhere.processed = true
            quickWhere.completed = true
            quickWhere.awaitingCommandEcho = false
            quickWhere.probePending = false
            snd.triggers.disableQuickWhereTriggers()
            return
        end
        quickWhere.index = (tonumber(quickWhere.index) or 1) + 1
        if quickWhere.index < 101 then
            local lookupKeyword = snd.utils.trim(quickWhere.lookupKeyword or quickWhere.requestedKeyword or "")
            if lookupKeyword ~= "" then
                local cmd = string.format("where %d.%s", quickWhere.index, lookupKeyword)
                snd.utils.qwDebugNote("QW DEBUG: line not accepted, probing next index with '" .. cmd .. "'")
                quickWhere.probePending = true
                if type(tempTimer) == "function" then
                    local activeQuickWhere = quickWhere
                    activeQuickWhere.probeTimer = tempTimer(0.05, function()
                        activeQuickWhere.probeTimer = nil
                        if snd.nav and snd.nav.quickWhere == activeQuickWhere
                            and activeQuickWhere.processed == false
                            and activeQuickWhere.probePending == true
                        then
                            activeQuickWhere.probePending = false
                            local currentBlockReason = quickWhereBlockedReason()
                            if currentBlockReason then
                                if currentBlockReason == "combat"
                                    and snd.commands and snd.commands.abortQuickWhereForCombat
                                then
                                    snd.commands.abortQuickWhereForCombat()
                                else
                                    activeQuickWhere.processed = true
                                    activeQuickWhere.completed = true
                                    activeQuickWhere.awaitingCommandEcho = false
                                    activeQuickWhere.commandInFlight = false
                                    snd.triggers.disableQuickWhereTriggers()
                                end
                                return
                            end

                            activeQuickWhere.awaitingCommandEcho = true
                            activeQuickWhere.commandInFlight = true
                            local sent = false
                            if snd.commands and snd.commands.sendGameCommand then
                                sent = snd.commands.sendGameCommand(cmd, false) == true
                            elseif type(send) == "function" then
                                send(cmd, false)
                                sent = true
                            end
                            if not sent then
                                activeQuickWhere.commandInFlight = false
                            end
                        end
                    end)
                else
                    quickWhere.probePending = false
                    quickWhere.awaitingCommandEcho = true
                    quickWhere.commandInFlight = true
                    if snd.commands and snd.commands.sendGameCommand then
                        if snd.commands.sendGameCommand(cmd, false) ~= true then
                            quickWhere.commandInFlight = false
                        end
                    else
                        send(cmd, false)
                    end
                end
            else
                quickWhere.processed = true
                quickWhere.completed = true
                quickWhere.awaitingCommandEcho = false
                quickWhere.probePending = false
                snd.triggers.disableQuickWhereTriggers()
            end
        else
            snd.utils.infoNote("qw: too many fails")
            quickWhere.processed = true
            quickWhere.completed = true
            quickWhere.awaitingCommandEcho = false
            quickWhere.probePending = false
            snd.triggers.disableQuickWhereTriggers()
        end
        return
    end

    snd.utils.qwDebugNote("QW DEBUG: accepted where row at index=" .. tostring(quickWhere.index or 1))

    selectCurrentLine()
    deleteLine()

    quickWhere.lastMatch = {
        mob = mobName,
        room = roomName,
        rawLine = rawLine,
        matchesCurrentTarget = true,
    }
    quickWhere.pendingMatches = {quickWhere.lastMatch}
    quickWhere.processed = true
    quickWhere.completed = true
    quickWhere.accepted = true
    quickWhere.awaitingCommandEcho = false
    quickWhere.probePending = false
    quickWhere.commandInFlight = false
    if quickWhere.probeTimer then
        pcall(function() killTimer(quickWhere.probeTimer) end)
        quickWhere.probeTimer = nil
    end

    local ok, err = pcall(snd.commands.processQuickWhereResult)
    if not ok then
        snd.utils.errorNote("QW DEBUG: processing where result failed: " .. tostring(err))
        quickWhere.processed = true
        quickWhere.completed = true
        quickWhere.awaitingCommandEcho = false
        quickWhere.probePending = false
        quickWhere.commandInFlight = false
        snd.triggers.disableQuickWhereTriggers()
    end
end

--- Quick where no match trigger
function snd.triggers.qwNoMatch()
    snd.utils.debugNote("QW: No match found")
    snd.utils.qwDebugNote("QW DEBUG: server returned 'There is no ... around here.'")
    
    if snd.nav.quickWhere and snd.nav.quickWhere.processed == false then
        snd.nav.quickWhere.commandInFlight = false
        if snd.nav.quickWhere.probeTimer then
            pcall(function() killTimer(snd.nav.quickWhere.probeTimer) end)
            snd.nav.quickWhere.probeTimer = nil
        end
        if snd.utils.trim(snd.nav.quickWhere.exactTargetName or "") ~= "" then
            snd.utils.qwDebugNote("QW DEBUG: exact selected-target lookup stopped without broad fallback")
        end
        if snd.nav.quickWhere.processTimer then
            killTimer(snd.nav.quickWhere.processTimer)
            snd.nav.quickWhere.processTimer = nil
        end
        local handledByDb = false
        if snd.commands and snd.commands.processQuickWhereNoMatch then
            local ok, result = pcall(snd.commands.processQuickWhereNoMatch)
            handledByDb = ok and result == true
            if not ok then
                snd.utils.errorNote("QW DEBUG: processing no-match fallback failed: " .. tostring(result))
            end
        end
        snd.nav.quickWhere.lastMatch = nil
        if not handledByDb then
            snd.nav.quickWhere.processed = true
            snd.nav.quickWhere.completed = true
            snd.nav.quickWhere.awaitingCommandEcho = false
            snd.nav.quickWhere.probePending = false
        end
        snd.triggers.disableQuickWhereTriggers()
    end
end

-------------------------------------------------------------------------------
-- Output Gags
-------------------------------------------------------------------------------

function snd.triggers.gagCurrentLine()
    selectCurrentLine()
    deleteLine()
end

-------------------------------------------------------------------------------
-- Hunt Triggers
-------------------------------------------------------------------------------

--- Hunt direction trigger
-- Matches: "You are certain that mob is north from here."
function snd.triggers.huntDirection(matches)
    if not matches or not matches[2] then return end
    
    local direction = matches[2]
    snd.utils.debugNote("Hunt direction: " .. direction)
    
    -- Store for hunt trick / auto hunt
    if snd.nav.autoHunt then
        snd.nav.autoHunt.direction = direction
    end

    if snd.nav and snd.nav.autoHunt and snd.nav.autoHunt.active and snd.commands and snd.commands.autoHuntNext then
        snd.commands.autoHuntNext(direction)
        return
    end

    if snd.nav and snd.nav.huntTrick and snd.nav.huntTrick.active and snd.commands and snd.commands.huntTrickContinue then
        snd.commands.huntTrickContinue()
    end
end

--- Hunt here trigger
-- Matches: "Mob is here!"
function snd.triggers.huntHere()
    snd.utils.debugNote("Hunt: Target is here!")
    
    if snd.nav.autoHunt then
        snd.nav.autoHunt.direction = "here"
    end

    if snd.nav and snd.nav.autoHunt and snd.nav.autoHunt.active and snd.commands and snd.commands.autoHuntComplete then
        snd.commands.autoHuntComplete()
        return
    end

    if snd.nav and snd.nav.huntTrick and snd.nav.huntTrick.active and snd.commands and snd.commands.huntTrickContinue then
        snd.commands.huntTrickContinue()
    end
end

--- Hunt trick complete trigger
function snd.triggers.huntComplete()
    if snd.nav and snd.nav.autoHunt and snd.nav.autoHunt.active and snd.commands and snd.commands.autoHuntComplete then
        snd.commands.autoHuntComplete()
        return
    end
    if snd.commands and snd.commands.huntTrickComplete then
        snd.commands.huntTrickComplete()
    end
end

--- Hunt trick fail trigger
function snd.triggers.huntFail()
    if snd.nav and snd.nav.autoHunt and snd.nav.autoHunt.active and snd.commands and snd.commands.stopAutoHunt then
        snd.commands.stopAutoHunt(true)
        return
    end
    if snd.commands and snd.commands.huntTrickFail then
        snd.commands.huntTrickFail()
    end
end

--- Hunt trick abort trigger
function snd.triggers.huntAbort()
    if snd.nav and snd.nav.autoHunt and snd.nav.autoHunt.active and snd.commands and snd.commands.stopAutoHunt then
        snd.commands.stopAutoHunt(true)
        return
    end
    if snd.commands and snd.commands.stopHunt then
        snd.commands.stopHunt()
    end
end

-------------------------------------------------------------------------------
-- Reward Tracking Triggers
-------------------------------------------------------------------------------

--- Campaign info QP reward trigger
function snd.triggers.cpInfoRewardQP(matches)
    if not matches or not matches[2] then return end
    if snd.cp and snd.cp.parsing and not snd.cp.parsing.infoActive and snd.cp.startCpInfo then
        snd.cp.startCpInfo()
    end
    snd.campaign.qpReward = tonumber(matches[2]) or 0
    snd.cp.syncHistoryRewards()
    scheduleCpInfoEnd()
end

--- Campaign info complete-by trigger
function snd.triggers.cpInfoCompleteBy(matches)
    if not matches or not matches[2] then return end
    if snd.cp and snd.cp.parsing and not snd.cp.parsing.infoActive and snd.cp.startCpInfo then
        snd.cp.startCpInfo()
    end
    if snd.cp and snd.cp.captureCompleteBy then
        snd.cp.captureCompleteBy(matches[2])
    end
    scheduleCpInfoEnd()
end

--- Campaign info time-left trigger
function snd.triggers.cpInfoTimeLeft(matches)
    if not matches or not matches[2] then return end
    if snd.cp and snd.cp.parsing and not snd.cp.parsing.infoActive and snd.cp.startCpInfo then
        snd.cp.startCpInfo()
    end
    if snd.cp and snd.cp.captureTimeLeft then
        snd.cp.captureTimeLeft(matches[2])
    end
    scheduleCpInfoEnd()
end

--- Campaign info gold reward trigger
function snd.triggers.cpInfoRewardGold(matches)
    if not matches or not matches[2] then return end
    if snd.gq and snd.gq.parsing and snd.gq.parsing.infoActive then return end
    if snd.cp and snd.cp.parsing and not snd.cp.parsing.infoActive and snd.cp.startCpInfo then
        snd.cp.startCpInfo()
    end
    local gold = tostring(matches[2]):gsub(",", "")
    snd.campaign.goldReward = tonumber(gold) or 0
    snd.cp.syncHistoryRewards()
    scheduleCpInfoEnd()
end

--- Campaign info TP reward trigger
function snd.triggers.cpInfoRewardTP(matches)
    if not matches or not matches[2] then return end
    if snd.cp and snd.cp.parsing and not snd.cp.parsing.infoActive and snd.cp.startCpInfo then
        snd.cp.startCpInfo()
    end
    snd.campaign.tpReward = tonumber(matches[2]) or 0
    snd.cp.syncHistoryRewards()
    scheduleCpInfoEnd()
end

--- Campaign info training reward trigger
function snd.triggers.cpInfoRewardTrain(matches)
    if not matches or not matches[2] then return end
    if snd.gq and snd.gq.parsing and snd.gq.parsing.infoActive then return end
    if snd.cp and snd.cp.parsing and not snd.cp.parsing.infoActive and snd.cp.startCpInfo then
        snd.cp.startCpInfo()
    end
    snd.campaign.trainReward = tonumber(matches[2]) or 0
    snd.cp.syncHistoryRewards()
    scheduleCpInfoEnd()
end

--- Campaign info practice reward trigger
function snd.triggers.cpInfoRewardPrac(matches)
    if not matches or not matches[2] then return end
    if snd.gq and snd.gq.parsing and snd.gq.parsing.infoActive then return end
    if snd.cp and snd.cp.parsing and not snd.cp.parsing.infoActive and snd.cp.startCpInfo then
        snd.cp.startCpInfo()
    end
    snd.campaign.pracReward = tonumber(matches[2]) or 0
    snd.cp.syncHistoryRewards()
    scheduleCpInfoEnd()
end

-------------------------------------------------------------------------------
-- Scan/Consider Triggers (Placeholder)
-------------------------------------------------------------------------------

--- Process scan output
function snd.triggers.scanLine(matches)
    -- Placeholder for scan processing
    -- Would parse scan output to find mobs
end

--- Process consider output
function snd.triggers.considerLine(matches)
    -- Placeholder for consider processing
end

-------------------------------------------------------------------------------
-- Level Up Trigger
-------------------------------------------------------------------------------

function snd.triggers.levelUp()
    snd.campaign.canGetNew = true
    
    if snd.gui and snd.gui.refresh then
        snd.gui.refresh()
    end
end

-------------------------------------------------------------------------------
-- Dynamic Trigger Management
-------------------------------------------------------------------------------


local function quickWhereTriggerRefs(name)
    local refs = {name}

    if type(getNamedTriggers) == "function" then
        local ok, ids = pcall(getNamedTriggers, name)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do
                local seen = false
                for _, existing in ipairs(refs) do
                    if existing == id then
                        seen = true
                        break
                    end
                end
                if not seen then
                    table.insert(refs, id)
                end
            end
        end
    end

    return refs
end

local function quickWhereTriggerState(name)
    for _, ref in ipairs(quickWhereTriggerRefs(name)) do
        if type(isActive) == "function" then
            local ok, active = pcall(isActive, ref, "trigger")
            if ok and type(active) == "number" then
                if active > 0 then
                    return "on"
                end
            end
        end

        if type(isTriggerActive) == "function" then
            local ok, active = pcall(isTriggerActive, ref)
            if ok and type(active) == "boolean" then
                if active then
                    return "on"
                end
            elseif ok and type(active) == "number" then
                if active > 0 then
                    return "on"
                end
            end
        end
    end

    return "off"
end

local function quickWhereTriggerCount(name)
    if type(exists) == "function" then
        local ok, count = pcall(exists, name, "trigger")
        if ok and type(count) == "number" then
            return count
        end
    end

    return 0
end

function snd.triggers.enableQuickWhereTriggers()
    local matchName = "qw_match"
    local noMatchName = "qw_no_match"

    snd.utils.qwDebugNote("QW DEBUG: enabling quick-where triggers")
    for _, ref in ipairs(quickWhereTriggerRefs(matchName)) do
        enableTrigger(ref)
    end
    for _, ref in ipairs(quickWhereTriggerRefs(noMatchName)) do
        enableTrigger(ref)
    end

    local matchState = quickWhereTriggerState(matchName)
    local noMatchState = quickWhereTriggerState(noMatchName)

    snd.utils.qwDebugNote(string.format(
        "QW DEBUG: trigger states match=%s, no_match=%s (counts: %d/%d)",
        matchState, noMatchState,
        quickWhereTriggerCount(matchName), quickWhereTriggerCount(noMatchName)
    ))

end

function snd.triggers.disableQuickWhereTriggers()
    local matchName = "qw_match"
    local noMatchName = "qw_no_match"

    for _, ref in ipairs(quickWhereTriggerRefs(noMatchName)) do
        disableTrigger(ref)
    end
    for _, ref in ipairs(quickWhereTriggerRefs(matchName)) do
        disableTrigger(ref)
    end

    snd.utils.qwDebugNote(string.format(
        "QW DEBUG: trigger states match=%s, no_match=%s (counts: %d/%d)",
        quickWhereTriggerState(matchName), quickWhereTriggerState(noMatchName),
        quickWhereTriggerCount(matchName), quickWhereTriggerCount(noMatchName)
    ))
end

--- Enable a trigger group
function snd.triggers.enableGroup(groupName)
    if groupName == "QuickWhere" then
        snd.triggers.enableQuickWhereTriggers()
    else
        enableTrigger("SND_" .. groupName)
    end
    snd.utils.debugNote("Enabled trigger group: " .. groupName)
end

--- Disable a trigger group
function snd.triggers.disableGroup(groupName)
    if groupName == "QuickWhere" then
        snd.triggers.disableQuickWhereTriggers()
    else
        disableTrigger("SND_" .. groupName)
    end
    snd.utils.debugNote("Disabled trigger group: " .. groupName)
end

--- Create a temporary trigger for cp info end
function snd.triggers.createCpInfoEndTrigger()
    if snd.cp.parsing.infoEndTimer then
        pcall(function() killTimer(snd.cp.parsing.infoEndTimer) end)
    end
    snd.cp.parsing.infoEndTimer = tempTimer(0.6, function()
        if snd.cp.parsing.infoActive then
            snd.cp.endCpInfo()
        end
        snd.cp.parsing.infoEndTimer = nil
    end)
end

--- Create a temporary trigger for gq info end
function snd.triggers.createGqInfoEndTrigger()
    if snd.gq.parsing.infoEndTimer then
        pcall(function() killTimer(snd.gq.parsing.infoEndTimer) end)
    end
    snd.gq.parsing.infoEndTimer = tempTimer(0.6, function()
        if snd.gq.parsing.infoActive then
            snd.gq.endGqInfo()
        end
        snd.gq.parsing.infoEndTimer = nil
    end)
end

-- Module loaded silently
