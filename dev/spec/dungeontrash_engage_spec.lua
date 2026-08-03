-- Tier 2: DungeonTrash engage-gated first-cast seeding (Batch B).
-- A mob that is BOTH resolved and engaged gets speculative "enter" anchors +
-- first-cast countdowns for every curated spell before it ever casts. The
-- 2026-07-07 revert taught the failure mode (seeding from plate-visibility lit
-- up the whole room), so the gates ARE the feature: these specs pin that a
-- seed happens only with combat evidence, only once, and never clobbers a
-- real anchor. Live alert rendering stays in-game-only.

local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("DungeonTrash — engage-gated first-cast seeding", function()
    local DTrash, KE, clock, timers, world, scheduled, predicted

    before_each(function()
        clock = { now = 100 }
        timers = {}
        world = { combat = {}, hostile = {}, dead = {}, auras = {} }
        scheduled, predicted = {}, {}

        mock.install({
            GetTime = function() return clock.now end,
            C_Timer = {
                After = function(delay, fn)
                    timers[#timers + 1] = { at = clock.now + delay, fn = fn }
                end,
            },
        })
        _G.UnitIsDead = function(u) return world.dead[u] == true end
        _G.UnitAffectingCombat = function(u) return world.combat[u] == true end
        -- nil (unset) = unreadable answer → the intake gate fails OPEN, so
        -- every test that doesn't care about hostility still tracks plates.
        _G.UnitCanAttack = function(_, u) return world.hostile[u] end
        -- Controllable aura count for the success buff-count delta sampler.
        _G.C_UnitAuras = { GetAuraDataByIndex = function(u, i)
            if i <= (world.auras[u] or 0) then return {} end
            return nil
        end }
        _G.GetInstanceInfo = function() return "Dungeon", "party", 8, nil, nil, nil, nil, 1 end
        _G.IsInInstance = function() return true, "party" end

        local modules = helpers.installAddonShim()
        KE = { Print = function() end }  -- DEBUG_DTRASH dprints route here
        -- Trash.xml order: inference first, so DungeonTrash's load-time
        -- `local TI = KE.TrashInference` binds.
        helpers.loadModule("Modules/DungeonTimers/Trash/TrashInference.lua", KE)
        helpers.loadModule("Modules/DungeonTimers/Trash/DungeonTrash.lua", KE)
        helpers.loadModule("Modules/DungeonTimers/Trash/TrashCache.lua", KE)
        DTrash = modules["DungeonTrash"]

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
        KE.TrashData = { [1] = { mobs = { [111] = { npcID = 111, name = "Mob", spells = {
            [10] = { name = "Slam",  first = 5,  cd = { 20 }, castTime = 2 },
            [20] = { name = "Bolt",  first = 12, cd = { 15 }, castTime = 3 },
            [30] = { name = "NoCd",  castTime = 4 },  -- unschedulable: no first/cd
        } } } } }
    end)

    after_each(function()
        mock.reset()
        _G.UnitIsDead = nil
        _G.UnitAffectingCombat = nil
        _G.UnitCanAttack = nil
        _G.C_UnitAuras = nil
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

    it("does NOT seed a resolved mob without combat evidence (the revert's lesson)", function()
        local rt = trackResolved("nameplate1")
        DTrash:SeedFirstCasts(rt)
        assert.is_nil(rt.engagedAt)          -- plate-add no longer stamps engage
        assert.is_falsy(rt.enterSeeded)
        assert.same({}, scheduled)
    end)

    it("seeds enter anchors + outputs the moment an already-resolved mob engages", function()
        local rt = trackResolved("nameplate1")
        clock.now = 110
        DTrash:MarkEngaged(rt)
        assert.equals(110, rt.engagedAt)
        assert.is_true(rt.enterSeeded)
        -- both schedulable spells armed at engagedAt + first
        assert.equals(2, #scheduled)
        local byId = {}
        for _, s in ipairs(scheduled) do byId[s.spellID] = s end
        assert.equals(115, byId[10].nextStart)   -- 110 + 5
        assert.equals(122, byId[20].nextStart)   -- 110 + 12
        assert.is_nil(byId[30])                  -- no first/cd → never seeded
        -- anchors carry the enter invariant: anchorAt + first == nextStartAt
        assert.equals("enter", rt.anchors[10].mode)
        assert.equals(110, rt.anchors[10].anchorAt)
        assert.equals(115, rt.anchors[10].nextStartAt)
        assert.equals(1, rt.anchors[10].nextSeqIndex)
        -- plate icons got the same prediction; swipe origin = REGISTRATION
        -- time (here the seed happens AT the engage moment, so they coincide)
        assert.equals(2, #predicted)
        assert.equals(110, predicted[1].startTime)
    end)

    it("seeds when resolution arrives AFTER engagement, rolled past missed occurrences", function()
        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        DTrash:MarkEngaged(rt)                   -- engaged at 100, unresolved → no seed yet
        assert.is_falsy(rt.enterSeeded)
        clock.now = 112                          -- Slam's first (105) already missed
        rt.matchedNPCID = 111
        DTrash:SeedFirstCasts(rt)
        assert.is_true(rt.enterSeeded)
        local byId = {}
        for _, s in ipairs(scheduled) do byId[s.spellID] = s end
        assert.equals(125, byId[10].nextStart)   -- rolled: 105 + cd 20
        -- Bolt's first lands exactly at now (112): inside MIN_LEAD there is
        -- nothing to count down to, so it rolls a cycle (112 + cd 15).
        assert.equals(127, rt.anchors[20].nextStartAt)
        -- Rolled seed draws a FRESH swipe: origin = registration (112), never
        -- the engage moment (100) — a pre-drained arc was the P1 drift.
        assert.equals(112, predicted[1].startTime)
    end)

    it("seeds only ONCE per runtime", function()
        local rt = trackResolved("nameplate1")
        DTrash:MarkEngaged(rt)
        local count = #scheduled
        DTrash:SeedFirstCasts(rt)
        DTrash:MarkEngaged(rt)                   -- engage stamp is once-only too
        assert.equals(count, #scheduled)
        assert.equals(100, rt.engagedAt)
    end)

    it("never clobbers an existing (real) anchor", function()
        local rt = trackResolved("nameplate1")
        rt.anchors = { [10] = { mode = "success", anchorAt = 95, nextSeqIndex = 2, nextStartAt = 118 } }
        DTrash:MarkEngaged(rt)
        assert.equals("success", rt.anchors[10].mode)   -- untouched
        assert.equals(118, rt.anchors[10].nextStartAt)
        assert.equals("enter", rt.anchors[20].mode)     -- the unseen spell still seeds
    end)

    it("plate added mid-combat stamps engagedAt immediately", function()
        world.combat.nameplate1 = true
        DTrash:OnNameplateAdded(nil, "nameplate1")
        assert.equals(clock.now, DTrash.tracked.nameplate1.engagedAt)
    end)

    it("PLAYER_REGEN sweep engages + seeds a mob whose own UNIT_FLAGS edge was missed", function()
        local rt = trackResolved("nameplate1")
        rt.obs = {}                                      -- identity already read
        world.combat.nameplate1 = true                   -- in combat, but no event edge ever seen
        DTrash:OnPlayerCombatChanged()
        assert.equals(clock.now, rt.engagedAt)
        assert.is_true(rt.enterSeeded)
        assert.is_true(#scheduled > 0)
    end)

    it("interrupt evidence stamps engagement and seeds a resolved mob", function()
        local rt = trackResolved("nameplate1")
        DTrash:OnCastInterrupted(nil, "nameplate1", nil, nil, nil, 4)
        assert.equals(100, rt.engagedAt)
        assert.is_true(rt.enterSeeded)
    end)

    it("a mob resolved by a cast that then DEFIES inference still seeds its schedules", function()
        KE.TrashData[1].mobs[111].spells = {
            [30] = { name = "Grab", channelTime = 4 },   -- matches duration; unschedulable
            [40] = { name = "Volley", castTime = 2, first = 7, cd = { 20 } },
        }
        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        rt.candidates = { { npcID = 111 } }
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)  -- engages; unresolved: no seed
        assert.is_falsy(rt.enterSeeded)
        clock.now = 104                                  -- 4s stop = Grab's channelTime
        DTrash:OnChannelStop(nil, "nameplate1", nil, nil, nil, 7)
        assert.equals(111, rt.matchedNPCID)              -- Layer2-verified lone candidate
        assert.is_true(rt.enterSeeded)                   -- seeded on the inference-failure exit
        assert.equals("enter", rt.anchors[40].mode)
        assert.is_nil(rt.anchors[30])                    -- no first/cd → never seeded
    end)

    it("a delta-curating CHANNEL defers its credit for the buff-count sample", function()
        KE.TrashData[1].mobs[111].spells = {
            [50] = { name = "Drain", channelTime = 4, first = 6, cd = { 20 },
                selfBuffCountDeltaOnSuccess = 1 },
        }
        local rt = trackResolved("nameplate1")
        world.auras.nameplate1 = 2
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)   -- engages + enter-seeds [50]
        clock.now = 104                                          -- 4s = Drain's channelTime
        local base = #timers
        DTrash:OnChannelStop(nil, "nameplate1", nil, nil, nil, 7)
        assert.equals("enter", rt.anchors[50].mode)              -- credit still deferred
        world.auras.nameplate1 = 3                               -- +1 buff on success
        for i = base + 1, #timers do timers[i].fn() end
        assert.equals("success", rt.anchors[50].mode)            -- sampled delta 1 matched
        assert.equals(124, rt.anchors[50].nextStartAt)           -- successAt(104) + cd 20
    end)

    -- Drift review B7: a deferred credit lands only under the identity that
    -- earned it (reference: candidateChanged wipes pending success state
    -- before consumption). A contradiction FLIP inside the 0.10s sample
    -- window otherwise re-armed the discredited npcID's anchors and alerts
    -- right after resetResolvedOutput swept them.
    it("a deferred credit dies when the identity flips inside its window (B7)", function()
        KE.TrashData[1].dungeonKey = "D"
        KE.TrashData[1].mobs[111].spells = {
            [50] = { name = "Drain", channelTime = 4, first = 6, cd = { 20 },
                selfBuffCountDeltaOnSuccess = 1 },
        }
        KE.TrashTraits = {
            [111] = { dungeonKey = "D", name = "Mob",
                identity = { level = 91, sex = 2, power = 0, classID = 2, nonElite = true,
                    hasCastSpell = true, hasChannelSpell = true, cannotInterrupt = true } },
            [222] = { dungeonKey = "D", name = "Twin",
                identity = { level = 91, sex = 2, power = 0, classID = 2, nonElite = true,
                    hasCastSpell = true, hasChannelSpell = true } },
        }
        local rt = trackResolved("nameplate1")
        rt.obs = { level = 91, sex = 2, power = 0, classID = 2, buffCount = 0,
            unitClassification = "normal" }
        world.auras.nameplate1 = 2
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)
        clock.now = 104
        local base = #timers
        DTrash:OnChannelStop(nil, "nameplate1", nil, nil, nil, 7)  -- credit deferred
        -- contradiction evidence lands inside the window: the kick rejects
        -- 111 (cannotInterrupt) and re-derivation flips to its interruptible
        -- twin, sweeping 111's output
        DTrash:OnCastInterrupted(nil, "nameplate1", nil, nil, nil, 9)
        assert.equals(222, rt.matchedNPCID)
        world.auras.nameplate1 = 3                                 -- delta WOULD match
        for i = base + 1, #timers do timers[i].fn() end            -- closure fires
        assert.is_nil(rt.anchors)                                  -- no resurrected credit
    end)

    it("combat flips reset the target-state sampler", function()
        local rt = trackResolved("nameplate1")
        rt.targetStateExists = true                       -- stale pre-combat baseline
        rt.targetSwitchEvents = { 99 }
        world.combat.nameplate1 = true
        DTrash:OnUnitFlags(nil, "nameplate1")             -- OOC→IC: reset via MarkEngaged
        assert.is_nil(rt.targetSwitchEvents)
        world.combat.nameplate1 = false
        DTrash:OnUnitFlags(nil, "nameplate1")             -- IC→OOC flip: baseline cleared
        assert.is_nil(rt.targetStateExists)
    end)

    it("friendly and dead plates never enter tracking; unreadable fails OPEN", function()
        world.hostile.nameplate1 = false                 -- friendly/pet: rejected
        DTrash:OnNameplateAdded(nil, "nameplate1")
        assert.is_nil(DTrash.tracked.nameplate1)
        world.hostile.nameplate2 = true                  -- hostile but dead: rejected
        world.dead.nameplate2 = true
        DTrash:OnNameplateAdded(nil, "nameplate2")
        assert.is_nil(DTrash.tracked.nameplate2)
        DTrash:OnNameplateAdded(nil, "nameplate3")       -- unreadable answer: kept
        assert.is_not_nil(DTrash.tracked.nameplate3)
    end)

    it("pre-castConfirmed identity flip cancels the old output and re-seeds the new mob", function()
        KE.TrashData[1].dungeonKey = "D"
        KE.TrashData[1].mobs[222] = { npcID = 222, name = "Twin", spells = {
            [77] = { name = "Rend", first = 6, cd = { 18 }, castTime = 2 },
        } }
        KE.TrashTraits = {
            [111] = { dungeonKey = "D", name = "Mob",
                identity = { sex = 1, power = 1, classID = 9, nonElite = true } },
            [222] = { dungeonKey = "D", name = "Twin",
                identity = { level = 91, sex = 1, power = 1, classID = 2, nonElite = true } },
        }
        local hidden = {}
        DTrash.HideUnitAlerts = function(_, unit, npcID) hidden[#hidden + 1] = { unit, npcID } end

        local rt = trackResolved("nameplate1")           -- matchedNPCID = 111
        DTrash:MarkEngaged(rt)                           -- seeds 111's spells
        assert.is_true(rt.enterSeeded)
        rt._alertTokens = { ["nameplate1:111:10"] = 3 }
        rt.predictions = { [10] = { nextStart = 115 } }

        rt.obs = { level = 91, sex = 1, power = 1, classID = 2, buffCount = 0,
            unitClassification = "normal" }
        DTrash:ResolveMob(rt)                            -- lone levelAgreed survivor: 222

        assert.equals(222, rt.matchedNPCID)
        assert.same({ { "nameplate1", 111 } }, hidden)   -- old identity's bars swept, scoped
        assert.is_nil(next(rt._alertTokens))             -- deferred reveals die via token
        assert.is_nil(next(rt.predictions))              -- plate predictions cleared
        assert.is_true(rt.enterSeeded)                   -- re-seeded for the NEW identity
        assert.equals("enter", rt.anchors[77].mode)
        assert.is_nil(rt.anchors[10])                    -- old spellID anchors gone
    end)

    it("UNIT_FLAGS combat flip engages and seeds a resolved mob", function()
        local rt = trackResolved("nameplate1")
        DTrash:OnUnitFlags(nil, "nameplate1")    -- not in combat yet → nothing
        assert.is_nil(rt.engagedAt)
        clock.now = 108
        world.combat.nameplate1 = true
        DTrash:OnUnitFlags(nil, "nameplate1")
        assert.equals(108, rt.engagedAt)
        assert.is_true(rt.enterSeeded)
        assert.is_true(#scheduled > 0)
    end)

    -- Keep-locked contradiction handling (reference parity, ExBoss v26.6.29
    -- ObservationTest keepLockedRuntime): a behavior contradiction commits
    -- only when re-derivation actually lands on a DIFFERENT mob. When every
    -- surviving row rejects — all five Algeth'ar Academy rows are
    -- cannotInterrupt, so a Shadowmeld-shaped interrupt latch rejects them
    -- ALL — the identity, its lock and its output are KEPT: the reference
    -- retains a locked in-combat runtime rather than blanking the plate
    -- forever (the 2026-07-24 disappearing-timer field report).
    it("a kick contradiction with no resolvable alternative keeps the lock and its output", function()
        KE.TrashData[1].dungeonKey = "D"
        KE.TrashTraits = { [111] = { dungeonKey = "D", name = "Mob",
            identity = { level = 91, sex = 2, power = 0, classID = 2, nonElite = true,
                hasCastSpell = true, hasChannelSpell = true, cannotInterrupt = true } } }
        local hidden = {}
        DTrash.HideUnitAlerts = function(_, unit, npcID) hidden[#hidden + 1] = { unit, npcID } end
        local rt = trackResolved("nameplate1")
        DTrash:MarkEngaged(rt)                            -- armed output for 111
        rt.castConfirmed = true
        rt.obs = { level = 91, sex = 2, power = 0, classID = 2, buffCount = 0,
            unitClassification = "normal" }               -- re-derivation runs and yields nothing
        rt._alertTokens = { ["nameplate1:111:10"] = 1 }
        rt.predictions = { [10] = { nextStart = 115 } }
        DTrash:OnCastInterrupted(nil, "nameplate1", nil, nil, nil, 4)
        assert.is_true(rt.sawInterrupted)                 -- evidence still latched
        assert.equals(111, rt.matchedNPCID)               -- identity kept
        assert.is_true(rt.castConfirmed)                  -- lock kept
        assert.same({}, hidden)                           -- output untouched
        assert.is_not_nil(next(rt.predictions))
        assert.is_not_nil(rt.anchors)
        assert.is_true(rt.enterSeeded)
    end)

    -- The Maisara-hexxer heal the unlock exists for (it wore Rokh'zal's
    -- cannotInterrupt timers through repeated kicks): when the kick's
    -- re-derivation DOES resolve an interruptible sibling, the flip still
    -- commits — through even a castConfirmed lock — with full output hygiene.
    it("a kick contradiction re-resolving to an interruptible sibling flips through the lock", function()
        KE.TrashData[1].dungeonKey = "D"
        KE.TrashData[1].mobs[222] = { npcID = 222, name = "Twin", spells = {
            [77] = { name = "Rend", first = 6, cd = { 18 }, castTime = 2 },
        } }
        KE.TrashTraits = {
            [111] = { dungeonKey = "D", name = "Mob",
                identity = { level = 91, sex = 2, power = 0, classID = 2, nonElite = true,
                    hasCastSpell = true, cannotInterrupt = true } },
            [222] = { dungeonKey = "D", name = "Twin",
                identity = { level = 91, sex = 2, power = 0, classID = 2, nonElite = true,
                    hasCastSpell = true } },
        }
        local hidden = {}
        DTrash.HideUnitAlerts = function(_, unit, npcID) hidden[#hidden + 1] = { unit, npcID } end
        local rt = trackResolved("nameplate1")
        DTrash:MarkEngaged(rt)                            -- seeds 111's spells
        rt.castConfirmed = true                           -- even a Layer2 lock flips on contradiction
        rt.obs = { level = 91, sex = 2, power = 0, classID = 2, buffCount = 0,
            unitClassification = "normal" }
        DTrash:OnCastInterrupted(nil, "nameplate1", nil, nil, nil, 4)  -- genuine kick
        assert.equals(222, rt.matchedNPCID)
        assert.is_nil(rt.castConfirmed)
        assert.same({ { "nameplate1", 111 } }, hidden)    -- old output swept, scoped
        assert.equals("enter", rt.anchors[77].mode)       -- new identity seeded
        assert.is_nil(rt.anchors[10])                     -- old spellID anchors gone
    end)

    it("a kick on an interruptible identity keeps the lock", function()
        KE.TrashTraits = { [111] = { dungeonKey = "D", name = "Mob",
            identity = { level = 91, sex = 2, power = 0, classID = 2,
                hasCastSpell = true, hasChannelSpell = true, cannotInterrupt = false } } }
        local rt = trackResolved("nameplate1")
        DTrash:MarkEngaged(rt)
        DTrash:OnCastInterrupted(nil, "nameplate1", nil, nil, nil, 4)
        assert.equals(111, rt.matchedNPCID)               -- kickable row: evidence consistent
        assert.is_true(rt.enterSeeded)                    -- output untouched
    end)

    -- FAILED is NOT interrupt evidence (in-game Algeth'ar Academy 2026-07-10;
    -- documented deviation — the reference's FAILED handlers latch the same
    -- sticky sawInterrupted a kick sets): a cast aborts on Shadowmeld / LoS /
    -- CC without proving anything about interruptibility. All five Academy
    -- trait rows are cannotInterrupt, so one abort permanently rejected every
    -- row on that plate — unresolved Ravagers never gained timers, resolved
    -- ones dropped and never came back.
    it("a FAILED cast tears down the lifecycle but never poisons cannotInterrupt rows", function()
        KE.TrashTraits = { [111] = { dungeonKey = "D", name = "Mob",
            identity = { level = 91, sex = 2, power = 0, classID = 2,
                hasCastSpell = true, hasChannelSpell = true, cannotInterrupt = true } } }
        local rt = trackResolved("nameplate1")
        DTrash:MarkEngaged(rt)
        DTrash:OnCastStart(nil, "nameplate1", nil, nil, 4)
        clock.now = 102
        DTrash:OnCastFailed(nil, "nameplate1", nil, nil, 4)   -- Shadowmeld/CC abort
        assert.is_nil(rt.sawInterrupted)                  -- no false testimony
        assert.equals(111, rt.matchedNPCID)               -- identity kept
        assert.is_true(rt.enterSeeded)                    -- output kept
        assert.is_nil(rt.activeCastKind)                  -- lifecycle torn down
        -- a REAL kick afterwards still latches evidence — but with every row
        -- cannotInterrupt and no resolvable alternative, the identity is KEPT
        -- (keep-locked) instead of blanking the plate
        DTrash:OnCastInterrupted(nil, "nameplate1", nil, nil, nil, 5)
        assert.is_true(rt.sawInterrupted)
        assert.equals(111, rt.matchedNPCID)
    end)

    -- interruptedBy on a correlated CHANNEL_STOP is a lifecycle signal, not
    -- kick evidence (reference parity: MarkRuntimeChannelStop feeds it only
    -- into pendingInterrupted; the Layer1-visible sawInterrupted latches
    -- ONLY from the INTERRUPTED/FAILED events). Hardening alongside the
    -- 2026-07-24 keep-locked fix: a Shadowmeld breaking a channel aimed at
    -- the melder (Riftbreath's channel phase) would stop it with
    -- interruptedBy present, and the old latch here rejected every
    -- cannotInterrupt Academy row exactly like the FAILED latch had.
    it("an interruptedBy channel stop ends the lifecycle without latching kick evidence", function()
        KE.TrashTraits = { [111] = { dungeonKey = "D", name = "Mob",
            identity = { level = 91, sex = 2, power = 0, classID = 2, nonElite = true,
                hasCastSpell = true, hasChannelSpell = true, cannotInterrupt = true } } }
        local rt = trackResolved("nameplate1")
        DTrash:MarkEngaged(rt)
        DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)
        clock.now = 102
        DTrash:OnChannelStop(nil, "nameplate1", nil, nil, "Player-1-ABCD", 7)  -- meld-broken
        assert.is_nil(rt.sawInterrupted)              -- no false kick testimony
        assert.equals(111, rt.matchedNPCID)           -- identity kept
        assert.is_true(rt.enterSeeded)                -- output kept
        assert.is_nil(rt.activeCastKind)              -- lifecycle torn down
        assert.equals("enter", rt.anchors[10].mode)   -- no success credit for the abort
    end)

    -- castConfirmed gating (drift review A2): the lock's strength comes from
    -- the pool shape BEFORE the cast. A multi-pool collapse can be driven by
    -- NEGATIVE evidence (an uncurated filler cast failing the true mob while
    -- coincidentally matching a sibling), so it resolves WITHOUT the lock —
    -- Layer1 re-derivation can still heal it, approximating the reference's
    -- stateless semantics. A verified lone survivor / levelAgreed winner
    -- keeps earning the lock (the pinned D14 compensation).
    describe("Layer2 confirm strength", function()
        local function addTwin()
            KE.TrashData[1].mobs[222] = { npcID = 222, name = "Twin", spells = {
                [77] = { name = "Rend", first = 6, cd = { 18 }, castTime = 6 },
            } }
        end
        local function castSixSeconds(unit)
            DTrash:OnCastStart(nil, unit, nil, nil, 4)
            clock.now = clock.now + 6
            DTrash:OnCastStop(nil, unit, nil, nil, 4)
        end

        it("a multi-pool collapse resolves FLIPPABLE — no castConfirmed lock", function()
            addTwin()
            DTrash:OnNameplateAdded(nil, "nameplate1")
            local rt = DTrash.tracked.nameplate1
            -- Two level-disagreed siblings; the 6s cast matches only 222.
            rt.candidates = { { npcID = 111 }, { npcID = 222 } }
            castSixSeconds("nameplate1")
            assert.equals(222, rt.matchedNPCID)
            assert.is_nil(rt.castConfirmed)
        end)

        it("a multi-pool collapse onto a levelAgreed winner still locks", function()
            addTwin()
            DTrash:OnNameplateAdded(nil, "nameplate1")
            local rt = DTrash.tracked.nameplate1
            rt.candidates = { { npcID = 111 }, { npcID = 222, levelAgreed = true } }
            castSixSeconds("nameplate1")
            assert.equals(222, rt.matchedNPCID)
            assert.is_true(rt.castConfirmed)
        end)

        it("a verified lone survivor still locks (the pinned D14 shape)", function()
            addTwin()
            DTrash:OnNameplateAdded(nil, "nameplate1")
            local rt = DTrash.tracked.nameplate1
            rt.candidates = { { npcID = 222 } }   -- lone, level-disagreed
            castSixSeconds("nameplate1")
            assert.equals(222, rt.matchedNPCID)
            assert.is_true(rt.castConfirmed)
        end)

        -- A5 resolve-without-lock (Brandon 2026-07-10: reference-true): a bare
        -- channel — transition unprovable, castIntoChannel nil — matches a
        -- TWO-PHASE spell's channelTime as easily as a pure channel's. The
        -- reference survives that lenient match because it never locks; KE's
        -- castConfirmed must not be earned by it. Resolve + output still arm.
        local function addTwoPhaseTwin()
            KE.TrashData[1].mobs[222] = { npcID = 222, name = "Twin", spells = {
                [88] = { name = "Chains", castTime = 2, channelTime = 6,
                    first = 7, cd = { 15 } },
            } }
        end

        it("a bare channel verifying a two-phase-only survivor resolves WITHOUT the lock (A5)", function()
            addTwoPhaseTwin()
            DTrash:OnNameplateAdded(nil, "nameplate1")
            local rt = DTrash.tracked.nameplate1
            rt.candidates = { { npcID = 222 } }          -- lone, level-disagreed
            DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 7)   -- bare: no prior cast
            clock.now = 106
            DTrash:OnChannelStop(nil, "nameplate1", nil, nil, nil, 7)
            assert.equals(222, rt.matchedNPCID)          -- resolves...
            assert.equals("success", rt.anchors[88].mode) -- ...and output arms
            assert.is_nil(rt.castConfirmed)              -- but stays flippable
        end)

        it("a PROVEN cast->channel transition still earns the lock (A5 control)", function()
            addTwoPhaseTwin()
            DTrash:OnNameplateAdded(nil, "nameplate1")
            local rt = DTrash.tracked.nameplate1
            rt.candidates = { { npcID = 222 } }
            DTrash:OnCastStart(nil, "nameplate1", nil, nil, 5)
            clock.now = 102
            DTrash:OnCastStop(nil, "nameplate1", nil, nil, 5)       -- cast phase ends
            DTrash:OnChannelStart(nil, "nameplate1", nil, nil, 6)   -- +1 in window: proven
            rt.castConfirmed = nil       -- isolate the CHANNEL evidence's lock
            clock.now = 108
            DTrash:OnChannelStop(nil, "nameplate1", nil, nil, nil, 6)
            assert.equals(222, rt.matchedNPCID)
            assert.is_true(rt.castConfirmed)             -- unambiguous two-phase evidence
        end)

        -- TrashCache consult at the Layer2 confirm (drift review B4): a
        -- level-disagreed mob's ONLY resolve path is FinishCast, so without
        -- this consult flicker recovery was unreachable for exactly the mobs
        -- D1 routes through Layer2 — and the confirming cast must credit
        -- INTO the adopted runtime, not the discarded virgin table.
        it("a Layer2 confirm consults the cache and credits into the restored runtime", function()
            local old = trackResolved("nameplate1")
            DTrash:MarkEngaged(old)
            old.castConfirmed = true
            old.anchors = { [10] = { mode = "success", anchorAt = 95,
                nextSeqIndex = 1, nextStartAt = 130 } }
            DTrash:OnNameplateRemoved(nil, "nameplate1")     -- flickers off; cached
            assert.is_true(old._cachePending)

            clock.now = 102
            DTrash:OnNameplateAdded(nil, "nameplate7")       -- returns on a new token
            local fresh = DTrash.tracked.nameplate7
            fresh.candidates = { { npcID = 111 } }           -- lone, level-disagreed
            DTrash:OnCastStart(nil, "nameplate7", nil, nil, 4)
            clock.now = 104                                  -- 2s cast = Slam
            DTrash:OnCastStop(nil, "nameplate7", nil, nil, 4)

            assert.equals(old, DTrash.tracked.nameplate7)    -- adopted the cached table
            assert.equals("nameplate7", old.unit)
            assert.is_nil(old._cachePending)
            assert.equals(0, #DTrash._trashPending)
            assert.is_true(old.castConfirmed)
            assert.equals(124, old.anchors[10].nextStartAt)  -- THIS cast credited into it (104 + cd 20)
            local last = scheduled[#scheduled]
            assert.equals("nameplate7", last.unit)
            assert.equals(124, last.nextStart)
        end)

        -- Layer2 flip hygiene (drift review A4): the FinishCast confirm site
        -- can change an existing identity — locked or cache-restored — and
        -- must run the same output reset as the Layer1 flip branch, or the
        -- old npcID's alerts/predictions/anchors orphan (surviving even plate
        -- removal, whose sweep is scoped to the NEW npcID) and enterSeeded
        -- blocks the new identity's seeding.
        it("a Layer2 identity flip cancels the old identity's output and re-credits", function()
            addTwin()
            local hidden = {}
            DTrash.HideUnitAlerts = function(_, unit, npcID) hidden[#hidden + 1] = { unit, npcID } end
            local rt = trackResolved("nameplate1")     -- wrongly resolved to 111
            DTrash:MarkEngaged(rt)                     -- seeds 111's spells
            rt.castConfirmed = true                    -- even a locked identity heals
            rt._alertTokens = { ["nameplate1:111:10"] = 3 }
            rt.predictions = { [10] = { nextStart = 115 } }
            rt.candidates = { { npcID = 111 }, { npcID = 222 } }
            castSixSeconds("nameplate1")               -- only 222's Rend fits 6s
            assert.equals(222, rt.matchedNPCID)
            assert.is_nil(rt.castConfirmed)            -- multi-pool flip: flippable
            assert.same({ { "nameplate1", 111 } }, hidden)  -- old output swept, scoped
            assert.is_nil(next(rt.predictions))
            assert.is_nil(rt.anchors[10])              -- old spellID anchors dropped
            assert.equals("success", rt.anchors[77].mode)   -- new identity credited
        end)
    end)
end)
