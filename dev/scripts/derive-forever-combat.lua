-- derive-forever-combat.lua: print the spell rank families and the combat
-- potion list of Modules/Combat/CombatDataForever.lua from game-data (DB2)
-- tables saved by fetch-db2.ps1.
--
-- Run from the repo root with the local Lua 5.1 interpreter:
--   lua dev/scripts/derive-forever-combat.lua <dir>
--   lua dev/scripts/derive-forever-combat.lua <dir> --check Modules/Combat/CombatDataForever.lua
--
-- <dir> holds SkillLineAbility, SpellName, SpellLevels, ItemEffect and
-- ItemXItemEffect as <Table>.csv. The first form prints RANK_FAMILIES and
-- POTION_IDS, to be pasted into Modules/Combat/CombatDataForever.lua as
-- printed; both forms write the count of families, the largest family and
-- the count of potion candidates to stderr. --check exits 0 when the file holds the printed text exactly;
-- otherwise it prints the text and exits 1. A missing table or column, or
-- any refusal below, exits 1 naming its cause.
--
-- Rules:
--   1. A class spell is a SkillLineAbility row whose ClassMask has a Forever
--      class bit (class id n is bit n-1), or a row with ClassMask 0 on a
--      skill line that has such a row: the data lists some ranks with no
--      mask (Bane of Agony rank 2). Rows whose spell has no SpellName row
--      are left out; a race mask does not exclude a row.
--   2. A family is the class spells of one skill line and one name, joined
--      with any row whose SupercedesSpell names a row of the same skill
--      line, and with the group of another skill line that lists the same
--      id. The run fails, naming the id, when that id joins two groups of
--      two or more ids that do not hold the same ids.
--   3. Ranks are ordered by SupercedesSpell chain depth, then SpellLevels
--      BaseLevel, then id; the first is the family's key. A level-0 id can
--      sort before the trained rank 1, so readers find a family by any of
--      its ids, never by key.
--   4. Only families of two or more ranks are printed, by key.
--   5. A potion candidate is an item (ItemXItemEffect) with an ItemEffect
--      row of SpellCategoryID 4 and CategoryCoolDownMSec above 0. Every
--      candidate is listed once, in POTIONS or in NOT_POTIONS with its
--      reason. The run fails on a candidate in neither list, a listed item
--      that is not a candidate, an item in both, or a POTIONS item whose
--      category-4 effect has a CoolDownMSec of its own above 0.
--   6. POTIONS is printed by item id.
--
-- ItemSparse is not read: its multi-line fields defeat the CSV reader, so
-- the item names below are copied from it by hand.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local CSV = dofile(_dir .. "_db2_csv.lua")

local dir, checkPath = arg[1], nil
if arg[2] == "--check" then checkPath = arg[3] end
if not dir or (arg[2] and not checkPath) then
    io.stderr:write("usage: lua dev/scripts/derive-forever-combat.lua <dir> [--check <file>]\n")
    os.exit(2)
end

local function fail(msg)
    io.stderr:write("FAIL " .. msg .. "\n")
    os.exit(1)
end

-- The nine Forever classes, by class id.
local FOREVER_CLASSES = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }

