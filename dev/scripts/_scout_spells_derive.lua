-- _scout_spells_derive.lua: the rules of derive-scout-spells.lua, apart from
-- file reading, so dev/spec/scout_spells_derive_spec.lua can run them on rows
-- it builds. Loaded by dofile:
--
--   local Derive = dofile(_dir .. "_scout_spells_derive.lua")
--   local lines, words, scopes = Derive.Run(tables, { spellIds = ids, num = CSV.num, wrap = Source.Wrap })
--
-- `tables` maps SpellName, SpellCategories, SpellEffect, SpellMisc and
-- SpellRange to rows keyed by column name, as _db2_csv.lua reads them. Run
-- returns the output lines, in the stored form `wrap` gives them, and the two
-- maps; a refusal raises error(msg, 0). FileMatches says whether a file's text
-- is exactly those lines.
--
-- Rules, on DifficultyID 0 rows only:
--   1. Word: SpellCategories.Mechanic, then EffectMechanic by EffectIndex. The
--      first id in WORDS gives the word.
--   2. Scope, range-0 spells only: any ImplicitTarget 24 gives Cone;
--      ImplicitTarget_0 22 with _1 in 15, 30 or 7, or _0 in 15 or 30, gives
--      Around it; otherwise no row, since Self is the default.
--   3. A spell id with no SpellName row fails the run.

local M = {}

local WORDS = {
    [1] = "Charm", [2] = "Disorient", [3] = "Disarm", [5] = "Fear", [7] = "Root", [8] = "Slow",
    [9] = "Silence", [10] = "Sleep", [11] = "Slow", [12] = "Stun", [13] = "Freeze", [14] = "Knockout",
    [17] = "Poly", [18] = "Banish", [20] = "Shackle", [23] = "Turn", [24] = "Horror", [26] = "Kick",
    [27] = "Daze", [30] = "Sap",
}

local TARGET_CONE = 24
local TARGET_AROUND_FIRST = 22
local AROUND_SECOND = { [15] = true, [30] = true, [7] = true }
local AROUND_ALONE = { [15] = true, [30] = true }

local function appendTable(lines, name, ids, map)
    lines[#lines + 1] = name .. "={"
    for _, id in ipairs(ids) do
        if map[id] then lines[#lines + 1] = ('    [%d]="%s",'):format(id, map[id]) end
    end
    lines[#lines + 1] = "},"
end

function M.Run(tables, cfg)
    local num = cfg.num

    local named = {}
    for _, r in ipairs(tables.SpellName) do named[num(r.ID)] = true end

    local categoryOf = {}
    for _, r in ipairs(tables.SpellCategories) do
        if num(r.DifficultyID) == 0 then categoryOf[num(r.SpellID)] = num(r.Mechanic) end
    end

    local effectsOf = {}
    for _, r in ipairs(tables.SpellEffect) do
        if num(r.DifficultyID) == 0 then
            local id = num(r.SpellID)
            local effects = effectsOf[id] or {}
            effectsOf[id] = effects
            effects[#effects + 1] = {
                index = num(r.EffectIndex),
                mechanic = num(r.EffectMechanic),
                target0 = num(r.ImplicitTarget_0),
                target1 = num(r.ImplicitTarget_1),
            }
        end
    end
    for _, effects in pairs(effectsOf) do
        table.sort(effects, function(a, b) return a.index < b.index end)
    end

    local rangeIndexOf = {}
    for _, r in ipairs(tables.SpellMisc) do
        if num(r.DifficultyID) == 0 then rangeIndexOf[num(r.SpellID)] = num(r.RangeIndex) end
    end

    local rangeMaxOf = {}
    for _, r in ipairs(tables.SpellRange) do rangeMaxOf[num(r.ID)] = num(r.RangeMax_0) end

    local function wordOf(id)
        local word = WORDS[categoryOf[id]]
        if word then return word end
        for _, e in ipairs(effectsOf[id] or {}) do
            if WORDS[e.mechanic] then return WORDS[e.mechanic] end
        end
        return nil
    end

    local function scopeOf(id)
        local index = rangeIndexOf[id]
        if index and (rangeMaxOf[index] or 0) ~= 0 then return nil end
        local around = false
        for _, e in ipairs(effectsOf[id] or {}) do
            if e.target0 == TARGET_CONE or e.target1 == TARGET_CONE then return "Cone" end
            if (e.target0 == TARGET_AROUND_FIRST and AROUND_SECOND[e.target1]) or AROUND_ALONE[e.target0] then
                around = true
            end
        end
        return around and "Around it" or nil
    end

    local ids = {}
    for i, id in ipairs(cfg.spellIds) do ids[i] = id end
    table.sort(ids)

    local words, scopes = {}, {}
    for _, id in ipairs(ids) do
        if not named[id] then error(("%d has no SpellName row"):format(id), 0) end
        words[id] = wordOf(id)
        scopes[id] = scopeOf(id)
    end

    local source = { "return {" }
    appendTable(source, "words", ids, words)
    appendTable(source, "scopes", ids, scopes)
    source[#source + 1] = "}"
    return cfg.wrap("ScoutSpells", "dev/scripts/derive-scout-spells.lua", source), words, scopes
end

function M.FileMatches(text, lines)
    return (text:gsub("\r\n", "\n")) == table.concat(lines, "\n") .. "\n"
end

return M
