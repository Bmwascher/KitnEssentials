-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/ClassUtilities/DoTTrackerRules.lua              ║
-- ║  Purpose: DoT Tracker's per-spec DoT table, its pure     ║
-- ║           rules and its guards. No WoW API, no frames.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local floor, math_max, math_min = math.floor, math.max, math.min
local next, pairs, tonumber, tostring, type = next, pairs, tonumber, tostring, type
local table_sort = table.sort

local Rules = {}
KE.DoTTrackerRules = Rules

Rules.BUILD_BASE = 8
Rules.BUILD_AHEAD = 4

-- class -> global spec id -> rows. Ids are the DEBUFF's, which for many spells
-- is not the id of the button that applies it. `id` is also the saved key;
-- `also` lists more debuff ids the row counts. `talent` (an id or a list):
-- listed only while one of them is known. `replacedBy`: dropped while that
-- talent is known. `cap`: the game's target limit for the DoT. `defaultOff`:
-- unticked until the player ticks it. The icon is `iconId` while `iconTalent`
-- is known.
local DEEP_WOUNDS_TALENTS = { 1261060, 1261062, 1270704 }

KE.DOT_TRACKER_SEEDS = {
    DEATHKNIGHT = {
        [250] = { { id = 55078, color = { 0.80, 0.20, 0.20 } } },
        [251] = { { id = 55095, color = { 0.40, 0.75, 1.00 } } },
        [252] = {
            { id = 191587, color = { 0.40, 0.85, 0.75 } },
            -- Applied by Outbreak.
            { id = 1240996, talent = 77575, cap = 1, color = { 0.70, 0.30, 0.90 } },
        },
    },
    DRUID = {
        [102] = {
            { id = 164812, color = { 0.50, 0.65, 1.00 } },
            { id = 164815, color = { 1.00, 0.70, 0.20 } },
        },
        [103] = {
            { id = 155722, color = { 1.00, 0.50, 0.15 } },
            { id = 1079, color = { 0.85, 0.15, 0.15 } },
            { id = 405233, color = { 1.00, 0.85, 0.30 } },
            { id = 155625, talent = 155580, color = { 0.50, 0.65, 1.00 } },
        },
        [104] = {
            { id = 164812, color = { 0.50, 0.65, 1.00 } },
            { id = 192090, color = { 1.00, 0.85, 0.30 } },
        },
        -- Restoration has Sunfire only through its talent, the 93402 cast.
        [105] = {
            { id = 164812, color = { 0.50, 0.65, 1.00 } },
            { id = 164815, talent = 93402, color = { 1.00, 0.70, 0.20 } },
        },
    },
    PRIEST = {
        [256] = {
            { id = 589, replacedBy = 204197, color = { 1.00, 0.85, 0.30 } },
            { id = 204213, talent = 204197, color = { 1.00, 0.55, 0.15 } },
        },
        [257] = { { id = 589, color = { 1.00, 0.85, 0.30 } } },
        [258] = {
            { id = 589, color = { 1.00, 0.85, 0.30 } },
            { id = 34914, color = { 0.65, 0.35, 1.00 } },
            { id = 335467, talent = 335467, color = { 1.00, 0.30, 0.60 } },
        },
    },
    ROGUE = {
        [259] = {
            { id = 703, color = { 1.00, 0.55, 0.15 } },
            { id = 1943, color = { 0.85, 0.15, 0.15 } },
        },
        [261] = { { id = 1943, color = { 0.85, 0.15, 0.15 } } },
    },
    SHAMAN = {
        [262] = { { id = 188389, cap = 6, color = { 1.00, 0.45, 0.10 } } },
        [263] = { { id = 188389, cap = 6, color = { 1.00, 0.45, 0.10 } } },
        [264] = { { id = 188389, cap = 6, color = { 1.00, 0.45, 0.10 } } },
    },
    WARLOCK = {
        -- Wither (445474) replaces Corruption and Immolate under its hero talent.
        [265] = {
            { id = 980, color = { 1.00, 0.82, 0.25 } },
            { id = 146739, also = { 445474 }, iconTalent = 445465, iconId = 445474, color = { 0.95, 0.40, 0.40 } },
            { id = 1259790, talent = 1259790, color = { 0.70, 0.42, 1.00 } },
        },
        [266] = { { id = 460553, talent = 460551, color = { 0.35, 0.82, 0.78 } } },
        [267] = {
            { id = 157736, also = { 445474 }, iconTalent = 445465, iconId = 445474, color = { 1.00, 0.48, 0.10 } },
        },
    },
    WARRIOR = {
        [71] = {
            { id = 388539, talent = 772, color = { 0.85, 0.15, 0.15 } },
            { id = 262115, talent = DEEP_WOUNDS_TALENTS, defaultOff = true, color = { 1.00, 0.55, 0.15 } },
        },
        [72] = {
            { id = 262115, talent = DEEP_WOUNDS_TALENTS, defaultOff = true, color = { 1.00, 0.55, 0.15 } },
        },
        [73] = {
            { id = 388539, talent = 772, color = { 0.85, 0.15, 0.15 } },
            { id = 262115, talent = DEEP_WOUNDS_TALENTS, defaultOff = true, color = { 1.00, 0.55, 0.15 } },
        },
    },
}

