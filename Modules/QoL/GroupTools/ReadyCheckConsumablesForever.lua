-- ╔══════════════════════════════════════════════════════════╗
-- ║  ReadyCheckConsumablesForever.lua                        ║
-- ║  Purpose: The Forever client's consumables for Ready     ║
-- ║           Check Consumables, as printed by the derive    ║
-- ║           script dev/scripts/derive-forever-consumables  ║
-- ║           (.lua --check). Only the Forever list loads it ║
-- ╚══════════════════════════════════════════════════════════╝

local FOOD = {
    [19705] = true,  -- Well Fed
    [19706] = true,  -- Well Fed
    [19708] = true,  -- Well Fed
    [19709] = true,  -- Well Fed
    [19710] = true,  -- Well Fed
    [19711] = true,  -- Well Fed
    [24799] = true,  -- Well Fed
    [24870] = true,  -- Well Fed
    [25661] = true,  -- Increased Stamina
    [25694] = true,  -- Well Fed
    [25941] = true,  -- Well Fed
    [1225778] = true,  -- Well Fed
    [1225779] = true,  -- Well Fed
    [1225780] = true,  -- Well Fed
    [1225782] = true,  -- Well Fed
    [1248406] = true,  -- Well Fed
    [1248420] = true,  -- Well Fed
    [1248421] = true,  -- Well Fed
    [1248422] = true,  -- Well Fed
    [1248688] = true,  -- Well Fed
    [1249519] = true,  -- Well Fed
    [1249520] = true,  -- Well Fed
    [1249521] = true,  -- Well Fed
    [1249523] = true,  -- Well Fed
    [1249907] = true,  -- Well Fed
    [1249926] = true,  -- Well Fed
    [1249927] = true,  -- Well Fed
    [1283082] = true,  -- Well Fed
    [1294007] = true,  -- Well Fed
    [1302064] = true,  -- Well Fed
    [1319310] = true,  -- Well Fed
}
local FLASKS = {
    { item = 13512, buff = 17628 },  -- Supreme Power
    { item = 13511, buff = 17627 },  -- Distilled Wisdom
    { item = 13510, buff = 17626 },  -- Flask of the Titans
    { item = 274273, buff = 1293740 },  -- Flask of Natural Accuracy
    { item = 274274, buff = 1293741 },  -- Flask of Natural Aggression
    { item = 274275, buff = 1293742 },  -- Flask of Natural Precision
    { item = 274276, buff = 1293743 },  -- Flask of Natural Accuracy
    { item = 13513, buff = 17629 },  -- Chromatic Resistance
}
local ELIXIRS = {
    { item = 2457, buff = 2374 },  -- Lesser Agility
    { item = 3390, buff = 3160 },  -- Agility
    { item = 8949, buff = 11328 },  -- Agility
    { item = 9187, buff = 11334 },  -- Greater Agility
    { item = 13452, buff = 17538 },  -- Elixir of the Mongoose
    { item = 250328, buff = 1250918 },  -- Elixir of Cunning
    { item = 2454, buff = 2367 },  -- Lesser Strength
    { item = 3391, buff = 3164 },  -- Strength
    { item = 250349, buff = 1250984 },  -- Elixir of Strength
    { item = 9206, buff = 11405 },  -- Greater Strength
    { item = 13453, buff = 17537 },  -- Elixir of Brute Force
    { item = 250350, buff = 1250985 },  -- Elixir of Ferocity
    { item = 250351, buff = 1250986 },  -- Elixir of the Grizzly
    { item = 12820, buff = 17038 },  -- Winterfall Firewater
    { item = 246948, buff = 17038 },  -- Winterfall Firewater
    { item = 6373, buff = 7844 },  -- Fire Power
    { item = 17708, buff = 21920 },  -- Frost Power
    { item = 9264, buff = 11474 },  -- Shadow Power
    { item = 21546, buff = 1310077 },  -- Greater Firepower
    { item = 250343, buff = 1250972 },  -- Elixir of Nature Power
    { item = 247754, buff = 1245244 },  -- Minor Arcane Elixir
    { item = 217398, buff = 439959 },  -- Lesser Arcane Elixir
    { item = 250342, buff = 1250971 },  -- Lesser Arcane Elixir
    { item = 9155, buff = 11390 },  -- Arcane Elixir
    { item = 13454, buff = 17539 },  -- Greater Arcane Elixir
    { item = 247755, buff = 1245249 },  -- Elixir of Minor Force
    { item = 250330, buff = 1250922 },  -- Minor Cleric's Elixir
    { item = 250331, buff = 1250924 },  -- Lesser Cleric's Elixir
    { item = 250332, buff = 1250925 },  -- Cleric's Elixir
    { item = 250333, buff = 1250926 },  -- Greater Cleric's Elixir
    { item = 3383, buff = 3166 },  -- Lesser Intellect
    { item = 250353, buff = 1250988 },  -- Elixir of Lesser Intellect
    { item = 250354, buff = 1250989 },  -- Elixir of Intellect
    { item = 9179, buff = 11396 },  -- Greater Intellect
    { item = 13447, buff = 17535 },  -- Elixir of the Sages
    { item = 250338, buff = 1250941 },  -- Elixir of Sages
    { item = 250337, buff = 1250940 },  -- Elixir of the Owl
    { item = 250344, buff = 1250974 },  -- Elixir of Minor Spirit
    { item = 250345, buff = 1250976 },  -- Elixir of Lesser Spirit
    { item = 250346, buff = 1250978 },  -- Elixir of Spirit
    { item = 250347, buff = 1250979 },  -- Elixir of Greater Spirit
    { item = 250348, buff = 1250981 },  -- Elixir of the Whale
    { item = 20007, buff = 24363 },  -- Mana Regeneration
    { item = 250339, buff = 1250942 },  -- Minor Mageblood Elixir
    { item = 250340, buff = 1250944 },  -- Lesser Mageblood Elixir
    { item = 250341, buff = 1250948 },  -- Greater Mageblood Elixir
    { item = 250336, buff = 1250932 },  -- Elixir of Wicked Regeneration
    { item = 3382, buff = 3219 },  -- Minor Troll's Blood Elixir
    { item = 3388, buff = 3222 },  -- Lesser Troll's Blood Elixir
    { item = 3826, buff = 3223 },  -- Troll's Blood Elixir
    { item = 20004, buff = 24361 },  -- Major Troll's Blood Elixir
    { item = 5997, buff = 673 },  -- Elixir of Minor Defense
    { item = 1177, buff = 673 },  -- Elixir of Minor Defense
    { item = 3389, buff = 3220 },  -- Armor
    { item = 8951, buff = 11349 },  -- Armor
    { item = 13445, buff = 11348 },  -- Greater Armor
    { item = 2458, buff = 2378 },  -- Health
    { item = 3825, buff = 3593 },  -- Health II
    { item = 250334, buff = 1250928 },  -- Elixir of Fortitude
    { item = 250335, buff = 1250931 },  -- Elixir of Greater Fortitude
    { item = 250329, buff = 1250920 },  -- Elixir of the Phalanx
}
local ENHANCEMENTS = {
    { item = 2862, enchant = 40, kind = "stone", family = "Sharpening Stone", rank = 1, applies = { 0, 1, 6, 7, 8, 15 } },  -- Sharpen Blade
    { item = 287978, enchant = 40, kind = "stone", family = "Sharpening Stone", rank = 1, applies = { 0, 1, 6, 7, 8, 15 } },  -- Sharpen Blade
    { item = 2863, enchant = 13, kind = "stone", family = "Sharpening Stone", rank = 2, applies = { 0, 1, 6, 7, 8, 15 } },  -- Sharpen Blade II
    { item = 2871, enchant = 14, kind = "stone", family = "Sharpening Stone", rank = 3, applies = { 0, 1, 6, 7, 8, 15 } },  -- Sharpen Blade III
    { item = 7964, enchant = 483, kind = "stone", family = "Sharpening Stone", rank = 4, applies = { 0, 1, 6, 7, 8, 15 } },  -- Sharpen Blade IV
    { item = 12404, enchant = 1643, kind = "stone", family = "Sharpening Stone", rank = 5, applies = { 0, 1, 6, 7, 8, 15 } },  -- Sharpen Blade V
    { item = 18262, enchant = 2506, kind = "stone", family = "Elemental Sharpening Stone", rank = 6, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15 } },  -- Sharpen Weapon - Critical
    { item = 287980, enchant = 2506, kind = "stone", family = "Elemental Sharpening Stone", rank = 6, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15 } },  -- Sharpen Weapon - Critical
    { item = 3239, enchant = 19, kind = "stone", family = "Weightstone", rank = 1, applies = { 4, 5, 10, 13 } },  -- Enhance Blunt Weapon
    { item = 3240, enchant = 20, kind = "stone", family = "Weightstone", rank = 2, applies = { 4, 5, 10, 13 } },  -- Enhance Blunt Weapon II
    { item = 3241, enchant = 21, kind = "stone", family = "Weightstone", rank = 3, applies = { 4, 5, 10, 13 } },  -- Enhance Blunt Weapon III
    { item = 7965, enchant = 484, kind = "stone", family = "Weightstone", rank = 4, applies = { 4, 5, 10, 13 } },  -- Enhance Blunt Weapon IV
    { item = 12643, enchant = 1703, kind = "stone", family = "Weightstone", rank = 5, applies = { 4, 5, 10, 13 } },  -- Enhance Blunt Weapon V
    { item = 23122, enchant = 2684, kind = "stone", family = "Consecrated Sharpening Stone", rank = 0, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 11, 12, 13, 15, 20 } },  -- Consecrated Weapon
    { item = 20744, enchant = 2623, kind = "wizard", family = "Wizard Oil", rank = 1 },  -- Minor Wizard Oil
    { item = 20750, enchant = 2627, kind = "wizard", family = "Wizard Oil", rank = 2 },  -- Wizard Oil
    { item = 20749, enchant = 2628, kind = "wizard", family = "Wizard Oil", rank = 3 },  -- Brilliant Wizard Oil
    { item = 23123, enchant = 2685, kind = "wizard", family = "Blessed Wizard Oil", rank = 0 },  -- Blessed Wizard Oil
    { item = 20745, enchant = 2624, kind = "mana", family = "Mana Oil", rank = 1 },  -- Minor Mana Oil
    { item = 20748, enchant = 2629, kind = "mana", family = "Mana Oil", rank = 2 },  -- Brilliant Mana Oil
    { item = 3824, enchant = 25, kind = "oil", family = "Shadow Oil", rank = 1, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Shadow Oil
    { item = 3829, enchant = 26, kind = "oil", family = "Frost Oil", rank = 1, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Frost Oil
    { item = 232611, enchant = 7644, kind = "oil", family = "Magnificent Trollshine", rank = 1 },  -- Magnificent Trollshine
    { item = 3775, enchant = 22, kind = "poison", family = "Crippling Poison", rank = 1, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Crippling Poison
    { item = 3776, enchant = 603, kind = "poison", family = "Crippling Poison", rank = 2, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Crippling Poison
    { item = 2892, enchant = 7, kind = "poison", family = "Deadly Poison", rank = 1, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Deadly Poison
    { item = 2893, enchant = 8, kind = "poison", family = "Deadly Poison", rank = 2, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Deadly Poison II
    { item = 8984, enchant = 626, kind = "poison", family = "Deadly Poison", rank = 3, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Deadly Poison III
    { item = 8985, enchant = 627, kind = "poison", family = "Deadly Poison", rank = 4, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Deadly Poison IV
    { item = 20844, enchant = 2630, kind = "poison", family = "Deadly Poison", rank = 5, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Deadly Poison V
    { item = 6947, enchant = 323, kind = "poison", family = "Instant Poison", rank = 1, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Instant Poison
    { item = 6949, enchant = 324, kind = "poison", family = "Instant Poison", rank = 2, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Instant Poison II
    { item = 6950, enchant = 325, kind = "poison", family = "Instant Poison", rank = 3, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Instant Poison III
    { item = 8926, enchant = 623, kind = "poison", family = "Instant Poison", rank = 4, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Instant Poison IV
    { item = 8927, enchant = 624, kind = "poison", family = "Instant Poison", rank = 5, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Instant Poison V
    { item = 8928, enchant = 625, kind = "poison", family = "Instant Poison", rank = 6, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Instant Poison VI
    { item = 5237, enchant = 35, kind = "poison", family = "Mind-numbing Poison", rank = 1, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Mind-numbing Poison
    { item = 6951, enchant = 23, kind = "poison", family = "Mind-numbing Poison", rank = 2, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Mind-numbing Poison II
    { item = 9186, enchant = 643, kind = "poison", family = "Mind-numbing Poison", rank = 3, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Mind-numbing Poison III
    { item = 10918, enchant = 703, kind = "poison", family = "Wound Poison", rank = 1, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Wound Poison
    { item = 10920, enchant = 704, kind = "poison", family = "Wound Poison", rank = 2, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Wound Poison
    { item = 10921, enchant = 705, kind = "poison", family = "Wound Poison", rank = 3, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Wound Poison
    { item = 10922, enchant = 706, kind = "poison", family = "Wound Poison", rank = 4, applies = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 } },  -- Wound Poison
}
local IMBUES = {
    { family = "Windfury Weapon", ranks = { 8232, 8235, 10486, 16362 }, enchants = { 283, 284, 525, 1669 } },
    { family = "Flametongue Weapon", ranks = { 8024, 8027, 8030, 16339, 16341, 16342 }, enchants = { 5, 4, 3, 523, 1665, 1666 } },
    { family = "Frostbrand Weapon", ranks = { 8033, 8038, 10456, 16355, 16356 }, enchants = { 2, 12, 524, 1667, 1668 } },
    { family = "Rockbiter Weapon", ranks = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 }, enchants = { 29, 6, 1, 503, 1663, 683, 1664 } },
}
local HEALTHSTONES = {
    { item = 5512 },
    { item = 5511 },
    { item = 5509 },
    { item = 5510 },
    { item = 9421 },
    { item = 19004 },
    { item = 19005 },
    { item = 19006 },
    { item = 19007 },
    { item = 19008 },
    { item = 19009 },
    { item = 19010 },
    { item = 19011 },
    { item = 19012 },
    { item = 19013 },
}
local CREATE_HEALTHSTONE = { 6201, 6202, 5699, 11729, 11730 }
local SOULSTONES = {
    { item = 16896, buff = 20765 },  -- Soulstone Resurrection
    { item = 16895, buff = 20764 },  -- Soulstone Resurrection
    { item = 16893, buff = 20763 },  -- Soulstone Resurrection
    { item = 16892, buff = 20762 },  -- Soulstone Resurrection
    { item = 5232, buff = 20707 },  -- Soulstone Resurrection
}
local CREATE_SOULSTONE = { 693, 20752, 20755, 20756, 20757 }
local ICONS = { food = 134021, flask = 134842, oil = 134727, oiloh = 135252, elixir = 134812, healthstone = 135230, class = 134336 }

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Each `applies` list becomes a set; byEnchant names the row, or the imbue
-- family, that an active enchant id belongs to.
local byEnchant = {}
for _, row in ipairs(ENHANCEMENTS) do
    if row.applies then
        local set = {}
        for _, subclass in ipairs(row.applies) do set[subclass] = true end
        row.applies = set
    end
    byEnchant[row.enchant] = byEnchant[row.enchant] or row
end
for _, family in ipairs(IMBUES) do
    for _, enchant in ipairs(family.enchants) do
        byEnchant[enchant] = byEnchant[enchant] or { kind = "imbue", family = family.ranks[1] }
    end
end

KE.ReadyCheckConsumablesForever = {
    food = FOOD,
    flasks = FLASKS,
    elixirs = ELIXIRS,
    enhancements = ENHANCEMENTS,
    imbues = IMBUES,
    healthstones = HEALTHSTONES,
    createHealthstone = CREATE_HEALTHSTONE,
    soulstones = SOULSTONES,
    createSoulstone = CREATE_SOULSTONE,
    icons = ICONS,
    byEnchant = byEnchant,
}
