-- Tier 1: Party Cooldowns' pure rules
-- (Modules/AuraTracking/PartyBuffs/PartyCooldownsRules.lua): which spells a
-- spec shows and for how long, the icon a talent picks, where a teammate's
-- spec comes from, who is inspected next, and which trinkets get a cell.
local L = require("dev.spec._ke_loader")

local function ids(list)
    local out = {}
    for i, entry in ipairs(list) do out[i] = entry.id end
    return out
end

local function entryOf(R, specID, castID, db)
    for _, entry in ipairs(R.SpellList(specID, db or {}, true)) do
        if entry.id == castID then return entry end
    end
end

describe("PartyCooldownsRules.SpellList", function()
    it("puts saved casts first, keeps table order after them, and drops switched-off ones", function()
        local R = L.loadPartyCooldownsRules()
        local cases = {
            { name = "table order", db = {}, want = { 360194, 31224, 5277 } },
            { name = "saved order first", db = { CooldownOrder = { [259] = { 5277 } } },
              want = { 5277, 360194, 31224 } },
            { name = "switched off", db = { CooldownOff = { ["259:31224"] = true } }, want = { 360194, 5277 } },
            { name = "unknown spec", db = {}, spec = 999, want = {} },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, ids(R.SpellList(case.spec or 259, case.db)), case.name)
        end
        assert.are.same({ 360194, 31224, 5277 },
            ids(R.SpellList(259, { CooldownOff = { ["259:31224"] = true } }, true)), "all")
    end)
end)

describe("PartyCooldownsRules lengths", function()
    it("prefers typed seconds, then the spec's talented length, then the base, clamping the typed one", function()
        local R = L.loadPartyCooldownsRules()
        assert.are.same({ 90, 120 }, { entryOf(R, 250, 49028).cd, entryOf(R, 250, 48792).cd })
        local cases = {
            { typed = 75, want = 75 }, { typed = 3, want = 5 }, { typed = 2000, want = 900 },
            { typed = 61.7, want = 61 }, { typed = "abc", want = 90 },
        }
        for _, case in ipairs(cases) do
            local db = { CooldownSeconds = { ["250:49028"] = case.typed } }
            assert.are.equal(case.want, entryOf(R, 250, 49028, db).cd, tostring(case.typed))
        end
    end)
end)

