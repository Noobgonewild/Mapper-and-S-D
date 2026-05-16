--[[
    Search and Destroy - GUI Module
    Mudlet Port
    
    Original MUSHclient plugin by Crowley
    Ported to Mudlet by Gizmmo
    
    This module creates the visual target tracking window
    using Mudlet's Geyser framework, faithfully replicating
    the original plugin's miniwindow:
      - Draggable title bar with version and quest timer
      - Action buttons (xcp, go, kk, nx, qs, qw, ht, ref)
      - Circle status readout (cp level / gq / init / off)
      - Noexp readout
      - Clickable, color-coded target list (CP/GQ/Quest)
      - Resize handle
      - Minimize/maximize toggle
      - Right-click context menu
]]

snd = snd or {}
snd.gui = snd.gui or {}

-------------------------------------------------------------------------------
-- GUI Configuration & Color Theme
-- Colors ported directly from the original plugin's TEXT_COLOR_DETAILS
-------------------------------------------------------------------------------

snd.gui.styles = {
    -- Window chrome
    bgColor        = "#000000",      -- Window background (black, like original)
    titleBarBg     = "#0a0a0a",      -- Title bar background
    titleBarBorder = "#4a4a4a",      -- Title bar border
    windowBorder   = "#4a4a4a",      -- Window border
    innerBorder    = "#000000",      -- Inner border line
    titleText      = "#A0FFFF",      -- Title text (light cyan-yellow from original)

    -- Target text colors (from TEXT_COLOR_DETAILS in original)
    normal          = "#E0E0E0",     -- Normal mobs
    targeted        = "#FF4000",     -- Currently targeted mob
    dead            = "#484848",     -- Dead mobs
    unknown         = "#FF0000",     -- Mobs in unknown area
    unknownDead     = "#900000",     -- Dead mobs in unknown area
    unlikely        = "#484848",     -- Unlikely mobs
    unlikelyTag     = "#0000CD",     -- Tag beside unlikely mobs
    questAvailable  = "#1E90FF",     -- Quest available text
    questComplete   = "#7CFC00",     -- Quest complete text
    questWaiting    = "#FF7A7A",     -- Next quest timer
    alternatingRow  = "#000040",     -- Alternating row background
    express         = "#FF4000",     -- Express target tag

    -- Button colors
    btnBg           = "#000000",
    btnBorder1      = "#E0E0E0",     -- Light border (top/left)
    btnBorder2      = "#808080",     -- Dark border (bottom/right)
    btnText         = "#E0E0E0",
    btnPressedBorder1 = "#808080",   -- Inverted when pressed
    btnPressedBorder2 = "#E0E0E0",

    -- Circle readout colors
    circleGreen1    = "#00C030",
    circleGreen2    = "#004000",
    circleRed1      = "#F04000",
    circleRed2      = "#800000",
    circleBlue1     = "#0088C0",
    circleBlue2     = "#003040",
    circleViolet1   = "#C000C0",
    circleViolet2   = "#400040",
    circleText1     = "#A0FFFF",
    circleText2     = "#0C1830",

    -- Fonts
    titleFont       = "Consolas",
    titleFontSize   = 10,
    buttonFont      = "Consolas",
    buttonFontSize  = 9,
    listFont        = "Consolas",
    listFontSize    = 8,
    statusFont      = "Consolas",
    statusFontSize  = 9,
}

-------------------------------------------------------------------------------
-- GUI State
-------------------------------------------------------------------------------

snd.gui.elements = {}          -- All Geyser elements
snd.gui.targetLabels = {}      -- Dynamic per-target labels
snd.gui.initialized = false
snd.gui.minimized = false
snd.gui.windowState = "max"    -- "max" or "min"
snd.gui.tabOrder = {"quest", "gq", "cp"}
snd.gui.tabLabels = {quest = "Quest", gq = "GQ", cp = "Campaign"}
snd.gui.tabColors = {quest = "#9F2A2A", gq = "#2478c8", cp = "#2E8B57"}

-- Default window geometry
local DEFAULT_WIDTH  = 380
local DEFAULT_HEIGHT = 300
local MIN_WIDTH      = 340
local MIN_HEIGHT     = 80
local TITLE_HEIGHT   = 20
local BUTTON_ROW_Y   = 22
local BUTTON_HEIGHT  = 26
local STATUS_ROW_Y   = 50
local TARGET_START_Y = 60
local TAB_HEIGHT     = 22

local AREA_BAND_COLORS = {
    "<medium_orchid>",
    "<cornflower_blue>",
    "<gold>",
    "<medium_sea_green>",
    "<salmon>",
    "<light_sky_blue>",
    "<dark_orchid>",
    "<chartreuse>",
    "<deep_sky_blue>",
    "<orange_red>",
}

-------------------------------------------------------------------------------
-- Action Button Definitions
-- Mirrors button_1_list from the original plugin
-------------------------------------------------------------------------------

local actionButtons = {
    {id = "xcp", text = "xcp", cmd = "xcp",      rcmd = "xcp 0",    tip = "L: get target | R: clear target"},
    {id = "go",  text = "go",  cmd = "snd_go",    rcmd = "snd_go_area", tip = "L: go to target | R: go to area start"},
    {id = "kk",  text = "kk",  cmd = "xkill",     rcmd = "xkill",    tip = "L: kill target | R: kill target"},
    {id = "nx",  text = "nx",  cmd = "nx",         rcmd = "nx",       tip = "L: select next & go | R: same"},
    {id = "qs",  text = "qs",  cmd = "snd_qs",     rcmd = "snd_qs",   tip = "Quick-scan for current target"},
    {id = "qw",  text = "qw",  cmd = "qw",         rcmd = "qw",       tip = "L: quick-where | R: quick-where"},
    {id = "ht",  text = "ht",  cmd = "ht",         rcmd = "ht cancel", tip = "L: hunt trick | R: cancel hunt"},
    {id = "ref", text = "ref", cmd = "snd_rel",    rcmd = "snd_ref",  tip = "Refresh by active tab (Quest=quest info, CP=cp check, GQ=gq check)"},
}

-------------------------------------------------------------------------------
-- CSS Helpers
-- Build inline stylesheet strings for Geyser labels
-------------------------------------------------------------------------------

local function cssButton(styles, pressed)
    local b1 = pressed and styles.btnPressedBorder1 or styles.btnBorder1
    local b2 = pressed and styles.btnPressedBorder2 or styles.btnBorder2
    return string.format([[
        background-color: %s;
        color: %s;
        border-top: 1px solid %s;
        border-left: 1px solid %s;
        border-bottom: 1px solid %s;
        border-right: 1px solid %s;
        font-family: "%s";
        font-size: %dpt;
        font-weight: bold;
        qproperty-alignment: AlignCenter;
    ]], styles.btnBg, styles.btnText, b1, b1, b2, b2,
        styles.buttonFont, styles.buttonFontSize)
end

local function cssTitle(styles)
    return string.format([[
        background-color: %s;
        color: %s;
        border-top: 1px solid %s;
        border-left: 1px solid %s;
        border-bottom: 1px solid %s;
        border-right: 1px solid %s;
        font-family: "%s";
        font-size: %dpt;
        padding-left: 4px;
    ]], styles.titleBarBg, styles.titleText,
        styles.titleBarBorder, styles.titleBarBorder, styles.titleBarBorder, styles.titleBarBorder,
        styles.titleFont, styles.titleFontSize)
end

local function cssTargetArea(styles)
    return string.format([[
        background-color: %s;
        color: %s;
        font-family: "%s";
        font-size: %dpt;
        padding: 2px 4px;
    ]], styles.bgColor, styles.normal, styles.listFont, styles.listFontSize)
