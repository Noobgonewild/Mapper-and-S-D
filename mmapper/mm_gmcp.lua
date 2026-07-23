mm = mm or {}

local function trim(s)
  if type(s) ~= "string" then return s end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function now_millis()
  if type(getEpoch) == "function" then
    local v = tonumber(getEpoch())
    if v then return v end
  end
  return math.floor((os.clock() or 0) * 1000)
end

function mm.get_room_packet()
  if gmcp and gmcp.room then
    return gmcp.room
  end
  if gmcp and gmcp.Room then
    return gmcp.Room
  end
  return nil
end

function mm.get_room_info()
  local packet = mm.get_room_packet()
  if packet and packet.info then
    return packet.info
  end

  -- Fallbacks for clients that flatten keys differently.
  if gmcp and gmcp.room and gmcp.room.info then
    return gmcp.room.info
  end
  if gmcp and gmcp.Room and gmcp.Room.Info then
    return gmcp.Room.Info
  end
  return nil
end

function mm.get_room_exits()
  local packet = mm.get_room_packet()
  if packet and type(packet.exits) == "table" then
    return packet.exits
  end

  if gmcp and gmcp.Room and type(gmcp.Room.Exits) == "table" then
    return gmcp.Room.Exits
  end

  local info = mm.get_room_info()
  if info and type(info.exits) == "table" then
    return info.exits
  end

  return nil
end

function mm.get_room_area_info()
  local packet = mm.get_room_packet()
  if packet and type(packet.area) == "table" then
    return packet.area
  end
  if gmcp and gmcp.room and type(gmcp.room.area) == "table" then
    return gmcp.room.area
  end
  if gmcp and gmcp.Room and type(gmcp.Room.Area) == "table" then
    return gmcp.Room.Area
  end
  return nil
end

function mm.get_area_display_name(info)
  info = type(info) == "table" and info or (mm.get_room_info() or {})
  local area_id = tostring(info.zone or info.area or "")
  local area_info = mm.get_room_area_info()

  if type(area_info) == "table" then
    local packet_id = tostring(area_info.id or area_info.uid or "")
    local packet_name = tostring(area_info.name or area_info.title or "")
    if packet_name ~= "" and
        (area_id == "" or packet_id == "" or packet_id == area_id) then
      return packet_name
    end
  end

  if mm.area_references and type(mm.area_references.get) == "function" then
    local reference = mm.area_references.get(area_id)
    if reference and tostring(reference.name or "") ~= "" then
      return tostring(reference.name)
    end
  end

  return area_id
end

function mm.get_room_sectors_packet()
  local packet = mm.get_room_packet()
  if packet and type(packet.sectors) == "table" then
    return packet.sectors
  end
  if gmcp and gmcp.room and type(gmcp.room.sectors) == "table" then
    return gmcp.room.sectors
  end
  if gmcp and gmcp.Room and type(gmcp.Room.Sectors) == "table" then
    return gmcp.Room.Sectors
  end
  return nil
end


local function style_triplet(seg)
  if type(seg) ~= "table" then return nil end

  if type(seg.textcolour) == "table" then
    return seg.textcolour[1], seg.textcolour[2], seg.textcolour[3]
  end
  if type(seg.textColor) == "table" then
    return seg.textColor[1], seg.textColor[2], seg.textColor[3]
  end
  if type(seg.fg_color) == "table" then
    return seg.fg_color[1], seg.fg_color[2], seg.fg_color[3]
  end

  local packed = seg.textcolour or seg.textColor or seg.fg_color
  if type(packed) == "number" then
    local r = math.floor(packed / 65536) % 256
    local g = math.floor(packed / 256) % 256
    local b = packed % 256
    return r, g, b
  end

  local r = seg.r or seg.red
  local g = seg.g or seg.green
  local b = seg.b or seg.blue
  if r and g and b then return r, g, b end

  return nil
end

local function styles_to_decho()
  if type(styles) ~= "table" then return nil end

  local parts = {}
  for _, seg in ipairs(styles) do
    local text = seg.text or seg[1] or ""
    text = tostring(text or "")
    if text ~= "" then
      local r, g, b = style_triplet(seg)
      if r and g and b then
        table.insert(parts, string.format("<%d,%d,%d>%s", tonumber(r) or 255, tonumber(g) or 255, tonumber(b) or 255, text))
      else
        table.insert(parts, text)
      end
    end
  end

  if #parts == 0 then return nil end
  return table.concat(parts, "")
