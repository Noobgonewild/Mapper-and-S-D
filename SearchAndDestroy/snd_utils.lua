snd = snd or {}
snd.utils = snd.utils or {}

-- Convert Aardwolf @ color codes to Mudlet colors.
snd.utils.aardColorMap = {
    ["k"] = "<black>",
    ["r"] = "<maroon>",
    ["g"] = "<green>",
    ["y"] = "<ansi_yellow>",
    ["b"] = "<navy>",
    ["m"] = "<purple>",
    ["c"] = "<turquoise>",
    ["w"] = "<light_gray>",
    ["D"] = "<gray>",
    ["R"] = "<red>",
    ["G"] = "<ansi_light_green>",
    ["Y"] = "<yellow>",
    ["B"] = "<blue>",
    ["M"] = "<magenta>",
    ["C"] = "<cyan>",
    ["W"] = "<white>",
}

snd.utils.xtermToHex = {}

local function initXtermColors()
    local basic16 = {
        "000000", "800000", "008000", "808000", "000080", "800080", "008080", "c0c0c0",
        "808080", "ff0000", "00ff00", "ffff00", "0000ff", "ff00ff", "00ffff", "ffffff"
    }
    for i = 0, 15 do
        snd.utils.xtermToHex[i] = basic16[i + 1]
    end
    
    local levels = {0, 95, 135, 175, 215, 255}
    local i = 16
    for r = 1, 6 do
        for g = 1, 6 do
            for b = 1, 6 do
                snd.utils.xtermToHex[i] = string.format("%02x%02x%02x", 
                    levels[r], levels[g], levels[b])
                i = i + 1
            end
        end
    end
    
    for i = 232, 255 do
        local gray = 8 + (i - 232) * 10
        snd.utils.xtermToHex[i] = string.format("%02x%02x%02x", gray, gray, gray)
    end
end

initXtermColors()

function snd.utils.aardColorsToMudlet(str)
    if not str or str == "" then return "" end
    
    str = str:gsub("@@", "\001") -- temporary placeholder
    
    str = str:gsub("@x(%d%d?%d?)", function(num)
        local n = tonumber(num)
        if n and n >= 0 and n <= 255 then
            local hex = snd.utils.xtermToHex[n]
            if hex then
                return "<#" .. hex .. ">"
            end
        end
        return ""
    end)
    
    str = str:gsub("@([krgybmcwDRGYBMCW])", function(code)
        return snd.utils.aardColorMap[code] or ""
    end)
    
    str = str:gsub("@%-", "~")
    
    str = str:gsub("@[^@]", "")
    
    str = str:gsub("\001", "@")
    
    return str
end

function snd.utils.stripColors(str)
    if not str then return "" end

    str = tostring(str)
    str = str:gsub("\27%[[0-9;]*m", "")
    str = str:gsub("[%z\1-\8\11\12\14-\31]", "")
    str = str:gsub("@@", "\001")
    str = str:gsub("@%-", "~")
    str = str:gsub("@x%d?%d?%d?", "")
    str = str:gsub("@.", "")
    str = str:gsub("\001", "@")
    
    return str
end

function snd.utils.escapeRegex(str)
    if not str then return "" end
    return tostring(str):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

function snd.utils.aardEcho(str)
    cecho(snd.utils.aardColorsToMudlet(str))
end

function snd.utils.aardEchoLine(str)
    cecho(snd.utils.aardColorsToMudlet(str) .. "\n")
end

function snd.utils.fixsql(sql, likeOperator)
    if sql == nil then
        return "NULL"
    end
    
    sql = tostring(sql)
    sql = sql:gsub("'", "''")
    
    if likeOperator then
        if likeOperator == "left" then
            return "'%" .. sql .. "'"
        elseif likeOperator == "right" then
            return "'" .. sql .. "%'"
        else
            return "'%" .. sql .. "%'"
        end
    else
        return "'" .. sql .. "'"
    end
end

function snd.utils.toPascalCase(str)
    if not str then return "" end
    return str:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

function snd.utils.capitalize(str)
    if not str or str == "" then return "" end
    return str:sub(1, 1):upper() .. str:sub(2):lower()
end

function snd.utils.strjoin(delimiter, list)
    if not list or #list == 0 then return "" end
    return table.concat(list, delimiter)
end

