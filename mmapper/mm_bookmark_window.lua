mm = mm or {}

if type(mm.bookmark_window) == "table" and type(mm.bookmark_window.shutdown) == "function" then
  pcall(mm.bookmark_window.shutdown, true, true)
end

mm.bookmark_window = {
  version = "1.1.2",
  ui = {},
  handlers = {},
  rows = {},
  display_area = "",
  display_error = nil,
  processed_area_key = nil,
}

local window = mm.bookmark_window
local STATE_FILE = "mmapper_bookmark_window.lua"
local CONTAINER_NAME = "MMBookmarkWindow"
local HEADER_HEIGHT = 25
local SUBHEADER_HEIGHT = 23
local COMPACT_HEADER_HEIGHT = 25
local BODY_GAP = 2
local RESIZE_MARGIN = 10

local defaults = {
  schema = 1,
  x = "2%",
  y = "2%",
  width = "28%",
  height = "45%",
  visible = false,
  mode = "auto",
  manual_area = "",
  font_size = 9,
  detailed_title = true,
}

local colors = {
  frame = "#000000",
  background = "#101216",
  panel = "#181b21",
  panel_permanent = "#1d2630",
  border = "#4a4f59",
  text = "#e6e6e6",
  muted = "#8b9099",
  accent = "#64d8ff",
  permanent = "#f0a500",
}

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function clean(value)
  local text = mm.strip_ansi and mm.strip_ansi(value) or tostring(value or "")
  return trim(text:gsub("[\r\n\t]+", " "))
end

local function normalize_area(value)
  return clean(value):lower()
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
  if type(state.visible) ~= "boolean" then state.visible = defaults.visible end
  if type(state.detailed_title) ~= "boolean" then state.detailed_title = defaults.detailed_title end
  if state.mode ~= "auto" and state.mode ~= "manual" then state.mode = defaults.mode end
  state.manual_area = clean(state.manual_area)
  state.font_size = clamp(state.font_size, 7, 24)
  return state
end

local function body_top()
  if window.state and window.state.detailed_title == false then
    return COMPACT_HEADER_HEIGHT + BODY_GAP
  end
  return HEADER_HEIGHT + SUBHEADER_HEIGHT + BODY_GAP
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
  if not file then return false, "unable to open bookmark window settings for writing" end
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
  if not window.ui then return end
  for _, card in ipairs(window.ui.cards or {}) do
    destroy_object(card.container)
  end
  for _, section in ipairs(window.ui.sections or {}) do
    destroy_object(section)
  end
  destroy_object(window.ui.empty)
  destroy_object(window.ui.scroll)
  destroy_object(window.ui.subheader)
  destroy_object(window.ui.header)
  destroy_object(window.ui.container)
  window.ui = {}
end

function window.shutdown(save, destroy)
  if save and window.state then pcall(window.save_state) end
  for _, handler_id in pairs(window.handlers or {}) do
    if handler_id and type(killAnonymousEventHandler) == "function" then
      pcall(killAnonymousEventHandler, handler_id)
    end
  end
  window.handlers = {}
  if destroy then
    window.destroy_ui()
  elseif window.ui and window.ui.container and type(window.ui.container.hide) == "function" then
    pcall(window.ui.container.hide, window.ui.container)
  end
end

local function label_style(background, border, foreground, extra)
  return string.format(
    "background-color: %s; border: 1px solid %s; color: %s; padding: 2px; font-size: %dpt; %s",
    background or "transparent",
    border or "transparent",
    foreground or colors.text,
    tonumber(window.state and window.state.font_size) or defaults.font_size,
    extra or ""
  )
end

local function set_label(label, text, foreground, alignment)
  if not label or type(label.echo) ~= "function" then return end
  pcall(label.echo, label, html_escape(text), foreground or colors.text, alignment or "l")
end

local function set_clickable(label, room_uid, tooltip)
  if not label then return end
  if type(label.setClickCallback) == "function" then
    pcall(label.setClickCallback, label, "mm.bookmark_window.card_click", tostring(room_uid or ""))
  end
  if type(label.setToolTip) == "function" then pcall(label.setToolTip, label, tooltip) end
  if type(label.setCursor) == "function" then pcall(label.setCursor, label, "PointingHand") end