end


function mm.refresh_terrain_ids()
  mm.terrain_ids = mm.terrain_ids or {}
  local packet = mm.get_room_sectors_packet()
  local sectors = packet and packet.sectors
  if type(sectors) ~= "table" then return false end

  local count = 0
  for _, v in pairs(sectors) do
    if type(v) == "table" and v.name and v.id ~= nil then
      mm.terrain_ids[tostring(v.name)] = tonumber(v.id) and (tonumber(v.id) + 16) or mm.terrain_ids[tostring(v.name)]
      count = count + 1
    end
  end
  if count > 0 then
    mm.debug("loaded terrain sector map entries: " .. tostring(count))
    return true
  end
  return false
end

local terrain_rgb = {
  city = {240,128,128}, inside = {211,211,211}, forest = {34,139,34}, hills = {0,250,154},
  mountain = {188,143,143}, desert = {245,222,179}, swamp = {107,142,35},
  waterswim = {100,149,237}, waternoswim = {123,104,238}, ocean = {30,144,255},
  ocean2 = {0,191,255}, ocean3 = {65,105,225}, ocean4 = {25,25,112}, underwater = {0,0,128},
  road = {184,134,11}, field = {154,205,50}, plain = {152,251,152}, cave = {255,140,0},
}

function mm.apply_terrain_colors()
  mm.refresh_terrain_ids()
  if type(setCustomEnvColor) ~= "function" then
    return false, "setCustomEnvColor unavailable"
  end

  local applied = 0
  for terrain, rgb in pairs(terrain_rgb) do
    local env = mm.terrain_ids and mm.terrain_ids[terrain]
    if env and type(rgb) == "table" then
      local ok = pcall(setCustomEnvColor, env, rgb[1], rgb[2], rgb[3], 255)
      if ok then applied = applied + 1 end
    end
  end

  if applied == 0 then
    return false, "no terrain env ids available yet (wait for gmcp room.sectors)"
  end

  if mm and mm.bump_stats then
    mm.bump_stats("env_colors_set", applied)
  end
  mm.runtime = mm.runtime or {}
  mm.runtime.terrain_colors_applied = true
  mm.note("Applied mapper terrain colors to " .. tostring(applied) .. " sector environments.")
  return true, applied
end

function mm.apply_room_terrain(room_id, terrain_name)
  if not room_id or not terrain_name or terrain_name == "" then return end
  if type(setRoomEnv) ~= "function" then return end
  mm.refresh_terrain_ids()
  local env = mm.terrain_ids and mm.terrain_ids[tostring(terrain_name)]
  if not env then return end
  local ok, result = pcall(setRoomEnv, tonumber(room_id), env)
  if mm and mm.bump_stats then
    if ok and result ~= false then
      mm.bump_stats("room_colors_set")
    else
      mm.bump_stats("failed")
    end
  end
end

local function room_exists(room_id)
  if type(roomExists) == "function" then
    local ok, exists = pcall(roomExists, room_id)
    return ok and exists and true or false
  end
  if type(getRoomArea) ~= "function" then return false end
  local ok, area = pcall(getRoomArea, room_id)
  if not ok then return false end
  return area ~= nil and area ~= -1
end

local function locate_room_by_coords(info)
  if not info then return nil end
  if type(getRoomsByPosition) ~= "function" or type(getAreaTable) ~= "function" then return nil end

  local coord = info.coord or {}
  local x = tonumber(coord.x or info.x)
  local y = tonumber(coord.y or info.y)
  local z = tonumber(coord.z or info.z) or 0
  if not x or not y then return nil end

  local zone = tostring(info.zone or info.area or "")
  local area_id
  local area_table = getAreaTable() or {}
  for key, value in pairs(area_table) do
    if tostring(key) == zone then
      area_id = tonumber(value)
      break
    elseif tostring(value) == zone then
      area_id = tonumber(key)
      break
    end
  end

  local function find_in_area(aid)
    local ok, rooms = pcall(getRoomsByPosition, aid, x, y, z)
    if not ok or type(rooms) ~= "table" then return nil end
    for room_id, _ in pairs(rooms) do
      return tonumber(room_id)
    end
    return nil
  end

  if area_id then
    local rid = find_in_area(area_id)
    if rid then return rid end
    mm.debug("coords lookup in matched area failed; scanning all areas")
  end

  for key, value in pairs(area_table) do
    local aid = tonumber(value) or tonumber(key)
    if aid then
      local rid = find_in_area(aid)
      if rid then
        mm.debug("coords lookup found room in area " .. tostring(aid))
        return rid
      end
    end
  end

  return nil
