mm = mm or {}

mm.state = mm.state or {
  quick_mode = true,
  shownotes = true,
  compact_mode = false,
  backups_enabled = true,
  backups_quiet = false,
  backups_compressed = false,
  show_up_down = false,
  underline_links = true,
  minimap = { enabled = true, show_room = true, show_exits = true, show_coords = true, echo = true, bigmap_mode = "hybrid", local_radius = 4, local_room_size = 15 },
  windows = {
    minimap = { x = "70%", y = "0%", width = "30%", height = "35%", max_lines = 16, enabled = true, locked = false, font_size = 8 },
    bigmap = { x = "45%", y = "35%", width = "55%", height = "65%", max_lines = 60, enabled = true, locked = false, font_size = 9 },
  },
  last_target = nil,
  map_db = "Aardwolf.db",
  native_mapper_db = "mmapper_converted_map.dat",
  auto_locate = true,
  center_on_locate = true,
  portal_guard_enabled = true,
  debug = false,
}

mm.runtime = mm.runtime or {
  located_once = false,
  cexit_last_rows = {},
  cexit_last_scope = nil,
}

mm.search_state = mm.search_state or {
  results = {},
  index = 0,
}

mm.portals = mm.portals or {
  rebuilt = {},
  rebuilt_at = nil,
  settings = {
    recall_ids = {},
    bounce_portal_id = nil,
    bounce_recall_id = nil,
  },
}

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

local function now_millis()
  if type(getEpoch) == "function" then
    local v = tonumber(getEpoch())
    if v then
      if v < 10000000000 then
        return v * 1000
      end
      return v
    end
  end
  return (os.clock() or 0) * 1000
end

local STATS_FIELDS = {
  "rooms_updated",
  "areas_updated",
  "exits_updated",
  "env_rows_updated",
  "coords_stored",
  "coords_set",
  "layouts_rebuilt",
  "room_colors_set",
  "env_colors_set",
  "skipped",
  "failed",
}

function mm.ensure_stats()
  mm.runtime = mm.runtime or {}
  local stats = mm.runtime.stats
  if type(stats) ~= "table" then
    stats = {}
    mm.runtime.stats = stats
  end
  stats.started_at = tonumber(stats.started_at) or now_millis()
  for _, field in ipairs(STATS_FIELDS) do
    stats[field] = tonumber(stats[field]) or 0
  end
  return stats
end

function mm.reset_stats()
  mm.runtime = mm.runtime or {}
  mm.runtime.stats = { started_at = now_millis() }
  mm.ensure_stats()
  mm.note("Mapper stats reset.")
end

function mm.bump_stats(field, amount)
  local stats = mm.ensure_stats()
  local value = tonumber(amount) or 1
  if value == 0 then return end
  stats[field] = (tonumber(stats[field]) or 0) + value
end

function mm.bump_stats_many(changes)
  if type(changes) ~= "table" then return end
  for field, amount in pairs(changes) do
    mm.bump_stats(field, amount)
  end
end

local function elapsed_text(started_at)
  local elapsed = math.max(0, math.floor((now_millis() - (tonumber(started_at) or now_millis())) / 1000))
  local hours = math.floor(elapsed / 3600)
  local minutes = math.floor((elapsed % 3600) / 60)
  local seconds = elapsed % 60
  return string.format("%02d:%02d:%02d ago", hours, minutes, seconds)
end

local function print_stat(label, value)
  cecho(string.format("    <cyan>%-19s<reset> %8d\n", label .. ":", tonumber(value) or 0))
end

local function pending_room_persist_count()
  local pending = snd and snd.mapper and snd.mapper.pendingPersists
  if type(pending) ~= "table" then return 0 end
  local count = 0
  for _ in pairs(pending) do
    count = count + 1
  end
  return count
end

function mm.show_stats()
  local stats = mm.ensure_stats()
  local pending = pending_room_persist_count()
  cecho("\n<CornflowerBlue>[MMAPPER]<reset> <white>Mapper stats since load/reset<reset>\n\n")

  cecho("  <yellow>DB updates<reset>\n")
  print_stat("Rooms updated", stats.rooms_updated)
  print_stat("Areas updated", stats.areas_updated)
  print_stat("Exits updated", stats.exits_updated)
  print_stat("Coords stored", stats.coords_stored)
  print_stat("Env rows updated", stats.env_rows_updated)

  cecho("\n  <yellow>Map updates<reset>\n")
  print_stat("Coords set", stats.coords_set)
  print_stat("Layouts rebuilt", stats.layouts_rebuilt)
  print_stat("Room colors set", stats.room_colors_set)
  print_stat("Env colors set", stats.env_colors_set)

  cecho("\n  <yellow>Problems<reset>\n")
  print_stat("Skipped", stats.skipped)
  print_stat("Failed", stats.failed)

  cecho("\n  <yellow>Status<reset>\n")
  cecho("    <cyan>Live room env colors:<reset> " .. (type(setRoomEnv) == "function" and "on" or "unavailable") .. "\n")
  cecho("    <cyan>Bulk env colors:<reset> manual\n")
  if pending > 0 then
    cecho("    <cyan>Pending room persists:<reset> " .. tostring(pending) .. " not counted yet\n")
  end
  cecho("    <cyan>Since:<reset> " .. elapsed_text(stats.started_at) .. "\n")
end

local function persistence_dir()
  return getMudletHomeDir() .. "/persistence"
end

function mm.persistence_path(filename)
  return persistence_dir() .. "/" .. tostring(filename or "")
end

function mm.legacy_persistence_path(filename)
  return getMudletHomeDir() .. "/" .. tostring(filename or "")
end

function mm.load_persistence_chunk(filename)
  local primary = mm.persistence_path(filename)
  local chunk = loadfile(primary)
  if chunk then
    return chunk, primary
  end

  local legacy = mm.legacy_persistence_path(filename)
  chunk = loadfile(legacy)
  if chunk then
    return chunk, legacy
  end

  return nil, primary
end

function mm.open_persistence_file(filename, mode)
  local path = mm.persistence_path(filename)
  local f = io.open(path, mode or "wb")
  if f then
    return f
  end

  if type(mm.ensure_dir) == "function" then
    mm.ensure_dir(persistence_dir())
  end
  return io.open(path, mode or "wb")
end

local PORTAL_PERSIST_FILE = "mmapper_portals.lua"
local DELETED_CEXITS_PERSIST_FILE = "mmapper_deleted_cexits.lua"
local DELETED_PORTALS_PERSIST_FILE = "mmapper_deleted_portals.lua"
local SETTINGS_PERSIST_FILE = "mmapper_settings.lua"

function mm.load_settings_persistence()
  local chunk = mm.load_persistence_chunk(SETTINGS_PERSIST_FILE)
  if not chunk then return false end

  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return false end
  if type(data.portal_guard_enabled) == "boolean" then
    mm.state.portal_guard_enabled = data.portal_guard_enabled
  end
  if type(data.native_mapper_db) == "string" and data.native_mapper_db ~= "" then
    mm.state.native_mapper_db = data.native_mapper_db
  end
  if type(data.auto_locate) == "boolean" then
    mm.state.auto_locate = data.auto_locate
    mm.state.center_on_locate = data.auto_locate
  end
  if type(data.minimap) == "table" then
    mm.state.minimap = mm.state.minimap or {}
    if data.minimap.bigmap_mode == "local" or data.minimap.bigmap_mode == "native" or
        data.minimap.bigmap_mode == "hybrid" then
      mm.state.minimap.bigmap_mode = data.minimap.bigmap_mode
    end
    if tonumber(data.minimap.local_radius) then
      mm.state.minimap.local_radius = tonumber(data.minimap.local_radius)
    end
    if tonumber(data.minimap.local_room_size) then
      mm.state.minimap.local_room_size = tonumber(data.minimap.local_room_size)
    end
  end
  return true
end

function mm.save_settings_persistence()
  local f = mm.open_persistence_file(SETTINGS_PERSIST_FILE, "wb")
  if not f then
    return false, "unable to open mapper settings persistence file for writing"
  end
  f:write("return " .. serialize_value({
    portal_guard_enabled = mm.state.portal_guard_enabled ~= false,
    native_mapper_db = mm.state.native_mapper_db or "mmapper_converted_map.dat",
    auto_locate = mm.state.auto_locate ~= false,
    minimap = {
      bigmap_mode = (mm.state.minimap and mm.state.minimap.bigmap_mode) or "hybrid",
      local_radius = tonumber(mm.state.minimap and mm.state.minimap.local_radius) or 4,
      local_room_size = tonumber(mm.state.minimap and mm.state.minimap.local_room_size) or 15,
    },
  }))
  f:close()
  return true
end

function mm.portal_guard_status_text()
  return string.format(
    "portalguard %s: when on, guarded routes only use portals within 30 levels of your current level; xrtforce bypasses this safety.",
    (mm.state.portal_guard_enabled ~= false) and "on" or "off"
  )
end

function mm.set_portal_guard(enabled)
  mm.state.portal_guard_enabled = enabled ~= false
  local ok, err = mm.save_settings_persistence()
  if not ok then
    return false, err
  end
  return true
end

