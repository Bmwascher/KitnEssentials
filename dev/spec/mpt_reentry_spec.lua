-- Lifecycle spec for MythicPlusTimer's mid-key exit/re-entry behavior:
-- CheckForActiveRun's reset gating and the recovery-cache ownership boundaries.
--
-- The split cache lives in db.GLOBAL (KE.db.global.MPTActiveRunSplits), not on
-- the profile: an AceDB profile switch mid-run rebinds MPT.db and would hand the
-- live run another profile's stale splits. The death log cache is still profile-
-- scoped (display-only; it cannot poison the improve-only PB store).
--
-- Loads the REAL Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua headlessly
-- (fresh per test — file-local state resets with the reload). Collaborator
-- methods that live in sibling files or Ace mixins (tracker visibility, overlay,
-- run-event registration, splits) are stubbed AFTER load: this spec asserts the
-- lifecycle's state transitions and cache routing, never those seams' behavior.
-- The caches are seeded as raw db keys deliberately — they are internal
-- persistence the lifecycle code itself owns; no public accessor exists.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("MPT run lifecycle: mid-key exit / re-entry", function()
    local MPT, KE
    local activeMapID          -- what C_ChallengeMode.GetActiveChallengeMapID returns
    local instanceInfo         -- {name, type, difficulty} for GetInstanceInfo
    local startRunCalls

    local function setInstance(kind)
        if kind == "challenge" then
            instanceInfo = { "Some Dungeon", "party", 8 }
        else
            instanceInfo = { "Stormwind", "none", 0 }
        end
    end

    before_each(function()
        -- Inert C_Timer: deferred re-checks/renders must not fire mid-spec.
        mock.install({
            C_Timer = {
                After = function() end,
                NewTicker = function() return { Cancel = function() end } end,
            },
        })
        local modules = helpers.installAddonShim()

        activeMapID = nil
        setInstance("challenge")
        startRunCalls = 0

        -- File-scope locals captured at load: C_ChallengeMode must exist BEFORE
        -- loadModule. GetInstanceInfo is a plain global lookup at call time.
        _G.C_ChallengeMode = {
            GetActiveChallengeMapID = function() return activeMapID end,
        }
        _G.GetInstanceInfo = function()
            return instanceInfo[1], instanceInfo[2], instanceInfo[3]
        end

        KE = helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua",
            { Print = function() end, db = { global = {}, profile = {} } })
        MPT = modules["MythicPlusTimer"]
        assert(MPT and MPT.CheckForActiveRun, "real MythicPlusTimer.lua did not load")

        -- Collaborator seams (sibling files / Ace mixins) — not under test.
        MPT.ApplyTrackerVisibility = function() end
        MPT.SetOverlayActive = function() end
        MPT.RegisterRunEvents = function() end
        MPT.UnregisterRunEvents = function() end
        MPT.NotifyRefresh = function() end
        MPT.StartRun = function() startRunCalls = startRunCalls + 1 end
        MPT.MigrateLegacyOverlayDB = function() end  -- lives in the Overlay file

        -- Minimal db with live recovery caches, as a mid-key run would have.
        MPT.db = {
            Enabled = true,
            _activeRunDeaths = { mapID = 375, log = { { t = 142, name = "Healer" } } },
        }
        KE.db.global.MPTActiveRunSplits = { key = "375:12", [1] = 180 }
    end)

    local function seedActiveRun()
        local run = MPT.run
        run.active = true
        run.completed = false
        run.mapID = 375
        run.level = 12
        run.maxTime = 1980
        run.elapsed = 900
    end

    it("keeps an active run when the map ID flaps while still inside", function()
        -- Re-entry PEW window: GetActiveChallengeMapID reads nil for a moment
        -- while the player is standing in the challenge instance. The run
        -- must survive: a reset requires being OUTSIDE.
        seedActiveRun()
        activeMapID = nil
        setInstance("challenge")
        MPT:CheckForActiveRun()
        assert.is_true(MPT.run.active)
        assert.equals(375, MPT.run.mapID)
        assert.is_table(KE.db.global.MPTActiveRunSplits)
        assert.is_table(MPT.db._activeRunDeaths)
    end)

    it("resets a walked-out run but keeps the recovery caches", function()
        -- Genuine walk-out: outside the instance, run still live server-side.
        -- Run state resets (HUD hides), but the caches survive so re-entry
        -- restores splits + death log through the /reload-recovery path.
        seedActiveRun()
        activeMapID = nil
        setInstance("open-world")
        MPT:CheckForActiveRun()
        assert.is_false(MPT.run.active)
        assert.is_table(KE.db.global.MPTActiveRunSplits)
        assert.is_table(MPT.db._activeRunDeaths)
    end)

    it("keeps the caches when WORLD_STATE_TIMER_STOP trails the walk-out reset", function()
        -- Event-order hazard: the timer-stop event can arrive after the PEW
        -- reset already ran (run inert). It must not wipe what the walk-out
        -- path deliberately spared.
        seedActiveRun()
        activeMapID = nil
        setInstance("open-world")
        MPT:CheckForActiveRun()          -- walk-out reset (keeps caches)
        MPT:WORLD_STATE_TIMER_STOP()     -- trailing stop event
        assert.is_table(KE.db.global.MPTActiveRunSplits)
        assert.is_table(MPT.db._activeRunDeaths)
    end)

    it("wipes the caches at CHALLENGE_MODE_START (genuinely new key)", function()
        -- The new-key event owns the staleness wipe: a cache left over from a
        -- walked-out or logged-out run must never leak into a fresh key.
        MPT:CHALLENGE_MODE_START()
        assert.is_nil(KE.db.global.MPTActiveRunSplits)
        assert.is_nil(MPT.db._activeRunDeaths)
        assert.equals(1, startRunCalls)
    end)

    it("still wipes the caches on CHALLENGE_MODE_RESET", function()
        seedActiveRun()
        MPT:CHALLENGE_MODE_RESET()
        assert.is_false(MPT.run.active)
        assert.is_nil(KE.db.global.MPTActiveRunSplits)
        assert.is_nil(MPT.db._activeRunDeaths)
    end)

    it("survives a profile switch — the split cache is global, not profile-scoped", function()
        -- Regression: the cache used to live on MPT.db, i.e.
        -- KE.db.profile.MythicPlusTimer. ProfileManager:RefreshAllModules calls
        -- UpdateDB on every module, and UpdateDB REBINDS self.db — so a mid-run
        -- profile switch handed the live run another profile's stale splits. Those
        -- times PREDATE the current run clock, so they read as plausible and no
        -- downstream sanity check can reject them; CommitSplits would then persist
        -- one as a personal best, and improve-only makes a too-low value immortal.
        seedActiveRun()
        MPT:UpdateDB()  -- exactly what a profile switch does

        assert.is_nil(MPT.db._activeRunSplits)                    -- not on the profile at all
        assert.is_table(KE.db.global.MPTActiveRunSplits)          -- untouched by the rebind
        assert.equals("375:12", KE.db.global.MPTActiveRunSplits.key)

        -- ...and the module still OWNS the surviving cache: its own wipe path has
        -- to reach it. (Pre-fix this is where it breaks: the wipe nils the key on
        -- the freshly-rebound PROFILE table, and the run's real cache lives on.)
        MPT:CHALLENGE_MODE_RESET()
        assert.is_nil(KE.db.global.MPTActiveRunSplits)
    end)

    it("leaves a completed run alone during the inside-instance fanfare window", function()
        -- Post-completion, GetActiveChallengeMapID flips nil while the player
        -- is still inside: the frozen summary must persist until zone-out.
        local run = MPT.run
        run.active = false
        run.completed = true
        run.mapID = 375
        activeMapID = nil
        setInstance("challenge")
        MPT:CheckForActiveRun()
        assert.is_true(MPT.run.completed)
    end)
end)

