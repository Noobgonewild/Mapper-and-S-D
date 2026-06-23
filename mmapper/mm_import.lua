mm = mm or {}
mm.import = mm.import or {}

local function require_luasql()
  local ok, mod = pcall(require, "luasql.sqlite3")
  if not ok then
    return nil, "LuaSQL sqlite3 module not available"
  end
  return mod
end

local function open_sqlite(path)
  local luasql, err = require_luasql()
  if not luasql then return nil, nil, err end

  local env = luasql.sqlite3()
  if not env then
    return nil, nil, "failed to create sqlite3 environment"
  end

  local conn, conn_err = env:connect(path)
  if not conn then
    env:close()
    return nil, nil, "failed to connect sqlite DB: " .. tostring(conn_err)
  end

  return env, conn
end

local function sqlite_query(conn, sql)
  local cursor, err = conn:execute(sql)
  if not cursor then
    return nil, tostring(err)
  end

  local rows = {}
  local row = cursor:fetch({}, "a")
  while row do
    local copy = {}
    for k, v in pairs(row) do
      copy[k] = v
    end
    table.insert(rows, copy)
    row = cursor:fetch(row, "a")
  end
  cursor:close()
  return rows
end

local function get_columns(conn, table_name)
  local rows, err = sqlite_query(conn, string.format("PRAGMA table_info('%s')", table_name))
  if not rows then return nil, err end

  local cols = {}
  for _, row in ipairs(rows) do
    cols[row.name] = true
  end
  return cols
end

local function has_col(cols, name)
  return cols and cols[name] == true
end

function mm.import.inspect_sqlite(source_path)
  local source = mm.resolve_native_mapper_db(source_path)
  if not source or not mm.path_exists(source) then
    return false, "source DB not found: " .. tostring(source)
  end

  local env, conn, openErr = open_sqlite(source)
  if not conn then
    return false, openErr
  end

  local ok, data = pcall(function()
    local tables = {}
    local tblRows, tblErr = sqlite_query(conn, "SELECT name FROM sqlite_master WHERE type='table'")
    if not tblRows then error(tblErr) end
    for _, row in ipairs(tblRows) do
      tables[row.name] = true
    end

    local roomCols = get_columns(conn, "rooms") or {}
    local exitCols = get_columns(conn, "exits") or {}

    local roomCount = sqlite_query(conn, "SELECT COUNT(*) AS cnt FROM rooms")
    local exitCount = sqlite_query(conn, "SELECT COUNT(*) AS cnt FROM exits")

    local out = {
      path = source,
      has_rooms = tables.rooms == true,
      has_exits = tables.exits == true,
      room_columns = roomCols,
      exit_columns = exitCols,
      room_count = tonumber(roomCount and roomCount[1] and roomCount[1].cnt) or 0,
      exit_count = tonumber(exitCount and exitCount[1] and exitCount[1].cnt) or 0,
    }

    -- rooms.x/y/z are Aardwolf continent coordinates, not Mudlet area-layout
    -- coordinates.  A native map can be rebuilt without those columns because
    -- local room positions are derived from cardinal exits below.
    local required_rooms = { "uid", "name", "area" }
    local required_exits = { "fromuid", "touid", "dir" }

    out.compatible = out.has_rooms and out.has_exits
    out.missing = {}

    for _, col in ipairs(required_rooms) do
      if not has_col(roomCols, col) then
        out.compatible = false
        table.insert(out.missing, "rooms." .. col)
      end
    end
    for _, col in ipairs(required_exits) do
      if not has_col(exitCols, col) then
        out.compatible = false
        table.insert(out.missing, "exits." .. col)
      end
    end

    return out
  end)

  conn:close()
  env:close()

  if not ok then
    return false, tostring(data)
  end

  return true, data
end

local cardinal = {
  n = { name = "north", dx = 0, dy = 1, dz = 0, inverse = "s", order = 1 },
  e = { name = "east",  dx = 1, dy = 0, dz = 0, inverse = "w", order = 2 },
  s = { name = "south", dx = 0, dy = -1, dz = 0, inverse = "n", order = 3 },
  w = { name = "west",  dx = -1, dy = 0, dz = 0, inverse = "e", order = 4 },
  u = { name = "up",    dx = 0, dy = 0, dz = 1, inverse = "d", order = 5 },
  d = { name = "down",  dx = 0, dy = 0, dz = -1, inverse = "u", order = 6 },
}

local cardinal_alias = {
  n = "n", north = "n", e = "e", east = "e",
  s = "s", south = "s", w = "w", west = "w",
  u = "u", up = "u", d = "d", down = "d",
}

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_cardinal(dir)
  return cardinal_alias[trim(dir):lower()]
end

local function sql_literal(value)
  if value == nil then return "NULL" end
  return "'" .. tostring(value):gsub("'", "''") .. "'"
end

local function area_condition(column, value)
  if value == nil then return column .. " IS NULL" end
  return column .. " = " .. sql_literal(value)
end

local function area_label(area)
  local label = trim(area and area.key or "")
  return label ~= "" and label or "<no area>"
end

local function coord_key(x, y, z)
  return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function add_layout_edge(graph, from_id, to_id, dir)
  local def = cardinal[dir]
  if not def then return end
  graph.adjacency[from_id] = graph.adjacency[from_id] or {}
  graph.adjacency_seen[from_id] = graph.adjacency_seen[from_id] or {}
  local key = tostring(to_id) .. ":" .. dir
  if graph.adjacency_seen[from_id][key] then return end
  graph.adjacency_seen[from_id][key] = true
  table.insert(graph.adjacency[from_id], {
    to = to_id,
    dir = dir,
    dx = def.dx,
    dy = def.dy,
    dz = def.dz,
    order = def.order,
  })
end