end

local function area_display_name(area)
  local key = clean(area)
  if key == "" then return "Unknown area" end
  if mm.area_references and type(mm.area_references.get) == "function" then
    local reference = mm.area_references.get(key)
    if reference and clean(reference.name) ~= "" then return clean(reference.name) end
  end
  return key
end

local function current_area_from_info(info)
  info = type(info) == "table" and info or (mm.get_room_info and mm.get_room_info() or {})
  return clean(info.zone or info.area)
end

local function current_location_title()
  local info = mm.get_room_info and mm.get_room_info() or {}
  local area_name = mm.get_area_display_name and mm.get_area_display_name(info) or current_area_from_info(info)
  local room_name = clean(info.name)
  local room_id = clean(info.num or info.id)
  if mm.ui and type(mm.ui.format_location_title) == "function" then
    return mm.ui.format_location_title(area_name, room_name, room_id)
  end
  if room_id ~= "" then room_name = room_name .. " (" .. room_id .. ")" end
  if clean(area_name) ~= "" then return clean(area_name) .. " / " .. room_name end
  return room_name ~= "" and room_name or "Bookmark Window"
end

local function body_parent()
  return window.ui.scroll or window.ui.container
end

local function make_section(index)
  local label = Geyser.Label:new({
    name = "MMBookmarkWindowSection" .. tostring(index),
    x = 6,
    y = 0,
    width = "100%-18px",
    height = 22,
  }, body_parent())
  label:setStyleSheet(label_style(colors.background, "transparent", colors.muted, "font-weight: bold;"))
  window.ui.sections[index] = label
  return label
end

local function make_card(index)
  local prefix = "MMBookmarkWindowCard" .. tostring(index)
  local card = {}
  card.container = Geyser.Container:new({
    name = prefix,
    x = 6,
    y = 0,
    width = "100%-18px",
    height = 50,
  }, body_parent())
  card.background = Geyser.Label:new({ name = prefix .. "Background", x = 0, y = 0, width = "100%", height = "100%" }, card.container)
  card.name = Geyser.Label:new({ name = prefix .. "Name", x = 5, y = 3, width = "100%-58px", height = 21 }, card.container)
  card.badge = Geyser.Label:new({ name = prefix .. "Badge", x = "100%-52px", y = 3, width = 47, height = 19 }, card.container)
  card.meta = Geyser.Label:new({ name = prefix .. "Meta", x = 5, y = 25, width = "100%-10px", height = 20 }, card.container)
  window.ui.cards[index] = card
  return card
end

