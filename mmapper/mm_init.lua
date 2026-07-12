mm = mm or {}

local function dirname(path)
  return (path:gsub("\\", "/"):match("^(.*)/") or "")
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function loader_note(message)
  cecho("<cyan>[MMAPPER]<reset> " .. tostring(message) .. "\n")
end

local function loader_error(message)
  cecho("<orange_red>[MMAPPER ERROR]<reset> " .. tostring(message) .. "\n")
end

local function resolve_base_dir()
  if mm.base_dir and mm.base_dir ~= "" then
    return mm.base_dir
  end

  local src = debug.getinfo(1, "S").source or ""
  if src:sub(1, 1) == "@" then
    local inferred = dirname(src:sub(2))
    if inferred ~= "" then
      return inferred
    end
  end

  local home = getMudletHomeDir()
  local candidates = {
    home .. "/mmapper",
    home .. "/packages/mmapper",
    home .. "/packages/mmapper/mmapper",
  }

  for _, c in ipairs(candidates) do
    if file_exists(c .. "/mm_core.lua") then
      return c
    end
  end

  return home .. "/mmapper"
end

local loadedCount = 0
local errorCount = 0

local function load_module(base, file)
  local full = base .. "/" .. file
  local ok, err = pcall(dofile, full)
  if not ok then
    errorCount = errorCount + 1
    loader_error(string.format("Failed to load %s from %s: %s", file, full, tostring(err)))
    return false
  end
  loadedCount = loadedCount + 1
  if mm and mm.debug then
    mm.debug("module loaded: " .. tostring(file))
  end
  return true
end

local base = resolve_base_dir()
mm.base_dir = base

load_module(base, "mm_core.lua")
load_module(base, "mm_area_references.lua")
load_module(base, "mm_navigation.lua")
load_module(base, "mm_frontier.lua")
load_module(base, "mm_bookmarks.lua")
load_module(base, "mm_help.lua")
load_module(base, "mm_minimap.lua")
load_module(base, "mm_commands.lua")
load_module(base, "mm_import.lua")
load_module(base, "mm_gmcp.lua")

local summary = string.format("<green>Loaded %d modules<reset>", loadedCount)
if errorCount > 0 then
  summary = summary .. string.format(" <red>(%d errors)<reset>", errorCount)
end
loader_note(summary .. " from " .. tostring(base))

if errorCount > 0 then
  loader_error("MMapper initialization stopped because one or more modules failed after the installation preflight passed. This is a module error, not a folder-placement error.")
  return
end

