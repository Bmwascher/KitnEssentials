-- Tier 1: Party Cooldowns' pure rules
-- (Modules/AuraTracking/PartyBuffs/PartyCooldownsRules.lua): which spells a
-- spec shows and for how long, the icon a talent picks, where a teammate's
-- spec comes from, who is inspected next, and which trinkets get a cell.
-- The rules run on DATA, never the shipped table, and limits are read from
-- the rules' constants, so a balance or tuning edit fails no case.
local L = require("dev.spec._ke_loader")

-- Spec 10 lists a talented cast, a cast with a swap for every spec and one
-- with a swap scoped to spec 10; spec 11 lists only the scoped one. ROLE_SPEC
-- holds a tank and a healer guess, and a damage cell no guess may use. Cast 4
-- is the racial of the race Dwarf, in no spec list. Spec 12 lists only cast 5,
-- which needs talent 55 and is not likely taken.
local DATA = {
    SPELLS = {
        [1] = { kind = "offensive", cd = 120, buffs = { 1 } },
        [2] = { kind = "defensive", cd = 60, buffs = { 2 },
                swap = { id = 20, talents = { [20] = true }, likely = true } },
        [3] = { kind = "defensive", cd = 90, buffs = { 3 },
                swap = { id = 30, talents = { [30] = true }, likely = true, specs = { [10] = true } } },
        [4] = { kind = "defensive", cd = 120, buffs = { 40 } },
        [5] = { kind = "offensive", cd = 60, buffs = { 50 }, needs = { talents = { [55] = true } } },
    },
    RACIALS = {
        { race = "Dwarf", raceID = 3, id = 4 },
    },
    SPECS = {
        [10] = { { 1, 45 }, 2, 3 },
        [11] = { 3 },
        [12] = { 5 },
    },
    ROLE_SPEC = {
        DRUID = { TANK = 10, HEALER = 11 },
        ROGUE = { DAMAGER = 10 },
    },
}

local function loadRules() return L.loadPartyCooldownsRules(DATA) end

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
        local R = loadRules()
        local cases = {
            { name = "table order", db = {}, want = { 1, 2, 3 } },
            { name = "saved order first", db = { CooldownOrder = { [10] = { 3 } } }, want = { 3, 1, 2 } },
            { name = "switched off", db = { CooldownOff = { ["10:2"] = true } }, want = { 1, 3 } },
            { name = "unknown spec", db = {}, spec = 999, want = {} },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, ids(R.SpellList(case.spec or 10, case.db)), case.name)
        end
        assert.are.same({ 1, 2, 3 }, ids(R.SpellList(10, { CooldownOff = { ["10:2"] = true } }, true)), "all")
    end)
end)

describe("PartyCooldownsRules lengths", function()
    it("prefers typed seconds, then the spec's talented length, then the base, clamping the typed one", function()
        local R = loadRules()
        assert.are.same({ 45, 60 }, { entryOf(R, 10, 1).cd, entryOf(R, 10, 2).cd })
        local cases = {
            { typed = 75, want = 75 }, { typed = R.CD_MIN - 2, want = R.CD_MIN },
            { typed = R.CD_MAX + 1100, want = R.CD_MAX }, { typed = 61.7, want = 61 },
            { typed = "abc", want = 45 },
        }
        for _, case in ipairs(cases) do
            local db = { CooldownSeconds = { ["10:1"] = case.typed } }
            assert.are.equal(case.want, entryOf(R, 10, 1, db).cd, tostring(case.typed))
        end
    end)
end)

