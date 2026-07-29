--[[
    Search and Destroy - Utility Functions
    Mudlet Port
    
    Original MUSHclient plugin by Crowley
    Ported to Mudlet
    
    This module contains utility functions for:
    - Aardwolf color code conversion
    - String manipulation
    - SQL helpers
    - Time formatting
    - Level calculations
]]

snd = snd or {}
snd.utils = snd.utils or {}

-------------------------------------------------------------------------------
-- Aardwolf Color Code Conversion
-------------------------------------------------------------------------------

-- Aardwolf uses @ codes: @R = bold red, @g = green, @x123 = xterm color
-- Mudlet uses cecho format: <red>, <green>, or decho/hecho

-- Map Aardwolf color codes to Mudlet cecho color names
snd.utils.aardColorMap = {
    -- Normal colors (lowercase)
    ["k"] = "<black>",
    ["r"] = "<maroon>",
    ["g"] = "<green>",
    ["y"] = "<ansi_yellow>",
    ["b"] = "<navy>",
    ["m"] = "<purple>",
    ["c"] = "<turquoise>",
    ["w"] = "<light_gray>",
    -- Bold colors (uppercase)
    ["D"] = "<gray>",
    ["R"] = "<red>",
    ["G"] = "<ansi_light_green>",
    ["Y"] = "<yellow>",
    ["B"] = "<blue>",
    ["M"] = "<magenta>",
    ["C"] = "<cyan>",
    ["W"] = "<white>",
}

-- Convert xterm 256 color number to hex for Mudlet
-- This is a simplified version - full xterm palette
snd.utils.xtermToHex = {}

-- Initialize xterm color table (standard 256 color palette)
local function initXtermColors()
    -- Colors 0-15: Standard colors (handled by aardColorMap mostly)
    local basic16 = {
        "000000", "800000", "008000", "808000", "000080", "800080", "008080", "c0c0c0",
        "808080", "ff0000", "00ff00", "ffff00", "0000ff", "ff00ff", "00ffff", "ffffff"
    }
    for i = 0, 15 do
        snd.utils.xtermToHex[i] = basic16[i + 1]
    end
    
    -- Colors 16-231: 6x6x6 color cube
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
    
    -- Colors 232-255: Grayscale
    for i = 232, 255 do
        local gray = 8 + (i - 232) * 10
        snd.utils.xtermToHex[i] = string.format("%02x%02x%02x", gray, gray, gray)
    end
end

initXtermColors()

--- Convert Aardwolf @-color codes to Mudlet cecho format
-- @param str String with Aardwolf color codes
-- @return String with Mudlet cecho color codes
function snd.utils.aardColorsToMudlet(str)
    if not str or str == "" then return "" end
    
    -- Handle @@ (literal @)
    str = str:gsub("@@", "\001") -- temporary placeholder
    
    -- Handle xterm colors @x000-@x255
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
    
    -- Handle standard color codes
    str = str:gsub("@([krgybmcwDRGYBMCW])", function(code)
        return snd.utils.aardColorMap[code] or ""
    end)
    
    -- Handle @- (tilde, historical)
    str = str:gsub("@%-", "~")
    
    -- Remove any remaining invalid @ codes
    str = str:gsub("@[^@]", "")
    
    -- Restore literal @
    str = str:gsub("\001", "@")
    
    return str
end

--- Strip all Aardwolf color codes from a string
-- @param str String with color codes
-- @return Plain string without color codes
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

--- Escape a string for use in regex patterns
-- @param str String to escape
-- @return Escaped string safe for regex
function snd.utils.escapeRegex(str)
    if not str then return "" end
    return tostring(str):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

--- Echo text with Aardwolf color codes to Mudlet
-- @param str String with Aardwolf @ color codes
function snd.utils.aardEcho(str)
    cecho(snd.utils.aardColorsToMudlet(str))
end

--- Echo text with Aardwolf color codes + newline
-- @param str String with Aardwolf @ color codes
function snd.utils.aardEchoLine(str)
    cecho(snd.utils.aardColorsToMudlet(str) .. "\n")
end

-------------------------------------------------------------------------------
-- SQL Helpers
-------------------------------------------------------------------------------

--- Escape a string for SQL queries (handles single quotes)
-- @param sql String to escape
-- @param likeOperator Optional: "left", "right", or "both" for LIKE wildcards
-- @return Escaped and quoted string
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

-------------------------------------------------------------------------------
-- String Utilities
-------------------------------------------------------------------------------

--- Convert string to Pascal Case (capitalize each word)
-- @param str Input string
-- @return Pascal cased string
function snd.utils.toPascalCase(str)
    if not str then return "" end
    return str:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