local function safe_step(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    loader_error("Initialization step failed (" .. tostring(label) .. "): " .. tostring(err))
    return false
  end
  return true
end

local NATIVE_LOAD_MAX_ATTEMPTS = 10
local NATIVE_LOAD_RETRY_DELAY = 0.2

local function cancel_native_startup_load()
  mm.runtime = mm.runtime or {}
  mm.runtime.native_startup_generation = (tonumber(mm.runtime.native_startup_generation) or 0) + 1
  if mm.runtime.native_startup_timer and type(killTimer) == "function" then
    pcall(killTimer, mm.runtime.native_startup_timer)
  end
  mm.runtime.native_startup_timer = nil
  return mm.runtime.native_startup_generation
end

local function fallback_hybrid_bigmap_to_local(reason)
  local configured_mode = mm.minimap and mm.minimap.get_bigmap_mode and mm.minimap.get_bigmap_mode()
  if configured_mode ~= "hybrid" then return false end

  mm.runtime = mm.runtime or {}
  mm.runtime.hybrid_native_unavailable_reason = tostring(reason or "native mapper data unavailable")
  if mm.minimap and mm.minimap.activate_bigmap_local then
    mm.minimap.activate_bigmap_local()
  end
  mm.warn("Native bigmap unavailable; hybrid mode is using the local bigmap instead (" ..
    mm.runtime.hybrid_native_unavailable_reason .. ").")
  return true
end

local function native_startup_load(generation, attempt, reason)
  mm.runtime = mm.runtime or {}
  if generation ~= mm.runtime.native_startup_generation then return end
  mm.runtime.native_startup_timer = nil

  local active_mode = mm.minimap and mm.minimap.get_active_bigmap_mode and
    mm.minimap.get_active_bigmap_mode()
  if active_mode ~= "native" then return end

  local native_path = mm.resolve_native_mapper_db(mm.state.native_mapper_db)
  if not native_path or not mm.path_exists(native_path) then
    local load_err = "native mapper DB not found at " .. tostring(native_path)
    if not fallback_hybrid_bigmap_to_local(load_err) then
      mm.warn("Native mapper DB was not auto-loaded: " .. load_err)
    end
    return
  end
  if mm.looks_like_sqlite(native_path) then
    local load_err = "configured path is the SQLite live mapper DB, not a Mudlet native map export"
    if not fallback_hybrid_bigmap_to_local(load_err) then
      mm.warn("Native mapper DB was not auto-loaded: " .. load_err)
    end
    return
  end
  if mm.runtime.native_mapper_db_loaded_path == native_path then
    if mm.sync_native_bigmap_to_current_room then
      mm.sync_native_bigmap_to_current_room(reason or "native_map_already_loaded")
    end
    return
  end

  local window = mm.minimap and mm.minimap.windows and mm.minimap.windows.bigmap
  local mapper_ready = mm.minimap and mm.minimap.backend == "mudlet_mapper" and window and window.mapper
  local loaded, err = false, "embedded mapper widget is not open yet"
  if mapper_ready then
    loaded, err = mm.load_native_mapper_db()
  end
  if loaded then return end

  if attempt < NATIVE_LOAD_MAX_ATTEMPTS and type(tempTimer) == "function" then
    mm.debug(string.format(
      "Native mapper startup load attempt %d/%d deferred: %s",
      attempt, NATIVE_LOAD_MAX_ATTEMPTS, tostring(err)))
    mm.runtime.native_startup_timer = tempTimer(NATIVE_LOAD_RETRY_DELAY, function()
      native_startup_load(generation, attempt + 1, reason)
    end)
    return
  end

  local load_err = "load failed after " .. tostring(attempt) .. " attempts: " .. tostring(err)
  if not fallback_hybrid_bigmap_to_local(load_err) then
    mm.warn("Native mapper DB was not auto-loaded: " .. load_err)
  end
end

function mm.schedule_native_mapper_load(reason)
  local generation = cancel_native_startup_load()
  if type(tempTimer) == "function" then
    mm.runtime.native_startup_timer = tempTimer(0, function()
      native_startup_load(generation, 1, reason)
    end)
  else
    native_startup_load(generation, 1, reason)
  end
end

function mm.initialize()
  if mm and mm.debug then
    mm.debug("initialization begin")
  end
  mm.runtime = mm.runtime or {}
  -- Retry native hybrid support once on each package/profile load. If it is
  -- unavailable, the runtime latch prevents every room event from reopening a
  -- blank native widget; hybrid remains on the working local surface instead.
  mm.runtime.hybrid_native_unavailable_reason = nil
  safe_step("load_settings_persistence", function()
    if mm.load_settings_persistence then
      mm.load_settings_persistence()
    end
  end)

  local mapper_db_ready = false
  safe_step("ensure_mapper_database", function()
    if not mm.ensure_mapper_database then
      mm.warn("Mapper database initializer is unavailable.")
      return
    end
    local ok, result = mm.ensure_mapper_database(mm.state and mm.state.map_db)
    if not ok then
      mm.warn("Mapper database unavailable: " .. tostring(result))
      return
    end
    mapper_db_ready = true
    if result and result.created then
      mm.note("Created new empty mapper database: " .. tostring(result.path))
      mm.warn("The new Aardwolf.db has 0 rooms and 0 exits. Replace it manually with the supplied populated Aardwolf.db if you want preloaded map data.")
    end
  end)
  local configured_mode = mm.minimap and mm.minimap.get_bigmap_mode and mm.minimap.get_bigmap_mode()
  safe_step("register_aliases", function() mm.register_aliases() end)
  safe_step("register_events", function() mm.register_events() end)
  safe_step("minimap.init", function() mm.minimap.init() end)

  if configured_mode == "native" then
    mm.schedule_native_mapper_load("native_startup")
  else
    cancel_native_startup_load()
    mm.debug("Native mapper DB autoload skipped while bigmap local/hybrid mode is active.")
  end

  if mapper_db_ready then
    safe_step("ensure_exits_chaos_column", function()
      if mm.ensure_exits_chaos_column then
        local ok, ensure_err = mm.ensure_exits_chaos_column()
        if not ok then
          mm.warn("Could not ensure exits.chaos column: " .. tostring(ensure_err))
        end
      end
    end)
  end

  safe_step("frontier.initialize", function()
    if mm.frontier and mm.frontier.initialize then
      local ok, frontier_err = mm.frontier.initialize()
      if not ok then
        mm.warn("Could not initialize boundary redirects: " .. tostring(frontier_err))
      end
    end
  end)

  if mapper_db_ready then
    safe_step("bookmarks.initialize", function()
      if mm.bookmarks and mm.bookmarks.initialize then
        local ok, bookmark_err = mm.bookmarks.initialize()
        if not ok then
          mm.warn("Could not initialize mapper bookmarks: " .. tostring(bookmark_err))
        end
      end
    end)
  end

  safe_step("load_portal_persistence", function()
    if mm.load_portal_persistence and mm.load_portal_persistence() then
      mm.note("Loaded rebuilt portals from local state file.")
      if mm.apply_bounce_settings_to_snd then
        mm.apply_bounce_settings_to_snd()
      end
    end
  end)

  safe_step("load_deleted_cexits_persistence", function()
    if mm.load_deleted_cexits_persistence then
      mm.load_deleted_cexits_persistence()
    end
  end)

  safe_step("load_deleted_portals_persistence", function()
    if mm.load_deleted_portals_persistence then
      mm.load_deleted_portals_persistence()
    end
  end)

  if mm and mm.debug then
    mm.debug("initialization completed")
  end
  mm.note("MMapper initialized from: " .. tostring(mm.base_dir))
end

safe_step("initialize", mm.initialize)