-- Combat potions on the shared potion cooldown.
local POTIONS = {
    [118] = "Minor Healing Potion",
    [858] = "Lesser Healing Potion",
    [929] = "Healing Potion",
    [1450] = "Potion of Fervor",
    [1710] = "Greater Healing Potion",
    [2455] = "Minor Mana Potion",
    [2456] = "Minor Rejuvenation Potion",
    [2459] = "Swiftness Potion",
    [3384] = "Minor Magic Resistance Potion",
    [3385] = "Lesser Mana Potion",
    [3387] = "Limited Invulnerability Potion",
    [3827] = "Mana Potion",
    [3928] = "Superior Healing Potion",
    [4596] = "Minor Discolored Healing Potion",
    [4623] = "Lesser Stoneshield Potion",
    [5631] = "Rage Potion",
    [5633] = "Great Rage Potion",
    [5634] = "Free Action Potion",
    [6048] = "Shadow Protection Potion",
    [6049] = "Fire Protection Potion",
    [6050] = "Frost Protection Potion",
    [6051] = "Holy Protection Potion",
    [6052] = "Nature Protection Potion",
    [6149] = "Greater Mana Potion",
    [9030] = "Restorative Potion",
    [9036] = "Magic Resistance Potion",
    [9144] = "Wildvine Potion",
    [13442] = "Mighty Rage Potion",
    [13443] = "Superior Mana Potion",
    [13444] = "Major Mana Potion",
    [13446] = "Major Healing Potion",
    [13455] = "Greater Stoneshield Potion",
    [13456] = "Greater Frost Protection Potion",
    [13457] = "Greater Fire Protection Potion",
    [13458] = "Greater Nature Protection Potion",
    [13459] = "Greater Shadow Protection Potion",
    [13460] = "Greater Holy Protection Potion",
    [13461] = "Greater Arcane Protection Potion",
    [13462] = "Purification Potion",
    [17348] = "Major Healing Draught",
    [17349] = "Superior Healing Draught",
    [17351] = "Major Mana Draught",
    [17352] = "Superior Mana Draught",
    [18253] = "Major Rejuvenation Potion",
    [18839] = "Combat Healing Potion",
    [18841] = "Combat Mana Potion",
    [20008] = "Living Action Potion",
    [223912] = "Purification Potion",
    [223913] = "Major Healing Potion",
    [223914] = "Greater Healing Potion",
    [241650] = "Major Discolored Healing Potion",
    [247239] = "Lesser Discolored Healing Potion",
    [247240] = "Discolored Healing Potion",
    [247241] = "Greater Discolored Healing Potion",
    [247242] = "Superior Discolored Healing Potion",
    [250327] = "Potion of Predatory Senses",
    [268881] = "Perishable Minor Healing Potion",
    [268882] = "Perishable Lesser Healing Potion",
    [268883] = "Perishable Healing Potion",
    [282011] = "Restored Healing Potion",
    [282013] = "Restored Mana Potion",
    [287966] = "Minor Healing Potion",
    [287967] = "Lesser Healing Potion",
    [287968] = "Minor Mana Potion",
    [287969] = "Lesser Mana Potion",
    [287975] = "Swiftness Potion",
    [287976] = "Free Action Potion",
    [287977] = "Greater Healing Potion",
}

-- Candidates that are not combat potions, each with its reason.
local NOT_POTIONS = {
    [737] = "Holy Spring Water: drink",
    [1072] = "Full Moonshine: drink",
    [1401] = "Green Tea Leaf: herb",
    [2462] = "Deprecated Potion of Lesser Invulnerability (Fix): deprecated",
    [2633] = "Jungle Remedy: quest",
    [3087] = "Mug of Shimmer Stout: drink",
    [3768] = "Deprecated Anti-magic Potion: deprecated",
    [3823] = "Lesser Invisibility Potion: out of combat",
    [5632] = "no ItemSparse row: not in the item data",
    [5816] = "Light of Elune: quest",
    [6372] = "Swim Speed Potion: out of combat",
    [9172] = "Invisibility Potion: out of combat",
    [12190] = "Dreamless Sleep Potion: out of combat",
    [14894] = "Lily Root: herb",
    [17350] = "no ItemSparse row: not in the item data",
    [20002] = "Greater Dreamless Sleep Potion: out of combat",
    [23578] = "Diet McWeaksauce: drink",
    [23579] = "The McWeaksauce Classic: drink",
    [226856] = "Guided Buoyancy Accelerant: quest",
    [255663] = "Windstone: currency",
    [274918] = "Warding Candle: not a potion",
    [274935] = "Tessa's Tonic: quest",
}

local num = CSV.num

local function loadTable(name, columns)
    local ok, rows = pcall(CSV.read, dir .. "/" .. name .. ".csv", columns)
    if not ok then fail(tostring(rows)) end
    return rows
end

-- Lua 5.1 has no bit operators; bit is 0-based.
local function hasBit(mask, bit)
    return math.floor(mask / 2 ^ bit) % 2 == 1
