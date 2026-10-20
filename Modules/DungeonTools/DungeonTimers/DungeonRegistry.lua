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

local pairs = pairs
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
    { key = "AltarOfFangs",      name = "Altar of Fangs",          iconID = 7956175, instanceID = 2993, season = 2 },
    { key = "DenOfNalorakk",     name = "Den of Nalorakk",         iconID = 7266214, instanceID = 2825, season = 2 },
    { key = "KingsRest",         name = "Kings' Rest",             iconID = 2011123, instanceID = 1762, season = 2 },
    { key = "MurderRow",         name = "Murder Row",              iconID = 7266213, instanceID = 2813, season = 2 },
    { key = "RubyLifePools",     name = "Ruby Life Pools",         iconID = 4578416, instanceID = 2521, season = 2 },
    { key = "TempleOfSethraliss", name = "Temple of Sethraliss",   iconID = 2011143, instanceID = 1877, season = 2 },
    { key = "TheBlindingVale",   name = "The Blinding Vale",      iconID = 7354408, instanceID = 2859, season = 2 },
    { key = "VoidscarArena",     name = "Voidscar Arena",          iconID = 7439626, instanceID = 2923, season = 2 },
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

-- string.format("%d", nil) raises on Lua 5.1, so an entry without an iconID
-- takes the question-mark texture the other icon fallbacks use.
function KE.GetDungeonTimerDungeonLabel(iconID, name)
    if iconID then
        return ("|T%d:16:16:0:0:64:64:5:59:5:59|t %s"):format(iconID, name)
    end
    return ("|TInterface\\Icons\\INV_Misc_QuestionMark:16:16:0:0:64:64:5:59:5:59|t %s"):format(name)
end

-- One group per boss with rows: its timer rows, then its reminder rows from
-- firstReminder on. The ordinal comes from the full input, so a boss left out
-- does not renumber the bosses after it.
function KE.GroupDungeonTimerBossRows(bosses)
    local groups = {}
    for position, boss in ipairs(bosses) do
        local rows, reminderRows = {}, {}
        for _, item in ipairs(boss.items) do
            if item.isAura == true then
                reminderRows[#reminderRows + 1] = item
            else
                rows[#rows + 1] = item
            end
        end
        local firstReminder
        if #reminderRows > 0 then
            firstReminder = #rows + 1
            for _, item in ipairs(reminderRows) do rows[#rows + 1] = item end
        end
        if #rows > 0 then
            groups[#groups + 1] = {
                id = boss.id,
                name = boss.name,
                ordinal = boss.bossOrder or position,
                spells = rows,
                firstReminder = firstReminder,
            }
        end
    end
    return groups
end

-- Settings-page order for one boss: the rows rowOrder names come first, in its
-- order (a number names a spell row, a string a cue by name), then every other
-- row in its incoming order.
function KE.OrderDungeonTimerBossRows(items, rowOrder)
    if type(rowOrder) ~= "table" or #rowOrder == 0 then return items end
    local ordered, placed = {}, {}
    for _, entry in ipairs(rowOrder) do
        for index, item in ipairs(items) do
            if not placed[index] then
                local match
                if type(entry) == "number" then
                    match = item.id == entry
                else
                    match = item.isCue == true and item.cueName == entry
                end
                if match then
                    placed[index] = true
                    ordered[#ordered + 1] = item
                    break
                end
            end
        end
    end
    for index, item in ipairs(items) do
        if not placed[index] then ordered[#ordered + 1] = item end
    end
    return ordered
end

local function CountEntries(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

-- Season coverage for the General tab. Timers are the non-reminder rows the
-- Dungeon Bosses tab lists; trash skips hidden fingerprint-only spells, which
-- the Dungeon Trash tab also leaves out.
function KE.CountDungeonTimerCoverage(registry, encounterData, trashData, season, isReminder)
    local inSeason, covered = {}, {}
    for _, d in ipairs(registry) do
        if d.season == season then inSeason[d.key] = true end
    end
    local c = { dungeons = 0, bosses = 0, timers = 0, reminders = 0, trashEnemies = 0, trashAbilities = 0 }
    for _, enc in pairs(encounterData) do
        if inSeason[enc.dungeon] then
            c.bosses = c.bosses + 1
            if not covered[enc.dungeon] then
                covered[enc.dungeon] = true
                c.dungeons = c.dungeons + 1
            end
            c.timers = c.timers + CountEntries(enc.spells) + CountEntries(enc.phaseCues) + CountEntries(enc.phases)
            if type(enc.auraSounds) == "table" then
                for _, rule in ipairs(enc.auraSounds) do
                    if isReminder(rule) then c.reminders = c.reminders + 1 end
                end
            end
        end
    end
    for _, dungeon in pairs(trashData) do
        if inSeason[dungeon.dungeonKey] then
            for _, mob in pairs(dungeon.mobs or {}) do
                local tracked = 0
                for _, spell in pairs(mob.spells or {}) do
                    if spell.hidden ~= true then tracked = tracked + 1 end
                end
                if tracked > 0 then
                    c.trashEnemies = c.trashEnemies + 1
                    c.trashAbilities = c.trashAbilities + tracked
                end
            end
        end
    end
    return c
end
