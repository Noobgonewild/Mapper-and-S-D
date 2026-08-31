mm = mm or {}

if type(mm.explore) == "table" and type(mm.explore.shutdown) == "function" then
  pcall(mm.explore.shutdown, true)
end

mm.explore = {
  version = "1.0.0",
  handlers = {},
  triggers = {},
}

local explore = mm.explore
local INACTIVITY_SECONDS = 5 * 60
local MOVEMENT_TIMEOUT_SECONDS = 10
local NEXT_COLOR = "@C"
local COLOR_END = "@D"
local direction_order = { "n", "s", "e", "w", "u", "d" }
local direction_rank = { n = 1, s = 2, e = 3, w = 4, u = 5, d = 6 }
local direction_names = {
  n = "north", s = "south", e = "east", w = "west", u = "up", d = "down",
}
local direction_aliases = {
  n = "n", north = "n",
  s = "s", south = "s",
  e = "e", east = "e",
  w = "w", west = "w",
  u = "u", up = "u",
  d = "d", down = "d",
}

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function clean(value)
  local text = mm.strip_ansi and mm.strip_ansi(value) or tostring(value or "")
  return trim(text:gsub("[\r\n\t]+", " "))
end

local function canonical_uid(value)
  local text = trim(value)
  local number = tonumber(text)
  if number then return tostring(math.floor(number)) end
  return text
end

local function current_room_uid()
  local room = mm.current_room and mm.current_room() or nil
  if room == nil then return nil end
  local uid = canonical_uid(room)
  return uid ~= "" and uid or nil
end

local function current_area()
  local info = mm.get_room_info and mm.get_room_info() or nil
  if type(info) ~= "table" then return nil end
  local area = clean(info.zone or info.area)
  return area ~= "" and area or nil
end

local function normalize_direction(value)
  return direction_aliases[trim(value):lower()]
end

local function display_direction(value)
  local dir = normalize_direction(value)
  return dir and direction_names[dir]:upper() or "?"
end

local function is_in_combat()
  local state
  if gmcp and gmcp.char and gmcp.char.status then
    state = gmcp.char.status.state
  end
  if state == nil and snd and snd.char then
    state = snd.char.state or (snd.char.status and snd.char.status.state)
  end
  return tonumber(state) == 8
end

local function new_runtime(generation)
  return {
    phase = "stopped",
    generation = tonumber(generation) or 0,
    rows = {},
    frontier = {},
    list_scope = nil,
    list_area = nil,
    selected = nil,
    expected_source = nil,
    pending_room = nil,
    deadline = nil,
    timeout_timer = nil,
    movement_deadline = nil,
    movement_timer = nil,
    movement_serial = 0,
    room_serial = 0,
    last_room_event_uid = nil,
    last_roomchars_serial = -1,
    prompt_pending = false,
    excluded_edges = {},
  }
end

explore.runtime = new_runtime(0)

local function runtime()
  explore.runtime = explore.runtime or new_runtime(0)
  return explore.runtime
end

local function kill_timeout_timer()
  local rt = runtime()
  if rt.timeout_timer and type(killTimer) == "function" then
    pcall(killTimer, rt.timeout_timer)
  end
  rt.timeout_timer = nil
end

local function kill_movement_timer()
  local rt = runtime()
  if rt.movement_timer and type(killTimer) == "function" then
    pcall(killTimer, rt.movement_timer)
  end
  rt.movement_timer = nil
  rt.movement_deadline = nil
end

local function emit_changed(reason)
  if type(raiseEvent) == "function" then
    raiseEvent("mm.explore.changed", tostring(reason or runtime().phase))
  end
end

function explore.on_timeout(generation, deadline)
  local rt = runtime()
  if rt.phase == "stopped" or rt.deadline == nil then return end
  if tonumber(generation) ~= tonumber(rt.generation) then return end
  if tonumber(deadline) ~= tonumber(rt.deadline) then return end
  if os.time() < tonumber(rt.deadline or 0) then return end
  explore.stop(false, "inactive")
end

function explore.on_movement_timeout(generation, movement_serial, movement_deadline)
  local rt = runtime()
  if tonumber(generation) ~= tonumber(rt.generation) then return end
  if tonumber(movement_serial) ~= tonumber(rt.movement_serial) then return end
  if tonumber(movement_deadline) ~= tonumber(rt.movement_deadline) then return end
  if os.time() < tonumber(rt.movement_deadline or 0) then return end
  if rt.phase ~= "crossing" and rt.phase ~= "travelling" then return end
  explore.recover_from_movement("movement_timeout")
end