end

local function cssTab(styles, selected, selectedColor)
    local bg = selected and (selectedColor or styles.btnBg) or "#101010"
    return string.format([[
        background-color: %s;
        color: #FFFFFF;
        border: 1px solid #4a4a4a;
        font-family: "%s";
        font-size: %dpt;
        font-weight: bold;
        qproperty-alignment: AlignCenter;
    ]], bg, styles.buttonFont, styles.buttonFontSize)
end

local function cssStatusCircle(styles, color1, color2)
    return string.format([[
        background-color: %s;
        color: %s;
        border: 2px solid %s;
        border-radius: 18px;
        font-family: "%s";
        font-size: %dpt;
        font-weight: bold;
        qproperty-alignment: AlignCenter;
    ]], color2, styles.circleText1, color1,
        styles.statusFont, styles.statusFontSize + 1)
end

local function cssNoexp(styles, active)
    local color = active and "#0060FF" or "#00C030"
    return string.format([[
        background-color: %s;
        color: %s;
        font-family: "%s";
        font-size: %dpt;
        qproperty-alignment: AlignCenter;
    ]], styles.bgColor, color, styles.statusFont, styles.statusFontSize)
end

local function cssQuestTimer(styles, color)
    return string.format([[
        background-color: transparent;
        color: %s;
        font-family: "%s";
        font-size: %dpt;
        qproperty-alignment: AlignRight;
        padding-right: 4px;
    ]], color or styles.questWaiting, styles.titleFont, styles.titleFontSize)
end

local function cssResizeHandle(styles)
    return string.format([[
        background-color: transparent;
        color: %s;
        font-family: "%s";
        font-size: 8pt;
        qproperty-alignment: AlignBottom | AlignRight;
        padding-right: 1px;
        padding-bottom: 0px;
    ]], "#707070", styles.listFont)
end

local function cssMinimizeBtn(styles)
    return string.format([[
        background-color: transparent;
        color: %s;
        font-family: "%s";
        font-size: 10pt;
        font-weight: bold;
        qproperty-alignment: AlignCenter;
    ]], "#C0C0C0", styles.titleFont)
end


local function isRightButton(...)
    local args = {...}

    local function is_right_value(v)
        if v == nil then return false end
        if v == 2 or v == "RightButton" then return true end
        if type(v) == "string" then
            local lv = v:lower()
            return lv:find("right", 1, true) ~= nil
        end
        return false
    end

    local function inspect(v)
        if is_right_value(v) then return true end
        if type(v) == "table" then
            if is_right_value(v.button) or is_right_value(v[1]) or is_right_value(v[2]) then
                return true
            end
        end
        return false
    end

    for _, a in ipairs(args) do
        if inspect(a) then
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------
-- Create the Main Window
-------------------------------------------------------------------------------

