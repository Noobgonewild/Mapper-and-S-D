mm = mm or {}
mm.frontier = mm.frontier or {}

local frontier = mm.frontier
local REDIRECT_PERSIST_FILE = "mmapper_redirects.lua"

if frontier.exitHandler then
  pcall(killAnonymousEventHandler, frontier.exitHandler)
  frontier.exitHandler = nil
end
if frontier.dbState then
  if frontier.dbState.conn then
    pcall(function() frontier.dbState.conn:close() end)
  end
  if frontier.dbState.env then
    pcall(function() frontier.dbState.env:close() end)
  end
end
frontier.dbState = nil

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_uid(value)
  local uid = tonumber(value)
  if not uid or uid <= 0 then return nil end
  return math.floor(uid)
end

local function mapper_nav()
  return (mm and mm.nav) or (snd and snd.mapper) or nil
end

local function mapper_room_info(roomId)
  local nav = mapper_nav()
  if not (nav and type(nav.getRoomInfo) == "function") then return nil end
  return nav.getRoomInfo(roomId)
end

local function current_room()
  local room = mm.current_room and mm.current_room() or nil
  room = tonumber(room)
  if room and room > 0 then return room end
  return nil
end

local function now_millis()
  if type(getEpoch) == "function" then
    local value = tonumber(getEpoch())
    if value then
      return value < 10000000000 and value * 1000 or value
    end
  end
  return (os.clock() or 0) * 1000
end

frontier.redirects = {}
frontier.redirectsLoaded = false

local function sanitize_redirect(entry)
  if type(entry) ~= "table" then return nil end
  local target = normalize_uid(entry.target_uid)
  local destination = normalize_uid(entry.destination_uid)
  if not target or not destination or target == destination then return nil end
  return {
    target_uid = target,
    destination_uid = destination,
    target_name = trim(entry.target_name),
    destination_name = trim(entry.destination_name),
    created_at = tonumber(entry.created_at) or os.time(),
    deleted_at = tonumber(entry.deleted_at),
  }
end

local function active_redirect(targetUid)
  local target = normalize_uid(targetUid)
  if not target then return nil end

  for _, entry in ipairs(frontier.redirects) do
    if entry.target_uid == target and entry.deleted_at == nil then
      return entry
    end
  end
  return nil
end

--- Return the active redirect explicitly saved for a requested room.
-- Boundary candidates calculated by xrtnear are never stored in this table,
-- so callers cannot accidentally treat a calculated suggestion as a manual
-- redirect. Return a copy so external consumers cannot mutate persistence.
function frontier.get_manual_redirect(targetUid)
  if not frontier.redirectsLoaded then return nil end

  local redirect = active_redirect(targetUid)
  if not redirect then return nil end

  return {
    target_uid = redirect.target_uid,
    destination_uid = redirect.destination_uid,
    target_name = redirect.target_name,
    destination_name = redirect.destination_name,
    created_at = redirect.created_at,
  }
end

local function enforce_single_active_redirects()
  local activeByTarget = {}
  local collapsed = 0
  local now = os.time()

  for _, entry in ipairs(frontier.redirects) do
    if entry.deleted_at == nil then
      local previous = activeByTarget[entry.target_uid]
      if not previous then
        activeByTarget[entry.target_uid] = entry
      elseif (tonumber(entry.created_at) or 0) >= (tonumber(previous.created_at) or 0) then
        previous.deleted_at = now
        activeByTarget[entry.target_uid] = entry
        collapsed = collapsed + 1
      else
        entry.deleted_at = now
        collapsed = collapsed + 1
      end
    end
  end

  return collapsed
end

local function save_redirects()
  local started = now_millis()
  local path = type(mm.persistence_path) == "function"
    and mm.persistence_path(REDIRECT_PERSIST_FILE)
    or (getMudletHomeDir() .. "/persistence/" .. REDIRECT_PERSIST_FILE)
  local file = io.open(path, "wb")
  if not file then
    return false, "unable to open redirect persistence file directly: " .. tostring(path)
  end

  file:write("return {\n  redirects = {\n")
  for _, entry in ipairs(frontier.redirects) do
    file:write(string.format(
      "    { target_uid = %d, destination_uid = %d, target_name = %q, destination_name = %q, created_at = %d, deleted_at = %s },\n",
      entry.target_uid,
      entry.destination_uid,
      entry.target_name or "",
      entry.destination_name or "",
      entry.created_at,
      entry.deleted_at and tostring(entry.deleted_at) or "nil"
    ))
  end
  file:write("  },\n}\n")
  file:close()
  mm.debug(string.format("redirect persistence save timing: %.1fms", now_millis() - started))
  return true
