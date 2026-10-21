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
-- which needs talent 55 and is not likely taken. Spec 15 lists only cast 7,
-- which starts switched off. Cast 8 has talent mods, a spec-only one for spec
-- 16 and two charge talents; spec 16 lists it paired at 100 s, spec 17
-- unpaired, spec 18 with two charges. Cast 9 has only a charge talent; spec
-- 19 lists it paired at 50 s. TRINKET_BUFFS maps trinket use spell 333 to its
-- buff 334. Spec 20 lists only cast 13, which is hidden in spec 20 while talent
-- 131 is taken.
local DATA = {
    SPELLS = {
        [1] = { kind = "offensive", cd = 120, buffs = { 1 } },
        [2] = { kind = "defensive", cd = 60, buffs = { 2 },
                swap = { id = 20, talents = { [20] = true }, likely = true } },
        [3] = { kind = "defensive", cd = 90, buffs = { 3 },
                swap = { id = 30, talents = { [30] = true }, likely = true, specs = { [10] = true } } },
        [4] = { kind = "defensive", cd = 120, buffs = { 40 } },
        [5] = { kind = "offensive", cd = 60, buffs = { 50 }, needs = { talents = { [55] = true } } },
        [7] = { kind = "offensive", cd = 90, buffs = { 70 }, off = true },
        [8] = { kind = "offensive", cd = 180, buffs = { 80 },
                mods = { { 81, add = -30 }, { 82, pct = -50 }, { spec = 16, add = -60 },
                         { 83, charges = 1 }, { 84, spec = 99, charges = 1 } } },
        [9] = { kind = "defensive", cd = 60, buffs = { 90 }, mods = { { 85, charges = 1 } } },
        [13] = { kind = "offensive", cd = 60, buffs = { 130 },
                 hide = { talents = { [131] = true }, specs = { [20] = true } } },
    },
    RACIALS = {
        { race = "Dwarf", raceID = 3, id = 4 },
    },
    SPECS = {
        [10] = { { 1, 45 }, 2, 3 },
        [11] = { 3 },
        [12] = { 5 },
        [15] = { 7 },
        [16] = { { 8, 100 } },
        [17] = { 8 },
        [18] = { { 8, charges = 2 } },
        [19] = { { 9, 50 } },
        [20] = { 13 },
    },
    ROLE_SPEC = {
        DRUID = { TANK = 10, HEALER = 11 },
        ROGUE = { DAMAGER = 10 },
    },
    TRINKET_BUFFS = { [333] = { 334 } },
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
            { name = "off by default", db = {}, spec = 15, want = {} },
            { name = "off by default, switched on", db = { CooldownOff = { ["15:7"] = false } }, spec = 15, want = { 7 } },
            { name = "unknown spec", db = {}, spec = 999, want = {} },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, ids(R.SpellList(case.spec or 10, case.db)), case.name)
        end
        assert.are.same({ 1, 2, 3 }, ids(R.SpellList(10, { CooldownOff = { ["10:2"] = true } }, true)), "all")
    end)
end)

