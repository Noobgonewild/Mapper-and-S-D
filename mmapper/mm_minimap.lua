mm = mm or {}
mm.minimap = mm.minimap or {}

local function to_percent(v)
  if type(v) == "number" then
    return tostring(v) .. "%"
  end
  local s = tostring(v or "")
  if s:find("%%$") then
    return s
  end
  local n = tonumber(s)
  if n then
    return tostring(n) .. "%"
  end
  return s
end

local function pct_to_px(value, total)
  local s = tostring(value or "")
  local n = s:match("^([%-%.%d]+)%%$")
  if n then
    return (tonumber(n) or 0) * total / 100
  end
  return tonumber(s) or 0
end

local function is_adjustable_available()
  return Adjustable and Adjustable.Container and Adjustable.Container.new
end

local function pct_geom_to_px(cfg)
  local winw, winh = getMainWindowSize()
  return {
    x = math.floor(pct_to_px(cfg.x, winw) + 0.5),
    y = math.floor(pct_to_px(cfg.y, winh) + 0.5),
    width = math.max(120, math.floor(pct_to_px(cfg.width, winw) + 0.5)),
    height = math.max(90, math.floor(pct_to_px(cfg.height, winh) + 0.5)),
  }
end

local function style_bg()
  return "background-color: rgba(0,0,0,200); border: 1px solid #4a4a4a;"
end

local function style_title()
  return table.concat({
    "background-color: rgba(18,18,18,220);",
    "color: #A0FFFF;",
    "border: 1px solid #4a4a4a;",
    "font-weight: bold;",
    "padding-left: 4px;",
  }, " ")
end

local WINDOW_PERSIST_FILE = "mmapper_windows.lua"

local function persist_path()
  if mm.persistence_path then
    return mm.persistence_path(WINDOW_PERSIST_FILE)
  end
  return getMudletHomeDir() .. "/persistence/" .. WINDOW_PERSIST_FILE
end

local function legacy_persist_path()
  return getMudletHomeDir() .. "/" .. WINDOW_PERSIST_FILE
end

local function load_window_chunk()
  if mm.load_persistence_chunk then
    return mm.load_persistence_chunk(WINDOW_PERSIST_FILE)
  end

  local chunk = loadfile(persist_path())
  if chunk then return chunk, persist_path() end
  chunk = loadfile(legacy_persist_path())
  if chunk then return chunk, legacy_persist_path() end
  return nil, persist_path()
end

local function open_window_persist_file()
  if mm.open_persistence_file then
    return mm.open_persistence_file(WINDOW_PERSIST_FILE, "wb")
  end
  return io.open(persist_path(), "wb")
end

local function serialize_value(v)
  local t = type(v)
  if t == "number" or t == "boolean" then
    return tostring(v)
  elseif t == "string" then
    return string.format("%q", v)
  elseif t == "table" then
    local parts = {"{"}
    for k, val in pairs(v) do
      local key
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        key = k
      else
        key = "[" .. serialize_value(k) .. "]"
      end
      table.insert(parts, key .. "=" .. serialize_value(val) .. ",")
    end
    table.insert(parts, "}")
    return table.concat(parts)
  end
  return "nil"
end

local save_window_persistence

local function load_window_persistence()
  mm.runtime = mm.runtime or {}
  if mm.runtime._windows_loaded then return end
  mm.runtime._windows_loaded = true

  local chunk, source_path = load_window_chunk()
  if not chunk then return end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return end
  if type(data.windows) ~= "table" then return end

  mm.state.windows = mm.state.windows or {}
  for which, cfg in pairs(data.windows) do
    if type(cfg) == "table" then
      mm.state.windows[which] = mm.state.windows[which] or {}
      for k, v in pairs(cfg) do
        mm.state.windows[which][k] = v
      end
    end
  end
  if source_path == legacy_persist_path() then
    save_window_persistence()
  end
end

function save_window_persistence()
  mm.state = mm.state or {}
  mm.state.windows = mm.state.windows or {}
  local out = "return " .. serialize_value({ windows = mm.state.windows })
  local f = open_window_persist_file()
  if not f then return end
  f:write(out)
  f:close()
end

local function set_window_title(which, title)
  local w = mm.minimap.windows and mm.minimap.windows[which]
  if not (w and w.dragbar and w.dragbar.echo) then return end
  w.dragbar:echo(title or "")
end

function mm.minimap.set_room_title(room_name, room_id, area_name)
  local room_label = tostring(room_name or "")
  if room_label == "" then return end

  local area_label = tostring(area_name or "")
  set_window_title("minimap", room_label)
