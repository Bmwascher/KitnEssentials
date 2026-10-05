-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/ClassUtilities/DoTTrackerRules.lua              ║
-- ║  Purpose: DoT Tracker's per-spec DoT table, its pure     ║
-- ║           rules and its guards. No WoW API, no frames.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local floor, math_max, math_min = math.floor, math.max, math.min
local pairs, tonumber, tostring, type = pairs, tonumber, tostring, type
local table_sort = table.sort

local Rules = {}
KE.DoTTrackerRules = Rules

Rules.BUILD_BASE = 8
Rules.BUILD_AHEAD = 4

-- class -> global spec id -> rows. Ids are the DEBUFF's, which for many spells
-- is not the id of the button that applies it. `talent`: listed only while
-- that talent is known. `replacedBy`: dropped while that talent is known.
KE.DOT_TRACKER_SEEDS = {
    DEATHKNIGHT = {
        [250] = { { id = 55078 } },
        [251] = { { id = 55095 } },
        [252] = { { id = 191587 } },
    },
    DRUID = {
        [102] = { { id = 164812 }, { id = 164815 }, { id = 202347, talent = 202347 } },
        [103] = { { id = 155722 }, { id = 1079 }, { id = 155625, talent = 155580 } },
        [104] = { { id = 164812 } },
        [105] = { { id = 164812 }, { id = 164815 } },
    },
    HUNTER = {
        [253] = { { id = 271788 } },
        [254] = { { id = 271788 } },
        [255] = { { id = 271788 } },
    },
    PRIEST = {
        [256] = { { id = 589, replacedBy = 204197 }, { id = 204213, talent = 204197 } },
        [257] = { { id = 589 } },
        [258] = { { id = 589 }, { id = 34914 } },
    },
    ROGUE = {
        [259] = { { id = 703 }, { id = 1943 } },
        [261] = { { id = 1943 } },
    },
    SHAMAN = {
        [262] = { { id = 188389 } },
        [263] = { { id = 188389 } },
        [264] = { { id = 188389 } },
    },
    WARLOCK = {
        [265] = { { id = 980 }, { id = 146739 }, { id = 445474 } },
        [267] = { { id = 157736 }, { id = 445474 } },
    },
    WARRIOR = {
        [71] = { { id = 388539, talent = 772 }, { id = 262115 } },
        [73] = { { id = 388539, talent = 772 }, { id = 262115 } },
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

function Rules.IsSeed(seeds, class, specID, id)
    local byClass = seeds and seeds[class]
    local rows = byClass and byClass[specID]
    if not rows then return false end
    for i = 1, #rows do
        if rows[i].id == id then return true end
    end
    return false
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
    if row.talent and isKnown(row.talent) == false then return false end
    if row.replacedBy and isKnown(row.replacedBy) == true then return false end
    return true
end

function Rules.ResolveList(seeds, spells, class, specID, isKnown)
    local out = {}
    if not specID then return out end
    local byClass = seeds and seeds[class]
    local rows = byClass and byClass[specID]
    local listed = {}
    if rows then
        for i = 1, #rows do
            local row = rows[i]
            listed[row.id] = true
            local entry = Entry(spells, specID, row.id)
            if not (entry and entry.enabled == false) and RowShown(row, isKnown) then
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

-- On a unit the player can assist, the game ignores the spell-id filter for
-- harmful auras, so the timer would show any of the player's debuffs there.
function Rules.TimerWanted(exists, canAssist)
    return exists == true and canAssist ~= true
end

-- Threat moves on every hit on every engaged plate. It is worth a scan only for
-- a plate not yet counted while a slot is free: a mob that just joined.
function Rules.WantsThreatScan(holdsSlot, total, cap)
    return not holdsSlot and total < cap
end