local function load_layout_graph(source_path, opts)
  opts = opts or {}
  local ok_inspect, inspect = mm.import.inspect_sqlite(source_path)
  if not ok_inspect then return nil, inspect end
  if not inspect.compatible then
    return nil, "schema mismatch. missing columns: " .. table.concat(inspect.missing or {}, ", ")
  end

  local env, conn, open_err = open_sqlite(inspect.path)
  if not conn then return nil, open_err end

  local ok, graph_or_err = pcall(function()
    local selected_area = nil
    local selected_area_known = false
    if opts.room_id then
      local selected_room_id = tonumber(opts.room_id)
      local area_rows, area_err = sqlite_query(conn,
        "SELECT area FROM rooms WHERE uid = " .. sql_literal(selected_room_id or opts.room_id) .. " LIMIT 1")
      if not area_rows then error(area_err) end
      if #area_rows > 0 then
        selected_area = area_rows[1].area
      elseif selected_room_id then
        -- A numeric room may already have usable exits before its metadata row
        -- reaches rooms.  A direct cardinal neighbour is enough to infer which
        -- area should be rebuilt.
        local neighbour_sql =
          "SELECT DISTINCT neighbour.area AS area FROM exits e " ..
          "JOIN rooms neighbour ON neighbour.uid = e.touid " ..
          "WHERE e.fromuid = " .. sql_literal(selected_room_id) .. " " ..
          "AND lower(trim(e.dir)) IN ('n','north','e','east','s','south','w','west','u','up','d','down') " ..
          "UNION " ..
          "SELECT DISTINCT neighbour.area AS area FROM exits e " ..
          "JOIN rooms neighbour ON neighbour.uid = e.fromuid " ..
          "WHERE e.touid = " .. sql_literal(selected_room_id) .. " " ..
          "AND lower(trim(e.dir)) IN ('n','north','e','east','s','south','w','west','u','up','d','down')"
        local neighbour_rows, neighbour_err = sqlite_query(conn, neighbour_sql)
        if not neighbour_rows then error(neighbour_err) end
        local candidates = {}
        for _, row in ipairs(neighbour_rows) do
          candidates[tostring(row.area or "")] = { value = row.area }
        end
        local candidate_count = 0
        for _, candidate in pairs(candidates) do
          selected_area = candidate.value
          candidate_count = candidate_count + 1
        end
        if candidate_count == 0 then
          error("room not found in rooms and has no cardinal connection to a known area: " .. tostring(opts.room_id))
        elseif candidate_count > 1 then
          error("room is missing from rooms and its cardinal neighbours span multiple areas: " .. tostring(opts.room_id))
        end
      else
        error("room not found in mapper database: " .. tostring(opts.room_id))
      end
      selected_area_known = true
    end

    local optional = {}
    if has_col(inspect.room_columns, "norecall") then table.insert(optional, "norecall") end
    if has_col(inspect.room_columns, "noportal") then table.insert(optional, "noportal") end
    if has_col(inspect.room_columns, "terrain") then table.insert(optional, "terrain") end

    local select_cols = "uid, name, area"
    if #optional > 0 then select_cols = select_cols .. ", " .. table.concat(optional, ", ") end
    local room_sql = "SELECT " .. select_cols .. " FROM rooms"
    if selected_area_known then
      room_sql = room_sql .. " WHERE " .. area_condition("area", selected_area)
    end
    local room_rows, room_err = sqlite_query(conn, room_sql)
    if not room_rows then error(room_err) end

    local graph = {
      source = inspect.path,
      rooms = {},
      areas = {},
      area_list = {},
      adjacency = {},
      adjacency_seen = {},
      actual_exits = {},
      room_order = {},
      source_room_count = inspect.room_count,
      source_exit_count = inspect.exit_count,
      skipped_virtual_rooms = 0,
      skipped_custom_exits = 0,
      skipped_invalid_exits = 0,
      skipped_missing_destinations = 0,
      inferred_rooms = 0,
      ambiguous_inferred_rooms = 0,
      selected_area = selected_area,
    }

    local function ensure_area(key)
      key = tostring(key or "")
      local area = graph.areas[key]
      if not area then
        area = {
          key = key,
          rooms = {},
          actual_exits = 0,
          layout_exits = {},
          custom_exits = 0,
          outside_exits = 0,
          missing_exits = 0,
          inferred_rooms = 0,
        }
        graph.areas[key] = area
        table.insert(graph.area_list, area)
      end
      return area
    end

    for _, row in ipairs(room_rows) do
      local room_id = tonumber(row.uid)
      if room_id and room_id > 0 then
        local key = tostring(row.area or "")
        local room = {
          uid = room_id,
          name = tostring(row.name or ""),
          area = key,
          terrain = row.terrain,
          norecall = tonumber(row.norecall) or 0,
          noportal = tonumber(row.noportal) or 0,
        }
        graph.rooms[room_id] = room
        table.insert(ensure_area(key).rooms, room_id)
      else
        graph.skipped_virtual_rooms = graph.skipped_virtual_rooms + 1
      end
    end

    local exit_sql = "SELECT e.fromuid, e.touid, e.dir, source_record.uid AS source_exists, destination.uid AS target_exists " ..
      "FROM exits e " ..
      "LEFT JOIN rooms source_record ON source_record.uid = e.fromuid " ..
      "LEFT JOIN rooms destination ON destination.uid = e.touid " ..
      "WHERE e.fromuid NOT IN ('*','**')"
    if selected_area_known then
      local selected_condition = area_condition("area", selected_area)
      exit_sql = exit_sql .. " AND (" ..
        "e.fromuid IN (SELECT uid FROM rooms WHERE " .. selected_condition .. ") OR " ..
        "e.touid IN (SELECT uid FROM rooms WHERE " .. selected_condition .. ") OR " ..
        "e.fromuid IN (SELECT area_edge.touid FROM exits area_edge JOIN rooms area_source ON area_source.uid = area_edge.fromuid " ..
          "WHERE " .. area_condition("area_source.area", selected_area) .. " " ..
          "AND lower(trim(area_edge.dir)) IN ('n','north','e','east','s','south','w','west','u','up','d','down'))" ..
        ")"
    end
    local exit_rows, exit_err = sqlite_query(conn, exit_sql)
    if not exit_rows then error(exit_err) end

    local raw_cardinal_exits = {}
    local orphan_sources = {}
    for _, row in ipairs(exit_rows) do
      local from_id, to_id = tonumber(row.fromuid), tonumber(row.touid)
      local dir = normalize_cardinal(row.dir)
      local source_room = from_id and graph.rooms[from_id] or nil
      local source_area = source_room and graph.areas[source_room.area] or nil

      if not dir then
        if not selected_area_known or source_room then
          graph.skipped_custom_exits = graph.skipped_custom_exits + 1
          if source_area then source_area.custom_exits = source_area.custom_exits + 1 end
        end
      elseif not from_id or from_id <= 0 or not to_id or to_id <= 0 then
        graph.skipped_invalid_exits = graph.skipped_invalid_exits + 1
      else
        local raw = {
          from = from_id,
          to = to_id,
          dir = dir,
          source_exists = row.source_exists ~= nil,
          target_exists = row.target_exists ~= nil,
        }
        table.insert(raw_cardinal_exits, raw)
        if not raw.source_exists then orphan_sources[from_id] = true end
      end
    end

    -- Some mapper databases contain fully usable numeric rooms in exits.fromuid
    -- before a metadata row exists in rooms.  Infer only those source-room IDs;
    -- destination-only frontier IDs remain reported as missing.  Area inference
    -- must be unambiguous and never writes back to the SQLite database.
    local orphan_parent = {}
    for room_id in pairs(orphan_sources) do orphan_parent[room_id] = room_id end
    local function find_orphan(room_id)
      local p = orphan_parent[room_id]
      if p and p ~= room_id then
        orphan_parent[room_id] = find_orphan(p)
      end
      return orphan_parent[room_id]
    end
    local function join_orphans(a, b)
      local ar, br = find_orphan(a), find_orphan(b)
      if ar and br and ar ~= br then
        if ar < br then orphan_parent[br] = ar else orphan_parent[ar] = br end
      end
    end
    for _, raw in ipairs(raw_cardinal_exits) do
      if orphan_sources[raw.from] and orphan_sources[raw.to] then
        join_orphans(raw.from, raw.to)
      end
    end

    local component_areas = {}
    for _, raw in ipairs(raw_cardinal_exits) do
      local source_room = graph.rooms[raw.from]
      local target_room = graph.rooms[raw.to]
      if orphan_sources[raw.from] and target_room then
        local root = find_orphan(raw.from)
        component_areas[root] = component_areas[root] or {}
        component_areas[root][target_room.area] = true
      end
      if orphan_sources[raw.to] and source_room then
        local root = find_orphan(raw.to)
        component_areas[root] = component_areas[root] or {}
        component_areas[root][source_room.area] = true
      end
    end

    for room_id in pairs(orphan_sources) do
      local area_candidates = component_areas[find_orphan(room_id)] or {}
      local only_area, count = nil, 0
      for key in pairs(area_candidates) do only_area, count = key, count + 1 end
      if count == 1 then
        graph.rooms[room_id] = {
          uid = room_id,
          name = "Room " .. tostring(room_id),
          area = only_area,
          terrain = nil,
          norecall = 0,
          noportal = 0,
          inferred = true,
        }
        local inferred_area = ensure_area(only_area)
        table.insert(inferred_area.rooms, room_id)
        inferred_area.inferred_rooms = inferred_area.inferred_rooms + 1
        graph.inferred_rooms = graph.inferred_rooms + 1
      else
        graph.ambiguous_inferred_rooms = graph.ambiguous_inferred_rooms + 1
      end
    end

    table.sort(graph.area_list, function(a, b)
      local al, bl = area_label(a):lower(), area_label(b):lower()
      if al == bl then return area_label(a) < area_label(b) end
      return al < bl
    end)
    for _, area in ipairs(graph.area_list) do
      table.sort(area.rooms)
      for _, room_id in ipairs(area.rooms) do table.insert(graph.room_order, room_id) end
    end

    for _, raw in ipairs(raw_cardinal_exits) do
      local from_id, to_id, dir = raw.from, raw.to, raw.dir
      local source_room = graph.rooms[from_id]
      local source_area = source_room and graph.areas[source_room.area] or nil
      if not source_room then
        graph.skipped_invalid_exits = graph.skipped_invalid_exits + 1
      else
        local target_room = graph.rooms[to_id]
        source_area.actual_exits = source_area.actual_exits + 1
        if target_room then
          local exit_def = cardinal[dir]
          table.insert(graph.actual_exits, {
            from = from_id,
            to = to_id,
            dir = dir,
            mudlet_dir = exit_def.name,
            area = source_room.area,
          })
          if source_room.area == target_room.area then
            table.insert(source_area.layout_exits, { from = from_id, to = to_id, dir = dir })
            add_layout_edge(graph, from_id, to_id, dir)
            -- Reverse traversal is a layout constraint only.  It does not add a
            -- reverse Mudlet exit that is absent from the source database.
            add_layout_edge(graph, to_id, from_id, exit_def.inverse)
          else
            source_area.outside_exits = source_area.outside_exits + 1
          end
        elseif selected_area_known and raw.target_exists then
          -- An area-scoped load intentionally does not load destination rooms
          -- in other areas.
          source_area.outside_exits = source_area.outside_exits + 1
        else
          graph.skipped_missing_destinations = graph.skipped_missing_destinations + 1
          source_area.missing_exits = source_area.missing_exits + 1
        end
      end
    end

    table.sort(graph.actual_exits, function(a, b)
      if a.from ~= b.from then return a.from < b.from end
      local ao, bo = cardinal[a.dir].order, cardinal[b.dir].order
      if ao ~= bo then return ao < bo end
      return a.to < b.to
    end)
    for _, edges in pairs(graph.adjacency) do
      table.sort(edges, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.to < b.to
      end)
    end
    for _, area in ipairs(graph.area_list) do
      table.sort(area.layout_exits, function(a, b)
        if a.from ~= b.from then return a.from < b.from end
        local ao, bo = cardinal[a.dir].order, cardinal[b.dir].order
        if ao ~= bo then return ao < bo end
        return a.to < b.to
      end)
    end

    return graph
  end)

  conn:close()
  env:close()
  if not ok then return nil, tostring(graph_or_err) end
  return graph_or_err
