-- ╔══════════════════════════════════════════════════════════╗
-- ║  ScoutRules.lua                                          ║
-- ║  Purpose: The pure rules behind Scout's tooltip lines.   ║
-- ║           No WoW API: secret checks and colors come in   ║
-- ║           as arguments.                                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local concat = table.concat
local floor = math.floor
local format = string.format
local ipairs = ipairs
local min = math.min
local tonumber = tonumber
local type = type

local Rules = {}
KE.ScoutRules = Rules

Rules.MAX_ABILITY_ROWS = 8

Rules.SHOW_IN = {
    { key = "ShowInWorld", label = "Open World", state = "world" },
    { key = "ShowInInstances", label = "Dungeons and Raids", state = "instance" },
    { key = "ShowInCombat", label = "In Combat", state = "combat" },
}

Rules.DETAILS_KEYS = {
    { key = "ctrl", text = "Ctrl" },
    { key = "alt", text = "Alt" },
    { key = "shift", text = "Shift" },
}

local DOT = " \194\183 "
local ICON_SIZE = 14
local MAX_LISTED_WORDS = 5
local PHYSICAL_SCHOOL_ID = 1
local DATA_TABLES = { "abilities", "stats", "tame", "armor", "words", "scopes" }

-- Table entries whose names mark them as script machinery, not something a mob does.
local SCRIPT_SPELLS = {
    [4063] = true,  -- Argus Shadow Mage Transform
    [6822] = true,  -- Corrupted Stamina Passive
    [7131] = true,  -- Illusion Passive
    [9032] = true,  -- Self Stun - 30 seconds
    [15750] = true, -- Rookery Whelp Spawn-in Spell
    [16078] = true, -- Emberseer Despawn
    [16619] = true, -- Quest - Temporal Parasite Death Summon
    [19515] = true, -- Enrage Trigger
    [21336] = true, -- Discordant Surge Visual
    [23159] = true, -- Summon Dreadsteed Spirit (DND)
    [23363] = true, -- Summon Drakonid Corpse Trigger
    [26683] = true, -- Get Gosssip, Test
    [28355] = true, -- Reaper of Souls DND
}