end

local function ensure_geom(which)
  load_window_persistence()
  mm.state.windows = mm.state.windows or {}
  local cfg = mm.state.windows[which]
  if not cfg then
    local defaults = {
      minimap = { x = "70%", y = "0%", width = "30%", height = "35%", max_lines = 16, enabled = true, locked = false, font_size = 8 },
      bigmap = { x = "45%", y = "35%", width = "55%", height = "65%", max_lines = 60, enabled = true, locked = false, font_size = 9 },
    }
    cfg = defaults[which]
    mm.state.windows[which] = cfg
  end
  cfg.x = to_percent(cfg.x)
  cfg.y = to_percent(cfg.y)
  cfg.width = to_percent(cfg.width)
  cfg.height = to_percent(cfg.height)
  cfg.font_size = tonumber(cfg.font_size) or (which == "bigmap" and 9 or 8)
  return cfg
end

local function ensure_window_storage()
  mm.minimap.windows = mm.minimap.windows or {}
  mm.minimap.lines = mm.minimap.lines or {}
end

local function set_window_visibility(which, visible)
  local w = mm.minimap.windows and mm.minimap.windows[which]
  if not w then return end

  if which == "bigmap" and w.kind == "mudlet_mapper" and w.mapper then
    if visible then
      w.mapper:show()
      if w.container then w.container:show() end
      if w.dragbar then w.dragbar:show() end
    else
      w.mapper:hide()
      if w.container then w.container:hide() end
      if w.dragbar then w.dragbar:hide() end
    end
  elseif w.console then
    if visible then
      w.console:show()
      if w.container then w.container:show() end
      if w.dragbar then w.dragbar:show() end
    else
      w.console:hide()
      if w.container then w.container:hide() end
      if w.dragbar then w.dragbar:hide() end
    end
  end
end

local function apply_font_size(which)
  local cfg = ensure_geom(which)
  local w = mm.minimap.windows and mm.minimap.windows[which]
  if not w then return end
  if w.console and w.console.setFontSize then
    w.console:setFontSize(cfg.font_size)
  end
end

local function create_adjustable_shell(which)
  local cfg = ensure_geom(which)
  local title = ""

  if not is_adjustable_available() then
    return nil, "Adjustable.Container unavailable"
  end

  if not is_adjustable_available() then
    return nil, "Adjustable.Container unavailable"
  end


  local px = pct_geom_to_px(cfg)
  local ok_container, container = pcall(function()
    return Adjustable.Container:new({
      name = string.format("mm_%s_main", which),
      x = px.x,
      y = px.y,
      width = px.width,
      height = px.height,
      adjLabelstyle = style_bg(),
      buttonstyle = "",
      lockStyle = "border: 0px;",
      titleText = "",
      titleTxtColor = "white",
    })
  end)
  if not ok_container or not container then
    return nil, "failed to create Adjustable.Container"
  end

  local body = Geyser.Container:new({
    name = string.format("mm_%s_body", which),
    x = 0,
    y = 0,
    width = "100%",
    height = "100%",
  }, container)

  return {
    container = container,
    border = nil,
    dragbar = nil,
    body = body,
    adjustable = true,
  }
end

local function is_left_button(event_or_button, maybe_button)
  local candidates = {
    maybe_button,
    event_or_button,
    type(event_or_button) == "table" and event_or_button.button or nil,
    type(event_or_button) == "table" and event_or_button[1] or nil,
  }

  for _, c in ipairs(candidates) do
    if c == "LeftButton" or c == 1 then
      return true
    end
  end
  return false
end

