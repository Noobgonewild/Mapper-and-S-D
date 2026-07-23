--[[
    Search and Destroy - Navigation Compatibility Shim

    Navigation, portal management, and mapper DB import logic now live under
    mmapper/mm_navigation.lua and are owned by the mapper package.

    This shim keeps legacy S&D entry points working by attaching snd.mapper
    to the navigation module already loaded and owned by MMapper.
]]

if type(mm) ~= "table" or type(mm.canonical_room_uid) ~= "function" or type(mm.nav) ~= "table" then
    error("Search and Destroy navigation requires MMapper to be fully loaded first.")
end

snd = snd or {}
snd.mapper = mm.nav
