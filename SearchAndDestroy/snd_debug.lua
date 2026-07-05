--[[
    Search and Destroy - Debug Module
    Mudlet Port

    Provides debug helpers and state tracking.
]]

snd = snd or {}
snd.debug = snd.debug or {
    enabled = false,
    lastSearch = nil,
}

local function normalizeEnabled(value)
    return value == true
end

function snd.debug.setEnabled(enabled)
    local normalized = normalizeEnabled(enabled)
    snd.debug.enabled = normalized
    if snd.config then
        snd.config.debugMode = normalized
    end
    return normalized
end

function snd.debug.toggle()
    local current = snd.config and snd.config.debugMode or snd.debug.enabled
    local nextValue = not current
    snd.debug.setEnabled(nextValue)
    if snd.utils and snd.utils.infoNote then
        snd.utils.infoNote("Debug mode: " .. (nextValue and "ON" or "OFF"))
    end
    return nextValue
end

function snd.debug.log(message)
    if snd.config and snd.config.debugMode then
        snd.utils.debugNote(message)
    end
end

function snd.debug.mobTag(message)
    if snd.config and (snd.config.mobTagDebug or snd.config.debugMode) then
        local text = "MOBTAG DEBUG: " .. tostring(message)
        if snd.config.debugMode and snd.utils and snd.utils.debugNote then
            snd.utils.debugNote(text)
        elseif type(cecho) == "function" then
            cecho("<dim_gray>[S&D DEBUG]<reset> <gray>" .. text .. "<reset>\n")
        elseif type(echo) == "function" then
            echo("[S&D DEBUG] " .. text .. "\n")
        end
    end
end

function snd.debug.recordSearch(context)
    if type(context) ~= "table" then
        return
    end
    snd.debug.lastSearch = context
end

-- Module loaded silently