local function bind_dragbar(which, dragbar)
  local drag = { active = false, offset_x = 0, offset_y = 0 }
  if not dragbar then return end

  if dragbar.setClickCallback then
    dragbar:setClickCallback(function(_, event, button)
      if not is_left_button(event, button) then return end
      local cfg = ensure_geom(which)
      if cfg.locked then
        mm.warn(which .. " window is locked. Unlock it before dragging.")
        return
      end

      local mx, my = getMousePosition()
      local winw, winh = getMainWindowSize()
      drag.active = true
      drag.offset_x = mx - pct_to_px(cfg.x, winw)
      drag.offset_y = my - pct_to_px(cfg.y, winh)
    end)
  end

  if dragbar.setReleaseCallback then
    dragbar:setReleaseCallback(function(_, event, button)
      if not is_left_button(event, button) then return end
      drag.active = false
    end)
  end

  if dragbar.setMoveCallback then
    dragbar:setMoveCallback(function()
      if not drag.active then return end

      local mx, my = getMousePosition()
      local cfg = ensure_geom(which)
      local winw, winh = getMainWindowSize()

      local width_px = pct_to_px(cfg.width, winw)
      local height_px = pct_to_px(cfg.height, winh)

      local nx = mx - drag.offset_x
      local ny = my - drag.offset_y

      if nx < 0 then nx = 0 end
      if ny < 0 then ny = 0 end
      if nx > (winw - width_px) then nx = winw - width_px end
      if ny > (winh - height_px) then ny = winh - height_px end

      local x_pct = string.format("%.2f%%", (nx / winw) * 100)
      local y_pct = string.format("%.2f%%", (ny / winh) * 100)
      mm.minimap.move_window(which, x_pct, y_pct)
    end)
  end
end

local function create_miniconsole(which)
  local cfg = ensure_geom(which)
  local name = string.format("mm_%s_console", which)

  local shell, shell_err = create_adjustable_shell(which)
  local parent = shell and shell.body or nil

  local container
  local dragbar
  if not parent then
    local container_name = string.format("mm_%s_container", which)
    container = Geyser.Container:new({
      name = container_name,
      x = cfg.x,
      y = cfg.y,
      width = cfg.width,
      height = cfg.height,
    })

    dragbar = Geyser.Label:new({
      name = container_name .. "_dragbar",
      x = 0,
      y = 0,
      width = "100%",
      height = 16,
    }, container)
    dragbar:setStyleSheet("background-color: rgba(35,35,35,120);")

    parent = container
  end

  local console = Geyser.MiniConsole:new({
    name = name,
    x = 0,
    y = shell and 0 or 16,
    width = "100%",
    height = shell and "100%" or "100%-16",
  }, parent)
  console:setColor(0, 0, 0, 180)

  mm.minimap.windows[which] = {
    kind = "miniconsole",
    container = shell and shell.container or container,
    border = shell and shell.border or nil,
    dragbar = shell and shell.dragbar or dragbar,
    body = shell and shell.body or nil,
    console = console,
    adjustable = shell and true or false,
  }

  apply_font_size(which)
  if mm.minimap.windows[which].dragbar and not mm.minimap.windows[which].adjustable then
    bind_dragbar(which, mm.minimap.windows[which].dragbar)
  end
  set_window_visibility(which, cfg.enabled)

  if shell_err then
    mm.warn(string.format("%s window using fallback container (%s).", which, tostring(shell_err)))
  end

  return mm.minimap.windows[which]
end

local function create_bigmap_mapper()
  local cfg = ensure_geom("bigmap")

  if not (Geyser and Geyser.Mapper and Geyser.Mapper.new) then
    if mm.debug then mm.debug("bigmap mapper widget unavailable: Geyser.Mapper missing") end
    return nil, "Geyser.Mapper not available"
  end

  local shell, shell_err = create_adjustable_shell("bigmap")
  local parent = shell and shell.body or nil
  local container = shell and shell.container or nil
  local dragbar = shell and shell.dragbar or nil

  if not parent then
    local mapper_container_name = "mm_bigmap_mapper_container"
    local ok_container, fallback_container = pcall(function()
      return Geyser.Container:new({
        name = mapper_container_name,
        x = cfg.x,
        y = cfg.y,
        width = cfg.width,
        height = cfg.height,
      })
    end)
    if not ok_container or not fallback_container then
      return nil, "failed to create mapper container"
    end

    container = fallback_container
    dragbar = nil
    parent = container
  end

  local ok_mapper, mapper = pcall(function()
    return Geyser.Mapper:new({
      name = "mm_bigmap_mapper",
      x = 0,
      y = 0,
      width = "100%",
      height = "100%",
    }, parent)
  end)

  if not ok_mapper or not mapper then
    if mm.debug then mm.debug("bigmap mapper creation failed") end
    return nil, "failed to create Geyser.Mapper"
  end

  if mm.debug then mm.debug("bigmap mapper widget created successfully") end

  mm.minimap.windows.bigmap = {
    kind = "mudlet_mapper",
    container = container,
    border = shell and shell.border or nil,
    dragbar = dragbar,
    body = shell and shell.body or nil,
    mapper = mapper,
    adjustable = shell and true or false,
  }

  if dragbar and not mm.minimap.windows.bigmap.adjustable then
    bind_dragbar("bigmap", dragbar)
  end

  set_window_visibility("bigmap", cfg.enabled)
  if mm.debug then mm.debug("bigmap visibility set to " .. tostring(cfg.enabled)) end

  if shell_err then
    mm.warn("bigmap using fallback container (" .. tostring(shell_err) .. ").")
  end

  return mm.minimap.windows.bigmap
