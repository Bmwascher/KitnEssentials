-- Tier 1: Kings' Rest wave core (Modules/DungeonTools/DungeonTimers/Trash/TrashKingsRest.lua).
-- Plain owner records, snapshots, possibility sets and times. The providers
-- are small fakes that record their calls; no event, timer or cache is
-- modeled.

local helpers = require("dev.spec._helpers")

local function loadCore()
    _G.KitnEssentials = _G.KitnEssentials or {}
    local KE = {}
    helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/TrashInference.lua", KE)
    helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/TrashKingsRest.lua", KE)
    return KE.TrashKingsRest, KE.TrashInference
end

describe("DungeonTrash Kings' Rest wave core", function()
    local KR, TI
    setup(function() KR, TI = loadCore() end)

    local WAVE = { [101] = true, [102] = true }

    -- A fresh plate generation: its owner record carries the snapshot, the
    -- recovery set and the compatible rows the fake providers return.
    local function plate(name, fields)
        local o = { name = name, live = true, pending = {},
            obs = { level = 91, power = 1, hasCreatureFamily = false, rows = { [101] = true } } }
        for k, v in pairs(fields or {}) do o[k] = v end
        if o.unjudged then o.pending = nil end
        return o
    end

    local function newEnv()
        local env = { familyGate = true, waveRows = WAVE, resolved = {}, refreshed = {}, summaries = {} }
        function env.holds(o) return o.live == true end
        function env.resolve(o)
            env.resolved[#env.resolved + 1] = o.name
            env.summaries[o.name] = KR.SummaryFor(o) or false
        end
        function env.refresh(o)
            env.refreshed[#env.refreshed + 1] = o.name
            if o.afterRefresh then o.pending = o.afterRefresh end
        end
        function env.state(o) return o.obs, o.pending end
        function env.compatible(obs) return obs and obs.rows or {} end
        return env
    end

    local function started(at)
        local st = KR.New()
        KR.Start(st, at or -10)
        return st
    end

    local function decisions(owners)
        local out = {}
        for i, o in ipairs(owners) do out[i] = o.krDecision or "none" end
        return out
    end

    it("fresh plates added within the join window form one batch", function()
        local cases = {
            { name = "a leader and four companions 0.39 s later", adds = { 0, 0.39, 0.39, 0.39, 0.39 },
              classes = { "opened", "joined", "joined", "joined", "joined" } },
            { name = "a later member does not extend the window", adds = { 0, 0.4, 0.8 },
              classes = { "opened", "joined", "late" } },
        }
        for _, c in ipairs(cases) do
            local st, env = started(), newEnv()
            local classes = {}
            for i, at in ipairs(c.adds) do
                classes[i] = (KR.OnAdd(st, plate("p" .. i), at, true, env))
            end
            assert.same(c.classes, classes, c.name)
        end

        local st, env = started(), newEnv()
        local existing = plate("existing", { obs = { level = 90, power = 1, rows = { [101] = true } } })
        local _, gen = KR.OnAdd(st, plate("a"), 0, true, env)
        KR.OnAdd(st, plate("b"), 0.39, true, env)
        KR.JoinClose(st, gen, env)
        assert.equals("ready", KR.ReadyCheck(st, gen, env))
        assert.is_nil(existing.krDecision)
        assert.is_false(st.batch.summary.groupHasLevel90)
    end)

    it("join close releases fewer than two members, counting unjudged and pending ones", function()
        local cases = {
            { members = { {} }, phase = "released", resolved = { "p1" } },
            { members = { {}, { unjudged = true } }, phase = "waiting", resolved = {} },
            { members = { {}, { pending = { "level" } } }, phase = "waiting", resolved = {} },
        }
        for i, c in ipairs(cases) do
            local st, env = started(), newEnv()
            local gen
            for j, fields in ipairs(c.members) do
                local _, g = KR.OnAdd(st, plate("p" .. j, fields), (j - 1) * 0.1, true, env)
                gen = gen or g
            end
            assert.equals(c.phase, KR.JoinClose(st, gen, env), "row " .. i)
            assert.equals(c.phase, KR.JoinClose(st, gen, env), "row " .. i)
            assert.same(c.resolved, env.resolved, "row " .. i)
        end
    end)

    it("holds a member from its add and leaves its cast records alone in every outcome", function()
        local outcomes = {
            { name = "granted", rows = { [101] = true, [137989] = true }, want = "granted" },
            { name = "excluded", rows = { [137989] = true }, want = "excluded" },
            { name = "released by a member's removal", rows = { [101] = true }, remove = true, want = "released" },
        }
        for _, c in ipairs(outcomes) do
            local st, env = started(), newEnv()
            local castState = { records = { { kind = "cast", eligible = true } },
                pendingAdvance = { provenance = "fresh" }, latest = { cueConsumed = true } }
            local records, advance, latest = castState.records, castState.pendingAdvance, castState.latest
            local a = plate("a", { obs = { level = 91, power = 1, hasCreatureFamily = false, rows = c.rows },
                runtime = { castState = castState } })
            local b = plate("b")
            local _, gen = KR.OnAdd(st, a, 0, true, env)
            assert.is_true(KR.HoldsIdentity(a), c.name)
            KR.OnAdd(st, b, 0.2, true, env)
            assert.equals("waiting", KR.JoinClose(st, gen, env), c.name)
            assert.is_true(KR.HoldsIdentity(a) and KR.RefusesAdoption(a), c.name)
            assert.same({}, env.resolved, c.name)
            if c.remove then
                b.live = false
                assert.is_true(KR.MemberGone(st, b, env), c.name)
                assert.is_true(KR.RecordRemoval(st, b, 0.6, b.obs, nil, b.obs.rows), c.name)
                assert.equals(1, #st.history, c.name)
            else
                KR.ReadyCheck(st, gen, env)
            end
            assert.equals(c.want, a.krDecision, c.name)
            assert.is_false(KR.HoldsIdentity(a), c.name)
            assert.equals(records, castState.records, c.name)
            assert.equals(1, #records, c.name)
            assert.equals(advance, castState.pendingAdvance, c.name)
            assert.equals(latest, castState.latest, c.name)
            assert.is_true(latest.cueConsumed, c.name)
        end
    end)

    it("new: writes removal entries and takes immutable captures at enrollment", function()
        local env = newEnv()
        local st = started()
        assert.is_true(KR.RecordRemoval(st, plate("u"), 1, { level = 91 }, nil, { [101] = true }))
        assert.is_true(KR.RecordRemoval(st, plate("n"), 1, nil, nil, nil))
        assert.is_false(KR.RecordRemoval(st, plate("e"), 1, { level = 92 }, nil, {}))
        assert.is_true(KR.RecordRemoval(st, plate("r"), 1, { level = 91 }, 555, { [101] = true }))
        assert.same({ { set = { [101] = true }, removedAt = 1 }, { unknown = true, removedAt = 1 },
            { set = { [101] = true, [555] = true }, removedAt = 1 } }, st.history)

        local deaths = started()
        local first, second = plate("first"), plate("second")
        assert.is_true(KR.RecordRemoval(deaths, first, 2, first.obs, nil, first.obs.rows))
        KR.MarkDied(second)
        assert.is_false(KR.RecordRemoval(deaths, second, 3, second.obs, nil, second.obs.rows))
        assert.equals(1, #deaths.history)

        -- A replacement, in handler order: the old owner is dead, nothing is
        -- overdue, its joining batch is released, its entry is written, and
        -- the fresh plate opens the next batch holding that entry.
        local rep = started()
        local old = plate("old")
        local _, gen = KR.OnAdd(rep, old, 10, true, env)
        old.live = false
        KR.ApplyOverdueClose(rep, 10.25, env)
        assert.is_true(KR.MemberGone(rep, old, env))
        assert.is_true(KR.RecordRemoval(rep, old, 10.25, old.obs, nil, old.obs.rows))
        local fresh = plate("fresh")
        local class, nextGen = KR.OnAdd(rep, fresh, 10.25, true, env)
        assert.equals("opened", class)
        assert.is_true(nextGen > gen)
        assert.equals(rep.history[1], fresh.krCapture.entries[1])
        assert.same({}, env.resolved)
        local died = plate("died")
        KR.MarkDied(died)
        assert.is_false(KR.RecordRemoval(rep, died, 10.3, died.obs, nil, died.obs.rows))

        local ends = started(0)
        for _, at in ipairs({ 4.75, 5, 10 }) do KR.RecordRemoval(ends, plate("w"), at, {}, 7, nil) end
        local m = plate("m")
        KR.OnAdd(ends, m, 10, true, env)
        KR.RecordRemoval(ends, plate("w"), 10.25, {}, 7, nil)
        local captured = {}
        for i, e in ipairs(m.krCapture.entries) do captured[i] = e.removedAt end
        assert.same({ 5, 10 }, captured)
        assert.is_false(m.krCapture.unknown)

        local over = started(0)
        local early = plate("early")
        for k = 0, 16 do KR.RecordRemoval(over, plate("w"), 10 + k * 0.125, {}, 7, nil) end
        KR.OnAdd(over, early, 12, true, env)
        local before = early.krCapture.entries
        for k = 17, 24 do KR.RecordRemoval(over, plate("w"), 10 + k * 0.125, {}, 7, nil) end
        assert.equals(24, #over.history)
        assert.equals(15, over.incompleteUntil)
        local atEdge, after = plate("edge"), plate("after")
        KR.OnAdd(over, atEdge, 15, true, env)
        KR.OnAdd(over, after, 15.25, true, env)
        assert.is_true(atEdge.krCapture.unknown)
        assert.is_false(after.krCapture.unknown)
        assert.equals(before, early.krCapture.entries)
        assert.equals(17, #early.krCapture.entries)
        assert.equals(10, early.krCapture.entries[1].removedAt)
        assert.is_false(early.krCapture.unknown)

        local restart = started(100)
        local s1, s2 = plate("s1"), plate("s2")
        KR.OnAdd(restart, s1, 105, true, env)
        KR.OnAdd(restart, s2, 105.25, true, env)
        assert.is_true(s1.krCapture.unknown)
        assert.is_false(s2.krCapture.unknown)
        KR.RecordRemoval(restart, plate("w"), 106, {}, 7, nil)
        KR.ResetBatch(restart, env)
        assert.equals(1, #restart.history)
        assert.equals(105, restart.incompleteUntil)
        KR.Stop(restart, env)
        KR.Start(restart, 200)
        assert.same({}, restart.history)
        assert.equals(205, restart.incompleteUntil)
    end)

    it("new: judges a member's return status from its capture and settled rows", function()
        local shared = { set = { [101] = true }, removedAt = 1 }
        local apart = { set = { [102] = true }, removedAt = 1 }
        local unknown = { unknown = true, removedAt = 1 }
        local rows = { [101] = true }
        local cases = {
            { "an empty capture after incompleteUntil", { entries = {} }, "clear" },
            { "a known, permanently incompatible entry", { entries = { apart } }, "clear" },
            { "a known entry sharing a row", { entries = { apart, shared } }, "possible-return" },
            { "an unknown entry", { entries = { unknown } }, "possible-return" },
            { "added at or before incompleteUntil", { entries = {}, unknown = true }, "unknown-history" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c[3], KR.MemberStatus(c[2], rows), c[1])
        end

        -- A context-rejected row stays permanently compatible, so an overlap
        -- on it alone is still a possible return.
        local traits = { [102] = { dungeonKey = "S", schema = "named", identity = {
            level = 91, power = 1, bossEncounter = true, roomNames = { "Elsewhere" }, hasCastSpell = false } } }
        local seen = { level = 91, power = 1, unitClassification = "elite", sawCastStart = true }
        local compatible = TI.IdentityCompatibleRows(seen, "S", { traits = traits })
        assert.equals("possible-return", KR.MemberStatus({ entries = { apart } }, compatible))

        -- An entry that shared only the partial reads at the add is clear
        -- against the settled snapshot at the ready check.
        local st, env = started(), newEnv()
        KR.RecordRemoval(st, plate("gone"), -0.25, {}, nil, { [102] = true })
        local a = plate("a", { pending = { "level" }, obs = { power = 1, rows = { [101] = true, [102] = true } } })
        local _, gen = KR.OnAdd(st, a, 0, true, env)
        KR.OnAdd(st, plate("b"), 0.1, true, env)
        assert.equals("possible-return", KR.MemberStatus(a.krCapture, a.obs.rows))
        KR.JoinClose(st, gen, env)
        a.pending = {}
        a.obs = { level = 91, power = 1, hasCreatureFamily = false, rows = { [101] = true } }
        assert.equals("ready", KR.ReadyCheck(st, gen, env))
        assert.equals("granted", a.krDecision)

        local neutral = {
            { "a known level other than 90 with the gate off", { level = 91 }, false, true },
            { "family read false", { level = 91, hasCreatureFamily = false }, true, true },
            { "level 90", { level = 90, hasCreatureFamily = false }, true, false },
            { "family unknown with the gate on", { level = 91 }, true, false },
            { "family read true", { level = 91, hasCreatureFamily = true }, true, false },
            { "level unknown", { hasCreatureFamily = false }, true, false },
        }
        for _, c in ipairs(neutral) do
            assert.equals(c[4], KR.StrictlyNeutral(c[2], c[3]), c[1])
        end
    end)

    it("the ready check runs in order and leaves no member held", function()
        local apart = { level = 91, power = 1, hasCreatureFamily = false, rows = { [102] = true } }
        local nonWave = { level = 91, power = 1, hasCreatureFamily = false, rows = { [137989] = true } }
        local cases = {
            { name = "a refresh settles a member whose early reads missed a field",
              members = { {}, { pending = { "level" }, afterRefresh = {} } }, refreshed = { "p2" },
              phase = "ready", decisions = { "granted", "granted" },
              check = function(_, _, env) assert.is_table(env.summaries.p1) end },
            { name = "a member still pending after its refresh releases, never excluded",
              members = { {}, { pending = { "unitClassification" }, obs = { level = 91, power = 1, rows = {} } } },
              refreshed = { "p2" }, phase = "released", decisions = { "released", "released" } },
            { name = "an unjudged member releases", members = { {}, { unjudged = true } }, refreshed = { "p2" },
              phase = "released", decisions = { "released", "released" } },
            { name = "a settled non-wave member is excluded; an unknown or temporary rejection stays",
              members = { {}, { obs = { level = 91, power = 1, hasCreatureFamily = false,
                  rows = { [101] = true, [137989] = true } } }, { obs = nonWave } },
              phase = "ready", decisions = { "granted", "granted", "excluded" }, reasons = { nil, nil, "non-wave" } },
            { name = "a possible return that is not strictly neutral releases every member", history = { [102] = true },
              members = { {}, { obs = { level = 90, power = 1, hasCreatureFamily = false, rows = { [102] = true } } } },
              phase = "released", decisions = { "released", "released" } },
            { name = "unknown history releases, even for strictly neutral members", unknownHistory = true,
              members = { {}, {} }, phase = "released", decisions = { "released", "released" } },
            { name = "a strictly neutral possible return is excluded alone", history = { [101] = true },
              members = { { obs = apart }, { obs = apart }, {} }, phase = "ready",
              decisions = { "granted", "granted", "excluded" }, reasons = { nil, nil, "strictly-neutral" },
              check = function(owners, st)
                  assert.same(KR.Summary({ owners[1].obs, owners[2].obs, owners[3].obs }, true), st.batch.summary)
              end },
            { name = "the minimum-two rule runs after the neutral exclusion", history = { [101] = true },
              members = { { obs = apart }, {} }, phase = "released", decisions = { "released", "excluded" },
              reasons = { nil, "strictly-neutral" } },
            { name = "a possible return already excluded as non-wave releases nothing", history = { [137989] = true },
              members = { {}, {}, { obs = nonWave } }, phase = "ready",
              decisions = { "granted", "granted", "excluded" }, reasons = { nil, nil, "non-wave" } },
        }
        for _, c in ipairs(cases) do
            local st, env = started(c.unknownHistory and -1 or -10), newEnv()
            if c.history then KR.RecordRemoval(st, plate("gone"), -0.25, {}, nil, c.history) end
            local owners, gen = {}, nil
            for i, fields in ipairs(c.members) do
                owners[i] = plate("p" .. i, fields)
                local _, g = KR.OnAdd(st, owners[i], (i - 1) * 0.1, true, env)
                gen = gen or g
            end
            KR.JoinClose(st, gen, env)
            assert.equals(c.phase, KR.ReadyCheck(st, gen, env), c.name)
            assert.same(c.refreshed or {}, env.refreshed, c.name)
            for i, o in ipairs(owners) do
                assert.equals(c.decisions[i], o.krDecision, c.name .. " p" .. i)
                assert.equals(c.reasons and c.reasons[i], o.krReason, c.name .. " p" .. i)
            end
            assert.equals(c.phase == "ready", st.batch.summary ~= nil, c.name)
            if c.check then c.check(owners, st, env) end
            assert.equals("opened", (KR.OnAdd(st, plate("next"), 5, true, env)), c.name)
        end
    end)

    it("a member that settles between join close and the ready check counts as settled", function()
        local st, env = started(), newEnv()
        local a, b = plate("a"), plate("b", { pending = { "level" } })
        local _, gen = KR.OnAdd(st, a, 0, true, env)
        KR.OnAdd(st, b, 0.3, true, env)
        assert.equals("waiting", KR.JoinClose(st, gen, env))
        b.pending = {}
        assert.equals("ready", KR.ReadyCheck(st, gen, env))
        assert.same({}, env.refreshed)
        assert.equals("granted", b.krDecision)
    end)

    it("orders batches on the add timeline and never changes a decision", function()
        local timelines = {
            { name = "a late plate while waiting", adds = { 0, 0.2, 0.75 },
              classes = { "opened", "joined", "late" }, decisions = { "held", "held", "none" }, resolved = {} },
            { name = "a lone leader, then a pair", adds = { 0, 0.75, 0.8 },
              classes = { "opened", "opened", "joined" }, decisions = { "released", "held", "held" },
              resolved = { "p1" } },
        }
        for _, c in ipairs(timelines) do
            for _, timerFirst in ipairs({ true, false }) do
                local label = c.name .. (timerFirst and ", timer first" or ", overdue close by the add")
                local st, env = started(), newEnv()
                local owners, classes, firstGen, closed = {}, {}, nil, false
                for i, at in ipairs(c.adds) do
                    if timerFirst and at > 0.5 and not closed then
                        KR.JoinClose(st, firstGen, env)
                        closed = true
                    end
                    owners[i] = plate("p" .. i)
                    local class, gen = KR.OnAdd(st, owners[i], at, true, env)
                    classes[i] = class
                    firstGen = firstGen or gen
                end
                KR.JoinClose(st, firstGen, env)
                assert.same(c.classes, classes, label)
                assert.same(c.decisions, decisions(owners), label)
                assert.same(c.resolved, env.resolved, label)
            end
        end

        for _, phase in ipairs({ "joining", "waiting" }) do
            local st, env = started(), newEnv()
            local a, b, c3 = plate("a"), plate("b"), plate("c")
            local _, gen = KR.OnAdd(st, a, 0, true, env)
            KR.OnAdd(st, b, 0.1, true, env)
            KR.OnAdd(st, c3, 0.2, true, env)
            if phase == "waiting" then KR.JoinClose(st, gen, env) end
            b.live, c3.live = false, false
            assert.is_true(KR.MemberGone(st, b, env), phase)
            assert.same({ "released", "released", "released" }, decisions({ a, b, c3 }), phase)
            assert.same({ "a" }, env.resolved, phase)
            assert.equals("opened", (KR.OnAdd(st, plate("d"), 0.4, true, env)), phase)
        end

        local stopping, stopEnv = started(), newEnv()
        local s1, s2 = plate("s1"), plate("s2")
        KR.OnAdd(stopping, s1, 0, true, stopEnv)
        KR.OnAdd(stopping, s2, 0.1, true, stopEnv)
        s1.live, s2.live = false, false
        KR.Stop(stopping, stopEnv)
        assert.same({ "released", "released" }, decisions({ s1, s2 }))
        assert.same({}, stopEnv.resolved)

        local st, env = started(), newEnv()
        local a, b = plate("a"), plate("b")
        local x = plate("x", { obs = { level = 91, power = 1, hasCreatureFamily = false, rows = { [137989] = true } } })
        local _, gen = KR.OnAdd(st, a, 0, true, env)
        KR.OnAdd(st, b, 0.1, true, env)
        KR.OnAdd(st, x, 0.2, true, env)
        KR.JoinClose(st, gen, env)
        KR.ReadyCheck(st, gen, env)
        local done = st.batch
        local frozen = done.summary
        assert.is_false(KR.MemberGone(st, a, env))
        KR.RecordRemoval(st, a, 1, a.obs, 101, a.obs.rows)
        assert.equals("opened", (KR.OnAdd(st, plate("c"), 2, true, env)))
        assert.is_nil((KR.OnAdd(st, a, 2.1, true, env)))
        KR.ResetBatch(st, env)
        assert.same({ "granted", "granted", "excluded" }, decisions({ a, b, x }))
        assert.equals(frozen, done.summary)
        assert.equals("ready", done.phase)
    end)

    it("a released, excluded or unbatched plate is not filtered by the summary", function()
        local batch = { summary = { groupHasLevel90 = false, groupHasCreatureFamily = false,
            groupHasLevel90Power0 = false } }
        local traits = {
            [101] = { identity = { groupHasLevel90 = true, groupHasCreatureFamily = false, groupHasLevel90Power0 = false } },
            [137989] = { identity = { level = 90, power = 1 } },
        }
        local function traitOf(npcID) return traits[npcID] end
        local candidates = { { npcID = 101 }, { npcID = 137989 } }
        for _, decision in ipairs({ "released", "excluded", "held", "none" }) do
            local owner = { krDecision = decision ~= "none" and decision or nil, krBatch = batch }
            local kept, removed = KR.ApplySummary(candidates, KR.SummaryFor(owner), traitOf)
            assert.equals(candidates, kept, decision)
            assert.is_false(removed, decision)
        end
        local kept, removed = KR.ApplySummary(candidates,
            KR.SummaryFor({ krDecision = "granted", krBatch = batch }), traitOf)
        assert.same({ { npcID = 137989 } }, kept)
        assert.is_true(removed)
    end)

    it("the summary keeps a room row only when all three flags match, false included", function()
        local summary = { groupHasLevel90 = true, groupHasCreatureFamily = false, groupHasLevel90Power0 = false }
        local cases = {
            { { groupHasLevel90 = true, groupHasCreatureFamily = false, groupHasLevel90Power0 = false }, true },
            { { groupHasLevel90 = false, groupHasCreatureFamily = false, groupHasLevel90Power0 = false }, false },
            { { groupHasLevel90 = true, groupHasCreatureFamily = true, groupHasLevel90Power0 = false }, false },
            { { groupHasLevel90 = true, groupHasCreatureFamily = false, groupHasLevel90Power0 = true }, false },
        }
        for i, c in ipairs(cases) do
            assert.equals(c[2], KR.SummaryKeeps(c[1], summary), "row " .. i)
        end
        assert.same({ groupHasLevel90 = true, groupHasCreatureFamily = false, groupHasLevel90Power0 = true },
            KR.Summary({ { level = 90, power = 0 }, { level = 91, power = 1, hasCreatureFamily = false } }, true))
        local gateOff = KR.Summary({ { level = 91, hasCreatureFamily = true } }, false)
        assert.same({ groupHasLevel90 = false, groupHasLevel90Power0 = false }, gateOff)
        assert.is_true(KR.SummaryKeeps(
            { groupHasLevel90 = false, groupHasCreatureFamily = true, groupHasLevel90Power0 = false }, gateOff))
    end)

    it("the summary never removes a row that is not room-scoped", function()
        local summaries = {
            { groupHasLevel90 = true, groupHasCreatureFamily = true, groupHasLevel90Power0 = true },
            { groupHasLevel90 = false, groupHasCreatureFamily = false, groupHasLevel90Power0 = false },
        }
        for i, s in ipairs(summaries) do
            assert.is_true(KR.SummaryKeeps({ level = 90, power = 1, isLieutenant = false }, s), "row " .. i)
            assert.is_true(KR.SummaryKeeps(nil, s), "row " .. i)
        end
    end)

    it("marks a summary-only resolve wave-derived until a resolve without the summary agrees", function()
        local cases = {
            { "resolved only because the summary removed a candidate", nil, 101, nil, true, true },
            { "the summary removed one, but the same NPC resolves without it", nil, 101, 101, true, false },
            { "a cast verifying its lone candidate keeps the mark", true, 101, nil, false, true },
            { "a re-derivation without the summary to the same NPC clears it", true, 101, 101, false, false },
            { "no summary involvement leaves it unset", nil, 101, nil, false, false },
            { "an unresolved runtime carries no mark", true, nil, nil, true, false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c[6], KR.WaveDerivedAfter(c[2], c[3], c[4], c[5]), c[1])
        end
    end)

    it("leaving the room ends the batch generation, releases held members and keeps the history", function()
        local st, env = started(), newEnv()
        KR.RecordRemoval(st, plate("gone"), 0, {}, 7, nil)
        local a = plate("a")
        local _, gen = KR.OnAdd(st, a, 0.25, true, env)
        KR.ResetBatch(st, env)
        assert.equals("released", a.krDecision)
        assert.same({ "a" }, env.resolved)
        assert.is_nil(KR.JoinClose(st, gen, env))
        assert.is_nil(KR.ReadyCheck(st, gen, env))
        assert.equals(1, #st.history)
        assert.is_nil((KR.OnAdd(st, plate("outside"), 0.5, false, env)))
        local _, nextGen = KR.OnAdd(st, plate("b"), 0.5, true, env)
        assert.is_true(nextGen > gen)
    end)
end)