local MSG_NOT_ID = "Enter a debuff spell id (a whole number)."
local MSG_DUPLICATE = "That DoT is already listed for this spec."

function Rules.SpellKey(specID, spellID)
    return tostring(specID or 0) .. ":" .. tostring(spellID)
end

-- Canonical keys only, the form SpellKey writes: an entry under "0102:4" or
-- "102:04" could never be found again by its ids.
local function ParseKey(key)
    if type(key) ~= "string" then return nil end
    local spec, spell = key:match("^([1-9]%d*):([1-9]%d*)$")
    if not spec then return nil end
    return tonumber(spec), tonumber(spell)
end

local function ParseId(text)
    local n = tonumber(text)
    if not n or n <= 0 or n ~= floor(n) then return nil end
    return n
end

local function Entry(spells, specID, id)
    local entry = type(spells) == "table" and spells[Rules.SpellKey(specID, id)]
    if type(entry) ~= "table" then return nil end
    return entry
end

-- true at the first true read, nil when none is true but one could not be
-- read, false only when every read is a definite false.
local function AnyTrue(list, read, arg)
    local unread = false
    for i = 1, #list do
        local value = read(list[i], arg)
        if value == true then return true end
        if value == nil then unread = true end
    end
    if unread then return nil end
    return false
end

-- `talent` is one id or a list; the row shows while any of them is known.
function Rules.AnyKnown(talent, isKnown)
    if type(talent) ~= "table" then return isKnown(talent) end
    return AnyTrue(talent, isKnown)
end

-- A saved tick wins; without one a row starts on unless it ships off.
function Rules.IsEnabled(entry, row)
    if type(entry) == "table" and type(entry.enabled) == "boolean" then return entry.enabled end
    return not (row and row.defaultOff)
end

-- Every read arrives already resolved to true, false or nil. A unit whose
-- existence cannot be read is refused: nothing could be bound to it. Any other
-- nil (an error or a secret) lets the unit through, and so does strict being
-- off for the combat rule.
function Rules.Verdict(unit, strict, onlyEnemiesInCombat, api)
    if api.exists(unit) ~= true then return "no unit" end
    if api.canAttack(unit) == false then return "not attackable" end
    -- The game ignores spell-id filters for harmful auras on a unit the player
    -- can assist, so a sensor there would light for any of the player's debuffs.
    if api.canAssist(unit) == true then return "assistable" end
    if api.isDead(unit) == true then return "dead" end
    if not strict then return nil end
    if onlyEnemiesInCombat and api.inCombat(unit) == false then return "not in combat" end
    return nil
end