describe("PartyCooldownsRules.IsOff", function()
    it("takes a saved switch over the data default, and the data default while unset", function()
        local R = loadRules()
        local cases = {
            { name = "saved off", off = { k = true }, spell = {}, want = true },
            { name = "saved on over a default off", off = { k = false }, spell = { off = true }, want = false },
            { name = "unset, default off", off = {}, spell = { off = true }, want = true },
            { name = "unset, no default", off = {}, spell = {}, want = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.IsOff(case.off, "k", case.spell), case.name)
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

    it("skips a member that is done, cannot be inspected, is offline or is resting", function()
        local R = loadRules()
        local members = {
            member("done", { done = true }), member("far", { canInspect = false }),
            member("offline", { offline = true }), member("resting", { waitUntil = 40 }), member("next"),
        }
        assert.are.equal("next", R.NextInspect({ now = 10 }, members).name)
    end)

    it("asks nobody within FOREIGN_GAP seconds of another addon's inspect request", function()
        local R = loadRules()
        local members = { member("a") }
        local cases = {
            { name = "inside the gap", foreignAt = 10.5 - R.FOREIGN_GAP },
            { name = "at the gap", foreignAt = 10 - R.FOREIGN_GAP, want = "a" },
            { name = "no foreign request", want = "a" },
        }
        for _, case in ipairs(cases) do
            local got = R.NextInspect({ now = 10, foreignAt = case.foreignAt }, members)
            assert.are.equal(case.want, got and got.name, case.name)
        end
    end)

    it("rests a member for TRY_WAIT seconds after MAX_TRIES tries, or STALE_TRIES when only stale", function()
        local R = loadRules()
        local cases = {
            { name = "unread", stale = false, cap = R.MAX_TRIES },
            { name = "stale", stale = true, cap = R.STALE_TRIES },
        }
        for _, case in ipairs(cases) do
            local m = member("a")
            for _ = 1, case.cap - 1 do R.CountTry(m, 100, case.stale) end
            assert.is_nil(m.waitUntil, case.name)
            R.CountTry(m, 100, case.stale)
            local back = 100 + R.TRY_WAIT
            assert.are.same({ 0, back }, { m.tries, m.waitUntil }, case.name)
            assert.is_nil(R.NextInspect({ now = back - 1 }, { m }), case.name)
            assert.are.equal(m, R.NextInspect({ now = back }, { m }), case.name)
        end
    end)
end)

describe("PartyCooldownsRules trinkets", function()
    it("gives a cell to a listed, switched-on trinket with a known length, clamped", function()
        local R = loadRules()
        local db = {
            ListTrinkets = { [111] = { enabled = true }, [222] = { enabled = false }, [333] = { enabled = true } },
        }
        local got = R.TrinketEntries({ { item = 1, spell = 111 }, { item = 2, spell = 333 } }, { [1] = 120, [2] = 45 }, db)
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

    it("watches a mapped trinket's buff, and any other trinket's use spell", function()
        local R = loadRules()
        local db = { ListTrinkets = { [111] = { enabled = true }, [333] = { enabled = true } } }
        local got = R.TrinketEntries({ { item = 1, spell = 111 }, { item = 2, spell = 333 } }, { [1] = 120, [2] = 45 }, db)
        assert.are.same({ { 111 }, { 334 } }, { got[1].buffs, got[2].buffs })
    end)

    it("reads the use cooldown from a tooltip line", function()
        local R = loadRules()
        local cases = {
            { text = "Use: Gain 2000 Haste for 20 sec. (2 Min Cooldown)", want = 120 },
            { text = "Use: Shield yourself. (1 Min 30 Sec Cooldown)", want = 90 },
            { text = "Use: Burst (scales with level). (90 Sec Cooldown)", want = 90 },
            { text = "Use: Gain 2000 Haste for 20 sec. (2 |4Min:Min; Cooldown)", want = 120 },
            { text = "Use: Shield yourself. (1 |4Min:Min; 30 |4Sec:Sec; Cooldown)", want = 90 },
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
        local windowed = R.NewTracker(120, false)
        R.ArmFall(windowed, 0, 6)
        local armed = deepest(windowed, { secret(true), secret(false) })
        assert.is_true(armed > 0 and armed <= 2, "windowed sensor: " .. armed)
        -- A charge tracker's stamp is secret, and its finished state is read
        -- back as a secret answer.
        local function past() return true, secret(true) end
        local function deepestCharge(t, reads)
            local most = 0
            for _, prev in ipairs(reads) do
                for _, lit in ipairs(reads) do
                    R.Clear(t, 0)
                    t.primed, t.prev, t.prevShort = true, prev, false
                    t.slot[t.cur].c = { secret = true, value = true, depth = 0 }
                    R.Feed(t, lit, false, 12, isSecret, counting, past, true)
                    local c = t.slot[t.cur].c
                    most = math.max(most, type(c) == "table" and c.depth or 0)
                end
            end
            return most
        end
        local single = deepestCharge(R.NewTracker(120, false, false, 2), { secret(true), secret(false) })
        assert.is_true(single > 0 and single <= 4, "a charge read: " .. single)
        local shorted = deepestCharge(R.NewTracker(120, true, false, 2), { secret(true), secret(false) })
        assert.is_true(shorted > 0 and shorted <= 6, "a charge read with a short sensor: " .. shorted)
        local group = deepestCharge(R.NewTracker(120, false, true, 2), lists)
        assert.is_true(group > 0 and group <= 2 * m + 2, "a charge read, five units: " .. group)
        local ticked = R.NewTracker(120, false, false, 2)
        R.Clear(ticked, 0)
        ticked.slot[ticked.cur].c = { secret = true, value = true, depth = 0 }
        ticked.f1, ticked.f2, ticked.fRead = secret(true), secret(false), true
        R.ChargeTick(ticked, 12, isSecret, counting, past, true)
        local tick = ticked.slot[ticked.cur].c.depth
        assert.is_true(tick > 0 and tick <= 5, "a charge tick: " .. tick)
    end)

    -- A 300-second tracker counts in 2-second codes from its clear at 0.
    local function windowRun(R, reads, armed)
        local t = R.NewTracker(300, false)
        R.Clear(t, 0)
        if armed then R.ArmFall(t, 0, 30) end
        for _, read in ipairs(reads) do R.Feed(t, read[1], nil, read[2], isSecret, pick) end
        local sl = t.slot[t.cur]
        return { sl.v, sl.c }
    end

    it("stamps a fall 30 seconds back only from fallFrom to fallTo, and never without a window", function()
        local R = loadRules()
        local cases = {
            { name = "a second before the window", at = 31, armed = true, want = { 0, 1 } },
            { name = "the window's first second", at = 32, armed = true, want = { 1, (255 - 1) / 255 } },
            { name = "inside the window", at = 40, armed = true, want = { 1, (255 - 5) / 255 } },
            { name = "the window's last second", at = 61, armed = true, want = { 1, (255 - 15) / 255 } },
            { name = "a second after the window", at = 62, armed = true, want = { 0, 1 } },
            { name = "no window", at = 40, armed = false, want = { 0, 1 } },
        }
        for _, wrap in ipairs({ { "plain", function(v) return v end }, { "secret", secret } }) do
            local w = wrap[2]
            for _, case in ipairs(cases) do
                local got = windowRun(R, { { w(true), 5 }, { w(false), case.at } }, case.armed)
                assert.are.same(case.want, got, wrap[1] .. ": " .. case.name)
            end
        end
    end)

    it("takes no fall after a clear in a window armed before it", function()
        local R = loadRules()
        for _, wrap in ipairs({ { "plain", function(v) return v end }, { "secret", secret } }) do
            local w = wrap[2]
            local t = R.NewTracker(300, false)
            R.Clear(t, 0)
            R.ArmFall(t, 0, 30)
            -- A potion list change mid-key: the window's seconds are 32 to 61.
            R.Clear(t, 10)
            R.Feed(t, w(true), nil, 15, isSecret, pick)
            R.Feed(t, w(false), nil, 40, isSecret, pick)
            local sl = t.slot[t.cur]
            assert.are.same({ 0, 1 }, { sl.v, sl.c }, wrap[1])
        end
    end)

    it("still stamps a rise inside the window at the read", function()
        local R = loadRules()
        for _, wrap in ipairs({ { "plain", function(v) return v end }, { "secret", secret } }) do
            local got = windowRun(R, { { wrap[2](false), 35 }, { wrap[2](true), 40 } }, true)
            assert.are.same({ 1, (255 - 20) / 255 }, got, wrap[1])
        end
    end)

    it("takes no rise for CAST_QUIET seconds after a cast stamp, and a clear ends the quiet", function()
        local R = loadRules()
        local q = R.CAST_QUIET
        local cases = {
            { name = "a rise inside the quiet keeps the cast stamp", rise = 10 + q, clear = false,
              want = { 1, (255 - 5) / 255 } },
            { name = "a rise after the quiet stamps", rise = 11 + q, clear = false,
              want = { 1, (255 - math.floor((11 + q) / 2)) / 255 } },
            { name = "a rise after a clear stamps", rise = 12, clear = true, want = { 1, (255 - 6) / 255 } },
        }
        for _, wrap in ipairs({ { "plain", function(v) return v end }, { "secret", secret } }) do
            local w = wrap[2]
            for _, case in ipairs(cases) do
                local t = R.NewTracker(300, false)
                R.Clear(t, 0)
                R.StartCast(t, 10)
                if case.clear then R.Clear(t, 0) end
                R.Feed(t, w(false), nil, case.rise - 1, isSecret, pick)
                R.Feed(t, w(true), nil, case.rise, isSecret, pick)
                local sl = t.slot[t.cur]
                assert.are.same(case.want, { sl.v, sl.c }, wrap[1] .. ": " .. case.name)
            end
        end
    end)

    it("takes no plain rise for a tracker's quiet seconds after a plain start, and leaves hidden reads alone", function()
        local R = loadRules()
        local q = 15
        local plain = function(v) return v end
        -- s wraps the start's two reads, r the rise's two.
        local cases = {
            { name = "a plain rise inside the quiet keeps the start", s = plain, r = plain, quiet = q,
              rise = 10 + q, want = { 1, (255 - 5) / 255 } },
            { name = "a plain rise after the quiet stamps", s = plain, r = plain, quiet = q, rise = 11 + q,
              want = { 1, (255 - math.floor((11 + q) / 2)) / 255 } },
            { name = "no quiet: the next rise stamps", s = plain, r = plain, rise = 10 + q,
              want = { 1, (255 - math.floor((10 + q) / 2)) / 255 } },
            { name = "a hidden start opens no quiet", s = secret, r = plain, quiet = q, rise = 10 + q,
              want = { 1, (255 - math.floor((10 + q) / 2)) / 255 } },
            { name = "a hidden rise inside the quiet still stamps", s = plain, r = secret, quiet = q,
              rise = 10 + q, want = { 1, (255 - math.floor((10 + q) / 2)) / 255 } },
        }
        for _, case in ipairs(cases) do
            local t = R.NewTracker(300, false)
            t.quiet = case.quiet
            R.Clear(t, 0)
            R.Feed(t, case.s(false), nil, 9, isSecret, pick)
            R.Feed(t, case.s(true), nil, 10, isSecret, pick)
            R.Feed(t, case.r(false), nil, case.rise - 1, isSecret, pick)
            R.Feed(t, case.r(true), nil, case.rise, isSecret, pick)
            local sl = t.slot[t.cur]
            assert.are.same(case.want, { sl.v, sl.c }, case.name)
        end
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

describe("PartyCooldownsRules.NextDeriveWait", function()
    it("waits each of DERIVE_WAITS in turn, then no more", function()
        local R = loadRules()
        local got, want = {}, {}
        for tries = 0, #R.DERIVE_WAITS do
            got[#got + 1] = R.NextDeriveWait(tries > 0 and tries or nil) or false
            want[#want + 1] = R.DERIVE_WAITS[tries + 1] or false
        end
        assert.are.same(want, got)
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

describe("PartyCooldownsRules.AfterTalentMisses", function()
    it("retries an unread member once, then keeps the empty answer", function()
        local R = loadRules()
        local first, retry = R.AfterTalentMisses(nil)
        assert.are.same({}, first)
        assert.is_true(retry)
        local second, again = R.AfterTalentMisses(first)
        assert.are.equal(first, second)
        assert.is_false(again)
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

describe("PartyCooldownsRules.GearArrived", function()
    it("refuses a read with no trinket unless the chest or main hand holds an item", function()
        local R = loadRules()
        local cases = {
            { name = "a trinket", items = { nil, 2 }, others = {}, arrived = true },
            { name = "no trinket, a chest", items = {}, others = { 5 }, arrived = true },
            { name = "no trinket, a main hand", items = {}, others = { nil, 16 }, arrived = true },
            { name = "nothing", items = {}, others = {}, arrived = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.arrived, R.GearArrived(case.items, case.others), case.name)
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

describe("PartyCooldownsRules.ActiveSeconds", function()
    it("keeps a summon's active seconds whole and at least one second short of its cooldown", function()
        local R = loadRules()
        local cases = {
            { name = "no active phase", args = { nil, 180 }, want = 0 },
            { name = "fits", args = { 30, 180 }, want = 30 },
            { name = "fraction dropped", args = { 30.7, 180 }, want = 30 },
            { name = "cooldown typed shorter", args = { 30, 20 }, want = 19 },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.ActiveSeconds(case.args[1], case.args[2]), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.GlowWindow", function()
    -- The bar's fill edge sits (t - cd + 1) steps above the inner area's
    -- bottom at elapsed second t, as the gate bar's does. The glow reaches 0.8
    -- sizes either side of the icon's center (the 1.6-size style).
    it("covers the whole glow during the active seconds and none of it after", function()
        local R = loadRules()
        local cases = {
            { size = 16, px = 1, cd = 120, active = 20 },
            { size = 36, px = 0.71, cd = 180, active = 30 },
            { size = 72, px = 1, cd = 90, active = 30 },
            { size = 36, px = 1, cd = 31, active = 30 },
        }
        for _, c in ipairs(cases) do
            local step, low, high = R.GlowWindow(c.size, c.px, c.cd, c.active)
            local center = c.size / 2 - c.px
            local bottom, top = center - 0.8 * c.size, center + 0.8 * c.size
            local function edge(t) return (t - c.cd + 1) * step end
            local name = c.size .. "/" .. c.active
            assert.is_true(edge(0) + high >= top, name .. " first second")
            assert.is_true(edge(c.active - 1) + low <= bottom, name .. " last active second")
            assert.is_true(edge(c.active) + low >= top, name .. " first second after")
        end
    end)
end)

describe("PartyCooldownsRules.StripMargin", function()
    it("keeps a whole quarter of the line plus one blank around each label", function()
        local R = loadRules()
        local cases = {
            { name = "rounds a part pixel up", line = 9, want = 4 },
            { name = "tested font", line = 12, want = 4 },
            { name = "largest font", line = 48, want = 13 },
            { name = "no measure", line = nil, want = 1 },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.StripMargin(case.line), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.Seat", function()
    -- A secret number still has type "number", so the fake is a number: read
    -- as plain it would give a different seat, and a missing guard shows.
    local HIDDEN = 777.3
    local isSecret = function(v) return v == HIDDEN end

    it("keeps the last seat for a hidden center and guesses a quarter before any", function()
        local R = loadRules()
        assert.is_nil(R.Seat(HIDDEN, 12, 1, 768, 0.6, isSecret))
        assert.are.equal(0.125, R.Seat(HIDDEN, 12, 2, 768, nil, isSecret))
    end)

    it("does nothing when the scale is hidden or the line is not laid out", function()
        local R = loadRules()
        assert.is_nil(R.Seat(763, 12, HIDDEN, 768, nil, isSecret))
        assert.is_nil(R.Seat(763, nil, 1, 768, nil, isSecret))
    end)

    it("lands the line a quarter pixel above the grid, rolls up from 0.75, and keeps a seat within a tenth", function()
        local R = loadRules()
        local cases = {
            { name = "lands at a quarter", y = 100.5, want = -0.25 },
            { name = "lands at a quarter, two pixels a unit", y = 100.25, scale = 2, want = -0.125 },
            { name = "rolls at 0.75", y = 100.75, want = 0.5 },
            { name = "seated within tolerance", y = 100.5, seat = -0.2 },
        }
        for _, case in ipairs(cases) do
            local got = R.Seat(case.y, 0, case.scale or 1, 768, case.seat, isSecret)
            if case.want == nil then
                assert.is_nil(got, case.name)
            else
                assert.is_number(got, case.name)
                assert.is_true(math.abs(got - case.want) < 1e-9, case.name)
            end
        end
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
    it("gives a race's racial under its own key only while Racials and its row are on", function()
        local R = loadRules()
        local on = { ShowRacials = true }
        local e = R.MemberRacial("Dwarf", on)
        assert.are.same({ 4, "race:4", 120, { 40 } }, { e.id, e.key, e.cd, e.buffs })
        local cases = {
            { name = "Racials off", race = "Dwarf", db = { ShowRacials = false } },
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
    it("wants a spec for a cooldown cell, a racial the member's race has, or the healer externals box", function()
        local R = loadRules()
        local cases = {
            { name = "class cells", args = { true, false, false, "Human" }, want = true },
            { name = "trinket cells", args = { false, true, false, nil }, want = true },
            { name = "racial of the race", args = { false, false, true, "Dwarf" }, want = true },
            { name = "race with no racial", args = { false, false, true, "Human" }, want = false },
            { name = "race not read", args = { false, false, true, nil }, want = false },
            { name = "Racials off", args = { false, false, false, "Dwarf" }, want = false },
            { name = "the healer box alone", args = { false, false, false, nil, true }, want = true },
        }
        for _, case in ipairs(cases) do
            local a = case.args
            assert.are.equal(case.want, R.SpecWanted(a[1], a[2], a[3], a[4], a[5]), case.name)
        end
    end)
end)

describe("PartyCooldownsRules talent gate", function()
    it("shows a needs row while its talent is taken, hides a hide row in its specs while taken, unread by likely", function()
        local R = loadRules()
        local plain = entryOf(R, 10, 1)
        local gated = entryOf(R, 12, 5)
        local likely = { spell = { needs = { talents = {}, likely = true } } }
        local hidden = entryOf(R, 20, 13)
        local likelyHidden = { spell = { hide = { talents = {}, likely = true, specs = { [20] = true } } } }
        local cases = {
            { name = "no talent needed", entry = plain, taken = nil, want = true },
            { name = "taken", entry = gated, taken = true, want = true },
            { name = "not taken", entry = gated, taken = false, want = false },
            { name = "unread, not likely", entry = gated, taken = nil, want = false },
            { name = "unread, likely", entry = likely, taken = nil, want = true },
            { name = "hide, taken", entry = hidden, taken = true, spec = 20, want = false },
            { name = "hide, not taken", entry = hidden, taken = false, spec = 20, want = true },
            { name = "hide, unread, not likely", entry = hidden, taken = nil, spec = 20, want = true },
            { name = "hide, unread, likely", entry = likelyHidden, taken = nil, spec = 20, want = false },
            { name = "hide, another spec", entry = hidden, taken = true, spec = 21, want = true },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.TalentAllows(case.entry, case.taken, case.spec), case.name)
        end
        assert.are.equal(hidden.spell.hide, R.TalentsFor(20).rules[13], "a hide rule for its spec")
        assert.are.equal(gated.spell.needs, R.TalentsFor(12).rules[5], "a needs row")
        assert.is_not_nil(R.TalentsFor(10).rules[3], "a swap for its spec")
        assert.is_nil(R.TalentsFor(11), "a swap scoped to another spec")
        assert.is_true(R.TalentsFor(16).want[81], "a mod's talent")
    end)
end)

describe("PartyCooldownsRules.TalentsFor box rows", function()
    it("flags the talents a spec's box rows name apart from its own casts', with each row's rule", function()
        -- Spec 20 lists no cast; its box rows give cast 6, which needs talent
        -- 60, and cast 13, whose swap to talent 130 applies to every spec.
        -- Specs 12 and 14 list cast 5, which needs talent 55; spec 12 also
        -- owns box row 7, which needs talent 55 or 77.
        local data = {
            SPELLS = {
                [5] = { kind = "offensive", cd = 60, buffs = { 50 }, needs = { talents = { [55] = true } } },
                [6] = { kind = "external", cd = 180, buffs = { 6 },
                        needs = { talents = { [60] = true }, likely = true } },
                [7] = { kind = "external", cd = 120, buffs = { 7 },
                        needs = { talents = { [55] = true, [77] = true }, likely = true } },
                [13] = { kind = "external", cd = 300, buffs = { 13, 130 },
                         swap = { id = 130, talents = { [130] = true }, likely = false } },
            },
            SPECS = { [12] = { 5 }, [14] = { 5 } },
            BOX_ROWS = {
                { id = 6, class = "DRUID", specs = { [20] = true }, watch = "owner" },
                { id = 13, class = "DRUID", specs = { [20] = true }, watch = "target" },
                { id = 7, class = "MONK", specs = { [12] = true }, watch = "owner" },
            },
        }
        local R = L.loadPartyCooldownsRules(data)
        local box, mixed, own = R.TalentsFor(20), R.TalentsFor(12), R.TalentsFor(14)
        assert.are.same({ false, true }, { box.rows, box.box }, "box rows only")
        assert.are.equal(data.SPELLS[6].needs, box.rules[6], "a box row's needs rule")
        assert.are.equal(data.SPELLS[13].swap, box.rules[13], "a box row's swap")
        assert.are.same({ [60] = true, [130] = true }, box.boxOnly, "every talent box-only")
        assert.are.same({ true, true }, { mixed.rows, mixed.box }, "own casts and a box row")
        assert.are.same({ [77] = true }, mixed.boxOnly, "a talent its own cast names is not box-only")
        assert.are.same({ true, false }, { own.rows, own.box }, "its own casts only")
        assert.are.same({}, own.boxOnly, "no box-only talent")
    end)
end)

describe("PartyCooldownsRules talent read guards", function()
    it("wants a member's talents only for a switched-on part that names one", function()
        local R = loadRules()
        local rowsOnly = { rows = true, box = false, boxOnly = {} }
        local boxOnly = { rows = false, box = true, boxOnly = { [60] = true } }
        local cases = {
            { name = "no talents", class = true, box = true, want = false },
            { name = "own casts, Class Cooldowns on", talents = rowsOnly, class = true, box = false, want = true },
            { name = "own casts, only the box on", talents = rowsOnly, class = false, box = true, want = false },
            { name = "box rows, the box on", talents = boxOnly, class = false, box = true, want = true },
            { name = "box rows, only Class Cooldowns on", talents = boxOnly, class = true, box = false,
              want = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.TalentsWanted(case.talents, case.class, case.box), case.name)
        end
    end)

    it("skips a talent only box rows name while the box is off", function()
        local R = loadRules()
        local talents = { boxOnly = { [77] = true } }
        local cases = {
            { name = "box-only, box off", talent = 77, box = false, want = false },
            { name = "box-only, box on", talent = 77, box = true, want = true },
            { name = "its own cast's, box off", talent = 55, box = false, want = true },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.TalentRead(talents, case.talent, case.box), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.CellLength", function()
    it("counts the talented length once every length talent is read, the listed one until then", function()
        local R = loadRules()
        local paired, unpaired = entryOf(R, 16, 8), entryOf(R, 17, 8)
        local long = { cd = 900, spell = { cd = 900 } }
        local cases = {
            { name = "every length talent read", entry = paired, spec = 16, ranks = { [81] = 1, [82] = 1 }, want = 45 },
            { name = "one of two read", entry = paired, spec = 16, ranks = { [81] = 1 }, want = 100 },
            { name = "none read", entry = paired, spec = 16, want = 100 },
            { name = "unpaired, none read", entry = unpaired, spec = 17, want = 180 },
            { name = "only a charge mod, read", entry = entryOf(R, 19, 9), spec = 19, ranks = { [85] = 1 }, want = 50 },
            { name = "a charge cell over the cap", entry = long, spec = 16, charges = 2, want = R.CHARGE_CD_MAX },
            { name = "a one-charge cell, no cap", entry = long, spec = 16, charges = 1, want = 900 },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.CellLength(case.entry, case.spec, case.ranks, case.charges), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.CellCharges", function()
    it("adds a charge for a charge talent read as taken in its spec, none unread, and caps the count", function()
        local R = loadRules()
        local plain, based = entryOf(R, 16, 8), entryOf(R, 18, 8)
        local cases = {
            { name = "base count from the list", entry = based, ranks = {}, want = 2 },
            { name = "talent taken", entry = plain, ranks = { [83] = 1 }, want = 2 },
            { name = "talent read, not taken", entry = plain, ranks = { [83] = 0 }, want = 1 },
            { name = "talent unread", entry = plain, ranks = {}, want = 1 },
            { name = "talent for another spec", entry = plain, ranks = { [84] = 1 }, want = 1 },
            { name = "a base of two and a talent", entry = based, ranks = { [83] = 1 }, want = R.MAX_CHARGES },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.CellCharges(case.entry, 16, case.ranks), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.Taken", function()
    it("takes a rule when any of its talents is taken, and answers nil only when none is read", function()
        local R = loadRules()
        local rule = { talents = { [91] = true, [92] = true } }
        local cases = {
            { name = "one taken", ranks = { [91] = 0, [92] = 2 }, want = true },
            { name = "all read, none taken", ranks = { [91] = 0, [92] = 0 }, want = false },
            { name = "some read, none taken", ranks = { [91] = 0 }, want = false },
            { name = "none read", ranks = {}, want = nil },
            { name = "no answer", ranks = nil, want = nil },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.Taken(rule, case.ranks), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.TrackerKey", function()
    it("keeps a count across a new length in the same code unit, never across a new unit, charges or buffs", function()
        local R = loadRules()
        local base = { buffs = { 1 }, cd = 120 }
        local cases = {
            { name = "shorter, same unit", e = { buffs = { 1 }, cd = 90 }, same = true },
            { name = "a new unit", from = { buffs = { 1 }, cd = 240 }, e = { buffs = { 1 }, cd = 300 }, same = false },
            { name = "a new charge count", e = { buffs = { 1 }, cd = 120, charges = 2 }, same = false },
            { name = "other buffs", e = { buffs = { 2 }, cd = 120 }, same = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.same, R.TrackerKey(case.from or base) == R.TrackerKey(case.e), case.name)
        end
    end)
end)

describe("PartyCooldownsRules charges", function()
    local function secret(value) return { secret = true, value = value } end
    local function isSecret(v) return type(v) == "table" and v.secret == true end
    local function choose(b, a, c)
        if isSecret(b) then b = b.value end
        if b then return a end
        return c
    end
    local function count(t)
        if t.a0 == 1 then return 0 elseif t.a1 == 1 then return 1 elseif t.a2 == 1 then return 2 end
    end

    it("recharges two charges one after the other on plain reads", function()
        local R = loadRules()
        local t = R.NewTracker(60, false, false, 2)
        R.Clear(t, 0)
        local function read(lit, n) R.Feed(t, lit, nil, n, isSecret, choose, nil) end
        local steps = {}
        read(false, 9)
        read(true, 10)
        steps[#steps + 1] = { "first use", count(t), t.b }
        read(false, 15)
        read(true, 20)
        steps[#steps + 1] = { "second use", count(t), t.b }
        R.ChargeTick(t, 70, isSecret, choose, nil, nil)
        steps[#steps + 1] = { "the first recharge ends", count(t), t.b, R.Left(t, t.slot[t.cur], 70) }
        R.ChargeTick(t, 130, isSecret, choose, nil, nil)
        steps[#steps + 1] = { "the second ends", count(t), t.b }
        assert.are.same({
            { "first use", 1, 0 }, { "second use", 0, 1 }, { "the first recharge ends", 1, 0, 60 },
            { "the second ends", 2, 0 },
        }, steps)
    end)

    it("fills both charges at a key start only on a cell the game resets, KEY_RESET_MIN or more", function()
        local R = loadRules()
        local cases = {
            { name = "a 60-second cell keeps its count", cd = 60, want = { false, 0, 1 } },
            { name = "a 180-second cell is filled", cd = 180, want = { true, 2, 0 } },
        }
        for _, case in ipairs(cases) do
            local t = R.NewTracker(case.cd, false, false, 2)
            R.Clear(t, 0)
            for _, step in ipairs({ { false, 9 }, { true, 10 }, { false, 15 }, { true, 20 } }) do
                R.Feed(t, step[1], nil, step[2], isSecret, choose, nil)
            end
            local cleared = R.KeyStartClear(t, { cd = case.cd }, 25)
            assert.are.same(case.want, { cleared, count(t), t.b }, case.name)
        end
    end)

    it("finds reads unhidden only when no restriction kind that can hide them is active", function()
        local R = loadRules()
        local kinds = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
        local cases = {
            { name = "none active", on = {}, want = true },
            { name = "only Chat active, which hides no read", on = { [5] = true }, want = true },
            { name = "Combat active", on = { [0] = true }, want = false },
            { name = "an answer that errs counts as active", on = { [3] = "error" }, want = false },
            { name = "no enum", on = {}, noEnum = true, want = false },
        }
        for _, case in ipairs(cases) do
            local function isActive(kind)
                if case.on[kind] == "error" then error("refused") end
                return case.on[kind] == true
            end
            local given = kinds
            if case.noEnum then given = nil end
            assert.are.equal(case.want, R.ReadsUnhidden(given, isActive), case.name)
        end
    end)

    it("fills a cell when the restrictions end only when it is a charge cell on hidden state", function()
        local R = loadRules()
        -- want: reset, the current stamp still secret, the count (nil on a
        -- one-charge cell).
        local cases = {
            { name = "a charge cell on plain state keeps its count", charges = 2, hide = false, want = { false, false, 0 } },
            { name = "a charge cell on hidden state is filled", charges = 2, hide = true, want = { true, false, 2 } },
            { name = "a one-charge cell keeps its timer", charges = 1, hide = true, want = { false, true } },
        }
        for _, case in ipairs(cases) do
            local t = R.NewTracker(60, false, false, case.charges)
            R.Clear(t, 0)
            for _, step in ipairs({ { false, 9 }, { true, 10 }, { false, 15 }, { true, 20 } }) do
                R.Feed(t, step[1], nil, step[2], isSecret, choose, nil)
            end
            if case.hide then t.slot[t.cur].c = secret(t.slot[t.cur].c) end
            local cleared = R.HiddenChargeClear(t, 25, isSecret)
            assert.are.same(case.want, { cleared, isSecret(t.slot[t.cur].c), count(t) }, case.name)
        end
    end)

    it("counts a group's second use on another unit while the first unit's buff is still up", function()
        local R = loadRules()
        local t = R.NewTracker(60, false, true, 2)
        R.Clear(t, 0)
        local function read(n, a, b) R.Feed(t, { a, b, n = 2 }, nil, n, isSecret, choose, nil) end
        read(9, false, false)
        read(10, true, false)
        read(12, true, true)
        assert.are.same({ 0, 1 }, { count(t), t.b })
    end)

    it("starts the waiting recharge first when a use lands on the second the running one ends", function()
        local R = loadRules()
        local t = R.NewTracker(60, false, false, 2)
        R.Clear(t, 0)
        local function read(lit, n) R.Feed(t, lit, nil, n, isSecret, choose, nil) end
        for _, step in ipairs({ { false, 9 }, { true, 10 }, { false, 15 }, { true, 20 }, { false, 25 }, { true, 70 } }) do
            read(step[1], step[2])
        end
        assert.are.same({ 0, 1, 60 }, { count(t), t.b, R.Left(t, t.slot[t.cur], 70) })
    end)

    it("times a lost count's use from the read that saw it, a group's per unit", function()
        local R = loadRules()
        local t = R.NewTracker(60, false, true, 2)
        R.Clear(t, 0)
        local function read(n, a, b) return R.Feed(t, { a, b, n = 2 }, nil, n, isSecret, choose, nil) end
        read(9, false, false)
        read(10, true, false)
        t.b = secret(0)
        R.ChargeLose(t)
        local changed = read(12, true, true)
        local sl = t.slot[t.cur]
        assert.are.same({ true, true, 1, 1, 60 }, { changed, t.legacy, sl.v, t.lb, R.Left(t, sl, 12) })
    end)

    it("keeps a use whose charge read errs: one cooldown from that read, and a redraw", function()
        local R = loadRules()
        local t = R.NewTracker(60, false, true, 2)
        R.Clear(t, 0)
        local function boom() error("refused") end
        R.Feed(t, { false, false, n = 2 }, nil, 9, isSecret, choose, nil)
        R.Feed(t, { true, false, n = 2 }, nil, 10, isSecret, choose, nil)
        t.slot[t.cur].c = secret(t.slot[t.cur].c)
        local changed = R.Feed(t, { true, true, n = 2 }, nil, 12, isSecret, choose, boom, true)
        local sl = t.slot[t.cur]
        assert.are.same({ true, true, 1, 1, 60 }, { changed, t.legacy, sl.v, t.lb, R.Left(t, sl, 12) })
    end)

    it("holds a read whose fallback errs as well, so the next read finds the same use", function()
        local R = loadRules()
        local t = R.NewTracker(60, false, true, 2)
        R.Clear(t, 0)
        local function boom() error("refused") end
        local before = { false, false, n = 2 }
        R.Feed(t, before, nil, 9, isSecret, choose, nil)
        local changed = R.Feed(t, { secret(true), secret(false), n = 2 }, nil, 10, isSecret, boom, nil, true)
        local held, lost = t.prev == before, t.legacy
        R.Feed(t, { true, false, n = 2 }, nil, 11, isSecret, choose, nil)
        local sl = t.slot[t.cur]
        assert.are.same({ true, true, true, 1, 1, 60 }, { changed, held, lost, count(t), sl.v, R.Left(t, sl, 11) })
    end)

    it("only records a hidden read until the self-check decides", function()
        local R = loadRules()
        local cases = {
            { name = "undecided", checked = nil, want = { false, 2 } },
            { name = "passed", checked = true, want = { true, 1 } },
        }
        for _, case in ipairs(cases) do
            local t = R.NewTracker(60, false, false, 2)
            R.Clear(t, 0)
            R.Feed(t, false, nil, 9, isSecret, choose, nil, case.checked)
            local changed = R.Feed(t, secret(true), nil, 10, isSecret, choose, nil, case.checked)
            assert.are.same(case.want, { changed, count(t) }, case.name)
        end
    end)

    it("recounts a lost count on plain state at the next tick; an idle read leaves it lost", function()
        local R = loadRules()
        local t = R.NewTracker(60, false, false, 2)
        R.Clear(t, 0)
        R.Feed(t, false, nil, 9, isSecret, choose, nil)
        R.ChargeLose(t)
        local read = R.Feed(t, false, nil, 12, isSecret, choose, nil)
        local lost = t.legacy == true
        local ticked = R.ChargeTick(t, 13, isSecret, choose, nil, nil)
        assert.are.same({ false, true, true, 2 }, { read, lost, ticked, count(t) })
        assert.is_nil(t.legacy)
    end)

    it("finds a read idle only when no unit can have risen, from plain answers", function()
        local R = loadRules()
        local cases = {
            { name = "single, not lit now", prev = secret(true), lit = false, want = true },
            { name = "single, lit before", prev = true, lit = secret(true), want = true },
            { name = "single, a rise", prev = false, lit = true, want = false },
            { name = "single, hidden now after an unlit read", prev = false, lit = secret(true), want = false },
            { name = "group, a second unit rising while the first is lit", multi = true,
                prev = { true, false, n = 2 }, lit = { true, true, n = 2 }, want = false },
            { name = "group, every unit off now or lit before", multi = true,
                prev = { true, false, n = 2 }, lit = { secret(true), false, n = 2 }, want = true },
        }
        for _, case in ipairs(cases) do
            local t = R.NewTracker(60, false, case.multi == true, 2)
            t.prev, t.prevShort = case.prev, nil
            assert.are.equal(case.want, R.ChargeIdle(t, case.lit, nil, isSecret), case.name)
        end
    end)

    it("only records an idle read on hidden state after the verdict, losing no count", function()
        local R = loadRules()
        local t = R.NewTracker(60, false, false, 2)
        R.Clear(t, 0)
        local function unreadable() return false, nil end
        R.Feed(t, secret(true), nil, 9, isSecret, choose, unreadable, true)
        t.slot[t.cur].c = secret(t.slot[t.cur].c)
        local changed = R.Feed(t, false, nil, 12, isSecret, choose, unreadable, true)
        assert.are.same({ false, false }, { changed, t.legacy == true })
    end)

    it("reads a charge tracker as plain only when every value its plain pass reads is plain", function()
        local R = loadRules()
        local cases = {
            { name = "all plain", want = true },
            { name = "a secret digit alpha", field = "a1", want = false },
            { name = "a secret lost-count cover", field = "lb", want = false },
        }
        for _, case in ipairs(cases) do
            local t = R.NewTracker(60, false, false, 2)
            R.Clear(t, 0)
            t.lb = 1
            if case.field then t[case.field] = secret(t[case.field]) end
            assert.are.equal(case.want, R.ChargePlain(t, isSecret), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.CellKey", function()
    it("keeps a count with its entry when a spell before it goes, never across a new code unit", function()
        local R = loadRules()
        local a = { key = "1:10", buffs = { 10 }, cd = 120 }
        local b = { key = "1:20", buffs = { 20 }, cd = 120 }
        local cases = {
            { name = "a spell before it switched off", old = { a, b }, new = { b }, want = { 2 } },
            { name = "the same key across a new code unit",
              old = { { key = "1:10", buffs = { 10 }, cd = 240 } },
              new = { { key = "1:10", buffs = { 10 }, cd = 300 } }, want = { false } },
        }
        for _, case in ipairs(cases) do
            local oldKeys, newKeys = {}, {}
            for i, e in ipairs(case.old) do oldKeys[i] = R.CellKey(e, i) end
            for i, e in ipairs(case.new) do newKeys[i] = R.CellKey(e, i) end
            assert.are.same(case.want, R.MatchKeys(oldKeys, newKeys), case.name)
        end
    end)
end)

describe("PartyCooldownsRules.MatchKeys", function()
    it("finds each key's old index wherever it moved, and gives each old index once", function()
        local R = loadRules()
        local cases = {
            { name = "the first removed", old = { "a", "b" }, new = { "b" }, want = { 2 } },
            { name = "one added before", old = { "b" }, new = { "a", "b" }, want = { false, 1 } },
            { name = "a key repeated", old = { "a" }, new = { "a", "a" }, want = { 1, false } },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, R.MatchKeys(case.old, case.new), case.name)
        end
    end)
end)

describe("PartyCooldownsRules free uses", function()
    local function secret(value) return { secret = true, value = value } end
    local function isSecret(v) return type(v) == "table" and v.secret == true end
    local function choose(b, a, c)
        if isSecret(b) then b = b.value end
        if b then return a end
        return c
    end
    local function count(t)
        if t.a0 == 1 then return 0 elseif t.a1 == 1 then return 1 elseif t.a2 == 1 then return 2 end
    end
    -- A step is { lit, free, lock, n }, or "unprime".
    local function run(R, t, steps, checked)
        for _, step in ipairs(steps) do
            if step == "unprime" then
                t.primed = false
            else
                R.Feed(t, step[1], nil, step[4], isSecret, choose, nil, checked, step[2], step[3])
            end
        end
    end
    local function join(a, b)
        local out = {}
        for _, s in ipairs(a) do out[#out + 1] = s end
        for _, s in ipairs(b) do out[#out + 1] = s end
        return out
    end
    local function chargeCell(R)
        local t = R.NewTracker(20, false, false, 2)
        R.Clear(t, 0)
        return t
    end
    local function plainCell(R)
        local t = R.NewTracker(20, false, false, nil)
        R.Clear(t, 0)
        return t
    end
    -- Two uses from full: no charge left and a second use waiting.
    local USES = {
        { false, false, nil, 9 }, { true, false, nil, 10 }, { false, false, nil, 12 }, { true, false, nil, 13 },
    }

    it("fills a charge cell when the free buff rises in a primed read, on plain answers", function()
        local R = loadRules()
        local cases = {
            { name = "a rise fills both charges", more = { { false, true, nil, 14 } }, want = { 2, 0 } },
            { name = "an unprimed read only records", more = { "unprime", { false, true, nil, 14 } },
              want = { 0, 1 } },
            { name = "an answer lit in both reads keeps the count",
              more = { "unprime", { false, true, nil, 14 }, { false, true, nil, 15 } }, want = { 0, 1 } },
        }
        for _, case in ipairs(cases) do
            local t = chargeCell(R)
            run(R, t, join(USES, case.more))
            assert.are.same(case.want, { count(t), t.b }, case.name)
        end
    end)

    it("fills a charge cell through picks when the free answer is secret", function()
        local R = loadRules()
        local cases = {
            { name = "a secret rise fills both charges", more = { { false, secret(true), nil, 14 } },
              want = { 2, 0 } },
            { name = "a secret answer lit in both reads keeps the count",
              more = { "unprime", { false, secret(true), nil, 14 }, { false, secret(true), nil, 15 } },
              want = { 0, 1 } },
        }
        for _, case in ipairs(cases) do
            local t = chargeCell(R)
            run(R, t, join(USES, case.more))
            assert.are.same(case.want, { count(t), t.b }, case.name)
        end
    end)

    it("keeps a lost count lost through a secret fill, with its timer and cover cleared", function()
        local R = loadRules()
        local t = chargeCell(R)
        run(R, t, USES)
        R.ChargeLose(t)
        run(R, t, { { false, secret(true), nil, 14 } })
        assert.are.same({ true, 0, 0, 0 }, { t.legacy, t.lb, t.slot[1].v, t.slot[2].v })
    end)

    it("spends no charge for a use read while the free buff is up or the lockout rises", function()
        local R = loadRules()
        local cases = {
            { name = "free buff up", steps = { { false, true, nil, 9 }, { true, true, nil, 10 } }, want = 2 },
            { name = "lockout rising", steps = { { false, false, false, 9 }, { true, false, true, 10 } }, want = 2 },
            { name = "lockout up in both reads spends a charge",
              steps = { { false, false, true, 9 }, { true, false, true, 10 } }, want = 1 },
        }
        for _, case in ipairs(cases) do
            local t = chargeCell(R)
            run(R, t, case.steps)
            assert.are.equal(case.want, count(t), case.name)
        end
    end)

    it("starts no timer on a one-charge cell for a use read while the free buff is up", function()
        local R = loadRules()
        local t = plainCell(R)
        run(R, t, { { false, true, nil, 9 }, { true, true, nil, 10 } })
        assert.are.same({ 0, 0 }, { t.slot[1].v, t.slot[2].v })
    end)

    it("keeps every value on the hidden branches when the free answer is secret and lit", function()
        local R = loadRules()
        local hidden = { { secret(false), secret(true), nil, 9 }, { secret(true), secret(true), nil, 10 } }
        local cases = {
            { name = "the charge pick path", make = chargeCell, steps = hidden,
              look = function(t) return { count(t) } end, want = { 2 } },
            { name = "the one-charge Pick block", make = plainCell, steps = hidden,
              look = function(t) return { t.slot[1].v, t.slot[2].v } end, want = { 0, 0 } },
            { name = "the lost count's single timer",
              make = function()
                  local t = chargeCell(R)
                  R.ChargeLose(t)
                  t.lb = secret(0)
                  return t
              end,
              steps = { { false, secret(true), nil, 9 }, { true, secret(true), nil, 10 } },
              look = function(t) return { t.slot[1].v, t.slot[2].v, isSecret(t.lb) and t.lb.value } end,
              want = { 0, 0, 0 } },
        }
        for _, case in ipairs(cases) do
            local t = case.make(R)
            run(R, t, case.steps, true)
            assert.are.same(case.want, case.look(t), case.name)
        end
    end)
end)
