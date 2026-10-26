-- derive-forever-kicks.lua: print the Forever kick rows of Core/Interrupts.lua
-- from game-data (DB2) tables saved by fetch-db2.ps1.
--
-- Run from the repo root with the local Lua 5.1 interpreter:
--   lua dev/scripts/derive-forever-kicks.lua <dir>
--   lua dev/scripts/derive-forever-kicks.lua <dir> --check Core/Interrupts.lua
--
-- <dir> holds ChrSpecialization, SkillLineAbility, SpellName, SpellEffect,
-- SpellCooldowns, SpellShapeshift, SpellMisc, SpellLevels and
-- SpellEquippedItems as <Table>.csv.
-- The first form prints FOREVER_INTERRUPTS and FOREVER_KICK_ALIASES, to be
-- pasted into Core/Interrupts.lua as printed. --check exits 0 when the file
-- holds that text exactly; otherwise it prints the text and exits 1. A
-- missing table or column, a kick with no cooldown row, or a kick whose form
-- or item data the castbar selector cannot express, exits 1 naming it.
--
-- Rules:
--   1. A class's spells are the SkillLineAbility rows whose ClassMask has the
--      class bit (class id n is bit n-1), plus the rows of the skill lines in
--      CLASSLESS_SKILL_LINES, which carry no class bit. A row with a race
--      mask is a racial and is left out.
--   2. A class spell is a kick when a SpellEffect row of it has Effect 68
--      (interrupt) or EffectAura 27 (silence), or triggers a spell that has
--      an Effect 68 row; that triggered spell is an announce extra.
--   3. Kicks of one class with one skill line and name are one kick in ranks,
--      ordered by the SupercedesSpell chain, then SpellLevels BaseLevel, then
--      id. Rank 1 is the canonical id, and every higher rank is aliased to it.
--   4. Cooldown: the larger of RecoveryTime and CategoryRecoveryTime of the
--      DifficultyID 0 SpellCooldowns row, in seconds.
--   5. Forms: SpellShapeshift ShapeshiftMask_0 bit n is form n+1, and the
--      kick needs one of those forms. A spell whose SpellMisc Attributes_2
--      has bit 0x80000 can also be cast with no form, so its mask lists forms
--      it may be cast in and it gets no form condition. A kick with a
--      ShapeshiftExclude or ShapeshiftMask_1 bit fails the run: the
--      selector models neither.
--   6. Within a spec, kicks by shorter cooldown, then canonical id, ranks
--      highest first. Talent and rune spells stay in: the game's known check
--      skips a spell the player has not learned. When the first kick has
--      ranks, its rank 1 is the row's `tracked` id, so a cooldown tracker
--      gets the canonical id the cooldown tables are keyed on.
--   7. Items: a kick with a SpellEquippedItems row needs that item. Item
--      class 4 with subclass mask exactly 64 (a shield) and no inventory
--      types prints `shield = true`; any other row fails the run, because
--      the selector models only the shield.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local CSV = dofile(_dir .. "_db2_csv.lua")

local dir, checkPath = arg[1], nil
if arg[2] == "--check" then checkPath = arg[3] end
if not dir or (arg[2] and not checkPath) then
    io.stderr:write("usage: lua dev/scripts/derive-forever-kicks.lua <dir> [--check <file>]\n")
    os.exit(2)
end

local function fail(msg)
    io.stderr:write("FAIL " .. msg .. "\n")
    os.exit(1)
end

-- The nine Forever specs, one per class.
local FOREVER_SPECS = { 1482, 1484, 1485, 1486, 1487, 1488, 1489, 1490, 1491 }

-- Skill lines whose rows carry ClassMask 0, by the class they belong to.
local CLASSLESS_SKILL_LINES = {
    [134] = 11,  -- Feral Combat (Druid): Feral Charge (Bear)
    [189] = 9,   -- Felhunter (Warlock pet)
}

