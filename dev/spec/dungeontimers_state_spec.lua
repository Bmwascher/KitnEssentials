-- Specs for the private DungeonTimers TimerState component: pause-aware
-- source clocks, replacement/ownership scoping and binding resolution, all
-- driven with plain values and injected time (no frames, no AceTimer).
local loader = require("dev.spec._ke_loader")

describe("DungeonTimers TimerState", function()
    local State

    before_each(function()
        State = loader.loadDungeonTimerState()
    end)

    -- Refusal contract: nil plus a lowercase reason string, never an error.
    local function assertRefusal(value, reason, label)
        assert.is_nil(value, label)
        assert.equal("string", type(reason), label)
        assert.equal(reason, string.lower(reason), label)
    end

    local function timerBinding(encounterId, key, extension)
        return {
            encounterId = encounterId,
            key = key,
            kind = "Timer",
            discriminator = "any",
            policy = "legacy",
            spanMode = "remaining-only",
            curationId = key,
            extension = extension or 0,
        }
    end

    -- The zero-curation binding comes from the admission path itself, so the
    -- lifecycle cases below exercise exactly what an admitted zero row gets.
    local function admittedZeroBinding()
        local data = {
            [3208] = { timerPolicy = "explicit", spells = { [1235548] = { castDuration = 0, timerSource = {
                kind = "Timer", isCooldown = true, policy = "estimated-impact",
                spanMode = "remaining-only", stopTolerance = 0.15,
                collisionPolicy = "refuse-unresolved-label",
            } } } },
        }
        return State.BuildBindings(data).timers[3208][1235548]
    end

    it("pause/resume preserves remaining across held intervals and a cast clock keeps its own origin", function()
        local store = State.New()
        State.AdmitOwner(store, "boss1", 1)
        local binding = timerBinding(1, 100, 5)

        local instance = State.Start(store, "boss1", "label1", binding, 12, 45, 0, true)

        local _, _, remaining5 = State.Sample(instance, 5)
        assert.equal(7, remaining5)

        local _, changedPause = State.Pause(store, "boss1", "label1", 5)
        assert.is_true(changedPause)
        local _, _, remainingHeld = State.Sample(instance, 9)
        assert.equal(7, remainingHeld)

        local _, changedResume = State.Resume(store, "boss1", "label1", 9)
        assert.is_true(changedResume)
        local _, changedResumeAgain = State.Resume(store, "boss1", "label1", 9)
        assert.is_false(changedResumeAgain)

        local _, _, remaining12 = State.Sample(instance, 12)
        assert.equal(4, remaining12)

        State.Pause(store, "boss1", "label1", 12)
        State.Resume(store, "boss1", "label1", 20)
        local _, _, remaining22 = State.Sample(instance, 22)
        assert.equal(2, remaining22)

        -- Cast clock elapsed is measured from this Stop receipt (22), not
        -- from the source clock's receipt (0).
        local fill = State.BeginLegacyCast(instance, 22, 5)
        assert.equal(7, fill)
        local castElapsed, _, castRemaining = State.SampleClock(instance.castClock, 24)
        assert.equal(2, castElapsed)
        assert.equal(3, castRemaining)

        -- A Stop received while the source is held starts the cast clock
        -- already paused, so cast-phase time does not run during the hold.
        local held = State.Start(store, "boss1", "label2", binding, 12, 12, 0, true)
        State.Pause(store, "boss1", "label2", 2)
        assert.equal(15, State.BeginLegacyCast(held, 4, 5))
        local _, _, heldCastRemaining = State.SampleClock(held.castClock, 9)
        assert.equal(5, heldCastRemaining)
    end)

    it("partial span preserves initial elapsed through a hold, and a remaining-only input normalizes differently", function()
        local store = State.New()
        State.AdmitOwner(store, "boss2", 1)
        local binding = timerBinding(1, 200)

        local cases = {
            { label = "partial-span", remaining = 12, span = 45, expectedInitialElapsed = 33 },
            { label = "remaining-only", remaining = 12, span = 12, expectedInitialElapsed = 0 },
        }
        for _, case in ipairs(cases) do
            local instance = State.Start(store, "boss2", case.label, binding, case.remaining, case.span, 0, true)
            assert.equal(case.expectedInitialElapsed, instance.sourceClock.initialElapsed)
        end

        -- Holding it does not move the due instant: five running seconds land
        -- on sourceElapsed 38, and pausing there holds it, not advances it.
        local instance = State.Find(store, "boss2", "partial-span")
        local _, sourceElapsed5 = State.Sample(instance, 5)
        assert.equal(38, sourceElapsed5)
        State.Pause(store, "boss2", "partial-span", 5)
        local _, sourceElapsedHeld = State.Sample(instance, 9)
        assert.equal(38, sourceElapsedHeld)
        State.Resume(store, "boss2", "partial-span", 9)

        -- Replacement restarts receipt and initialElapsed from the new inputs.
        local replacement = State.Start(store, "boss2", "partial-span", binding, 20, 45, 100, true)
        assert.equal(100, replacement.sourceClock.receivedAt)
        assert.equal(25, replacement.sourceClock.initialElapsed)
    end)

    it("replacement retires the predecessor and its job token without mutating the successor", function()
        local store = State.New()
        State.AdmitOwner(store, "boss3", 1)
        local binding = timerBinding(1, 300)

        local first = State.Start(store, "boss3", "label3", binding, 12, 45, 0, true)
        local firstGeneration, firstModuleEpoch, firstEncounterEpoch =
            first.generation, first.moduleEpoch, first.encounterEpoch

        local second, retiredPredecessor = State.Start(store, "boss3", "label3", binding, 20, 45, 10, true)

        assert.equal(first, retiredPredecessor)
        assert.equal("retired", first.state)
        assert.is_false(State.IsCurrent(store, first, firstGeneration, firstModuleEpoch, firstEncounterEpoch))
        assert.is_true(State.IsCurrent(store, second, second.generation, second.moduleEpoch, second.encounterEpoch))

        assert.equal("running", second.state)
        assert.equal(20, second.sourceClock.remainingAtReceipt)
        assert.equal(10, second.sourceClock.receivedAt)
    end)

    it("owner/encounter/global invalidation scopes correctly and unknown owners/tokens are inert", function()
        local binding = timerBinding(1, 400)

        -- RetireOwner retires only that owner's instances.
        local storeA = State.New()
        local scopeA = State.AdmitOwner(storeA, "ownerA", 1)
        local scopeB = State.AdmitOwner(storeA, "ownerB", 1)
        local instanceA = State.Start(storeA, "ownerA", "label", binding, 12, 45, 0, true)
        local instanceB = State.Start(storeA, "ownerB", "label", binding, 12, 45, 0, true)
        local retiredA = State.RetireOwner(storeA, "ownerA")
        assert.same({ instanceA }, retiredA)
        assert.equal("retired", instanceA.state)
        assert.equal("running", instanceB.state)
        assert.is_false(State.IsScopeCurrent(storeA, "ownerA", scopeA))
        assert.is_true(State.IsScopeCurrent(storeA, "ownerB", scopeB))

        -- RetireEncounter advances only that encounter's epoch.
        local storeB = State.New()
        State.AdmitOwner(storeB, "ownerC", 10)
        State.AdmitOwner(storeB, "ownerD", 20)
        local instanceC = State.Start(storeB, "ownerC", "label", timerBinding(10, 500), 12, 45, 0, true)
        local instanceD = State.Start(storeB, "ownerD", "label", timerBinding(20, 500), 12, 45, 0, true)
        local capturedEpochC, capturedEpochD = instanceC.encounterEpoch, instanceD.encounterEpoch
        State.RetireEncounter(storeB, 20)
        assert.is_true(State.IsCurrent(storeB, instanceC, instanceC.generation, instanceC.moduleEpoch, capturedEpochC))
        assert.is_false(State.IsCurrent(storeB, instanceD, instanceD.generation, instanceD.moduleEpoch, capturedEpochD))

        -- RetireAll invalidates everything.
        local storeC = State.New()
        State.AdmitOwner(storeC, "ownerE", 1)
        local instanceE = State.Start(storeC, "ownerE", "label", binding, 12, 45, 0, true)
        local capturedModuleEpoch = instanceE.moduleEpoch
        State.RetireAll(storeC)
        assert.equal("retired", instanceE.state)
        assert.is_false(State.IsCurrent(storeC, instanceE, instanceE.generation, capturedModuleEpoch, instanceE.encounterEpoch))

        -- Unknown owner/token inputs are inert, never an error.
        local storeD = State.New()
        assert.same({}, State.RetireOwner(storeD, "unknownOwner"))
        assert.is_false(State.IsCurrent(storeD, nil, 1, 1, 1))
        assert.is_false(State.IsSlotCurrent(storeD, "unknownOwner", "phantom", "slotkey", 1))

        -- A plain re-admission with no retirement in between reuses the
        -- scope and its slot generations stay current.
        local storeE = State.New()
        local scopeInitial = State.AdmitOwner(storeE, "ownerF", 1)
        local slotGeneration = State.NextSlot(storeE, "ownerF", "phantom", "slotkey")
        local scopeReAdmitted = State.AdmitOwner(storeE, "ownerF", 1)
        assert.equal(scopeInitial.serial, scopeReAdmitted.serial)
        assert.is_true(State.IsSlotCurrent(storeE, "ownerF", "phantom", "slotkey", slotGeneration))

        -- RetireOwner then re-admitting yields a new scope serial; the old
        -- scope's slot generation stops being current, and a fresh
        -- generation for the same slot never collides with it.
        State.RetireOwner(storeE, "ownerF")
        local scopeAfterRetire = State.AdmitOwner(storeE, "ownerF", 1)
        assert.is_false(scopeInitial.serial == scopeAfterRetire.serial)
        assert.is_false(State.IsSlotCurrent(storeE, "ownerF", "phantom", "slotkey", slotGeneration))
        local slotGenerationAfterRetire = State.NextSlot(storeE, "ownerF", "phantom", "slotkey")
        assert.is_false(slotGenerationAfterRetire == slotGeneration)
        assert.is_false(State.IsSlotCurrent(storeE, "ownerF", "phantom", "slotkey", slotGeneration))
    end)

    it("binding resolution refuses ambiguous/mismatched requests and resolves valid ones", function()
        local encounterData = {
            [1] = {
                name = "Boss One",
                spells = {
                    [100] = { castDuration = 3 },
                    [200] = { spawnOnMessage = "MSG_200" },
                    [300] = { phantomFollowupOf = 100 },
                },
            },
            [2] = {
                name = "Boss Two",
                spells = {
                    [100] = { castDuration = 5 },
                },
            },
        }
        local bindings = State.BuildBindings(encounterData)

        -- BuildBindings only ever emits discriminator="any"; an explicitly
        -- bound active variant needs a hand-built binding to exercise the
        -- discriminator-mismatch branch.
        local explicitBindings = {
            timers = { [1] = { [999] = {
                encounterId = 1, key = 999, kind = "Timer", discriminator = true,
                policy = "legacy", spanMode = "remaining-only", curationId = 999, extension = 0,
            } } },
            messages = {}, casts = {},
        }

        local refusals = {
            { name = "activeEncounterId not an ordinary number",
              encounterIds = { 1 }, activeEncounterId = "one", kind = "Timer", key = 100, discriminator = true },
            { name = "owner encounter list does not contain the active encounter",
              encounterIds = { 2 }, activeEncounterId = 1, kind = "Timer", key = 100, discriminator = true },
            { name = "unknown key",
              encounterIds = { 1 }, activeEncounterId = 1, kind = "Timer", key = 9999, discriminator = true },
            { name = "Timer request for the message-only key",
              encounterIds = { 1 }, activeEncounterId = 1, kind = "Timer", key = 200, discriminator = true },
            { name = "Timer request for the phantom's own key",
              encounterIds = { 1 }, activeEncounterId = 1, kind = "Timer", key = 300, discriminator = true },
            { name = "CastTimer request for a legacy row",
              encounterIds = { 1 }, activeEncounterId = 1, kind = "CastTimer", key = 100, discriminator = nil },
            { name = "explicitly bound discriminator mismatch", bindings = explicitBindings,
              encounterIds = { 1 }, activeEncounterId = 1, kind = "Timer", key = 999, discriminator = false },
        }
        for _, case in ipairs(refusals) do
            local binding, reason = State.ResolveBinding(
                case.bindings or bindings, case.encounterIds, case.activeEncounterId, case.kind, case.key,
                case.discriminator)
            assertRefusal(binding, reason, case.name)
        end

        -- Legacy Timer accepts Bar and CDBar (discriminator true/false) alike.
        local resolvedTrue = State.ResolveBinding(bindings, { 1 }, 1, "Timer", 100, true)
        local resolvedFalse = State.ResolveBinding(bindings, { 1 }, 1, "Timer", 100, false)
        assert.same(resolvedTrue, resolvedFalse)
        assert.equal(3, resolvedTrue.extension)

        -- An explicitly bound discriminator accepts its matching variant.
        local resolvedExplicit = State.ResolveBinding(explicitBindings, { 1 }, 1, "Timer", 999, true)
        assert.is_not_nil(resolvedExplicit)
        assert.equal(true, resolvedExplicit.discriminator)

        -- The spawnOnMessage row resolves through its Message route.
        local resolvedMessage = State.ResolveBinding(bindings, { 1 }, 1, "Message", 200, nil)
        assert.equal("Message", resolvedMessage.kind)
        assert.equal(200, resolvedMessage.key)

        -- The phantom row is recorded under its parent's key, not its own.
        assert.same({ 300 }, bindings.phantoms[1][100])
    end)

    it("invalid identity/duration/clock data refuses before any mutation", function()
        local nan = 0 / 0
        local invalidCases = {
            { name = "NaN remaining", remaining = nan, span = 45, now = 0 },
            { name = "infinite remaining", remaining = math.huge, span = 45, now = 0 },
            { name = "negative remaining", remaining = -1, span = 45, now = 0 },
            { name = "zero remaining", remaining = 0, span = 45, now = 0 },
            { name = "span smaller than remaining", remaining = 12, span = 5, now = 0 },
            { name = "non-number now", remaining = 12, span = 45, now = "later" },
        }
        for _, case in ipairs(invalidCases) do
            local clock, reason = State.NewClock(case.remaining, case.span, case.now)
            assertRefusal(clock, reason, case.name)
        end

        local store = State.New()
        State.AdmitOwner(store, "boss6", 1)
        local binding = timerBinding(1, 600)
        for _, case in ipairs(invalidCases) do
            local instance, reason = State.Start(store, "boss6", "label6", binding, case.remaining, case.span, case.now, true)
            assertRefusal(instance, reason, case.name)
        end
        assert.is_nil(State.Find(store, "boss6", "label6"))

        local instance = State.Start(store, "boss6", "label6", binding, 12, 45, 0, true)
        State.Sample(instance, 5)
        local before = {
            state = instance.state,
            receivedAt = instance.sourceClock.receivedAt,
            remainingAtReceipt = instance.sourceClock.remainingAtReceipt,
            accumulatedPause = instance.sourceClock.accumulatedPause,
            pausedAt = instance.sourceClock.pausedAt,
            lastAcceptedNow = instance.sourceClock.lastAcceptedNow,
        }

        -- A backwards now refuses without touching the held clock.
        local sampleVal, sampleReason = State.Sample(instance, 3)
        assertRefusal(sampleVal, sampleReason)

        -- A non-number now refuses on Pause the same way.
        local pausedInstance, pauseReason = State.Pause(store, "boss6", "label6", "later")
        assertRefusal(pausedInstance, pauseReason)

        assert.same(before, {
            state = instance.state,
            receivedAt = instance.sourceClock.receivedAt,
            remainingAtReceipt = instance.sourceClock.remainingAtReceipt,
            accumulatedPause = instance.sourceClock.accumulatedPause,
            pausedAt = instance.sourceClock.pausedAt,
            lastAcceptedNow = instance.sourceClock.lastAcceptedNow,
        })

        -- A backwards now refuses on Resume once actually paused.
        State.Pause(store, "boss6", "label6", 5)
        local resumedInstance, resumeReason = State.Resume(store, "boss6", "label6", 2)
        assertRefusal(resumedInstance, resumeReason)
        assert.equal("paused", instance.state)
    end)

    local function withoutField(base, field)
        local copy = {}
        for k, v in pairs(base) do copy[k] = v end
        copy[field] = nil
        return copy
    end

    it("explicit admission refuses malformed/forbidden rows and an unknown encounter policy, accepting the supported binding and leaving legacy untouched", function()
        local nan = 0 / 0
        local validContract = {
            kind = "Timer", isCooldown = true, policy = "estimated-impact",
            spanMode = "remaining-only", stopTolerance = 0.15,
            collisionPolicy = "refuse-unresolved-label",
        }
        local function withContract(overrides)
            local contract = {}
            for k, v in pairs(validContract) do contract[k] = v end
            for k, v in pairs(overrides or {}) do contract[k] = v end
            return contract
        end

        local refusalRows = {
            { name = "missing timerSource", row = { castDuration = 3 } },
            { name = "non-table timerSource", row = { castDuration = 3, timerSource = "yes" } },
            { name = "wrong kind", row = { castDuration = 3, timerSource = withContract({ kind = "Message" }) } },
            { name = "isCooldown not exactly true",
              row = { castDuration = 3, timerSource = withContract({ isCooldown = false }) } },
            { name = "wrong policy", row = { castDuration = 3, timerSource = withContract({ policy = "legacy" }) } },
            { name = "wrong spanMode",
              row = { castDuration = 3, timerSource = withContract({ spanMode = "full-span" }) } },
            { name = "wrong collisionPolicy",
              row = { castDuration = 3, timerSource = withContract({ collisionPolicy = "quarantine" }) } },
            { name = "missing collisionPolicy",
              row = { castDuration = 3, timerSource = withoutField(validContract, "collisionPolicy") } },
            { name = "non-finite stopTolerance",
              row = { castDuration = 3, timerSource = withContract({ stopTolerance = nan }) } },
            { name = "zero stopTolerance",
              row = { castDuration = 3, timerSource = withContract({ stopTolerance = 0 }) } },
            { name = "negative stopTolerance",
              row = { castDuration = 3, timerSource = withContract({ stopTolerance = -0.1 }) } },
            { name = "missing castDuration", row = { timerSource = validContract } },
            { name = "nan castDuration", row = { castDuration = nan, timerSource = validContract } },
            { name = "negative castDuration", row = { castDuration = -3, timerSource = validContract } },
            { name = "negative-infinite castDuration", row = { castDuration = -math.huge, timerSource = validContract } },
            { name = "non-finite castDuration", row = { castDuration = math.huge, timerSource = validContract } },
            { name = "string castDuration", row = { castDuration = "3", timerSource = validContract } },
            { name = "invalid anchor value",
              row = { castDuration = 3, timerSource = withContract({ anchor = "encounter-complete" }) } },
            { name = "invalid castConfirm value",
              row = { castDuration = 3, timerSource = withContract({ castConfirm = "boss-cast-stop" }) } },
            { name = "forbidden channelDuration",
              row = { castDuration = 3, channelDuration = 5, timerSource = validContract } },
            { name = "forbidden extendByChannel",
              row = { castDuration = 3, extendByChannel = true, timerSource = validContract } },
            { name = "forbidden forceDuration",
              row = { castDuration = 3, forceDuration = 8, timerSource = validContract } },
            { name = "forbidden postCastBar",
              row = { castDuration = 3, postCastBar = { duration = 5 }, timerSource = validContract } },
            { name = "forbidden phantomFollowupOf",
              row = { castDuration = 3, phantomFollowupOf = 100, timerSource = validContract } },
            { name = "forbidden spawnOnMessage",
              row = { castDuration = 3, spawnOnMessage = true, timerSource = validContract } },
            { name = "forbidden shieldBar",
              row = { castDuration = 3, shieldBar = { baseAmount = 10 }, timerSource = validContract } },
            { name = "forbidden secondary",
              row = { castDuration = 3, secondary = {}, timerSource = validContract } },
            { name = "forbidden castDisplayText",
              row = { castDuration = 3, castDisplayText = "Cast!", timerSource = validContract } },
        }
        for _, case in ipairs(refusalRows) do
            local encounterData = { [3208] = { timerPolicy = "explicit", spells = { [1235548] = case.row } } }
            local bindings = State.BuildBindings(encounterData)
            assert.is_nil(bindings.timers[3208] and bindings.timers[3208][1235548], case.name)
        end

        -- Finite zero and positive curation both admit; the binding carries the
        -- row's castDuration as its extension unchanged.
        for _, curated in ipairs({ 0, 1 }) do
            local acceptedData = {
                [3208] = { timerPolicy = "explicit", spells = { [1235548] = { castDuration = curated, timerSource = validContract } } },
            }
            local accepted = State.BuildBindings(acceptedData).timers[3208][1235548]
            assert.same({
                encounterId = 3208, key = 1235548, kind = "Timer", discriminator = true,
                policy = "estimated-impact", spanMode = "remaining-only", curationId = 1235548,
                extension = curated, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
            }, accepted, "curated " .. tostring(curated))
        end

        local anchoredData = {
            [3208] = { timerPolicy = "explicit", spells = { [1235548] = {
                castDuration = 1, timerSource = withContract({ anchor = "timeline-finished", castConfirm = "boss-cast-start" }) } } },
        }
        local anchoredAccepted = State.BuildBindings(anchoredData).timers[3208][1235548]
        assert.same({
            encounterId = 3208, key = 1235548, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = 1235548,
            extension = 1, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
            anchor = "timeline-finished", castConfirm = "boss-cast-start",
        }, anchoredAccepted)

        -- An unknown non-nil encounter policy installs no bindings at all
        -- for that encounter, even for an otherwise-ordinary row.
        local unknownPolicyData = {
            [9999] = { timerPolicy = "something-else", spells = { [100] = { castDuration = 3 } } },
        }
        local unknownPolicyBindings = State.BuildBindings(unknownPolicyData)
        assert.is_nil(unknownPolicyBindings.timers[9999])
        assert.is_nil(unknownPolicyBindings.messages[9999])

        -- A legacy encounter (no timerPolicy) is entirely unaffected, even
        -- when one of its rows happens to carry a timerSource typo.
        local legacyData = {
            [1] = { spells = { [100] = { castDuration = 3, timerSource = validContract } } },
        }
        local legacyBindings = State.BuildBindings(legacyData)
        assert.same({
            encounterId = 1, key = 100, kind = "Timer", discriminator = "any",
            policy = "legacy", spanMode = "remaining-only", curationId = 100, extension = 3,
        }, legacyBindings.timers[1][100])
    end)

    it("estimated-impact stop classification distinguishes early/near/late/expired/zero-extension/paused stops and ignores forceDuration", function()
        local store = State.New()
        State.AdmitOwner(store, "sentinel", 3208)
        local binding = {
            encounterId = 3208, key = 1235548, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = 1235548,
            extension = 3, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
        }

        -- receipt 0, remaining 10, extension 3, stopTolerance 0.15: provider
        -- deadline 10, predicted endpoint 13.
        local timingCases = {
            { name = "early, before tolerance", now = 9.8, expected = "retire" },
            { name = "just inside tolerance", now = 9.85, expected = "keep-estimate" },
            { name = "at the provider deadline", now = 10, expected = "keep-estimate" },
            { name = "late but before the predicted endpoint", now = 11, expected = "keep-estimate" },
            { name = "at the predicted endpoint", now = 13, expected = "retire" },
            { name = "after the predicted endpoint", now = 14, expected = "retire" },
        }
        for _, case in ipairs(timingCases) do
            local instance = State.Start(store, "sentinel", "label-" .. case.name, binding, 10, 10, 0, true)
            assert.equal(case.expected, State.ClassifyStop(instance, case.now, nil), case.name)
        end

        -- A repeated near stop against the SAME instance retains the
        -- original deadline rather than drifting it.
        local repeated = State.Start(store, "sentinel", "repeated", binding, 10, 10, 0, true)
        assert.equal("keep-estimate", State.ClassifyStop(repeated, 10.5, nil))
        assert.equal("keep-estimate", State.ClassifyStop(repeated, 12.9, nil))
        assert.equal(10, repeated.sourceClock.remainingAtReceipt)

        -- Zero effective extension: rule 4 wins over rule 3 even inside the
        -- tolerance window, since the predicted endpoint equals the
        -- provider deadline.
        local zeroExtBinding = admittedZeroBinding()
        assert.equal(0, zeroExtBinding.extension)
        for _, now in ipairs({ 9.9, 9.95, 10, 10.1 }) do
            local instance = State.Start(store, "sentinel", "zero-ext-" .. tostring(now), zeroExtBinding, 10, 10, 0, true)
            assert.equal("retire", State.ClassifyStop(instance, now, nil))
        end

        -- The pause sits inside the keep window, so only rule 5 (a source
        -- already known paused retires immediately) can retire it.
        local paused = State.Start(store, "sentinel", "paused", binding, 10, 10, 0, true)
        State.Pause(store, "sentinel", "paused", 10)
        assert.equal("retire", State.ClassifyStop(paused, 11, nil))

        -- forceDuration cannot excuse an early stop for an admitted row.
        local forced = State.Start(store, "sentinel", "forced", binding, 10, 10, 0, true)
        assert.equal("retire", State.ClassifyStop(forced, 2, 999))
    end)

    it("estimated-impact expiry keeps while source remaining plus effective extension is positive, holds through a pause, and never enters a legacy cast", function()
        local store = State.New()
        State.AdmitOwner(store, "sentinel", 3208)
        local binding = {
            encounterId = 3208, key = 1235548, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = 1235548,
            extension = 3, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
        }

        local instance = State.Start(store, "sentinel", "expiry", binding, 10, 10, 0, true)
        assert.equal("keep", State.ClassifyExpiry(instance, 12.9))
        assert.equal("retire", State.ClassifyExpiry(instance, 13))
        assert.is_nil(instance.castClock)

        -- A held interval shifts the wall-clock endpoint by exactly the
        -- hold duration; the source clock, not a legacy stale grace,
        -- governs it.
        local held = State.Start(store, "sentinel", "held-expiry", binding, 10, 10, 0, true)
        State.Pause(store, "sentinel", "held-expiry", 4)
        State.Resume(store, "sentinel", "held-expiry", 8)
        assert.equal("keep", State.ClassifyExpiry(held, 16.9))
        assert.equal("retire", State.ClassifyExpiry(held, 17))

        -- A zero effective extension retires exactly at the source
        -- deadline, never producing a legacy followup.
        local zeroExtBinding = admittedZeroBinding()
        assert.equal(0, zeroExtBinding.extension)
        local zeroExt = State.Start(store, "sentinel", "zero-ext-expiry", zeroExtBinding, 10, 10, 0, true)
        assert.equal("keep", State.ClassifyExpiry(zeroExt, 9.9))
        assert.equal("retire", State.ClassifyExpiry(zeroExt, 10))
    end)

    it("ResolveTimelineEvent resolves the single receipt-tick/duration match, refuses no-event/ambiguous, and encounter/global teardown drops recorded events", function()
        local store = State.New()
        State.AdmitOwner(store, "sentinel", 3208)
        local binding = {
            encounterId = 3208, key = 1235548, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = 1235548,
            extension = 3, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
            anchor = "timeline-finished",
        }
        local instance = State.Start(store, "sentinel", "resolve", binding, 10, 10, 0, true)

        local nothing, nothingReason = State.ResolveTimelineEvent(store, instance)
        assert.is_nil(nothing)
        assert.equal("no-event", nothingReason)

        State.RecordTimelineEvent(store, 3208, 501, 10, 0)
        assert.equal(501, State.ResolveTimelineEvent(store, instance))

        local otherTick = State.Start(store, "sentinel", "other-tick", binding, 10, 10, 5, true)
        local tickMiss, tickReason = State.ResolveTimelineEvent(store, otherTick)
        assert.is_nil(tickMiss)
        assert.equal("no-event", tickReason)

        local otherDuration = State.Start(store, "sentinel", "other-duration", binding, 20, 20, 0, true)
        local durationMiss, durationReason = State.ResolveTimelineEvent(store, otherDuration)
        assert.is_nil(durationMiss)
        assert.equal("no-event", durationReason)

        State.RecordTimelineEvent(store, 3208, 502, 10, 0)
        local ambiguous, ambiguousReason = State.ResolveTimelineEvent(store, instance)
        assert.is_nil(ambiguous)
        assert.equal("ambiguous", ambiguousReason)

        State.RetireEncounter(store, 3208)
        local afterEncounterRetire, afterEncounterReason = State.ResolveTimelineEvent(store, instance)
        assert.is_nil(afterEncounterRetire)
        assert.equal("no-event", afterEncounterReason)

        State.RecordTimelineEvent(store, 3208, 503, 10, 0)
        State.RetireAll(store)
        local afterAllRetire, afterAllReason = State.ResolveTimelineEvent(store, instance)
        assert.is_nil(afterAllRetire)
        assert.equal("no-event", afterAllReason)
    end)

    it("ResolveTimelineEvent with a provider identity takes only that event on the receipt tick at the receipt's duration, refuses a contradicting or refused identity, and without one still refuses the duplicate shape", function()
        local store = State.New()
        State.AdmitOwner(store, "sentinel", 3101)
        local binding = {
            encounterId = 3101, key = 474240, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = 474240,
            extension = 3.5, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
            anchor = "timeline-finished",
        }
        local tick = 216001.046
        State.RecordTimelineEvent(store, 3101, 419, 12, tick, 6)
        State.RecordTimelineEvent(store, 3101, 421, 12, tick, 6)
        State.RecordTimelineEvent(store, 3101, 423, 8, tick, 6)
        local cases = {
            { name = "kept duplicate", at = tick, identity = 421, want = 421 },
            { name = "identity absent from the tick", at = tick, identity = 999, reason = "exact-mismatch" },
            { name = "identity recorded at another duration", at = tick, identity = 423, reason = "exact-mismatch" },
            { name = "identity on a tick with no records", at = tick + 1, identity = 421, reason = "exact-mismatch" },
            { name = "refused evidence", at = tick, identity = "refused", reason = "identity-refused" },
            { name = "no identity", at = tick, reason = "ambiguous" },
        }
        for _, case in ipairs(cases) do
            local instance = State.Start(store, "sentinel", "Fel Nova (5)", binding, 12, 12, case.at, true)
            instance.timelineIdentity = case.identity
            local eventId, second = State.ResolveTimelineEvent(store, instance)
            if case.want then
                assert.equal(case.want, eventId, case.name)
                assert.equal(6, second, case.name)
            else
                assertRefusal(eventId, second, case.name)
                assert.equal(case.reason, second, case.name)
            end
        end
    end)

    it("StartBar evidence noted without owner admission reaches only the next matching Timer from its owner on the same tick, a conflict refuses the rest of that tick, and owner, encounter and global teardown drop it", function()
        local KEY, TEXT, TIME = 474240, "Fel Nova (5)", 12
        local A, B, C = {}, {}, {}
        local function note(store, owner, at, eventId, accepted, encounterId)
            return State.NoteStartBar(store, owner, encounterId or 3101, at, accepted ~= false,
                KEY, TEXT, TIME, true, eventId)
        end
        -- The Timer callback's order: take first, match, poison on a refusal.
        local function timer(store, owner, at, fields)
            fields = fields or {}
            local function field(name, default)
                if fields[name] == nil then return default end
                return fields[name]
            end
            local evidence, key, text, time, isCooldown, eventId = State.TakeStartBar(store, owner, at)
            local identity = State.MatchStartBar(evidence, key, text, time, isCooldown, eventId,
                field("key", KEY), field("text", TEXT), field("time", TIME),
                field("isCooldown", true), field("isBarEnabled", true))
            if identity == "refused" then State.PoisonStartBars(store, owner, at) end
            if identity == nil then return "absent" end
            return identity
        end

        local cases = {
            { name = "matched, then consumed", want = { 421, "absent" }, run = function(s)
                note(s, A, 0, 421)
                local first = timer(s, A, 0)
                return { first, timer(s, A, 0) }
            end },
            { name = "duplicate shape: two pairs on one tick", want = { 419, 421 }, run = function(s)
                note(s, A, 0, 419)
                local first = timer(s, A, 0)
                note(s, A, 0, 421)
                return { first, timer(s, A, 0) }
            end },
            { name = "no StartBar", want = { "absent" }, run = function(s)
                return { timer(s, A, 0) }
            end },
            { name = "earlier tick", want = { "absent" }, run = function(s)
                note(s, A, 0, 421)
                return { timer(s, A, 1) }
            end },
            { name = "rejected StartBar alone", want = { "absent" }, run = function(s)
                note(s, A, 0, 421, false)
                return { timer(s, A, 0) }
            end },
            { name = "second StartBar on the tick", want = { "refused", "refused", 425 }, run = function(s)
                note(s, A, 0, 421)
                note(s, A, 0, 422)
                local first = timer(s, A, 0)
                local second = timer(s, A, 0)
                note(s, A, 1, 425)
                return { first, second, timer(s, A, 1) }
            end },
            { name = "rejected StartBar while one is pending", want = { "refused" }, run = function(s)
                note(s, A, 0, 421)
                note(s, A, 0, 422, false)
                return { timer(s, A, 0) }
            end },
            { name = "unattributable Timer", want = { "refused", "refused" }, run = function(s)
                note(s, A, 0, 421)
                note(s, B, 0, 500)
                State.TakeStartBar(s, nil, 0)
                local first = timer(s, A, 0)
                return { first, timer(s, B, 0) }
            end },
        }
        for _, invalid in ipairs({ 0, -1, 1.5, "421" }) do
            cases[#cases + 1] = { name = "invalid timeline ID " .. tostring(invalid), want = { "absent" },
                run = function(s)
                    note(s, A, 0, invalid)
                    return { timer(s, A, 0) }
                end }
        end
        for _, mismatch in ipairs({
            { key = 1253811 }, { text = "Fel Spray (3)" }, { time = 8 }, { isCooldown = false },
            { isBarEnabled = false },
        }) do
            local name = next(mismatch)
            cases[#cases + 1] = { name = "mismatched " .. name, want = { "refused", "refused", 425 },
                run = function(s)
                    note(s, A, 0, 421)
                    local first = timer(s, A, 0, mismatch)
                    note(s, A, 0, 422)
                    local second = timer(s, A, 0)
                    note(s, A, 1, 425)
                    return { first, second, timer(s, A, 1) }
                end }
        end
        for _, case in ipairs(cases) do
            assert.same(case.want, case.run(State.New()), case.name)
        end

        local store = State.New()
        note(store, A, 0, 421)
        note(store, B, 0, 500)
        note(store, C, 0, 600, true, 3102)
        State.RetireOwner(store, A)
        assert.equal("absent", timer(store, A, 0), "owner teardown")
        State.RetireEncounter(store, 3101)
        assert.equal("absent", timer(store, B, 0), "encounter teardown")
        assert.equal(600, timer(store, C, 0), "another encounter's record survives")
        note(store, C, 1, 700, true, 3102)
        State.RetireAll(store)
        assert.equal("absent", timer(store, C, 1), "global teardown")
    end)

    it("ClassifyStop applies the timeline state only for an anchored contract, resumes-and-anchors a paused Finished inside the hold bound, retires at or past it, and ignores an anchored instance", function()
        local store = State.New()
        State.AdmitOwner(store, "sentinel", 3208)
        local anchoredBinding = {
            encounterId = 3208, key = 1235548, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = 1235548,
            extension = 3, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
            anchor = "timeline-finished",
        }

        -- receipt 0, remaining 10, extension 3, stopTolerance 0.15: elapsed 2
        -- is far earlier than providerDeadline - stopTolerance (9.85) and
        -- would retire under the heuristic rules; "finished" anchors anyway.
        local finishedEarly = State.Start(store, "sentinel", "finished-early", anchoredBinding, 10, 10, 0, true)
        assert.equal("anchor", State.ClassifyStop(finishedEarly, 2, nil, "finished"))

        local canceledInside = State.Start(store, "sentinel", "canceled-inside", anchoredBinding, 10, 10, 0, true)
        assert.equal("retire", State.ClassifyStop(canceledInside, 10, nil, "canceled"))

        local nilState = State.Start(store, "sentinel", "nil-state", anchoredBinding, 10, 10, 0, true)
        assert.equal("keep-estimate", State.ClassifyStop(nilState, 10, nil, nil))

        local unanchoredBinding = {
            encounterId = 3208, key = 1235548, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = 1235548,
            extension = 3, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
        }
        local noAnchorField = State.Start(store, "sentinel", "no-anchor-field", unanchoredBinding, 10, 10, 0, true)
        assert.equal("keep-estimate", State.ClassifyStop(noAnchorField, 10, nil, "finished"))

        -- A Finished while paused is the one stop the paused test does not
        -- retire: the module resumes in full before anchoring.
        local paused = State.Start(store, "sentinel", "paused-finished", anchoredBinding, 10, 10, 0, true)
        State.Pause(store, "sentinel", "paused-finished", 10)
        assert.equal("resume-and-anchor", State.ClassifyStop(paused, 11, nil, "finished"))
        assert.equal("retire", State.ClassifyStop(paused, 11, nil, "canceled"))
        assert.equal("retire", State.ClassifyStop(paused, 11, nil, nil))

        local alreadyAnchored = State.Start(store, "sentinel", "already-anchored", anchoredBinding, 10, 10, 0, true)
        State.Anchor(alreadyAnchored, 5)
        assert.equal("ignore", State.ClassifyStop(alreadyAnchored, 6, nil, "finished"))

        -- Hold bound: receipt 10 + queue 6 + 0.5 = 16.5 on the elapsed clock.
        local held = State.Start(store, "sentinel", "held-finished", anchoredBinding, 10, 10, 0, true)
        assert.equal(16.5, State.BeginHold(held, 6))
        assert.equal("anchor", State.ClassifyStop(held, 16.4, nil, "finished"))
        assert.equal("retire", State.ClassifyStop(held, 16.5, nil, "finished"))
        assert.equal("retire", State.ClassifyStop(held, 16.4, nil, "canceled"))

        local heldPaused = State.Start(store, "sentinel", "held-paused", anchoredBinding, 10, 10, 0, true)
        State.BeginHold(heldPaused, 6)
        State.Pause(store, "sentinel", "held-paused", 16)
        assert.equal("resume-and-anchor", State.ClassifyStop(heldPaused, 20, nil, "finished"))
        State.Resume(store, "sentinel", "held-paused", 20)
        State.Pause(store, "sentinel", "held-paused", 20.5)
        assert.equal("retire", State.ClassifyStop(heldPaused, 30, nil, "finished"))
    end)

    it("Anchor fixes the anchored total once, ClassifyExpiry keeps until that instant and retires after it, a pause holds it, and a second Anchor refuses", function()
        local store = State.New()
        State.AdmitOwner(store, "sentinel", 3208)
        local binding = {
            encounterId = 3208, key = 1235548, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = 1235548,
            extension = 3, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
            anchor = "timeline-finished",
        }

        local instance = State.Start(store, "sentinel", "anchored", binding, 10, 10, 0, true)
        local total = State.Anchor(instance, 2)
        assert.equal(5, total)
        assert.equal(2, instance.anchorElapsed)

        assert.equal(5, State.AnchoredRemaining(instance, 0))
        assert.equal(3, State.AnchoredRemaining(instance, 2))
        assert.equal(0, State.AnchoredRemaining(instance, 5))
        assert.equal(-1, State.AnchoredRemaining(instance, 6))

        assert.equal("keep", State.ClassifyExpiry(instance, 4.9))
        assert.equal("retire", State.ClassifyExpiry(instance, 5))

        local held = State.Start(store, "sentinel", "held-anchor", binding, 10, 10, 0, true)
        State.Anchor(held, 2)
        State.Pause(store, "sentinel", "held-anchor", 3)
        State.Resume(store, "sentinel", "held-anchor", 6)
        assert.equal("keep", State.ClassifyExpiry(held, 7.9))
        assert.equal("retire", State.ClassifyExpiry(held, 8))

        local refusedTotal, refusedReason = State.Anchor(instance, 4)
        assert.is_nil(refusedTotal)
        assert.equal("already-anchored", refusedReason)
        assert.equal(2, instance.anchorElapsed)
    end)

    it("ClassifyExpiry holds only an unanchored anchor row at forecast zero, keeps until the pause-excluded hold deadline and retires at it, keeps anchored precedence, and retires rows without anchor at zero", function()
        local store = State.New()
        State.AdmitOwner(store, "sentinel", 3207)
        local anchored = {
            encounterId = 3207, key = 1253268, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = 1253268,
            extension = 4, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
            anchor = "timeline-finished",
        }
        local plain = {
            encounterId = 3207, key = 1235118, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = 1235118,
            extension = 4, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
        }

        -- receipt 0, remaining 10, extension 4: forecast zero at 14.
        local held = State.Start(store, "sentinel", "held", anchored, 10, 10, 0, true)
        assert.equal("keep", State.ClassifyExpiry(held, 13.9))
        assert.equal("hold-eligible", State.ClassifyExpiry(held, 14))
        assert.is_nil(held.holdDeadline)

        -- Deadline 10 + 6 + 0.5 on the elapsed clock; keep before, retire at.
        assert.equal(16.5, State.BeginHold(held, 6))
        assert.equal(16.5, held.holdDeadline)
        assert.equal("keep", State.ClassifyExpiry(held, 14))
        assert.equal("keep", State.ClassifyExpiry(held, 16.4))
        assert.equal("retire", State.ClassifyExpiry(held, 16.5))

        -- A pause inside the hold defers the bound by the held interval.
        local paused = State.Start(store, "sentinel", "paused-hold", anchored, 10, 10, 0, true)
        State.BeginHold(paused, 6)
        State.Pause(store, "sentinel", "paused-hold", 15)
        assert.equal("keep", State.ClassifyExpiry(paused, 40))
        State.Resume(store, "sentinel", "paused-hold", 17)
        assert.equal("keep", State.ClassifyExpiry(paused, 18.4))
        assert.equal("retire", State.ClassifyExpiry(paused, 18.5))

        -- An anchored instance is classified by its anchored remaining only.
        local anchoredFirst = State.Start(store, "sentinel", "anchored-first", anchored, 10, 10, 0, true)
        State.BeginHold(anchoredFirst, 6)
        assert.equal(18, State.Anchor(anchoredFirst, 14))
        assert.is_nil(anchoredFirst.holdDeadline)
        assert.equal("keep", State.ClassifyExpiry(anchoredFirst, 17.9))
        assert.equal("retire", State.ClassifyExpiry(anchoredFirst, 18))

        -- Rows without anchor retire at zero exactly as before.
        local plainInstance = State.Start(store, "sentinel", "plain", plain, 10, 10, 0, true)
        assert.equal("keep", State.ClassifyExpiry(plainInstance, 13.9))
        assert.equal("retire", State.ClassifyExpiry(plainInstance, 14))
        assert.is_nil(plainInstance.holdDeadline)
    end)

    it("Confirm re-bases the anchored origin once after an anchor, refuses before an anchor, a second time and while paused, and keeps the extension", function()
        local store = State.New()
        State.AdmitOwner(store, "sentinel", 3207)
        local binding = {
            encounterId = 3207, key = 1253268, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = 1253268,
            extension = 4, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
            anchor = "timeline-finished", castConfirm = "boss-cast-start",
        }

        local instance = State.Start(store, "sentinel", "confirm", binding, 10, 10, 0, true)
        local early, earlyReason = State.Confirm(instance, 5)
        assert.is_nil(early)
        assert.equal("not-anchored", earlyReason)

        assert.equal(14, State.Anchor(instance, 10))
        assert.equal(15, State.Confirm(instance, 11))
        assert.equal(11, instance.anchorElapsed)
        assert.is_true(instance.confirmed)
        assert.equal(4, State.AnchoredRemaining(instance, 11))
        assert.equal("keep", State.ClassifyExpiry(instance, 14.9))
        assert.equal("retire", State.ClassifyExpiry(instance, 15))

        local second, secondReason = State.Confirm(instance, 12)
        assert.is_nil(second)
        assert.equal("already-confirmed", secondReason)
        assert.equal(11, instance.anchorElapsed)

        local pausedInstance = State.Start(store, "sentinel", "confirm-paused", binding, 10, 10, 0, true)
        State.Anchor(pausedInstance, 10)
        State.Pause(store, "sentinel", "confirm-paused", 10.5)
        local pausedTotal, pausedReason = State.Confirm(pausedInstance, 11)
        assert.is_nil(pausedTotal)
        assert.equal("paused", pausedReason)
        assert.equal(10, pausedInstance.anchorElapsed)
    end)

    it("explicit owner, encounter and global teardown clear the appropriate awaiting-stop buckets, including owners with no live instance", function()
        -- RetireOwner clears only that owner's bucket.
        local storeA = State.New()
        State.AdmitOwner(storeA, "ownerA", 3208)
        State.AdmitOwner(storeA, "ownerB", 3208)
        State.ObservePilotLabel(storeA, "ownerA", 3208, "Glacial Torment")
        State.ObservePilotLabel(storeA, "ownerB", 3208, "Glacial Torment")
        State.RetireOwner(storeA, "ownerA")
        State.AdmitOwner(storeA, "ownerA", 3208)
        assert.is_true(State.ObservePilotLabel(storeA, "ownerA", 3208, "Glacial Torment"))
        assert.is_false(State.ObservePilotLabel(storeA, "ownerB", 3208, "Glacial Torment"))

        -- RetireEncounter clears buckets for that encounter only, including
        -- an owner whose publication was filtered/expired and so has no
        -- live instance.
        local storeB = State.New()
        State.AdmitOwner(storeB, "ownerC", 3208)
        State.AdmitOwner(storeB, "ownerD", 9999)
        State.ObservePilotLabel(storeB, "ownerC", 3208, "Glacial Torment")
        State.ObservePilotLabel(storeB, "ownerD", 9999, "Glacial Torment")
        State.RetireEncounter(storeB, 3208)
        assertRefusal(State.ObservePilotLabel(storeB, "ownerC", 3208, "Glacial Torment"))
        State.AdmitOwner(storeB, "ownerC", 3208)
        assert.is_true(State.ObservePilotLabel(storeB, "ownerC", 3208, "Glacial Torment"))
        assert.is_false(State.ObservePilotLabel(storeB, "ownerD", 9999, "Glacial Torment"))

        -- RetireAll — the shared endpoint behind every profile/world/module
        -- teardown caller — clears the entire set unconditionally.
        local storeC = State.New()
        State.AdmitOwner(storeC, "ownerE", 3208)
        State.AdmitOwner(storeC, "ownerF", 9999)
        State.ObservePilotLabel(storeC, "ownerE", 3208, "Glacial Torment")
        State.ObservePilotLabel(storeC, "ownerF", 9999, "Raging Squall")
        State.RetireAll(storeC)
        assertRefusal(State.ObservePilotLabel(storeC, "ownerE", 3208, "Glacial Torment"))
        assertRefusal(State.ObservePilotLabel(storeC, "ownerF", 9999, "Raging Squall"))
        State.AdmitOwner(storeC, "ownerE", 3208)
        State.AdmitOwner(storeC, "ownerF", 9999)
        assert.is_true(State.ObservePilotLabel(storeC, "ownerE", 3208, "Glacial Torment"))
        assert.is_true(State.ObservePilotLabel(storeC, "ownerF", 9999, "Raging Squall"))
    end)

    it("awaiting-stop guard refuses invalid ordinary labels and absent/stale owner scopes without creating or clearing an entry", function()
        local store = State.New()
        State.AdmitOwner(store, "sentinel", 3208)

        for _, label in ipairs({ 12345, false, {} }) do
            local observed, reason = State.ObservePilotLabel(store, "sentinel", 3208, label)
            assertRefusal(observed, reason, "observe " .. type(label))
        end
        assertRefusal(State.ObservePilotLabel(store, "sentinel", 3208, nil))
        assertRefusal(State.ObservePilotLabel(store, "sentinel", 3208, ""))

        for _, label in ipairs({ 12345, false, {}, "" }) do
            assert.is_false(State.ResolveAwaitingStop(store, "sentinel", label))
        end
        assert.is_false(State.ResolveAwaitingStop(store, "sentinel", nil))

        -- An absent scope (owner never admitted) refuses to create an entry...
        assertRefusal(State.ObservePilotLabel(store, "neverAdmitted", 3208, "Glacial Torment"))

        -- ...and a stale scope (admitted under a different encounter)
        -- refuses too.
        assertRefusal(State.ObservePilotLabel(store, "sentinel", 9999, "Glacial Torment"))

        -- A scope invalidated by an encounter-epoch bump, not merely a
        -- mismatched encounterId, refuses the same way.
        local epochStore = State.New()
        State.AdmitOwner(epochStore, "epochStale", 3208)
        assert.is_true(State.ObservePilotLabel(epochStore, "epochStale", 3208, "Glacial Torment"))
        State.RetireEncounter(epochStore, 3208)
        assertRefusal(State.ObservePilotLabel(epochStore, "epochStale", 3208, "Glacial Torment"))

        -- None of the above created any entry: the label is still free.
        assert.is_true(State.ObservePilotLabel(store, "sentinel", 3208, "Glacial Torment"))

        -- A resolve for an owner who was never admitted cannot touch
        -- sentinel's outstanding label.
        assert.is_false(State.ResolveAwaitingStop(store, "neverAdmitted", "Glacial Torment"))
        assert.is_false(State.ObservePilotLabel(store, "sentinel", 3208, "Glacial Torment"))
    end)

    local SEQUEL_PARENT, SEQUEL_CHILD = 1243569, 1297797

    local function sequelParentRow(anchor, castConfirm)
        return { castDuration = 7, timerSource = {
            kind = "Timer", isCooldown = true, policy = "estimated-impact",
            spanMode = "remaining-only", stopTolerance = 0.15,
            collisionPolicy = "refuse-unresolved-label",
            anchor = anchor, castConfirm = castConfirm,
        } }
    end

    local function sequelChildRow(parent, after, castDuration, extra)
        local row = { castDuration = castDuration, timerSource = { kind = "Sequel", parent = parent, after = after } }
        for k, v in pairs(extra or {}) do row[k] = v end
        return row
    end

    local function withAnchoredParent(child)
        return { [SEQUEL_PARENT] = sequelParentRow("timeline-finished"), [SEQUEL_CHILD] = child }
    end

    local function sequelAnchoredBinding(ownsExpiry, admitsLateFinished)
        return {
            encounterId = 3209, key = SEQUEL_PARENT, kind = "Timer", discriminator = true,
            policy = "estimated-impact", spanMode = "remaining-only", curationId = SEQUEL_PARENT,
            extension = 7, stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
            anchor = "timeline-finished", ownsExpiry = ownsExpiry, admitsLateFinished = admitsLateFinished,
        }
    end

    it("BuildBindings installs one Sequel binding under an anchored unconfirmed explicit parent, no Timer binding for the child, and marks the parent ownsExpiry", function()
        local bindings = State.BuildBindings({
            [3209] = { timerPolicy = "explicit", spells = withAnchoredParent(sequelChildRow(SEQUEL_PARENT, 10, 5)) },
        })
        assert.same({
            encounterId = 3209, key = SEQUEL_CHILD, kind = "Sequel", curationId = SEQUEL_CHILD,
            parent = SEQUEL_PARENT, after = 10,
        }, bindings.sequels[3209][SEQUEL_PARENT])
        assert.is_nil(bindings.timers[3209][SEQUEL_CHILD])
        assert.is_true(bindings.timers[3209][SEQUEL_PARENT].ownsExpiry)
    end)

    it("BuildBindings refuses a Sequel with an invalid parent, timing or field, refuses both children of one parent, and leaves the parent unowned", function()
        local nan = 0 / 0
        local cases = {
            { name = "parent missing", spells = { [SEQUEL_CHILD] = sequelChildRow(SEQUEL_PARENT, 10, 5) } },
            { name = "parent refused by its own contract", spells = {
                [SEQUEL_PARENT] = { castDuration = -1, timerSource = sequelParentRow("timeline-finished").timerSource },
                [SEQUEL_CHILD] = sequelChildRow(SEQUEL_PARENT, 10, 5) } },
            { name = "parent unanchored", spells = {
                [SEQUEL_PARENT] = sequelParentRow(nil), [SEQUEL_CHILD] = sequelChildRow(SEQUEL_PARENT, 10, 5) } },
            { name = "parent confirmed", spells = {
                [SEQUEL_PARENT] = sequelParentRow("timeline-finished", "boss-cast-start"),
                [SEQUEL_CHILD] = sequelChildRow(SEQUEL_PARENT, 10, 5) } },
            { name = "child names itself", spells = withAnchoredParent(sequelChildRow(SEQUEL_CHILD, 10, 5)) },
            { name = "non-numeric parent", spells = withAnchoredParent(sequelChildRow(tostring(SEQUEL_PARENT), 10, 5)) },
            { name = "missing after", spells = withAnchoredParent(sequelChildRow(SEQUEL_PARENT, nil, 5)) },
            { name = "nan after", spells = withAnchoredParent(sequelChildRow(SEQUEL_PARENT, nan, 5)) },
            { name = "negative after", spells = withAnchoredParent(sequelChildRow(SEQUEL_PARENT, -1, 5)) },
            { name = "missing castDuration", spells = withAnchoredParent(sequelChildRow(SEQUEL_PARENT, 10, nil)) },
            { name = "negative castDuration", spells = withAnchoredParent(sequelChildRow(SEQUEL_PARENT, 10, -1)) },
            { name = "zero span", spells = withAnchoredParent(sequelChildRow(SEQUEL_PARENT, 0, 0)) },
            { name = "forbidden field",
              spells = withAnchoredParent(sequelChildRow(SEQUEL_PARENT, 10, 5, { channelDuration = 3 })) },
            { name = "extendByChannel",
              spells = withAnchoredParent(sequelChildRow(SEQUEL_PARENT, 10, 5, { extendByChannel = true })) },
            { name = "two children for one parent", spells = {
                [SEQUEL_PARENT] = sequelParentRow("timeline-finished"),
                [SEQUEL_CHILD] = sequelChildRow(SEQUEL_PARENT, 10, 5),
                [SEQUEL_CHILD + 1] = sequelChildRow(SEQUEL_PARENT, 8, 5) } },
        }
        for _, case in ipairs(cases) do
            local bindings = State.BuildBindings({ [3209] = { timerPolicy = "explicit", spells = case.spells } })
            assert.is_nil(bindings.sequels[3209], case.name)
            local parentBinding = bindings.timers[3209] and bindings.timers[3209][SEQUEL_PARENT]
            assert.is_nil(parentBinding and parentBinding.ownsExpiry, case.name)
        end
    end)

    it("PlanSequel ends at the anchor plus after plus extension, reveals one window earlier or at the anchor when the window is zero or covers the span, and refuses invalid input", function()
        local cases = {
            { name = "default span, window inside", after = 10, extension = 5, window = 5, reveal = 110, finish = 115 },
            { name = "minimum span, window inside", after = 10, extension = 2, window = 5, reveal = 107, finish = 112 },
            { name = "zero window", after = 10, extension = 5, window = 0, reveal = 100, finish = 115 },
            { name = "window equals span", after = 10, extension = 5, window = 15, reveal = 100, finish = 115 },
            { name = "window above span", after = 10, extension = 10, window = 30, reveal = 100, finish = 120 },
        }
        for _, case in ipairs(cases) do
            local revealAt, endAt = State.PlanSequel(100, case.after, case.extension, case.window)
            assert.equal(case.reveal, revealAt, case.name)
            assert.equal(case.finish, endAt, case.name)
        end

        local nan = 0 / 0
        local refusals = {
            { name = "nan now", now = nan, after = 10, extension = 5, window = 5 },
            { name = "negative after", now = 100, after = -1, extension = 5, window = 5 },
            { name = "nan extension", now = 100, after = 10, extension = nan, window = 5 },
            { name = "missing window", now = 100, after = 10, extension = 5 },
            { name = "zero span", now = 100, after = 0, extension = 0, window = 5 },
        }
        for _, case in ipairs(refusals) do
            local revealAt, reason = State.PlanSequel(case.now, case.after, case.extension, case.window)
            assertRefusal(revealAt, reason, case.name)
        end
    end)

    it("ClassifyExpiry leaves an ownsExpiry instance's forecast-zero decision to its owner, then applies the hold bound; an unowned instance still reports hold-eligible", function()
        local store = State.New()
        State.AdmitOwner(store, "nalorakk", 3209)
        -- receipt 0, remaining 10, extension 7: forecast zero at 17; hold
        -- with queue 8 ends at 10 + 8 + 0.5 = 18.5 on the elapsed clock.
        local cases = {
            { name = "owned", ownsExpiry = true, atZero = "keep" },
            { name = "unowned", ownsExpiry = nil, atZero = "hold-eligible" },
        }
        for _, case in ipairs(cases) do
            local instance = State.Start(store, "nalorakk", case.name, sequelAnchoredBinding(case.ownsExpiry), 10, 10, 0, true)
            assert.equal("keep", State.ClassifyExpiry(instance, 16.9), case.name)
            assert.equal(case.atZero, State.ClassifyExpiry(instance, 17), case.name)
            assert.equal(18.5, State.BeginHold(instance, 8), case.name)
            assert.equal("keep", State.ClassifyExpiry(instance, 18.4), case.name)
            assert.equal("retire", State.ClassifyExpiry(instance, 18.5), case.name)
        end
    end)

    it("ClassifyStop refuses an unheld Finished on an ownsExpiry instance at or past forecast zero, keeps the hold bound, and leaves unowned rows and owned rows admitting a late Finished on the base rule", function()
        local store = State.New()
        State.AdmitOwner(store, "nalorakk", 3209)
        local function start(label, ownsExpiry, admitsLateFinished)
            return State.Start(store, "nalorakk", label, sequelAnchoredBinding(ownsExpiry, admitsLateFinished),
                10, 10, 0, true)
        end
        -- receipt 0, remaining 10, extension 7: forecast zero at 17.
        local unheld = {
            { name = "owned before zero", ownsExpiry = true, at = 16.9, want = "anchor" },
            { name = "owned at zero", ownsExpiry = true, at = 17, want = "retire" },
            { name = "owned past zero", ownsExpiry = true, at = 19, want = "retire" },
            { name = "owned admitting a late Finished at zero", ownsExpiry = true, admits = true, at = 17,
              want = "anchor" },
            { name = "unowned past zero", ownsExpiry = nil, at = 19, want = "anchor" },
        }
        for _, case in ipairs(unheld) do
            local instance = start(case.name, case.ownsExpiry, case.admits)
            assert.equal(case.want, State.ClassifyStop(instance, case.at, nil, "finished"), case.name)
        end

        -- Elapsed is frozen at the pause, so the stop time past it does not count.
        local paused = {
            { name = "owned paused before zero", pauseAt = 16, want = "resume-and-anchor" },
            { name = "owned paused past zero", pauseAt = 17.5, want = "retire" },
        }
        for _, case in ipairs(paused) do
            local instance = start(case.name, true)
            State.Pause(store, "nalorakk", case.name, case.pauseAt)
            assert.equal(case.want, State.ClassifyStop(instance, 30, nil, "finished"), case.name)
        end

        local held = start("owned held", true)
        assert.equal(18.5, State.BeginHold(held, 8))
        assert.equal("anchor", State.ClassifyStop(held, 18, nil, "finished"))
        assert.equal("retire", State.ClassifyStop(held, 18.5, nil, "finished"))
    end)

    local CUE_ENC, CUE_KEY = 77, 9001

    local function cueTimerRow(extra)
        local contract = {
            kind = "Timer", isCooldown = true, policy = "estimated-impact",
            spanMode = "remaining-only", stopTolerance = 0.15,
            collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished",
        }
        for k, v in pairs(extra or {}) do contract[k] = v end
        return { castDuration = 4, timerSource = contract }
    end

    local function messageCue(extra)
        local cue = { name = "Window", iconOverride = 134400, duration = 20,
                      source = { kind = "Message", key = CUE_KEY } }
        for k, v in pairs(extra or {}) do cue[k] = v end
        return cue
    end

    local function timerCue(extra)
        local cue = { name = "Phase", iconOverride = 134400,
                      source = { kind = "Timer", key = CUE_KEY, isCooldown = false } }
        for k, v in pairs(extra or {}) do cue[k] = v end
        return cue
    end

    local function sequelCue(extra)
        local cue = { name = "Lockout", iconOverride = 134400, duration = 10,
                      source = { kind = "Sequel", parent = CUE_KEY, after = 0 } }
        for k, v in pairs(extra or {}) do cue[k] = v end
        return cue
    end

    local function cueWithout(cue, field)
        cue[field] = nil
        return cue
    end

    local function buildCues(phaseCues, spells)
        return State.BuildBindings({
            [CUE_ENC] = { timerPolicy = "explicit", spells = spells or {}, phaseCues = phaseCues },
        })
    end

    it("numbered sounds require a complete ordinal Message mapping and a usable fallback", function()
        local changes = {
            { name = "valid", allowed = true },
            { name = "not ordinal", clear = "ordinals" },
            { name = "Timer", kind = "Timer" },
            { name = "Sequel", kind = "Sequel" },
            { name = "no fallback", clear = "sound" },
            { name = "muted fallback", fallback = "None" },
            { name = "empty fallback", fallback = "" },
            { name = "scalar mapping", sounds = false },
            { name = "hole", sounds = { [1] = "First", [3] = "Third" } },
            { name = "empty value", sounds = { "First", "", "Third" } },
            { name = "muted value", sounds = { "First", "None", "Third" } },
            { name = "non-string value", sounds = { "First", 2, "Third" } },
            { name = "extra ordinal", sounds = { "First", "Second", "Third", "Fourth" } },
            { name = "string index", sounds = { "First", "Second", "Third", extra = "Other" } },
            { name = "fractional index", sounds = { "First", "Second", "Third", [1.5] = "Other" } },
            { name = "zero index", sounds = { "First", "Second", "Third", [0] = "Other" } },
        }
        for _, change in ipairs(changes) do
            local cue = messageCue({ ordinals = 3, sound = "Fallback",
                ordinalSounds = { "First", "Second", "Third" } })
            if change.clear then cue[change.clear] = nil end
            if change.kind then cue.source.kind = change.kind end
            if change.fallback ~= nil then cue.sound = change.fallback end
            if change.sounds ~= nil then cue.ordinalSounds = change.sounds end
            local bindings = buildCues({ window = cue }, { [CUE_KEY] = cueTimerRow() })
            if change.allowed then
                assert.is_not_nil(bindings.messages[CUE_ENC], change.name)
                assert.is_not_nil(bindings.messages[CUE_ENC][CUE_KEY], change.name)
            else
                assert.is_nil(bindings.messages[CUE_ENC], change.name)
                assert.is_nil(bindings.phaseTimers[CUE_ENC], change.name)
                assert.is_nil(bindings.sequels[CUE_ENC], change.name)
            end
        end
    end)

    it("interrupt results require a last-ordinal Message cue and a bounded boss result", function()
        local changes = {
            { name = "valid", allowed = true },
            { name = "not an ordinal", ordinals = false },
            { name = "earlier ordinal", field = "ordinal", value = 2 },
            { name = "wrong unit", field = "unit", value = "target" },
            { name = "empty result", field = "displayText", value = "" },
            { name = "zero duration", field = "duration", value = 0 },
            { name = "invalid color", field = "color", value = { 0, 2, 0 } },
            { name = "non Message", timer = true },
        }
        for _, case in ipairs(changes) do
            local result = { ordinal = 3, unit = "boss1", displayText = "DONE", duration = 1.5, color = { 0, 1, 0 } }
            if case.field then result[case.field] = case.value end
            local cue = messageCue({ ordinals = 3, interruptResult = result })
            if case.ordinals == false then cue.ordinals = nil end
            if case.timer then cue = timerCue({ ordinals = 3, interruptResult = result }) end
            local bindings = buildCues({ window = cue })
            local present = bindings.messages[CUE_ENC] and bindings.messages[CUE_ENC][CUE_KEY] ~= nil
            assert.equal(case.allowed == true, present == true, case.name)
        end
    end)

    it("interrupt matching requires both IDs, the unit, current scope and generation, an unexpired window and no prior completion", function()
        local cases = {
            { name = "match", allowed = true },
            { name = "other ID", id = 12 },
            { name = "missing event ID", id = false },
            { name = "missing snapshot ID", snapshot = false },
            { name = "other unit", unit = "boss2" },
            { name = "before receipt", now = -1 },
            { name = "at deadline", now = 4 },
            { name = "already consumed", completed = true },
            { name = "new generation", replace = true },
            { name = "owner retired", retire = true },
            { name = "equal string IDs", allowed = true, snapshotId = "cast-11", id = "cast-11" },
            { name = "other string ID", snapshotId = "cast-11", id = "cast-12" },
            { name = "number against its string spelling", snapshotId = "11", id = 11 },
            { name = "empty IDs", snapshotId = "", id = "" },
        }
        for _, case in ipairs(cases) do
            local store = State.New()
            local scope = State.AdmitOwner(store, "owner", CUE_ENC)
            local generation = State.NextSlot(store, "owner", "cue", "kick#plan")
            local watch = { owner = "owner", scope = scope, slotKey = "kick#plan", generation = generation,
                startedAt = 0, endAt = 4, unit = "boss1", castBarID = 11, completed = case.completed }
            local id = case.id or 11
            if case.id == false then id = nil end
            if case.snapshot == false then watch.castBarID = nil end
            if case.snapshotId ~= nil then watch.castBarID = case.snapshotId end
            if case.replace then State.NextSlot(store, "owner", "cue", "kick#plan") end
            if case.retire then State.RetireOwner(store, "owner") end
            assert.equal(case.allowed == true,
                State.MatchCueInterrupt(store, watch, case.unit or "boss1", id, case.now or 1), case.name)
        end
    end)

    it("a cast ID is a nonempty string or a finite number, never converted", function()
        local cases = {
            { name = "string", value = "cast-11", allowed = true },
            { name = "number", value = 11, allowed = true },
            { name = "empty string", value = "" },
            { name = "NaN", value = 0 / 0 },
            { name = "infinity", value = math.huge },
            { name = "negative infinity", value = -math.huge },
            { name = "nil", value = nil },
            { name = "boolean", value = true },
            { name = "table", value = {} },
        }
        for _, case in ipairs(cases) do
            assert.equal(case.allowed == true, State.IsCastBarId(case.value), case.name)
        end
    end)

    it("a kick Message is a duplicate when the cue's current watch holds its cast ID, or completed that kick number and the Message has no ID", function()
        local cases = {
            { name = "same ID, same ordinal", duplicate = true },
            { name = "same ID, other ordinal", ordinal = 3, duplicate = true },
            { name = "missing ID, same completed ordinal", id = false, completed = true, duplicate = true },
            { name = "missing ID, other completed ordinal", id = false, completed = true, ordinal = 2 },
            { name = "different ID", id = "cast-12", completed = true },
            { name = "expired watch", now = 4 },
        }
        for _, case in ipairs(cases) do
            local store = State.New()
            local scope = State.AdmitOwner(store, "owner", CUE_ENC)
            local generation = State.NextSlot(store, "owner", "cue", "kick#plan")
            local watch = { owner = "owner", scope = scope, slotKey = "kick#plan", generation = generation,
                startedAt = 0, endAt = 4, unit = "boss1", castBarID = "cast-11", ordinal = 1,
                completed = case.completed }
            local id = case.id or "cast-11"
            if case.id == false then id = nil end
            assert.equal(case.duplicate == true,
                State.IsCueMessageDuplicate(store, watch, case.ordinal or 1, id, case.now or 1), case.name)
        end
    end)

    it("BuildBindings installs one Message binding for a valid Message cue and nothing for a malformed cue", function()
        local good = buildCues({ window = messageCue({
            leadDelay = 1.7, maxPerPull = 4, prepareText = "SOON", endedText = "ENDED", endedDuration = 2,
        }) })
        assert.same({
            encounterId = CUE_ENC, key = CUE_KEY, kind = "Message",
            curationId = "cue:77:window", cueKey = "cue:77:window",
        }, good.messages[CUE_ENC][CUE_KEY])

        local parent = { [CUE_KEY] = cueTimerRow() }
        local cases = {
            { name = "bad name", cues = { ["Bad Name"] = messageCue() } },
            { name = "missing display name", cues = { window = cueWithout(messageCue(), "name") } },
            { name = "missing icon", cues = { window = cueWithout(messageCue(), "iconOverride") } },
            { name = "missing key", cues = { window = messageCue({ source = { kind = "Message" } }) } },
            { name = "non-numeric key",
              cues = { window = messageCue({ source = { kind = "Message", key = "9001" } }) } },
            { name = "missing duration", cues = { window = cueWithout(messageCue(), "duration") } },
            { name = "zero duration", cues = { window = messageCue({ duration = 0 }) } },
            { name = "negative lead", cues = { window = messageCue({ leadDelay = -1 }) } },
            { name = "zero cap", cues = { window = messageCue({ maxPerPull = 0 }) } },
            { name = "fractional cap", cues = { window = messageCue({ maxPerPull = 1.5 }) } },
            { name = "cap on a Timer cue", cues = { window = timerCue({ maxPerPull = 2 }) } },
            { name = "cap on a Sequel cue", cues = { window = sequelCue({ maxPerPull = 2 }) }, spells = parent },
            { name = "prepare text without a lead", cues = { window = messageCue({ prepareText = "SOON" }) } },
            { name = "prepare text with a zero lead",
              cues = { window = messageCue({ prepareText = "SOON", leadDelay = 0 }) } },
            { name = "prepare text on a Timer cue", cues = { window = timerCue({ prepareText = "SOON" }) } },
            { name = "prepare text on a Sequel cue",
              cues = { window = sequelCue({ prepareText = "SOON" }) }, spells = parent },
            { name = "ended text without a duration", cues = { window = messageCue({ endedText = "ENDED" }) } },
            { name = "ended duration without a text", cues = { window = messageCue({ endedDuration = 2 }) } },
            { name = "duration on a Timer cue", cues = { window = timerCue({ duration = 15 }) } },
            { name = "refused field", cues = { window = messageCue({ castDuration = 3 }) } },
        }
        for _, case in ipairs(cases) do
            local bindings = buildCues(case.cues, case.spells)
            assert.is_nil(bindings.messages[CUE_ENC], case.name)
            assert.is_nil(bindings.phaseTimers[CUE_ENC], case.name)
            assert.is_nil(bindings.sequels[CUE_ENC], case.name)
        end

        local legacy = State.BuildBindings({ [CUE_ENC] = { spells = {}, phaseCues = { window = messageCue() } } })
        assert.is_nil(legacy.messages[CUE_ENC], "non-explicit encounter")
    end)

    it("MatchMessageOrdinal returns the ordinal whose provider text equals the message", function()
        local fullwidth = "%s\239\188\136%d/%d\239\188\137"
        local cases = {
            { template = "%s (%d/%d)", rename = "Toxic Atrophy", message = "Toxic Atrophy (1/3)", want = 1 },
            { template = "%s (%d/%d)", rename = "Toxic Atrophy", message = "Toxic Atrophy (2/3)", want = 2 },
            { template = "%s (%d/%d)", rename = "Toxic Atrophy", message = "Toxic Atrophy (3/3)", want = 3 },
            { template = fullwidth, rename = "Toxic Atrophy", message = "Toxic Atrophy\239\188\1362/3\239\188\137", want = 2 },
            { template = "%s (%d/%d)", rename = "Kick 1 at 100%", message = "Kick 1 at 100% (3/3)", want = 3 },
        }
        for _, case in ipairs(cases) do
            assert.equal(case.want, State.MatchMessageOrdinal(case.message, case.template, case.rename, 3), case.message)
        end
    end)

    it("MatchMessageOrdinal refuses a message equal to no ordinal's text", function()
        for _, message in ipairs({ "Toxic Atrophy (4/3)", "Venom Jet (1/3)", "" }) do
            local ordinal, reason = State.MatchMessageOrdinal(message, "%s (%d/%d)", "Toxic Atrophy", 3)
            assertRefusal(ordinal, reason, message)
            assert.equal("unmatched", reason, message)
        end
    end)

    it("MatchMessageOrdinal refuses a template that gives two ordinals the message's text", function()
        local ordinal, reason = State.MatchMessageOrdinal("Toxic Atrophy", "%s", "Toxic Atrophy", 3)
        assertRefusal(ordinal, reason, "ambiguous")
        assert.equal("ambiguous", reason)
    end)

    it("MatchMessageOrdinal refuses malformed input, including a total outside whole 2 to 9, before formatting", function()
        local function call(field, value)
            local args = { message = "Toxic Atrophy (1/3)", template = "%s (%d/%d)", rename = "Toxic Atrophy", total = 3 }
            args[field] = value
            return State.MatchMessageOrdinal(args.message, args.template, args.rename, args.total)
        end
        local cases = {
            { field = "message", value = 13 },
            { field = "message" },
            { field = "template", value = false },
            { field = "rename", value = "" },
            { field = "rename" },
            { field = "total", value = 1 },
            { field = "total", value = 10 },
            { field = "total", value = 2.5 },
            { field = "total", value = "3" },
        }
        for _, case in ipairs(cases) do
            local label = case.field .. "=" .. tostring(case.value)
            local ordinal, reason = call(case.field, case.value)
            assertRefusal(ordinal, reason, label)
            assert.equal("invalid-input", reason, label)
        end
    end)

    it("MatchMessageOrdinal refuses a template whose format raises", function()
        local ordinal, reason = State.MatchMessageOrdinal("Toxic Atrophy (1/3)", "%d (%d/%d)", "Toxic Atrophy", 3)
        assertRefusal(ordinal, reason, "raising template")
        assert.equal("template-error", reason)
    end)

    it("MatchMessageCount accepts only the message equal to the provider's count text for its number", function()
        assert.equal(1, State.MatchMessageCount("Ravenous Stomp (1)", "%s (%d)", "Ravenous Stomp", 1))
        local cases = {
            { args = { "Ravenous Stomp (2)", "%s (%d)", "Ravenous Stomp", 1 }, reason = "unmatched" },
            { args = { "Fresh Meat (1)", "%s (%d)", "Ravenous Stomp", 1 }, reason = "unmatched" },
            { args = { 7, "%s (%d)", "Ravenous Stomp", 1 }, reason = "invalid-input" },
            { args = { "Ravenous Stomp (1)", false, "Ravenous Stomp", 1 }, reason = "invalid-input" },
            { args = { "Ravenous Stomp (1)", "%s (%d)", "", 1 }, reason = "invalid-input" },
            { args = { "Ravenous Stomp (0)", "%s (%d)", "Ravenous Stomp", 0 }, reason = "invalid-input" },
            { args = { "Ravenous Stomp (10)", "%s (%d)", "Ravenous Stomp", 10 }, reason = "invalid-input" },
            { args = { "Ravenous Stomp (1)", "%d (%d)", "Ravenous Stomp", 1 }, reason = "template-error" },
        }
        for i, case in ipairs(cases) do
            local label = "case " .. i
            local n, reason = State.MatchMessageCount(case.args[1], case.args[2], case.args[3], case.args[4])
            assertRefusal(n, reason, label)
            assert.equal(case.reason, reason, label)
        end
    end)

    it("BuildBindings installs a Message cue carrying whole ordinals from 2 to 9 or a whole messageCount from 1 to 9", function()
        local cases = {
            { name = "ordinals 2", fields = { ordinals = 2 } },
            { name = "ordinals 9", fields = { ordinals = 9 } },
            { name = "count 1 with a cap", fields = { messageCount = 1, maxPerPull = 1 } },
            { name = "count 9", fields = { messageCount = 9 } },
        }
        for _, case in ipairs(cases) do
            local bindings = buildCues({ window = messageCue(case.fields) })
            assert.equal("cue:77:window", bindings.messages[CUE_ENC][CUE_KEY].cueKey, case.name)
        end
    end)

    it("BuildBindings refuses a cue whose ordinals or messageCount are out of range or not whole or sit on a Timer or Sequel source, whose ordinals come with a lead, cap, prepare text, gate, ended text or messageCount", function()
        local parent = { [CUE_KEY] = cueTimerRow() }
        local cases = {
            { name = "one", cues = { window = messageCue({ ordinals = 1 }) } },
            { name = "ten", cues = { window = messageCue({ ordinals = 10 }) } },
            { name = "fractional", cues = { window = messageCue({ ordinals = 2.5 }) } },
            { name = "string", cues = { window = messageCue({ ordinals = "3" }) } },
            { name = "Timer source", cues = { window = timerCue({ ordinals = 3 }) } },
            { name = "Sequel source", cues = { window = sequelCue({ ordinals = 3 }) }, spells = parent },
            { name = "lead", cues = { window = messageCue({ ordinals = 3, leadDelay = 1 }) } },
            { name = "cap", cues = { window = messageCue({ ordinals = 3, maxPerPull = 3 }) } },
            { name = "prepare text",
              cues = { window = messageCue({ ordinals = 3, leadDelay = 1, prepareText = "SOON" }) } },
            { name = "gate", cues = { window = messageCue({ ordinals = 3, hidesForecasts = { CUE_KEY } }) },
              spells = parent },
            { name = "ended text",
              cues = { window = messageCue({ ordinals = 3, endedText = "ENDED", endedDuration = 2 }) } },
            { name = "ordinals with a count", cues = { window = messageCue({ ordinals = 3, messageCount = 1 }) } },
            { name = "count zero", cues = { window = messageCue({ messageCount = 0 }) } },
            { name = "count ten", cues = { window = messageCue({ messageCount = 10 }) } },
            { name = "count fractional", cues = { window = messageCue({ messageCount = 1.5 }) } },
            { name = "count string", cues = { window = messageCue({ messageCount = "1" }) } },
            { name = "count on Timer source", cues = { window = timerCue({ messageCount = 1 }) } },
            { name = "count on Sequel source", cues = { window = sequelCue({ messageCount = 1 }) }, spells = parent },
        }
        for _, case in ipairs(cases) do
            local bindings = buildCues(case.cues, case.spells)
            assert.is_nil(bindings.messages[CUE_ENC], case.name)
            assert.is_nil(bindings.phaseTimers[CUE_ENC], case.name)
            assert.is_nil(bindings.sequels[CUE_ENC], case.name)
        end
    end)

    it("BuildBindings carries pullReceipt on a Message cue and an unanchored explicit row, and refuses it anchored, on another cue source or other than true", function()
        local unanchored = cueTimerRow({ pullReceipt = true })
        unanchored.timerSource.anchor = nil
        local good = buildCues({ window = messageCue({ pullReceipt = true }) }, { [CUE_KEY] = unanchored })
        assert.is_true(good.messages[CUE_ENC][CUE_KEY].pullReceipt)
        assert.is_true(good.timers[CUE_ENC][CUE_KEY].pullReceipt)

        local loose = cueTimerRow({ pullReceipt = 1 })
        loose.timerSource.anchor = nil
        local rows = {
            { name = "anchored row", spells = { [CUE_KEY] = cueTimerRow({ pullReceipt = true }) } },
            { name = "row value", spells = { [CUE_KEY] = loose } },
        }
        for _, case in ipairs(rows) do
            local bindings = buildCues({}, case.spells)
            assert.is_nil((bindings.timers[CUE_ENC] or {})[CUE_KEY], case.name)
        end

        local cues = {
            { name = "cue value", cues = { window = messageCue({ pullReceipt = "yes" }) } },
            { name = "Timer source", cues = { window = timerCue({ pullReceipt = true }) } },
            { name = "Sequel source", cues = { window = sequelCue({ pullReceipt = true }) },
              spells = { [CUE_KEY] = cueTimerRow() } },
        }
        for _, case in ipairs(cues) do
            local bindings = buildCues(case.cues, case.spells)
            assert.is_nil(bindings.messages[CUE_ENC], case.name)
            assert.is_nil(bindings.phaseTimers[CUE_ENC], case.name)
            assert.is_nil(bindings.sequels[CUE_ENC], case.name)
        end
    end)

    it("a non-cooldown Timer cue and a cooldown row on one key both install and resolve by isCooldown", function()
        local bindings = buildCues({ phase = timerCue() }, { [CUE_KEY] = cueTimerRow() })
        local cue = State.ResolveBinding(bindings, { CUE_ENC }, CUE_ENC, "Timer", CUE_KEY, false)
        assert.equal("cue:77:phase", cue.cueKey)
        assert.equal(0, cue.extension)
        local row = State.ResolveBinding(bindings, { CUE_ENC }, CUE_ENC, "Timer", CUE_KEY, true)
        assert.equal(CUE_KEY, row.curationId)
        assert.is_nil(row.cueKey)
    end)

    it("a key with only a cooldown row refuses a non-cooldown Timer", function()
        local bindings = buildCues(nil, { [CUE_KEY] = cueTimerRow() })
        local binding, reason = State.ResolveBinding(bindings, { CUE_ENC }, CUE_ENC, "Timer", CUE_KEY, false)
        assertRefusal(binding, reason, "non-cooldown Timer on a cooldown-only key")
    end)

    it("two cues naming one source install neither", function()
        local cases = {
            { name = "Message", cues = { a = messageCue(), b = messageCue() } },
            { name = "Timer", cues = { a = timerCue(), b = timerCue() } },
            { name = "Sequel", cues = { a = sequelCue(), b = sequelCue() } },
        }
        for _, case in ipairs(cases) do
            local bindings = buildCues(case.cues, { [CUE_KEY] = cueTimerRow() })
            assert.is_nil(bindings.messages[CUE_ENC], case.name)
            assert.is_nil(bindings.phaseTimers[CUE_ENC], case.name)
            assert.is_nil(bindings.sequels[CUE_ENC], case.name)
            assert.is_nil(bindings.timers[CUE_ENC][CUE_KEY].ownsExpiry, case.name)
        end
    end)

    it("a Sequel cue installs under its parent and marks it owned; a parent claimed by a cue and a Sequel row gets neither", function()
        local bindings = buildCues({ lockout = sequelCue({ endedText = "ENDED", endedDuration = 2 }) },
            { [CUE_KEY] = cueTimerRow() })
        assert.same({
            encounterId = CUE_ENC, key = "cue:77:lockout", kind = "Sequel", curationId = "cue:77:lockout",
            cueKey = "cue:77:lockout", parent = CUE_KEY, after = 0, duration = 10,
        }, bindings.sequels[CUE_ENC][CUE_KEY])
        assert.is_true(bindings.timers[CUE_ENC][CUE_KEY].ownsExpiry)

        local mixed = buildCues({ lockout = sequelCue() }, {
            [CUE_KEY] = cueTimerRow(),
            [CUE_KEY + 1] = { castDuration = 5, timerSource = { kind = "Sequel", parent = CUE_KEY, after = 10 } },
        })
        assert.is_nil(mixed.sequels[CUE_ENC])
        assert.is_nil(mixed.timers[CUE_ENC][CUE_KEY].ownsExpiry)
    end)

    it("BuildBindings accepts endedColor only as an in-range triple beside endedText, and endsOnAnchor only on a Sequel cue naming another anchored unconfirmed row, which lists the cue under that row", function()
        local ENDER = CUE_KEY + 5
        local function rows(enderRow)
            return { [CUE_KEY] = cueTimerRow(), [ENDER] = enderRow or cueTimerRow() }
        end
        local good = buildCues({
            lockout = sequelCue({ endedText = "ENDED", endedDuration = 2,
                endedColor = { 0.1, 0.9, 0.3 }, endsOnAnchor = ENDER }),
            guard = { name = "Guard", iconOverride = 134400, duration = 10,
                      source = { kind = "Sequel", parent = ENDER, after = 0 } },
        }, rows())
        assert.equal("cue:77:lockout", good.sequels[CUE_ENC][CUE_KEY].cueKey)
        assert.same({ "cue:77:lockout" }, good.cueEnders[CUE_ENC][ENDER])
        assert.same({ "cue:77:lockout" }, good.cuesEndedByWindow["cue:77:guard"])
        local message = buildCues({ window = messageCue({ endedText = "ENDED", endedDuration = 2,
            endedColor = { 0, 1, 0 } }) })
        assert.equal("cue:77:window", message.messages[CUE_ENC][CUE_KEY].cueKey)

        local unanchored = cueTimerRow()
        unanchored.timerSource.anchor = nil
        local function colored(color)
            return sequelCue({ endedText = "ENDED", endedDuration = 2, endedColor = color })
        end
        local cases = {
            { name = "color without ended text", cue = sequelCue({ endedColor = { 0, 1, 0 } }) },
            { name = "two components", cue = colored({ 0, 1 }) },
            { name = "four components", cue = colored({ 0, 1, 0, 1 }) },
            { name = "non-number component", cue = colored({ 0, "1", 0 }) },
            { name = "component above one", cue = colored({ 0, 1.5, 0 }) },
            { name = "negative component", cue = colored({ -0.1, 1, 0 }) },
            { name = "color not a table", cue = colored("green") },
            { name = "ender on a Message cue", cue = messageCue({ endsOnAnchor = ENDER }) },
            { name = "non-numeric ender", cue = sequelCue({ endsOnAnchor = "ender" }) },
            { name = "unknown ender", cue = sequelCue({ endsOnAnchor = CUE_KEY + 9 }) },
            { name = "ender without an anchor", cue = sequelCue({ endsOnAnchor = ENDER }), spells = rows(unanchored) },
            { name = "ender with a cast confirm", cue = sequelCue({ endsOnAnchor = ENDER }),
              spells = rows(cueTimerRow({ castConfirm = "boss-cast-start" })) },
            { name = "ender is the parent", cue = sequelCue({ endsOnAnchor = CUE_KEY }) },
        }
        for _, case in ipairs(cases) do
            local bindings = buildCues({ lockout = case.cue }, case.spells or rows())
            assert.is_nil(bindings.messages[CUE_ENC], case.name)
            assert.is_nil(bindings.sequels[CUE_ENC], case.name)
            assert.is_nil(bindings.cueEnders[CUE_ENC], case.name)
            assert.is_nil(next(bindings.cuesEndedByWindow), case.name)
        end
    end)

    it("ClassifyStop retires a pausedStop row on a Paused event inside the keep-estimate interval, keeps the estimate without it, and never anchors on Paused", function()
        local store = State.New()
        State.AdmitOwner(store, "xathuux", CUE_ENC)
        local cases = {
            { name = "opted in", pausedStop = "retire", want = "retire" },
            { name = "not opted in", want = "keep-estimate" },
        }
        for _, case in ipairs(cases) do
            local bindings = buildCues(nil, { [CUE_KEY] = cueTimerRow({ pausedStop = case.pausedStop }) })
            local instance = State.Start(store, "xathuux", case.name, bindings.timers[CUE_ENC][CUE_KEY], 10, 10, 0, true)
            -- receipt 0, deadline 10, extension 4: 11 is inside the keep interval.
            assert.equal(case.want, State.ClassifyStop(instance, 11, nil, "paused"), case.name)
        end
    end)

    it("AdmitCue accepts up to the cap then refuses, never refuses without a cap, and resets only at encounter boundaries", function()
        local store = State.New()
        State.AdmitOwner(store, "kystia", CUE_ENC)
        local key = "cue:77:window"
        for n = 1, 4 do
            assert.is_true(State.AdmitCue(store, CUE_ENC, key, 4), "admission " .. n)
        end
        local ok, reason = State.AdmitCue(store, CUE_ENC, key, 4)
        assert.is_false(ok)
        assert.equal("over-cap", reason)
        for n = 1, 6 do
            assert.is_true(State.AdmitCue(store, CUE_ENC, "cue:77:uncapped", nil), "uncapped " .. n)
        end

        State.RetireOwner(store, "kystia")
        State.AdmitOwner(store, "kystia", CUE_ENC)
        assert.is_false((State.AdmitCue(store, CUE_ENC, key, 4)))

        State.RetireEncounter(store, CUE_ENC)
        assert.is_true(State.AdmitCue(store, CUE_ENC, key, 4))
        State.ClearCueCounts(store, CUE_ENC)
        for n = 1, 4 do
            assert.is_true(State.AdmitCue(store, CUE_ENC, key, 4), "after clear " .. n)
        end
    end)

    it("an unowned zero-extension anchored row anchors on a Finished stop before forecast zero and "
        .. "then retires, anchors from a hold before its bound and retires at it, and retires on a stop "
        .. "that is not Finished", function()
        local store = State.New()
        State.AdmitOwner(store, "kystia", CUE_ENC)
        local row = cueTimerRow()
        row.castDuration = 0
        local binding = buildCues(nil, { [CUE_KEY] = row }).timers[CUE_ENC][CUE_KEY]
        local function start(label)
            return State.Start(store, "kystia", label, binding, 10, 10, 0, true)
        end

        -- receipt 0, remaining 10, extension 0: forecast zero at 10; a hold
        -- with queue 6 ends at 10 + 6 + 0.5 = 16.5 on the elapsed clock.
        local early = start("stop first")
        assert.equal("anchor", State.ClassifyStop(early, 9, nil, "finished"))
        assert.equal(9, State.Anchor(early, 9))
        assert.equal("retire", State.ClassifyExpiry(early, 9))

        local held = start("expiry first")
        assert.equal("hold-eligible", State.ClassifyExpiry(held, 10))
        assert.equal(16.5, State.BeginHold(held, 6))
        assert.equal("keep", State.ClassifyExpiry(held, 12))
        assert.equal("anchor", State.ClassifyStop(held, 12, nil, "finished"))

        local overdue = start("at the bound")
        assert.equal(16.5, State.BeginHold(overdue, 6))
        assert.equal("retire", State.ClassifyStop(overdue, 16.5, nil, "finished"))

        local stops = {
            { name = "canceled before zero", at = 9, state = "canceled" },
            { name = "unresolved before zero", at = 9 },
            { name = "unresolved while held", at = 12, hold = true },
        }
        for _, case in ipairs(stops) do
            local instance = start(case.name)
            if case.hold then State.BeginHold(instance, 6) end
            assert.equal("retire", State.ClassifyStop(instance, case.at, nil, case.state), case.name)
        end
    end)

    local QUEUE_ENC, QUEUE_PARENT, QUEUE_TARGET = 3103, 473898, 1295453

    local function queueRow(extra)
        local contract = {
            kind = "Timer", isCooldown = true, policy = "estimated-impact",
            spanMode = "remaining-only", stopTolerance = 0.15,
            collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished",
        }
        for k, v in pairs(extra or {}) do contract[k] = v end
        return { castDuration = 3, timerSource = contract }
    end

    local function buildQueue(spells)
        return State.BuildBindings({ [QUEUE_ENC] = { timerPolicy = "explicit", spells = spells } })
    end

    local function queueBindings()
        return buildQueue({
            [QUEUE_PARENT] = queueRow(),
            [QUEUE_TARGET] = queueRow({ queueAfter = { parent = QUEUE_PARENT, delay = 3.6 } }),
        })
    end

    it("BuildBindings installs one queue relation under an anchored unconfirmed parent and marks only "
        .. "the parent owned, and refuses a missing, self, unanchored, confirmed, owned, malformed or "
        .. "doubly claimed relation", function()
        local good = queueBindings()
        assert.same({ target = QUEUE_TARGET, delay = 3.6 }, good.queues[QUEUE_ENC][QUEUE_PARENT])
        assert.is_true(good.timers[QUEUE_ENC][QUEUE_PARENT].ownsExpiry)
        assert.is_true(good.timers[QUEUE_ENC][QUEUE_PARENT].admitsLateFinished)
        assert.is_nil(good.timers[QUEUE_ENC][QUEUE_TARGET].ownsExpiry)

        local function target(delay, parent)
            return queueRow({ queueAfter = { parent = parent or QUEUE_PARENT, delay = delay } })
        end
        local function unanchored(extra)
            local row = queueRow(extra)
            row.timerSource.anchor = nil
            return row
        end
        local cases = {
            { name = "parent missing", spells = { [QUEUE_TARGET] = target(3.6) } },
            { name = "target names itself",
              spells = { [QUEUE_PARENT] = queueRow(), [QUEUE_TARGET] = target(3.6, QUEUE_TARGET) } },
            { name = "parent unanchored", spells = { [QUEUE_PARENT] = unanchored(), [QUEUE_TARGET] = target(3.6) } },
            { name = "target unanchored", spells = { [QUEUE_PARENT] = queueRow(),
              [QUEUE_TARGET] = unanchored({ queueAfter = { parent = QUEUE_PARENT, delay = 3.6 } }) } },
            { name = "parent confirmed", spells = {
              [QUEUE_PARENT] = queueRow({ castConfirm = "boss-cast-start" }), [QUEUE_TARGET] = target(3.6) } },
            { name = "zero delay", spells = { [QUEUE_PARENT] = queueRow(), [QUEUE_TARGET] = target(0) } },
            { name = "non-numeric delay", spells = { [QUEUE_PARENT] = queueRow(), [QUEUE_TARGET] = target("3.6") } },
            { name = "target owned by a sequel", spells = {
              [QUEUE_PARENT] = queueRow(), [QUEUE_TARGET] = target(3.6),
              [QUEUE_TARGET + 2] = { castDuration = 5, timerSource = { kind = "Sequel", parent = QUEUE_TARGET, after = 0 } } } },
            { name = "target is itself a queue parent", spells = {
              [QUEUE_PARENT] = queueRow(), [QUEUE_TARGET] = target(3.6),
              [QUEUE_TARGET + 3] = target(2, QUEUE_TARGET) } },
            { name = "parent claimed twice", spells = {
              [QUEUE_PARENT] = queueRow(), [QUEUE_TARGET] = target(3.6), [QUEUE_TARGET + 1] = target(2) } },
        }
        for _, case in ipairs(cases) do
            local bindings = buildQueue(case.spells)
            local queues = bindings.queues[QUEUE_ENC]
            assert.is_nil(queues and queues[QUEUE_PARENT], case.name)
            local timers = bindings.timers[QUEUE_ENC]
            local parentBinding = timers and timers[QUEUE_PARENT]
            assert.is_nil(parentBinding and parentBinding.ownsExpiry, case.name)
        end
    end)

    it("BuildBindings installs a forecast gate under a Message cue naming anchored unconfirmed rows and "
        .. "marks those rows owned, and installs none for another cue kind or an unknown, unanchored, "
        .. "confirmed, non-numeric or empty list", function()
        local GATED = CUE_KEY + 1
        local good = buildCues({ window = messageCue({ hidesForecasts = { GATED } }) }, { [GATED] = cueTimerRow() })
        assert.same({ ["cue:77:window"] = { [GATED] = true } }, good.forecastGates[CUE_ENC])
        assert.is_true(good.timers[CUE_ENC][GATED].ownsExpiry)
        assert.is_true(good.timers[CUE_ENC][GATED].admitsLateFinished)
        assert.equal("cue:77:window", good.messages[CUE_ENC][CUE_KEY].cueKey)

        local unanchored = cueTimerRow()
        unanchored.timerSource.anchor = nil
        local cases = {
            { name = "gate on a Timer cue", cue = timerCue({ hidesForecasts = { GATED } }) },
            { name = "gate on a Sequel cue", cue = sequelCue({ hidesForecasts = { GATED } }) },
            { name = "unknown row", cue = messageCue({ hidesForecasts = { CUE_KEY + 9 } }) },
            { name = "unanchored row", cue = messageCue({ hidesForecasts = { GATED } }), row = unanchored },
            { name = "confirmed row", cue = messageCue({ hidesForecasts = { GATED } }),
              row = cueTimerRow({ castConfirm = "boss-cast-start" }) },
            { name = "overlap-held row", cue = messageCue({ hidesForecasts = { GATED } }),
              row = cueTimerRow({ holdOverlapping = true }) },
            { name = "non-numeric entry", cue = messageCue({ hidesForecasts = { tostring(GATED) } }) },
            { name = "empty list", cue = messageCue({ hidesForecasts = {} }) },
        }
        for _, case in ipairs(cases) do
            local bindings = buildCues({ window = case.cue },
                { [CUE_KEY] = cueTimerRow(), [GATED] = case.row or cueTimerRow() })
            assert.is_nil(bindings.forecastGates[CUE_ENC], case.name)
            assert.is_nil(bindings.timers[CUE_ENC][GATED].ownsExpiry, case.name)
        end
    end)

    local function startTarget(store, label, remaining, trackOnly)
        local binding = queueBindings().timers[QUEUE_ENC][QUEUE_TARGET]
        return State.Start(store, "xathuux", label, binding, remaining or 10, remaining or 10, 0, true, trackOnly)
    end

    local function targetStore()
        local store = State.New()
        State.AdmitOwner(store, "xathuux", QUEUE_ENC)
        return store
    end

    it("SelectQueuedTarget returns the one unresolved target due before the queued start, none for "
        .. "anchored, retired, track-only or later ones, and refuses two", function()
        local cases = {
            { name = "due earlier", rows = { { remaining = 10 } }, want = 1 },
            { name = "due later", rows = { { remaining = 30 } }, reason = "none" },
            { name = "anchored", rows = { { remaining = 10, anchorAt = 9 } }, reason = "none" },
            { name = "retired", rows = { { remaining = 10, retire = true } }, reason = "none" },
            { name = "track-only", rows = { { remaining = 10, trackOnly = true } }, reason = "none" },
            { name = "two due earlier", rows = { { remaining = 10 }, { remaining = 12 } }, reason = "ambiguous" },
        }
        for _, case in ipairs(cases) do
            local store = targetStore()
            local started = {}
            for i, row in ipairs(case.rows) do
                local instance = startTarget(store, "Infernal Crush (" .. i .. ")", row.remaining, row.trackOnly)
                if row.anchorAt then State.Anchor(instance, row.anchorAt) end
                if row.retire then State.Retire(store, instance) end
                started[i] = instance
            end
            -- Queued start at 11 + 3.6 = 14.6 on each instance's elapsed clock.
            local found, reason = State.SelectQueuedTarget(store, "xathuux", QUEUE_TARGET, 11, 3.6)
            if case.want then
                assert.equal(started[case.want], found, case.name)
            else
                assert.is_nil(found, case.name)
                assert.equal(case.reason, reason, case.name)
            end
        end
    end)

    -- receipt 0, remaining 10, extension 3, queue 4: the original hold bound is 10 + 4 + 0.5 = 14.5.
    it("Predict moves an unresolved start strictly later below the original hold bound and clears a "
        .. "hold, and refuses a retired, paused, anchored, earlier or at-bound start or invalid input", function()
        local store = targetStore()
        local held = startTarget(store, "held")
        assert.equal(14.5, State.BeginHold(held, 4))
        local total, bound = State.Predict(held, 10.75, 3.5, 4)
        assert.equal(17.25, total)
        assert.equal(14.5, bound)
        assert.equal(14.25, held.predictedStart)
        assert.is_nil(held.holdDeadline)

        local nan = 0 / 0
        local refusals = {
            { name = "retired", prep = function(s, i) State.Retire(s, i) end, reason = "retired" },
            { name = "paused", prep = function(s, i) State.Pause(s, "xathuux", i.label, 5) end, reason = "paused" },
            { name = "anchored", prep = function(_, i) State.Anchor(i, 9) end, reason = "already-anchored" },
            { name = "zero delay", delay = 0, reason = "invalid-delay" },
            { name = "nan queue", maxQueue = nan, reason = "invalid-maxqueue" },
            { name = "negative queue", maxQueue = -1, reason = "invalid-maxqueue" },
            { name = "queue truncates baseline", now = 10, delay = 1, maxQueue = 1, reason = "truncates-baseline" },
            { name = "offset exceeds queue", reason = "truncates-baseline",
              prep = function(_, i) i.binding.extension = 6 end },
            { name = "not later", now = 5, reason = "not-later" },
            { name = "at the bound", now = 11, reason = "beyond-queue" },
        }
        for _, case in ipairs(refusals) do
            local s = targetStore()
            local instance = startTarget(s, case.name)
            if case.prep then case.prep(s, instance) end
            local value, reason = State.Predict(instance, case.now or 10.75, case.delay or 3.5, case.maxQueue or 4)
            assertRefusal(value, reason, case.name)
            assert.equal(case.reason, reason, case.name)
            assert.is_nil(instance.predictedStart, case.name)
        end
    end)

    it("a predicted instance keeps until predicted zero, is hold-eligible there, and retires at the "
        .. "original hold bound even with predicted time left", function()
        local cases = {
            -- Start 14.25: predicted zero 17.25 lies past the bound 14.5.
            { name = "zero past the bound", now = 10.75,
              checks = { { at = 13, want = "keep" }, { at = 14.4, want = "keep" }, { at = 14.5, want = "retire" } } },
            -- Start 11.25: predicted zero 14.25 lies inside the bound.
            { name = "zero inside the bound", now = 7.75, holdAfter = true,
              checks = { { at = 14.2, want = "keep" }, { at = 14.25, want = "hold-eligible" } } },
        }
        for _, case in ipairs(cases) do
            local instance = startTarget(targetStore(), case.name)
            State.Predict(instance, case.now, 3.5, 4)
            for _, check in ipairs(case.checks) do
                assert.equal(check.want, State.ClassifyExpiry(instance, check.at), case.name .. " at " .. check.at)
            end
            if case.holdAfter then
                assert.equal(14.5, State.BeginHold(instance, 4), case.name)
                assert.equal("keep", State.ClassifyExpiry(instance, 14.4), case.name)
                assert.equal("retire", State.ClassifyExpiry(instance, 14.5), case.name)
            end
        end
    end)

    it("a predicted instance anchors on a qualified Finished before the original hold bound and "
        .. "retires on one at or after it, and the anchor clears the prediction", function()
        local cases = {
            { name = "before the bound", at = 14.25, want = "anchor" },
            { name = "at the bound", at = 14.5, want = "retire" },
        }
        for _, case in ipairs(cases) do
            local instance = startTarget(targetStore(), case.name)
            State.Predict(instance, 10.75, 3.5, 4)
            assert.equal(case.want, State.ClassifyStop(instance, case.at, nil, "finished"), case.name)
        end

        local anchored = startTarget(targetStore(), "anchored")
        State.Predict(anchored, 10.75, 3.5, 4)
        assert.equal(17.25, State.Anchor(anchored, 14.25))
        assert.is_nil(anchored.predictedStart)
        assert.is_nil(anchored.predictBound)
    end)

    it("GateCovers reports a listed row only before its gate's end, never an unlisted row or without "
        .. "gates, and follows a replaced record", function()
        local GATE, NOVA, SPRAY = "cue:3101:light_infusion", 474240, 1253811
        local gates = { [GATE] = { endsAt = 121.75, spells = { [NOVA] = true } } }
        local cases = {
            { name = "listed, open", id = NOVA, now = 121.5, want = true },
            { name = "listed, at the end", id = NOVA, now = 121.75, want = false },
            { name = "unlisted", id = SPRAY, now = 110, want = false },
        }
        for _, case in ipairs(cases) do
            assert.equal(case.want, State.GateCovers(gates, case.id, case.now), case.name)
        end
        assert.is_false(State.GateCovers(nil, NOVA, 110))
        gates[GATE] = { endsAt = 140, spells = { [NOVA] = true } }
        assert.is_true(State.GateCovers(gates, NOVA, 130))
    end)

    it("ProviderMessageStatus reports unknown for malformed or out-of-range flags and for masks that "
        .. "are malformed, multi-bit or equal, satisfied when either bit is set, and missing otherwise",
        function()
        local MESSAGE, EMPHASIZE = 2, 512
        local cases = {
            { name = "neither bit", flags = 1 + 16 + 64, want = "missing" },
            { name = "zero flags", flags = 0, want = "missing" },
            { name = "message bit", flags = 1 + 2, want = "satisfied" },
            { name = "emphasize bit only", flags = 1 + 512, want = "satisfied" },
            { name = "string flags", flags = "3", want = "unknown" },
            { name = "negative flags", flags = -1, want = "unknown" },
            { name = "fractional flags", flags = 1.5, want = "unknown" },
            { name = "nan flags", flags = 0 / 0, want = "unknown" },
            { name = "flags at the limit", flags = 2147483648, want = "unknown" },
            { name = "multi-bit message mask", flags = 1, message = 6, want = "unknown" },
            { name = "zero message mask", flags = 1, message = 0, want = "unknown" },
            { name = "fractional emphasize mask", flags = 1, emphasize = 0.5, want = "unknown" },
            { name = "string emphasize mask", flags = 1, emphasize = "512", want = "unknown" },
            { name = "equal masks", flags = 1, emphasize = 2, want = "unknown" },
        }
        for _, case in ipairs(cases) do
            local status = State.ProviderMessageStatus(case.flags, case.message or MESSAGE,
                case.emphasize or EMPHASIZE)
            assert.equal(case.want, status, case.name)
        end
        assert.equal("unknown", State.ProviderMessageStatus(nil, MESSAGE, EMPHASIZE), "nil flags")
    end)

    it("PlanProviderMessageEnable writes the current flags plus the message bit for the opened "
        .. "profile, writes nothing when already satisfied, and refuses in combat, for a disabled cue, "
        .. "for a different or absent profile and for unreadable flags", function()
        local profileA, profileB = {}, {}
        local function current(overrides)
            local ctx = { profile = profileA, flags = 1 + 16 + 64, messageBit = 2, emphasizeBit = 512,
                          cueEnabled = true, inCombat = false }
            for k, v in pairs(overrides or {}) do ctx[k] = v end
            return ctx
        end
        local opened = { profile = profileA }
        local cases = {
            { name = "same profile", current = current(), want = "write", detail = 1 + 2 + 16 + 64 },
            { name = "other bits set", current = current({ flags = 1 + 4 + 8 + 4096 }), want = "write",
              detail = 1 + 2 + 4 + 8 + 4096 },
            { name = "message already on", current = current({ flags = 1 + 2 }), want = "satisfied" },
            { name = "emphasize already on", current = current({ flags = 1 + 512 }), want = "satisfied" },
            { name = "combat", current = current({ inCombat = true }), want = "refuse", detail = "combat" },
            { name = "cue disabled", current = current({ cueEnabled = false }), want = "refuse",
              detail = "cue-disabled" },
            { name = "different profile", current = current({ profile = profileB }), want = "refuse",
              detail = "profile-changed" },
            { name = "unreadable flags", current = current({ flags = "81" }), want = "refuse",
              detail = "unknown" },
            { name = "no current state", current = { cueEnabled = true, inCombat = false },
              want = "refuse", detail = "unknown" },
        }
        for _, case in ipairs(cases) do
            local decision, detail = State.PlanProviderMessageEnable(opened, case.current)
            assert.equal(case.want, decision, case.name)
            assert.equal(case.detail, detail, case.name)
        end
    end)

    it("ProviderSetupGate passes an enabled descriptor out of combat and names the first failing "
        .. "input in order", function()
        local function input(overrides)
            local ctx = { hasDescriptor = true, moduleEnabled = true, cueEnabled = true, inCombat = false }
            for k, v in pairs(overrides or {}) do ctx[k] = v end
            return ctx
        end
        local cases = {
            { name = "all pass", input = input() },
            { name = "no descriptor", input = input({ hasDescriptor = false }), want = "no-descriptor" },
            { name = "module disabled", input = input({ moduleEnabled = false }), want = "module-disabled" },
            { name = "cue disabled", input = input({ cueEnabled = false }), want = "cue-disabled" },
            { name = "combat", input = input({ inCombat = true }), want = "combat" },
            { name = "module before cue and combat",
              input = input({ moduleEnabled = false, cueEnabled = false, inCombat = true }),
              want = "module-disabled" },
        }
        for _, case in ipairs(cases) do
            assert.equal(case.want, State.ProviderSetupGate(case.input), case.name)
        end
    end)

    it("PlanProviderSetup opens an automatic prompt only in the instance, on a missing status, "
        .. "unanswered and with nothing pending", function()
        local function input(overrides)
            local ctx = { explicit = false, inInstance = true, status = "missing", answered = false }
            for k, v in pairs(overrides or {}) do ctx[k] = v end
            return ctx
        end
        local cases = {
            { name = "eligible", input = input(), want = "open" },
            { name = "outside the instance", input = input({ inInstance = false }), want = "none" },
            { name = "satisfied", input = input({ status = "satisfied" }), want = "none" },
            { name = "unknown", input = input({ status = "unknown" }), want = "none" },
            { name = "answered", input = input({ answered = true }), want = "none" },
            { name = "automatic prompt pending", input = input({ pending = "auto" }), want = "keep" },
            { name = "explicit prompt pending", input = input({ pending = "explicit" }), want = "keep" },
        }
        for _, case in ipairs(cases) do
            assert.equal(case.want, State.PlanProviderSetup(case.input), case.name)
        end
    end)

    it("PlanProviderSetup opens an explicit prompt on a missing status regardless of instance, "
        .. "answer and pending prompt, and not on any other status", function()
        local function input(overrides)
            local ctx = { explicit = true, inInstance = false, status = "missing", answered = true }
            for k, v in pairs(overrides or {}) do ctx[k] = v end
            return ctx
        end
        local cases = {
            { name = "outside and answered", input = input(), want = "open" },
            { name = "automatic prompt pending", input = input({ pending = "auto" }), want = "open" },
            { name = "explicit prompt pending", input = input({ pending = "explicit" }), want = "open" },
            { name = "satisfied", input = input({ status = "satisfied" }), want = "none" },
            { name = "unknown", input = input({ status = "unknown" }), want = "none" },
        }
        for _, case in ipairs(cases) do
            assert.equal(case.want, State.PlanProviderSetup(case.input), case.name)
        end
    end)

    it("PlanProviderSetup closes a pending prompt on a status that is not missing, and an automatic "
        .. "one outside the instance while an explicit one is kept", function()
        local cases = {
            { name = "automatic, satisfied",
              input = { explicit = false, inInstance = true, status = "satisfied", pending = "auto" },
              want = "close" },
            { name = "explicit, unknown",
              input = { explicit = false, inInstance = false, status = "unknown", pending = "explicit" },
              want = "close" },
            { name = "explicit call, satisfied",
              input = { explicit = true, inInstance = true, status = "satisfied", pending = "explicit" },
              want = "close" },
            { name = "automatic, outside",
              input = { explicit = false, inInstance = false, status = "missing", pending = "auto" },
              want = "close" },
            { name = "explicit, outside",
              input = { explicit = false, inInstance = false, status = "missing", pending = "explicit" },
              want = "keep" },
        }
        for _, case in ipairs(cases) do
            assert.equal(case.want, State.PlanProviderSetup(case.input), case.name)
        end
    end)

    it("PlanProviderSetup preserves another cue's prompt unless this cue is explicitly requested and missing", function()
        for _, status in ipairs({ "missing", "satisfied", "unknown" }) do
            for _, explicit in ipairs({ false, true }) do
                local input = { status = status, explicit = explicit, pending = "other", inInstance = false }
                local want = explicit and status == "missing" and "open" or "keep"
                assert.equal(want, State.PlanProviderSetup(input), status .. tostring(explicit))
            end
        end
    end)

    local SHIELD_PARENT = 373686

    local function shieldParentRow(anchor, castConfirm)
        return { castDuration = 0, timerSource = {
            kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only",
            stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label",
            anchor = anchor, castConfirm = castConfirm,
        } }
    end

    local function shieldEncounter(spells, shields)
        return { [2609] = { timerPolicy = "explicit", spells = spells, shields = shields } }
    end

    it("BuildBindings installs an explicit shield only under an anchored unconfirmed parent and refuses "
        .. "malformed, orphan or duplicate entries", function()
        local accepted = State.BuildBindings(shieldEncounter(
            { [SHIELD_PARENT] = shieldParentRow("timeline-finished") },
            { { parent = SHIELD_PARENT, baseAmount = 2490819.8, timeout = 60, displayText = "SHIELD" } }))
        assert.same({
            encounterId = 2609, parent = SHIELD_PARENT, explicit = true,
            baseAmount = 2490819.8, timeout = 60, displayText = "SHIELD",
        }, accepted.shields[2609][SHIELD_PARENT])

        local anchored = { [SHIELD_PARENT] = shieldParentRow("timeline-finished") }
        local valid = { parent = SHIELD_PARENT, baseAmount = 100, timeout = 60 }
        local cases = {
            { name = "parent row missing", spells = {}, shields = { valid } },
            { name = "parent unanchored", spells = { [SHIELD_PARENT] = shieldParentRow(nil) }, shields = { valid } },
            { name = "parent confirmed",
              spells = { [SHIELD_PARENT] = shieldParentRow("timeline-finished", "boss-cast-start") },
              shields = { valid } },
            { name = "zero amount", spells = anchored,
              shields = { { parent = SHIELD_PARENT, baseAmount = 0, timeout = 60 } } },
            { name = "missing timeout", spells = anchored,
              shields = { { parent = SHIELD_PARENT, baseAmount = 100 } } },
            { name = "nan timeout", spells = anchored,
              shields = { { parent = SHIELD_PARENT, baseAmount = 100, timeout = 0 / 0 } } },
            { name = "empty label", spells = anchored,
              shields = { { parent = SHIELD_PARENT, baseAmount = 100, timeout = 60, displayText = "" } } },
            { name = "unknown field", spells = anchored,
              shields = { { parent = SHIELD_PARENT, baseAmount = 100, timeout = 60, color = { 0, 1, 0 } } } },
            { name = "two entries for one parent", spells = anchored, shields = { valid, valid } },
            { name = "malformed second entry for one parent", spells = anchored,
              shields = { valid, { parent = SHIELD_PARENT, baseAmount = 0, timeout = 60 } } },
        }
        for _, case in ipairs(cases) do
            local bindings = State.BuildBindings(shieldEncounter(case.spells, case.shields))
            assert.is_nil(bindings.shields[2609], case.name)
        end
    end)

    it("BuildBindings keeps a legacy row's shieldBar as a non-explicit shield capped at its channel "
        .. "duration plus two seconds", function()
        local bindings = State.BuildBindings({
            [3213] = { spells = { [1250708] = { castType = "channel", channelDuration = 60,
                shieldBar = { baseAmount = 1160814, displayText = "SHIELD" } } } },
        })
        assert.same({
            encounterId = 3213, parent = 1250708, explicit = false,
            baseAmount = 1160814, timeout = 62, displayText = "SHIELD",
        }, bindings.shields[3213][1250708])
    end)

    it("ResolveShieldWatch opens the window on an explicit parent's qualified Finished", function()
        for _, outcome in ipairs({ "anchor", "resume-and-anchor" }) do
            assert.equal("open", State.ResolveShieldWatch(true, outcome, false), outcome)
        end
    end)

    it("ResolveShieldWatch closes an explicit parent's unopened watch on any other resolved stop, including "
        .. "a stop that finds no published occurrence", function()
        for _, outcome in ipairs({ "retire", "keep-estimate" }) do
            assert.equal("close", State.ResolveShieldWatch(true, outcome, false), outcome)
        end
        assert.equal("close", State.ResolveShieldWatch(true, nil, false), "no occurrence")
    end)

    it("ResolveShieldWatch keeps an explicit parent's window on a repeat stop after its anchor or once "
        .. "the window has opened", function()
        assert.equal("keep", State.ResolveShieldWatch(true, "ignore", false), "ignore")
        for _, outcome in ipairs({ "anchor", "retire" }) do
            assert.equal("keep", State.ResolveShieldWatch(true, outcome, true), "after open " .. outcome)
        end
        assert.equal("keep", State.ResolveShieldWatch(true, nil, true), "after open, no occurrence")
    end)

    it("ResolveShieldWatch never touches a legacy parent's watch", function()
        for _, outcome in ipairs({ "anchor", "retire", "legacy-followup-and-retire" }) do
            assert.equal("keep", State.ResolveShieldWatch(false, outcome, false), outcome)
        end
    end)

    it("ShieldUnitMatches ties a shield to its own unit and refuses only two known, different "
        .. "cast-bar IDs", function()
        local cases = {
            { name = "other unit", args = { "boss1", 7, "boss2", 7 }, want = false },
            { name = "no shield unit", args = { nil, nil, "boss1", nil }, want = false },
            { name = "same unit, same id", args = { "boss1", 7, "boss1", 7 }, want = true },
            { name = "same unit, different ids", args = { "boss1", 7, "boss1", 8 }, want = false },
            { name = "same unit, event id missing", args = { "boss1", 7, "boss1", nil }, want = true },
            { name = "same unit, shield id missing", args = { "boss1", nil, "boss1", 8 }, want = true },
        }
        for _, case in ipairs(cases) do
            local a = case.args
            assert.equal(case.want, State.ShieldUnitMatches(a[1], a[2], a[3], a[4]), case.name)
        end
    end)

    it("ShieldWatchOnRetire closes an explicit watch whose occurrence retires before its Finished, keeps it "
        .. "after, and always keeps a legacy watch", function()
        local cases = {
            { name = "explicit, not finished", explicit = true, finished = false, want = "close" },
            { name = "explicit, finished", explicit = true, finished = true, want = "keep" },
            { name = "legacy, not finished", explicit = false, finished = false, want = "keep" },
        }
        for _, case in ipairs(cases) do
            assert.equal(case.want, State.ShieldWatchOnRetire(case.explicit, case.finished), case.name)
        end
    end)

    -- Receipt 0, deadline 10, extension 2: the time left at a stop is 10
    -- minus the pause-excluded elapsed time.
    local ABSENT = {}

    local function canceledStopRow(contractExtra)
        local contract = {
            kind = "Timer", isCooldown = true, policy = "estimated-impact",
            spanMode = "remaining-only", stopTolerance = 0.15,
            collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished",
            canceledStop = { stage = 3, within = 1 },
        }
        for k, v in pairs(contractExtra or {}) do
            if v == ABSENT then contract[k] = nil else contract[k] = v end
        end
        return { castDuration = 2, timerSource = contract }
    end

    local function buildStageRow(row)
        local timers = State.BuildBindings({
            [3201] = { timerPolicy = "explicit", spells = { [1239824] = row } },
        }).timers
        return timers[3201] and timers[3201][1239824]
    end

    local function startStageInstance(binding, label, publishedStage, duration)
        local store = State.New()
        State.AdmitOwner(store, "ruia", 3201)
        local instance = State.Start(store, "ruia", label, binding, duration or 10, duration or 10, 0, true)
        State.RecordPublishedStage(instance, publishedStage)
        return instance, store
    end

    it("BuildBindings installs canceledStop only with a timeline anchor, a positive stage and a window in (0, 1], and refuses the whole row otherwise", function()
        assert.same({ stage = 3, within = 1 }, buildStageRow(canceledStopRow()).canceledStop)
        local refusals = {
            { name = "non-table", contract = { canceledStop = 3 } },
            { name = "zero stage", contract = { canceledStop = { stage = 0, within = 1 } } },
            { name = "missing stage", contract = { canceledStop = { within = 1 } } },
            { name = "zero window", contract = { canceledStop = { stage = 3, within = 0 } } },
            { name = "window over 1", contract = { canceledStop = { stage = 3, within = 1.5 } } },
            { name = "NaN window", contract = { canceledStop = { stage = 3, within = 0 / 0 } } },
            { name = "no anchor", contract = { anchor = ABSENT } },
            { name = "castConfirm", contract = { castConfirm = "boss-cast-start" } },
            { name = "pausedStop", contract = { pausedStop = "retire" } },
            { name = "queueAfter", contract = { queueAfter = { parent = 1240098, delay = 1 } } },
        }
        for _, case in ipairs(refusals) do
            assert.is_nil(buildStageRow(canceledStopRow(case.contract)), case.name)
        end
    end)

    it("ClassifyStop retains an in-stage cancellation near the deadline while its original cast tail remains", function()
        local binding = buildStageRow(canceledStopRow())
        local cases = {
            { name = "0.5 s left", stop = 9.5 },
            { name = "exactly 1 s left", stop = 9 },
            { name = "at the deadline", stop = 10 },
            { name = "just past the deadline", stop = 10.009 },
            { name = "at late tolerance", stop = 10.15 },
            { name = "0.5 s left after a 3 s pause", stop = 12.5, pause = { 2, 5 } },
        }
        for _, case in ipairs(cases) do
            local instance, store = startStageInstance(binding, case.name, 3)
            if case.pause then
                State.Pause(store, "ruia", case.name, case.pause[1])
                State.Resume(store, "ruia", case.name, case.pause[2])
            end
            assert.equal("retain-canceled",
                State.ClassifyStop(instance, case.stop, nil, "canceled", nil, 3), case.name)
        end
    end)

    it("ClassifyStop retires a canceledStop row's Canceled stop unless both the published and the stop stage match", function()
        local binding = buildStageRow(canceledStopRow())
        local cases = {
            { name = "stopped in stage 2", published = 3, stop = 2 },
            { name = "published in stage 2, stopped in stage 3", published = 2, stop = 3 },
            { name = "publication stage unread", published = nil, stop = 3 },
            { name = "stop stage unread", published = 3, stop = nil },
        }
        for _, case in ipairs(cases) do
            local instance = startStageInstance(binding, case.name, case.published)
            assert.equal("retire", State.ClassifyStop(instance, 9.5, nil, "canceled", nil, case.stop), case.name)
        end
    end)

    it("ClassifyStop refuses cancellation retention outside its window, after impact, while paused, held or predicted", function()
        local cases = {
            { name = "1.01 s left", stop = 8.99 },
            { name = "past late tolerance", stop = 10.151 },
            { name = "impact already reached", stop = 10, extension = 0 },
            { name = "paused", stop = 9.5, pauseAt = 9 },
            { name = "held", stop = 9.5, hold = 6 },
            { name = "predicted", stop = 9.5, predictBound = 14 },
        }
        for _, case in ipairs(cases) do
            local row = canceledStopRow()
            if case.extension ~= nil then row.castDuration = case.extension end
            local instance, store = startStageInstance(buildStageRow(row), case.name, 3)
            if case.pauseAt then State.Pause(store, "ruia", case.name, case.pauseAt) end
            if case.hold then State.BeginHold(instance, case.hold) end
            instance.predictBound = case.predictBound
            assert.equal("retire", State.ClassifyStop(instance, case.stop, nil, "canceled", nil, 3), case.name)
        end
    end)

    local function earlyFinishedRow(extra)
        local contract = { canceledStop = ABSENT, retainEarlyFinished = true }
        for k, v in pairs(extra or {}) do contract[k] = v end
        return canceledStopRow(contract)
    end

    local function restartRow(extra)
        local contract = { canceledStop = ABSENT, suppressConcurrentRestart = { from = 29, duration = 6 } }
        for k, v in pairs(extra or {}) do contract[k] = v end
        return canceledStopRow(contract)
    end

    it("BuildBindings refuses malformed or conflicting concurrent-restart suppression", function()
        local refusals = {
            { suppressConcurrentRestart = true },
            { suppressConcurrentRestart = { from = 0, duration = 6 } },
            { suppressConcurrentRestart = { from = 29, duration = 0 } },
            { suppressConcurrentRestart = { from = 6, duration = 6 } },
            { suppressConcurrentRestart = { from = math.huge, duration = 6 } },
            { suppressConcurrentRestart = { from = 29, duration = 0 / 0 } },
            { anchor = ABSENT },
            { castConfirm = "boss-cast-start" },
            { pausedStop = "retire" },
            { queueAfter = { parent = 1239824, delay = 1 } },
            { canceledStop = { stage = 3, within = 1 } },
            { retainEarlyFinished = true },
        }
        for _, extra in ipairs(refusals) do
            assert.is_nil(buildStageRow(restartRow(extra)))
        end
    end)

    it("IsConcurrentRestart requires a fresh uninterrupted shorter forecast and a distinct same-scope long anchor", function()
        local cases = {
            { name = "same receipt", want = true },
            { name = "receipt before anchor", receipt = 28.9, want = true },
            { name = "receipt after anchor", receipt = 29.1, want = true },
            { name = "queue-delayed source", anchor = 33.4, receipt = 33.4, want = true },
            { name = "too early", receipt = 28.8 },
            { name = "too late", receipt = 29.2 },
            { name = "ordinary long replacement", duration = 29 },
            { name = "normal six-second recurrence", from = 6 },
            { name = "not opted in", edit = function(t) t.binding.suppressConcurrentRestart = nil end },
            { name = "other owner", edit = function(t) t.owner = "other" end },
            { name = "other scope", edit = function(t) t.scope = {} end },
            { name = "other encounter", edit = function(t) t.encounterId = 999 end },
            { name = "other curation", edit = function(t) t.binding.curationId = 999 end },
            { name = "unknown target event", edit = function(t) t.timelineIdentity = nil end },
            { name = "refused target event", edit = function(t) t.timelineIdentity = "refused" end },
            { name = "same event", edit = function(t) t.timelineIdentity = 71 end },
            { name = "unknown anchor event", edit = function(_, a) a.anchorEventId = nil end },
            { name = "not anchored", edit = function(_, a) a.anchorAt = nil end },
            { name = "fresh future anchor", edit = function(_, a) a.anchorElapsed = 0 end },
            { name = "anchor retired", edit = function(_, a) a.state = "retired" end },
            { name = "target retired", edit = function(t) t.state = "retired" end },
            { name = "target anchored", edit = function(t) t.anchorElapsed = 0 end },
            { name = "target paused", edit = function(t) t.state = "paused" end },
            { name = "target resumed", edit = function(t) t.hasPaused = true end },
            { name = "target retained", edit = function(t) t.retainedEstimate = "finished" end },
            { name = "target held", edit = function(t) t.holdDeadline = 12 end },
            { name = "target predicted", edit = function(t) t.predictBound = 12 end },
        }
        for _, case in ipairs(cases) do
            local binding = buildStageRow(restartRow())
            local source, store = startStageInstance(binding, "source", nil, case.from or 29)
            assert.is_truthy(State.Anchor(source, case.anchor or 29, 71))
            local target = State.Start(store, "ruia", "target", buildStageRow(restartRow()),
                case.duration or 6, case.duration or 6, case.receipt or 29, true)
            target.timelineIdentity = 72
            if case.edit then case.edit(target, source) end
            assert.equal(case.want == true, State.IsConcurrentRestart(target, source), case.name)
        end
    end)

    it("BuildBindings refuses malformed or conflicting early-Finished retention contracts", function()
        local refusals = {
            { retainEarlyFinished = false },
            { retainEarlyFinished = "true" },
            { anchor = ABSENT },
            { castConfirm = "boss-cast-start" },
            { pausedStop = "retire" },
            { queueAfter = { parent = 1240098, delay = 1 } },
            { canceledStop = { stage = 3, within = 1 } },
        }
        for _, extra in ipairs(refusals) do
            assert.is_nil(buildStageRow(earlyFinishedRow(extra)))
        end
    end)

    it("ClassifyStop retains only a fresh future Finished on an opted-in uninterrupted forecast", function()
        local cases = {
            { name = "same receipt", now = 0, want = "retain-finished" },
            { name = "at receipt tolerance", now = 0.15, want = "retain-finished" },
            { name = "past receipt tolerance", now = 0.151, want = "anchor" },
            { name = "normal deadline", now = 10, want = "anchor" },
            { name = "no opt-in", now = 0, extra = { retainEarlyFinished = ABSENT }, want = "anchor" },
            { name = "short forecast", now = 0, remaining = 0.1, want = "anchor" },
            { name = "before receipt", now = -0.01, want = "anchor" },
            { name = "currently paused", now = 0.1, pause = true, want = "resume-and-anchor" },
            { name = "previously paused", now = 0.1, pause = true, resume = 0.04, want = "anchor" },
            { name = "same-tick pause and resume", now = 0.1, pause = true, resume = 0.02, want = "anchor" },
            { name = "held", now = 0.1, hold = true, want = "anchor" },
            { name = "predicted", now = 0.1, predicted = true, want = "anchor" },
            { name = "owned expiry", now = 0.1, ownsExpiry = true, want = "anchor" },
            { name = "canceled", now = 0, state = "canceled", want = "retire" },
        }
        for _, case in ipairs(cases) do
            local instance, store = startStageInstance(buildStageRow(earlyFinishedRow(case.extra)), case.name, 3, case.remaining)
            if case.pause then State.Pause(store, "ruia", case.name, 0.02) end
            if case.resume then State.Resume(store, "ruia", case.name, case.resume) end
            if case.hold then State.BeginHold(instance, 6) end
            if case.predicted then instance.predictBound = 14 end
            instance.binding.ownsExpiry = case.ownsExpiry
            assert.equal(case.want, State.ClassifyStop(instance, case.now, nil, case.state or "finished"), case.name)
        end
    end)

    it("ClassifyStop keeps the existing outcomes for a row without canceledStop and for a canceledStop row's Finished stop", function()
        local cases = {
            { name = "no canceledStop, in-stage Canceled", binding = buildStageRow(canceledStopRow({ canceledStop = ABSENT })),
              state = "canceled", want = "retire" },
            { name = "canceledStop, Finished", binding = buildStageRow(canceledStopRow()),
              state = "finished", want = "anchor" },
        }
        for _, case in ipairs(cases) do
            local instance = startStageInstance(case.binding, case.name, 3)
            assert.equal(case.want, State.ClassifyStop(instance, 9.5, nil, case.state, nil, 3), case.name)
        end
    end)

    it("ClassifyStop ignores every later stop on either kind of retained estimate", function()
        local binding = buildStageRow(canceledStopRow())
        local cases = {
            { name = "finished", state = "finished" },
            { name = "canceled", state = "canceled" },
            { name = "no state", state = nil },
        }
        for _, reason in ipairs({ "canceled", "finished" }) do
            for _, case in ipairs(cases) do
                local instance = startStageInstance(binding, case.name, 3)
                State.RetainEstimate(instance, reason)
                assert.equal("ignore", State.ClassifyStop(instance, 9.6, nil, case.state, nil, 3), case.name)
            end
        end
    end)

    it("Pause and Resume refuse either retained estimate and leave its clock running", function()
        for _, reason in ipairs({ "canceled", "finished" }) do
            local instance, store = startStageInstance(buildStageRow(canceledStopRow()), "retained", 3)
            State.RetainEstimate(instance, reason)
            local paused, pauseReason = State.Pause(store, "ruia", "retained", 9.6)
            assertRefusal(paused, pauseReason, "pause")
            assert.is_nil(instance.sourceClock.pausedAt)
            local resumed, resumeReason = State.Resume(store, "ruia", "retained", 9.7)
            assertRefusal(resumed, resumeReason, "resume")
        end
    end)

    it("ClassifyExpiry keeps either retained estimate until its original end, then retires it instead of holding", function()
        local binding = buildStageRow(canceledStopRow())
        for _, reason in ipairs({ "canceled", "finished" }) do
            local retained = startStageInstance(binding, "retained", 3)
            State.RetainEstimate(retained, reason)
            assert.equal("keep", State.ClassifyExpiry(retained, 11.9))
            assert.equal("retire", State.ClassifyExpiry(retained, 12))
        end
        local unretained = startStageInstance(binding, "unretained", 3)
        assert.equal("hold-eligible", State.ClassifyExpiry(unretained, 12))
    end)
end)
