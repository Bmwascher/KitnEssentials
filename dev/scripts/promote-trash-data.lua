-- promote-trash-data.lua: checks a season-2 trash data candidate written by
-- dev/scripts/extract-trash-data.lua and, only with --publish, copies it over
-- the tracked files.
--
--   lua dev/scripts/promote-trash-data.lua --candidate <dir> [--publish]
--
-- A candidate passes only when its TrashData.lua and TrashTraits.lua begin
-- with the tracked files' bytes up to their final closing brace, so every
-- season-1 byte is unchanged; the season-1 maps still hold the expected
-- counts; the manifest's season-2 counts equal both the expected counts and
-- a recount of the candidate files; and the structural diff holds: every
-- season-2 row and trait equals the independently projected source
-- inventory (dev/data/trash-s2-inventory.lua) field by field, with types and
-- the presentation defaults included, each row's name equals the spell-name
-- record, and the only inventory rows left out are the pinned exclusions,
-- each with its reason.
-- Without --publish nothing is written. With it, exactly three tracked files
-- are written: the two data files and dev/data/trash-s2-manifest.lua.

local M = {}

M.TARGETS = {
    data = "Modules/DungeonTools/DungeonTimers/Trash/TrashData.lua",
    traits = "Modules/DungeonTools/DungeonTimers/Trash/TrashTraits.lua",
    manifest = "dev/data/trash-s2-manifest.lua",
}

-- The structural diff's references, read and never written: the source
-- inventory, and the spell-name record the generator joined.
M.INVENTORY = "dev/data/trash-s2-inventory.lua"
M.SPELL_NAMES = "dev/data/trash-spell-names-enUS.lua"

-- Season-1 counts stay as shipped; season-2 visible rows are the editor rows
-- each dungeon shows. D1-A leaves out exactly the Den marker.
M.EXPECTED = {
    s1 = { npcs = 46, rows = 80, visibleRows = 79, traits = 46 },
    s2 = { npcs = 68, rows = 138, visibleRows = 134, hiddenRows = 4, traits = 109 },
    visibleByMap = {
        [1762] = 28, [1877] = 17, [2521] = 24, [2813] = 13,
        [2825] = 9, [2859] = 11, [2923] = 21, [2993] = 11,
    },
    excludedRows = {
        { 2825, 250478, 1309947, reason = "disabled untimed marker: no first cast and no cooldown" },
    },
    uniqueSpells = 135,
}

-- Shipped fields the structural diff compares with the source inventory:
-- every row field the generator writes, the extracted presentation fields
-- included. They are diffed for source fidelity only: TrashConfig reads
-- showNameplate and roles as data steps and ignores the extracted display.
local ROW_FIELDS = {
    "castTime", "channelTime", "first", "cd", "cdMode", "openingCastOrder",
    "targetExists", "targetAPIExists", "targetHostile",
    "showNameplate", "display", "roles",
}
local IDENTITY_FIELDS = {
    "level", "power", "nonElite", "hasCastSkill", "noCastSkill", "hasCastSpell",
    "hasChannelSpell", "hasInterruptFlag", "cannotInterrupt", "isLieutenant",
    "hasCreatureFamily", "preCombatChanneling", "bossEncounter", "groupHasLevel90",
    "groupHasCreatureFamily", "groupHasLevel90Power0", "uiMapIDs", "coPresenceNPCIDs",
}

local S1_FIELDS = { "npcs", "rows", "visibleRows", "traits" }
local S2_FIELDS = { "npcs", "rows", "visibleRows", "hiddenRows", "traits" }
local CANDIDATE_FILES = {
    { key = "data", name = "TrashData.lua" },
    { key = "traits", name = "TrashTraits.lua" },
    { key = "manifest", name = "trash-s2-manifest.lua" },
}

local function fail(msg)
    error("promote-trash-data: " .. msg, 0)
end

local function same(label, got, want)
    if got ~= want then
        fail(string.format("%s is %s, expected %s", label, tostring(got), tostring(want)))
    end
end

