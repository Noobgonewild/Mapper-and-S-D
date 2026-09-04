mm = mm or {}

mm.help_header = "GMCP Mapper Help"

mm.help_index_rows = {
  { cmd = "mapper help", desc = "Show this list" },
  { cmd = "mapper version", desc = "Show the currently loaded mapper build number" },
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
      { cmd = "mapper bigmap native", desc = "Use Mudlet's native mapper widget for the bigmap when available" },
      { cmd = "mapper bigmap hybrid", desc = "Use native display in continent rooms and local display inside areas" },
      { cmd = "mapper native preload [on/off]", desc = "Preload the native map after startup through the normal native BigMap, then restore hybrid; off keeps lazy first-continent loading" },
      { cmd = "mapper bigmap radius <1-8>", desc = "Set the local bigmap radius; 4 gives a 9x9 room grid" },
      { cmd = "mapper bigmap roomsize <10-30>", desc = "Set the preferred local-map room box size in pixels" },
      { cmd = "mapper zoom in/out", desc = "Zoom the active bigmap in or out; local zoom scales the complete view" },
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
      { cmd = "mapper version", desc = "Show the currently loaded mapper build number" },
      { cmd = "mapper backup", desc = "Create new archived backup of your map database in a db_backups directory, preserving a few prior backups" },
      { cmd = "mapper addnote", desc = "Append a new note line to the current room" },
      { cmd = "mapper addnote <note>", desc = "Append a new note line without using the dialog" },
      { cmd = "mapper delete note", desc = "Delete the only note, or list numbered choices when the room has multiple notes" },
      { cmd = "mapper delete note <number>", desc = "Delete one numbered note from the current room" },
      { cmd = "mapper delete note all", desc = "Delete every note from the current room" },
      { cmd = "mapper stats", desc = "Show session-only mapper update counters for rooms, areas, exits, coordinates, colors, skipped rows, and failures" },
      { cmd = "mapper stats reset", desc = "Reset the session-only mapper stats counters" },
      { cmd = "mapper bigmap renderstats", desc = "Show measured local-render time and drawable reuse counters" },
      { cmd = "mapper bigmap renderstats reset", desc = "Reset local-render measurements for a fresh travel sample" },
      { cmd = "mapper ui", desc = "Show optional search/QW text settings (links, chips); these do not change map windows or navigation" },
      { cmd = "mapper ui status", desc = "Show links/chips settings; changes apply to newly printed output" },
      { cmd = "mapper ui links [on/off]", desc = "Toggle clickable room entries in search/QW text, or explicitly turn them on/off" },
      { cmd = "mapper ui hover", desc = "Unused legacy command: hover styling was never implemented and has no effect" },
      { cmd = "mapper ui visited", desc = "Unused legacy command: visited-room styling was never implemented and has no effect" },
      { cmd = "mapper ui chips [on/off]", desc = "Toggle the [QW] target heading above search results, or explicitly turn it on/off" },
      { cmd = "mapper ui reset", desc = "Restore clickable room entries and the [QW] target heading (both on)" },
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
      { cmd = "mapper cexit <command>", desc = "Follow and link a custom exit (ex: 'mapper cexit ride bucket') Stacked mapper walkto commands hold later steps until that room is confirmed. To insert a pause, use wait(<seconds>). Stack commands with ; or ;; (ex: 'mapper cexit open south;south')" },
      { cmd = "mapper cexit_wait <seconds>", desc = "Set the next cexit's base confirmation window from cexit start instead of the standard 2 seconds; wait() values extend it (between 2 and 40)" },
      { cmd = "mapper cexitkeys [thisroom]", desc = "List unresolved observed key uses; pairs already configured with cexitif are removed" },
      { cmd = "mapper cexitkeys delete <row>", desc = "Delete one row from the last mapper cexitkeys list" },
      { cmd = "mapper cexitif <row> keyid <id> do {<alternate command>}", desc = "Add or replace an alternate using a current key ID; Mapper stores its full keywords and later identifies newly looted items with that key name" },
      { cmd = "mapper cexitif <row> key {<exact keywords>} do {<alternate command>}", desc = "Add or replace an alternate using an exact full-identify keyword set" },
      { cmd = "mapper cexitif <row> test", desc = "Check DINV and show which cexit command would run without moving" },
      { cmd = "mapper cexitif <row> off", desc = "Remove the alternate while keeping the regular cexit" },
      { cmd = "mapper randomcexit {<command>} <source> {<destination1>,<destination2>[,...]} <level>", desc = "Add or replace a random custom exit. Navigation sends it once as a terminal step, then stops without reporting or recalculating." },
      { cmd = "mapper randomcexits [thisroom|here|area <name>]", desc = "List random custom exits and all recorded possible destinations." },
      { cmd = "mapper deleterandomcexit <number>", desc = "Delete one random custom exit by row number from the last mapper randomcexits list." },
      { cmd = "mapper lockedexits", desc = "List locked exits for the current room." },
      { cmd = "mapper lockexit <n|s|e|w|u|d> [level]", desc = "Set the selected cardinal direction and unlocked (level 0) cexits to the same destination. Existing nonzero cexit levels are preserved. Without level, sets 999." },
      { cmd = "mapper lockexit <n|s|e|w|u|d> off", desc = "Set exits.level to 0 for only the selected cardinal direction." },
      { cmd = "mapper fullcexit {<command>} <source> <destination> <level> (quiet)", desc = "Set all cexit aspects without running it. The command inside braces is stored exactly as entered." },
    }
  },
  ['portals'] = {
    header = "Portal Actions",
    rows = {
      { cmd = "mapper portals", desc = "List known hand-held portals; click/right-click a bracketed portal row to report or copy it" },
      { cmd = "mapper portalstats [count|all]", desc = "Show current portals ranked by used/tried, followed by unused portals in mapper order (default 20); click/right-click a portal ID to report or copy it" },
      { cmd = "mapper portalstats unused [count|all]", desc = "Show only current portals that have never been attempted" },
      { cmd = "mapper chaosstats [count|all]", desc = "Show the same statistics for current chaos portals only, including unused chaos portals (default 20); portal IDs can be reported or copied" },
      { cmd = "mapper chaosstats unused [count|all]", desc = "Show only current chaos portals that have never been attempted" },
      { cmd = "mapper portalstats recent [count]", desc = "Show the newest portal attempts with confirmation details (default 20, maximum 50)" },
      { cmd = "mapper rebuildportals", desc = "Rebuild portal list from exits with commands starting 'dinv portal use <id>'" },
      { cmd = "mapper portalguard", desc = "List individually guarded DINV portals and their required effective levels" },
      { cmd = "mapper portalguard <portal-id> [guard-level]", desc = "Add a per-portal effective-level surcharge (default +20); recall portals cannot be guarded" },
      { cmd = "mapper portalguard <portal-id> off", desc = "Remove the individual guard from a DINV portal; xrtforce bypasses guards" },
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
      { cmd = "mapper analyzelanding <room id>[,room id,...]", desc = "Analyze one or more portal landing rooms (e.g. 16600, 2199). Each landing shows its travel comparison and a table containing only other area starts made shorter by the new portal" },
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
      { cmd = "mapper unmapped <here/area>", desc = "List indexed, directly explorable cardinal exits in this or another area" },
      { cmd = "mapper explore <index>", desc = "Walk without portals to that indexed source room and prepare its unmapped exit" },
      { cmd = "mapper explore next [direction]", desc = "Take one prepared cardinal exit; a direction selects between multiple exits" },
      { cmd = "mapper explore status", desc = "Show the current Explore state" },
      { cmd = "mapper explore stop", desc = "Stop Explore without cancelling unrelated movement" },
      { cmd = "mapper explore window <on|off|toggle>", desc = "Enable, disable, or toggle the compact Explore controller" },
      { cmd = "mapper explore window fontsize <6-32>", desc = "Set the Explore controller font size (default 11)" },
    }
  },
  ['moving'] = {
    header = "Moving",
    rows = {
      { cmd = "mapper goto <room id>", desc = "Run to a room by its room number" },
      { cmd = "xset areaguard <on|off>", desc = "Guard high-level xrt rooms; clan rooms are locally exempt, later rooms are checked; default off" },
      { cmd = "mapper portalguard <portal-id> [guard-level|off]", desc = "Set a per-DINV-portal effective-level surcharge (default +20), remove it with off, or omit the ID to list guards" },
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
