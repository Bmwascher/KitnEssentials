-- Tier 1: Modules/QoL/QualityOfLife/RareAlertRules.lua. The alert's pure
-- decisions: what fires, what replaces what, where the arrow points, and what
-- the card's third line and party line say.
local L = require("dev.spec._ke_loader")

local PI = math.pi

local function merged(base, over)
    for key, value in pairs(over or {}) do base[key] = value end
    return base
end

local function settings(over)
    return merged({
        FireVignette = true, FirePlate = true, FireTarget = true,
        LoudGray = false, LoudTapped = false, LoudFound = false,
        ShowQuiet = true,
    }, over)
end

local function fact(over)
    return merged({
        source = "vignette", npc = 5828, isRare = true, hostile = true,
        dead = false, tapped = false, gray = false, friendly = false,
        seenRecently = false,
    }, over)
end

-- Compared by direction: a rotation and the same rotation a full turn away
-- point the arrow the same way.
local function assertSameAngle(expected, actual, name)
    assert.near(math.cos(expected), math.cos(actual), 1e-9, name)
    assert.near(math.sin(expected), math.sin(actual), 1e-9, name)
end

describe("Rare Alert rules", function()
    local RA

    before_each(function()
        RA = L.loadRareAlertRules()
    end)

    describe("RA.Decide", function()
        it("gives none when a tick is off or a fact rules the rare out", function()
            for _, row in ipairs({
                { name = "vignette tick off",  fact = { source = "vignette" },  settings = { FireVignette = false } },
                { name = "plate tick off",     fact = { source = "plate" },     settings = { FirePlate = false } },
                { name = "target tick off",    fact = { source = "target" },    settings = { FireTarget = false } },
                { name = "mouseover tick off", fact = { source = "mouseover" }, settings = { FireTarget = false } },
                { name = "no npc",             fact = { npc = false } },
                { name = "not a rare",         fact = { isRare = false } },
                { name = "not hostile",        fact = { hostile = false } },
                { name = "dead",               fact = { dead = true } },
                { name = "friendly",           fact = { friendly = true } },
                { name = "seen recently",      fact = { seenRecently = true } },
                { name = "proved, vignette",   fact = { provedWrong = true } },
            }) do
                assert.equals("none", RA.Decide(fact(row.fact), settings(row.settings)), row.name)
            end
        end)

        it("gives loud or quiet by the reasons left after the Loud For boxes", function()
            for _, row in ipairs({
                { name = "alive by vignette",    fact = { source = "vignette" }, want = "loud" },
                { name = "alive by plate",       fact = { source = "plate" },    want = "loud" },
                { name = "proved, by plate",     fact = { source = "plate", provedWrong = true },     want = "loud" },
                { name = "proved, by target",    fact = { source = "target", provedWrong = true },    want = "quiet" },
                { name = "proved, by mouseover", fact = { source = "mouseover", provedWrong = true }, want = "quiet" },
                { name = "tapped",               fact = { tapped = true },       want = "quiet" },
                { name = "tapped, box on",       fact = { tapped = true },       settings = { LoudTapped = true }, want = "loud" },
                { name = "gray",                 fact = { gray = true },         want = "quiet" },
                { name = "gray, box on",         fact = { gray = true },         settings = { LoudGray = true },   want = "loud" },
                { name = "found by target",      fact = { source = "target" },   want = "quiet" },
                { name = "found by mouseover",   fact = { source = "mouseover" }, want = "quiet" },
                { name = "found by target, box on",
                  fact = { source = "target" }, settings = { LoudFound = true }, want = "loud" },
                { name = "tapped and gray, one box on",
                  fact = { tapped = true, gray = true }, settings = { LoudTapped = true }, want = "quiet" },
            }) do
                assert.equals(row.want, RA.Decide(fact(row.fact), settings(row.settings)), row.name)
            end
        end)

        it("turns quiet into none with Show Quiet Cards off and leaves loud alone", function()
            local off = settings({ ShowQuiet = false })
            assert.equals("none", RA.Decide(fact({ tapped = true }), off))
            assert.equals("loud", RA.Decide(fact(), off))
        end)
    end)

    describe("RA.VignetteCounts", function()
        it("counts a known hostile rare, or an unknown one with a Kill atlas", function()
            for _, row in ipairs({
                { name = "no npc",                npc = nil,  on = true,  dead = false, known = false, friendly = false, kill = true,  want = false },
                { name = "off the minimap",       npc = 5828, on = false, dead = false, known = true,  friendly = false, kill = true,  want = false },
                { name = "dead",                  npc = 5828, on = true,  dead = true,  known = true,  friendly = false, kill = true,  want = false },
                { name = "known and hostile",     npc = 5828, on = true,  dead = false, known = true,  friendly = false, kill = false, want = true },
                { name = "known, friendly, Kill", npc = 5828, on = true,  dead = false, known = true,  friendly = true,  kill = true,  want = false },
                { name = "unknown with Kill",     npc = 5828, on = true,  dead = false, known = false, friendly = false, kill = true,  want = true },
                { name = "unknown without Kill",  npc = 5828, on = true,  dead = false, known = false, friendly = false, kill = false, want = false },
            }) do
                assert.equals(row.want,
                    RA.VignetteCounts(row.npc, row.on, row.dead, row.known, row.friendly, row.kill), row.name)
            end
        end)
    end)

    describe("RA.SeenRecently and RA.Stamp", function()
        it("holds a creature for 300 seconds from its stamp, and no other creature", function()
            local seen = {}
            assert.is_false(RA.SeenRecently(seen, 5828, 1000))
            RA.Stamp(seen, 5828, 1000)
            assert.is_true(RA.SeenRecently(seen, 5828, 1299))
            assert.is_false(RA.SeenRecently(seen, 5828, 1300))
            assert.is_false(RA.SeenRecently(seen, 10644, 1100))
        end)
    end)

    describe("RA.Replaces", function()
        it("lets a card in over nothing, a preview, or by the loud and quiet order", function()
            for _, row in ipairs({
                { incoming = "quiet", shown = nil,       want = true },
                { incoming = "quiet", shown = "preview", want = true },
                { incoming = "loud",  shown = nil,       want = true },
                { incoming = "loud",  shown = "preview", want = true },
                { incoming = "loud",  shown = "quiet",   want = true },
                { incoming = "loud",  shown = "loud",    want = true },
                { incoming = "quiet", shown = "loud",    want = false },
                { incoming = "quiet", shown = "quiet",   want = true },
            }) do
                assert.equals(row.want, RA.Replaces(row.incoming, row.shown),
                    row.incoming .. " over " .. tostring(row.shown))
            end
        end)
    end)

    describe("RA.Bearing", function()
        it("points the arrow at the rare, at two facings", function()
            for _, row in ipairs({
                { name = "north, ahead",  facing = 0,      vx = 0.5, vy = 0.4, want = 0 },
                { name = "north, left",   facing = 0,      vx = 0.4, vy = 0.5, want = PI / 2 },
                { name = "north, right",  facing = 0,      vx = 0.6, vy = 0.5, want = -PI / 2 },
                { name = "north, behind", facing = 0,      vx = 0.5, vy = 0.6, want = PI },
                { name = "west, ahead",   facing = PI / 2, vx = 0.4, vy = 0.5, want = 0 },
                { name = "west, left",    facing = PI / 2, vx = 0.5, vy = 0.6, want = PI / 2 },
                { name = "west, right",   facing = PI / 2, vx = 0.5, vy = 0.4, want = -PI / 2 },
                { name = "west, behind",  facing = PI / 2, vx = 0.6, vy = 0.5, want = PI },
            }) do
                local rotation = RA.Bearing(0.5, 0.5, row.vx, row.vy, 1000, 1000, row.facing)
                assertSameAngle(row.want, rotation, row.name)
            end
        end)

        it("measures yards across a map that is not square", function()
            local _, yards = RA.Bearing(0, 0, 0.3, 0.2, 1000, 2000, 0)
            assert.near(500, yards, 1e-9)
        end)

        it("gives nil for any nil input and for a world size of 0", function()
            for i = 1, 7 do
                local args = { 0.5, 0.5, 0.4, 0.4, 1000, 1000, 0 }
                args[i] = nil
                assert.is_nil((RA.Bearing(unpack(args, 1, 7))), "argument " .. i)
            end
            assert.is_nil((RA.Bearing(0.5, 0.5, 0.4, 0.4, 0, 1000, 0)))
            assert.is_nil((RA.Bearing(0.5, 0.5, 0.4, 0.4, 1000, 0, 0)))
        end)
    end)

    describe("RA.ThirdLine", function()
        it("takes the first state that applies", function()
            local drop = { name = "Mark of the Pack Leader" }
            for _, row in ipairs({
                { name = "targeted",            want = "targeted", state = { targeted = true, unitSeen = true } },
                { name = "dead and targeted",   want = "dead",     state = { dead = true, targeted = true } },
                { name = "tapped",              want = "tapped",   state = { tapped = true, unitSeen = true } },
                { name = "tapped and left",     want = "tapped",   state = { tapped = true, left = true } },
                { name = "tapped in combat",    want = "combat",   state = { tapped = true, combat = true } },
                { name = "dead and tapped",     want = "dead",     state = { dead = true, tapped = true } },
                { name = "left",                want = "left",     state = { left = true, unitSeen = true } },
                { name = "left in combat",      want = "left",     state = { left = true, combat = true } },
                { name = "combat with a drop",  want = "combat",   state = { combat = true, drop = drop } },
                { name = "drop while far",      want = "drop",     state = { drop = drop } },
                { name = "far",                 want = "far",      state = {} },
                { name = "unit seen, no drop",  want = "click",    state = { unitSeen = true } },
            }) do
                assert.equals(row.want, RA.ThirdLine(row.state), row.name)
            end
        end)
    end)

    describe("RA.BestDrop", function()
        it("takes quality, then new, then chance", function()
            for _, row in ipairs({
                { name = "quality beats new", want = "blue", loot = {
                    { name = "green", quality = 2, new = true, chance = 50 },
                    { name = "blue", quality = 3, chance = 1 },
                } },
                { name = "new beats chance", want = "new", loot = {
                    { name = "common", quality = 3, chance = 50 },
                    { name = "new", quality = 3, new = true, chance = 1 },
                } },
                { name = "chance decides", want = "likely", loot = {
                    { name = "unlikely", quality = 3, chance = 1 },
                    { name = "likely", quality = 3, chance = 2 },
                } },
            }) do
                assert.equals(row.want, RA.BestDrop(row.loot).name, row.name)
            end
        end)

        it("gives nil for no loot", function()
            assert.is_nil(RA.BestDrop({}))
            assert.is_nil(RA.BestDrop(nil))
        end)
    end)

    describe("RA.PartyAllowed", function()
        it("is true only for the setting on, a loud alert, a party, no combat and no lock", function()
            assert.is_true(RA.PartyAllowed(true, "loud", true, false, false, false))
            for _, row in ipairs({
                { name = "setting off", args = { false, "loud", true, false, false, false } },
                { name = "quiet",       args = { true, "quiet", true, false, false, false } },
                { name = "no group",    args = { true, "loud", false, false, false, false } },
                { name = "raid",        args = { true, "loud", true, true, false, false } },
                { name = "combat",      args = { true, "loud", true, false, true, false } },
                { name = "locked",      args = { true, "loud", true, false, false, true } },
            }) do
                assert.is_false(RA.PartyAllowed(unpack(row.args)), row.name)
            end
        end)
    end)

    describe("RA.PartyLine", function()
        it("drops what is unknown and strips what chat would read as codes", function()
            for _, row in ipairs({
                { name = "full", args = { "Humar the Pridelord", "23", true, 62, 33.4 },
                  want = "Rare: Humar the Pridelord, level 23 elite, at 62.0, 33.4" },
                { name = "not elite", args = { "Mist Howler", "22", false, 10.5, 20 },
                  want = "Rare: Mist Howler, level 22, at 10.5, 20.0" },
                { name = "no level", args = { "Mist Howler", nil, false, 10.5, 20 },
                  want = "Rare: Mist Howler, at 10.5, 20.0" },
                { name = "elite with no level", args = { "Humar", nil, true, 62, 33.4 },
                  want = "Rare: Humar, elite, at 62.0, 33.4" },
                { name = "no position", args = { "Humar", "23", false, nil, nil },
                  want = "Rare: Humar, level 23" },
                { name = "neither", args = { "Humar", nil, false, nil, nil },
                  want = "Rare: Humar" },
                { name = "control characters and pipes", args = { "Hu\nmar|", nil, false, nil, nil },
                  want = "Rare: Humar" },
            }) do
                assert.equals(row.want, RA.PartyLine(unpack(row.args, 1, 5)), row.name)
            end
        end)
    end)
end)