local CLASS_NAMES = {
    [1] = "Warrior", [2] = "Paladin", [3] = "Hunter", [4] = "Rogue", [5] = "Priest",
    [7] = "Shaman", [8] = "Mage", [9] = "Warlock", [11] = "Druid",
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

local classOfSpec = {}
for _, r in ipairs(loadTable("ChrSpecialization", { "ID", "ClassID" })) do
    classOfSpec[num(r.ID)] = num(r.ClassID)
end
local wantedClass = {}
for _, specID in ipairs(FOREVER_SPECS) do
    local classID = classOfSpec[specID]
    if not classID or not CLASS_NAMES[classID] then
        fail(("ChrSpecialization row %d has no Forever class"):format(specID))
    end
    wantedClass[classID] = true
end

local nameOf = {}
for _, r in ipairs(loadTable("SpellName", { "ID", "Name_lang" })) do
    nameOf[num(r.ID)] = r.Name_lang
end

local effectsOf = {}
for _, r in ipairs(loadTable("SpellEffect", { "SpellID", "DifficultyID", "Effect", "EffectAura", "EffectTriggerSpell" })) do
    if num(r.DifficultyID) == 0 then
        local id = num(r.SpellID)
        local list = effectsOf[id] or {}
        effectsOf[id] = list
        list[#list + 1] = { effect = num(r.Effect), aura = num(r.EffectAura), trigger = num(r.EffectTriggerSpell) }
    end
end

local function hasInterruptEffect(id)
    for _, e in ipairs(effectsOf[id] or {}) do
        if e.effect == 68 then return true end
    end
    return false
end

local cooldownOf = {}
for _, r in ipairs(loadTable("SpellCooldowns", { "SpellID", "DifficultyID", "RecoveryTime", "CategoryRecoveryTime" })) do
    if num(r.DifficultyID) == 0 then
        cooldownOf[num(r.SpellID)] = math.max(num(r.RecoveryTime), num(r.CategoryRecoveryTime)) / 1000
    end
end

-- SpellMisc Attributes_2 bit 19 (0x80000): castable with no shapeshift form.
local formOptional = {}
for _, r in ipairs(loadTable("SpellMisc", { "SpellID", "DifficultyID", "Attributes_2" })) do
    if num(r.DifficultyID) == 0 and hasBit(num(r.Attributes_2), 19) then
        formOptional[num(r.SpellID)] = true
    end
end

local formsOf, unmodeledForms = {}, {}
for _, r in ipairs(loadTable("SpellShapeshift", { "SpellID", "ShapeshiftMask_0", "ShapeshiftMask_1", "ShapeshiftExclude_0", "ShapeshiftExclude_1" })) do
    local id = num(r.SpellID)
    local mask, forms = num(r.ShapeshiftMask_0), {}
    for bit = 0, 31 do
        if hasBit(mask, bit) then forms[#forms + 1] = bit + 1 end
    end
    if #forms > 0 and not formOptional[id] then formsOf[id] = forms end
    if num(r.ShapeshiftMask_1) ~= 0 or num(r.ShapeshiftExclude_0) ~= 0 or num(r.ShapeshiftExclude_1) ~= 0 then
        unmodeledForms[id] = true
    end
end

local levelOf = {}
for _, r in ipairs(loadTable("SpellLevels", { "SpellID", "DifficultyID", "BaseLevel" })) do
    if num(r.DifficultyID) == 0 then levelOf[num(r.SpellID)] = num(r.BaseLevel) end
end

-- Rule 7.
local shieldKick, unmodeledItems = {}, {}
for _, r in ipairs(loadTable("SpellEquippedItems", { "SpellID", "EquippedItemClass", "EquippedItemInvTypes", "EquippedItemSubclass" })) do
    local id = num(r.SpellID)
    if num(r.EquippedItemClass) == 4 and num(r.EquippedItemSubclass) == 64 and num(r.EquippedItemInvTypes) == 0 then
        shieldKick[id] = true
    else
        unmodeledItems[id] = true
    end
end

-- Rules 1 and 2.
local kicksOfClass = {}
for _, r in ipairs(loadTable("SkillLineAbility", { "SkillLine", "Spell", "ClassMask", "SupercedesSpell", "RaceMasks_0" })) do
    local skill, id, mask = num(r.SkillLine), num(r.Spell), num(r.ClassMask)
    local classes = {}
    if num(r.RaceMasks_0) == 0 then
        if mask == 0 then
            classes[1] = CLASSLESS_SKILL_LINES[skill]
        else
            for classID in pairs(wantedClass) do
                if hasBit(mask, classID - 1) then classes[#classes + 1] = classID end
            end
        end
    end
    local isKick, extra = false, nil
    for _, e in ipairs(effectsOf[id] or {}) do
        if e.effect == 68 or e.aura == 27 then isKick = true end
        if e.trigger > 0 and hasInterruptEffect(e.trigger) then isKick, extra = true, e.trigger end
    end
    if isKick then
        for _, classID in ipairs(classes) do
            if wantedClass[classID] then
                local kicks = kicksOfClass[classID] or {}
                kicksOfClass[classID] = kicks
                kicks[id] = kicks[id] or { id = id, skill = skill, supersedes = num(r.SupercedesSpell), extra = extra }
            end
        end
    end
end

-- Rule 3.
local function familyKey(kick)
    return kick.skill .. "|" .. (nameOf[kick.id] or "")
end

local function chainDepth(kick, kicks, key)
    local depth, cur = 0, kick
    while cur.supersedes > 0 and depth < 50 do
        local prev = kicks[cur.supersedes]
        if not prev or familyKey(prev) ~= key then break end
        depth, cur = depth + 1, prev
    end
    return depth
end

-- Rules 3, 4 and 6: the class's kicks, each with its ranks lowest first.
local function familiesOf(classID)
    local kicks = kicksOfClass[classID]
    if not kicks then return {} end
    local byKey, families = {}, {}
    for _, kick in pairs(kicks) do
        local key = familyKey(kick)
        local family = byKey[key]
        if not family then
            family = { key = key, ranks = {} }
            byKey[key] = family
            families[#families + 1] = family
        end
        family.ranks[#family.ranks + 1] = kick
    end
    for _, family in ipairs(families) do
        for _, kick in ipairs(family.ranks) do
            kick.depth = chainDepth(kick, kicks, family.key)
            kick.level = levelOf[kick.id] or 0
            kick.cd = cooldownOf[kick.id]
            if not kick.cd then
                fail(("SpellCooldowns has no row for %d %s"):format(kick.id, nameOf[kick.id] or "?"))
            end
            if unmodeledForms[kick.id] then
                fail(("SpellShapeshift row of %d %s has an exclude or high mask"):format(kick.id, nameOf[kick.id] or "?"))
            end
            if unmodeledItems[kick.id] then
                fail(("SpellEquippedItems row of %d %s needs an item other than a shield"):format(kick.id, nameOf[kick.id] or "?"))
            end
        end
        table.sort(family.ranks, function(a, b)
            if a.depth ~= b.depth then return a.depth < b.depth end
            if a.level ~= b.level then return a.level < b.level end
            return a.id < b.id
        end)
        family.canon = family.ranks[1].id
        family.cd = family.ranks[1].cd
    end
    table.sort(families, function(a, b)
        if a.cd ~= b.cd then return a.cd < b.cd end
        return a.canon < b.canon
    end)
    return families
end

local function formsText(forms)
    if not forms then return "" end
    local parts = {}
    for i, form in ipairs(forms) do parts[i] = tostring(form) end
    return ", forms = { " .. table.concat(parts, ", ") .. " }"
end

local lines, aliases = {}, {}
local function add(text) lines[#lines + 1] = text end

add("local FOREVER_INTERRUPTS = {")
for _, specID in ipairs(FOREVER_SPECS) do
    local classID = classOfSpec[specID]
    local families = familiesOf(classID)
    if #families > 0 then
        add(("    [%d] = {  -- %s"):format(specID, CLASS_NAMES[classID]))
        add("        candidates = {")
        local extras, seen = {}, {}
        for _, family in ipairs(families) do
            for i = #family.ranks, 1, -1 do
                local kick = family.ranks[i]
                add(("            { id = %d, cd = %s%s%s },  -- %s"):format(
                    kick.id, ("%g"):format(kick.cd), formsText(formsOf[kick.id]),
                    shieldKick[kick.id] and ", shield = true" or "", nameOf[kick.id] or "?"))
                if kick.id ~= family.canon then
                    aliases[#aliases + 1] = { id = kick.id, canon = family.canon }
                end
                if kick.extra and not seen[kick.extra] then
                    seen[kick.extra] = true
                    extras[#extras + 1] = kick.extra
                end
            end
        end
        add("        },")
        if #families[1].ranks > 1 then
            add(("        tracked = %d,"):format(families[1].canon))
        end
        if #extras > 0 then
            table.sort(extras)
            local parts = {}
            for i, id in ipairs(extras) do parts[i] = tostring(id) end
            add("        announceExtras = { " .. table.concat(parts, ", ") .. " },")
        end
        add("    },")
    end
end
add("}")
add("local FOREVER_KICK_ALIASES = {")
table.sort(aliases, function(a, b) return a.id < b.id end)
for _, alias in ipairs(aliases) do
    add(("    [%d] = %d,  -- %s"):format(alias.id, alias.canon, nameOf[alias.id] or "?"))
end
add("}")

local out = table.concat(lines, "\n") .. "\n"
if checkPath then
    local f = io.open(checkPath, "rb")
    if not f then fail("cannot read " .. checkPath) end
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    if text:find(out, 1, true) then
        print("OK " .. checkPath .. " holds the derived rows")
        os.exit(0)
    end
    io.write(out)
    fail(checkPath .. " does not hold the rows above exactly")
end
io.write(out)
