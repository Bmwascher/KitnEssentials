-- _forever_consumables_derive.lua: the rules of derive-forever-consumables.lua,
-- apart from file reading, so dev/spec/forever_consumables_derive_spec.lua can
-- run them on rows it builds. Loaded by dofile:
--
--   local Derive = dofile(_dir .. "_forever_consumables_derive.lua")
--   local lines = Derive.Run(tables, cfg)
--
-- `tables` maps Item, ItemEffect, ItemXItemEffect, SpellName, SpellEffect,
-- SpellMisc, SpellDuration, SpellItemEnchantment, SkillLineAbility,
-- SpellEquippedItems and SpellLevels to rows keyed by column name, as
-- _db2_csv.lua reads them. `cfg` holds the seed lists and `num`; a list left
-- out prints an empty table. Run returns the output lines; every refusal
-- raises error(msg, 0).
--
-- Rules:
--   1. An item's use spells are its ItemXItemEffect rows mapped through
--      ItemEffect SpellID. A seed resolves to exactly one use spell that
--      meets its rule, or the run fails naming the item.
--   2. Flask, elixir and Soulstone seeds: the use spell has a DifficultyID 0
--      SpellEffect row with Effect 6 (apply aura); the buff id is the use
--      spell id. A flask is Item ClassID 0, SubclassID 3; an elixir is
--      ClassID 0 with a SpellMisc DurationIndex of 20 minutes or more.
--   3. Stone and oil seeds: the use spell has an Effect 54 row whose
--      EffectMiscValue_0 is a SpellItemEnchantment ID, and a
--      SpellEquippedItems row with EquippedItemClass 2, whose
--      EquippedItemSubclass bits are the weapons it takes (0: any weapon).
--   4. Poisons are found, not seeded: every Item whose use spell has an
--      Effect 360 enchant, an EquippedItemClass 2 row and a family in
--      cfg.poisonFamilies (Effect 360 also marks Firestone and other weapon
--      imbues, which are not poisons). The family is the use spell's name
--      less a trailing " I" to " VI". Within a family the rank orders by
--      that numeral, then the use spell's SpellLevels BaseLevel (one name
--      can cover every rank), 1 lowest; equal pairs share a rank. A listed
--      family with no poison fails. They print after the seeds, by family,
--      rank, then item id.
--   5. Class ranks (imbues, Create Healthstone, Create Soulstone) are the
--      SkillLineAbility rows with the class bit (class id n is bit n-1), the
--      exact SpellName, no race mask and an AcquireMethod other than 3,
--      ordered by the SupercedesSpell chain, then SpellLevels BaseLevel,
--      then id. An imbue rank has an Effect 360 enchant; a Create Soulstone
--      rank has an Effect 24 row creating a seeded Soulstone. A name with no
--      rank fails.
--   6. Food: every SpellName row named exactly cfg.foodName, plus
--      cfg.foodExtra, each with an Effect 6 row.
--   7. Icons: the Item IconFileDataID of each cfg.icons item, never 0.
--      Healthstone seeds are Item rows with ClassID 0.
--   8. An item seeded twice fails; two items may share an enchant.
-- Rule 9, the output, is the script's: Run returns its lines.

local M = {}

local function fail(msg)
    error(msg, 0)
end

-- Lua 5.1 has no bit operators; bit is 0-based.
local function hasBit(mask, bit)
    return math.floor(mask / 2 ^ bit) % 2 == 1
end

local NUMERALS = { I = 1, II = 2, III = 3, IV = 4, V = 5, VI = 6 }

-- Rule 4: "Instant Poison III" is family "Instant Poison", numeral 3.
function M.PoisonFamily(name)
    local base, numeral = name:match("^(.-) ([IV]+)$")
    if base and NUMERALS[numeral] then return base, NUMERALS[numeral] end
    return name, 1
end

local function listText(parts)
    if #parts == 0 then return "{}" end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