function snd.utils.wrap(line, length)
    local lines = {}
    length = length or 80
    
    while #line > length do
        local col = line:sub(1, length):find("[%s,][^%s,]*$")
        if col and col > 2 then
        else
            col = length
        end
        
        table.insert(lines, line:sub(1, col))
        line = line:sub(col + 1)
    end
    
    table.insert(lines, line)
    return lines
end

function snd.utils.trimr(str)
    if not str then return "" end
    return str:find("^%s*$") and "" or str:match("^(.*%S)")
end

function snd.utils.trim(str)
    if not str then return "" end
    return str:match("^%s*(.-)%s*$")
end

function snd.utils.readableNumber(num, places)
    if not num then return "0" end
    
    local fmt = "%." .. (places or 0) .. "f"
    
    if num >= 1000000000000 then
        return string.format(fmt .. " T", num / 1000000000000)
    elseif num >= 1000000000 then
        return string.format(fmt .. " B", num / 1000000000)
    elseif num >= 1000000 then
        return string.format(fmt .. " M", num / 1000000)
    elseif num >= 1000 then
        return string.format(fmt .. " K", num / 1000)
    else
        return tostring(num)
    end
end

function snd.utils.formatSeconds(seconds)
    if not tonumber(seconds) then return tostring(seconds) end
    
    seconds = tonumber(seconds)
    
    if seconds < 1 then
        return string.format("%.2fs", seconds)
    end
    
    local hours = math.floor(seconds / 3600)
    seconds = seconds % 3600
    local mins = math.floor(seconds / 60)
    seconds = math.floor(seconds % 60)
    
    local duration = ""
    
    if hours > 0 then
        duration = hours .. "h "
    end
    if mins > 0 then
        duration = duration .. mins .. "m "
    end
    if seconds > 0 or duration == "" then
        duration = duration .. seconds .. "s"
    end
    
    return snd.utils.trim(duration)
end

function snd.utils.formatDuration(duration)
    if type(duration) == "number" then
        return snd.utils.formatSeconds(duration)
    elseif type(duration) == "table" then
        local parts = {}
        if duration.h and duration.h > 0 then
            table.insert(parts, duration.h .. "h")
        end
        if duration.m and duration.m > 0 then
            table.insert(parts, duration.m .. "m")
        end
        if duration.s and duration.s > 0 then
            table.insert(parts, duration.s .. "s")
        end
        return table.concat(parts, " ")
    end
    return ""
end

function snd.utils.getActualLevel(level, remorts, tier, redos)
    if not level then return -1 end
    
    tier = tier or 0
    remorts = remorts or 1
    redos = redos or 0
    
    if redos == 0 then
        return (tier * 7 * 201) + ((remorts - 1) * 201) + level
    else
        return (tier * 7 * 201) + (redos * 7 * 201) + ((remorts - 1) * 201) + level
    end
end

function snd.utils.convertLevel(actualLevel)
    if not actualLevel or actualLevel < 1 then
        return {tier = -1, redos = -1, remort = -1, level = -1}
    end
    
    actualLevel = tonumber(actualLevel)
    
    local tier = math.floor(actualLevel / (7 * 201))
    if actualLevel % (7 * 201) == 0 then
        tier = tier - 1
    end
    
    local remort = math.floor((actualLevel - (tier * 7 * 201)) / 202) + 1
    
    local level = actualLevel % 201
    if level == 0 then
        level = 201
    end
    
    local redos = 0
    if tier > 9 then
        redos = tier - 9
        tier = 9
    end
    
    return {tier = tier, redos = redos, remort = remort, level = level}
end

function snd.utils.findKeyword(item)
    if not item then return "" end
    
    local badwords = {
        ["a"] = true, ["an"] = true, ["the"] = true, ["of"] = true,
        ["some"] = true, ["and"] = true, ["or"] = true
    }
    
    for word in item:gmatch("%S+") do
        word = word:gsub("[,]", "")
        local pre, post = word:match("^(.-)%'(.+)$")
        if pre and post then word = #pre <= 1 and (pre .. post) or pre end
        if word ~= "" and not badwords[word:lower()] then
            return word:lower()
        end
    end
    
    return item:lower()
end

-- Identity normalization intentionally retains articles and punctuation.
function snd.utils.normalizeMobIdentity(name, maxLen)
    local text = snd.utils.stripColors(tostring(name or ""))
    if maxLen then
        text = text:sub(1, maxLen)
    end
    text = text:lower()
    text = text:gsub("%s+", " ")
    return snd.utils.trim(text)