local function ensure_ui()
  if not Geyser then return false, "Geyser is unavailable; the bookmark window cannot be created" end
  if window.ui.container then return true end

  local container
  if Adjustable and Adjustable.Container and type(Adjustable.Container.new) == "function" then
    local ok, result = pcall(function()
      return Adjustable.Container:new({
        name = CONTAINER_NAME,
        x = window.state.x,
        y = window.state.y,
        width = window.state.width,
        height = window.state.height,
        autoLoad = false,
        autoSave = false,
        padding = 0,
        adjLabelstyle = "border: 1px solid " .. colors.frame .. "; background-color: " .. colors.frame .. ";",
        buttonstyle = "",
        lockStyle = "border: 0px;",
        titleText = "",
        titleTxtColor = "white",
      })
    end)
    if ok then container = result end
  end
  if not container then
    container = Geyser.Container:new({
      name = CONTAINER_NAME,
      x = window.state.x,
      y = window.state.y,
      width = window.state.width,
      height = window.state.height,
    })
    if container.enableDrag then pcall(container.enableDrag, container) end
  end
  window.ui.container = container
  if type(container.setPadding) == "function" then pcall(container.setPadding, container, 0) end

  window.ui.header = Geyser.Label:new({
    name = "MMBookmarkWindowHeader",
    x = 0,
    y = 0,
    width = "100%",
    height = HEADER_HEIGHT,
    clickthrough = true,
  }, container)
  window.ui.subheader = Geyser.Label:new({
    name = "MMBookmarkWindowSubheader",
    x = 0,
    y = HEADER_HEIGHT,
    width = "100%",
    height = SUBHEADER_HEIGHT,
    clickthrough = true,
  }, container)
  window.ui.header:setStyleSheet(label_style(colors.panel, colors.border, colors.text, "font-weight: bold;"))
  window.ui.subheader:setStyleSheet(label_style(colors.background, colors.border, colors.muted, ""))

  local list_top = body_top()
  if Geyser.ScrollBox and type(Geyser.ScrollBox.new) == "function" then
    window.ui.scroll = Geyser.ScrollBox:new({
      name = "MMBookmarkWindowScroll",
      x = RESIZE_MARGIN,
      y = list_top,
      width = "100%-" .. tostring(RESIZE_MARGIN * 2) .. "px",
      height = "100%-" .. tostring(list_top + RESIZE_MARGIN) .. "px",
    }, container)
  else
    window.ui.scroll = Geyser.Container:new({
      name = "MMBookmarkWindowBody",
      x = RESIZE_MARGIN,
      y = list_top,
      width = "100%-" .. tostring(RESIZE_MARGIN * 2) .. "px",
      height = "100%-" .. tostring(list_top + RESIZE_MARGIN) .. "px",
    }, container)
  end
  window.ui.sections = {}
  window.ui.cards = {}
  window.ui.empty = Geyser.Label:new({
    name = "MMBookmarkWindowEmpty",
    x = 8,
    y = 8,
    width = "100%-20px",
    height = 42,
  }, body_parent())
  window.ui.empty:setStyleSheet(label_style(colors.background, "transparent", colors.muted, ""))

  if type(container.newCustomItem) == "function" then
    pcall(container.newCustomItem, container, "Auto area mode", function() window.command("auto") end)
    pcall(container.newCustomItem, container, "Refresh bookmarks", function() window.command("refresh") end)
    pcall(container.newCustomItem, container, "Toggle detailed title", function() window.command("title toggle") end)
    pcall(container.newCustomItem, container, "Hide bookmark window", function() window.command("hide") end)
  end
  return true
end

