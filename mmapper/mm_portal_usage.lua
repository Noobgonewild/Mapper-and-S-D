mm = mm or {}

mm.portal_usage = mm.portal_usage or {}
local usage = mm.portal_usage

local STATE_DB_FILE = "mmapper_state.db"
local LEGACY_DB_FILE = "mmapper_frontiers.db"
local SCHEMA_VERSION = 1
local CONFIRM_TIMEOUT_SECONDS = 10
local PORTAL_INTENT_TIMEOUT_SECONDS = 20
local RECENT_HISTORY_LIMIT = 50
local REASON_LABELS = {
  gmcp_destination_mismatch = "GMCP destination mismatch",
  confirmation_timeout = "confirmation timeout",
  superseded_by_new_enter = "superseded by new enter",
  package_reloaded = "package reloaded",
  magic_walls_bounced_portal = "magic walls bounced portal",
  portal_blocked = "portal blocked",
}

usage.runtime = usage.runtime or {}
usage.last_rows = usage.last_rows or {}

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalized_id(value)
  local text = trim(value)
  if text == "" then return nil end
  local numeric = tonumber(text)
  if numeric then return tostring(math.floor(numeric)) end
  return text
end

local function path_exists(path)
  if type(mm.path_exists) == "function" then
    return mm.path_exists(path)
  end
  local file = io.open(path, "rb")
  if not file then return false end
  file:close()
  return true
end

local function sql_quote(value)
  if type(mm.sql_escape) == "function" then
    return mm.sql_escape(value)
  end
  return "'" .. tostring(value or ""):gsub("'", "''") .. "'"
end

local function sql_nullable(value)
  if value == nil or trim(value) == "" then return "NULL" end
  return sql_quote(value)
end

local function sql_number(value)
  local numeric = tonumber(value)
  return numeric and tostring(numeric) or "NULL"
end

local function close_cursor(cursor)
  if type(cursor) == "userdata" and type(cursor.close) == "function" then
    pcall(function() cursor:close() end)
  end
end

local function close_database(env, conn)
  if conn then pcall(function() conn:close() end) end
  if env then pcall(function() env:close() end) end
end

local function state_path()
  if type(mm.persistence_path) == "function" then
    return mm.persistence_path(STATE_DB_FILE)
  end
  return getMudletHomeDir() .. "/persistence/" .. STATE_DB_FILE
end

local function legacy_path()
  if type(mm.persistence_path) == "function" then
    return mm.persistence_path(LEGACY_DB_FILE)
  end
  return getMudletHomeDir() .. "/persistence/" .. LEGACY_DB_FILE
end

function usage.get_database_path()
  return state_path()
end

local function migrate_legacy_database()
  local target = state_path()
  local legacy = legacy_path()
  if path_exists(target) or not path_exists(legacy) then
    return true, false
  end

  local renamed, rename_err = os.rename(legacy, target)
  if not renamed then
    return false, "could not rename " .. legacy .. " to " .. target .. ": " .. tostring(rename_err)
  end
  return true, true
end

local function open_database()
  local ok, luasql = pcall(require, "luasql.sqlite3")
  if not ok or not luasql then
    return nil, nil, "LuaSQL sqlite3 module not available"
  end

  local env = luasql.sqlite3()
  if not env then return nil, nil, "failed to create SQLite environment" end
  local conn, conn_err = env:connect(state_path())
  if not conn then
    env:close()
    return nil, nil, "failed to open " .. state_path() .. ": " .. tostring(conn_err)
  end
  conn:execute("PRAGMA busy_timeout = 2000")
  return env, conn
end

local function execute(conn, sql)
  local result, err = conn:execute(sql)
  if not result then return false, tostring(err) end
  close_cursor(result)
  return true
end

local function execute_exactly_one(conn, sql)
  local result, err = conn:execute(sql)
  if not result then return false, tostring(err) end
  close_cursor(result)
  local affected = tonumber(result)
  if affected ~= 1 then
    return false, "expected one affected row, got " .. tostring(result)
  end
  return true
end

local function query_connection(conn, sql)
  local cursor, err = conn:execute(sql)
  if not cursor then return nil, tostring(err) end
  if type(cursor) ~= "userdata" or type(cursor.fetch) ~= "function" then
    return {}
  end

  local rows = {}
  local row = cursor:fetch({}, "a")
  while row do
    local copy = {}
    for key, value in pairs(row) do copy[key] = value end
    table.insert(rows, copy)
    row = cursor:fetch(row, "a")
  end
  close_cursor(cursor)
  return rows
end

local function with_database(callback)
  local env, conn, open_err = open_database()
  if not conn then return nil, open_err end
  local ok, first, second = pcall(callback, conn)
  close_database(env, conn)
  if not ok then return nil, tostring(first) end
  return first, second
end

local SCHEMA = {
  [[CREATE TABLE IF NOT EXISTS portal_usage (
      portal_id TEXT PRIMARY KEY,
      confirmed_count INTEGER NOT NULL DEFAULT 0,
      attempt_count INTEGER NOT NULL DEFAULT 0,
      blocked_count INTEGER NOT NULL DEFAULT 0,
      unconfirmed_count INTEGER NOT NULL DEFAULT 0,
      manual_count INTEGER NOT NULL DEFAULT 0,
      mapper_count INTEGER NOT NULL DEFAULT 0,
      first_used_at INTEGER,
      last_used_at INTEGER,
      last_attempt_at INTEGER,
      last_was_chaos INTEGER,
      portal_name TEXT,
      portal_color_name TEXT,
      portal_level INTEGER,
      last_source_room_id TEXT,
      last_source_room_name TEXT,
      last_source_area TEXT,
      last_landing_room_id TEXT,
      last_landing_room_name TEXT,
      last_landing_area TEXT,
      updated_at INTEGER NOT NULL DEFAULT 0
  )]],
  [[CREATE TABLE IF NOT EXISTS portal_usage_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      portal_id TEXT NOT NULL,
      attempted_at INTEGER NOT NULL,
      completed_at INTEGER,
      status TEXT NOT NULL DEFAULT 'pending',
      reason TEXT,
      was_chaos INTEGER NOT NULL DEFAULT 0,
      use_mode TEXT NOT NULL DEFAULT 'manual',
      source_room_id TEXT,
      source_room_name TEXT,
      source_area TEXT,
      expected_room_id TEXT,
      landing_room_id TEXT,
      landing_room_name TEXT,
      landing_area TEXT,
      gq_active INTEGER,
      portal_name TEXT,
      portal_level INTEGER
  )]],
  [[CREATE INDEX IF NOT EXISTS idx_portal_usage_last_used
      ON portal_usage(last_used_at)]],
  [[CREATE INDEX IF NOT EXISTS idx_portal_usage_history_portal
      ON portal_usage_history(portal_id, id DESC)]],
}

