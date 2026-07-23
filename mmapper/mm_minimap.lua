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

local function clamp_local_radius(value)
  local n = tonumber(value) or 4
  n = math.floor(n)
  if n < 1 then n = 1 end
  if n > 8 then n = 8 end
  return n
end

local function clamp_local_room_size(value)
  local n = tonumber(value) or 15
  n = math.floor(n)
  if n < 10 then n = 10 end
  if n > 30 then n = 30 end
  return n
end

local function ensure_minimap_options()
  mm.state = mm.state or {}
  mm.state.minimap = mm.state.minimap or {}
  local opts = mm.state.minimap
  if opts.bigmap_mode ~= "local" and opts.bigmap_mode ~= "native" and opts.bigmap_mode ~= "hybrid" then
    opts.bigmap_mode = "hybrid"
  end
  opts.local_radius = clamp_local_radius(opts.local_radius)
  opts.local_room_size = clamp_local_room_size(opts.local_room_size)
  return opts
end

local function active_bigmap_mode()
  local configured = ensure_minimap_options().bigmap_mode
  if configured == "hybrid" then
    local runtime_mode = mm.runtime and mm.runtime.hybrid_bigmap_backend
    return runtime_mode == "native" and "native" or "local"
  end
  return configured
end

function mm.minimap.is_local_mode()
  return active_bigmap_mode() == "local"
end

function mm.minimap.is_native_mode()
  return active_bigmap_mode() == "native"
end

function mm.minimap.is_navigation_active()
  return snd and ((snd.nav and snd.nav.goingToRoom) or
    (snd.mapper and snd.mapper.goingToRoom)) ~= nil
end

local function set_window_title(which, title)
  title = title or ""
  mm.minimap.window_titles = mm.minimap.window_titles or {}
  mm.minimap.window_titles[which] = title

  local w = mm.minimap.windows and mm.minimap.windows[which]
  if not w then return end

  if w.container and type(w.container.setTitle) == "function" then
    w.container:setTitle(title, "#A0FFFF", "l")
  elseif w.dragbar and type(w.dragbar.echo) == "function" then
    w.dragbar:echo(title)
  end
end

local function restore_window_title(which)
  local titles = mm.minimap.window_titles
  if titles and titles[which] ~= nil then
    set_window_title(which, titles[which])
  end
end

function mm.minimap.set_room_title(room_name, room_id, area_name)
  local room_label = tostring(room_name or "")
  if room_label == "" then return end

  local area_label = tostring(area_name or "")
  set_window_title("minimap", "")
  local big_label = room_label
  if room_id ~= nil and tostring(room_id) ~= "" then
    big_label = string.format("%s (%s)", big_label, tostring(room_id))
  end
  if area_label ~= "" then
    big_label = string.format("%s / %s", area_label, big_label)
  end
  set_window_title("bigmap", big_label)
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
  elseif w.canvas then
    if visible then
      w.canvas:show()
      if w.container then w.container:show() end
      if w.dragbar then w.dragbar:show() end
    else
      w.canvas:hide()
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

local function destroy_window(which)
  local w = mm.minimap.windows and mm.minimap.windows[which]
  if not w then return end
  set_window_visibility(which, false)

  local root = w.container
  if root and type(root.delete) == "function" then
    pcall(root.delete, root)
  elseif w.mapper and type(w.mapper.delete) == "function" then
    pcall(w.mapper.delete, w.mapper)
  elseif w.canvas and type(w.canvas.delete) == "function" then
    pcall(w.canvas.delete, w.canvas)
  elseif w.console and type(w.console.delete) == "function" then
    pcall(w.console.delete, w.console)
  end

  mm.minimap.windows[which] = nil
  if which == "bigmap" then mm.minimap.backend = nil end
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

  restore_window_title(which)
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