describe("PartyCooldownsRules.ShowID", function()
    it("follows a read talent, falls back to the likely icon, and ignores a swap for another spec", function()
        local R = loadRules()
        local cases = {
            { name = "taken", spec = 10, cast = 2, taken = true, want = 20 },
            { name = "not taken", spec = 10, cast = 2, taken = false, want = 2 },
            { name = "unread, likely", spec = 10, cast = 2, want = 20 },
            { name = "scoped spec, unread", spec = 10, cast = 3, want = 30 },
            { name = "outside the scoped spec", spec = 11, cast = 3, taken = true, want = 3 },
            { name = "no swap", spec = 10, cast = 1, taken = true, want = 1 },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.ShowID(entryOf(R, case.spec, case.cast), case.spec, case.taken), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.ResolveSpec", function()
    it("takes the first known source and guesses only a single-spec tank or healer", function()
        local R = loadRules()
        local cases = {
            { name = "player first", s = { player = 72, lib = 71, inspect = 73 }, spec = 72, src = "player" },
            { name = "library before inspect", s = { lib = 71, inspect = 73 }, spec = 71, src = "lib" },
            { name = "inspect", s = { lib = 0, inspect = 73 }, spec = 73, src = "inspect" },
            { name = "tank guess", s = { class = "DRUID", role = "TANK" }, spec = 10, src = "guess" },
            { name = "healer guess", s = { class = "DRUID", role = "HEALER" }, spec = 11, src = "guess" },
            { name = "no single spec for the role", s = { class = "PRIEST", role = "HEALER" } },
            { name = "damage never guessed", s = { class = "ROGUE", role = "DAMAGER" } },
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

    it("asks nothing while an inspect view is open, in combat, or within INSPECT_GAP of the last request", function()
        local R = loadRules()
        local members = { member("a") }
        local cases = {
            { name = "window open", state = { inspectShown = true, now = 10 } },
            { name = "talent view inspecting", state = { talentsInspecting = true, now = 10 } },
            { name = "in combat", state = { inCombat = true, now = 10 } },
            { name = "within the gap", state = { now = 10, lastRequest = 10.5 - R.INSPECT_GAP } },
        }
        for _, case in ipairs(cases) do
            assert.is_nil(R.NextInspect(case.state, members), case.name)
        end
        assert.are.equal("a", R.NextInspect({ now = 10, lastRequest = 10 - R.INSPECT_GAP }, members).name)
    end)

    it("skips a member that is done, cannot be inspected or is resting", function()
        local R = loadRules()
        local members = {
            member("done", { done = true }), member("far", { canInspect = false }),
            member("resting", { waitUntil = 40 }), member("next"),
        }
        assert.are.equal("next", R.NextInspect({ now = 10 }, members).name)
    end)

    it("rests a member for TRY_WAIT seconds after MAX_TRIES tries", function()
        local R = loadRules()
        local m = member("a")
        for _ = 1, R.MAX_TRIES - 1 do R.CountTry(m, 100) end
        assert.is_nil(m.waitUntil)
        R.CountTry(m, 100)
        local back = 100 + R.TRY_WAIT
        assert.are.same({ 0, back }, { m.tries, m.waitUntil })
        assert.is_nil(R.NextInspect({ now = back - 1 }, { m }))
        assert.are.equal(m, R.NextInspect({ now = back }, { m }))
    end)
end)

describe("PartyCooldownsRules trinkets", function()
    it("gives a cell to a listed, switched-on trinket with a known length, typed length first, clamped", function()
        local R = loadRules()
        local db = {
            ListTrinkets = { [111] = { enabled = true }, [222] = { enabled = false }, [333] = { enabled = true } },
            CooldownSeconds = { ["trinket:333"] = 45 },
        }
        local got = R.TrinketEntries({ { item = 1, spell = 111 }, { item = 2, spell = 333 } }, { [1] = 120 }, db)
        assert.are.same({ { 111, 120, 1 }, { 333, 45, 2 } },
            { { got[1].id, got[1].cd, got[1].item }, { got[2].id, got[2].cd, got[2].item } })
        local long = R.TrinketEntries({ { item = 1, spell = 111 } }, { [1] = R.CD_MAX + 300 }, db)
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
        local R = loadRules()
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
        local R = loadRules()
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

    it("stamps a group tracker when some member's buff appears and none was up at the read before", function()
        local R = loadRules()
        local F, T = false, true
        local function group(reads, w)
            local t = R.NewTracker(120, false, true)
            R.Clear(t, 0)
            for i, answers in ipairs(reads) do
                local list = { n = #answers }
                for j, lit in ipairs(answers) do
                    if j == 1 then list[j] = w(lit) else list[j] = lit end
                end
                R.Feed(t, list, nil, 10 + i, isSecret, pick)
            end
            local sl = t.slot[t.cur]
            return { sl.v, sl.c }
        end
        local first = (255 - 12) / 255
        local cases = {
            { name = "a first read only records", reads = { { T, F, F } }, want = { 0, 1 } },
            { name = "rising edge", reads = { { F, F, F }, { F, T, F } }, want = { 1, first } },
            { name = "another member while one stays up",
              reads = { { F, F, F }, { T, F, F }, { T, T, F } }, want = { 1, first } },
            { name = "one falls as another rises",
              reads = { { F, F, F }, { T, F, F }, { F, T, F } }, want = { 1, first } },
        }
        for _, wrap in ipairs({ { "plain", function(v) return v end }, { "secret", secret } }) do
            for _, case in ipairs(cases) do
                assert.are.same(case.want, group(case.reads, wrap[2]), wrap[1] .. ": " .. case.name)
            end
        end
    end)

    it("passes the kept stamp through at most two evaluations per watched unit", function()
        local R = loadRules()
        local function counting(b, a, c)
            local out = pick(b, a, c)
            return { depth = (type(out) == "table" and out.depth or 0) + 1 }
        end
        local function deepest(t, lists)
            local most = 0
            for _, prev in ipairs(lists) do
                for _, lit in ipairs(lists) do
                    R.Clear(t, 0)
                    t.primed, t.prev = true, prev
                    t.slot[t.cur].c = { depth = 0 }
                    R.Feed(t, lit, nil, 12, isSecret, counting)
                    local c = t.slot[t.cur].c
                    most = math.max(most, type(c) == "table" and c.depth or 0)
                end
            end
            return most
        end
        local m, lists = 5, {}
        for bits = 0, 2 ^ m - 1 do
            local list = { n = m }
            for j = 1, m do list[j] = secret(math.floor(bits / 2 ^ (j - 1)) % 2 == 1) end
            lists[#lists + 1] = list
        end
        local five = deepest(R.NewTracker(120, false, true), lists)
        assert.is_true(five > 0 and five <= 2 * m, "five units: " .. five)
        local one = deepest(R.NewTracker(120, false), { secret(true), secret(false) })
        assert.is_true(one > 0 and one <= 2, "one sensor: " .. one)
    end)
end)

describe("PartyCooldownsRules.Tick", function()
    it("clears a plain slot LINGER seconds past zero and never clears a secret one", function()
        local R = loadRules()
        local isSecret = function(v) return type(v) == "table" end
        local t = R.NewTracker(120, false)
        R.Clear(t, 0)
        R.StartPlain(t, 10)
        local sl = t.slot[t.cur]
        -- Started at 10, the 120-second slot reaches zero at 130.
        local cleared = 130 + R.LINGER
        assert.is_true((R.Tick(t, cleared - 1, isSecret)))
        assert.are.equal(1, sl.v)
        local running, changed = R.Tick(t, cleared, isSecret)
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
        local R = loadRules()
        local isSecret = function(v) return type(v) == "table" end
        local exact = function(b, a, c)
            if b then return a end
            return c
        end
        local cases = {
            { name = "exact", eval = exact, want = "exact", open = true },
            -- 4.5e-9 a pass adds up to 7.2e-8, the drift of a live client.
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
        local R = loadRules()
        local tries, got, want = {}, {}, {}
        for i = 1, R.LOAD_TRIES + 1 do
            got[i] = R.TakeLoadTry(tries, 111)
            want[i] = i <= R.LOAD_TRIES
        end
        assert.are.same(want, got)
        assert.is_true(R.TakeLoadTry(tries, 222))
    end)
end)

describe("PartyCooldownsRules.TrinketShow", function()
    it("shows an icon only once the row surely leaves its trinket out", function()
        local R = loadRules()
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
            { name = "accepted, nothing excluded: nothing waits", show = { [2] = true }, set = {},
              accepted = true, kept = {} },
        }
        for _, s in ipairs(steps) do
            local kept, pending = R.TrinketShow(s.show, s.set, s.accepted)
            assert.are.same(s.kept, kept, s.name)
            assert.are.same(s.pending, pending, s.name)
        end
    end)
end)

describe("PartyCooldownsRules.GearEventCounts", function()
    it("ignores a gear event in a key, right after a read, and after repeated same reads until the rest", function()
        local R = loadRules()
        local quiet, rest, spent = 10 + R.GEAR_QUIET, 10 + R.TRY_WAIT, R.MAX_SAME_READS
        local cases = {
            { name = "in a key", args = { true, quiet, 10, 0 }, want = false },
            { name = "within the quiet time", args = { false, quiet - 1, 10, 0 }, want = false },
            { name = "at the end of the quiet time", args = { false, quiet, 10, 0 }, want = true },
            { name = "same reads spent, before the rest", args = { false, rest - 1, 10, spent }, want = false },
            { name = "same reads spent, at the rest", args = { false, rest, 10, spent }, want = true },
            { name = "never read", args = { false, 10, nil, 0 }, want = true },
        }
        for _, case in ipairs(cases) do
            local a = case.args
            assert.are.equal(case.want, R.GearEventCounts(a[1], a[2], a[3], a[4]), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.BuildEventCounts", function()
    it("ignores a teammate's spec or talent event inside a running key, never your own", function()
        local R = loadRules()
        local cases = {
            { name = "teammate in a key", inKey = true, want = false },
            { name = "teammate outside a key", inKey = false, want = true },
            { name = "you in a key", inKey = true, isPlayer = true, want = true },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.BuildEventCounts(case.inKey, case.isPlayer), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.TrinketReadStands", function()
    it("lets a read with an empty slot stand only once a second read agrees", function()
        local R = loadRules()
        local cases = {
            { name = "both slots, first read", items = { 1, 2 }, stands = true, same = false },
            { name = "empty slot, first read", items = { 1 }, stands = false, same = false },
            { name = "empty slot, agrees", prev = { 1 }, items = { 1 }, stands = true, same = true },
            { name = "empty slot, differs", prev = { 2 }, items = { 1 }, stands = false, same = false },
        }
        for _, case in ipairs(cases) do
            local stands, same = R.TrinketReadStands(case.prev, case.items)
            assert.are.same({ case.stands, case.same }, { stands, same }, case.name)
        end
    end)
end)

describe("PartyCooldownsRules.ResetsAtKeyStart", function()
    it("resets a class spell counted at KEY_RESET_MIN seconds or more, never a trinket", function()
        local R = loadRules()
        local threshold = R.KEY_RESET_MIN
        local cases = {
            { name = "class spell at the threshold", entry = { cd = threshold }, want = true },
            { name = "class spell under it", entry = { cd = threshold - 1 }, want = false },
            { name = "trinket over it", entry = { cd = threshold + 30, trinket = true }, want = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.ResetsAtKeyStart(case.entry), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.TalentsMoved", function()
    it("drops a talent answer only for a new talent string, or when either message has none", function()
        local R = loadRules()
        local cases = {
            { name = "sent again unchanged", prev = "AAA", talents = "AAA", want = false },
            { name = "changed", prev = "AAA", talents = "BBB", want = true },
            { name = "message without one", prev = "AAA", want = true },
            { name = "none stored", talents = "AAA", want = true },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.TalentsMoved(case.prev, case.talents), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.StartLoop", function()
    it("starts a preview sample cooling with its loop seconds left, again each time it restarts", function()
        local R = loadRules()
        local t = R.NewTracker(120, false)
        t.loop = 74
        R.StartLoop(t, 1000)
        local first = { R.Left(t, t.slot[t.cur], 1000), t.slot[t.cur].v }
        local again = 1000 + t.loop + R.LINGER
        R.StartLoop(t, again)
        assert.are.same({ { 74, 1 }, { 74, 1 } }, { first, { R.Left(t, t.slot[t.cur], again), t.slot[t.cur].v } })
    end)
end)

describe("PartyCooldownsRules.LibKey", function()
    it("keys a member of another realm by name-realm only, never by the bare name", function()
        local R = loadRules()
        local cases = {
            { name = "your realm", args = { "Sam" }, want = "Sam" },
            { name = "empty realm", args = { "Sam", "" }, want = "Sam" },
            { name = "another realm", args = { "Sam", "Other" }, want = "Sam-Other" },
            { name = "no name", args = { nil, "Other" } },
            { name = "realm not a string", args = { "Sam", 5 } },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.LibKey(case.args[1], case.args[2]), case.name)
        end
    end)
end)

describe("PartyCooldownsRules racials", function()
    it("gives a race's racial under its own key only while Show Racials and its row are on", function()
        local R = loadRules()
        local on = { ShowRacials = true }
        local e = R.MemberRacial("Dwarf", on)
        assert.are.same({ 4, "race:4", 120, { 40 } }, { e.id, e.key, e.cd, e.buffs })
        local typed = { ShowRacials = true, CooldownSeconds = { ["race:4"] = 90 } }
        assert.are.equal(90, R.MemberRacial("Dwarf", typed).cd, "typed seconds")
        local cases = {
            { name = "Show Racials off", race = "Dwarf", db = { ShowRacials = false } },
            { name = "race with no racial", race = "Human", db = on },
            { name = "race not read", race = nil, db = on },
            { name = "row off", race = "Dwarf", db = { ShowRacials = true, CooldownOff = { ["race:4"] = true } } },
        }
        for _, case in ipairs(cases) do
            assert.is_nil(R.MemberRacial(case.race, case.db), case.name)
        end
        assert.is_true(R.RacialEntry(4, { CooldownOff = { ["race:4"] = true } }, true).off, "editor list")
    end)
end)

describe("PartyCooldownsRules.SpecWanted", function()
    it("wants a spec for a cooldown cell, or for a racial the member's race has", function()
        local R = loadRules()
        local cases = {
            { name = "class cells", args = { true, false, false, "Human" }, want = true },
            { name = "trinket cells", args = { false, true, false, nil }, want = true },
            { name = "racial of the race", args = { false, false, true, "Dwarf" }, want = true },
            { name = "race with no racial", args = { false, false, true, "Human" }, want = false },
            { name = "race not read", args = { false, false, true, nil }, want = false },
            { name = "Show Racials off", args = { false, false, false, "Dwarf" }, want = false },
        }
        for _, case in ipairs(cases) do
            local a = case.args
            assert.are.equal(case.want, R.SpecWanted(a[1], a[2], a[3], a[4]), case.name)
        end
    end)
end)

describe("PartyCooldownsRules talent gate", function()
    it("shows a row that needs a talent while it is taken, and unread only when likely", function()
        local R = loadRules()
        local plain = entryOf(R, 10, 1)
        local gated = entryOf(R, 12, 5)
        local likely = { spell = { needs = { talents = {}, likely = true } } }
        local cases = {
            { name = "no talent needed", entry = plain, taken = nil, want = true },
            { name = "taken", entry = gated, taken = true, want = true },
            { name = "not taken", entry = gated, taken = false, want = false },
            { name = "unread, not likely", entry = gated, taken = nil, want = false },
            { name = "unread, likely", entry = likely, taken = nil, want = true },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.TalentAllows(case.entry, case.taken), case.name)
        end
        assert.are.equal(gated.spell.needs, R.TalentsFor(12)[5], "a needs row")
        assert.is_not_nil(R.TalentsFor(10)[3], "a swap for its spec")
        assert.is_nil(R.TalentsFor(11), "a swap scoped to another spec")
    end)
end)

describe("PartyCooldownsRules.OwnTaken", function()
    it("answers taken or not taken only from a plain spellbook answer, else nil", function()
        local R = loadRules()
        local needs = DATA.SPELLS[5].needs
        local swap = DATA.SPELLS[2].swap
        local cases = {
            { name = "needs, known", rule = needs, known = { [55] = true }, want = true },
            { name = "needs, not known", rule = needs, known = { [55] = false }, want = false },
            { name = "needs, unread", rule = needs, known = {}, want = nil },
            { name = "swap, overridden", rule = swap, override = 20, known = {}, want = true },
            { name = "swap, other override", rule = swap, override = 2, known = {}, want = false },
            { name = "swap, nothing read", rule = swap, known = {}, want = nil },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.OwnTaken(case.rule, case.override, case.known), case.name)
        end
    end)
end)
