-- Intentional compatibility shim: MMapper owns navigation; legacy S&D uses snd.mapper.

if type(mm) ~= "table" or type(mm.canonical_room_uid) ~= "function" or type(mm.nav) ~= "table" then
    error("Search and Destroy navigation requires MMapper to be fully loaded first.")
end

snd = snd or {}
snd.mapper = mm.nav
