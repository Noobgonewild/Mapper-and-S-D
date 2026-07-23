--[[
    Search and Destroy - Consider Window Module
    Mudlet Port

    Tracks consider output in a dedicated window and supports click-to-kill.
]]

snd = snd or {}
snd.conwin = snd.conwin or {}

local CW = snd.conwin

CW.MARKER = "__SND_CONWIN_DONE__"
CW.ids = CW.ids or {triggers = {}, events = {}}
CW.ids.keys = CW.ids.keys or {}
CW.ids.aliases = CW.ids.aliases or {}
CW.mobs = CW.mobs or {}
CW.awaiting = CW.awaiting or false
CW.doneTimer = CW.doneTimer or nil
CW.lastRoomId = CW.lastRoomId or nil
CW.lastAutoRoomId = CW.lastAutoRoomId or nil
CW.lastAutoConsiderAt = CW.lastAutoConsiderAt or 0
CW.lastEnemy = CW.lastEnemy or ""
CW.nextMobId = CW.nextMobId or 0
CW.killsSinceRefresh = CW.killsSinceRefresh or 0
CW.currentEnemyMobId = CW.currentEnemyMobId or nil
CW.lastKnownEnemyPct = CW.lastKnownEnemyPct or nil
CW.lastTrackedMobId = CW.lastTrackedMobId or nil
CW.lastKilledMobName = CW.lastKilledMobName or ""
CW.lastKilledAt = CW.lastKilledAt or 0
CW.lastRawEnemy = CW.lastRawEnemy or ""
CW.travelGeneration = tonumber(CW.travelGeneration) or 0
CW.travelActive = CW.travelActive == true
CW.travelClearedGeneration = tonumber(CW.travelClearedGeneration) or -1
CW.lastAutomaticRefreshKey = CW.lastAutomaticRefreshKey or nil
CW.latestRoomId = CW.latestRoomId or CW.lastRoomId
CW.lastPlayerState = CW.lastPlayerState or nil
CW.ROOM_REFRESH_DELAY = 0.20
CW.roomRefreshSerial = tonumber(CW.roomRefreshSerial) or 0
CW.captureSerial = tonumber(CW.captureSerial) or 0
CW.captureInFlight = nil -- A reload invalidates any marker from the old code.
CW.suppressConsiderLines = false
CW.refreshDirty = CW.refreshDirty == true
CW.pendingRefreshReason = CW.pendingRefreshReason or nil
CW.forceRefreshRevision = tonumber(CW.forceRefreshRevision) or 0
CW.forceRefreshPending = CW.forceRefreshPending == true
CW.lastServedForceRevision = tonumber(CW.lastServedForceRevision) or 0
CW.lastSuccessfulAutomaticKey = CW.lastSuccessfulAutomaticKey or nil
CW.combatSessionActive = CW.combatSessionActive == true
CW.combatRefreshQueued = CW.combatRefreshQueued == true
CW.COMBAT_END_DELAY = 0.20
CW.ATTACK_INTENT_TTL = 2.0
CW.ESCAPE_INTENT_TTL = 2.0
CW.SAME_NAME_RESET_MIN_JUMP = 20
CW.SAME_NAME_RESET_MAX_LOW = 50
-- Combat observations are session-local; a script reload invalidates their
-- ordering relative to future CP/GQ kill messages.
CW.deathEvents = {}
CW.deathEventSerial = tonumber(CW.deathEventSerial) or 0
CW.lastReturnedDeathSerial = nil
CW.lastKilledMobName = ""
CW.lastKilledAt = 0
CW.pendingAttackIntent = nil
CW.pendingEscapeIntent = nil
CW.combat = CW.combat or {}
if CW.combat.pendingEndTimer and type(killTimer) == "function" then
    pcall(killTimer, CW.combat.pendingEndTimer)
end
CW.combat = {
    activeRowId = nil,
    activeName = "",
    lastHp = nil,
    minimumHp = nil,
    roomId = "",
    generation = tonumber(CW.combat.generation) or 0,
    pendingEndTimer = nil,
    pendingEndSerial = tonumber(CW.combat.pendingEndSerial) or 0,
}
-- RoomChars includes players and every visible inhabitant. Retire the old
-- provisional integration so only parsed consider output can populate ConWin.
CW.provisionalLines = nil
CW.provisionalRoomId = nil
CW.onRoomcharsStart = nil
CW.onRoomcharsLine = nil

-- Retire any callback created by an older copy of this file. The new timer is
-- only a quiet-room debounce; GMCP state and the single-flight marker remain
-- the source of truth.
if CW.roomRefreshTimer and type(killTimer) == "function" then
    pcall(killTimer, CW.roomRefreshTimer)
end
CW.roomRefreshTimer = nil
CW.roomRefreshSerial = CW.roomRefreshSerial + 1

local consider_map = {
    {[[^(\(.+\) ?)?(.+) looks a little worried about the idea\.$]], "chartreuse", "-2 to -4"},
    {[[^(\(.+\) ?)?(.+) says 'BEGONE FROM MY SIGHT unworthy!'$]], "dark_violet", "+41 to +50"},
    {[[^(\(.+\) ?)?(.+) should be a fair fight!$]], "spring_green", "-1 to +1"},
    {[[^(\(.+\) ?)?(.+) snickers nervously\.$]], "dark_goldenrod", "+2 to +4"},
    {[[^(\(.+\) ?)?(.+) would be easy, but is it even worth the work out\?$]], "dark_green", "-10 to -19"},
    {[[^(\(.+\) ?)?(.+) would crush you like a bug!$]], "light_pink", "+21 to +30"},
    {[[^(\(.+\) ?)?(.+) would dance on your grave!$]], "dark_orchid", "+31 to +41"},
    {[[^(\(.+\) ?)?Best run away from (.+) while you can!$]], "tomato", "+10 to +15"},
    {[[^(\(.+\) ?)?Challenging (.+) would be either very brave or very stupid\.$]], "indian_red", "+16 to +20"},
    {[[^(\(.+\) ?)?No Problem! (.+) is weak compared to you\.$]], "forest_green", "-5 to -9"},
    {[[^(\(.+\) ?)?You would be completely annihilated by (.+)!$]], "magenta", "+51 and above"},
    {[[^(\(.+\) )?You would stomp (.+) into the ground\.$]], "gray", "-20 and below"},
    {[[^(\(.+\) ?)?(.+) chuckles at the thought of you fighting]], "gold", "+5 to +9"},
}

local function cfg()
    snd.config.conwin = snd.config.conwin or {
        enabled = true,
        fontSize = 9,
        x = "70%", y = "52%", width = "28%", height = "43%",
        mode = "consider", -- consider | off
        strictFocusIdOnly = false, -- When true, ambiguous duplicate targets require currentEnemyMobId for HP overlay/death mark.
        killCommand = "kill",
        repopulate = 3, -- Refresh window after N confirmed kills (0 = disabled)
        clearOnSafe = true,
        clearOnEmptyRoomchars = true,
        alignTags = true,
    }
    local mode = tostring(snd.config.conwin.mode or "consider"):lower()
    if mode == "scan" then
        mode = "off"
    elseif mode ~= "consider" and mode ~= "off" then
        mode = "consider"
    end
    snd.config.conwin.mode = mode
    return snd.config.conwin
end

local function gmcp_get(path)
    local node = gmcp
    for key in tostring(path):gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return node
end

local function currentRoomId()
    -- Read the live GMCP packet first. Anonymous handlers for the same event do
    -- not have a guaranteed execution order, so snd.room.current may still be
    -- the room we just left when ConWin's room.info handler runs.
    local roomInfo = gmcp_get("room.info")
    if type(roomInfo) == "table" and type(mm) == "table" and type(mm.canonical_room_uid) == "function" then
        local ok, roomId = pcall(mm.canonical_room_uid, roomInfo)
        if ok and roomId ~= nil and tostring(roomId) ~= "" then
            return tostring(roomId)
        end
    end
    local roomId = snd and snd.room and snd.room.current and snd.room.current.rmid or nil
    if roomId ~= nil and tostring(roomId) ~= "" then
        return tostring(roomId)
    end
    return tostring(gmcp_get("room.info.num") or "")
