-- Pure unit test for MPT.RepairCountSplitsIn (the busted-testable core of
-- RepairCountSplits). Same loading route as mpt_resolvepb_spec.lua.
--
-- Regression cover for the Pit of Saron "Quarry Camps" bug: pre-fix builds
-- stamped count objectives at the FIRST increment, so the store held 81s "PBs"
-- against real ~21min clears. CommitSplits is improve-only, so those could never
-- be beaten and the row's delta was permanently wrong.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local MPT
setup(function()
    mock.install()
    local modules = helpers.installAddonShim()
    helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer_Splits.lua")
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