end


local function find_room_by_user_data(vnum)
  if type(getRooms) ~= "function" or type(getRoomUserData) ~= "function" then return nil end
  local ok_rooms, rooms = pcall(getRooms)
  if not ok_rooms or type(rooms) ~= "table" then return nil end

  local target = tostring(vnum or "")
  if target == "" then return nil end

  for room_id, _ in pairs(rooms) do
    local ok_ud, ud = pcall(getRoomUserData, room_id)
    if ok_ud and type(ud) == "table" then
      if tostring(ud.vnum or "") == target or tostring(ud.id or "") == target or tostring(ud.roomid or "") == target then
        return tonumber(room_id)
      end
    end
  end
  return nil
end

local function native_bigmap_active()
  if mm.minimap and mm.minimap.is_native_mode then
    return mm.minimap.is_native_mode()
  end
  return mm.state and mm.state.minimap and mm.state.minimap.bigmap_mode == "native"
end

local function local_bigmap_active()
  return not native_bigmap_active()
end


local function sync_to_room_id(room_id, reason)
  room_id = tonumber(room_id)
  if not room_id then return false end
  if type(centerview) ~= "function" then
    mm.runtime = mm.runtime or {}
    if not mm.runtime.missing_centerview_warned then
      mm.runtime.missing_centerview_warned = true
      mm.warn("Mudlet centerview() is unavailable; native bigmap tracking is disabled.")
    else
      mm.debug("centerview() missing; skipping bigmap sync for room " .. tostring(room_id) .. " (" .. tostring(reason or "direct") .. ")")
    end
    return false
  end

  -- Mudlet uses centerview() to set both the mapper's player room and view.
  -- There is no separate setPlayerRoom() mapper API.
  local ok, result = pcall(centerview, room_id)
  if not ok or result == false then
    local detail = ok and "centerview() returned false" or tostring(result)
    mm.warn("Failed to center native bigmap on room " .. tostring(room_id) .. " (" .. tostring(reason or "direct") .. "): " .. detail)
    mm.debug("centerview failed (" .. tostring(reason or "direct") .. "): " .. detail)
    return false
  end

  if type(getPlayerRoom) == "function" then
    local got_room, player_room = pcall(getPlayerRoom)
    if got_room and tonumber(player_room) and tonumber(player_room) ~= room_id then
      mm.debug(string.format(
        "centerview verification failed (%s): requested=%s actual=%s",
        tostring(reason or "direct"), tostring(room_id), tostring(player_room)))
      return false
    end
  end

  mm.runtime = mm.runtime or {}
  mm.runtime.last_player_room = room_id
  mm.debug("centerview -> " .. tostring(room_id) .. " (" .. tostring(reason or "direct") .. ")")
  return true
end

local function sync_from_runtime_coords(reason)
  local rt = mm.runtime or {}
  local x = tonumber(rt.last_coords_x)
  local y = tonumber(rt.last_coords_y)
  local z = tonumber(rt.last_coords_z) or 0
  if not x or not y then return false end

  local info = {
    x = x,
    y = y,
    z = z,
    zone = rt.last_zone,
    area = rt.last_zone,
  }

  local rid = locate_room_by_coords(info)
  if not rid then
    mm.debug("coords runtime fallback failed for " .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z))
    return false
  end

  return sync_to_room_id(rid, reason or "runtime_coords")
end