-- Index i is school id i + 1, and resist field i.
local SCHOOL_WORDS = { "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }

local MECHANIC_WORDS = {
    { id = 12, word = "Stun" }, { id = 5, word = "Fear" }, { id = 7, word = "Root" },
    { id = 11, word = "Slow" }, { id = 9, word = "Silence" }, { id = 10, word = "Sleep" },
    { id = 1, word = "Charm" }, { id = 17, word = "Polymorph" }, { id = 18, word = "Banish" },
    { id = 2, word = "Disorient" }, { id = 26, word = "Interrupt" }, { id = 15, word = "Bleed" },
    { id = 20, word = "Shackle" }, { id = 3, word = "Disarm" }, { id = 30, word = "Sap" },
    { id = 14, word = "Knockout" }, { id = 13, word = "Freeze" }, { id = 24, word = "Horror" },
    { id = 23, word = "Turn" },
}

-- School and mechanic words never collide, so one set serves both.
local CLASS_WORDS = {
    MAGE = { Polymorph = true, Root = true, Slow = true, Interrupt = true, Fire = true, Frost = true, Arcane = true },
    ROGUE = { Sap = true, Knockout = true, Stun = true, Disorient = true, Interrupt = true, Bleed = true },
    HUNTER = { Freeze = true, Disorient = true, Slow = true, Fear = true, Nature = true, Arcane = true },
    WARRIOR = { Stun = true, Fear = true, Slow = true, Interrupt = true, Bleed = true, Disarm = true },
    PRIEST = { Fear = true, Charm = true, Shackle = true, Silence = true, Holy = true, Shadow = true },
    WARLOCK = { Fear = true, Horror = true, Banish = true, Charm = true, Shadow = true, Fire = true },
    PALADIN = { Stun = true, Turn = true, Knockout = true, Holy = true },
    DRUID = { Root = true, Sleep = true, Stun = true, Bleed = true, Nature = true, Arcane = true },
    SHAMAN = { Interrupt = true, Slow = true, Nature = true, Fire = true, Frost = true },
}
local NO_WORDS = {}

-- Lua 5.1 has no bit operators, and this file runs with no bit library.
local function hasBit(mask, id)
    return floor(mask / 2 ^ (id - 1)) % 2 == 1
end

function Rules.NpcId(guid, isSecret)
    if isSecret(guid) then return nil end
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

function Rules.PlainTrue(value, isSecret)
    if isSecret(value) then return false end
    return value == true
end

-- The predicate comes first: a secret token errors on a truth test.
function Rules.PickUnit(token, isSecret, mouseoverExists)
    if not isSecret(token) and token then return token end
    if Rules.PlainTrue(mouseoverExists, isSecret) then return "mouseover" end
    return nil
end

function Rules.DataComplete(data)
    if type(data) ~= "table" then return false end
    for _, name in ipairs(DATA_TABLES) do
        if type(data[name]) ~= "table" then return false end
    end
    return true
end

local function boxOn(db, boxes, state)
    for _, box in ipairs(boxes) do
        if box.state == state then return db[box.key] == true end
    end
    return false
end

function Rules.ShownHere(db, inInstance, inCombat, boxes)
    if not boxOn(db, boxes, inInstance and "instance" or "world") then return false end
    return not inCombat or boxOn(db, boxes, "combat")
end

local resistScratch = { 0, 0, 0, 0, 0, 0 }

-- The resists table is reused: read it before the next call.
function Rules.UnpackStats(row)
    local isRow = type(row) == "table"
    for i = 1, #SCHOOL_WORDS do
        resistScratch[i] = isRow and row[i + 3] or 0
    end
    if isRow then return row[1] or 0, row[2] or 0, row[3] or 0, resistScratch end
    return type(row) == "number" and row or 0, 0, 0, resistScratch
end

function Rules.ArmorInput(row, mobLevel, classification, playerLevel, armorByLevel)
    local armor, schoolMask = Rules.UnpackStats(row)
    if hasBit(schoolMask, PHYSICAL_SCHOOL_ID) then return nil end
    if armor > 0 then return armor, false end
    if mobLevel == nil then return nil end
    local top = #armorByLevel
    local level
    if mobLevel > 0 then
        level = min(mobLevel, top)
    elseif classification == "worldboss" then
        level = top
    else
        level = min(playerLevel + 10, top)
    end
    return armorByLevel[level], true
end

function Rules.ArmorLine(armor, estimated, effectiveness, paint)
    local left = paint("accent", "Armor") .. " " .. paint("gold", (estimated and "~" or "") .. armor)
    if type(effectiveness) ~= "number" then return left, nil end
    return left, paint("muted", "Your physical") .. " " .. paint("gold", format("-%.1f%%", effectiveness * 100))
end

function Rules.ImmunityWords(schoolMask, mechanicMask)
    local schools, mechanics = {}, {}
    for i, word in ipairs(SCHOOL_WORDS) do
        if hasBit(schoolMask, i + 1) then schools[#schools + 1] = word end
    end
    for _, entry in ipairs(MECHANIC_WORDS) do
        if hasBit(mechanicMask, entry.id) then mechanics[#mechanics + 1] = entry.word end
    end
    return schools, mechanics
end

function Rules.ImmunityLine(words, class, paint)
    if #words == 0 then return nil, nil end
    local yours = CLASS_WORDS[class] or NO_WORDS
    local mine, others = {}, {}
    for _, word in ipairs(words) do
        if yours[word] then
            mine[#mine + 1] = paint("red", word)
        else
            others[#others + 1] = paint("muted", word)
        end
    end
    local head, comma = paint("muted", "Immune: "), paint("muted", ", ")
    if #words <= MAX_LISTED_WORDS then
        for _, word in ipairs(others) do mine[#mine + 1] = word end
        return head .. concat(mine, comma), nil
    end
    local full = paint("muted", "Immune: " .. concat(words, ", "))
    if #mine > 0 then
        return head .. concat(mine, comma) .. paint("muted", ", + " .. #others .. " more"), full
    end
    return paint("muted", "Immune: " .. #words .. " effects, none of yours"), full
end

function Rules.ResistsLine(resists, class, paint)
    local yours = CLASS_WORDS[class] or NO_WORDS
    local parts = {}
    for i, word in ipairs(SCHOOL_WORDS) do
        local points = resists[i]
        if points and points > 0 then
            parts[#parts + 1] = paint(yours[word] and "red" or "muted", word .. " " .. points)
        end
    end
    if #parts == 0 then return nil end
    return paint("muted", "Resists: ") .. concat(parts, paint("muted", ", "))
end

function Rules.RangeLabel(minRange, maxRange, scope)
    local maxYards = maxRange or 0
    if maxYards == 0 then return scope or "Self" end
    if maxYards <= 5 then return "Melee" end
    if maxYards >= 100 then return "Any range" end
    if minRange and minRange > 0 then return format("%d-%d yd", minRange, maxYards) end
    return format("%d yd", maxYards)
end

function Rules.AbilityMeta(view, showWord, paint)
    local text = Rules.RangeLabel(view.minRange, view.maxRange, view.scope)
    if view.castTime and view.castTime > 0 then
        text = text .. DOT .. format("%gs cast", view.castTime / 1000)
    end
    if showWord and view.word then
        return paint("muted", text .. DOT) .. paint("amber", view.word)
    end
    return paint("muted", text)
end

function Rules.AbilityTitle(icon, name, paint)
    local title = paint("white", name)
    if not icon then return title end
    return format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t ", icon, ICON_SIZE, ICON_SIZE) .. title
end

function Rules.IsScriptSpell(id)
    return SCRIPT_SPELLS[id] == true
end

-- Abilities alone cannot speak for a tame flag: every flag sits on a stats row.
function Rules.TameKnown(data, npcId)
    return data.tame[npcId] == true or data.stats[npcId] ~= nil
end

function Rules.FamilyLine(family, tameable, mobLevel, playerLevel)
    if mobLevel == nil then return nil end
    local state, color = "Tameable", "green"
    if not tameable then
        state, color = "Untameable", "red"
    elseif mobLevel <= 0 then
        state, color = "Untameable at your level", "red"
    elseif mobLevel > playerLevel then
        state, color = "Untameable until level " .. mobLevel, "red"
    end
    return family .. DOT .. state, color
end

local function addLine(lines, left, right, wrap)
    lines[#lines + 1] = { left = left, right = right, wrap = wrap }
end

local function addAbilities(lines, view, opts, paint)
    if #view.abilities == 0 then return end
    local hint = opts.keyHint and paint("muted", opts.keyName .. ": details") or nil
    addLine(lines, paint("accent", "Abilities"), hint)
    for i = 1, min(#view.abilities, Rules.MAX_ABILITY_ROWS) do
        local ability = view.abilities[i]
        addLine(lines, Rules.AbilityTitle(ability.icon, ability.name, paint),
            Rules.AbilityMeta(ability, opts.controlWords, paint))
    end
end

function Rules.BuildLines(view, opts, paint)
    local lines = {}
    local fullImmunity

    if opts.petFamily and opts.class == "HUNTER" and view.tameKnown and view.family then
        local text, color = Rules.FamilyLine(view.family, view.tameable, view.mobLevel, view.playerLevel)
        if text then addLine(lines, paint("muted", "Pet family"), paint(color, text)) end
    end

    if opts.abilities then addAbilities(lines, view, opts, paint) end

    if opts.armor and view.armor then
        addLine(lines, Rules.ArmorLine(view.armor, view.estimated, view.effectiveness, paint))
    end

    if opts.immunities then
        local words, mechanics = Rules.ImmunityWords(view.schoolMask, view.mechanicMask)
        for _, word in ipairs(mechanics) do words[#words + 1] = word end
        local line, full = Rules.ImmunityLine(words, opts.class, paint)
        if line then
            addLine(lines, line, nil, true)
            fullImmunity = full
        end
        local resists = Rules.ResistsLine(view.resists, opts.class, paint)
        if resists then addLine(lines, resists, nil, true) end
    end

    return lines, fullImmunity
end

function Rules.DetailsBelow(tooltipBottom, blockHeight, gap)
    if type(tooltipBottom) ~= "number" or type(blockHeight) ~= "number" or type(gap) ~= "number" then
        return false
    end
    return tooltipBottom - gap - blockHeight >= 0
end
