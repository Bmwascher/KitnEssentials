-- Tier 1: refusal rules of the trash data generator
-- (dev/scripts/extract-trash-data.lua). Every refusal must stop a run before a
-- byte is written, and the output must not depend on input order. Inputs are
-- plain tables and an in-memory file table; no real file is read or written.

local X = dofile("dev/scripts/extract-trash-data.lua")

local BASE_DATA = "KE.TrashData = {\n    [1] = {\n    },\n}\n"
local BASE_TRAITS = "KE.TrashTraits = {\n    [1] = {\n    },\n}\n"

local function pins()
    return {
        challengeToInstance = { [900] = 1900 },
        excluded = {},
        pinnedSpells = {},
        waveRoomID = 94539,
    }
end

local function fixture()
    return {
        data = { [900] = { mapID = 900, mapName = "zone-a", mobs = {
            [5001] = { npcID = 5001, name = "mob-a", spells = {
                [7001] = { spellID = 7001, name = "s1", nameEN = "", eventType = "x",
                    castTime = 2, first = 5, cd = { 10 } },
                [7002] = { spellID = 7002, name = "s2", nameEN = "", eventType = "x",
                    channelTime = 4 },
            } },
        } } },
        traits = {
            wmoAreaNamesByID = { [94539] = { enUS = "Wave Room" } },
            rows = {
                { dungeon = "zone-a", npcID = 5001, name = "mob-a", level = 91, power = 1,
                  boss = "1", nonElite = false, isLieutenant = false, hasCastSpell = true,
                  castTimeSet = "2", channelTimeSet = "4", spellIDs = { 7001, 7002 } },
                { dungeon = "zone-a", npcID = 5002, name = "mob-b", level = 90, power = 0,
                  nonElite = false, spellIDs = {} },
            },
        },
        preset = {},
        npcNames = { [5001] = { enUS = "Mob One" }, [5002] = { enUS = "Mob Two" } },
        instances = { { mapID = 1900, challengeModeID = 900, name = "zone-a" } },
        spellNames = {
            sourceSha256 = "00",
            entries = { { 7001, "Bolt" }, { 7002, "Beam" } },
            includedRows = { { 1900, 5001, 7001 }, { 1900, 5001, 7002 } },
            excludedRows = {},
        },
        registry = { { key = "TestKeep", name = "Test Keep", instanceID = 1900 } },
        baseData = BASE_DATA,
        baseTraits = BASE_TRAITS,
    }
end

local function refusal(inputs, p)
    local ok, err = pcall(X.Build, inputs, p or pins())
    assert.is_false(ok)
    return tostring(err)
end