function usage.initialize()
  if type(mm.ensure_dir) == "function" then
    mm.ensure_dir(getMudletHomeDir() .. "/persistence")
  end
  local migrated_ok, migrated_or_err = migrate_legacy_database()
  if not migrated_ok then
    usage.runtime.ready = false
    return false, migrated_or_err
  end

  local result, schema_err = with_database(function(conn)
    local ok, err = execute(conn, "BEGIN IMMEDIATE")
    if ok then
      for _, statement in ipairs(SCHEMA) do
        ok, err = execute(conn, statement)
        if not ok then break end
      end
    end
    if ok then
      local version_rows, version_err = query_connection(conn, "PRAGMA user_version")
      if not version_rows then
        ok, err = false, version_err
      elseif (tonumber(version_rows[1] and (version_rows[1].user_version or version_rows[1][1])) or 0) < SCHEMA_VERSION then
        ok, err = execute(conn, "PRAGMA user_version = " .. tostring(SCHEMA_VERSION))
      end
    end
    if ok then
      ok, err = execute(conn, "COMMIT")
    end
    if not ok then
      pcall(function() conn:execute("ROLLBACK") end)
      return false, err
    end
    return true
  end)

  if not result then
    usage.runtime.ready = false
    return false, schema_err
  end
  usage.runtime.ready = true
  usage.runtime.migrated_legacy = migrated_or_err == true
  return true, {path = state_path(), migrated = usage.runtime.migrated_legacy}
end

local function ensure_ready()
  if usage.runtime.ready == true then return true end
  local ok, err = usage.initialize()
  if not ok then return false, err end
  return true
end

local function query(sql)
  local ready, ready_err = ensure_ready()
  if not ready then return nil, ready_err end
  return with_database(function(conn)
    return query_connection(conn, sql)
  end)
end

local function find_mapper_portal(portal_id)
  local wanted = tostring(portal_id or "")
  for _, portal in ipairs(mm.portals and mm.portals.rebuilt or {}) do
    if tostring(portal.portal_id or "") == wanted then return portal end
  end
  return nil
end

local function is_inventory_portal(portal)
  if type(portal) ~= "table" then return false end
  local command = trim(portal.command):lower()
  return command:match("^dinv%s+portal%s+use%s+[%w_%-]+") ~= nil
end

local function dinv_portal_items()
  local api = _G.DINV and _G.DINV.api
  if not api or type(api.getPortals) ~= "function" then return {} end
  local ok, result = pcall(api.getPortals, {
    source = "auto",
    fields = {"id", "name", "colorName", "level", "type", "location", "worn"},
  })
  if not ok or type(result) ~= "table" or result.ok ~= true then return {} end
  local by_id = {}
  for _, item in ipairs(result.items or {}) do
    local id = normalized_id(item.id)
    if id then by_id[id] = item end
  end
  return by_id
end

local function strip_aard_colors(value)
  return tostring(value or ""):gsub("@.", "")
end

local function metadata_for_item(item)
  item = type(item) == "table" and item or {}
  local name = trim(item.name)
  local color_name = trim(item.colorName or item.color_name)
  if name == "" and color_name ~= "" then name = trim(strip_aard_colors(color_name)) end
  return {
    name = name ~= "" and name or nil,
    color_name = color_name ~= "" and color_name or nil,
    level = tonumber(item.level),
  }
end

local function sync_metadata(portals, dinv_items)
  local ready, ready_err = ensure_ready()
  if not ready then return false, ready_err end

  local ok, err = with_database(function(conn)
    local began, begin_err = execute(conn, "BEGIN IMMEDIATE")
    if not began then return false, begin_err end
    local timestamp = os.time()
    for _, portal in ipairs(portals or {}) do
      if is_inventory_portal(portal) then
        local id = normalized_id(portal.portal_id)
        local metadata = metadata_for_item(dinv_items[id])
        local inserted, insert_err = execute(conn, string.format(
          "INSERT OR IGNORE INTO portal_usage (portal_id, portal_name, portal_color_name, portal_level, updated_at) VALUES (%s, %s, %s, %s, %d)",
          sql_quote(id), sql_nullable(metadata.name), sql_nullable(metadata.color_name),
          sql_number(metadata.level), timestamp
        ))
        if not inserted then
          pcall(function() conn:execute("ROLLBACK") end)
          return false, insert_err
        end
        if metadata.name or metadata.color_name or metadata.level then
          local updated, update_err = execute(conn, string.format([[
            UPDATE portal_usage
            SET portal_name=COALESCE(%s, portal_name),
                portal_color_name=COALESCE(%s, portal_color_name),
                portal_level=COALESCE(%s, portal_level),
                updated_at=%d
            WHERE portal_id=%s]],
            sql_nullable(metadata.name), sql_nullable(metadata.color_name),
            sql_number(metadata.level), timestamp, sql_quote(id)
          ))
          if not updated then
            pcall(function() conn:execute("ROLLBACK") end)
            return false, update_err
          end
        end
      end
    end
    local committed, commit_err = execute(conn, "COMMIT")
    if not committed then
      pcall(function() conn:execute("ROLLBACK") end)
      return false, commit_err
    end
    return true
  end)
  return ok == true, err
end

