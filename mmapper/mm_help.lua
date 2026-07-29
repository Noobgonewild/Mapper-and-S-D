mm = mm or {}

mm.help_header = "GMCP Mapper Help"

mm.help_index_rows = {
  { cmd = "mapper help", desc = "Show this list" },
  { cmd = "mapper help all", desc = "Show the entire list of all mapper commands" },
  { cmd = "mapper help config", desc = "Commands for configuring the mapper" },
  { cmd = "mapper help exits", desc = "Commands for managing exits" },
  { cmd = "mapper help portals", desc = "Commands for managing portals" },
  { cmd = "mapper help boundaries", desc = "Commands for boundary discovery and manual redirects" },
  { cmd = "mapper help bookmarks", desc = "Commands for saving useful rooms by area" },
  { cmd = "mapper help searching", desc = "Commands for finding rooms" },
  { cmd = "mapper help exploring", desc = "Commands to aid exploring" },
  { cmd = "mapper help moving", desc = "Commands for moving between rooms" },
  { cmd = "mapper help utils", desc = "Other utilitarian commands" },
  { cmd = "mapper help search <txt>", desc = "Searches through help lines looking for a particular word or phrase." },
}

mm.help_table = {
  ['config'] = {
    header = "Configuration",
    rows = {
      { cmd = "mapper quicklist (on/off)", desc = "ON will cause search results to display much faster, but the results will not be sorted by distance (default is on)" },
      { cmd = "mapper shownotes [on/off]", desc = "Show status, or turn automatic room-note display on/off (default is on)" },
      { cmd = "mapper compact (on/off)", desc = "ON will make it so no blank lines are displayed by the mapper (default is off)" },
      { cmd = "mapper backups <off/on>", desc = "Turn off or on automatic database backups The default setting is on" },
      { cmd = "mapper backups quiet", desc = "Toggle whether messages are shown during backups" },
      { cmd = "mapper backups (un)/compressed", desc = "Turn off or on database backup compression The default setting is uncompressed (off)" },
      { cmd = "mapper hide", desc = "Hide map" },
      { cmd = "mapper show", desc = "Show map" },
      { cmd = "mapper minimap show/hide", desc = "Show or hide the minimap builder window" },
      { cmd = "mapper minimap move <x> <y>", desc = "Move minimap window (percent values)" },
      { cmd = "mapper minimap resize <w> <h>", desc = "Resize minimap window (percent values)" },
      { cmd = "mapper minimap lock/unlock", desc = "Lock or unlock minimap position" },
      { cmd = "mapper minimap fontsize <num>", desc = "Set minimap font size (6-32)" },
      { cmd = "mapper bigmap show/hide", desc = "Show or hide the big map window" },
      { cmd = "mapper bigmap move <x> <y>", desc = "Move big map window (percent values)" },
      { cmd = "mapper bigmap resize <w> <h>", desc = "Resize big map window (percent values)" },
      { cmd = "mapper bigmap lock/unlock", desc = "Lock or unlock big map position" },
      { cmd = "mapper bigmap fontsize <num>", desc = "Set bigmap font size (6-32)" },
      { cmd = "mapper bigmap local", desc = "Use the sidecar-compiled player-centered map with local overlap suppression" },
      { cmd = "mapper bigmap native", desc = "Use Mudlet's native mapper widget for the bigmap when available" },
      { cmd = "mapper bigmap hybrid", desc = "Use native display in continent rooms and local display inside areas" },
      { cmd = "mapper bigmap radius <1-8>", desc = "Set the local bigmap radius; 4 gives a 9x9 room grid" },
      { cmd = "mapper bigmap roomsize <10-30>", desc = "Set the preferred local-map room box size in pixels" },
      { cmd = "mapper bigmap refresh", desc = "Redraw the local bigmap from the current room" },
      { cmd = "mapper updown", desc = "Toggle up/down exit drawing" },
      { cmd = "mapper underlines [on/off]", desc = "Show status, or turn clickable link underlines on/off in mapper output" },
      { cmd = "mapper autolocate (on/off)", desc = "Automatically follow and center the native map from GMCP" },
      { cmd = "mapper centerlocate (on/off)", desc = "Compatibility alias for mapper autolocate" },
      { cmd = "mapper debug (on/off)", desc = "Toggle mapper debug diagnostics" },
      { cmd = "mapper locate", desc = "Send look to force fresh GMCP room info" },
      { cmd = "mapper database", desc = "Show configured name, resolved path, detection, schema, integrity, and room/exit counts." },
      { cmd = "mapper set database <new_name>", desc = "Change the map database file." },
      { cmd = "mapper native db", desc = "Show current native Mudlet mapper DB path" },
      { cmd = "mapper native db <path>", desc = "Set native Mudlet mapper DB path (e.g. Aardwolf.db in profile dir)" },
      { cmd = "mapper native load", desc = "Load configured native Mudlet mapper DB" },
      { cmd = "mapper native load <path>", desc = "Load native Mudlet mapper DB from path" },
      { cmd = "mapper native inspect", desc = "Inspect configured sqlite DB schema/row counts" },
      { cmd = "mapper native inspect <path>", desc = "Inspect specific sqlite DB schema/row counts" },
      { cmd = "mapper native convert", desc = "Convert configured sqlite mapper DB (default: mapper set database value) and save to mmapper_converted_map.dat" },
      { cmd = "mapper native convert <src>", desc = "Convert sqlite source DB into Mudlet map" },
      { cmd = "mapper native convert <src> to <dst>", desc = "Convert sqlite DB and save map to path" },
      { cmd = "mapper checkimport", desc = "Show Mudlet map room/area status vs Aardwolf.db room count" },
      { cmd = "mapper calccoords", desc = "Confirm an in-place rebuild of every area layout and classified cardinal links/stubs" },
      { cmd = "mapper calccoords confirm", desc = "Refresh links/layouts, compile the local display sidecar, and save" },
      { cmd = "mapper rebuild map", desc = "Recreate the map, rebuild layouts, compile the local display sidecar, and save" },
      { cmd = "mapper import rooms", desc = "Alias for mapper rebuild map" },
      { cmd = "mapper rebuild layout", desc = "Recalculate and save the current room's area from geometric database cardinal exits" },
      { cmd = "mapper rebuild layout <room>", desc = "Recalculate and save the specified room's area" },
      { cmd = "mapper rebuild lookup", desc = "Rebuild the rooms_lookup full-text room-name index from rooms; fixes missing/stale global search entries without changing rooms or exits" },
      { cmd = "mapper refresh terrain", desc = "Explicitly request and persist fresh GMCP sector/terrain metadata" },
      { cmd = "mapper recolor map", desc = "Apply Aard terrain colors using GMCP sectors data" },
      { cmd = "mapper updatecolors (db)", desc = "Load environments/terrain colors from sqlite DB (default uses configured map DB)" },
      { cmd = "mapper showenv", desc = "Show environment/terrain color mapping from sqlite DB" },
      { cmd = "updatecolors (db)", desc = "Legacy shorthand for mapper updatecolors" },
    }
  },
  ['utils'] = {
    header = "Utilities",
    rows = {
      { cmd = "mapper backup", desc = "Create new archived backup of your map database in a db_backups directory, preserving a few prior backups" },
      { cmd = "mapper addnote", desc = "Add a new note to the current room" },
      { cmd = "mapper addnote <note>", desc = "Ditto, but skips the dialog" },
      { cmd = "mapper delete note", desc = "Delete the note in the current room without using the addnote dialog" },
      { cmd = "mapper stats", desc = "Show session-only mapper update counters for rooms, areas, exits, coordinates, colors, skipped rows, and failures" },
      { cmd = "mapper stats reset", desc = "Reset the session-only mapper stats counters" },
      { cmd = "mapper ui", desc = "Show mapper/S&D UI style status (links, hover, visited, chips)" },
      { cmd = "mapper ui status", desc = "Print current mapper/S&D UI style toggles" },
      { cmd = "mapper ui links on/off", desc = "Enable or disable clickable room links in quick-where style output" },
      { cmd = "mapper ui hover on/off", desc = "Reserve toggle for hover styling behavior (OSC8 capable clients)" },
      { cmd = "mapper ui visited on/off", desc = "Enable or disable visited-room styling in quick-where cycles" },
      { cmd = "mapper ui chips on/off", desc = "Enable or disable compact status chips in mapper output headers" },
      { cmd = "mapper ui reset", desc = "Reset mapper/S&D UI style toggles to defaults (all on)" },
      { cmd = "mapper autostop [on|off]", desc = "Send the MUD command 'stop' when GMCP enters combat during active mapper navigation (default is on)" },
      { cmd = "mapper saferoom", desc = "Mark current room safe (appends 'safe' to rooms.info, preserving existing flags)" },
      { cmd = "mapper saferoom on/off", desc = "Toggle the safe flag on the current room" },
      { cmd = "mapper saferoom <roomId>", desc = "Mark the given room id as safe" },
      { cmd = "mapper saferoom <roomId> on/off", desc = "Toggle the safe flag on the given room id" },
    }
  },
  ['exits'] = {
    header = "Exit Actions",
    rows = {
      { cmd = "mapper exits", desc = "Show mapped cardinal destinations from the current room, including room names and IDs" },
      { cmd = "mapper exits <room id>", desc = "Show mapped cardinal destinations from another room" },
      { cmd = "mapper cexits", desc = "List known custom exits" },
      { cmd = "mapper cexits thisroom", desc = "List known custom exits in your current room" },
      { cmd = "mapper cexits here", desc = "List known custom exits in your current area" },
      { cmd = "mapper cexits area <name>", desc = "List known custom exits in an area name match (local or remote area)" },
      { cmd = "mapper deletecexit <number>", desc = "Delete one custom exit by table row number from your last mapper cexits list" },
      { cmd = "mapper deletedcexits", desc = "List recently deleted custom exits (history capped at 20)" },
      { cmd = "mapper restorecexit <number|last>", desc = "Restore one deleted custom exit by row number, or restorecexit last" },
      { cmd = "mapper cexit <command>", desc = "Follow and link a custom exit (ex: 'mapper cexit ride bucket') Stacked mapper walkto commands hold later steps until that room is confirmed. To insert a pause, use wait(<seconds>). To stack commands use ;; as separator (ex: 'mapper cexit open south;;south')" },
      { cmd = "mapper cexit_wait <seconds>", desc = "Set the next cexit's base confirmation window from cexit start instead of the standard 2 seconds; wait() values extend it (between 2 and 40)" },
      { cmd = "mapper randomcexit {<command>} <source> {<destination1>,<destination2>[,...]} <level>", desc = "Add or replace a random custom exit. Navigation sends it once as a terminal step, then stops without reporting or recalculating." },
      { cmd = "mapper randomcexits [thisroom|here|area <name>]", desc = "List random custom exits and all recorded possible destinations." },
      { cmd = "mapper deleterandomcexit <number>", desc = "Delete one random custom exit by row number from the last mapper randomcexits list." },
      { cmd = "mapper lockedexits", desc = "List locked exits for the current room." },
      { cmd = "mapper lockexit <n|s|e|w|u|d> [level]", desc = "Lock the selected direction and any same-room exits to the same destination by writing exits.level. Without level, sets level 999 (all levels)." },
      { cmd = "mapper lockexit <n|s|e|w|u|d> off", desc = "Remove the lock for the selected direction and any same-room exits to the same destination." },
      { cmd = "mapper fullcexit {<command>} <source> <destination> <level> (quiet)", desc = "Set all cexit aspects in one command without running it." },
    }
  },
  ['portals'] = {
    header = "Portal Actions",
    rows = {
      { cmd = "mapper portals", desc = "List known hand-held portals; click/right-click a bracketed portal row to report it" },
      { cmd = "mapper portalstats [count|all]", desc = "Show the top portals ranked by used/tried (default 20), or all portal statistics; click/right-click a portal ID to report it" },
      { cmd = "mapper portalstats recent [count]", desc = "Show the newest portal attempts with confirmation details (default 20, maximum 50)" },
      { cmd = "mapper rebuildportals", desc = "Rebuild portal list from exits with commands starting 'dinv portal use <id>'" },
      { cmd = "mapper portalguard [on|off]", desc = "Guard portal routes unless your level is within 30 of the portal level; xrtforce bypasses it" },
      { cmd = "mapper portals here/<area>", desc = "List known hand-held portals only to this or another area (by area keyword)." },
      { cmd = "mapper portal <command> level <number>", desc = "Link a handheld portal to the current room as a special exit from everwhere else. The level suffix is required (ex: 'mapper portal recall level 50'). To stack commands use ;; as separator (ex: 'mapper portal hold amulet;;enter level 50')." },
      { cmd = "mapper fullportal {<command>} {<room_id>} <level> (quiet)", desc = "Set all portal aspects in one command without being there." },
      { cmd = "mapper portalrecall <index>", desc = "Flag/unflag a portal as using a recall or home command, to avoid using it in identified norecall rooms. Find the indices with 'mapper portals'" },
      { cmd = "mapper chaosportal <index>", desc = "Toggle chaos flag on a non-recall portal. Chaos portals are ignored while actively on global quest and cannot be set as recall/bounce portals. Find the indices with 'mapper portals'" },
      { cmd = "mapper bounceportal <index>", desc = "Specifies which non-recall mapper portal to bounce through when the path calculation wants to recall or home from a portal-friendly norecall room. For this to work properly you must indicate which mapper portals use recall or home with the portalrecall command listed above. Find the indices with 'mapper portals'" },
      { cmd = "mapper bouncerecall <index>", desc = "Specifies which home/recall mapper portal to bounce through when the path calculation wants to portal from a recall-friendly noportal room. You may only choose a portal that has been marked as being a recall portal using the portalrecall command listed above. Find the indices with 'mapper portals'" },
      { cmd = "mapper bounceportal", desc = "Display the current bounce portal" },
      { cmd = "mapper bouncerecall", desc = "Display the current bounce recall" },
      { cmd = "mapper bounceportal clear", desc = "Clear the current bounce portal" },
      { cmd = "mapper bouncerecall clear", desc = "Clear the current bounce recall" },
      { cmd = "mapper noportal <room_id> (true/false)", desc = "Manually set noportal flag for a room id (not a portal index)" },
      { cmd = "mapper norecall on/off/toggle", desc = "Set or toggle the norecall flag for the current room" },
      { cmd = "mapper norecall <room_id> true/false", desc = "Manually set the norecall flag for a room id (not a portal index)" },
      { cmd = "mapper portallevel <ind> <lvl> (quiet)", desc = "Change the level lock on a portal. Find indices with 'mapper portals'. Do not manually account for tiers. Adding 'quiet' means no output." },
      { cmd = "mapper delete portal #<index>", desc = "Remove a hand-held portal by its index Find the indices with 'mapper portals'" },
      { cmd = "mapper editportal #<index> {<new cmd>}", desc = "Change a portal command using the exact index from mapper portals." },
      { cmd = "mapper deletedportals", desc = "List recently deleted portals (history capped at 20)" },
      { cmd = "mapper restoreportal <number|last>", desc = "Restore one deleted portal by row number, or restoreportal last" },
    }
  },
  ['boundaries'] = {
    header = "Boundaries and Redirects",
    rows = {
      { cmd = "mapper boundaries here", desc = "Show reachable database rooms here with exits to missing or unmapped destinations" },
      { cmd = "mapper boundaries <area>", desc = "Show reachable database rooms in an area with exits to missing or unmapped destinations" },
      { cmd = "mapper boundaries <room UID>", desc = "Use the room's area and show its reachable database boundaries" },
      { cmd = "xrtnear <room UID>", desc = "Run its stored redirect when present; if directly reachable, show its route; otherwise find the nearest reachable edge of the target's mapped graph and rank explicit database boundaries" },
      { cmd = "mapper redirect add <target UID> <destination UID>", desc = "Set or replace the single xrtnear redirect after verifying the destination is currently reachable" },
      { cmd = "mapper redirects [target UID]", desc = "List saved suggestions with clickable destinations, optionally limited to one target" },
      { cmd = "mapper redirect delete <index>", desc = "Delete an entry by index from the last mapper redirects list" },
      { cmd = "mapper redirect deleted", desc = "List deleted redirects" },
      { cmd = "mapper redirect restore <index|last>", desc = "Restore an entry from the last deleted redirect list" },
    }
  },
  ['bookmarks'] = {
    header = "Bookmarks",
    rows = {
      { cmd = "bookmark <command>", desc = "Shortcut for mapper bookmarks <command>; bookmarks and mapper bookmark also work" },
      { cmd = "bookmarkwin <command>", desc = "Shortcut for mapper bookmarkwin <command>" },
      { cmd = "mapper bookmarks", desc = "List bookmarks in your current area with clickable xrt links" },
      { cmd = "mapper bookmarks list", desc = "List all bookmarks across every area" },
      { cmd = "mapper bookmarks search <label>", desc = "Search all active bookmarks by label (case-insensitive partial match)" },
      { cmd = "mapper bookmarks here", desc = "List bookmarks in your current area" },
      { cmd = "mapper bookmarks <area>", desc = "List bookmarks in one exact or uniquely matched area" },
      { cmd = "mapper bookmarks add", desc = "Bookmark the current room using the room name as the label" },
      { cmd = "mapper bookmarks add <label>", desc = "Bookmark the current room using a custom label" },
      { cmd = "mapper bookmarks add <roomID>", desc = "Bookmark the given room using its room name as the label" },
      { cmd = "mapper bookmarks add <roomID> as <label>", desc = "Bookmark the given room using a custom label" },
      { cmd = "mapper bookmarks go #<index>", desc = "Run xrt to a bookmark from the last mapper bookmarks list" },
      { cmd = "mapper bookmarks delete #<index>", desc = "Delete a bookmark from the last mapper bookmarks list" },
      { cmd = "mapper bookmarks delete <roomID>", desc = "Delete the active bookmark for a specific room id" },
      { cmd = "mapper bookmarks rename #<index> <label>", desc = "Rename a bookmark from the last mapper bookmarks list" },
      { cmd = "mapper bookmarks pin [<exact label>|room <roomID>]", desc = "Pin an active bookmark at the top of the window; defaults to the current room (use 'label <label>' for a numeric label)" },
      { cmd = "mapper bookmarks unpin [<exact label>|room <roomID>]", desc = "Unpin by exact label or room without deleting the bookmark" },
      { cmd = "mapper bookmarks listdeleted", desc = "List the last 20 deleted bookmarks" },
      { cmd = "mapper bookmarks restore #<index>", desc = "Restore a bookmark; conflicting labels receive a _conflict name" },
      { cmd = "mapper bookmarkwin [show|hide|toggle]", desc = "Show, hide, toggle, or report the mouse-movable bookmark window" },
      { cmd = "mapper bookmarkwin auto", desc = "Show bookmarks for the current area and refresh only when the area changes" },
      { cmd = "mapper bookmarkwin manual <area>", desc = "Keep showing one exact or uniquely matched area" },
      { cmd = "mapper bookmarkwin refresh", desc = "Force the bookmark window to reload its bookmarks" },
      { cmd = "mapper bookmarkwin font <7-24>", desc = "Set bookmark window card font size" },
      { cmd = "mapper bookmarkwin title [on|off|toggle]", desc = "Show the detailed title/subtitle, or collapse them to one draggable 'Bookmarks' bar" },
    }
  },
  ['searching'] = {
    header = "Searching",
    rows = {
      { cmd = "mapper area <text>", desc = "Full-text search limited to the current zone" },
      { cmd = "mapper find <text>", desc = "Full-text search the whole database" },
      { cmd = "mapper list <text>", desc = "Find rooms without the known-path limits of \"area\" and \"find\"" },
      { cmd = "mapper notes", desc = "Show nearby rooms that you marked with notes" },
      { cmd = "mapper notes <here/area>", desc = "Ditto" },
      { cmd = "mapper searchnotes <text>", desc = "Search note text and print full matching notes" },
      { cmd = "mapper shops", desc = "Show all shops/banks" },
      { cmd = "mapper shops <here/area>", desc = "Ditto" },
      { cmd = "mapper train", desc = "Show all trainers" },
      { cmd = "mapper train <here/area>", desc = "Ditto" },
      { cmd = "mapper quest", desc = "Show all quest-givers" },
      { cmd = "mapper quest <here/area>", desc = "Ditto" },
      { cmd = "mapper next", desc = "Visit the next room in the most recent list of results." },
      { cmd = "mapper next <index>", desc = "Ditto, but skip to the given result index." },
      { cmd = "mapper where <room id>", desc = "Show directions to a room number" },
      { cmd = "mapper guarded <room id>", desc = "Preview the xrt route with AreaGuard forced on; does not move you (alias: mapper areaguard)" },
    }
  },
  ['exploring'] = {
    header = "Exploring",
    rows = {
      { cmd = "mapper thisroom", desc = "Show current-room details" },
      { cmd = "mapper showroom <room id>", desc = "Draw the map as if you were standing in a different room" },
      { cmd = "mapper areas", desc = "Show a list of all mapped areas" },
      { cmd = "mapper areas <name>", desc = "Show a list of mapped areas partially matching <name>" },
      { cmd = "mapper unmapped", desc = "List unmapped exit counts for known areas" },
      { cmd = "mapper unmapped <here/area>", desc = "List unmapped exits in this or another area" },
    }
  },
  ['moving'] = {
    header = "Moving",
    rows = {
      { cmd = "mapper goto <room id>", desc = "Run to a room by its room number" },
      { cmd = "xset areaguard <on|off>", desc = "Guard high-level xrt rooms; clan rooms are locally exempt, later rooms are checked; default off" },
      { cmd = "mapper portalguard [on|off]", desc = "Guard portal routes unless your level is within 30 of the portal level; xrtforce bypasses it" },
      { cmd = "xrtforce <area|room id>", desc = "Run like xrt but ignore area guard, portalguard, and exits.level checks (forced route)" },
      { cmd = "mapper walkto <room id>", desc = "Run to a room by its room number without using any mapper portals" },
      { cmd = "mapper resume", desc = "Initiate a new run to the previous target" },
    }
  },
}