function M.Run(tables, cfg)
    local num = cfg.num

    local nameOf = {}
    for _, r in ipairs(tables.SpellName) do
        nameOf[num(r.ID)] = r.Name_lang
    end
    local function nameText(id)
        return nameOf[id] or "?"
    end

    local itemOf = {}
    for _, r in ipairs(tables.Item) do
        itemOf[num(r.ID)] = { class = num(r.ClassID), subclass = num(r.SubclassID), icon = num(r.IconFileDataID) }
    end

    local effectsOf = {}
    for _, r in ipairs(tables.SpellEffect) do
        if num(r.DifficultyID) == 0 then
            local id = num(r.SpellID)
            local effects = effectsOf[id] or {}
            effectsOf[id] = effects
            effects[#effects + 1] = { effect = num(r.Effect), misc = num(r.EffectMiscValue_0), item = num(r.EffectItemType) }
        end
    end
    local function effectRow(id, effect)
        for _, e in ipairs(effectsOf[id] or {}) do
            if e.effect == effect then return e end
        end
        return nil
    end
    local function appliesAura(id)
        return effectRow(id, 6) ~= nil
    end

    local enchantExists = {}
    for _, r in ipairs(tables.SpellItemEnchantment) do
        enchantExists[num(r.ID)] = true
    end
    local function enchantOf(id, effect)
        local e = effectRow(id, effect)
        if e and enchantExists[e.misc] then return e.misc end
        return nil
    end

    local durationOf = {}
    for _, r in ipairs(tables.SpellDuration) do
        durationOf[num(r.ID)] = num(r.Duration)
    end
    local spellDuration = {}
    for _, r in ipairs(tables.SpellMisc) do
        if num(r.DifficultyID) == 0 then
            spellDuration[num(r.SpellID)] = durationOf[num(r.DurationIndex)] or 0
        end
    end

    local weaponMask = {}
    for _, r in ipairs(tables.SpellEquippedItems) do
        if num(r.EquippedItemClass) == 2 then
            weaponMask[num(r.SpellID)] = num(r.EquippedItemSubclass)
        end
    end

    local levelOf = {}
    for _, r in ipairs(tables.SpellLevels) do
        if num(r.DifficultyID) == 0 then levelOf[num(r.SpellID)] = num(r.BaseLevel) end
    end

    local effectSpell = {}
    for _, r in ipairs(tables.ItemEffect) do
        effectSpell[num(r.ID)] = num(r.SpellID)
    end
    local useSpells = {}
    for _, r in ipairs(tables.ItemXItemEffect) do
        local item, spell = num(r.ItemID), effectSpell[num(r.ItemEffectID)]
        if spell and spell > 0 then
            local spells = useSpells[item] or {}
            useSpells[item] = spells
            spells[#spells + 1] = spell
        end
    end

    -- Rule 1.
    local function useSpellOf(item, what, meets)
        local found
        for _, spell in ipairs(useSpells[item] or {}) do
            if meets(spell) then
                if found then fail(("item %d gives more than one %s"):format(item, what)) end
                found = spell
            end
        end
        if not found then fail(("item %d gives no %s"):format(item, what)) end
        return found
    end

    local function requireItem(item, class, subclass, what)
        local row = itemOf[item]
        if not row or row.class ~= class or (subclass and row.subclass ~= subclass) then
            fail(("item %d is not a %s"):format(item, what))
        end
    end

    -- Rule 8.
    local seeded = {}
    local function seed(item)
        if seeded[item] then fail(("item %d is seeded twice"):format(item)) end
        seeded[item] = true
    end

    -- Rule 5: the ranks of a class spell, lowest first.
    local function ranksOf(classID, name)
        local byId, ranks = {}, {}
        for _, r in ipairs(tables.SkillLineAbility) do
            local id, mask = num(r.Spell), num(r.ClassMask)
            if mask ~= 0 and hasBit(mask, classID - 1) and nameOf[id] == name
                and num(r.RaceMasks_0) == 0 and num(r.AcquireMethod) ~= 3 and not byId[id] then
                byId[id] = { id = id, supersedes = num(r.SupercedesSpell), level = levelOf[id] or 0 }
                ranks[#ranks + 1] = byId[id]
            end
        end
        if #ranks == 0 then fail(("no rank of %s for class %d"):format(name, classID)) end
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

    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end

    -- Rule 6.
    local food, foodSeen = {}, {}
    local function addFood(id)
        if not foodSeen[id] then
            foodSeen[id] = true
            food[#food + 1] = id
        end
    end
    if cfg.foodName then
        for _, r in ipairs(tables.SpellName) do
            if r.Name_lang == cfg.foodName then addFood(num(r.ID)) end
        end
    end
    for _, id in ipairs(cfg.foodExtra or {}) do
        addFood(id)
    end
    table.sort(food)
    add("local FOOD = {")
    for _, id in ipairs(food) do
        if not appliesAura(id) then fail(("%d %s applies no aura"):format(id, nameText(id))) end
        add(("    [%d] = true,  -- %s"):format(id, nameText(id)))
    end
    add("}")

    -- Rule 2.
    local function buffRows(name, items, check)
        add("local " .. name .. " = {")
        for _, item in ipairs(items or {}) do
            seed(item)
            local spell = useSpellOf(item, "aura", appliesAura)
            if check then check(item, spell) end
            add(("    { item = %d, buff = %d },  -- %s"):format(item, spell, nameText(spell)))
        end
        add("}")
    end
    buffRows("FLASKS", cfg.flasks, function(item)
        requireItem(item, 0, 3, "flask")
    end)
    buffRows("ELIXIRS", cfg.elixirs, function(item, spell)
        requireItem(item, 0, nil, "consumable")
        if (spellDuration[spell] or 0) < 1200000 then
            fail(("item %d lasts under 20 minutes"):format(item))
        end
    end)

    -- Rules 3 and 4.
    local function appliesText(spell, item)
        local mask = weaponMask[spell]
        if not mask then fail(("item %d has no weapon requirement"):format(item)) end
        if mask == 0 then return "" end
        local bits = {}
        for bit = 0, 31 do
            if hasBit(mask, bit) then bits[#bits + 1] = tostring(bit) end
        end
        return ", applies = " .. listText(bits)
    end
    local function enhancementRow(item, spell, enchant, kind, family, rank)
        add(('    { item = %d, enchant = %d, kind = "%s", family = "%s", rank = %d%s },  -- %s'):format(
            item, enchant, kind, family, rank, appliesText(spell, item), nameText(spell)))
    end
    local function givesStoneEnchant(id)
        return enchantOf(id, 54) ~= nil
    end

    add("local ENHANCEMENTS = {")
    for _, s in ipairs(cfg.enhancements or {}) do
        seed(s.item)
        local spell = useSpellOf(s.item, "enchant", givesStoneEnchant)
        enhancementRow(s.item, spell, enchantOf(spell, 54), s.kind, s.family, s.rank)
    end
    local isPoisonFamily, familyFound, poisons = {}, {}, {}
    for _, name in ipairs(cfg.poisonFamilies or {}) do
        isPoisonFamily[name] = true
    end
    for _, r in ipairs(tables.Item) do
        local item = num(r.ID)
        local found
        for _, spell in ipairs(useSpells[item] or {}) do
            local family, numeral = M.PoisonFamily(nameText(spell))
            if isPoisonFamily[family] and enchantOf(spell, 360) and weaponMask[spell] then
                if found then fail(("item %d gives more than one poison"):format(item)) end
                -- Levels stay under 1000, so numeral then level is one key.
                found = { item = item, spell = spell, family = family, key = numeral * 1000 + (levelOf[spell] or 0) }
            end
        end
        if found then
            familyFound[found.family] = true
            poisons[#poisons + 1] = found
        end
    end
    for _, name in ipairs(cfg.poisonFamilies or {}) do
        if not familyFound[name] then fail(("no poison of %s"):format(name)) end
    end
    table.sort(poisons, function(a, b)
        if a.family ~= b.family then return a.family < b.family end
        if a.key ~= b.key then return a.key < b.key end
        return a.item < b.item
    end)
    local lastFamily, lastKey, poisonRank
    for _, p in ipairs(poisons) do
        if p.family ~= lastFamily then
            lastFamily, lastKey, poisonRank = p.family, p.key, 1
        elseif p.key ~= lastKey then
            lastKey, poisonRank = p.key, poisonRank + 1
        end
        seed(p.item)
        enhancementRow(p.item, p.spell, enchantOf(p.spell, 360), "poison", p.family, poisonRank)
    end
    add("}")

    -- Rule 5: imbues.
    add("local IMBUES = {")
    for _, name in ipairs(cfg.imbueFamilies or {}) do
        local ranks, enchants = {}, {}
        for _, rank in ipairs(ranksOf(cfg.shamanClass, name)) do
            local enchant = enchantOf(rank.id, 360)
            if not enchant then fail(("%d %s has no enchant"):format(rank.id, name)) end
            ranks[#ranks + 1] = tostring(rank.id)
            enchants[#enchants + 1] = tostring(enchant)
        end
        add(('    { family = "%s", ranks = %s, enchants = %s },'):format(name, listText(ranks), listText(enchants)))
    end
    add("}")

    -- Rule 7: healthstones.
    add("local HEALTHSTONES = {")
    for _, item in ipairs(cfg.healthstones or {}) do
        seed(item)
        requireItem(item, 0, nil, "consumable")
        add(("    { item = %d },"):format(item))
    end
    add("}")

    local function rankIds(classID, name, check)
        local ids = {}
        if name then
            for _, rank in ipairs(ranksOf(classID, name)) do
                if check then check(rank.id) end
                ids[#ids + 1] = tostring(rank.id)
            end
        end
        return listText(ids)
    end
    add("local CREATE_HEALTHSTONE = " .. rankIds(cfg.warlockClass, cfg.createHealthstone))

    buffRows("SOULSTONES", cfg.soulstones)
    local isSoulstone = {}
    for _, item in ipairs(cfg.soulstones or {}) do
        isSoulstone[item] = true
    end
    add("local CREATE_SOULSTONE = " .. rankIds(cfg.warlockClass, cfg.createSoulstone, function(id)
        local e = effectRow(id, 24)
        if not (e and isSoulstone[e.item]) then
            fail(("%d %s creates no listed soulstone"):format(id, nameText(id)))
        end
    end))

    -- Rule 7: icons.
    local icons = {}
    for _, icon in ipairs(cfg.icons or {}) do
        local row = itemOf[icon.item]
        if not row or row.icon == 0 then fail(("icon item %d has no icon"):format(icon.item)) end
        icons[#icons + 1] = ("%s = %d"):format(icon.key, row.icon)
    end
    add("local ICONS = " .. listText(icons))
    return lines
end

return M