end

local function create_window(which)
  ensure_window_storage()
  if mm.minimap.windows[which] then
    return mm.minimap.windows[which]
  end

  if which == "bigmap" then
    local win, err = create_bigmap_mapper()
    if win then
      mm.minimap.backend = "mudlet_mapper"
      mm.note("Big map builder is using Mudlet's native mapper widget.")
      mm.minimap.lines.bigmap = mm.minimap.lines.bigmap or {}
      return win
    end
    mm.warn("Mudlet mapper widget unavailable for bigmap (" .. tostring(err) .. "). Falling back to ASCII console.")
  end

  local fallback = create_miniconsole(which)
  mm.minimap.lines[which] = mm.minimap.lines[which] or {}
  if which == "bigmap" then
    mm.minimap.backend = "ascii_fallback"
  end
  return fallback
end

local function set_geom(which, x, y, w, h)
  local cfg = ensure_geom(which)
  cfg.x = to_percent(x or cfg.x)
  cfg.y = to_percent(y or cfg.y)
  cfg.width = to_percent(w or cfg.width)
  cfg.height = to_percent(h or cfg.height)

  local win = create_window(which)

  if win.container then
    if win.adjustable then
      local px = pct_geom_to_px(cfg)
      win.container:move(px.x, px.y)
      win.container:resize(px.width, px.height)
    else
      win.container:move(cfg.x, cfg.y)
      win.container:resize(cfg.width, cfg.height)
    end
  elseif win.console then
    win.console:move(cfg.x, cfg.y)
    win.console:resize(cfg.width, cfg.height)
  end
end


function mm.minimap.get_console_name(which)
  local w = mm.minimap.windows and mm.minimap.windows[which]
  if not (w and w.console) then return nil end
  return w.console.name or string.format("mm_%s_console", which)
end

function mm.minimap.clear_console(which)
  local w = mm.minimap.windows and mm.minimap.windows[which]
  if w and w.console and w.console.clear then
    w.console:clear()
    return true
  end
  return false
end

function mm.minimap.append_current_line(which)
  mm.minimap.init()
  local target = mm.minimap.get_console_name(which)
  if not target then return false end
  if type(selectCurrentLine) ~= "function" or type(copy) ~= "function" or type(appendBuffer) ~= "function" then
    return false
  end

  selectCurrentLine()
  copy()
  appendBuffer(target)
  if type(deleteLine) == "function" then
    deleteLine()
  end
  return true
end

function mm.minimap.init()
  create_window("minimap")
  create_window("bigmap")
end

function mm.minimap.push_line(line)
  if not mm.state.minimap.enabled then return end
  mm.minimap.init()

  for _, which in ipairs({ "minimap", "bigmap" }) do
    local cfg = ensure_geom(which)
    local lines = mm.minimap.lines[which] or {}
    mm.minimap.lines[which] = lines
    table.insert(lines, line)
    while #lines > cfg.max_lines do
      table.remove(lines, 1)
    end
  end

  mm.minimap.redraw("minimap")
  mm.minimap.redraw("bigmap")
end

local function colorize_ascii_map_line(raw)
  if raw == "" then return nil end
  local out = {}
  local i = 1
  while i <= #raw do
    local ch = raw:sub(i, i)
    local color
    if ch == "[" or ch == "]" or ch == "?" then
      color = "<220,220,220>"
    elseif ch == "#" or ch == "!" then
      color = "<255,140,80>"
    elseif ch == "+" or ch == "*" or ch == "." then
      color = "<120,220,120>"
    elseif ch == "<" or ch == ">" or ch == "|" or ch == "-" then
      color = "<120,180,255>"
    end

    if color then
      table.insert(out, color .. ch)
    else
      table.insert(out, ch)
    end
    i = i + 1
  end

  local joined = table.concat(out)
  if joined == raw then return nil end
  return joined
end

local function render_line(console, line)
  local raw = line
  local decho_line
  if type(line) == "table" then
    decho_line = line.decho
    raw = line.raw or line.text or ""
  end

  raw = tostring(raw or "")

  if decho_line and decho_line ~= "" and console.decho then
    console:decho(decho_line .. "\n")
    return
  end

  if type(ansi2decho) == "function" and raw:find(string.char(27) .. "%[") then
    local ok, converted = pcall(ansi2decho, raw)
    if ok and converted and converted ~= "" and console.decho then
      console:decho(converted .. "\n")
      return
    end
  end

  if console.echo then
    console:echo(raw .. "\n")
  end