end

local function calculate_area_layout(graph, area)
  local diagnostic_limit = 25
  local collision_details = {}
  local conflict_details = {}
  local rejected_constraint_details = {}
  local collision_events = 0

  local function keep_detail(list, detail)
    if #list < diagnostic_limit then table.insert(list, detail) end
  end

  -- Solve the Z axis separately from X/Y placement.  Up/down relations are
  -- hard constraints and are accepted before horizontal same-layer
  -- constraints.  This prevents a room reached horizontally first from
  -- incorrectly keeping an upstairs/downstairs destination on the same layer.
  local parent, weight = {}, {}
  for _, room_id in ipairs(area.rooms) do
    parent[room_id] = room_id
    weight[room_id] = 0 -- z[room] - z[parent[room]]
  end

  local function find_root(room_id)
    local direct_parent = parent[room_id]
    if direct_parent ~= room_id then
      local root, parent_weight = find_root(direct_parent)
      weight[room_id] = weight[room_id] + parent_weight
      parent[room_id] = root
    end
    return parent[room_id], weight[room_id]
  end

  local function constrain_z(from_id, to_id, delta)
    local from_root, from_weight = find_root(from_id)
    local to_root, to_weight = find_root(to_id)
    if from_root == to_root then
      local existing_delta = to_weight - from_weight
      return existing_delta == delta, existing_delta
    end
    parent[to_root] = from_root
    weight[to_root] = delta + from_weight - to_weight
    return true, delta
  end

  local rejected_vertical_constraints = 0
  local rejected_horizontal_constraints = 0
  for pass = 1, 2 do
    for _, edge in ipairs(area.layout_exits) do
      local is_vertical = edge.dir == "u" or edge.dir == "d"
      if (pass == 1 and is_vertical) or (pass == 2 and not is_vertical) then
        local required_delta = cardinal[edge.dir].dz
        local accepted, existing_delta = constrain_z(edge.from, edge.to, required_delta)
        if not accepted then
          if is_vertical then
            rejected_vertical_constraints = rejected_vertical_constraints + 1
          else
            rejected_horizontal_constraints = rejected_horizontal_constraints + 1
          end
          keep_detail(rejected_constraint_details, {
            from = edge.from,
            to = edge.to,
            dir = edge.dir,
            required_delta = required_delta,
            existing_delta = existing_delta,
            vertical = is_vertical,
          })
        end
      end
    end
  end

  local z_by_room = {}
  for _, room_id in ipairs(area.rooms) do
    local _, z = find_root(room_id)
    z_by_room[room_id] = z
  end

  -- X/Y belongs to a plane, not to the route used to reach that plane.  Up and
  -- down only constrain the cumulative Z index; they must never make east/west
  -- or north/south movement on different planes cancel each other.  Build each
  -- same-plane horizontal section locally, then pack sections independently on
  -- their already-solved Z plane.
  local coords = {}
  local components, collisions = 0, 0
  local next_component_x_by_z = {}

  for _, root in ipairs(area.rooms) do
    if not coords[root] then
      components = components + 1
      local root_z = z_by_room[root] or 0
      local local_coords = { [root] = { x = 0, y = 0, z = root_z } }
      local local_occupied = { [coord_key(0, 0, root_z)] = root }
      local local_collision_details = {}
      local min_x, max_x, min_y = 0, 0, 0

      local queue, head = { root }, 1
      while head <= #queue do
        local room_id = queue[head]
        head = head + 1
        local base = local_coords[room_id]
        for _, edge in ipairs(graph.adjacency[room_id] or {}) do
          local target_z = z_by_room[edge.to]
          local is_horizontal = edge.dz == 0
          local stays_on_plane = target_z == base.z
          if is_horizontal and stays_on_plane and
             not coords[edge.to] and not local_coords[edge.to] then
            local step = 1
            local x = base.x + edge.dx
            local y = base.y + edge.dy
            local z = target_z
            local wanted_x, wanted_y, wanted_z = x, y, z
            local first_occupant = nil
            local blocked_positions = 0
            while local_occupied[coord_key(x, y, z)] and
                  local_occupied[coord_key(x, y, z)] ~= edge.to do
              collisions = collisions + 1
              blocked_positions = blocked_positions + 1
              first_occupant = first_occupant or local_occupied[coord_key(x, y, z)]
              step = step + 1
              x = base.x + edge.dx * step
              y = base.y + edge.dy * step
            end
            if blocked_positions > 0 then
              collision_events = collision_events + 1
              if #local_collision_details < diagnostic_limit then
                table.insert(local_collision_details, {
                  from = room_id,
                  to = edge.to,
                  dir = edge.dir,
                  wanted = { x = wanted_x, y = wanted_y, z = wanted_z },
                  occupant = first_occupant,
                  blocked_positions = blocked_positions,
                  placed = { x = x, y = y, z = z },
                })
              end
            end
            local_coords[edge.to] = { x = x, y = y, z = z }
            local_occupied[coord_key(x, y, z)] = edge.to
            min_x, max_x = math.min(min_x, x), math.max(max_x, x)
            min_y = math.min(min_y, y)
            table.insert(queue, edge.to)
          end
        end
      end

      local packed_min_x = next_component_x_by_z[root_z] or 0
      local offset_x = packed_min_x - min_x
      local offset_y = -min_y
      for room_id, coord in pairs(local_coords) do
        coords[room_id] = {
          x = coord.x + offset_x,
          y = coord.y + offset_y,
          z = coord.z,
        }
      end
      next_component_x_by_z[root_z] = max_x + offset_x + 4

      for _, detail in ipairs(local_collision_details) do
        detail.wanted.x = detail.wanted.x + offset_x
        detail.wanted.y = detail.wanted.y + offset_y
        detail.placed.x = detail.placed.x + offset_x
        detail.placed.y = detail.placed.y + offset_y
        keep_detail(collision_details, detail)
      end
    end
  end

  local conflicts = 0
  local vertical_layer_conflicts = 0
  for _, edge in ipairs(area.layout_exits) do
    local from_coord, to_coord = coords[edge.from], coords[edge.to]
    local def = cardinal[edge.dir]
    local is_vertical = edge.dir == "u" or edge.dir == "d"
    local is_conflict = false
    if from_coord and to_coord then
      if is_vertical then
        -- A vertical exit changes only the plane index.  X/Y positions on the
        -- two planes are intentionally independent.
        is_conflict = to_coord.z ~= from_coord.z + def.dz
      else
        is_conflict = to_coord.x ~= from_coord.x + def.dx or
          to_coord.y ~= from_coord.y + def.dy or
          to_coord.z ~= from_coord.z
      end
    end
    if from_coord and to_coord and is_conflict then
      conflicts = conflicts + 1
      local is_layer_conflict = is_vertical and to_coord.z ~= from_coord.z + def.dz
      if is_layer_conflict then
        vertical_layer_conflicts = vertical_layer_conflicts + 1
      end
      keep_detail(conflict_details, {
        from = edge.from,
        to = edge.to,
        dir = edge.dir,
        expected = is_vertical and {
          x = to_coord.x,
          y = to_coord.y,
          z = from_coord.z + def.dz,
        } or {
          x = from_coord.x + def.dx,
          y = from_coord.y + def.dy,
          z = from_coord.z,
        },
        actual = { x = to_coord.x, y = to_coord.y, z = to_coord.z },
        layer = is_layer_conflict,
      })
    end
  end

  return coords, {
    rooms = #area.rooms,
    components = components,
    collisions = collisions,
    conflicts = conflicts,
    vertical_layer_conflicts = vertical_layer_conflicts,
    rejected_vertical_constraints = rejected_vertical_constraints,
    rejected_horizontal_constraints = rejected_horizontal_constraints,
    collision_events = collision_events,
    collision_details = collision_details,
    conflict_details = conflict_details,
    rejected_constraint_details = rejected_constraint_details,
    diagnostic_limit = diagnostic_limit,
    exits = area.actual_exits,
    custom_exits = area.custom_exits,
    outside_exits = area.outside_exits,
    missing_exits = area.missing_exits,
    inferred_rooms = area.inferred_rooms,
  }
