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
CW.mobDetectDispatched = CW.mobDetectDispatched or false
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
        mode = "consider", -- consider | scan | off
        strictFocusIdOnly = false, -- When true, ambiguous duplicate targets require currentEnemyMobId for HP overlay/death mark.
        killCommand = "kill",
        repopulate = 3, -- Refresh window after N confirmed kills (0 = disabled)
        clearOnSafe = true,
        clearOnEmptyRoomchars = true,
        alignTags = true,
    }
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


local function tokenizedContainsPk(info)
    local v = tostring(info or ""):lower()
    if v == "" then return false end
    for token in v:gmatch("[^,%s]+") do
        if token == "pk" then return true end
    end
    return false
end

function CW.isCurrentRoomPk()
    local details = gmcp_get("room.info.details")
    if details ~= nil and tokenizedContainsPk(details) then return true end
    local roomId = tostring(gmcp_get("room.info.num") or "")
    if roomId ~= "" and snd.mapper and type(snd.mapper.getRoomInfo) == "function" then
        local room = snd.mapper.getRoomInfo(roomId)
        if room and room.info then
            return tokenizedContainsPk(room.info)
        end
    end
    return false
end

function CW.roomHasPlayers()
    -- TODO: Aardwolf GMCP does not currently provide a documented room-players list.
    -- If a reliable source becomes available (GMCP payload or deterministic tagged output),
    -- implement player-presence detection here and re-enable this safety guard.
    return false
end

local function activeActivityLabel(target)
    local activity = tostring(target and target.activity or ""):lower()
    if activity == "cp" and snd and snd.campaign and snd.campaign.active then
        return "CP"
    elseif activity == "gq" and snd and snd.gquest and snd.gquest.active then
        return "GQ"
    elseif activity == "quest" and snd and snd.quest and snd.quest.active then
        return "quest"
    end
    return nil
end

function CW.tryMobDetectConfirmedTarget()
    if CW.mobDetectDispatched then return false end
    local mode = tostring(snd and snd.config and snd.config.mobdetect or "off"):lower()
    if mode == "off" then return false end

    local roomId = tostring(gmcp_get("room.info.num") or "")
    if roomId == "" or roomId ~= tostring(CW.lastRoomId or "") then return false end

    local current = snd and snd.targets and snd.targets.current or nil
    if not current then return false end
    if current.dead or tostring(current.status or ""):lower() == "dead" then return false end
    local activityLabel = activeActivityLabel(current)
    if not activityLabel then return false end

    local targetName = normalizeMobName(current.name or "")
    local present = false
    for _, m in ipairs(CW.mobs or {}) do
        if not m.dead and normalizeMobName(m.name) == targetName then
            present = true
            break
        end
    end
    if not present then return false end
    
    if snd and snd.mapper and type(snd.mapper.isInCombat) == "function" and snd.mapper.isInCombat() then
        return false
    end
    
    if mode ~= "always" then
        if snd and snd.room and snd.room.current and snd.room.current.maze and snd.room.current.maze ~= 0 then return false end
        if CW.isCurrentRoomPk() then return false end
        if CW.roomHasPlayers() then return false end
    end

    
    return true
end
function CW.clear(_reason)
    CW.mobs = {}
    CW.killsSinceRefresh = 0
    CW.currentEnemyMobId = nil
    CW.lastKnownEnemyPct = nil
    CW.lastTrackedMobId = nil
    CW.render()
end

function CW.isCurrentRoomSafe()
    local details = gmcp_get("room.info.details")
    if details ~= nil and tokenizedContainsSafe(details) then return true end
    local roomId = tostring(gmcp_get("room.info.num") or "")
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

function CW.attack(index)
    local cmd = CW.killCommandFor(tonumber(index))
    if not cmd then return end
    local m = CW.mobs[tonumber(index)]
    if m then
        CW.currentEnemyMobId = m.id
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
        CW.render()
    end
end

function CW.trackAttackCommand(command)
    local raw = trim(command)
    if raw == "" then return end
    local lowered = raw:lower()

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
            CW.trackAttackCommand(arg)
            return
        end
        if type(arg) == "table" then
            local maybeCmd = arg.command or arg.cmd or arg.line
            if type(maybeCmd) == "string" then
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
    if #CW.mobs == 0 then
        c:cecho("<dim_gray>(no mobs)\n")
        return
    end
    CW.reindexDuplicates()
    local activeEnemy = normalizeMobName(CW.getActiveEnemyName())
    local enemyPct = clamp(gmcp_get("char.status.enemypct") or 100, 0, 100)
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
    CW.mobDetectDispatched = false
    CW.clear("start")
end