local function sync_current_room(info, reason)
  if type(centerview) ~= "function" then return false end

  local gmcp_uid = tonumber(info and info.num)
  local coord = (info and info.coord) or {}
  local gx = tonumber(coord.x or info.x)
  local gy = tonumber(coord.y or info.y)
  local gz = tonumber(coord.z or info.z) or 0

  mm.debug("gmcp room info: num=" .. tostring(info and info.num) .. " zone=" .. tostring(info and (info.zone or info.area)) .. " name=" .. tostring(info and info.name) .. " coords=" .. tostring(gx) .. "," .. tostring(gy) .. "," .. tostring(gz))

  if gmcp_uid == -1 then gmcp_uid = nil end

  if gmcp_uid then
    local exists = room_exists(gmcp_uid)
    mm.debug("gmcp room id exists in map DB=" .. tostring(exists))
    if exists and sync_to_room_id(gmcp_uid, reason or "gmcp_room_direct") then
      mm.runtime = mm.runtime or {}
      if not mm.runtime.located_once then
        mm.runtime.located_once = true
        mm.note("Mapper synchronized to room " .. tostring(gmcp_uid) .. ".")
      end
      return true
    end
    if not exists then
      mm.debug("gmcp room id " .. tostring(gmcp_uid) .. " missing in loaded map; trying coordinate/userdata fallback")
    end
  end

  local target_uid = locate_room_by_coords(info)
  if target_uid then
    if sync_to_room_id(target_uid, reason or "gmcp_coords_fallback") then return true end
  end

  target_uid = find_room_by_user_data(info and info.num)
  if target_uid then
    if sync_to_room_id(target_uid, reason or "gmcp_userdata_fallback") then return true end
  end

  mm.warn("Bigmap location unresolved. GMCP room=" .. tostring(info and info.num) .. " coords=" .. tostring(gx) .. "," .. tostring(gy) .. "," .. tostring(gz))
  return false
end

function mm.sync_native_bigmap_to_current_room(reason)
  if not native_bigmap_active() then return false end
  local info = mm.get_room_info and mm.get_room_info() or nil
  if not info then return false end
  return sync_current_room(info, reason)
end

function mm.on_room_info()
  local info = mm.get_room_info()
  if not info then
    mm.debug("on_room_info: gmcp room info missing")
    return
  end

  mm.runtime = mm.runtime or {}
  local coord = info.coord or {}
  mm.runtime.last_coords_x = tonumber(coord.x or info.x) or mm.runtime.last_coords_x
  mm.runtime.last_coords_y = tonumber(coord.y or info.y) or mm.runtime.last_coords_y
  mm.runtime.last_coords_z = tonumber(coord.z or info.z) or mm.runtime.last_coords_z
  mm.runtime.last_zone = tostring(info.zone or info.area or mm.runtime.last_zone or "")

  if mm.minimap and mm.minimap.on_navigation_state_changed then
    mm.minimap.on_navigation_state_changed("room_update")
  end

  local native_mode = native_bigmap_active()
  if native_mode and (not mm.state or mm.state.auto_locate ~= false) then
    sync_current_room(info)
  end

  local room_id = tonumber(info.num) or info.num
  local center_room = native_mode and
    (tonumber(mm.runtime and mm.runtime.last_player_room) or tonumber(info.num)) or room_id
  local room_name = tostring(info.name or "")
  local area_name = mm.get_area_display_name(info)
  if mm.minimap and mm.minimap.set_room_title then
    mm.minimap.set_room_title(room_name, room_id, area_name)
  end
  if not native_mode and mm.minimap and mm.minimap.update_local_map then
    mm.minimap.update_local_map(center_room or room_id)
  end
  if native_mode then
    mm.apply_room_terrain(room_id, info.terrain)
  end

  mm.runtime = mm.runtime or {}
  if tostring(mm.runtime.last_reported_room_num or "") ~= tostring(room_id or "") then
    mm.runtime.last_reported_room_num = tostring(room_id or "")
  end

  mm.runtime.last_room_name = room_name
  mm.runtime.last_room_num = tostring(room_id or "")

  mm.show_room_note(room_id, info, "gmcp_room_info")

end

function mm.show_room_note(room_id, info, source)
  if not (mm and mm.state and mm.state.shownotes) then return false end
  if room_id == nil then return false end

  local note_info = info
  if type(note_info) ~= "table" then
    note_info = mm.get_room_info and mm.get_room_info() or {}
  end

  local room_note = tostring(note_info.note or "")
  if room_note == "" and mm.get_room_note then
    local saved_note = mm.get_room_note(room_id)
    room_note = tostring(saved_note or "")
  end
  if room_note == "" then return false end

  local note_source = tostring(source or "unknown")

  if mm.state and mm.state.debug then
    mm.debug(string.format(
      "room-note candidate source=%s room=%s",
      note_source,
      tostring(room_id)
    ))
  end

  -- Defer one tick so the room title line is already printed, avoiding the
  -- note being concatenated onto the same row as the room name.
  local emit_note = function()
    local player_state = nil
    if gmcp and gmcp.char and gmcp.char.status and gmcp.char.status.state ~= nil then
      player_state = tonumber(gmcp.char.status.state) or tostring(gmcp.char.status.state)
    elseif snd and snd.char and snd.char.status and snd.char.status.state ~= nil then
      player_state = tonumber(snd.char.status.state) or tostring(snd.char.status.state)
    end
    mm.debug("player state before room note emit=" .. tostring(player_state))
    mm.debug("emitting room note (source=" .. note_source .. ", room=" .. tostring(room_id) .. ")")
    if mm.room_note then
      mm.room_note("Room note: " .. room_note)
    else
      mm.note("Room note: " .. room_note)
    end
  end
  if type(tempTimer) == "function" then
    tempTimer(0, emit_note)
  else
    emit_note()
  end
  return true