end

local function isClassSpell(mask)
    if mask == 0 then return false end
    for _, classID in ipairs(FOREVER_CLASSES) do
        if hasBit(mask, classID - 1) then return true end
    end
    return false
end

local function sortedKeys(t)
    local keys = {}
    for key in pairs(t) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local nameOf = {}
for _, r in ipairs(loadTable("SpellName", { "ID", "Name_lang" })) do
    nameOf[num(r.ID)] = r.Name_lang
end

local levelOf = {}
for _, r in ipairs(loadTable("SpellLevels", { "SpellID", "DifficultyID", "BaseLevel" })) do
    if num(r.DifficultyID) == 0 then levelOf[num(r.SpellID)] = num(r.BaseLevel) end
end

-- Rule 1: the skill lines that carry a Forever class bit on some row.
local abilityRows = loadTable("SkillLineAbility", { "SkillLine", "Spell", "ClassMask", "SupercedesSpell" })
local classLine = {}
for _, r in ipairs(abilityRows) do
    if isClassSpell(num(r.ClassMask)) then classLine[num(r.SkillLine)] = true end
end

-- Rules 1 and 2: one group per skill line and name.
local groups, groupsOf, supersedesOf, links = {}, {}, {}, {}
for _, r in ipairs(abilityRows) do
    local skill, id, mask = num(r.SkillLine), num(r.Spell), num(r.ClassMask)
    if id > 0 and nameOf[id] and (isClassSpell(mask) or (mask == 0 and classLine[skill])) then
        local key = skill .. "|" .. nameOf[id]
        local group = groups[key]
        if not group then
            group = { skill = skill, ids = {}, member = {} }
            groups[key] = group
        end
        if not group.member[id] then
            group.member[id] = true
            group.ids[#group.ids + 1] = id
            local list = groupsOf[id] or {}
            groupsOf[id] = list
            list[#list + 1] = group
        end
        local supersedes = num(r.SupercedesSpell)
        if supersedes > 0 then
            supersedesOf[id] = supersedesOf[id] or supersedes
            links[#links + 1] = { id = id, supersedes = supersedes, skill = skill }
        end
    end
end

local parent = {}
local function rootOf(group)
    while parent[group] do group = parent[group] end
    return group
end
local function join(a, b)
    local ra, rb = rootOf(a), rootOf(b)
    if ra ~= rb then parent[ra] = rb end
end
local function sameIds(a, b)
    if #a.ids ~= #b.ids then return false end
    for _, id in ipairs(a.ids) do
        if not b.member[id] then return false end
    end
    return true
end

-- Rule 2: one id listed under several skill lines joins their groups, unless
-- two of them are different families of their own.
for _, id in ipairs(sortedKeys(groupsOf)) do
    local list = groupsOf[id]
    for i = 1, #list - 1 do
        for j = i + 1, #list do
            local a, b = list[i], list[j]
            if #a.ids >= 2 and #b.ids >= 2 and not sameIds(a, b) then
                fail(("%d %s is in two families: skill lines %d and %d"):format(id, nameOf[id], a.skill, b.skill))
            end
        end
        join(list[i], list[#list])
    end
end

-- Rule 2: groups joined by a SupercedesSpell row of the same skill line.
for _, link in ipairs(links) do
    local b
    for _, group in ipairs(groupsOf[link.supersedes] or {}) do
        if group.skill == link.skill then b = group end
    end
    if b then
        for _, group in ipairs(groupsOf[link.id]) do
            if group.skill == link.skill then join(group, b) end
        end
    end
end

-- A joined id is listed once.
local membersOf, listed = {}, {}
for _, group in pairs(groups) do
    local root = rootOf(group)
    local list = membersOf[root]
    if not list then
        list = {}
        membersOf[root] = list
        listed[root] = {}
    end
    for _, id in ipairs(group.ids) do
        if not listed[root][id] then
            listed[root][id] = true
            list[#list + 1] = id
        end
    end
end

-- Rules 3 and 4.
local printed = {}
for _, ranks in pairs(membersOf) do
    if #ranks >= 2 then
        local inFamily, depthOf = {}, {}
        for _, id in ipairs(ranks) do inFamily[id] = true end
        for _, id in ipairs(ranks) do
            local depth, cur = 0, id
            while supersedesOf[cur] and inFamily[supersedesOf[cur]] and depth < 50 do
                depth, cur = depth + 1, supersedesOf[cur]
            end
            depthOf[id] = depth
        end
        table.sort(ranks, function(a, b)
            if depthOf[a] ~= depthOf[b] then return depthOf[a] < depthOf[b] end
            local la, lb = levelOf[a] or 0, levelOf[b] or 0
            if la ~= lb then return la < lb end
            return a < b
        end)
        printed[#printed + 1] = ranks
    end
end
table.sort(printed, function(a, b) return a[1] < b[1] end)
if #printed == 0 then fail("no rank families") end
local largest = printed[1]
for _, ranks in ipairs(printed) do
    if #ranks > #largest then largest = ranks end
end

-- Rule 5.
local potionEffects = {}
for _, r in ipairs(loadTable("ItemEffect", { "ID", "CoolDownMSec", "CategoryCoolDownMSec", "SpellCategoryID" })) do
    if num(r.SpellCategoryID) == 4 and num(r.CategoryCoolDownMSec) > 0 then
        potionEffects[num(r.ID)] = num(r.CoolDownMSec)
    end
end
local candidates, candidateCount = {}, 0
for _, r in ipairs(loadTable("ItemXItemEffect", { "ItemEffectID", "ItemID" })) do
    local own = potionEffects[num(r.ItemEffectID)]
    if own then
        local item = num(r.ItemID)
        if candidates[item] == nil then
            candidateCount = candidateCount + 1
            candidates[item] = false
        end
        if own > 0 then candidates[item] = true end
    end
end
for _, item in ipairs(sortedKeys(candidates)) do
    if not POTIONS[item] and not NOT_POTIONS[item] then
        fail(("potion candidate %d is in neither POTIONS nor NOT_POTIONS"):format(item))
    end
end
for _, item in ipairs(sortedKeys(POTIONS)) do
    if NOT_POTIONS[item] then
        fail(("item %d %s is in both POTIONS and NOT_POTIONS"):format(item, POTIONS[item]))
    end
    if candidates[item] == nil then
        fail(("POTIONS item %d %s is not a potion candidate"):format(item, POTIONS[item]))
    end
    if candidates[item] then
        fail(("POTIONS item %d %s has a cooldown of its own"):format(item, POTIONS[item]))
    end
end
for _, item in ipairs(sortedKeys(NOT_POTIONS)) do
    if candidates[item] == nil then
        fail(("NOT_POTIONS item %d is not a potion candidate"):format(item))
    end
end

local lines = {}
local function add(text) lines[#lines + 1] = text end

add("local RANK_FAMILIES = {")
for _, ranks in ipairs(printed) do
    local parts = {}
    for i, id in ipairs(ranks) do parts[i] = tostring(id) end
    add(("    [%d] = { %s },  -- %s"):format(ranks[1], table.concat(parts, ", "), nameOf[ranks[1]]))
end
add("}")
-- Rule 6.
add("local POTION_IDS = {")
for _, item in ipairs(sortedKeys(POTIONS)) do
    add(("    %d,  -- %s"):format(item, POTIONS[item]))
end
add("}")
io.stderr:write(("%d rank families, largest %d ids (%s), %d potion candidates\n"):format(
    #printed, #largest, nameOf[largest[1]], candidateCount))

local out = table.concat(lines, "\n") .. "\n"
if checkPath then
    local f = io.open(checkPath, "rb")
    if not f then fail("cannot read " .. checkPath) end
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    if text:find(out, 1, true) then
        print("OK " .. checkPath .. " holds the derived blocks")
        os.exit(0)
    end
    io.write(out)
    fail(checkPath .. " does not hold the blocks above exactly")
end
io.write(out)
