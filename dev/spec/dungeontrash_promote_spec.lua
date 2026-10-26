-- Tier 1: refusal rules of the trash data promote step
-- (dev/scripts/promote-trash-data.lua). A candidate that would change a
-- season-1 byte, whose counts disagree with the expected counts or with its
-- own manifest, or whose season-2 rows, exclusions or traits differ from the
-- source inventory, is refused before any tracked file is written. Inputs are
-- in-memory files; no real file is read or written.

local P = dofile("dev/scripts/promote-trash-data.lua")

local HEAD = "local KE = select(2, ...)\nif not KitnEssentials then return end\n"
local S1_DATA = "    [10] = { mobs = { [1] = { spells = { [100] = { first = 1 }, [101] = { hidden = true } } } } },\n"
local ROLES = "roles = { tank = true, healer = true, dps = true }"
local S2_DATA = '    [20] = { mapID = 20, dungeonKey = "K", mobs = { [2] = { npcID = 2, name = "Two", spells = {\n'
    .. '        [200] = { spellID = 200, name = "Bolt", first = 2, showNameplate = false, display = "bar", ' .. ROLES .. " },\n"
    .. '        [201] = { spellID = 201, name = "Beam", hidden = true, showNameplate = true, display = "text", ' .. ROLES .. " },\n"
    .. "    } } } },\n"
local S1_TRAITS = "    [1] = { mapID = 10 },\n"
local S2_TRAITS = '    [2] = { npcID = 2, mapID = 20, dungeonKey = "K", name = "Two", schema = "named", identity = {} },\n'
    .. '    [3] = { npcID = 3, mapID = 20, dungeonKey = "K", name = "Three", schema = "named", identityOnly = true, identity = {} },\n'
local MANIFEST = table.concat({
    "return {",
    "    totals = { npcs = 1, rows = 2, visibleRows = 1, hiddenRows = 1, traits = 2 },",
    "    maps = { { mapID = 20, visibleRows = 1 } },",
    '    excluded = { { mapID = 20, npcID = 2, spellID = 202, reason = "test" } },',
    "}",
}, "\n") .. "\n"
-- The independent source inventory: the two shipped rows, the excluded one,
-- and both traits; only a timed NPC carries its name.
local INVENTORY = table.concat({
    "return {",
    "    rows = {",
    '        { 20, 2, 200, npcName = "Two", first = 2, showNameplate = false, display = "bar", ' .. ROLES .. " },",
    '        { 20, 2, 201, npcName = "Two", showNameplate = true, display = "text", ' .. ROLES .. " },",
    '        { 20, 2, 202, npcName = "Two", showNameplate = true, display = "bar", ' .. ROLES .. " },",
    "    },",
    '    traits = { { 20, 2, name = "Two" }, { 20, 3 } },',
    "}",
}, "\n") .. "\n"
local SPELL_NAMES = 'return { entries = { { 200, "Bolt" }, { 201, "Beam" } } }\n'

local function expected()
    return {
        s1 = { npcs = 1, rows = 2, visibleRows = 1, traits = 1 },
        s2 = { npcs = 1, rows = 2, visibleRows = 1, hiddenRows = 1, traits = 2 },
        visibleByMap = { [20] = 1 },
        excludedRows = { { 20, 2, 202, reason = "test" } },
        uniqueSpells = 2,
    }
end

local function files()
    return {
        [P.TARGETS.data] = HEAD .. "KE.TrashData = {\n" .. S1_DATA .. "}\n",
        [P.TARGETS.traits] = HEAD .. "KE.TrashTraits = {\n" .. S1_TRAITS .. "}\n",
        [P.INVENTORY] = INVENTORY,
        [P.SPELL_NAMES] = SPELL_NAMES,
        ["cand/TrashData.lua"] = HEAD .. "KE.TrashData = {\n" .. S1_DATA .. "\n" .. S2_DATA .. "}\n",
        ["cand/TrashTraits.lua"] = HEAD .. "KE.TrashTraits = {\n" .. S1_TRAITS .. "\n" .. S2_TRAITS .. "}\n",
        ["cand/trash-s2-manifest.lua"] = MANIFEST,
    }
end

