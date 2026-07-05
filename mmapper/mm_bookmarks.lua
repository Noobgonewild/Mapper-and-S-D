mm = mm or {}
mm.bookmarks = mm.bookmarks or {}

local bookmarks = mm.bookmarks

local TABLE_NAME = "mapper_area_bookmarks"
local DELETED_LIMIT = 20
local LABEL_WIDTH = 30
local ROOM_WIDTH = 9
local ACTION_WIDTH = 7

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function clean_line(value)
  return trim((mm.strip_ansi and mm.strip_ansi(value) or tostring(value or "")):gsub("[\r\n\t]+", " "))
end

local function strip_wrapping_quotes(value)
  local text = trim(value)
  if #text >= 2 then
    local first = text:sub(1, 1)
    local last = text:sub(-1)
    if (first == "'" and last == "'") or (first == '"' and last == '"') then
      return trim(text:sub(2, -2))
    end
  end
  return text
end

local function fit(value, width)
  local text = clean_line(value)
  if #text > width then
    if width <= 3 then
      text = text:sub(1, width)
    else
      text = text:sub(1, width - 3) .. "..."
    end
  end
  return text, string.rep(" ", math.max(0, width - #text))
end

local function today_text(ts)
  local n = tonumber(ts) or 0
  if n <= 0 then return "n/a" end
  return os.date("%Y-%m-%d", n)
end

local function link_or_echo(label, command, tooltip, enabled)
  if enabled ~= false and type(echoLink) == "function" then
    echoLink(label, command, tooltip or "", true)
  else
    echo(label)
  end
end

local function table_exists()
  local rows, err = mm.query_mapper_db(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=" .. mm.sql_escape(TABLE_NAME) .. " LIMIT 1"
  )
  if not rows then return nil, err end
  return rows[1] ~= nil
end

function bookmarks.ensure_schema()
  if bookmarks._schema_ready then return true end

  local exists, err = table_exists()
  if exists == nil then
    return false, err
  end

  if not exists then
    local ok, create_err = mm.exec_mapper_db([[
      CREATE TABLE IF NOT EXISTS mapper_area_bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        room_uid TEXT NOT NULL UNIQUE,
        label TEXT,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
      )
    ]])
    if not ok then return false, create_err end
  end

  bookmarks._schema_ready = true
  return true
end

function bookmarks.initialize()
  local ok, err = bookmarks.ensure_schema()
  if not ok then
    return false, err
  end
  return true
end

local function ensure_ready()
  if not (mm.query_mapper_db and mm.exec_mapper_db and mm.sql_escape) then
    return false, "mapper database helpers are unavailable"
  end
  return bookmarks.ensure_schema()
end

local function room_info(room_id)
  local uid = trim(room_id)
  if uid == "" then return nil, "room id is required" end
  local rows, err = mm.query_mapper_db(
    "SELECT uid, name, area FROM rooms WHERE uid = " .. mm.sql_escape(uid) .. " LIMIT 1"
  )
  if not rows then return nil, err end
  if not rows[1] then
    return nil, "room not found in mapper database: " .. uid
  end
  return rows[1]
end

local function current_room_id()
  local room = mm.current_room and mm.current_room() or nil
  if not room then return nil, "current room unknown; try LOOK first" end
  if type(room) ~= "number" then
    return nil, "bookmarks are only available in mapped rooms"
  end
  return tostring(room)
end

local function current_area()
  local info = mm.get_room_info and mm.get_room_info() or nil
  local area = info and trim(info.zone or info.area) or ""
  if area ~= "" then return area end

  local room, room_err = current_room_id()
  if not room then return nil, room_err end
  local row, err = room_info(room)
  if not row then return nil, err end
  area = trim(row.area)
  if area == "" then return nil, "current area is unknown; try LOOK first" end
  return area
end

local function resolve_area(raw_scope)
  local scope = trim(raw_scope)
  if scope == "" or scope:lower() == "here" then
    return current_area()
  end

  local lowered = scope:lower()
  local exact, exact_err = mm.query_mapper_db(
    "SELECT DISTINCT area FROM rooms WHERE lower(area) = " .. mm.sql_escape(lowered) .. " ORDER BY area LIMIT 2"
  )
  if not exact then return nil, exact_err end
  if #exact == 1 then return exact[1].area end

  local partial, partial_err = mm.query_mapper_db(
    "SELECT DISTINCT area FROM rooms WHERE lower(area) LIKE " .. mm.sql_escape("%" .. lowered .. "%") .. " ORDER BY area LIMIT 6"
  )
  if not partial then return nil, partial_err end
  if #partial == 0 then
    return nil, "no mapper area matched: " .. scope
  end
  if #partial > 1 then
    local names = {}
    for _, row in ipairs(partial) do
      table.insert(names, tostring(row.area or "?"))
    end
    return nil, "area match is ambiguous: " .. table.concat(names, ", ")
  end
  return partial[1].area
end

local function existing_bookmark(room_id)
  local rows, err = mm.query_mapper_db(
    "SELECT * FROM " .. TABLE_NAME .. " WHERE room_uid = " .. mm.sql_escape(room_id) .. " LIMIT 1"
  )
  if not rows then return nil, err end
  return rows[1]
end

local function cap_deleted_history()
  local ok, err = mm.exec_mapper_db(string.format([[
    DELETE FROM %s
    WHERE deleted_at IS NOT NULL
      AND id NOT IN (
        SELECT id FROM %s
        WHERE deleted_at IS NOT NULL
        ORDER BY deleted_at DESC, id DESC
        LIMIT %d
      )
  ]], TABLE_NAME, TABLE_NAME, DELETED_LIMIT))
  return ok, err
end

local function parse_add_args(raw_arg)
  local arg = trim(raw_arg)
  if arg == "" then
    local room, err = current_room_id()
    return room, nil, false, err
  end

  local room, label = arg:match("^(%d+)%s+[Aa][Ss]%s+(.+)$")
  if room then
    return room, strip_wrapping_quotes(label), true
  end

  if arg:match("^(%d+)%s+[Aa][Ss]%s*$") then
    return nil, nil, false, "Usage: mapper bookmarks add <roomID> as <label>"
  end

  if arg:match("^%d+$") then
    return arg, nil, false
  end

  local current, err = current_room_id()
  return current, strip_wrapping_quotes(arg), true, err
end

function bookmarks.add(raw_arg)
  local ok, err = ensure_ready()
  if not ok then return false, err end

  local room_id, label, has_label, parse_err = parse_add_args(raw_arg)
  if not room_id then return false, parse_err end

  local info, info_err = room_info(room_id)
  if not info then return false, info_err end

  local existing, existing_err = existing_bookmark(tostring(info.uid))
  if existing_err then return false, existing_err end

  local room_name = clean_line(info.name or "")
  local label_text = clean_line(label or "")
  if label_text == "" then
    if existing and existing.deleted_at and tostring(existing.deleted_at) ~= "" then
      label_text = clean_line(existing.label or "")
    end
    if label_text == "" then
      label_text = room_name ~= "" and room_name or ("room " .. tostring(info.uid))
    end
  end

  local now = os.time()
  if existing then
    local active = existing.deleted_at == nil or tostring(existing.deleted_at) == ""
    if active and not has_label then
      mm.note(string.format("Bookmark already exists for room %s: %s", tostring(info.uid), clean_line(existing.label or label_text)))
      return true
    end

    local upd_ok, upd_err = mm.exec_mapper_db(string.format(
      "UPDATE %s SET label = %s, updated_at = %d, deleted_at = NULL WHERE id = %d",
      TABLE_NAME,
      mm.sql_escape(label_text),
      now,
      tonumber(existing.id) or 0
    ))
    if not upd_ok then return false, upd_err end
    mm.note(string.format("Bookmark %s for room %s: %s", active and "updated" or "restored", tostring(info.uid), label_text))
    return true
  end

  local ins_ok, ins_err = mm.exec_mapper_db(string.format(
    "INSERT INTO %s (room_uid, label, created_at, updated_at, deleted_at) VALUES (%s, %s, %d, %d, NULL)",
    TABLE_NAME,
    mm.sql_escape(tostring(info.uid)),
    mm.sql_escape(label_text),
    now,
    now
  ))
  if not ins_ok then return false, ins_err end

  mm.note(string.format("Bookmark added for room %s: %s", tostring(info.uid), label_text))
  return true
end

local function active_rows_for_area(area)
  return mm.query_mapper_db(string.format([[
    SELECT b.id, b.room_uid, b.label, b.created_at, b.updated_at,
           COALESCE(NULLIF(rooms.name, ''), lookup.name, '') AS room_name,
           rooms.area AS area
    FROM %s b
    JOIN rooms ON rooms.uid = b.room_uid
    LEFT JOIN (SELECT uid, MIN(name) AS name FROM rooms_lookup GROUP BY uid) lookup ON lookup.uid = rooms.uid
    WHERE b.deleted_at IS NULL
      AND rooms.area = %s
    ORDER BY lower(b.label), lower(COALESCE(NULLIF(rooms.name, ''), lookup.name, '')), CAST(b.room_uid AS INTEGER)
  ]], TABLE_NAME, mm.sql_escape(area)))
end

local function room_link_command(room_id)
  return string.format([[mm.bookmarks.go_room(%d)]], tonumber(room_id) or 0)
end

function bookmarks.go_room(room_id)
  local ok, err = mm.goto_room(room_id)
  if not ok then mm.warn(err) end
end

function bookmarks.where(room_id)
  local ok, err = mm.where_room(room_id)
  if not ok then mm.warn(err) end
end

local function echo_active_row(index, row)
  local room_id = tostring(row.room_uid or "")
  local label = clean_line(row.label or "")
  if label == "" then label = clean_line(row.room_name or ("room " .. room_id)) end

  local label_text, label_pad = fit(label, LABEL_WIDTH)
  local room_text, room_pad = fit("(" .. room_id .. ")", ROOM_WIDTH)
  local action_text, action_pad = fit("[where]", ACTION_WIDTH)
  local go_cmd = room_link_command(room_id)
  local where_cmd = string.format([[mm.bookmarks.where(%d)]], tonumber(room_id) or 0)
  local tip = "xrt " .. room_id .. " - " .. label

  cecho("  <white>")
  link_or_echo(string.format("[%2d]", index), go_cmd, tip, true)
  cecho("<reset> ")
  cecho("<deep_sky_blue>")
  link_or_echo(label_text, go_cmd, tip, true)
  cecho("<reset>")
  echo(label_pad .. " ")
  cecho("<light_slate_blue>")
  link_or_echo(room_text, go_cmd, tip, true)
  cecho("<reset>")
  echo(room_pad .. "  ")
  cecho("<medium_purple>")
  link_or_echo(action_text, where_cmd, "Show path to room " .. room_id, true)
  cecho("<reset>")
  echo(action_pad .. "  ")
  local room_name = clean_line(row.room_name or "")
  if room_name == "" then room_name = "?" end
  cecho("<light_grey>")
  echo(room_name)
  cecho("<reset>")
  cecho("\n")
end

local function echo_active_header()
  local label_text, label_pad = fit("Bookmark Name", LABEL_WIDTH)
  local room_text, room_pad = fit("Room ID", ROOM_WIDTH)
  local action_text, action_pad = fit("Route", ACTION_WIDTH)
  cecho("<dim_gray>  #    " .. label_text .. label_pad .. " " .. room_text .. room_pad .. "  " .. action_text .. action_pad .. "  Room name<reset>\n")
end

function bookmarks.list(raw_scope)
  local ok, err = ensure_ready()
  if not ok then return false, err end

  local area, area_err = resolve_area(raw_scope)
  if not area then return false, area_err end

  local rows, rows_err = active_rows_for_area(area)
  if not rows then return false, rows_err end

  mm.runtime = mm.runtime or {}
  mm.runtime.bookmark_last_rows = rows

  cecho(string.format("\n<white>Showing %d bookmark%s - <cyan>%s<reset>\n", #rows, #rows == 1 and "" or "s", tostring(area)))
  cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
  if #rows == 0 then
    cecho("<yellow>No bookmarks found in this area.<reset>\n")
    cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
    return true
  end

  echo_active_header()
  cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
  for i, row in ipairs(rows) do
    echo_active_row(i, row)
  end
  cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
  cecho("<dim_gray>Click bookmark or type \"mapper bookmarks go #<index>\"<reset>\n")
  return true
end

local function active_row_by_index(index)
  local i = tonumber(index)
  if not i then return nil, "bookmark index must be a number" end
  local rows = mm.runtime and mm.runtime.bookmark_last_rows or nil
  if not rows or #rows == 0 then
    return nil, "no cached bookmark list; run mapper bookmarks first"
  end
  if not rows[i] then
    return nil, "no bookmark #" .. tostring(i) .. " in the last list"
  end
  return rows[i]
end

local function bookmark_by_id(bookmark_id)
  local rows, err = mm.query_mapper_db(
    "SELECT * FROM " .. TABLE_NAME .. " WHERE id = " .. tostring(tonumber(bookmark_id) or 0) .. " LIMIT 1"
  )
  if not rows then return nil, err end
  if not rows[1] then return nil, "bookmark not found" end
  return rows[1]
end

function bookmarks.go_index(index)
  local row, err = active_row_by_index(index)
  if not row then return false, err end
  local full, full_err = bookmark_by_id(row.id)
  if not full then return false, full_err end
  if full.deleted_at and tostring(full.deleted_at) ~= "" then
    return false, "bookmark #" .. tostring(index) .. " is no longer active; run mapper bookmarks again"
  end
  bookmarks.go_room(full.room_uid)
  return true
end

local function delete_bookmark_row(row)
  local ok, err = ensure_ready()
  if not ok then return false, err end

  local full, full_err = bookmark_by_id(row.id)
  if not full then return false, full_err end
  if full.deleted_at and tostring(full.deleted_at) ~= "" then
    return false, "bookmark is already deleted"
  end

  local now = os.time()
  local del_ok, del_err = mm.exec_mapper_db(string.format(
    "UPDATE %s SET deleted_at = %d, updated_at = %d WHERE id = %d",
    TABLE_NAME,
    now,
    now,
    tonumber(row.id) or 0
  ))
  if not del_ok then return false, del_err end
  cap_deleted_history()
  mm.note(string.format("Bookmark deleted for room %s: %s", tostring(row.room_uid or full.room_uid), clean_line(row.label or full.label or "")))
  return true
end

function bookmarks.delete_index(index)
  local row, err = active_row_by_index(index)
  if not row then return false, err end
  return delete_bookmark_row(row)
end

function bookmarks.delete_room(room_id)
  local ok, err = ensure_ready()
  if not ok then return false, err end

  local uid = trim(room_id)
  if not uid:match("^%d+$") then
    return false, "Usage: mapper bookmarks delete #<index> OR mapper bookmarks delete <roomID>"
  end

  local rows, qerr = mm.query_mapper_db(
    "SELECT * FROM " .. TABLE_NAME .. " WHERE room_uid = " .. mm.sql_escape(uid) .. " AND deleted_at IS NULL LIMIT 1"
  )
  if not rows then return false, qerr end
  if not rows[1] then return false, "no active bookmark found for room " .. uid end
  return delete_bookmark_row(rows[1])
end

function bookmarks.rename_index(index, raw_label)
  local ok, err = ensure_ready()
  if not ok then return false, err end

  local row, row_err = active_row_by_index(index)
  if not row then return false, row_err end
  local full, full_err = bookmark_by_id(row.id)
  if not full then return false, full_err end
  if full.deleted_at and tostring(full.deleted_at) ~= "" then
    return false, "bookmark #" .. tostring(index) .. " is no longer active; run mapper bookmarks again"
  end
  local label = clean_line(strip_wrapping_quotes(raw_label))
  if label == "" then return false, "bookmark label cannot be empty" end

  local upd_ok, upd_err = mm.exec_mapper_db(string.format(
    "UPDATE %s SET label = %s, updated_at = %d WHERE id = %d AND deleted_at IS NULL",
    TABLE_NAME,
    mm.sql_escape(label),
    os.time(),
    tonumber(full.id) or 0
  ))
  if not upd_ok then return false, upd_err end
  row.label = label
  mm.note(string.format("Bookmark #%d renamed: %s", tonumber(index) or 0, label))
  return true
end

local function deleted_rows()
  return mm.query_mapper_db(string.format([[
    SELECT b.id, b.room_uid, b.label, b.created_at, b.updated_at, b.deleted_at,
           COALESCE(NULLIF(rooms.name, ''), lookup.name, '') AS room_name,
           rooms.area AS area
    FROM %s b
    LEFT JOIN rooms ON rooms.uid = b.room_uid
    LEFT JOIN (SELECT uid, MIN(name) AS name FROM rooms_lookup GROUP BY uid) lookup ON lookup.uid = rooms.uid
    WHERE b.deleted_at IS NOT NULL
    ORDER BY b.deleted_at DESC, b.id DESC
    LIMIT %d
  ]], TABLE_NAME, DELETED_LIMIT))
end

local function echo_deleted_row(index, row)
  local room_id = tostring(row.room_uid or "")
  local label = clean_line(row.label or "")
  if label == "" then label = clean_line(row.room_name or ("room " .. room_id)) end

  local label_text, label_pad = fit(label, LABEL_WIDTH)
  local room_text, room_pad = fit("(" .. room_id .. ")", ROOM_WIDTH)
  local date_text, date_pad = fit(today_text(row.deleted_at), 10)
  local restore_cmd = string.format([[mm.bookmarks.restore_link(%d)]], index)

  cecho("  <white>")
  link_or_echo(string.format("[%2d]", index), restore_cmd, "Restore bookmark #" .. tostring(index), true)
  cecho("<reset> ")
  echo(label_text .. label_pad .. " ")
  echo(room_text .. room_pad .. "  ")
  echo(date_text .. date_pad .. "  ")
  local room_name = clean_line(row.room_name or "")
  if room_name == "" then room_name = "?" end
  echo(room_name)
  cecho("\n")
end

function bookmarks.list_deleted()
  local ok, err = ensure_ready()
  if not ok then return false, err end

  local rows, rows_err = deleted_rows()
  if not rows then return false, rows_err end

  mm.runtime = mm.runtime or {}
  mm.runtime.bookmark_deleted_last_rows = rows

  cecho("\n<white>Deleted Mapper Bookmarks<reset>\n")
  cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
  if #rows == 0 then
    cecho("<yellow>No deleted bookmarks found.<reset>\n")
    cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
    return true
  end

  cecho(string.format(
    "<dim_gray>Showing last %d deleted bookmark%s. Click [#] or use mapper bookmarks restore #<index>.\n<reset>",
    #rows,
    #rows == 1 and "" or "s"
  ))
  for i, row in ipairs(rows) do
    echo_deleted_row(i, row)
  end
  cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
  return true
end

function bookmarks.restore_index(index)
  local ok, err = ensure_ready()
  if not ok then return false, err end

  local i = tonumber(index)
  if not i then return false, "bookmark index must be a number" end
  local rows = mm.runtime and mm.runtime.bookmark_deleted_last_rows or nil
  if not rows or #rows == 0 then
    return false, "no cached deleted bookmark list; run mapper bookmarks listdeleted first"
  end
  local row = rows[i]
  if not row then return false, "no deleted bookmark #" .. tostring(i) .. " in the last list" end

  local info, info_err = room_info(row.room_uid)
  if not info then
    return false, "cannot restore bookmark; " .. tostring(info_err)
  end

  local upd_ok, upd_err = mm.exec_mapper_db(string.format(
    "UPDATE %s SET deleted_at = NULL, updated_at = %d WHERE id = %d",
    TABLE_NAME,
    os.time(),
    tonumber(row.id) or 0
  ))
  if not upd_ok then return false, upd_err end

  table.remove(rows, i)
  mm.note(string.format("Bookmark restored for room %s: %s", tostring(info.uid), clean_line(row.label or info.name or "")))
  return true
end

function bookmarks.restore_link(index)
  local ok, err = bookmarks.restore_index(index)
  if not ok then mm.warn(err) end
end