describe("MPT:UpdateForces — forces-cap clock rule", function()
    -- Regression cover for the back-dated forces cap: the 100% stamp must use
    -- the LIVE world clock while the run is live (run.elapsed is refreshed only
    -- once per whole second, so it lags the criteria event by up to ~1s and the
    -- improve-only best.forces commit would bake the skew in), and must fall
    -- back to run.elapsed once the run is completed (the world clock goes stale
    -- post-depletion — the "99:99" class). Same load pattern as the lifecycle
    -- describe above: C_Scenario/C_ScenarioInfo/GetWorldElapsedTime are
    -- file-scope captures, so their mocks must exist BEFORE loadModule.
    local MPT, run, criteria, worldElapsed

    before_each(function()
        mock.install({
            C_Timer = {
                After = function() end,
                NewTicker = function() return { Cancel = function() end } end,
            },
        })
        local modules = helpers.installAddonShim()

        criteria = {}
        worldElapsed = 0
        _G.C_ChallengeMode = { GetActiveChallengeMapID = function() return nil end }
        _G.GetInstanceInfo = function() return "Some Dungeon", "party", 8 end
        _G.C_Scenario = { GetStepInfo = function() return nil, nil, #criteria end }
        _G.C_ScenarioInfo = { GetCriteriaInfo = function(i) return criteria[i] end }
        _G.GetWorldElapsedTime = function() return 0, worldElapsed end

        helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua",
            { Print = function() end, db = { global = {}, profile = {} } })
        MPT = modules["MythicPlusTimer"]
        assert(MPT and MPT.UpdateForces, "real MythicPlusTimer.lua did not load")

        run = MPT.run
        run.forces = {}
    end)

    local function capCriterion(infoElapsed)
        return { isWeightedProgress = true, completed = true, elapsed = infoElapsed,
                 quantityString = "100%", totalQuantity = 100 }
    end

    it("back-dates the cap from the live clock while the run is live", function()
        run.completed = false
        run.elapsed = 100          -- lagging once-per-second tick clock
        worldElapsed = 101.4       -- fresh live clock at the criteria event
        criteria[1] = capCriterion(0.4)
        MPT:UpdateForces()
        assert.is_true(run.forces.completed)
        assert.near(101.0, run.forces.clearTime, 1e-9)   -- live - info.elapsed, not run.elapsed
    end)

    it("stamps the cap exactly once (sticky completion)", function()
        run.completed = false
        run.elapsed = 100
        worldElapsed = 101.4
        criteria[1] = capCriterion(0.4)
        MPT:UpdateForces()
        worldElapsed = 200         -- a later teardown re-read must not restamp
        MPT:UpdateForces()
        assert.near(101.0, run.forces.clearTime, 1e-9)
    end)

    it("uses authoritative run.elapsed once the run is completed", function()
        run.completed = true
        run.elapsed = 1500         -- GetChallengeCompletionInfo's final time
        worldElapsed = 42          -- stale/garbage world clock post-depletion
        criteria[1] = capCriterion(2)
        MPT:UpdateForces()
        assert.near(1498, run.forces.clearTime, 1e-9)
    end)

    it("falls back to run.elapsed when the live clock reads negative", function()
        run.completed = false
        run.elapsed = 100
        worldElapsed = -1          -- guarded: live and live >= 0
        criteria[1] = capCriterion(0.4)
        MPT:UpdateForces()
        assert.near(99.6, run.forces.clearTime, 1e-9)
    end)
end)