end

local function apply_area_layout(graph, area)
  local coords, stats = calculate_area_layout(graph, area)
  stats.applied, stats.failed = 0, 0
  stats.failed_ids = {}
  stats.failure_details = {}
  for _, room_id in ipairs(area.rooms) do
    local coord = coords[room_id]
    local ok, result = pcall(setRoomCoordinates, room_id, coord.x, coord.y, coord.z)
    if ok and result ~= false then
      stats.applied = stats.applied + 1
    else
      stats.failed = stats.failed + 1
      if #stats.failed_ids < 10 then table.insert(stats.failed_ids, room_id) end
      if #stats.failure_details < stats.diagnostic_limit then
        table.insert(stats.failure_details, {
          operation = "setRoomCoordinates",
          room = room_id,
          coord = { x = coord.x, y = coord.y, z = coord.z },
          reason = ok and "returned false" or tostring(result),
        })
      end
    end
  end
  return stats
end

local function prepare_area_for_layout(graph, area)
  local limit = 25
  local stats = {
    created_rooms = 0,
    exits_refreshed = 0,
    failed = 0,
    failure_details = {},
    inferred_details = {},
  }

  local function record_failure(operation, detail, reason)
    stats.failed = stats.failed + 1
    if #stats.failure_details < limit then
      table.insert(stats.failure_details, {
        operation = operation,
        detail = detail,
        reason = reason,
      })
    end
  end

  local native_rooms = {}
  local rooms_ok, rooms_result = pcall(getRooms)
  if not rooms_ok or type(rooms_result) ~= "table" then
    record_failure("getRooms", area_label(area), rooms_ok and "did not return a table" or tostring(rooms_result))
    return stats
  end
  for room_id in pairs(rooms_result) do
    room_id = tonumber(room_id)
    if room_id then native_rooms[room_id] = true end
  end

  local area_id = nil
  if area.key == "" then
    area_id = -1
  else
    local areas_ok, areas_result = pcall(getAreaTable)
    if areas_ok and type(areas_result) == "table" then
      area_id = tonumber(areas_result[area.key])
    end
    if not area_id and type(getRoomArea) == "function" then
      for _, room_id in ipairs(area.rooms) do
        if native_rooms[room_id] then
          local room_area_ok, room_area = pcall(getRoomArea, room_id)
          room_area = room_area_ok and tonumber(room_area) or nil
          if room_area and room_area ~= -1 then
            area_id = room_area
            break
          end
        end
      end
    end
    if not area_id then
      local area_ok, area_result = pcall(addAreaName, area.key)
      if area_ok and area_result ~= false and area_result ~= nil then
        area_id = tonumber(area_result)
      else
        record_failure("addAreaName", area.key, area_ok and "returned false" or tostring(area_result))
      end
    end
  end

  for _, room_id in ipairs(area.rooms) do
    local room = graph.rooms[room_id]
    local was_created = false
    if not native_rooms[room_id] then
      local add_ok, add_result = pcall(addRoom, room_id)
      if add_ok and add_result ~= false then
        native_rooms[room_id] = true
        was_created = true
        stats.created_rooms = stats.created_rooms + 1
      else
        record_failure("addRoom", room_id, add_ok and "returned false" or tostring(add_result))
      end
    end

    if room and room.inferred and #stats.inferred_details < limit then
      table.insert(stats.inferred_details, {
        room = room_id,
        status = was_created and "created" or (native_rooms[room_id] and "already present" or "creation failed"),
      })
    end

    if was_created and room then
      if room.name ~= "" then
        local name_ok, name_result = pcall(setRoomName, room_id, room.name)
        if not name_ok or name_result == false then
          record_failure("setRoomName", room_id, name_ok and "returned false" or tostring(name_result))
        end
      end
      if area_id then
        local room_area_ok, room_area_result = pcall(setRoomArea, room_id, area_id)
        if not room_area_ok or room_area_result == false then
          record_failure("setRoomArea", room_id, room_area_ok and "returned false" or tostring(room_area_result))
        end
      end
    end
  end

  for _, exit in ipairs(graph.actual_exits) do
    local detail = tostring(exit.from) .. " --" .. tostring(exit.dir) .. "--> " .. tostring(exit.to)
    if native_rooms[exit.from] and native_rooms[exit.to] then
      local exit_ok, exit_result = pcall(setExit, exit.from, exit.to, exit.mudlet_dir)
      if exit_ok and exit_result ~= false then
        stats.exits_refreshed = stats.exits_refreshed + 1
      else
        record_failure("setExit", detail, exit_ok and "returned false" or tostring(exit_result))
      end
    else
      record_failure("setExit", detail, "source or destination is missing from the Mudlet map")
    end
  end

  return stats
