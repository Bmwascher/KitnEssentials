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

describe("PartyCooldownsRules.Feed", function()
    -- A secret answer is a boxed boolean only the injected evaluator opens,
    -- as only the client function can read a real one.
    local function secret(value) return { secret = true, value = value } end
    local function isSecret(v) return type(v) == "table" and v.secret == true end
    local function pick(b, a, c)
        if isSecret(b) then b = b.value end
        if b then return a end
        return c
    end
    local function run(R, reads, shorts)
        local t = R.NewTracker(120, shorts ~= nil)
        R.Clear(t, 0)
        for i, lit in ipairs(reads) do R.Feed(t, lit, shorts and shorts[i], 10 + i, isSecret, pick) end
        return t.slot[t.cur]
    end

    it("stamps only when the buff appears after a read without it", function()
        local R = L.loadPartyCooldownsRules()
        for _, wrap in ipairs({ { "plain", function(v) return v end }, { "secret", secret } }) do
            local name, w = wrap[1], wrap[2]
            local steady = run(R, { w(true), w(true) })
            assert.are.equal(0, steady.v, name .. ": a first read only records")
            local edge = run(R, { w(false), w(true) })
            assert.are.same({ 1, (255 - 12) / 255 }, { edge.v, edge.c }, name .. ": rising edge")
            local proc = run(R, { w(false), w(true) }, { w(false), w(true) })
            assert.are.equal(0, proc.v, name .. ": a proc copy")
        end
    end)
end)

describe("PartyCooldownsRules.Tick", function()
    it("clears a plain slot four seconds past zero and never clears a secret one", function()
        local R = L.loadPartyCooldownsRules()
        local isSecret = function(v) return type(v) == "table" end
        local t = R.NewTracker(120, false)
        R.Clear(t, 0)
        R.StartPlain(t, 10)
        local sl = t.slot[t.cur]
        assert.is_true((R.Tick(t, 133, isSecret)))
        assert.are.equal(1, sl.v)
        local running, changed = R.Tick(t, 134, isSecret)
        assert.are.same({ false, true, 0 }, { running, changed, sl.v })
        local hidden = R.NewTracker(120, false)
        R.Clear(hidden, 0)
        hidden.slot[1].c, hidden.slot[1].v = { secret = true }, { secret = true }
        assert.is_true((R.Tick(hidden, 200, isSecret)))
        assert.is_true(isSecret(hidden.slot[1].v))
    end)
end)

describe("PartyCooldownsRules.DoorVerdict", function()
    it("opens for exact, close or hidden answers and closes for coarse ones or an error", function()
        local R = L.loadPartyCooldownsRules()
        local isSecret = function(v) return type(v) == "table" end
        local exact = function(b, a, c)
            if b then return a end
            return c
        end
        local cases = {
            { name = "exact", eval = exact, want = "exact", open = true },
            -- 4.5e-9 a pass reaches the 7.2e-8 PR-4 measured on a live client.
            { name = "close", eval = function(b, a, c) return exact(b, a, c) + 4.5e-9 end, want = "close", open = true },
            { name = "hidden", eval = function() return { secret = true } end, want = "hidden", open = true },
            { name = "coarse", eval = function(b, a, c) return math.floor(exact(b, a, c) * 100 + 0.5) / 100 end,
              want = "coarse", open = false },
            { name = "error", eval = function() error("refused") end, want = "error", open = false },
            { name = "missing", eval = nil, want = "error", open = false },
        }
        for _, case in ipairs(cases) do
            local verdict = R.DoorVerdict(case.eval, isSecret)
            assert.are.same({ case.want, case.open }, { verdict, R.DoorOpen(verdict) }, case.name)
        end
    end)
end)

describe("PartyCooldownsRules.TakeLoadTry", function()
    it("allows LOAD_TRIES requests per item and no more", function()
        local R = L.loadPartyCooldownsRules()
        local tries, got = {}, {}
        for _ = 1, R.LOAD_TRIES + 1 do got[#got + 1] = R.TakeLoadTry(tries, 111) end
        assert.are.same({ true, true, true, false }, got)
        assert.is_true(R.TakeLoadTry(tries, 222))
    end)
end)

describe("PartyCooldownsRules.TrinketShow", function()
    it("shows an icon only once the row surely leaves its trinket out", function()
        local R = L.loadPartyCooldownsRules()
        local steps = {
            { name = "accepted: new icons wait", show = {}, set = { [1] = true }, accepted = true,
              kept = {}, pending = { [1] = true } },
            { name = "refused: kept while still requested", show = { [1] = true },
              set = { [1] = true, [2] = true }, accepted = false, kept = { [1] = true } },
            { name = "second refusal: intersection, not union", show = { [1] = true },
              set = { [2] = true }, accepted = false, kept = {} },
            { name = "accepted after refusals: waits again", show = {}, set = { [2] = true },
              accepted = true, kept = {}, pending = { [2] = true } },
            { name = "accepted: a shown icon still excluded stays", show = { [1] = true, [2] = true },
              set = { [2] = true }, accepted = true, kept = { [2] = true }, pending = { [2] = true } },
        }
        for _, s in ipairs(steps) do
            local kept, pending = R.TrinketShow(s.show, s.set, s.accepted)
            assert.are.same(s.kept, kept, s.name)
            assert.are.same(s.pending, pending, s.name)
        end
    end)
end)
