mm = mm or {}

if type(mm.explore_window) == "table" and type(mm.explore_window.shutdown) == "function" then
  pcall(mm.explore_window.shutdown, true)
end

mm.explore_window = {
  version = "1.0.0",
  handlers = {},
  ui = {},
}

local window = mm.explore_window
local STATE_FILE = "mmapper_explore_window.lua"
local CONTAINER_NAME = "MMExploreWindow"

local defaults = {
  schema = 1,
  enabled = true,
  x = "68%",
  y = "36%",
  width = 310,
  height = 112,
  font_size = 11,
}

local colors = {
  frame = "#050608",
  background = "#10141a",
  panel = "#171d26",
  border = "#49566a",
  text = "#e9edf2",
  muted = "#9da7b5",
  accent = "#65c8ff",
  warning = "#f2c14e",
  stop = "#e06969",
  disabled = "#343b45",
}

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function clamp(value, minimum, maximum)
  value = tonumber(value) or minimum
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function html_escape(value)
  local text = tostring(value or "")
  text = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  text = text:gsub('"', "&quot;"):gsub("'", "&#39;")
  return text
end

local function serialize(value)
  local value_type = type(value)
  if value_type == "number" or value_type == "boolean" then return tostring(value) end
  if value_type == "string" then return string.format("%q", value) end
  if value_type ~= "table" then return "nil" end

  local parts = { "{" }
  for key, item in pairs(value) do
    local encoded_key
    if type(key) == "string" and key:match("^[%a_][%w_]*$") then
      encoded_key = key
    else
      encoded_key = "[" .. serialize(key) .. "]"
    end
    parts[#parts + 1] = encoded_key .. "=" .. serialize(item) .. ","
  end
  parts[#parts + 1] = "}"
  return table.concat(parts)
end

local function merge_defaults(state)
  state = type(state) == "table" and state or {}
  for key, value in pairs(defaults) do
    if state[key] == nil then state[key] = value end
  end
  if type(state.enabled) ~= "boolean" then state.enabled = defaults.enabled end
  state.font_size = math.floor(clamp(state.font_size, 6, 32))
  return state
end

local function minimum_size()
  local font = tonumber(window.state and window.state.font_size) or defaults.font_size
  return math.max(280, 120 + font * 14), math.max(108, 58 + font * 3.7)
end

local function load_state()
  local state
  if type(mm.load_persistence_chunk) == "function" then
    local chunk = mm.load_persistence_chunk(STATE_FILE)
    if chunk then
      local ok, loaded = pcall(chunk)
      if ok and type(loaded) == "table" then state = loaded end
    end
  end
  window.state = merge_defaults(state)
end

local function capture_geometry()
  local container = window.ui and window.ui.container
  if not container or not window.state then return end
  local getters = {
    x = "get_x",
    y = "get_y",
    width = "get_width",
    height = "get_height",
  }
  for key, getter in pairs(getters) do
    if type(container[getter]) == "function" then
      local ok, value = pcall(container[getter], container)
      if ok and value ~= nil then window.state[key] = value end
    end
  end
end

function window.save_state()
  if not window.state or type(mm.open_persistence_file) ~= "function" then return false end
  capture_geometry()
  local file = mm.open_persistence_file(STATE_FILE, "wb")
  if not file then return false, "unable to open Explore window settings for writing" end
  file:write("return " .. serialize(window.state))
  file:close()
  return true
end

local function destroy_object(object)
  if not object then return end
  if type(object.hide) == "function" then pcall(object.hide, object) end
  if type(object.delete) == "function" then pcall(object.delete, object) end
end

function window.destroy_ui()
  destroy_object(window.ui.primary)
  destroy_object(window.ui.stop)
  destroy_object(window.ui.status)
  destroy_object(window.ui.header)
  destroy_object(window.ui.container)
  window.ui = {}
end

local function style(background, border, foreground, extra)
  return string.format(
    "background-color: %s; border: 1px solid %s; color: %s; padding: 2px; font-size: %dpt; %s",
    background or "transparent",
    border or "transparent",
    foreground or colors.text,
    tonumber(window.state and window.state.font_size) or defaults.font_size,
    extra or ""
  )
end

local function set_label(label, text, color, alignment)
  if label and type(label.echo) == "function" then
    pcall(label.echo, label, html_escape(text), color or colors.text, alignment or "c")
  end
end

local function set_callback(label, callback, tooltip, enabled)
  if not label then return end
  if type(label.setClickCallback) == "function" then
    pcall(label.setClickCallback, label, enabled and callback or "mm.explore_window.inactive_click")
  end
  if type(label.setToolTip) == "function" then
    pcall(label.setToolTip, label, tooltip or "")
  end
  if type(label.setCursor) == "function" then
    pcall(label.setCursor, label, enabled and "PointingHand" or "Arrow")
  end
end

local function enforce_minimum_size()
  local container = window.ui and window.ui.container
  if not container then return end
  local minimum_width, minimum_height = minimum_size()
  local width, height
  if type(container.get_width) == "function" then
    local ok, value = pcall(container.get_width, container)
    if ok then width = tonumber(value) end
  end
  if type(container.get_height) == "function" then
    local ok, value = pcall(container.get_height, container)
    if ok then height = tonumber(value) end
  end
  width = math.max(tonumber(width) or tonumber(window.state.width) or minimum_width, minimum_width)
  height = math.max(tonumber(height) or tonumber(window.state.height) or minimum_height, minimum_height)
  if type(container.resize) == "function" then pcall(container.resize, container, width, height) end
  window.state.width = width
  window.state.height = height
end

local function ensure_ui()
  if window.ui.container then return true end
  if not Geyser then return false, "Geyser is unavailable; the Explore window cannot be created" end

  local minimum_width, minimum_height = minimum_size()
  local width = math.max(tonumber(window.state.width) or minimum_width, minimum_width)
  local height = math.max(tonumber(window.state.height) or minimum_height, minimum_height)
  local container
  if Adjustable and Adjustable.Container and type(Adjustable.Container.new) == "function" then
    local ok, result = pcall(function()
      return Adjustable.Container:new({
        name = CONTAINER_NAME,
        x = window.state.x,
        y = window.state.y,
        width = width,
        height = height,
        autoLoad = false,
        autoSave = false,
        padding = 0,
        adjLabelstyle = "border: 1px solid " .. colors.frame .. "; background-color: " .. colors.frame .. ";",
        buttonstyle = "",
        lockStyle = "border: 0px;",
        titleText = "",
      })
    end)
    if ok then container = result end
  end
  if not container then
    container = Geyser.Container:new({
      name = CONTAINER_NAME,
      x = window.state.x,
      y = window.state.y,
      width = width,
      height = height,
    })
    if type(container.enableDrag) == "function" then pcall(container.enableDrag, container) end
  end
  window.ui.container = container
  if type(container.setPadding) == "function" then pcall(container.setPadding, container, 0) end

  window.ui.header = Geyser.Label:new({
    name = "MMExploreWindowHeader",
    x = 0,
    y = 0,
    width = "100%",
    height = 25,
    clickthrough = true,
  }, container)
  window.ui.status = Geyser.Label:new({ name = "MMExploreWindowStatus", x = 0, y = 25, width = "100%", height = 30 }, container)
  window.ui.primary = Geyser.Label:new({ name = "MMExploreWindowPrimary", x = 6, y = 59, width = "70%-9px", height = 34 }, container)
  window.ui.stop = Geyser.Label:new({ name = "MMExploreWindowStop", x = "70%+3px", y = 59, width = "30%-9px", height = 34 }, container)
  set_callback(window.ui.stop, "mm.explore_window.stop_click", "Stop Explore", true)

  if type(container.newCustomItem) == "function" then
    pcall(container.newCustomItem, container, "Disable Explore window", function() window.command("off") end)
  end
  enforce_minimum_size()
  return true
end

local function hide_ui()
  capture_geometry()
  if window.ui and window.ui.container and type(window.ui.container.hide) == "function" then
    pcall(window.ui.container.hide, window.ui.container)
  end
end

local function view_text(view)
  local phase = tostring(view.phase or "stopped")
  if phase == "list_ready" then
    return "List ready — " .. tostring(view.list_count or 0) .. " exits", "Choose index", true, colors.accent
  elseif phase == "travelling" then
    return "Travelling to " .. tostring(view.expected_source or "?") .. " — 10s stall timeout", "Travelling...", false, colors.accent
  elseif phase == "ready" then
    return "Next: " .. tostring(view.direction or "?"), "Next " .. tostring(view.direction or ""), true, colors.accent
  elseif phase == "combat" then
    return "Next: " .. tostring(view.direction or "?") .. " — combat", "Next " .. tostring(view.direction or ""), true, colors.warning
  elseif phase == "off_source" then
    return "Off-source — room " .. tostring(view.current_room or "?"), "xrt " .. tostring(view.expected_source or "?"), true, colors.warning
  elseif phase == "choose" then
    return "Next: " .. tostring(view.direction or "?") .. " — first of " .. tostring(view.frontier_count or 0),
      "Next " .. tostring(view.direction or ""), true, colors.accent
  elseif phase == "blocked" then
    local detail = view.direction and ("Blocked: " .. tostring(view.direction)) or "Explore needs a new list"
    return detail, "Unmapped here", true, colors.warning
  elseif phase == "crossing" then
    return "Moving " .. tostring(view.direction or "?") .. " — 10s timeout", "Moving...", false, colors.accent
  elseif phase == "settling" then
    return "Reading the new room", "Waiting...", false, colors.muted
  end
  return "Explore inactive", "Next", false, colors.muted
end

function window.render()
  if not window.state then load_state() end
  local view = mm.explore and mm.explore.get_view and mm.explore.get_view() or { phase = "stopped" }
  if not window.state.enabled or view.phase == "stopped" then
    hide_ui()
    return true
  end

  local ok, err = ensure_ui()
  if not ok then return false, err end
  enforce_minimum_size()

  local font = tonumber(window.state.font_size) or defaults.font_size
  local header_height = math.max(24, font + 14)
  local status_height = math.max(28, font * 1.7 + 10)
  local button_height = math.max(30, font * 1.9 + 10)
  local button_top = header_height + status_height + 4

  window.ui.header:move(0, 0)
  window.ui.header:resize("100%", header_height)
  window.ui.status:move(0, header_height)
  window.ui.status:resize("100%", status_height)
  window.ui.primary:move(6, button_top)
  window.ui.primary:resize("70%-9px", button_height)
  window.ui.stop:move("70%+3px", button_top)
  window.ui.stop:resize("30%-9px", button_height)

  window.ui.header:setStyleSheet(style(colors.panel, colors.border, colors.text, "font-weight: bold;"))
  window.ui.status:setStyleSheet(style(colors.background, colors.border, colors.muted, ""))
  window.ui.stop:setStyleSheet(style("#57262d", "#d96b75", "#fff0f1", "font-weight: bold; border-radius: 5px; padding: 3px;"))
  set_label(window.ui.header, "MAPPER EXPLORE", colors.text, "c")
  set_label(window.ui.stop, "Stop", "#fff0f1", "c")

  local status, primary, enabled, accent = view_text(view)
  set_label(window.ui.status, status, accent, "c")
  set_label(window.ui.primary, primary, enabled and colors.text or colors.muted, "c")
  window.ui.primary:setStyleSheet(style(
    enabled and "#205570" or colors.disabled,
    enabled and accent or colors.border,
    enabled and colors.text or colors.muted,
    "font-weight: bold; border-radius: 5px; padding: 3px;"
  ))
  local primary_tooltip = view.phase == "list_ready" and "Explore index 1" or primary
  set_callback(window.ui.primary, "mm.explore_window.primary_click", primary_tooltip, enabled)

  if type(window.ui.container.show) == "function" then pcall(window.ui.container.show, window.ui.container) end
  return true
end

function window.primary_click()
  if not (mm.explore and mm.explore.get_view) then return end
  local view = mm.explore.get_view()
  if view.phase == "list_ready" and mm.explore.select then
    local ok, err = mm.explore.select(1)
    if not ok and err and mm.warn then mm.warn(err) end
    return
  end
  if view.phase == "off_source" and tostring(view.expected_source or "") ~= "" then
    local command = "xrt " .. tostring(view.expected_source)
    if type(expandAlias) == "function" then expandAlias(command) end
    return
  end
  if view.phase == "blocked" and mm.explore.refresh_here then
    local ok, err = mm.explore.refresh_here()
    if not ok and err and mm.warn then mm.warn(err) end
    return
  end
  if view.phase == "ready" or view.phase == "combat" or view.phase == "choose" then
    local ok, err = mm.explore.next()
    if not ok and err and mm.warn then mm.warn(err) end
  end
end

function window.inactive_click()
end

function window.stop_click()
  if not (mm.explore and mm.explore.stop) then return false end
  local ok, result = pcall(mm.explore.stop, false)
  if not ok then
    if mm.warn then mm.warn("Explore Stop failed: " .. tostring(result)) end
    return false
  end
  hide_ui()
  return result == true
end

function window.on_changed()
  local ok, err = window.render()
  if not ok and mm.debug then mm.debug("Explore window render failed: " .. tostring(err)) end
end

function window.on_reposition_finish(_, container_name, width, height, x, y)
  if tostring(container_name or "") ~= CONTAINER_NAME or not window.state then return end
  if tonumber(x) then window.state.x = tonumber(x) end
  if tonumber(y) then window.state.y = tonumber(y) end
  if tonumber(width) then window.state.width = tonumber(width) end
  if tonumber(height) then window.state.height = tonumber(height) end
  enforce_minimum_size()
  window.save_state()
  window.render()
end

function window.command(raw_command)
  if not window.state then load_state() end
  local command = trim(raw_command):lower()
  if command == "" or command == "status" then
    if mm.note then
      mm.note(string.format(
        "Explore window is %s; font size %d.",
        window.state.enabled and "on" or "off",
        tonumber(window.state.font_size) or defaults.font_size
      ))
    end
    return true
  elseif command == "on" then
    window.state.enabled = true
    window.save_state()
    local ok, err = window.render()
    if not ok then return false, err end
    if mm.note then mm.note("Explore window enabled.") end
    return true
  elseif command == "off" then
    window.state.enabled = false
    hide_ui()
    window.save_state()
    if mm.note then mm.note("Explore window disabled.") end
    return true
  elseif command == "toggle" then
    return window.command(window.state.enabled and "off" or "on")
  end

  local size = command:match("^fontsize%s+(%d+)$")
  if size then
    size = tonumber(size)
    if not size or size < 6 or size > 32 then
      return false, "Usage: mapper explore window fontsize <6-32>"
    end
    window.state.font_size = size
    if window.ui and window.ui.container then enforce_minimum_size() end
    window.save_state()
    local ok, err = window.render()
    if not ok then return false, err end
    if mm.note then mm.note("Explore window font size set to " .. tostring(size) .. ".") end
    return true
  end

  return false, "Usage: mapper explore window <on|off|toggle|status|fontsize 6-32>"
end

function window.shutdown(save)
  if save and window.state then pcall(window.save_state) end
  for _, handler_id in pairs(window.handlers or {}) do
    if handler_id and type(killAnonymousEventHandler) == "function" then
      pcall(killAnonymousEventHandler, handler_id)
    end
  end
  window.handlers = {}
  window.destroy_ui()
end

function window.initialize()
  load_state()
  if mm.explore then mm.explore.window = window end
  if type(registerAnonymousEventHandler) == "function" then
    window.handlers.changed = registerAnonymousEventHandler("mm.explore.changed", "mm.explore_window.on_changed")
    window.handlers.reposition = registerAnonymousEventHandler("AdjustableContainerRepositionFinish", "mm.explore_window.on_reposition_finish")
    window.handlers.exit = registerAnonymousEventHandler("sysExitEvent", function() window.shutdown(true) end)
  end
  window.render()
  return true
end

if mm.explore then mm.explore.window = window end
