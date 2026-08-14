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
  minimap = { enabled = true, show_room = true, show_exits = true, show_coords = true, echo = true, bigmap_mode = "hybrid", local_radius = 4, local_room_size = 15, local_zoom = 100 },
  windows = {
    minimap = { x = "70%", y = "0%", width = "30%", height = "35%", max_lines = 16, enabled = true, locked = false, font_size = 8 },
    bigmap = { x = "45%", y = "35%", width = "55%", height = "65%", max_lines = 60, enabled = true, locked = false, font_size = 9 },
  },
  last_target = nil,
  map_db = "Aardwolf.db",
  native_mapper_db = "mmapper_converted_map.dat",
  native_mapper_preload_enabled = false,
  auto_locate = true,
  center_on_locate = true,
  portal_guard_enabled = false,
  autostop_enabled = true,
  debug = false,
}

-- A partially populated state table can survive package reloads.  Always keep
-- the live SQLite database name usable instead of resolving whitespace to the
-- profile directory and producing a misleading "database not found" warning.
if type(mm.state.map_db) ~= "string" or not mm.state.map_db:match("%S") then
  mm.state.map_db = "Aardwolf.db"
end
if type(mm.state.native_mapper_db) ~= "string" or not mm.state.native_mapper_db:match("%S") then
  mm.state.native_mapper_db = "mmapper_converted_map.dat"
end
if type(mm.state.native_mapper_preload_enabled) ~= "boolean" then
  mm.state.native_mapper_preload_enabled = false
end
if type(mm.state.autostop_enabled) ~= "boolean" then
  mm.state.autostop_enabled = true
end
-- Portal guarding is configured per DINV portal ID.  Keep the retired global
-- flag false even across an in-session package reload where mm.state survives.
mm.state.portal_guard_enabled = false

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
    portal_guard_levels = {},
    portal_guard_migration_version = 1,
  },
}

local DEFAULT_PORTAL_GUARD_LEVEL = 20
local PORTAL_GUARD_MIGRATION_VERSION = 1

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
  "coords_set",
  "layouts_rebuilt",
  "room_colors_set",
  "env_colors_set",
  "local_map_renders",
  "local_map_render_ms",
  "local_map_render_max_ms",
  "local_drawables_created",
  "local_drawables_reused",
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
  print_stat("Env rows updated", stats.env_rows_updated)

  cecho("\n  <yellow>Map updates<reset>\n")
  print_stat("Coords set", stats.coords_set)
  print_stat("Layouts rebuilt", stats.layouts_rebuilt)
  print_stat("Room colors set", stats.room_colors_set)
  print_stat("Env colors set", stats.env_colors_set)

  cecho("\n  <yellow>Local BigMap rendering<reset>\n")
  print_stat("Renders", stats.local_map_renders)
  print_stat("Total render ms", stats.local_map_render_ms)
  print_stat("Slowest render ms", stats.local_map_render_max_ms)
  print_stat("Drawables created", stats.local_drawables_created)
  print_stat("Drawables reused", stats.local_drawables_reused)

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
  mm.state.portal_guard_enabled = false
  local chunk = mm.load_persistence_chunk(SETTINGS_PERSIST_FILE)
  if not chunk then return false end

  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return false end
  if type(data.autostop_enabled) == "boolean" then
    mm.state.autostop_enabled = data.autostop_enabled
  end
  if type(data.native_mapper_db) == "string" and data.native_mapper_db ~= "" then
    mm.state.native_mapper_db = data.native_mapper_db
  end
  if type(data.native_mapper_preload_enabled) == "boolean" then
    mm.state.native_mapper_preload_enabled = data.native_mapper_preload_enabled
  end
  if type(data.auto_locate) == "boolean" then
    mm.state.auto_locate = data.auto_locate
    mm.state.center_on_locate = data.auto_locate
  end
  if type(data.minimap) == "table" then
    mm.state.minimap = mm.state.minimap or {}
    if data.minimap.bigmap_mode == "native" or data.minimap.bigmap_mode == "hybrid" then
      mm.state.minimap.bigmap_mode = data.minimap.bigmap_mode
    elseif data.minimap.bigmap_mode == "local" then
      -- Local remains an internal hybrid backend, but is no longer a public
      -- configuration. Migrate old profiles without making them render
      -- continents through the area renderer.
      mm.state.minimap.bigmap_mode = "hybrid"
    end
    if tonumber(data.minimap.local_radius) then
      mm.state.minimap.local_radius = tonumber(data.minimap.local_radius)
    end
    if tonumber(data.minimap.local_room_size) then
      mm.state.minimap.local_room_size = tonumber(data.minimap.local_room_size)
    end
    if tonumber(data.minimap.local_zoom) then
      mm.state.minimap.local_zoom = tonumber(data.minimap.local_zoom)
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
    -- Kept only so older builds also start with their retired global guard off.
    portal_guard_enabled = false,
    autostop_enabled = mm.state.autostop_enabled ~= false,
    native_mapper_db = mm.state.native_mapper_db or "mmapper_converted_map.dat",
    native_mapper_preload_enabled = mm.state.native_mapper_preload_enabled == true,
    auto_locate = mm.state.auto_locate ~= false,
    minimap = {
      bigmap_mode = (mm.state.minimap and mm.state.minimap.bigmap_mode) or "hybrid",
      local_radius = tonumber(mm.state.minimap and mm.state.minimap.local_radius) or 4,
      local_room_size = tonumber(mm.state.minimap and mm.state.minimap.local_room_size) or 15,
      local_zoom = tonumber(mm.state.minimap and mm.state.minimap.local_zoom) or 100,
    },
  }))
  f:close()
  return true
end

function mm.portal_guard_status_text()
  return "PortalGuard is configured per DINV portal ID. Use 'mapper portalguard' to list guarded portals."
end

function mm.set_portal_guard()
  mm.state.portal_guard_enabled = false
  return false, "global PortalGuard was retired; use mapper portalguard <portal-id> [guard-level|off]"
end

function mm.autostop_status_text()
  return string.format(
    "autostop %s: sends the MUD command 'stop' when GMCP enters combat during active mapper navigation.",
    (mm.state.autostop_enabled ~= false) and "on" or "off"
  )
end