end

function snd.utils.mobIdentityMatches(a, b, maxLen)
    local left = snd.utils.normalizeMobIdentity(a, maxLen)
    local right = snd.utils.normalizeMobIdentity(b, maxLen)
    return left ~= "" and right ~= "" and left == right
end

local commandSelectorOmitWords = {
    ["a"] = true,
    ["an"] = true,
    ["and"] = true,
    ["at"] = true,
    ["by"] = true,
    ["for"] = true,
    ["from"] = true,
    ["in"] = true,
    ["of"] = true,
    ["on"] = true,
    ["or"] = true,
    ["some"] = true,
    ["the"] = true,
    ["to"] = true,
    ["with"] = true,
}

local commandSelectorRelationWords = {
    ["around"] = true,
    ["at"] = true,
    ["beside"] = true,
    ["by"] = true,
    ["for"] = true,
    ["from"] = true,
    ["in"] = true,
    ["inside"] = true,
    ["near"] = true,
    ["of"] = true,
    ["on"] = true,
    ["outside"] = true,
    ["to"] = true,
    ["under"] = true,
    ["with"] = true,
}

-- Never emit a bare movement direction such as "kill up"; multi-word selectors
-- ending in a direction remain valid.
local reservedMobCommandSelectors = {
    ["n"] = true,
    ["north"] = true,
    ["ne"] = true,
    ["northeast"] = true,
    ["e"] = true,
    ["east"] = true,
    ["se"] = true,
    ["southeast"] = true,
    ["s"] = true,
    ["south"] = true,
    ["sw"] = true,
    ["southwest"] = true,
    ["w"] = true,
    ["west"] = true,
    ["nw"] = true,
    ["northwest"] = true,
    ["u"] = true,
    ["up"] = true,
    ["d"] = true,
    ["down"] = true,
}

function snd.utils.isReservedMobCommandSelector(selector)
    local normalized = snd.utils.trim(tostring(selector or "")):lower()
    return reservedMobCommandSelectors[normalized] == true
end

local function rawMobCommandWords(name)
    local text = snd.utils.stripColors(tostring(name or "")):lower()
    text = text:gsub("[^%w']+", " ")

    local words = {}
    for word in text:gmatch("%S+") do
        -- Only remove suffix "'s"; global removal corrupts names such as 'Sorr.
        word = word:gsub("'s$", "")
        word = word:gsub("^'+", ""):gsub("'+$", "")
        if word ~= "" then
            table.insert(words, word)
        end
    end
    return words
end

-- This is only for temporary MUD commands, never for storage or DB lookup.
function snd.utils.mobCommandWords(name)
    local words = {}
    for _, word in ipairs(rawMobCommandWords(name)) do
        local commandWord = word:gsub("'", "")
        if commandWord ~= "" and not commandSelectorOmitWords[commandWord] then
            table.insert(words, commandWord)
        end
    end
    return words
end

local function mobCommandHeadWords(name)
    local head = {}
    local brokeOnRelation = false

    for _, word in ipairs(rawMobCommandWords(name)) do
        if commandSelectorRelationWords[word] and #head > 0 then
            brokeOnRelation = true
            break
        end
        if word ~= "" and not commandSelectorOmitWords[word] then
            table.insert(head, word)
        end
    end

    if not brokeOnRelation then
        return {}
    end
    return head
end