local function arm_movement_timeout()
  local rt = runtime()
  kill_movement_timer()
  rt.movement_serial = (tonumber(rt.movement_serial) or 0) + 1
  rt.movement_deadline = os.time() + MOVEMENT_TIMEOUT_SECONDS
  if type(tempTimer) == "function" then
    local generation = rt.generation
    local movement_serial = rt.movement_serial
    local movement_deadline = rt.movement_deadline
    rt.movement_timer = tempTimer(MOVEMENT_TIMEOUT_SECONDS, function()
      explore.on_movement_timeout(generation, movement_serial, movement_deadline)
    end)
  end
end

local function arm_timeout(reset_deadline)
  local rt = runtime()
  kill_timeout_timer()
  if reset_deadline or not rt.deadline then
    rt.deadline = os.time() + INACTIVITY_SECONDS
  end
  local remaining = math.max(0, tonumber(rt.deadline) - os.time())
  if type(tempTimer) == "function" then
    local generation = rt.generation
    local deadline = rt.deadline
    rt.timeout_timer = tempTimer(remaining, function()
      explore.on_timeout(generation, deadline)
    end)
  end
end

local function touch_activity()
  arm_timeout(true)
  emit_changed("activity")
end

local function start_session_clock()
  arm_timeout(false)
end

local function explore_prefix()
  if type(cecho) == "function" then
    cecho("<CornflowerBlue>[MMAPPER EXPLORE]<reset> ")
  elseif type(echo) == "function" then
    echo("[MMAPPER EXPLORE] ")
  end
end

local function render_mush_colors(value)
  local text = tostring(value or "")
  if snd and snd.utils and type(snd.utils.aardColorsToMudlet) == "function" then
    return snd.utils.aardColorsToMudlet(text)
  end
  -- Explore only needs the two Aardwolf/MUSH colors documented in Colors.txt.
  return text:gsub("@C", "<cyan>"):gsub("@D", "<gray>")
end

local function link_or_echo(label, command, tooltip, enabled, color)
  if enabled ~= false and color and type(cechoLink) == "function" then
    cechoLink(render_mush_colors(color .. label), command, tooltip or "", true)
  elseif enabled ~= false and type(echoLink) == "function" then
    echoLink(label, command, tooltip or "", true)
  elseif color and type(cecho) == "function" then
    cecho(render_mush_colors(color .. label))
  elseif type(echo) == "function" then
    echo(label)
  end
end

local function edge_is_actionable(row)
  local source = tonumber(row and row.uid)
  local target = canonical_uid(row and row.touid)
  local dir = normalize_direction(row and row.dir)
  local level = tonumber(row and row.level) or 0
  return source ~= nil and source > 0 and target ~= "" and target ~= "-1"
    and dir ~= nil and level < 999
end

local function normalize_edge(row)
  if not edge_is_actionable(row) then return nil end
  return {
    uid = canonical_uid(row.uid),
    name = clean(row.name) ~= "" and clean(row.name) or "?",
    area = clean(row.area) ~= "" and clean(row.area) or "?",
    dir = normalize_direction(row.dir),
    touid = canonical_uid(row.touid),
    level = tonumber(row.level) or 0,
  }
end

local function edge_key(edge)
  return table.concat({
    canonical_uid(edge and edge.uid),
    normalize_direction(edge and edge.dir) or "?",
    canonical_uid(edge and edge.touid),
  }, "|")
end

local function edge_sort(a, b)
  local aa, ba = tostring(a.area or ""):lower(), tostring(b.area or ""):lower()
  if aa ~= ba then return aa < ba end
  local auid, buid = tonumber(a.uid), tonumber(b.uid)
  if auid and buid and auid ~= buid then return auid < buid end
  if tostring(a.uid) ~= tostring(b.uid) then return tostring(a.uid) < tostring(b.uid) end
  local ad, bd = direction_rank[a.dir] or 99, direction_rank[b.dir] or 99
  if ad ~= bd then return ad < bd end
  return tostring(a.touid) < tostring(b.touid)
end