end

local function currentPlayerState()
    local state = gmcp_get("char.status.state")
    if state == nil and snd and snd.char then
        state = snd.char.state
    end
    return state ~= nil and tostring(state) or ""
end

local function mapperHasPendingTravel(roomId)
    if snd and snd.mapper and snd.mapper.pathExecutionHasPendingGroups == true then
        return true
    end

    local destination = snd and (
        (snd.nav and snd.nav.goingToRoom) or
        (snd.mapper and snd.mapper.goingToRoom)
    ) or nil
    if destination ~= nil and tostring(destination) ~= "" then
        return tostring(destination) ~= tostring(roomId or "")
    end
    return false
end

local function trim(s) return (tostring(s or ""):gsub("^%s+",""):gsub("%s+$","")) end

local function normalizeMobName(s)
    local n = trim(s)
    n = n:gsub("^%b()%s*", "")
    n = n:lower()
    n = n:gsub("%s+", " ")
    return trim(n)
end

local function startsWithIgnoreCase(text, prefix)
    local a = tostring(text or "")
    local b = tostring(prefix or "")
    if b == "" then return false end
    return a:sub(1, #b):lower() == b:lower()
end

local function clamp(n, lo, hi)
    n = tonumber(n) or 0
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function hpTintedName(name, fgColor, bgColor, pct, enabled)
    local mobName = tostring(name or "")
    if not enabled then
        return string.format("<%s>%s<reset>", fgColor, mobName)
    end

    local hpPct = clamp(pct, 0, 100)
    local total = #mobName
    if total == 0 then
        return string.format("<%s>%s<reset>", fgColor, mobName)
    end

    -- The highlighted section shrinks from right-to-left as HP goes down.
    local aliveChars = math.floor((hpPct / 100) * total + 0.5)
    aliveChars = clamp(aliveChars, 0, total)

    local hpPart = mobName:sub(1, aliveChars)
    local emptyPart = mobName:sub(aliveChars + 1)

    return string.format("<black:%s>%s<reset><%s>%s<reset>", bgColor, hpPart, fgColor, emptyPart)
end

local function tokenizedContainsSafe(info)
    local v = tostring(info or ""):lower()
    if v == "" then return false end
    for token in v:gmatch("[^,%s]+") do
        if token == "safe" then return true end
    end
    return false
end


local function activeActivityLabel(target)
    local activity = tostring(target and target.activity or ""):lower()
    if activity == "cp" and snd and snd.campaign and snd.campaign.active then
        return "CP"
    elseif activity == "gq" and snd and snd.gquest and snd.gquest.active then
        return "GQ"
    elseif activity == "quest" and snd and snd.quest and snd.quest.active then
        local questStatus = tostring(snd.quest.target and snd.quest.target.status or ""):lower()
        if questStatus == "dead" or questStatus == "killed" then return nil end
        return "quest"
    end
    return nil
end

function CW.detectActiveTargetInRoom()
    local roomId = currentRoomId()
    if roomId == "" or roomId ~= tostring(CW.lastRoomId or "") then return false end

    local current = snd and snd.targets and snd.targets.current or nil
    local pendingAction = snd and snd.scan and snd.scan.pendingNxAction and snd.scan.pendingNxAction.action or nil
    if pendingAction == "smartscan" and snd.scan and snd.scan.resolveSmartScanTarget then
        current = snd.scan.resolveSmartScanTarget({select = true})
    end
    if not current then return false end
    if snd and snd.scan and snd.scan.targetIsAlive then
        if not snd.scan.targetIsAlive(current) then return false end
    elseif current.dead or tostring(current.status or ""):lower() == "dead" then
        return false
    end
    local activityLabel = activeActivityLabel(current)
    if not activityLabel then return false end

    local targetName = normalizeMobName(current.name or current.mob or current.matchedMobName or "")
    if targetName == "" then return false end
    local present = false
    for _, m in ipairs(CW.mobs or {}) do
        if not m.dead and normalizeMobName(m.name) == targetName then
            present = true
            break
        end
    end
    if not present then return false end

    return {
        roomId = roomId,
        activityLabel = activityLabel,
        target = current,
    }
end

function CW.resolveCurrentRoomTargetForNxAction()
    local targetHere = CW.detectActiveTargetInRoom()

    if not targetHere then
        if snd and snd.scan and snd.scan.runPendingNxAction then
            snd.scan.runPendingNxAction(CW.lastRoomId, "target-not-found")
        end
        return false
    else
        if snd and snd.scan and snd.scan.cancelPendingNxAction then
            snd.scan.cancelPendingNxAction(targetHere.roomId, "target-found")
        end

        return true
    end
end

local function automaticRefreshKey(roomId)
    return tostring(CW.travelGeneration or 0) .. ":" .. tostring(roomId or "")
end

function CW.cancelPendingCombatEnd()
    local combat = CW.combat or {}
    combat.pendingEndSerial = (tonumber(combat.pendingEndSerial) or 0) + 1
    if combat.pendingEndTimer and type(killTimer) == "function" then
        pcall(killTimer, combat.pendingEndTimer)
    end
    combat.pendingEndTimer = nil
    CW.combat = combat
end

function CW.releaseCombatBinding()
    CW.cancelPendingCombatEnd()
    local combat = CW.combat
    combat.activeRowId = nil
    combat.activeName = ""
    combat.lastHp = nil
    combat.minimumHp = nil
    combat.roomId = ""
    CW.currentEnemyMobId = nil
    CW.lastKnownEnemyPct = nil
    CW.lastTrackedMobId = nil
end

function CW.resetCombatTracking()
    CW.releaseCombatBinding()
    CW.pendingAttackIntent = nil
    CW.pendingEscapeIntent = nil
    CW.lastEnemy = ""
    CW.lastRawEnemy = ""
end

function CW.resetConsideredMobs(resetKills)
    CW.mobs = {}
    if resetKills then
        CW.killsSinceRefresh = 0
    end
    CW.resetCombatTracking()
end

function CW.clear(_reason)
    CW.resetConsideredMobs(true)
    CW.render()
end

function CW.abortCapture()
    if CW.doneTimer then
        if type(killTimer) == "function" then
            pcall(killTimer, CW.doneTimer)
        end
        CW.doneTimer = nil
    end
    CW.awaiting = false
end

function CW.cancelRoomRefreshTimer()
    CW.roomRefreshSerial = (tonumber(CW.roomRefreshSerial) or 0) + 1
    if CW.roomRefreshTimer and type(killTimer) == "function" then
        pcall(killTimer, CW.roomRefreshTimer)
    end
    CW.roomRefreshTimer = nil
end

function CW.hasPendingRefresh()
    local roomId = tostring(CW.latestRoomId or currentRoomId() or "")
    local automaticPending = CW.travelActive
        and roomId ~= ""
        and CW.lastSuccessfulAutomaticKey ~= automaticRefreshKey(roomId)
    return CW.refreshDirty == true or automaticPending or CW.forceRefreshPending == true
end

function CW.isRefreshEligible(roomId)
    if currentPlayerState() ~= "3" then return false end
    if trim(gmcp_get("char.status.enemy") or "") ~= "" then return false end
    if snd and snd.mapper and snd.mapper.pathExecutionHasPendingGroups == true then
        return false
    end

    -- A combat-issued MUD stop can leave the old mapper destination in place
    -- even though no client-side groups remain. That is a genuine ConWin stop.
    if not CW.combatRefreshQueued and mapperHasPendingTravel(roomId) then
        return false
    end
    return true
end

function CW.armRoomRefresh(delay)
    if CW.captureInFlight then return false end
    CW.cancelRoomRefreshTimer()
    local serial = CW.roomRefreshSerial
    CW.roomRefreshTimer = tempTimer(tonumber(delay) or CW.ROOM_REFRESH_DELAY, function()
        if serial ~= CW.roomRefreshSerial then return end
        CW.roomRefreshTimer = nil
        CW.tryStartRefresh()
    end)
    return true
end

function CW.requestRefresh(reason, force, delay)
    local roomId = currentRoomId()
    if roomId == "" then return false end
    CW.latestRoomId = roomId
    CW.pendingRefreshReason = tostring(reason or "automatic")
    CW.refreshDirty = true
    if force and not CW.forceRefreshPending then
        CW.forceRefreshRevision = (tonumber(CW.forceRefreshRevision) or 0) + 1
        CW.forceRefreshPending = true
    end
    if not CW.captureInFlight then
        CW.armRoomRefresh(delay)
    end
    return true
end

function CW.startSerializedCapture(roomId)
    if CW.captureInFlight then return false end
    CW.suppressConsiderLines = false
    CW.captureSerial = (tonumber(CW.captureSerial) or 0) + 1
    local serial = CW.captureSerial
    CW.captureInFlight = {
        serial = serial,
        requestRoom = tostring(roomId or currentRoomId()),
        generation = tonumber(CW.travelGeneration) or 0,
        forceRevision = CW.forceRefreshPending and CW.forceRefreshRevision or CW.lastServedForceRevision,
        combatRefresh = CW.combatRefreshQueued == true,
        reason = CW.pendingRefreshReason or "automatic",
        failed = false,
        cancelled = false,
        observedRoom = nil,
        mobs = {},
    }
    CW.awaiting = true
    CW.mobDetectDispatched = false
    send("consider all", false)
    send("echo " .. CW.MARKER .. ":" .. tostring(serial), false)
    return true
end

function CW.tryStartRefresh()
    if CW.captureInFlight or not CW.hasPendingRefresh() then return false end

    local roomId = currentRoomId()
    if roomId == "" then return false end
    CW.latestRoomId = roomId

    if not cfg().enabled or tostring(cfg().mode or "consider"):lower() ~= "consider" then
        CW.refreshDirty = false
        CW.travelActive = false
        return false
    end
    if not CW.isRefreshEligible(roomId) then return false end

    if CW.isCurrentRoomSafe() then
        CW.clear("safe")
        CW.lastSuccessfulAutomaticKey = automaticRefreshKey(roomId)
        CW.lastServedForceRevision = CW.forceRefreshRevision
        CW.forceRefreshPending = false
        CW.refreshDirty = false
        CW.travelActive = false
        CW.combatSessionActive = false
        CW.combatRefreshQueued = false
        return true
    end

    return CW.startSerializedCapture(roomId)
end

function CW.noteCaptureRoom()
    local flight = CW.captureInFlight
    if not flight or flight.failed or flight.cancelled then return end
    local roomId = currentRoomId()
    if roomId == "" then return end
    if flight.observedRoom and flight.observedRoom ~= roomId then
        flight.failed = true
        return
    end
    flight.observedRoom = roomId
end

function CW.onConsiderRejected()
    local flight = CW.captureInFlight
    if not flight then return false end
    flight.failed = true
    CW.awaiting = false
    CW.refreshDirty = true
    CW.combatSessionActive = true
    return true
end

function CW.onCaptureMarker(serial)
    serial = tonumber(serial)
    local flight = CW.captureInFlight
    if not flight or serial ~= tonumber(flight.serial) then return false end

    if CW.doneTimer then
        if type(killTimer) == "function" then pcall(killTimer, CW.doneTimer) end
        CW.doneTimer = nil
    end
    CW.awaiting = false
    CW.captureInFlight = nil

    if currentPlayerState() == "8" or trim(gmcp_get("char.status.enemy") or "") ~= "" then
        flight.failed = true
    end
    local completedRoom = currentRoomId()
    if flight.observedRoom and flight.observedRoom ~= completedRoom then
        flight.failed = true
    end

    if flight.cancelled then
        return false
    end

    if flight.failed then
        CW.refreshDirty = true
        if currentPlayerState() == "3" and trim(gmcp_get("char.status.enemy") or "") == "" then
            CW.armRoomRefresh()
        end
        return false
    end

    -- Keep the previous rows visible while the server produces consider output,
    -- then replace the list immediately before the completed result is rendered.
    CW.resetConsideredMobs(false)
    CW.mobs = flight.mobs or {}
    CW.killsSinceRefresh = 0
    CW.lastSuccessfulAutomaticKey = automaticRefreshKey(completedRoom)
    CW.lastAutoRoomId = completedRoom
    CW.lastAutoConsiderAt = os.time()
    CW.lastServedForceRevision = math.max(
        tonumber(CW.lastServedForceRevision) or 0,
        tonumber(flight.forceRevision) or 0
    )
    if CW.lastServedForceRevision >= (tonumber(CW.forceRefreshRevision) or 0) then
        CW.forceRefreshPending = false
    end

    -- The consider and marker are sent adjacently, so live GMCP at marker time
    -- identifies the room whose output we just captured. It supersedes the
    -- Room.Info packet that originally requested this flight.
    CW.latestRoomId = completedRoom
    CW.lastRoomId = completedRoom
    CW.refreshDirty = false
    CW.travelActive = false

    if flight.combatRefresh and not CW.forceRefreshPending then
        CW.combatSessionActive = false
        CW.combatRefreshQueued = false
    end

    CW.render()
    CW.resolveCurrentRoomTargetForNxAction()
    if CW.hasPendingRefresh() then
        CW.armRoomRefresh()
    end
    return true
end

function CW.onTravelStarted(reason)
    if CW.travelActive then return false end

    CW.travelGeneration = (tonumber(CW.travelGeneration) or 0) + 1
    CW.travelActive = true
    CW.latestRoomId = currentRoomId()
    CW.refreshDirty = true
    if CW.awaiting and not CW.captureInFlight then
        CW.abortCapture()
    end

    if CW.travelClearedGeneration ~= CW.travelGeneration then
        CW.travelClearedGeneration = CW.travelGeneration
        CW.clear(reason or "travel-started")
    end
    return true
end

function CW.maybeRefreshStoppedRoom(reason)
    if not CW.hasPendingRefresh() then return false end
    if currentPlayerState() ~= "3" then return false end

    local roomId = currentRoomId()
    if roomId == "" then
        return false
    end
    if not CW.combatRefreshQueued and mapperHasPendingTravel(roomId) then
        return false
    end

    CW.latestRoomId = roomId
    CW.lastRoomId = roomId
    return CW.requestRefresh(reason or "travel-stopped", false)
end

function CW.onNavigationStopped(reason)
    return CW.maybeRefreshStoppedRoom(reason or "navigation-stopped")
end

function CW.cancelTravel()
    CW.cancelRoomRefreshTimer()
    if CW.captureInFlight then
        CW.captureSerial = (tonumber(CW.captureSerial) or 0) + 1
        CW.captureInFlight = nil
        CW.suppressConsiderLines = true
    end
    CW.abortCapture()
    CW.travelActive = false
    CW.refreshDirty = false
    CW.forceRefreshPending = false
    CW.combatSessionActive = false
    CW.combatRefreshQueued = false
end

function CW.isCurrentRoomSafe()
    local details = gmcp_get("room.info.details")
    if details ~= nil and tokenizedContainsSafe(details) then return true end
    local roomId = currentRoomId()
    if roomId ~= "" and snd.mapper and type(snd.mapper.isSafeRoom) == "function" then
        if snd.mapper.isSafeRoom(roomId) then return true end
    end
    return false
end

function CW.shouldClearForSafeRoom()
    if not cfg().clearOnSafe then return false end
    return CW.isCurrentRoomSafe()
end

function CW.activityMarkersForMob(name)
    local markers = {}
    local needle = trim(name):lower()
    if needle == "" or not snd.targets or not snd.targets.list then return "" end
    local seen = {}
    for _, t in ipairs(snd.targets.list) do
        if trim(t.mob or ""):lower() == needle and t.activity and not seen[t.activity] then
            seen[t.activity] = true
            if t.activity == "quest" then markers[#markers+1] = "[Q]"
            elseif t.activity == "gq" then markers[#markers+1] = "[GQ]"
            elseif t.activity == "cp" then markers[#markers+1] = "[CP]" end
        end
    end
    return table.concat(markers, "")
end

function CW.visibleNameForActivityTarget(targetName, activity)
    local needle = trim(targetName)
    if needle == "" then return "" end

    local activityMarkers = {
        quest = "[Q]",
        cp = "[CP]",
        gq = "[GQ]",
    }
    local marker = activityMarkers[tostring(activity or ""):lower()]

    for _, m in ipairs(CW.mobs or {}) do
        local mobName = trim(m.name or "")
        if not m.dead and snd.utils.mobIdentityMatches(mobName, needle)
            and (not marker or CW.activityMarkersForMob(mobName):find(marker, 1, true))
        then
            return mobName
        end
    end

    if not marker then return "" end

    local matches = {}
    for _, m in ipairs(CW.mobs or {}) do
        local mobName = trim(m.name or "")
        if not m.dead and mobName ~= "" and CW.activityMarkersForMob(mobName):find(marker, 1, true) then
            local selectorMatches = snd.utils.mobSelectorMatchesName(needle, mobName)
            if not selectorMatches then
                local mobNorm = normalizeMobName(mobName)
                local needleNorm = normalizeMobName(needle)
                selectorMatches = needleNorm ~= ""
                    and (mobNorm:find(needleNorm, 1, true) or needleNorm:find(mobNorm, 1, true))
            end
            if selectorMatches then
                matches[#matches + 1] = mobName
            end
        end
    end

    if #matches == 1 then
        return matches[1]
    end

    for _, m in ipairs(CW.mobs or {}) do
        local mobName = trim(m.name or "")
        if not m.dead and snd.utils.mobIdentityMatches(mobName, needle) then
            return mobName
        end
    end
    return ""
end

local function markerToColorToken(marker)
    if marker == "[Q]" then return "<red>" end
    if marker == "[CP]" then return "<green>" end
    if marker == "[GQ]" then return "<dodger_blue>" end
    return "<white>"
end

local function formatMarkersColored(markerText)
    if markerText == "" then return "" end
    local chunks = {}
    for marker in markerText:gmatch("%b[]") do
        chunks[#chunks + 1] = string.format("%s%s<reset>", markerToColorToken(marker), marker)
    end
    if #chunks == 0 then return "" end
    return " " .. table.concat(chunks, " ")
end

function CW.getActiveEnemyName()
    local enemy = trim(gmcp_get("char.status.enemy"))
    if enemy ~= "" then return enemy end
    enemy = trim(gmcp_get("combat.target"))
    if enemy ~= "" then return enemy end
    enemy = trim(gmcp_get("char.status.opponent"))
    if enemy ~= "" then return enemy end
    return ""
end

function CW.killCommandFor(index)
    local m = CW.mobs[index]
    if not m then return nil end
    if m.dead then return nil end
    local base = trim(cfg().killCommand)
    if base == "" then base = "kill" end
    local aliveNames = {}
    for _, other in ipairs(CW.mobs) do
        if not other.dead and other.name and other.name ~= "" then
            table.insert(aliveNames, other.name)
        end
    end
    local kw = snd.utils.buildMobCommandSelector(m.name, aliveNames, {mode = "kill"})
    if not kw or kw == "" then
        kw = snd.utils.findKeyword(m.name)
    end
    local aliveDupCount = 0
    local aliveDupIndex = 1
    local targetName = normalizeMobName(m.name)
    for i, other in ipairs(CW.mobs) do
        if not other.dead and normalizeMobName(other.name) == targetName then
            aliveDupCount = aliveDupCount + 1
            if i == index then
                aliveDupIndex = aliveDupCount
            end
        end
    end
    if aliveDupCount > 1 then
        local dupIdx = math.max(1, math.floor(tonumber(aliveDupIndex) or 1))
        return string.format("%s %d.%s", base, dupIdx, kw)
    end
    return string.format("%s %s", base, kw)
end

function CW.noteAttackIntent(mob, source)
    if type(mob) ~= "table" then return nil end
    local name = normalizeMobName(mob.name)
    if name == "" then return nil end
    CW.pendingAttackIntent = {
        rowId = mob.id,
        name = name,
        roomId = currentRoomId(),
        createdAt = os.clock(),
        source = tostring(source or "attack"),
    }
    return CW.pendingAttackIntent
end

function CW.noteEscapeIntent(command)
    CW.pendingEscapeIntent = {
        command = tostring(command or ""),
        roomId = currentRoomId(),
        createdAt = os.clock(),
    }
end

function CW.attack(index)
    local cmd = CW.killCommandFor(tonumber(index))
    if not cmd then return end
    local m = CW.mobs[tonumber(index)]
    if m then
        CW.currentEnemyMobId = m.id
        CW.noteAttackIntent(m, "conwin")
    end
    send(cmd, false)
end

function CW.onHotkey(index)
    if not cfg().enabled then return end
    index = tonumber(index)
    if not index or index < 1 then return end
    if not CW.mobs[index] then return end
    if CW.mobs[index].dead then
        for i, m in ipairs(CW.mobs) do
            if not m.dead then
                index = i
                break
            end
        end
    end
    CW.attack(index)
end

function CW.selectMobForKeyword(keyword, dupIndex)
    local kw = trim(keyword):lower()
    if kw == "" then return nil end
    local matches = {}
    for _, m in ipairs(CW.mobs) do
        if not m.dead then
            local mobKeyword = trim(snd.utils.findKeyword(m.name)):lower()
            local mobName = normalizeMobName(m.name)
            if mobKeyword == kw or mobName:find(kw, 1, true)
                or (snd.utils.mobSelectorMatchesName and snd.utils.mobSelectorMatchesName(kw, m.name))
            then
                matches[#matches + 1] = m
            end
        end
    end
    if #matches == 0 then return nil end
    local idx = math.max(1, math.floor(tonumber(dupIndex) or 1))
    return matches[idx] or matches[1]
end

function CW.noteAttackByKeyword(keyword, dupIndex)
    local m = CW.selectMobForKeyword(keyword, dupIndex)
    if m then
        CW.currentEnemyMobId = m.id
        CW.noteAttackIntent(m, "outgoing-command")
        CW.render()
    end
    return m
end

function CW.trackAttackCommand(command)
    local raw = trim(command)
    if raw == "" then return end
    local lowered = raw:lower()
    local verb = lowered:match("^(%S+)") or ""
    if verb == "flee" or verb == "retreat" then
        CW.noteEscapeIntent(raw)
        return
    end

    if lowered == "xkill" then
        local t = snd.targets and snd.targets.current
        local keyword = ""
        if t then
            local names = {}
            for _, m in ipairs(CW.mobs or {}) do
                if not m.dead and m.name and m.name ~= "" then
                    table.insert(names, m.name)
                end
            end
            local selectorName = t.name or t.mob or ""
            local visibleName = CW.visibleNameForActivityTarget(selectorName, t.activity)
            if visibleName ~= "" then
                selectorName = visibleName
            end
            keyword = snd.utils.buildMobCommandSelector(selectorName, names, {mode = "kill"})
            if keyword == "" then
                if visibleName ~= "" then
                    keyword = snd.utils.findKeyword(visibleName)
                else
                    keyword = t.keyword or t.matchedMobName or snd.utils.findKeyword(t.name or "")
                end
            end
        end
        if t and t.name and keyword:find("%-") and snd.gmcp and snd.gmcp.guessMobKeyword then
            local arid = snd.room and snd.room.current and snd.room.current.arid
            local guessed = trim(snd.gmcp.guessMobKeyword(t.name, arid) or "")
            if guessed ~= "" then
                keyword = guessed
            end
        end
        keyword = trim(keyword:gsub("%s+", " "))
        CW.noteAttackByKeyword(keyword, 1)
        return
    end

    local base = trim(cfg().killCommand)
    if base == "" then base = "kill" end
    if not startsWithIgnoreCase(raw, base) then return end
    local rest = trim(raw:sub(#base + 1))
    if rest == "" then return end

    local dupIndex, keyword = rest:match("^(%d+)%.(.+)$")
    if not keyword or keyword == "" then
        keyword = rest
        dupIndex = 1
    end
    keyword = trim(keyword)
    if keyword == "" then return end
    CW.noteAttackByKeyword(keyword, dupIndex)
end

function CW.onDataSendRequest(...)
    local argc = select("#", ...)
    for i = 1, argc do
        local arg = select(i, ...)
        if type(arg) == "string" then
            if trim(arg):lower() == "consider all" then CW.suppressConsiderLines = false end
            CW.trackAttackCommand(arg)
            return
        end
        if type(arg) == "table" then
            local maybeCmd = arg.command or arg.cmd or arg.line
            if type(maybeCmd) == "string" then
                if trim(maybeCmd):lower() == "consider all" then CW.suppressConsiderLines = false end
                CW.trackAttackCommand(maybeCmd)
                return
            end
        end
    end
end

function CW.reindexDuplicates()
    local counts, seen = {}, {}
    for _, m in ipairs(CW.mobs) do
        local k = trim(m.name):lower()
        counts[k] = (counts[k] or 0) + 1
    end
    for _, m in ipairs(CW.mobs) do
        local k = trim(m.name):lower()
        seen[k] = (seen[k] or 0) + 1
        m.dupIndex = seen[k]
        m.dupCount = counts[k] or 1
    end
end

local function countAliveByNormalizedName(name)
    local needle = normalizeMobName(name)
    if needle == "" then return 0 end
    local count = 0
    for _, m in ipairs(CW.mobs) do
        if not m.dead and normalizeMobName(m.name) == needle then
            count = count + 1
        end
    end
    return count
end

function CW.render()
    if not CW.ui or not CW.ui.console then return end
    local c = CW.ui.console
    c:clear()
    c:setFontSize(cfg().fontSize)
    local rawActiveEnemy = trim(CW.getActiveEnemyName())
    local activeEnemy = normalizeMobName(rawActiveEnemy)
    local liveCombat = currentPlayerState() == "8" and activeEnemy ~= ""
    local enemyPct = clamp(gmcp_get("char.status.enemypct") or 100, 0, 100)
    if #CW.mobs == 0 then
        if liveCombat then
            c:cecho(string.format(
                "<white>[combat] %s %3d%%<reset>\n",
                rawActiveEnemy ~= "" and rawActiveEnemy or activeEnemy,
                enemyPct
            ))
        else
            c:cecho("<dim_gray>(no mobs)\n")
        end
        return
    end
    CW.reindexDuplicates()
    local strictFocus = cfg().strictFocusIdOnly and true or false
    local matchingEnemyCount = 0
    if activeEnemy ~= "" then
        for _, m in ipairs(CW.mobs) do
            if not m.dead then
                local mobName = normalizeMobName(m.name)
                if mobName == activeEnemy or mobName:find(activeEnemy, 1, true) or activeEnemy:find(mobName, 1, true) then
                    matchingEnemyCount = matchingEnemyCount + 1
                end
            end
        end
    end
    local hideAmbiguousEnemy = strictFocus and activeEnemy ~= "" and matchingEnemyCount > 1 and not CW.currentEnemyMobId

    if liveCombat and matchingEnemyCount == 0 then
        c:cecho(string.format(
            "<white>[combat] %s %3d%% <dim_gray>(not in considered list)<reset>\n",
            rawActiveEnemy ~= "" and rawActiveEnemy or activeEnemy,
            enemyPct
        ))
    end

    for i, m in ipairs(CW.mobs) do
        local marker = CW.activityMarkersForMob(m.name)
        local markerPrefix = formatMarkersColored(marker)
        local sword = ""
        local mobName = normalizeMobName(m.name)
        local nameMatchesEnemy = activeEnemy ~= "" and not m.dead and
            (mobName == activeEnemy or mobName:find(activeEnemy, 1, true) or activeEnemy:find(mobName, 1, true))
        local isFocusedEnemy = CW.currentEnemyMobId and (m.id == CW.currentEnemyMobId)
        local isActive = false
        if nameMatchesEnemy and not hideAmbiguousEnemy then
            if matchingEnemyCount <= 1 then
                isActive = true
            elseif isFocusedEnemy then
                isActive = true
            end
        end
        if isActive then
            sword = "⚔ "
        end
        local color = trim(m.color or "")
        if color == "" then color = "white" end
        local displayName = hpTintedName(m.name, color, color, enemyPct, isActive)
        local alignPrefix = ""
        if cfg().alignTags and m.alignTag == "G" then
            alignPrefix = "<gold>(G)<reset> "
        elseif cfg().alignTags and m.alignTag == "E" then
            alignPrefix = "<red>(E)<reset> "
        end
        local linePrefix = string.format("<white>%2d)<reset> ", i)
        local killTag = m.dead and "<ansiLightRed>✗<reset> " or ""
        local targetName = alignPrefix .. (markerPrefix ~= "" and (markerPrefix .. " ") or "") .. displayName
        local label = string.format("%s%s%s%s <dim_gray>(<%s>%s<dim_gray>)<reset>",
            linePrefix, killTag, sword, targetName, color, m.range or "?")
        if isActive then
            label = label .. string.format(" <white>%3d%%%s<reset>", enemyPct, enemyPct <= 25 and " !!" or "")
        end
        label = label .. "\n"
        if m.dead then
            c:cecho(label)
        else
            local cmd = string.format("snd.conwin.attack(%d)", i)
            local hint = CW.killCommandFor(i) or "kill"
            c:cechoLink(label, cmd, hint, true)
        end
    end
end

function CW.addMob(name, color, range)
    local mob = trim(name)
    if mob == "" then return end
    CW.nextMobId = CW.nextMobId + 1
    CW.mobs[#CW.mobs + 1] = {
        id = CW.nextMobId,
        name = mob,
        color = color or "white",
        range = range or "?",
        dead = false,
        alignTag = nil,
    }
    CW.render()
end

function CW.startCapture()
    CW.awaiting = true
    CW.resetConsideredMobs(false)
    CW.render()
end

function CW.finishCapture()
    CW.awaiting = false
    if CW.doneTimer then killTimer(CW.doneTimer) CW.doneTimer = nil end
    CW.killsSinceRefresh = 0
    CW.render()
    CW.resolveCurrentRoomTargetForNxAction()
end

function CW.deferFinish()
    if CW.doneTimer then killTimer(CW.doneTimer) end
    CW.doneTimer = tempTimer(0.25, function() CW.finishCapture() end)
end

function CW.considerLine(name, color, range, prefixHint)
    local function parseAlignTag(prefix)
        local token = trim(prefix):lower()
        if token == "" then return nil end
        if token:find("golden aura", 1, true) then
            return "G"
        end
        if token:find("red aura", 1, true) then
            return "E"
        end
        return nil
    end

    local function splitPrefixAndName(rawName)
        local text = trim(rawName)
        if text == "" then return "", nil end
        local prefix = text:match("^(%b())")
        local tag = parseAlignTag(prefix)
        if prefix then
            text = trim(text:gsub("^%b()%s*", "", 1))
        end
        return text, tag
    end

    local flight = CW.captureInFlight
    if CW.suppressConsiderLines and not flight then return end
    if flight and (flight.failed or flight.cancelled) then return end
    if flight then
        CW.noteCaptureRoom()
        CW.awaiting = true
    elseif not CW.awaiting then
        CW.startCapture()
    end
    local mobName, alignTag = splitPrefixAndName(name)
    if not alignTag then
        alignTag = parseAlignTag(prefixHint)
    end
    if flight then
        if mobName ~= "" then
            CW.nextMobId = CW.nextMobId + 1
            flight.mobs[#flight.mobs + 1] = {
                id = CW.nextMobId,
                name = mobName,
                color = color or "white",
                range = range or "?",
                dead = false,
                alignTag = alignTag,
            }
        end
    else
        CW.addMob(mobName, color, range)
        if #CW.mobs > 0 and alignTag then
            CW.mobs[#CW.mobs].alignTag = alignTag
        end
    end
    if mobName ~= "" and snd.db and snd.room and snd.room.current and snd.room.current.rmid then
        snd.db.recordMobSeen(
            mobName,
            snd.room.current.name,
            snd.room.current.rmid,
            snd.room.current.arid
        )
    end
    if not flight then
        CW.deferFinish()
    end
end

function CW.refresh(source)
    if not cfg().enabled then return end
    source = tostring(source or "manual")
    local delay = source == "manual" and 0 or CW.ROOM_REFRESH_DELAY
    return CW.requestRefresh(source, true, delay)
end

local function requestRepopulateRefresh()
    local requested = CW.refresh("repopulate")
    if requested then
        -- A combat-issued stop may leave a stale mapper destination. Only the
        -- threshold-approved refresh should bypass that stale destination.
        CW.combatSessionActive = true
        CW.combatRefreshQueued = true
    end
    return requested
end

local function aliveRowsByName(name)
    local needle = normalizeMobName(name)
    local rows = {}
    if needle == "" then return rows end
    for _, mob in ipairs(CW.mobs or {}) do
        if not mob.dead and normalizeMobName(mob.name) == needle then
            rows[#rows + 1] = mob
        end
    end
    return rows
end

local function aliveRowById(rowId, expectedName)
    if rowId == nil then return nil end
    local needle = normalizeMobName(expectedName)
    for _, mob in ipairs(CW.mobs or {}) do
        if tostring(mob.id) == tostring(rowId) and not mob.dead
                and (needle == "" or normalizeMobName(mob.name) == needle) then
            return mob
        end
    end
    return nil
end

function CW.getRecentAttackIntent(enemyName)
    local intent = CW.pendingAttackIntent
    if type(intent) ~= "table" then return nil end
    local age = os.clock() - (tonumber(intent.createdAt) or 0)
    if age < 0 or age > CW.ATTACK_INTENT_TTL then
        CW.pendingAttackIntent = nil
        return nil
    end
    if intent.roomId ~= "" and tostring(intent.roomId) ~= currentRoomId() then
        CW.pendingAttackIntent = nil
        return nil
    end
    if normalizeMobName(intent.name) ~= normalizeMobName(enemyName) then
        return nil
    end
    return intent
end

function CW.hasRecentEscapeIntent()
    local intent = CW.pendingEscapeIntent
    if type(intent) ~= "table" then return false end
    local age = os.clock() - (tonumber(intent.createdAt) or 0)
    if age < 0 or age > CW.ESCAPE_INTENT_TTL then
        CW.pendingEscapeIntent = nil
        return false
    end
    if intent.roomId ~= "" and tostring(intent.roomId) ~= currentRoomId() then
        return false
    end
    return true
end

function CW.bindCombatEnemy(enemyName, enemyPct, preferredRowId)
    local normalizedName = normalizeMobName(enemyName)
    if normalizedName == "" then return nil end

    local row = aliveRowById(preferredRowId, normalizedName)
    local candidates = aliveRowsByName(normalizedName)
    if not row and (#candidates == 1 or not cfg().strictFocusIdOnly) then
        row = candidates[1]
    end

    local hp = tonumber(enemyPct)
    if hp ~= nil then hp = clamp(hp, 0, 100) end
    local combat = CW.combat
    combat.generation = (tonumber(combat.generation) or 0) + 1
    combat.activeRowId = row and row.id or nil
    combat.activeName = normalizedName
    combat.lastHp = hp
    combat.minimumHp = hp
    combat.roomId = currentRoomId()
    CW.currentEnemyMobId = combat.activeRowId
    CW.lastTrackedMobId = combat.activeRowId
    CW.lastKnownEnemyPct = hp
    return row
end

function CW.recordDeathEvent(name, rowId, cause, hpBefore)
    local normalizedName = normalizeMobName(name)
    if normalizedName == "" then return nil end
    CW.deathEventSerial = (tonumber(CW.deathEventSerial) or 0) + 1
    local event = {
        serial = CW.deathEventSerial,
        name = normalizedName,
        rowId = rowId,
        cause = tostring(cause or "combat-transition"),
        hpBefore = tonumber(hpBefore),
        roomId = currentRoomId(),
        at = os.time(),
        clock = os.clock(),
    }
    CW.deathEvents[#CW.deathEvents + 1] = event
    while #CW.deathEvents > 16 do
        table.remove(CW.deathEvents, 1)
    end
    CW.lastKilledMobName = normalizedName
    CW.lastKilledAt = event.at
    return event
end

function CW.markCombatEnemyDead(rowId, enemyName, cause, hpBefore)
    local normalizedName = normalizeMobName(enemyName)
    if normalizedName == "" then return false end

    local row = aliveRowById(rowId, normalizedName)
    local candidates = aliveRowsByName(normalizedName)
    if not row and (#candidates == 1 or not cfg().strictFocusIdOnly) then
        row = candidates[1]
    end
    if row and row.dead then return false end

    local recordedName = row and trim(row.name) or normalizedName
    if row then row.dead = true end
    CW.killsSinceRefresh = (tonumber(CW.killsSinceRefresh) or 0) + 1
    CW.recordDeathEvent(recordedName, row and row.id or nil, cause, hpBefore)

    if recordedName ~= "" and snd.db and snd.room and snd.room.current and snd.room.current.rmid then
        snd.db.recordMobKill(
            recordedName,
            snd.room.current.rmid,
            snd.room.current.name,
            snd.room.current.arid
        )
    end

    CW.render()
    local threshold = math.max(0, math.floor(tonumber(cfg().repopulate) or 0))
    if threshold > 0 and CW.killsSinceRefresh >= threshold
            and cfg().enabled and tostring(cfg().mode or "consider"):lower() == "consider" then
        requestRepopulateRefresh()
    end
    return true
end

function CW.scheduleCombatEnd()
    local combat = CW.combat
    if combat.activeName == "" or combat.pendingEndTimer then return false end

    combat.pendingEndSerial = (tonumber(combat.pendingEndSerial) or 0) + 1
    local serial = combat.pendingEndSerial
    local pending = {
        rowId = combat.activeRowId,
        name = combat.activeName,
        hp = combat.lastHp,
        roomId = combat.roomId ~= "" and combat.roomId or currentRoomId(),
    }
    combat.pendingEndTimer = tempTimer(CW.COMBAT_END_DELAY, function()
        if serial ~= tonumber(CW.combat.pendingEndSerial) then return end
        CW.combat.pendingEndTimer = nil

        local roomId = currentRoomId()
        if roomId == "" or tostring(roomId) ~= tostring(pending.roomId) then
            CW.clear("combat-ended-after-movement")
            return
        end

        local state = currentPlayerState()
        local activeEnemy = normalizeMobName(CW.getActiveEnemyName())
        if state == "8" and activeEnemy ~= "" then
            local hp = tonumber(gmcp_get("char.status.enemypct"))
            CW.observeCombatStatus(state, activeEnemy, hp)
            return
        end

        if CW.hasRecentEscapeIntent() then
            CW.releaseCombatBinding()
            CW.render()
            return
        end

        if state == "3" and activeEnemy == "" then
            CW.markCombatEnemyDead(pending.rowId, pending.name, "combat-ended", pending.hp)
        end
        CW.releaseCombatBinding()
        CW.render()
    end)
    return true
end

function CW.confirmPendingCombatDeath(cause)
    local combat = CW.combat
    if not combat.pendingEndTimer or combat.activeName == "" then return "" end
    local rowId = combat.activeRowId
    local name = combat.activeName
    local hp = combat.lastHp
    CW.cancelPendingCombatEnd()
    CW.markCombatEnemyDead(rowId, name, cause or "kill-message", hp)
    CW.releaseCombatBinding()
    CW.render()
    return name
end

function CW.observeCombatStatus(playerState, enemyName, enemyPct)
    local state = tostring(playerState or "")
    local normalizedName = normalizeMobName(enemyName)
    local combatNow = state == "8" and normalizedName ~= ""
    local combat = CW.combat

    if not combatNow then
        if combat.activeName ~= "" then
            CW.scheduleCombatEnd()
        end
        return false
    end

    CW.cancelPendingCombatEnd()
    local hp = tonumber(enemyPct)
    if hp ~= nil then hp = clamp(hp, 0, 100) end
    local intent = CW.getRecentAttackIntent(normalizedName)

    if combat.activeName == "" then
        CW.bindCombatEnemy(normalizedName, hp, intent and intent.rowId or nil)
    elseif combat.activeName ~= normalizedName then
        local previousRowId = combat.activeRowId
        local previousName = combat.activeName
        local previousHp = combat.lastHp
        if not intent then
            CW.markCombatEnemyDead(previousRowId, previousName, "target-changed", previousHp)
        end
        CW.bindCombatEnemy(normalizedName, hp, intent and intent.rowId or nil)
    else
        local manualSameNameSwitch = intent and intent.rowId ~= nil
            and tostring(intent.rowId) ~= tostring(combat.activeRowId)
        if manualSameNameSwitch then
            CW.bindCombatEnemy(normalizedName, hp, intent.rowId)
        else
            local lastHp = tonumber(combat.lastHp)
            local minimumHp = tonumber(combat.minimumHp)
            local hasAnotherCopy = combat.activeRowId ~= nil
                and countAliveByNormalizedName(normalizedName) > 1
            local resetDetected = hp ~= nil and lastHp ~= nil and minimumHp ~= nil
                and hasAnotherCopy
                and minimumHp <= CW.SAME_NAME_RESET_MAX_LOW
                and (hp - lastHp) >= CW.SAME_NAME_RESET_MIN_JUMP
            if resetDetected then
                local previousRowId = combat.activeRowId
                CW.markCombatEnemyDead(previousRowId, normalizedName, "same-name-hp-reset", lastHp)
                CW.bindCombatEnemy(normalizedName, hp, nil)
            else
                if hp ~= nil then
                    combat.lastHp = hp
                    combat.minimumHp = minimumHp and math.min(minimumHp, hp) or hp
                    CW.lastKnownEnemyPct = hp
                end
            end
        end
    end

    if intent then CW.pendingAttackIntent = nil end
    CW.pendingEscapeIntent = nil
    CW.render()
    return true
end

function CW.onRoomInfo()
    local roomId = currentRoomId()
    local moved = false
    if roomId ~= "" and CW.lastRoomId and roomId ~= CW.lastRoomId then
        moved = true
    end
    if roomId ~= "" then
        if not CW.lastRoomId then moved = true end
        CW.lastRoomId = roomId
    end

    if moved then
        CW.latestRoomId = roomId
        CW.onTravelStarted("room-changed")
        -- Debounce rapid Room.Info bursts. The callback still requires GMCP
        -- state 3 and no mapper continuation before it may send anything.
        CW.requestRefresh("room-arrived", false)
    end
end

function CW.onRoomcharsEnd()
    if not cfg().clearOnEmptyRoomchars then return end
    -- RoomChars may clear stale considered rows, but never contributes rows.
    if CW.awaiting and #CW.mobs == 0 then
        CW.clear("empty-roomchars")
    end
end

function CW.onEmptyConsiderResult()
    if CW.suppressConsiderLines and not CW.captureInFlight then return end
    if CW.captureInFlight then
        if CW.captureInFlight.failed or CW.captureInFlight.cancelled then return end
        CW.noteCaptureRoom()
        CW.captureInFlight.mobs = {}
        return
    end
    CW.clear("empty")
end

function CW.createWindow()
    if not Geyser then return false end
    local c = cfg()
    if CW.ui and CW.ui.container then return true end
    CW.ui = CW.ui or {}
    local created = nil
    if Adjustable and Adjustable.Container and Adjustable.Container.new then
        local okAdj, adj = pcall(function()
            return Adjustable.Container:new({
                name = "sndConwinContainer",
                x = c.x,
                y = c.y,
                width = c.width,
                height = c.height,
                adjLabelstyle = "border: 1px solid #4a4a4a; background-color: #000000;",
                buttonstyle = "",
                lockStyle = "border: 0px;",
                titleText = "",
                titleTxtColor = "white",
            })
        end)
        if okAdj then created = adj end
    end
    if not created then
        created = Geyser.Container:new({name="sndConwinContainer", x=c.x, y=c.y, width=c.width, height=c.height})
        if created and created.enableDrag then created:enableDrag() end
    end
    CW.ui.container = created
    CW.ui.console = Geyser.MiniConsole:new({name="sndConwinConsole", x=0, y=0, width="100%", height="100%"}, CW.ui.container)
    CW.ui.console:setColor("black")
    CW.ui.console:setFontSize(c.fontSize)
    CW.ui.console:cecho("<gold>[S&D ConWin]\n")
    return true
end

function CW.onCharStatus()
    local playerState = currentPlayerState()
    local previousPlayerState = CW.lastPlayerState
    local rawEnemyNow = CW.getActiveEnemyName()
    local enemyNow = normalizeMobName(rawEnemyNow)
    local combatNow = playerState == "8" or enemyNow ~= ""
    CW.lastPlayerState = playerState

    if combatNow then
        if not CW.combatSessionActive then
            CW.combatSessionActive = true
            CW.combatRefreshQueued = false
        end
        CW.cancelRoomRefreshTimer()
        if CW.captureInFlight then
            CW.captureInFlight.failed = true
        end
    elseif playerState == "12" then
        CW.onTravelStarted("running")
    elseif playerState == "3" then
        if CW.combatSessionActive and CW.combatRefreshQueued then
            -- The timer may have fired while combat still made the refresh
            -- ineligible, or a later combat packet may have cancelled it.
            if not CW.captureInFlight and not CW.roomRefreshTimer and CW.hasPendingRefresh() then
                CW.armRoomRefresh()
            end
        elseif CW.combatSessionActive and CW.hasPendingRefresh() then
            CW.combatRefreshQueued = CW.requestRefresh("post-combat-retry", false) == true
        else
            -- Ordinary combat completion is handled by the kill counter below.
            -- Do not refresh here or the configured repopulate threshold is bypassed.
            CW.combatSessionActive = false
            CW.combatRefreshQueued = false
            CW.maybeRefreshStoppedRoom(previousPlayerState == "8" and "post-combat-ready" or "player-ready")
        end
    end

    local enemyPct = tonumber(gmcp_get("char.status.enemypct"))
    CW.observeCombatStatus(playerState, rawEnemyNow, enemyPct)
    CW.lastEnemy = enemyNow
    CW.lastRawEnemy = rawEnemyNow
    CW.lastTrackedMobId = CW.currentEnemyMobId
end

function CW.getRecentKilledMobName(maxAgeSeconds)
    local ttl = tonumber(maxAgeSeconds) or 3
    if ttl < 0 then ttl = 0 end

    local nowClock = os.clock()
    for i = #CW.deathEvents, 1, -1 do
        local event = CW.deathEvents[i]
        local age = nowClock - (tonumber(event.clock) or nowClock)
        if age < 0 or age > ttl then
            table.remove(CW.deathEvents, i)
        end
    end
    local event = CW.deathEvents[1]
    if event then
        CW.lastReturnedDeathSerial = event.serial
        return trim(event.name or "")
    end

    local killedName = trim(CW.lastKilledMobName or "")
    if killedName == "" then return "" end
    local killedAt = tonumber(CW.lastKilledAt) or 0
    if killedAt <= 0 then return "" end
    if (os.time() - killedAt) > ttl then return "" end
    return killedName
end

function CW.clearRecentKilledMobName()
    local returnedSerial = CW.lastReturnedDeathSerial
    if returnedSerial ~= nil then
        for i, event in ipairs(CW.deathEvents) do
            if tostring(event.serial) == tostring(returnedSerial) then
                table.remove(CW.deathEvents, i)
                break
            end
        end
    end
    CW.lastReturnedDeathSerial = nil

    local newest = CW.deathEvents[#CW.deathEvents]
    if newest then
        CW.lastKilledMobName = newest.name or ""
        CW.lastKilledAt = newest.at or 0
    else
        CW.lastKilledMobName = ""
        CW.lastKilledAt = 0
    end
end

function CW.getCurrentCombatMobName()
    -- A target is authoritative only while GMCP also says the player is fighting.
    if currentPlayerState() ~= "8" then return "" end
    local activeEnemy = normalizeMobName(CW.getActiveEnemyName())
    if activeEnemy == "" then return "" end
    -- ID match is preferred for precision, but only when it agrees with GMCP.
    if CW.currentEnemyMobId then
        for _, m in ipairs(CW.mobs) do
            if m.id == CW.currentEnemyMobId and not m.dead and normalizeMobName(m.name) == activeEnemy then
                return activeEnemy
            end
        end
    end
    -- Name-only fallback (handles case where ID was stale or never set)
    for _, m in ipairs(CW.mobs) do
        if not m.dead and normalizeMobName(m.name) == activeEnemy then
            return activeEnemy
        end
    end
    -- GMCP remains authoritative even when an aggressive joiner was not part
    -- of the last consider snapshot; the UI shows it as a combat-only row.
    return activeEnemy
end

function CW.onPrompt()
    CW.onCharStatus()
end

local function readContainerValue(container, keys)
    if type(container) ~= "table" then return nil end
    for _, key in ipairs(keys) do
        local member = container[key]
        if type(member) == "function" then
            local ok, value = pcall(member, container)
            if ok and value ~= nil then return value end
        elseif member ~= nil then
            return member
        end
    end
    return nil
end

function CW.captureWindowState()
    local c = cfg()
    local container = CW.ui and CW.ui.container
    if not container then return end
    local x = readContainerValue(container, {"get_x", "getX", "x"})
    local y = readContainerValue(container, {"get_y", "getY", "y"})
    local w = readContainerValue(container, {"get_width", "getWidth", "width"})
    local h = readContainerValue(container, {"get_height", "getHeight", "height"})
    if x ~= nil then c.x = x end
    if y ~= nil then c.y = y end
    if w ~= nil then c.width = w end
    if h ~= nil then c.height = h end
end

function CW.show()
    if not CW.createWindow() then return end
    if CW.ui and CW.ui.container then CW.ui.container:show() end
end

function CW.hide()
    if CW.ui and CW.ui.container then CW.ui.container:hide() end
end

function CW.setEnabled(v)
    cfg().enabled = v and true or false
    if cfg().enabled then CW.show() else CW.hide() end
    snd.saveState()
end

function CW.toggle()
    CW.setEnabled(not cfg().enabled)
end

function CW.setFontSize(n)
    n = tonumber(n)
    if not n or n < 6 or n > 24 then return false end
    cfg().fontSize = math.floor(n)
    if CW.ui and CW.ui.console then CW.ui.console:setFontSize(cfg().fontSize) end
    CW.render()
    snd.saveState()
    return true
end

function CW.setMode(mode)
    mode = tostring(mode or ""):lower()
    if mode ~= "consider" and mode ~= "off" then
        return false
    end
    cfg().mode = mode
    snd.saveState()
    return true
end

function CW.setKillCommand(command)
    local cmd = trim(command)
    if cmd == "" then
        return false
    end
    cfg().killCommand = cmd
    CW.render()
    snd.saveState()
    return true
end

function CW.setRepopulate(n)
    n = tonumber(n)
    if not n then return false end
    n = math.floor(n)
    if n < 0 or n > 999 then return false end
    cfg().repopulate = n
    snd.saveState()
    return true
end

function CW.setFocusIdMode(mode)
    mode = tostring(mode or ""):lower()
    if mode ~= "strict" and mode ~= "fallback" then
        return false
    end
    cfg().strictFocusIdOnly = (mode == "strict")
    CW.render()
    snd.saveState()
    return true
end

function CW.setAlignTagsEnabled(mode)
    local v = tostring(mode or ""):lower()
    if v == "on" then
        cfg().alignTags = true
    elseif v == "off" then
        cfg().alignTags = false
    else
        return false
    end
    CW.render()
    snd.saveState()
    return true
end

function CW.install()
    cfg()
    CW.createWindow()
    if cfg().enabled then CW.show() else CW.hide() end

    for _, id in ipairs(CW.ids.triggers) do pcall(killTrigger, id) end
    CW.ids.triggers = {}

    for _, row in ipairs(consider_map) do
        CW.ids.triggers[#CW.ids.triggers + 1] = tempRegexTrigger(row[1], function()
            CW.considerLine(matches[3] or matches[2], row[2], row[3], matches[1] or "")
        end)
    end

    CW.ids.triggers[#CW.ids.triggers + 1] = tempRegexTrigger("^" .. CW.MARKER .. ":(\\d+)$", function()
        deleteLine()
        CW.onCaptureMarker(matches[2])
    end)
    CW.ids.triggers[#CW.ids.triggers + 1] = tempRegexTrigger("^nhm$", function()
        deleteLine()
        if not CW.captureInFlight then CW.finishCapture() end
    end)
    CW.ids.triggers[#CW.ids.triggers + 1] = tempRegexTrigger("^You see no one here but yourself!$", "snd.conwin.onEmptyConsiderResult")
    CW.ids.triggers[#CW.ids.triggers + 1] = tempRegexTrigger("^Not while you are fighting!$", "snd.conwin.onConsiderRejected")
    -- TODO: do repop/sense life in the future.

    for _, id in ipairs(CW.ids.events) do pcall(killAnonymousEventHandler, id) end
    CW.ids.events = {}
    CW.ids.events[#CW.ids.events+1] = registerAnonymousEventHandler("gmcp.room.info", "snd.conwin.onRoomInfo")
    CW.ids.events[#CW.ids.events+1] = registerAnonymousEventHandler("gmcp.char.status", "snd.conwin.onCharStatus")
    CW.ids.events[#CW.ids.events+1] = registerAnonymousEventHandler("gmcp.comm.prompt", "snd.conwin.onPrompt")
    CW.ids.events[#CW.ids.events+1] = registerAnonymousEventHandler("sysDataSendRequest", "snd.conwin.onDataSendRequest")

    for _, id in ipairs(CW.ids.keys or {}) do pcall(killKey, id) end
    CW.ids.keys = {}
    for _, id in ipairs(CW.ids.aliases or {}) do pcall(killAlias, id) end
    CW.ids.aliases = {}
    if type(tempAlias) == "function" then
        for i = 1, 9 do
            local aliasPattern = string.format("^%d$", i)
            CW.ids.aliases[#CW.ids.aliases + 1] = tempAlias(aliasPattern, function() CW.onHotkey(i) end)
        end
    end
end