function CW.finishCapture()
    CW.awaiting = false
    if CW.doneTimer then killTimer(CW.doneTimer) CW.doneTimer = nil end
    CW.render()
    CW.tryMobDetectConfirmedTarget()
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

    if not CW.awaiting then
        CW.startCapture()
    end
    local mobName, alignTag = splitPrefixAndName(name)
    if not alignTag then
        alignTag = parseAlignTag(prefixHint)
    end
    CW.addMob(mobName, color, range)
    if #CW.mobs > 0 and alignTag then
        CW.mobs[#CW.mobs].alignTag = alignTag
    end
    if mobName ~= "" and snd.db and snd.room and snd.room.current and snd.room.current.rmid then
        snd.db.recordMobSeen(
            mobName,
            snd.room.current.name,
            snd.room.current.rmid,
            snd.room.current.arid
        )
    end
    CW.deferFinish()
end

function CW.refresh(source)
    if not cfg().enabled then return end
    if CW.awaiting then return end
    if CW.shouldClearForSafeRoom() then
        CW.clear("safe")
        return
    end
    source = tostring(source or "manual")
    if source == "auto" then
        local roomId = tostring(gmcp_get("room.info.num") or "")
        local now = os.time()
        if roomId ~= "" and CW.lastAutoRoomId == roomId and (now - (CW.lastAutoConsiderAt or 0)) < 15 then
            return
        end
        CW.lastAutoRoomId = roomId
        CW.lastAutoConsiderAt = now
    end
    CW.startCapture()
    send("consider all", false)
    send("echo " .. CW.MARKER, false)
end

function CW.onRoomInfo()
    local roomId = tostring(gmcp_get("room.info.num") or "")
    local moved = false
    if roomId ~= "" and CW.lastRoomId and roomId ~= CW.lastRoomId then
        moved = true
        CW.clear("room-changed")
    end
    if roomId ~= "" then
        if not CW.lastRoomId then moved = true end
        CW.lastRoomId = roomId
    end

    if not moved or not cfg().enabled then return end
    local mode = tostring(cfg().mode or "consider"):lower()
    if mode ~= "consider" and mode ~= "scan" then return end

    if CW.isCurrentRoomSafe() then
        CW.clear("safe-room")
        return
    end

    if mode == "consider" then
        CW.refresh("auto")
    elseif mode == "scan" then
        send("scan", false)
    end
end

function CW.onRoomcharsEnd()
    if not cfg().clearOnEmptyRoomchars then return end
    -- If roomchars stream ended and no mobs were parsed for this room, clear stale entries.
    if CW.awaiting and #CW.mobs == 0 then
        CW.clear("empty-roomchars")
    end
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
    local prevEnemy = normalizeMobName(CW.lastEnemy or "")
    local prevRawEnemy = trim(CW.lastRawEnemy or "")
    local rawEnemyNow = CW.getActiveEnemyName()
    local enemyNow = normalizeMobName(rawEnemyNow)
    local hadEnemy = prevEnemy ~= ""
    local hasEnemy = enemyNow ~= ""

    if hadEnemy and not hasEnemy then
        local prevKnownEnemyPct = CW.lastKnownEnemyPct
        local matched = false
        local killedMobName = ""
        local strictFocus = cfg().strictFocusIdOnly and true or false
        local ambiguousPrevEnemy = strictFocus and not CW.currentEnemyMobId and countAliveByNormalizedName(prevEnemy) > 1
        if CW.currentEnemyMobId then
            for _, m in ipairs(CW.mobs) do
                if m.id == CW.currentEnemyMobId and not m.dead then
                    m.dead = true
                    killedMobName = m.name or ""
                    matched = true
                    break
                end
            end
        end
        if not matched and not ambiguousPrevEnemy then
            for _, m in ipairs(CW.mobs) do
                if not m.dead and normalizeMobName(m.name) == prevEnemy then
                    m.dead = true
                    killedMobName = m.name or ""
                    matched = true
                    break
                end
            end
        end
        CW.currentEnemyMobId = nil
        CW.lastKnownEnemyPct = nil
        if matched then
            CW.lastKilledMobName = normalizeMobName(killedMobName)
            CW.lastKilledAt = os.time()
            CW.killsSinceRefresh = (tonumber(CW.killsSinceRefresh) or 0) + 1
        end

        if matched then
            local mobToRecord = trim(killedMobName)
            if mobToRecord == "" then
                mobToRecord = trim(CW.lastEnemy or "")
            end
            if mobToRecord ~= "" and snd.db and snd.room and snd.room.current and snd.room.current.rmid then
                snd.db.recordMobKill(
                    mobToRecord,
                    snd.room.current.rmid,
                    snd.room.current.name,
                    snd.room.current.arid
                )
            end
        end

        if not matched and #CW.mobs == 0 and prevRawEnemy ~= ""
                and prevKnownEnemyPct == 0 then
            CW.lastKilledMobName = prevRawEnemy
            CW.lastKilledAt = os.time()
        end

        local threshold = math.max(0, math.floor(tonumber(cfg().repopulate) or 0))
        if matched and threshold > 0 and CW.killsSinceRefresh >= threshold and cfg().enabled and tostring(cfg().mode or "consider"):lower() == "consider" then
            CW.refresh("auto")
        else
            CW.render()
        end
    else
        local phantomKill = false
        if CW.currentEnemyMobId ~= CW.lastTrackedMobId then
            CW.lastKnownEnemyPct = nil
        end
        if hasEnemy then
            local enemyPct = clamp(gmcp_get("char.status.enemypct") or 100, 0, 100)
            if CW.currentEnemyMobId and prevEnemy == enemyNow
                    and CW.lastKnownEnemyPct and CW.lastKnownEnemyPct < 30
                    and enemyPct > CW.lastKnownEnemyPct + 50
                    and countAliveByNormalizedName(enemyNow) > 1 then
                for _, m in ipairs(CW.mobs) do
                    if m.id == CW.currentEnemyMobId and not m.dead and normalizeMobName(m.name) == enemyNow then
                        m.dead = true
                        CW.killsSinceRefresh = (tonumber(CW.killsSinceRefresh) or 0) + 1
                        phantomKill = true
                        local killedName = trim(m.name or "")
                        if killedName ~= "" and snd.db and snd.room and snd.room.current and snd.room.current.rmid then
                            snd.db.recordMobKill(killedName, snd.room.current.rmid, snd.room.current.name, snd.room.current.arid)
                        end
                        break
                    end
                end
                if phantomKill then
                    CW.currentEnemyMobId = nil
                end
            end
            CW.lastKnownEnemyPct = enemyPct
            if not CW.currentEnemyMobId then
                local strictFocus = cfg().strictFocusIdOnly and true or false
                local aliveMatches = countAliveByNormalizedName(enemyNow)
                if not (strictFocus and aliveMatches > 1) then
                    for _, m in ipairs(CW.mobs) do
                        if not m.dead and normalizeMobName(m.name) == enemyNow then
                            CW.currentEnemyMobId = m.id
                            break
                        end
                    end
                end
            end
        else
            CW.lastKnownEnemyPct = nil
        end
        local threshold = math.max(0, math.floor(tonumber(cfg().repopulate) or 0))
        if phantomKill and threshold > 0 and CW.killsSinceRefresh >= threshold and cfg().enabled and tostring(cfg().mode or "consider"):lower() == "consider" then
            CW.refresh("auto")
        else
            CW.render()
        end
    end
    CW.lastEnemy = enemyNow
    CW.lastRawEnemy = rawEnemyNow
    CW.lastTrackedMobId = CW.currentEnemyMobId
end

function CW.getRecentKilledMobName(maxAgeSeconds)
    local killedName = trim(CW.lastKilledMobName or "")
    if killedName == "" then return "" end
    local ttl = tonumber(maxAgeSeconds) or 3
    if ttl < 0 then ttl = 0 end
    local killedAt = tonumber(CW.lastKilledAt) or 0
    if killedAt <= 0 then return "" end
    if (os.time() - killedAt) > ttl then return "" end
    return killedName
end

function CW.clearRecentKilledMobName()
    CW.lastKilledMobName = ""
    CW.lastKilledAt = 0
end

function CW.getCurrentCombatMobName()
    -- Require live GMCP enemy name in all paths: currentEnemyMobId is only set when nil
    -- (see onCharStatus), so it can be stale if the player switched targets without a kill.
    -- Gating on activeEnemy ensures we never return a mob that disagrees with GMCP.
    local activeEnemy = normalizeMobName(CW.getActiveEnemyName())
    if activeEnemy == "" then return "" end
    -- ID match is preferred for precision, but only when ID mob name agrees with GMCP
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
    if #CW.mobs == 0 then
        return activeEnemy
    end
    return ""
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
    if mode ~= "consider" and mode ~= "scan" and mode ~= "off" then
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

    CW.ids.triggers[#CW.ids.triggers + 1] = tempRegexTrigger("^" .. CW.MARKER .. "$", function() deleteLine(); CW.finishCapture() end)
    CW.ids.triggers[#CW.ids.triggers + 1] = tempRegexTrigger("^nhm$", function() deleteLine(); CW.finishCapture() end)
    CW.ids.triggers[#CW.ids.triggers + 1] = tempRegexTrigger("^You see no one here but yourself!$", function() CW.clear("empty") end)
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