function Rules.Label(k, total, format)
    if format == "COUNT" then return tostring(k) end
    if format == "MISSING" then return tostring(total - k) end
    return k .. "/" .. total
end

function Rules.LabelColorKey(k, total)
    if total > 0 and k == total then return "all" end
    return "some"
end

-- The answer for k lit sensors: the DoT's target limit caps the denominator,
-- and k with it.
function Rules.Capped(k, total, cap)
    local d = cap and math_min(total, cap) or total
    return math_min(k, d), d
end

-- Hands back one of the tables it is given, so a paint allocates nothing.
function Rules.CountColor(k, d, own, some, all, fullCoverage)
    if fullCoverage and Rules.LabelColorKey(k, d) == "all" then return all end
    return own or some
end

-- nil means no color of its own: Some Have It and a black border.
function Rules.ColorOf(entry, row, colorsOn)
    if not colorsOn then return nil end
    if type(entry) == "table" and type(entry.color) == "table" then return entry.color end
    return row and row.color or nil
end

-- Each control writes only its own field, so a tick never wipes a color. An
-- entry left with nothing in it is removed.
function Rules.SetField(spells, key, field, value)
    local entry = spells[key]
    if type(entry) ~= "table" then
        entry = {}
        spells[key] = entry
    end
    entry[field] = value
    if next(entry) == nil then spells[key] = nil end
end

-- What a picker write saves. The picker sends back the color it opened with on
-- Cancel, on Escape and on any click outside it; for a row with no override of
-- its own that must leave it without one, not pin the default as an override.
function Rules.PickedColor(r, g, b, a, shown, overridden)
    if not overridden and r == shown[1] and g == shown[2] and b == shown[3] and a == (shown[4] or 1) then
        return nil
    end
    return { r, g, b, a }
end

local function SpecRows(seeds, class, specID)
    local byClass = seeds and seeds[class]
    return byClass and byClass[specID]
end

local function RowHas(row, id)
    if row.id == id then return true end
    local also = row.also
    if not also then return false end
    for i = 1, #also do
        if also[i] == id then return true end
    end
    return false
end

-- Matches the ids a row also counts, so none of them can be added as a custom.
function Rules.IsSeed(seeds, class, specID, id)
    local rows = SpecRows(seeds, class, specID)
    if not rows then return false end
    for i = 1, #rows do
        if RowHas(rows[i], id) then return true end
    end
    return false
end

-- The shipped row keyed by `id`, or nil for an added DoT.
function Rules.RowOf(seeds, class, specID, id)
    local rows = SpecRows(seeds, class, specID)
    if not rows then return nil end
    for i = 1, #rows do
        if rows[i].id == id then return rows[i] end
    end
    return nil
end

local NO_IDS = {}

-- The extra ids a row counts: none for a row without them or an added DoT.
function Rules.AlsoOf(row)
    return row and row.also or NO_IDS
end

-- A new set on every call: each sensor and timer filter gets its own.
function Rules.FilterIds(id, also)
    local ids = { [id] = true }
    for i = 1, #also do ids[also[i]] = true end
    return ids
end

function Rules.IconOf(row, id, isKnown)
    if row and row.iconId and isKnown(row.iconTalent) == true then return row.iconId end
    return id
end