local function create_local_map_canvas()
  local cfg = ensure_geom("bigmap")
  if not (Geyser and Geyser.Container and Geyser.Container.new and
          Geyser.Label and Geyser.Label.new) then
    return nil, "Geyser graphical widgets unavailable"
  end

  local shell, shell_err = create_adjustable_shell("bigmap")
  local parent = shell and shell.body or nil
  local container = shell and shell.container or nil
  local dragbar = shell and shell.dragbar or nil

  if not parent then
    container = Geyser.Container:new({
      name = "mm_bigmap_local_container",
      x = cfg.x,
      y = cfg.y,
      width = cfg.width,
      height = cfg.height,
    })
    dragbar = Geyser.Label:new({
      name = "mm_bigmap_local_dragbar",
      x = 0,
      y = 0,
      width = "100%",
      height = 16,
    }, container)
    dragbar:setStyleSheet("background-color: rgba(35,35,35,180);")
    parent = container
  end

  local canvas = Geyser.Container:new({
    name = "mm_bigmap_local_canvas",
    x = 0,
    y = shell and 0 or 16,
    width = "100%",
    height = shell and "100%" or "100%-16",
  }, parent)
  local background = Geyser.Label:new({
    name = "mm_bigmap_local_background",
    x = 0,
    y = 0,
    width = "100%",
    height = "100%",
  }, canvas)
  background:setStyleSheet("background-color: rgba(17,17,17,245); border: 0px;")

  mm.minimap.windows.bigmap = {
    kind = "local_radius",
    container = container,
    border = shell and shell.border or nil,
    dragbar = dragbar,
    body = shell and shell.body or nil,
    canvas = canvas,
    background = background,
    drawables = {},
    draw_serial = 0,
    adjustable = shell and true or false,
  }

  restore_window_title("bigmap")
  if dragbar and not mm.minimap.windows.bigmap.adjustable then
    bind_dragbar("bigmap", dragbar)
  end
  set_window_visibility("bigmap", cfg.enabled)
  if shell_err then
    mm.warn("bigmap local view using fallback container (" .. tostring(shell_err) .. ").")
  end
  return mm.minimap.windows.bigmap
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
      embedded = true,
    }, parent)
  end)

  if not ok_mapper or not mapper then
    if mm.debug then mm.debug("bigmap mapper creation failed") end
    if container and type(container.delete) == "function" then
      pcall(container.delete, container)
    end
    return nil, "failed to create Geyser.Mapper"
  end

  if mapper.embedded ~= true then
    if container and type(container.delete) == "function" then
      pcall(container.delete, container)
    elseif type(mapper.delete) == "function" then
      pcall(mapper.delete, mapper)
    end
    return nil, "Geyser.Mapper did not create an embedded mapper"
  end

  if mm.debug then
    mm.debug("embedded bigmap mapper created in " .. tostring(mapper.windowname or "main"))
  end

  mm.minimap.windows.bigmap = {
    kind = "mudlet_mapper",
    container = container,
    border = shell and shell.border or nil,
    dragbar = dragbar,
    body = shell and shell.body or nil,
    mapper = mapper,
    adjustable = shell and true or false,
  }

  restore_window_title("bigmap")
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
    local opts = ensure_minimap_options()
    if active_bigmap_mode() == "native" then
      local win, err = create_bigmap_mapper()
      if win then
        mm.minimap.backend = "mudlet_mapper"
        mm.minimap.lines.bigmap = mm.minimap.lines.bigmap or {}
        return win
      end
      mm.warn("Mudlet mapper widget unavailable for bigmap (" .. tostring(err) .. "). Falling back to local radius map.")
      if opts.bigmap_mode == "hybrid" then
        mm.runtime = mm.runtime or {}
        mm.runtime.hybrid_bigmap_backend = "local"
      else
        opts.bigmap_mode = "local"
      end
    end
  end

  if which == "bigmap" then
    local local_window, local_err = create_local_map_canvas()
    if local_window then
      mm.minimap.lines[which] = mm.minimap.lines[which] or {}
      mm.minimap.backend = "local_radius"
      return local_window
    end
    mm.warn("Graphical local map unavailable (" .. tostring(local_err) .. "). Falling back to text output.")
  end

  local fallback = create_miniconsole(which)
  mm.minimap.lines[which] = mm.minimap.lines[which] or {}
  if which == "bigmap" then
    fallback.kind = "local_radius_text"
    mm.minimap.backend = "local_radius"
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
  if which == "bigmap" and win.kind == "local_radius" and mm.minimap.redraw then
    mm.minimap.redraw(which)
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

  local targets = { "minimap" }
  if mm.minimap.backend ~= "local_radius" then
    table.insert(targets, "bigmap")
  end

  for _, which in ipairs(targets) do
    local cfg = ensure_geom(which)
    local lines = mm.minimap.lines[which] or {}
    mm.minimap.lines[which] = lines
    table.insert(lines, line)
    while #lines > cfg.max_lines do
      table.remove(lines, 1)
    end
  end

  mm.minimap.redraw("minimap")
  if mm.minimap.backend ~= "local_radius" then
    mm.minimap.redraw("bigmap")
  end
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
    elseif ch == "@" then
      color = "<255,230,120>"
    elseif ch == "o" then
      color = "<210,210,210>"
    elseif ch == "<" or ch == ">" or ch == "^" or ch == "v" then
      color = "<255,160,80>"
    elseif ch == "|" or ch == "-" then
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

