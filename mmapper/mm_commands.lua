mm = mm or {}

local function show_window_status(which)
  local cfg = mm.state.windows and mm.state.windows[which]
  if not cfg then
    mm.warn("Unknown window: " .. tostring(which))
    return
  end

  mm.note(string.format("%s status: %s, position=%s,%s size=%s x %s, locked=%s", which, cfg.enabled and "shown" or "hidden", tostring(cfg.x), tostring(cfg.y), tostring(cfg.width), tostring(cfg.height), tostring(cfg.locked)))
  if which == "bigmap" and mm.minimap and mm.minimap.get_bigmap_mode then
    local mode, radius = mm.minimap.get_bigmap_mode()
    local active = mm.minimap.get_active_bigmap_mode and mm.minimap.get_active_bigmap_mode() or mode
    local suffix = (mode == "local" or mode == "hybrid") and
      string.format(" radius=%d", tonumber(radius) or 4) or ""
    if mode == "hybrid" then suffix = suffix .. " active=" .. tostring(active) end
    mm.note(string.format("bigmap display: %s%s", tostring(mode), suffix))
  end
end

local function handle_window_command(which, action, a, b)
  which = which == "map" and "bigmap" or which
  if action == "show" then
    mm.minimap.set_window_visible(which, true)
  elseif action == "hide" then
    mm.minimap.set_window_visible(which, false)
  elseif action == "move" then
    mm.minimap.move_window(which, a, b)
  elseif action == "resize" then
    mm.minimap.resize_window(which, a, b)
  elseif action == "lock" then
    mm.minimap.lock_window(which, true)
  elseif action == "unlock" then
    mm.minimap.lock_window(which, false)
  end
end

local function run_inspect(source)
  local ok, info = mm.import.inspect_sqlite(source)
  if not ok then
    mm.warn(info)
    return
  end

  mm.note("inspect path: " .. tostring(info.path))
  mm.note(string.format("inspect: compatible=%s, rooms=%d, exits=%d", tostring(info.compatible), info.room_count or 0, info.exit_count or 0))
  if not info.compatible then
    mm.warn("Missing: " .. table.concat(info.missing or {}, ", "))
  end
end

local function rebuild_rooms_lookup()
  if not (snd and snd.mapper and snd.mapper.rebuildRoomsLookup) then
    mm.warn("Mapper database lookup rebuild is not available.")
    return
  end
  local ok, info = snd.mapper.rebuildRoomsLookup()
  if not ok then
    mm.warn(info)
    return
  end
  mm.note(string.format(
    "rooms_lookup rebuilt from rooms: %d room rows, %d lookup rows.",
    tonumber(info.rooms) or 0,
    tonumber(info.lookup) or 0
  ))
end

local function ensure_mapper_ui_config()
  snd = snd or {}
  snd.config = snd.config or {}
  snd.config.mapperUI = snd.config.mapperUI or {}
  local ui = snd.config.mapperUI
  if ui.links == nil then ui.links = true end
  if ui.hover == nil then ui.hover = true end
  if ui.visited == nil then ui.visited = true end
  if ui.chips == nil then ui.chips = true end
  return ui
end

local function mapper_ui_status_text()
  local ui = ensure_mapper_ui_config()
  return string.format(
    "mapper ui: links=%s, hover=%s, visited=%s, chips=%s",
    ui.links and "on" or "off",
    ui.hover and "on" or "off",
    ui.visited and "on" or "off",
    ui.chips and "on" or "off"
  )
end

local function set_native_follow(enabled, command_name)
  enabled = enabled ~= false
  mm.state.auto_locate = enabled
  mm.state.center_on_locate = enabled
  if mm.save_settings_persistence then
    mm.save_settings_persistence()
  end
  mm.note(string.format("%s %s", command_name or "autolocate", enabled and "on" or "off"))
  if enabled and mm.sync_native_bigmap_to_current_room then
    mm.sync_native_bigmap_to_current_room("native_follow_enabled")
  end
end

local function set_mapper_ui_flag(flag, mode)
  local ui = ensure_mapper_ui_config()
  if mode == nil then
    ui[flag] = not ui[flag]
  else
    ui[flag] = mm.bool_arg(mode, ui[flag] ~= false)
  end
  if snd and snd.saveState then
    snd.saveState()
  end
  mm.note(mapper_ui_status_text())
end


local function normalize_line(line)
  return tostring(line or "")
    :gsub("[\r\n]+", "")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
end

local function parse_command_with_optional_level(raw)
  local cleaned = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if mm.normalize_stacked_command then
    cleaned = mm.normalize_stacked_command(cleaned)
  end

  local explicit_command, explicit_level = cleaned:match("^(.-)%s+[Ll][Ee][Vv][Ee][Ll]%s+(%d+)$")
  if explicit_command and explicit_command ~= "" then
    return explicit_command, tonumber(explicit_level) or 0, nil
  end

  return nil, nil, "Usage: mapper portal <command> level <number>"
end

local function rebuild_portals_if_available()
  if mm.rebuild_portals_from_db then
    local ok, err = mm.rebuild_portals_from_db()
    if not ok then
      mm.warn(err)
      return false
    end
  end
  return true
end

local function portal_command_for_selected_id(selected_id)
  if not selected_id then return nil end
  local target = tostring(selected_id)
  for _, portal in ipairs(mm.portals and mm.portals.rebuilt or {}) do
    if tostring(portal.portal_id) == target then
      return portal.command or portal.dir
    end
  end
  return nil
end