function snd.gui.createWindow()
    -- Prevent double-creation
    if snd.gui.initialized and snd.gui.elements.main then
        snd.utils.debugNote("GUI already exists, refreshing")
        snd.gui.refresh()
        return
    end

    -- Destroy any stale remnants
    snd.gui.destroy()

    local cfg = snd.config.window
    local s = snd.gui.styles
    local fontSize = tonumber(cfg.fontSize) or s.listFontSize
    s.listFontSize = fontSize
    s.buttonFontSize = fontSize
    s.statusFontSize = fontSize
    s.titleFontSize = fontSize + 1
    local w = cfg.width or DEFAULT_WIDTH
    local h = cfg.height or DEFAULT_HEIGHT
    local px = cfg.posX or 50
    local py = cfg.posY or 50

    -----------------------------------------------------------------------
    -- Main container (Adjustable = draggable + resizable)
    -----------------------------------------------------------------------
    snd.gui.elements.main = Adjustable.Container:new({
        name = "sndMain",
        x = px, y = py,
        width = w, height = h,
        adjLabelstyle = "border: 1px solid " .. s.windowBorder .. "; background-color: " .. s.bgColor .. ";",
        buttonstyle = "",
        lockStyle = "border: 0px;",
        titleText = "",
        titleTxtColor = "white",
    })

    -----------------------------------------------------------------------
    -- Title Bar
    -----------------------------------------------------------------------
    snd.gui.elements.titleBar = Geyser.Label:new({
        name = "sndTitleBar",
        x = 0, y = 0,
        width = "100%", height = TITLE_HEIGHT,
    }, snd.gui.elements.main)
    snd.gui.elements.titleBar:setStyleSheet(cssTitle(s))
    snd.gui.elements.titleBar:echo(snd.fullVersion or "Search & Destroy")
    -- Enable drag (title bar moves the whole container)
    snd.gui.elements.titleBar:setClickCallback("snd.gui.onTitleRightClick")

    -----------------------------------------------------------------------
    -- Minimize / Maximize button (top-right)
    -----------------------------------------------------------------------
    snd.gui.elements.minBtn = Geyser.Label:new({
        name = "sndMinBtn",
        x = -22, y = 0,
        width = 20, height = TITLE_HEIGHT,
    }, snd.gui.elements.main)
    snd.gui.elements.minBtn:setStyleSheet(cssMinimizeBtn(s))
    snd.gui.elements.minBtn:echo("▬")
    snd.gui.elements.minBtn:setClickCallback("snd.gui.toggleMinimize")

    -----------------------------------------------------------------------
    -- Quest Timer (in title bar, right-aligned)
    -----------------------------------------------------------------------
    snd.gui.elements.questTimer = Geyser.Label:new({
        name = "sndQuestTimer",
        x = "40%", y = 0,
        width = "60%-24", height = TITLE_HEIGHT,
    }, snd.gui.elements.main)
    snd.gui.elements.questTimer:setStyleSheet(cssQuestTimer(s, s.questWaiting))
    snd.gui.elements.questTimer:echo("")

    -----------------------------------------------------------------------
    -- Circle Status Readout (activity indicator)
    -----------------------------------------------------------------------
    snd.gui.elements.circle = Geyser.Label:new({
        name = "sndCircle",
        x = 5, y = BUTTON_ROW_Y,
        width = 36, height = 36,
    }, snd.gui.elements.main)
    snd.gui.elements.circle:setStyleSheet(cssStatusCircle(s, s.circleBlue1, s.circleBlue2))
    snd.gui.elements.circle:echo("init")
    snd.gui.elements.circle:setClickCallback("snd.gui.onNoexpMouse")

    -----------------------------------------------------------------------
    -- Action Buttons
    -----------------------------------------------------------------------
    local btnX = 44
    local btnW = 35
    local btnGap = 3
    snd.gui.elements.buttons = {}

    for i, btn in ipairs(actionButtons) do
        local bx = btnX + (i - 1) * (btnW + btnGap)
        local label = Geyser.Label:new({
            name = "sndBtn_" .. btn.id,
            x = bx, y = BUTTON_ROW_Y + 3,
            width = btnW, height = BUTTON_HEIGHT,
        }, snd.gui.elements.main)
        label:setStyleSheet(cssButton(s, false))
        label:echo(btn.text)
        label:setClickCallback("snd.gui.onButtonClick", btn.id)
        -- Store tooltip info for later
        label:setToolTip(btn.tip)
        snd.gui.elements.buttons[btn.id] = label
    end
	--- Quick Scan - mirrors quick_scan() from original plugin
	-- Sends "scan <keyword>" if target selected, plain "scan" otherwise
	function snd.gui.quickScan()
		if snd.targets.current and snd.targets.current.keyword and snd.targets.current.keyword ~= "" then
			send("scan " .. snd.targets.current.keyword, false)
		else
			send("scan", false)
		end
	end
    -----------------------------------------------------------------------
    -- AutoCheck Readout (right of buttons)
    -----------------------------------------------------------------------
    snd.gui.elements.autocheck = Geyser.Label:new({
        name = "sndAutocheck",
        x = -55, y = BUTTON_ROW_Y + 3,
        width = 50, height = BUTTON_HEIGHT,
    }, snd.gui.elements.main)
    snd.gui.elements.autocheck:setStyleSheet(cssNoexp(s, false))
    snd.gui.elements.autocheck:echo("AC:ON")
    snd.gui.elements.autocheck:setToolTip("L: cycle AutoCheck mode (ON/SMART/OFF)")
    snd.gui.elements.autocheck:setClickCallback("snd.gui.onAutocheckClick")

    -----------------------------------------------------------------------
    -- Target List Area (MiniConsole for proper multi-line colored text)
    -----------------------------------------------------------------------
    snd.gui.elements.targetArea = Geyser.MiniConsole:new({
        name = "sndTargetArea",
        x = 0, y = TARGET_START_Y,
        width = "100%", height = string.format("100%%-%d", TARGET_START_Y + TAB_HEIGHT + 18),
        color = "black",
        scrollBar = false,
        fontSize = s.listFontSize,
        font = s.listFont,
    }, snd.gui.elements.main)
    setBackgroundColor("sndTargetArea", 0, 0, 0, 255)
    setFont("sndTargetArea", s.listFont)
    setFontSize("sndTargetArea", s.listFontSize)

    snd.gui.elements.tabBar = Geyser.Container:new({
        name = "sndTabBar",
        x = 0, y = -TAB_HEIGHT,
        width = "100%", height = TAB_HEIGHT,
    }, snd.gui.elements.main)
    snd.gui.elements.tabs = {}
    local tabWidthPct = math.floor(100 / #snd.gui.tabOrder)
    for i, key in ipairs(snd.gui.tabOrder) do
        local x = ((i - 1) * tabWidthPct) .. "%"
        local w = (i == #snd.gui.tabOrder) and (100 - ((i - 1) * tabWidthPct)) .. "%" or tabWidthPct .. "%"
        local tab = Geyser.Label:new({
            name = "sndTab_" .. key,
            x = x, y = 0, width = w, height = "100%",
            message = snd.gui.tabLabels[key] or key,
        }, snd.gui.elements.tabBar)
        tab:setClickCallback("snd.gui.onTabClick", key)
        snd.gui.elements.tabs[key] = tab
    end

    -----------------------------------------------------------------------
    -- Resize Handle (bottom-right corner)
    -----------------------------------------------------------------------
    snd.gui.elements.resizeHandle = Geyser.Label:new({
        name = "sndResizeHandle",
        x = -16, y = -16,
        width = 15, height = 15,
    }, snd.gui.elements.main)
    snd.gui.elements.resizeHandle:setStyleSheet(cssResizeHandle(s))
    snd.gui.elements.resizeHandle:echo("◢")
    snd.gui.elements.resizeHandle:setToolTip("Drag to resize (use xset win width/height)")

    -----------------------------------------------------------------------
    -- Final setup
    -----------------------------------------------------------------------
    snd.gui.initialized = true
    snd.gui.minimized = false

    if cfg.enabled == false then
        snd.gui.hide()
    else
        snd.gui.show()
    end

    -- Initial draw
    snd.gui.refresh()
    if snd.quest
        and snd.quest.requestCooldownStatus
        and (not snd.quest.active)
        and (not snd.quest.nextQuestTime or snd.quest.nextQuestTime <= 0) then
        snd.quest.requestCooldownStatus({silent = true})
    end
    snd.utils.debugNote("GUI window created")
end

-------------------------------------------------------------------------------
-- Destroy GUI (clean teardown)
-------------------------------------------------------------------------------

function snd.gui.destroy()
    -- Kill individual target labels
    snd.gui.clearTargetLabels()

    -- Kill all named elements
    for name, el in pairs(snd.gui.elements) do
        if type(el) == "table" then
            -- It might be a sub-table (like buttons)
            if el.hide then
                pcall(function() el:hide() end)
            end
        end
    end

    -- Kill the main container
    if snd.gui.elements.main then
        pcall(function() snd.gui.elements.main:hide() end)
    end

    -- Clean up Geyser references
    if Geyser and Geyser.Label then
        for _, name in ipairs({
            "sndMain", "sndBorder", "sndTitleBar", "sndMinBtn",
            "sndQuestTimer", "sndCircle", "sndAutocheck",
            "sndTargetArea", "sndResizeHandle",
        }) do
            if Geyser.Label.all and Geyser.Label.all[name] then
                Geyser.Label.all[name] = nil
            end
        end
    end

    snd.gui.elements = {}
    snd.gui.targetLabels = {}
    snd.gui.initialized = false
end

-------------------------------------------------------------------------------
-- Clear dynamic target labels
-------------------------------------------------------------------------------

function snd.gui.clearTargetLabels()
    for _, lbl in ipairs(snd.gui.targetLabels) do
        if lbl and lbl.hide then
            pcall(function() lbl:hide() end)
        end
    end
    snd.gui.targetLabels = {}
end


function snd.gui.bindNoexpCallbacks()
    local labels = {snd.gui.elements.circle}
    for _, label in ipairs(labels) do
        if label and label.setClickCallback then
            label:setClickCallback(function(...)
                snd.gui.onNoexpMouse(...)
            end)
        end
        if label and label.setRightClickCallback then
            label:setRightClickCallback(function(...)
                snd.gui.onNoexpRightClick(...)
            end)
        end
    end
end

-------------------------------------------------------------------------------
-- Refresh Entire GUI
-- Called whenever data changes (target list, quest status, room change, etc.)
-------------------------------------------------------------------------------

function snd.gui.refresh()
    if not snd.gui.initialized or not snd.gui.elements.main then return end
    if snd.gui.minimized then return end

    snd.gui.updateCircle()
    snd.gui.updateNoexp()
    snd.gui.updateAutocheck()
    snd.gui.updateQuestTimer()
    snd.gui.updateTargetList()
    snd.gui.applyTabStyles()
end

function snd.gui.applyTabStyles()
    if not snd.gui.elements or not snd.gui.elements.tabs then return end
    local active = snd.getActiveTab and snd.getActiveTab() or nil
    for key, tab in pairs(snd.gui.elements.tabs) do
        local selected = (key == active)
        if tab.echo then
            tab:echo(snd.gui.getTabLabel(key))
        end
        tab:setStyleSheet(cssTab(snd.gui.styles, selected, snd.gui.tabColors[key]))
    end
end

function snd.gui.getQuestTabMinutes()
    if not snd.quest then return nil end
    local qstat = snd.quest.target and snd.quest.target.status or "1"

    if qstat == "2" and snd.quest.timer and snd.quest.timer > 0 then
        return math.max(0, math.ceil((snd.quest.timer - os.time()) / 60))
    end

    if snd.quest.nextQuestTime and snd.quest.nextQuestTime > 0 then
        local mins = snd.quest.getNextQuestMinutesRemaining and snd.quest.getNextQuestMinutesRemaining() or 0
        if mins and mins > 0 then
            return mins
        end
        if mins == 0 then
            return 0
        end
    end

    return nil
end

function snd.gui.getTabLabel(tabKey)
    local baseLabel = snd.gui.tabLabels[tabKey] or tabKey
    if tabKey ~= "quest" then
        return baseLabel
    end

    local mins = snd.gui.getQuestTabMinutes()
    if mins and mins > 0 then
        return string.format("%s - %dm", baseLabel, mins)
    end

    local qstat = snd.quest and snd.quest.target and snd.quest.target.status or "1"
    local hasCooldown = snd.quest and snd.quest.nextQuestTime and snd.quest.nextQuestTime > 0
    local availableText = snd.quest and snd.quest.nextQuestText or ""
    local isAvailableByStatus = (qstat == "0" and not hasCooldown)
    if (snd.quest and snd.quest.available and not hasCooldown)
        or mins == 0
        or isAvailableByStatus
        or (not (snd.quest and snd.quest.active) and availableText:lower():find("quest available", 1, true)) then
        return string.format("%s [Available] ⚠️", baseLabel)
    end

    return baseLabel
end

function snd.gui.onTabClick(tabKey, _, button)
    if isRightButton(button) then return end
    if snd.setActiveTab then
        snd.setActiveTab(tabKey, {save = true, refresh = true})
    end
end

-------------------------------------------------------------------------------
-- Update the Circle Status Readout
-- Mirrors draw_circle_readout() from the original
-------------------------------------------------------------------------------

function snd.gui.updateCircle()
    if not snd.gui.elements.circle then return end

    local s = snd.gui.styles
    local auto = snd.config.anex and snd.config.anex.automatic
    local cutoff = snd.config.anex and snd.config.anex.tnlCutoff or 0
    local active = auto and cutoff > 0
    local c1 = active and s.circleGreen1 or s.circleRed1
    local c2 = active and s.circleGreen2 or s.circleRed2
    local text = active and tostring(cutoff) or "off"

    snd.gui.elements.circle:setStyleSheet(cssStatusCircle(s, c1, c2))
    snd.gui.elements.circle:echo(text)
    local tip = "L: +100 TNL cutoff | R: -100 TNL cutoff"
    if auto then
        tip = tip .. "\nTNL cutoff: " .. cutoff
    else
        tip = tip .. "\nNoexp is manual mode"
    end
    snd.gui.elements.circle:setToolTip(tip)
end

-------------------------------------------------------------------------------
-- Update Noexp Readout
-- Mirrors draw_noexp_readout() from the original
-------------------------------------------------------------------------------

function snd.gui.updateNoexp()
    snd.gui.updateCircle()
end

function snd.gui.updateAutocheck()
    if not snd.gui.elements.autocheck then return end
    local mode = snd.getAutocheckMode and snd.getAutocheckMode() or "on"
    local label = "AC:" .. string.upper(mode)
    snd.gui.elements.autocheck:echo(label)
    snd.gui.elements.autocheck:setToolTip("L: cycle AutoCheck mode (ON/SMART/OFF)")
end

function snd.gui.applyFontSize()
    if not snd.gui.initialized then
        return
    end
    local s = snd.gui.styles
    local cfg = snd.config.window or {}
    local fontSize = tonumber(cfg.fontSize) or s.listFontSize
    s.listFontSize = fontSize
    s.buttonFontSize = fontSize
    s.statusFontSize = fontSize
    s.titleFontSize = fontSize + 1

    if snd.gui.elements.titleBar then
        snd.gui.elements.titleBar:setStyleSheet(cssTitle(s))
    end
    if snd.gui.elements.questTimer then
        snd.gui.elements.questTimer:setStyleSheet(cssQuestTimer(s, s.questWaiting))
    end
    if snd.gui.elements.buttons then
        for _, btn in pairs(snd.gui.elements.buttons) do
            if btn and btn.setStyleSheet then
                btn:setStyleSheet(cssButton(s, false))
            end
        end
    end
    if snd.gui.elements.resizeHandle then
        snd.gui.elements.resizeHandle:setStyleSheet(cssResizeHandle(s))
    end
    if snd.gui.elements.targetArea then
        pcall(function()
            snd.gui.elements.targetArea:setFontSize(s.listFontSize)
        end)
        setFont("sndTargetArea", s.listFont)
        setFontSize("sndTargetArea", s.listFontSize)
    end
    if snd.gui.elements.circle then
        snd.gui.updateCircle()
    end
    snd.gui.updateNoexp()
    snd.gui.updateAutocheck()
    snd.gui.updateQuestTimer()
    snd.gui.updateTargetList()
end

--- Refresh target links - mirrors xgui_RefreshLinks() from original
-- Sends cp check or gq check depending on current activity
function snd.gui.refreshTargets()
    local activeTab = snd.getActiveTab and snd.getActiveTab() or "quest"
    if activeTab == "gq" then
        send("gq check", false)
    elseif activeTab == "cp" then
        if snd.cp and snd.cp.requestCheck then
            snd.cp.requestCheck(0, "gui.refreshTargets:tab-cp")
        else
            send("cp check", false)
        end
    else
        send("quest info", false)
    end
    -- Maximize window if minimized
    if snd.gui.minimized then
        snd.gui.maximize()
    end
end

--- Reload target data - mirrors xgui_ReloadLinks() from original
--- Like refreshTargets but uses the heavier `gq info` payload on the GQ tab
--- so reward/metadata parsing (handled by the gq-info parser) runs.
function snd.gui.reloadTargets()
    local activeTab = snd.getActiveTab and snd.getActiveTab() or "quest"
    if activeTab == "gq" then
        send("gq info", false)
    elseif activeTab == "cp" then
        if snd.cp and snd.cp.requestCheck then
            snd.cp.requestCheck(0, "gui.reloadTargets:tab-cp")
        else
            send("cp check", false)
        end
    else
        send("quest info", false)
    end
    if snd.gui.minimized then
        snd.gui.maximize()
    end
end

function snd.gui.onAutocheckClick()
    local mode = snd.getAutocheckMode and snd.getAutocheckMode() or "on"
    local nextMode = (mode == "on" and "smart") or (mode == "smart" and "off") or "on"
    if snd.commands and snd.commands.setAutocheckMode then
        snd.commands.setAutocheckMode(nextMode)
    end
    snd.gui.updateAutocheck()
end
-------------------------------------------------------------------------------
-- Update Quest Timer (in title bar)
-- Mirrors draw_next_quest_time() and quest_timer_text() from the original
-------------------------------------------------------------------------------

function snd.gui.updateQuestTimer()
    if not snd.gui.elements.questTimer then return end
    local s = snd.gui.styles
    local text = ""
    local color = s.questWaiting

    if snd.quest then
        local qstat = snd.quest.target and snd.quest.target.status or "1"
        if qstat == "2" then
            -- Active quest, show time remaining
            color = s.targeted
            if snd.quest.timer and snd.quest.timer > 0 then
                local mins = math.max(0, math.ceil((snd.quest.timer - os.time()) / 60))
                text = string.format("Quest: %dm", mins)
            else
                text = "Quest active"
            end
        elseif qstat == "3" then
            -- Quest complete, turn it in
            color = s.questComplete
            text = "Quest done!"
        elseif qstat == "0" then
            -- Quest available (or waiting)
            if snd.quest.nextQuestTime and snd.quest.nextQuestTime > 0 then
                local mins, cooldownText = snd.quest.getNextQuestStatus()
                if mins > 0 then
                    text = cooldownText ~= "" and cooldownText or string.format("Next quest: %dm", mins)
                    color = s.questWaiting
                else
                    color = s.questAvailable
                    text = "Quest ready"
                end
            else
                color = s.questAvailable
                text = "Quest ready"
            end
        else
            -- Waiting for quest
            if snd.quest.nextQuestTime and snd.quest.nextQuestTime > 0 then
                local mins, cooldownText = snd.quest.getNextQuestStatus()
                if mins > 0 then
                    text = cooldownText ~= "" and cooldownText or string.format("Next quest: %dm", mins)
                    color = s.questWaiting
                else
                    text = "Quest ready"
                    color = s.questAvailable
                end
            end
        end
    end

    snd.gui.elements.questTimer:setStyleSheet(cssQuestTimer(s, color))
    snd.gui.elements.questTimer:echo(text)
end

function snd.gui.stopQuestTimer()
    if snd.quest and snd.quest.timerTickerId then
        killTimer(snd.quest.timerTickerId)
        snd.quest.timerTickerId = nil
    end
end

function snd.gui.startQuestTimer()
    if not snd.quest then
        return
    end

    snd.gui.stopQuestTimer()

    local function tick()
        if not snd.quest or not snd.quest.timerEndTime or snd.quest.timerEndTime <= 0 then
            snd.gui.stopQuestTimer()
            return
        end

        local remaining = snd.quest.timerEndTime - os.time()
        if remaining <= 0 then
            snd.quest.timerEndTime = 0
            snd.gui.stopQuestTimer()
            if snd.gui and snd.gui.updateQuestTimer then
                snd.gui.updateQuestTimer()
            end
            return
        end

        if snd.gui and snd.gui.elements and snd.gui.elements.questTimer then
            local s = snd.gui.styles
            local mins = math.floor(remaining / 60)
            local secs = remaining % 60
            local color = "#FFFFFF"
            if remaining < 120 then
                color = "#FF3B30"
            elseif remaining < 300 then
                color = "#FF9500"
            end

            snd.gui.elements.questTimer:setStyleSheet(cssQuestTimer(s, color))
            snd.gui.elements.questTimer:echo(string.format("%d:%02d", mins, secs))
        end

        snd.quest.timerTickerId = tempTimer(1, tick)
    end

    tick()
end
-------------------------------------------------------------------------------
-- Named color map for cecho (Mudlet named colors)
-------------------------------------------------------------------------------
local TC = {
    normal      = "<light_gray>",
    targeted    = "<orange_red>",
    dead        = "<dim_gray>",
    unknown     = "<red>",
    unknownDead = "<maroon>",
    unlikely    = "<dim_gray>",
    unlikelyTag = "<medium_blue>",
    questAvail  = "<steel_blue>",
    questDone   = "<lawn_green>",
    questWait   = "<light_coral>",
    express     = "<orange_red>",
    gray        = "<gray>",
    gqTab       = "<dodger_blue>",
    cpTab       = "<sea_green>",
    reset       = "<reset>",
}
-------------------------------------------------------------------------------
-- Update Target List
-- Mirrors xg_show_target_links() and xg_show_quest_target_link()
-- Builds clickable labels for each target
-------------------------------------------------------------------------------

function snd.gui.updateTargetList()
    if not snd.gui.elements.targetArea then
        snd.utils.debugNote("ABORT: targetArea element is nil")
        return
    end

    local tc = snd.gui.elements.targetArea
    local targetName = tc.name or "sndTargetArea"

    local function clearTargetArea()
        if targetName and type(clearWindow) == "function" then
            return pcall(function() clearWindow(targetName) end)
        end
        if tc and tc.clear then
            return pcall(function() tc:clear() end)
        end
        return false, "No clear method available"
    end

    local function writeTargetText(text)
        if targetName and type(cecho) == "function" then
            return pcall(function() cecho(targetName, text) end)
        end
        if tc and tc.cecho then
            return pcall(function() tc:cecho(text) end)
        end
        return false, "No cecho method available"
    end

    local function writeTargetLink(text, command, hint)
        if targetName and type(cechoLink) == "function" then
            return pcall(function() cechoLink(targetName, text, command, hint, true) end)
        end
        if targetName and type(echoLink) == "function" then
            return pcall(function() echoLink(targetName, text, command, hint, true) end)
        end
        return writeTargetText(text)
    end

    -- Try clearing
    local ok, err = clearTargetArea()
    if not ok then
        snd.utils.debugNote("clear() ok=false err=" .. tostring(err))
    end

    local targetCount = snd.targets and snd.targets.list and #snd.targets.list or 0

    -- Measure the actual rendered line height and the MiniConsole's pixel height
    -- so the displayed target count adapts to real geometry (window resizes,
    -- font-size changes) instead of relying on hardcoded constants that left
    -- visible empty space at the bottom of the window.
    local lineHeight = 13
    if type(calcFontSize) == "function" then
        local ok, fw, fh = pcall(calcFontSize, "sndTargetArea")
        if ok and type(fh) == "number" and fh > 0 then
            lineHeight = fh
        end
    end

    local areaPixelHeight
    local taElement = snd.gui.elements.targetArea
    if taElement then
        local heightGetter = taElement.get_height or taElement.getHeight
        if type(heightGetter) == "function" then
            local ok, h = pcall(heightGetter, taElement)
            if ok and type(h) == "number" and h > 0 then
                areaPixelHeight = h
            end
        end
    end

    local maxHeight
    if areaPixelHeight then
        maxHeight = areaPixelHeight
    else
        maxHeight = (snd.config.window.height or DEFAULT_HEIGHT) - TARGET_START_Y - TAB_HEIGHT - 18
    end
    local maxLines = math.max(1, math.floor(maxHeight / lineHeight))
    local lineCount = 0
    local activeTab = snd.getActiveTab and snd.getActiveTab() or nil
    local function normalizeMobName(name)
        local n = tostring(name or "")
        n = n:gsub("^%b()%s*", "")
        n = n:lower()
        n = n:gsub("%s+", " ")
        return snd.utils.trim(n)
    end
    local currentEnemyName = ""
    if gmcp and gmcp.char and gmcp.char.status then
        currentEnemyName = gmcp.char.status.enemy or gmcp.char.status.opponent or ""
    end
    currentEnemyName = normalizeMobName(currentEnemyName)
    local function isFightingTarget(targetMob)
        if currentEnemyName == "" then return false end
        local mobName = normalizeMobName(targetMob)
        if mobName == "" then return false end
        return mobName == currentEnemyName
            or mobName:find(currentEnemyName, 1, true) ~= nil
            or currentEnemyName:find(mobName, 1, true) ~= nil
    end

    ---------------------------------------------------------------------------
    -- Quest Target Line
    ---------------------------------------------------------------------------
    if (activeTab == nil or activeTab == "quest") and snd.quest then
        local qstat = snd.quest.target and snd.quest.target.status or "1"

        if qstat == "0" then
            if snd.quest.nextQuestTime and snd.quest.nextQuestTime > 0 then
                local mins, cooldownText = snd.quest.getNextQuestStatus()
                if mins > 0 then
                    local waitText = cooldownText ~= "" and cooldownText
                        or string.format("Next quest in: %d minutes", mins)
                    writeTargetText(TC.questWait .. " " .. waitText .. "\n")
                else
                    local questRequestCommand = [[send("quest request", false)]]
                    local okLink = writeTargetLink(
                        TC.questAvail .. " You may now quest again",
                        questRequestCommand,
                        "Request a new quest"
                    )
                    if not okLink then
                        writeTargetText(TC.questAvail .. " You may now quest again")
                    end
                    writeTargetText(TC.reset)
                    writeTargetText("\n")
                end
            else
                local questRequestCommand = [[send("quest request", false)]]
                local okLink = writeTargetLink(
                    TC.questAvail .. " You may now quest again",
                    questRequestCommand,
                    "Request a new quest"
                )
                if not okLink then
                    writeTargetText(TC.questAvail .. " You may now quest again")
                end
                writeTargetText(TC.reset)
                writeTargetText("\n")
            end
            lineCount = lineCount + 1
        elseif qstat == "2" or qstat == "active" or qstat == "missing" then
            local mob = snd.quest.target.mob or "?"
            local room = snd.quest.target.room or ""
            local area = snd.quest.target.area or ""
            local roomId = nil
            if snd.targets and snd.targets.current and snd.targets.current.activity == "quest" then
                roomId = snd.targets.current.roomId
            end
            local color = TC.normal
            local locStr = ""
            if room ~= "" then
                local roomSuffix = roomId and string.format(" (%s)", tostring(roomId)) or ""
                locStr = string.format(" - '%s'%s (%s)", room, roomSuffix, area)
            elseif area ~= "" then
                locStr = " - " .. area
            end
            local selectCommand = [[snd.commands.selectQuestTargetAndKill()]]
            writeTargetText(color .. " 1) ")
            local okLink = writeTargetLink(mob, selectCommand, "Click to go and xkill quest target")
            if not okLink then
                writeTargetText(mob)
            end
            writeTargetText(string.format("%s%s\n", locStr, TC.reset))
            lineCount = lineCount + 1
            local questCache = snd.nav and snd.nav.quickWhereByActivity and snd.nav.quickWhereByActivity.quest
            local questCacheValid = true
            if questCache and questCache.targetKey and questCache.targetKey ~= "" and snd.commands and snd.commands.buildQuickWhereTargetKeyFromCurrent then
                local questTarget = snd.targets and snd.targets.scoped and snd.targets.scoped.quest
                if not questTarget and snd.targets and snd.targets.current and snd.targets.current.activity == "quest" then
                    questTarget = snd.targets.current
                end
                local currentQuestKey = questTarget and snd.commands.buildQuickWhereTargetKeyFromCurrent(questTarget) or ""
                questCacheValid = (currentQuestKey ~= "" and currentQuestKey == questCache.targetKey)
            end
            if questCacheValid and questCache and questCache.rooms and #questCache.rooms > 0 then
                writeTargetText("<gray>  rooms:<reset>\n")
                lineCount = lineCount + 1
                for i, roomId in ipairs(questCache.rooms) do
                    if lineCount >= maxLines then break end
                    local marker = (questCache.index == i) and "*" or " "
                    local roomName = ""
                    if snd.mapper and snd.mapper.getRoomInfo then
                        local info = snd.mapper.getRoomInfo(roomId)
                        roomName = info and info.name or ""
                    end
                    roomName = snd.utils.stripColors(roomName or "")
                    local label = roomName ~= ""
                        and string.format("'%s' (%s)", roomName, tostring(roomId))
                        or string.format("(room %s)", tostring(roomId))
                    writeTargetText(string.format("<light_slate_gray>   %s %2d) ", marker, i))
                    local gotoRoomCommand = string.format([[snd.commands.selectQuickWhereRoom(%d, "quest")]], i)
                    local okRoomLink = writeTargetLink(label, gotoRoomCommand, "Go to this quest room")
                    if not okRoomLink then
                        writeTargetText(label)
                    end
                    writeTargetText("<reset>\n")
                    lineCount = lineCount + 1
                    if i >= 12 then
                        if #questCache.rooms > i then
                            writeTargetText(string.format("<gray>   ... %d more rooms ...<reset>\n", #questCache.rooms - i))
                            lineCount = lineCount + 1
                        end
                        break
                    end
                end
            end
        elseif qstat == "3" or qstat == "killed" then
            local completeCommand = [[send("complete", false)]]
            local okLink = writeTargetLink(
                TC.questDone .. " Quest complete, turn it in",
                completeCommand,
                "Turn in quest"
            )
            if not okLink then
                writeTargetText(TC.questDone .. " Quest complete, turn it in")
            end
            writeTargetText(TC.reset)
            writeTargetText("\n")
            lineCount = lineCount + 1
        else
            writeTargetText(TC.questWait .. " Quest status pending\n")
            lineCount = lineCount + 1
        end

        writeTargetText("\n")
        lineCount = lineCount + 1
    else
        snd.utils.debugNote("snd.quest is nil/false")
    end

    ---------------------------------------------------------------------------
    -- CP / GQ Target Lines
    ---------------------------------------------------------------------------
    if snd.targets and snd.targets.list then
        local gqDisplayIndex = 0
        local areaColorMap = {}
        if snd.config.areaColors ~= false then
            local areaColorNext = 1
            for _, target in ipairs(snd.targets.list) do
                local arid = target.arid or ""
                if arid ~= "" and not areaColorMap[arid] then
                    areaColorMap[arid] = AREA_BAND_COLORS[areaColorNext]
                    areaColorNext = (areaColorNext % #AREA_BAND_COLORS) + 1
                end
            end
        end

        for index, v in ipairs(snd.targets.list) do
            if lineCount >= maxLines then
                writeTargetText(TC.gray .. string.format(" ... %d more targets ...\n",
                    #snd.targets.list - index + 1))
                break
            end

            if v.activity ~= "quest" and (activeTab == nil or v.activity == activeTab) then
                -- Determine color
                local color = TC.normal
                local isTargeted = snd.gui.isCurrentTarget(v, index)

                if isTargeted then
                    color = TC.targeted
                elseif v.unlikely then
                    color = TC.unlikely
                elseif v.killed then
                    color = TC.dead
                elseif v.dead and (not v.arid or v.arid == "") then
                    color = TC.unknownDead
                elseif v.dead then
                    color = (v.activity == "cp") and "<tomato>" or TC.dead
                elseif v.lowConfidence then
                    color = TC.unlikely
                elseif (not v.arid or v.arid == "") and v.loc and v.loc ~= "" then
                    color = TC.unknown
                end

                local mob = v.mob or "?"
                local deathTag = ""
                if v.killed then
                    deathTag = " [Killed]"
                elseif v.dead then
                    deathTag = " [Dead]"
                end

                local location = ""
                if snd.targets.type == "room" and v.roomName and v.roomName ~= "" then
                    local roomSuffix = v.roomId and string.format(" (%s)", tostring(v.roomId)) or ""
                    location = string.format("'%s'%s (%s)", v.roomName, roomSuffix, v.arid or v.loc or "")
                elseif v.arid and v.arid ~= "" then
                    location = v.arid
                elseif v.loc and v.loc ~= "" then
                    location = v.loc
                end

                local qtyStr = ""
                if v.activity == "gq" and v.qty and tonumber(v.qty) and tonumber(v.qty) > 0 then
                    qtyStr = tostring(v.qty) .. "* "
                end

                local dupStr = ""
                if v.duplicates and v.duplicates > 1 then
                    dupStr = string.format("(%d/%d) ", v.dupIndex or v.index or 1, v.duplicates)
                end

                local prefix = ""
                if v.unlikely then
                    prefix = TC.unlikelyTag .. "(Unlikely) "
                end

                local suffix = ""
                if snd.gui.isExpressTarget and snd.gui.isExpressTarget(v) then
                    suffix = "  " .. TC.express .. "(Express)"
                end

                local displayIndex = nil
                if v.activity == "cp" then
                    if v.dead then
                        displayIndex = tonumber(v.cpListIndex) or tonumber(v.displayIndex)
                    else
                        displayIndex = tonumber(v.displayIndex) or tonumber(v.cpListIndex)
                    end
                elseif v.activity == "gq" and not v.dead then
                    gqDisplayIndex = gqDisplayIndex + 1
                    displayIndex = gqDisplayIndex
                end

                local displayLabel = displayIndex and string.format("%2d", displayIndex) or "--"
                local isFighting = isFightingTarget(v.mob) and not v.dead
                local numberColor = color
                if isTargeted or isFighting then
                    numberColor = TC.targeted
                elseif v.lowConfidence then
                    numberColor = TC.unlikely
                elseif v.activity == "gq" then
                    numberColor = TC.gqTab
                elseif v.activity == "cp" then
                    numberColor = TC.cpTab
                end
                local indexVisual = displayLabel .. ")"
                local okPrefix = writeTargetText(string.format("%s%s%s %s%s",
                    prefix, numberColor, indexVisual, dupStr, qtyStr))
                if not okPrefix then
                    writeTargetText(string.format("%s%s %s%s", numberColor, indexVisual, dupStr, qtyStr))
                end

                if displayIndex then
                    local selectCommand = string.format([[snd.commands.selectTarget(%d, "%s")]], displayIndex, v.activity or "cp")
                    local selectHint = string.format("Click to select target #%d (xcp %d)", displayIndex, displayIndex)
                    if v.activity == "cp" and v.dead then
                        selectHint = string.format("Click to refresh dead target #%d (runs cp check)", displayIndex)
                    end
                    local okLink, errL = writeTargetLink(mob .. deathTag, selectCommand, selectHint)
                    if not okLink then
                        snd.utils.debugNote("ERROR echoing line " .. index .. ": " .. tostring(errL))
                    end
                else
                    writeTargetText(mob .. deathTag)
                end
                local bandColor = ""
                local arid = v.arid or ""
                if arid ~= "" and areaColorMap[arid]
                   and not v.lowConfidence and not v.unlikely then
                    bandColor = areaColorMap[arid]
                end
                writeTargetText(string.format(" - %s%s%s%s\n", bandColor, location, suffix, TC.reset))

                lineCount = lineCount + 1
            end
        end
    end

    if snd.triggers and snd.triggers.registerTargetLineTriggers then
        snd.triggers.registerTargetLineTriggers()
    end

    ---------------------------------------------------------------------------
    -- Empty state
    ---------------------------------------------------------------------------
    if lineCount == 0 then
        if activeTab == "gq" then
            writeTargetText(TC.gray .. "You are not on a global campaign.\n")
        elseif activeTab == "cp" then
            local cpTargetsInDisplay = 0
            if snd.targets and snd.targets.list then
                for _, t in ipairs(snd.targets.list) do
                    if t.activity == "cp" then
                        cpTargetsInDisplay = cpTargetsInDisplay + 1
                    end
                end
            end
            local cpTargetsInCampaign = snd.campaign and snd.campaign.targets and #snd.campaign.targets or 0
            local hasAnyCpTargets = cpTargetsInDisplay > 0 or cpTargetsInCampaign > 0

            writeTargetText(TC.gray .. "No targets\n\n")
            if hasAnyCpTargets then
                writeTargetText(TC.gray .. "Campaign data is still syncing. Use 'cp check' to refresh.\n")
            else
                writeTargetText(TC.gray .. "Use 'campaign request' to populate.\n")
                local canTakeAnotherCampaign = snd.campaign and snd.campaign.canGetNew
                if canTakeAnotherCampaign == true then
                    writeTargetText(TC.questAvail .. "\nYou can take another campaign at your level.\n")
                elseif canTakeAnotherCampaign == false then
                    writeTargetText(TC.gray .. "\nYou will have to level before you can go on another campaign.\n")
                end
            end
            if snd.cp and snd.cp.normalizeCampaignTodayCounter then
                snd.cp.normalizeCampaignTodayCounter()
            end
            local totalCampaignsToday = snd.campaign and tonumber(snd.campaign.completedToday) or 0
            writeTargetText(TC.gray .. string.format("Campaigns completed today: %d\n", totalCampaignsToday))
        else
            writeTargetText(TC.gray .. "No targets\n\n")
            writeTargetText(TC.gray .. "Use 'cp info' or 'gq check' to populate\n")
        end
    end
end

-------------------------------------------------------------------------------
-- Check if a target entry matches the current selected target
-- Mirrors target_matches_current_target() from the original
-------------------------------------------------------------------------------

function snd.gui.isCurrentTarget(target, index)
    local ct = snd.targets.current
    if snd.targets and snd.targets.scoped and target and target.activity then
        local scoped = snd.targets.scoped[target.activity]
        if scoped then
            ct = scoped
        end
    end
    if not ct then return false end
    if target.mob ~= ct.name then return false end
    if ct.activity and target.activity ~= ct.activity then return false end
    -- For room-based, also check room name
    if ct.roomName and ct.roomName ~= "" then
        if target.roomName ~= ct.roomName then return false end
    end
    return true
end

-------------------------------------------------------------------------------
-- Check if a target qualifies for express mode
-- Mirrors is_express_target() from the original
-------------------------------------------------------------------------------

function snd.gui.isExpressTarget(target)
    if not snd.config.express or not snd.config.express.enabled then return false end
    if not target.killCount then return false end
    return target.killCount >= (snd.config.express.minKillCount or 2)
end

-------------------------------------------------------------------------------
-- Button Click Handler
-------------------------------------------------------------------------------

local function isRightClick(button)
    if type(button) == "number" then
        return button == 2
    end
    if type(button) == "string" then
        return button:lower():find("right") ~= nil
    end
    if type(button) == "table" then
        local raw = button.button or button[1]
        if type(raw) == "number" then
            return raw == 2
        end
        if type(raw) == "string" then
            return raw:lower():find("right") ~= nil
        end
    end
    return false
end

function snd.gui.onButtonClick(btnId, _, button)
    local btn = nil
    for _, b in ipairs(actionButtons) do
        if b.id == btnId then
            btn = b
            break
        end
    end
    if not btn then return end

    -- Handle special commands that map to Lua functions
    local cmd = btn.cmd
    if isRightClick(button) and btn.rcmd then
        cmd = btn.rcmd
    end
    local function getContextTarget()
        local activeTab = snd.getActiveTab and snd.getActiveTab() or nil
        if snd.targets and snd.targets.scoped and activeTab and snd.targets.scoped[activeTab] then
            return snd.targets.scoped[activeTab]
        end
        return snd.targets and snd.targets.current or nil
    end

    if cmd == "snd_qs" then
        snd.gui.quickScan()
    elseif cmd == "snd_go" then
        if snd.commands and snd.commands.gotoTarget then
            snd.commands.gotoTarget()
        end
    elseif cmd == "snd_go_area" then
        local contextTarget = getContextTarget()
        if contextTarget then
            local areaKey = contextTarget.area or contextTarget.arid or ""
            if areaKey ~= "" then
                snd.commands.gotoArea(areaKey)
            else
                snd.utils.infoNote("Target has no area information")
            end
        else
            snd.utils.infoNote("No target selected")
        end
    elseif cmd == "snd_ref" then
        snd.gui.refreshTargets()
    elseif cmd == "snd_rel" then
        snd.gui.reloadTargets()
    elseif cmd == "xkill" then
        if snd.commands and snd.commands.xkill then
            snd.commands.xkill()
        end
    else
        expandAlias(cmd, false)
    end
end

--- Title bar right-click handler (opens context menu)
function snd.gui.onTitleRightClick()
    snd.gui.showContextMenu()
end

--- Noexp click handler
function snd.gui.onNoexpClick()
    if snd.config.anex and snd.config.anex.automatic then
        snd.config.anex.tnlCutoff = (snd.config.anex.tnlCutoff or 0) + 100
        if snd.config.anex.tnlCutoff > 9900 then
            snd.config.anex.tnlCutoff = 9900
        end
        if snd.gmcp and snd.gmcp.checkAutoNoexp then
            snd.gmcp.checkAutoNoexp()
        end
        snd.gui.updateNoexp()
    end
end

--- Noexp right-click handler
function snd.gui.onNoexpRightClick()
    if snd.config.anex and snd.config.anex.automatic then
        snd.config.anex.tnlCutoff = (snd.config.anex.tnlCutoff or 0) - 100
        if snd.config.anex.tnlCutoff < 0 then
            snd.config.anex.tnlCutoff = 0
        end
        if snd.gmcp and snd.gmcp.checkAutoNoexp then
            snd.gmcp.checkAutoNoexp()
        end
        snd.gui.updateNoexp()
    end
end

--- Unified noexp mouse handler (works even if right-click callback is unavailable)
function snd.gui.onNoexpMouse(...)
    if isRightButton(...) then
        snd.gui.onNoexpRightClick()
    else
        snd.gui.onNoexpClick()
    end
end
-------------------------------------------------------------------------------
-- Toggle Minimize / Maximize
-- Mirrors mouseup_drag hsMinimize from the original
-------------------------------------------------------------------------------

function snd.gui.toggleMinimize()
    if snd.gui.minimized then
        snd.gui.maximize()
    else
        snd.gui.minimize()
    end
end

function snd.gui.minimize()
    if not snd.gui.elements.main then return end
    snd.gui.minimized = true
    snd.gui.windowState = "min"

    -- Hide everything except title bar
    local keep = {main = true, border = true, titleBar = true, minBtn = true, questTimer = true}
    for name, el in pairs(snd.gui.elements) do
        if not keep[name] and type(el) == "table" and el.hide then
            pcall(function() el:hide() end)
        end
    end

    -- Collapse height
    snd.gui.elements.main:resize(snd.config.window.width or DEFAULT_WIDTH, TITLE_HEIGHT + 2)
    snd.gui.elements.minBtn:echo("▼")

    -- Also hide button sub-elements
    for _, el in pairs(snd.gui.elements.buttons or {}) do
        if el and el.hide then pcall(function() el:hide() end) end
    end
end

function snd.gui.maximize()
    if not snd.gui.elements.main then return end
    snd.gui.minimized = false
    snd.gui.windowState = "max"

    -- Restore height
    snd.gui.elements.main:resize(
        snd.config.window.width or DEFAULT_WIDTH,
        snd.config.window.height or DEFAULT_HEIGHT)

    -- Show everything
    for name, el in pairs(snd.gui.elements) do
        if type(el) == "table" and el.show then
            pcall(function() el:show() end)
        end
    end
    for _, el in pairs(snd.gui.elements.buttons or {}) do
        if el and el.show then pcall(function() el:show() end) end
    end

    snd.gui.elements.minBtn:echo("▬")
    snd.gui.refresh()
end

-------------------------------------------------------------------------------
-- Show / Hide / Toggle
-------------------------------------------------------------------------------

function snd.gui.show()
    if not snd.gui.elements.main then
        snd.gui.createWindow()
    end
    if snd.gui.elements.main then
        snd.gui.elements.main:show()
        snd.config.window.enabled = true
    else
        snd.utils.errorNote("Failed to create GUI window")
    end
end

function snd.gui.hide()
    if snd.gui.elements.main then
        snd.gui.elements.main:hide()
        snd.config.window.enabled = false
    end
end

function snd.gui.toggle()
    local isVisible = false
    if snd.gui.elements.main and snd.gui.elements.main.isVisible then
        local ok, visible = pcall(function()
            return snd.gui.elements.main:isVisible()
        end)
        isVisible = ok and visible or false
    end

    if snd.config.window.enabled and snd.gui.elements.main and isVisible then
        snd.gui.hide()
        snd.utils.infoNote("Window hidden. Type 'snd window' or 'xset win on' to show.")
    else
        snd.gui.show()
        if snd.gui.elements.main then
            snd.utils.infoNote("Window shown.")
        end
    end
end

-------------------------------------------------------------------------------
-- Resize (called by xset commands)
-------------------------------------------------------------------------------

function snd.gui.resize(width, height)
    width = math.max(width or DEFAULT_WIDTH, MIN_WIDTH)
    height = math.max(height or DEFAULT_HEIGHT, MIN_HEIGHT)
    snd.config.window.width = width
    snd.config.window.height = height
    if snd.gui.elements.main then
        snd.gui.elements.main:resize(width, height)
        snd.gui.refresh()
    end
end

function snd.gui.move(x, y)
    if snd.gui.elements.main then
        snd.gui.elements.main:move(x, y)
        snd.config.window.posX = x
        snd.config.window.posY = y
    end
end

-------------------------------------------------------------------------------
-- Context Menu (right-click on title bar)
-- Mirrors right_click_menu() from the original
-------------------------------------------------------------------------------

function snd.gui.showContextMenu()
    -- Mudlet doesn't have native popup menus like MUSHclient.
    -- We echo a clickable text menu to the main console instead.
    local divider = string.rep("─", 40)

    cecho("\n<DimGray>" .. divider .. "\n")
    cecho("<white> Search & Destroy Options\n")
    cecho("<DimGray>" .. divider .. "\n")

    cechoLink("<cyan> [Collapse Window]", function() snd.gui.minimize() end, "Minimize the S&D window", true)
    cecho("  ")
    cechoLink("<cyan> [Expand Window]", function() snd.gui.maximize() end, "Maximize the S&D window", true)
    cecho("\n")

    cechoLink("<cyan> [Bring to Front]", function()
        if snd.gui.elements.main and snd.gui.elements.main.raiseAll then
            snd.gui.elements.main:raiseAll()
        end
    end, "Bring window to front", true)
    cecho("  ")
    cechoLink("<cyan> [Send to Back]", function()
        if snd.gui.elements.main and snd.gui.elements.main.lowerAll then
            snd.gui.elements.main:lowerAll()
        end
    end, "Send window to back", true)
    cecho("\n")

    cechoLink("<cyan> [Reset Position]", function()
        snd.gui.move(50, 50)
        snd.gui.resize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
        cecho("\n<green>Window position reset.\n")
    end, "Reset window position and size", true)
    cecho("\n")

    cechoLink("<cyan> [Toggle Debug]", function()
        snd.config.debugMode = not snd.config.debugMode
        cecho(string.format("\n<green>Debug mode: %s\n", snd.config.debugMode and "ON" or "OFF"))
    end, "Toggle debug mode", true)
    cecho("  ")
    cechoLink("<cyan> [Help]", function() expandAlias("xhelp", false) end, "Show help", true)
    cecho("\n")

    cecho("<DimGray>" .. divider .. "\n")
end

-------------------------------------------------------------------------------
-- Cleanup
-------------------------------------------------------------------------------

function snd.gui.cleanup()
    if snd.gui.elements.main then
        -- Save position
        snd.config.window.posX = snd.gui.elements.main.get_x and snd.gui.elements.main:get_x() or 0
        snd.config.window.posY = snd.gui.elements.main.get_y and snd.gui.elements.main:get_y() or 0
    end

    snd.gui.destroy()
end

-------------------------------------------------------------------------------
-- Periodic Refresh Timer
-- Keeps the quest timer and target list up to date
-------------------------------------------------------------------------------

if snd.gui.refreshTimer then
    killTimer(snd.gui.refreshTimer)
    snd.gui.refreshTimer = nil
end

snd.gui.refreshTimer = tempTimer(2, function()
    if snd.gui.initialized then
        snd.gui.refresh()
    end
end, true)

-- Also set up a timer for the quest countdown (every minute)
if snd.gui.questTimerTick then
    killTimer(snd.gui.questTimerTick)
    snd.gui.questTimerTick = nil
end

snd.gui.questTimerTick = tempTimer(60, function()
    if snd.gui.initialized then
        snd.quest.updateCooldownRemaining()
        snd.gui.updateQuestTimer()
        snd.gui.applyTabStyles()
    end
end, true)

-------------------------------------------------------------------------------
-- Module loaded
-------------------------------------------------------------------------------
-- (silent load, no output)
