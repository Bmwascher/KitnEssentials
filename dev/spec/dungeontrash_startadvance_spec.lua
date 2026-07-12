-- Tier 2: DungeonTrash CAST_START pending start-advance (WS1).
-- CAST_START-mode spells anchor their cd at the observed cast START, whatever
-- the outcome — the reference's ONLY anchor path for them (its success-mode
-- inference returns nil for CAST_START), and the reason a KICKED Pulsing
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
        world = { combat = {} }
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

        local modules = helpers.installAddonShim()
        KE = { Print = function() end }  -- DEBUG_DTRASH dprints route here
        helpers.loadModule("Modules/DungeonTimers/Trash/TrashInference.lua", KE)
        helpers.loadModule("Modules/DungeonTimers/Trash/DungeonTrash.lua", KE)
        helpers.loadModule("Modules/DungeonTimers/Trash/TrashCache.lua", KE)
        DTrash = modules["DungeonTrash"]
        TI = KE.TrashInference

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

    -- Needs-based fingerprint wait (drift review B5): the sampler is the sole
    -- writer of startFingerprintsReady, so an unconditional wait let a plate
    -- blink inside the 0.10s window strand the pending forever. With no
    -- curated start fingerprint there is nothing to sample — consume without
    -- the wait (the reference's waits exist only for spells that curate one).
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

    it("a plate blink inside the sample window cannot poison the pending (flicker-gap)", function()
        local rt = trackResolved("nameplate1")
        rt.castConfirmed = true
        local base = #timers
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)
        DTrash:OnNameplateRemoved(nil, "nameplate1")     -- cached mid-window
        assert.is_true(rt._cachePending)
        fireTimersAfter(base)                            -- sampler fires mid-gap
        assert.equals("success", rt.anchors[10].mode)    -- consumed, not stranded
        assert.is_nil(rt.pendingStartAdvanceAt)
    end)

    it("a paired cast->channel transition does not arm a fresh advance", function()
        DTrash:OnNameplateAdded(nil, "nameplate1")               -- stays unresolved
        local rt = DTrash.tracked.nameplate1
        DTrash:OnCastStart(nil, "nameplate1", nil, nil, 5)
        assert.equals(100, rt.pendingStartAdvanceAt)
        assert.equals("cast", rt.pendingStartAdvanceKind)
        clock.now = 103
        DTrash:OnCastStop(nil, "nameplate1", nil, nil, 5)
        clock.now = 103.1
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 6)    -- +1 within window: paired
        assert.is_true(rt.sawCastIntoChannel)
        assert.is_nil(rt.pendingStartAdvanceAt)                  -- cleared, NOT re-armed
        -- an UNPAIRED start re-arms normally
        clock.now = 110
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 9)
        assert.equals(110, rt.pendingStartAdvanceAt)
        assert.equals("channel", rt.pendingStartAdvanceKind)
    end)

    -- Drift review D2: the reference pairs the incoming channel against the
    -- STILL-ACTIVE cast (isCastIntoChannel needs no processed STOP) — a late,
    -- reordered or dropped STOP must not break the transition proof. Each
    -- KE-only miss fired the phantom one-phase twin credit AND anchored the
    -- channel late by castTime.
    it("an implied-stop +1 channel pairs against the STILL-ACTIVE cast (D2)", function()
        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        DTrash:OnCastStart(nil, "nameplate1", nil, nil, 5)
        clock.now = 103
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 6)   -- STOP never processed
        assert.is_true(rt.sawCastIntoChannel)
        assert.equals(100, rt.transitionCastStartAt)    -- anchors at the TRUE cast start
        assert.is_nil(rt.pendingStartAdvanceAt)         -- paired: no fresh advance
        -- the superseded cast's late STOP is now a stale event
        clock.now = 103.05
        DTrash:OnCastStop(nil, "nameplate1", nil, nil, 5)
        assert.equals("channel", rt.activeCastKind)     -- channel untouched
        assert.equals(100, rt.transitionCastStartAt)    -- pairing intact for the channel finish
    end)

    it("a non-adjacent channel while a cast is active does not pair (D2 control)", function()
        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        DTrash:OnCastStart(nil, "nameplate1", nil, nil, 5)
        clock.now = 103
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 9)   -- +4: not the same castbar rolling over
        assert.is_nil(rt.sawCastIntoChannel)
        assert.is_nil(rt.transitionCastStartAt)
        assert.equals(103, rt.pendingStartAdvanceAt)    -- unpaired start re-arms
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

        it("a spell curating the unported castStartAuraDelta is not start-advance owned", function()
            local ambush = { cdMode = "CAST_START", castTime = 3.5, castStartAuraDelta = true }
            assert.is_false(TI.IsStartAdvanceOwned(ambush))
            assert.is_false(TI.MatchesObservedCastStart(ambush, "cast", {}))
            assert.is_true(TI.IsStartAdvanceOwned({ cdMode = "CAST_START", channelTime = 5 }))
            assert.is_false(TI.IsStartAdvanceOwned({ cdMode = "SUCCESS", castTime = 2 }))
        end)

        it("sampled fingerprints gate the match; unsampled stay lenient", function()
            local sp = { cdMode = "CAST_START", channelTime = 5, castStartChangeTarget = true }
            assert.is_false(TI.MatchesObservedCastStart(sp, "channel", { castStartChangeTarget = false }))
            assert.is_true(TI.MatchesObservedCastStart(sp, "channel", { castStartChangeTarget = true }))
            assert.is_true(TI.MatchesObservedCastStart(sp, "channel", {}))
        end)
    end)

    -- Producer-side pin for the 2026-07-10 chains fix: KE can PROVE a cast→
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