end

local function coord_text(coord)
  return string.format("(%d,%d,%d)", coord.x, coord.y, coord.z)
end

local function emit_area_layout_diagnostics(area, stats, preparation)
  for _, detail in ipairs(preparation.inferred_details or {}) do
    mm.note(string.format(
      "[layout inferred] room %d was inferred from exits.fromuid in %s (%s)",
      detail.room, area_label(area), detail.status
    ))
  end

  for _, detail in ipairs(stats.collision_details or {}) do
    mm.warn(string.format(
      "[layout collision] %d --%s--> %d wanted %s, occupied by room %s; placed at %s after %d blocked position%s",
      detail.from, detail.dir, detail.to, coord_text(detail.wanted), tostring(detail.occupant),
      coord_text(detail.placed), detail.blocked_positions, detail.blocked_positions == 1 and "" or "s"
    ))
  end
  if (stats.collision_events or 0) > #(stats.collision_details or {}) then
    mm.warn(string.format(
      "[layout collision] %d additional collision events omitted",
      stats.collision_events - #stats.collision_details
    ))
  end

  for _, detail in ipairs(stats.rejected_constraint_details or {}) do
    mm.warn(string.format(
      "[layout DB constraint] %d --%s--> %d requires layer delta %+d, but an earlier accepted path requires %+d",
      detail.from, detail.dir, detail.to, detail.required_delta, detail.existing_delta
    ))
  end
  local rejected_total = (stats.rejected_vertical_constraints or 0) + (stats.rejected_horizontal_constraints or 0)
  if rejected_total > #(stats.rejected_constraint_details or {}) then
    mm.warn(string.format(
      "[layout DB constraint] %d additional contradictory constraints omitted",
      rejected_total - #stats.rejected_constraint_details
    ))
  end

  for _, detail in ipairs(stats.conflict_details or {}) do
    if detail.layer then
      mm.warn(string.format(
        "[layout layer conflict] %d --%s--> %d expected plane %d, actual plane %d",
        detail.from, detail.dir, detail.to, detail.expected.z, detail.actual.z
      ))
    else
      mm.warn(string.format(
        "[layout conflict] %d --%s--> %d expected %s, actual %s; another accepted horizontal path or collision fixed the room elsewhere",
        detail.from, detail.dir, detail.to, coord_text(detail.expected), coord_text(detail.actual)
      ))
    end
  end
  if (stats.conflicts or 0) > #(stats.conflict_details or {}) then
    mm.warn(string.format(
      "[layout conflict] %d additional conflicts omitted",
      stats.conflicts - #stats.conflict_details
    ))
  end

  for _, detail in ipairs(preparation.failure_details or {}) do
    mm.warn(string.format(
      "[layout failure] %s %s: %s",
      tostring(detail.operation), tostring(detail.detail), tostring(detail.reason)
    ))
  end
  for _, detail in ipairs(stats.failure_details or {}) do
    mm.warn(string.format(
      "[layout failure] %s room %d at %s: %s",
      detail.operation, detail.room, coord_text(detail.coord), tostring(detail.reason)
    ))
  end
  local shown_failures = #(preparation.failure_details or {}) + #(stats.failure_details or {})
  local total_failures = (preparation.failed or 0) + (stats.failed or 0)
  if total_failures > shown_failures then
    mm.warn(string.format("[layout failure] %d additional failures omitted", total_failures - shown_failures))
  end