--- Capitalize first letter of string
-- @param str Input string
-- @return Capitalized string
function snd.utils.capitalize(str)
    if not str or str == "" then return "" end
    return str:sub(1, 1):upper() .. str:sub(2):lower()
end

--- Join table elements with delimiter
-- @param delimiter String to join with
-- @param list Table of strings
-- @return Joined string
function snd.utils.strjoin(delimiter, list)
    if not list or #list == 0 then return "" end
    return table.concat(list, delimiter)
end

--- Wrap text to specified width
-- @param line String to wrap
-- @param length Maximum line length (default 80)
-- @return Table of wrapped lines
function snd.utils.wrap(line, length)
    local lines = {}
    length = length or 80
    
    while #line > length do
        local col = line:sub(1, length):find("[%s,][^%s,]*$")
        if col and col > 2 then
            -- Found a good break point
        else
            col = length
        end
        
        table.insert(lines, line:sub(1, col))
        line = line:sub(col + 1)
    end
    
    table.insert(lines, line)
    return lines
end

--- Trim whitespace from right side of string
-- @param str Input string
-- @return Trimmed string
function snd.utils.trimr(str)
    if not str then return "" end
    return str:find("^%s*$") and "" or str:match("^(.*%S)")
end

--- Trim whitespace from both sides of string
-- @param str Input string
-- @return Trimmed string
function snd.utils.trim(str)
    if not str then return "" end
    return str:match("^%s*(.-)%s*$")
end

--- Format a number into readable format (K, M, B, T)
-- @param num Number to format
-- @param places Decimal places (default 0)
-- @return Formatted string
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

-------------------------------------------------------------------------------
-- Time Formatting
-------------------------------------------------------------------------------

--- Format seconds into human readable duration
-- @param seconds Number of seconds
-- @return Formatted string (e.g., "1h 23m 45s")
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

--- Format a duration table or seconds for display
-- @param duration Either seconds or table with h, m, s keys
-- @return Formatted string
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

-------------------------------------------------------------------------------
-- Level Calculations (Aardwolf-specific)
-------------------------------------------------------------------------------

--- Calculate actual total level from tier/remort/level
-- @param level Current level (1-201)
-- @param remorts Number of remorts (1-7)
-- @param tier Current tier (0-9)
-- @param redos Number of redo tiers (0+)
-- @return Actual total level
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

--- Convert actual level back to tier/remort/level components
-- @param actualLevel Total actual level
-- @return Table with tier, redos, remort, level keys
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

-------------------------------------------------------------------------------
-- Mob Keyword Guessing
-------------------------------------------------------------------------------

--- Find a keyword for an item/mob name (skip articles)
-- @param item Full name of item/mob
-- @return Best keyword to use
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

--- Normalize a mob name for identity comparison only.
-- This intentionally keeps articles and punctuation; it just removes colors,
-- collapses whitespace, and ignores case.
-- @param name Mob name
-- @param maxLen Optional maximum length, used for fixed-width where output
-- @return Normalized identity string
function snd.utils.normalizeMobIdentity(name, maxLen)
    local text = snd.utils.stripColors(tostring(name or ""))
    if maxLen then
        text = text:sub(1, maxLen)
    end
    text = text:lower()
    text = text:gsub("%s+", " ")
    return snd.utils.trim(text)
end

--- Compare two mob names as identities.
-- @param a First mob name
-- @param b Second mob name
-- @param maxLen Optional maximum length
-- @return True if both normalize to the same non-empty identity
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

local function rawMobCommandWords(name)
    local text = snd.utils.stripColors(tostring(name or "")):lower()
    text = text:gsub("'s", "")
    text = text:gsub("[^%w']+", " ")

    local words = {}
    for word in text:gmatch("%S+") do
        word = word:gsub("^'+", ""):gsub("'+$", "")
        if word ~= "" then
            table.insert(words, word)
        end
    end
    return words
end

--- Split a mob name into command-selector words.
-- This is only for temporary MUD commands, never for storage or DB lookup.
-- @param name Mob name
-- @return List of lowercase selector words
function snd.utils.mobCommandWords(name)
    local words = {}
    for _, word in ipairs(rawMobCommandWords(name)) do
        if word ~= "" and not commandSelectorOmitWords[word] then
            table.insert(words, word)
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

local function appendUnique(list, seen, value)
    local text = snd.utils.trim(tostring(value or ""):gsub("%s+", " "))
    if text == "" then return end
    local key = text:lower()
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

--- Check whether a command selector could name a mob.
-- @param selector Temporary command selector
-- @param name Full mob name
-- @return True if all selector words appear in the mob name
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