local function sanitize_deleted_cexit_entry(entry)
  if type(entry) ~= "table" then return nil end
  local fromuid = tostring(entry.fromuid or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local touid = tostring(entry.touid or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local dir = tostring(entry.dir or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if fromuid == "" or touid == "" or dir == "" then return nil end
  return {
    fromuid = fromuid,
    touid = touid,
    dir = dir,
    area = tostring(entry.area or ""),
    name = tostring(entry.name or ""),
    deleted_at = tonumber(entry.deleted_at) or os.time(),
  }
end

function mm.load_deleted_cexits_persistence()
  local chunk, source_path = mm.load_persistence_chunk(DELETED_CEXITS_PERSIST_FILE)
  if not chunk then return false end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return false end

  local restored = {}
  for _, entry in ipairs(data.deleted or {}) do
    local cleaned = sanitize_deleted_cexit_entry(entry)
    if cleaned then
      table.insert(restored, cleaned)
    end
  end

  while #restored > 20 do
    table.remove(restored, 1)
  end
  mm.state.deleted_cexits = restored
  if source_path == mm.legacy_persistence_path(DELETED_CEXITS_PERSIST_FILE) then
    mm.save_deleted_cexits_persistence()
  end
  return #restored > 0
end

function mm.save_deleted_cexits_persistence()
  local timing_enabled = mm.state and mm.state.debug
  local timing_start = timing_enabled and now_millis() or nil
  local payload = {
    deleted = mm.state.deleted_cexits or {},
  }
  local serialized = "return " .. serialize_value(payload)
  local serialize_done = timing_enabled and now_millis() or nil

  local f = mm.open_persistence_file(DELETED_CEXITS_PERSIST_FILE, "wb")
  local open_done = timing_enabled and now_millis() or nil
  if not f then
    return false, "unable to open deleted cexit persistence file for writing"
  end

  f:write(serialized)
  local write_done = timing_enabled and now_millis() or nil
  f:close()
  local close_done = timing_enabled and now_millis() or nil

  if timing_enabled then
    mm.debug(string.format(
      "deleted cexit history save timing: serialize=%.1fms open=%.1fms write=%.1fms close=%.1fms total=%.1fms",
      (serialize_done or timing_start) - timing_start,
      (open_done or serialize_done) - (serialize_done or timing_start),
      (write_done or open_done) - (open_done or timing_start),
      (close_done or write_done) - (write_done or timing_start),
      (close_done or timing_start) - timing_start
    ))
  end

  return true
end

local function sanitize_deleted_portal_entry(entry)
  if type(entry) ~= "table" then return nil end
  local fromuid = tostring(entry.fromuid or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local touid = tostring(entry.touid or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local command = tostring(entry.command or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if (fromuid ~= "*" and fromuid ~= "**") or touid == "" or command == "" then
    return nil
  end
  return {
    fromuid = fromuid,
    touid = touid,
    command = command,
    level = tonumber(entry.level) or 0,
    chaos = (tostring(entry.chaos or "no") == "yes") and "yes" or "no",
    area = tostring(entry.area or ""),
    room_name = tostring(entry.room_name or ""),
    deleted_at = tonumber(entry.deleted_at) or os.time(),
  }
end

function mm.load_deleted_portals_persistence()
  local chunk, source_path = mm.load_persistence_chunk(DELETED_PORTALS_PERSIST_FILE)
  if not chunk then return false end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return false end

  local restored = {}
  for _, entry in ipairs(data.deleted or {}) do
    local cleaned = sanitize_deleted_portal_entry(entry)
    if cleaned then table.insert(restored, cleaned) end
  end
  while #restored > 20 do table.remove(restored, 1) end
  mm.state.deleted_portals = restored
  if source_path == mm.legacy_persistence_path(DELETED_PORTALS_PERSIST_FILE) then
    mm.save_deleted_portals_persistence()
  end
  return #restored > 0
end

function mm.save_deleted_portals_persistence()
  local payload = {
    deleted = mm.state.deleted_portals or {},
  }
  local f = mm.open_persistence_file(DELETED_PORTALS_PERSIST_FILE, "wb")
  if not f then
    return false, "unable to open deleted portal persistence file for writing"
  end
  f:write("return " .. serialize_value(payload))
  f:close()
  return true
end

local function sanitize_rebuilt_portal_entry(entry)
  if type(entry) ~= "table" then return nil end
  local portal_id = tostring(entry.portal_id or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local command = tostring(entry.command or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if portal_id == "" or command == "" then
    return nil
  end
  return {
    nr = tonumber(entry.nr) or 0,
    portal_id = portal_id,
    command = command,
    level = tonumber(entry.level) or 0,
    chaos = (tostring(entry.chaos or "no") == "yes") and "yes" or "no",
    touid = entry.touid ~= nil and tostring(entry.touid) or nil,
    fromuid = entry.fromuid ~= nil and tostring(entry.fromuid) or "*",
    leadsto = entry.leadsto ~= nil and tostring(entry.leadsto) or nil,
    target_uid = entry.target_uid ~= nil and tostring(entry.target_uid) or nil,
    area = tostring(entry.area or "?"),
    room_name = tostring(entry.room_name or "?"),
    fixed_recall = entry.fixed_recall == true,
  }
end

function mm.load_portal_persistence()
  local chunk, source_path = mm.load_persistence_chunk(PORTAL_PERSIST_FILE)
  if not chunk then return false end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return false end

  local restored = {}
  for _, entry in ipairs(data.rebuilt or {}) do
    local cleaned = sanitize_rebuilt_portal_entry(entry)
    if cleaned then
      table.insert(restored, cleaned)
    end
  end

  if #restored == 0 then
    return false
  end

  table.sort(restored, function(a, b)
    return (tonumber(a.nr) or 0) < (tonumber(b.nr) or 0)
  end)
  for i, entry in ipairs(restored) do
    entry.nr = i
  end

  mm.portals = mm.portals or {}
  mm.portals.rebuilt = restored
  mm.portals.rebuilt_at = tonumber(data.rebuilt_at) or os.time()
  local persisted_settings = type(data.settings) == "table" and data.settings or {}
  mm.portals.settings = mm.portals.settings or {}
  mm.portals.settings.recall_ids = {}
  for _, id in ipairs(persisted_settings.recall_ids or {}) do
    local normalized = tostring(id or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if normalized ~= "" then
      mm.portals.settings.recall_ids[normalized] = true
    end
  end
  mm.portals.settings.bounce_portal_id = persisted_settings.bounce_portal_id and tostring(persisted_settings.bounce_portal_id) or nil
  mm.portals.settings.bounce_recall_id = persisted_settings.bounce_recall_id and tostring(persisted_settings.bounce_recall_id) or nil
  if source_path == mm.legacy_persistence_path(PORTAL_PERSIST_FILE) then
    mm.save_portal_persistence()
  end
  return true
end

function mm.save_portal_persistence()
  mm.portals = mm.portals or {}
  mm.portals.settings = mm.portals.settings or {}
  local recall_ids = {}
  for id, enabled in pairs(mm.portals.settings.recall_ids or {}) do
    if enabled then
      table.insert(recall_ids, tostring(id))
    end
  end
  table.sort(recall_ids)
  local payload = {
    rebuilt = mm.portals.rebuilt or {},
    rebuilt_at = mm.portals.rebuilt_at,
    settings = {
      recall_ids = recall_ids,
      bounce_portal_id = mm.portals.settings.bounce_portal_id and tostring(mm.portals.settings.bounce_portal_id) or nil,
      bounce_recall_id = mm.portals.settings.bounce_recall_id and tostring(mm.portals.settings.bounce_recall_id) or nil,
    },
  }
  local f = mm.open_persistence_file(PORTAL_PERSIST_FILE, "wb")
  if not f then
    return false, "unable to open portal persistence file for writing"
  end
  f:write("return " .. serialize_value(payload))
  f:close()
  return true
end

local function ensure_portal_settings()
  mm.portals = mm.portals or {}
  mm.portals.settings = mm.portals.settings or {}
  mm.portals.settings.recall_ids = mm.portals.settings.recall_ids or {}
end

local function get_portal_by_index(index)
  local portals = mm.portals and mm.portals.rebuilt or {}
  index = tonumber(index)
  if not index then
    return nil, "invalid index"
  end
  if index < 1 or index > #portals then
    return nil, "portal index out of range"
  end
  return portals[index]
end

function mm.is_portal_recall(portal)
  ensure_portal_settings()
  if not portal then return false end
  if portal.fixed_recall then return true end
  return mm.portals.settings.recall_ids[tostring(portal.portal_id)] == true
end

function mm.is_portal_chaos(portal)
  if not portal then return false end
  return tostring(portal.chaos or "no") == "yes"
end

function mm.set_portal_recall(index, explicit_state)
  ensure_portal_settings()
  local portal, err = get_portal_by_index(index)
  if not portal then
    return false, err
  end
  local id = tostring(portal.portal_id)
  local next_state
  if explicit_state == nil then
    next_state = not mm.is_portal_recall(portal)
  else
    next_state = explicit_state == true
  end
  if next_state and mm.is_portal_chaos(portal) then
    return false, "portal is marked as chaos; toggle chaos off before marking it as recall"
  end
  mm.portals.settings.recall_ids[id] = next_state or nil
  if not next_state and mm.portals.settings.bounce_recall_id == id then
    mm.portals.settings.bounce_recall_id = nil
  end
  return mm.save_portal_persistence()
end


function mm.set_portal_level(args)
  local pnum, level, quiet = tostring(args or ""):match("^%s*(%d+)%s+(%d+)%s*(%S*)%s*$")
  if not pnum or not level then
    mm.warn("Usage: mapper portallevel <index> <level> [quiet]")
    return false, "invalid arguments"
  end

  pnum = tonumber(pnum)
  level = tonumber(level)
  if not pnum or not level then
    mm.warn("Usage: mapper portallevel <index> <level> [quiet]")
    return false, "invalid arguments"
  end

  local quiet_mode = tostring(quiet or ""):lower() == "quiet"
  local selected = get_portal_by_index(pnum)
  if not selected then
    mm.warn("PORTALLEVEL FAILED: Did not find index " .. tostring(pnum) .. ". Try 'mapper portals'.")
    return false, "portal index not found"
  end

  local dir = tostring(selected.command or selected.dir or "")
  local fromuid = tostring(selected.fromuid or "")
  local touid = tostring(selected.touid or selected.target_uid or "")
  if dir == "" or fromuid == "" or touid == "" then
    return false, "selected portal row is missing required fields"
  end

  local ok, qerr = mm.exec_mapper_db(string.format(
    "UPDATE exits SET level=%d WHERE dir=%s AND fromuid=%s AND touid=%s",
    level,
    mm.sql_escape(dir),
    mm.sql_escape(fromuid),
    mm.sql_escape(touid)
  ))
  if not ok then
    return false, qerr
  end

  selected.level = level
  if not quiet_mode then
    mm.note("Portal '" .. dir .. "' to '" .. tostring(selected.room_name or "?") .. "' given minimum level lock of " .. tostring(level) .. ".")
  end
  return mm.save_portal_persistence()
end

function mm.set_portal_chaos(index, explicit_state)
  ensure_portal_settings()
  local ensured, ensure_err = mm.ensure_exits_chaos_column()
  if not ensured then
    return false, "failed ensuring exits.chaos column: " .. tostring(ensure_err)
  end
  local portal, err = get_portal_by_index(index)
  if not portal then
    return false, err
  end
  if mm.is_portal_recall(portal) then
    return false, "chaos can only be toggled on non-recall portals"
  end

  local current = mm.is_portal_chaos(portal)
  local next_state = (explicit_state == nil) and (not current) or (explicit_state == true)
  local next_chaos = next_state and "yes" or "no"
  local fromuid = tostring(portal.fromuid or (portal.fixed_recall and "**" or "*"))
  local command = tostring(portal.command or "")
  local touid = tostring(portal.touid or portal.target_uid or "")
  if command == "" or touid == "" then
    return false, "selected portal row is missing required fields"
  end

  local ok, qerr = mm.exec_mapper_db(string.format(
    "UPDATE exits SET chaos=%s WHERE fromuid=%s AND dir=%s AND touid=%s",
    mm.sql_escape(next_chaos),
    mm.sql_escape(fromuid),
    mm.sql_escape(command),
    mm.sql_escape(touid)
  ))
  if not ok then
    return false, qerr
  end

  local id = tostring(portal.portal_id)
  if next_state then
    mm.portals.settings.recall_ids[id] = nil
    if mm.portals.settings.bounce_portal_id == id then
      mm.portals.settings.bounce_portal_id = nil
    end
    if mm.portals.settings.bounce_recall_id == id then
      mm.portals.settings.bounce_recall_id = nil
    end
  end

  local portals = mm.portals and mm.portals.rebuilt or {}
  for _, entry in ipairs(portals) do
    if tostring(entry.fromuid or "") == fromuid
      and tostring(entry.command or "") == command
      and tostring(entry.touid or entry.target_uid or "") == touid then
      entry.chaos = next_chaos
    end
  end
  mm.apply_bounce_settings_to_snd()
  return mm.save_portal_persistence()
end

local function find_portal_by_id(id)
  if not id then return nil end
  for _, portal in ipairs(mm.portals and mm.portals.rebuilt or {}) do
    if tostring(portal.portal_id) == tostring(id) then
      return portal
    end
  end
  return nil
end

function mm.apply_bounce_settings_to_snd()
  local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
  if not (nav and nav.config) then
    return false, "mapper navigation module is unavailable"
  end
  ensure_portal_settings()
  local bouncePortal = find_portal_by_id(mm.portals.settings.bounce_portal_id)
  local bounceRecall = find_portal_by_id(mm.portals.settings.bounce_recall_id)
  nav.config.bouncePortal = bouncePortal and {
    dir = bouncePortal.command,
    uid = bouncePortal.touid or bouncePortal.target_uid,
    level = tonumber(bouncePortal.level) or 0,
    travelType = "portal",
  } or nil
  nav.config.bounceRecall = bounceRecall and {
    dir = bounceRecall.command,
    uid = bounceRecall.touid or bounceRecall.target_uid,
    level = tonumber(bounceRecall.level) or 0,
    travelType = "recall",
  } or nil
  if snd and snd.config then
    snd.config.mapper = snd.config.mapper or {}
    snd.config.mapper.bouncePortalId = bouncePortal and tostring(bouncePortal.portal_id) or nil
    snd.config.mapper.bounceRecallId = bounceRecall and tostring(bounceRecall.portal_id) or nil
    snd.config.mapper.bouncePortalCommand = bouncePortal and tostring(bouncePortal.command) or nil
    snd.config.mapper.bounceRecallCommand = bounceRecall and tostring(bounceRecall.command) or nil
  end
  if snd and snd.saveState then pcall(snd.saveState) end
  return true
end

function mm.set_bounce_portal(index)
  ensure_portal_settings()
  local portal, err = get_portal_by_index(index)
  if not portal then
    return false, err
  end
  if mm.is_portal_recall(portal) then
    return false, "bounceportal must be a non-recall portal; use mapper portalrecall to unflag it first"
  end
  if mm.is_portal_chaos(portal) then
    return false, "bounceportal cannot be set to a chaos portal; toggle chaos off first"
  end
  mm.portals.settings.bounce_portal_id = tostring(portal.portal_id)
  local ok, save_err = mm.save_portal_persistence()
  if not ok then return false, save_err end
  mm.apply_bounce_settings_to_snd()
  return true, portal
end

function mm.clear_bounce_portal()
  ensure_portal_settings()
  mm.portals.settings.bounce_portal_id = nil
  local ok, err = mm.save_portal_persistence()
  if ok then mm.apply_bounce_settings_to_snd() end
  return ok, err
end

function mm.set_bounce_recall(index)
  ensure_portal_settings()
  local portal, err = get_portal_by_index(index)
  if not portal then
    return false, err
  end
  if not mm.is_portal_recall(portal) then
    return false, "bouncerecall must be set to a portal flagged as recall via mapper portalrecall"
  end
  if mm.is_portal_chaos(portal) then
    return false, "bouncerecall cannot be set to a chaos portal; toggle chaos off first"
  end
  mm.portals.settings.bounce_recall_id = tostring(portal.portal_id)
  local ok, save_err = mm.save_portal_persistence()
  if not ok then return false, save_err end
  mm.apply_bounce_settings_to_snd()
  return true, portal
end

function mm.clear_bounce_recall()
  ensure_portal_settings()
  mm.portals.settings.bounce_recall_id = nil
  local ok, err = mm.save_portal_persistence()
  if ok then mm.apply_bounce_settings_to_snd() end
  return ok, err
end

function mm.note(msg)
  cecho(string.format("<CornflowerBlue>[MMAPPER]<reset> %s\n", msg))
end

function mm.room_note(msg)
  cecho(string.format("<CornflowerBlue>[MMAPPER]<reset> <yellow>%s<reset>\n", msg))
end

function mm.warn(msg)
  cecho(string.format("<orange_red>[MMAPPER]<reset> %s\n", msg))
end

function mm.debug(msg)
  if not (mm.state and mm.state.debug) then return end
  cecho(string.format("<DarkSeaGreen>[MMAPPER:DEBUG]<reset> %s\n", tostring(msg)))
end

function mm.bool_arg(v, default)
  if v == nil or v == "" then return default end
  v = tostring(v):lower()
  if v == "on" or v == "true" or v == "1" then return true end
  if v == "off" or v == "false" or v == "0" then return false end
  return default
end

function mm.path_exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

function mm.dir_exists(path)
  local ok, lfs = pcall(require, "lfs")
  if ok and lfs and type(lfs.attributes) == "function" then
    return lfs.attributes(path, "mode") == "directory"
  end

  local sep = package.config:sub(1, 1)
  local probe = path
  if probe:sub(-1) ~= sep then
    probe = probe .. sep
  end
  return mm.path_exists(probe)
end

function mm.ensure_dir(path)
  if mm.dir_exists(path) then
    return true
  end

  local ok, lfs = pcall(require, "lfs")
  if ok and lfs and type(lfs.mkdir) == "function" then
    local made = lfs.mkdir(path)
    if made or mm.dir_exists(path) then
      return true
    end
  end

  local isWindows = package.config:sub(1, 1) == "\\"
  local cmd = isWindows
    and string.format('mkdir "%s"', tostring(path))
    or string.format('mkdir -p "%s"', tostring(path))

  local result = os.execute(cmd)
  if result == true or result == 0 then
    return true
  end

  return mm.dir_exists(path)
end

local function resolved_map_db_path()
  local p = tostring(mm.state.map_db or "")
  if p == "" then return nil end
  if p:sub(1, 1) == "/" or p:match("^%a:[/\\]") then
    return p
  end
  return getMudletHomeDir() .. "/" .. p
end

local function backup_dir_path()
  return getMudletHomeDir() .. "/db_backups"
end

local function gzip_file(path)
  local cmd = string.format('gzip -f "%s"', tostring(path))
  local result = os.execute(cmd)
  if result == true or result == 0 then
    return true
  end
  return false
end

function mm.print_backup_settings()
  mm.note("backups " .. (mm.state.backups_enabled and "on" or "off"))
  mm.note("backups quiet " .. (mm.state.backups_quiet and "on" or "off"))
  mm.note("backups compression " .. (mm.state.backups_compressed and "on" or "off"))
end

function mm.create_backup(force, quiet_override)
  if not force and mm.state.backups_enabled == false then
    return false, "automatic backups are currently disabled"
  end

  local source = resolved_map_db_path()
  if not source or source == "" then
    return false, "map database path is empty"
  end
  if not mm.path_exists(source) then
    return false, "map database not found: " .. tostring(source)
  end

  local dir = backup_dir_path()
  if not mm.ensure_dir(dir) then
    return false, "unable to create backup directory: " .. tostring(dir)
  end

  local stamp = os.date("!%Y%m%d_%H%M%S")
  local base = tostring(mm.state.map_db or "mapper.db"):gsub("[/\\:*?\"<>|]", "_")
  local backupPath = string.format("%s/%s.%s.bak", dir, base, stamp)
  local suffix = 1
  while mm.path_exists(backupPath) do
    backupPath = string.format("%s/%s.%s_%d.bak", dir, base, stamp, suffix)
    suffix = suffix + 1
  end

  if not (mm.exec_mapper_db and mm.sql_escape) then
    return false, "SQLite backup helpers are unavailable"
  end
  local ok, backupErr = mm.exec_mapper_db("VACUUM INTO " .. mm.sql_escape(backupPath))
  if not ok then
    return false, "transactional SQLite backup failed: " .. tostring(backupErr)
  end

  local compressed = false
  if mm.state.backups_compressed then
    if gzip_file(backupPath) then
      backupPath = backupPath .. ".gz"
      compressed = true
    else
      if not (quiet_override or mm.state.backups_quiet) then
        mm.warn("backup compression requested, but gzip is unavailable; stored uncompressed backup")
      end
    end
  end

  if not (quiet_override or mm.state.backups_quiet) then
    mm.note(string.format("Backup created: %s%s", backupPath, compressed and " (compressed)" or ""))
  end
  return true, backupPath
end


function mm.read_file_header(path, n)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read(n or 16)
  f:close()
  return data
end

function mm.looks_like_sqlite(path)
  local hdr = mm.read_file_header(path, 16)
  return hdr and hdr:find("^SQLite format 3") ~= nil
end

function mm.resolve_native_mapper_db(path)
  local p = path or mm.state.native_mapper_db
  if not p or p == "" then return nil end
  p = tostring(p)

  if p:sub(1, 1) == "/" or p:match("^%a:[/\\]") then
    return p
  end

  return getMudletHomeDir() .. "/" .. p
end

function mm.set_native_mapper_db(path)
  mm.state.native_mapper_db = path
  if mm.save_settings_persistence then mm.save_settings_persistence() end
  local resolved = mm.resolve_native_mapper_db(path)
  mm.note("Native mapper DB set to: " .. tostring(resolved))
end

function mm.load_native_mapper_db(path)
  local resolved = mm.resolve_native_mapper_db(path)
  if not resolved then
    return false, "native mapper DB path is empty"
  end

  if not mm.path_exists(resolved) then
    return false, "native mapper DB not found at " .. resolved
  end

  if mm.looks_like_sqlite(resolved) then
    return false, "configured path is SQLite live mapper DB, not a Mudlet native map export"
  end

  if type(loadMap) ~= "function" then
    return false, "Mudlet API loadMap() is unavailable"
  end

  local load_started = now_millis()
  local ok, result = pcall(loadMap, resolved)
  mm.debug(string.format(
    "native Mudlet map load timing: %.1fms (%s)",
    now_millis() - load_started,
    tostring(resolved)
  ))
  if not ok then
    return false, "loadMap() errored: " .. tostring(result)
  end

  if result == false then
    return false, "loadMap() returned false"
  end

  mm.state.native_mapper_db = path or mm.state.native_mapper_db
  if mm.save_settings_persistence then mm.save_settings_persistence() end
  mm.runtime = mm.runtime or {}
  mm.runtime.native_mapper_db_loaded_path = resolved
  mm.note("Loaded native Mudlet mapper DB: " .. resolved)
  if mm.sync_native_bigmap_to_current_room then
    mm.sync_native_bigmap_to_current_room("native_map_loaded")
  end
  return true
end

function mm.current_room()
  local function build_nomap_uid(name, zone)
    local clean_name = mm.strip_ansi(name):gsub("^%s+", ""):gsub("%s+$", "")
    local clean_zone = mm.strip_ansi(zone):gsub("^%s+", ""):gsub("%s+$", "")
    if clean_name == "" then clean_name = "?" end
    if clean_zone == "" then clean_zone = "?" end
    return "nomap_" .. clean_name .. "_" .. clean_zone
  end

  if mm and mm.get_room_info then
    local info = mm.get_room_info()
    if info and info.num then
      local n = tonumber(info.num)
      if n == -1 then
        return build_nomap_uid(info.name, info.zone or info.area)
      end
      return n
    end
  end
  if gmcp and gmcp.Room and gmcp.Room.Info and gmcp.Room.Info.num then
    local n = tonumber(gmcp.Room.Info.num)
    if n == -1 then
      return build_nomap_uid(gmcp.Room.Info.name, gmcp.Room.Info.zone or gmcp.Room.Info.area)
    end
    if n then return n end
  end
  if gmcp and gmcp.room and gmcp.room.info and gmcp.room.info.num then
    local n = tonumber(gmcp.room.info.num)
    if n == -1 then
      return build_nomap_uid(gmcp.room.info.name, gmcp.room.info.zone or gmcp.room.info.area)
    end
    return n
  end
  return nil
end

function mm.goto_room(target)
  target = tonumber(target)
  if not target then
    return false, "invalid room"
  end

  if type(expandAlias) ~= "function" then
    return false, "expandAlias is unavailable"
  end

  expandAlias("xrt " .. target)
  mm.state.last_target = target
  return true
end

function mm.walkto_room(target)
  target = tonumber(target)
  if not target then return false, "invalid room" end

  local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
  if not (nav and type(nav.walkTo) == "function") then
    return false, "walkto requires mapper navigation module"
  end

  local ok, result = pcall(nav.walkTo, tostring(target))
  if not ok then
    return false, "walkto failed: " .. tostring(result)
  end
  if result == false then
    return false, "no no-portal path found"
  end

  mm.state.last_target = target
  return true
end

function mm.lock_exit(direction, level)
  local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
  if not (nav and type(nav.setExitLock) == "function") then
    return false, "lockexit requires mapper navigation module"
  end

  local room = mm.current_room()
  if not room then
    return false, "current room unknown"
  end

  local dir = nav.normalizeDirection and nav.normalizeDirection(direction) or nil
  if not dir then
    return false, "invalid direction; use n/s/e/w/u/d"
  end

  local lockLevel = level and tonumber(level) or 999
  local ok, affected_or_err = nav.setExitLock(room, dir, lockLevel)
  if not ok then
    return false, affected_or_err
  end
  local affected = tonumber(affected_or_err) or 0
  if affected == 0 then
    return false, string.format("no '%s' exit found in room %s", dir, tostring(room))
  end

  mm.note(string.format("Locked exit %s in room %s below level %d.", dir, tostring(room), lockLevel))
  return true
end

function mm.unlock_exit(direction)
  local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
  if not (nav and type(nav.clearExitLock) == "function") then
    return false, "unlockexit requires mapper navigation module"
  end

  local room = mm.current_room()
  if not room then
    return false, "current room unknown"
  end

  local dir = nav.normalizeDirection and nav.normalizeDirection(direction) or nil
  if not dir then
    return false, "invalid direction; use n/s/e/w/u/d"
  end

  local ok, affected_or_err = nav.clearExitLock(room, dir)
  if not ok then
    return false, affected_or_err
  end
  local affected = tonumber(affected_or_err) or 0
  if affected == 0 then
    return false, string.format("no '%s' exit found in room %s", dir, tostring(room))
  end
  mm.note(string.format("Unlocked exit %s in room %s.", dir, tostring(room)))
  return true
end

function mm.list_locked_exits_here()
  local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
  if not (nav and type(nav.getRoomExitLocks) == "function") then
    return false, "lockexit requires mapper navigation module"
  end

  local room = mm.current_room()
  if not room then
    return false, "current room unknown"
  end

  local rows = nav.getRoomExitLocks(room)
  if not rows or #rows == 0 then
    mm.note("No locked exits set for room " .. tostring(room) .. ".")
    return true
  end

  local byRoom = {}
  for _, row in ipairs(rows) do
    local dir = nav.normalizeDirection and nav.normalizeDirection(row.dir) or tostring(row.dir):lower()
    local lvl = tonumber(row.level)
    if dir and lvl and lvl > 0 then
      byRoom[dir] = math.max(byRoom[dir] or 0, lvl)
    end
  end

  if next(byRoom) == nil then
    mm.note("No locked exits set for room " .. tostring(room) .. ".")
    return true
  end

  mm.note("Locked exits for room " .. tostring(room) .. ":")
  local order = {"n", "s", "e", "w", "u", "d"}
  for _, dir in ipairs(order) do
    local lvl = byRoom[dir]
    if lvl then
      if lvl >= 999 then
        mm.note("  " .. dir .. " => all levels (db level " .. tostring(lvl) .. ")")
      else
        mm.note("  " .. dir .. " => below level " .. tostring(lvl))
      end
    end
  end
  return true
end

function mm.resume()
  if not mm.state.last_target then
    return false, "no previous mapper target"
  end
  return mm.goto_room(mm.state.last_target)
end

function mm.print_room_details(room)
  room = tonumber(room) or mm.current_room()
  if not room then
    mm.warn("No room information available yet.")
    return
  end
  if type(room) ~= "number" then
    mm.warn("Room details are not available in unmapped rooms.")
    return
  end
  mm.note("Room: " .. room)
  local info = mm.get_room_info and mm.get_room_info()
  if info then
    mm.note("Name: " .. tostring(info.name or "?"))
    mm.note("Area: " .. tostring(info.zone or info.area or "?"))
    mm.note("Terrain: " .. tostring(info.terrain or "?"))
  end

  local rows = mm.query_mapper_db(string.format("SELECT noportal, norecall, info FROM rooms WHERE uid = %d LIMIT 1", room), "Aardwolf.db") or {}
  if rows[1] then
    local noportal = tonumber(rows[1].noportal) == 1 and "yes" or "no"
    local norecall = tonumber(rows[1].norecall) == 1 and "yes" or "no"
    local isSafe = snd and snd.mapper and snd.mapper.infoContainsSafe and snd.mapper.infoContainsSafe(rows[1].info)
    mm.note(string.format("Flags: noportal=%s, norecall=%s, %s", noportal, norecall, isSafe and "safe" or "not-safe"))
    if rows[1].info and tostring(rows[1].info) ~= "" then
      mm.note("Info: " .. tostring(rows[1].info))
    end
  end
end

function mm.set_room_flag(flag, arg)
  local safe_flag
  if flag == "noportal" or flag == "norecall" then
    safe_flag = flag
  else
    return false, "invalid room flag"
  end

  local room = mm.current_room()
  if not room then
    return false, "current room unknown"
  end
  if type(room) ~= "number" then
    return false, "room flags are not available in unmapped rooms"
  end

  local mode = tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if mode == "" then
    mode = "toggle"
  end
  if mode ~= "on" and mode ~= "off" and mode ~= "toggle" then
    return false, string.format("Usage: mapper %s [on|off|toggle]", safe_flag)
  end

  local rows, read_err = mm.query_mapper_db(
    string.format("SELECT name, %s FROM rooms WHERE uid = %d LIMIT 1", safe_flag, room),
    "Aardwolf.db"
  )
  if not rows then
    return false, read_err
  end
  if not rows[1] then
    return false, string.format("room %s not found in mapper database", tostring(room))
  end

  local current = tonumber(rows[1][safe_flag]) == 1
  local next_value
  if mode == "on" then
    next_value = true
  elseif mode == "off" then
    next_value = false
  else
    next_value = not current
  end

  local ok, write_err = mm.exec_mapper_db(
    string.format("UPDATE rooms SET %s = %d WHERE uid = %d", safe_flag, next_value and 1 or 0, room),
    "Aardwolf.db"
  )
  if not ok then
    return false, write_err
  end

  local room_name = tostring(rows[1].name or "?")
  mm.note(string.format("Room %s (id: %s) %s set to %s.", room_name, tostring(room), safe_flag, next_value and "on" or "off"))
  return true
end

local NOTES_DB_NAME = "Aardwolf.db"

function mm.add_note(note_text)
  local room = mm.current_room()
  if not room then
    return false, "current room unknown"
  end
  if type(room) ~= "number" then
    return false, "notes are not available in unmapped rooms"
  end

  local note = tostring(note_text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if note == "" then
    return false, "note text cannot be empty"
  end

  local clear_ok, clear_err = mm.exec_mapper_db(string.format("DELETE FROM bookmarks WHERE uid=%d", room), NOTES_DB_NAME)
  if not clear_ok then
    return false, clear_err
  end

  local sql = string.format("INSERT INTO bookmarks (uid, notes) VALUES (%d, %s)", room, mm.sql_escape(note))
  local ok, err = mm.exec_mapper_db(sql, NOTES_DB_NAME)
  if not ok then
    return false, err
  end

  mm.note(string.format("Room note saved for %d.", room))
  return true
end

function mm.delete_note()
  local room = mm.current_room()
  if not room then
    return false, "current room unknown"
  end
  if type(room) ~= "number" then
    return false, "notes are not available in unmapped rooms"
  end

  local ok, err = mm.exec_mapper_db(string.format("DELETE FROM bookmarks WHERE uid=%d", room), NOTES_DB_NAME)
  if not ok then
    return false, err
  end

  mm.note(string.format("Room note deleted for %d.", room))
  return true
end

function mm.get_room_note(room_id)
  local rid = tonumber(room_id)
  if not rid then
    return nil
  end

  local sql = string.format("SELECT notes FROM bookmarks WHERE uid = %d LIMIT 1", rid)
  local rows, err = mm.query_mapper_db(sql, NOTES_DB_NAME)
  if not rows then
    return nil, err
  end
  if not rows[1] then
    return ""
  end
  return tostring(rows[1].notes or "")
end

local function require_luasql()
  local ok, mod = pcall(require, "luasql.sqlite3")
  if not ok then return nil, "LuaSQL sqlite3 module not available" end
  return mod
end

local function open_mapper_db(path)
  local luasql, mod_err = require_luasql()
  if not luasql then return nil, nil, mod_err end
  local env = luasql.sqlite3()
  if not env then return nil, nil, "failed to create sqlite environment" end
  local conn, conn_err = env:connect(path)
  if not conn then
    env:close()
    return nil, nil, "failed to connect to mapper db: " .. tostring(conn_err)
  end
  return env, conn
end

function mm.sql_escape(value)
  local s = tostring(value or "")
  return "'" .. s:gsub("'", "''") .. "'"
end

function mm.strip_ansi(text)
  local cleaned = tostring(text or "")
  cleaned = cleaned:gsub("\27%[[0-9;]*m", "")
  cleaned = cleaned:gsub("[%z\1-\8\11\12\14-\31]", "")
  return cleaned
end

function mm.query_mapper_db(sql, db_path)
  local source = mm.resolve_native_mapper_db(db_path or mm.state.map_db)
  if not source or not mm.path_exists(source) then
    return nil, "mapper db not found: " .. tostring(source)
  end

  local env, conn, open_err = open_mapper_db(source)
  if not conn then return nil, open_err end

  local cursor, qerr = conn:execute(sql)
  if not cursor then
    conn:close(); env:close()
    return nil, tostring(qerr)
  end

  local rows = {}
  local row = cursor:fetch({}, "a")
  while row do
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    table.insert(rows, copy)
    row = cursor:fetch(row, "a")
  end

  cursor:close()
  conn:close()
  env:close()
  return rows
end


function mm.exec_mapper_db(sql, db_path)
  local source = mm.resolve_native_mapper_db(db_path or mm.state.map_db)
  if not source or not mm.path_exists(source) then
    return false, "mapper db not found: " .. tostring(source)
  end

  local env, conn, open_err = open_mapper_db(source)
  if not conn then return false, open_err end

  local ok, err = conn:execute(sql)
  conn:close()
  env:close()
  if not ok then return false, tostring(err) end
  return true
end

function mm.ensure_exits_chaos_column()
  local rows, err = mm.query_mapper_db("PRAGMA table_info('exits')")
  if not rows then
    return false, err
  end

  local has_chaos = false
  for _, row in ipairs(rows) do
    if tostring(row.name or "") == "chaos" then
      has_chaos = true
      break
    end
  end

  if not has_chaos then
    local ok, alter_err = mm.exec_mapper_db("ALTER TABLE exits ADD COLUMN chaos TEXT NOT NULL DEFAULT 'no'")
    if not ok then
      return false, alter_err
    end
  end

  local ok, upd_err = mm.exec_mapper_db("UPDATE exits SET chaos='no' WHERE chaos IS NULL OR trim(chaos) = ''")
  if not ok then
    return false, upd_err
  end
  return true
end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_uid(value)
  if value == nil then return nil end
  local n = tonumber(value)
  if n then return tostring(math.floor(n)) end
  local s = trim(value)
  if s == "" then return nil end
  return s
end

local function parse_portal_command(dir)
  local raw = trim(dir)
  local full, portal_id = raw:match("^(dinv portal use%s+([%w%-_]+).*)$")
  if not full then return nil, nil end
  return full, portal_id
end

local function make_custom_portal_id(command, touid, fromuid)
  local normalized_command = trim(command):lower():gsub("%s+", " ")
  local normalized_touid = normalize_uid(touid) or "?"
  local normalized_fromuid = trim(fromuid):lower()
  return string.format("custom:%s|%s|%s", normalized_fromuid, normalized_touid, normalized_command)
end

local function get_portal_persistence_roots()
  local roots, seen = {}, {}
  local function maybe_add(root)
    if type(root) == "table" and not seen[root] then
      seen[root] = true
      table.insert(roots, root)
    end
  end

  local function maybe_add_inv_items()
    if type(_G.inv) == "table"
      and type(_G.inv.items) == "table"
      and type(_G.inv.items.table) == "table"
    then
      maybe_add(_G.inv.items.table)
      return true
    end
    return false
  end

  maybe_add_inv_items()

  maybe_add(mm.state.portal_persistence)
  maybe_add(_G.mapper_persistence)
  maybe_add(_G.persistence)
  return roots
end

local function read_leadsto_from_node(node)
  if type(node) ~= "table" then return nil end
  if node.leadsto ~= nil then return normalize_uid(node.leadsto) end
  if type(node.data) == "table" and node.data.leadsto ~= nil then
    return normalize_uid(node.data.leadsto)
  end
  return nil
end

local function lookup_portal_leadsto(portal_id)
  local roots = get_portal_persistence_roots()
  if #roots == 0 then return nil end

  for _, root in ipairs(roots) do
    local direct = read_leadsto_from_node(root[portal_id])
    if direct then return direct end
    direct = read_leadsto_from_node(root[tostring(portal_id)])
    if direct then return direct end

    if type(root.portals) == "table" then
      direct = read_leadsto_from_node(root.portals[portal_id])
      if direct then return direct end
      direct = read_leadsto_from_node(root.portals[tostring(portal_id)])
      if direct then return direct end
    end

    for _, node in pairs(root) do
      if type(node) == "table" and tostring(node.id or node.portal_id or "") == tostring(portal_id) then
        local inferred = read_leadsto_from_node(node)
        if inferred then return inferred end
      end
    end
  end
  return nil
end

local function collect_portal_ids_from_persistence()
  local roots = get_portal_persistence_roots()
  if #roots == 0 then return {} end

  local ids, seen_nodes = {}, {}
  local function maybe_add(id)
    local normalized = normalize_uid(id)
    if normalized then ids[normalized] = true end
  end

  local function node_type(node)
    if type(node) ~= "table" then return "" end
    local t = node.type
    if t == nil and type(node.stats) == "table" then t = node.stats.type end
    if t == nil and type(node.data) == "table" then t = node.data.type end
    return tostring(t or ""):lower()
  end

  local function node_id(node, fallback_key)
    if type(node) ~= "table" then return nil end
    return node.id
      or (type(node.stats) == "table" and node.stats.id)
      or node.portal_id
      or (type(node.data) == "table" and (node.data.id or node.data.portal_id))
      or fallback_key
  end

  local function walk(node)
    if type(node) ~= "table" then return end
    if seen_nodes[node] then return end
    seen_nodes[node] = true

    for k, v in pairs(node) do
      if type(v) == "table" then
        local type_name = node_type(v)
        if type_name == "portal" then
          maybe_add(node_id(v, k))
        end
        walk(v)
      end
    end
  end

  for _, root in ipairs(roots) do
    walk(root)
  end
  return ids
end

function mm.rebuild_portals_from_db()
  ensure_portal_settings()
  local chaos_ok, chaos_err = mm.ensure_exits_chaos_column()
  if not chaos_ok then
    return false, "failed ensuring exits.chaos column: " .. tostring(chaos_err)
  end
  local rows, err = mm.query_mapper_db([[
    SELECT dir, level, touid, fromuid, ifnull(chaos, 'no') AS chaos
    FROM exits
    WHERE LOWER(dir) LIKE 'dinv portal use %'
      OR fromuid IN ('*', '**')
    ORDER BY touid, dir
  ]])
  if not rows then
    return false, "failed reading exits: " .. tostring(err)
  end

  local rebuilt = {}
  local room_ids = {}
  local seen_room = {}

  for _, row in ipairs(rows) do
    local command, portal_id = parse_portal_command(row.dir)
    local fromuid = trim(row.fromuid)
    local is_inventory_portal = (command ~= nil and portal_id ~= nil)

    if not command then
      command = trim(row.dir)
      if command == "" then command = nil end
    end

    if not portal_id and command and command ~= "" then
      portal_id = make_custom_portal_id(command, row.touid, fromuid)
    end

    if command and portal_id then
      local touid = normalize_uid(row.touid)
      local leadsto = lookup_portal_leadsto(portal_id)
      local target_uid = normalize_uid(leadsto) or touid
      if target_uid and not seen_room[target_uid] then
        seen_room[target_uid] = true
        table.insert(room_ids, mm.sql_escape(target_uid))
      end
      table.insert(rebuilt, {
        nr = #rebuilt + 1,
        portal_id = tostring(portal_id),
        command = command,
        level = tonumber(row.level) or 0,
        chaos = (tostring(row.chaos or "no") == "yes") and "yes" or "no",
        touid = touid,
        fromuid = fromuid,
        leadsto = leadsto,
        target_uid = target_uid,
        area = "?",
        room_name = "?",
        fixed_recall = (fromuid == "**"),
        persistence_track = is_inventory_portal,
      })
    end
  end

  if #room_ids > 0 then
    local room_rows, room_err = mm.query_mapper_db(
      string.format(
        "SELECT uid, name, area FROM rooms WHERE uid IN (%s)",
        table.concat(room_ids, ",")
      )
    )
    if not room_rows then
      return false, "failed reading rooms: " .. tostring(room_err)
    end

    local room_map = {}
    for _, room in ipairs(room_rows) do
      room_map[normalize_uid(room.uid)] = room
    end

    for _, entry in ipairs(rebuilt) do
      local room = room_map[entry.target_uid]
      if room then
        entry.area = trim(room.area) ~= "" and tostring(room.area) or "?"
        entry.room_name = trim(room.name) ~= "" and tostring(room.name) or "?"
      end
    end
  end

  table.sort(rebuilt, function(a, b)
    local al, bl = tonumber(a.level) or 0, tonumber(b.level) or 0
    if al ~= bl then return al < bl end
    local ac, bc = tostring(a.command or ""), tostring(b.command or "")
    if ac ~= bc then return ac < bc end
    return tostring(a.portal_id or "") < tostring(b.portal_id or "")
  end)

  for i, entry in ipairs(rebuilt) do
    entry.nr = i
  end

  mm.portals.rebuilt = rebuilt
  mm.portals.rebuilt_at = os.time()
  local valid_ids = {}
  for _, entry in ipairs(rebuilt) do
    valid_ids[tostring(entry.portal_id)] = true
  end
  for id, _ in pairs(mm.portals.settings.recall_ids or {}) do
    if not valid_ids[tostring(id)] then
      mm.portals.settings.recall_ids[id] = nil
    end
  end
  if mm.portals.settings.bounce_portal_id and not valid_ids[tostring(mm.portals.settings.bounce_portal_id)] then
    mm.portals.settings.bounce_portal_id = nil
  end
  if mm.portals.settings.bounce_recall_id and not valid_ids[tostring(mm.portals.settings.bounce_recall_id)] then
    mm.portals.settings.bounce_recall_id = nil
  end
  if mm.portals.settings.bounce_portal_id then
    local bp = find_portal_by_id(mm.portals.settings.bounce_portal_id)
    if bp and mm.is_portal_chaos(bp) then
      mm.portals.settings.bounce_portal_id = nil
    end
  end
  if mm.portals.settings.bounce_recall_id then
    local br = find_portal_by_id(mm.portals.settings.bounce_recall_id)
    if br and mm.is_portal_chaos(br) then
      mm.portals.settings.bounce_recall_id = nil
    end
  end

  if snd and snd.config and snd.config.mapper then
    local mapperCfg = snd.config.mapper
    local function detect_by_command(command, must_recall)
      local normalized = trim(command):lower()
      if normalized == "" then return nil end
      for _, portal in ipairs(rebuilt) do
        local is_recall = mm.is_portal_recall(portal)
        if trim(portal.command):lower() == normalized and (must_recall == nil or must_recall == is_recall) then
          return tostring(portal.portal_id)
        end
      end
      return nil
    end
    if not mm.portals.settings.bounce_portal_id and mapperCfg.bouncePortalCommand then
      mm.portals.settings.bounce_portal_id = detect_by_command(mapperCfg.bouncePortalCommand, false)
    end
    if not mm.portals.settings.bounce_recall_id and mapperCfg.bounceRecallCommand then
      mm.portals.settings.bounce_recall_id = detect_by_command(mapperCfg.bounceRecallCommand, true)
    end
  end

  local persisted, persist_err = mm.save_portal_persistence()
  if not persisted then
    mm.warn("Rebuilt portals are available for this session, but failed to save persistence: " .. tostring(persist_err))
  end
  mm.apply_bounce_settings_to_snd()

  local rebuilt_ids = {}
  local rebuilt_by_id = {}
  for _, entry in ipairs(rebuilt) do
    local id = tostring(entry.portal_id)
    rebuilt_ids[id] = true
    if not rebuilt_by_id[id] then
      rebuilt_by_id[id] = entry
    end
  end

  local persistence_ids = collect_portal_ids_from_persistence()
  local missing_in_rebuilt = {}
  local missing_in_persistence = {}
  for id, _ in pairs(persistence_ids) do
    if not rebuilt_ids[tostring(id)] then
      table.insert(missing_in_rebuilt, tostring(id))
    end
  end

  for id, _ in pairs(rebuilt_ids) do
    local entry = rebuilt_by_id[id]
    if entry and entry.persistence_track and not persistence_ids[tostring(id)] then
      table.insert(missing_in_persistence, tostring(id))
    end
  end

  local function sort_ids(ids)
    table.sort(ids, function(a, b)
      local na, nb = tonumber(a), tonumber(b)
      if na and nb then return na < nb end
      if na and not nb then return true end
      if nb and not na then return false end
      return a < b
    end)
  end

  sort_ids(missing_in_rebuilt)
  sort_ids(missing_in_persistence)

  local function print_id_mismatch_table(title, rows)
    if not rows or #rows == 0 then return end
    mm.warn(title)
    cecho("<gray>--------------------------------------------------------------------------------------------------<reset>\n")
    cecho(string.format(
      "<deep_sky_blue>%-42s <medium_purple>%-14s <cornflower_blue>%-14s<reset>\n",
      "command",
      "idDB",
      "idPersistence"
    ))
    cecho("<gray>--------------------------------------------------------------------------------------------------<reset>\n")
    for _, row in ipairs(rows) do
      cecho(string.format(
        "<white>%-42s <khaki>%-14s <light_slate_blue>%-14s<reset>\n",
        tostring(row.command or "-"),
        tostring(row.id_db or "-"),
        tostring(row.id_persistence or "-")
      ))
    end
  end

  mm.note(string.format("Rebuilt %d portal entries from exits.", #rebuilt))

  if #missing_in_rebuilt > 0 then
    local rows = {}
    for _, id in ipairs(missing_in_rebuilt) do
      table.insert(rows, {
        command = "-",
        id_db = "-",
        id_persistence = id,
      })
    end
    print_id_mismatch_table(
      string.format("ID(s) found in persistence but not in the database rebuilt list (%d):", #missing_in_rebuilt),
      rows
    )
  end

  if #missing_in_persistence > 0 then
    local rows = {}
    for _, id in ipairs(missing_in_persistence) do
      local entry = rebuilt_by_id[id] or {}
      local command = trim(entry.command)
      if command == "" then
        command = string.format("dinv portal use %s", tostring(id))
      end
      table.insert(rows, {
        command = command,
        id_db = id,
        id_persistence = "-",
      })
    end
    print_id_mismatch_table(
      string.format("command(s) found in the database but ID not found in persistence (%d):", #missing_in_persistence),
      rows
    )
  end

  if #missing_in_rebuilt == 0 and #missing_in_persistence == 0 then
    if next(persistence_ids) == nil then
      mm.note("No portal IDs were found in persistence, and no mismatches were detected.")
    else
      mm.note("All persistence Portal IDs were found in rebuilt portal list.")
    end
  end
  return true, rebuilt
end

function mm.print_portals(area_arg)
  local portals = mm.portals and mm.portals.rebuilt or {}
  if not portals or #portals == 0 then
    mm.warn("No rebuilt portals are loaded. Run: mapper rebuildportals")
    return false
  end

  local selected = portals
  local raw_filter = tostring(area_arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if raw_filter ~= "" then
    local filter = raw_filter:lower()
    if filter == "here" then
      local info = mm.get_room_info and mm.get_room_info() or {}
      filter = tostring(info.zone or info.area or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
      if filter == "" then
        mm.warn("current area is unknown; try LOOK first")
        return false
      end
    end

    selected = {}
    for _, p in ipairs(portals) do
      local hay = tostring(p.area or ""):lower()
      if hay:find(filter, 1, true) then
        table.insert(selected, p)
      end
    end

    if #selected == 0 then
      mm.warn("No rebuilt portals matched area filter: " .. tostring(raw_filter))
      return false
    end
  end

  ensure_portal_settings()
  cecho("\n<deep_sky_blue>Nr  <medium_purple>Type     <medium_purple>Area                      <cornflower_blue>Room name                                  <medium_purple>Portal command                    <deep_sky_blue>Level<reset>\n")
  cecho("<gray>--------------------------------------------------------------------------------------------------------------------<reset>\n")

  local function fit(value, width)
    local text = tostring(value or "")
    if #text <= width then
      return text .. string.rep(" ", width - #text)
    end
    return text:sub(1, width - 3) .. "..."
  end

  for _, p in ipairs(selected) do
    local is_recall = mm.is_portal_recall(p)
    local is_chaos = mm.is_portal_chaos(p)
    local type_color = is_chaos and "medium_purple" or (is_recall and "light_sky_blue" or "yellow")
    local command_color = is_chaos and "medium_purple" or (is_recall and "light_sky_blue" or "light_slate_blue")
    cecho(string.format(
      "<deep_sky_blue>%-3s <%s>%-8s <light_grey>%-25s <white>%-42s <%s>%-33s <khaki>%5d<reset>",
      tostring(p.nr or "?"),
      type_color,
      is_chaos and "Chaos" or (is_recall and "Recall" or "Portal"),
      fit(p.area or "?", 25),
      fit(p.room_name or "?", 42),
      command_color,
      fit(p.command or "?", 33),
      tonumber(p.level) or 0
    ))
    if mm.portals.settings.bounce_portal_id == tostring(p.portal_id) then
      cecho(" <magenta>[BouncePortal]<reset>")
    end
    if mm.portals.settings.bounce_recall_id == tostring(p.portal_id) then
      cecho(" <magenta>[BounceRecall]<reset>")
    end
    cecho("\n")
  end
  return true
end

local function current_area_name()
  local info = mm.get_room_info and mm.get_room_info() or {}
  return tostring(info.zone or info.area or "")
end

local function resolve_area_filter(which)
  local arg = tostring(which or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "" then return nil end
  if arg == "here" or arg == "area" then
    local area = current_area_name()
    if area == "" then return nil, "current area is unknown; try LOOK first" end
    return area
  end
  return "%" .. arg .. "%"
end

local function set_search_results(results)
  mm.search_state.results = results or {}
  mm.search_state.index = (#mm.search_state.results > 0) and 1 or 0
end

local function format_result(entry, i)
  local rid = tonumber(entry.uid) or tonumber(entry.rmid) or -1
  local name = mm.strip_ansi(entry.name or "?")
  local area = mm.strip_ansi(entry.area or entry.arid or "?")
  local note = mm.strip_ansi(entry.reason or entry.info or "")
  local prefix = string.format("%3d) (%s) %s [%s]", i, (rid > 0 and tostring(rid) or "?"), name, area)
  return (note ~= "" and (prefix .. " - " .. note) or prefix), rid
end

function mm.print_search_results(results, title)
  results = results or {}
  set_search_results(results)
  if title then mm.note(title) end
  if #results == 0 then
    mm.note("No matching rooms found.")
    return true
  end

  cecho("\n<gray>Idx  Room     Name                                       Area                      Notes<reset>\n")
  cecho("<gray>----------------------------------------------------------------------------------------------------<reset>\n")

  local function trim_to(v, n)
    local t = mm.strip_ansi(v or "")
    if #t <= n then return t .. string.rep(" ", n - #t) end
    return t:sub(1, n - 1) .. "..."
  end

  for i, entry in ipairs(results) do
    local rid = tonumber(entry.uid) or tonumber(entry.rmid) or -1
    local name = trim_to(entry.name or "?", 42)
    local area = trim_to(entry.area or entry.arid or "?", 24)
    local notes = trim_to(entry.reason or entry.info or "", 24)
    local rowColor = (i % 2 == 0) and "light_grey" or "dark_slate_grey"

    local idx_display = string.format("%3d", i)
    local note_summary = notes

    if rid > 0 then
      echoLink(idx_display, string.format([[mm.show_note_for_room(%d)]], rid), "Show full room note", true)
      echo(" ")
    else
      cecho(string.format("<%s>%3d<reset> ", rowColor, i))
    end

    if rid > 0 then
      local ridtxt = string.format("(%d)", rid)
      echoLink(string.format("%-8s", ridtxt), [[mm.goto_room(]] .. rid .. [[)]], "Go to room " .. rid, true)
      echo(" ")
      echoLink(name, [[mm.goto_room(]] .. rid .. [[)]], "Go to room " .. rid, true)
      cecho("  <" .. rowColor .. ">" .. area .. "  <reset>")
      echoLink(note_summary, string.format([[mm.show_note_for_room(%d)]], rid), "Show full room note", true)
      echo("  ")
      echoLink("{sw}", [[mm.goto_room(]] .. rid .. [[)]], "Speedwalk to room " .. rid, true)
      echo("\n")
    else
      cecho(string.format("%-8s %s  <%s>%s  %s<reset>\n", "(?)", name, rowColor, area, notes))
    end

    if i >= 100 then
      mm.warn("More than 100 results found; showing first 100.")
      break
    end
  end

  cecho("<gray>----------------------------------------------------------------------------------------------------<reset>\n")
  mm.note("Use: mapper next [index] to travel through this list.")
  return true
end

function mm.show_note_for_room(room_id)
  local rid = tonumber(room_id)
  if not rid then return false, "invalid room id" end
  if type(mm.get_room_note) ~= "function" then
    return false, "note lookup is unavailable"
  end
  local note, err = mm.get_room_note(rid)
  if note == nil and err then
    return false, err
  end
  note = tostring(note or "")
  if note == "" then
    mm.note(string.format("Room %d has no saved note.", rid))
    return true
  end
  mm.note(string.format("Room %d note: %s", rid, note))
  return true
end

function mm.search_text(scope, raw_text)
  local text = tostring(raw_text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return false, "search text is required" end
  if text:sub(1, 1) == '"' and text:sub(-1) == '"' and #text >= 2 then text = text:sub(2, -2) end
  local like = mm.sql_escape("%" .. text .. "%")

  local sql
  if scope == "area" then
    local area = current_area_name()
    if area == "" then return false, "current area is unknown; try LOOK first" end
    sql = string.format("SELECT uid, name, area FROM rooms WHERE trim(name) LIKE %s AND area = %s ORDER BY name LIMIT 101", like, mm.sql_escape(area))
  elseif scope == "list" then
    sql = string.format("SELECT rooms.uid AS uid, rooms_lookup.name AS name, rooms.area AS area FROM rooms_lookup JOIN rooms ON rooms_lookup.uid = rooms.uid WHERE rooms_lookup.name LIKE %s ORDER BY rooms.area, rooms_lookup.name LIMIT 101", like)
  else
    sql = string.format("SELECT rooms_lookup.uid AS uid, rooms_lookup.name AS name, rooms.area AS area FROM rooms_lookup JOIN rooms ON rooms_lookup.uid = rooms.uid WHERE rooms_lookup.name LIKE %s ORDER BY rooms.area, rooms_lookup.name LIMIT 101", like)
  end

  local rows, err = mm.query_mapper_db(sql)
  if not rows then return false, err end
  mm.print_search_results(rows, string.format("%s search for: %s", scope, text))
  return true
end

function mm.search_special(which, area_arg)
  local tags = {
    shops = {"shop", "bank"},
    train = {"trainer"},
    quest = {"questor"},
  }
  local wanted = tags[which]
  if not wanted then return false, "unknown special search type" end

  local where = "rooms.info IS NOT NULL AND rooms.info != ''"
  local area_like, area_err = resolve_area_filter(area_arg)
  if area_arg and tostring(area_arg):gsub("%s+", "") ~= "" then
    if not area_like then return false, area_err end
    where = where .. " AND lower(rooms.area) LIKE " .. mm.sql_escape(area_like:lower())
  end

  local rows, err = mm.query_mapper_db("SELECT uid, name, area, info FROM rooms WHERE " .. where .. " ORDER BY area, name")
  if not rows then return false, err end

  local lookup = {}
  for _, tag in ipairs(wanted) do lookup[tag] = true end
  local results = {}
  for _, row in ipairs(rows) do
    local info = tostring(row.info or "")
    local reasons = {}
    for item in info:gmatch("[^,]+") do
      local clean = item:gsub("^%s+", ""):gsub("%s+$", ""):lower()
      if lookup[clean] then table.insert(reasons, clean) end
    end
    if #reasons > 0 then
      row.reason = table.concat(reasons, ",")
      table.insert(results, row)
    end
  end

  mm.print_search_results(results, "special search: " .. which)
  return true
end

function mm.show_unmapped(raw_arg)
  local arg = tostring(raw_arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  mm.debug("show_unmapped invoked with arg: '" .. arg .. "'")
  if arg == "" then
    local rows, err = mm.query_mapper_db([[
      SELECT area, count(dir) as cnt
      FROM rooms INNER JOIN exits ON rooms.uid = fromuid
      WHERE touid NOT IN (SELECT uid FROM rooms) AND touid != -1
      GROUP BY area
      ORDER BY area
    ]])
    if not rows then return false, err end
    mm.debug("show_unmapped summary rows: " .. tostring(#rows))
    if #rows == 0 then
      mm.note("No unmapped exits found.")
      return true
    end

    cecho("<cyan>Unmapped exits by area<reset>\n")
    cecho("<gray>--------------------------------------------------------------------<reset>\n")
    cecho(string.format("<white>| %-50s | %5s |<reset>\n", "area", "count"))
    cecho("<gray>--------------------------------------------------------------------<reset>\n")
    for _, row in ipairs(rows) do
      cecho(string.format("| %-50s | %5d |\n", tostring(row.area or "?"), tonumber(row.cnt) or 0))
    end
    cecho("<gray>--------------------------------------------------------------------<reset>\n")
    return true
  end

  local area = arg
  local where_area_sql
  if arg:lower() == "here" then
    local info = mm.get_room_info and mm.get_room_info() or nil
    if not info then
      return false, "current room is unknown; try LOOK first"
    end
    local current_area = info and (info.zone or info.area) or nil
    if not current_area or tostring(current_area):gsub("%s+", "") == "" then
      return false, "current area is unknown; try LOOK first"
    end
    area = tostring(current_area)
    where_area_sql = "lower(area) = " .. mm.sql_escape(area:lower())
  else
    where_area_sql = "lower(area) LIKE " .. mm.sql_escape("%" .. area:lower() .. "%")
  end

  local rows, err = mm.query_mapper_db(string.format([[
    SELECT uid, name, area, dir, touid
    FROM rooms INNER JOIN exits ON rooms.uid = fromuid
    WHERE %s
      AND touid NOT IN (SELECT uid FROM rooms)
      AND touid != -1
    ORDER BY area, uid
  ]], where_area_sql))
  if not rows then return false, err end
  mm.debug("show_unmapped detail rows: " .. tostring(#rows) .. " (area filter: " .. tostring(area) .. ")")
  if #rows == 0 then
    mm.note("No unmapped exits found for area filter: " .. tostring(area))
    return true
  end

  cecho("<cyan>Rooms with unmapped exits<reset>\n")
  cecho("<gray>-------------------------------------------------------------------------------------------------------------------<reset>\n")
  cecho(string.format("<white>| %-24s | %-28s | %-8s | %-5s | %-8s |<reset>\n", "area", "room name", "rm uid", "dir", "to uid"))
  cecho("<gray>-------------------------------------------------------------------------------------------------------------------<reset>\n")
  for _, row in ipairs(rows) do
    local uid = tonumber(row.uid)
    cecho(string.format("| %-24s | ", tostring(row.area or "?")))
    cechoLink(
      string.format("%-28s", tostring(row.name or "?")),
      uid and string.format("mm.goto_room(%d)", uid) or "",
      "Go to room " .. tostring(row.uid or ""),
      uid ~= nil
    )
    cecho(string.format(" | %-8s | %-5s | %-8s |\n", tostring(row.uid or "?"), tostring(row.dir or "?"), tostring(row.touid or "?")))
  end
  cecho("<gray>-------------------------------------------------------------------------------------------------------------------<reset>\n")
  return true
end

function mm.search_notes(area_arg)
  local sql = "SELECT bookmarks.uid as uid, rooms.name as name, rooms.area as area, bookmarks.notes as reason FROM bookmarks JOIN rooms ON bookmarks.uid = rooms.uid"
  local area_like, area_err = resolve_area_filter(area_arg)
  local arg = tostring(area_arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "room" or arg == "thisroom" then
    local room = mm.current_room()
    if not room then return false, "current room is unknown; try LOOK first" end
    sql = sql .. " WHERE rooms.uid = " .. mm.sql_escape(room)
  elseif arg ~= "" then
    if not area_like then return false, area_err end
    sql = sql .. " WHERE lower(rooms.area) LIKE " .. mm.sql_escape(area_like:lower())
  end
  sql = sql .. " ORDER BY rooms.area, rooms.name"

  local rows, err = mm.query_mapper_db(sql, NOTES_DB_NAME)
  if not rows then return false, err end
  mm.print_search_results(rows, "notes search")
  return true
end

function mm.search_notes_text(raw_text)
  local text = tostring(raw_text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return false, "Usage: mapper searchnotes <text>" end

  local sql = string.format(
    "SELECT bookmarks.uid as uid, rooms.name as name, rooms.area as area, bookmarks.notes as reason FROM bookmarks JOIN rooms ON bookmarks.uid = rooms.uid WHERE lower(bookmarks.notes) LIKE %s ORDER BY rooms.area, rooms.name",
    mm.sql_escape("%" .. text:lower() .. "%")
  )

  local rows, err = mm.query_mapper_db(sql, NOTES_DB_NAME)
  if not rows then return false, err end
  set_search_results(rows)

  mm.note(string.format("notes text search: '%s' (%d found)", text, #rows))
  if #rows == 0 then
    mm.note("No matching rooms found.")
    return true
  end

  for i, entry in ipairs(rows) do
    local rid = tonumber(entry.uid) or -1
    local name = mm.strip_ansi(entry.name or "?")
    local area = mm.strip_ansi(entry.area or "?")
    local note = mm.strip_ansi(entry.reason or "")
    cecho(string.format("<light_grey>%3d)<reset> ", i))
    if rid > 0 then
      echoLink(string.format("(%d)", rid), [[mm.goto_room(]] .. rid .. [[)]], "Go to room " .. rid, true)
      echo(" ")
    else
      echo("(?) ")
    end
    cecho(string.format("<cyan>%s<reset> [<dark_orange>%s<reset>]\n", name, area))
    if rid > 0 then
      echoLink(note, string.format([[mm.show_note_for_room(%d)]], rid), "Show full room note", true)
      echo("\n")
    else
      cecho(note .. "\n")
    end
    if i >= 100 then
      mm.warn("More than 100 results found; showing first 100.")
      break
    end
  end
  return true
end

function mm.where_room(dest)
  dest = tonumber(dest)
  if not dest then return false, "mapper where expects a room id" end
  local src = mm.current_room()
  if not src then return false, "current room unknown; try LOOK first" end
  if src == dest then return false, "you are already in that room" end
  local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
  if not (nav and type(nav.findPath) == "function") then
    return false, "mapper where requires mapper navigation module"
  end
  -- mapper where only displays a route; keep level, portal, and area guards
  -- scoped to commands that actually move the character. Mirror xrt's
  -- outward-jump planner first, since plain findPath can miss routes when the
  -- current room blocks both portal and recall.
  local path, depth
  if type(nav.buildOutwardJumpRoute) == "function" then
    path = nav.buildOutwardJumpRoute(tostring(src), tostring(dest), true)
    if path and #path > 0 then
      depth = #path
    else
      path = nil
    end
  end
  if not path then
    path, depth = nav.findPath(src, dest, nil, nil, true, true)
  end
  if not path then return false, string.format("path from %s to %s not found", tostring(src), tostring(dest)) end

  local room_rows = mm.query_mapper_db(string.format(
    "SELECT name, area, info FROM rooms WHERE uid = %d LIMIT 1",
    dest
  ))
  local room = room_rows and room_rows[1] or nil
  if room then
    local name = mm.strip_ansi(room.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local area = mm.strip_ansi(room.area or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local info = tostring(room.info or ""):lower()
    local color = nil
    local marker = nil
    if info:find("pk", 1, true) then
      color = "red"
      marker = "PK"
    elseif info:find("safe", 1, true) then
      color = "green"
      marker = "safe"
    end

    local room_label = name ~= "" and name or tostring(dest)
    if marker then
      room_label = string.format("%s (%s)", room_label, marker)
    end
    if color then
      room_label = string.format("<%s>%s<reset>", color, room_label)
    end
    if area ~= "" then
      cecho(string.format("<CornflowerBlue>[MMAPPER]<reset> %s / %s\n", room_label, area))
    else
      cecho(string.format("<CornflowerBlue>[MMAPPER]<reset> %s\n", room_label))
    end
  end

  local steps = {}
  for _, p in ipairs(path) do table.insert(steps, tostring(p.dir or "")) end
  mm.note(string.format("Path to %d: %s", dest, table.concat(steps, " ; ")))
  mm.note(string.format("Distance: %d", tonumber(depth) or #steps))
  return true
end

function mm.next_result(index)
  local results = mm.search_state.results or {}
  if #results == 0 then return false, "no saved search results" end

  local idx = tonumber(index)
  if idx then
    if idx < 1 or idx > #results then return false, "index out of range" end
    mm.search_state.index = idx
  else
    mm.search_state.index = ((mm.search_state.index or 0) % #results) + 1
  end

  local pick = results[mm.search_state.index]
  local rid = pick and (tonumber(pick.uid) or tonumber(pick.rmid)) or nil
  if not rid then return false, "selected result has no room id" end
  mm.note(string.format("next -> #%d room %d", mm.search_state.index, rid))
  return mm.goto_room(rid)
end

mm.terrain_ids = mm.terrain_ids or {}


local function is_cardinal_dir(dir)
  local d = tostring(dir or ""):lower()
  return d == "n" or d == "s" or d == "e" or d == "w" or d == "u" or d == "d" or
    d == "north" or d == "south" or d == "east" or d == "west" or d == "up" or d == "down"
end

function mm.normalize_stacked_command(command)
  local normalized = tostring(command or "")
  normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
  -- Mudlet special exits require doubled separators between chained commands.
  -- Canonicalize any semicolon separator runs to ";;" so persisted cexits are
  -- usable when replayed through mapper navigation.
  normalized = normalized:gsub("%s*;+%s*", ";;")
  return normalized
end

function mm.set_cexit_wait(seconds)
  local n = tonumber(seconds)
  if not n or n < 2 or n > 40 then
    return false, "cexit_wait must be between 2 and 40 seconds"
  end
  mm.state.temp_cexit_delay = n
  mm.note(string.format("cexit_wait set to %s seconds for next mapper cexit", tostring(n)))
  return true
end

function mm.add_full_cexit(command, src, dst, level, quiet, opts)
  opts = opts or {}
  if not opts.preserve_command then
    command = mm.normalize_stacked_command(command)
  else
    command = tostring(command or ""):gsub("^%s+", ""):gsub("%s+$", "")
  end
  -- Preserve nomap_ virtual IDs as strings; convert numeric IDs normally.
  local srcStr = mm.strip_ansi(src):gsub("^%s+", ""):gsub("%s+$", "")
  local dstStr = mm.strip_ansi(dst):gsub("^%s+", ""):gsub("%s+$", "")
  local srcIsNomap = srcStr:match("^nomap_")
  local dstIsNomap = dstStr:match("^nomap_")
  if srcIsNomap then src = srcStr else src = tonumber(src) end
  if dstIsNomap then dst = dstStr else dst = tonumber(dst) end
  level = tonumber(level) or 0
  if command == "" then return false, "cexit command is required" end
  if (not srcIsNomap and not src) or (not dstIsNomap and not dst) then
    return false, "source and destination room ids are required"
  end
  if src == dst then return false, "start room and destination room should be different" end

  local ok, err = mm.exec_mapper_db(string.format(
    "INSERT OR REPLACE INTO exits (dir, fromuid, touid, level) VALUES (%s, %s, %s, %s)",
    mm.sql_escape(command), mm.sql_escape(src), mm.sql_escape(dst), mm.sql_escape(level)
  ))
  if not ok then return false, err end

  -- Mudlet bigmap APIs require numeric room IDs; skip them for nomap_ virtual rooms.
  if not srcIsNomap and not dstIsNomap then
    if is_cardinal_dir(command) and type(setExit) == "function" then
      pcall(setExit, src, dst, command)
    elseif type(addSpecialExit) == "function" then
      pcall(addSpecialExit, src, dst, command)
    end
  end

  if not quiet then
    mm.note(string.format("Custom Exit CONFIRMED: %s (%s) -> %s [lock level %d]", tostring(src), command, tostring(dst), level))
  end
  return true
end

function mm.cexit(command)
  local src = mm.current_room()
  if not src then return false, "CEXIT FAILED: No room received yet. Try LOOK first." end
  local original_command = tostring(command or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if original_command == "" then return false, "Nothing to do" end

  mm.note(string.format("CEXIT DEBUG: src=%s command='%s'", tostring(src), original_command))
  local added_waits = 0
  for wait_secs in string.gmatch(original_command, "wait%((%d*.?%d+)%)") do
    added_waits = added_waits + (tonumber(wait_secs) or 0)
  end
  mm.note(string.format("CEXIT DEBUG: added_waits=%s", tostring(added_waits)))
  mm.note("CEXIT: WAIT FOR CONFIRMATION BEFORE MOVING.")
  mm.note(string.format("CEXIT DEBUG: sending='%s'", original_command))

  local function split_stacked_commands(raw)
    local parts = {}
    for part in tostring(raw or ""):gmatch("([^;]+)") do
      local trimmed = tostring(part):gsub("^%s+", ""):gsub("%s+$", "")
      if trimmed ~= "" then
        table.insert(parts, trimmed)
      end
    end
    return parts
  end

  local function run_cexit_step(step_cmd)
    if type(expandAlias) == "function" then
      expandAlias(step_cmd)
    else
      send(step_cmd)
    end
  end

  local steps = split_stacked_commands(original_command)
  local cursor_delay = 0
  local step_gap = 0.05
  for idx, step in ipairs(steps) do
    local wait_time = tonumber(step:match("^wait%((%d*.?%d+)%)$"))
    if wait_time then
      cursor_delay = cursor_delay + wait_time
      mm.note(string.format("CEXIT DEBUG: step[%d]='%s' (local wait %.2fs)", idx, step, wait_time))
    else
      mm.note(string.format("CEXIT DEBUG: step[%d]='%s' delay=%.2f", idx, step, cursor_delay))
      if cursor_delay <= 0 then
        run_cexit_step(step)
      else
        tempTimer(cursor_delay, function()
          run_cexit_step(step)
        end)
      end
      cursor_delay = cursor_delay + step_gap
    end
  end

  local delay = tonumber(mm.state.temp_cexit_delay) or 2
  delay = delay + added_waits
  mm.state.temp_cexit_delay = nil
  tempTimer(delay, function()
    local dst = mm.current_room()
    if not dst then mm.warn("CEXIT FAILED: Need to know where we ended up."); return end
    mm.note(string.format("CEXIT DEBUG: post-delay src=%s dst=%s command='%s'", tostring(src), tostring(dst), original_command))
    local ok, err = mm.add_full_cexit(original_command, src, dst, 0, false, { preserve_command = true })
    if not ok then
      mm.warn("CEXIT FAILED: " .. tostring(err))
    else
      mm.note(string.format("CEXIT DEBUG: add_full_cexit persisted command='%s' from=%s to=%s", original_command, tostring(src), tostring(dst)))
    end
  end)
  return true
end

local function print_cexits_table(rows)
  cecho("<gray>#   From     Area         Name                           Dir                    To<reset>\n")
  cecho("<gray>-----------------------------------------------------------------------------------<reset>\n")
  for i, row in ipairs(rows) do
    local from = tonumber(row.uid or row.fromuid) or -1
    local to = tonumber(row.touid) or -1
    local area = tostring(row.area or "")
    local name = tostring(row.name or "")
    local dir = tostring(row.dir or "")
    cecho(string.format("<light_grey>%-3d<reset> ", i))
    if from > 0 then
      echoLink(string.format("(%d)", from), [[mm.goto_room(]] .. from .. [[)]], "Go to source room", true)
    else
      echo("(?)")
    end
    cecho(string.format("  <light_grey>%-10.10s %-30.30s %-22.22s<reset> ", area, name, dir))
    if to > 0 then
      echoLink(string.format("(%d)", to), [[mm.goto_room(]] .. to .. [[)]], "Go to destination room", true)
    else
      echo("(?)")
    end
    echo("\n")
    if i >= 200 then break end
  end
end

local function cexit_where_for_scope(scope_arg)
  local arg = tostring(scope_arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local lower = arg:lower()
  local where = "dir NOT IN ('n','s','e','w','u','d') AND fromuid NOT IN ('*','**')"
  local intro = "The following rooms have custom exits:"
  if lower == "thisroom" then
    local room = mm.current_room()
    if not room then return nil, nil, "CEXITS THISROOM ERROR: unknown current room; try LOOK" end
    where = where .. " AND fromuid = " .. mm.sql_escape(room)
    intro = "The following custom exits are in this room:"
  elseif lower == "here" then
    local area = current_area_name()
    if area == "" then return nil, nil, "CEXITS HERE ERROR: unknown current area; try LOOK" end
    where = where .. " AND lower(area) = " .. mm.sql_escape(area:lower())
    intro = "The following rooms in the current area have custom exits:"
  elseif lower:match("^area%s+") then
    local area_name = arg:sub(6):gsub("^%s+", ""):gsub("%s+$", "")
    if area_name == "" then return nil, nil, "Usage: mapper cexits area <area name>" end
    where = where .. " AND lower(area) LIKE " .. mm.sql_escape("%" .. area_name:lower() .. "%")
    intro = string.format("The following rooms in areas partially matching '%s' have custom exits:", area_name)
  elseif lower ~= "" then
    where = where .. " AND lower(area) LIKE " .. mm.sql_escape("%" .. lower .. "%")
    intro = string.format("The following rooms in areas partially matching '%s' have custom exits:", arg)
  end
  return where, intro, nil
end

function mm.list_cexits(scope_arg)
  local where, intro, err = cexit_where_for_scope(scope_arg)
  if not where then return false, err end

  local sql = "SELECT COALESCE(rooms.uid, exits.fromuid) AS uid, COALESCE(rooms.name, exits.fromuid) AS name, COALESCE(rooms.area, '') AS area, exits.dir, exits.touid "
    .. "FROM exits LEFT JOIN rooms ON rooms.uid = exits.fromuid WHERE " .. where .. " ORDER BY area, uid, dir"
  local rows, qerr = mm.query_mapper_db(sql)
  if not rows then return false, qerr end

  mm.runtime.cexit_last_rows = rows
  mm.runtime.cexit_last_scope = tostring(scope_arg or "")

  mm.note(intro)
  if #rows == 0 then mm.note("Found 0 custom exits."); return true end
  print_cexits_table(rows)
  mm.note(string.format("Found %d custom exits.", #rows))
  return true
end

function mm.delete_cexits_here()
  local room = mm.current_room()
  if not room then return false, "EXIT DELETE ERROR: unknown current room; try LOOK" end

  local ok, err = mm.exec_mapper_db(string.format(
    "DELETE FROM exits WHERE fromuid=%s AND dir NOT IN ('n','s','e','w','u','d')",
    mm.sql_escape(room)
  ))
  if not ok then return false, err end

  if type(getSpecialExits) == "function" and type(removeSpecialExit) == "function" then
    local se = getSpecialExits(room) or {}
    for dir, _ in pairs(se) do pcall(removeSpecialExit, room, dir) end
  end

  mm.note("Removed custom exits from the current room.")
  return true
end

local function remember_deleted_cexit(entry)
  mm.state.deleted_cexits = mm.state.deleted_cexits or {}
  table.insert(mm.state.deleted_cexits, entry)
  while #mm.state.deleted_cexits > 20 do
    table.remove(mm.state.deleted_cexits, 1)
  end
  local ok, err = mm.save_deleted_cexits_persistence()
  if not ok then
    mm.warn("Deleted cexit history save failed: " .. tostring(err))
  end
end

local function cexit_row_to_entry(row)
  return {
    fromuid = tostring(row.uid or row.fromuid or ""),
    touid = tostring(row.touid or ""),
    dir = tostring(row.dir or ""),
    area = tostring(row.area or ""),
    name = tostring(row.name or ""),
    deleted_at = os.time(),
  }
end

function mm.delete_cexit(index)
  local n = tonumber(index)
  if not n then return false, "Usage: mapper deletecexit <number>" end
  local rows = mm.runtime.cexit_last_rows or {}
  local row = rows[n]
  if not row then return false, "DELETE CEXIT ERROR: index out of range for last shown cexits table" end
  local entry = cexit_row_to_entry(row)
  if entry.fromuid == "" or entry.dir == "" or entry.touid == "" then
    return false, "DELETE CEXIT ERROR: selected cexit row is missing required fields"
  end

  local timing_enabled = mm.state and mm.state.debug
  local timing_start = timing_enabled and now_millis() or nil
  local db_start = timing_start

  -- never delete active cexits
  local ok, err = mm.exec_mapper_db(string.format(
    "DELETE FROM exits WHERE fromuid=%s AND dir=%s AND touid=%s",
    mm.sql_escape(entry.fromuid), mm.sql_escape(entry.dir), mm.sql_escape(entry.touid)
  ))
  local db_done = timing_enabled and now_millis() or nil
  if not ok then return false, err end

  local remove_done = db_done
  if type(removeSpecialExit) == "function" then
    pcall(removeSpecialExit, tonumber(entry.fromuid) or entry.fromuid, entry.dir)
    if timing_enabled then remove_done = now_millis() end
  end

  remember_deleted_cexit(entry)
  local history_done = timing_enabled and now_millis() or nil

  if timing_enabled then
    mm.debug(string.format(
      "deletecexit timing: from=%s dir=%s to=%s db=%.1fms removeSpecialExit=%.1fms history=%.1fms total=%.1fms",
      entry.fromuid,
      entry.dir,
      entry.touid,
      (db_done or timing_start) - (db_start or timing_start),
      (remove_done or db_done) - (db_done or timing_start),
      (history_done or remove_done) - (remove_done or timing_start),
      (history_done or timing_start) - timing_start
    ))
  end

  table.remove(rows, n)
  mm.runtime.cexit_last_rows = rows

  mm.note(string.format(
    "Deleted cexit: from (%s) area '%s' room '%s' dir '%s' to (%s).",
    entry.fromuid, entry.area, entry.name, entry.dir, entry.touid
  ))
  return true
end

function mm.list_deleted_cexits()
  local rows = mm.state.deleted_cexits or {}
  mm.note("Recently deleted custom exits:")
  if #rows == 0 then
    mm.note("No deleted custom exits saved.")
    return true
  end
  local shaped = {}
  for i = #rows, 1, -1 do
    local row = rows[i]
    table.insert(shaped, {
      uid = row.fromuid,
      area = row.area,
      name = row.name,
      dir = row.dir,
      touid = row.touid,
    })
  end
  print_cexits_table(shaped)
  mm.note(string.format("Showing %d deleted custom exits (max 20).", #rows))
  return true
end

function mm.restore_cexit(which)
  local rows = mm.state.deleted_cexits or {}
  if #rows == 0 then return false, "RESTORE CEXIT ERROR: deleted cexit history is empty" end
  local pick
  local from_last = false
  if tostring(which or ""):lower() == "last" then
    pick = #rows
    from_last = true
  else
    local shown_index = tonumber(which)
    if shown_index then pick = (#rows - shown_index + 1) end
  end
  if not pick then return false, "Usage: mapper restorecexit <number|last>" end
  if pick < 1 or pick > #rows then return false, "RESTORE CEXIT ERROR: index out of range" end
  local row = rows[pick]
  local ok, err = mm.exec_mapper_db(string.format(
    "INSERT OR REPLACE INTO exits (fromuid, dir, touid, level) VALUES (%s, %s, %s, 0)",
    mm.sql_escape(row.fromuid), mm.sql_escape(row.dir), mm.sql_escape(row.touid)
  ))
  if not ok then return false, err end
  table.remove(rows, pick)
  mm.save_deleted_cexits_persistence()
  if not from_last then
    mm.note(string.format("Restored deleted cexit row %s from mapper deletedcexits list.", tostring(which)))
  end
  mm.note(string.format(
    "Restored cexit: from (%s) area '%s' room '%s' dir '%s' to (%s).",
    tostring(row.fromuid), tostring(row.area or ""), tostring(row.name or ""), tostring(row.dir), tostring(row.touid)
  ))
  return true
end

local function remember_deleted_portal(entry)
  mm.state.deleted_portals = mm.state.deleted_portals or {}
  table.insert(mm.state.deleted_portals, entry)
  while #mm.state.deleted_portals > 20 do
    table.remove(mm.state.deleted_portals, 1)
  end
  local ok, err = mm.save_deleted_portals_persistence()
  if not ok then
    mm.warn("Deleted portal history save failed: " .. tostring(err))
  end
end

function mm.delete_portal_by_index(index)
  local n = tonumber(index)
  if not n then return false, "Usage: mapper delete portal #<index>" end
  local portals = mm.portals and mm.portals.rebuilt or {}
  local portal = portals[n]
  if not portal then return false, "Portal index not found in rebuilt list. Run 'mapper portals' and try again." end

  local fromuid = tostring(portal.fromuid or (portal.fixed_recall and "**" or "*"))
  local command = tostring(portal.command or "")
  local touid = tostring(portal.touid or "")
  if (fromuid ~= "*" and fromuid ~= "**") or command == "" or touid == "" then
    return false, "Selected portal row is missing required fields."
  end

  local count_rows, cerr = mm.query_mapper_db(string.format(
    "SELECT COUNT(*) AS cnt FROM exits WHERE fromuid=%s AND dir=%s AND touid=%s",
    mm.sql_escape(fromuid), mm.sql_escape(command), mm.sql_escape(touid)
  ))
  if not count_rows then return false, cerr end
  local count = tonumber(count_rows[1] and count_rows[1].cnt) or 0
  if count < 1 then
    return false, "No matching portal row found in database for selected index."
  end

  local ok, err = mm.exec_mapper_db(string.format(
    "DELETE FROM exits WHERE fromuid=%s AND dir=%s AND touid=%s",
    mm.sql_escape(fromuid), mm.sql_escape(command), mm.sql_escape(touid)
  ))
  if not ok then return false, err end

  remember_deleted_portal({
    fromuid = fromuid,
    touid = touid,
    command = command,
    level = tonumber(portal.level) or 0,
    chaos = tostring(portal.chaos or "no"),
    area = tostring(portal.area or ""),
    room_name = tostring(portal.room_name or ""),
    deleted_at = os.time(),
  })

  if mm.rebuild_portals_from_db then mm.rebuild_portals_from_db() end
  mm.note(string.format("Deleted %s portal #%d: '%s' to room %s.", (fromuid == "**" and "recall" or "regular"), n, command, touid))
  return true
end

function mm.list_deleted_portals()
  local rows = mm.state.deleted_portals or {}
  mm.note("Recently deleted portals:")
  if #rows == 0 then
    mm.note("No deleted portals saved.")
    return true
  end
  cecho("\n<gray>Idx  Type     Command                           To Room    Area                    Room<reset>\n")
  cecho("<gray>----------------------------------------------------------------------------------------------------<reset>\n")
  local shown = 0
  for i = #rows, 1, -1 do
    shown = shown + 1
    local row = rows[i]
    local ptype = (tostring(row.fromuid) == "**") and "Recall" or "Portal"
    cecho(string.format(
      "<light_steel_blue>%-3d<reset> <khaki>%-8s<reset> <white>%-32s<reset> <light_grey>%-10s %-22s %-22s<reset>\n",
      shown,
      ptype,
      tostring(row.command or "?"),
      tostring(row.touid or "?"),
      tostring(row.area or ""),
      tostring(row.room_name or "")
    ))
  end
  mm.note(string.format("Showing %d deleted portals (max 20).", #rows))
  return true
end

function mm.restore_portal(which)
  local rows = mm.state.deleted_portals or {}
  if #rows == 0 then return false, "RESTORE PORTAL ERROR: deleted portal history is empty" end

  local pick
  local from_last = false
  if tostring(which or ""):lower() == "last" then
    pick = #rows
    from_last = true
  else
    local shown_index = tonumber(which)
    if shown_index then pick = (#rows - shown_index + 1) end
  end
  if not pick then return false, "Usage: mapper restoreportal <number|last>" end
  if pick < 1 or pick > #rows then return false, "RESTORE PORTAL ERROR: index out of range" end

  local row = rows[pick]
  local fromuid = tostring(row.fromuid or "")
  if fromuid ~= "*" and fromuid ~= "**" then
    return false, "RESTORE PORTAL ERROR: invalid portal type in history"
  end
  local ok, err = mm.exec_mapper_db(string.format(
    "INSERT OR REPLACE INTO exits (fromuid, dir, touid, level, chaos) VALUES (%s, %s, %s, %d, %s)",
    mm.sql_escape(fromuid),
    mm.sql_escape(tostring(row.command or "")),
    mm.sql_escape(tostring(row.touid or "")),
    tonumber(row.level) or 0,
    mm.sql_escape(tostring(row.chaos or "no"))
  ))
  if not ok then return false, err end

  table.remove(rows, pick)
  mm.save_deleted_portals_persistence()
  if mm.rebuild_portals_from_db then mm.rebuild_portals_from_db() end
  if not from_last then
    mm.note(string.format("Restored deleted portal row %s from mapper deletedportals list.", tostring(which)))
  end
  mm.note(string.format("Restored %s portal: '%s' to room %s.", (fromuid == "**" and "recall" or "regular"), tostring(row.command or ""), tostring(row.touid or "")))
  return true
end
