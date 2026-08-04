-- Pure unit test for MPT.RepairCountSplitsIn (the busted-testable core of
-- RepairCountSplits). Same loading route as mpt_resolvepb_spec.lua.
--
-- Regression cover for the Pit of Saron "Quarry Camps" bug: pre-fix builds
-- stamped count objectives at the FIRST increment, so the store held 81s "PBs"
-- against real ~21min clears. CommitSplits is improve-only, so those could never
-- be beaten and the row's delta was permanently wrong.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local MPT, KE
setup(function()
    mock.install()
    local modules = helpers.installAddonShim()
    -- Seed KE.db: the live-store paths (GetStore) read KE.db.global, unlike the
    -- pure resolver spec which never touches it.
    KE = helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer_Splits.lua",
        { db = { global = {} } })
    MPT = modules["MythicPlusTimer"]
    assert(MPT and MPT.RepairCountSplitsIn, "Splits file did not expose RepairCountSplitsIn")
end)

describe("MPT.RepairCountSplitsIn", function()
    local store
    before_each(function()
        -- Pit of Saron (556). Criterion 3 is the Quarry Camps count objective.
        -- Levels 22/23 carry poisoned first-camp-tag splits; level 18 carries a
        -- legitimate post-fix one. Map 402 is a different dungeon entirely.
        store = {
            ["556:22"] = { best = { [1] = 613, [2] = 996, [3] = 71,   [4] = 1453, overall = 1452 } },
            ["556:23"] = { best = { [1] = 640, [2] = 1010, [3] = 81,  [4] = 1500, overall = 1499 } },
            ["556:18"] = { best = { [1] = 613, [2] = 996, [3] = 1014, [4] = 1453, overall = 1452 } },
            ["402:15"] = { best = { [1] = 970, [2] = 624, [3] = 233,  [4] = 1319, overall = 1319 } },
        }
    end)

    it("drops the count criterion across EVERY level key of the map", function()
        -- The whole point: ResolvePBFrom falls back across levels within a
        -- dungeon, so repairing only the run's exact key would leave the
        -- poisoned split reachable from a run at another level.
        MPT.RepairCountSplitsIn(store, 556, { 3 })
        assert.is_nil(store["556:22"].best[3])
        assert.is_nil(store["556:23"].best[3])
        assert.is_nil(store["556:18"].best[3])
    end)

    it("leaves non-count criteria and overall untouched", function()
        MPT.RepairCountSplitsIn(store, 556, { 3 })
        assert.are.equal(613, store["556:22"].best[1])
        assert.are.equal(996, store["556:22"].best[2])
        assert.are.equal(1453, store["556:22"].best[4])
        assert.are.equal(1452, store["556:22"].best.overall)
    end)

    it("never touches another dungeon's splits", function()
        MPT.RepairCountSplitsIn(store, 556, { 3 })
        assert.are.equal(233, store["402:15"].best[3])
        assert.is_nil(store["402:15"].countRepaired)
    end)

    it("does not match a map whose id merely prefixes the target", function()
        store["5566:10"] = { best = { [3] = 500 } }
        MPT.RepairCountSplitsIn(store, 556, { 3 })
        assert.are.equal(500, store["5566:10"].best[3])
    end)

    it("is idempotent — a repaired entry is never purged twice", function()
        local first = MPT.RepairCountSplitsIn(store, 556, { 3 })
        assert.are.equal(3, first)  -- 556:22, 556:23, 556:18

        -- A fresh (correct) split written after the repair must survive a
        -- second pass — otherwise every subsequent run would wipe the new PB.
        store["556:23"].best[3] = 1257
        local second = MPT.RepairCountSplitsIn(store, 556, { 3 })
        assert.are.equal(0, second)
        assert.are.equal(1257, store["556:23"].best[3])
    end)

    it("handles multiple count criteria in one map", function()
        store["556:23"].best[4] = 1500
        MPT.RepairCountSplitsIn(store, 556, { 3, 4 })
        assert.is_nil(store["556:23"].best[3])
        assert.is_nil(store["556:23"].best[4])
        assert.are.equal(640, store["556:23"].best[1])
    end)

    it("no-ops safely on empty or missing input", function()
        assert.are.equal(0, MPT.RepairCountSplitsIn(nil, 556, { 3 }))
        assert.are.equal(0, MPT.RepairCountSplitsIn(store, nil, { 3 }))
        assert.are.equal(0, MPT.RepairCountSplitsIn(store, 556, {}))
        assert.are.equal(0, MPT.RepairCountSplitsIn(store, 556, nil))
        assert.are.equal(71, store["556:22"].best[3])  -- nothing purged
    end)

    it("tolerates an entry with no best table", function()
        store["556:30"] = { lastSeenSeason = 1 }
        assert.has_no.errors(function()
            MPT.RepairCountSplitsIn(store, 556, { 3 })
        end)
        assert.is_true(store["556:30"].countRepaired)
    end)
end)

