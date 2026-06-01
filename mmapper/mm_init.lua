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

local function load_module(base, file)
  local full = base .. "/" .. file
  local ok, err = pcall(dofile, full)
  if not ok then
    error(string.format("MMAPPER failed to load '%s': %s", full, tostring(err)))
  end
  if mm and mm.debug then
    mm.debug("module loaded: " .. tostring(file))
  elseif mm and mm.note then
    mm.note("module loaded: " .. tostring(file))
  end
end

local base = resolve_base_dir()
mm.base_dir = base

load_module(base, "mm_core.lua")
do
  local ok, err = pcall(load_module, base, "mm_navigation.lua")
  if not ok then
    if mm and mm.warn then
      mm.warn("Optional module mm_navigation.lua not loaded: " .. tostring(err))
    else
      cecho("<orange_red>[MMAPPER]<reset> Optional module mm_navigation.lua not loaded: " .. tostring(err) .. "\n")
    end
  end
end
load_module(base, "mm_help.lua")
load_module(base, "mm_minimap.lua")
load_module(base, "mm_commands.lua")
load_module(base, "mm_import.lua")
load_module(base, "mm_gmcp.lua")

local function safe_step(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    mm.warn("Initialization step failed (" .. tostring(label) .. "): " .. tostring(err))
    return false
  end
  return true
end

function mm.initialize()
  if mm and mm.debug then
    mm.debug("initialization begin")
  end
  safe_step("register_aliases", function() mm.register_aliases() end)
  safe_step("register_events", function() mm.register_events() end)
  safe_step("minimap.init", function() mm.minimap.init() end)

  local loaded, err = mm.load_native_mapper_db()
  if not loaded then
    local native_path = mm.resolve_native_mapper_db(mm.state.native_mapper_db)
    if native_path and mm.path_exists(native_path) and mm.looks_like_sqlite(native_path) then
      mm.debug("Native mapper DB autoload skipped: configured path is SQLite live mapper DB.")
    else
      mm.warn("Native mapper DB was not auto-loaded: " .. tostring(err))
    end
  end

  safe_step("ensure_exits_chaos_column", function()
    if mm.ensure_exits_chaos_column then
      local ok, ensure_err = mm.ensure_exits_chaos_column()
      if not ok then
        mm.warn("Could not ensure exits.chaos column: " .. tostring(ensure_err))
      end
    end
  end)

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