local LOCAL_DIRS = {
  n = { dx = 0, dy = 1, inverse = "s" },
  e = { dx = 1, dy = 0, inverse = "w" },
  s = { dx = 0, dy = -1, inverse = "n" },
  w = { dx = -1, dy = 0, inverse = "e" },
}

local function normalize_local_dir(dir)
  local d = tostring(dir or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local aliases = {
    north = "n",
    east = "e",
    south = "s",
    west = "w",
    up = "u",
    down = "d",
  }
  return aliases[d] or d
end

local function is_real_local_room_id(uid)
  local s = tostring(uid or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return s ~= "" and s ~= "*" and s ~= "**" and s ~= "-1" and not s:find("^nomap_")
end

local function local_coord_key(x, y)
  return tostring(x) .. "," .. tostring(y)
end

local function clean_local_label(text, max_len)
  local s = tostring(text or "")
  if mm.strip_ansi then s = mm.strip_ansi(s) end
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  max_len = max_len or 52
  if #s > max_len then
    s = s:sub(1, max_len - 3) .. "..."
  end
  return s
end

local function add_local_stub(graph, source_id, dir, target_id, reason, one_way)
  graph.stubs[source_id] = graph.stubs[source_id] or {}
  if graph.stubs[source_id][dir] then return end
  graph.stubs[source_id][dir] = {
    target = target_id,
    reason = reason,
    one_way = one_way == true,
  }
  graph.stub_count = (graph.stub_count or 0) + 1
end

local function add_local_connection(graph, source_id, dir, target_id, one_way)
  graph.connections[source_id] = graph.connections[source_id] or {}
  graph.connections[source_id][dir] = {
    target = target_id,
    one_way = one_way == true,
  }
end

local function same_local_area(center_area, target_area)
  center_area = tostring(center_area or "")
  target_area = tostring(target_area or "")
  return center_area == "" or target_area == "" or center_area == target_area
end

local function resolve_local_room_id(room_id)
  if is_real_local_room_id(room_id) then
    return tostring(room_id)
  end

  local rt = mm.runtime or {}
  local candidates = {}
  local function add_candidate(value)
    if value ~= nil and tostring(value) ~= "" then
      table.insert(candidates, value)
    end
  end
  add_candidate(rt.last_player_room)
  add_candidate(rt.last_room_num)
  if mm.current_room then
    add_candidate(mm.current_room())
  end
  if mm.get_room_info then
    local info = mm.get_room_info()
    if info then add_candidate(info.num) end
  end

  for _, candidate in ipairs(candidates) do
    if is_real_local_room_id(candidate) then
      return tostring(candidate)
    end
  end
  return nil
end

local function place_local_room(graph, room_id, x, y)
  graph.placed[room_id] = { x = x, y = y }
  graph.occupied[local_coord_key(x, y)] = room_id
  graph.room_count = (graph.room_count or 0) + 1
end

local function local_exit_is_reconsiderable(exit)
  return exit.map_kind == "direct" or
    (exit.map_kind == "stub" and exit.stub_reason == "coordinate overlap")
end

local function build_local_graph(center_id, radius)
  if not (mm.import and (mm.import.get_compiled_layout_area_snapshot or
      mm.import.get_layout_area_snapshot)) then
    return nil, "shared layout classifier is not loaded"
  end

  local center_num = tonumber(center_id)
  if not center_num then return nil, "current mapped room is not numeric" end
  local snapshot, snapshot_err
  if mm.import.get_compiled_layout_area_snapshot then
    snapshot, snapshot_err = mm.import.get_compiled_layout_area_snapshot(center_num)
  end
  if not snapshot and mm.import.get_layout_area_snapshot then
    if mm.debug then
      mm.debug("local map compiled cache unavailable; using live area classification: " ..
        tostring(snapshot_err))
    end
    snapshot, snapshot_err = mm.import.get_layout_area_snapshot(center_num)
  end
  if not snapshot then return nil, snapshot_err end

  local source_graph = snapshot.graph
  local area = snapshot.area
  local center_key = tostring(center_num)
  local center_room = source_graph.rooms[center_num]
  if not center_room then return nil, "current room is missing from classified area" end

  local graph = {
    center = center_key,
    radius = radius,
    center_area = tostring(center_room.area or ""),
    terrain_colors = source_graph.terrain_colors or {},
    rooms = { [center_key] = center_room },
    placed = {},
    occupied = {},
    connections = {},
    stubs = {},
    vertical = {},
    exit_index = source_graph.actual_exit_index or {},
    room_count = 0,
    stub_count = 0,
  }
  place_local_room(graph, center_key, 0, 0)

  if not next(graph.exit_index) then
    for _, exit in ipairs(source_graph.actual_exits or {}) do
      if exit.area == area.key then
        local dir = normalize_local_dir(exit.dir)
        graph.exit_index[exit.from] = graph.exit_index[exit.from] or {}
        graph.exit_index[exit.from][dir] = exit
      end
    end
  end

  local function is_one_way(exit)
    local dir = normalize_local_dir(exit.dir)
    local def = LOCAL_DIRS[dir]
    if not def or not tonumber(exit.to) or tonumber(exit.to) <= 0 then return false end
    local inverse = graph.exit_index[tonumber(exit.to)] and
      graph.exit_index[tonumber(exit.to)][def.inverse]
    return not inverse or tonumber(inverse.to) ~= tonumber(exit.from)
  end

  local max_rooms = (radius * 2 + 1) * (radius * 2 + 1)
  local queue, head = { center_num }, 1
  while head <= #queue and graph.room_count < max_rooms do
    local source_num = queue[head]
    head = head + 1
    local source_key = tostring(source_num)
    local source_pos = graph.placed[source_key]
    local exits = graph.exit_index[source_num] or {}
    for _, dir in ipairs({ "n", "e", "s", "w", "u", "d" }) do
      local exit = exits[dir]
      if exit and source_pos then
        local target_key = tostring(exit.to or "")
        local one_way = is_one_way(exit)
        if dir == "u" or dir == "d" then
          graph.vertical[source_key] = graph.vertical[source_key] or {}
          graph.vertical[source_key][dir] = {
            target = target_key,
            one_way = one_way,
          }
        else
          local def = LOCAL_DIRS[dir]
          local target_num = tonumber(exit.to)
          local target_room = target_num and source_graph.rooms[target_num] or nil
          local nx = source_pos.x + def.dx
          local ny = source_pos.y + def.dy
          local target_pos = graph.placed[target_key]
          local occupant = graph.occupied[local_coord_key(nx, ny)]
          local in_bounds = math.abs(nx) <= radius and math.abs(ny) <= radius
          local can_place = local_exit_is_reconsiderable(exit) and target_room and
            same_local_area(graph.center_area, target_room.area)

          if not can_place then
            add_local_stub(graph, source_key, dir, target_key,
              exit.stub_reason or "non-geometric local edge", one_way)
          elseif target_pos then
            if target_pos.x == nx and target_pos.y == ny then
              add_local_connection(graph, source_key, dir, target_key, one_way)
            else
              add_local_stub(graph, source_key, dir, target_key,
                "target already placed elsewhere", one_way)
            end
          elseif not in_bounds then
            add_local_stub(graph, source_key, dir, target_key, "outside local radius", one_way)
          elseif occupant and occupant ~= target_key then
            add_local_stub(graph, source_key, dir, target_key, "local coordinate overlap", one_way)
          else
            graph.rooms[target_key] = target_room
            place_local_room(graph, target_key, nx, ny)
            add_local_connection(graph, source_key, dir, target_key, one_way)
            table.insert(queue, target_num)
          end
        end
      end
    end
  end

  return graph
end

local LOCAL_EXIT_COLOR = "rgba(224,255,255,220)"
local LOCAL_VERTICAL_COLOR = "#ffb6c1"
local LOCAL_CURRENT_COLOR = "#ff1493"
local LOCAL_TRIANGLE = {
  n = "\226\150\178",
  e = "\226\150\182",
  s = "\226\150\188",
  w = "\226\151\128",
}

local function clear_local_drawables(window)
  for i = #(window.drawables or {}), 1, -1 do
    local drawable = window.drawables[i]
    if drawable and type(drawable.delete) == "function" then
      pcall(drawable.delete, drawable)
    end
  end
  window.drawables = {}
end

local function new_local_drawable(window, kind, x, y, width, height, stylesheet, text, tooltip)
  window.draw_serial = (window.draw_serial or 0) + 1
  local ok, label = pcall(function()
    return Geyser.Label:new({
      name = string.format("mm_bigmap_local_%s_%d", kind, window.draw_serial),
      x = math.floor(x + 0.5),
      y = math.floor(y + 0.5),
      width = math.max(1, math.floor(width + 0.5)),
      height = math.max(1, math.floor(height + 0.5)),
    }, window.canvas)
  end)
  if not ok or not label then return nil end

  if stylesheet and label.setStyleSheet then label:setStyleSheet(stylesheet) end
  if text and label.echo then pcall(label.echo, label, text, nil, "c") end
  if tooltip and label.setToolTip then pcall(label.setToolTip, label, tooltip) end
  table.insert(window.drawables, label)
  return label
end

local function local_canvas_dimensions(window)
  local width, height
  if window.canvas and window.canvas.get_width then
    local ok, value = pcall(window.canvas.get_width, window.canvas)
    if ok then width = tonumber(value) end
  end
  if window.canvas and window.canvas.get_height then
    local ok, value = pcall(window.canvas.get_height, window.canvas)
    if ok then height = tonumber(value) end
  end

  local px = pct_geom_to_px(ensure_geom("bigmap"))
  width = width and width > 0 and width or px.width
  height = height and height > 0 and height or (px.height - (window.adjustable and 0 or 16))
  return math.max(120, width), math.max(90, height)
end

local function local_room_rgb(graph, room)
  local terrain = tostring(room and room.terrain or ""):lower()
  local rgb = graph.terrain_colors and graph.terrain_colors[terrain] or nil
  if rgb then return rgb end
  if terrain:find("water") or terrain:find("river") or terrain:find("ocean") then
    return { 0, 96, 190 }
  elseif terrain:find("forest") or terrain:find("jungle") or terrain:find("field") then
    return { 0, 128, 48 }
  elseif terrain:find("air") or terrain:find("sky") then
    return { 0, 160, 180 }
  elseif terrain:find("desert") or terrain:find("sand") then
    return { 170, 150, 30 }
  elseif terrain:find("lava") or terrain:find("fire") then
    return { 190, 45, 25 }
  end
  return { 105, 105, 105 }
end

local function local_point(layout, pos)
  return layout.center_x + pos.x * layout.cell,
    layout.center_y - pos.y * layout.cell
end

local function draw_local_line(window, x1, y1, x2, y2, color)
  if math.abs(x2 - x1) >= math.abs(y2 - y1) then
    return new_local_drawable(window, "hline", math.min(x1, x2), y1,
      math.max(1, math.abs(x2 - x1)), 1,
      "background-color: " .. color .. "; border: 0px;")
  end
  return new_local_drawable(window, "vline", x1, math.min(y1, y2),
    1, math.max(1, math.abs(y2 - y1)),
    "background-color: " .. color .. "; border: 0px;")
end

local function draw_local_direction_marker(window, layout, source_pos, dir, color)
  local def = LOCAL_DIRS[dir]
  if not def then return end
  local sx, sy = local_point(layout, source_pos)
  local distance = layout.node_half + 5
  local mx = sx + def.dx * distance - 5
  local my = sy - def.dy * distance - 5
  new_local_drawable(window, "arrow", mx, my, 10, 10,
    "background-color: transparent; border: 0px; color: " .. color .. "; font-size: 7pt;",
    LOCAL_TRIANGLE[dir])
end

local function render_local_graphical(window, graph)
  clear_local_drawables(window)
  window.graph = graph

  local width, height = local_canvas_dimensions(window)
  local span = graph.radius * 2 + 1
  local available = math.min((width - 24) / span, (height - 24) / span)
  local requested_room_size = clamp_local_room_size(graph.local_room_size)
  local cell_cap = math.min(48, math.max(30, requested_room_size + 10))
  local cell = math.max(18, math.min(cell_cap, math.floor(available)))
  local node_size = math.max(10, math.min(requested_room_size, cell - 6))
  local layout = {
    center_x = width / 2,
    center_y = height / 2,
    cell = cell,
    node_size = node_size,
    node_half = node_size / 2,
  }

  local drawn_segments = {}
  for source_id, dirs in pairs(graph.connections) do
    local source_pos = graph.placed[source_id]
    if source_pos then
      for dir, connection in pairs(dirs) do
        local target_pos = graph.placed[tostring(connection.target)]
        local def = LOCAL_DIRS[dir]
        if target_pos and def then
          local source_x, source_y = local_point(layout, source_pos)
          local target_x, target_y = local_point(layout, target_pos)
          local key_a = local_coord_key(source_pos.x, source_pos.y)
          local key_b = local_coord_key(target_pos.x, target_pos.y)
          local segment_key = key_a < key_b and (key_a .. "|" .. key_b) or (key_b .. "|" .. key_a)
          if not drawn_segments[segment_key] then
            drawn_segments[segment_key] = true
            draw_local_line(window,
              source_x + def.dx * layout.node_half,
              source_y - def.dy * layout.node_half,
              target_x - def.dx * layout.node_half,
              target_y + def.dy * layout.node_half,
              LOCAL_EXIT_COLOR)
          end
          if connection.one_way then
            draw_local_direction_marker(window, layout, source_pos, dir, "#e0ffff")
          end
        end
      end
    end
  end

  local stub_length = math.max(4, math.floor((cell - node_size) / 3))
  for source_id, dirs in pairs(graph.stubs) do
    local source_pos = graph.placed[source_id]
    if source_pos then
      local source_x, source_y = local_point(layout, source_pos)
      for dir, stub in pairs(dirs) do
        local def = LOCAL_DIRS[dir]
        if def then
          local x1 = source_x + def.dx * layout.node_half
          local y1 = source_y - def.dy * layout.node_half
          draw_local_line(window, x1, y1,
            x1 + def.dx * stub_length,
            y1 - def.dy * stub_length,
            LOCAL_EXIT_COLOR)
          if stub.one_way then
            draw_local_direction_marker(window, layout, source_pos, dir, "#e0ffff")
          end
        end
      end
    end
  end

  for room_id, pos in pairs(graph.placed) do
    local room = graph.rooms[room_id] or {}
    local rgb = local_room_rgb(graph, room)
    local x, y = local_point(layout, pos)
    local current = room_id == graph.center
    local border_width = current and 3 or 1
    local border_color = current and LOCAL_CURRENT_COLOR or "#dcdcdc"
    local stylesheet = string.format(
      "background-color: rgba(%d,%d,%d,155); border: %dpx solid %s;",
      rgb[1], rgb[2], rgb[3], border_width, border_color)
    local tooltip = string.format("%s\nRoom: %s\nTerrain: %s",
      clean_local_label(room.name or ("Room " .. room_id), 80),
      room_id,
      clean_local_label(room.terrain or "unknown", 40))
    new_local_drawable(window, "room", x - layout.node_half, y - layout.node_half,
      node_size, node_size, stylesheet, nil, tooltip)

    local vertical = graph.vertical[room_id] or {}
    if vertical.u then
      new_local_drawable(window, "up", x + layout.node_half - 2, y - layout.node_half - 7,
        8, 8, "background-color: transparent; border: 0px; color: " .. LOCAL_VERTICAL_COLOR .. "; font-size: 6pt;",
        LOCAL_TRIANGLE.n)
    end
    if vertical.d then
      new_local_drawable(window, "down", x - layout.node_half - 6, y + layout.node_half - 1,
        8, 8, "background-color: transparent; border: 0px; color: " .. LOCAL_VERTICAL_COLOR .. "; font-size: 6pt;",
        LOCAL_TRIANGLE.s)
    end
  end

  if window.background and window.background.lower then pcall(window.background.lower, window.background) end
end

local function render_local_error(window, message)
  clear_local_drawables(window)
  window.graph = nil
  local width, height = local_canvas_dimensions(window)
  new_local_drawable(window, "error", 12, height / 2 - 12, width - 24, 24,
    "background-color: transparent; border: 0px; color: #ff7878; font-size: 9pt;",
    clean_local_label(message, 120))
end

local function render_local_nomap(window, room_size)
  clear_local_drawables(window)
  window.graph = nil
  local width, height = local_canvas_dimensions(window)
  local size = clamp_local_room_size(room_size)
  new_local_drawable(window, "nomap", (width - size) / 2, (height - size) / 2,
    size, size,
    "background-color: rgba(105,105,105,155); border: 3px solid " .. LOCAL_CURRENT_COLOR .. ";")
  if window.background and window.background.lower then pcall(window.background.lower, window.background) end
end

mm.minimap._build_local_graph = build_local_graph

function mm.minimap.update_local_map(room_id, update_opts)
  local opts = ensure_minimap_options()
  if active_bigmap_mode() ~= "local" then return false end

  ensure_window_storage()
  local window = create_window("bigmap")
  if mm.minimap.backend ~= "local_radius" then return false end
  if not (window and window.kind == "local_radius" and window.canvas) then
    mm.minimap.lines.bigmap = {
      "Graphical local map unavailable: Geyser canvas creation failed.",
    }
    mm.minimap.redraw("bigmap")
    return false
  end

  local requested_id = tostring(room_id or "")
  local info = mm.get_room_info and mm.get_room_info() or nil
  if requested_id == "-1" or requested_id:find("^nomap_") or
      (info and tonumber(info.num) == -1) then
    render_local_nomap(window, opts.local_room_size)
    return true
  end

  local center_id = resolve_local_room_id(room_id)
  if not center_id then
    render_local_error(window, "Local map unavailable: current mapped room is unknown.")
    return false
  end

  local cache_generation = tonumber(mm.import and mm.import._layout_cache_generation) or 0
  local same_view = window.graph
    and tostring(window.local_center_id or "") == tostring(center_id)
    and tonumber(window.local_radius) == tonumber(opts.local_radius)
    and tonumber(window.local_room_size) == tonumber(opts.local_room_size)
    and tonumber(window.layout_cache_generation or 0) == cache_generation
  if same_view and not (update_opts and update_opts.force) then
    return true
  end

  local graph, err = build_local_graph(center_id, opts.local_radius)
  if not graph then
    render_local_error(window, "Local map unavailable: " .. tostring(err))
    return false
  end

  graph.local_room_size = opts.local_room_size
  window.graph = graph
  window.local_center_id = center_id
  window.local_radius = opts.local_radius
  window.local_room_size = opts.local_room_size
  window.layout_cache_generation = cache_generation
  mm.minimap.redraw("bigmap")
  return true
end

function mm.minimap.set_local_radius(radius)
  local opts = ensure_minimap_options()
  opts.local_radius = clamp_local_radius(radius)
  if mm.save_settings_persistence then
    mm.save_settings_persistence()
  end
  mm.minimap.update_local_map()
  mm.note(string.format("Bigmap local radius set to %d.", opts.local_radius))
end

function mm.minimap.set_local_room_size(room_size)
  local opts = ensure_minimap_options()
  opts.local_room_size = clamp_local_room_size(room_size)
  if mm.save_settings_persistence then
    mm.save_settings_persistence()
  end
  local window = mm.minimap.windows and mm.minimap.windows.bigmap
  if window and window.kind == "local_radius" and window.graph then
    window.local_room_size = opts.local_room_size
    window.graph.local_room_size = opts.local_room_size
    mm.minimap.redraw("bigmap")
  end
  mm.note(string.format("Bigmap local room size set to %d pixels.", opts.local_room_size))
end

local function ensure_native_bigmap_data()
  if not mm.load_native_mapper_db then return true end
  local native_path = mm.resolve_native_mapper_db and
    mm.resolve_native_mapper_db(mm.state and mm.state.native_mapper_db)
  local loaded_path = mm.runtime and mm.runtime.native_mapper_db_loaded_path
  if not native_path or native_path == loaded_path then return true end
  if not mm.path_exists(native_path) or mm.looks_like_sqlite(native_path) then return true end

  local loaded, load_err = mm.load_native_mapper_db()
  if not loaded then
    mm.warn("Native mapper DB was not loaded while switching displays: " .. tostring(load_err))
    return false
  end
  return true
end

local function activate_current_bigmap_surface(reason)
  destroy_window("bigmap")
  mm.minimap.lines = mm.minimap.lines or {}
  mm.minimap.lines.bigmap = {}
  create_window("bigmap")

  if active_bigmap_mode() == "local" then
    mm.minimap.update_local_map(nil, { force = true })
  elseif mm.minimap.backend == "mudlet_mapper" then
    if mm.schedule_native_mapper_load then
      mm.schedule_native_mapper_load(reason or "bigmap_backend_switch")
    else
      ensure_native_bigmap_data()
      if mm.sync_native_bigmap_to_current_room then
        mm.sync_native_bigmap_to_current_room(reason or "bigmap_backend_switch")
      end
    end
  end
  return true
end

local function navigation_destination()
  if not snd then return nil end
  return (snd.nav and snd.nav.goingToRoom) or
    (snd.mapper and snd.mapper.goingToRoom)
end

function mm.minimap.on_navigation_state_changed(reason)
  local opts = ensure_minimap_options()
  mm.runtime = mm.runtime or {}
  local destination = navigation_destination()

  if opts.bigmap_mode ~= "hybrid" then
    return false
  end

  mm.runtime.hybrid_navigation_active = destination and true or nil
  mm.runtime.hybrid_navigation_destination = destination and tostring(destination) or nil
  return false
end

function mm.minimap.set_bigmap_mode(mode)
  local requested = tostring(mode or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if requested ~= "local" and requested ~= "native" and requested ~= "hybrid" then
    mm.warn("Usage: mapper bigmap local|native|hybrid")
    return false
  end
  if mm.minimap.is_navigation_active() then
    mm.note("Bigmap mode change ignored while navigation is active.")
    return false
  end

  local opts = ensure_minimap_options()
  mm.runtime = mm.runtime or {}
  mm.runtime.hybrid_navigation_active = nil
  mm.runtime.hybrid_navigation_destination = nil
  mm.runtime.hybrid_bigmap_backend = nil
  mm.runtime.hybrid_native_unavailable_reason = nil
  opts.bigmap_mode = requested
  if mm.save_settings_persistence then
    mm.save_settings_persistence()
  end

  activate_current_bigmap_surface("bigmap_mode_switch")
  if requested == "native" and mm.minimap.backend ~= "mudlet_mapper" then
    opts.bigmap_mode = "local"
    if mm.save_settings_persistence then
      mm.save_settings_persistence()
    end
  end

  mm.note(string.format("Bigmap mode set to %s.", opts.bigmap_mode))
  return true
end

function mm.minimap.activate_bigmap_native()
  if active_bigmap_mode() == "native" then return false end
  mm.runtime = mm.runtime or {}
  if mm.runtime.hybrid_native_unavailable_reason then
    return false
  end
  mm.runtime.hybrid_bigmap_backend = "native"
  activate_current_bigmap_surface("gmcp_continent_room")
  return true
end

function mm.minimap.activate_bigmap_local()
  if active_bigmap_mode() == "local" then return false end
  mm.runtime = mm.runtime or {}
  mm.runtime.hybrid_bigmap_backend = "local"
  activate_current_bigmap_surface("gmcp_area_room")
  return true
end

function mm.minimap.get_bigmap_mode()
  local opts = ensure_minimap_options()
  return opts.bigmap_mode, opts.local_radius, opts.local_room_size
end

function mm.minimap.get_active_bigmap_mode()
  return active_bigmap_mode()
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
  if mm.minimap.backend ~= "local_radius" then
    mm.minimap.redraw("bigmap")
  end
end

function mm.minimap.redraw(which)
  local w = mm.minimap.windows and mm.minimap.windows[which]
  if not w then return end

  if which == "bigmap" and w.kind == "mudlet_mapper" then
    return
  end
  if which == "bigmap" and w.kind == "local_radius" then
    if w.graph then render_local_graphical(w, w.graph) end
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