end

function frontier.initialize()
  if frontier.redirectsLoaded then return true end
  local started = now_millis()
  frontier.redirects = {}

  local path = type(mm.persistence_path) == "function"
    and mm.persistence_path(REDIRECT_PERSIST_FILE)
    or (getMudletHomeDir() .. "/persistence/" .. REDIRECT_PERSIST_FILE)
  local chunk = loadfile(path)
  if chunk then
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then
      return false, "redirect persistence file is invalid"
    end

    local seen = {}
    for _, entry in ipairs(data.redirects or {}) do
      local cleaned = sanitize_redirect(entry)
      if cleaned then
        local key = tostring(cleaned.target_uid) .. ":" .. tostring(cleaned.destination_uid)
        if not seen[key] then
          seen[key] = true
          table.insert(frontier.redirects, cleaned)
        end
      end
    end
  end

  local collapsed = enforce_single_active_redirects()
  if collapsed > 0 then
    local saved, saveErr = save_redirects()
    if not saved then
      return false, "unable to persist single-redirect migration: " .. tostring(saveErr)
    end
  end
  frontier.redirectsLoaded = true
  mm.debug(string.format(
    "redirect persistence load timing: %.1fms (%d rows, %d duplicate targets collapsed)",
    now_millis() - started,
    #frontier.redirects,
    collapsed
  ))
  return true
end