function Rules.CustomIds(spells, specID)
    local ids = {}
    if type(spells) ~= "table" then return ids end
    for key, entry in pairs(spells) do
        local spec, spell = ParseKey(key)
        if spec == specID and type(entry) == "table" and entry.custom == true then
            ids[#ids + 1] = spell
        end
    end
    table_sort(ids)
    return ids
end

local function RowShown(row, isKnown)
    if row.talent and Rules.AnyKnown(row.talent, isKnown) == false then return false end
    if row.replacedBy and isKnown(row.replacedBy) == true then return false end
    return true
end

function Rules.ResolveList(seeds, spells, class, specID, isKnown)
    local out = {}
    if not specID then return out end
    local rows = SpecRows(seeds, class, specID)
    local listed = {}
    if rows then
        for i = 1, #rows do
            local row = rows[i]
            listed[row.id] = true
            -- A custom entry for an id the row also counts would count it twice.
            local also = row.also
            if also then
                for j = 1, #also do listed[also[j]] = true end
            end
            if Rules.IsEnabled(Entry(spells, specID, row.id), row) and RowShown(row, isKnown) then
                out[#out + 1] = row.id
            end
        end
    end
    local customs = Rules.CustomIds(spells, specID)
    for i = 1, #customs do
        local id = customs[i]
        local entry = Entry(spells, specID, id)
        if not listed[id] and entry and entry.enabled ~= false then
            out[#out + 1] = id
        end
    end
    return out
end

function Rules.CanAdd(seeds, spells, class, specID, text, nameOf)
    local id = ParseId(text)
    if not id then return nil, MSG_NOT_ID end
    if not nameOf(id) then return nil, "No spell has the id " .. id .. "." end
    if Rules.IsSeed(seeds, class, specID, id) then return nil, MSG_DUPLICATE end
    local entry = Entry(spells, specID, id)
    if entry and entry.custom == true then return nil, MSG_DUPLICATE end
    return id
end

function Rules.CanRemove(seeds, spells, class, specID, text)
    local id = ParseId(text)
    if not id then return nil, MSG_NOT_ID end
    if Rules.IsSeed(seeds, class, specID, id) then
        return nil, "That is a shipped DoT: untick it instead."
    end
    local entry = Entry(spells, specID, id)
    if not (entry and entry.custom == true) then
        return nil, "That id is not one of your added DoTs for this spec."
    end
    return Rules.SpellKey(specID, id)
end

---------------------------------------------------------------------------------
-- The module's guards
---------------------------------------------------------------------------------
function Rules.SameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- What an Apply may do now. Gated: any change to the row on screen, re-pointing
-- a pooled cell, and timer work. `request` is asked only when some of that is
-- owed, so a yes is always followed by the work. Refused, the row on screen
-- stays as it is; a row not yet shown waits when it needs re-pointing and
-- otherwise starts without its timers.
function Rules.PlanApply(shown, wanted, refilter, timerWork, request)
    local changed = #shown > 0 and not Rules.SameList(shown, wanted)
    if not (changed or refilter or timerWork) then return wanted, true end
    if request() then return wanted, true end
    if #shown > 0 then return shown, false end
    if refilter then return nil, false end
    return wanted, false
end

-- Whether re-pointing a pooled cell is owed: a new id, or the same id with
-- other extra ids (an added DoT on one spec can be a merged row on another).
-- Cells past the wanted list, and cells never used, are left alone.
function Rules.NeedsRefilter(cells, wanted, alsoOf)
    for i = 1, math_min(#wanted, #cells) do
        local cell = cells[i]
        local id = cell.id
        if id ~= nil and (id ~= wanted[i] or not Rules.SameList(cell.also, alsoOf(wanted[i]))) then
            return true
        end
    end
    return false
end

-- No more than the setting, and no more than the fewest sensors any shown DoT
-- has, so "/n" never counts an enemy one of the DoTs cannot see.
function Rules.UsableCap(maxEnemies, cells, shown)
    if shown == 0 then return 0 end
    local cap = maxEnemies
    for i = 1, shown do
        local built = #cells[i].sensors
        if built < cap then cap = built end
    end
    return cap
end

function Rules.BuildTarget(maxEnemies, highestTaken)
    return math_min(maxEnemies, math_max(Rules.BUILD_BASE, highestTaken + Rules.BUILD_AHEAD))
end

-- The same filter gap as the assistable refusal in Rules.Verdict.
function Rules.TimerWanted(exists, canAssist)
    return exists == true and canAssist ~= true
end

-- Threat moves on every hit on every engaged plate. It is worth a scan only for
-- a plate not yet counted while a slot is free: a mob that just joined.
function Rules.WantsThreatScan(holdsSlot, total, cap)
    return not holdsSlot and total < cap
end
