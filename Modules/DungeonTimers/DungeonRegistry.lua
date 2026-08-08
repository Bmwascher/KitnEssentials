-- ╔══════════════════════════════════════════════════════════╗
-- ║  DungeonRegistry.lua                                     ║
-- ║  Canonical Dungeon Timers dungeon registry + selection   ║
-- ║  helpers. The single source for dungeon identity in the  ║
-- ║  GUI: dropdown options, reset rows, sidebar keywords,    ║
-- ║  and initial selection all read this table.              ║
-- ║                                                          ║
-- ║  season is a GUI browsing filter ONLY — the combat path  ║
-- ║  never reads it; off-season dungeons stay fully live     ║
-- ║  when you zone into them.                                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local ipairs = ipairs

-- instanceID = instance map ID (GetInstanceInfo 8th return); each value
-- matches the KE.TrashData mapID for the same dungeonKey. Ordered
-- alphabetically by name within each season — the dungeon dropdown
-- renders registry order.
KE.DungeonTimerDungeons = {
    { key = "AlgetharAcademy",   name = "Algeth'ar Academy",       iconID = 4578414, instanceID = 2526, season = 1 },
    { key = "MagistersTerrace",  name = "Magisters' Terrace",      iconID = 7439625, instanceID = 2811, season = 1 },
    { key = "MaisaraCaverns",    name = "Maisara Caverns",         iconID = 7322719, instanceID = 2874, season = 1 },
    { key = "NexusPointXenas",   name = "Nexus-Point Xenas",       iconID = 7553062, instanceID = 2915, season = 1 },
    { key = "PitOfSaron",        name = "Pit of Saron",            iconID = 343641,  instanceID = 658,  season = 1 },
    { key = "SeatOfTriumvirate", name = "Seat of the Triumvirate", iconID = 1711340, instanceID = 1753, season = 1 },
    { key = "Skyreach",          name = "Skyreach",                iconID = 1002596, instanceID = 1209, season = 1 },
    { key = "WindrunnerSpire",   name = "Windrunner Spire",        iconID = 7266215, instanceID = 2805, season = 1 },
}

-- Distinct seasons, ascending.
function KE.GetDungeonTimerSeasons(registry)
    local seen, list = {}, {}
    for _, d in ipairs(registry) do
        if not seen[d.season] then
            seen[d.season] = true
            list[#list + 1] = d.season
        end
    end
    table.sort(list)
    return list
end

-- Registry entries for one season, in registry order.
function KE.GetDungeonTimerDungeonsForSeason(registry, season)
    local list = {}
    for _, d in ipairs(registry) do
        if d.season == season then list[#list + 1] = d end
    end
    return list
end

-- Initial Dungeons-tab selection: the instance the player is standing in
-- wins, then the saved selection (validated — a stale key falls through),
-- then the newest season's first dungeon. Returns season, dungeonKey.
function KE.ResolveDungeonTimerSelection(registry, instanceID, saved)
    if instanceID then
        for _, d in ipairs(registry) do
            if d.instanceID == instanceID then return d.season, d.key end
        end
    end
    if saved and saved.dungeon then
        for _, d in ipairs(registry) do
            if d.key == saved.dungeon then return d.season, d.key end
        end
    end
    local newest
    for _, d in ipairs(registry) do
        if not newest or d.season > newest then newest = d.season end
    end
    for _, d in ipairs(registry) do
        if d.season == newest then return newest, d.key end
    end
    return nil, nil
end