local function resolve_area(scope)
  local nav = mapper_nav()
  if not (nav and nav.db and type(nav.db.query) == "function") then
    return nil, "mapper navigation database is unavailable"
  end

  scope = trim(scope)
  if scope == "" then
    return nil, "Usage: mapper boundaries <here|area|UID>"
  end

  if scope:lower() == "here" then
    local roomId = current_room()
    if not roomId then return nil, "current room is unknown; try LOOK first" end
    local info = mapper_room_info(roomId)
    local area = info and trim(info.area) or ""
    if area == "" then return nil, "current room has no mapper area" end
    return area
  end

  local roomId = normalize_uid(scope)
  if roomId then
    local info = mapper_room_info(roomId)
    local area = info and trim(info.area) or ""
    if area == "" then
      return nil, "room " .. tostring(roomId) .. " has no mapper area"
    end
    return area, nil, roomId
  end

  local exact = nav.db.query(string.format(
    "SELECT DISTINCT area FROM rooms WHERE lower(area) = lower(%s) ORDER BY area",
    nav.db.escape(scope)
  )) or {}
  if #exact == 1 then return tostring(exact[1].area or "") end

  local partial = nav.db.query(string.format(
    "SELECT DISTINCT area FROM rooms WHERE lower(area) LIKE lower(%s) ORDER BY area LIMIT 21",
    nav.db.escape("%" .. scope .. "%")
  )) or {}
  if #partial == 0 then
    return nil, "no mapper area matches '" .. scope .. "'"
  end
  if #partial > 1 then
    local names = {}
    for i = 1, math.min(#partial, 20) do
      table.insert(names, tostring(partial[i].area or "?"))
    end
    return nil, "area is ambiguous: " .. table.concat(names, ", ")
  end
  return tostring(partial[1].area or "")
end

local function add_evidence(candidates, roomId, name, area, evidence)
  roomId = normalize_uid(roomId)
  if not roomId then return end
  local candidate = candidates[roomId]
  if not candidate then
    candidate = {
      uid = roomId,
      name = tostring(name or "?"),
      area = tostring(area or ""),
      evidence = {},
      evidenceSeen = {},
    }
    candidates[roomId] = candidate
  end
  if evidence and not candidate.evidenceSeen[evidence] then
    candidate.evidenceSeen[evidence] = true
    table.insert(candidate.evidence, evidence)
  end
end

local function path_between(nav, source, destination, noPortals, noRecalls, ignoreLockedExits, ignoreAreaGuard)
  source = normalize_uid(source)
  destination = normalize_uid(destination)
  if not source or not destination or not (nav and type(nav.findPath) == "function") then
    return nil
  end
  if source == destination then return {}, 0 end
  return nav.findPath(tostring(source), tostring(destination), noPortals, noRecalls, ignoreLockedExits, ignoreAreaGuard)
end

local function target_boundary_distance(nav, target, candidateUid)
  local path, depth = path_between(nav, target, candidateUid, true, true, true, true)
  if path then return #path, tonumber(depth) or #path end

  -- Some map edges are one-way. Reverse reachability is still useful as a
  -- proximity hint, but walk-only so portals/recalls do not skew "near".
  path, depth = path_between(nav, candidateUid, target, true, true, true, true)
  if path then return #path, tonumber(depth) or #path end

  return nil, nil
end

local function graph_boundary_evidence(edge, candidateUid, towardTargetUid)
  local direction = trim(edge and edge.dir)
  if direction == "" then direction = "?" end

  if edge and edge.fromuid == candidateUid and edge.touid == towardTargetUid then
    return string.format("mapped %s -> %d", direction, towardTargetUid)
  end
  if edge and edge.touid == candidateUid and edge.fromuid == towardTargetUid then
    return string.format("incoming %s from %d", direction, towardTargetUid)
  end
  return string.format("mapped adjacency toward %d", towardTargetUid)
end

-- Walk outward from an unreachable target over the database graph without
-- assuming exit direction. The first layer containing a room that the real
-- directed router can reach is the reachability cut nearest to the target.
-- This lets xrtnear use an incoming one-way edge as proximity evidence while
-- leaving normal navigation conservative about reverse traversal.
local function nearest_reachable_graph_boundaries(nav, area, source, target)
  local edgeRows = nav.db.query(string.format([[
    SELECT source.uid AS fromuid,
           source.name AS from_name,
           source.area AS from_area,
           destination.uid AS touid,
           destination.name AS to_name,
           destination.area AS to_area,
           exits.dir AS dir
    FROM exits
    JOIN rooms AS source ON source.uid = exits.fromuid
    JOIN rooms AS destination ON destination.uid = exits.touid
    WHERE exits.fromuid NOT IN ('*', '**')
      AND lower(source.area) = lower(%s)
      AND lower(destination.area) = lower(%s)
    ORDER BY CAST(source.uid AS INTEGER), CAST(destination.uid AS INTEGER), exits.dir
  ]], nav.db.escape(area), nav.db.escape(area))) or {}

  local adjacency = {}
  local roomDetails = {}
  local function remember_room(uid, name, roomArea)
    if not roomDetails[uid] then
      roomDetails[uid] = {
        name = tostring(name or "?"),
        area = tostring(roomArea or area or ""),
      }
    end
  end
  local function link(fromUid, toUid, edge)
    adjacency[fromUid] = adjacency[fromUid] or {}
    table.insert(adjacency[fromUid], {uid = toUid, edge = edge})
  end

  for _, row in ipairs(edgeRows) do
    local fromUid = normalize_uid(row.fromuid)
    local toUid = normalize_uid(row.touid)
    if fromUid and toUid and fromUid ~= toUid then
      local edge = {
        fromuid = fromUid,
        touid = toUid,
        dir = tostring(row.dir or ""),
      }
      remember_room(fromUid, row.from_name, row.from_area)
      remember_room(toUid, row.to_name, row.to_area)
      link(fromUid, toUid, edge)
      link(toUid, fromUid, edge)
    end
  end

  if not adjacency[target] then return {} end

  local visited = {[target] = true}
  local layer = {target}
  local distance = 0
  local arrival = {}

  while #layer > 0 do
    if distance > 0 then
      table.sort(layer)
      local found = {}
      for _, uid in ipairs(layer) do
        local path, depth = path_between(nav, source, uid, nil, nil, true, true)
        if path then
          local details = roomDetails[uid] or mapper_room_info(uid) or {}
          local approach = arrival[uid] or {}
          table.insert(found, {
            uid = uid,
            name = tostring(details.name or "?"),
            area = tostring(details.area or area or ""),
            evidence = graph_boundary_evidence(approach.edge, uid, approach.from or target),
            path = path,
            depth = tonumber(depth) or #path,
            targetDistance = distance,
            targetDepth = distance,
          })
        end
      end
      if #found > 0 then return found end
    end

    local nextLayer = {}
    for _, uid in ipairs(layer) do
      for _, neighbor in ipairs(adjacency[uid] or {}) do
        if not visited[neighbor.uid] then
          visited[neighbor.uid] = true
          arrival[neighbor.uid] = {from = uid, edge = neighbor.edge}
          table.insert(nextLayer, neighbor.uid)
        end
      end
    end
    layer = nextLayer
    distance = distance + 1
  end

  return {}
end

function frontier.find_boundaries(scope, options)
  options = type(options) == "table" and options or {}
  local area, err, targetRoom = resolve_area(scope)
  if not area then return nil, err end
  local rankTarget = normalize_uid(options.rankTarget or targetRoom)

  local nav = mapper_nav()
  local candidates = {}
  local danglingRows = nav.db.query(string.format([[
    SELECT source.uid, source.name, source.area, exits.dir, exits.touid
    FROM exits
    JOIN rooms AS source ON source.uid = exits.fromuid
    LEFT JOIN rooms AS destination ON destination.uid = exits.touid
    WHERE lower(source.area) = lower(%s)
      AND exits.fromuid NOT IN ('*', '**')
      AND (
        exits.touid IS NULL
        OR trim(CAST(exits.touid AS TEXT)) = ''
        OR CAST(exits.touid AS TEXT) = '-1'
        OR substr(lower(CAST(exits.touid AS TEXT)), 1, 6) = 'nomap_'
        OR destination.uid IS NULL
      )
    ORDER BY CAST(source.uid AS INTEGER), exits.dir
  ]], nav.db.escape(area))) or {}

  for _, row in ipairs(danglingRows) do
    add_evidence(
      candidates,
      row.uid,
      row.name,
      row.area,
      string.format("unmapped %s -> %s", tostring(row.dir or "?"), tostring(row.touid or "?"))
    )
  end

  local source = current_room()
  if not source then return nil, "current room is unknown; try LOOK first" end

  if options.targetAware and rankTarget then
    for _, boundary in ipairs(nearest_reachable_graph_boundaries(nav, area, source, rankTarget)) do
      add_evidence(
        candidates,
        boundary.uid,
        boundary.name,
        boundary.area,
        boundary.evidence
      )
      local candidate = candidates[boundary.uid]
      candidate.path = boundary.path
      candidate.depth = boundary.depth
      candidate.pathKnown = true
      candidate.targetDistance = boundary.targetDistance
      candidate.targetDepth = boundary.targetDepth
    end
  end

  local reachable = {}
  for _, candidate in pairs(candidates) do
    local path, depth
    if candidate.pathKnown then
      path, depth = candidate.path, candidate.depth
    elseif candidate.uid == source then
      path, depth = {}, 0
    else
      -- Boundary discovery is display-only; use an unguarded route lookup
      -- rather than xrt's movement guards.
      path, depth = path_between(nav, source, candidate.uid, nil, nil, true, true)
    end
    if path then
      candidate.path = path
      candidate.pathLength = #path
      candidate.depth = tonumber(depth) or #path
      if options.targetAware and rankTarget and candidate.targetDistance == nil then
        candidate.targetDistance, candidate.targetDepth = target_boundary_distance(nav, rankTarget, candidate.uid)
      end
      candidate.evidenceSeen = nil
      table.insert(reachable, candidate)
    end
  end

  table.sort(reachable, function(a, b)
    if options.rankByTarget then
      local aTarget = tonumber(a.targetDistance) or math.huge
      local bTarget = tonumber(b.targetDistance) or math.huge
      if aTarget ~= bTarget then
        return aTarget < bTarget
      end
    end
    if a.pathLength ~= b.pathLength then
      return a.pathLength < b.pathLength
    end
    return a.uid < b.uid
  end)
  return reachable, nil, {area = area, targetRoom = targetRoom}
end

local function echo_xrt_link(label, uid)
  local command = string.format([[mm.goto_room(%d)]], uid)
  echoLink(label, command, "Run xrt " .. tostring(uid), true)
end

local function echo_xrt_path(candidate)
  local label = string.format("path %d", tonumber(candidate.pathLength) or 0)
  echo_xrt_link(label, candidate.uid)
end

local function show_boundary_rows(rows, area, options)
  options = type(options) == "table" and options or {}
  local targetRoom = normalize_uid(options.targetRoom)
  if targetRoom then
    cecho(string.format("\n<cyan>Reachable boundary rooms by mapped distance from room %d in %s:<reset>\n", targetRoom, tostring(area or "?")))
    cecho("<gray>------------------------------------------------------------------------------------------------<reset>\n")
    cecho(string.format("<white>%-34s %-10s %-10s %-10s %s<reset>\n", "Room", "(uid)", "Route", "MapDist", "Evidence"))
    cecho("<gray>------------------------------------------------------------------------------------------------<reset>\n")
    for _, candidate in ipairs(rows) do
      local mapped = candidate.targetDistance and string.format("map %d", candidate.targetDistance) or "map ?"
      cecho(string.format("%-34s (%-8d) ", tostring(candidate.name or "?"):sub(1, 34), candidate.uid))
      echo_xrt_path(candidate)
      cecho(string.format("  %-10s <dim_gray>%s<reset>\n", mapped, table.concat(candidate.evidence or {}, ", ")))
    end
    cecho("<gray>------------------------------------------------------------------------------------------------<reset>\n")
  else
    cecho(string.format("\n<cyan>Reachable boundary rooms in %s:<reset>\n", tostring(area or "?")))
    cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
    cecho(string.format("<white>%-36s %-10s %-10s %s<reset>\n", "Room", "(uid)", "Route", "Evidence"))
    cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
    for _, candidate in ipairs(rows) do
      cecho(string.format("%-36s (%-8d) ", tostring(candidate.name or "?"):sub(1, 36), candidate.uid))
      echo_xrt_path(candidate)
      cecho("  <dim_gray>" .. table.concat(candidate.evidence or {}, ", ") .. "<reset>\n")
    end
    cecho("<gray>--------------------------------------------------------------------------------<reset>\n")
  end
end

function frontier.show_boundaries(scope)
  local rows, err, context = frontier.find_boundaries(scope)
  if not rows then return false, err end
  if #rows == 0 then
    mm.note("No reachable boundary rooms found in " .. tostring(context.area) .. ".")
    return true
  end
  show_boundary_rows(rows, context.area)
  mm.note(string.format("Found %d reachable boundary room%s.", #rows, #rows == 1 and "" or "s"))
  return true
end

function frontier.show_near_boundaries(targetUid)
  local target = normalize_uid(targetUid)
  if not target then return false, "Usage: xrtnear <room UID>" end

  local rows, err, context = frontier.find_boundaries(tostring(target), {
    targetAware = true,
    rankByTarget = true,
    rankTarget = target,
  })
  if not rows then return false, err end
  if #rows == 0 then
    mm.note("No reachable boundary rooms found near room " .. tostring(target) .. ".")
    return true
  end

  local hasMappedDistance = false
  for _, candidate in ipairs(rows) do
    if candidate.targetDistance ~= nil then
      hasMappedDistance = true
      break
    end
  end
  if not hasMappedDistance then
    mm.note(string.format(
      "No mapped walk-distance from room %d to reachable boundaries; showing reachable boundary rooms in %s instead.",
      target,
      tostring(context.area or "?")
    ))
    show_boundary_rows(rows, context.area)
    mm.note(string.format("Found %d reachable boundary room%s.", #rows, #rows == 1 and "" or "s"))
    return true
  end

  show_boundary_rows(rows, context.area, {targetRoom = target})
  mm.note(string.format(
    "Found %d reachable boundary room%s with mapped distance from room %d.",
    #rows,
    #rows == 1 and "" or "s",
    target
  ))
  return true
end

local function show_reachable_target(target, path)
  local info = mapper_room_info(target) or {}
  local name = trim(info.name) ~= "" and trim(info.name) or "room"
  cecho("\n<cyan>Mapper has a route to the target room:<reset>\n")
  cecho(string.format("  %-36s (%-8d) ", tostring(name):sub(1, 36), target))
  echo_xrt_link(string.format("path %d", path and #path or 0), target)
  cecho("\n")
end

local function show_gq_blocked_chaos_target(target, path)
  local info = mapper_room_info(target) or {}
  local name = trim(info.name) ~= "" and trim(info.name) or "room"
  cecho("\n<yellow>Mapper found a chaos-portal route, but it is disabled during GQ:<reset>\n")
  cecho(string.format(
    "  %-36s (%-8d) path %d <yellow>[GQ chaos blocked]<reset>\n",
    tostring(name):sub(1, 36),
    target,
    path and #path or 0
  ))
end

function frontier.xrtnear(targetUid)
  local target = normalize_uid(targetUid)
  if not target then return false, "Usage: xrtnear <room UID>" end

  if not frontier.redirectsLoaded then
    return false, "redirect persistence is not initialized; reload the mapper package"
  end

  local nav = mapper_nav()
  if not (nav and type(nav.findPath) == "function") then
    return false, "mapper navigation is unavailable"
  end

  local source = current_room()
  if not source then return false, "current room is unknown; try LOOK first" end
  if source == target then
    mm.note(string.format("Already in room %d.", target))
    return true
  end

  local redirect = active_redirect(target)
  if redirect then
    local destination = normalize_uid(redirect.destination_uid)
    if not (nav and type(nav.xrt) == "function") then
      return false, "mapper navigation is unavailable"
    end
    mm.note(string.format(
      "xrtnear redirect: room %d -> room %d%s.",
      target,
      destination,
      trim(redirect.destination_name) ~= "" and " (" .. trim(redirect.destination_name) .. ")" or ""
    ))
    if nav.xrt(tostring(destination)) then return true end
    return false, string.format("stored xrtnear redirect %d -> %d could not be started", target, destination)
  end

  local directPath, routePlan
  if type(nav.planNavigationRoute) == "function" then
    local ok, selected, details = pcall(
      nav.planNavigationRoute,
      tostring(source),
      tostring(target),
      true,
      false
    )
    if ok then
      directPath = selected and selected.path or nil
      routePlan = details
    else
      if type(mm.debug) == "function" then
        mm.debug("xrtnear route preview failed: " .. tostring(selected))
      end
    end
  else
    directPath = path_between(nav, source, target)
    if not directPath and type(nav.buildOutwardJumpRoute) == "function" then
      directPath = nav.buildOutwardJumpRoute(tostring(source), tostring(target), nil)
    end
  end
  if directPath then
    show_reachable_target(target, directPath)
    return true
  end

  if type(nav.findGqChaosDiagnosticPath) == "function" then
    routePlan = type(routePlan) == "table" and routePlan or {}
    local chaosPath = nav.findGqChaosDiagnosticPath(
      tostring(source),
      tostring(target),
      routePlan.noPortals,
      routePlan.noRecalls,
      false,
      false
    )
    if chaosPath then
      show_gq_blocked_chaos_target(target, chaosPath)
      return true
    end
  end

  return frontier.show_near_boundaries(tostring(target))
end

local function validate_redirect_destination(destination)
  local nav = mapper_nav()
  local source = current_room()
  if not (nav and type(nav.findPath) == "function") then
    return false, "mapper navigation is unavailable"
  end
  if not source then
    return false, "current room is unknown; try LOOK first"
  end
  if source == destination then return true end

  local path = nav.findPath(tostring(source), tostring(destination))
  if not path and type(nav.buildOutwardJumpRoute) == "function" then
    path = nav.buildOutwardJumpRoute(tostring(source), tostring(destination), nil)
  end
  if not path then
    return false, string.format(
      "redirect room %d is not reachable from current room %d; redirect was not saved",
      destination,
      source
    )
  end
  return true
end

local function redirect_rows(targetUid, deleted)
  if not frontier.redirectsLoaded then
    return nil, "redirect persistence is not initialized; reload the mapper package"
  end

  local rows = {}
  for _, row in ipairs(frontier.redirects) do
    local isDeleted = row.deleted_at ~= nil
    if isDeleted == deleted and (not targetUid or row.target_uid == targetUid) then
      table.insert(rows, row)
    end
  end
  table.sort(rows, function(a, b)
    if a.target_uid ~= b.target_uid then return a.target_uid < b.target_uid end
    return a.destination_uid < b.destination_uid
  end)
  return rows
end

local function native_room_name(roomId)
  if type(getRoomName) ~= "function" then return nil end
  local ok, name = pcall(getRoomName, roomId)
  name = ok and trim(name) or ""
  return name ~= "" and name or nil
end

local function enrich_redirect(row)
  if trim(row.target_name) == "" then
    row.target_name = native_room_name(row.target_uid) or "?"
  end
  if trim(row.destination_name) == "" then
    row.destination_name = native_room_name(row.destination_uid) or "?"
  end
  return row
end

local function print_redirect_rows(rows, deleted)
  cecho(deleted and "\n<cyan>Deleted redirects:<reset>\n" or "\n<cyan>Manual redirects:<reset>\n")
  cecho("<gray>------------------------------------------------------------------------------------------------<reset>\n")
  cecho(string.format("<white>%-4s %-34s %-10s %-34s %-10s<reset>\n", "#", "Requested room", "(uid)", "Redirect room", "(uid)"))
  cecho("<gray>------------------------------------------------------------------------------------------------<reset>\n")
  for index, row in ipairs(rows) do
    enrich_redirect(row)
    cecho(string.format(
      "%-4d %-34s (%-8s) %-34s ",
      index,
      tostring(row.target_name):sub(1, 34),
      tostring(row.target_uid),
      tostring(row.destination_name):sub(1, 34)
    ))
    local destination = normalize_uid(row.destination_uid)
    if destination then
      echoLink(
        string.format("(%d)", destination),
        string.format([[mm.goto_room(%d)]], destination),
        "Run xrt " .. tostring(destination),
        true
      )
    else
      cecho(string.format("(%s)", tostring(row.destination_uid or "?")))
    end
    echo("\n")
  end
  cecho("<gray>------------------------------------------------------------------------------------------------<reset>\n")
end

function frontier.list_redirects(targetUid)
  local started = now_millis()
  local target = trim(targetUid)
  if target ~= "" then
    target = normalize_uid(target)
    if not target then return false, "Usage: mapper redirects [target UID]" end
  else
    target = nil
  end

  local rows, err = redirect_rows(target, false)
  if not rows then return false, err end
  mm.runtime = mm.runtime or {}
  mm.runtime.redirect_last_rows = rows
  if #rows == 0 then
    mm.note("No manual redirects found.")
    mm.debug(string.format("mapper redirects timing: %.1fms (0 rows)", now_millis() - started))
    return true
  end
  print_redirect_rows(rows, false)
  mm.note(string.format("Showing %d redirect%s.", #rows, #rows == 1 and "" or "s"))
  mm.debug(string.format("mapper redirects timing: %.1fms (%d rows)", now_millis() - started, #rows))
  return true
end

function frontier.add_redirect(targetUid, destinationUid)
  local target = normalize_uid(targetUid)
  local destination = normalize_uid(destinationUid)
  if not target or not destination then
    return false, "Usage: mapper redirect add <target UID> <destination UID>"
  end
  if target == destination then return false, "target and destination must be different rooms" end
  local targetInfo = mapper_room_info(target)
  local destinationInfo = mapper_room_info(destination)
  if not targetInfo then return false, "target room is not in the mapper database: " .. tostring(target) end
  if not destinationInfo then return false, "redirect room is not in the mapper database: " .. tostring(destination) end

  if not frontier.redirectsLoaded then
    return false, "redirect persistence is not initialized; reload the mapper package"
  end

  local reachable, reachErr = validate_redirect_destination(destination)
  if not reachable then return false, reachErr end

  local existing = active_redirect(target)
  if existing then
    if existing.destination_uid == destination then
      return false, string.format("redirect %d -> %d already exists", target, destination)
    end

    local previousDestination = existing.destination_uid
    local previousDestinationName = existing.destination_name
    local previousTargetName = existing.target_name
    local previousCreated = existing.created_at
    existing.destination_uid = destination
    existing.destination_name = trim(destinationInfo.name)
    existing.target_name = trim(targetInfo.name)
    existing.created_at = os.time()
    local saved, saveErr = save_redirects()
    if not saved then
      existing.destination_uid = previousDestination
      existing.destination_name = previousDestinationName
      existing.target_name = previousTargetName
      existing.created_at = previousCreated
      return false, saveErr
    end
    mm.note(string.format(
      "Updated redirect for room %d: room %d -> room %d.",
      target,
      previousDestination,
      destination
    ))
    return true
  end

  for _, deleted in ipairs(frontier.redirects) do
    if deleted.target_uid == target and deleted.destination_uid == destination then
      local previousDeleted = deleted.deleted_at
      local previousCreated = deleted.created_at
      local previousTargetName = deleted.target_name
      local previousDestinationName = deleted.destination_name
      deleted.deleted_at = nil
      deleted.created_at = os.time()
      deleted.target_name = trim(targetInfo.name)
      deleted.destination_name = trim(destinationInfo.name)
      local saved, saveErr = save_redirects()
      if not saved then
        deleted.deleted_at = previousDeleted
        deleted.created_at = previousCreated
        deleted.target_name = previousTargetName
        deleted.destination_name = previousDestinationName
        return false, saveErr
      end
      mm.note(string.format("Added redirect: room %d -> room %d.", target, destination))
      return true
    end
  end

  local entry = {
    target_uid = target,
    destination_uid = destination,
    target_name = trim(targetInfo.name),
    destination_name = trim(destinationInfo.name),
    created_at = os.time(),
    deleted_at = nil,
  }
  table.insert(frontier.redirects, entry)
  local saved, saveErr = save_redirects()
  if not saved then
    table.remove(frontier.redirects)
    return false, saveErr
  end

  mm.note(string.format("Added redirect: room %d -> room %d.", target, destination))
  return true
end

function frontier.delete_redirect(index)
  local pick = tonumber(index)
  local rows = mm.runtime and mm.runtime.redirect_last_rows or nil
  local row = rows and rows[pick] or nil
  if not row then
    return false, "Run 'mapper redirects' first, then use: mapper redirect delete <index>"
  end
  local previousDeleted = row.deleted_at
  row.deleted_at = os.time()
  local saved, saveErr = save_redirects()
  if not saved then
    row.deleted_at = previousDeleted
    return false, saveErr
  end
  table.remove(rows, pick)
  mm.note(string.format("Deleted redirect: room %s -> room %s.", row.target_uid, row.destination_uid))
  return true
end

function frontier.list_deleted_redirects()
  local rows, err = redirect_rows(nil, true)
  if not rows then return false, err end
  table.sort(rows, function(a, b)
    return (tonumber(a.deleted_at) or 0) > (tonumber(b.deleted_at) or 0)
  end)
  mm.runtime = mm.runtime or {}
  mm.runtime.redirect_deleted_rows = rows
  if #rows == 0 then
    mm.note("No deleted redirects found.")
    return true
  end
  print_redirect_rows(rows, true)
  mm.note(string.format("Showing %d deleted redirect%s.", #rows, #rows == 1 and "" or "s"))
  return true
end

function frontier.restore_redirect(which)
  local rows = mm.runtime and mm.runtime.redirect_deleted_rows or nil
  if not rows or #rows == 0 then
    return false, "Run 'mapper redirect deleted' first."
  end

  local index
  if trim(which):lower() == "last" then
    index = 1
  else
    index = tonumber(which)
  end
  local row = index and rows[index] or nil
  if not row then return false, "Usage: mapper redirect restore <index|last>" end

  local replaced = active_redirect(row.target_uid)
  local replacedDeleted = replaced and replaced.deleted_at or nil
  if replaced and replaced ~= row then
    replaced.deleted_at = os.time()
  end

  local previousDeleted = row.deleted_at
  local previousCreated = row.created_at
  row.deleted_at = nil
  row.created_at = os.time()
  local saved, saveErr = save_redirects()
  if not saved then
    if replaced and replaced ~= row then
      replaced.deleted_at = replacedDeleted
    end
    row.deleted_at = previousDeleted
    row.created_at = previousCreated
    return false, saveErr
  end
  table.remove(rows, index)
  if replaced and replaced ~= row then
    mm.note(string.format(
      "Restored redirect: room %s -> room %s (replaced room %s).",
      row.target_uid,
      row.destination_uid,
      replaced.destination_uid
    ))
  else
    mm.note(string.format("Restored redirect: room %s -> room %s.", row.target_uid, row.destination_uid))
  end
  return true
end

if frontier.xrtNearAlias then
  killAlias(frontier.xrtNearAlias)
end
frontier.xrtNearAlias = tempAlias("^xrtnear(?:\\s+(.*))?$", function()
  local target = matches[2] or ""
  local ok, err = frontier.xrtnear(target)
  if not ok then mm.warn(err) end
end)