--- Build a temporary selector for MUD commands.
-- The returned value is not suitable for storage or DB lookup.
-- @param targetName Full target name
-- @param knownNames Optional list of visible/active full mob names
-- @param options Optional table: mode = "where" or "kill"
-- @return selector, reason
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
            appendKillWordCandidates(candidates, seen, mobCommandHeadWords(fullName))
            appendKillWordCandidates(candidates, seen, words)
        end
    end

    appendUnique(candidates, seen, guessedKeyword)
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

-------------------------------------------------------------------------------
-- Conditional Helper
-------------------------------------------------------------------------------

--- Inline conditional (ternary operator helper)
-- @param condition Boolean condition
-- @param trueVal Value if true
-- @param falseVal Value if false
-- @return trueVal or falseVal based on condition
function snd.utils.ifc(condition, trueVal, falseVal)
    if condition then
        return trueVal
    else
        return falseVal
    end
end

-------------------------------------------------------------------------------
-- Note/Echo Helpers (styled output)
-------------------------------------------------------------------------------

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

--- Output an info note
function snd.utils.infoNote(...)
    if snd and snd.config and snd.config.silentMode then
        return
    end
    local args = {...}
    local msg = table.concat(args, "")
    cecho("\n<orange>[S&D]<reset> <cyan>" .. msg .. "<reset>\n")
end

--- Output an error note
function snd.utils.errorNote(...)
    local args = {...}
    local msg = table.concat(args, "")
    cecho("<red>[S&D ERROR]<reset> <yellow>" .. msg .. "<reset>\n")
end

--- Output a debug note (only if debug mode is on)
function snd.utils.debugNote(...)
    if snd.config and snd.config.debugMode then
        local args = {...}
        local msg = table.concat(args, "")
        cecho("<dim_gray>[S&D DEBUG]<reset> <gray>" .. msg .. "<reset>\n")
    end
end

--- Output a quick-where debug note (only if debug mode is on)
function snd.utils.qwDebugNote(...)
    if snd.config and snd.config.debugMode then
        local args = {...}
        local msg = table.concat(args, "")
        cecho("\n<orange>[S&D]<reset> <cyan>" .. msg .. "<reset>\n")
    end
end

--- Build plain text label for history/event output by type
-- @param eventType quest|campaign|gquest|gold|history|general
-- @return prefix label and cecho color name
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

--- Convert a style type to Aard color code for outbound channel text
-- @param eventType quest|campaign|gquest|gold|history|general
-- @return Aard color code like @R
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

--- True when report channel should render as local echo output
-- @param channel string configured report channel
-- @return boolean
function snd.utils.isDefaultReportChannel(channel)
    channel = snd.utils.trim(channel or ""):lower()
    return channel == "" or channel == "default" or channel == "echo"
end


--- True when configured report channel is a direct MUD channel command.
-- Non-MUD channels are treated as local aliases/macros and sent via expandAlias.
-- @param channel string configured report channel command
-- @return boolean
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

--- Dispatch report payload through configured channel.
-- Mud channels go directly to game; virtual/custom channels go through expandAlias.
-- @param channel string configured report channel command
-- @param payload string report text payload
-- @return boolean true when dispatch function ran without error
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

--- Route a formatted report line to default echo or configured channel
-- @param text string Text to report
-- @param eventType string semantic type for color coding
-- @param channelOverride optional explicit report channel
-- @return true if delivered, false otherwise
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

--- Format quest duration for completion output as H/M/S with minutes included.
-- @param seconds number Duration in seconds
-- @return string Formatted duration (e.g., "0m 11s", "1h 3m 4s")
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

--- Report quest completion with segmented colors (matches history reward colors)
-- @param qp number Total QP reward
-- @param gold number Gold reward
-- @param durationSeconds number|nil Optional completion duration in seconds
-- @return true if delivered, false otherwise
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

--- Report campaign completion with rewards and duration from history.
-- @param rewards table|nil Reward table with qp, gold, tp, trains, pracs fields
-- @param durationSeconds number|nil Optional completion duration in seconds
-- @return true if delivered, false otherwise
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

-------------------------------------------------------------------------------
-- Table Utilities
-------------------------------------------------------------------------------

--- Deep copy a table
-- @param orig Original table
-- @return Copy of table
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

--- Check if table contains value
-- @param tbl Table to search
-- @param val Value to find
-- @return true if found, false otherwise
function snd.utils.tableContains(tbl, val)
    if not tbl then return false end
    for _, v in pairs(tbl) do
        if v == val then return true end
    end
    return false
end

--- Get table length (works for non-sequential tables)
-- @param tbl Table to count
-- @return Number of elements
function snd.utils.tableLength(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

-- Search and Destroy: Utilities module loaded silently
