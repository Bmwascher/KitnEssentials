-- _forever_cc_derive.lua: the rules of derive-forever-cc.lua, apart from
-- file reading, so dev/spec/forever_cc_derive_spec.lua can run them on rows
-- it builds. Loaded by dofile:
--
--   local Derive = dofile(_dir .. "_forever_cc_derive.lua")
--   local lines = Derive.Run(tables, { entries = ENTRIES,
--       classless = CLASSLESS_SKILL_LINES, num = CSV.num })
--
-- `tables` maps SpellName, SkillLineAbility, SpellEffect, SpellCategories
-- and SpellLevels to rows keyed by column name, as _db2_csv.lua reads them.
-- Run returns the output lines; every refusal raises error(msg, 0).
--
-- Rules:
--   1. The ranks of an entry are the SkillLineAbility rows whose Spell has
--      one of the entry's `names` and no race mask, whose ClassMask has the
--      class bit (class id n is bit n-1) or is 0 in a skill line that
--      `classless` gives the class, and whose AcquireMethod is not 3 (no
--      trainer). Each of the entry's names needs a rank, or the run fails.
--   2. A rank's debuff is the rank itself when a DifficultyID 0 SpellEffect
--      row applies an aura (Effect 6), else a spell one of its effects
--      triggers that does. Any other rank fails.
--   3. Every debuff carries the entry's `mechanic`: its DifficultyID 0
--      SpellCategories Mechanic, or the EffectMechanic of one of its Effect
--      6 rows, equals it. Otherwise the run fails.
--   4. An entry with `debuffs` lists its debuff ids, for a spell whose cast
--      applies nothing. The class still needs a rank by rule 1, which is
--      not printed; each listed id must have the entry's first name, apply
--      an aura and carry the mechanic, or the run fails.
--   5. Ids print in rank order: SupercedesSpell chain depth, then SpellLevels
--      BaseLevel, then id; listed debuffs print as listed. A debuff two
--      ranks of one entry give prints once; one two entries give fails.
--   6. Output: KE.CC_TRACKER_SEEDS in the retail table's shape, ids eight
--      to a line.

local M = {}

local IDS_PER_LINE = 8

local function fail(msg)
    error(msg, 0)
end

-- Lua 5.1 has no bit operators; bit is 0-based.
local function hasBit(mask, bit)
    return math.floor(mask / 2 ^ bit) % 2 == 1
end

function M.Run(tables, cfg)
    local num, classless = cfg.num, cfg.classless

    local nameOf = {}
    for _, r in ipairs(tables.SpellName) do
        nameOf[num(r.ID)] = r.Name_lang
    end

    local effectsOf = {}
    for _, r in ipairs(tables.SpellEffect) do
        if num(r.DifficultyID) == 0 then
            local id = num(r.SpellID)
            local effects = effectsOf[id] or {}
            effectsOf[id] = effects
            effects[#effects + 1] = {
                effect = num(r.Effect),
                mechanic = num(r.EffectMechanic),
                trigger = num(r.EffectTriggerSpell),
            }
        end
    end

    local mechanicOf = {}
    for _, r in ipairs(tables.SpellCategories) do
        if num(r.DifficultyID) == 0 then mechanicOf[num(r.SpellID)] = num(r.Mechanic) end
    end

    local levelOf = {}
    for _, r in ipairs(tables.SpellLevels) do
        if num(r.DifficultyID) == 0 then levelOf[num(r.SpellID)] = num(r.BaseLevel) end
    end

    local function appliesAura(id)
        for _, e in ipairs(effectsOf[id] or {}) do
            if e.effect == 6 then return true end
        end
        return false
    end

    -- Rule 2.
    local function debuffOf(id)
        if appliesAura(id) then return id end
        for _, e in ipairs(effectsOf[id] or {}) do
            if e.trigger > 0 and appliesAura(e.trigger) then return e.trigger end
        end
        fail(("%d %s applies no aura and triggers none"):format(id, nameOf[id] or "?"))
    end

    -- Rule 3.
    local function checkMechanic(id, mechanic)
        if mechanicOf[id] == mechanic then return end
        for _, e in ipairs(effectsOf[id] or {}) do
            if e.effect == 6 and e.mechanic == mechanic then return end
        end
        fail(("%d %s lacks mechanic %d"):format(id, nameOf[id] or "?", mechanic))
    end

    -- Rules 1 and 5: the entry's ranks, lowest first.
    local function ranksOf(entry)
        local names, matched = {}, {}
        for _, name in ipairs(entry.names) do names[name] = true end
        local byId, ranks = {}, {}
        for _, r in ipairs(tables.SkillLineAbility) do
            local id, mask = num(r.Spell), num(r.ClassMask)
            local name = nameOf[id] or ""
            local classOk
            if mask == 0 then
                classOk = classless[num(r.SkillLine)] == entry.class
            else
                classOk = hasBit(mask, entry.class - 1)
            end
            if classOk and names[name] and num(r.RaceMasks_0) == 0
                and num(r.AcquireMethod) ~= 3 and not byId[id] then
                matched[name] = true
                byId[id] = { id = id, supersedes = num(r.SupercedesSpell), level = levelOf[id] or 0 }
                ranks[#ranks + 1] = byId[id]
            end
        end
        -- Each name, so a second name cannot pass on the first one's ranks.
        for _, name in ipairs(entry.names) do
            if not matched[name] then fail(("no rank of %s for class %d"):format(name, entry.class)) end
        end
        for _, rank in ipairs(ranks) do
            local depth, cur = 0, rank
            while cur.supersedes > 0 and byId[cur.supersedes] and depth < 50 do
                depth, cur = depth + 1, byId[cur.supersedes]
            end
            rank.depth = depth
        end
        table.sort(ranks, function(a, b)
            if a.depth ~= b.depth then return a.depth < b.depth end
            if a.level ~= b.level then return a.level < b.level end
            return a.id < b.id
        end)
        return ranks
    end

    local lines, seen = { "KE.CC_TRACKER_SEEDS = {" }, {}
    for _, entry in ipairs(cfg.entries) do
        local ids, mine = {}, {}
        -- Rule 5: once per entry, never in two entries.
        local function add(id)
            if mine[id] then return end
            if seen[id] then fail(("%d is produced by two entries"):format(id)) end
            seen[id], mine[id] = true, true
            ids[#ids + 1] = id
        end

        local ranks = ranksOf(entry)
        if entry.debuffs then
            -- Rule 4.
            for _, id in ipairs(entry.debuffs) do
                if nameOf[id] ~= entry.names[1] then fail(("%d is not %s"):format(id, entry.names[1])) end
                if not appliesAura(id) then fail(("%d %s applies no aura"):format(id, entry.names[1])) end
                checkMechanic(id, entry.mechanic)
                add(id)
            end
        else
            for _, rank in ipairs(ranks) do
                local id = debuffOf(rank.id)
                checkMechanic(id, entry.mechanic)
                add(id)
            end
        end

        -- Rule 6.
        lines[#lines + 1] = ('    { key = "%s", label = "%s", group = "%s", default = %s, ids = {'):format(
            entry.key, entry.label, entry.group, tostring(entry.default))
        for i = 1, #ids, IDS_PER_LINE do
            local chunk = {}
            for j = i, math.min(i + IDS_PER_LINE - 1, #ids) do chunk[#chunk + 1] = tostring(ids[j]) end
            lines[#lines + 1] = "        " .. table.concat(chunk, ", ") .. ","
        end
        lines[#lines + 1] = "    } },"
    end
    lines[#lines + 1] = "}"
    return lines
end

return M