end

local function save_native_map(target_path)
  if type(saveMap) ~= "function" then return false, "Mudlet saveMap() API unavailable" end
  local ok, result
  if target_path and target_path ~= "" then
    ok, result = pcall(saveMap, target_path)
  else
    ok, result = pcall(saveMap)
  end
  if not ok then return false, tostring(result) end
  if result == false then return false, "saveMap returned false" end
  return true
end

local MAP_JOB_BATCH_SIZE = 500
local run_map_job_tick

local function record_job_failure(job, kind, detail)
  job.import_failures = job.import_failures + 1
  job.failure_counts[kind] = (job.failure_counts[kind] or 0) + 1
  if detail and #job.failure_samples < 10 then
    table.insert(job.failure_samples, tostring(kind) .. " " .. tostring(detail))
  end
end

local function finish_map_job(job)
  local save_ok, save_err = save_native_map(job.target_path)
  if not save_ok then error("map save failed: " .. tostring(save_err)) end

  if job.target_path then mm.note("Map saved to: " .. tostring(job.target_path)) end
  if type(updateMap) == "function" then pcall(updateMap) end
  if job.player_room and type(setPlayerRoom) == "function" then pcall(setPlayerRoom, job.player_room) end
  if job.player_room and type(centerview) == "function" then pcall(centerview, job.player_room) end

  mm.import._active_map_job = nil
  mm.note(string.format(
    "%s complete: %d areas, %d rooms positioned, %d cardinal exits, %d collisions, %d constraint conflicts, %d failures. Skipped %d custom exits and %d invalid/missing exits.",
    job.mode == "rebuild" and "Map rebuild" or "Coordinate rebuild",
    #job.graph.area_list,
    job.totals.applied,
    #job.graph.actual_exits,
    job.totals.collisions,
    job.totals.conflicts,
    job.totals.failed + job.import_failures,
    job.graph.skipped_custom_exits,
    job.graph.skipped_invalid_exits + job.graph.skipped_missing_destinations
  ))
  if job.totals.vertical_layer_conflicts > 0 then
    mm.warn(string.format(
      "Vertical layer constraints still unresolved: %d (including %d contradictory up/down constraints).",
      job.totals.vertical_layer_conflicts,
      job.totals.rejected_vertical_constraints
    ))
  end
  if job.import_failures > 0 then
    local categories = {}
    for kind, count in pairs(job.failure_counts) do
      table.insert(categories, tostring(kind) .. "=" .. tostring(count))
    end
    table.sort(categories)
    mm.warn("Mudlet API failure categories: " .. table.concat(categories, ", "))
    if #job.failure_samples > 0 then
      mm.warn("First failures: " .. table.concat(job.failure_samples, "; "))
    end
  end
end

local function schedule_map_job(job)
  if type(tempTimer) == "function" then
    tempTimer(0, function()
      if mm.import._active_map_job == job then run_map_job_tick(job, false) end
    end)
  else
    while mm.import._active_map_job == job do run_map_job_tick(job, true) end
  end
end