describe("MPT.CacheBelongsToRun", function()
    -- The in-flight split cache is identity-stamped "mapID:level" so it can only
    -- restore into the run that wrote it. But a reload-recovery StartRun races
    -- GetActiveKeystoneInfo, so run.level reads 0 until RepairRunInfo fixes it —
    -- and an exact compare misses in that window. A boss criterion survives the
    -- miss (it back-dates off info.elapsed); a COUNT criterion would be
    -- re-stamped at the RELOAD time and CommitSplits would persist that.

    -- All positive cases carry a char stamp: ownership is REQUIRED
    -- (ownerless caches are rejected outright — see the last case).
    local ME = "Player-1234-000A"

    it("matches the exact key", function()
        assert.is_true(MPT.CacheBelongsToRun({ key = "556:23", char = ME }, 556, 23, ME))
    end)

    it("matches on mapID alone while the level is still unknown", function()
        assert.is_true(MPT.CacheBelongsToRun({ key = "556:23", char = ME }, 556, 0, ME))
        assert.is_true(MPT.CacheBelongsToRun({ key = "556:23", char = ME }, 556, nil, ME))
    end)

    it("does NOT relax across maps, even at level 0", function()
        assert.is_false(MPT.CacheBelongsToRun({ key = "402:23", char = ME }, 556, 0, ME))
        assert.is_false(MPT.CacheBelongsToRun({ key = "5566:23", char = ME }, 556, 0, ME))
    end)

    it("does NOT relax once the level is known", function()
        -- A known-level mismatch is a genuinely different run: stay strict.
        assert.is_false(MPT.CacheBelongsToRun({ key = "556:23", char = ME }, 556, 24, ME))
    end)

    it("rejects a missing, keyless, or mapless probe", function()
        assert.is_false(MPT.CacheBelongsToRun(nil, 556, 23, ME))
        assert.is_false(MPT.CacheBelongsToRun({}, 556, 23, ME))
        assert.is_false(MPT.CacheBelongsToRun({ key = "556:23", char = ME }, nil, 23, ME))
    end)

    it("accepts the owning character and rejects a foreign one at the exact key", function()
        -- The cache is account-GLOBAL and survives a mid-key logout, so the
        -- same map+level on another character is a collision, not a recovery
        -- — no API race required (review finding).
        local cache = { key = "556:23", char = "Player-1234-000A" }
        assert.is_true(MPT.CacheBelongsToRun(cache, 556, 23, "Player-1234-000A"))
        assert.is_false(MPT.CacheBelongsToRun(cache, 556, 23, "Player-1234-000B"))
    end)

    it("rejects a foreign character in the level-0 window too", function()
        -- The relaxed map-only match must never widen ACROSS characters:
        -- a foreign cache's splits predate the new run's clock, so the
        -- caller's provenance bound cannot catch them.
        local cache = { key = "556:23", char = "Player-1234-000A" }
        assert.is_true(MPT.CacheBelongsToRun(cache, 556, 0, "Player-1234-000A"))
        assert.is_false(MPT.CacheBelongsToRun(cache, 556, 0, "Player-1234-000B"))
    end)

    it("rejects a cache with no character stamp", function()
        -- Ownerless caches are untrusted by definition (review):
        -- every released writer stamps char at create, so an unstamped cache
        -- is a pre-stamp artifact whose owner cannot be recovered. Adopting
        -- one would launder a possibly-foreign cache into this character's
        -- improve-only PB store; rejection displaces it at the next create.
        assert.is_false(MPT.CacheBelongsToRun({ key = "556:23" }, 556, 23, "Player-1234-000A"))
        assert.is_false(MPT.CacheBelongsToRun({ key = "556:23" }, 556, 0, "Player-1234-000A"))
    end)
end)

