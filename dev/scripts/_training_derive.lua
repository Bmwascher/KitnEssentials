-- _training_derive.lua: the rules of derive-training-data.lua, apart from file
-- reading, so dev/spec/training_derive_spec.lua can run them on rows it builds.
--
--   Client(tables, num)    the client tables as lookups
--   ClassRows(id, inputs, client, lists)    one class's merged rows, sorted, the
--       count of level rows left out, and the sorted untrainable ids removed
--   Races(client, spellId, classId)    race ids from the client's masks, or nil
--   Weapons(id, inputs, client, lists)    one class's weapon rows, and the ids removed
--   Replaced(id, rows, client)    each row or outside needs rank with the spells the
--       client says replace it
--   ReplacedCheck(spellsA, rows, replaced)    lines where spellsA's
--       replacedBy and the client disagree
--   ClassSource, RouteSource    the source lines for a stored table
--   Check(files, read, matches)    the paths whose text is not their lines
--
-- inputs holds spellsA[class] rows { level, id, cost, needs, quest, talent }, and
-- replacedBy, read only by ReplacedCheck,
-- levelsB[class] rows by level { id, cost, requiredIds, requiredTalentId },
-- questB[class] by spell id, and weaponsA[class] rows { level, id, cost, masters }.
-- lists holds untrainable. A refusal raises error(msg, 0).

local M = {}

local floor = math.floor
local concat, sort = table.concat, table.sort

local TWO_32 = 4294967296
local WEAPON_MASTER = "Weapon Master"
local PLAYABLE = {
    [1] = true, [2] = true, [3] = true, [4] = true, [5] = true,
    [6] = true, [7] = true, [8] = true, [95] = true, [96] = true,
}
local PLAYABLE_COUNT = 10

local function BitSet(mask, bit)
    if mask < 0 then mask = mask + TWO_32 end
    return floor(mask / 2 ^ bit) % 2 == 1
end

function M.Client(tables, num)
    local client = { names = {}, levels = {}, abilities = {}, raceBits = {} }
    for _, r in ipairs(tables.SpellName) do client.names[num(r.ID)] = r.Name_lang end
    for _, r in ipairs(tables.SpellLevels) do
        local id = num(r.SpellID)
        if client.levels[id] == nil or num(r.DifficultyID) == 0 then
            client.levels[id] = num(r.SpellLevel)
        end
    end
    for _, r in ipairs(tables.SkillLineAbility) do
        local id = num(r.Spell)
        local rows = client.abilities[id] or {}
        client.abilities[id] = rows
        rows[#rows + 1] = {
            classMask = num(r.ClassMask), mask0 = num(r.RaceMasks_0), mask1 = num(r.RaceMasks_1),
            supercedes = num(r.SupercedesSpell),
        }
    end
    for _, r in ipairs(tables.ChrRaces) do
        local bit = num(r.PlayableRaceBit)
        if r.PlayableRaceBit ~= "" and bit >= 0 then client.raceBits[bit] = num(r.ID) end
    end
    return client
end

local function AppliesTo(row, classId)
    return row.classMask == 0 or BitSet(row.classMask, classId - 1)
end