-- Preserve two-word subjects; pair an -ing action only with a single-word subject.
local function mobCommandSubjectSelectors(name)
    local subjectWords = {}
    local cleanSubjectWords = {}
    local actionWord = nil

    for _, word in ipairs(rawMobCommandWords(name)) do
        if commandSelectorRelationWords[word] and #subjectWords > 0 then
            break
        end
        if word ~= "" and not commandSelectorOmitWords[word] then
            if #subjectWords > 0 and #word > 4 and word:match("ing$") then
                actionWord = word
                break
            end
            table.insert(subjectWords, word)
            -- Aardwolf may reject interior apostrophes (Dra'ork -> draork), so
            -- prefer a clean descriptor/head pair when available.
            if not word:find("'", 1, true) then
                table.insert(cleanSubjectWords, word)
            end
        end
    end

    local selectors = {}
    if #cleanSubjectWords >= 2 then
        table.insert(selectors, cleanSubjectWords[#cleanSubjectWords - 1] .. " " .. cleanSubjectWords[#cleanSubjectWords])
        if actionWord then
            table.insert(selectors, cleanSubjectWords[#cleanSubjectWords] .. " " .. actionWord)
        end
    elseif #cleanSubjectWords == 1 and actionWord then
        table.insert(selectors, cleanSubjectWords[1] .. " " .. actionWord)
    end
    return selectors
end

local function appendUnique(list, seen, value)
    local text = snd.utils.trim(tostring(value or ""):gsub("%s+", " "))
    text = text:gsub("'", "")
    if text == "" then return end
    local key = text:lower()
    if snd.utils.isReservedMobCommandSelector(key) then return end
    if seen[key] then return end
    seen[key] = true
    table.insert(list, text)
end

local function appendKillWordCandidates(candidates, seen, words)
    if not words or #words == 0 then return end
    appendUnique(candidates, seen, words[#words])
    for i = #words - 1, 1, -1 do
        appendUnique(candidates, seen, words[i])
    end
    for len = 2, #words do
        local start = #words - len + 1
        local chunk = {}
        for i = start, #words do
            table.insert(chunk, words[i])
        end
        appendUnique(candidates, seen, table.concat(chunk, " "))
    end
end

-- Subtract an ambiguous selector from the activity target, then keep its noun
-- anchor: "bonded student" + "junior" becomes "junior student".
local function appendDiscriminatorAnchorCandidates(candidates, seen, words, baselineSelector)
    if not words or #words < 2 then return end

    local baselineWords = snd.utils.mobCommandWords(baselineSelector)
    if #baselineWords == 0 then return end

    local remainingCounts = {}
    for _, word in ipairs(baselineWords) do
        remainingCounts[word] = (remainingCounts[word] or 0) + 1
    end

    local discriminatorWords = {}
    for _, word in ipairs(words) do
        local count = remainingCounts[word] or 0
        if count > 0 then
            remainingCounts[word] = count - 1
        else
            table.insert(discriminatorWords, word)
        end
    end

    local anchor = baselineWords[#baselineWords]
    for i = #discriminatorWords, 1, -1 do
        appendUnique(candidates, seen, discriminatorWords[i] .. " " .. anchor)
    end
end

local function appendRelationAnchoredCandidates(candidates, seen, headWords, allWords)
    if not headWords or #headWords == 0 then return end
    local anchor = headWords[#headWords]
    for i = #headWords + 1, #allWords do
        appendUnique(candidates, seen, anchor .. " " .. allWords[i])
    end
    if #allWords > #headWords + 1 then
        local anchoredPhrase = {anchor}
        for i = #headWords + 1, #allWords do
            table.insert(anchoredPhrase, allWords[i])
        end
        appendUnique(candidates, seen, table.concat(anchoredPhrase, " "))
    end
end

function snd.utils.mobSelectorMatchesName(selector, name)
    local selectorWords = snd.utils.mobCommandWords(selector)
    if #selectorWords == 0 then return false end

    local nameWords = {}
    for _, word in ipairs(snd.utils.mobCommandWords(name)) do
        nameWords[word] = true
    end

    for _, word in ipairs(selectorWords) do
        if not nameWords[word] then
            return false
        end
    end
    return true
end

local function selectorUniquelyNamesTarget(selector, targetName, knownNames)
    if not knownNames or #knownNames == 0 then
        return true
    end

    local matches = 0
    local targetMatched = false
    local seenIdentities = {}
    local targetIdentity = snd.utils.normalizeMobIdentity(targetName)
    for _, name in ipairs(knownNames) do
        if snd.utils.mobSelectorMatchesName(selector, name) then
            local identity = snd.utils.normalizeMobIdentity(name)
            if identity ~= "" and not seenIdentities[identity] then
                seenIdentities[identity] = true
                matches = matches + 1
            end
            if identity ~= "" and identity == targetIdentity then
                targetMatched = true
            end
        end
    end

    return matches == 1 and targetMatched
end

-- The returned value is not suitable for storage or DB lookup.
function snd.utils.buildMobCommandSelector(targetName, knownNames, options)
    local fullName = snd.utils.trim(targetName or "")
    if fullName == "" then
        return "", "empty"
    end

    local opts = options or {}
    local mode = tostring(opts.mode or "kill"):lower()
    local words = snd.utils.mobCommandWords(fullName)
    local candidates = {}
    local seen = {}
    local guessedKeyword = nil
    local killRelationHead = {}

    if snd.gmcp and snd.gmcp.guessMobKeyword then
        local ok, guessed = pcall(snd.gmcp.guessMobKeyword, fullName, opts.areaKey)
        if ok then
            guessedKeyword = guessed
        end
    end

    if fullName:find(",", 1, true) then
        appendUnique(candidates, seen, guessedKeyword)
        local commaLead = snd.utils.trim(fullName:match("^%s*([^,]+)") or "")
        local leadWords = snd.utils.mobCommandWords(commaLead)
        if #leadWords > 0 then
            appendUnique(candidates, seen, table.concat(leadWords, " "))
            appendUnique(candidates, seen, leadWords[1])
        end
    end

    if #words > 0 then
        if mode == "where" then
            appendUnique(candidates, seen, guessedKeyword)
            appendUnique(candidates, seen, words[#words])
            for len = 2, #words do
                local start = #words - len + 1
                local chunk = {}
                for i = start, #words do
                    table.insert(chunk, words[i])
                end
                appendUnique(candidates, seen, table.concat(chunk, " "))
            end
        else
            for _, selector in ipairs(mobCommandSubjectSelectors(fullName)) do
                appendUnique(candidates, seen, selector)
            end
            killRelationHead = mobCommandHeadWords(fullName)
            if #killRelationHead == 0 then
                appendDiscriminatorAnchorCandidates(
                    candidates,
                    seen,
                    words,
                    opts.preferredSelector or guessedKeyword
                )
            end
            appendKillWordCandidates(candidates, seen, killRelationHead)
            if #killRelationHead > 0 then
                -- After a relation establishes the subject, never fall back to
                -- an object-only selector such as "fishing pole".
                appendRelationAnchoredCandidates(candidates, seen, killRelationHead, words)
            else
                appendKillWordCandidates(candidates, seen, words)
            end
        end
    end

    -- Skip the final-word guess when it would cross a relation boundary.
    if mode ~= "kill" or #killRelationHead == 0 then
        appendUnique(candidates, seen, guessedKeyword)
    end
    appendUnique(candidates, seen, snd.utils.findKeyword(fullName))
    appendUnique(candidates, seen, fullName:lower())

    if mode == "kill" and knownNames and #knownNames > 0 then
        for _, candidate in ipairs(candidates) do
            if selectorUniquelyNamesTarget(candidate, fullName, knownNames) then
                return candidate, "unique"
            end
        end
    end

    return candidates[1] or "", "fallback"
end

local validMobTargetModes = {
    auto = true,
    skill = true,
    cast = true,
    raw = true,
}

-- "pro" is retained as an alias for the older Consider-window terminology.
function snd.utils.normalizeMobTargetMode(mode)
    local normalized = snd.utils.trim(tostring(mode or "")):lower()
    if normalized == "pro" then normalized = "raw" end
    if validMobTargetModes[normalized] then return normalized end
    return nil
end

-- Cast numbers go inside quotes; skill numbers go outside. Cast aliases must
-- select cast mode because their expansion is not visible here.
function snd.utils.resolveMobTargetMode(command, requestedMode)
    local mode = snd.utils.normalizeMobTargetMode(requestedMode) or "auto"
    if mode ~= "auto" then return mode end

    local verb = snd.utils.trim(tostring(command or "")):lower():match("^(%S+)") or ""
    if verb == "cast" or verb == "c" then
        return "cast"
    end
    return "skill"
end

local function unwrapMobTargetQuotes(value)
    local text = snd.utils.trim(tostring(value or ""))
    local quote = text:sub(1, 1)
    if #text >= 2 and (quote == "'" or quote == '"') and text:sub(-1) == quote then
        return snd.utils.trim(text:sub(2, -2))
    end
    return text
end

-- Accept raw, skill, and cast forms: 2.strong guard, 2.'strong guard', '2.strong guard'.
function snd.utils.parseMobCommandTarget(target)
    local text = unwrapMobTargetQuotes(target)
    local indexText, keyword = text:match("^(%d+)%.(.+)$")
    if indexText then
        keyword = unwrapMobTargetQuotes(keyword)
    else
        keyword = text
    end
    keyword = snd.utils.trim(tostring(keyword or ""):gsub("%s+", " "))
    return keyword, indexText and tonumber(indexText) or nil
end

-- Multi-word selectors use the server's distinct skill/cast quoting rules.
function snd.utils.formatMobCommandTarget(selector, requestedMode, command)
    local rawSelector = snd.utils.trim(tostring(selector or ""))
    if rawSelector == "" then return "", snd.utils.resolveMobTargetMode(command, requestedMode) end

    local resolvedMode = snd.utils.resolveMobTargetMode(command, requestedMode)
    if resolvedMode == "raw" then
        return rawSelector, resolvedMode
    end

    local keyword, index = snd.utils.parseMobCommandTarget(rawSelector)
    if keyword == "" then return "", resolvedMode end

    local indexedSelector = index and (tostring(index) .. "." .. keyword) or keyword
    if not keyword:find("%s") then
        return indexedSelector, resolvedMode
    end

    if resolvedMode == "cast" then
        return "'" .. indexedSelector .. "'", resolvedMode
    end
    if index then
        return tostring(index) .. ".'" .. keyword .. "'", resolvedMode
    end
    return "'" .. keyword .. "'", resolvedMode
end

function snd.utils.buildMobTargetCommand(command, selector, requestedMode)
    local base = snd.utils.trim(tostring(command or ""))
    if base == "" then return "", snd.utils.resolveMobTargetMode(base, requestedMode) end
    local target, resolvedMode = snd.utils.formatMobCommandTarget(selector, requestedMode, base)
    if target == "" then return "", resolvedMode end
    return base .. " " .. target, resolvedMode
end

function snd.utils.ifc(condition, trueVal, falseVal)
    if condition then
        return trueVal
    else
        return falseVal
    end
end

snd.utils.NOTE_COLORS = {
    INFO = "#FF5000",
    INFO_HIGHLIGHT = "#00B4E0",
    IMPORTANT = "#FFFFFF",
    IMPORTANT_HIGHLIGHT = "#00FF00",
    IMPORTANT_BACKGROUND = "#000080",
    ERROR = "#FFFFFF",
    ERROR_HIGHLIGHT = "#FFE32E",
    ERROR_BACKGROUND = "#650101",
    DEBUG = "#87CEFA",
    DEBUG_HIGHLIGHT = "#FFD700",
}

function snd.utils.infoNote(...)
    if snd and snd.config and snd.config.silentMode then
        return
    end
    local args = {...}
    local msg = table.concat(args, "")
    cecho("\n<orange>[S&D]<reset> <cyan>" .. msg .. "<reset>\n")
end

function snd.utils.errorNote(...)
    local args = {...}
    local msg = table.concat(args, "")
    cecho("<red>[S&D ERROR]<reset> <yellow>" .. msg .. "<reset>\n")
end

function snd.utils.debugNote(...)
    if snd.config and snd.config.debugMode then
        local args = {...}
        local msg = table.concat(args, "")
        cecho("<dim_gray>[S&D DEBUG]<reset> <gray>" .. msg .. "<reset>\n")
    end
end

function snd.utils.qwDebugNote(...)
    if snd.config and snd.config.debugMode then
        local args = {...}
        local msg = table.concat(args, "")
        cecho("\n<orange>[S&D]<reset> <cyan>" .. msg .. "<reset>\n")
    end
end

function snd.utils.getReportTypeStyle(eventType)
    local t = tostring(eventType or "general"):lower()
    local map = {
        quest = {label = "QUEST", cecho = "red"},
        campaign = {label = "CAMPAIGN", cecho = "green"},
        gquest = {label = "GQUEST", cecho = "dodger_blue"},
        gold = {label = "GOLD", cecho = "yellow"},
        history = {label = "HISTORY", cecho = "magenta"},
        general = {label = "SND", cecho = "cyan"},
    }
    return map[t] or map.general
end

function snd.utils.getReportAardColor(eventType)
    local t = tostring(eventType or "general"):lower()
    -- Use bright Aard @ codes because reports are stored with color codes; Mudlet tags may not survive.
    local map = {
        quest = "@R",
        campaign = "@G",
        gquest = "@C",
        gold = "@Y",
        history = "@M",
        general = "@W",
    }
    return map[t] or map.general
end

function snd.utils.isDefaultReportChannel(channel)
    channel = snd.utils.trim(channel or ""):lower()
    return channel == "" or channel == "default" or channel == "echo"
end

function snd.utils.copyReportText(payload)
    local text = snd.utils.trim(tostring(payload or ""))
    if text == "" then
        return false
    end
    if type(setClipboardText) ~= "function" then
        snd.utils.errorNote("Copying reports requires Mudlet 4.10 or newer.")
        return false
    end

    local ok, err = pcall(setClipboardText, text)
    if not ok then
        snd.utils.errorNote("Could not copy report to clipboard: " .. tostring(err))
        return false
    end

    snd.utils.infoNote("Report copied to clipboard.")
    return true
end


-- Non-MUD channels are treated as local aliases/macros and sent via expandAlias.
function snd.utils.isMudReportChannel(channel)
    local raw = snd.utils.trim(channel or "")
    if raw == "" then return false end

    local cmd = raw:match("^(%S+)") or ""
    cmd = cmd:lower()

    local mudChannels = {
        say = true,
        tell = true,
        reply = true,
        gtell = true,
        group = true,
        clan = true,
        ct = true,
        gt = true,
        auction = true,
        newbie = true,
        notify = true,
        gossip = true,
        chat = true,
        atalk = true,
        ytell = true,
        yell = true,
        shout = true,
    }

    return mudChannels[cmd] == true
end

-- Mud channels go directly to game; virtual/custom channels go through expandAlias.
function snd.utils.dispatchReportChannel(channel, payload)
    channel = snd.utils.trim(channel or "")
    payload = snd.utils.trim(payload or "")
    if channel == "" or payload == "" then
        return false
    end

    local cmd = channel .. " " .. payload

    if not snd.utils.isMudReportChannel(channel) and type(expandAlias) == "function" then
        return pcall(expandAlias, cmd, false)
    end

    if snd.commands and snd.commands.sendGameCommand then
        return snd.commands.sendGameCommand(cmd, false)
    end

    if type(send) == "function" then
        local ok = pcall(send, cmd, false)
        return ok
    end

    return false
end

function snd.utils.reportLine(text, eventType, channelOverride)
    text = snd.utils.trim(text or "")
    if text == "" then
        return false
    end

    local style = snd.utils.getReportTypeStyle(eventType)
    local channel = channelOverride and snd.utils.trim(tostring(channelOverride)) or "default"
    if not channelOverride and snd.config and snd.config.reportChannel then
        channel = snd.utils.trim(snd.config.reportChannel)
    end

    if snd.utils.isDefaultReportChannel(channel) then
        cecho(string.format("\n<orange>[S&D]<reset> <%s>%s<reset>\n", style.cecho, text))
        return true
    end

    local payload = string.format("%s[%s]@W %s", snd.utils.getReportAardColor(eventType), style.label, text)
    return snd.utils.dispatchReportChannel(channel, payload)
end

function snd.utils.formatQuestCompletionDuration(seconds)
    local totalSeconds = tonumber(seconds)
    if not totalSeconds then
        return ""
    end

    totalSeconds = math.max(0, math.floor(totalSeconds))
    local hours = math.floor(totalSeconds / 3600)
    local mins = math.floor((totalSeconds % 3600) / 60)
    local secs = totalSeconds % 60

    if hours > 0 then
        return string.format("%dh %dm %ds", hours, mins, secs)
    end

    return string.format("%dm %ds", mins, secs)
end

function snd.utils.reportQuestCompletion(qp, gold, durationSeconds, tp, trains, pracs)
    qp = tonumber(qp) or 0
    gold = tonumber(gold) or 0
    tp = tonumber(tp) or 0
    trains = tonumber(trains) or 0
    pracs = tonumber(pracs) or 0
    local durationText = snd.utils.formatQuestCompletionDuration(durationSeconds)

    local channel = "default"
    if snd.config and snd.config.reportChannel then
        channel = snd.utils.trim(snd.config.reportChannel)
    end

    if snd.utils.isDefaultReportChannel(channel) then
        local parts = {
            string.format("<red>QP: %d<reset>", qp),
            string.format("<yellow>Gold: %d<reset>", gold),
        }
        if tp > 0 then table.insert(parts, string.format("<white>TP: %d<reset>", tp)) end
        if trains > 0 then table.insert(parts, string.format("<cyan>Trains: %d<reset>", trains)) end
        if pracs > 0 then table.insert(parts, string.format("<green>Pracs: %d<reset>", pracs)) end
        if durationText ~= "" then table.insert(parts, string.format("<cyan>Duration: %s<reset>", durationText)) end
        cecho(string.format(
            "<orange>[S&D]<reset> <magenta>Quest complete!<reset> %s\n",
            table.concat(parts, ", ")
        ))
        return true
    end

    local channelParts = {
        string.format("@RQP: %d@W", qp),
        string.format("@YGold: %d@W", gold),
    }
    if tp > 0 then table.insert(channelParts, string.format("@WTP: %d@W", tp)) end
    if trains > 0 then table.insert(channelParts, string.format("@CTrains: %d@W", trains)) end
    if pracs > 0 then table.insert(channelParts, string.format("@GPracs: %d@W", pracs)) end
    if durationText ~= "" then table.insert(channelParts, string.format("@CDuration: %s@W", durationText)) end
    local payload = string.format("@MQuest complete!@W %s", table.concat(channelParts, ", "))
    return snd.utils.dispatchReportChannel(channel, payload)
end

function snd.utils.reportCampaignCompletion(rewards, durationSeconds)
    rewards = rewards or {}
    local qp = tonumber(rewards.qp) or 0
    local dailyQpBonus = tonumber(rewards.dailyQpBonus) or 0
    local baseQp = tonumber(rewards.baseQp) or 0
    if dailyQpBonus > 0 and baseQp <= 0 then
        baseQp = math.max(qp - dailyQpBonus, 0)
    end
    local gold = tonumber(rewards.gold) or 0
    local tp = tonumber(rewards.tp) or 0
    local trains = tonumber(rewards.trains) or 0
    local pracs = tonumber(rewards.pracs) or 0
    local durationText = snd.utils.formatQuestCompletionDuration(durationSeconds)

    local channel = "default"
    if snd.config and snd.config.reportChannel then
        channel = snd.utils.trim(snd.config.reportChannel)
    end

    local qpText = dailyQpBonus > 0
        and string.format("%dqp + %ddaily", baseQp, dailyQpBonus)
        or tostring(qp)

    if snd.utils.isDefaultReportChannel(channel) then
        local parts = {
            string.format("<red>QP: %s<reset>", qpText),
            string.format("<yellow>Gold: %d<reset>", gold),
        }
        if tp > 0 then table.insert(parts, string.format("<white>TP: %d<reset>", tp)) end
        if trains > 0 then table.insert(parts, string.format("<cyan>Trains: %d<reset>", trains)) end
        if pracs > 0 then table.insert(parts, string.format("<green>Pracs: %d<reset>", pracs)) end
        if durationText ~= "" then table.insert(parts, string.format("<cyan>Duration: %s<reset>", durationText)) end
        cecho(string.format(
            "\n<orange>[S&D]<reset> <green>Campaign complete!<reset> %s\n",
            table.concat(parts, ", ")
        ))
        return true
    end

    local channelQpText = dailyQpBonus > 0
        and string.format("%dqp + %ddaily", baseQp, dailyQpBonus)
        or tostring(qp)

    local channelParts = {
        string.format("@RQP: %s@W", channelQpText),
        string.format("@YGold: %d@W", gold),
    }
    if tp > 0 then table.insert(channelParts, string.format("@WTP: %d@W", tp)) end
    if trains > 0 then table.insert(channelParts, string.format("@CTrains: %d@W", trains)) end
    if pracs > 0 then table.insert(channelParts, string.format("@GPracs: %d@W", pracs)) end
    if durationText ~= "" then table.insert(channelParts, string.format("@CDuration: %s@W", durationText)) end
    local payload = string.format("@GCampaign complete!@W %s", table.concat(channelParts, ", "))

    -- Custom channel aliases can echo immediately while the campaign-complete
    -- server line is still open, so finish that line before expanding the alias.
    if not snd.utils.isMudReportChannel(channel) then
        cecho("\n")
    end

    return snd.utils.dispatchReportChannel(channel, payload)
end

function snd.utils.deepcopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in next, orig, nil do
            copy[snd.utils.deepcopy(k)] = snd.utils.deepcopy(v)
        end
        setmetatable(copy, snd.utils.deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function snd.utils.tableContains(tbl, val)
    if not tbl then return false end
    for _, v in pairs(tbl) do
        if v == val then return true end
    end
    return false
end

function snd.utils.tableLength(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end