end
function mm.on_room_exits()
  -- Minimap updates are intentionally limited to copied ASCII map lines between
  -- <MAPSTART>/<MAPEND>; this hook remains for debug/event parity only.
  return
end

function mm.on_map_start_tag()
  if type(deleteLine) == "function" then deleteLine() end
  mm.on_map_start()
end

function mm.on_map_start()
  mm.runtime = mm.runtime or {}
  mm.runtime.in_ascii_map = true
  mm.runtime.ascii_map_lines = {}
  mm.runtime.map_copy_mode = true

  if mm.minimap and mm.minimap.clear_console then
    mm.minimap.clear_console("minimap")
    if mm.minimap.backend == "ascii_fallback" then
      mm.minimap.clear_console("bigmap")
    end
  end
end

function mm.on_map_ascii_line()
  if not (mm.runtime and mm.runtime.in_ascii_map) then return end
  if not matches or matches[2] == nil then return end

  local line = matches[2]
  if line == "<MAPSTART>" or line == "<MAPEND>" then
    return
  end

  local decho_line = styles_to_decho()
  table.insert(mm.runtime.ascii_map_lines, { raw = line, decho = decho_line })

  local copied = false
  if mm.minimap and mm.minimap.append_current_line then
    copied = mm.minimap.append_current_line("minimap") or false
    if mm.minimap.backend == "ascii_fallback" then
      mm.minimap.append_current_line("bigmap")
    end
  end

  if not copied then
    mm.runtime.map_copy_mode = false
  end

end

function mm.on_map_end_tag()
  if type(deleteLine) == "function" then deleteLine() end
  mm.on_map_end()
end

function mm.on_map_end()
  if not (mm.runtime and mm.runtime.in_ascii_map) then return end

  mm.runtime.in_ascii_map = false
  local lines = mm.runtime.ascii_map_lines or {}

  if mm.runtime.map_copy_mode then
    mm.runtime.last_map_copy_time = (type(getEpoch) == "function") and getEpoch() or os.time()
  elseif mm.minimap and mm.minimap.set_map_lines then
    mm.minimap.set_map_lines(lines)
  else
    mm.minimap.lines = mm.minimap.lines or {}
    mm.minimap.lines.minimap = lines
    mm.minimap.redraw("minimap")
  end

  local first_line = lines[1]
  if type(first_line) == "table" then first_line = first_line.raw end
  local room_name = trim(first_line or "")
  if room_name and room_name ~= "" and room_name ~= "<MAPSTART>" then
    mm.runtime.last_ascii_room_name = room_name
    local info = mm.get_room_info() or {}
    mm.runtime.last_ascii_room_num = tostring(info.num or "")
    if mm.minimap and mm.minimap.set_room_title then
      mm.minimap.set_room_title(room_name, info.num, mm.get_area_display_name(info))
    end
    if local_bigmap_active() and mm.minimap and mm.minimap.update_local_map then
      mm.minimap.update_local_map(info.num)
    end
  end
end



function mm.on_room_vnum_line()
  if not matches then return end
  local vnum = tonumber(matches[2])
  local rname = tostring(matches[3] or "")
  if not vnum then return end

  if mm.minimap and mm.minimap.set_room_title and rname ~= "" then
    mm.minimap.set_room_title(rname, vnum, mm.get_area_display_name())
  end

  if local_bigmap_active() then
    if mm.minimap and mm.minimap.update_local_map then
      mm.minimap.update_local_map(vnum)
    end
    return
  end

  if room_exists(vnum) and sync_to_room_id(vnum, "vnum_line") then return end

  local mapped = find_room_by_user_data(vnum)
  if mapped then
    sync_to_room_id(mapped, "vnum_userdata")
  end
end