function usage.prepare_rows(portals)
  portals = portals or {}
  local dinv_items = dinv_portal_items()
  local synced, sync_err = sync_metadata(portals, dinv_items)
  if not synced and not usage.runtime.warned_database then
    usage.runtime.warned_database = true
    if mm and mm.warn then mm.warn("Portal usage database unavailable: " .. tostring(sync_err)) end
  end

  local ids = {}
  for _, portal in ipairs(portals) do
    if is_inventory_portal(portal) then
      local id = normalized_id(portal.portal_id)
      if id then table.insert(ids, sql_quote(id)) end
    end
  end

  local rows_by_id = {}
  if #ids > 0 then
    local rows = query("SELECT * FROM portal_usage WHERE portal_id IN (" .. table.concat(ids, ",") .. ")") or {}
    for _, row in ipairs(rows) do rows_by_id[tostring(row.portal_id)] = row end
  end

  usage.last_rows = {}
  for _, portal in ipairs(portals) do
    local id = normalized_id(portal.portal_id)
    local stored = id and rows_by_id[id] or nil
    local item = id and dinv_items[id] or nil
    local metadata = metadata_for_item(item)
    portal.usage_trackable = is_inventory_portal(portal)
    portal.usage_count = portal.usage_trackable and (tonumber(stored and stored.confirmed_count) or 0) or nil
    portal.portal_name = metadata.name or (stored and trim(stored.portal_name) ~= "" and stored.portal_name) or portal.portal_name
    portal.portal_color_name = metadata.color_name or (stored and trim(stored.portal_color_name) ~= "" and stored.portal_color_name) or portal.portal_color_name
    -- Keep DINV's physical item level as metadata. The public portal level is
    -- the mapper lock persisted in Aardwolf.db exits.level.
    portal.portal_item_level = metadata.level
      or tonumber(stored and stored.portal_level)
      or tonumber(portal.portal_item_level)
    portal.portal_level = tonumber(portal.level) or 0
    usage.last_rows[tonumber(portal.nr) or #usage.last_rows + 1] = portal
  end
  return portals
end

function usage.count_color(portal, minimum, maximum)
  if not portal or not portal.usage_trackable then return "dim_gray", "-" end
  local count = tonumber(portal.usage_count) or 0
  if minimum ~= nil and maximum ~= nil and minimum ~= maximum then
    if count == minimum then return "red", tostring(count) end
    if count == maximum then return "green", tostring(count) end
  end
  return "white", tostring(count)
end

function usage.count_range(portals)
  local minimum, maximum
  for _, portal in ipairs(portals or {}) do
    if portal.usage_trackable then
      local count = tonumber(portal.usage_count) or 0
      minimum = minimum == nil and count or math.min(minimum, count)
      maximum = maximum == nil and count or math.max(maximum, count)
    end
  end
  return minimum, maximum
end

local function configured_report_channel()
  local channel = snd and snd.config and trim(snd.config.reportChannel) or ""
  return channel ~= "" and channel or "default"
end

local function channel_label(channel)
  channel = trim(channel):lower()
  if channel == "" or channel == "default" or channel == "echo" then return "Echo" end
  if channel == "group" or channel == "gtell" then return "Group" end
  return channel:gsub("^%l", string.upper)
end

local function echo_report_link(label, menu_label, reporter, fallback_command)
  local channel = configured_report_channel()
  if type(cechoPopup) == "function" then
    cechoPopup(
      "<deep_sky_blue>" .. label .. "<reset>",
      {
        function() reporter(channel) end,
        "",
        function() reporter(channel) end,
        "",
        function() reporter("clan") end,
        "",
        function() reporter("say") end,
        "",
        function() reporter("gtell") end,
      },
      {
        "Left-click: report this portal via " .. channel_label(channel) .. "\nRight-click for other channels",
        menu_label,
        "",
        channel_label(channel),
        "",
        "Clan",
        "",
        "Say",
        "",
        "Group",
      },
      true
    )
  elseif type(cechoLink) == "function" then
    cechoLink(
      "<deep_sky_blue>" .. label .. "<reset>",
      fallback_command,
      "Report this portal",
      true
    )
  else
    cecho("<deep_sky_blue>" .. label .. "<reset>")
  end
end

function usage.echo_report_link(index)
  local label = string.format("[%2s]", tostring(index or "?"))
  echo_report_link(
    label,
    label,
    function(channel) usage.report_from_link(index, channel) end,
    string.format("mm.portal_usage.report_from_link(%d)", tonumber(index) or 0)
  )
end

function usage.echo_report_id_link(portal_id, display_label)
  local id = normalized_id(portal_id)
  local label = tostring(display_label or id or "?")
  if not id then
    cecho("<deep_sky_blue>" .. label .. "<reset>")
    return
  end
  echo_report_link(
    label,
    id,
    function(channel) usage.report_id_from_link(id, channel) end,
    string.format("mm.portal_usage.report_id_from_link(%q)", id)
  )
end

function usage.report_from_link(index, channel)
  local ok, err = usage.report(index, channel)
  if not ok and mm and mm.warn then mm.warn(err) end
  return ok
end

function usage.report_id_from_link(portal_id, channel)
  local ok, err = usage.report_by_id(portal_id, channel)
  if not ok and mm and mm.warn then mm.warn(err) end
  return ok
end

local function portal_report_parts(portal)
  local count = tonumber(portal.usage_count) or 0
  local name = trim(portal.portal_name)
  if name == "" then name = "an unknown portal" end
  local room = trim(portal.room_name)
  if room == "" then room = "?" end
  local area = trim(portal.area)
  if area == "" then area = "?" end
  local level = tonumber(portal.level) or tonumber(portal.portal_level) or 0
  local times = count == 1 and "time" or "times"
  return name, room, area, level, count, times
end

local function has_leading_aard_color(value)
  value = tostring(value or "")
  return value:match("^@x%d%d?%d?") ~= nil
    or value:match("^@[krgybmcwDRGYBMCW]") ~= nil
end

local function native_portal_name(color_name, plain_name, chaos)
  local name = trim(color_name)
  if name == "" then name = trim(plain_name) end
  if name == "" then name = "an unknown portal" end
  if chaos and not has_leading_aard_color(name) then
    name = "@M" .. name .. "@W"
  end
  return name
end

function usage.build_report(portal)
  local name, room, area, level, count, times = portal_report_parts(portal)
  local chaos = mm.is_portal_chaos and mm.is_portal_chaos(portal) or false
  local colored_name = native_portal_name(portal.portal_color_name, name, chaos)

  return string.format(
    "%s - @W%s @D(@W%s@D)@W | @Clevel %d@W | used @C%d %s@W",
    colored_name, room, area, level, count, times
  )
end

local function render_aard_for_cecho(payload)
  local rendered = tostring(payload or "")
  if snd and snd.utils and type(snd.utils.aardColorsToMudlet) == "function" then
    rendered = snd.utils.aardColorsToMudlet(rendered)
    -- This Mudlet build expects decimal RGB cecho tags, not <#rrggbb>.
    rendered = rendered:gsub("<#(%x%x)(%x%x)(%x%x)>", function(red, green, blue)
      return string.format("<%d,%d,%d>", tonumber(red, 16), tonumber(green, 16), tonumber(blue, 16))
    end)
    return rendered, true
  end
  return rendered, false
end

local function echo_aard_text(payload, newline)
  local rendered, is_cecho = render_aard_for_cecho(payload)
  local suffix = newline and "\n" or ""
  if is_cecho and type(cecho) == "function" then
    cecho(rendered .. suffix)
  elseif type(echo) == "function" then
    echo(rendered .. suffix)
  end
end

local function echo_aard_report(payload)
  echo_aard_text(payload, true)
end

local function dispatch_report(channel, payload)
  channel = trim(channel)
  if channel == "" then channel = configured_report_channel() end
  if channel:lower() == "group" then channel = "gtell" end
  local lower = channel:lower()
  if lower == "default" or lower == "echo" then
    return false
  end
  if snd and snd.utils and type(snd.utils.dispatchReportChannel) == "function" then
    return snd.utils.dispatchReportChannel(channel, payload)
  end
  if type(send) == "function" then
    send(channel .. " " .. payload, false)
    return true
  end
  return false
end

local function report_portal(portal, channel)
  local selected_channel = trim(channel)
  if selected_channel == "" then selected_channel = configured_report_channel() end
  if selected_channel:lower() == "default" or selected_channel:lower() == "echo" then
    echo_aard_report(usage.build_report(portal))
    return true
  end
  local payload = usage.build_report(portal)
  if not dispatch_report(selected_channel, payload) then
    return false, "Could not report portal row via channel: " .. tostring(selected_channel)
  end
  return true
end

function usage.report(index, channel)
  index = tonumber(index)
  if not index then return false, "Invalid portal report row" end
  local portal = usage.last_rows[index] or (mm.portals and mm.portals.rebuilt and mm.portals.rebuilt[index])
  if not portal then
    return false, "No portal row #" .. tostring(index) .. ". Run 'mapper portals' first."
  end
  usage.prepare_rows({portal})
  if not portal.usage_trackable then
    return false, "Portal row #" .. tostring(index) .. " is not a DINV handheld portal."
  end
  return report_portal(portal, channel)
end

function usage.report_by_id(portal_id, channel)
  local id = normalized_id(portal_id)
  if not id then return false, "Invalid portal ID" end

  local portal = find_mapper_portal(id)
  if portal then
    usage.prepare_rows({portal})
    if not portal.usage_trackable then
      return false, "Portal ID " .. id .. " is not a DINV handheld portal."
    end
    return report_portal(portal, channel)
  end

  local rows, rows_err = query(string.format([[
    SELECT portal_id, confirmed_count, last_was_chaos, portal_name,
           portal_color_name, portal_level, last_landing_room_name,
           last_landing_area
    FROM portal_usage
    WHERE portal_id=%s
    LIMIT 1
  ]], sql_quote(id)))
  if not rows then return false, rows_err end
  local row = rows[1]
  if not row then return false, "No portal usage found for ID " .. id .. "." end

  portal = {
    portal_id = id,
    portal_name = row.portal_name,
    portal_color_name = row.portal_color_name,
    room_name = row.last_landing_room_name,
    area = row.last_landing_area,
    level = tonumber(row.portal_level) or 0,
    usage_count = tonumber(row.confirmed_count) or 0,
    usage_trackable = true,
    chaos = tonumber(row.last_was_chaos) == 1 and "yes" or "no",
  }
  return report_portal(portal, channel)
end

local function clean_stat_text(value, fallback)
  local text = tostring(value or "")
  if mm and type(mm.strip_ansi) == "function" then text = mm.strip_ansi(text) end
  text = trim(text):gsub("[\r\n\t]+", " ")
  return text ~= "" and text or (fallback or "?")
end

local function display_reason(value)
  local code = clean_stat_text(value, "")
  if code == "" then return "unknown/unrecorded" end
  return REASON_LABELS[code] or code:gsub("_", " ")
end

local function stat_date(value)
  local timestamp = tonumber(value)
  if not timestamp or timestamp <= 0 then return "-" end
  return os.date("%Y-%m-%d", timestamp)
end

local function stat_recent_time(value)
  local timestamp = tonumber(value)
  if not timestamp or timestamp <= 0 then return "-" end
  return os.date("%m-%d %H:%M:%S", timestamp)
end

local function stat_last_time(value)
  local timestamp = tonumber(value)
  if not timestamp or timestamp <= 0 then return "-" end
  return os.date("%m-%d %H:%M", timestamp)
end

local function current_portal_stats(row)
  local portal = find_mapper_portal(row and row.portal_id)
  local chaos
  if portal and mm.is_portal_chaos then
    chaos = mm.is_portal_chaos(portal)
  else
    chaos = tonumber(row and row.last_was_chaos) == 1
  end
  local plain_name = row and trim(row.portal_name) ~= "" and row.portal_name
    or (portal and portal.portal_name)
  local name = native_portal_name(
    row and row.portal_color_name,
    plain_name,
    chaos
  )
  local room = clean_stat_text(
    portal and portal.room_name or (row and row.last_landing_room_name),
    "?"
  )
  local area = clean_stat_text(
    portal and portal.area or (row and row.last_landing_area),
    "?"
  )
  return {
    portal = portal,
    chaos = chaos,
    name = name,
    room = room,
    area = area,
    lock = portal and tonumber(portal.level) or nil,
  }
end

local function refresh_stats_metadata()
  local portals = mm.portals and mm.portals.rebuilt or {}
  if #portals == 0 then return true end
  return sync_metadata(portals, dinv_portal_items())
end

function usage.show_stats()
  refresh_stats_metadata()
  local rows, rows_err = query([[
    SELECT portal_id, confirmed_count, attempt_count, blocked_count, unconfirmed_count,
           manual_count, mapper_count, first_used_at, last_used_at, last_attempt_at,
           last_was_chaos, portal_name, portal_color_name,
           last_landing_room_id, last_landing_room_name, last_landing_area
    FROM portal_usage
    WHERE attempt_count > 0 OR confirmed_count > 0
       OR blocked_count > 0 OR unconfirmed_count > 0
    ORDER BY confirmed_count DESC, last_attempt_at DESC, portal_id
  ]])
  if not rows then return false, rows_err end

  local totals = {used = 0, tried = 0, manual = 0, mapper = 0, blocked = 0, unconfirmed = 0}
  for _, row in ipairs(rows) do
    totals.used = totals.used + (tonumber(row.confirmed_count) or 0)
    totals.tried = totals.tried + (tonumber(row.attempt_count) or 0)
    totals.manual = totals.manual + (tonumber(row.manual_count) or 0)
    totals.mapper = totals.mapper + (tonumber(row.mapper_count) or 0)
    totals.blocked = totals.blocked + (tonumber(row.blocked_count) or 0)
    totals.unconfirmed = totals.unconfirmed + (tonumber(row.unconfirmed_count) or 0)
  end

  local mapped = #(mm.portals and mm.portals.rebuilt or {})
  cecho("\n<white>Mapper Portal Statistics<reset>\n")
  cecho(string.format(
    "<dim_gray>Mapped: %d | Active: %d | Used/attempted: %d/%d | Manual/mapper: %d/%d | Blocked: %d | Unconfirmed: %d<reset>\n",
    mapped, #rows, totals.used, totals.tried, totals.manual, totals.mapper,
    totals.blocked, totals.unconfirmed
  ))
  cecho("<gray>------------------------------------------------------------------------------------------------------------------------------------------------<reset>\n")
  cecho(string.format(
    "<deep_sky_blue>%-12s %-6s %5s %11s %9s %5s %5s %-10s %-11s  %s<reset>\n",
    "Portal ID", "Now", "Lock", "Used/Tried", "Manual/X", "Block", "Uncf", "First", "Last", "Portal / destination"
  ))
  cecho("<gray>------------------------------------------------------------------------------------------------------------------------------------------------<reset>\n")

  if #rows == 0 then
    cecho("<yellow>No portal attempts have been recorded.<reset>\n")
  end

  for _, row in ipairs(rows) do
    local details = current_portal_stats(row)
    local lock = details.lock and tostring(details.lock) or "-"
    local used_tried = string.format("%d/%d", tonumber(row.confirmed_count) or 0, tonumber(row.attempt_count) or 0)
    local manual_mapper = string.format("%d/%d", tonumber(row.manual_count) or 0, tonumber(row.mapper_count) or 0)
    usage.echo_report_id_link(row.portal_id, string.format("%-12s", tostring(row.portal_id or "?")))
    cecho(string.format(
      " <%s>%-6s<reset> <white>%5s %11s %9s %5d %5d<reset> <dim_gray>%-10s %-11s<reset>  ",
      details.chaos and "medium_purple" or "light_grey",
      details.chaos and "Chaos" or "Normal", lock, used_tried, manual_mapper,
      tonumber(row.blocked_count) or 0, tonumber(row.unconfirmed_count) or 0,
      stat_date(row.first_used_at), stat_last_time(row.last_used_at)
    ))
    echo_aard_text(details.name, false)
    cecho(" <dim_gray>-<reset> <white>")
    echo(details.room)
    cecho("<reset> <dim_gray>(<white>")
    echo(details.area)
    cecho("<dim_gray>)<reset>\n")
  end
  cecho("<gray>------------------------------------------------------------------------------------------------------------------------------------------------<reset>\n")
  return true
end

local function recent_status_style(status)
  status = trim(status):lower()
  if status == "confirmed" then return "green", "Confirmed" end
  if status == "blocked" then return "red", "Blocked" end
  if status == "pending" then return "cyan", "Pending" end
  return "yellow", "Unconfirmed"
end

local function recent_room_label(id, name, area)
  if trim(id) == "" and trim(name) == "" and trim(area) == "" then return "-" end
  local room_id = clean_stat_text(id, "?")
  local room_name = clean_stat_text(name, "?")
  local room_area = clean_stat_text(area, "?")
  return string.format("%s %s (%s)", room_id, room_name, room_area)
end

function usage.show_stats_recent(count)
  count = math.floor(tonumber(count) or 20)
  count = math.max(1, math.min(RECENT_HISTORY_LIMIT, count))
  refresh_stats_metadata()
  local rows, rows_err = query(string.format([[
    SELECT h.*, u.portal_name AS current_portal_name,
           u.portal_color_name AS current_portal_color_name
    FROM portal_usage_history h
    LEFT JOIN portal_usage u ON u.portal_id = h.portal_id
    ORDER BY h.attempted_at DESC, h.id DESC
    LIMIT %d
  ]], count))
  if not rows then return false, rows_err end

  cecho(string.format("\n<white>Recent Portal Attempts<reset> <dim_gray>(newest %d)<reset>\n", count))
  cecho("<gray>------------------------------------------------------------------------------------------------------------------------------------------------<reset>\n")
  cecho("<deep_sky_blue> #  Time           Status       Mode    At use  GQ   Portal ID     Portal<reset>\n")
  cecho("<gray>------------------------------------------------------------------------------------------------------------------------------------------------<reset>\n")

  if #rows == 0 then
    cecho("<yellow>No portal attempts have been recorded.<reset>\n")
  end

  for index, row in ipairs(rows) do
    local status_color, status_label = recent_status_style(row.status)
    local was_chaos = tonumber(row.was_chaos) == 1
    local mode = trim(row.use_mode):lower() == "mapper" and "Mapper" or "Manual"
    local historical_name = trim(row.portal_name) ~= "" and row.portal_name or row.current_portal_name
    local portal_name = native_portal_name(
      row.current_portal_color_name,
      historical_name,
      was_chaos
    )
    cecho(string.format(
      "<deep_sky_blue>[%2d]<reset> <dim_gray>%-14s<reset> <%s>%-11s<reset> <cyan>%-7s<reset> <%s>%-7s<reset> <light_slate_blue>%-4s<reset> <khaki>%-13s<reset> ",
      index, stat_recent_time(row.attempted_at), status_color, status_label, mode,
      was_chaos and "medium_purple" or "light_grey", was_chaos and "Chaos" or "Normal",
      tonumber(row.gq_active) == 1 and "yes" or "no", tostring(row.portal_id or "?")
    ))
    echo_aard_text(portal_name, false)
    cecho("\n    <dim_gray>from<reset> ")
    echo(recent_room_label(row.source_room_id, row.source_room_name, row.source_area))
    cecho(" <dim_gray>-><reset> ")
    echo(recent_room_label(row.landing_room_id, row.landing_room_name, row.landing_area))

    local expected = normalized_id(row.expected_room_id)
    local landing = normalized_id(row.landing_room_id)
    if expected and expected ~= landing then
      cecho(" <dim_gray>| expected<reset> ")
      echo(expected)
    end
    if trim(row.status):lower() ~= "confirmed" then
      cecho(" <dim_gray>| reason:<reset> <yellow>")
      echo(display_reason(row.reason))
      cecho("<reset>")
    end
    cecho("\n")
  end
  cecho("<gray>------------------------------------------------------------------------------------------------------------------------------------------------<reset>\n")
  return true
end

local function current_room_snapshot()
  local info = type(mm.get_room_info) == "function" and mm.get_room_info() or nil
  info = type(info) == "table" and info or {}
  local snd_room = snd and snd.room and snd.room.current or nil
  local room_id = mm.canonical_room_uid(info)
  if not room_id then room_id = normalized_id(snd_room and snd_room.rmid) end
  local room_name = trim(info.name)
  if room_name == "" then room_name = trim(snd_room and snd_room.name) end
  local room_area = trim(info.zone or info.area)
  if room_area == "" then room_area = trim(snd_room and snd_room.arid) end
  return {
    id = normalized_id(room_id),
    name = room_name,
    area = room_area,
  }
end

local function currently_worn_portal()
  local api = _G.DINV and _G.DINV.api
  if not api then return nil, "DINV API is unavailable" end

  local fn = api.getCurrentlyWornPortal or api.getEquipped
  if type(fn) ~= "function" then return nil, "DINV equipped-item API is unavailable" end
  local ok, result
  if fn == api.getEquipped then
    ok, result = pcall(fn, "portal", {
      source = "auto",
      fields = {"id", "name", "colorName", "level", "type", "location", "worn"},
    })
  else
    ok, result = pcall(fn, {
      source = "auto",
      fields = {"id", "name", "colorName", "level", "type", "location", "worn"},
    })
  end
  if not ok or type(result) ~= "table" or result.ok ~= true then
    return nil, type(result) == "table" and result.message or tostring(result)
  end
  if tonumber(result.count) == 0 and not result.id and not result.item then
    return nil, "no portal is worn"
  end
  if tonumber(result.count) and tonumber(result.count) > 1 then
    return nil, "multiple items are marked as worn in the portal slot"
  end
  local item = type(result.item) == "table" and result.item or nil
  local id = normalized_id(result.id or (item and item.id))
  if not id then return nil, "worn portal has no object ID" end
  return {id = id, item = item or {id = id}}
end

local function gq_active()
  if snd and snd.gquest then
    local joined = snd.gquest.joined or snd.gquest.id
    return snd.gquest.active == true or (joined ~= nil and tostring(joined) ~= "-1")
  end
  return false
end

local function begin_attempt_row(attempt)
  local ready, ready_err = ensure_ready()
  if not ready then return nil, ready_err end
  return with_database(function(conn)
    local ok, err = execute(conn, "BEGIN IMMEDIATE")
    if not ok then return nil, err end
    local metadata = attempt.metadata or {}
    ok, err = execute(conn, string.format([[
      INSERT OR IGNORE INTO portal_usage
        (portal_id, portal_name, portal_color_name, portal_level, updated_at)
      VALUES (%s, %s, %s, %s, %d)]],
      sql_quote(attempt.portal_id), sql_nullable(metadata.name),
      sql_nullable(metadata.color_name), sql_number(metadata.level), attempt.started_at
    ))
    if ok then
      ok, err = execute(conn, string.format([[
        UPDATE portal_usage
        SET attempt_count=attempt_count+1,
            last_attempt_at=%d,
            last_was_chaos=%d,
            portal_name=COALESCE(%s, portal_name),
            portal_color_name=COALESCE(%s, portal_color_name),
            portal_level=COALESCE(%s, portal_level),
            last_source_room_id=%s,
            last_source_room_name=%s,
            last_source_area=%s,
            updated_at=%d
        WHERE portal_id=%s]],
        attempt.started_at, attempt.was_chaos and 1 or 0,
        sql_nullable(metadata.name), sql_nullable(metadata.color_name), sql_number(metadata.level),
        sql_nullable(attempt.source.id), sql_nullable(attempt.source.name), sql_nullable(attempt.source.area),
        attempt.started_at, sql_quote(attempt.portal_id)
      ))
    end
    if ok then
      ok, err = execute(conn, string.format([[
        INSERT INTO portal_usage_history
          (portal_id, attempted_at, status, was_chaos, use_mode,
           source_room_id, source_room_name, source_area, expected_room_id,
           gq_active, portal_name, portal_level)
        VALUES (%s, %d, 'pending', %d, %s, %s, %s, %s, %s, %d, %s, %s)]],
        sql_quote(attempt.portal_id), attempt.started_at, attempt.was_chaos and 1 or 0,
        sql_quote(attempt.mode), sql_nullable(attempt.source.id), sql_nullable(attempt.source.name),
        sql_nullable(attempt.source.area), sql_nullable(attempt.expected_room_id),
        attempt.gq_active and 1 or 0, sql_nullable(metadata.name), sql_number(metadata.level)
      ))
    end
    local history_id
    if ok then
      local rows, row_err = query_connection(conn, "SELECT last_insert_rowid() AS id")
      if not rows then ok, err = false, row_err else history_id = tonumber(rows[1] and rows[1].id) end
    end
    if ok then ok, err = execute(conn, "COMMIT") end
    if not ok then
      pcall(function() conn:execute("ROLLBACK") end)
      return nil, err
    end
    return history_id
  end)
end

local function stop_attempt_timer(attempt)
  if attempt and attempt.timer and type(killTimer) == "function" then
    pcall(killTimer, attempt.timer)
  end
  if attempt then attempt.timer = nil end
end

local function finish_attempt(status, reason)
  local attempt = usage.runtime.pending
  if not attempt or attempt.finished then return false end
  status = trim(status):lower()
  reason = trim(reason)
  if reason == "" then
    reason = status == "confirmed" and "confirmed_without_reason"
      or (status == "blocked" and "portal_blocked" or "unconfirmed_without_reason")
  end
  attempt.finished = true
  stop_attempt_timer(attempt)
  usage.runtime.pending = nil
  local completed_at = os.time()
  local landing = attempt.landing or {}
  local mode_column = attempt.mode == "mapper" and "mapper_count" or "manual_count"

  local result, finish_err = with_database(function(conn)
    local ok, err = execute(conn, "BEGIN IMMEDIATE")
    if not ok then return false, err end
    if status == "confirmed" then
      ok, err = execute(conn, string.format([[
        UPDATE portal_usage
        SET confirmed_count=confirmed_count+1,
            %s=%s+1,
            first_used_at=COALESCE(first_used_at, %d),
            last_used_at=%d,
            last_landing_room_id=%s,
            last_landing_room_name=%s,
            last_landing_area=%s,
            updated_at=%d
        WHERE portal_id=%s]],
        mode_column, mode_column, completed_at, completed_at,
        sql_nullable(landing.id), sql_nullable(landing.name), sql_nullable(landing.area),
        completed_at, sql_quote(attempt.portal_id)
      ))
    elseif status == "blocked" then
      ok, err = execute(conn, string.format(
        "UPDATE portal_usage SET blocked_count=blocked_count+1, updated_at=%d WHERE portal_id=%s",
        completed_at, sql_quote(attempt.portal_id)
      ))
    else
      ok, err = execute(conn, string.format(
        "UPDATE portal_usage SET unconfirmed_count=unconfirmed_count+1, updated_at=%d WHERE portal_id=%s",
        completed_at, sql_quote(attempt.portal_id)
      ))
    end
    if ok and attempt.history_id then
      ok, err = execute_exactly_one(conn, string.format([[
        UPDATE portal_usage_history
        SET completed_at=%d, status=%s, reason=%s,
            landing_room_id=%s, landing_room_name=%s, landing_area=%s
        WHERE id=%d]],
        completed_at, sql_quote(status), sql_quote(reason),
        sql_nullable(landing.id), sql_nullable(landing.name), sql_nullable(landing.area),
        attempt.history_id
      ))
    end
    if ok then
      ok, err = execute(conn, string.format([[
        DELETE FROM portal_usage_history
        WHERE portal_id=%s AND id NOT IN (
          SELECT id FROM portal_usage_history
          WHERE portal_id=%s ORDER BY id DESC LIMIT %d
        )]],
        sql_quote(attempt.portal_id), sql_quote(attempt.portal_id), RECENT_HISTORY_LIMIT
      ))
    end
    if ok then ok, err = execute(conn, "COMMIT") end
    if not ok then
      pcall(function() conn:execute("ROLLBACK") end)
      return false, err
    end
    return true
  end)
  if result ~= true and mm and mm.warn then
    mm.warn("Could not store portal usage result: " .. tostring(finish_err))
  end
  return result == true
end

local function evaluate_attempt()
  local attempt = usage.runtime.pending
  if not attempt or not attempt.saw_whoosh or not attempt.landing then return end
  if normalized_id(attempt.landing.id) == normalized_id(attempt.expected_room_id) then
    finish_attempt("confirmed", "whoosh_and_expected_gmcp_room")
  else
    finish_attempt("unconfirmed", "gmcp_destination_mismatch")
  end
end

function usage.note_mapper_portal_command(command)
  local id = trim(command):match("^[Dd][Ii][Nn][Vv]%s+[Pp][Oo][Rr][Tt][Aa][Ll]%s+[Uu][Ss][Ee]%s+([%w_%-]+)")
  if not id then return false end
  id = normalized_id(id)
  local portal = find_mapper_portal(id)
  usage.runtime.mapper_intent = {
    portal_id = id,
    expected_room_id = portal and normalized_id(portal.target_uid or portal.touid) or nil,
    created_at = os.time(),
  }
  return true
end

local function fresh_portal_intent(intent)
  if type(intent) ~= "table" or not normalized_id(intent.portal_id) then return false end
  local age = os.time() - (tonumber(intent.created_at) or 0)
  return age >= 0 and age <= PORTAL_INTENT_TIMEOUT_SECONDS
end

local function intended_portal_for_enter()
  local mapper_intent = usage.runtime.mapper_intent
  local hold_intent = usage.runtime.hold_intent
  local mapper_fresh = fresh_portal_intent(mapper_intent)
  local hold_fresh = fresh_portal_intent(hold_intent)
  local selected = hold_fresh and hold_intent or (mapper_fresh and mapper_intent or nil)

  usage.runtime.mapper_intent = nil
  usage.runtime.hold_intent = nil
  if not selected then return nil end

  local id = normalized_id(selected.portal_id)
  local portal = find_mapper_portal(id)
  if not portal or not is_inventory_portal(portal) then return nil end
  local mode = mapper_fresh and normalized_id(mapper_intent.portal_id) == id and "mapper" or "manual"
  local expected = normalized_id(portal.target_uid or portal.touid)
  if mode == "mapper" and mapper_intent.expected_room_id then
    expected = normalized_id(mapper_intent.expected_room_id) or expected
  end
  local item = dinv_portal_items()[id]
  return {
    id = id,
    item = item or {id = id},
    portal = portal,
    expected_room_id = expected,
    mode = mode,
    identity_source = hold_fresh and "hold_command" or "mapper_command",
  }
end

function usage.begin_attempt()
  if usage.runtime.pending then
    finish_attempt("unconfirmed", "superseded_by_new_enter")
  end
  local intended = intended_portal_for_enter()
  local worn, worn_err
  if intended then
    worn = {id = intended.id, item = intended.item}
  else
    worn, worn_err = currently_worn_portal()
    if not worn then
      if mm and mm.debug then mm.debug("Portal usage ignored at enter: " .. tostring(worn_err)) end
      return false, worn_err
    end
  end

  local portal = intended and intended.portal or find_mapper_portal(worn.id)
  if not portal or not is_inventory_portal(portal) then
    return false, "worn portal ID is not mapped"
  end
  local expected = intended and intended.expected_room_id
    or normalized_id(portal.target_uid or portal.touid)
  if not expected then return false, "mapped portal has no expected destination" end

  local mode = intended and intended.mode or "manual"

  local metadata = metadata_for_item(worn.item)
  local attempt = {
    serial = (tonumber(usage.runtime.serial) or 0) + 1,
    portal_id = worn.id,
    expected_room_id = expected,
    source = current_room_snapshot(),
    metadata = metadata,
    was_chaos = mm.is_portal_chaos and mm.is_portal_chaos(portal) or false,
    mode = mode,
    gq_active = gq_active(),
    started_at = os.time(),
    saw_whoosh = false,
    finished = false,
  }
  usage.runtime.serial = attempt.serial
  if mm and mm.debug then
    mm.debug(string.format(
      "Portal usage armed: id=%s expected=%s mode=%s source=%s",
      tostring(attempt.portal_id), tostring(attempt.expected_room_id), tostring(attempt.mode),
      tostring(intended and intended.identity_source or "worn_persistence")
    ))
  end
  local history_id, history_err = begin_attempt_row(attempt)
  if not history_id then
    return false, history_err
  end
  attempt.history_id = history_id
  usage.runtime.pending = attempt
  if type(tempTimer) == "function" then
    local serial = attempt.serial
    attempt.timer = tempTimer(CONFIRM_TIMEOUT_SECONDS, function()
      local pending = usage.runtime.pending
      if pending and pending.serial == serial then
        finish_attempt("unconfirmed", "confirmation_timeout")
      end
    end)
  end
  return true
end

function usage.on_data_send_request(...)
  for index = 1, select("#", ...) do
    local value = select(index, ...)
    local command_text
    if type(value) == "string" and value ~= "sysDataSendRequest" then
      command_text = value
    elseif type(value) == "table" then
      command_text = value.command or value.cmd or value.line
    end
    if command_text then
      for part in tostring(command_text):gmatch("[^;\r\n]+") do
        local command = trim(part)
        local held_id = command:match("^[Hh][Oo][Ll][Dd]%s+([%w_%-]+)")
        if held_id then
          held_id = normalized_id(held_id)
          if held_id and find_mapper_portal(held_id) then
            usage.runtime.hold_intent = {portal_id = held_id, created_at = os.time()}
          end
        elseif command:lower() == "enter" then
          usage.begin_attempt()
        end
      end
    end
  end
end

function usage.on_whoosh()
  local attempt = usage.runtime.pending
  if not attempt then return end
  attempt.saw_whoosh = true
  evaluate_attempt()
end

function usage.on_room_info(info)
  local attempt = usage.runtime.pending
  if not attempt or attempt.finished then return end
  info = type(info) == "table" and info or (type(mm.get_room_info) == "function" and mm.get_room_info() or {})
  local landing_id = normalized_id(mm.canonical_room_uid(info))
  if not landing_id or landing_id == normalized_id(attempt.source.id) then return end
  if not attempt.landing then
    attempt.landing = {
      id = landing_id,
      name = trim(info.name),
      area = trim(info.zone or info.area),
    }
  end
  evaluate_attempt()
end

function usage.mark_blocked(reason)
  if not usage.runtime.pending then return false end
  return finish_attempt("blocked", reason or "portal_blocked")
end

function usage.register_events()
  if usage.runtime.pending then
    finish_attempt("unconfirmed", "package_reloaded")
  end
  for _, event_id in ipairs(usage.runtime.event_ids or {}) do
    if type(killAnonymousEventHandler) == "function" then
      pcall(killAnonymousEventHandler, event_id)
    end
  end
  usage.runtime.event_ids = {}
  if type(registerAnonymousEventHandler) == "function" then
    table.insert(usage.runtime.event_ids,
      registerAnonymousEventHandler("sysDataSendRequest", "mm.portal_usage.on_data_send_request"))
  end

  if usage.runtime.whoosh_trigger and type(killTrigger) == "function" then
    pcall(killTrigger, usage.runtime.whoosh_trigger)
  end
  usage.runtime.whoosh_trigger = nil
  if type(tempRegexTrigger) == "function" then
    usage.runtime.whoosh_trigger = tempRegexTrigger(
      "^\\s*WHO+SH!\\s*$",
      "mm.portal_usage.on_whoosh()"
    )
  end
end