-- Lifecycle cover, driving the real UpdateSplits/CommitSplits against the live
-- store. The pure-core tests above pass even when the repair is never REACHED —
-- both known defects (a session-sticky run flag, and CommitSplits creating an
-- unstamped entry) lived in the wiring, not in the core.
describe("count-split repair lifecycle", function()
    local store

    local function boss(i)  return { criteriaIndex = i, totalQuantity = 1 } end
    local function count(i) return { criteriaIndex = i, totalQuantity = 6 } end

    local function armRun(mapID, level, objectives)
        MPT.run = {
            mapID = mapID, level = level, objectives = objectives,
            forces = {}, elapsed = 0,
        }
        return MPT.run
    end

    before_each(function()
        KE.db.global.MythicPlusTimerSplits = {
            ["556:22"] = { best = { [1] = 613, [2] = 996,  [3] = 71,  [4] = 1453, overall = 1452 } },
            ["556:23"] = { best = { [1] = 640, [2] = 1010, [3] = 81,  [4] = 1500, overall = 1499 } },
            ["402:15"] = { best = { [1] = 970, [2] = 624,  [3] = 233, [4] = 1319, overall = 1319 } },
        }
        store = KE.db.global.MythicPlusTimerSplits
    end)

    it("still repairs after an earlier count-free run in the same session", function()
        -- MPT.run is ONE long-lived table whose fields StartRun/ResetRun reset
        -- individually, so a run-scoped "already repaired" flag survives into
        -- the next run: the first dungeon of a session would latch it and every
        -- dungeon after would skip the repair. There must be no such flag.
        armRun(402, 15, { boss(1), boss(2), boss(3), boss(4) })  -- no count criterion
        MPT:UpdateSplits()

        armRun(556, 23, { boss(1), boss(2), count(3), boss(4) })
        MPT:UpdateSplits()

        assert.is_nil(store["556:23"].best[3])
        assert.is_nil(store["556:22"].best[3])
    end)

    it("clears the poisoned pbTime so no bogus delta can render", function()
        local objs = { boss(1), boss(2), count(3), boss(4) }
        armRun(556, 23, objs)
        MPT:UpdateSplits()

        assert.is_nil(objs[3].pbTime)          -- the 81s poison never reaches the HUD
        assert.are.equal(640, objs[1].pbTime)  -- real boss PBs survive
    end)

    it("keeps a split written into a NEW level entry across the next run's sweep", function()
        -- CommitSplits creating `{ best = {} }` without the countRepaired stamp
        -- let the following run's sweep delete the correct count PB it had just
        -- written — a new level key could never hold a count PB at all.
        local objs = { boss(1), boss(2), count(3), boss(4) }
        objs[3].completed, objs[3].clearTime = true, 1257

        local run = armRun(556, 24, objs)  -- 556:24 does not exist yet
        run.elapsed = 1800
        MPT:UpdateSplits()
        MPT:CommitSplits()
        assert.are.equal(1257, store["556:24"].best[3])

        armRun(556, 23, { boss(1), boss(2), count(3), boss(4) })
        MPT:UpdateSplits()
        assert.are.equal(1257, store["556:24"].best[3])
    end)

    it("retries when a count criterion is discovered late", function()
        -- GetCriteriaInfo can transiently return nil, so a run can tick with
        -- only some criteria known. That must not latch the run as repaired.
        armRun(556, 23, { boss(1), boss(2) })
        MPT:UpdateSplits()
        assert.are.equal(81, store["556:23"].best[3])  -- not yet discovered, nothing purged

        MPT.run.objectives = { boss(1), boss(2), count(3), boss(4) }
        MPT:UpdateSplits()
        assert.is_nil(store["556:23"].best[3])
    end)
end)