local function fakeFS(store)
    local writes = {}
    local fs = {
        read = function(path) return store[path] end,
        write = function(path, text)
            writes[#writes + 1] = { path = path, text = text }
            return true
        end,
    }
    return fs, writes
end

describe("trash data promote step", function()
    it("refuses a candidate that changes season-1 bytes or disagrees with the counts, writing nothing", function()
        local cases = {
            { want = "TrashData: the candidate changes season-1 bytes",
              mutate = function(f)
                  f["cand/TrashData.lua"] = (f["cand/TrashData.lua"]:gsub("first = 1", "first = 9"))
              end },
            { want = "TrashTraits: the candidate changes season-1 bytes",
              mutate = function(f)
                  f["cand/TrashTraits.lua"] = (f["cand/TrashTraits.lua"]:gsub("mapID = 10", "mapID = 11"))
              end },
            { want = "manifest totals.visibleRows is 2, expected 1",
              mutate = function(f)
                  f["cand/trash-s2-manifest.lua"] = (f["cand/trash-s2-manifest.lua"]:gsub(
                      "visibleRows = 1, hidden", "visibleRows = 2, hidden"))
              end },
            { want = "manifest visibleRows for map 20 is 1, expected 2",
              mutate = function(_, e) e.visibleByMap[20] = 2 end },
            { want = "candidate visibleRows is 2, manifest says 1",
              mutate = function(f)
                  f["cand/TrashData.lua"] = (f["cand/TrashData.lua"]:gsub("hidden = true, ", "first = 3, "))
              end },
            { want = "season-1 npcs is 1, expected 2",
              mutate = function(_, e) e.s1.npcs = 2 end },
            { want = "missing candidate file cand/trash-s2-manifest.lua",
              mutate = function(f) f["cand/trash-s2-manifest.lua"] = nil end },
            -- The structural diff against the source inventory (spec 6).
            { want = "missing inventory " .. P.INVENTORY,
              mutate = function(f) f[P.INVENTORY] = nil end },
            { want = "missing spell-name record " .. P.SPELL_NAMES,
              mutate = function(f) f[P.SPELL_NAMES] = nil end },
            { want = "candidate row 20:2:200.cd is {9}, the inventory says nil",
              mutate = function(f)
                  f["cand/TrashData.lua"] = (f["cand/TrashData.lua"]:gsub("first = 2, ", "first = 2, cd = { 9 }, "))
              end },
            -- Types count: a string that prints like the number is refused (Astra R2 F4).
            { want = 'candidate row 20:2:200.first is "2", the inventory says 2',
              mutate = function(f)
                  f["cand/TrashData.lua"] = (f["cand/TrashData.lua"]:gsub("first = 2, ", 'first = "2", '))
              end },
            { want = 'candidate row key 20:2:200 is not three whole numbers',
              mutate = function(f)
                  f["cand/TrashData.lua"] = (f["cand/TrashData.lua"]:gsub("%[200%] =", '["200"] ='))
              end },
            -- A presentation default is a shipped field (Astra R2 K3).
            { want = "candidate row 20:2:200.showNameplate is true, the inventory says false",
              mutate = function(f)
                  f["cand/TrashData.lua"] = (f["cand/TrashData.lua"]:gsub("showNameplate = false", "showNameplate = true"))
              end },
            { want = 'candidate row 20:2:200 name is "Bolts", the spell-name record says "Bolt"',
              mutate = function(f)
                  f["cand/TrashData.lua"] = (f["cand/TrashData.lua"]:gsub('"Bolt"', '"Bolts"'))
              end },
            { want = "candidate row 20:2:203 is not in the source inventory",
              mutate = function(f)
                  f["cand/TrashData.lua"] = (f["cand/TrashData.lua"]:gsub("%[200%] =", "[203] ="))
              end },
            { want = "candidate ships the excluded row 20:2:202",
              mutate = function(f)
                  f["cand/TrashData.lua"] = (f["cand/TrashData.lua"]:gsub("%[200%] =", "[202] ="))
              end },
            { want = 'manifest excludes 20:2:202 ("other"), which the pins do not',
              mutate = function(f)
                  f["cand/trash-s2-manifest.lua"] = (f["cand/trash-s2-manifest.lua"]:gsub('"test"', '"other"'))
              end },
            { want = "candidate season-2 rows against the inventory is 2, expected 3",
              mutate = function(f)
                  f[P.INVENTORY] = (f[P.INVENTORY]:gsub("{ 20, 2, 202,", '{ 20, 2, 204, npcName = "Two" }, { 20, 2, 202,'))
              end },
            { want = "candidate unique season-2 spells is 2, expected 3",
              mutate = function(_, e) e.uniqueSpells = 3 end },
            { want = "candidate trait 3 identityOnly is false, the inventory says true",
              mutate = function(f)
                  f["cand/TrashTraits.lua"] = (f["cand/TrashTraits.lua"]:gsub(", identityOnly = true", ""))
              end },
            { want = "candidate trait 2.level is 90, the inventory says nil",
              mutate = function(f)
                  f["cand/TrashTraits.lua"] = (f["cand/TrashTraits.lua"]:gsub(
                      'name = "Two", schema = "named", identity = {}', 'name = "Two", schema = "named", identity = { level = 90 }'))
              end },
        }
        for _, c in ipairs(cases) do
            local f, e = files(), expected()
            c.mutate(f, e)
            local fs, writes = fakeFS(f)
            local ok, err = P.Run({ candidate = "cand", publish = true }, fs, e)
            assert.is_false(ok)
            assert.truthy(tostring(err):find(c.want, 1, true))
            assert.same({}, writes)
        end
    end)

    it("check mode writes nothing, and publish writes the three tracked files with the candidate bytes", function()
        local f = files()
        local fs, writes = fakeFS(f)
        assert.is_true((P.Run({ candidate = "cand" }, fs, expected())))
        assert.same({}, writes)
        assert.is_true((P.Run({ candidate = "cand", publish = true }, fs, expected())))
        assert.same({
            { path = P.TARGETS.data, text = f["cand/TrashData.lua"] },
            { path = P.TARGETS.traits, text = f["cand/TrashTraits.lua"] },
            { path = P.TARGETS.manifest, text = f["cand/trash-s2-manifest.lua"] },
        }, writes)
    end)
end)