function M.Races(client, spellId, classId)
    local seen, count = {}, 0
    for _, row in ipairs(client.abilities[spellId] or {}) do
        if AppliesTo(row, classId) then
            if (row.mask0 == 0 and row.mask1 == 0) or (row.mask0 == -1 and row.mask1 == -1) then return nil end
            for bit, race in pairs(client.raceBits) do
                local set
                if bit < 32 then set = BitSet(row.mask0, bit) else set = BitSet(row.mask1, bit - 32) end
                if set and PLAYABLE[race] and not seen[race] then
                    seen[race] = true
                    count = count + 1
                end
            end
        end
    end
    if count == 0 or count == PLAYABLE_COUNT then return nil end
    local races = {}
    for race in pairs(seen) do races[#races + 1] = race end
    sort(races)
    return races
end

local function ClientChain(client, id, classId)
    for _, row in ipairs(client.abilities[id] or {}) do
        if AppliesTo(row, classId) and row.supercedes ~= 0 then return row.supercedes end
    end
    return nil
end

-- A source that holds no row for the spell says nothing, so the other's flag stands.
-- Only two sources that both hold the row and differ give maybe.
local function QuestFlag(a, b, inQuestB)
    if not a then return inQuestB or nil end
    local inA = a.quest == true
    if not b and not inQuestB then return inA or nil end
    if inA == inQuestB then return inA or nil end
    return "maybe"
end

local function TalentFlag(a, b, names)
    if a and b then
        local root = b.requiredTalentId
        if a.talent == root then return a.talent end
        -- A root the client has no name for cannot be learned, so it decides nothing.
        if root and not names[root] then return a.talent end
        return "maybe"
    end
    if a then return a.talent end
    return b and b.requiredTalentId or nil
end

-- A set of the untrainable ids, a function that notes each one an input holds,
-- and the sorted list it fills.
local function Remover(lists)
    local banned, noted, removed = {}, {}, {}
    for _, id in ipairs(lists and lists.untrainable or {}) do banned[id] = true end
    local function IsRemoved(id)
        if not banned[id] then return false end
        if not noted[id] then
            noted[id] = true
            removed[#removed + 1] = id
            sort(removed)
        end
        return true
    end
    return banned, IsRemoved, removed
end

function M.ClassRows(classId, inputs, client, lists)
    local aById, bById, ids, seen = {}, {}, {}, {}
    local banned, IsRemoved, removed = Remover(lists)
    local function Add(id)
        if not seen[id] and not IsRemoved(id) then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    for _, row in ipairs(inputs.spellsA[classId] or {}) do
        aById[row[2]] = row
        Add(row[2])
    end
    for _, rows in pairs(inputs.levelsB[classId] or {}) do
        for _, row in ipairs(rows) do
            if not IsRemoved(row.id) then bById[row.id] = row end
        end
    end
    local questB = inputs.questB[classId] or {}
    for id in pairs(questB) do
        if type(id) == "number" then Add(id) end
    end

    local out = {}
    for _, id in ipairs(ids) do
        local level = client.levels[id]
        if not client.names[id] or not level then
            error(("%d has no client name or level"):format(id), 0)
        end
        local a, b = aById[id], bById[id]
        local cost = 0
        if b then cost = b.cost or 0 elseif a then cost = a[3] or 0 end
        local needs
        if a then
            needs = a.needs
        elseif b then
            needs = b.requiredIds and b.requiredIds[1]
        else
            needs = ClientChain(client, id, classId)
        end
        if needs and banned[needs] then needs = nil end
        out[#out + 1] = {
            level, id, cost, needs = needs, races = M.Races(client, id, classId),
            quest = QuestFlag(a, b, questB[id] ~= nil), talent = TalentFlag(a, b, client.names),
        }
    end
    sort(out, function(x, y)
        if x[1] ~= y[1] then return x[1] < y[1] end
        return x[2] < y[2]
    end)

    local leftOut = 0
    for id in pairs(bById) do
        if not seen[id] then leftOut = leftOut + 1 end
    end
    return out, leftOut, removed
end

function M.Weapons(classId, inputs, client, lists)
    local out = {}
    local _, IsRemoved, removed = Remover(lists)
    for _, row in ipairs(inputs.weaponsA[classId] or {}) do
        if not IsRemoved(row[2]) then
            if not client.names[row[2]] then error(("weapon skill %d has no client name"):format(row[2]), 0) end
            out[#out + 1] = { row[1], row[2], masters = row.masters }
        end
    end
    return out, removed
end

-- A learned spell can replace a rank in the book, so the game no longer calls that
-- rank known. For each row, and each needs rank outside the rows, this lists the
-- spells that replace it, up a chain of spells outside the rows. A row whose needs
-- names it is the rank chain, which the known test already follows, so it is left out.
function M.Replaced(classId, rows, client)
    local byId, targets, over = {}, {}, {}
    for _, row in ipairs(rows) do byId[row[2]] = row end
    for _, row in ipairs(rows) do
        targets[row[2]] = true
        if row.needs and not byId[row.needs] then targets[row.needs] = true end
    end
    for spell, abilities in pairs(client.abilities) do
        for _, ability in ipairs(abilities) do
            if ability.supercedes ~= 0 and AppliesTo(ability, classId) then
                local list = over[ability.supercedes] or {}
                over[ability.supercedes] = list
                list[#list + 1] = spell
            end
        end
    end
    local replaced = {}
    for id in pairs(targets) do
        local found, seen, queue, i = {}, { [id] = true }, { id }, 1
        while queue[i] do
            local current = queue[i]
            for _, spell in ipairs(over[current] or {}) do
                if not seen[spell] then
                    seen[spell] = true
                    local row = byId[spell]
                    if not row then
                        found[#found + 1] = spell
                        queue[#queue + 1] = spell
                    elseif row.needs ~= current then
                        found[#found + 1] = spell
                    end
                end
            end
            i = i + 1
        end
        if #found > 0 then
            sort(found)
            replaced[id] = found
        end
    end
    return replaced
end

-- A replacement that is itself a row belongs to the rank chain, so only one outside
-- the rows is expected in spellsA's replacedBy.
function M.ReplacedCheck(spellsA, rows, replaced)
    local inRows = {}
    for _, row in ipairs(rows) do inRows[row[2]] = true end
    local lines = {}
    for _, a in ipairs(spellsA or {}) do
        local id = a[2]
        if inRows[id] then
            local outside, named = {}, false
            for _, other in ipairs(replaced[id] or {}) do
                if other == a.replacedBy then named = true end
                if not inRows[other] then outside[#outside + 1] = other end
            end
            if a.replacedBy and not named then
                lines[#lines + 1] = ("%d replaced by %d in the list, not in the client"):format(id, a.replacedBy)
            elseif not a.replacedBy and #outside > 0 then
                lines[#lines + 1] = ("%d replaced by %s in the client, not in the list"):format(id, concat(outside, ", "))
            end
        end
    end
    return lines
end

local function SortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    sort(keys)
    return keys
end

local function Quoted(value)
    return type(value) == "string" and ("%q"):format(value) or tostring(value)
end

local function SpellLine(row)
    local parts = { row[1], row[2], row[3] }
    if row.needs then parts[#parts + 1] = "needs = " .. row.needs end
    if row.races then parts[#parts + 1] = "races = { " .. concat(row.races, ", ") .. " }" end
    if row.quest then parts[#parts + 1] = "quest = " .. Quoted(row.quest) end
    if row.talent then parts[#parts + 1] = "talent = " .. Quoted(row.talent) end
    return "{ " .. concat(parts, ", ") .. " },"
end

local function WeaponLine(row)
    if not row.masters then return ("{ %d, %d },"):format(row[1], row[2]) end
    local names = {}
    for i, name in ipairs(row.masters) do names[i] = Quoted(name) end
    return ("{ %d, %d, masters = { %s } },"):format(row[1], row[2], concat(names, ", "))
end

function M.ClassSource(rows, weapons, build, replaced)
    local lines = { "return {", "build = " .. Quoted(build) .. ",", "spells = {" }
    for _, row in ipairs(rows) do lines[#lines + 1] = SpellLine(row) end
    lines[#lines + 1] = "},"
    lines[#lines + 1] = "weapons = {"
    for _, row in ipairs(weapons) do lines[#lines + 1] = WeaponLine(row) end
    lines[#lines + 1] = "},"
    if replaced and next(replaced) then
        lines[#lines + 1] = "replaced = {"
        for _, id in ipairs(SortedKeys(replaced)) do
            lines[#lines + 1] = ("[%d] = { %s },"):format(id, concat(replaced[id], ", "))
        end
        lines[#lines + 1] = "},"
    end
    lines[#lines + 1] = "}"
    return lines
end

function M.RouteSource(towns, build)
    local lines = { "return {", "build = " .. Quoted(build) .. ",", "capitals = {" }
    for _, map in ipairs(SortedKeys(towns.capitals)) do
        lines[#lines + 1] = ("[%d] = true,"):format(map)
    end
    lines[#lines + 1] = "},"
    lines[#lines + 1] = "npcs = {"
    for _, map in ipairs(SortedKeys(towns.npcs)) do
        for _, npc in ipairs(towns.npcs[map]) do
            if (npc[3] == "class" and npc[6]) or npc[5] == WEAPON_MASTER then
                lines[#lines + 1] = ("{ %d, %s, %s, %s, %s, %s, %s },"):format(map, tostring(npc[1]), tostring(npc[2]),
                    Quoted(npc[4]), Quoted(npc[5]), npc[6] and Quoted(npc[6]) or "false", Quoted(npc[7]))
            end
        end
    end
    lines[#lines + 1] = "},"
    lines[#lines + 1] = "}"
    return lines
end

function M.Totals(rows)
    local totals = { count = #rows, copper = 0, quest = 0, talent = 0, maybe = 0 }
    for _, row in ipairs(rows) do
        totals.copper = totals.copper + row[3]
        if row.quest == "maybe" or row.talent == "maybe" then totals.maybe = totals.maybe + 1 end
        if row.quest == true then totals.quest = totals.quest + 1 end
        if type(row.talent) == "number" then totals.talent = totals.talent + 1 end
    end
    return totals
end

function M.Check(files, read, matches)
    local failed = {}
    for _, file in ipairs(files) do
        local text = read(file.path)
        if not text or not matches(text, file.lines) then failed[#failed + 1] = file.path end
    end
    return failed
end

return M
