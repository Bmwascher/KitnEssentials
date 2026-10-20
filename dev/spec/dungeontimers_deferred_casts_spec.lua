-- Pure-state cases for cast-matched rows, post-forecast waits and the Soon
-- display decision. Plain values and injected time; no frames, no events.
local loader = require("dev.spec._ke_loader")

describe("DungeonTimers deferred casts", function()
    local State
    local TF = "timeline-finished"

    before_each(function()
        State = loader.loadDungeonTimerState()
    end)

    local function contract(extra)
        local result = {
            kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only",
            stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
        }
        for key, value in pairs(extra or {}) do result[key] = value end
        return result
    end

    local function binding(castDuration, extra)
        local data = { [9001] = { timerPolicy = "explicit",
            spells = { [100] = { castDuration = castDuration, timerSource = contract(extra) } } } }
        local timers = State.BuildBindings(data).timers[9001]
        return timers and timers[100]
    end

    -- Refusal contract: nil plus a lowercase reason string, never an error.
    local function assertRefusal(value, reason, label)
        assert.is_nil(value, label)
        assert.equal("string", type(reason), label)
        assert.equal(reason, string.lower(reason), label)
    end

    -- A fresh store per occurrence, so cases cannot share epochs or labels.
    local function start(b, label, remaining, now)
        local store = State.New()
        State.AdmitOwner(store, "boss", 9001)
        local instance = State.Start(store, "boss", label, b, remaining, remaining, now, true)
        return instance, store
    end

    it("admits castMatch, waitAfter and soonOnHold only in their valid shapes", function()
        local ruby = binding(2, { anchor = TF, castMatch = { spells = { 381602, 381605 }, within = 5 }, soonOnHold = true })
        assert.same({ spells = { [381602] = true, [381605] = true }, within = 5 }, ruby.castMatch)
        assert.is_true(ruby.soonOnHold)
        local hunting = binding(2, { castMatch = { spells = { 269232 }, endpoint = "cast-end" } })
        assert.same({ spells = { [269232] = true }, endpoint = "cast-end", curated = 2 }, hunting.castMatch)
        assert.same({ spells = { [7] = true } }, binding(2, { castMatch = { spells = { 7 } } }).castMatch)
        local freshMeat = binding(0, { waitAfter = 5, pullReceipt = true })
        assert.equal(5, freshMeat.waitAfter)
        assert.is_nil(binding(2, { anchor = TF }).castMatch)

        local spells = { 7 }
        local refusals = {
            { "castMatch not a table", 2, { castMatch = true } },
            { "no spells", 2, { castMatch = { spells = {} } } },
            { "five spells", 2, { castMatch = { spells = { 1, 2, 3, 4, 5 } } } },
            { "duplicate spell", 2, { castMatch = { spells = { 7, 7 } } } },
            { "fractional spell", 2, { castMatch = { spells = { 7.5 } } } },
            { "zero spell", 2, { castMatch = { spells = { 0 } } } },
            { "string spell", 2, { castMatch = { spells = { "7" } } } },
            { "sparse spells", 2, { castMatch = { spells = { [1] = 7, [3] = 8 } } } },
            { "unknown castMatch field", 2, { castMatch = { spells = spells, delay = 1 } } },
            { "zero castDuration", 0, { castMatch = { spells = spells } } },
            { "anchored without within", 2, { anchor = TF, castMatch = { spells = spells } } },
            { "zero within", 2, { anchor = TF, castMatch = { spells = spells, within = 0 } } },
            { "within over five", 2, { anchor = TF, castMatch = { spells = spells, within = 5.5 } } },
            { "within without anchor", 2, { castMatch = { spells = spells, within = 5 } } },
            { "misspelled endpoint", 2, { castMatch = { spells = spells, endpoint = "end" } } },
            { "endpoint on an anchored row", 2,
              { anchor = TF, castMatch = { spells = spells, within = 5, endpoint = "cast-end" } } },
            { "castMatch with castConfirm", 2,
              { anchor = TF, castConfirm = "boss-cast-start", castMatch = { spells = spells, within = 5 } } },
            { "castMatch with holdOverlapping", 2,
              { anchor = TF, holdOverlapping = true, castMatch = { spells = spells, within = 5 } } },
            { "castMatch with pausedStop", 2,
              { anchor = TF, pausedStop = "retire", castMatch = { spells = spells, within = 5 } } },
            { "castMatch with queueAfter", 2,
              { queueAfter = { parent = 200, delay = 1 }, castMatch = { spells = spells } } },
            { "castMatch with canceledStop", 2,
              { anchor = TF, canceledStop = { stage = 1, within = 0.5 }, castMatch = { spells = spells, within = 5 } } },
            { "castMatch with retainEarlyFinished", 2,
              { anchor = TF, retainEarlyFinished = true, castMatch = { spells = spells, within = 5 } } },
            { "castMatch with suppressConcurrentRestart", 2,
              { anchor = TF, suppressConcurrentRestart = { from = 30, duration = 10 },
                castMatch = { spells = spells, within = 5 } } },
            { "castMatch with replacement", 2,
              { anchor = TF, replacement = { from = 30, duration = 10 }, castMatch = { spells = spells, within = 5 } } },
            { "castMatch with pullReceipt", 2, { pullReceipt = true, castMatch = { spells = spells } } },
            { "castMatch with waitAfter", 2, { waitAfter = 5, castMatch = { spells = spells } } },
            { "waitAfter with queueAfter", 0, { waitAfter = 5, queueAfter = { parent = 200, delay = 1 } } },
            { "zero waitAfter", 0, { waitAfter = 0 } },
            { "waitAfter over five", 0, { waitAfter = 6 } },
            { "anchored waitAfter", 0, { anchor = TF, waitAfter = 5 } },
            { "waitAfter with castConfirm", 0, { castConfirm = "boss-cast-start", waitAfter = 5 } },
            { "soonOnHold not true", 2, { anchor = TF, soonOnHold = "yes" } },
            { "soonOnHold without anchor", 2, { soonOnHold = true } },
            { "soonOnHold with holdOverlapping", 2, { anchor = TF, holdOverlapping = true, soonOnHold = true } },
        }
        for _, case in ipairs(refusals) do
            assert.is_nil(binding(case[2], case[3]), case[1])
        end
    end)

    it("refuses a cast-matched row as a sequel parent or ender, a forecast-gate row, a queue parent or a shield parent", function()
        local matched = { castDuration = 2, timerSource = contract({ anchor = TF, castMatch = { spells = { 7 }, within = 5 } }) }
        local plain = { castDuration = 2, timerSource = contract({ anchor = TF }) }
        local cases = {
            { name = "sequel parent",
              enc = { spells = { [100] = matched,
                  [101] = { castDuration = 1, timerSource = { kind = "Sequel", parent = 100, after = 0 } } } },
              installed = function(b) return b.sequels[9001] end },
            { name = "cue ender",
              enc = { spells = { [100] = matched, [102] = plain },
                  phaseCues = { leap = { name = "Leap", iconOverride = 1,
                      source = { kind = "Sequel", parent = 102, after = 0 }, duration = 3, endsOnAnchor = 100 } } },
              installed = function(b) return b.sequels[9001] end },
            { name = "forecast gate",
              enc = { spells = { [100] = matched },
                  phaseCues = { gate = { name = "Gate", iconOverride = 1,
                      source = { kind = "Message", key = 55 }, duration = 3, hidesForecasts = { 100 } } } },
              installed = function(b) return b.forecastGates[9001] end },
            { name = "queue parent",
              enc = { spells = { [100] = matched,
                  [101] = { castDuration = 1,
                      timerSource = contract({ anchor = TF, queueAfter = { parent = 100, delay = 1 } }) } } },
              installed = function(b) return b.queues[9001] end },
            { name = "shield parent",
              enc = { spells = { [100] = matched }, shields = { { parent = 100, baseAmount = 10, timeout = 5 } } },
              installed = function(b) return b.shields[9001] end },
        }
        for _, case in ipairs(cases) do
            case.enc.timerPolicy = "explicit"
            local bindings = State.BuildBindings({ [9001] = case.enc })
            assert.is_not_nil(bindings.timers[9001] and bindings.timers[9001][100], case.name)
            assert.is_nil(case.installed(bindings), case.name)
        end
    end)

    it("offers a cast wait only when each allowed spell reads as not secret on some boss unit", function()
        local spells = { [1] = true, [2] = true }
        local function answer(spellId, value) return { spellId = spellId, answer = value } end
        assert.is_true(State.SelectWait(spells,
            { answer(1, "readable"), answer(2, "secret"), answer(1, "secret"), answer(2, "readable") }))
        local cases = {
            { "no boss unit", {} },
            { "one spell secret everywhere", { answer(1, "readable"), answer(2, "secret") } },
            { "one spell unknown", { answer(1, "readable"), answer(2, "unknown") } },
        }
        for _, case in ipairs(cases) do
            local selected, reason = State.SelectWait(spells, case[2])
            assertRefusal(selected, reason, case[1])
        end
    end)

    it("takes the cast times only from a START its unit's current cast corroborates", function()
        local spells = { [7] = true }
        assert.same({ 99.5, 101.5 }, { State.CastTimesFromEvidence(spells, 7, 40, 7, 40, 99500, 101500, 100) })
        assert.same({ 100.05, 102 }, { State.CastTimesFromEvidence(spells, 7, 40, 7, 40, 100050, 102000, 100) })
        local refusals = {
            { "spell not allowed", 8, 40, 8, 40, 99500, 101500 },
            { "no START spell", nil, 40, 7, 40, 99500, 101500 },
            { "snapshot names another spell", 7, 40, 8, 40, 99500, 101500 },
            { "snapshot on another cast bar", 7, 40, 7, 41, 99500, 101500 },
            { "no public cast bar", 7, nil, 7, nil, 99500, 101500 },
            { "unreadable start time", 7, 40, 7, 40, nil, 101500 },
            { "end not after start", 7, 40, 7, 40, 99500, 99500 },
            { "cast already over", 7, 40, 7, 40, 98000, 100000 },
            { "start ahead of the clock", 7, 40, 7, 40, 100200, 102000 },
        }
        for _, case in ipairs(refusals) do
            local value, reason = State.CastTimesFromEvidence(spells, case[2], case[3], case[4], case[5],
                case[6], case[7], 100)
            assertRefusal(value, reason, case[1])
        end
    end)

    it("gives a cast only to the one eligible occurrence that allows its spell, until its own expiry", function()
        local matched = binding(2, { castMatch = { spells = { 7 } } })
        local inst = start(matched, "occ", 10, 0)
        assert.is_false(State.IsCastMatchEligible(inst, 9.8))
        assert.is_true(State.IsCastMatchEligible(inst, 9.9))
        assert.equal(inst, (State.SelectCastOccurrence({ inst }, 7, 10, 10)))
        local early = start(matched, "early", 10, 0)
        State.Anchor(early, 9)
        assert.is_true(State.IsCastMatchEligible(early, 9))
        local paused, pausedStore = start(matched, "paused", 10, 0)
        State.Pause(pausedStore, "boss", "paused", 9.5)
        local closed = start(matched, "closed", 10, 0)
        State.NoteCastMatchStop(closed, "canceled")
        local confirmed = start(matched, "confirmed", 10, 0)
        confirmed.confirmed = true
        local cases = {
            { name = "paused", list = { paused }, spell = 7 },
            { name = "closed", list = { closed }, spell = 7 },
            { name = "confirmed", list = { confirmed }, spell = 7 },
            { name = "other spell", list = { inst }, spell = 8 },
            { name = "two eligible occurrences", list = { inst, early }, spell = 7 },
        }
        for _, case in ipairs(cases) do
            local found, reason = State.SelectCastOccurrence(case.list, case.spell, 10, 10)
            assertRefusal(found, reason, case.name)
        end

        -- The occurrence's own expiry decision ends eligibility, before any retirement callback runs.
        local waiting = binding(2, { anchor = TF, castMatch = { spells = { 7 }, within = 5 } })
        local anchored = start(waiting, "anchored", 10, 0)
        State.Anchor(anchored, 10)
        local waited = start(waiting, "waited", 10, 0)
        State.Anchor(waited, 10)
        State.BeginCastWait(waited)
        local held = start(waiting, "held", 10, 0)
        State.BeginHold(held, 3)
        local deadlines = {
            { name = "unanchored estimate", inst = start(matched, "estimate", 10, 0), open = 11.9, shut = 12 },
            { name = "anchored estimate", inst = anchored, open = 11.9, shut = 12 },
            { name = "cast wait", inst = waited, open = 14.9, shut = 15 },
            { name = "hold", inst = held, open = 13.4, shut = 13.5 },
            { name = "pending hold resolution", inst = start(waiting, "pending", 10, 0), open = 11.9, shut = 12 },
        }
        for _, case in ipairs(deadlines) do
            assert.is_true(State.IsCastMatchEligible(case.inst, case.open), case.name)
            assert.is_false(State.IsCastMatchEligible(case.inst, case.shut), case.name)
        end
    end)

    it("admits only a cast that started within the occurrence", function()
        local matched = binding(2, { castMatch = { spells = { 7 } } })
        -- Forecast zero 10, stop tolerance 0.15: eligible from 9.85, so admitted from 9.7.
        local cases = {
            { name = "inside the forecast bound", castStart = 9.75, admitted = true },
            { name = "before the forecast bound", castStart = 9.6, admitted = false },
            { name = "inside an early anchor's bound", anchor = 5, castStart = 4.9, admitted = true },
            { name = "before an early anchor's bound", anchor = 5, castStart = 4.8, admitted = false },
        }
        for _, case in ipairs(cases) do
            local inst = start(matched, case.name, 10, 0)
            local now = 10
            if case.anchor then
                State.Anchor(inst, case.anchor)
                now = 6
            end
            assert.equal(case.admitted, State.AdmitsCastStart(inst, now, case.castStart), case.name)
            local found = State.SelectCastOccurrence({ inst }, 7, now, case.castStart)
            assert.equal(case.admitted and inst or nil, found, case.name)
            if not case.admitted then
                local total, reason = State.MatchCast(inst, now, case.castStart)
                assertRefusal(total, reason, case.name)
            end
        end

        -- A pause inside the lead: admission reads the pause-excluded start, while the
        -- re-time keeps the wall lead because the cast itself does not pause.
        local overlaps = {
            -- Paused at 9.95, the cast starts at 10.5 inside the pause, resume-and-anchor at 11.
            { name = "start inside the pause", pauseFrom = 9.95, pauseTo = 11, anchor = true, castStart = 10.5,
              total = 11.45, remainingNow = 1.5 },
            -- Cast from 9.85, paused 9.9 to 10.9, matched at 11.
            { name = "start before the pause", pauseFrom = 9.9, pauseTo = 10.9, castStart = 9.85,
              total = 10.85, remainingNow = 0.85 },
        }
        for _, case in ipairs(overlaps) do
            local inst, store = start(matched, case.name, 10, 0)
            State.Pause(store, "boss", case.name, case.pauseFrom)
            State.Resume(store, "boss", case.name, case.pauseTo)
            if case.anchor then State.Anchor(inst, case.pauseTo) end
            assert.is_true(State.AdmitsCastStart(inst, 11, case.castStart), case.name)
            assert.near(case.total, State.MatchCast(inst, 11, case.castStart), 1e-9, case.name)
            local elapsed = State.SampleClock(inst.sourceClock, 11)
            assert.near(case.remainingNow, State.AnchoredRemaining(inst, elapsed), 1e-9, case.name)
        end
    end)

    it("keeps an occurrence open to casts only through Active or Finished stops", function()
        local matched = binding(2, { castMatch = { spells = { 7 } } })
        for _, timelineState in ipairs({ "active", "finished" }) do
            local inst = start(matched, timelineState, 10, 0)
            State.NoteCastMatchStop(inst, timelineState)
            assert.is_nil(inst.castMatchClosed, timelineState)
        end
        for _, label in ipairs({ "canceled", "paused", "unreadable" }) do
            local inst = start(matched, label, 10, 0)
            local timelineState = label
            if label == "unreadable" then timelineState = nil end
            State.NoteCastMatchStop(inst, timelineState)
            assert.is_true(inst.castMatchClosed, label)
        end
        local confirmed = start(matched, "confirmed", 10, 0)
        confirmed.confirmed = true
        State.NoteCastMatchStop(confirmed, "canceled")
        assert.is_nil(confirmed.castMatchClosed)
    end)

    it("re-times an occurrence from the cast start on the pause-excluded clock, once", function()
        local matched = binding(2, { anchor = TF, castMatch = { spells = { 7 }, within = 5 } })
        local inst, store = start(matched, "occ", 10, 0)
        State.Pause(store, "boss", "occ", 2)
        State.Resume(store, "boss", "occ", 4)
        inst.holdDeadline, inst.waitBound = 12, 15
        assert.equal(12.5, State.MatchCast(inst, 13, 12.5))
        assert.equal(10.5, inst.anchorElapsed)
        assert.is_true(inst.confirmed)
        assert.is_nil(inst.holdDeadline)
        assert.is_nil(inst.waitBound)
        local again, againReason = State.MatchCast(inst, 14, 13.5)
        assertRefusal(again, againReason, "second match")
        local ahead = start(matched, "ahead", 10, 0)
        assert.equal(13, State.MatchCast(ahead, 11, 11.05))
        local paused, pausedStore = start(matched, "paused", 10, 0)
        State.Pause(pausedStore, "boss", "paused", 5)
        local value, reason = State.MatchCast(paused, 11, 10.5)
        assertRefusal(value, reason, "paused")
    end)

    it("ends a cast-end row at its cast's readable end plus the user offset, once, and follows that cast", function()
        local endpoint = binding(2, { castMatch = { spells = { 7 }, endpoint = "cast-end" } })
        local function withExtension(extension)
            local copy = {}
            for key, value in pairs(endpoint) do copy[key] = value end
            copy.extension = extension
            return copy
        end
        -- Extension is curated 2 plus the user offset. Each match falls inside the
        -- occurrence's own window (forecast zero 10 plus its effective extension),
        -- so the expiry guard admits it: at 11 for a cast from 10.5, except the
        -- floor case, whose effective extension 0 ends its estimate at 10, so it
        -- matches at 9.9 for a cast from 9.8 that ends at 11.3.
        local cases = {
            { name = "no offset", extension = 2, now = 11, castStart = 10.5, castEnd = 12.5, total = 12.5 },
            { name = "measured length, not curated", extension = 2, now = 11, castStart = 10.5, castEnd = 13.5,
              total = 13.5 },
            { name = "user offset once", extension = 3, now = 11, castStart = 10.5, castEnd = 12.5, total = 13.5 },
            { name = "floored at the cast start", extension = 0, now = 9.9, castStart = 9.8, castEnd = 11.3,
              total = 9.8 },
        }
        for _, case in ipairs(cases) do
            local inst = start(withExtension(case.extension), case.name, 10, 0)
            assert.near(case.total, State.MatchCast(inst, case.now, case.castStart, case.castEnd), 1e-9, case.name)
        end
        local curated = start(binding(2, { castMatch = { spells = { 7 } } }), "curated", 10, 0)
        assert.equal(12.5, State.MatchCast(curated, 11, 10.5, 13.5))

        local followed = start(endpoint, "followed", 10, 0)
        State.MatchCast(followed, 11, 10.5, 12.5)
        assert.equal(13.5, State.FollowCastEnd(followed, 12, 13.5))
        assert.equal(1.5, State.AnchoredRemaining(followed, 12))
        local unmatched = start(endpoint, "unmatched", 10, 0)
        local paused, pausedStore = start(endpoint, "paused", 10, 0)
        State.MatchCast(paused, 11, 10.5, 12.5)
        State.Pause(pausedStore, "boss", "paused", 11.5)
        local refusals = {
            { "curated row", curated },
            { "unmatched", unmatched },
            { "paused", paused },
        }
        for _, case in ipairs(refusals) do
            local total, followReason = State.FollowCastEnd(case[2], 12, 13.5)
            assertRefusal(total, followReason, case[1])
        end
        local expired = start(endpoint, "expired", 10, 0)
        State.MatchCast(expired, 11, 10.5, 12.5)
        local late, lateReason = State.FollowCastEnd(expired, 12.6, 13.5)
        assertRefusal(late, lateReason, "expired")
    end)

    it("ends a followed cast that stops early without completion, and keeps only the offset ahead after completion", function()
        local endpoint = binding(2, { castMatch = { spells = { 7 }, endpoint = "cast-end" } })
        local function endpointWith(extension)
            local copy = {}
            for key, value in pairs(endpoint) do copy[key] = value end
            copy.extension = extension
            return copy
        end
        -- Matched at 11 for a cast from 10.5 to 12.5; stop tolerance 0.15. Extension 3 is a +1 user offset.
        local cases = {
            { name = "interrupted", kind = "interrupted", now = 11.5, outcome = "ended-early" },
            { name = "failed", kind = "failed", now = 11.5, outcome = "ended-early" },
            { name = "early stop", kind = "stopped", now = 12, outcome = "ended-early" },
            { name = "stop inside the tolerance", kind = "stopped", now = 12.4, outcome = "completed",
              left = 0.1, total = 12.5 },
            { name = "stop after the read end, +1 offset", kind = "stopped", now = 12.6, extension = 3,
              outcome = "completed", left = 1, total = 13.6 },
            { name = "completion while paused", kind = "stopped", now = 12.5, pausedAt = 11.5, outcome = "completed",
              left = 0, total = 11.5 },
            { name = "offset after a paused completion", kind = "stopped", now = 12.5, pausedAt = 11.5, extension = 3,
              outcome = "completed", left = 1, total = 12.5 },
            { name = "interrupt after the countdown expired", kind = "interrupted", now = 12.6, outcome = nil,
              expired = true },
            { name = "stop after the countdown expired", kind = "stopped", now = 12.6, outcome = nil, expired = true },
            -- +1 offset: the countdown expires at 13.5; a stop at 14, before retirement runs, must not reopen it.
            { name = "stop after a +1 offset expired", kind = "stopped", now = 14, extension = 3, outcome = nil,
              expired = true },
        }
        for _, case in ipairs(cases) do
            local inst, store = start(endpointWith(case.extension or 2), case.name, 10, 0)
            State.MatchCast(inst, 11, 10.5, 12.5)
            if case.pausedAt then State.Pause(store, "boss", case.name, case.pausedAt) end
            assert.equal(case.outcome, State.EndFollowedCast(inst, case.kind, case.now), case.name)
            assert.equal(case.outcome == "ended-early", State.EndsSilently(inst), case.name)
            if case.outcome == "completed" then
                -- Elapsed stays frozen through the pause; the remaining offset then runs on wall time.
                local total, left = State.CompleteFollowedCast(inst, case.now)
                assert.near(case.total, total, 1e-9, case.name)
                assert.near(case.left, left, 1e-9, case.name)
                assert.equal("running", inst.state, case.name)
                assert.is_nil((State.Pause(store, "boss", case.name, case.now + 0.5)), case.name)
            end
            if case.expired then
                local total, reason = State.CompleteFollowedCast(inst, case.now)
                assertRefusal(total, reason, case.name)
                assert.is_nil(inst.castCompleted, case.name)
                assert.equal("retire", State.ClassifyExpiry(inst, case.now), case.name)
            end
        end
        local curated = start(binding(2, { castMatch = { spells = { 7 } } }), "curated", 10, 0)
        State.MatchCast(curated, 11, 10.5)
        local outcome, reason = State.EndFollowedCast(curated, "interrupted", 11.5)
        assertRefusal(outcome, reason, "curated")
    end)

    it("ignores a provider stop on a paused followed cast and leaves its end to the cast", function()
        local endpoint = binding(2, { castMatch = { spells = { 7 }, endpoint = "cast-end" } })
        local followed, followedStore = start(endpoint, "followed", 10, 0)
        State.MatchCast(followed, 11, 10.5, 12.5)
        State.Pause(followedStore, "boss", "followed", 11.5)
        assert.equal("ignore", State.ClassifyStop(followed, 11.8, nil, nil))
        assert.equal("ignore", State.ClassifyStop(followed, 11.8, nil, "canceled"))
        -- The follow still owns the end: completion resumes the frozen countdown with nothing left.
        assert.equal("completed", State.EndFollowedCast(followed, "stopped", 12.5))
        assert.near(11.5, State.CompleteFollowedCast(followed, 12.5), 1e-9)
        assert.equal("running", followed.state)

        -- Unrelated paused stops keep today's retirement: a curated match and an unmatched estimate.
        local curated, curatedStore = start(binding(2, { castMatch = { spells = { 7 } } }), "curated", 10, 0)
        State.MatchCast(curated, 11, 10.5)
        State.Pause(curatedStore, "boss", "curated", 11.5)
        local plain, plainStore = start(binding(2, {}), "plain", 10, 0)
        State.Pause(plainStore, "boss", "plain", 5)
        local cases = {
            { name = "paused curated match", inst = curated, now = 11.8 },
            { name = "paused unmatched estimate", inst = plain, now = 5.5 },
        }
        for _, case in ipairs(cases) do
            assert.equal("retire", State.ClassifyStop(case.inst, case.now, nil, nil), case.name)
        end
    end)

    it("lets one observed cast re-time at most one occurrence per pull", function()
        local store = State.New()
        assert.is_false(State.IsCastBarUsed(store, 9001, 40))
        assert.is_true(State.TakeCastBar(store, 9001, 40))
        assert.is_true(State.IsCastBarUsed(store, 9001, 40))
        assert.is_false(State.TakeCastBar(store, 9001, 40))
        assert.is_true(State.TakeCastBar(store, 9002, 40))
        assert.is_false(State.TakeCastBar(store, 9001, nil))
        State.RetireEncounter(store, 9001)
        assert.is_true(State.TakeCastBar(store, 9001, 40))
    end)

    it("keeps a cast wait past its estimate until the bound and ends it unconfirmed", function()
        local matched = binding(2, { anchor = TF, castMatch = { spells = { 7 }, within = 5 } })
        local inst = start(matched, "occ", 10, 0)
        local early, earlyReason = State.BeginCastWait(inst)
        assertRefusal(early, earlyReason, "not anchored")
        State.Anchor(inst, 10)
        assert.equal(15, State.BeginCastWait(inst))
        assert.is_true(State.ShowsSoon(inst))
        assert.is_true(State.EndsSilently(inst))
        assert.equal("keep", State.ClassifyExpiry(inst, 12.5))
        assert.equal("retire", State.ClassifyExpiry(inst, 15))
        assert.equal("expired", State.EndCastWait(inst, 13))
        assert.is_false(State.ShowsSoon(inst))
        assert.is_true(State.EndsSilently(inst))

        local long = start(binding(8, { anchor = TF, castMatch = { spells = { 7 }, within = 5 } }), "long", 10, 0)
        State.Anchor(long, 10)
        State.BeginCastWait(long)
        assert.equal("keep", State.ClassifyExpiry(long, 15))
        assert.equal("estimate", State.EndCastWait(long, 12))
        assert.is_false(State.EndsSilently(long))
        assert.equal("keep", State.ClassifyExpiry(long, 17.9))

        local hunting = start(binding(2, { castMatch = { spells = { 7 } } }), "hunting", 10, 0)
        State.Anchor(hunting, 10)
        local none, noneReason = State.BeginCastWait(hunting)
        assertRefusal(none, noneReason, "no within")

        -- A negative offset can consume the entire extension at the anchor.
        local zero = {}
        for key, value in pairs(matched) do zero[key] = value end
        zero.extension = 0
        local runningAtEnd = start(zero, "running at end", 10, 0)
        State.Anchor(runningAtEnd, 10)
        local refused, refusedReason = State.BeginCastWait(runningAtEnd, 10, true)
        assertRefusal(refused, refusedReason, "cast running at the end")
        assert.is_nil(runningAtEnd.waitBound)
        assert.equal("retire", State.ClassifyExpiry(runningAtEnd, 10))
        local idleAtEnd = start(zero, "idle at end", 10, 0)
        State.Anchor(idleAtEnd, 10)
        assert.equal(15, State.BeginCastWait(idleAtEnd, 10, false))
        local live = start(matched, "running with time left", 10, 0)
        State.Anchor(live, 10)
        assert.equal(15, State.BeginCastWait(live, 10, true))
    end)

    it("lets only a waitAfter row wait past its forecast, for its own bound", function()
        local freshMeat = start(binding(0, { waitAfter = 5 }), "fresh", 6, 0)
        local plain = start(binding(0, {}), "plain", 6, 0)
        assert.equal("retire", State.ClassifyExpiry(plain, 6))
        assert.equal("hold-eligible", State.ClassifyExpiry(freshMeat, 6))
        assert.equal(11, State.BeginForecastWait(freshMeat))
        assert.is_true(State.ShowsSoon(freshMeat))
        assert.is_true(State.EndsSilently(freshMeat))
        assert.equal("keep", State.ClassifyExpiry(freshMeat, 10.9))
        assert.equal("retire", State.ClassifyExpiry(freshMeat, 11))
        State.EndForecastWait(freshMeat)
        assert.is_false(State.ShowsSoon(freshMeat))
        assert.is_false(State.EndsSilently(freshMeat))
        local again, reason = State.BeginForecastWait(freshMeat)
        assertRefusal(again, reason, "stop seen")
    end)

    it("shows Soon in an existing hold only for a soonOnHold row, without silencing it", function()
        local soon = start(binding(3, { anchor = TF, soonOnHold = true }), "soon", 10, 0)
        local blank = start(binding(3, { anchor = TF }), "blank", 10, 0)
        State.BeginHold(soon, 1)
        State.BeginHold(blank, 1)
        assert.is_true(State.ShowsSoon(soon))
        assert.is_false(State.ShowsSoon(blank))
        assert.is_false(State.EndsSilently(soon))
    end)
end)