local function query_unmapped_edges(where_sql)
  local where = trim(where_sql)
  if where ~= "" then where = " AND (" .. where .. ")" end
  local rows, err = mm.query_mapper_db([[
    SELECT rooms.uid AS uid,
           rooms.name AS name,
           rooms.area AS area,
           exits.dir AS dir,
           exits.touid AS touid,
           COALESCE(exits.level, 0) AS level
    FROM rooms
    INNER JOIN exits ON rooms.uid = exits.fromuid
    WHERE exits.touid != -1
      AND NOT EXISTS (SELECT 1 FROM rooms destination WHERE destination.uid = exits.touid)
  ]] .. where)
  if not rows then return nil, err end

  local result = {}
  for _, row in ipairs(rows) do
    local edge = normalize_edge(row)
    if edge and not runtime().excluded_edges[edge_key(edge)] then
      result[#result + 1] = edge
    end
  end
  table.sort(result, edge_sort)
  return result
end

local function query_room_frontier(room_uid)
  local room = tonumber(room_uid)
  if not room then return nil, "invalid source room" end
  return query_unmapped_edges("rooms.uid = " .. mm.sql_escape(math.floor(room)))
end

local function room_exists(room_uid)
  local rows = mm.query_mapper_db(
    "SELECT uid FROM rooms WHERE uid = " .. mm.sql_escape(canonical_uid(room_uid)) .. " LIMIT 1"
  )
  return rows and rows[1] ~= nil
end

local function same_edge(a, b)
  return a and b
    and canonical_uid(a.uid) == canonical_uid(b.uid)
    and normalize_direction(a.dir) == normalize_direction(b.dir)
    and canonical_uid(a.touid) == canonical_uid(b.touid)
end

local function find_edge(rows, direction, target)
  local wanted_dir = normalize_direction(direction)
  local wanted_target = target and canonical_uid(target) or nil
  for _, row in ipairs(rows or {}) do
    if (not wanted_dir or row.dir == wanted_dir)
        and (not wanted_target or canonical_uid(row.touid) == wanted_target) then
      return row
    end
  end
  return nil
end

local function find_frontier_target(rows, room_uid)
  local target = canonical_uid(room_uid)
  for _, row in ipairs(rows or {}) do
    if canonical_uid(row.touid) == target then return row end
  end
  return nil
end

local function edge_still_unmapped(edge)
  local rows, err = query_room_frontier(edge and edge.uid)
  if not rows then return false, err end
  local current = find_edge(rows, edge.dir, edge.touid)
  if not current then return false, "selected exit is no longer unmapped" end
  return true, current, rows
end

local function filter_frontier_by_live_exits(rows, source_uid)
  local source = canonical_uid(source_uid)
  if current_room_uid() ~= source then return rows or {}, {} end
  local info = mm.get_room_info and mm.get_room_info() or nil
  if type(info) ~= "table" or canonical_uid(info.num) ~= source or type(info.exits) ~= "table" then
    return rows or {}, {}
  end

  local live = {}
  for raw_direction, raw_target in pairs(info.exits) do
    local direction = normalize_direction(raw_direction)
    if direction then live[direction] = canonical_uid(raw_target) end
  end

  local filtered, rejected = {}, {}
  for _, edge in ipairs(rows or {}) do
    local live_target = live[edge.dir]
    if live_target ~= nil and live_target == canonical_uid(edge.touid) then
      filtered[#filtered + 1] = edge
    else
      runtime().excluded_edges[edge_key(edge)] = true
      rejected[#rejected + 1] = edge
    end
  end
  return filtered, rejected
end

local function print_ready()
  local rt = runtime()
  local edge = rt.selected
  if not edge then return end
  explore_prefix()
  if type(cecho) == "function" then cecho(render_mush_colors(NEXT_COLOR .. "Next: ")) else echo("Next: ") end
  local generation = rt.generation
  link_or_echo(
    display_direction(edge.dir),
    string.format("mm.explore.next(nil, %d)", generation),
    "mapper explore next",
    true,
    NEXT_COLOR
  )
  if type(cecho) == "function" then cecho(render_mush_colors("." .. COLOR_END .. "\n")) else echo(".\n") end
end

local function print_choices()
  local rt = runtime()
  explore_prefix()
  if type(cecho) == "function" then cecho(render_mush_colors(NEXT_COLOR .. "Next: ")) else echo("Next: ") end
  for index, edge in ipairs(rt.frontier or {}) do
    if index > 1 then
      if type(cecho) == "function" then cecho(render_mush_colors(NEXT_COLOR .. " / ")) else echo(" / ") end
    end
    link_or_echo(
      display_direction(edge.dir),
      string.format("mm.explore.next(%q, %d)", edge.dir, rt.generation),
      "mapper explore next " .. tostring(edge.dir),
      true,
      NEXT_COLOR
    )
  end
  if type(cecho) == "function" then cecho(render_mush_colors("." .. COLOR_END .. "\n")) else echo(".\n") end
end

local function print_combat_pause()
  local edge = runtime().selected
  explore_prefix()
  if type(cecho) == "function" then
    cecho(render_mush_colors(
      NEXT_COLOR .. "Next: " .. display_direction(edge and edge.dir) .. COLOR_END .. " — paused (combat).\n"
    ))
  else
    echo("Next: " .. display_direction(edge and edge.dir) .. " — paused (combat).\n")
  end
end

local function print_frontier_prompt()
  local rt = runtime()
  rt.prompt_pending = false
  if rt.phase == "combat" then
    print_combat_pause()
  elseif rt.phase == "choose" then
    print_choices()
  elseif rt.phase == "ready" then
    print_ready()
  end
end

local function show_frontier_prompt_after_roomchars(defer_prompt)
  local rt = runtime()
  rt.prompt_pending = false
  if defer_prompt then
    if tonumber(rt.last_roomchars_serial) ~= tonumber(rt.room_serial) then
      rt.prompt_pending = true
      return
    end
  end
  print_frontier_prompt()
end

local function print_off_source()
  local rt = runtime()
  local current = current_room_uid() or "?"
  local expected = canonical_uid(rt.expected_source)
  explore_prefix()
  echo(string.format("Next unavailable — expected %s, currently %s. ", expected, current))
  local command = "xrt " .. expected
  link_or_echo(command, string.format("expandAlias(%q)", command), command, expected ~= "")
  echo(" to continue.\n")
end

local function set_off_source()
  local rt = runtime()
  local announce = rt.phase ~= "off_source"
  kill_movement_timer()
  rt.prompt_pending = false
  rt.phase = "off_source"
  rt.pending_room = nil
  if announce then print_off_source() end
  emit_changed("off_source")
end

local function set_frontier_ready(rows, preferred, defer_prompt)
  local rt = runtime()
  kill_movement_timer()
  local filtered, rejected = filter_frontier_by_live_exits(rows, rt.expected_source)
  rt.frontier = filtered
  rt.pending_room = nil
  if #rejected > 0 then
    local rejected_directions = {}
    for _, edge in ipairs(rejected) do
      rejected_directions[#rejected_directions + 1] = display_direction(edge.dir)
    end
    explore_prefix()
    echo("Ignored stale exit: " .. table.concat(rejected_directions, ", ") .. ".\n")
  end
  rt.selected = preferred and find_edge(rt.frontier, preferred.dir, preferred.touid) or nil
  if not rt.selected and #rt.frontier == 1 then rt.selected = rt.frontier[1] end

  if rt.selected then
    rt.phase = is_in_combat() and "combat" or "ready"
  elseif #rt.frontier > 1 then
    rt.phase = "choose"
  else
    return false
  end
  show_frontier_prompt_after_roomchars(defer_prompt == true)
  emit_changed("frontier_ready")
  return true
end

local function prepare_expected_source(preferred)
  local rt = runtime()
  local source = canonical_uid(rt.expected_source)
  local rows, err = query_room_frontier(source)
  if not rows then return false, err end
  if set_frontier_ready(rows, preferred, true) then return true end
  return explore.show_unmapped("here", { internal = true })
end

local function complete_frontier_arrival(room_uid)
  local rt = runtime()
  local room = canonical_uid(room_uid)
  rt.expected_source = room
  rt.selected = nil
  rt.pending_room = nil
  local rows, err = query_room_frontier(room)
  if not rows then
    rt.phase = "off_source"
    emit_changed("frontier_query_failed")
    return false, err
  end
  if set_frontier_ready(rows, nil, true) then return true end
  return explore.show_unmapped("here", { internal = true })
end

local function begin_settling(room_uid)
  local rt = runtime()
  kill_movement_timer()
  local room = canonical_uid(room_uid)
  rt.phase = "settling"
  rt.pending_room = room
  emit_changed("settling")
  if room_exists(room) then
    return complete_frontier_arrival(room)
  end
  return true
end

local function set_detail_list(rows, scope, area, opts)
  local rt = runtime()
  kill_timeout_timer()
  kill_movement_timer()
  rt.generation = (tonumber(rt.generation) or 0) + 1
  rt.phase = "list_ready"
  rt.rows = rows
  rt.frontier = {}
  rt.list_scope = scope
  rt.list_area = area
  rt.selected = nil
  rt.expected_source = nil
  rt.pending_room = nil
  rt.prompt_pending = false
  if not (opts and opts.internal) or not rt.deadline then start_session_clock() else arm_timeout(false) end
  emit_changed("list_ready")
end

local function print_detail_table(rows)
  local rt = runtime()
  cecho("<cyan>Rooms with unmapped exits<reset>\n")
  cecho("<gray>-------------------------------------------------------------------------------------------------------------------------<reset>\n")
  cecho(string.format(
    "<white>| %-3s | %-24s | %-28s | %-8s | %-5s | %-8s |<reset>\n",
    "##", "area", "room name", "rm uid", "dir", "to uid"
  ))
  cecho("<gray>-------------------------------------------------------------------------------------------------------------------------<reset>\n")
  for index, row in ipairs(rows) do
    cecho("| ")
    link_or_echo(
      string.format("%-3d", index),
      string.format("mm.explore.select(%d, %d)", index, rt.generation),
      "mapper explore " .. tostring(index),
      true
    )
    cecho(string.format(
      " | %-24.24s | %-28.28s | %-8s | %-5s | %-8s |\n",
      tostring(row.area or "?"),
      tostring(row.name or "?"),
      tostring(row.uid or "?"),
      tostring(row.dir or "?"),
      tostring(row.touid or "?")
    ))
  end
  cecho("<gray>-------------------------------------------------------------------------------------------------------------------------<reset>\n")
end

function explore.show_unmapped(raw_arg, opts)
  opts = opts or {}
  local arg = trim(raw_arg)
  if arg == "" then
    local rows, err = query_unmapped_edges("")
    if not rows then return false, err end
    if #rows == 0 then
      mm.note("No unmapped exits found.")
      return true
    end
    local counts, areas = {}, {}
    for _, row in ipairs(rows) do
      local area = row.area ~= "" and row.area or "?"
      if not counts[area] then areas[#areas + 1] = area end
      counts[area] = (counts[area] or 0) + 1
    end
    table.sort(areas, function(a, b) return a:lower() < b:lower() end)
    cecho("<cyan>Unmapped exits by area<reset>\n")
    cecho("<gray>--------------------------------------------------------------------<reset>\n")
    cecho(string.format("<white>| %-50s | %5s |<reset>\n", "area", "count"))
    cecho("<gray>--------------------------------------------------------------------<reset>\n")
    for _, area in ipairs(areas) do
      cecho(string.format("| %-50.50s | %5d |\n", area, counts[area]))
    end
    cecho("<gray>--------------------------------------------------------------------<reset>\n")
    return true
  end

  local area = arg
  local where_area_sql
  if arg:lower() == "here" then
    area = current_area()
    if not area then return false, "current area is unknown; try LOOK first" end
    where_area_sql = "lower(rooms.area) = " .. mm.sql_escape(area:lower())
  else
    where_area_sql = "lower(rooms.area) LIKE " .. mm.sql_escape("%" .. area:lower() .. "%")
  end

  local rows, err = query_unmapped_edges(where_area_sql)
  if not rows then return false, err end
  if #rows == 0 then
    if opts.keep_open then
      local rt = runtime()
      kill_movement_timer()
      rt.phase = "blocked"
      rt.rows = {}
      rt.frontier = {}
      rt.selected = nil
      rt.expected_source = current_room_uid()
      rt.pending_room = nil
      rt.prompt_pending = false
      emit_changed("no_unmapped_here")
    else
      explore.stop(true)
    end
    mm.note("No unmapped exits found for area filter: " .. tostring(area))
    return true
  end

  set_detail_list(rows, arg:lower() == "here" and "here" or "area", area, opts)
  print_detail_table(rows)
  return true
end

mm.show_unmapped = function(raw_arg)
  return explore.show_unmapped(raw_arg)
end

function explore.select(index, generation)
  local rt = runtime()
  if generation ~= nil and tonumber(generation) ~= tonumber(rt.generation) then
    return false, "that unmapped-list link is stale; print the list again"
  end
  local row_index = tonumber(index)
  if not row_index or row_index < 1 or row_index > #(rt.rows or {}) then
    return false, "unmapped index out of range"
  end
  touch_activity()
  local edge = rt.rows[row_index]
  local ok, current_or_err, frontier = edge_still_unmapped(edge)
  if not ok then return false, current_or_err end
  edge = current_or_err
  rt.selected = edge
  rt.frontier = frontier or { edge }
  rt.expected_source = edge.uid
  rt.pending_room = nil

  if current_room_uid() == canonical_uid(edge.uid) then
    if set_frontier_ready(rt.frontier, edge) then return true end
    return explore.show_unmapped("here", { internal = true })
  end

  rt.phase = "travelling"
  arm_movement_timeout()
  emit_changed("travelling")
  local moved, move_err = mm.walkto_room(edge.uid)
  if not moved then
    kill_movement_timer()
    rt.phase = "list_ready"
    rt.selected = nil
    rt.frontier = {}
    rt.expected_source = nil
    emit_changed("travel_rejected")
    return false, move_err
  end
  return true
end

local function choose_edge(choice)
  local rt = runtime()
  if choice ~= nil and trim(choice) ~= "" then
    local direction = normalize_direction(choice)
    if direction then return find_edge(rt.frontier, direction, nil) end
    local index = tonumber(choice)
    if index then return rt.frontier[index] end
    return nil
  end
  if rt.selected then return rt.selected end
  return (rt.frontier or {})[1]
end

function explore.next(choice, generation)
  local rt = runtime()
  if generation ~= nil and tonumber(generation) ~= tonumber(rt.generation) then
    return false, "that Explore link is stale"
  end
  if rt.phase == "stopped" or rt.phase == "list_ready" or rt.phase == "travelling"
      or rt.phase == "settling" or rt.phase == "blocked" then
    return false, "Explore Next is not ready"
  end
  touch_activity()

  local edge = choose_edge(choice)
  if not edge then
    if choice ~= nil and trim(choice) ~= "" then
      return false, "that direction is not an unmapped exit here"
    end
    return false, "no unmapped exit is ready here"
  end
  rt.selected = edge
  rt.expected_source = edge.uid

  local current = current_room_uid()
  if current ~= canonical_uid(rt.expected_source) then
    set_off_source()
    return true
  end
  if is_in_combat() then
    rt.phase = "combat"
    print_combat_pause()
    emit_changed("combat")
    return true
  end

  local valid, current_edge, frontier = edge_still_unmapped(edge)
  if not valid then return false, current_edge end
  rt.selected = current_edge
  rt.frontier = frontier or { current_edge }
  rt.phase = "crossing"
  arm_movement_timeout()
  emit_changed("crossing")
  if type(send) == "function" then
    send(current_edge.dir, false)
  elseif type(expandAlias) == "function" then
    expandAlias(current_edge.dir)
  else
    kill_movement_timer()
    rt.phase = "ready"
    emit_changed("movement_unavailable")
    return false, "movement sender is unavailable"
  end
  return true
end

function explore.status()
  local view = explore.get_view()
  if view.phase == "stopped" then
    mm.note("Explore is stopped.")
  elseif view.phase == "ready" or view.phase == "combat" then
    mm.note(string.format(
      "Explore %s; next %s from room %s; timeout %ds.",
      view.phase,
      tostring(view.direction or "?"),
      tostring(view.expected_source or "?"),
      tonumber(view.remaining) or 0
    ))
  else
    mm.note(string.format("Explore %s; timeout %ds.", view.phase, tonumber(view.remaining) or 0))
  end
  return true
end

function explore.stop(silent, reason)
  local old = runtime()
  local old_phase = old.phase
  local direction = old.selected and display_direction(old.selected.dir) or "movement"
  local expected_source = canonical_uid(old.expected_source)
  -- Invalidate the state before touching the Mudlet timer. Even if an already
  -- queued callback still executes, it must observe a stopped, deadline-free session.
  old.phase = "stopped"
  old.deadline = nil
  kill_timeout_timer()
  kill_movement_timer()
  local generation = (tonumber(old.generation) or 0) + 1
  explore.runtime = new_runtime(generation)
  emit_changed(reason or "stopped")
  if not silent then
    if reason == "inactive" then
      explore_prefix()
      echo("Stopped — inactive 5 minutes.\n")
    elseif reason == "movement_blocked" then
      explore_prefix()
      if old_phase == "travelling" then
        echo(string.format("Stopped — navigation to room %s was blocked.\n", expected_source ~= "" and expected_source or "?"))
      else
        echo(string.format("Stopped — %s was blocked; still in room %s.\n", direction, expected_source ~= "" and expected_source or "?"))
      end
    elseif reason == "movement_timeout" then
      explore_prefix()
      if old_phase == "travelling" then
        echo(string.format(
          "Stopped — navigation to room %s made no progress for 10 seconds.\n",
          expected_source ~= "" and expected_source or "?"
        ))
      else
        echo(string.format("Stopped — %s did not move you within 10 seconds.\n", direction))
      end
    elseif reason == "movement_failed" then
      explore_prefix()
      echo(string.format("Stopped — %s did not move you.\n", direction))
    else
      explore_prefix()
      echo("Stopped.\n")
    end
  end
  return true
end

function explore.recover_from_movement(reason)
  local rt = runtime()
  local old_phase = rt.phase
  if old_phase ~= "crossing" and old_phase ~= "travelling" then return false end
  local blocked_edge = rt.selected
  local direction = blocked_edge and display_direction(blocked_edge.dir) or "movement"
  local expected_source = canonical_uid(rt.expected_source)
  local remaining = {}

  if old_phase == "crossing" and blocked_edge then
    local blocked_key = edge_key(blocked_edge)
    rt.excluded_edges[blocked_key] = true
    for _, edge in ipairs(rt.frontier or {}) do
      if edge_key(edge) ~= blocked_key then remaining[#remaining + 1] = edge end
    end
  end
  kill_movement_timer()
  rt.pending_room = nil
  rt.prompt_pending = false

  explore_prefix()
  if reason == "movement_timeout" then
    if old_phase == "travelling" then
      echo(string.format(
        "navigation to room %s made no progress for 10 seconds.\n",
        expected_source ~= "" and expected_source or "?"
      ))
    else
      echo(string.format("%s did not move you within 10 seconds.\n", direction))
    end
  elseif reason == "movement_failed" then
    echo(string.format("%s did not move you.\n", direction))
  elseif old_phase == "travelling" then
    echo(string.format("navigation to room %s was blocked.\n", expected_source ~= "" and expected_source or "?"))
  else
    echo(string.format("%s was blocked; still in room %s.\n", direction, expected_source ~= "" and expected_source or "?"))
  end

  if old_phase == "crossing" and #remaining > 0 then
    rt.selected = nil
    if set_frontier_ready(remaining, nil, false) then return true end
  end

  rt.phase = "blocked"
  rt.selected = nil
  rt.frontier = {}
  rt.expected_source = current_room_uid() or rt.expected_source
  emit_changed(reason or "blocked")
  return true
end

function explore.refresh_here()
  touch_activity()
  return explore.show_unmapped("here", { internal = true, keep_open = true })
end

function explore.get_view()
  local rt = runtime()
  local current = current_room_uid()
  local primary_edge = rt.selected or (rt.frontier and rt.frontier[1]) or nil
  local remaining = rt.deadline and math.max(0, rt.deadline - os.time()) or 0
  local movement_remaining = rt.movement_deadline and math.max(0, rt.movement_deadline - os.time()) or 0
  return {
    phase = rt.phase,
    generation = rt.generation,
    direction = primary_edge and display_direction(primary_edge.dir) or nil,
    direction_command = primary_edge and primary_edge.dir or nil,
    destination = primary_edge and primary_edge.touid or nil,
    expected_source = rt.expected_source,
    current_room = current,
    remaining = remaining,
    movement_remaining = movement_remaining,
    list_count = #(rt.rows or {}),
    frontier_count = #(rt.frontier or {}),
  }
end

function explore.on_room_changed(_, room_uid)
  local rt = runtime()
  if rt.phase == "stopped" or rt.phase == "list_ready" then return end
  local current = canonical_uid(room_uid)
  if current == "" then current = current_room_uid() or "" end
  if current == "" then return end
  if current ~= canonical_uid(rt.last_room_event_uid) then
    rt.room_serial = (tonumber(rt.room_serial) or 0) + 1
    rt.last_room_event_uid = current
  end

  if rt.phase == "crossing" then
    if current == canonical_uid(rt.expected_source) then
      explore.recover_from_movement("movement_failed")
      return
    end
    kill_movement_timer()
  end

  if rt.phase == "travelling" then
    if current == canonical_uid(rt.expected_source) then
      local preferred = rt.selected
      local ok, err = prepare_expected_source(preferred)
      if not ok and mm.warn then mm.warn(err) end
    else
      -- Route travel may legitimately take longer than ten seconds overall.
      -- Each room arrival proves progress and restarts the stall watchdog.
      arm_movement_timeout()
    end
    return
  end

  if rt.phase == "settling" then
    if current == canonical_uid(rt.pending_room) and room_exists(current) then
      local ok, err = complete_frontier_arrival(current)
      if not ok and mm.warn then mm.warn(err) end
    end
    return
  end

  local expected = canonical_uid(rt.expected_source)
  if current == expected then
    if rt.phase == "off_source" then
      local ok, err = prepare_expected_source(rt.selected)
      if not ok and mm.warn then mm.warn(err) end
    end
    return
  end

  local crossed = find_frontier_target(rt.frontier, current)
  if crossed then
    rt.selected = crossed
    local ok, err = begin_settling(current)
    if not ok and mm.warn then mm.warn(err) end
    return
  end

  if rt.phase == "ready" or rt.phase == "combat" or rt.phase == "choose"
      or rt.phase == "crossing" or rt.phase == "off_source" then
    set_off_source()
  end
end

function explore.flush_room_prompt(generation, room_serial, room_uid)
  local rt = runtime()
  if tonumber(generation) ~= tonumber(rt.generation) then return false end
  if tonumber(room_serial) ~= tonumber(rt.room_serial) then return false end
  if canonical_uid(room_uid) ~= canonical_uid(current_room_uid()) then return false end
  if not rt.prompt_pending then return false end
  if rt.phase ~= "ready" and rt.phase ~= "combat" and rt.phase ~= "choose" then return false end
  print_frontier_prompt()
  emit_changed("room_prompt")
  return true
end

function explore.on_roomchars_end()
  local rt = runtime()
  local current = current_room_uid()
  if not current then return false end
  rt.last_roomchars_serial = rt.room_serial
  if not rt.prompt_pending then return false end
  local generation = rt.generation
  local room_serial = rt.room_serial
  if type(tempTimer) == "function" then
    tempTimer(0, function()
      explore.flush_room_prompt(generation, room_serial, current)
    end)
  else
    explore.flush_room_prompt(generation, room_serial, current)
  end
  return true
end

function explore.on_movement_blocked()
  local phase = runtime().phase
  if phase ~= "crossing" and phase ~= "travelling" then return false end
  return explore.recover_from_movement("movement_blocked")
end

function explore.on_mapper_db_updated(_, room_uid)
  local rt = runtime()
  if rt.phase ~= "settling" then return end
  local updated = canonical_uid(room_uid)
  if updated ~= "" and updated ~= canonical_uid(rt.pending_room) then return end
  local ok, err = complete_frontier_arrival(rt.pending_room)
  if not ok and mm.warn then mm.warn(err) end
end

function explore.on_char_status()
  local rt = runtime()
  if rt.phase == "stopped" or rt.phase == "list_ready" or rt.phase == "travelling"
      or rt.phase == "settling" or rt.phase == "off_source" or rt.phase == "blocked" then
    return
  end
  if is_in_combat() then
    if rt.phase == "ready" then
      rt.phase = "combat"
      if not rt.prompt_pending then print_combat_pause() end
      emit_changed("combat")
    end
    return
  end
  if rt.phase == "combat" then
    if current_room_uid() == canonical_uid(rt.expected_source) then
      rt.phase = "ready"
      if not rt.prompt_pending then print_ready() end
      emit_changed("combat_ended")
    else
      set_off_source()
    end
  end
end

function explore.shutdown(silent)
  explore.stop(silent ~= false, "shutdown")
  for _, handler_id in pairs(explore.handlers or {}) do
    if handler_id and type(killAnonymousEventHandler) == "function" then
      pcall(killAnonymousEventHandler, handler_id)
    end
  end
  explore.handlers = {}
  for _, trigger_id in pairs(explore.triggers or {}) do
    if trigger_id and type(killTrigger) == "function" then
      pcall(killTrigger, trigger_id)
    end
  end
  explore.triggers = {}
end

function explore.initialize()
  explore.stop(true, "initialize")
  if type(registerAnonymousEventHandler) == "function" then
    explore.handlers.room = registerAnonymousEventHandler("mm.room.changed", "mm.explore.on_room_changed")
    explore.handlers.database = registerAnonymousEventHandler("mm.mapper.db.updated", "mm.explore.on_mapper_db_updated")
    explore.handlers.combat = registerAnonymousEventHandler("gmcp.char.status", "mm.explore.on_char_status")
    explore.handlers.exit = registerAnonymousEventHandler("sysExitEvent", function() explore.shutdown(true) end)
  end
  if type(tempRegexTrigger) == "function" then
    explore.triggers.ward_bounce = tempRegexTrigger(
      "^Magical wards around .+ bounce you back\\.$",
      "mm.explore.on_movement_blocked()"
    )
    explore.triggers.private_room = tempRegexTrigger(
      "^That is a privately owned room\\. You cannot enter without invitation\\.$",
      "mm.explore.on_movement_blocked()"
    )
    explore.triggers.roomchars_end = tempRegexTrigger(
      "^\\{/roomchars\\}$",
      "mm.explore.on_roomchars_end()"
    )
  end
  return true
end

function explore.command(raw_command)
  local command = trim(raw_command)
  if command == "" or command:lower() == "status" then return explore.status() end
  if command:lower() == "stop" then return explore.stop(false) end
  local next_arg = command:match("^[Nn][Ee][Xx][Tt]%s*(.*)$")
  if next_arg ~= nil then
    next_arg = trim(next_arg)
    return explore.next(next_arg ~= "" and next_arg or nil)
  end
  local index = command:match("^(%d+)$")
  if index then return explore.select(index) end
  return false, "Usage: mapper explore <index|next [direction]|stop|status>"
end