function mm.on_coords_line()
  if type(deleteLine) == "function" then deleteLine() end
end

function mm.on_tag_line()
  if type(deleteLine) == "function" then deleteLine() end
end

function mm.on_room_packet()
  -- Keep for debug compatibility only. Specific room handlers process updates.
end

local continent_area_keys = {
  mesolar = true,
  ["the continent of mesolar"] = true,
  southern = true,
  ["southern ocean"] = true,
  gelidus = true,
  abend = true,
  ["the dark continent, abend"] = true,
  alagh = true,
  uncharted = true,
  ["uncharted oceans"] = true,
  vidblain = true,
  ["vidblain, the ever dark"] = true,
}

local function room_area_key(info)
  local area = tostring(info and (info.zone or info.area) or ""):lower()
    :gsub("^%s+", ""):gsub("%s+$", "")
  if area ~= "" then return area end

  local room_id = info and info.num
  if room_id and snd and snd.mapper and snd.mapper.getRoomInfo then
    local room = snd.mapper.getRoomInfo(tostring(room_id))
    area = tostring(room and room.area or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  end
  return area
end

function mm.is_continent_room(info)
  return continent_area_keys[room_area_key(info)] == true
end

function mm.sync_hybrid_bigmap_to_room(info)
  if mm.is_continent_room(info) then
    return mm.minimap.activate_bigmap_native(), true
  else
    return mm.minimap.activate_bigmap_local(), false
  end
end

function mm.on_room_info_event()
  local info = mm.get_room_info()
  local room_num = tostring(info and info.num or "")
  local room_area = tostring(info and (info.zone or info.area) or "")

  local switched, continent = false, false
  if mm.portal_usage and mm.portal_usage.on_room_info then
    mm.portal_usage.on_room_info(info)
  end
  if mm.minimap and mm.minimap.get_bigmap_mode and mm.minimap.get_bigmap_mode() == "hybrid" then
    switched, continent = mm.sync_hybrid_bigmap_to_room(info)
  end
  mm.on_room_info()
  if switched and continent then raiseWindow("mapper") end
  if snd and snd.mapper and snd.mapper.requestMetadataForRoom then
    snd.mapper.requestMetadataForRoom(info)
  end
  if type(raiseEvent) == "function" then
    -- Integration surface: external scripts can listen to "mm.room.changed"
    raiseEvent("mm.room.changed", room_num, room_area)
  end
end

function mm.on_room_exits_event()
  local exits = mm.get_room_exits()
  mm.debug("gmcp.room.exits event; exits=" .. tostring(type(exits) == "table" and "table" or "nil"))
  mm.on_room_exits()
end

function mm.on_room_area_event()
  local area = mm.get_room_area_info()
  if type(area) ~= "table" then
    mm.debug("gmcp.room.area event; area payload missing")
    return
  end
  if snd and snd.mapper and snd.mapper.persistAreaInfo then
    local ok, err = snd.mapper.persistAreaInfo(area)
    if not ok then
      mm.debug("gmcp.room.area persist skipped/failed: " .. tostring(err))
    end
  end

  local info = mm.get_room_info() or {}
  local room_name = tostring(info.name or (mm.runtime and mm.runtime.last_room_name) or "")
  if room_name ~= "" and mm.minimap and mm.minimap.set_room_title then
    mm.minimap.set_room_title(room_name, info.num, mm.get_area_display_name(info))
  end
end

function mm.on_room_sectors_event()
  local packet = mm.get_room_sectors_packet()
  local refreshed = mm.refresh_terrain_ids()
  if type(packet) ~= "table" then
    mm.debug("gmcp.room.sectors event; sectors payload missing")
    return
  end
  if snd and snd.mapper and snd.mapper.persistSectors then
    local ok, err = snd.mapper.persistSectors(packet)
    if not ok then
      mm.debug("gmcp.room.sectors persist skipped/failed: " .. tostring(err))
    end
  end
  mm.runtime = mm.runtime or {}
  if refreshed and not mm.runtime.terrain_colors_applied then
    local ok, err = mm.apply_terrain_colors()
    if not ok then mm.debug("terrain color application deferred: " .. tostring(err)) end
  end
end

-- Compatibility shim for sessions that still have the removed auto-rebuild
-- event handler registered from an older script load.
function mm.schedule_auto_layout_rebuild()
  return false
end

local function current_char_status_state()
  if not (gmcp and gmcp.char and gmcp.char.status) then return nil end
  return tonumber(gmcp.char.status.state)
end

function mm.on_char_status_event()
  local state = current_char_status_state()
  if state == nil then return end

  mm.runtime = mm.runtime or {}
  local previous_state = mm.runtime.autostop_previous_char_state
  mm.runtime.autostop_previous_char_state = state

  if previous_state == nil or previous_state == 8 or state ~= 8 then return end
  if not (mm.state and mm.state.autostop_enabled ~= false) then return end

  local navigating = snd and (
    (snd.nav and snd.nav.goingToRoom ~= nil) or
    (snd.mapper and snd.mapper.goingToRoom ~= nil)
  )
  if not navigating then return end

  send("stop")
end

local function kill_trigger_field(field)
  local id = mm[field]
  if id and type(killTrigger) == "function" then
    pcall(killTrigger, id)
  end
  mm[field] = nil
end

function mm.register_events()
  if mm._events then
    if type(killAnonymousEventHandler) ~= "function" then return end
    for _, event_id in ipairs(mm._events) do
      pcall(killAnonymousEventHandler, event_id)
    end
    mm._events = nil
  end

  kill_trigger_field("_room_vnum_trigger")
  kill_trigger_field("_map_start_trigger")
  kill_trigger_field("_map_line_trigger")
  kill_trigger_field("_map_end_trigger")
  kill_trigger_field("_coords_trigger")
  kill_trigger_field("_roomchars_open_trigger")
  kill_trigger_field("_roomchars_close_trigger")
  kill_trigger_field("_roomobjs_open_trigger")
  kill_trigger_field("_roomobjs_close_trigger")
  kill_trigger_field("_rdesc_open_trigger")
  kill_trigger_field("_rdesc_close_trigger")

  mm.runtime = mm.runtime or {}
  mm.runtime.autostop_previous_char_state = current_char_status_state()

  mm._events = {
    registerAnonymousEventHandler("gmcp.char.status", "mm.on_char_status_event"),
    registerAnonymousEventHandler("gmcp.room.info", "mm.on_room_info_event"),
    registerAnonymousEventHandler("gmcp.Room.Info", "mm.on_room_info_event"),
    registerAnonymousEventHandler("gmcp.room.exits", "mm.on_room_exits_event"),
    registerAnonymousEventHandler("gmcp.Room.Exits", "mm.on_room_exits_event"),
    registerAnonymousEventHandler("gmcp.room", "mm.on_room_packet"),
    registerAnonymousEventHandler("gmcp.Room", "mm.on_room_packet"),
    registerAnonymousEventHandler("gmcp.room.area", "mm.on_room_area_event"),
    registerAnonymousEventHandler("gmcp.Room.Area", "mm.on_room_area_event"),
    registerAnonymousEventHandler("gmcp.room.sectors", "mm.on_room_sectors_event"),
    registerAnonymousEventHandler("gmcp.Room.Sectors", "mm.on_room_sectors_event"),
  }

  -- Capture every line while the map block is active; Aardwolf map lines contain
  -- braces/tags and not just line-art symbols.
  mm._map_start_trigger = tempTrigger("<MAPSTART>", "mm.on_map_start_tag()")
  mm._map_line_trigger = tempRegexTrigger("^(.*)$", "mm.on_map_ascii_line()")
  mm._map_end_trigger = tempTrigger("<MAPEND>", "mm.on_map_end_tag()")
  -- Disabled: this generic pattern also matches combat lines like "[1] ...",
  -- which can cause incorrect room sync. Prefer gmcp.room.info as source of truth.
  mm._room_vnum_trigger = nil
  mm._coords_trigger = tempRegexTrigger("^\\{coords\\}(.*)$", "mm.on_coords_line()")
  mm._roomchars_open_trigger = tempTrigger("{roomchars}", "mm.on_tag_line()")
  mm._roomchars_close_trigger = tempTrigger("{/roomchars}", "mm.on_tag_line()")
  mm._roomobjs_open_trigger = tempTrigger("{roomobjs}", "mm.on_tag_line()")
  mm._roomobjs_close_trigger = tempTrigger("{/roomobjs}", "mm.on_tag_line()")
  mm._rdesc_open_trigger = tempTrigger("{rdesc}", "mm.on_tag_line()")
  mm._rdesc_close_trigger = tempTrigger("{/rdesc}", "mm.on_tag_line()")
end