end

function mm.minimap.set_map_lines(lines)
  mm.minimap.lines = mm.minimap.lines or {}
  mm.minimap.lines.minimap = {}

  for _, line in ipairs(lines or {}) do
    if type(line) == "table" then
      table.insert(mm.minimap.lines.minimap, { raw = tostring(line.raw or line.text or ""), decho = line.decho })
    else
      table.insert(mm.minimap.lines.minimap, tostring(line or ""))
    end
  end

  local cfg = ensure_geom("bigmap")
  if mm.minimap.backend == "ascii_fallback" then
    mm.minimap.lines.bigmap = {}
    for i, line in ipairs(mm.minimap.lines.minimap) do
      if i > cfg.max_lines then
        table.remove(mm.minimap.lines.bigmap, 1)
      end
      table.insert(mm.minimap.lines.bigmap, line)
    end
  end

  mm.minimap.redraw("minimap")
  mm.minimap.redraw("bigmap")
end

function mm.minimap.redraw(which)
  local w = mm.minimap.windows and mm.minimap.windows[which]
  if not w then return end

  if which == "bigmap" and w.kind == "mudlet_mapper" then
    return
  end

  local console = w.console
  if not console then return end
  console:clear()

  for _, line in ipairs((mm.minimap.lines and mm.minimap.lines[which]) or {}) do
    render_line(console, line)
  end
end

function mm.minimap.toggle_show(setting, option)
  local state = option == "on"
  if setting:find("^room") then
    mm.state.minimap.show_room = state
  elseif setting == "exits" then
    mm.state.minimap.show_exits = state
  elseif setting:find("^coord") then
    mm.state.minimap.show_coords = state
  elseif setting == "echo" then
    mm.state.minimap.echo = state
  end
  mm.note(string.format("Minimap setting '%s' is now %s.", setting, option))
end

function mm.minimap.set_type(kind)
  mm.state.minimap.type = kind
  send("maptype " .. tostring(kind))
  mm.note("Map type set to '" .. tostring(kind) .. "'.")
end

function mm.minimap.set_window_visible(which, visible)
  local cfg = ensure_geom(which)
  cfg.enabled = visible and true or false
  create_window(which)
  set_window_visibility(which, cfg.enabled)
  save_window_persistence()
  mm.note(string.format("%s window %s.", which, cfg.enabled and "shown" or "hidden"))
end

function mm.minimap.move_window(which, x, y)
  local cfg = ensure_geom(which)
  if cfg.locked then
    mm.warn(which .. " window is locked. Unlock it before moving.")
    return
  end
  set_geom(which, x, y, cfg.width, cfg.height)
  save_window_persistence()
  mm.note(string.format("Moved %s window to %s, %s.", which, cfg.x, cfg.y))
end

function mm.minimap.resize_window(which, width, height)
  local cfg = ensure_geom(which)
  if cfg.locked then
    mm.warn(which .. " window is locked. Unlock it before resizing.")
    return
  end
  set_geom(which, cfg.x, cfg.y, width, height)
  save_window_persistence()
  mm.note(string.format("Resized %s window to %s x %s.", which, cfg.width, cfg.height))
end

function mm.minimap.set_font_size(which, size)
  local cfg = ensure_geom(which)
  local n = tonumber(size)
  if not n then
    mm.warn("Font size must be a number.")
    return
  end

  n = math.floor(n)
  if n < 6 then n = 6 end
  if n > 32 then n = 32 end

  cfg.font_size = n
  save_window_persistence()
  create_window(which)
  apply_font_size(which)
  mm.minimap.redraw(which)
  mm.note(string.format("%s font size set to %d.", which, n))
end

function mm.minimap.lock_window(which, on)
  local cfg = ensure_geom(which)
  cfg.locked = on and true or false
  save_window_persistence()
  mm.note(string.format("%s window position lock %s.", which, cfg.locked and "enabled" or "disabled"))
end

function mm.minimap.show_all()
  mm.minimap.set_window_visible("minimap", true)
  mm.minimap.set_window_visible("bigmap", true)
end

function mm.minimap.hide_all()
  mm.minimap.set_window_visible("minimap", false)
  mm.minimap.set_window_visible("bigmap", false)
end