local function wrap_text(text, width)
  local words, lines, line = {}, {}, ""
  for word in text:gmatch("%S+") do table.insert(words, word) end
  if #words == 0 then return {""} end
  for _, word in ipairs(words) do
    if line == "" then line = word
    elseif #line + 1 + #word <= width then line = line .. " " .. word
    else table.insert(lines, line); line = word end
  end
  if line ~= "" then table.insert(lines, line) end
  return lines
end

local function print_help_row(row, command_width, details_width)
  if row.cmd and row.desc then
    local cmd_lines = wrap_text(row.cmd, command_width)
    local desc_lines = wrap_text(row.desc, details_width)
    local total = math.max(#cmd_lines, #desc_lines)
    for i = 1, total do
      local cmd = cmd_lines[i] or ""
      local desc = desc_lines[i] or ""
      cecho(string.format("<cyan>%-" .. command_width .. "s<reset>  <light_grey>%s<reset>\n", cmd, desc))
    end
    return
  end

  if row.text then
    cecho("<light_grey>" .. row.text .. "<reset>\n")
    return
  end

  cecho("\n")
end

function mm.show_help(topic)
  local command_width = 34
  local details_width = 76

  local function print_section(section)
    cecho("\n<yellow>" .. section.header .. "<reset>\n\n")
    for _, row in ipairs(section.rows) do
      print_help_row(row, command_width, details_width)
    end
  end

  local function row_matches(row, needle)
    return (row.cmd and row.cmd:lower():find(needle, 1, true))
      or (row.desc and row.desc:lower():find(needle, 1, true))
      or (row.text and row.text:lower():find(needle, 1, true))
  end

  cecho("\n<white>" .. mm.help_header .. "<reset>\n\n")
  topic = (topic or ""):gsub("^%s+", ""):gsub("%s+$", "")

  if topic == "" then
    for _, row in ipairs(mm.help_index_rows) do
      print_help_row(row, command_width, details_width)
    end
  elseif topic == "all" then
    for _, key in ipairs({"config", "exits", "portals", "boundaries", "bookmarks", "searching", "exploring", "moving", "utils"}) do
      print_section(mm.help_table[key])
    end
  elseif mm.help_table[topic] then
    print_section(mm.help_table[topic])
  elseif topic:find("^search ") then
    local needle = topic:sub(8):lower()
    if needle == "" then
      for _, row in ipairs(mm.help_index_rows) do
        print_help_row(row, command_width, details_width)
      end
    else
      cecho("<orange>[MAPPER]<reset> <cyan>Searching help for: <yellow>" .. needle .. "<reset>\n")
      for _, section in pairs(mm.help_table) do
        local shown = false
        for _, row in ipairs(section.rows) do
          if row_matches(row, needle) then
            if not shown then
              cecho("\n<yellow>" .. section.header .. "<reset>\n\n")
              shown = true
            end
            print_help_row(row, command_width, details_width)
          end
        end
      end
    end
  else
    for _, row in ipairs(mm.help_index_rows) do
      print_help_row(row, command_width, details_width)
    end
  end

  cecho("\n")
end
