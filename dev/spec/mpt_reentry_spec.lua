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
        -- must survive (upstream parity: reset requires being OUTSIDE).
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
        -- Regression (Codex, 2026-07-14): the cache used to live on MPT.db, i.e.
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
