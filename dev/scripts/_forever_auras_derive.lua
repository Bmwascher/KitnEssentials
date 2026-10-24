-- _forever_auras_derive.lua: the rules of derive-forever-auras.lua, apart
-- from file reading, so dev/spec/forever_auras_derive_spec.lua can run them
-- on rows it builds. Loaded by dofile:
--
--   local Derive = dofile(_dir .. "_forever_auras_derive.lua")
--   local lines = Derive.Run(tables, { entries = ENTRIES, lists = LISTS,
--       classless = CLASSLESS_SKILL_LINES, num = CSV.num })
--
-- `tables` maps SpellName, SkillLineAbility, SpellEffect, SpellLevels,
-- ItemEffect and ItemXItemEffect to rows keyed by column name, as
-- _db2_csv.lua reads them. Run returns the output lines; every refusal
-- raises error(msg, 0).
--
-- Rules:
--   1. The ranks of a class spell are the SkillLineAbility rows whose Spell
--      has the entry's SpellName and no race mask, and whose ClassMask has the
--      class bit (class id n is bit n-1) or is 0 in a skill line that
--      `classless` gives the class, and whose AcquireMethod is not 3 (no
--      trainer).
--   2. Every id applies an aura: a DifficultyID 0 SpellEffect row with Effect
--      6 (apply aura) or 35 (party area aura). A rank with neither, one of
--      whose effects triggers a spell that has one, is replaced by that
--      spell. Any other rank fails.
--   3. An item entry resolves through ItemXItemEffect to ItemEffect SpellID;
--      exactly one aura-applying spell must result, or the run fails.
--   4. Entries print in `entries` order, ranks by the SupercedesSpell chain,
--      then SpellLevels BaseLevel, then id.
--   5. A name with no rank fails, so an entry whose spell only a talent
--      grants fails until a talent lookup is added for it. An id two entries
--      produce fails. (A missing table or column is the script's refusal.)
-- Rule 6, the output, is the script's.

local M = {}

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
            effects[#effects + 1] = { effect = num(r.Effect), trigger = num(r.EffectTriggerSpell) }
        end
    end

    local function appliesAura(id)
        for _, e in ipairs(effectsOf[id] or {}) do
            if e.effect == 6 or e.effect == 35 then return true end
        end
        return false
    end

    -- Rule 2.
    local function auraIdOf(id)
        if appliesAura(id) then return id end
        for _, e in ipairs(effectsOf[id] or {}) do
            if e.trigger > 0 and appliesAura(e.trigger) then return e.trigger end
        end
        fail(("%d %s applies no aura and triggers none"):format(id, nameOf[id] or "?"))
    end

    local levelOf = {}
    for _, r in ipairs(tables.SpellLevels) do
        if num(r.DifficultyID) == 0 then levelOf[num(r.SpellID)] = num(r.BaseLevel) end
    end

    -- Rules 1, 4 and 5: the entry's ranks, lowest first.
    local function ranksOf(entry)
        local byId, ranks = {}, {}
        for _, r in ipairs(tables.SkillLineAbility) do
            local id, mask = num(r.Spell), num(r.ClassMask)
            local classOk
            if mask == 0 then
                classOk = classless[num(r.SkillLine)] == entry.class
            else
                classOk = hasBit(mask, entry.class - 1)
            end
            if classOk and nameOf[id] == entry.name and num(r.RaceMasks_0) == 0
                and num(r.AcquireMethod) ~= 3 and not byId[id] then
                byId[id] = { id = id, supersedes = num(r.SupercedesSpell), level = levelOf[id] or 0 }
                ranks[#ranks + 1] = byId[id]
            end
        end
        if #ranks == 0 then fail(("no rank of %s for class %d"):format(entry.name, entry.class)) end
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

    local effectSpell = {}
    for _, r in ipairs(tables.ItemEffect) do
        effectSpell[num(r.ID)] = num(r.SpellID)
    end
    local itemSpells = {}
    for _, r in ipairs(tables.ItemXItemEffect) do
        local item, spell = num(r.ItemID), effectSpell[num(r.ItemEffectID)]
        if spell and spell > 0 then
            local spells = itemSpells[item] or {}
            itemSpells[item] = spells
            spells[#spells + 1] = spell
        end
    end

    -- Rule 3.
    local function itemSpellOf(entry)
        local found
        for _, spell in ipairs(itemSpells[entry.item] or {}) do
            if appliesAura(spell) then
                if found then fail(("item %d %s gives more than one aura"):format(entry.item, entry.itemName)) end
                found = spell
            end
        end
        if not found then fail(("item %d %s gives no aura"):format(entry.item, entry.itemName)) end
        return found
    end

    local lines, seen = {}, {}
    local function add(text) lines[#lines + 1] = text end
    -- Rule 5: an id two entries produce.
    local function addRow(id, enabled, comment)
        if seen[id] then fail(("%d is produced by two entries"):format(id)) end
        seen[id] = true
        add(("    [%d] = { enabled = %s, default = true },  -- %s"):format(id, tostring(enabled), comment))
    end

    for _, list in ipairs(cfg.lists) do
        add("local " .. list.name .. " = {")
        for _, entry in ipairs(cfg.entries) do
            if entry.list == list.key then
                if entry.item then
                    local spell = itemSpellOf(entry)
                    addRow(spell, entry.enabled, ("%s (%s)"):format(nameOf[spell] or "?", entry.itemName))
                else
                    for _, rank in ipairs(ranksOf(entry)) do
                        local id = auraIdOf(rank.id)
                        addRow(id, entry.enabled, nameOf[id] or "?")
                    end
                end
            end
        end
        add("}")
    end
    return lines
end

return M
