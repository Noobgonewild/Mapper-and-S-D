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

local function clear_mudlet_map()
  local existingRooms = getRooms() or {}
  for roomId, _ in pairs(existingRooms) do
    deleteRoom(roomId)
  end

  local existingAreas = getAreaTable() or {}
  for _, id in pairs(existingAreas) do
    if id ~= -1 then
      deleteArea(id)
    end
  end
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

    local required_rooms = { "uid", "name", "area", "x", "y", "z" }
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

local function import_rooms(conn, roomCols)
  local areaRows, areaErr = sqlite_query(conn, "SELECT DISTINCT area FROM rooms WHERE area IS NOT NULL AND area != ''")
  if not areaRows then return nil, areaErr end

  local areaMap = {}
  for _, row in ipairs(areaRows) do
    local areaName = row.area
    if areaName and areaName ~= "" then
      local areaId = addAreaName(areaName)
      if areaId then
        areaMap[areaName] = areaId
      end
    end
  end

  local optional = {}
  if has_col(roomCols, "norecall") then table.insert(optional, "norecall") end
  if has_col(roomCols, "noportal") then table.insert(optional, "noportal") end
  if has_col(roomCols, "terrain") then table.insert(optional, "terrain") end

  local select_cols = "uid, name, area, x, y, z"
  if #optional > 0 then
    select_cols = select_cols .. ", " .. table.concat(optional, ", ")
  end

  local roomRows, roomErr = sqlite_query(conn, "SELECT " .. select_cols .. " FROM rooms")
  if not roomRows then return nil, roomErr end

  local createdRooms = 0
  for _, room in ipairs(roomRows) do
    local roomId = tonumber(room.uid)
    if roomId and roomId > 0 and addRoom(roomId) then
      if room.name then setRoomName(roomId, room.name) end
      if room.area and areaMap[room.area] then setRoomArea(roomId, areaMap[room.area]) end
      setRoomCoordinates(roomId, tonumber(room.x) or 0, tonumber(room.y) or 0, tonumber(room.z) or 0)

      if tonumber(room.noportal) == 1 then
        setRoomChar(roomId, "P")
      elseif tonumber(room.norecall) == 1 then
        setRoomChar(roomId, "R")
      end

      if room.terrain and room.terrain ~= "" then
        if type(setRoomUserData) == "function" then
          pcall(setRoomUserData, roomId, "terrain", tostring(room.terrain))
        end
        if mm.apply_room_terrain then
          mm.apply_room_terrain(roomId, tostring(room.terrain))
        end
      end

      createdRooms = createdRooms + 1
    end
  end

  return { rooms = createdRooms, areas = #areaRows }
end

local function import_exits(conn)
  local dirMap = {
    n = "north", s = "south", e = "east", w = "west",
    u = "up", d = "down",
    ne = "northeast", nw = "northwest", se = "southeast", sw = "southwest",
    north = "north", south = "south", east = "east", west = "west",
    up = "up", down = "down", northeast = "northeast", northwest = "northwest",
    southeast = "southeast", southwest = "southwest",
  }

  local exitRows, exitErr = sqlite_query(conn, "SELECT fromuid, touid, dir FROM exits WHERE fromuid NOT IN ('*','**')")
  if not exitRows then return nil, exitErr end

  local created = 0
  for _, ex in ipairs(exitRows) do
    local fromId, toId = tonumber(ex.fromuid), tonumber(ex.touid)
    local dir = ex.dir and tostring(ex.dir)
    if fromId and toId and dir and dir ~= "" then
      local std = dirMap[dir:lower()]
      local ok = std and setExit(fromId, toId, std) or addSpecialExit(fromId, toId, dir)
      if ok then created = created + 1 end
    end
  end

  return { exits = created }
end

function mm.import.convert_sqlite_to_mudlet(source_path, target_path)
  if not source_path or source_path == "" then
    return false, "missing source sqlite path"
  end

  local okInspect, inspect = mm.import.inspect_sqlite(source_path)
  if not okInspect then
    return false, inspect
  end

  if not inspect.compatible then
    return false, "schema mismatch. missing columns: " .. table.concat(inspect.missing or {}, ", ")
  end

  local env, conn, openErr = open_sqlite(inspect.path)
  if not conn then
    return false, openErr
  end

  local ok, result_or_err = pcall(function()
    mm.note("Converting sqlite mapper DB -> Mudlet map: " .. inspect.path)
    mm.note(string.format("Source has %d rooms, %d exits.", inspect.room_count, inspect.exit_count))

    clear_mudlet_map()

    local roomStats, roomErr = import_rooms(conn, inspect.room_columns)
    if not roomStats then error("room import failed: " .. tostring(roomErr)) end

    local exitStats, exitErr = import_exits(conn)
    if not exitStats then error("exit import failed: " .. tostring(exitErr)) end

    local saved
    local final_target
    if target_path and target_path ~= "" then
      final_target = mm.resolve_native_mapper_db(target_path)
      mm.state.native_mapper_db = target_path
    else
      final_target = getMudletHomeDir() .. "/mmapper_converted_map.dat"
      mm.state.native_mapper_db = "mmapper_converted_map.dat"
    end

    saved = saveMap(final_target)
    mm.note("Map saved to: " .. tostring(final_target))

    if saved == false then
      error("saveMap returned false")
    end

    return {
      rooms = roomStats.rooms or 0,
      areas = roomStats.areas or 0,
      exits = exitStats.exits or 0,
    }
  end)

  conn:close()
  env:close()

  if not ok then
    return false, tostring(result_or_err)
  end

  local stats = result_or_err
  mm.note(string.format("Conversion complete: %d rooms, %d exits, %d areas.", stats.rooms, stats.exits, stats.areas))
  return true, stats
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


local dir_vectors = {
  north = {0, 1, 0}, south = {0, -1, 0}, east = {1, 0, 0}, west = {-1, 0, 0},
  northeast = {1, 1, 0}, northwest = {-1, 1, 0}, southeast = {1, -1, 0}, southwest = {-1, -1, 0},
  up = {0, 0, 1}, down = {0, 0, -1},
}

local dir_alias = {
  n = "north", s = "south", e = "east", w = "west",
  ne = "northeast", nw = "northwest", se = "southeast", sw = "southwest",
  u = "up", d = "down",
}

local function normalize_dir(dir)
  dir = tostring(dir or ""):lower():gsub("%s+", "")
  return dir_alias[dir] or dir
end

function mm.import.rebuild_layout_from(start_room, opts)
  opts = opts or {}
  if type(getRoomExits) ~= "function" or type(setRoomCoordinates) ~= "function" then
    return false, "Mudlet room coordinate APIs unavailable"
  end

  local rooms = getRooms() or {}
  local start = tonumber(start_room)
  if not start then
    return false, "start room must be a number"
  end
  if not rooms[start] and type(roomExists) == "function" then
    local ok, exists = pcall(roomExists, start)
    if not ok or not exists then
      return false, "start room not found in current map: " .. tostring(start)
    end
  end

  local queue = { start }
  local head = 1
  local coords = { [start] = { x = 0, y = 0, z = 0 } }
  local visited = { [start] = true }

  while head <= #queue do
    local rid = queue[head]
    head = head + 1

    local base = coords[rid]
    local ok_exits, exits = pcall(getRoomExits, rid)
    if ok_exits and type(exits) == "table" then
      for dir, toid in pairs(exits) do
        local nd = normalize_dir(dir)
        local vec = dir_vectors[nd]
        local target = tonumber(toid)
        if vec and target then
          if not coords[target] then
            coords[target] = { x = base.x + vec[1], y = base.y + vec[2], z = base.z + vec[3] }
          end
          if not visited[target] then
            visited[target] = true
            queue[#queue + 1] = target
          end
        end
      end
    end
  end

  local applied = 0
  for rid, c in pairs(coords) do
    local ok = pcall(setRoomCoordinates, rid, c.x, c.y, c.z)
    if ok then applied = applied + 1 end
  end

  if type(centerview) == "function" then
    pcall(centerview, start)
  end
  if type(setPlayerRoom) == "function" then
    pcall(setPlayerRoom, start)
  end

  if not opts.silent then
    mm.note(string.format("Rebuilt layout from room %d. Updated coordinates for %d rooms.", start, applied))
  end
  return true, { start = start, applied = applied }
end