function mm.set_autostop(enabled)
  mm.state.autostop_enabled = enabled ~= false
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
  local cleaned = {
    fromuid = fromuid,
    touid = touid,
    dir = dir,
    area = tostring(entry.area or ""),
    name = tostring(entry.name or ""),
    level = tonumber(entry.level) or 0,
    deleted_at = tonumber(entry.deleted_at) or os.time(),
  }
  local key_name = tostring(entry.key_name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local key_keywords = tostring(entry.key_keywords or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local alternate_command = tostring(entry.alternate_command or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if key_keywords ~= "" and alternate_command ~= "" then
    cleaned.key_name = key_name
    cleaned.key_keywords = key_keywords
    cleaned.alternate_command = alternate_command
  end
  return cleaned
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
  local guard_migrated = tonumber(persisted_settings.portal_guard_migration_version)
    == PORTAL_GUARD_MIGRATION_VERSION
  mm.portals.settings.portal_guard_levels = {}
  if guard_migrated then
    for id, raw_level in pairs(persisted_settings.portal_guard_levels or {}) do
      local normalized = tostring(id or ""):gsub("^%s+", ""):gsub("%s+$", "")
      local guard_level = tonumber(raw_level)
      if normalized ~= "" and guard_level and guard_level >= 1 and guard_level <= 201
          and mm.portals.settings.recall_ids[normalized] ~= true then
        local fixed_recall = false
        for _, portal in ipairs(restored) do
          if tostring(portal.portal_id) == normalized and portal.fixed_recall == true then
            fixed_recall = true
            break
          end
        end
        if not fixed_recall then
          mm.portals.settings.portal_guard_levels[normalized] = math.floor(guard_level)
        end
      end
    end
  end
  -- A missing migration marker is the legacy global-guard format.  Its state is
  -- deliberately not imported: every portal starts unguarded exactly once.
  mm.portals.settings.portal_guard_migration_version = PORTAL_GUARD_MIGRATION_VERSION
  if source_path == mm.legacy_persistence_path(PORTAL_PERSIST_FILE) or not guard_migrated then
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
  local portal_guard_levels = {}
  for id, raw_level in pairs(mm.portals.settings.portal_guard_levels or {}) do
    local guard_level = tonumber(raw_level)
    if guard_level and guard_level >= 1 and guard_level <= 201 then
      portal_guard_levels[tostring(id)] = math.floor(guard_level)
    end
  end
  local payload = {
    rebuilt = mm.portals.rebuilt or {},
    rebuilt_at = mm.portals.rebuilt_at,
    settings = {
      recall_ids = recall_ids,
      bounce_portal_id = mm.portals.settings.bounce_portal_id and tostring(mm.portals.settings.bounce_portal_id) or nil,
      bounce_recall_id = mm.portals.settings.bounce_recall_id and tostring(mm.portals.settings.bounce_recall_id) or nil,
      portal_guard_levels = portal_guard_levels,
      portal_guard_migration_version = PORTAL_GUARD_MIGRATION_VERSION,
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
  if tonumber(mm.portals.settings.portal_guard_migration_version) ~= PORTAL_GUARD_MIGRATION_VERSION then
    mm.portals.settings.portal_guard_levels = {}
    mm.portals.settings.portal_guard_migration_version = PORTAL_GUARD_MIGRATION_VERSION
  end
  mm.portals.settings.portal_guard_levels = mm.portals.settings.portal_guard_levels or {}
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
  local removed_guard = nil
  if next_state then
    removed_guard = mm.portals.settings.portal_guard_levels[id]
    mm.portals.settings.portal_guard_levels[id] = nil
    if mm.portals.settings.bounce_portal_id == id then
      mm.portals.settings.bounce_portal_id = nil
    end
  end
  if not next_state and mm.portals.settings.bounce_recall_id == id then
    mm.portals.settings.bounce_recall_id = nil
  end
  local saved, save_err = mm.save_portal_persistence()
  return saved, save_err, removed_guard
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

mm.find_portal_by_id = find_portal_by_id

function mm.dinv_portal_id(command)
  return tostring(command or ""):lower():match("^%s*dinv%s+portal%s+use%s+([%w_%-]+)")
end

function mm.portal_effective_level()
  local level = tonumber(snd and snd.char and snd.char.level) or 0
  local tier = tonumber(snd and snd.char and snd.char.tier) or 0
  return level + (tier * 10)
end

function mm.portal_guard_level(portal_id)
  ensure_portal_settings()
  local guard_level = tonumber(mm.portals.settings.portal_guard_levels[tostring(portal_id or "")])
  if not guard_level or guard_level < 1 then return nil end
  return math.floor(guard_level)
end

function mm.portal_guard_details(portal_id)
  local id = tostring(portal_id or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local guard_level = mm.portal_guard_level(id)
  if not guard_level then return nil end
  local portal = find_portal_by_id(id)
  if not portal or mm.is_portal_recall(portal) then return nil end
  if tostring(mm.dinv_portal_id(portal.command) or "") ~= id then return nil end
  local base_level = tonumber(portal.level) or 0
  local effective_level = mm.portal_effective_level()
  return {
    portal_id = id,
    portal = portal,
    guard_level = guard_level,
    base_level = base_level,
    required_level = base_level + guard_level,
    effective_level = effective_level,
    blocked = effective_level < (base_level + guard_level),
  }
end

function mm.portal_guard_details_for_command(command)
  local portal_id = mm.dinv_portal_id(command)
  if not portal_id then return nil end
  return mm.portal_guard_details(portal_id)
end

function mm.portal_guard_entries()
  ensure_portal_settings()
  local entries = {}
  for id in pairs(mm.portals.settings.portal_guard_levels) do
    local details = mm.portal_guard_details(id)
    if details then table.insert(entries, details) end
  end
  table.sort(entries, function(a, b)
    local an, bn = tonumber(a.portal_id), tonumber(b.portal_id)
    if an and bn and an ~= bn then return an < bn end
    return tostring(a.portal_id) < tostring(b.portal_id)
  end)
  return entries
end

function mm.set_portal_guard_level(portal_id, raw_guard_level)
  ensure_portal_settings()
  local id = tostring(portal_id or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if id == "" then return false, "portal ID is required" end
  local portal = find_portal_by_id(id)
  if not portal then
    return false, "portal ID " .. id .. " was not found; run 'mapper portals' to list stable portal IDs"
  end
  if tostring(mm.dinv_portal_id(portal.command) or "") ~= id then
    return false, "only DINV portals can be guarded by portal ID"
  end
  if mm.is_portal_recall(portal) then
    return false, "portal " .. id .. " is configured as recall and cannot be guarded; recall destinations are assumed safe"
  end

  local guard_level = tonumber(raw_guard_level == nil and DEFAULT_PORTAL_GUARD_LEVEL or raw_guard_level)
  if not guard_level or guard_level ~= math.floor(guard_level) or guard_level < 1 or guard_level > 201 then
    return false, "guard level must be a whole number from 1 to 201"
  end
  local previous = mm.portals.settings.portal_guard_levels[id]
  mm.portals.settings.portal_guard_levels[id] = guard_level
  local saved, save_err = mm.save_portal_persistence()
  if not saved then
    mm.portals.settings.portal_guard_levels[id] = previous
    return false, save_err
  end
  return true, {
    portal = portal,
    portal_id = id,
    guard_level = guard_level,
    required_level = (tonumber(portal.level) or 0) + guard_level,
    is_bounce_portal = tostring(mm.portals.settings.bounce_portal_id or "") == id,
  }
end

function mm.clear_portal_guard(portal_id)
  ensure_portal_settings()
  local id = tostring(portal_id or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if id == "" then return false, "portal ID is required" end
  local previous = mm.portals.settings.portal_guard_levels[id]
  mm.portals.settings.portal_guard_levels[id] = nil
  local saved, save_err = mm.save_portal_persistence()
  if not saved then
    mm.portals.settings.portal_guard_levels[id] = previous
    return false, save_err
  end
  return true, {portal_id = id, previous = previous, portal = find_portal_by_id(id)}
end

function mm.print_portal_guards()
  local entries = mm.portal_guard_entries()
  if #entries == 0 then
    mm.note("No individually guarded portals. Use: mapper portalguard <portal-id> [guard-level]")
    return true
  end
  mm.note("Individually guarded DINV portals:")
  for _, details in ipairs(entries) do
    local portal = details.portal
    mm.note(string.format(
      "  %s: level %d + guard %d = %d -> %s (%s) [%s at effective level %d]",
      details.portal_id,
      details.base_level,
      details.guard_level,
      details.required_level,
      tostring(portal.room_name or "?"),
      tostring(portal.area or "?"),
      details.blocked and "BLOCKED" or "allowed",
      details.effective_level
    ))
  end
  return true
end

-- Resolve bounce settings from their persisted portal IDs on demand.  The
-- navigation table is recreated when MMapper is reloaded, while mm.portals may
-- survive that reload.  Keeping this resolver in the portal owner prevents a
-- stale/nil copied setting from silently disabling bounce routing.
function mm.get_configured_bounce_step(travel_type)
  ensure_portal_settings()
  local is_recall = travel_type == "recall"
  local id = is_recall
    and mm.portals.settings.bounce_recall_id
    or mm.portals.settings.bounce_portal_id
  local portal = find_portal_by_id(id)
  if not portal then return nil end
  if is_recall ~= mm.is_portal_recall(portal) then return nil end
  if mm.is_portal_chaos(portal) then return nil end

  local landing = portal.touid or portal.target_uid
  if not portal.command or not landing then return nil end
  return {
    dir = portal.command,
    uid = tostring(landing),
    level = tonumber(portal.level) or 0,
    travelType = is_recall and "recall" or "portal",
    portalId = tostring(portal.portal_id),
  }
end

function mm.apply_bounce_settings_to_snd()
  local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
  if not (nav and nav.config) then
    return false, "mapper navigation module is unavailable"
  end
  ensure_portal_settings()
  local bouncePortal = find_portal_by_id(mm.portals.settings.bounce_portal_id)
  local bounceRecall = find_portal_by_id(mm.portals.settings.bounce_recall_id)
  nav.config.bouncePortal = mm.get_configured_bounce_step("portal")
  nav.config.bounceRecall = mm.get_configured_bounce_step("recall")
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

function mm.native_mapper_preload_status_text()
  if mm.state.native_mapper_preload_enabled == true then
    return "native map preload on: hybrid briefly initializes the normal native BigMap at startup, loads once, then restores the configured display mode."
  end
  return "native map preload off: hybrid loads the native map lazily on the first continent that needs it."
end

function mm.set_native_mapper_preload(enabled)
  mm.state.native_mapper_preload_enabled = enabled == true
  local ok, err = mm.save_settings_persistence()
  if not ok then
    return false, err
  end

  if mm.state.native_mapper_preload_enabled then
    if mm.initialized and mm.schedule_native_mapper_preload then
      mm.schedule_native_mapper_preload("native_preload_enabled")
    end
  else
    if mm.cancel_native_mapper_startup_load then
      mm.cancel_native_mapper_startup_load()
    end
    if mm.minimap and mm.minimap.cancel_native_preload then
      mm.minimap.cancel_native_preload("native preload disabled")
    end
  end
  return true
end

function mm.load_native_mapper_db(path)
  local pipeline_started = now_millis()
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
  mm.runtime.hybrid_native_unavailable_reason = nil
  mm.runtime.terrain_colors_applied = nil
  mm.runtime.native_missing_room_warnings = {}
  mm.note("Loaded native Mudlet mapper DB: " .. resolved)
  local colors_started = now_millis()
  if mm.import and mm.import.apply_environment_colors_from_sqlite then
    local colors_ok, colors_err = mm.import.apply_environment_colors_from_sqlite(mm.state.map_db)
    if not colors_ok then mm.debug("Native map terrain colors deferred: " .. tostring(colors_err)) end
  elseif mm.apply_terrain_colors then
    local colors_ok, colors_err = mm.apply_terrain_colors()
    if not colors_ok then mm.debug("Native map terrain colors deferred: " .. tostring(colors_err)) end
  end
  mm.debug(string.format(
    "native mapper terrain-color timing: %.1fms",
    now_millis() - colors_started))
  mm.runtime.native_exit_lock_visuals = {}
  local exit_visuals_started = now_millis()
  if snd and snd.mapper and type(snd.mapper.refreshNativeExitLockVisuals) == "function" then
    local visuals_ok, visuals_err = snd.mapper.refreshNativeExitLockVisuals(nil, true)
    if not visuals_ok then
      mm.debug("Native exit-lock colors deferred: " .. tostring(visuals_err))
    end
  end
  mm.debug(string.format(
    "native mapper exit-lock visual timing: %.1fms",
    now_millis() - exit_visuals_started))
  local sync_started = now_millis()
  if mm.sync_native_bigmap_to_current_room then
    mm.sync_native_bigmap_to_current_room("native_map_loaded")
  end
  mm.debug(string.format(
    "native mapper room-sync timing: %.1fms",
    now_millis() - sync_started))
  mm.debug(string.format(
    "native mapper total load pipeline timing: %.1fms",
    now_millis() - pipeline_started))
  return true
end

-- Convert GMCP/database room info to the mapper's stable TEXT UID convention.
-- Internal room-name spaces and case are intentionally preserved.
function mm.canonical_room_uid(info)
  if type(info) ~= "table" then return nil end
  local raw_uid = info.num
  if raw_uid == nil then raw_uid = info.uid end
  if raw_uid == nil then return nil end

  local uid = mm.strip_ansi(raw_uid):gsub("^%s+", ""):gsub("%s+$", "")
  if uid == "" then return nil end
  if uid:match("^nomap_.+") then return uid end

  local numeric = tonumber(uid)
  if not numeric then return nil end
  if numeric ~= -1 then return tostring(math.floor(numeric)) end

  local clean_name = mm.strip_ansi(info.name):gsub("^%s+", ""):gsub("%s+$", "")
  local clean_zone = mm.strip_ansi(info.zone or info.area):gsub("^%s+", ""):gsub("%s+$", "")
  if clean_name == "" then clean_name = "?" end
  if clean_zone == "" then clean_zone = "?" end
  return "nomap_" .. clean_name .. "_" .. clean_zone
end

function mm.current_room()
  local function legacy_room_value(info)
    local uid = mm.canonical_room_uid(info)
    if not uid then return nil end
    return tonumber(uid) or uid
  end

  if mm and mm.get_room_info then
    local room = legacy_room_value(mm.get_room_info())
    if room ~= nil then return room end
  end
  if gmcp and gmcp.Room and gmcp.Room.Info then
    local room = legacy_room_value(gmcp.Room.Info)
    if room ~= nil then return room end
  end
  if gmcp and gmcp.room and gmcp.room.info then
    return legacy_room_value(gmcp.room.info)
  end
  return nil
end

function mm.goto_room(target)
  target = tonumber(target)
  if not target then
    return false, "invalid room"
  end

  local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
  if not (nav and type(nav.xrt) == "function") then
    return false, "xrt requires mapper navigation module"
  end

  local ok, result, route_error = pcall(nav.xrt, tostring(target))
  if not ok then
    return false, "xrt failed: " .. tostring(result)
  end
  if result ~= true then
    return false, route_error or "xrt could not start a route to room " .. tostring(target)
  end
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

  if type(nav.syncExitLockVisual) == "function" then
    local visual_ok, visual_err = pcall(nav.syncExitLockVisual, room, dir)
    if not visual_ok then mm.debug("lockexit visual refresh failed: " .. tostring(visual_err)) end
  end

  mm.note(string.format("Set exit lock %s in room %s to %d.", dir, tostring(room), lockLevel))
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
  if type(nav.syncExitLockVisual) == "function" then
    local visual_ok, visual_err = pcall(nav.syncExitLockVisual, room, dir)
    if not visual_ok then mm.debug("unlockexit visual refresh failed: " .. tostring(visual_err)) end
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

  mm.note("Locked exits for room " .. tostring(room) .. ":")
  cecho("<gray>#   Command                        To             Lock<reset>\n")
  cecho("<gray>------------------------------------------------------------<reset>\n")
  for i, row in ipairs(rows) do
    local command = tostring(row.dir or "")
    local destination = tostring(row.touid or "")
    local destination_number = tonumber(destination)
    local level = tonumber(row.level) or 0
    cecho(string.format("<light_grey>%-3d %-30.30s <reset>", i, command))
    if destination_number and destination_number > 0 then
      echoLink(
        string.format("%-14s", "(" .. tostring(destination_number) .. ")"),
        [[mm.goto_room(]] .. tostring(destination_number) .. [[)]],
        "Go to destination room",
        true
      )
    else
      cecho(string.format("<light_grey>%-14.14s<reset>", "(" .. destination .. ")"))
    end
    cecho(string.format(" <light_grey>%d<reset>\n", level))
  end
  return true
end

function mm.resume()
  if not mm.state.last_target then
    return false, "no previous mapper target"
  end
  return mm.goto_room(mm.state.last_target)
end

local room_exit_direction_order = {"n", "s", "e", "w", "u", "d"}
local room_exit_direction_names = {
  n = "north", e = "east", s = "south", w = "west", u = "up", d = "down",
}
local room_exit_direction_aliases = {
  n = "n", north = "n",
  e = "e", east = "e",
  s = "s", south = "s",
  w = "w", west = "w",
  u = "u", up = "u",
  d = "d", down = "d",
}
local room_exit_reverse_direction = {
  n = "s", e = "w", s = "n", w = "e", u = "d", d = "u",
}
local room_exit_cardinal_sql = "'n','north','e','east','s','south','w','west','u','up','d','down'"

function mm.print_room_exits(room, opts)
  opts = opts or {}
  room = tonumber(room) or mm.current_room()
  if not room then return false, "current room unknown" end
  if type(room) ~= "number" then
    return false, "mapped exits are not available in unmapped rooms"
  end

  local room_rows, room_err = mm.query_mapper_db(string.format(
    "SELECT uid, name, area FROM rooms WHERE uid = %d LIMIT 1",
    room
  ))
  if not room_rows then return false, room_err end
  if not room_rows[1] then
    return false, string.format("room %s not found in mapper database", tostring(room))
  end

  local direct_rows, direct_err = mm.query_mapper_db(string.format([[
    SELECT lower(trim(exits.dir)) AS dir,
           exits.touid AS uid,
           COALESCE(rooms.name, '?') AS name,
           COALESCE(rooms.area, '') AS area,
           COALESCE(exits.level, 0) AS level
    FROM exits
    LEFT JOIN rooms ON rooms.uid = exits.touid
    WHERE exits.fromuid = %d
      AND lower(trim(exits.dir)) IN (%s)
    ORDER BY exits.dir, exits.touid
  ]], room, room_exit_cardinal_sql))
  if not direct_rows then return false, direct_err end

  local inferred_rows, inferred_err = mm.query_mapper_db(string.format([[
    SELECT lower(trim(exits.dir)) AS dir,
           exits.fromuid AS uid,
           COALESCE(rooms.name, '?') AS name,
           COALESCE(rooms.area, '') AS area
    FROM exits
    LEFT JOIN rooms ON rooms.uid = exits.fromuid
    WHERE exits.touid = %d
      AND exits.fromuid NOT IN ('*', '**')
      AND lower(trim(exits.dir)) IN (%s)
    ORDER BY exits.dir, exits.fromuid
  ]], room, room_exit_cardinal_sql))
  if not inferred_rows then return false, inferred_err end

  local exits_by_dir = {}
  local seen = {}
  local function add_exit(dir, row, inferred)
    local uid = tostring(row.uid or "")
    if uid == "" or uid == "-1" then return end
    local key = tostring(dir) .. "\001" .. uid
    if seen[key] then return end
    seen[key] = true
    exits_by_dir[dir] = exits_by_dir[dir] or {}
    table.insert(exits_by_dir[dir], {
      uid = uid,
      name = tostring(row.name or "?"),
      area = tostring(row.area or ""),
      level = tonumber(row.level) or 0,
      inferred = inferred == true,
    })
  end

  for _, row in ipairs(direct_rows) do
    local dir = room_exit_direction_aliases[tostring(row.dir or ""):lower()]
    if dir then add_exit(dir, row, false) end
  end

  for _, row in ipairs(inferred_rows) do
    local incoming = room_exit_direction_aliases[tostring(row.dir or ""):lower()]
    local inferred_dir = incoming and room_exit_reverse_direction[incoming] or nil
    if inferred_dir and not exits_by_dir[inferred_dir] then
      add_exit(inferred_dir, row, true)
    end
  end

  if opts.show_room ~= false then
    local info = room_rows[1]
    local area = tostring(info.area or "")
    local area_text = area ~= "" and (" / " .. area) or ""
    mm.note(string.format("Mapped exits from %s (%s)%s:", tostring(info.name or "?"), tostring(room), area_text))
  else
    mm.note("Mapped cardinal exits:")
  end

  for _, dir in ipairs(room_exit_direction_order) do
    local label = room_exit_direction_names[dir]
    local entries = exits_by_dir[dir] or {}
    if #entries == 0 then
      mm.note(string.format("  %-5s -> no mapped exit", label))
    else
      for index, entry in ipairs(entries) do
        local shown_label = index == 1 and label or ""
        local suffix = ""
        if entry.inferred then
          suffix = " [inferred from reverse exit; may be one-way]"
        elseif entry.level > 0 then
          suffix = entry.level >= 999 and " [locked: level 999]" or
            string.format(" [level %d]", entry.level)
        end
        mm.note(string.format(
          "  %-5s -> %s (%s)%s",
          shown_label,
          entry.name,
          entry.uid,
          suffix
        ))
      end
    end
  end
  return true
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

  local mode = tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  local explicit_room, explicit_value = mode:match("^(%d+)%s+(%a+)$")
  if explicit_value ~= "true" and explicit_value ~= "false" then
    explicit_room, explicit_value = nil, nil
  end
  local room
  if explicit_room then
    room = tonumber(explicit_room)
  else
    if mode == "" then
      mode = "toggle"
    end
    if mode ~= "on" and mode ~= "off" and mode ~= "toggle" then
      return false, string.format(
        "Usage: mapper %s [on|off|toggle] OR mapper %s <room_id> <true|false>",
        safe_flag, safe_flag
      )
    end

    room = mm.current_room()
    if not room then
      return false, "current room unknown"
    end
    if type(room) ~= "number" then
      return false, "room flags are not available in unmapped rooms"
    end
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
  if explicit_value then
    next_value = explicit_value == "true"
  elseif mode == "on" then
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
mm.room_notes_cache = mm.room_notes_cache or {}
mm.room_notes_cache_loaded = mm.room_notes_cache_loaded == true

function mm.invalidate_room_notes_cache()
  mm.room_notes_cache = {}
  mm.room_notes_cache_loaded = false
end

function mm.load_room_notes_cache()
  local rows, err
  if snd and snd.mapper and snd.mapper.db and type(snd.mapper.db.query) == "function" then
    rows = snd.mapper.db.query("SELECT uid, notes FROM bookmarks WHERE notes IS NOT NULL AND notes <> ''")
    if not rows then err = "persistent mapper database query failed" end
  end
  if not rows and type(mm.query_mapper_db) == "function" then
    rows, err = mm.query_mapper_db(
      "SELECT uid, notes FROM bookmarks WHERE notes IS NOT NULL AND notes <> ''",
      NOTES_DB_NAME)
  end
  if not rows then
    mm.room_notes_cache_loaded = false
    return false, err
  end

  local cache = {}
  for _, row in ipairs(rows) do
    local room_id = tonumber(row.uid)
    local note = tostring(row.notes or "")
    if room_id and note ~= "" then cache[room_id] = note end
  end
  mm.room_notes_cache = cache
  mm.room_notes_cache_loaded = true
  return true, cache
end

local function cache_room_note(room_id, note_text)
  if not mm.room_notes_cache_loaded then return end
  local rid = tonumber(room_id)
  if not rid then return end
  local note = tostring(note_text or "")
  mm.room_notes_cache[rid] = note ~= "" and note or nil
end

local function split_room_notes(note_text)
  local normalized = tostring(note_text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local notes = {}
  for line in (normalized .. "\n"):gmatch("(.-)\n") do
    if line:match("%S") then
      notes[#notes + 1] = line
    end
  end
  return notes
end

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

  local existing_note, read_err = mm.get_room_note(room)
  if existing_note == nil then
    return false, read_err or "could not read the existing room notes"
  end

  existing_note = tostring(existing_note)
  local combined_note = existing_note ~= "" and (existing_note .. "\n" .. note) or note
  local sql = string.format("INSERT OR REPLACE INTO bookmarks (uid, notes) VALUES (%d, %s)", room, mm.sql_escape(combined_note))
  local ok, err = mm.exec_mapper_db(sql, NOTES_DB_NAME)
  if not ok then
    return false, err
  end

  cache_room_note(room, combined_note)
  mm.note(string.format("Room note %s for %d.", existing_note ~= "" and "appended" or "saved", room))
  return true
end

function mm.delete_note(note_selector)
  local room = mm.current_room()
  if not room then
    return false, "current room unknown"
  end
  if type(room) ~= "number" then
    return false, "notes are not available in unmapped rooms"
  end

  local existing_note, read_err = mm.get_room_note(room)
  if existing_note == nil then
    return false, read_err or "could not read the existing room notes"
  end

  local notes = split_room_notes(existing_note)
  if #notes == 0 then
    return false, string.format("room %d has no saved notes", room)
  end

  local selector = tostring(note_selector or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if selector == "" and #notes > 1 then
    mm.note(string.format("Room %d has %d notes:", room, #notes))
    for index, note in ipairs(notes) do
      mm.note(string.format("  %d) %s", index, note))
    end
    mm.note("Use 'mapper delete note <number>' to remove one, or 'mapper delete note all' to remove every note.")
    return true
  end

  if selector:lower() == "all" then
    local ok, err = mm.exec_mapper_db(string.format("DELETE FROM bookmarks WHERE uid=%d", room), NOTES_DB_NAME)
    if not ok then
      return false, err
    end
    cache_room_note(room, "")
    mm.note(string.format("All room notes deleted for %d.", room))
    return true
  end

  if selector == "" then selector = "1" end
  if not selector:match("^%d+$") then
    return false, "Usage: mapper delete note <number|all>"
  end

  local note_index = tonumber(selector)
  if note_index < 1 or note_index > #notes then
    return false, string.format("note number must be between 1 and %d", #notes)
  end

  local removed_note = table.remove(notes, note_index)
  local sql
  if #notes == 0 then
    sql = string.format("DELETE FROM bookmarks WHERE uid=%d", room)
  else
    sql = string.format(
      "INSERT OR REPLACE INTO bookmarks (uid, notes) VALUES (%d, %s)",
      room,
      mm.sql_escape(table.concat(notes, "\n"))
    )
  end

  local ok, err = mm.exec_mapper_db(sql, NOTES_DB_NAME)
  if not ok then
    return false, err
  end

  cache_room_note(room, table.concat(notes, "\n"))
  mm.note(string.format("Room note %d deleted for %d: %s", note_index, room, removed_note))
  return true
end

function mm.get_room_note(room_id)
  local rid = tonumber(room_id)
  if not rid then
    return nil
  end

  if mm.room_notes_cache_loaded then
    return tostring(mm.room_notes_cache[rid] or "")
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

local MAPPER_SCHEMA_VERSION = 11
local MAPPER_CORE_TABLES = { "areas", "environments", "rooms", "exits" }
local MAPPER_REQUIRED_COLUMNS = {
  areas = { "uid", "name", "texture", "color", "flags" },
  environments = { "uid", "name", "color" },
  rooms = { "uid", "name", "area", "building", "terrain", "info", "notes", "x", "y", "z", "norecall", "noportal", "ignore_exits_mismatch" },
  -- chaos is a managed extension and is added during automatic migration.
  exits = { "dir", "fromuid", "touid", "level" },
}
local MAPPER_LEGACY_IDENTITY_COLUMNS = {
  areas = { "uid", "name" },
  environments = { "uid", "name" },
  rooms = { "uid", "name", "area" },
  exits = { "dir", "fromuid", "touid" },
}
local MAPPER_ADDITIVE_COLUMNS = {
  { table_name = "areas", column_name = "texture", definition = "texture TEXT" },
  { table_name = "areas", column_name = "color", definition = "color TEXT" },
  { table_name = "areas", column_name = "flags", definition = "flags TEXT NOT NULL DEFAULT ''" },
  { table_name = "environments", column_name = "color", definition = "color INTEGER" },
  { table_name = "rooms", column_name = "building", definition = "building TEXT" },
  { table_name = "rooms", column_name = "terrain", definition = "terrain TEXT" },
  { table_name = "rooms", column_name = "info", definition = "info TEXT" },
  { table_name = "rooms", column_name = "notes", definition = "notes TEXT" },
  { table_name = "rooms", column_name = "x", definition = "x INTEGER" },
  { table_name = "rooms", column_name = "y", definition = "y INTEGER" },
  { table_name = "rooms", column_name = "z", definition = "z INTEGER" },
  { table_name = "rooms", column_name = "norecall", definition = "norecall INTEGER" },
  { table_name = "rooms", column_name = "noportal", definition = "noportal INTEGER" },
  { table_name = "rooms", column_name = "ignore_exits_mismatch", definition = "ignore_exits_mismatch INTEGER NOT NULL DEFAULT 0" },
  { table_name = "exits", column_name = "level", definition = "level STRING NOT NULL DEFAULT '0'" },
  { table_name = "exits", column_name = "chaos", definition = "chaos TEXT NOT NULL DEFAULT 'no'" },
}
local MAPPER_MANAGED_TABLES = {
  "areas", "environments", "rooms", "exits", "random_cexits",
  "cexit_key_alternates", "cexit_key_observations", "bookmarks",
  "storage", "terrain", "mapper_area_bookmarks", "rooms_lookup",
}
local MAPPER_SCHEMA_SQL = {
  [[CREATE TABLE IF NOT EXISTS areas(
      uid TEXT NOT NULL,
      name TEXT,
      texture TEXT,
      color TEXT,
      flags TEXT NOT NULL DEFAULT '',
      PRIMARY KEY(uid))]],
  [[CREATE TABLE IF NOT EXISTS environments(
      uid TEXT NOT NULL,
      name TEXT,
      color INTEGER,
      PRIMARY KEY(uid))]],
  [[CREATE TABLE IF NOT EXISTS rooms(
      uid TEXT NOT NULL,
      name TEXT,
      area TEXT,
      building TEXT,
      terrain TEXT,
      info TEXT,
      notes TEXT,
      x INTEGER,
      y INTEGER,
      z INTEGER,
      norecall INTEGER,
      noportal INTEGER,
      ignore_exits_mismatch INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(uid))]],
  [[CREATE TABLE IF NOT EXISTS exits(
      dir TEXT NOT NULL,
      fromuid TEXT NOT NULL,
      touid TEXT NOT NULL,
      level STRING NOT NULL DEFAULT '0',
      chaos TEXT NOT NULL DEFAULT 'no',
      PRIMARY KEY(fromuid, dir))]],
  [[CREATE TABLE IF NOT EXISTS random_cexits(
      dir TEXT NOT NULL,
      fromuid TEXT NOT NULL,
      touid TEXT NOT NULL,
      level STRING NOT NULL DEFAULT '0',
      PRIMARY KEY(fromuid, dir, touid))]],
  [[CREATE TABLE IF NOT EXISTS cexit_key_alternates(
      fromuid TEXT NOT NULL,
      dir TEXT NOT NULL,
      touid TEXT NOT NULL,
      key_name TEXT NOT NULL,
      key_keywords TEXT NOT NULL DEFAULT '',
      alternate_command TEXT NOT NULL,
      PRIMARY KEY(fromuid, dir))]],
  [[CREATE TABLE IF NOT EXISTS cexit_key_observations(
      fromuid TEXT NOT NULL,
      dir TEXT NOT NULL,
      touid TEXT NOT NULL,
      observed_key TEXT NOT NULL,
      observed_key_normalized TEXT NOT NULL,
      resolved_key_name TEXT,
      door_direction TEXT,
      seen_count INTEGER NOT NULL DEFAULT 0,
      first_seen_at INTEGER NOT NULL,
      last_seen_at INTEGER NOT NULL,
      PRIMARY KEY(fromuid, dir, touid, observed_key_normalized))]],
  [[CREATE TABLE IF NOT EXISTS bookmarks(
      uid TEXT NOT NULL,
      notes TEXT,
      PRIMARY KEY(uid))]],
  [[CREATE TABLE IF NOT EXISTS storage(
      name TEXT NOT NULL,
      data TEXT NOT NULL,
      PRIMARY KEY(name))]],
  [[CREATE TABLE IF NOT EXISTS terrain(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      color INTEGER,
      date_added DATE,
      UNIQUE(name))]],
  [[CREATE TABLE IF NOT EXISTS mapper_area_bookmarks(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      room_uid TEXT NOT NULL UNIQUE,
      label TEXT,
      is_permanent INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL DEFAULT 0,
      deleted_at INTEGER)]],
  [[CREATE VIRTUAL TABLE IF NOT EXISTS rooms_lookup USING FTS3(uid, name)]],
  [[CREATE INDEX IF NOT EXISTS exits_touid_index ON exits(touid)]],
  [[CREATE INDEX IF NOT EXISTS random_cexits_touid_index ON random_cexits(touid)]],
  [[CREATE INDEX IF NOT EXISTS rooms_area_index ON rooms(area)]],
  [[CREATE VIEW IF NOT EXISTS camere AS SELECT * FROM rooms]],
}

local function trim_db_path(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function mm.resolve_mapper_db(path)
  local p = trim_db_path(path ~= nil and path or (mm.state and mm.state.map_db))
  if p == "" then return nil end
  if p:sub(1, 1) == "/" or p:match("^%a:[/\\]") then
    return p
  end
  return getMudletHomeDir() .. "/" .. p
end

local function close_cursor(cursor)
  local cursor_type = type(cursor)
  if (cursor_type == "userdata" or cursor_type == "table") and type(cursor.close) == "function" then
    pcall(function() cursor:close() end)
  end
end

local function execute_statement(conn, sql)
  local result, err = conn:execute(sql)
  if not result then return false, tostring(err) end
  close_cursor(result)
  return true
end

local function fetch_scalar(conn, sql)
  local cursor, err = conn:execute(sql)
  if not cursor then return nil, tostring(err) end
  local cursor_type = type(cursor)
  if (cursor_type ~= "userdata" and cursor_type ~= "table") or type(cursor.fetch) ~= "function" then
    return cursor
  end
  local row = cursor:fetch({}, "n")
  close_cursor(cursor)
  return row and row[1] or nil
end

local function mapper_table_set(conn)
  local cursor, err = conn:execute("SELECT name FROM sqlite_master WHERE type='table'")
  if not cursor then return nil, tostring(err) end
  local found = {}
  local row = cursor:fetch({}, "a")
  while row do
    found[tostring(row.name)] = true
    row = cursor:fetch(row, "a")
  end
  close_cursor(cursor)
  return found
end

local function mapper_column_set(conn, table_name)
  local safe_name = tostring(table_name):gsub("'", "''")
  local cursor, err = conn:execute("PRAGMA table_info('" .. safe_name .. "')")
  if not cursor then return nil, tostring(err) end
  local found = {}
  local row = cursor:fetch({}, "a")
  while row do
    found[tostring(row.name)] = true
    row = cursor:fetch(row, "a")
  end
  close_cursor(cursor)
  return found
end

local function sql_quote(value)
  return "'" .. tostring(value or ""):gsub("'", "''") .. "'"
end

local function next_mapper_migration_backup_path(source)
  local dir = backup_dir_path()
  if not mm.ensure_dir(dir) then
    return nil, "unable to create backup directory: " .. tostring(dir)
  end

  local base = tostring(source or "Aardwolf.db"):match("([^/\\]+)$") or "Aardwolf.db"
  base = base:gsub("[/\\:*?\"<>|]", "_")
  local stamp = os.date("!%Y%m%d_%H%M%S")
  local path = string.format("%s/%s.pre-migration.%s.bak", dir, base, stamp)
  local suffix = 1
  while mm.path_exists(path) do
    path = string.format("%s/%s.pre-migration.%s_%d.bak", dir, base, stamp, suffix)
    suffix = suffix + 1
  end
  return path
end

local function create_mapper_migration_backup(conn, source)
  local backup_path, path_err = next_mapper_migration_backup_path(source)
  if not backup_path then return nil, path_err end
  local ok, err = execute_statement(conn, "VACUUM INTO " .. sql_quote(backup_path))
  if not ok then
    return nil, "transactional SQLite backup failed: " .. tostring(err)
  end
  return backup_path
end

local function mapper_migration_plan(conn)
  local tables, tables_err = mapper_table_set(conn)
  if not tables then return nil, tables_err end

  local integrity, integrity_err = fetch_scalar(conn, "PRAGMA quick_check")
  if integrity == nil then
    return nil, "could not verify SQLite integrity: " .. tostring(integrity_err or "unknown error")
  end
  if tostring(integrity) ~= "ok" then
    return nil, "SQLite quick_check: " .. tostring(integrity)
  end

  local missing_core = {}
  for _, table_name in ipairs(MAPPER_CORE_TABLES) do
    if not tables[table_name] then table.insert(missing_core, table_name) end
  end
  if #missing_core > 0 then
    return nil, "unrecognized mapper schema; missing core tables: " .. table.concat(missing_core, ", ")
  end

  local columns_by_table = {}
  local missing_identity = {}
  for table_name, required_columns in pairs(MAPPER_LEGACY_IDENTITY_COLUMNS) do
    local columns, columns_err = mapper_column_set(conn, table_name)
    if not columns then return nil, columns_err end
    columns_by_table[table_name] = columns
    for _, column_name in ipairs(required_columns) do
      if not columns[column_name] then
        table.insert(missing_identity, table_name .. "." .. column_name)
      end
    end
  end
  if #missing_identity > 0 then
    return nil, "unrecognized mapper schema; missing identity columns: " .. table.concat(missing_identity, ", ")
  end

  local plan = {
    from_version = tonumber(fetch_scalar(conn, "PRAGMA user_version")) or 0,
    additions = {},
    missing_managed_tables = {},
    rooms_lookup_missing = not tables.rooms_lookup,
  }
  for _, addition in ipairs(MAPPER_ADDITIVE_COLUMNS) do
    local columns = columns_by_table[addition.table_name]
    if not columns then
      columns = mapper_column_set(conn, addition.table_name)
      columns_by_table[addition.table_name] = columns
    end
    if not columns or not columns[addition.column_name] then
      table.insert(plan.additions, addition)
    end
  end
  for _, table_name in ipairs(MAPPER_MANAGED_TABLES) do
    if not tables[table_name] then
      table.insert(plan.missing_managed_tables, table_name)
    end
  end
  plan.needed = plan.from_version < MAPPER_SCHEMA_VERSION
    or #plan.additions > 0
    or #plan.missing_managed_tables > 0
  return plan
end

local function validate_mapper_connection(conn)
  local tables, tables_err = mapper_table_set(conn)
  if not tables then return false, tables_err end
  for _, table_name in ipairs(MAPPER_CORE_TABLES) do
    if not tables[table_name] then
      return false, "missing core table after migration: " .. table_name
    end
  end
  for table_name, required_columns in pairs(MAPPER_REQUIRED_COLUMNS) do
    local columns, columns_err = mapper_column_set(conn, table_name)
    if not columns then return false, columns_err end
    for _, column_name in ipairs(required_columns) do
      if not columns[column_name] then
        return false, "missing core column after migration: " .. table_name .. "." .. column_name
      end
    end
  end
  local integrity, integrity_err = fetch_scalar(conn, "PRAGMA quick_check")
  if integrity == nil then return false, tostring(integrity_err or "SQLite quick_check failed") end
  if tostring(integrity) ~= "ok" then return false, "SQLite quick_check: " .. tostring(integrity) end
  return true
end

local function migrate_mapper_database(conn, source, plan)
  local backup_path, backup_err = create_mapper_migration_backup(conn, source)
  if not backup_path then
    return false, "automatic migration was not started because the backup failed: " .. tostring(backup_err)
  end

  local ok, err = execute_statement(conn, "BEGIN IMMEDIATE")
  if ok then
    for _, addition in ipairs(plan.additions) do
      ok, err = execute_statement(conn, string.format(
        "ALTER TABLE %s ADD COLUMN %s",
        addition.table_name,
        addition.definition
      ))
      if not ok then break end
    end
  end
  if ok then
    for _, sql in ipairs(MAPPER_SCHEMA_SQL) do
      ok, err = execute_statement(conn, sql)
      if not ok then break end
    end
  end
  if ok and plan.rooms_lookup_missing then
    ok, err = execute_statement(conn,
      "INSERT INTO rooms_lookup(uid, name) SELECT uid, COALESCE(name, '') FROM rooms")
  end
  if ok then
    ok, err = execute_statement(conn, "PRAGMA user_version = " .. tostring(MAPPER_SCHEMA_VERSION))
  end
  if ok then
    ok, err = validate_mapper_connection(conn)
  end
  if ok then
    local committed, commit_err = execute_statement(conn, "COMMIT")
    if not committed then
      ok, err = false, commit_err
      pcall(function() conn:execute("ROLLBACK") end)
    end
  else
    pcall(function() conn:execute("ROLLBACK") end)
  end

  if not ok then
    return false, "automatic mapper migration failed and was rolled back: " .. tostring(err) ..
      ". Pre-migration backup: " .. tostring(backup_path)
  end
  return true, backup_path
end

function mm.inspect_mapper_database(path)
  local configured = trim_db_path(path ~= nil and path or (mm.state and mm.state.map_db))
  local source = mm.resolve_mapper_db(configured)
  local status = {
    configured = configured,
    path = source,
    exists = source and mm.path_exists(source) or false,
    expected_schema = MAPPER_SCHEMA_VERSION,
  }
  if not status.exists then
    status.state = "NOT FOUND"
    return status
  end
  if not mm.looks_like_sqlite(source) then
    status.state = "FOUND BUT INVALID"
    status.error = "file is not a SQLite database; existing file was left untouched"
    return status
  end

  local env, conn, open_err = open_mapper_db(source)
  if not conn then
    status.state = "FOUND BUT CANNOT OPEN"
    status.error = open_err
    return status
  end

  local tables, tables_err = mapper_table_set(conn)
  if not tables then
    status.state = "FOUND BUT INVALID"
    status.error = tables_err
    conn:close(); env:close()
    return status
  end

  status.missing_tables = {}
  for _, name in ipairs(MAPPER_CORE_TABLES) do
    if not tables[name] then table.insert(status.missing_tables, name) end
  end
  status.missing_columns = {}
  for table_name, required_columns in pairs(MAPPER_REQUIRED_COLUMNS) do
    if tables[table_name] then
      local columns, columns_err = mapper_column_set(conn, table_name)
      if not columns then
        table.insert(status.missing_columns, table_name .. ".? (" .. tostring(columns_err) .. ")")
      else
        for _, column_name in ipairs(required_columns) do
          if not columns[column_name] then
            table.insert(status.missing_columns, table_name .. "." .. column_name)
          end
        end
      end
    end
  end
  status.schema_version = tonumber(fetch_scalar(conn, "PRAGMA user_version")) or 0
  local integrity, integrity_err = fetch_scalar(conn, "PRAGMA quick_check")
  status.integrity = tostring(integrity or "unknown")
  status.integrity_error = integrity == nil and integrity_err or nil
  if tables.rooms then status.rooms = tonumber(fetch_scalar(conn, "SELECT COUNT(*) FROM rooms")) or 0 end
  if tables.exits then status.exits = tonumber(fetch_scalar(conn, "SELECT COUNT(*) FROM exits")) or 0 end
  conn:close(); env:close()

  if #status.missing_tables > 0 then
    status.state = "FOUND BUT INVALID"
    status.error = "missing core tables: " .. table.concat(status.missing_tables, ", ")
  elseif #status.missing_columns > 0 then
    status.state = "FOUND BUT INVALID"
    status.error = "missing core columns: " .. table.concat(status.missing_columns, ", ")
  elseif status.integrity_error then
    status.state = "FOUND BUT INVALID"
    status.error = "could not verify SQLite integrity: " .. tostring(status.integrity_error)
  elseif status.integrity ~= "ok" then
    status.state = "FOUND BUT INVALID"
    status.error = "SQLite quick_check: " .. status.integrity
  else
    status.state = "FOUND"
  end
  return status
end

-- Create a complete empty database when no file exists. Recognized legacy
-- mapper schemas are backed up and migrated transactionally; corrupt,
-- incomplete, and unrelated SQLite files remain untouched.
function mm.ensure_mapper_database(path)
  local source = mm.resolve_mapper_db(path)
  if not source then return false, "mapper database path is empty" end

  if mm.path_exists(source) then
    if not mm.looks_like_sqlite(source) then
      return false, "existing mapper database was left untouched: file is not a SQLite database"
    end
    local env, conn, open_err = open_mapper_db(source)
    if not conn then
      return false, "existing mapper database was left untouched: " .. tostring(open_err)
    end
    local plan, plan_err = mapper_migration_plan(conn)
    if not plan then
      conn:close(); env:close()
      return false, "existing mapper database was left untouched: " .. tostring(plan_err)
    end

    local migrated = false
    local backup_path = nil
    if plan.needed then
      local migration_ok, migration_result = migrate_mapper_database(conn, source, plan)
      if not migration_ok then
        conn:close(); env:close()
        return false, tostring(migration_result)
      end
      migrated = true
      backup_path = migration_result
    end
    conn:close(); env:close()

    local existing = mm.inspect_mapper_database(path)
    if existing.state ~= "FOUND" then
      return false, "mapper database did not validate after initialization: " .. tostring(existing.error or existing.state)
    end
    existing.migrated = migrated
    existing.migration_backup = backup_path
    existing.previous_schema_version = plan.from_version
    return true, existing
  end

  local env, conn, open_err = open_mapper_db(source)
  if not conn then
    return false, "could not create mapper database at " .. source .. ": " .. tostring(open_err)
  end

  local ok, err = execute_statement(conn, "BEGIN IMMEDIATE")
  if ok then
    for _, sql in ipairs(MAPPER_SCHEMA_SQL) do
      ok, err = execute_statement(conn, sql)
      if not ok then break end
    end
  end
  if ok then
    ok, err = execute_statement(conn, "PRAGMA user_version = " .. tostring(MAPPER_SCHEMA_VERSION))
  end
  if ok then
    local committed, commit_err = execute_statement(conn, "COMMIT")
    if not committed then
      ok, err = false, commit_err
      pcall(function() conn:execute("ROLLBACK") end)
    end
  else
    pcall(function() conn:execute("ROLLBACK") end)
  end
  conn:close(); env:close()

  if not ok then
    return false, "new mapper database creation failed at " .. source .. ": " .. tostring(err) ..
      ". The file was not deleted or replaced."
  end

  local created = mm.inspect_mapper_database(path)
  if created.state ~= "FOUND" then
    return false, "new mapper database did not validate: " .. tostring(created.error or created.state)
  end
  created.created = true
  return true, created
end

function mm.print_mapper_database_status()
  local configured = trim_db_path(mm.state and mm.state.map_db)
  local status = mm.inspect_mapper_database(configured)
  mm.note("Database required default filename: Aardwolf.db")
  mm.note("Database configured value: " .. tostring(configured ~= "" and configured or "Aardwolf.db"))
  mm.note("Database resolved path: " .. tostring(status.path))
  if status.state ~= "FOUND" then
    mm.warn("Database status: " .. tostring(status.state) ..
      (status.error and (" (" .. tostring(status.error) .. ")") or ""))
    return false, status
  end
  mm.note("Database status: FOUND and opened successfully")
  mm.note(string.format("Database schema: %d (expected %d)", status.schema_version or 0, status.expected_schema or 0))
  mm.note("Database integrity: " .. tostring(status.integrity))
  mm.note(string.format("Database contents: %d rooms, %d exits", status.rooms or 0, status.exits or 0))
  if (status.rooms or 0) == 0 and (status.exits or 0) == 0 then
    mm.warn("Database classification: EMPTY. Replace it manually with the supplied populated Aardwolf.db if you want preloaded map data.")
  end
  return true, status
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

mm.ui = mm.ui or {}

function mm.ui.format_location_title(area_name, room_name, room_id)
  local function clean_label(value)
    return mm.strip_ansi(value):gsub("^%s+", ""):gsub("%s+$", "")
  end

  local area_label = clean_label(area_name)
  local room_label = clean_label(room_name)
  local id_label = clean_label(room_id)

  if room_label == "" then room_label = "Unknown room" end
  if id_label ~= "" then room_label = string.format("%s (%s)", room_label, id_label) end
  if area_label ~= "" then return string.format("%s / %s", area_label, room_label) end
  return room_label
end

function mm.query_mapper_db(sql, db_path)
  local source = mm.resolve_mapper_db(db_path ~= nil and db_path or mm.state.map_db)
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
  local source = mm.resolve_mapper_db(db_path ~= nil and db_path or mm.state.map_db)
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

function mm.ensure_random_cexits_table()
  local ok, err = mm.exec_mapper_db([[
    CREATE TABLE IF NOT EXISTS random_cexits(
      dir TEXT NOT NULL,
      fromuid TEXT NOT NULL,
      touid TEXT NOT NULL,
      level STRING NOT NULL DEFAULT '0',
      PRIMARY KEY(fromuid, dir, touid))
  ]])
  if not ok then return false, err end

  return mm.exec_mapper_db(
    "CREATE INDEX IF NOT EXISTS random_cexits_touid_index ON random_cexits(touid)"
  )
end

function mm.ensure_cexit_key_alternates_table()
  local ok, err = mm.exec_mapper_db([[
    CREATE TABLE IF NOT EXISTS cexit_key_alternates(
      fromuid TEXT NOT NULL,
      dir TEXT NOT NULL,
      touid TEXT NOT NULL,
      key_name TEXT NOT NULL,
      key_keywords TEXT NOT NULL DEFAULT '',
      alternate_command TEXT NOT NULL,
      PRIMARY KEY(fromuid, dir))
  ]])
  if not ok then return false, err end

  local columns, columns_err = mm.query_mapper_db("PRAGMA table_info('cexit_key_alternates')")
  if not columns then return false, columns_err end
  local has_key_keywords = false
  for _, column in ipairs(columns) do
    if tostring(column.name or ""):lower() == "key_keywords" then
      has_key_keywords = true
      break
    end
  end
  if not has_key_keywords then
    local altered, alter_err = mm.exec_mapper_db(
      "ALTER TABLE cexit_key_alternates ADD COLUMN key_keywords TEXT NOT NULL DEFAULT ''"
    )
    if not altered then return false, alter_err end
  end

  local indexed, index_err = mm.exec_mapper_db(
    "CREATE INDEX IF NOT EXISTS cexit_key_alternates_touid_index ON cexit_key_alternates(touid)"
  )
  if not indexed then return false, index_err end

  local orphan_rows, orphan_err = mm.query_mapper_db([[
    SELECT COUNT(*) AS cnt
    FROM cexit_key_alternates AS cka
    WHERE NOT EXISTS (
      SELECT 1 FROM exits
      WHERE exits.fromuid = cka.fromuid
        AND exits.dir = cka.dir
        AND exits.touid = cka.touid)
  ]])
  if not orphan_rows then return false, orphan_err end
  local orphan_count = tonumber(orphan_rows[1] and orphan_rows[1].cnt) or 0
  if orphan_count > 0 then
    local cleaned, cleanup_err = mm.exec_mapper_db([[
      DELETE FROM cexit_key_alternates
      WHERE NOT EXISTS (
        SELECT 1 FROM exits
        WHERE exits.fromuid = cexit_key_alternates.fromuid
          AND exits.dir = cexit_key_alternates.dir
          AND exits.touid = cexit_key_alternates.touid)
    ]])
    if not cleaned then return false, cleanup_err end
    mm.warn(string.format("Removed %d orphaned conditional cexit record%s.",
      orphan_count, orphan_count == 1 and "" or "s"))
  end
  return true
end

function mm.ensure_cexit_key_observations_table()
  local ok, err = mm.exec_mapper_db([[
    CREATE TABLE IF NOT EXISTS cexit_key_observations(
      fromuid TEXT NOT NULL,
      dir TEXT NOT NULL,
      touid TEXT NOT NULL,
      observed_key TEXT NOT NULL,
      observed_key_normalized TEXT NOT NULL,
      resolved_key_name TEXT,
      door_direction TEXT,
      seen_count INTEGER NOT NULL DEFAULT 0,
      first_seen_at INTEGER NOT NULL,
      last_seen_at INTEGER NOT NULL,
      PRIMARY KEY(fromuid, dir, touid, observed_key_normalized))
  ]])
  if not ok then return false, err end

  local indexed, index_err = mm.exec_mapper_db(
    "CREATE INDEX IF NOT EXISTS cexit_key_observations_touid_index ON cexit_key_observations(touid)"
  )
  if not indexed then return false, index_err end

  local last_seen_indexed, last_seen_index_err = mm.exec_mapper_db(
    "CREATE INDEX IF NOT EXISTS cexit_key_observations_last_seen_index ON cexit_key_observations(last_seen_at)"
  )
  if not last_seen_indexed then return false, last_seen_index_err end

  return mm.exec_mapper_db([[
    DELETE FROM cexit_key_observations
    WHERE NOT EXISTS (
      SELECT 1 FROM exits
      WHERE exits.fromuid = cexit_key_observations.fromuid
        AND exits.dir = cexit_key_observations.dir
        AND exits.touid = cexit_key_observations.touid)
  ]])
end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_observed_key(value)
  local cleaned = tostring(value or "")
  if mm.strip_ansi then cleaned = mm.strip_ansi(cleaned) end
  return cleaned:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):lower()
end

local function normalize_keyword_signature(value)
  local cleaned = tostring(value or "")
  if mm.strip_ansi then cleaned = mm.strip_ansi(cleaned) end
  return cleaned:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function without_leading_article(value)
  for _, article in ipairs({"a ", "an ", "the "}) do
    if value:sub(1, #article) == article then return value:sub(#article + 1) end
  end
  return value
end

local function delete_cexit_key_observation_record(row)
  return mm.exec_mapper_db(string.format(
    "DELETE FROM cexit_key_observations WHERE fromuid=%s AND dir=%s AND touid=%s AND observed_key_normalized=%s",
    mm.sql_escape(row.fromuid), mm.sql_escape(row.dir), mm.sql_escape(row.touid),
    mm.sql_escape(row.observed_key_normalized)
  ))
end

local function configured_cexit_key(fromuid, dir, touid)
  local rows, err = mm.query_mapper_db(string.format(
    "SELECT key_name, key_keywords FROM cexit_key_alternates WHERE fromuid=%s AND dir=%s AND touid=%s LIMIT 1",
    mm.sql_escape(fromuid), mm.sql_escape(dir), mm.sql_escape(touid)
  ))
  if not rows then return nil, err end
  return rows[1] or {}, nil
end

local function remove_configured_cexit_key_observations(fromuid, dir, touid)
  local ensured, ensure_err = mm.ensure_cexit_key_observations_table()
  if not ensured then return false, ensure_err end
  local rows, query_err = mm.query_mapper_db(string.format(
    "SELECT fromuid, dir, touid, observed_key, observed_key_normalized, resolved_key_name FROM cexit_key_observations WHERE fromuid=%s AND dir=%s AND touid=%s",
    mm.sql_escape(fromuid), mm.sql_escape(dir), mm.sql_escape(touid)
  ))
  if not rows then return false, query_err end

  local removed = #rows
  if removed > 0 then
    local deleted, delete_err = mm.exec_mapper_db(string.format(
      "DELETE FROM cexit_key_observations WHERE fromuid=%s AND dir=%s AND touid=%s",
      mm.sql_escape(fromuid), mm.sql_escape(dir), mm.sql_escape(touid)
    ))
    if not deleted then return false, delete_err end
  end
  if removed > 0 then
    mm.runtime.cexit_key_observation_last_rows = {}
  end
  return true, removed
end

local function normalize_uid(value)
  if value == nil then return nil end
  local n = tonumber(value)
  if n then return tostring(math.floor(n)) end
  local s = trim(value)
  if s == "" then return nil end
  return s
end

local function is_cardinal_cexit_dir(value)
  local dir = trim(value):lower()
  return dir == "n" or dir == "s" or dir == "e" or dir == "w" or dir == "u" or dir == "d"
    or dir == "north" or dir == "south" or dir == "east" or dir == "west"
    or dir == "up" or dir == "down"
end

local function selected_cexit_row(index)
  local n = tonumber(index)
  if not n then return nil, "cexit row must be a number from the last mapper cexits list" end
  local row = (mm.runtime.cexit_last_rows or {})[n]
  if not row then
    return nil, "cexit row is not available; run 'mapper cexits thisroom' first, then use the row number shown"
  end
  local fromuid = trim(row.uid or row.fromuid)
  local dir = trim(row.dir)
  local touid = trim(row.touid)
  if fromuid == "" or dir == "" or touid == "" then
    return nil, "selected cexit is missing its source, command, or destination"
  end
  return row, nil, n, fromuid, dir, touid
end

local function dinv_api_ready()
  local api = _G.DINV and _G.DINV.api
  if not api then return nil, "DINV API is unavailable" end
  if type(api.isReady) == "function" then
    local ready_ok, ready = pcall(api.isReady)
    if not ready_ok or ready ~= true then return nil, "DINV is not ready" end
  end
  return api, nil
end

function mm.check_dinv_key_keywords(key_keywords)
  key_keywords = normalize_keyword_signature(key_keywords)
  if key_keywords == "" then return nil, {reason = "key keyword identity is empty"} end

  local api, api_err = dinv_api_ready()
  if not api or type(api.getKeys) ~= "function" then
    return nil, {reason = api_err or "DINV getKeys API is unavailable"}
  end
  if type(api.getStatus) == "function" then
    local status_ok, status = pcall(api.getStatus, {})
    if not status_ok or type(status) ~= "table" or status.ok ~= true then
      return nil, {reason = "DINV status is unavailable"}
    end
    if status.buildInProgress == true or status.refreshInProgress == true then
      return nil, {reason = "DINV inventory refresh is in progress"}
    end
  end

  local ok, result = pcall(api.getKeys, {
    source = "live",
    includeIgnored = true,
    exactKeywords = key_keywords,
    fields = {"id", "name", "normalizedName", "keywords", "identifyLevel", "type", "flags", "location", "container", "worn"},
  })
  if not ok or type(result) ~= "table" or result.ok ~= true then
    return nil, {
      reason = type(result) == "table" and tostring(result.message or result.code or "DINV key query failed")
        or tostring(result),
    }
  end
  if result.keyDefinition ~= "isKeyOrTypeKey"
      or result.exactKeywordsApplied ~= true
      or result.keywordDefinition ~= "exactFullIdentifyTokenSet" then
    return nil, {reason = "DINV getKeys API does not support exact full-identify keyword queries"}
  end

  local items = type(result.items) == "table" and result.items or {}
  local count = tonumber(result.total) or tonumber(result.count) or #items
  local ids, locations = {}, {}
  for _, item in ipairs(items) do
    table.insert(ids, tostring(item.id or "?"))
    table.insert(locations, tostring(item.location or item.worn or item.container or "unknown"))
  end
  return count > 0, {
    count = count,
    items = items,
    ids = ids,
    locations = locations,
    keyword_signature = result.exactKeywords,
  }
end

local function note_dinv_key_check(key_keywords)
  local exists, details = mm.check_dinv_key_keywords(key_keywords)
  details = details or {}
  if exists == true then
    mm.note(string.format(
      "DINV currently has %d matching key%s: %s.",
      tonumber(details.count) or 1,
      tonumber(details.count) == 1 and "" or "s",
      key_keywords
    ))
  elseif exists == false then
    mm.note("DINV does not currently have a matching key; the regular cexit will be used.")
  else
    mm.warn("DINV could not verify the key keywords: " .. tostring(details.reason or "unknown error"))
  end
  return exists, details
end

local function has_exact_flag(flags, wanted)
  wanted = tostring(wanted or ""):lower()
  for token in tostring(flags or ""):lower():gmatch("[^,%s]+") do
    if token == wanted then return true end
  end
  return false
end

local function is_dinv_key_item(item)
  return tostring(item and item.type or ""):lower() == "key"
    or has_exact_flag(item and item.flags, "iskey")
end

local function get_dinv_item_by_id(obj_id)
  obj_id = trim(obj_id)
  if not obj_id:match("^%d+$") then return nil, "key object id must be numeric" end
  local api, api_err = dinv_api_ready()
  if not api or type(api.getItem) ~= "function" then
    return nil, api_err or "DINV getItem API is unavailable"
  end
  local ok, result = pcall(api.getItem, obj_id, {
    source = "live",
    includeIgnored = true,
    fields = {"id", "name", "normalizedName", "keywords", "identifyLevel", "type", "flags", "location", "container", "worn"},
  })
  if not ok or type(result) ~= "table" or result.ok ~= true or type(result.item) ~= "table" then
    return nil, type(result) == "table" and tostring(result.message or result.code or "DINV item query failed")
      or tostring(result)
  end
  return result.item, nil
end

function mm.on_dinv_item_observed(event_name, obj_id)
  local id = trim(obj_id)
  if id == "" and trim(event_name):match("^%d+$") then id = trim(event_name) end
  if not id:match("^%d+$") then return false end

  mm.runtime = mm.runtime or {}
  mm.runtime.cexitif_name_identify_ids = mm.runtime.cexitif_name_identify_ids or {}
  if mm.runtime.cexitif_name_identify_ids[id] then return false end

  local api, api_err = dinv_api_ready()
  if not api then
    mm.debug("CEXITIF KEY WATCH DEBUG: DINV unavailable: " .. tostring(api_err))
    return false
  end
  if type(api.getStatus) == "function" then
    local status_ok, status = pcall(api.getStatus, {})
    if not status_ok or type(status) ~= "table" or status.ok ~= true then return false end
    if status.refreshInProgress == true
        or (status.buildInProgress == true and status.targetedIdentifyInProgress ~= true) then
      return false
    end
  end

  local item, item_err = get_dinv_item_by_id(id)
  if not item then
    mm.debug("CEXITIF KEY WATCH DEBUG: item lookup failed id=" .. id
      .. " reason=" .. tostring(item_err))
    return false
  end
  if tostring(item.identifyLevel or ""):lower() == "full" then return false end
  local item_name_source = trim(item.normalizedName)
  if item_name_source == "" then item_name_source = item.name end
  local item_name = normalize_observed_key(item_name_source)
  if item_name == "" then return false end

  local rows, query_err = mm.query_mapper_db(
    "SELECT DISTINCT key_name FROM cexit_key_alternates WHERE trim(key_name) <> ''"
  )
  if not rows then
    mm.debug("CEXITIF KEY WATCH DEBUG: configured-name query failed: " .. tostring(query_err))
    return false
  end
  local watched = false
  for _, row in ipairs(rows) do
    if normalize_observed_key(row.key_name) == item_name then
      watched = true
      break
    end
  end
  if not watched then return false end

  local actions = _G.DINV and _G.DINV.actions
  if not actions or type(actions.identify) ~= "function" then
    mm.debug("CEXITIF KEY WATCH DEBUG: targeted identify action unavailable")
    return false
  end
  mm.runtime.cexitif_name_identify_ids[id] = true
  local action_ok, result = pcall(actions.identify, id, {source = "Mapper configured key name"})
  if not action_ok or type(result) ~= "table" or result.ok ~= true then
    mm.runtime.cexitif_name_identify_ids[id] = nil
    mm.debug("CEXITIF KEY WATCH DEBUG: identify rejected id=" .. id
      .. " reason=" .. tostring(type(result) == "table"
        and (result.message or result.code) or result))
    return false
  end
  mm.debug("CEXITIF KEY WATCH DEBUG: identifying configured key-name candidate id="
    .. id .. " name='" .. item_name .. "'")
  return true
end

local function validate_cexitif_target(index, alternate_command)
  local row, row_err, n, fromuid, dir, touid = selected_cexit_row(index)
  if not row then return nil, row_err end
  alternate_command = trim(alternate_command)
  if alternate_command == "" then return nil, "alternate cexit command is required" end
  if is_cardinal_cexit_dir(dir) or fromuid == "*" or fromuid == "**" then
    return nil, "cexitif supports regular custom exits only"
  end

  local ensured, ensure_err = mm.ensure_cexit_key_alternates_table()
  if not ensured then return nil, ensure_err end
  local current, current_err = mm.query_mapper_db(string.format(
    "SELECT COUNT(*) AS cnt FROM exits WHERE fromuid=%s AND dir=%s AND touid=%s",
    mm.sql_escape(fromuid), mm.sql_escape(dir), mm.sql_escape(touid)
  ))
  if not current then return nil, current_err end
  if tonumber(current[1] and current[1].cnt) ~= 1 then
    return nil, "selected cexit no longer exists; run mapper cexits again"
  end
  return {
    row = row,
    row_number = n,
    fromuid = fromuid,
    dir = dir,
    touid = touid,
    alternate_command = alternate_command,
  }, nil
end

local function same_cexitif_route(target, fromuid, dir, touid)
  return type(target) == "table"
    and tostring(target.fromuid or "") == tostring(fromuid or "")
    and tostring(target.dir or "") == tostring(dir or "")
    and tostring(target.touid or "") == tostring(touid or "")
end

local function clear_pending_cexitif_route(fromuid, dir, touid)
  local pending = mm.runtime and mm.runtime.pending_cexitif_keyids
  if type(pending) ~= "table" then return 0 end
  local removed = 0
  for token, entry in pairs(pending) do
    local target = type(entry) == "table" and (entry.target or entry) or nil
    if same_cexitif_route(target, fromuid, dir, touid) then
      pending[token] = nil
      removed = removed + 1
    end
  end
  return removed
end

local function add_pending_cexitif_keyid(obj_id, target)
  mm.runtime.pending_cexitif_keyids = mm.runtime.pending_cexitif_keyids or {}
  mm.runtime.cexitif_keyid_serial = (tonumber(mm.runtime.cexitif_keyid_serial) or 0) + 1
  local token = tostring(mm.runtime.cexitif_keyid_serial)
  mm.runtime.pending_cexitif_keyids[token] = {
    obj_id = tostring(obj_id),
    target = target,
  }
  return token
end

local function save_cexitif_target(target, key_name, key_keywords)
  key_name = trim(key_name)
  key_keywords = normalize_keyword_signature(key_keywords)
  if key_keywords == "" then return false, "a full key keyword identity is required" end
  clear_pending_cexitif_route(target.fromuid, target.dir, target.touid)
  local ensured, ensure_err = mm.ensure_cexit_key_alternates_table()
  if not ensured then return false, ensure_err end
  local current, current_err = mm.query_mapper_db(string.format(
    "SELECT COUNT(*) AS cnt FROM exits WHERE fromuid=%s AND dir=%s AND touid=%s",
    mm.sql_escape(target.fromuid), mm.sql_escape(target.dir), mm.sql_escape(target.touid)
  ))
  if not current then return false, current_err end
  if tonumber(current[1] and current[1].cnt) ~= 1 then
    return false, "selected cexit no longer exists; run mapper cexits again"
  end

  local ok, err = mm.exec_mapper_db(string.format(
    "INSERT OR REPLACE INTO cexit_key_alternates (fromuid, dir, touid, key_name, key_keywords, alternate_command) VALUES (%s, %s, %s, %s, %s, %s)",
    mm.sql_escape(target.fromuid), mm.sql_escape(target.dir), mm.sql_escape(target.touid),
    mm.sql_escape(key_name), mm.sql_escape(key_keywords), mm.sql_escape(target.alternate_command)
  ))
  if not ok then return false, err end

  local row = target.row
  if type(row) == "table" then
    row.key_name = key_name
    row.key_keywords = key_keywords
    row.alternate_command = target.alternate_command
  end
  mm.note(string.format(
    "Conditional cexit #%d saved: key keywords {%s} -> %s",
    tonumber(target.row_number) or 0, key_keywords, target.alternate_command
  ))

  local observations_cleaned, removed_or_err = remove_configured_cexit_key_observations(
    target.fromuid, target.dir, target.touid
  )
  if not observations_cleaned then
    mm.warn("Conditional cexit was saved, but its matching key observation could not be removed: "
      .. tostring(removed_or_err))
  elseif tonumber(removed_or_err) and tonumber(removed_or_err) > 0 then
    mm.note(string.format(
      "Removed %d matching key observation%s; this cexit no longer needs key monitoring.",
      tonumber(removed_or_err), tonumber(removed_or_err) == 1 and "" or "s"
    ))
  end

  note_dinv_key_check(key_keywords)
  return true
end

function mm.set_cexitif(index)
  return false, "name-only conditional keys are not supported; use 'mapper cexitif <row> keyid <id> do {<alternate command>}'"
end

function mm.set_cexitif_keywords(index, key_keywords, alternate_command)
  local target, target_err = validate_cexitif_target(index, alternate_command)
  if not target then return false, target_err end
  key_keywords = normalize_keyword_signature(key_keywords)
  if key_keywords == "" then return false, "key keywords are required" end
  local exists, details = mm.check_dinv_key_keywords(key_keywords)
  if exists == nil then return false, tostring(details and details.reason or "DINV keyword query failed") end
  local key_name = ""
  if details and details.items and details.items[1] then
    key_name = trim(details.items[1].name)
  end
  return save_cexitif_target(target, key_name, key_keywords)
end

function mm.set_cexitif_keyid(index, obj_id, alternate_command)
  obj_id = trim(obj_id)
  local target, target_err = validate_cexitif_target(index, alternate_command)
  if not target then return false, target_err end
  local item, item_err = get_dinv_item_by_id(obj_id)
  if not item then return false, item_err end

  local identify_level = tostring(item.identifyLevel or ""):lower()
  if identify_level == "full" then
    if not is_dinv_key_item(item) then return false, "DINV item " .. obj_id .. " is not a key" end
    local key_keywords = normalize_keyword_signature(item.keywords)
    if key_keywords == "" then return false, "fully identified key has no keywords" end
    return save_cexitif_target(target, item.name, key_keywords)
  end

  local actions = _G.DINV and _G.DINV.actions
  if not actions or type(actions.identify) ~= "function" then
    return false, "DINV targeted identify action is unavailable"
  end

  clear_pending_cexitif_route(target.fromuid, target.dir, target.touid)
  local pending_token = add_pending_cexitif_keyid(obj_id, target)
  local action_ok, result = pcall(actions.identify, obj_id, {source = "Mapper cexitif keyid"})
  if not action_ok or type(result) ~= "table" or result.ok ~= true then
    mm.runtime.pending_cexitif_keyids[pending_token] = nil
    return false, type(result) == "table" and tostring(result.message or result.code or "DINV identify failed")
      or tostring(result)
  end
  mm.note(string.format(
    "DINV is fully identifying item %s and verifying it is a key; the conditional cexit will be saved automatically when identification finishes.",
    obj_id
  ))
  return true
end

function mm.on_cexitif_key_identify_complete(event_name, obj_id)
  local id = trim(obj_id)
  if id == "" and trim(event_name):match("^%d+$") then id = trim(event_name) end
  if mm.runtime and mm.runtime.cexitif_name_identify_ids then
    mm.runtime.cexitif_name_identify_ids[id] = nil
  end
  local pending = mm.runtime and mm.runtime.pending_cexitif_keyids
  if type(pending) ~= "table" then return false end
  local targets = {}
  for token, entry in pairs(pending) do
    local entry_id = type(entry) == "table" and tostring(entry.obj_id or "") or ""
    local target = type(entry) == "table" and (entry.target or entry) or nil
    -- Accept the old id-keyed runtime shape during a hot package reload.
    if (entry_id == id or (entry_id == "" and tostring(token) == id)) and target then
      pending[token] = nil
      table.insert(targets, target)
    end
  end
  if #targets == 0 then return false end

  local item, item_err = get_dinv_item_by_id(id)
  if not item then
    mm.warn("Could not finish cexitif keyid " .. id .. ": " .. tostring(item_err))
    return false
  end
  if tostring(item.identifyLevel or ""):lower() ~= "full" then
    mm.warn("Could not finish cexitif keyid " .. id .. ": DINV did not obtain a full identify.")
    return false
  end
  if not is_dinv_key_item(item) then
    mm.warn("Could not finish cexitif keyid " .. id .. ": the fully identified item is not a key.")
    return false
  end
  local key_keywords = normalize_keyword_signature(item.keywords)
  if key_keywords == "" then
    mm.warn("Could not finish cexitif keyid " .. id .. ": the full identify contains no keywords.")
    return false
  end
  local saved = 0
  for _, target in ipairs(targets) do
    local ok, err = save_cexitif_target(target, item.name, key_keywords)
    if ok then
      saved = saved + 1
    else
      mm.warn("Could not finish cexitif keyid " .. id .. ": " .. tostring(err))
    end
  end
  return saved > 0
end

function mm.remove_cexitif(index)
  local row, row_err, n, fromuid, dir, touid = selected_cexit_row(index)
  if not row then return false, row_err end
  clear_pending_cexitif_route(fromuid, dir, touid)
  local ensured, ensure_err = mm.ensure_cexit_key_alternates_table()
  if not ensured then return false, ensure_err end
  local ok, err = mm.exec_mapper_db(string.format(
    "DELETE FROM cexit_key_alternates WHERE fromuid=%s AND dir=%s",
    mm.sql_escape(fromuid), mm.sql_escape(dir)
  ))
  if not ok then return false, err end
  row.key_name = nil
  row.key_keywords = nil
  row.alternate_command = nil
  mm.note(string.format("Conditional cexit #%d removed; the regular cexit is unchanged.", n))
  return true
end

function mm.test_cexitif(index)
  local row, row_err, n, fromuid, dir, touid = selected_cexit_row(index)
  if not row then return false, row_err end
  local ensured, ensure_err = mm.ensure_cexit_key_alternates_table()
  if not ensured then return false, ensure_err end
  local rows, query_err = mm.query_mapper_db(string.format(
    "SELECT key_name, key_keywords, alternate_command FROM cexit_key_alternates WHERE fromuid=%s AND dir=%s AND touid=%s LIMIT 1",
    mm.sql_escape(fromuid), mm.sql_escape(dir), mm.sql_escape(touid)
  ))
  if not rows then return false, query_err end
  local config = rows[1]
  if not config then return false, string.format("cexit #%d has no conditional alternate", n) end
  if normalize_keyword_signature(config.key_keywords) == "" then
    mm.note(string.format(
      "Cexit #%d has a legacy name-only key and is inactive; rewrite it with mapper cexitif %d keyid <id> do {<alternate command>}.",
      n, n
    ))
    return true
  end

  local exists, details = mm.check_dinv_key_keywords(config.key_keywords)
  details = details or {}
  if exists == true then
    mm.note(string.format(
      "Cexit #%d test: DINV has %d matching key%s; would execute alternate: %s",
      n, tonumber(details.count) or 1, tonumber(details.count) == 1 and "" or "s",
      tostring(config.alternate_command)
    ))
  elseif exists == false then
    mm.note(string.format(
      "Cexit #%d test: DINV has no matching key; would execute regular cexit: %s",
      n, dir
    ))
  else
    mm.note(string.format(
      "Cexit #%d test: DINV key state is unavailable (%s); would execute regular cexit: %s",
      n, tostring(details.reason or "unknown error"), dir
    ))
  end
  return true
end

function mm.cexit_key_alternates_for_path(path, initial_source)
  if type(path) ~= "table" or #path == 0 then return {} end
  local sources, wanted_sources, source = {}, {}, trim(initial_source)
  for index, step in ipairs(path) do
    sources[index] = source
    local dir = trim(step and step.dir)
    if source ~= "" and source ~= "*" and source ~= "**"
        and dir ~= "" and not is_cardinal_cexit_dir(dir)
        and not (step and step.randomCexit == true)
        and not (step and (step.travelType == "portal" or step.travelType == "recall"))
    then
      wanted_sources[source] = true
    end
    local destination = trim(step and step.uid)
    if destination ~= "" and destination ~= "-1" then source = destination end
  end
  if not next(wanted_sources) then return {} end

  local quoted = {}
  for fromuid in pairs(wanted_sources) do table.insert(quoted, mm.sql_escape(fromuid)) end
  table.sort(quoted)
  local rows, err = mm.query_mapper_db(
    "SELECT fromuid, dir, touid, key_name, key_keywords, alternate_command FROM cexit_key_alternates WHERE fromuid IN ("
      .. table.concat(quoted, ",") .. ")"
  )
  if not rows then
    mm.debug("CEXITIF DEBUG: route metadata query failed: " .. tostring(err))
    return {}
  end

  local by_identity = {}
  for _, row in ipairs(rows) do
    local identity = tostring(row.fromuid) .. "\0" .. tostring(row.dir) .. "\0" .. tostring(row.touid)
    by_identity[identity] = row
  end
  local configured = {}
  for index, step in ipairs(path) do
    local identity = tostring(sources[index] or "") .. "\0" .. tostring(step.dir or "") .. "\0" .. tostring(step.uid or "")
    local config = by_identity[identity]
    if config and normalize_keyword_signature(config.key_keywords) ~= "" then
      config.source_room = tostring(sources[index])
      config.destination_room = tostring(step.uid)
      configured[index] = config
    end
  end
  return configured
end

function mm.choose_cexit_key_command(config, regular_command)
  config = type(config) == "table" and config or {}
  regular_command = tostring(regular_command or config.dir or "")
  local exists, details = mm.check_dinv_key_keywords(config.key_keywords)
  details = details or {}
  local branch = exists == true and "alternate" or "regular"
  local selected = branch == "alternate" and tostring(config.alternate_command or "") or regular_command
  mm.debug(string.format(
    "CEXITIF DEBUG: from=%s to=%s key='%s' keywords='{%s}' result=%s count=%s ids={%s} locations={%s} branch=%s command='%s'%s",
    tostring(config.source_room or config.fromuid or "?"),
    tostring(config.destination_room or config.touid or "?"),
    tostring(config.key_name or ""),
    tostring(config.key_keywords or ""),
    exists == nil and "unknown" or tostring(exists),
    tostring(details.count or 0),
    table.concat(details.ids or {}, ","),
    table.concat(details.locations or {}, ","),
    branch,
    selected,
    details.reason and (" reason='" .. tostring(details.reason) .. "'") or ""
  ))
  if exists == nil then
    mm.warn("DINV key state unavailable; using the regular cexit.")
  end
  return selected, branch, details
end

local CEXIT_KEY_OBSERVATION_MAX_AGE = 60

local function infer_cexit_door_direction(command)
  local aliases = {
    n = "n", north = "n", s = "s", south = "s",
    e = "e", east = "e", w = "w", west = "w",
    u = "u", up = "u", d = "d", down = "d",
  }
  local inferred
  for token in tostring(command or ""):gmatch("[^;]+") do
    local verb, argument = token:lower():match("^%s*(%S+)%s+(%S+)")
    if verb == "o" or verb == "op" or verb == "ope" or verb == "open"
        or verb == "unlock" then
      inferred = aliases[argument] or inferred
    end
  end
  return inferred
end

function mm.resolve_observed_dinv_key(observed_key)
  local observed_normalized = normalize_observed_key(observed_key)
  if observed_normalized == "" then return nil, {reason = "empty observed key"} end

  local api = _G.DINV and _G.DINV.api
  if not api or type(api.getKeys) ~= "function" then
    return nil, {reason = "DINV getKeys API is unavailable"}
  end

  local ok, result = pcall(api.getKeys, {
    source = "live",
    includeIgnored = true,
    fields = {"id", "name", "normalizedName", "keywords", "type", "flags", "location", "container", "worn"},
  })
  if not ok or type(result) ~= "table" or result.ok ~= true then
    return nil, {reason = type(result) == "table" and tostring(result.message or result.code or "DINV key query failed") or tostring(result)}
  end
  if result.keyDefinition ~= "isKeyOrTypeKey" then
    return nil, {reason = "DINV getKeys API does not support isKey-or-Type-Key queries"}
  end

  local matched_names = {}
  local matched_items = {}
  for _, item in ipairs(type(result.items) == "table" and result.items or {}) do
    local normalized_name = normalize_observed_key(item.normalizedName or item.name)
    local name_matches = normalized_name == observed_normalized
      or without_leading_article(normalized_name) == observed_normalized
    local keyword_matches = false
    if not observed_normalized:find(" ", 1, true) then
      for keyword in tostring(item.keywords or ""):lower():gmatch("[^,%s]+") do
        if keyword == observed_normalized then
          keyword_matches = true
          break
        end
      end
    end
    if name_matches or keyword_matches then
      local identity = normalized_name ~= "" and normalized_name or normalize_observed_key(item.name)
      if identity ~= "" then
        matched_names[identity] = tostring(item.name or observed_key)
        table.insert(matched_items, item)
      end
    end
  end

  local identities = {}
  for identity in pairs(matched_names) do table.insert(identities, identity) end
  table.sort(identities)
  if #identities == 1 then
    return matched_names[identities[1]], {
      normalized_name = identities[1],
      items = matched_items,
      count = #matched_items,
    }
  end
  return nil, {
    reason = #identities == 0 and "no live DINV key matched the unlock text" or "multiple DINV key names matched the unlock text",
    items = matched_items,
    count = #matched_items,
  }
end

function mm.track_cexit_key_observation_path(path, initial_source, execution_serial)
  mm.runtime = mm.runtime or {}
  local context = {
    execution_serial = tonumber(execution_serial) or 0,
    started_at = os.time(),
    edges = {},
  }
  local source = normalize_uid(initial_source)
  local seen = {}
  for index, step in ipairs(type(path) == "table" and path or {}) do
    local executed_command = trim(step and step.dir)
    local base_command = trim(step and (step.cexitBaseDir or step.cexit_base_dir) or executed_command)
    local destination = normalize_uid(step and step.uid)
    local regular = source and destination and source ~= "*" and source ~= "**"
      and destination ~= "*" and destination ~= "**"
      and base_command ~= "" and not is_cardinal_cexit_dir(base_command)
      and not (step and step.randomCexit == true)
      and not (step and (step.travelType == "portal" or step.travelType == "recall"))
    if regular then
      local identity = source .. "\0" .. base_command .. "\0" .. destination
      if not seen[identity] then
        seen[identity] = true
        table.insert(context.edges, {
          path_index = index,
          fromuid = source,
          dir = base_command,
          touid = destination,
          executed_command = executed_command,
          door_direction = infer_cexit_door_direction(executed_command),
        })
      end
    end
    if destination then source = destination end
  end
  mm.runtime.cexit_key_observation_context = context
  mm.debug(string.format(
    "CEXIT KEY OBSERVE DEBUG: tracking serial=%s regular_cexits=%d",
    tostring(context.execution_serial), #context.edges
  ))
  return context
end

function mm.observe_cexit_key_unlock(observed_key)
  mm.runtime = mm.runtime or {}
  local context = mm.runtime.cexit_key_observation_context
  local nav = snd and snd.mapper or nil
  if type(context) ~= "table" or not nav
      or tonumber(nav.pathExecutionSerial) ~= tonumber(context.execution_serial)
      or nav.pathExecutionActive ~= true then
    mm.debug("CEXIT KEY OBSERVE DEBUG: ignored unlock line outside active tracked navigation")
    return false, "no active tracked mapper route"
  end

  local source = normalize_uid(mm.current_room())
  local observed = tostring(observed_key or "")
  if mm.strip_ansi then observed = mm.strip_ansi(observed) end
  observed = trim(observed)
  local observed_normalized = normalize_observed_key(observed)
  if not source or observed_normalized == "" then
    return false, "unlock observation is missing its source room or key text"
  end

  local candidates = {}
  for _, edge in ipairs(context.edges or {}) do
    if edge.fromuid == source then table.insert(candidates, edge) end
  end
  if #candidates ~= 1 then
    mm.debug(string.format(
      "CEXIT KEY OBSERVE DEBUG: ignored key='%s' source=%s candidate_cexits=%d",
      observed, tostring(source), #candidates
    ))
    return false, #candidates == 0 and "no tracked cexit starts in the unlock room" or "multiple tracked cexits start in the unlock room"
  end

  local resolved_key_name, resolution = mm.resolve_observed_dinv_key(observed)
  local edge = candidates[1]
  local pending = {
    execution_serial = context.execution_serial,
    observed_at = os.time(),
    fromuid = edge.fromuid,
    dir = edge.dir,
    touid = edge.touid,
    observed_key = observed,
    observed_key_normalized = observed_normalized,
    resolved_key_name = resolved_key_name,
    door_direction = edge.door_direction,
  }
  mm.runtime.pending_cexit_key_unlocks = mm.runtime.pending_cexit_key_unlocks or {}
  table.insert(mm.runtime.pending_cexit_key_unlocks, pending)
  mm.debug(string.format(
    "CEXIT KEY OBSERVE DEBUG: pending from=%s to=%s key='%s' resolved='%s' door=%s cexit='%s'%s",
    pending.fromuid, pending.touid, pending.observed_key,
    tostring(pending.resolved_key_name or ""), tostring(pending.door_direction or "-"), pending.dir,
    resolution and resolution.reason and (" reason='" .. tostring(resolution.reason) .. "'") or ""
  ))
  return true, pending
end

function mm.record_cexit_key_observation(entry)
  entry = type(entry) == "table" and entry or {}
  local fromuid = normalize_uid(entry.fromuid)
  local touid = normalize_uid(entry.touid)
  local dir = trim(entry.dir)
  local observed_key = trim(entry.observed_key)
  local observed_normalized = normalize_observed_key(entry.observed_key_normalized or observed_key)
  if not fromuid or not touid or dir == "" or observed_key == "" or observed_normalized == "" then
    return false, "incomplete cexit key observation"
  end
  if fromuid == "*" or fromuid == "**" or is_cardinal_cexit_dir(dir) then
    return false, "key observations require a regular custom exit"
  end

  local valid_rows, valid_err = mm.query_mapper_db(string.format(
    "SELECT COUNT(*) AS cnt FROM exits WHERE fromuid=%s AND dir=%s AND touid=%s",
    mm.sql_escape(fromuid), mm.sql_escape(dir), mm.sql_escape(touid)
  ))
  if not valid_rows then return false, valid_err end
  if tonumber(valid_rows[1] and valid_rows[1].cnt) ~= 1 then
    return false, "the observed source, command, and destination no longer identify an existing cexit"
  end

  local ensured, ensure_err = mm.ensure_cexit_key_observations_table()
  if not ensured then return false, ensure_err end
  local alternates_ensured, alternates_ensure_err = mm.ensure_cexit_key_alternates_table()
  if not alternates_ensured then return false, alternates_ensure_err end
  local configured, configured_key_err = configured_cexit_key(fromuid, dir, touid)
  if configured == nil then return false, configured_key_err end
  local configured_key = trim(configured.key_name)
  if normalize_keyword_signature(configured.key_keywords) ~= "" then
    local deleted, delete_err = delete_cexit_key_observation_record({
      fromuid = fromuid,
      dir = dir,
      touid = touid,
      observed_key_normalized = observed_normalized,
    })
    if not deleted then return false, delete_err end
    mm.runtime.cexit_key_observation_last_rows = {}
    mm.debug(string.format(
      "CEXIT KEY OBSERVE DEBUG: skipped configured pair from=%s to=%s key='%s' cexit='%s'",
      fromuid, touid, configured_key, dir
    ))
    return false, "this cexit/key pair is already configured"
  end
  local existing, existing_err = mm.query_mapper_db(string.format(
    "SELECT seen_count, first_seen_at, resolved_key_name, door_direction FROM cexit_key_observations WHERE fromuid=%s AND dir=%s AND touid=%s AND observed_key_normalized=%s LIMIT 1",
    mm.sql_escape(fromuid), mm.sql_escape(dir), mm.sql_escape(touid), mm.sql_escape(observed_normalized)
  ))
  if not existing then return false, existing_err end

  local previous = existing[1] or {}
  local now = tonumber(entry.observed_at) or os.time()
  local first_seen = tonumber(previous.first_seen_at) or now
  local seen_count = (tonumber(previous.seen_count) or 0) + 1
  local resolved_key_name = trim(entry.resolved_key_name)
  if resolved_key_name == "" then resolved_key_name = trim(previous.resolved_key_name) end
  local door_direction = trim(entry.door_direction)
  if door_direction == "" then door_direction = trim(previous.door_direction) end

  local ok, write_err = mm.exec_mapper_db(string.format(
    "INSERT OR REPLACE INTO cexit_key_observations (fromuid, dir, touid, observed_key, observed_key_normalized, resolved_key_name, door_direction, seen_count, first_seen_at, last_seen_at) VALUES (%s, %s, %s, %s, %s, %s, %s, %d, %d, %d)",
    mm.sql_escape(fromuid), mm.sql_escape(dir), mm.sql_escape(touid),
    mm.sql_escape(observed_key), mm.sql_escape(observed_normalized),
    mm.sql_escape(resolved_key_name), mm.sql_escape(door_direction),
    seen_count, first_seen, now
  ))
  if not ok then return false, write_err end
  mm.debug(string.format(
    "CEXIT KEY OBSERVE DEBUG: recorded from=%s to=%s key='%s' resolved='%s' count=%d",
    fromuid, touid, observed_key, resolved_key_name, seen_count
  ))
  return true, seen_count
end

function mm.on_cexit_key_observation_room(room_info)
  mm.runtime = mm.runtime or {}
  local pending = mm.runtime.pending_cexit_key_unlocks
  if type(pending) ~= "table" or #pending == 0 then return false end

  local room_uid = type(room_info) == "table" and mm.canonical_room_uid(room_info) or normalize_uid(room_info)
  if not room_uid then return false end
  room_uid = tostring(room_uid)
  local current_serial = snd and snd.mapper and tonumber(snd.mapper.pathExecutionSerial) or nil
  local now = os.time()
  local remaining = {}
  local recorded = 0
  for _, entry in ipairs(pending) do
    local expired = now - (tonumber(entry.observed_at) or now) > CEXIT_KEY_OBSERVATION_MAX_AGE
    local stale_serial = current_serial == nil or tonumber(entry.execution_serial) ~= current_serial
    if stale_serial or expired then
      mm.debug(string.format(
        "CEXIT KEY OBSERVE DEBUG: discarded pending key='%s' stale_serial=%s expired=%s",
        tostring(entry.observed_key or ""), tostring(stale_serial), tostring(expired)
      ))
    elseif room_uid == tostring(entry.touid) then
      local ok, count_or_err = mm.record_cexit_key_observation(entry)
      if ok then
        recorded = recorded + 1
      else
        mm.debug("CEXIT KEY OBSERVE DEBUG: validation/save rejected observation: " .. tostring(count_or_err))
      end
    else
      table.insert(remaining, entry)
    end
  end
  mm.runtime.pending_cexit_key_unlocks = remaining
  return recorded > 0, recorded
end

local function print_cexit_key_observations(rows)
  cecho("<gray>#   From     To       Door  Seen  Key                              Existing cexit                 Last observed<reset>\n")
  cecho("<gray>------------------------------------------------------------------------------------------------------------------------<reset>\n")
  for index, row in ipairs(rows) do
    local key_name = trim(row.resolved_key_name)
    if key_name == "" then key_name = tostring(row.observed_key or "?") end
    local last_seen = tonumber(row.last_seen_at)
    local last_text = last_seen and os.date("%Y-%m-%d %H:%M", last_seen) or "?"
    cecho(string.format(
      "<light_grey>%-3d %-8.8s %-8.8s %-5.5s %-5d %-32.32s %-30.30s %s<reset>\n",
      index, tostring(row.fromuid or "?"), tostring(row.touid or "?"),
      trim(row.door_direction) ~= "" and tostring(row.door_direction) or "-",
      tonumber(row.seen_count) or 0, key_name, tostring(row.dir or ""), last_text
    ))
  end
end

function mm.list_cexit_key_observations(scope_arg)
  local ensured, ensure_err = mm.ensure_cexit_key_observations_table()
  if not ensured then return false, ensure_err end
  local alternates_ensured, alternates_ensure_err = mm.ensure_cexit_key_alternates_table()
  if not alternates_ensured then return false, alternates_ensure_err end
  local scope = trim(scope_arg):lower()
  local where = "1=1"
  if scope == "thisroom" or scope == "here" then
    local room = normalize_uid(mm.current_room())
    if not room then return false, "current room is unknown; try LOOK first" end
    where = "o.fromuid=" .. mm.sql_escape(room)
  elseif scope ~= "" then
    return false, "Usage: mapper cexitkeys [thisroom]"
  end
  local rows, err = mm.query_mapper_db(
    "SELECT o.fromuid, o.dir, o.touid, o.observed_key, o.observed_key_normalized, o.resolved_key_name, o.door_direction, o.seen_count, o.first_seen_at, o.last_seen_at, a.key_name AS configured_key_name, a.key_keywords AS configured_key_keywords "
      .. "FROM cexit_key_observations AS o LEFT JOIN cexit_key_alternates AS a "
      .. "ON a.fromuid=o.fromuid AND a.dir=o.dir AND a.touid=o.touid WHERE "
      .. where .. " ORDER BY o.seen_count DESC, o.last_seen_at DESC, o.fromuid, o.dir"
  )
  if not rows then return false, err end
  local unresolved = {}
  for _, row in ipairs(rows) do
    if normalize_keyword_signature(row.configured_key_keywords) ~= "" then
      local deleted, delete_err = delete_cexit_key_observation_record(row)
      if not deleted then
        mm.debug("CEXIT KEY OBSERVE DEBUG: could not remove configured observation: " .. tostring(delete_err))
      end
    else
      table.insert(unresolved, row)
    end
  end
  rows = unresolved
  mm.runtime.cexit_key_observation_last_rows = rows
  mm.note(scope == "" and "Observed cexit key uses:" or "Observed cexit key uses from this room:")
  if #rows == 0 then
    mm.note("Found 0 observed cexit key uses.")
    return true
  end
  print_cexit_key_observations(rows)
  mm.note(string.format("Found %d observed cexit/key pair%s.", #rows, #rows == 1 and "" or "s"))
  return true
end

function mm.delete_cexit_key_observation(index)
  local row_number = tonumber(index)
  local row = row_number and (mm.runtime.cexit_key_observation_last_rows or {})[row_number] or nil
  if not row then return false, "cexit key observation row is out of range for the last mapper cexitkeys list" end
  local ok, err = delete_cexit_key_observation_record(row)
  if not ok then return false, err end
  table.remove(mm.runtime.cexit_key_observation_last_rows, row_number)
  mm.note(string.format(
    "Deleted observed cexit key row %d: %s -> %s, key '%s'.",
    row_number, tostring(row.fromuid), tostring(row.touid),
    trim(row.resolved_key_name) ~= "" and tostring(row.resolved_key_name) or tostring(row.observed_key)
  ))
  return true
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
  for id in pairs(mm.portals.settings.portal_guard_levels or {}) do
    local portal = find_portal_by_id(id)
    if not valid_ids[tostring(id)] or not portal or mm.is_portal_recall(portal)
        or tostring(mm.dinv_portal_id(portal.command) or "") ~= tostring(id) then
      mm.portals.settings.portal_guard_levels[id] = nil
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
  if mm.portal_usage and mm.portal_usage.prepare_rows then
    mm.portal_usage.prepare_rows(selected)
  end
  local minimum_usage, maximum_usage
  if mm.portal_usage and mm.portal_usage.count_range then
    minimum_usage, maximum_usage = mm.portal_usage.count_range(selected)
  end

  cecho("\n<deep_sky_blue>Nr   <medium_purple>Type     <medium_purple>Area                      <cornflower_blue>Room name                                  <medium_purple>Portal command                    <deep_sky_blue>Level  <cyan>Used<reset>\n")
  cecho("<gray>----------------------------------------------------------------------------------------------------------------------------<reset>\n")

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
    if p.usage_trackable and mm.portal_usage and mm.portal_usage.echo_report_link then
      mm.portal_usage.echo_report_link(p.nr)
    else
      cecho(string.format("<deep_sky_blue>[%2s]<reset>", tostring(p.nr or "?")))
    end
    local count_color, count_text = "dim_gray", "-"
    if mm.portal_usage and mm.portal_usage.count_color then
      count_color, count_text = mm.portal_usage.count_color(p, minimum_usage, maximum_usage)
    end
    cecho(string.format(
      " <%s>%-8s <light_grey>%-25s <white>%-42s <%s>%-33s <khaki>%5d<reset>  <%s>%4s<reset>",
      type_color,
      is_chaos and "Chaos" or (is_recall and "Recall" or "Portal"),
      fit(p.area or "?", 25),
      fit(p.room_name or "?", 42),
      command_color,
      fit(p.command or "?", 33),
      tonumber(p.level) or 0,
      count_color,
      count_text
    ))
    if mm.portals.settings.bounce_portal_id == tostring(p.portal_id) then
      cecho(" <magenta>[BouncePortal]<reset>")
    end
    if mm.portals.settings.bounce_recall_id == tostring(p.portal_id) then
      cecho(" <magenta>[BounceRecall]<reset>")
    end
    local guard_level = mm.portal_guard_level(p.portal_id)
    if guard_level and not is_recall then
      cecho(string.format(
        " <orange>[Guard +%d -> %d]<reset>",
        guard_level,
        (tonumber(p.level) or 0) + guard_level
      ))
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
  -- mapper where is deliberately theoretical: ignore level, area, portal, and
  -- source-room travel restrictions and rank only by database edge count. Ask
  -- for a pure walking alternative as well so an equal-distance walk wins over
  -- a portal route without importing xrt's live DINV operational cost.
  local candidates = {}
  local rawPath = nav.findPath(src, dest, nil, nil, true, true, true)
  if rawPath and #rawPath > 0 then
    table.insert(candidates, {kind = "raw", path = rawPath})
  end
  local walkingPath = nav.findPath(src, dest, true, true, true, true, true)
  if walkingPath and #walkingPath > 0 then
    table.insert(candidates, {kind = "walk", path = walkingPath})
  end

  local selected = nil
  if type(nav.chooseShortestRoute) == "function" then
    selected = nav.chooseShortestRoute(candidates, {mode = "distance"})
  else
    for _, candidate in ipairs(candidates) do
      local portalCount = 0
      for _, step in ipairs(candidate.path or {}) do
        if step.travelType == "portal" then portalCount = portalCount + 1 end
      end
      if not selected
          or #candidate.path < #selected.path
          or (#candidate.path == #selected.path and portalCount < selected.portalCount)
      then
        selected = candidate
        selected.portalCount = portalCount
      end
    end
  end

  local path = selected and selected.path or nil
  local depth = path and #path or nil
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
  local warned = {}
  for _, step in ipairs(path) do
    local details = mm.portal_guard_details_for_command
      and mm.portal_guard_details_for_command(step.dir)
      or nil
    if details and details.blocked and not warned[details.portal_id] then
      warned[details.portal_id] = true
      mm.warn(string.format(
        "Theoretical route warning: portal %s requires effective level %d (base %d + guard %d); your effective level is %d. Normal xrt will choose another route.",
        details.portal_id,
        details.required_level,
        details.base_level,
        details.guard_level,
        details.effective_level
      ))
    end
  end
  return true
end

function mm.guarded_room(dest)
  dest = tonumber(dest)
  if not dest then return false, "mapper guarded expects a room id" end
  local src = mm.current_room()
  if not src then return false, "current room unknown; try LOOK first" end
  if src == dest then return false, "you are already in that room" end

  local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
  if not (nav and type(nav.previewGuardedRoute) == "function") then
    return false, "mapper guarded requires mapper navigation module"
  end

  local savedConfig = type(nav.areaGuardConfig) == "function" and nav.areaGuardConfig() or nil
  local savedEnabled = type(savedConfig) == "table" and savedConfig.enabled == true
  local selected, details = nav.previewGuardedRoute(src, dest, true)
  if not selected then
    details = details or {}
    if details.reason == "destination_blocked" then
      local guard = details.destinationGuard or {}
      return false, string.format(
        "AreaGuard blocks room %d: %s requires level %d; your level is %d",
        dest,
        tostring(guard.area or guard.mapperArea or "destination area"),
        tonumber(guard.required) or 0,
        tonumber(guard.level) or 0
      )
    elseif details.reason == "area_guard_route_blocked" then
      return false, string.format(
        "no guarded path from %s to %d; the available route crosses an AreaGuard-blocked area",
        tostring(src),
        dest
      )
    end
    return false, string.format("guarded path from %s to %d not found", tostring(src), dest)
  end

  local path = selected.path
  if type(path) ~= "table" or #path == 0 then
    return false, string.format("guarded path from %s to %d not found", tostring(src), dest)
  end

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
  for _, step in ipairs(path) do table.insert(steps, tostring(step.dir or "")) end
  mm.note(string.format("Guarded path to %d: %s", dest, table.concat(steps, " ; ")))
  mm.note(string.format("Distance: %d", #steps))
  mm.note(string.format(
    "Preview only: AreaGuard was forced on; saved setting remains %s.",
    savedEnabled and "ON" or "OFF"
  ))
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

function mm.mapper_walkto_target(command)
  local normalized = tostring(command or ""):lower()
    :gsub("^%s+", ""):gsub("%s+$", "")
  local target = normalized:match("^mapper%s+walkto%s+(%d+)$")
  return target and tonumber(target) or nil
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

  local random_ready, random_err = mm.ensure_random_cexits_table()
  if not random_ready then return false, random_err end
  local random_conflicts, conflict_err = mm.query_mapper_db(string.format(
    "SELECT touid FROM random_cexits WHERE fromuid=%s AND dir=%s LIMIT 1",
    mm.sql_escape(src), mm.sql_escape(command)
  ))
  if not random_conflicts then return false, conflict_err end
  if random_conflicts[1] then
    return false, string.format(
      "a random cexit already uses '%s' from room %s; delete it before creating a regular cexit",
      command, tostring(src)
    )
  end

  local ok, err = mm.exec_mapper_db(string.format(
    "INSERT OR REPLACE INTO exits (dir, fromuid, touid, level) VALUES (%s, %s, %s, %s)",
    mm.sql_escape(command), mm.sql_escape(src), mm.sql_escape(dst), mm.sql_escape(level)
  ))
  if not ok then return false, err end

  -- Replacing a cexit with a different destination must not silently carry an
  -- alternate whose declared landing belonged to the old edge.
  local alt_ready = mm.ensure_cexit_key_alternates_table()
  if alt_ready then
    local cleaned, cleanup_err = mm.exec_mapper_db(string.format(
      "DELETE FROM cexit_key_alternates WHERE fromuid=%s AND dir=%s AND touid<>%s",
      mm.sql_escape(src), mm.sql_escape(command), mm.sql_escape(dst)
    ))
    if not cleaned then mm.warn("Could not clear stale conditional cexit: " .. tostring(cleanup_err)) end
  end
  local observation_ready, observation_err = mm.ensure_cexit_key_observations_table()
  if not observation_ready then
    mm.warn("Could not clear stale cexit key observations: " .. tostring(observation_err))
  end

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

local function normalize_random_cexit_destinations(destinations)
  local values = {}
  if type(destinations) == "table" then
    for _, value in ipairs(destinations) do table.insert(values, value) end
  else
    for value in tostring(destinations or ""):gmatch("([^,]+)") do
      table.insert(values, value)
    end
  end

  local normalized, seen = {}, {}
  for _, value in ipairs(values) do
    local uid = mm.strip_ansi(value):gsub("^%s+", ""):gsub("%s+$", "")
    if uid ~= "" and not seen[uid] then
      seen[uid] = true
      table.insert(normalized, uid)
    end
  end
  table.sort(normalized, function(a, b)
    local an, bn = tonumber(a), tonumber(b)
    if an and bn then return an < bn end
    return tostring(a) < tostring(b)
  end)
  return normalized
end

function mm.add_random_cexit(command, src, destinations, level, quiet)
  command = mm.normalize_stacked_command(command)
  src = mm.strip_ansi(src):gsub("^%s+", ""):gsub("%s+$", "")
  level = tonumber(level) or 0
  local outcomes = normalize_random_cexit_destinations(destinations)

  if command == "" then return false, "random cexit command is required" end
  if command:find(";", 1, true) then
    return false, "random cexit must be a single command without stacked separators"
  end
  if mm.mapper_walkto_target(command) or command:match("^wait%(") then
    return false, "random cexit must be a single MUD command"
  end
  if src == "" then return false, "random cexit source room id is required" end
  if #outcomes < 2 then return false, "random cexit requires at least two destination room ids" end
  for _, destination in ipairs(outcomes) do
    if destination == src then
      return false, "random cexit destinations must be different from the source room"
    end
  end

  local ensured, ensure_err = mm.ensure_random_cexits_table()
  if not ensured then return false, ensure_err end

  local conflicts, conflict_err = mm.query_mapper_db(string.format(
    "SELECT touid FROM exits WHERE fromuid=%s AND dir=%s LIMIT 1",
    mm.sql_escape(src), mm.sql_escape(command)
  ))
  if not conflicts then return false, conflict_err end
  if conflicts[1] then
    return false, string.format(
      "a regular cexit already uses '%s' from room %s; delete it before creating the random cexit",
      command, src
    )
  end

  local source = mm.resolve_mapper_db(mm.state and mm.state.map_db)
  if not source or not mm.path_exists(source) then
    return false, "mapper db not found: " .. tostring(source)
  end
  local env, conn, open_err = open_mapper_db(source)
  if not conn then return false, open_err end

  local ok, err = execute_statement(conn, "BEGIN IMMEDIATE")
  if ok then
    ok, err = execute_statement(conn, string.format(
      "DELETE FROM random_cexits WHERE fromuid=%s AND dir=%s",
      mm.sql_escape(src), mm.sql_escape(command)
    ))
  end
  if ok then
    for _, destination in ipairs(outcomes) do
      ok, err = execute_statement(conn, string.format(
        "INSERT INTO random_cexits (dir, fromuid, touid, level) VALUES (%s, %s, %s, %s)",
        mm.sql_escape(command), mm.sql_escape(src), mm.sql_escape(destination), mm.sql_escape(level)
      ))
      if not ok then break end
    end
  end
  if ok then
    ok, err = execute_statement(conn, "COMMIT")
  end
  if not ok then pcall(function() conn:execute("ROLLBACK") end) end
  conn:close()
  env:close()
  if not ok then return false, err end

  if not quiet then
    mm.note(string.format(
      "Random Exit CONFIRMED: %s (%s) -> {%s} [lock level %d]",
      src, command, table.concat(outcomes, ", "), level
    ))
  end
  return true
end

function mm.cexit(command)
  local src = mm.current_room()
  if not src then return false, "CEXIT FAILED: No room received yet. Try LOOK first." end
  local original_command = tostring(command or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if original_command == "" then return false, "Nothing to do" end

  mm.debug(string.format("CEXIT DEBUG: src=%s command='%s'", tostring(src), original_command))
  local added_waits = 0
  for wait_secs in string.gmatch(original_command, "wait%((%d*.?%d+)%)") do
    added_waits = added_waits + (tonumber(wait_secs) or 0)
  end
  mm.debug(string.format("CEXIT DEBUG: added_waits=%s", tostring(added_waits)))
  mm.note("CEXIT: WAIT FOR CONFIRMATION BEFORE MOVING.")
  mm.debug(string.format("CEXIT DEBUG: sending='%s'", original_command))

  local confirmation_delay = (tonumber(mm.state.temp_cexit_delay) or 2) + added_waits
  mm.state.temp_cexit_delay = nil
  mm.runtime = mm.runtime or {}
  mm.runtime.cexit_execution_serial = (tonumber(mm.runtime.cexit_execution_serial) or 0) + 1
  local execution_serial = mm.runtime.cexit_execution_serial

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
  local step_gap = 0.05

  local function is_execution_current()
    return mm.runtime and mm.runtime.cexit_execution_serial == execution_serial
  end

  local function schedule(delay, callback)
    if not is_execution_current() then return end
    if tonumber(delay) and tonumber(delay) > 0 then
      tempTimer(delay, callback)
    else
      callback()
    end
  end

  local function schedule_cexit_confirmation()
    mm.debug(string.format(
      "CEXIT DEBUG: confirmation window=%.2fs from cexit start",
      confirmation_delay
    ))
    schedule(confirmation_delay, function()
      if not is_execution_current() then return end
      local dst = mm.current_room()
      if not dst then mm.warn("CEXIT FAILED: Need to know where we ended up."); return end
      mm.debug(string.format("CEXIT DEBUG: post-delay src=%s dst=%s command='%s'", tostring(src), tostring(dst), original_command))
      local ok, err = mm.add_full_cexit(original_command, src, dst, 0, false, { preserve_command = true })
      if not ok then
        mm.warn("CEXIT FAILED: " .. tostring(err))
      else
        mm.debug(string.format("CEXIT DEBUG: add_full_cexit persisted command='%s' from=%s to=%s", original_command, tostring(src), tostring(dst)))
      end
    end)
  end

  local run_from
  run_from = function(index)
    if not is_execution_current() then return end
    local step = steps[index]
    if not step then
      mm.debug("CEXIT DEBUG: command sequence fully released")
      return
    end

    local wait_time = tonumber(step:match("^wait%((%d*.?%d+)%)$"))
    if wait_time then
      mm.debug(string.format("CEXIT DEBUG: step[%d]='%s' (local wait %.2fs)", index, step, wait_time))
      schedule(wait_time, function() run_from(index + 1) end)
      return
    end

    local walkto_target = mm.mapper_walkto_target(step)
    if walkto_target then
      mm.debug(string.format(
        "CEXIT DEBUG: step[%d]='%s' walkto barrier=%s holding_steps=%d",
        index,
        step,
        tostring(walkto_target),
        #steps - index
      ))
      local ok, err = mm.walkto_room(walkto_target)
      if not ok then
        mm.warn(string.format("CEXIT FAILED at step[%d] '%s': %s", index, step, tostring(err)))
        return
      end

      local function await_arrival()
        if not is_execution_current() then return end
        local current_room = mm.current_room()
        if tostring(current_room or "") == tostring(walkto_target) then
          mm.debug(string.format(
            "CEXIT DEBUG: walkto confirmed room=%s; releasing step[%d]",
            tostring(walkto_target),
            index + 1
          ))
          schedule(step_gap, function() run_from(index + 1) end)
          return
        end
        schedule(0.1, await_arrival)
      end
      await_arrival()
      return
    end

    mm.debug(string.format("CEXIT DEBUG: step[%d]='%s' released", index, step))
    run_cexit_step(step)
    schedule(step_gap, function() run_from(index + 1) end)
  end

  schedule_cexit_confirmation()
  run_from(1)
  return true
end

local function print_cexits_table(rows)
  cecho("<gray>#   From     Area         Name                           Dir                    Key                    Alternate              Lock   To<reset>\n")
  cecho("<gray>------------------------------------------------------------------------------------------------------------------------------------------<reset>\n")
  for i, row in ipairs(rows) do
    local from = tonumber(row.uid or row.fromuid) or -1
    local to = tonumber(row.touid) or -1
    local area = tostring(row.area or "")
    local name = tostring(row.name or "")
    local dir = tostring(row.dir or "")
    local key_name = tostring(row.key_name or "")
    local key_keywords = normalize_keyword_signature(row.key_keywords)
    local key_label = "-"
    if key_keywords ~= "" then
      key_label = "kw:" .. key_keywords
    elseif key_name ~= "" then
      key_label = "NEEDS KEYID"
    end
    local alternate = tostring(row.alternate_command or "")
    if alternate == "" then alternate = "-" end
    local level = tonumber(row.level) or 0
    cecho(string.format("<light_grey>%-3d<reset> ", i))
    if from > 0 then
      echoLink(string.format("(%d)", from), [[mm.goto_room(]] .. from .. [[)]], "Go to source room", true)
    else
      echo("(?)")
    end
    cecho(string.format(
      "  <light_grey>%-10.10s %-30.30s %-22.22s %-22.22s %-22.22s %-6d<reset> ",
      area, name, dir, key_label, alternate, level
    ))
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
  local where = "lower(exits.dir) NOT IN ('n','s','e','w','u','d','north','south','east','west','up','down') AND exits.fromuid NOT IN ('*','**')"
  local intro = "The following rooms have custom exits:"
  if lower == "thisroom" then
    local room = mm.current_room()
    if not room then return nil, nil, "CEXITS THISROOM ERROR: unknown current room; try LOOK" end
    where = where .. " AND exits.fromuid = " .. mm.sql_escape(room)
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

  local sql = "SELECT COALESCE(rooms.uid, exits.fromuid) AS uid, COALESCE(rooms.name, exits.fromuid) AS name, COALESCE(rooms.area, '') AS area, exits.dir, exits.touid, exits.level, cka.key_name, cka.key_keywords, cka.alternate_command "
    .. "FROM exits LEFT JOIN rooms ON rooms.uid = exits.fromuid "
    .. "LEFT JOIN cexit_key_alternates AS cka ON cka.fromuid = exits.fromuid AND cka.dir = exits.dir AND cka.touid = exits.touid "
    .. "WHERE " .. where .. " ORDER BY area, uid, exits.dir"
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

local function random_cexit_where_for_scope(scope_arg)
  local arg = tostring(scope_arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local lower = arg:lower()
  local where = "1=1"
  local intro = "The following rooms have random custom exits:"
  if lower == "thisroom" then
    local room = mm.current_room()
    if not room then return nil, nil, "RANDOM CEXITS THISROOM ERROR: unknown current room; try LOOK" end
    where = "random_cexits.fromuid = " .. mm.sql_escape(room)
    intro = "The following random custom exits are in this room:"
  elseif lower == "here" then
    local area = current_area_name()
    if area == "" then return nil, nil, "RANDOM CEXITS HERE ERROR: unknown current area; try LOOK" end
    where = "lower(rooms.area) = " .. mm.sql_escape(area:lower())
    intro = "The following rooms in the current area have random custom exits:"
  elseif lower:match("^area%s+") then
    local area_name = arg:sub(6):gsub("^%s+", ""):gsub("%s+$", "")
    if area_name == "" then return nil, nil, "Usage: mapper randomcexits area <area name>" end
    where = "lower(rooms.area) LIKE " .. mm.sql_escape("%" .. area_name:lower() .. "%")
    intro = string.format("The following rooms in areas partially matching '%s' have random custom exits:", area_name)
  elseif lower ~= "" then
    where = "lower(rooms.area) LIKE " .. mm.sql_escape("%" .. lower .. "%")
    intro = string.format("The following rooms in areas partially matching '%s' have random custom exits:", arg)
  end
  return where, intro, nil
end

local function print_random_cexits_table(rows)
  cecho("<gray>#   From     Area         Name                           Command                 Possible destinations<reset>\n")
  cecho("<gray>-------------------------------------------------------------------------------------------------------------<reset>\n")
  for i, row in ipairs(rows) do
    local from = tonumber(row.fromuid) or -1
    cecho(string.format("<light_grey>%-3d<reset> ", i))
    if from > 0 then
      echoLink(string.format("(%d)", from), [[mm.goto_room(]] .. from .. [[)]], "Go to source room", true)
    else
      echo("(?)")
    end
    cecho(string.format(
      "  <light_grey>%-10.10s %-30.30s %-23.23s {%s}<reset>\n",
      tostring(row.area or ""),
      tostring(row.name or ""),
      tostring(row.dir or ""),
      table.concat(row.destinations or {}, ", ")
    ))
    if i >= 200 then break end
  end
end

function mm.list_random_cexits(scope_arg)
  local ensured, ensure_err = mm.ensure_random_cexits_table()
  if not ensured then return false, ensure_err end

  local where, intro, err = random_cexit_where_for_scope(scope_arg)
  if not where then return false, err end
  local rows, qerr = mm.query_mapper_db(
    "SELECT random_cexits.fromuid, COALESCE(rooms.name, random_cexits.fromuid) AS name, " ..
    "COALESCE(rooms.area, '') AS area, random_cexits.dir, random_cexits.touid, random_cexits.level " ..
    "FROM random_cexits LEFT JOIN rooms ON rooms.uid = random_cexits.fromuid WHERE " .. where ..
    " ORDER BY area, random_cexits.fromuid, random_cexits.dir, random_cexits.touid"
  )
  if not rows then return false, qerr end

  local grouped, by_key = {}, {}
  for _, row in ipairs(rows) do
    local key = tostring(row.fromuid) .. "\0" .. tostring(row.dir)
    local entry = by_key[key]
    if not entry then
      entry = {
        fromuid = tostring(row.fromuid or ""),
        area = tostring(row.area or ""),
        name = tostring(row.name or ""),
        dir = tostring(row.dir or ""),
        level = tonumber(row.level) or 0,
        destinations = {},
      }
      by_key[key] = entry
      table.insert(grouped, entry)
    end
    table.insert(entry.destinations, tostring(row.touid or ""))
  end

  mm.runtime.random_cexit_last_rows = grouped
  mm.note(intro)
  if #grouped == 0 then mm.note("Found 0 random custom exits."); return true end
  print_random_cexits_table(grouped)
  mm.note(string.format("Found %d random custom exits.", #grouped))
  return true
end

function mm.delete_random_cexit(index)
  local n = tonumber(index)
  if not n then return false, "Usage: mapper deleterandomcexit <number>" end
  local rows = mm.runtime.random_cexit_last_rows or {}
  local row = rows[n]
  if not row then
    return false, "DELETE RANDOM CEXIT ERROR: index out of range for last shown randomcexits table"
  end

  local ok, err = mm.exec_mapper_db(string.format(
    "DELETE FROM random_cexits WHERE fromuid=%s AND dir=%s",
    mm.sql_escape(row.fromuid), mm.sql_escape(row.dir)
  ))
  if not ok then return false, err end
  table.remove(rows, n)
  mm.runtime.random_cexit_last_rows = rows
  mm.note(string.format(
    "Deleted random cexit: from (%s) dir '%s' to {%s}.",
    tostring(row.fromuid), tostring(row.dir), table.concat(row.destinations or {}, ", ")
  ))
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

  local alt_ok, alt_err = mm.exec_mapper_db(string.format(
    "DELETE FROM cexit_key_alternates WHERE fromuid=%s",
    mm.sql_escape(room)
  ))
  if not alt_ok then mm.warn("Could not remove conditional cexits from this room: " .. tostring(alt_err)) end

  local observed_ok, observed_err = mm.exec_mapper_db(string.format(
    "DELETE FROM cexit_key_observations WHERE fromuid=%s",
    mm.sql_escape(room)
  ))
  if not observed_ok then mm.warn("Could not remove cexit key observations from this room: " .. tostring(observed_err)) end

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
  local entry = {
    fromuid = tostring(row.uid or row.fromuid or ""),
    touid = tostring(row.touid or ""),
    dir = tostring(row.dir or ""),
    area = tostring(row.area or ""),
    name = tostring(row.name or ""),
    level = tonumber(row.level) or 0,
    deleted_at = os.time(),
  }
  local key_name = trim(row.key_name)
  local key_keywords = normalize_keyword_signature(row.key_keywords)
  local alternate_command = trim(row.alternate_command)
  if key_keywords ~= "" and alternate_command ~= "" then
    entry.key_name = key_name
    entry.key_keywords = key_keywords
    entry.alternate_command = alternate_command
  end
  return entry
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

  local alt_ok, alt_err = mm.exec_mapper_db(string.format(
    "DELETE FROM cexit_key_alternates WHERE fromuid=%s AND dir=%s",
    mm.sql_escape(entry.fromuid), mm.sql_escape(entry.dir)
  ))
  if not alt_ok then
    mm.warn("Could not remove the cexit's conditional alternate: " .. tostring(alt_err))
  end

  local observed_ok, observed_err = mm.exec_mapper_db(string.format(
    "DELETE FROM cexit_key_observations WHERE fromuid=%s AND dir=%s AND touid=%s",
    mm.sql_escape(entry.fromuid), mm.sql_escape(entry.dir), mm.sql_escape(entry.touid)
  ))
  if not observed_ok then
    mm.warn("Could not remove the cexit's key observations: " .. tostring(observed_err))
  end

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
      level = tonumber(row.level) or 0,
      key_name = row.key_name,
      key_keywords = row.key_keywords,
      alternate_command = row.alternate_command,
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
  local level = tonumber(row.level) or 0
  local ok, err = mm.exec_mapper_db(string.format(
    "INSERT OR REPLACE INTO exits (fromuid, dir, touid, level) VALUES (%s, %s, %s, %d)",
    mm.sql_escape(row.fromuid), mm.sql_escape(row.dir), mm.sql_escape(row.touid), level
  ))
  if not ok then return false, err end
  if normalize_keyword_signature(row.key_keywords) ~= "" and trim(row.alternate_command) ~= "" then
    local alt_ready, alt_ready_err = mm.ensure_cexit_key_alternates_table()
    if not alt_ready then return false, alt_ready_err end
    local alt_ok, alt_err = mm.exec_mapper_db(string.format(
      "INSERT OR REPLACE INTO cexit_key_alternates (fromuid, dir, touid, key_name, key_keywords, alternate_command) VALUES (%s, %s, %s, %s, %s, %s)",
      mm.sql_escape(row.fromuid), mm.sql_escape(row.dir), mm.sql_escape(row.touid),
      mm.sql_escape(row.key_name), mm.sql_escape(row.key_keywords), mm.sql_escape(row.alternate_command)
    ))
    if not alt_ok then return false, alt_err end
  end
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
