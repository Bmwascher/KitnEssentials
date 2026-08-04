-- Tier 2: DungeonTrash TrashCache flicker recovery (TrashCache.lua).
-- The cache is the most stateful piece of the trash engine: a removed plate's
-- runtime is held ~5s and adopted by a re-appearing plate of the same npcID,
-- with death / fresh-combat / expiry guards deciding between "bars keep
-- counting" and "tear down now". Every wrong branch is invisible in-game (a
-- bar that quietly vanished, or a corpse's countdown living on), so the state
-- machine is pinned here with a controllable clock and captured timers.
-- Frame/anchor behaviour (markers, alert re-key rendering) stays in-game-only.

local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("DungeonTrash — TrashCache flicker recovery", function()
    local DTrash, KE, clock, timers, world
    local hiddenUnits, rekeys, scheduled

    -- Fire every captured C_Timer whose due time has arrived.
    local function fireDue()
        local i = 1
        while i <= #timers do
            local t = timers[i]
            if t.at <= clock.now then
                table.remove(timers, i)
                t.fn()
            else
                i = i + 1
            end
        end
    end

    before_each(function()
        clock = { now = 100 }
        timers = {}
        world = { dead = {}, combat = {} }
        hiddenUnits, rekeys, scheduled = {}, {}, {}

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
        -- Captured as module locals at load; the SnapshotUnit timer path
        -- reaches them when a test fast-forwards the clock.
        _G.GetInstanceInfo = function() return "Dungeon", "party", 8, nil, nil, nil, nil, 1 end
        _G.IsInInstance = function() return true, "party" end

        local modules = helpers.installAddonShim()
        KE = { Print = function() end }  -- DEBUG_DTRASH dprints route here
        helpers.loadModule("Modules/DungeonTimers/Trash/DungeonTrash.lua", KE)
        helpers.loadModule("Modules/DungeonTimers/Trash/TrashCache.lua", KE)
        DTrash = modules["DungeonTrash"]

        -- Output-layer stubs: the cache only needs to CALL these correctly
        -- (including the npcID scope that isolates a recycled token's mobs).
        DTrash.HideUnitAlerts = function(_, unit, npcID)
            hiddenUnits[#hiddenUnits + 1] = { unit, npcID }
        end
        DTrash.HideNameplateMarker = function() end
        DTrash.UpdateNameplateMarker = function() end
        DTrash.EnsureMarkerTicker = function() end
        DTrash.RekeyUnitAlerts = function(_, oldU, newU, npcID)
            rekeys[#rekeys + 1] = { oldU, newU, npcID }
        end
        DTrash.ScheduleAlert = function(_, rt, npcID, spellID, _, nextStart)
            scheduled[#scheduled + 1] = { rt = rt, npcID = npcID, spellID = spellID, nextStart = nextStart }
        end

        -- Curated data for the re-schedule path (MobData reads KE.TrashData).
        DTrash.currentMapID = 1
        KE.TrashData = { [1] = { mobs = { [111] = { npcID = 111, name = "Mob",
            spells = { [10] = { first = 5, cd = { 20 } } } } } } }
    end)

    after_each(function()
        mock.reset()
        _G.UnitIsDead = nil
        _G.UnitAffectingCombat = nil
        _G.GetInstanceInfo = nil
        _G.IsInInstance = nil
        _G.KitnEssentials = nil
    end)

    -- Track a plate and hand-resolve its runtime (the resolve pipeline itself
    -- is covered by the inference specs; the cache only consumes its output).
    local function trackResolved(unit)
        DTrash:OnNameplateAdded(nil, unit)
        local rt = DTrash.tracked[unit]
        rt.matchedNPCID = 111
        rt.castConfirmed = true
        rt.anchors = { [10] = { mode = "success", anchorAt = clock.now - 5,
            nextSeqIndex = 1, nextStartAt = clock.now + 12 } }
        return rt
    end

    it("caches a resolved runtime on plate removal and keeps its alerts alive", function()
        local rt = trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        assert.is_nil(DTrash.tracked.nameplate1)
        assert.equals(1, #DTrash._trashPending)
        assert.equals(rt, DTrash._trashPending[1].rt)
        assert.same({}, hiddenUnits)  -- deferred cancel: NO immediate teardown
    end)

    it("does not cache an unresolved runtime — and sweeps nothing (it owns no alerts)", function()
        DTrash:OnNameplateAdded(nil, "nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        assert.equals(0, #DTrash._trashPending)
        -- An unresolved runtime never emitted alerts; an unscoped sweep here
        -- would cross-kill a cached mob's bars on a recycled token.
        assert.same({}, hiddenUnits)
    end)

    it("an UNTRACKED token's removal keeps the full-token orphan sweep", function()
        DTrash:OnNameplateRemoved(nil, "nameplate9")
        assert.same({ { "nameplate9" } }, hiddenUnits)
    end)

    it("restores the cached runtime TABLE into a virgin plate and re-arms outputs", function()
        local rt = trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")

        clock.now = clock.now + 2
        DTrash:OnNameplateAdded(nil, "nameplate7")
        local fresh = DTrash.tracked.nameplate7
        local adopted = DTrash:TryRestoreCachedRuntime(fresh, 111)

        assert.equals(rt, adopted)                       -- SAME table: closure guards survive
        assert.equals(rt, DTrash.tracked.nameplate7)
        assert.equals("nameplate7", rt.unit)
        assert.is_nil(rt._cachePending)                  -- restored: pending mark cleared
        assert.equals(0, #DTrash._trashPending)          -- row consumed
        assert.same({ { "nameplate1", "nameplate7", 111 } }, rekeys)
        assert.equals(1, #scheduled)                     -- re-armed from the anchor
        assert.equals(10, scheduled[1].spellID)
        assert.equals(rt.anchors[10].nextStartAt, scheduled[1].nextStart)
        -- expiry timer for the consumed row must now be a no-op
        clock.now = clock.now + 10
        fireDue()
        assert.same({}, hiddenUnits)
    end)

    it("expiry sweeps ONLY the cached mob's keys (npcID-scoped) and clears the pending mark", function()
        local rt = trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        assert.is_true(rt._cachePending)
        clock.now = clock.now + 5.5
        fireDue()
        assert.equals(0, #DTrash._trashPending)
        assert.same({ { "nameplate1", 111 } }, hiddenUnits)
        assert.is_nil(rt._cachePending)
    end)

    it("a unit seen dying is never cached (corpse bars tear down now)", function()
        trackResolved("nameplate1")
        world.dead.nameplate1 = true
        DTrash:OnUnitHealth(nil, "nameplate1")
        assert.is_nil(DTrash.tracked.nameplate1)
        assert.equals(0, #DTrash._trashPending)
        assert.same({ { "nameplate1", 111 } }, hiddenUnits)
    end)

    it("death also purges already-pending rows from that unit token", function()
        trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        assert.equals(1, #DTrash._trashPending)
        -- token recycles onto a new tracked mob which then dies
        trackResolved("nameplate1")
        world.dead.nameplate1 = true
        DTrash:OnUnitHealth(nil, "nameplate1")
        assert.equals(0, #DTrash._trashPending)
    end)

    -- Drop hygiene on the death purge (drift review B3): the purge was the ONE
    -- removal path that cleared neither the pending mark nor the row's alerts;
    -- the leaked mark is an affirmative liveness credential at the deferred-
    -- reveal gate (phantom bar + cast cue after the restore became impossible).
    it("death purge clears the pending mark and sweeps the purged row's alerts", function()
        local rtA = trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        assert.is_true(rtA._cachePending)
        -- token recycles onto a DIFFERENT-npcID mob which then dies
        DTrash:OnNameplateAdded(nil, "nameplate1")
        DTrash.tracked.nameplate1.matchedNPCID = 222
        world.dead.nameplate1 = true
        DTrash:OnUnitHealth(nil, "nameplate1")
        assert.equals(0, #DTrash._trashPending)
        assert.is_nil(rtA._cachePending)
        -- purge swept the cached mob's keys; the dying mob's own removal
        -- swept its own — and the dead row's expiry timer stays a no-op.
        assert.same({ { "nameplate1", 111 }, { "nameplate1", 222 } }, hiddenUnits)
        clock.now = clock.now + 6
        fireDue()
        assert.same({ { "nameplate1", 111 }, { "nameplate1", 222 } }, hiddenUnits)
    end)

    it("death purge skips the sweep when a live same-npcID twin owns the prefix", function()
        local rtA = trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        trackResolved("nameplate1")                      -- same-npcID successor
        world.dead.nameplate1 = true
        DTrash:OnUnitHealth(nil, "nameplate1")
        assert.is_nil(rtA._cachePending)
        -- exactly ONE sweep — the dying twin's own removal path; the purge's
        -- would have hit the same unit:npcID prefix a live mob owned.
        assert.same({ { "nameplate1", 111 } }, hiddenUnits)
    end)

    -- Ownership gate on the expiry sweep: the sweep key is
    -- a token+npcID prefix, so a recycled token hosting a LIVE same-npcID
    -- successor (clean start via the fresh-combat guard or a Layer2-first
    -- confirm) shares the cached row's exact prefix.
    it("expiry never sweeps a LIVE same-npcID successor's bars on the recycled token", function()
        local rtA = trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        clock.now = clock.now + 1
        local rtB = trackResolved("nameplate1")          -- clean-start twin, same npcID
        clock.now = clock.now + 4.5                      -- rtA's row expires
        fireDue()
        assert.equals(0, #DTrash._trashPending)
        assert.is_nil(rtA._cachePending)
        assert.same({}, hiddenUnits)                     -- the twin's live bars stay
        assert.equals(rtB, DTrash.tracked.nameplate1)
    end)

    it("expiry still sweeps when the recycled token hosts a DIFFERENT mob", function()
        trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        clock.now = clock.now + 1
        local rtB = trackResolved("nameplate1")
        rtB.matchedNPCID = 222
        clock.now = clock.now + 4.5
        fireDue()
        assert.same({ { "nameplate1", 111 } }, hiddenUnits)
    end)

    -- Eviction hygiene (drift review B6): the MAX_PENDING overflow drop now
    -- mirrors prune/expiry — without the sweep, a mass-despawn wipe left the
    -- evicted mobs' bars counting to zero and firing the "cast moment" cue.
    it("MAX_PENDING eviction sweeps the evicted row's alerts and clears its mark", function()
        local rt1 = trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        for i = 2, 25 do
            trackResolved("nameplate" .. i)
            DTrash:OnNameplateRemoved(nil, "nameplate" .. i)
        end
        assert.equals(24, #DTrash._trashPending)         -- capped
        assert.is_nil(rt1._cachePending)                 -- oldest evicted
        assert.same({ { "nameplate1", 111 } }, hiddenUnits)
    end)

    -- Same-token preference: a row sourced from the token
    -- being restored outranks newer rows from other tokens — the re-key then
    -- degenerates to a same-unit no-op and can never clobber a twin's live
    -- frames at the destination keys.
    it("restore prefers the row sourced from the same token over a newer twin's", function()
        local rtA = trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        clock.now = clock.now + 1
        local rtB = trackResolved("nameplate2")          -- same npcID, newer row
        DTrash:OnNameplateRemoved(nil, "nameplate2")

        DTrash:OnNameplateAdded(nil, "nameplate1")       -- the FIRST token returns
        local adopted = DTrash:TryRestoreCachedRuntime(DTrash.tracked.nameplate1, 111)
        assert.equals(rtA, adopted)
        assert.equals(1, #DTrash._trashPending)
        assert.equals(rtB, DTrash._trashPending[1].rt)
        assert.same({ { "nameplate1", "nameplate1", 111 } }, rekeys)
    end)

    it("fresh-combat guard: a plate that entered combat right after appearing starts clean", function()
        trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")

        clock.now = clock.now + 2
        DTrash:OnNameplateAdded(nil, "nameplate7")
        clock.now = clock.now + 0.5                      -- within NEW_COMBAT_BLOCK_WINDOW
        world.combat.nameplate7 = true
        DTrash:OnUnitFlags(nil, "nameplate7")

        local fresh = DTrash.tracked.nameplate7
        assert.is_nil(DTrash:TryRestoreCachedRuntime(fresh, 111))
        assert.equals(1, #DTrash._trashPending)          -- row NOT consumed
    end)

    it("a plate whose combat began well after appearing may still restore", function()
        trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")

        DTrash:OnNameplateAdded(nil, "nameplate7")
        clock.now = clock.now + 2                        -- outside the block window
        world.combat.nameplate7 = true
        DTrash:OnUnitFlags(nil, "nameplate7")

        local fresh = DTrash.tracked.nameplate7
        assert.is_not_nil(DTrash:TryRestoreCachedRuntime(fresh, 111))
    end)

    it("picks the NEWEST matching row and leaves the rest", function()
        local rtA = trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        clock.now = clock.now + 1
        local rtB = trackResolved("nameplate2")
        DTrash:OnNameplateRemoved(nil, "nameplate2")
        assert.equals(2, #DTrash._trashPending)

        DTrash:OnNameplateAdded(nil, "nameplate7")
        local adopted = DTrash:TryRestoreCachedRuntime(DTrash.tracked.nameplate7, 111)
        assert.equals(rtB, adopted)                      -- newest removedAt wins
        assert.equals(1, #DTrash._trashPending)
        assert.equals(rtA, DTrash._trashPending[1].rt)
    end)

    it("no matching npcID → no restore, runtime untouched", function()
        trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        DTrash:OnNameplateAdded(nil, "nameplate7")
        local fresh = DTrash.tracked.nameplate7
        assert.is_nil(DTrash:TryRestoreCachedRuntime(fresh, 222))
        assert.equals(fresh, DTrash.tracked.nameplate7)
    end)

    it("restore re-arm SKIPS a key already counting under the new token", function()
        local rt = trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        DTrash:OnNameplateAdded(nil, "nameplate7")
        -- the re-keyed frame is already live under the new-unit key
        DTrash.alerts = { ["nameplate7:111:10"] = {} }
        local adopted = DTrash:TryRestoreCachedRuntime(DTrash.tracked.nameplate7, 111)
        assert.equals(rt, adopted)
        -- re-arming it would ShowAlert-refresh the counting bar back to 100%
        assert.same({}, scheduled)
    end)

    it("ResetTrashCache wipes rows, meta, death marks and pending marks", function()
        local rt = trackResolved("nameplate1")
        DTrash:OnNameplateRemoved(nil, "nameplate1")
        assert.is_true(rt._cachePending)
        world.dead.nameplate2 = true
        DTrash._recentDeadByUnit.nameplate2 = clock.now
        DTrash:ResetTrashCache()
        assert.equals(0, #DTrash._trashPending)
        assert.is_nil(next(DTrash._plateMeta))
        assert.is_nil(next(DTrash._recentDeadByUnit))
        assert.is_nil(rt._cachePending)
    end)
end)

describe("DungeonTrash — deferred reveal pending-recovery gate (real ScheduleAlert)", function()
    local DTrash, KE, clock, timers, shown, dead

    local function fireDue()
        local i = 1
        while i <= #timers do
            local t = timers[i]
            if t.at <= clock.now then
                table.remove(timers, i)
                t.fn()
            else
                i = i + 1
            end
        end
    end

    before_each(function()
        clock = { now = 100 }
        timers = {}
        shown = {}
        dead = {}

        mock.install({
            GetTime = function() return clock.now end,
            C_Timer = {
                After = function(delay, fn)
                    timers[#timers + 1] = { at = clock.now + delay, fn = fn }
                end,
            },
        })
        _G.UnitIsDead = function(u) return dead[u] == true end
        _G.UnitAffectingCombat = function() return false end
        _G.GetInstanceInfo = function() return "Dungeon", "party", 8, nil, nil, nil, nil, 1 end
        _G.IsInInstance = function() return true, "party" end

        local modules = helpers.installAddonShim()
        KE = { Print = function() end }  -- DEBUG_DTRASH dprints route here
        -- Inference first (Trash.xml order): the cue's fingerprint filter
        -- and the sampler's pending-advance consult both dereference TI.
        helpers.loadModule("Modules/DungeonTimers/Trash/TrashInference.lua", KE)
        helpers.loadModule("Modules/DungeonTimers/Trash/DungeonTrash.lua", KE)
        helpers.loadModule("Modules/DungeonTimers/Trash/TrashOutput.lua", KE)
        helpers.loadModule("Modules/DungeonTimers/Trash/TrashCache.lua", KE)
        DTrash = modules["DungeonTrash"]

        -- Config accessors (TrashConfig.lua not loaded) + display sink.
        DTrash.GetSpellDisabled = function() return false end
        DTrash.PlayerSeesTrashSpell = function() return true end
        DTrash.GetSpellDisplay = function() return "bar" end
        DTrash.GetSpellRevealAt = function() return 5 end
        DTrash.GetSpellLabel = function() return "Spell" end
        DTrash.GetSpellEffectiveColor = function() return { 1, 1, 1 } end
        DTrash.GetSpellDecimalThreshold = function() return nil end
        DTrash.GetSpellSoundOnShow = function() return nil end
        DTrash.GetSpellSoundOnHide = function() return nil end
        DTrash.ShowAlert = function(_, key, duration)
            shown[#shown + 1] = { key = key, duration = duration }
        end
        DTrash.HideUnitAlerts = function() end
        DTrash.HideNameplateMarker = function() end

        DTrash.currentMapID = 1
        KE.TrashData = { [1] = { mobs = { [111] = { npcID = 111, name = "Mob",
            spells = { [10] = { first = 5, cd = { 20 } } } } } } }
    end)

    after_each(function()
        mock.reset()
        _G.UnitIsDead = nil
        _G.UnitAffectingCombat = nil
        _G.GetInstanceInfo = nil
        _G.IsInInstance = nil
        _G.KitnEssentials = nil
    end)

    local function armDeferred(unit)
        DTrash:OnNameplateAdded(nil, unit)
        local rt = DTrash.tracked[unit]
        rt.matchedNPCID = 111
        -- lead 12 > revealAt 5 → deferred reveal timer at now + 7
        DTrash:ScheduleAlert(rt, 111, 10, { name = "Spell" }, clock.now + 12)
        assert.same({}, shown)
        return rt
    end

    it("a reveal maturing INSIDE the flicker gap still fires (pending recovery)", function()
        armDeferred("nameplate1")
        clock.now = clock.now + 1
        DTrash:OnNameplateRemoved(nil, "nameplate1")     -- cached; _cachePending set
        clock.now = clock.now + 6                        -- reveal (t+7) matures mid-window
        fireDue()
        assert.equals(1, #shown)
        assert.equals("nameplate1:111:10", shown[1].key)
    end)

    it("after the cache row EXPIRES, the matured reveal stays dead", function()
        local rt = armDeferred("nameplate1")
        rt.anchors = nil                                 -- nothing to re-arm at restore/expiry
        DTrash:OnNameplateRemoved(nil, "nameplate1")     -- cached at t=100
        clock.now = clock.now + 5.5                      -- expiry (t+5) first...
        fireDue()                                        -- ...then the reveal (t+7)? not yet due
        clock.now = clock.now + 2
        fireDue()
        assert.same({}, shown)                           -- pending mark cleared at expiry
    end)

    -- Drift review C1: a deferred re-prediction must RETRACT a bar already
    -- showing under its key — the mob cast EARLIER than predicted, so the
    -- visible countdown is counting to an obsolete moment (stale zero + late
    -- "cast moment" cue, contradicting the corrected plate icon). HideAlert
    -- is silent; the stable-slot cache restores the stack position at reveal.
    it("a deferred re-prediction retracts the already-showing stale bar", function()
        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        rt.matchedNPCID = 111
        local frame = { _poolKey = "bar", key = "nameplate1:111:10", hidden = false }
        function frame:SetScript() end
        function frame:Hide() self.hidden = true end
        function frame:ClearAllPoints() end
        DTrash.alerts["nameplate1:111:10"] = frame           -- counting on screen
        DTrash:ScheduleAlert(rt, 111, 10, { name = "Spell" }, clock.now + 30)  -- re-predicted far out
        assert.is_nil(DTrash.alerts["nameplate1:111:10"])    -- retracted immediately
        assert.is_true(frame.hidden)
        assert.same({}, shown)
        clock.now = clock.now + 25                           -- reveal at lead - revealAt
        fireDue()
        assert.equals(1, #shown)                             -- re-revealed on the new schedule
        assert.equals("nameplate1:111:10", shown[1].key)
    end)

    -- Drift review C4: the extracted ReArmFromAnchors re-arms future anchors
    -- through the normal gates (GUI re-enable / role-churn recovery) and
    -- skips live keys so it can never snap a counting bar back to 100%.
    it("ReArmFromAnchors re-arms future anchors and skips live keys", function()
        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        rt.matchedNPCID = 111
        rt.anchors = { [10] = { mode = "success", anchorAt = 95,
            nextSeqIndex = 1, nextStartAt = clock.now + 3 } }
        local predicted = {}
        DTrash.SetNameplatePrediction = function(_, _, _, spellID)
            predicted[#predicted + 1] = spellID
        end
        DTrash:ReArmFromAnchors(rt, true)
        -- lead 3 <= revealAt 5 → the real ScheduleAlert shows immediately
        assert.equals(1, #shown)
        assert.equals("nameplate1:111:10", shown[1].key)
        assert.same({ 10 }, predicted)
        -- a live key is skipped entirely on a repeat pass
        DTrash.alerts["nameplate1:111:10"] = {}
        DTrash:ReArmFromAnchors(rt, true)
        assert.equals(1, #shown)
        assert.same({ 10 }, predicted)
    end)

    -- Observed cast-start cue: a third sound slot fired at the REAL cast bar.
    -- Deferred one cue window (0.12s) so the +0.10s sampler's start
    -- fingerprints can HARD-filter the
    -- candidates before the nearest-predicted-start scoring; once per cast
    -- instance; silent on a 0.05s tie.
    local function installCue()
        DTrash.db = { Enabled = true }
        KE.LSM = { Fetch = function(_, _, name) return "sound/" .. name end }
        local played = {}
        _G.PlaySoundFile = function(file) played[#played + 1] = file end
        -- The cue consults the EFFECTIVE resolver (override > curated default);
        -- resolution itself is pinned in dungeontrash_config_spec.
        DTrash.GetEffectiveSpellSoundOnCastStart = function(_, _, _, spellID)
            return "Ding" .. spellID
        end
        return played
    end
    local function fireCueWindow()
        clock.now = clock.now + 0.2   -- past sampler (0.10) + cue (0.12)
        fireDue()
    end

    it("the cast-start cue plays once per cast instance, one window after the start", function()
        local played = installCue()
        KE.TrashData[1].mobs[111].spells[10].castTime = 3

        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        rt.matchedNPCID = 111
        rt.anchors = { [10] = { nextStartAt = clock.now } }  -- predicted to start NOW
        DTrash:OnCastStart(nil, "nameplate1", nil, nil, 4)
        assert.same({}, played)                              -- deferred: not yet
        fireCueWindow()
        assert.same({ "sound/Ding10" }, played)
        DTrash:PlayObservedCastStartCue(rt, "cast")          -- re-entry, same instance
        fireCueWindow()
        assert.same({ "sound/Ding10" }, played)              -- once per activeCastSeq
        _G.PlaySoundFile = nil
    end)

    it("the cast-start cue stays silent when two predictions tie within 0.05s", function()
        local played = installCue()
        local spells = KE.TrashData[1].mobs[111].spells
        spells[10].castTime = 3
        spells[11] = { name = "Twin", castTime = 2, first = 5, cd = { 20 } }

        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        rt.matchedNPCID = 111
        rt.anchors = {
            [10] = { nextStartAt = clock.now },
            [11] = { nextStartAt = clock.now + 0.03 },       -- inside the tie window
        }
        DTrash:OnCastStart(nil, "nameplate1", nil, nil, 4)
        fireCueWindow()
        assert.same({}, played)                              -- ambiguous: no cue
        _G.PlaySoundFile = nil
    end)

    -- The Academy eagle bug (in game): Gust and Raging Screech are
    -- both cast-kind, and when the schedule drifts the nearest-prediction
    -- guess picks the wrong one. They separate by SAMPLED
    -- cast-start fingerprint (opposite targetClearOnCastStart curations) —
    -- a hard eligibility filter, not a tie-break.
    it("the sampled start fingerprint outranks schedule proximity (eagle shape)", function()
        local played = installCue()
        local spells = KE.TrashData[1].mobs[111].spells
        spells[10].castTime = 2.5
        spells[10].targetClearOnCastStart = true             -- Gust-shaped
        spells[11] = { name = "Screech", castTime = 3, first = 9, cd = { 23.3 },
            targetClearOnCastStart = false }

        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        rt.matchedNPCID = 111
        rt.anchors = {
            [10] = { nextStartAt = clock.now },              -- Gust predicted NOW (nearest)
            [11] = { nextStartAt = clock.now + 4 },          -- Screech predicted later
        }
        DTrash:OnCastStart(nil, "nameplate1", nil, nil, 4)
        fireCueWindow()
        -- No target-clear event in the ring at the start → the sampler reads
        -- FALSE → Gust (curates true) is excluded despite being nearest; the
        -- mob is really casting Screech and gets Screech's sound.
        assert.same({ "sound/Ding11" }, played)
        _G.PlaySoundFile = nil
    end)

    it("a kick inside the cue window kills the deferred cue", function()
        local played = installCue()
        KE.TrashData[1].mobs[111].spells[10].castTime = 3

        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        rt.matchedNPCID = 111
        rt.anchors = { [10] = { nextStartAt = clock.now } }
        DTrash:OnCastStart(nil, "nameplate1", nil, nil, 4)
        DTrash:OnCastInterrupted(nil, "nameplate1", nil, nil, nil, 4)  -- correlated: cast dies
        fireCueWindow()
        assert.same({}, played)                              -- nothing is casting
        _G.PlaySoundFile = nil
    end)

    -- Drift review B3: the death purge now clears _cachePending too, so a
    -- reveal that matures after its row was PURGED (token recycled, occupant
    -- died inside the window) stays dead instead of firing a phantom bar.
    it("a PURGED row's matured reveal stays dead (flag cleared at purge)", function()
        local rt = armDeferred("nameplate1")
        rt.anchors = nil
        clock.now = clock.now + 1
        DTrash:OnNameplateRemoved(nil, "nameplate1")     -- cached; _cachePending set
        assert.is_true(rt._cachePending)
        DTrash:OnNameplateAdded(nil, "nameplate1")       -- token recycles
        DTrash.tracked.nameplate1.matchedNPCID = 222
        dead.nameplate1 = true
        DTrash:OnUnitHealth(nil, "nameplate1")           -- purge strands rt's row
        assert.is_nil(rt._cachePending)
        clock.now = clock.now + 7                        -- reveal (t=107) matures
        fireDue()
        assert.same({}, shown)                           -- no phantom reveal
    end)
end)

describe("DungeonTrash — RekeyUnitAlerts destination-key collision (real TrashOutput)", function()
    local DTrash, KE

    before_each(function()
        mock.install({ GetTime = function() return 100 end })
        local modules = helpers.installAddonShim()
        KE = { Print = function() end }  -- DEBUG_DTRASH dprints route here
        helpers.loadModule("Modules/DungeonTimers/Trash/DungeonTrash.lua", KE)
        helpers.loadModule("Modules/DungeonTimers/Trash/TrashOutput.lua", KE)
        DTrash = modules["DungeonTrash"]
    end)

    after_each(function()
        mock.reset()
        _G.KitnEssentials = nil
    end)

    -- Registry-level fake: just enough surface for HideAlert's retire path.
    -- Rendering behavior (layout, OnUpdate) stays in-game-only.
    local function fakeKit(mode, key)
        local f = { _poolKey = mode, key = key, hidden = false }
        function f:SetScript() end
        function f:Hide() self.hidden = true end
        function f:ClearAllPoints() end
        function f:IsShown() return not self.hidden end
        function f:GetHeight() return 20 end
        return f
    end

    -- Drift review B1: two same-npcID twins can legally own the identical
    -- key once a recycled token is involved. The blind overwrite orphaned the
    -- occupant (Shown, OnUpdate attached, registry-unreachable — per-frame
    -- hide-sound loop until /reload); the move must retire it instead.
    it("hides and pools the destination occupant instead of orphaning it", function()
        local occupant = fakeKit("bar", "nameplate5:111:10")  -- live twin's counting bar
        local moving   = fakeKit("bar", "nameplate7:111:10")  -- restored mob's frame
        DTrash.alerts["nameplate5:111:10"] = occupant
        DTrash.alerts["nameplate7:111:10"] = moving
        DTrash._sortByKey["nameplate5:111:10"] = 1
        DTrash._sortByKey["nameplate7:111:10"] = 2

        DTrash:RekeyUnitAlerts("nameplate7", "nameplate5", 111)

        assert.equals(moving, DTrash.alerts["nameplate5:111:10"])
        assert.equals("nameplate5:111:10", moving.key)
        assert.is_nil(DTrash.alerts["nameplate7:111:10"])
        assert.is_true(occupant.hidden)                  -- retired, not orphaned
        assert.is_true(occupant._pooled)                 -- and returned to the pool
    end)

    it("a move with no destination occupant stays a plain re-key", function()
        local moving = fakeKit("bar", "nameplate7:111:10")
        DTrash.alerts["nameplate7:111:10"] = moving
        DTrash._sortByKey["nameplate7:111:10"] = 2

        DTrash:RekeyUnitAlerts("nameplate7", "nameplate5", 111)

        assert.equals(moving, DTrash.alerts["nameplate5:111:10"])
        assert.is_false(moving.hidden)
        assert.equals(2, DTrash._sortByKey["nameplate5:111:10"])
    end)
end)