local function handle_portalguard(mode)
  mode = tostring(mode or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if mode == "" then
    mm.note(mm.portal_guard_status_text())
    return true
  end
  if mode ~= "on" and mode ~= "off" then
    mm.warn("Usage: mapper portalguard [on|off]")
    return true
  end

  local enabled = mode == "on"
  local ok, err = mm.set_portal_guard(enabled)
  if not ok then
    mm.warn("Could not save portalguard setting: " .. tostring(err))
    return true
  end
  mm.note("Portal safety " .. (enabled and "ON" or "OFF") .. ".")
  mm.note(mm.portal_guard_status_text())
  return true
end

local function handle_autostop(mode)
  mode = tostring(mode or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if mode == "" then
    mm.note(mm.autostop_status_text())
    return true
  end
  if mode ~= "on" and mode ~= "off" then
    mm.warn("Usage: mapper autostop [on|off]")
    return true
  end

  local ok, err = mm.set_autostop(mode == "on")
  if not ok then
    mm.warn("Could not save autostop setting: " .. tostring(err))
    return true
  end
  mm.note(mm.autostop_status_text())
  return true
end

local function handle_command_inline(line)
  line = normalize_line(line)

  if line == "mapper" then
    mm.show_help()
    return true
  end

  if line == "mapper stats" then
    mm.show_stats()
    return true
  end

  if line == "mapper stats reset" then
    mm.reset_stats()
    return true
  end

  local help_topic = line:match("^mapper help%s+(.+)$")
  if line == "mapper help" or help_topic then
    mm.show_help(help_topic)
    return true
  end

  local window_only = line:match("^mapper%s+(%S+)$")
  if window_only and (window_only == "minimap" or window_only == "bigmap" or window_only == "map") then
    show_window_status((window_only == "map") and "bigmap" or window_only)
    return true
  end

  local bigmap_arg = line:match("^mapper%s+bigmap%s+(%S+)$") or line:match("^mapper%s+map%s+(%S+)$")
  if bigmap_arg and (bigmap_arg == "local" or bigmap_arg == "native" or bigmap_arg == "hybrid") then
    mm.minimap.set_bigmap_mode(bigmap_arg)
    return true
  end

  local bigmap_radius = line:match("^mapper%s+bigmap%s+radius%s+(%d+)$")
    or line:match("^mapper%s+map%s+radius%s+(%d+)$")
    or line:match("^mapper%s+localmap%s+radius%s+(%d+)$")
  if bigmap_radius then
    mm.minimap.set_local_radius(bigmap_radius)
    return true
  end

  local bigmap_room_size = line:match("^mapper%s+bigmap%s+roomsize%s+(%d+)$")
    or line:match("^mapper%s+map%s+roomsize%s+(%d+)$")
    or line:match("^mapper%s+localmap%s+roomsize%s+(%d+)$")
  if bigmap_room_size then
    mm.minimap.set_local_room_size(bigmap_room_size)
    return true
  end

  if line == "mapper bigmap roomsize" or line == "mapper map roomsize" or
      line == "mapper localmap roomsize" then
    local _, _, room_size = mm.minimap.get_bigmap_mode()
    mm.note(string.format("Bigmap local room size is %d pixels.", tonumber(room_size) or 15))
    return true
  end

  if line == "mapper localmap" then
    show_window_status("bigmap")
    return true
  end

  if line == "mapper bigmap refresh" or line == "mapper map refresh" or line == "mapper localmap refresh" then
    if mm.minimap and mm.minimap.update_local_map then
      mm.minimap.update_local_map(nil, { force = true })
      mm.note("Bigmap local view refreshed.")
    end
    return true
  end

  local which, action, a, b = line:match("^mapper%s+(%S+)%s+(%S+)%s*(%S*)%s*(%S*)$")
  if which and action and (which == "minimap" or which == "bigmap" or which == "map") then
    if not (action == "show" or action == "hide" or action == "lock" or action == "unlock" or action == "move" or action == "resize" or action == "fontsize") then
      return false
    end

    if action == "fontsize" then
      local target = (which == "map") and "bigmap" or which
      mm.minimap.set_font_size(target, a)
      return true
    end
    if action == "move" or action == "resize" then
      if a ~= "" and b ~= "" then
        handle_window_command(which, action, a, b)
        return true
      end
      mm.warn("Usage: mapper " .. which .. " " .. action .. " <x> <y>")
      return true
    end
    handle_window_command(which, action)
    return true
  end

  local setting, option = line:match("^mapshow%s+(%S+)%s+(%S+)$")
  if setting and (option == "on" or option == "off") then
    mm.minimap.toggle_show(setting, option)
    return true
  end

  local maptype = line:match("^maptype%s+(.+)$")
  if maptype then
    mm.minimap.set_type(maptype)
    return true
  end

  if line == "mapper show" then mm.minimap.show_all(); return true end
  if line == "mapper hide" then mm.minimap.hide_all(); return true end
  if line == "mapper locate" then send("look"); return true end
  if line == "mapper ui" or line == "mapper ui status" then
    mm.note(mapper_ui_status_text())
    return true
  end
  if line == "mapper ui reset" then
    local ui = ensure_mapper_ui_config()
    ui.links = true
    ui.hover = true
    ui.visited = true
    ui.chips = true
    if snd and snd.saveState then
      snd.saveState()
    end
    mm.note(mapper_ui_status_text())
    return true
  end

  local ui_flag, ui_mode = line:match("^mapper ui (links|hover|visited|chips)%s*(on|off)?$")
  if ui_flag then
    set_mapper_ui_flag(ui_flag, ui_mode)
    return true
  end

  local portalguard_mode = line:match("^mapper portalguard%s*(%S*)$")
  if portalguard_mode ~= nil then
    return handle_portalguard(portalguard_mode)
  end

  local autostop_mode = line:match("^mapper autostop%s*(%S*)$")
  if autostop_mode ~= nil then
    return handle_autostop(autostop_mode)
  end

  local mapper_portal_raw = line:match("^mapper portal%s+(.+)$")
  if mapper_portal_raw then
    local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
    if not (nav and nav.addPortal and nav.addRecallPortal) then
      mm.warn("mapper portal requires mapper navigation module to be loaded.")
      return true
    end
    local command, level, parse_err = parse_command_with_optional_level(mapper_portal_raw)
    if not command then
      mm.warn(parse_err or "Usage: mapper portal <command> level <number>")
      return true
    end
    local normalized = tostring(command):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local is_recall = (normalized == "recall" or normalized == "home" or normalized == "return home")
    local existing, check_err = mm.query_mapper_db(string.format(
      "SELECT COUNT(*) AS cnt FROM exits WHERE fromuid in ('*','**') AND dir = %s",
      mm.sql_escape(command)
    ))
    if not existing then
      mm.warn("Failed checking existing portal command: " .. tostring(check_err))
      return true
    end
    if (tonumber(existing[1] and existing[1].cnt) or 0) > 0 then
      mm.warn("A mapper portal with that command already exists.")
      mm.warn("Use 'mapper rebuildportals' to rebuild/update portal definitions.")
      mm.warn("Also see 'mapper help portals' for command usage.")
      return true
    end
    if is_recall then
      nav.addRecallPortal(command, level)
    else
      nav.addPortal(command, level)
    end
    return true
  end
  if line == "mapper portal" then
    mm.warn("Usage: mapper portal <command> level <number>")
    return true
  end

  local change_idx, change_cmd = line:match("^mapper editportal%s+#(%d+)%s+{(.+)}$")
  if change_idx and change_cmd then
    local index = tonumber(change_idx)
    local new_command = tostring(change_cmd or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if new_command == "" then
      mm.warn("Usage: mapper editportal #<index> {<new cmd>}")
      return true
    end
    local portals = mm.portals and mm.portals.rebuilt or {}
    local portal = portals[index]
    if not portal or not portal.command then
      mm.warn("Portal index not found in rebuilt list. Run 'mapper portals' and try again.")
      return true
    end
    local fromuid = tostring(portal.fromuid or (portal.fixed_recall and "**" or "*"))
    local old_command = tostring(portal.command or "")
    local touid = tostring(portal.touid or "")
    local check_sql = string.format(
      "SELECT COUNT(*) AS cnt FROM exits WHERE dir=%s AND touid=%s AND fromuid=%s",
      mm.sql_escape(old_command),
      mm.sql_escape(touid),
      mm.sql_escape(fromuid)
    )
    local existing, check_err = mm.query_mapper_db(check_sql)
    if not existing then
      mm.warn("Failed to verify selected portal row: " .. tostring(check_err))
      return true
    end
    if (tonumber(existing[1] and existing[1].cnt) or 0) < 1 then
      mm.warn("Selected portal index no longer matches a DB row. Run 'mapper rebuildportals' and try again.")
      return true
    end

    local sql = string.format(
      "UPDATE exits SET dir=%s WHERE dir=%s AND touid=%s AND fromuid=%s",
      mm.sql_escape(new_command),
      mm.sql_escape(old_command),
      mm.sql_escape(touid),
      mm.sql_escape(fromuid)
    )
    local ok, err = mm.exec_mapper_db(sql)
    if not ok then
      mm.warn("Failed to update portal command: " .. tostring(err))
      return true
    end
    rebuild_portals_if_available()
    mm.note(string.format("Updated %s portal #%d: '%s' -> '%s'", (fromuid == "**" and "recall" or "regular"), index, old_command, new_command))
    return true
  end

  if line == "mapper editportal" then
    mm.warn("Usage: mapper editportal #<index> {<new cmd>}")
    return true
  end

  local delete_portal_index = line:match("^mapper delete portal%s+#(%d+)$")
  if delete_portal_index then
    local ok, err = mm.delete_portal_by_index(delete_portal_index)
    if not ok then mm.warn(err) end
    return true
  end
  if line == "mapper delete portal" then
    mm.warn("Usage: mapper delete portal #<index>")
    return true
  end

  if line == "mapper deletedportals" then
    local ok, err = mm.list_deleted_portals()
    if not ok then mm.warn(err) end
    return true
  end

  local restore_portal_arg = line:match("^mapper restoreportal%s+(.+)$")
  if restore_portal_arg then
    local ok, err = mm.restore_portal(restore_portal_arg)
    if not ok then mm.warn(err) end
    return true
  end

  if line == "mapper portals" then
    local ok, err = mm.print_portals()
    if not ok and err then mm.warn(err) end
    return true
  end
  local portalstats_count = line:match("^mapper portalstats recent%s*(%d*)$")
  if portalstats_count ~= nil then
    local ok, err = mm.portal_usage.show_stats_recent(portalstats_count ~= "" and portalstats_count or nil)
    if not ok then mm.warn(err) end
    return true
  end
  local portalstats_arg = line == "mapper portalstats" and ""
    or line:match("^mapper portalstats%s+(.+)$")
  if portalstats_arg ~= nil then
    portalstats_arg = portalstats_arg:lower()
    if portalstats_arg == "" then portalstats_arg = nil end
    if portalstats_arg ~= nil and portalstats_arg ~= "all" and not portalstats_arg:match("^%d+$") then
      mm.warn("Usage: mapper portalstats [count|all]")
      return true
    end
    local ok, err = mm.portal_usage.show_stats(portalstats_arg)
    if not ok then mm.warn(err) end
    return true
  end
  local portals_filter = line:match("^mapper portals%s+(.+)$")
  if portals_filter then
    local ok, err = mm.print_portals(portals_filter)
    if not ok and err then mm.warn(err) end
    return true
  end

  local portallevel_args = line:match("^mapper portallevel%s+(.+)$")
  if portallevel_args then
    local ok, err = mm.set_portal_level(portallevel_args)
    if not ok and err then mm.warn(err) end
    return true
  end
  if line == "mapper portallevel" then
    mm.warn("Usage: mapper portallevel <index> <level> [quiet]")
    return true
  end

  if line == "mapper checkimport" then
    local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
    if nav and nav.checkImport then
      nav.checkImport()
    else
      mm.warn("mapper checkimport requires mapper navigation module to be loaded.")
    end
    return true
  end

  if line == "mapper showenv" then
    local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
    if nav and nav.showEnvironments then
      nav.showEnvironments()
    else
      mm.warn("mapper showenv requires mapper navigation module to be loaded.")
    end
    return true
  end

  if line == "mapper calccoords confirm" then
    local ok, err = mm.import.recalculate_all_layouts(mm.state.map_db)
    if not ok then mm.warn(err) end
    return true
  end
  if line == "mapper calccoords" then
    mm.note("This refreshes classified cardinal links/stubs, recalculates every area layout, and saves the native map. Maze/teleport exits remain navigation routes but are excluded from coordinates. Confirm with: mapper calccoords confirm")
    return true
  end

  local portalrecall_idx = line:match("^mapper portalrecall%s+(%d+)$")
  if portalrecall_idx then
    local ok, err = mm.set_portal_recall(tonumber(portalrecall_idx))
    if not ok then
      mm.warn(err)
    else
      mm.note("Toggled recall flag for portal #" .. tostring(portalrecall_idx))
      mm.apply_bounce_settings_to_snd()
    end
    return true
  end
  if line == "mapper portalrecall" then
    mm.warn("Usage: mapper portalrecall <index>")
    return true
  end

  local chaosportal_idx = line:match("^mapper chaosportal%s+(%d+)$")
  if chaosportal_idx then
    local ok, err
    if mm.set_portal_chaos then
      ok, err = mm.set_portal_chaos(tonumber(chaosportal_idx))
    else
      ok, err = false, "mapper chaosportal is unavailable"
    end
    if not ok then
      mm.warn(err)
    else
      mm.note("Toggled chaos flag for portal #" .. tostring(chaosportal_idx))
    end
    return true
  end
  if line == "mapper chaosportal" then
    mm.warn("Usage: mapper chaosportal <index>")
    return true
  end

  if line == "mapper bounceportal" then
    local selected = mm.portals and mm.portals.settings and mm.portals.settings.bounce_portal_id
    if not selected then
      mm.note("bounceportal is not set.")
    else
      local cmd = portal_command_for_selected_id(selected)
      if cmd and tostring(cmd) ~= "" then
        mm.note("bounceportal: #" .. tostring(selected) .. " -> " .. tostring(cmd))
      else
        mm.note("bounceportal portal_id: " .. tostring(selected))
      end
    end
    return true
  end
  if line == "mapper bouncerecall" then
    local selected = mm.portals and mm.portals.settings and mm.portals.settings.bounce_recall_id
    if not selected then
      mm.note("bouncerecall is not set.")
    else
      local step = mm.get_configured_bounce_step and mm.get_configured_bounce_step("recall") or nil
      if step then
        mm.note(string.format(
          "bouncerecall portal_id: %s; command: %s; landing room: %s",
          tostring(selected), tostring(step.dir), tostring(step.uid)
        ))
      else
        mm.warn("bouncerecall portal_id " .. tostring(selected) .. " is set but no longer resolves to a usable recall portal.")
      end
    end
    return true
  end

  local bounceportal_arg = line:match("^mapper bounceportal%s+(.+)$")
  if bounceportal_arg then
    local bounceportal_idx = tostring(bounceportal_arg):match("^(%d+)$")
    if bounceportal_idx then
      local ok, portal_or_err = mm.set_bounce_portal(tonumber(bounceportal_idx))
      if not ok then
        mm.warn(portal_or_err)
      else
        mm.note("bounceportal set to #" .. tostring(bounceportal_idx) .. ": " .. tostring(portal_or_err.command))
      end
      return true
    end
    local nav = (mm and mm.nav) or (snd and snd.mapper) or nil
    if nav and nav.setBouncePortalByCommand then
      nav.setBouncePortalByCommand(bounceportal_arg)
      return true
    end
    mm.warn("Usage: mapper bounceportal <index> OR mapper bounceportal <command>")
    return true
  end

  local bouncerecall_idx = line:match("^mapper bouncerecall%s+(%d+)$")
  if bouncerecall_idx then
    local ok, portal_or_err = mm.set_bounce_recall(tonumber(bouncerecall_idx))
    if not ok then
      mm.warn(portal_or_err)
    else
      mm.note("bouncerecall set to #" .. tostring(bouncerecall_idx) .. ": " .. tostring(portal_or_err.command))
    end
    return true
  end

  if line == "mapper bounceportal clear" then
    local ok, err = mm.clear_bounce_portal()
    if not ok then mm.warn(err) else mm.note("bounceportal cleared.") end
    return true
  end
  if line == "mapper bouncerecall clear" then
    local ok, err = mm.clear_bounce_recall()
    if not ok then mm.warn(err) else mm.note("bouncerecall cleared.") end
    return true
  end

  local boundaries_arg = line:match("^mapper boundaries%s*(.*)$")
  if boundaries_arg ~= nil then
    local ok, err = mm.frontier.show_boundaries(boundaries_arg)
    if not ok then mm.warn(err) end
    return true
  end

  local redirect_target, redirect_destination = line:match("^mapper redirect add%s+(%d+)%s+(%d+)$")
  if redirect_target then
    local ok, err = mm.frontier.add_redirect(redirect_target, redirect_destination)
    if not ok then mm.warn(err) end
    return true
  end

  local redirects_target = line:match("^mapper redirects%s*(%d*)$")
  if redirects_target ~= nil then
    local ok, err = mm.frontier.list_redirects(redirects_target)
    if not ok then mm.warn(err) end
    return true
  end

  local redirect_delete = line:match("^mapper redirect delete%s+(%d+)$")
  if redirect_delete then
    local ok, err = mm.frontier.delete_redirect(redirect_delete)
    if not ok then mm.warn(err) end
    return true
  end

  if line == "mapper redirect deleted" then
    local ok, err = mm.frontier.list_deleted_redirects()
    if not ok then mm.warn(err) end
    return true
  end

  local redirect_restore = line:match("^mapper redirect restore%s+(.+)$")
  if redirect_restore then
    local ok, err = mm.frontier.restore_redirect(redirect_restore)
    if not ok then mm.warn(err) end
    return true
  end

  if line:find("^mapper redirect") or line:find("^mapper redirects") then
    mm.warn("Use 'mapper help boundaries' for redirect commands.")
    return true
  end

  local search_arg = line:match("^mapper area%s+(.+)$")
  if search_arg then local ok, err = mm.search_text("area", search_arg); if not ok then mm.warn(err) end; return true end

  search_arg = line:match("^mapper find%s+(.+)$")
  if search_arg then local ok, err = mm.search_text("find", search_arg); if not ok then mm.warn(err) end; return true end

  search_arg = line:match("^mapper list%s+(.+)$")
  if search_arg then local ok, err = mm.search_text("list", search_arg); if not ok then mm.warn(err) end; return true end

  local notes_arg = line:match("^mapper notes%s+(.+)$")
  if line == "mapper notes" or notes_arg then local ok, err = mm.search_notes(notes_arg); if not ok then mm.warn(err) end; return true end
  local searchnotes_arg = line:match("^mapper searchnotes%s+(.+)$")
  if searchnotes_arg then local ok, err = mm.search_notes_text(searchnotes_arg); if not ok then mm.warn(err) end; return true end

  local special_arg = line:match("^mapper shops?%s+(.+)$")
  if line == "mapper shop" or line == "mapper shops" or special_arg then local ok, err = mm.search_special("shops", special_arg); if not ok then mm.warn(err) end; return true end

  special_arg = line:match("^mapper train%s+(.+)$")
  if line == "mapper train" or special_arg then local ok, err = mm.search_special("train", special_arg); if not ok then mm.warn(err) end; return true end

  special_arg = line:match("^mapper quest%s+(.+)$")
  if line == "mapper quest" or special_arg then local ok, err = mm.search_special("quest", special_arg); if not ok then mm.warn(err) end; return true end

  local next_arg = line:match("^mapper next%s+(%d+)$")
  if line == "mapper next" or next_arg then local ok, err = mm.next_result(next_arg); if not ok then mm.warn(err) end; return true end

  local where_arg = line:match("^mapper where%s+(.+)$")
  if line == "mapper where" then mm.warn("Usage: mapper where <room id>"); return true end
  if where_arg then local ok, err = mm.where_room(where_arg); if not ok then mm.warn(err) end; return true end

  local exits_room = line:match("^mapper exits%s+(%d+)$")
  if line == "mapper exits" or exits_room then
    local ok, err = mm.print_room_exits(exits_room)
    if not ok then mm.warn(err) end
    return true
  end

  local cexits_area_arg = line:match("^mapper cexits area%s+(.+)$")
  if cexits_area_arg then local ok, err = mm.list_cexits("area " .. cexits_area_arg); if not ok then mm.warn(err) end; return true end
  local cexits_arg = line:match("^mapper cexits%s+(.+)$")
  if line == "mapper cexits" or cexits_arg then local ok, err = mm.list_cexits(cexits_arg); if not ok then mm.warn(err) end; return true end

  local cexit_wait = line:match("^mapper cexit_wait%s+(.+)$")
  if cexit_wait then local ok, err = mm.set_cexit_wait(cexit_wait); if not ok then mm.warn(err) end; return true end

  local cexit_cmd = line:match("^mapper cexit%s+(.+)$")
  if cexit_cmd then
    mm.debug(string.format("CEXIT DEBUG: parsed='%s' from line='%s'", tostring(cexit_cmd), tostring(line)))
    local ok, err = mm.cexit(cexit_cmd)
    if not ok then mm.warn(err) end
    return true
  end

  local random_cexits_area_arg = line:match("^mapper randomcexits area%s+(.+)$")
  if random_cexits_area_arg then
    local ok, err = mm.list_random_cexits("area " .. random_cexits_area_arg)
    if not ok then mm.warn(err) end
    return true
  end
  local random_cexits_arg = line:match("^mapper randomcexits%s+(.+)$")
  if line == "mapper randomcexits" or random_cexits_arg then
    local ok, err = mm.list_random_cexits(random_cexits_arg)
    if not ok then mm.warn(err) end
    return true
  end

  local delete_random_cexit_idx = line:match("^mapper deleterandomcexit%s+(%d+)$")
  if delete_random_cexit_idx then
    local ok, err = mm.delete_random_cexit(delete_random_cexit_idx)
    if not ok then mm.warn(err) end
    return true
  end

  local random_cmd, random_src, random_destinations, random_level = line:match(
    "^mapper randomcexit%s+{(.+)}%s+(%S+)%s+{([^}]+)}%s+(%d+)$"
  )
  if random_cmd then
    local ok, err = mm.add_random_cexit(random_cmd, random_src, random_destinations, random_level, false)
    if not ok then mm.warn(err) end
    return true
  end
  if line:find("^mapper randomcexit") then
    mm.warn("Usage: mapper randomcexit {<command>} <source> {<destination1>,<destination2>[,...]} <level>")
    return true
  end

  local fx_cmd, fx_src, fx_dst, fx_lvl = line:match("^mapper fullcexit%s+{(.+)}%s+(%S+)%s+(%S+)%s+(%d+)$")
  local fx_quiet = false
  if not fx_cmd then
    fx_cmd, fx_src, fx_dst, fx_lvl = line:match("^mapper fullcexit%s+{(.+)}%s+(%S+)%s+(%S+)%s+(%d+)%s+quiet$")
    fx_quiet = fx_cmd ~= nil
  end
  if fx_cmd then local ok, err = mm.add_full_cexit(fx_cmd, fx_src, fx_dst, fx_lvl, fx_quiet); if not ok then mm.warn(err) end; return true end

  local delete_cexit_idx = line:match("^mapper deletecexit%s+(%d+)$")
  if delete_cexit_idx then local ok, err = mm.delete_cexit(delete_cexit_idx); if not ok then mm.warn(err) end; return true end

  local restore_cexit_arg = line:match("^mapper restorecexit%s+(.+)$")
  if restore_cexit_arg then local ok, err = mm.restore_cexit(restore_cexit_arg); if not ok then mm.warn(err) end; return true end

  if line == "mapper deletedcexits" then local ok, err = mm.list_deleted_cexits(); if not ok then mm.warn(err) end; return true end

  local lock_dir, lock_level = line:match("^mapper lockexit%s+(%S+)%s*(%S*)$")
  if lock_dir then
    local normalizedLevel = tostring(lock_level or ""):lower()
    if normalizedLevel == "" then
      local ok, err = mm.lock_exit(lock_dir)
      if not ok then mm.warn(err) end
      return true
    end
    if normalizedLevel == "off" or normalizedLevel == "clear" or normalizedLevel == "unlock" then
      local ok, err = mm.unlock_exit(lock_dir)
      if not ok then mm.warn(err) end
      return true
    end
    local asNumber = tonumber(lock_level)
    if not asNumber then
      mm.warn("Usage: mapper lockexit <n|s|e|w|u|d> [level|off]")
      return true
    end
    local ok, err = mm.lock_exit(lock_dir, asNumber)
    if not ok then mm.warn(err) end
    return true
  end

  if line == "mapper lockexit" or line == "mapper lockedexits" then
    local ok, err = mm.list_locked_exits_here()
    if not ok then mm.warn(err) end
    return true
  end

  local dbg = line:match("^mapper debug%s*(%S*)$")
  if dbg ~= nil then
    if dbg == "" then
      mm.note("debug " .. ((mm.state and mm.state.debug) and "on" or "off"))
      return true
    end
    if dbg == "on" or dbg == "off" then
      mm.state.debug = (dbg == "on")
      mm.note("debug " .. dbg)
      if dbg == "on" then mm.debug("debugging enabled; watch for centerview/map capture lines") end
      return true
    end
    mm.warn("Usage: mapper debug [on|off]")
    return true
  end

  local onoff
  onoff = line:match("^mapper shownotes%s*(%S*)$")
  if onoff ~= nil then
    if onoff == "" then
      mm.note("shownotes " .. (mm.state.shownotes and "on" or "off"))
      return true
    end
    if onoff == "on" or onoff == "off" then
      mm.state.shownotes = mm.bool_arg(onoff, mm.state.shownotes)
      mm.note("shownotes " .. (mm.state.shownotes and "on" or "off"))
      return true
    end
    mm.warn("Usage: mapper shownotes [on|off]")
    return true
  end

  onoff = line:match("^mapper underlines?%s*(%S*)$")
  if onoff ~= nil then
    if onoff == "" then
      mm.note("underlines " .. (mm.state.underline_links and "on" or "off"))
      return true
    end
    if onoff == "on" or onoff == "off" then
      mm.state.underline_links = mm.bool_arg(onoff, mm.state.underline_links)
      mm.note("underlines " .. (mm.state.underline_links and "on" or "off"))
      return true
    end
    mm.warn("Usage: mapper underlines [on|off]")
    return true
  end

  onoff = line:match("^mapper autolocate%s+(%S+)$")
  if onoff == "on" or onoff == "off" then set_native_follow(mm.bool_arg(onoff, mm.state.auto_locate), "autolocate"); return true end
  onoff = line:match("^mapper centerlocate%s+(%S+)$")
  if onoff == "on" or onoff == "off" then set_native_follow(mm.bool_arg(onoff, mm.state.auto_locate), "centerlocate"); return true end

  local backups_arg = line:match("^mapper backups%s*(.-)%s*$")
  if backups_arg ~= nil and line:find("^mapper backups") then
    local arg = backups_arg:lower()
    if arg == "" then
      mm.print_backup_settings()
      return true
    end
    if arg == "on" or arg == "off" then
      mm.state.backups_enabled = mm.bool_arg(arg, mm.state.backups_enabled)
      mm.note("backups " .. (mm.state.backups_enabled and "on" or "off"))
      return true
    end
    if arg == "quiet" then
      mm.state.backups_quiet = not mm.state.backups_quiet
      mm.note("backups quiet " .. (mm.state.backups_quiet and "on" or "off"))
      return true
    end
    if arg == "compressed" then
      mm.state.backups_compressed = true
      mm.note("backups compression on")
      return true
    end
    if arg == "uncompressed" then
      mm.state.backups_compressed = false
      mm.note("backups compression off")
      return true
    end
    mm.warn("Usage: mapper backups [on|off|quiet|compressed|uncompressed]")
    return true
  end

  if line == "mapper backup" then
    local ok, err = mm.create_backup(true)
    if not ok then mm.warn(err) end
    return true
  end

  local addnote_arg = line:match("^mapper addnote%s+(.+)$")
  if addnote_arg then
    local ok, err = mm.add_note(addnote_arg)
    if not ok then mm.warn(err) end
    return true
  end
  if line == "mapper addnote" then
    if type(appendCmdLine) == "function" then
      appendCmdLine("mapper addnote ")
      mm.note("Enter note text after 'mapper addnote ' and press Enter.")
    else
      mm.warn("Usage: mapper addnote <note>")
    end
    return true
  end

  if line == "mapper delete note" then
    local ok, err = mm.delete_note()
    if not ok then mm.warn(err) end
    return true
  end

  if line:match("^mapper purgezone%s+") or line == "mapper purgeroom" or line:match("^mapper ignore mismatch%s+") then
    mm.warn("This command has been removed and is no longer supported.")
    return true
  end

  local layout_arg = line:match("^mapper rebuild layout%s*(%S*)$")
  if layout_arg ~= nil then
    local normalized = layout_arg:lower()
    if normalized == "" then
      local info = mm.get_room_info and mm.get_room_info() or nil
      local start = (info and tonumber(info.num)) or 32418
      local ok, err = mm.import.rebuild_layout_from(start)
      if not ok then mm.warn(err) end
      return true
    end

    if normalized == "on" or normalized == "off" then
      mm.warn("Automatic layout rebuild on area entry has been removed. Use 'mapper rebuild layout' when you want a manual repair.")
      return true
    end

    local room_id = tonumber(layout_arg)
    if room_id then
      local ok, err = mm.import.rebuild_layout_from(room_id)
      if not ok then mm.warn(err) end
      return true
    end

    mm.warn("Usage: mapper rebuild layout [<room_id>]")
    return true
  end

  if line == "mapper recolor map" then
    local ok, err = mm.apply_terrain_colors()
    if not ok then mm.warn(err) end
    return true
  end

  local recolorDb = line:match("^mapper%s+updatecolors%s*(.*)$")
  if recolorDb ~= nil then
    local arg = tostring(recolorDb or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "" then
      local ok, info = mm.import.update_room_colors_from_sqlite(mm.state.map_db)
      if not ok then
        mm.warn(info)
      else
        mm.note(string.format("DB room colors updated: env=%d, env-colors=%d, rooms=%d, skipped=%d", info.env_rows or 0, info.colors_applied or 0, info.rooms_updated or 0, info.rooms_skipped or 0))
      end
      return true
    end

    local ok, info = mm.import.update_room_colors_from_sqlite(arg)
    if not ok then
      mm.warn(info)
    else
      mm.note(string.format("DB room colors updated from %s: env=%d, env-colors=%d, rooms=%d, skipped=%d", tostring(info.source), info.env_rows or 0, info.colors_applied or 0, info.rooms_updated or 0, info.rooms_skipped or 0))
    end
    return true
  end

  local updatecolorsArg = line:match("^updatecolors%s*(.*)$")
  if updatecolorsArg ~= nil then
    local arg = tostring(updatecolorsArg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local ok, info = mm.import.update_room_colors_from_sqlite((arg ~= "" and arg) or mm.state.map_db)
    if not ok then
      mm.warn(info)
    else
      mm.note(string.format("DB room colors updated: env=%d, env-colors=%d, rooms=%d, skipped=%d", info.env_rows or 0, info.colors_applied or 0, info.rooms_updated or 0, info.rooms_skipped or 0))
    end
    return true
  end

  if line == "mapper rebuild map" or line == "mapper import rooms" then
    local ok, err = mm.import.convert_sqlite_to_mudlet(mm.state.map_db)
    if not ok then mm.warn(err) end
    return true
  end

  if line == "mapper rebuild lookup" or line == "mapper rebuild rooms_lookup" then
    rebuild_rooms_lookup()
    return true
  end

  return false
end

mm.alias_specs = {
  {"^mapper help(?: (.*))?$", function(m) mm.show_help(m[2]) end},
  {"^mapper stats$", function() mm.show_stats() end},
  {"^mapper stats reset$", function() mm.reset_stats() end},
  {"^mapper goto (.+)$", function(m) local ok, err = mm.goto_room(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper walkto (.+)$", function(m) local ok, err = mm.walkto_room(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper where%s*(.*)$", function(m) local ok, err = mm.where_room(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper exits(?:%s+(%d+))?$", function(m) local ok, err = mm.print_room_exits(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper area%s+(.+)$", function(m) local ok, err = mm.search_text("area", m[2]); if not ok then mm.warn(err) end end},
  {"^mapper find%s+(.+)$", function(m) local ok, err = mm.search_text("find", m[2]); if not ok then mm.warn(err) end end},
  {"^mapper list%s+(.+)$", function(m) local ok, err = mm.search_text("list", m[2]); if not ok then mm.warn(err) end end},
  {"^mapper notes(?:%s+(.+))?$", function(m) local ok, err = mm.search_notes(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper bookmarks$", function() local ok, err = mm.bookmarks.list(); if not ok then mm.warn(err) end end},
  {"^mapper bookmarks add$", function() local ok, err = mm.bookmarks.add(); if not ok then mm.warn(err) end end},
  {"^mapper bookmarks add%s+(.+)$", function(m) local ok, err = mm.bookmarks.add(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper bookmarks go%s+#(%d+)$", function(m) local ok, err = mm.bookmarks.go_index(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper bookmarks delete%s+#(%d+)$", function(m) local ok, err = mm.bookmarks.delete_index(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper bookmarks delete%s+(%d+)$", function(m) local ok, err = mm.bookmarks.delete_room(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper bookmarks rename%s+#(%d+)%s+(.+)$", function(m) local ok, err = mm.bookmarks.rename_index(m[2], m[3]); if not ok then mm.warn(err) end end},
  {"^mapper bookmarks listdeleted$", function() local ok, err = mm.bookmarks.list_deleted(); if not ok then mm.warn(err) end end},
  {"^mapper bookmarks restore%s+#(%d+)$", function(m) local ok, err = mm.bookmarks.restore_index(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper bookmarks%s+(.+)$", function(m) local ok, err = mm.bookmarks.list(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper searchnotes%s+(.+)$", function(m) local ok, err = mm.search_notes_text(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper shops?(?:%s+(.+))?$", function(m) local ok, err = mm.search_special("shops", m[2]); if not ok then mm.warn(err) end end},
  {"^mapper train(?:%s+(.+))?$", function(m) local ok, err = mm.search_special("train", m[2]); if not ok then mm.warn(err) end end},
  {"^mapper quest(?:%s+(.+))?$", function(m) local ok, err = mm.search_special("quest", m[2]); if not ok then mm.warn(err) end end},
  {"^mapper unmapped%s*(.*)$", function(m) local ok, err = mm.show_unmapped(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper boundaries%s*(.*)$", function(m) local ok, err = mm.frontier.show_boundaries(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper redirect add%s+(%d+)%s+(%d+)$", function(m) local ok, err = mm.frontier.add_redirect(m[2], m[3]); if not ok then mm.warn(err) end end},
  {"^mapper redirects%s*(%d*)$", function(m) local ok, err = mm.frontier.list_redirects(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper redirect delete%s+(%d+)$", function(m) local ok, err = mm.frontier.delete_redirect(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper redirect deleted$", function() local ok, err = mm.frontier.list_deleted_redirects(); if not ok then mm.warn(err) end end},
  {"^mapper redirect restore%s+(.+)$", function(m) local ok, err = mm.frontier.restore_redirect(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper next(?:%s+(%d+))?$", function(m) local ok, err = mm.next_result(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper cexits area%s+(.+)$", function(m) local ok, err = mm.list_cexits("area " .. m[2]); if not ok then mm.warn(err) end end},
  {"^mapper cexits(?:%s+(.+))?$", function(m) local ok, err = mm.list_cexits(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper cexit_wait%s+(.+)$", function(m) local ok, err = mm.set_cexit_wait(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper cexit%s+(.+)$", function(m) local ok, err = mm.cexit(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper randomcexits area%s+(.+)$", function(m) local ok, err = mm.list_random_cexits("area " .. m[2]); if not ok then mm.warn(err) end end},
  {"^mapper randomcexits%s+(.+)$", function(m) local ok, err = mm.list_random_cexits(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper randomcexits$", function() local ok, err = mm.list_random_cexits(); if not ok then mm.warn(err) end end},
  {"^mapper deleterandomcexit%s+(%d+)$", function(m) local ok, err = mm.delete_random_cexit(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper randomcexit%s+{(.+)}%s+(%S+)%s+{([^}]+)}%s+(%d+)$", function(m) local ok, err = mm.add_random_cexit(m[2], m[3], m[4], m[5], false); if not ok then mm.warn(err) end end},
  {"^mapper fullcexit%s+{(.+)}%s+(%S+)%s+(%S+)%s+(%d+)%s+quiet$", function(m) local ok, err = mm.add_full_cexit(m[2], m[3], m[4], m[5], true); if not ok then mm.warn(err) end end},
  {"^mapper fullcexit%s+{(.+)}%s+(%S+)%s+(%S+)%s+(%d+)$", function(m) local ok, err = mm.add_full_cexit(m[2], m[3], m[4], m[5], false); if not ok then mm.warn(err) end end},
  {"^mapper deletecexit%s+(%d+)$", function(m) local ok, err = mm.delete_cexit(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper deletedcexits$", function() local ok, err = mm.list_deleted_cexits(); if not ok then mm.warn(err) end end},
  {"^mapper restorecexit%s+(.+)$", function(m) local ok, err = mm.restore_cexit(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper lockexit$", function() local ok, err = mm.list_locked_exits_here(); if not ok then mm.warn(err) end end},
  {"^mapper lockedexits$", function() local ok, err = mm.list_locked_exits_here(); if not ok then mm.warn(err) end end},
  {"^mapper lockexit%s+(%S+)%s*(%S*)$", function(m)
      local level = tostring(m[3] or ""):lower()
      if level == "" then
        local ok, err = mm.lock_exit(m[2])
        if not ok then mm.warn(err) end
        return
      end
      if level == "off" or level == "clear" or level == "unlock" then
        local ok, err = mm.unlock_exit(m[2])
        if not ok then mm.warn(err) end
        return
      end
      local n = tonumber(m[3])
      if not n then
        mm.warn("Usage: mapper lockexit <n|s|e|w|u|d> [level|off]")
        return
      end
      local ok, err = mm.lock_exit(m[2], n)
      if not ok then mm.warn(err) end
    end},
  {"^mapper noportal(.*)$", function(m) local ok, err = mm.set_room_flag("noportal", m[2]); if not ok then mm.warn(err) end end},
  {"^mapper norecall(.*)$", function(m) local ok, err = mm.set_room_flag("norecall", m[2]); if not ok then mm.warn(err) end end},
  {"^mapper resume$", function() local ok, err = mm.resume(); if not ok then mm.warn(err) end end},
  {"^mapper thisroom$", function() mm.print_room_details() end},
  {"^mapper showroom (.+)$", function(m) mm.print_room_details(m[2]) end},
  {"^mapper saferoom$", function()
      local rid = snd and snd.room and snd.room.current and snd.room.current.rmid
      if not rid or rid == "-1" then mm.warn("Current room unknown.") return end
      if snd.mapper and snd.mapper.markRoomSafe and snd.mapper.markRoomSafe(rid, true) then
        mm.note("Room " .. tostring(rid) .. " saferoom = on")
      else
        mm.warn("Failed to update safe flag.")
      end
    end},
  {"^mapper saferoom (%w+)$", function(m)
      local arg = tostring(m[2] or ""):lower()
      local rid = snd and snd.room and snd.room.current and snd.room.current.rmid
      local value
      local targetId
      if arg == "on" or arg == "off" then
        if not rid or rid == "-1" then mm.warn("Current room unknown.") return end
        targetId = rid
        value = (arg == "on")
      elseif tonumber(arg) then
        targetId = arg
        value = true
      else
        mm.warn("Usage: mapper saferoom [on|off|<roomId>]")
        return
      end
      if snd.mapper and snd.mapper.markRoomSafe and snd.mapper.markRoomSafe(targetId, value) then
        mm.note("Room " .. tostring(targetId) .. " saferoom = " .. (value and "on" or "off"))
      else
        mm.warn("Failed to update safe flag.")
      end
    end},
  {"^mapper saferoom (%d+) (%w+)$", function(m)
      local rid = m[2]
      local arg = tostring(m[3] or ""):lower()
      local value
      if arg == "on" then value = true
      elseif arg == "off" then value = false
      else mm.warn("Usage: mapper saferoom <roomId> [on|off]") return end
      if snd.mapper and snd.mapper.markRoomSafe and snd.mapper.markRoomSafe(rid, value) then
        mm.note("Room " .. tostring(rid) .. " saferoom = " .. (value and "on" or "off"))
      else
        mm.warn("Failed to update safe flag.")
      end
    end},
  {"^mapper quicklist%s*(%S*)$", function(m) mm.state.quick_mode = mm.bool_arg(m[2], not mm.state.quick_mode); mm.note("quicklist " .. (mm.state.quick_mode and "on" or "off")) end},
  {"^mapper shownotes(?: (on|off))?$", function(m) if m[2] then mm.state.shownotes = mm.bool_arg(m[2], mm.state.shownotes) end; mm.note("shownotes " .. (mm.state.shownotes and "on" or "off")) end},
  {"^mapper compact%s*(%S*)$", function(m) mm.state.compact_mode = mm.bool_arg(m[2], not mm.state.compact_mode); mm.note("compact " .. (mm.state.compact_mode and "on" or "off")) end},
  {"^mapper backup$", function() local ok, err = mm.create_backup(true); if not ok then mm.warn(err) end end},
  {"^mapper addnote$", function()
      if type(appendCmdLine) == "function" then
        appendCmdLine("mapper addnote ")
        mm.note("Enter note text after 'mapper addnote ' and press Enter.")
      else
        mm.warn("Usage: mapper addnote <note>")
      end
    end},
  {"^mapper addnote%s+(.+)$", function(m) local ok, err = mm.add_note(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper delete note$", function() local ok, err = mm.delete_note(); if not ok then mm.warn(err) end end},
  {"^mapper backups$", function() mm.print_backup_settings() end},
  {"^mapper backups (on|off)$", function(m) mm.state.backups_enabled = mm.bool_arg(m[2], mm.state.backups_enabled); mm.note("backups " .. (mm.state.backups_enabled and "on" or "off")) end},
  {"^mapper backups quiet$", function() mm.state.backups_quiet = not mm.state.backups_quiet; mm.note("backups quiet " .. (mm.state.backups_quiet and "on" or "off")) end},
  {"^mapper backups compressed$", function() mm.state.backups_compressed = true; mm.note("backups compression on") end},
  {"^mapper backups uncompressed$", function() mm.state.backups_compressed = false; mm.note("backups compression off") end},
  {"^mapper updown$", function() mm.state.show_up_down = not mm.state.show_up_down; mm.note("updown " .. (mm.state.show_up_down and "on" or "off")) end},
  {"^mapper underlines?(?: (on|off))?$", function(m) if m[2] then mm.state.underline_links = mm.bool_arg(m[2], mm.state.underline_links) end; mm.note("underlines " .. (mm.state.underline_links and "on" or "off")) end},
  {"^mapper autolocate(?: (on|off))?$", function(m) set_native_follow(mm.bool_arg(m[2], not mm.state.auto_locate), "autolocate") end},
  {"^mapper centerlocate(?: (on|off))?$", function(m) set_native_follow(mm.bool_arg(m[2], not mm.state.auto_locate), "centerlocate") end},
  {"^mapper portalguard%s*(%S*)$", function(m) handle_portalguard(m[2]) end},
  {"^mapper autostop%s*(%S*)$", function(m) handle_autostop(m[2]) end},
  {"^mapper locate$", function() send("look") end},
  {"^mapper debug(?: (on|off))?$", function(m) if m[2] then mm.state.debug = (m[2] == "on"); mm.note("debug " .. m[2]); if m[2] == "on" then mm.debug("debugging enabled; watch for centerview/map capture lines") end else mm.note("debug " .. ((mm.state and mm.state.debug) and "on" or "off")) end end},
  {"^mapper database$", function()
      if mm.print_mapper_database_status then
        mm.print_mapper_database_status()
      else
        mm.warn("Mapper database status helper is unavailable.")
      end
    end},
  {"^mapper set database (.+)$", function(m)
      local path = tostring(m[2] or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if path == "" then
        mm.warn("Mapper database path cannot be blank. Required default filename: Aardwolf.db")
        return
      end
      mm.state.map_db = path
      mm.note("Mapper database configured value set to: " .. path)
      if mm.print_mapper_database_status then mm.print_mapper_database_status() end
    end},
  {"^mapper native db$", function() mm.note("Native mapper DB: " .. tostring(mm.resolve_native_mapper_db(mm.state.native_mapper_db))) end},
  {"^mapper native db (.+)$", function(m) mm.set_native_mapper_db(m[2]) end},
  {"^mapper native load$", function() local ok, err = mm.load_native_mapper_db(); if not ok then mm.warn(err) end end},
  {"^mapper native load (.+)$", function(m) local ok, err = mm.load_native_mapper_db(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper native inspect$", function() run_inspect(mm.state.map_db) end},
  {"^mapper native inspect (.+)$", function(m) run_inspect(m[2]) end},
  {"^mapper native convert$", function() local ok, err = mm.import.convert_sqlite_to_mudlet(mm.state.map_db); if not ok then mm.warn(err) end end},
  {"^mapper native convert (.+) to (.+)$", function(m) local ok, err = mm.import.convert_sqlite_to_mudlet(m[2], m[3]); if not ok then mm.warn(err) end end},
  {"^mapper native convert (.+)$", function(m) local ok, err = mm.import.convert_sqlite_to_mudlet(m[2]); if not ok then mm.warn(err) end end},
  {"^mapper rebuildportals$", function() local ok, err = mm.rebuild_portals_from_db(); if not ok then mm.warn(err) end end},
  {"^mapper portals$", function() local ok, err = mm.print_portals(); if not ok and err then mm.warn(err) end end},
  {"^mapper portalrecall%s+(%d+)$", function(m) local ok, err = mm.set_portal_recall(tonumber(m[2])); if not ok then mm.warn(err) else mm.note("Toggled recall flag for portal #" .. tostring(m[2])); mm.apply_bounce_settings_to_snd() end end},
  {"^mapper chaosportal%s+(%d+)$", function(m) local ok, err = mm.set_portal_chaos(tonumber(m[2])); if not ok then mm.warn(err) else mm.note("Toggled chaos flag for portal #" .. tostring(m[2])) end end},
  {"^mapper bounceportal$", function() local selected = mm.portals and mm.portals.settings and mm.portals.settings.bounce_portal_id; if not selected then mm.note("bounceportal is not set.") else local cmd = portal_command_for_selected_id(selected); if cmd and tostring(cmd) ~= "" then mm.note("bounceportal: #" .. tostring(selected) .. " -> " .. tostring(cmd)) else mm.note("bounceportal portal_id: " .. tostring(selected)) end end end},
  {"^mapper bouncerecall$", function()
    local selected = mm.portals and mm.portals.settings and mm.portals.settings.bounce_recall_id
    if not selected then
      mm.note("bouncerecall is not set.")
      return
    end
    local step = mm.get_configured_bounce_step and mm.get_configured_bounce_step("recall") or nil
    if step then
      mm.note(string.format(
        "bouncerecall portal_id: %s; command: %s; landing room: %s",
        tostring(selected), tostring(step.dir), tostring(step.uid)
      ))
    else
      mm.warn("bouncerecall portal_id " .. tostring(selected) .. " is set but no longer resolves to a usable recall portal.")
    end
  end},
  {"^mapper bounceportal clear$", function() local ok, err = mm.clear_bounce_portal(); if not ok then mm.warn(err) else mm.note("bounceportal cleared.") end end},
  {"^mapper bouncerecall clear$", function() local ok, err = mm.clear_bounce_recall(); if not ok then mm.warn(err) else mm.note("bouncerecall cleared.") end end},
  {"^mapper bounceportal%s+(%d+)$", function(m) local ok, portal_or_err = mm.set_bounce_portal(tonumber(m[2])); if not ok then mm.warn(portal_or_err) else mm.note("bounceportal set to #" .. tostring(m[2]) .. ": " .. tostring(portal_or_err.command)) end end},
  {"^mapper bouncerecall%s+(%d+)$", function(m) local ok, portal_or_err = mm.set_bounce_recall(tonumber(m[2])); if not ok then mm.warn(portal_or_err) else mm.note("bouncerecall set to #" .. tostring(m[2]) .. ": " .. tostring(portal_or_err.command)) end end},
  {"^mapper rebuild map$", function() local ok, err = mm.import.convert_sqlite_to_mudlet(mm.state.map_db); if not ok then mm.warn(err) end end},
  {"^mapper import rooms$", function() local ok, err = mm.import.convert_sqlite_to_mudlet(mm.state.map_db); if not ok then mm.warn(err) end end},
  {"^mapper rebuild lookup$", function() rebuild_rooms_lookup() end},
  {"^mapper rebuild rooms_lookup$", function() rebuild_rooms_lookup() end},
  {"^mapper recolor map$", function() local ok, err = mm.apply_terrain_colors(); if not ok then mm.warn(err) end end},
  {"^mapper updatecolors$", function() local ok, info = mm.import.update_room_colors_from_sqlite(mm.state.map_db); if not ok then mm.warn(info) else mm.note(string.format("DB room colors updated: env=%d, env-colors=%d, rooms=%d, skipped=%d", info.env_rows or 0, info.colors_applied or 0, info.rooms_updated or 0, info.rooms_skipped or 0)) end end},
  {"^mapper updatecolors (.+)$", function(m) local ok, info = mm.import.update_room_colors_from_sqlite(m[2]); if not ok then mm.warn(info) else mm.note(string.format("DB room colors updated from %s: env=%d, env-colors=%d, rooms=%d, skipped=%d", tostring(info.source), info.env_rows or 0, info.colors_applied or 0, info.rooms_updated or 0, info.rooms_skipped or 0)) end end},
  {"^updatecolors$", function() local ok, info = mm.import.update_room_colors_from_sqlite(mm.state.map_db); if not ok then mm.warn(info) else mm.note(string.format("DB room colors updated: env=%d, env-colors=%d, rooms=%d, skipped=%d", info.env_rows or 0, info.colors_applied or 0, info.rooms_updated or 0, info.rooms_skipped or 0)) end end},
  {"^updatecolors (.+)$", function(m) local ok, info = mm.import.update_room_colors_from_sqlite(m[2]); if not ok then mm.warn(info) else mm.note(string.format("DB room colors updated from %s: env=%d, env-colors=%d, rooms=%d, skipped=%d", tostring(info.source), info.env_rows or 0, info.colors_applied or 0, info.rooms_updated or 0, info.rooms_skipped or 0)) end end},
  {"^mapper rebuild layout$", function() local info = mm.get_room_info and mm.get_room_info() or nil; local start = (info and tonumber(info.num)) or 32418; local ok, err = mm.import.rebuild_layout_from(start); if not ok then mm.warn(err) end end},
  {"^mapper rebuild layout (%d+)$", function(m) local ok, err = mm.import.rebuild_layout_from(tonumber(m[2])); if not ok then mm.warn(err) end end},
  {"^mapper hide$", function() mm.minimap.hide_all() end},
  {"^mapper show$", function() mm.minimap.show_all() end},
  {"^mapper$", function() mm.show_help() end},
  {"^mapper (minimap|bigmap|map)$", function(m) show_window_status((m[2] == "map") and "bigmap" or m[2]) end},
  {"^mapper (minimap|bigmap|map) (show|hide|lock|unlock)$", function(m) handle_window_command(m[2], m[3]) end},
  {"^mapper (minimap|bigmap|map) move (%S+) (%S+)$", function(m) handle_window_command(m[2], "move", m[3], m[4]) end},
  {"^mapper (minimap|bigmap|map) resize (%S+) (%S+)$", function(m) handle_window_command(m[2], "resize", m[3], m[4]) end},
  {"^mapper (minimap|bigmap|map) fontsize (%d+)$", function(m) local which = (m[2] == "map") and "bigmap" or m[2]; mm.minimap.set_font_size(which, m[3]) end},
  {"^maptype (.+)$", function(m) mm.minimap.set_type(m[2]) end},
  {"^mapshow (roomname|room|exits|coordinates|coordinate|coords|coord|echo) (on|off)$", function(m) mm.minimap.toggle_show(m[2], m[3]) end},
  {"^resetaard$", function() mm.note("Mapper reset complete.") end},
  {"^recon?$", function() send("recon") end},
}

mm.stubbed = {
  "mapper findpath", "mapper clearcache",
  "mapper fullportal",
  "mapper areas",
  "mapper zoom in", "mapper zoom out",
}

function mm.handle_command(line)
  line = normalize_line(line)
  mm.debug("handle_command received: " .. tostring(line))
  if handle_command_inline(line) then return true end

  for _, spec in ipairs(mm.alias_specs) do
    local start_idx, end_idx = line:find(spec[1])
    if start_idx == 1 and end_idx == #line then
      local matches = {line:match(spec[1])}
      table.insert(matches, 1, line)
      spec[2](matches)
      return true
    end
  end

  if line:find("^mapper ") then
    mm.debug("no alias matched mapper command: " .. tostring(line))
    for _, prefix in ipairs(mm.stubbed) do
      if line:find("^" .. prefix) then
        mm.warn("Command recognized but not yet implemented in Mudlet port: " .. line)
        return true
      end
    end
  end
  return false
end

function mm.register_aliases()
  if mm._alias then
    pcall(killAlias, mm._alias)
    mm._alias = nil
  end
  mm._alias = tempAlias("^(mapper|mapper .+|maptype .+|mapshow .+|updatecolors(?: .+)?|resetaard|recon?)$", function()
    -- Prefer Mudlet's raw command text when available so stacked separators
    -- like ";;" are preserved for downstream mapper parsing/persistence.
    local line = command or matches[2] or matches[1]
    if mm.handle_command(line) then return end
  end)
end