local function process_batch(job, list, callback)
  local last = math.min(#list, job.index + MAP_JOB_BATCH_SIZE - 1)
  for i = job.index, last do callback(list[i]) end
  job.index = last + 1
  return job.index > #list
end

local function create_import_room(job, room_id)
  local room = job.graph.rooms[room_id]
  local ok, added = pcall(addRoom, room_id)
  if not ok or added == false then
    record_job_failure(job, "room-create", room_id)
    return
  end
  if room.name ~= "" then
    local name_ok, name_result = pcall(setRoomName, room_id, room.name)
    if not name_ok or name_result == false then record_job_failure(job, "room-name", room_id) end
  end
  local area_id = job.area_ids[room.area]
  if area_id then
    local area_ok, area_result = pcall(setRoomArea, room_id, area_id)
    if not area_ok or area_result == false then record_job_failure(job, "room-area", room_id) end
  end
  if room.noportal == 1 then
    pcall(setRoomChar, room_id, "P")
  elseif room.norecall == 1 then
    pcall(setRoomChar, room_id, "R")
  end
  if room.terrain and room.terrain ~= "" then
    if type(setRoomUserData) == "function" then pcall(setRoomUserData, room_id, "terrain", tostring(room.terrain)) end
    if mm.apply_room_terrain then pcall(mm.apply_room_terrain, room_id, tostring(room.terrain)) end
  end
end

local function process_map_job_phase(job)
  if job.phase == "delete_rooms" then
    if process_batch(job, job.delete_rooms, function(room_id)
      local ok, result = pcall(deleteRoom, room_id)
      if not ok or result == false then record_job_failure(job, "room-delete", room_id) end
    end) then
      job.phase, job.index = "delete_areas", 1
      mm.note("Existing Mudlet rooms cleared; removing old areas...")
    end
  elseif job.phase == "delete_areas" then
    if process_batch(job, job.delete_areas, function(area_id)
      if area_id ~= -1 then
        local ok, result = pcall(deleteArea, area_id)
        if not ok or result == false then record_job_failure(job, "area-delete", area_id) end
      end
    end) then
      job.phase, job.index = "create_areas", 1
    end
  elseif job.phase == "create_areas" then
    if process_batch(job, job.graph.area_list, function(area)
      if area.key == "" then
        job.area_ids[area.key] = -1
      else
        local ok, area_id = pcall(addAreaName, area.key)
        if ok and area_id then
          job.area_ids[area.key] = area_id
        else
          record_job_failure(job, "area-create", area.key)
        end
      end
    end) then
      job.phase, job.index = "create_rooms", 1
      mm.note("Areas created; importing rooms in batches...")
    end
  elseif job.phase == "create_rooms" then
    if process_batch(job, job.graph.room_order, function(room_id) create_import_room(job, room_id) end) then
      job.phase, job.index = "create_exits", 1
      mm.note("Rooms imported; importing direct cardinal exits in batches...")
    end
  elseif job.phase == "create_exits" then
    if process_batch(job, job.graph.actual_exits, function(exit)
      local ok, result = pcall(setExit, exit.from, exit.to, exit.mudlet_dir)
      if not ok or result == false then
        record_job_failure(job, "exit-create", tostring(exit.from) .. "-" .. exit.dir .. "->" .. tostring(exit.to))
      end
    end) then
      job.phase, job.index = "layout", 1
      mm.note("Direct exits imported; rebuilding area layouts...")
    end
  elseif job.phase == "layout" then
    local area = job.graph.area_list[job.index]
    if not area then
      finish_map_job(job)
      return
    end
    local stats = apply_area_layout(job.graph, area)
    job.totals.applied = job.totals.applied + stats.applied
    job.totals.failed = job.totals.failed + stats.failed
    job.totals.collisions = job.totals.collisions + stats.collisions
    job.totals.conflicts = job.totals.conflicts + stats.conflicts
    job.totals.vertical_layer_conflicts = job.totals.vertical_layer_conflicts + stats.vertical_layer_conflicts
    job.totals.rejected_vertical_constraints = job.totals.rejected_vertical_constraints + stats.rejected_vertical_constraints
    job.totals.rejected_horizontal_constraints = job.totals.rejected_horizontal_constraints + stats.rejected_horizontal_constraints
    mm.note(string.format(
      "[%d/%d] %s: %d rooms, %d cardinal exits, %d placed, %d inferred, %d horizontal sections, %d collisions, %d conflicts, %d layer conflicts, %d missing targets, %d failures",
      job.index, #job.graph.area_list, area_label(area), stats.rooms, stats.exits,
      stats.applied, stats.inferred_rooms, stats.components, stats.collisions, stats.conflicts,
      stats.vertical_layer_conflicts, stats.missing_exits, stats.failed
    ))
    if #stats.failed_ids > 0 then
      mm.warn(area_label(area) .. " coordinate failures (first): " .. table.concat(stats.failed_ids, ", "))
    end
    job.index = job.index + 1
  end
end

run_map_job_tick = function(job, synchronous_loop)
  local ok, err = pcall(process_map_job_phase, job)
  if not ok then
    mm.import._active_map_job = nil
    mm.warn((job.mode == "rebuild" and "Map rebuild" or "Coordinate rebuild") .. " failed: " .. tostring(err))
    return
  end
  if mm.import._active_map_job == job and not synchronous_loop then schedule_map_job(job) end
end

local function start_all_area_job(mode, source_path, target_path)
  if mm.import._active_map_job then return false, "another map rebuild operation is already running" end
  if type(setRoomCoordinates) ~= "function" then return false, "Mudlet room coordinate APIs unavailable" end
  if mode == "rebuild" then
    for _, api in ipairs({ "getRooms", "deleteRoom", "getAreaTable", "deleteArea", "addAreaName", "addRoom", "setRoomArea", "setRoomName", "setExit" }) do
      if type(_G[api]) ~= "function" then return false, "Mudlet map API unavailable: " .. api .. "()" end
    end
  end
  local graph, graph_err = load_layout_graph(source_path)
  if not graph then return false, graph_err end
  if #graph.room_order == 0 then return false, "mapper database contains no numeric rooms to rebuild" end

  local info = mm.get_room_info and mm.get_room_info() or nil
  local job = {
    mode = mode,
    graph = graph,
    phase = mode == "rebuild" and "delete_rooms" or "layout",
    index = 1,
    area_ids = {},
    import_failures = 0,
    failure_counts = {},
    failure_samples = {},
    totals = {
      applied = 0,
      failed = 0,
      collisions = 0,
      conflicts = 0,
      vertical_layer_conflicts = 0,
      rejected_vertical_constraints = 0,
      rejected_horizontal_constraints = 0,
    },
    target_path = target_path,
    player_room = info and tonumber(info.num) or nil,
    delete_rooms = {},
    delete_areas = {},
  }

  if mode == "rebuild" then
    for room_id in pairs(getRooms() or {}) do
      room_id = tonumber(room_id)
      if room_id then table.insert(job.delete_rooms, room_id) end
    end
    table.sort(job.delete_rooms)
    for _, area_id in pairs(getAreaTable() or {}) do
      area_id = tonumber(area_id)
      if area_id and area_id ~= -1 then table.insert(job.delete_areas, area_id) end
    end
    table.sort(job.delete_areas)
  end

  mm.import._active_map_job = job
  mm.note(string.format(
    "%s started from %s: %d rooms in %d sorted areas (%d inferred from exits.fromuid); %d direct cardinal exits; %d custom exits will be ignored; %d orphan source rooms were ambiguous.",
    mode == "rebuild" and "Map rebuild" or "Coordinate rebuild",
    tostring(graph.source), #graph.room_order, #graph.area_list,
    graph.inferred_rooms, #graph.actual_exits, graph.skipped_custom_exits,
    graph.ambiguous_inferred_rooms
  ))
  schedule_map_job(job)
  return true, { started = true, areas = #graph.area_list, rooms = #graph.room_order }
end

function mm.import.convert_sqlite_to_mudlet(source_path, target_path)
  if not source_path or source_path == "" then return false, "missing source sqlite path" end
  local final_target
  if target_path and target_path ~= "" then
    final_target = mm.resolve_native_mapper_db(target_path)
    mm.state.native_mapper_db = target_path
  else
    final_target = getMudletHomeDir() .. "/mmapper_converted_map.dat"
    mm.state.native_mapper_db = "mmapper_converted_map.dat"
  end
  return start_all_area_job("rebuild", source_path, final_target)
end

function mm.import.recalculate_all_layouts(source_path)
  return start_all_area_job("layout", source_path or mm.state.map_db, nil)
end

function mm.import.update_room_colors_from_sqlite(source_path)
  local source = mm.resolve_native_mapper_db(source_path or mm.state.map_db)
  if not source or not mm.path_exists(source) then
    return false, "source DB not found: " .. tostring(source)
  end

  local env, conn, openErr = open_sqlite(source)
  if not conn then
    return false, openErr
  end

  local ok, result_or_err = pcall(function()
    local envRows, envErr = sqlite_query(conn, "SELECT uid, name, color FROM environments")
    if not envRows then error("failed loading environments: " .. tostring(envErr)) end
    if #envRows == 0 then error("no environments found in sqlite DB") end

    local ansiToRgb = {
      [1]  = {128, 0, 0}, [2]  = {0, 128, 0}, [3]  = {128, 128, 0}, [4]  = {0, 0, 128},
      [5]  = {128, 0, 128}, [6]  = {0, 128, 128}, [7]  = {192, 192, 192}, [8]  = {128, 128, 128},
      [9]  = {255, 0, 0}, [10] = {0, 255, 0}, [11] = {255, 255, 0}, [12] = {0, 0, 255},
      [13] = {255, 0, 255}, [14] = {0, 255, 255}, [15] = {255, 255, 255},
    }

    -- Match legacy aardwolf.xml behavior: Mudlet env ids are sqlite uid + 16.
    local envOffset = 16
    local terrainToEnv = {}
    local envColorCode = {}
    for _, row in ipairs(envRows) do
      local uid = tonumber(row.uid)
      local name = row.name and tostring(row.name):lower() or nil
      local color = tonumber(row.color)
      if uid and name and name ~= "" then
        local mudletEnv = uid + envOffset
        terrainToEnv[name] = mudletEnv
        if color then envColorCode[mudletEnv] = color end
      end
    end

    local colorsApplied = 0
    if type(setCustomEnvColor) == "function" then
      for envId, colorCode in pairs(envColorCode) do
        local rgb = ansiToRgb[colorCode] or {192, 192, 192}
        local okColor = pcall(setCustomEnvColor, envId, rgb[1], rgb[2], rgb[3], 255)
        if okColor then colorsApplied = colorsApplied + 1 end
      end
    end

    local roomRows, roomErr = sqlite_query(conn, "SELECT uid, terrain FROM rooms WHERE terrain IS NOT NULL AND terrain != ''")
    if not roomRows then error("failed loading rooms.terrain: " .. tostring(roomErr)) end

    local updated, skipped = 0, 0
    for _, row in ipairs(roomRows) do
      local roomId = tonumber(row.uid)
      local terrain = row.terrain and tostring(row.terrain):lower() or nil
      local envId = terrain and terrainToEnv[terrain] or nil
      if roomId and envId and type(setRoomEnv) == "function" then
        local okRoom = pcall(setRoomEnv, roomId, envId)
        if okRoom then
          updated = updated + 1
        else
          skipped = skipped + 1
        end
      else
        skipped = skipped + 1
      end
    end

    if type(saveMap) == "function" then
      pcall(saveMap)
    end

    return {
      source = source,
      env_rows = #envRows,
      colors_applied = colorsApplied,
      rooms_updated = updated,
      rooms_skipped = skipped,
    }
  end)

  conn:close()
  env:close()

  if not ok then
    return false, tostring(result_or_err)
  end

  return true, result_or_err
end


function mm.import.rebuild_layout_from(start_room, opts)
  opts = opts or {}
  for _, api in ipairs({
    "setRoomCoordinates", "getRooms", "getAreaTable", "addAreaName",
    "addRoom", "setRoomArea", "setRoomName", "setExit",
  }) do
    if type(_G[api]) ~= "function" then
      return false, "Mudlet map API unavailable: " .. api .. "()"
    end
  end
  local start = tonumber(start_room)
  if not start then return false, "start room must be a number" end
  if mm.import._active_map_job then return false, "another map rebuild operation is already running" end

  -- The room id selects an area; placement within that area is always rooted
  -- deterministically by sorted UID so manual, automatic, and full rebuilds
  -- produce the same result.
  local graph, graph_err = load_layout_graph(opts.source_path or mm.state.map_db, { room_id = start })
  if not graph then return false, graph_err end
  local area = graph.area_list[1]
  if not area then return false, "no rooms found for room " .. tostring(start) end

  -- Area-only rebuilds also repair rooms inferred from exits.fromuid and refresh
  -- the direct cardinal exits before applying the shared layout.
  local preparation = prepare_area_for_layout(graph, area)
  local stats = apply_area_layout(graph, area)
  local save_ok, save_err = save_native_map()
  if not save_ok then
    if not opts.silent then emit_area_layout_diagnostics(area, stats, preparation) end
    return false, "layout rebuilt but map save failed: " .. tostring(save_err)
  end

  if type(setPlayerRoom) == "function" then
    pcall(setPlayerRoom, start)
  end
  if type(centerview) == "function" then
    pcall(centerview, start)
  end
  if type(updateMap) == "function" then
    pcall(updateMap)
  end

  if not opts.silent then
    emit_area_layout_diagnostics(area, stats, preparation)
    mm.note(string.format(
      "Rebuilt and saved area %s: %d rooms, %d cardinal exits, %d placed, %d inferred, %d created, %d exits refreshed, %d horizontal sections, %d collisions, %d conflicts, %d layer conflicts, %d missing targets, %d failures.",
      area_label(area), stats.rooms, stats.exits, stats.applied, stats.inferred_rooms,
      preparation.created_rooms, preparation.exits_refreshed, stats.components,
      stats.collisions, stats.conflicts, stats.vertical_layer_conflicts,
      stats.missing_exits, stats.failed + preparation.failed
    ))
  end
  return true, {
    start = start,
    applied = stats.applied,
    failed = stats.failed + preparation.failed,
    area = area.key,
    area_rooms = stats.rooms,
    created_rooms = preparation.created_rooms,
    exits_refreshed = preparation.exits_refreshed,
    components = stats.components,
    collisions = stats.collisions,
    conflicts = stats.conflicts,
    vertical_layer_conflicts = stats.vertical_layer_conflicts,
    missing_exits = stats.missing_exits,
  }
end