describe("PartyCooldownsRules.ShowID", function()
    it("follows a read talent, falls back to the likely icon, and ignores a swap for another spec", function()
        local R = L.loadPartyCooldownsRules()
        local cases = {
            { name = "taken", spec = 64, cast = 45438, taken = true, want = 414658 },
            { name = "not taken", spec = 64, cast = 45438, taken = false, want = 45438 },
            { name = "unread, likely", spec = 64, cast = 45438, want = 414658 },
            { name = "scoped spec, unread", spec = 66, cast = 31884, want = 389539 },
            { name = "outside the scoped spec", spec = 70, cast = 31884, taken = true, want = 31884 },
            { name = "no swap", spec = 64, cast = 342245, taken = true, want = 342245 },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.ShowID(entryOf(R, case.spec, case.cast), case.spec, case.taken), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.ResolveSpec", function()
    it("takes the first known source and guesses only a single-spec tank or healer", function()
        local R = L.loadPartyCooldownsRules()
        local cases = {
            { name = "player first", s = { player = 72, lib = 71, inspect = 73 }, spec = 72, src = "player" },
            { name = "library before inspect", s = { lib = 71, inspect = 73 }, spec = 71, src = "lib" },
            { name = "inspect", s = { lib = 0, inspect = 73 }, spec = 73, src = "inspect" },
            { name = "tank guess", s = { class = "DRUID", role = "TANK" }, spec = 104, src = "guess" },
            { name = "healer guess", s = { class = "SHAMAN", role = "HEALER" }, spec = 264, src = "guess" },
            { name = "two healer specs", s = { class = "PRIEST", role = "HEALER" } },
            { name = "damage never guessed", s = { class = "WARRIOR", role = "DAMAGER" } },
            { name = "nothing known", s = {} },
        }
        for _, case in ipairs(cases) do
            local spec, src = R.ResolveSpec(case.s)
            assert.are.same({ case.spec, case.src }, { spec, src }, case.name)
        end
    end)
end)

describe("PartyCooldownsRules.NextInspect", function()
    local function member(name, extra)
        local m = { name = name, canInspect = true }
        for key, value in pairs(extra or {}) do m[key] = value end
        return m
    end

    it("asks nothing while the Inspect window is open, in combat, or within two seconds of the last request", function()
        local R = L.loadPartyCooldownsRules()
        local members = { member("a") }
        local cases = {
            { name = "window open", state = { inspectShown = true, now = 10 } },
            { name = "in combat", state = { inCombat = true, now = 10 } },
            { name = "within the gap", state = { now = 10, lastRequest = 8.5 } },
        }
        for _, case in ipairs(cases) do
            assert.is_nil(R.NextInspect(case.state, members), case.name)
        end
        assert.are.equal("a", R.NextInspect({ now = 10, lastRequest = 8 }, members).name)
    end)

    it("skips a member that is done, cannot be inspected or is resting", function()
        local R = L.loadPartyCooldownsRules()
        local members = {
            member("done", { done = true }), member("far", { canInspect = false }),
            member("resting", { waitUntil = 40 }), member("next"),
        }
        assert.are.equal("next", R.NextInspect({ now = 10 }, members).name)
    end)

    it("rests a member for 30 seconds after 12 tries", function()
        local R = L.loadPartyCooldownsRules()
        local m = member("a")
        for _ = 1, 11 do R.CountTry(m, 100) end
        assert.is_nil(m.waitUntil)
        R.CountTry(m, 100)
        assert.are.same({ 0, 130 }, { m.tries, m.waitUntil })
        assert.is_nil(R.NextInspect({ now = 129 }, { m }))
        assert.are.equal(m, R.NextInspect({ now = 130 }, { m }))
    end)
end)

describe("PartyCooldownsRules trinkets", function()
    it("gives a cell to a listed, switched-on trinket with a known length, typed length first, clamped", function()
        local R = L.loadPartyCooldownsRules()
        local db = {
            ListTrinkets = { [111] = { enabled = true }, [222] = { enabled = false }, [333] = { enabled = true } },
            CooldownSeconds = { ["trinket:333"] = 45 },
        }
        local got = R.TrinketEntries({ { item = 1, spell = 111 }, { item = 2, spell = 333 } }, { [1] = 120 }, db)
        assert.are.same({ { 111, 120, 1 }, { 333, 45, 2 } },
            { { got[1].id, got[1].cd, got[1].item }, { got[2].id, got[2].cd, got[2].item } })
        local long = R.TrinketEntries({ { item = 1, spell = 111 } }, { [1] = 1200 }, db)
        assert.are.equal(R.CD_MAX, long[1].cd)
        local dropped = {
            { name = "switched off", slots = { { item = 1, spell = 222 } }, lengths = { [1] = 120 } },
            { name = "not listed", slots = { { item = 1, spell = 444 } }, lengths = { [1] = 120 } },
            { name = "passive", slots = { { item = 1 } }, lengths = { [1] = 120 } },
            { name = "no length", slots = { { item = 1, spell = 111 } }, lengths = {} },
            { name = "empty slots", slots = {}, lengths = {} },
        }
        for _, case in ipairs(dropped) do
            assert.are.same({}, R.TrinketEntries(case.slots, case.lengths, db), case.name)
        end
    end)

    it("reads the use cooldown from a tooltip line", function()
        local R = L.loadPartyCooldownsRules()
        local cases = {
            { text = "Use: Gain 2000 Haste for 20 sec. (2 Min Cooldown)", want = 120 },
            { text = "Use: Shield yourself. (1 Min 30 Sec Cooldown)", want = 90 },
            { text = "Use: Burst (scales with level). (90 Sec Cooldown)", want = 90 },
            { text = "Equip: Your attacks sometimes do more." },
            { text = nil },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.ParseCooldownText(case.text), tostring(case.text))
        end
    end)
end)
