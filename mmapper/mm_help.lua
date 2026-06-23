mm = mm or {}

mm.help_header = "                              (GMCP Mapper Help)"

mm.help_index_rows = {
  { cmd = "mapper help", desc = "Show this list" },
  { cmd = "mapper help all", desc = "Show the entire list of all mapper commands" },
  { cmd = "mapper help config", desc = "Commands for configuring the mapper" },
  { cmd = "mapper help exits", desc = "Commands for managing exits" },
  { cmd = "mapper help portals", desc = "Commands for managing portals" },
  { cmd = "mapper help boundaries", desc = "Commands for boundary discovery and manual redirects" },
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
      { cmd = "mapper bigmap show/hide", desc = "Show or hide the big map builder window (native Mudlet mapper when available)" },
      { cmd = "mapper bigmap move <x> <y>", desc = "Move big map window (percent values)" },
      { cmd = "mapper bigmap resize <w> <h>", desc = "Resize big map window (percent values)" },
      { cmd = "mapper bigmap lock/unlock", desc = "Lock or unlock big map position" },
      { cmd = "mapper bigmap fontsize <num>", desc = "Set bigmap fallback font size (6-32)" },
      { cmd = "mapper updown", desc = "Toggle up/down exit drawing" },
      { cmd = "mapper underlines [on/off]", desc = "Show status, or turn clickable link underlines on/off in mapper output" },
      { cmd = "mapper autolocate (on/off)", desc = "Automatically sync Mudlet mapper room from GMCP" },
      { cmd = "mapper centerlocate (on/off)", desc = "Center view each auto-locate update" },
      { cmd = "mapper rebuild layout on/off", desc = "Toggle auto rebuild layout on area entry" },
      { cmd = "mapper debug (on/off)", desc = "Toggle mapper debug diagnostics" },
      { cmd = "mapper locate", desc = "Send look to force fresh GMCP room info" },
      { cmd = "mapper database", desc = "Print the name of the map database file." },
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
      { cmd = "mapper calccoords", desc = "Confirm a non-destructive rebuild of every area layout from database cardinal exits" },
      { cmd = "mapper calccoords confirm", desc = "Recalculate and save every sorted area layout with progress" },
      { cmd = "mapper rebuild map", desc = "Recreate rooms/exits, rebuild every sorted area layout, and save" },
      { cmd = "mapper import rooms", desc = "Alias for mapper rebuild map" },
      { cmd = "mapper rebuild layout", desc = "Recalculate and save the current room's area from database cardinal exits" },
      { cmd = "mapper rebuild layout <room>", desc = "Recalculate and save the specified room's area" },
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
      { cmd = "mapper ui", desc = "Show mapper/S&D UI style status (links, hover, visited, chips)" },
      { cmd = "mapper ui status", desc = "Print current mapper/S&D UI style toggles" },
      { cmd = "mapper ui links on/off", desc = "Enable or disable clickable room links in quick-where style output" },
      { cmd = "mapper ui hover on/off", desc = "Reserve toggle for hover styling behavior (OSC8 capable clients)" },
      { cmd = "mapper ui visited on/off", desc = "Enable or disable visited-room styling in quick-where cycles" },
      { cmd = "mapper ui chips on/off", desc = "Enable or disable compact status chips in mapper output headers" },
      { cmd = "mapper ui reset", desc = "Reset mapper/S&D UI style toggles to defaults (all on)" },
      { cmd = "mapper saferoom", desc = "Mark current room safe (appends 'safe' to rooms.info, preserving existing flags)" },
      { cmd = "mapper saferoom on/off", desc = "Toggle the safe flag on the current room" },
      { cmd = "mapper saferoom <roomId>", desc = "Mark the given room id as safe" },
      { cmd = "mapper saferoom <roomId> on/off", desc = "Toggle the safe flag on the given room id" },
    }
  },
  ['exits'] = {
    header = "Exit Actions",
    rows = {
      { cmd = "mapper cexits", desc = "List known custom exits" },
      { cmd = "mapper cexits thisroom", desc = "List known custom exits in your current room" },
      { cmd = "mapper cexits here", desc = "List known custom exits in your current area" },
      { cmd = "mapper cexits area <name>", desc = "List known custom exits in an area name match (local or remote area)" },
      { cmd = "mapper deletecexit <number>", desc = "Delete one custom exit by table row number from your last mapper cexits list" },
      { cmd = "mapper deletedcexits", desc = "List recently deleted custom exits (history capped at 20)" },
      { cmd = "mapper restorecexit <number|last>", desc = "Restore one deleted custom exit by row number, or restorecexit last" },
      { cmd = "mapper cexit <command>", desc = "Follow and link a custom exit (ex: 'mapper cexit ride bucket') To insert a pause during execution of the cexit, use wait(<seconds>) as one or more of the cexit moves To stack commands use ;; as separator (ex: 'mapper cexit open south;;south')" },
      { cmd = "mapper cexit_wait <seconds>", desc = "Wait this number of seconds instead of the standard 2 when constructing the next cexit (between 2 and 40)" },
      { cmd = "mapper lockedexits", desc = "List locked exits for the current room." },
      { cmd = "mapper lockexit <n|s|e|w|u|d> [level]", desc = "Lock the selected direction and any same-room exits to the same destination by writing exits.level. Without level, sets level 999 (all levels)." },
      { cmd = "mapper lockexit <n|s|e|w|u|d> off", desc = "Remove the lock for the selected direction and any same-room exits to the same destination." },
      { cmd = "mapper fullcexit {<command>} <source> <destination> <level> (quiet)", desc = "Set all cexit aspects in one command without running it." },
    }
  },
  ['portals'] = {
    header = "Portal Actions",
    rows = {
      { cmd = "mapper portals", desc = "List known hand-held portals" },
      { cmd = "mapper rebuildportals", desc = "Rebuild portal list from exits with commands starting 'dinv portal use <id>'" },
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
      { cmd = "mapper norecall <room_id> (true/false)", desc = "Manually set norecall flag for a room id (not a portal index)" },
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
      { cmd = "mapper boundaries here", desc = "Show reachable boundary rooms in the current area without moving" },
      { cmd = "mapper boundaries <area>", desc = "Show reachable boundary rooms in an area name or key" },
      { cmd = "mapper boundaries <room UID>", desc = "Use the room's area and show its reachable boundary rooms" },
      { cmd = "xrtnear <room UID>", desc = "Run its stored redirect when present; otherwise show reachable boundary rooms in the target area" },
      { cmd = "mapper redirect add <target UID> <destination UID>", desc = "Set or replace the single xrtnear redirect after verifying the destination is currently reachable" },
      { cmd = "mapper redirects [target UID]", desc = "List saved suggestions with clickable destinations, optionally limited to one target" },
      { cmd = "mapper redirect delete <index>", desc = "Delete an entry by index from the last mapper redirects list" },
      { cmd = "mapper redirect deleted", desc = "List deleted redirects" },
      { cmd = "mapper redirect restore <index|last>", desc = "Restore an entry from the last deleted redirect list" },
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
    }
  },
  ['exploring'] = {
    header = "Exploring",
    rows = {
      { cmd = "mapper thisroom", desc = "Show details about the current room" },
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
      { cmd = "xset areaguard <on|off>", desc = "Persistently guard xrt routes from areas more than 30 levels above you; default off" },
      { cmd = "xrtforce <area|room id>", desc = "Run like xrt but ignore area guard and exits.level checks (forced route)" },
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
      cecho(string.format("<light_steel_blue>%-" .. command_width .. "s<reset>  <light_grey>%s<reset>\n", cmd, desc))
    end
    return
  end

  if row.text then
    cecho("<dark_sea_green>" .. row.text .. "<reset>\n")
    return
  end

  cecho("\n")
end

function mm.show_help(topic)
  local command_width = 42
  local details_width = 78

  local function print_section(section)
    cecho("\n<medium_purple>" .. section.header .. "<reset>\n\n")
    for _, row in ipairs(section.rows) do
      print_help_row(row, command_width, details_width)
    end
  end

  local function row_matches(row, needle)
    return (row.cmd and row.cmd:lower():find(needle, 1, true))
      or (row.desc and row.desc:lower():find(needle, 1, true))
      or (row.text and row.text:lower():find(needle, 1, true))
  end

  cecho("\n<deep_sky_blue>" .. mm.help_header .. "<reset>\n")
  topic = (topic or ""):gsub("^%s+", ""):gsub("%s+$", "")

  if topic == "" then
    for _, row in ipairs(mm.help_index_rows) do
      print_help_row(row, command_width, details_width)
    end
  elseif topic == "all" then
    for _, key in ipairs({"config", "exits", "portals", "boundaries", "searching", "exploring", "moving", "utils"}) do
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
      cecho("<cornflower_blue>Searching help for: <tomato>" .. needle .. "<reset>\n")
      for _, section in pairs(mm.help_table) do
        local shown = false
        for _, row in ipairs(section.rows) do
          if row_matches(row, needle) then
            if not shown then
              cecho("\n<medium_purple>" .. section.header .. "<reset>\n\n")
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