describe("trash data generator — run", function()
    local OPTS = {
        ["data-root"] = "src", ["names-db"] = "names.lua", ["spell-names"] = "spell.lua",
        ["base-data"] = "base-data.lua", ["base-traits"] = "base-traits.lua",
        registry = "registry.lua", season = "2", out = "candidate",
    }
    local PATHS = {
        "src/TrashCDData.lua", "src/TrashMobTraits.lua", "src/TrashCDPreset.lua",
        "names.lua", "spell.lua", "base-data.lua", "base-traits.lua", "registry.lua",
    }

    it("writes nothing when an input is missing or malformed", function()
        local cases = {
            { drop = "src/TrashMobTraits.lua", want = "missing input" },
            { data = "T = {}\n", want = "no data literal" },
            { data = "_G.T_TRASH_CD_DATA = {\n    [1] = function() end,\n}\n", want = "holds a function" },
            -- Repeated map, NPC and spell keys; the same key in sibling tables
            -- and inside a string or comment is no repeat.
            { data = "_G.T_TRASH_CD_DATA = {\n    [1] = { mapID = 1 },\n    [1] = { mapID = 1 },\n}\n",
              want = "key 1 is written twice" },
            { data = "_G.T_TRASH_CD_DATA = {\n    [1] = { mobs = { [5] = { npcID = 5 }, [6] = { npcID = 6 },"
                .. " [5] = { npcID = 5 } } },\n}\n", want = "key 5 is written twice" },
            { data = "_G.T_TRASH_CD_DATA = {\n    [1] = { mobs = { [5] = { spells = { [7] = { name = \"a = {\" },"
                .. " -- [7] = {}\n [8] = { name = \"b\" }, [7] = { name = \"c\" } } } } },\n}\n",
              want = "key 7 is written twice" },
            -- A list item's implicit index can repeat a key, and a comment may
            -- stand between a key and its "=".
            { data = "_G.T_TRASH_CD_DATA = {\n    [1] = { [1] = \"a\", \"b\" },\n}\n",
              want = "a table mixes list items with keys" },
            { data = "_G.T_TRASH_CD_DATA = {\n    [1] = { mapID --[[x]] = 1, mapID -- y\n = 1 },\n}\n",
              want = "key mapID is written twice" },
        }
        for _, c in ipairs(cases) do
            local files, writes = {}, {}
            for _, path in ipairs(PATHS) do files[path] = "" end
            if c.drop then files[c.drop] = nil end
            if c.data then files["src/TrashCDData.lua"] = c.data end
            local fs = {
                read = function(path) return files[path] end,
                write = function(path) writes[#writes + 1] = path; return true end,
            }
            local ok, err = X.Run(OPTS, fs)
            assert.is_false(ok)
            assert.truthy(tostring(err):find(c.want, 1, true))
            assert.same({}, writes)
        end
    end)
end)

describe("trash data generator — refusals", function()
    it("refuses a map collision", function()
        local cases = {
            function(i, p)
                i.instances[2] = { mapID = 1900, challengeModeID = 901, name = "zone-b" }
                p.challengeToInstance[901] = 1900
            end,
            function(i) i.instances[2] = { mapID = 1901, challengeModeID = 900, name = "zone-c" } end,
            function(i) i.registry[2] = { key = "Other", name = "Other", instanceID = 1900 } end,
        }
        for _, mutate in ipairs(cases) do
            local inputs, p = fixture(), pins()
            mutate(inputs, p)
            assert.truthy(refusal(inputs, p):find("map collision", 1, true))
        end
    end)

    it("refuses an identity-only trait whose dungeon string maps to no instance", function()
        local inputs = fixture()
        inputs.traits.rows[2].dungeon = "zone-unknown"
        assert.truthy(refusal(inputs):find("unmapped dungeon", 1, true))
    end)

    it("refuses missing, empty, duplicate, stray or excluded English names", function()
        local cases = {
            { want = "npc 5001 has no English name",
              mutate = function(i) i.npcNames[5001].enUS = "" end },
            { want = "spell 7001 has an empty name",
              mutate = function(i) i.spellNames.entries[1] = { 7001, "" } end },
            { want = "no English name for spell 7002",
              mutate = function(i) i.spellNames.entries[2] = nil end },
            { want = "duplicate spell 7001",
              mutate = function(i) i.spellNames.entries[3] = { 7001, "Bolt" } end },
            { want = "entry 7999 belongs to no included row",
              mutate = function(i) i.spellNames.entries[3] = { 7999, "Extra" } end },
            { want = "is not in the spell-name rows",
              mutate = function(i) i.spellNames.includedRows[2] = nil end },
            { want = "is not generated",
              mutate = function(i) i.spellNames.includedRows[3] = { 1900, 5001, 7003 } end },
            { want = "entry 1 has no spell ID",
              mutate = function(i) i.spellNames.entries[1] = { 0, "Bolt" } end },
            { want = "excluded row 1900:5001:7999 is not pinned",
              mutate = function(i) i.spellNames.excludedRows = { { 1900, 5001, 7999 } } end },
            { want = "is among the included rows",
              mutate = function(i, p)
                  p.excluded = { { mapID = 1900, npcID = 5001, spellID = 7002, reason = "test" } }
                  i.spellNames.excludedRows = { { 1900, 5001, 7002 } }
              end },
        }
        for _, c in ipairs(cases) do
            local inputs, p = fixture(), pins()
            c.mutate(inputs, p)
            assert.truthy(refusal(inputs, p):find(c.want, 1, true))
        end
    end)

    it("refuses a wave-room trait without all three wave fields", function()
        local inputs = fixture()
        local row = inputs.traits.rows[2]
        row.wmoAreaIDs = { [94539] = true }
        row.groupHasLevel90 = true
        assert.truthy(refusal(inputs):find("wave fields", 1, true))
        row.groupHasCreatureFamily = false
        row.groupHasLevel90Power0 = false
        assert.is_true((pcall(X.Build, inputs, pins())))
    end)
end)

describe("trash data generator — determinism", function()
    local function reversed(list)
        local out = {}
        for i = #list, 1, -1 do out[#out + 1] = list[i] end
        return out
    end

    it("gives byte-identical output whatever the input order", function()
        local a = X.Build(fixture(), pins())
        local inputs = fixture()
        inputs.traits.rows = reversed(inputs.traits.rows)
        inputs.spellNames.entries = reversed(inputs.spellNames.entries)
        inputs.spellNames.includedRows = reversed(inputs.spellNames.includedRows)
        local b = X.Build(inputs, pins())
        for _, key in ipairs({ "data", "traits", "manifest", "report" }) do
            assert.equals(a[key], b[key])
        end
    end)
end)