local function split_rows()
  local permanent, local_rows = {}, {}
  for _, row in ipairs(window.rows or {}) do
    if tonumber(row.is_permanent) and tonumber(row.is_permanent) ~= 0 then
      permanent[#permanent + 1] = row
    else
      local_rows[#local_rows + 1] = row
    end
  end
  return permanent, local_rows
end

local function render_card(card, row, y, height, permanent)
  card.container:show()
  card.container:move(6, y)
  card.container:resize("100%-18px", height)
  card.background:setStyleSheet(label_style(
    permanent and colors.panel_permanent or colors.panel,
    colors.border,
    colors.text,
    "border-radius: 3px;"
  ))
  card.name:setStyleSheet(label_style("transparent", "transparent", colors.text, "font-weight: bold;"))
  card.meta:setStyleSheet(label_style("transparent", "transparent", colors.muted, ""))

  local room_uid = clean(row.room_uid)
  local label = clean(row.label)
  if label == "" then label = clean(row.room_name) end
  if label == "" then label = "Room " .. room_uid end
  local room_name = clean(row.room_name)
  if room_name == "" then room_name = "Unknown room" end
  local meta = string.format("%s (%s)", room_name, room_uid)
  if permanent then meta = area_display_name(row.area) .. "  •  " .. meta end

  card.name:move(5, 3)
  card.name:resize(permanent and "100%-58px" or "100%-10px", 21)
  card.meta:move(5, 25)
  card.meta:resize("100%-10px", math.max(18, height - 29))
  set_label(card.name, label, colors.text, "l")
  set_label(card.meta, meta, colors.muted, "l")

  if permanent then
    card.badge:show()
    card.badge:setStyleSheet(label_style("#3a2e12", colors.permanent, colors.permanent, "font-weight: bold; border-radius: 2px;"))
    set_label(card.badge, "PIN", colors.permanent, "c")
  else
    card.badge:hide()
  end

  local tooltip = string.format("Go to %s — room %s", label, room_uid)
  set_clickable(card.background, room_uid, tooltip)
  set_clickable(card.name, room_uid, tooltip)
  set_clickable(card.meta, room_uid, tooltip)
  set_clickable(card.badge, room_uid, tooltip)
end

local function set_header_text(permanent_count, local_count)
  if not window.ui.header or not window.ui.subheader then return end
  if window.state.detailed_title == false then
    window.ui.header:hide()
    window.ui.subheader:show()
    window.ui.subheader:move(0, 0)
    window.ui.subheader:resize("100%", COMPACT_HEADER_HEIGHT)
    window.ui.subheader:setStyleSheet(label_style(colors.panel, colors.frame, colors.text, "font-weight: bold;"))
    set_label(window.ui.subheader, "Bookmarks", colors.text, "c")
    return
  end

  window.ui.header:show()
  window.ui.subheader:show()
  window.ui.header:move(0, 0)
  window.ui.header:resize("100%", HEADER_HEIGHT)
  window.ui.subheader:move(0, HEADER_HEIGHT)
  window.ui.subheader:resize("100%", SUBHEADER_HEIGHT)
  window.ui.header:setStyleSheet(label_style(colors.panel, colors.border, colors.text, "font-weight: bold;"))
  window.ui.subheader:setStyleSheet(label_style(colors.background, colors.border, colors.muted, ""))
  set_label(window.ui.header, current_location_title(), colors.text, "l")
  local mode = (window.state.mode or "auto"):upper()
  local shown = window.display_area ~= "" and area_display_name(window.display_area) or "No area"
  local status
  if window.display_error then
    status = string.format("%s  •  %s", mode, window.display_error)
  else
    status = string.format(
      "%s  •  %s  •  %d pinned + %d local",
      mode,
      shown,
      permanent_count or 0,
      local_count or 0
    )
  end
  set_label(window.ui.subheader, status, window.display_error and colors.permanent or colors.muted, "l")
end

local function set_adjustable_controls_visible(visible)
  local container = window.ui and window.ui.container
  if not container then return end
  for _, control in ipairs({ container.minimizeLabel, container.exitLabel }) do
    local method = control and (visible and control.show or control.hide)
    if type(method) == "function" then pcall(method, control) end
  end
end

function window.render()
  if not window.state or not window.state.visible then return true end
  local ok, err = ensure_ui()
  if not ok then return false, err end

  window.ui.empty:setStyleSheet(label_style(colors.background, "transparent", colors.muted, ""))

  local permanent, local_rows = split_rows()
  set_header_text(#permanent, #local_rows)
  local card_height = math.max(48, math.floor(window.state.font_size * 4.8))
  local y = 5
  local section_index = 0
  local card_index = 0

  local function render_section(title, rows, permanent_section)
    if #rows == 0 then return end
    section_index = section_index + 1
    local section = window.ui.sections[section_index] or make_section(section_index)
    section:show()
    section:move(6, y)
    section:resize("100%-18px", 22)
    section:setStyleSheet(label_style(colors.background, "transparent", permanent_section and colors.permanent or colors.accent, "font-weight: bold;"))
    set_label(section, title, permanent_section and colors.permanent or colors.accent, "l")
    y = y + 23
    for _, row in ipairs(rows) do
      card_index = card_index + 1
      local card = window.ui.cards[card_index] or make_card(card_index)
      render_card(card, row, y, card_height, permanent_section)
      y = y + card_height + 4
    end
    y = y + 2
  end

  render_section("PINNED", permanent, true)
  render_section("AREA — " .. area_display_name(window.display_area), local_rows, false)

  for index = section_index + 1, #(window.ui.sections or {}) do window.ui.sections[index]:hide() end
  for index = card_index + 1, #(window.ui.cards or {}) do window.ui.cards[index].container:hide() end

  if card_index == 0 then
    window.ui.empty:show()
    local message = window.display_error or "No bookmarks to show for this area."
    set_label(window.ui.empty, message, window.display_error and colors.permanent or colors.muted, "l")
  else
    window.ui.empty:hide()
  end

  local list_top = body_top()
  if window.ui.scroll and type(window.ui.scroll.move) == "function" then
    pcall(window.ui.scroll.move, window.ui.scroll, RESIZE_MARGIN, list_top)
  end
  if window.ui.scroll and type(window.ui.scroll.resize) == "function" then
    pcall(
      window.ui.scroll.resize,
      window.ui.scroll,
      "100%-" .. tostring(RESIZE_MARGIN * 2) .. "px",
      "100%-" .. tostring(list_top + RESIZE_MARGIN) .. "px"
    )
  end
  if type(window.ui.container.show) == "function" then pcall(window.ui.container.show, window.ui.container) end
  set_adjustable_controls_visible(window.state.detailed_title ~= false)
  return true
end

function window.update_location_title()
  if not window.state or not window.state.visible or not window.ui.header then return end
  local permanent, local_rows = split_rows()
  set_header_text(#permanent, #local_rows)
end

local function automatic_area()
  local info = mm.get_room_info and mm.get_room_info() or nil
  local area = current_area_from_info(info)
  if area ~= "" then return area end
  if mm.bookmarks and type(mm.bookmarks.current_area) == "function" then
    return mm.bookmarks.current_area()
  end
  return nil, "current area is unknown; try LOOK first"
end

function window.refresh_area(area, quiet)
  area = clean(area)
  if area == "" then return false, "bookmark window area is unknown" end
  if not (mm.bookmarks and type(mm.bookmarks.window_rows) == "function") then
    return false, "bookmark window data module is unavailable"
  end

  local rows, err = mm.bookmarks.window_rows(area)
  if not rows then
    window.rows = {}
    window.display_area = area
    window.display_error = "Refresh failed: " .. tostring(err)
    window.render()
    if not quiet and mm.warn then mm.warn(window.display_error) end
    return false, err
  end

  window.rows = rows
  window.display_area = area
  window.display_error = nil
  window.render()
  return true
end

function window.refresh(quiet)
  local area, err
  if window.state.mode == "manual" then
    area = clean(window.state.manual_area)
    if area == "" then err = "manual bookmark area is not set" end
  else
    area, err = automatic_area()
  end
  if not area then return false, err end
  if window.state.mode == "auto" then window.processed_area_key = normalize_area(area) end
  return window.refresh_area(area, quiet)
end

function window.on_room_changed(_, room_id, room_area)
  window.update_location_title()
  if not window.state or not window.state.visible or window.state.mode ~= "auto" then return end

  local area = clean(room_area)
  if area == "" then area = current_area_from_info(mm.get_room_info and mm.get_room_info() or nil) end
  local area_key = normalize_area(area)
  if area_key == "" or area_key == window.processed_area_key then return end

  window.processed_area_key = area_key
  window.refresh_area(area, true)
end

function window.on_bookmarks_changed()
  if not window.state or not window.state.visible then return end
  window.refresh(true)
end

function window.on_resize()
  if window.state and window.state.visible then window.render() end
end

function window.on_reposition_finish(_, container_name, width, height, x, y)
  if tostring(container_name or "") ~= CONTAINER_NAME or not window.state then return end
  if tonumber(x) then window.state.x = tonumber(x) end
  if tonumber(y) then window.state.y = tonumber(y) end
  if tonumber(width) then window.state.width = tonumber(width) end
  if tonumber(height) then window.state.height = tonumber(height) end
  window.save_state()
  window.render()
end

function window.card_click(room_uid)
  if mm.bookmarks and type(mm.bookmarks.go_room) == "function" then
    mm.bookmarks.go_room(room_uid)
  elseif mm.goto_room then
    local ok, err = mm.goto_room(room_uid)
    if not ok and mm.warn then mm.warn(err) end
  end
end

function window.show()
  local ok, err = ensure_ui()
  if not ok then return false, err end
  window.state.visible = true
  local refreshed, refresh_err = window.refresh(true)
  window.render()
  window.save_state()
  if not refreshed then return false, refresh_err end
  return true
end

function window.hide()
  window.state.visible = false
  if window.ui and window.ui.container and type(window.ui.container.hide) == "function" then
    pcall(window.ui.container.hide, window.ui.container)
  end
  window.save_state()
  return true
end

local function status_text()
  local mode = (window.state.mode or "auto"):upper()
  local visibility = window.state.visible and "shown" or "hidden"
  local area = window.display_area
  if mode == "MANUAL" and clean(window.state.manual_area) ~= "" then area = window.state.manual_area end
  if clean(area) == "" then area = "not loaded" end
  return string.format(
    "Bookmark window is %s; mode %s; area %s; font %d; title %s.",
    visibility,
    mode,
    area_display_name(area),
    tonumber(window.state.font_size) or defaults.font_size,
    window.state.detailed_title == false and "compact" or "detailed"
  )
end

local function report_visibility(ok, err)
  if ok and mm.note then
    mm.note(window.state.visible and "Bookmark window shown." or "Bookmark window hidden.")
  end
  return ok, err
end

function window.command(raw_command)
  local command = clean(raw_command)
  local verb, argument = command:match("^(%S+)%s*(.-)$")
  verb = (verb or ""):lower()

  if verb == "" or verb == "status" then
    if mm.note then mm.note(status_text()) end
    return true
  elseif verb == "show" then
    return report_visibility(window.show())
  elseif verb == "hide" then
    return report_visibility(window.hide())
  elseif verb == "toggle" then
    if window.state.visible then return report_visibility(window.hide()) end
    return report_visibility(window.show())
  elseif verb == "auto" then
    window.state.mode = "auto"
    window.processed_area_key = nil
    window.save_state()
    if window.state.visible then
      local ok, err = window.refresh(false)
      if not ok then return false, err end
    end
    if mm.note then mm.note("Bookmark window mode set to AUTO.") end
    return true
  elseif verb == "manual" then
    if argument == "" then return false, "Usage: mapper bookmarkwin manual <area>" end
    if not (mm.bookmarks and type(mm.bookmarks.resolve_area) == "function") then
      return false, "bookmark area resolver is unavailable"
    end
    local area, err = mm.bookmarks.resolve_area(argument)
    if not area then return false, err end
    window.state.mode = "manual"
    window.state.manual_area = area
    window.save_state()
    if window.state.visible then
      local ok, refresh_err = window.refresh_area(area, false)
      if not ok then return false, refresh_err end
    end
    if mm.note then mm.note("Bookmark window manual area set to " .. tostring(area) .. ".") end
    return true
  elseif verb == "refresh" then
    local ok, err = window.refresh(false)
    if ok and mm.note then mm.note("Bookmark window refreshed for " .. area_display_name(window.display_area) .. ".") end
    return ok, err
  elseif verb == "font" then
    local size = tonumber(argument)
    if not size or size < 7 or size > 24 or size % 1 ~= 0 then
      return false, "Usage: mapper bookmarkwin font <7-24>"
    end
    window.state.font_size = size
    window.save_state()
    if window.state.visible then window.render() end
    if mm.note then mm.note("Bookmark window font size set to " .. tostring(size) .. ".") end
    return true
  elseif verb == "title" or verb == "titles" or verb == "header" or verb == "headers" or verb == "subtitle" then
    local setting = clean(argument):lower()
    local enabled
    if setting == "" or setting == "toggle" then
      enabled = window.state.detailed_title == false
    elseif setting == "on" then
      enabled = true
    elseif setting == "off" then
      enabled = false
    else
      return false, "Usage: mapper bookmarkwin title [on|off|toggle]"
    end
    window.state.detailed_title = enabled
    window.save_state()
    if window.state.visible then window.render() end
    if mm.note then
      mm.note(enabled and "Bookmark window detailed title enabled." or "Bookmark window title collapsed to the Bookmarks bar.")
    end
    return true
  end

  return false, "Usage: mapper bookmarkwin [show|hide|toggle|auto|manual <area>|refresh|font <7-24>|title on|off|toggle]"
end

function window.initialize()
  load_state()
  if type(registerAnonymousEventHandler) == "function" then
    window.handlers.room = registerAnonymousEventHandler("mm.room.changed", "mm.bookmark_window.on_room_changed")
    window.handlers.bookmarks = registerAnonymousEventHandler("mm.bookmarks.changed", "mm.bookmark_window.on_bookmarks_changed")
    window.handlers.resize = registerAnonymousEventHandler("sysWindowResizeEvent", "mm.bookmark_window.on_resize")
    window.handlers.reposition = registerAnonymousEventHandler("AdjustableContainerRepositionFinish", "mm.bookmark_window.on_reposition_finish")
    window.handlers.exit = registerAnonymousEventHandler("sysExitEvent", function() window.shutdown(true, false) end)
  end
  if window.state.visible then
    local ok, err = window.show()
    if not ok and mm.warn then mm.warn("Could not show bookmark window: " .. tostring(err)) end
  end
  return true
end