local function checkPrefix(base, candidate, label)
    if type(base) ~= "string" or not base:match("},\n}\n$") then
        fail(label .. ": the tracked file does not end with its closing brace")
    end
    local prefix = base:sub(1, #base - 2)
    if candidate:sub(1, #prefix) ~= prefix then
        fail(label .. ": the candidate changes season-1 bytes")
    end
end

-- Runs a generated addon file with only what its header needs and returns
-- the table it assigns onto the addon namespace.
local function loadAddonTable(text, field)
    local chunk, err = loadstring(text, "=" .. field)
    if not chunk then fail(field .. ": " .. tostring(err)) end
    setfenv(chunk, { select = select, KitnEssentials = true })
    local namespace = {}
    local ok, runErr = pcall(chunk, "KitnEssentials", namespace)
    if not ok then fail(field .. ": " .. tostring(runErr)) end
    if type(namespace[field]) ~= "table" then fail(field .. ": the candidate defines no table") end
    return namespace[field]
end

local function loadLiteral(text, label)
    local chunk, err = loadstring(text, "=" .. label)
    if not chunk then fail(label .. ": " .. tostring(err)) end
    setfenv(chunk, {})
    local ok, value = pcall(chunk)
    if not ok then fail(label .. ": " .. tostring(value)) end
    if type(value) ~= "table" then fail(label .. ": not a table") end
    return value
end

-- Diagnostic text only: strings quoted, so "2" and 2 read differently; keyed
-- tables in key order. Equality never goes through this.
local function render(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = (type(k) == "number" and "" or (k .. "=")) .. render(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Structural equality: the same type, and for tables the same keys with
-- structurally equal values, recursively.
local function sameValue(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not sameValue(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function differs(label, got, want, source)
    if not sameValue(got, want) then
        fail(string.format("%s is %s, %s says %s", label, render(got), source or "the inventory", render(want)))
    end
end

-- A row's key from three whole numbers; a string ID that prints like a
-- number is refused rather than matched.
local function rowKey(mapID, npcID, spellID, label)
    for _, part in ipairs({ { mapID }, { npcID }, { spellID } }) do
        local v = part[1]
        if type(v) ~= "number" or v % 1 ~= 0 then
            fail(string.format("%s key %s:%s:%s is not three whole numbers", label,
                tostring(mapID), tostring(npcID), tostring(spellID)))
        end
    end
    return string.format("%d:%d:%d", mapID, npcID, spellID)
end

-- The structural diff (spec 6): the candidate's season-2 rows and traits equal
-- the source inventory field by field, with types, and each row's name equals
-- the spell-name record. The only inventory rows it leaves out are the pinned
-- exclusions, which the manifest lists with their reasons.
local function checkInventory(data, traits, manifest, inventory, spellNames, expected)
    local s2Maps = expected.visibleByMap
    local excluded, excludedCount = {}, 0
    for _, x in ipairs(expected.excludedRows) do
        excluded[rowKey(x[1], x[2], x[3], "pinned exclusion")] = x.reason
        excludedCount = excludedCount + 1
    end
    local listed = 0
    for _, x in ipairs(type(manifest.excluded) == "table" and manifest.excluded or {}) do
        local key = rowKey(x.mapID, x.npcID, x.spellID, "manifest exclusion")
        if excluded[key] == nil or excluded[key] ~= x.reason then
            fail("manifest excludes " .. key .. " (" .. render(x.reason) .. "), which the pins do not")
        end
        listed = listed + 1
    end
    same("manifest excluded rows", listed, excludedCount)

    local nameBySpell = {}
    for _, entry in ipairs(type(spellNames.entries) == "table" and spellNames.entries or {}) do
        nameBySpell[entry[1]] = entry[2]
    end

    local rows, rowCount, timedNpcs = {}, 0, {}
    for _, r in ipairs(type(inventory.rows) == "table" and inventory.rows or {}) do
        local key = rowKey(r[1], r[2], r[3], "inventory row")
        if rows[key] then fail("inventory lists row " .. key .. " twice") end
        rows[key] = r
        rowCount = rowCount + 1
        if not excluded[key] then timedNpcs[r[2]] = true end
    end
    for key in pairs(excluded) do
        if not rows[key] then fail("excluded row " .. key .. " is not in the source inventory") end
    end
    local shipped, spells, uniqueSpells = 0, {}, 0
    for mapID in pairs(s2Maps) do
        local dungeon = data[mapID]
        if dungeon then differs("candidate map " .. mapID .. " mapID", dungeon.mapID, mapID, "its key") end
        for npcID, mob in pairs(dungeon and dungeon.mobs or {}) do
            for spellID, spell in pairs(mob.spells or {}) do
                local key = rowKey(mapID, npcID, spellID, "candidate row")
                local r = rows[key]
                if not r then fail("candidate row " .. key .. " is not in the source inventory") end
                if excluded[key] then fail("candidate ships the excluded row " .. key) end
                differs("candidate row " .. key .. " npcID", mob.npcID, npcID, "its key")
                differs("candidate row " .. key .. " NPC name", mob.name, r.npcName)
                differs("candidate row " .. key .. " spellID", spell.spellID, spellID, "its key")
                differs("candidate row " .. key .. " name", spell.name, nameBySpell[spellID], "the spell-name record")
                for _, field in ipairs(ROW_FIELDS) do
                    differs("candidate row " .. key .. "." .. field, spell[field], r[field])
                end
                if (spell.hidden == true) ~= (r.first == nil) then
                    fail("candidate row " .. key .. " is hidden only when it has no first cast")
                end
                shipped = shipped + 1
                if not spells[spellID] then
                    spells[spellID] = true
                    uniqueSpells = uniqueSpells + 1
                end
            end
        end
    end
    same("candidate season-2 rows against the inventory", shipped, rowCount - excludedCount)
    same("candidate unique season-2 spells", uniqueSpells, expected.uniqueSpells)

    local wanted, wantedCount = {}, 0
    for _, t in ipairs(type(inventory.traits) == "table" and inventory.traits or {}) do
        local npcID = t[2]
        if type(npcID) ~= "number" or npcID % 1 ~= 0 then
            fail("inventory trait " .. render(npcID) .. " has no whole-number npcID")
        end
        if wanted[npcID] then fail("inventory lists trait " .. npcID .. " twice") end
        wanted[npcID] = t
        wantedCount = wantedCount + 1
    end
    local shippedTraits = 0
    for npcID, trait in pairs(traits) do
        if s2Maps[trait.mapID] ~= nil then
            local t = wanted[npcID]
            local where = "candidate trait " .. render(npcID)
            if not t then fail(where .. " is not in the source inventory") end
            differs(where .. " npcID", trait.npcID, npcID, "its key")
            differs(where .. " mapID", trait.mapID, t[1])
            differs(where .. " schema", trait.schema, "named", "the named schema")
            differs(where .. " dungeonKey", trait.dungeonKey, data[trait.mapID] and data[trait.mapID].dungeonKey,
                "its map")
            -- The inventory names only NPCs with timer rows (spec 6).
            if t.name ~= nil then differs(where .. " name", trait.name, t.name) end
            differs(where .. " identityOnly", trait.identityOnly == true, not timedNpcs[npcID])
            local identity = trait.identity or {}
            for _, field in ipairs(IDENTITY_FIELDS) do
                differs(where .. "." .. field, identity[field], t[field])
            end
            differs(where .. " rooms", identity.roomNames and #identity.roomNames or nil, t.rooms)
            differs(where .. " placement", trait.placement or "", t.placement or "")
            differs(where .. " castTimeSet", trait.castTimeSet, t.castTimeSet)
            differs(where .. " channelTimeSet", trait.channelTimeSet, t.channelTimeSet)
            differs(where .. " spellIDs", trait.spellIDs, t.spellIDs)
            shippedTraits = shippedTraits + 1
        end
    end
    same("candidate season-2 traits against the inventory", shippedTraits, wantedCount)
end

local function countCandidate(data, traits, s2Maps)
    local s1 = { npcs = 0, rows = 0, visibleRows = 0, traits = 0 }
    local s2 = { npcs = 0, rows = 0, visibleRows = 0, hiddenRows = 0, traits = 0, visibleByMap = {} }
    for mapID, dungeon in pairs(data) do
        local isS2 = s2Maps[mapID] ~= nil
        local c = isS2 and s2 or s1
        for _, mob in pairs(dungeon.mobs or {}) do
            c.npcs = c.npcs + 1
            for _, spell in pairs(mob.spells or {}) do
                c.rows = c.rows + 1
                if spell.hidden == true then
                    if isS2 then s2.hiddenRows = s2.hiddenRows + 1 end
                else
                    c.visibleRows = c.visibleRows + 1
                    if isS2 then s2.visibleByMap[mapID] = (s2.visibleByMap[mapID] or 0) + 1 end
                end
            end
        end
    end
    for _, trait in pairs(traits) do
        local c = (s2Maps[trait.mapID] ~= nil) and s2 or s1
        c.traits = c.traits + 1
    end
    return s1, s2
end

function M.Check(texts, expected)
    expected = expected or M.EXPECTED
    checkPrefix(texts.baseData, texts.data, "TrashData")
    checkPrefix(texts.baseTraits, texts.traits, "TrashTraits")
    local manifest = loadLiteral(texts.manifest, "manifest")
    local inventory = loadLiteral(texts.inventory, "inventory")
    local spellNames = loadLiteral(texts.spellNames, "spell names")
    local s2Maps = expected.visibleByMap
    local data = loadAddonTable(texts.data, "TrashData")
    local traits = loadAddonTable(texts.traits, "TrashTraits")
    local s1, s2 = countCandidate(data, traits, s2Maps)

    for _, field in ipairs(S1_FIELDS) do
        same("season-1 " .. field, s1[field], expected.s1[field])
    end
    local totals = type(manifest.totals) == "table" and manifest.totals or {}
    for _, field in ipairs(S2_FIELDS) do
        same("manifest totals." .. field, totals[field], expected.s2[field])
    end
    for _, field in ipairs(S2_FIELDS) do
        if s2[field] ~= totals[field] then
            fail(string.format("candidate %s is %s, manifest says %s",
                field, tostring(s2[field]), tostring(totals[field])))
        end
    end
    local listed = {}
    for _, entry in ipairs(type(manifest.maps) == "table" and manifest.maps or {}) do
        local mapID = entry.mapID
        local want = s2Maps[mapID]
        if want == nil or listed[mapID] then
            fail("manifest lists map " .. tostring(mapID) .. " unexpectedly")
        end
        listed[mapID] = true
        same("manifest visibleRows for map " .. tostring(mapID), entry.visibleRows, want)
        same("candidate visibleRows for map " .. tostring(mapID), s2.visibleByMap[mapID] or 0, want)
    end
    for mapID in pairs(s2Maps) do
        if not listed[mapID] then fail("manifest does not list map " .. tostring(mapID)) end
    end
    checkInventory(data, traits, manifest, inventory, spellNames, expected)
    return { s1 = s1, s2 = s2 }
end

M.realFS = {
    read = function(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local text = f:read("*a")
        f:close()
        return text
    end,
    write = function(path, text)
        local f, err = io.open(path, "wb")
        if not f then return nil, err end
        f:write(text)
        f:close()
        return true
    end,
}

function M.Run(opts, fs, expected)
    fs = fs or M.realFS
    return pcall(function()
        if type(opts.candidate) ~= "string" or opts.candidate == "" then fail("missing --candidate") end
        local dir = opts.candidate:gsub("[/\\]+$", "")
        local texts = {}
        for _, file in ipairs(CANDIDATE_FILES) do
            local path = dir .. "/" .. file.name
            texts[file.key] = fs.read(path)
            if not texts[file.key] then fail("missing candidate file " .. path) end
        end
        texts.baseData = fs.read(M.TARGETS.data)
        texts.baseTraits = fs.read(M.TARGETS.traits)
        if not (texts.baseData and texts.baseTraits) then fail("missing tracked data file") end
        texts.inventory = fs.read(M.INVENTORY)
        if not texts.inventory then fail("missing inventory " .. M.INVENTORY) end
        texts.spellNames = fs.read(M.SPELL_NAMES)
        if not texts.spellNames then fail("missing spell-name record " .. M.SPELL_NAMES) end
        local counts = M.Check(texts, expected)
        if opts.publish then
            for _, file in ipairs(CANDIDATE_FILES) do
                local ok, err = fs.write(M.TARGETS[file.key], texts[file.key])
                if not ok then fail("cannot write " .. M.TARGETS[file.key] .. ": " .. tostring(err)) end
            end
        end
        return counts
    end)
end

if arg and type(arg[0]) == "string" and arg[0]:match("promote%-trash%-data%.lua$") then
    local opts = {}
    local i = 1
    while arg[i] ~= nil do
        if arg[i] == "--publish" then
            opts.publish = true
            i = i + 1
        elseif arg[i] == "--candidate" and arg[i + 1] ~= nil then
            opts.candidate = arg[i + 1]
            i = i + 2
        else
            io.stderr:write("promote-trash-data: bad argument " .. tostring(arg[i]) .. "\n")
            os.exit(2)
        end
    end
    local ok, result = M.Run(opts)
    if not ok then
        io.stderr:write(tostring(result) .. "\n")
        os.exit(1)
    end
    local s1, s2 = result.s1, result.s2
    print(string.format("season-1 npcs %d rows %d visible %d traits %d",
        s1.npcs, s1.rows, s1.visibleRows, s1.traits))
    print(string.format("season-2 npcs %d rows %d visible %d hidden %d traits %d",
        s2.npcs, s2.rows, s2.visibleRows, s2.hiddenRows, s2.traits))
    print(opts.publish and "published" or "checked; nothing written")
end

return M
