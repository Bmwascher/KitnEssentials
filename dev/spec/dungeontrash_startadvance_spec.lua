-- Tier 2: DungeonTrash CAST_START pending start-advance.
-- CAST_START-mode spells anchor their cd at the observed cast START, whatever
-- the outcome — their ONLY anchor path, since success-mode
-- inference returns nil for CAST_START, and the reason a KICKED Pulsing
-- Shriek still counts to its next cast. These specs pin the arm/consume
-- lifecycle: armed per non-transition start, consumed once on resolution +
-- sampled fingerprints, surviving interrupts, never double-advancing the
-- cd[] round-robin on success, and never armed by a paired transition.

local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("DungeonTrash — CAST_START start-advance", function()
    local DTrash, TI, KE, clock, timers, world, scheduled, predicted

    before_each(function()
        clock = { now = 100 }
        timers = {}
        world = { combat = {}, debuffs = {} }
        scheduled, predicted = {}, {}

        mock.install({
            GetTime = function() return clock.now end,
            C_Timer = {
                After = function(delay, fn)
                    timers[#timers + 1] = { at = clock.now + delay, fn = fn }
                end,
            },
        })
        _G.UnitIsDead = function() return false end
        _G.UnitAffectingCombat = function(u) return world.combat[u] == true end
        _G.GetInstanceInfo = function() return "Dungeon", "party", 8, nil, nil, nil, nil, 1 end
        _G.IsInInstance = function() return true, "party" end
        -- Party-debuff surface for the aura-delta sampler; set BEFORE the
        -- module loads so the parse-time locals capture it.
        _G.C_UnitAuras = {
            GetAuraDataByIndex = function() return nil end,
            GetDebuffDataByIndex = function(unit, index)
                local list = world.debuffs[unit]
                local id = list and list[index]
                if id then return { auraInstanceID = id } end
                return nil
            end,
        }

        local modules = helpers.installAddonShim()
        KE = { Print = function() end }  -- DEBUG_DTRASH dprints route here
        helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/TrashInference.lua", KE)
        helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/TrashKingsRest.lua", KE)
        helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/DungeonTrash.lua", KE)
        helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/TrashCache.lua", KE)
        DTrash = modules["DungeonTrash"]
        TI = KE.TrashInference
        -- Owner-bound cast callbacks (4.4) act only while monitoring is on.
        DTrash.monitoring = true

        DTrash.ScheduleAlert = function(_, rt, npcID, spellID, _, nextStart)
            scheduled[#scheduled + 1] = { unit = rt.unit, npcID = npcID,
                spellID = spellID, nextStart = nextStart }
        end
        DTrash.SetNameplatePrediction = function(_, rt, npcID, spellID, startTime, nextStart)
            predicted[#predicted + 1] = { unit = rt.unit, npcID = npcID,
                spellID = spellID, startTime = startTime, nextStart = nextStart }
        end
        DTrash.HideUnitAlerts = function() end
        DTrash.HideNameplateMarker = function() end

        DTrash.currentMapID = 1
        KE.TrashData = { [1] = { mobs = { [111] = { npcID = 111, name = "Kicker", spells = {
            -- Pulsing Shriek-shaped: pure kickable channel, CAST_START cd.
            [10] = { name = "Shriek", channelTime = 20, first = 10, cd = { 31, 62 },
                cdMode = "CAST_START" },
            -- success-mode control: must never be start-advanced.
            [20] = { name = "Bolt", castTime = 3, first = 12, cd = { 15 } },
        } } } } }
    end)

    after_each(function()
        mock.reset()
        _G.UnitIsDead = nil
        _G.UnitAffectingCombat = nil
        _G.GetInstanceInfo = nil
        _G.IsInInstance = nil
        _G.C_UnitAuras = nil
        _G.KitnEssentials = nil
    end)

    local function trackResolved(unit)
        DTrash:OnNameplateAdded(nil, unit)
        local rt = DTrash.tracked[unit]
        rt.matchedNPCID = 111
        return rt
    end

    -- Fire only the timers scheduled after index `n` (skips the plate-add
    -- snapshot timer; targets the +0.10s cast-start fingerprint sampler).
    local function fireTimersAfter(n)
        for i = n + 1, #timers do
            local t = timers[i]
            if t and t.fn then t.fn() end
        end
    end

    it("anchors a CAST_START channel at its observed start (resolved + sampled)", function()
        local rt = trackResolved("nameplate1")
        local base = #timers
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)   -- start at 100
        -- engage-seeded enter anchor exists until the advance overwrites it
        assert.equals("enter", rt.anchors[10].mode)
        fireTimersAfter(base)                                    -- +0.10s sampler
        local a = rt.anchors[10]
        assert.equals("success", a.mode)
        assert.equals(90, a.anchorAt)          -- startAt - first
        assert.equals(131, a.nextStartAt)      -- startAt + cd[1]
        assert.equals(2, a.nextSeqIndex)       -- one round-robin step
        assert.is_nil(rt.pendingStartAdvanceAt)                  -- consumed
        -- Bolt is cast-kind + success-mode: untouched by a channel start.
        assert.equals("enter", rt.anchors[20].mode)
        local hits = 0
        for _, s in ipairs(scheduled) do
            if s.spellID == 10 and s.nextStart == 131 then hits = hits + 1 end
        end
        assert.equals(1, hits)
    end)

    it("a KICKED channel keeps its start-anchored schedule (the headline fix)", function()
        local rt = trackResolved("nameplate1")
        local base = #timers
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)
        fireTimersAfter(base)
        local before = #scheduled
        clock.now = 105
        DTrash:OnCastInterrupted(nil, "nameplate1", nil, nil, nil, 7)
        assert.equals(131, rt.anchors[10].nextStartAt)   -- untouched by the kick
        assert.equals(2, rt.anchors[10].nextSeqIndex)
        assert.equals(before, #scheduled)                -- no duplicate emit
    end)

    it("advance consumed on LATE resolution, even after the kick landed", function()
        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        local base = #timers
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)   -- unresolved: pending waits
        fireTimersAfter(base)
        assert.equals(100, rt.pendingStartAdvanceAt)             -- armed, unconsumed
        clock.now = 103
        DTrash:OnCastInterrupted(nil, "nameplate1", nil, nil, nil, 7)
        assert.equals(100, rt.pendingStartAdvanceAt)             -- kick can't cancel it
        rt.matchedNPCID = 111                                    -- resolution arrives
        DTrash:ApplyPendingStartAdvance(rt)
        assert.equals(131, rt.anchors[10].nextStartAt)           -- anchored at the ORIGINAL start
        assert.is_nil(rt.pendingStartAdvanceAt)
    end)

    it("a successful finish does not double-advance the cd round-robin", function()
        local rt = trackResolved("nameplate1")
        local base = #timers
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)
        fireTimersAfter(base)
        clock.now = 120                                          -- full 20s channel
        DTrash:OnChannelStop(nil, "nameplate1", nil, nil, nil, 7)
        assert.equals(131, rt.anchors[10].nextStartAt)           -- not re-emitted
        assert.equals(2, rt.anchors[10].nextSeqIndex)            -- cd[] advanced ONCE
        local hits = 0
        for _, s in ipairs(scheduled) do
            if s.spellID == 10 and s.nextStart == 131 then hits = hits + 1 end
        end
        assert.equals(1, hits)
    end)

    -- Needs-based fingerprint wait: the sampler is the sole
    -- writer of startFingerprintsReady, so an unconditional wait let a plate
    -- blink inside the 0.10s window strand the pending forever. With no
    -- curated start fingerprint there is nothing to sample — consume without
    -- the wait.
    it("consumption does not wait for the sampler when nothing curates a start fingerprint", function()
        local rt = trackResolved("nameplate1")
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)
        assert.is_nil(rt.startFingerprintsReady)         -- sampler never fired
        DTrash:ApplyPendingStartAdvance(rt)              -- (ResolveMob-tail stand-in)
        assert.equals("success", rt.anchors[10].mode)
        assert.equals(131, rt.anchors[10].nextStartAt)
        assert.is_nil(rt.pendingStartAdvanceAt)
    end)

    it("consumption still waits for the sampler when a start fingerprint IS curated", function()
        KE.TrashData[1].mobs[111].spells[10].castStartChangeTarget = true
        local rt = trackResolved("nameplate1")
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)
        DTrash:ApplyPendingStartAdvance(rt)              -- sampler hasn't fired yet
        assert.equals("enter", rt.anchors[10].mode)      -- still waiting
        assert.equals(100, rt.pendingStartAdvanceAt)
    end)

    -- Removal kills the owner (4.4), so a removed plate's sampler does
    -- nothing. Its pending advance stays on the cached table as schedule data
    -- and is consumed after a restore with its own carried samples.
    it("a removed plate's sampler does nothing; its pending advance survives as schedule data", function()
        local rt = trackResolved("nameplate1")
        rt.castConfirmed = true
        local base = #timers
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)
        local sampler = #timers
        DTrash:OnNameplateRemoved(nil, "nameplate1")     -- cached mid-window; owner dead
        for i = base + 1, sampler do timers[i].fn() end  -- the sampler is refused
        assert.is_nil(rt.startFingerprintsReady)
        assert.equals(100, rt.pendingStartAdvanceAt)
        assert.equals("enter", rt.anchors[10].mode)
        DTrash:OnNameplateAdded(nil, "nameplate7")
        local adopted = DTrash:TryRestoreCachedRuntime(DTrash.tracked.nameplate7, 111)
        assert.equals(rt, adopted)
        DTrash:ApplyPendingStartAdvance(adopted)
        assert.equals("success", rt.anchors[10].mode)
        assert.equals(131, rt.anchors[10].nextStartAt)
        assert.is_nil(rt.pendingStartAdvanceAt)
    end)

    -- Transition proof (4.4) replaces the +1 rule: a channel is its cast's
    -- channel phase only when a two-phase cast phase explains the measured
    -- cast, after the cast's own STOP within the pairing window or while the
    -- cast is still open. Bar IDs are opaque; any distinct ID works.
    local function addTwoPhase()
        KE.TrashData[1].mobs[111].spells[60] = { name = "Beam", castTime = 3, channelTime = 6,
            first = 7, cd = { 15 } }
    end

    it("a proven channel phase after its cast's STOP clears the advance and arms none", function()
        addTwoPhase()
        local rt = trackResolved("nameplate1")
        DTrash:OnCastStart(nil, "nameplate1", nil, nil, "a")
        assert.equals(100, rt.pendingStartAdvanceAt)
        clock.now = 103
        DTrash:OnCastStop(nil, "nameplate1", nil, nil, "a")
        clock.now = 103.1
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, "b")
        assert.is_true(rt.sawCastIntoChannel)
        assert.equals(100, rt.transitionCastStartAt)
        assert.is_nil(rt.pendingStartAdvanceAt)
        clock.now = 110
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, "c")   -- no cast before it: unproven
        assert.is_nil(rt.transitionCastStartAt)
        assert.equals(110, rt.pendingStartAdvanceAt)
        assert.equals("channel", rt.pendingStartAdvanceKind)
    end)

    it("a channel starting while its cast is still open is proven through the implied stop", function()
        addTwoPhase()
        local rt = trackResolved("nameplate1")
        DTrash:OnCastStart(nil, "nameplate1", nil, nil, "a")
        clock.now = 103
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, "b")   -- the cast's STOP never arrived
        assert.is_true(rt.sawCastIntoChannel)
        assert.equals(100, rt.transitionCastStartAt)
        assert.is_nil(rt.pendingStartAdvanceAt)
        clock.now = 103.05
        DTrash:OnCastStop(nil, "nameplate1", nil, nil, "a")      -- the replaced cast's late STOP is refused
        assert.equals("channel", rt.activeCastKind)
        assert.equals(100, rt.transitionCastStartAt)
    end)

    it("a channel is not proven when no two-phase cast explains the cast, or its STOP is too old", function()
        addTwoPhase()
        local cases = {
            { castFor = 1, gap = 0.1 },   -- 1 s: no two-phase cast phase fits
            { castFor = 3, gap = 0.5 },   -- outside the 0.25 s pairing window
        }
        for i, c in ipairs(cases) do
            local unit = "nameplate" .. i
            local rt = trackResolved(unit)
            local t0 = clock.now
            DTrash:OnCastStart(nil, unit, nil, nil, "a")
            clock.now = t0 + c.castFor
            DTrash:OnCastStop(nil, unit, nil, nil, "a")
            clock.now = clock.now + c.gap
            DTrash:OnChannelStart(nil, unit, nil, nil, "b")
            assert.is_nil(rt.sawCastIntoChannel, "row " .. i)
            assert.is_nil(rt.transitionCastStartAt, "row " .. i)
            assert.equals(clock.now, rt.pendingStartAdvanceAt, "row " .. i)
        end
    end)

    -- WS9: a curated forced cast SEQUENCE (KE.TrashForcedCastSequences) names
    -- fingerprint-identical bare casts by POSITION, consulted before inference
    -- and advanced only by successful finishes (Phalanx Breaker's shipped case).
    describe("forced cast sequences (WS9)", function()
        local function addTwins()
            KE.TrashForcedCastSequences = { [111] = { 40, 30 } }
            local spells = KE.TrashData[1].mobs[111].spells
            spells[30] = { name = "Twin A", castTime = 5, first = 8, cd = { 20 } }
            spells[40] = { name = "Twin B", castTime = 5, first = 9, cd = { 25 } }
        end

        it("names fingerprint-identical twin casts by curated position", function()
            addTwins()
            local rt = trackResolved("nameplate1")
            DTrash:OnCastStart(nil, "nameplate1", nil, nil, 3)
            clock.now = 105
            DTrash:OnCastStop(nil, "nameplate1", nil, nil, 3)
            assert.equals("success", rt.anchors[40].mode)     -- position 1 → Twin B
            assert.equals(130, rt.anchors[40].nextStartAt)    -- stop 105 + cd 25
            assert.equals("enter", rt.anchors[30].mode)       -- engage seed untouched
            clock.now = 110
            DTrash:OnCastStart(nil, "nameplate1", nil, nil, 4)
            clock.now = 115
            DTrash:OnCastStop(nil, "nameplate1", nil, nil, 4)
            assert.equals("success", rt.anchors[30].mode)     -- position 2 → Twin A
            assert.equals(135, rt.anchors[30].nextStartAt)    -- stop 115 + cd 20
            assert.equals(130, rt.anchors[40].nextStartAt)    -- position-1 anchor kept
        end)

        it("a kicked cast does not advance the forced order", function()
            addTwins()
            local rt = trackResolved("nameplate1")
            DTrash:OnCastStart(nil, "nameplate1", nil, nil, 3)
            clock.now = 105
            DTrash:OnCastStop(nil, "nameplate1", nil, nil, 3)  -- position 1 consumed (40)
            clock.now = 110
            DTrash:OnCastStart(nil, "nameplate1", nil, nil, 4)
            clock.now = 112
            DTrash:OnCastInterrupted(nil, "nameplate1", nil, nil, nil, 4)  -- kicked: never consulted
            clock.now = 120
            DTrash:OnCastStart(nil, "nameplate1", nil, nil, 5)
            clock.now = 125
            DTrash:OnCastStop(nil, "nameplate1", nil, nil, 5)
            assert.equals(2, rt._forcedCastIndex)              -- the kick never advanced it
            assert.equals("success", rt.anchors[30].mode)      -- position 2 → Twin A
            assert.equals(145, rt.anchors[30].nextStartAt)     -- stop 125 + cd 20
        end)
    end)

    describe("TI.MatchesObservedCastStart / IsStartAdvanceOwned (pure)", function()
        it("two-phase spells start-match ONLY their cast phase", function()
            local twoPhase = { cdMode = "CAST_START", castTime = 2, channelTime = 5 }
            assert.is_true(TI.MatchesObservedCastStart(twoPhase, "cast", {}))
            assert.is_false(TI.MatchesObservedCastStart(twoPhase, "channel", {}))
            local pureChannel = { cdMode = "CAST_START", channelTime = 5 }
            assert.is_false(TI.MatchesObservedCastStart(pureChannel, "cast", {}))
            assert.is_true(TI.MatchesObservedCastStart(pureChannel, "channel", {}))
        end)

        it("a castStartAuraDelta spell is never start-advance-owned", function()
            local ambush = { cdMode = "CAST_START", castTime = 3.5, castStartAuraDelta = true }
            assert.is_false(TI.IsStartAdvanceOwned(ambush))
            -- The entry gate refuses too, and this line is CARRIED FORWARD
            -- unchanged from the case being replaced: it is the dark-path
            -- outcome, so it must survive.
            assert.is_false(TI.MatchesObservedCastStart(ambush, "cast", {}))
        end)

        it("a plain CAST_START spell is owned", function()
            assert.is_true(TI.IsStartAdvanceOwned({ cdMode = "CAST_START", channelTime = 5 }))
            assert.is_false(TI.IsStartAdvanceOwned({ cdMode = "SUCCESS", castTime = 2 }))
        end)

        it("NeedsStartFingerprints never waits for a castStartAuraDelta spell", function()
            local mob = { spells = { [1] = { cdMode = "CAST_START", castTime = 3.5,
                castStartAuraDelta = true } } }
            assert.is_false(TI.NeedsStartFingerprints(mob))
        end)

        it("sampled fingerprints gate the match; unsampled stay lenient", function()
            local sp = { cdMode = "CAST_START", channelTime = 5, castStartChangeTarget = true }
            assert.is_false(TI.MatchesObservedCastStart(sp, "channel", { castStartChangeTarget = false }))
            assert.is_true(TI.MatchesObservedCastStart(sp, "channel", { castStartChangeTarget = true }))
            assert.is_true(TI.MatchesObservedCastStart(sp, "channel", {}))
        end)
    end)

    -- Producer-side pin for the chains fix: KE can PROVE a cast→
    -- channel transition (castBarID +1 in the pairing window) but can never
    -- affirm its ABSENCE — a missed pairing is indistinguishable from a bare
    -- channel — so an unpaired channel must stay LENIENT and still credit a
    -- two-phase spell (Chains of Subjugation went permanently uncreditable
    -- when the unpaired case produced castIntoChannel=false).
    it("an UNPAIRED channel stays lenient and still credits a two-phase spell", function()
        KE.TrashData[1].mobs[111].spells = {
            [60] = { name = "Chains", castTime = 2, channelTime = 6, first = 7, cd = { 15 } },
        }
        local rt = trackResolved("nameplate1")
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 9)   -- no prior cast: pairing impossible
        clock.now = 106
        DTrash:OnChannelStop(nil, "nameplate1", nil, nil, nil, 9)
        assert.equals("success", rt.anchors[60].mode)   -- credited despite no transition proof
        assert.equals(121, rt.anchors[60].nextStartAt)  -- successAt (100+6) + cd 15
    end)

    describe("WS8 fingerprint completeness (pure)", function()
        it("channel evidence discriminates two-phase vs pure channels", function()
            local pure = { channelTime = 5 }
            local twoPhase = { castTime = 2, channelTime = 5 }
            local proven = { kind = "channel", duration = 5, castIntoChannel = true }
            local bare = { kind = "channel", duration = 5, castIntoChannel = false }
            local unknown = { kind = "channel", duration = 5 }
            assert.is_false(TI.SpellMatchesObserved(pure, proven))    -- proof → two-phase only
            assert.is_true(TI.SpellMatchesObserved(twoPhase, proven))
            assert.is_true(TI.SpellMatchesObserved(pure, bare))       -- no proof → pure only
            assert.is_false(TI.SpellMatchesObserved(twoPhase, bare))
            assert.is_true(TI.SpellMatchesObserved(pure, unknown))    -- unknowable → lenient
            assert.is_true(TI.SpellMatchesObserved(twoPhase, unknown))
        end)

        it("dormant fingerprints are mapped: castStartTargetUnitExists + targetIsTank", function()
            local spellA = { castTime = 3, castStartTargetUnitExists = true }
            assert.is_false(TI.SpellMatchesObserved(spellA,
                { kind = "cast", duration = 3, fingerprints = { targetExists = false } }))
            assert.is_true(TI.SpellMatchesObserved(spellA,
                { kind = "cast", duration = 3, fingerprints = { targetExists = true } }))
            local spellB = { castTime = 3, targetIsTank = true }
            assert.is_false(TI.SpellMatchesObserved(spellB,
                { kind = "cast", duration = 3, fingerprints = { targetIsTank = false } }))
            assert.is_true(TI.SpellMatchesObserved(spellB,
                { kind = "cast", duration = 3, fingerprints = {} }))  -- unsampled: lenient
        end)
    end)
end)
