-- Pure unit test for MPT.ResolvePBFrom (the busted-testable core of ResolvePB).
-- Runs under the repo's busted harness (see dev/README.md for setup). If
-- busted is unavailable, run the equivalent /run self-check macro noted at
-- the bottom of this file in-game.
--
-- Loads the REAL MythicPlusTimer_Splits.lua via helpers.loadModule, which
-- raises on loadfile failure and runs the chunk UNPROTECTED — a load error
-- fails the suite loudly instead of leaving MPT.ResolvePBFrom nil (the old
-- loadfile+pcall route swallowed both).
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local MPT
setup(function()
    mock.install()
    local modules = helpers.installAddonShim()
    helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer_Splits.lua")
    MPT = modules["MythicPlusTimer"]
    assert(MPT and MPT.ResolvePBFrom, "Splits file did not expose ResolvePBFrom")
end)

describe("MPT.ResolvePBFrom", function()
    local store
    before_each(function()
        store = {
            ["2648:10"] = { best = { [1] = 120, [2] = 300, overall = 1500 } },
            ["2648:12"] = { best = { [1] = 110, [2] = 280, overall = 1400 } },
            ["2649:15"] = { best = { [1] = 200, overall = 2000 } },
        }
    end)

    it("returns the exact level record when present", function()
        local rec = MPT.ResolvePBFrom(store, 2648, 12, nil)
        assert.are.equal(1400, rec.overall)
        assert.are.equal(110, rec[1])
    end)

    it("falls back to nearest level in the same dungeon", function()
        local rec = MPT.ResolvePBFrom(store, 2648, 13, nil)  -- no 2648:13; nearest is :12
        assert.is_truthy(rec)
        assert.are.equal(1400, rec.overall)
    end)

    it("breaks an equidistant tie toward the lower level deterministically", function()
        local rec = MPT.ResolvePBFrom(store, 2648, 11, nil)  -- :10 and :12 both delta 1
        assert.is_truthy(rec)
        assert.are.equal(1500, rec.overall)                  -- lower level (:10) wins
    end)

    it("returns nil for an unknown dungeon", function()
        assert.is_nil(MPT.ResolvePBFrom(store, 9999, 10, nil))
    end)

    it("returns nil for a nil store or nil mapID", function()
        assert.is_nil(MPT.ResolvePBFrom(nil, 2648, 10, nil))
        assert.is_nil(MPT.ResolvePBFrom(store, nil, 10, nil))
    end)

    it("returns the source level alongside the record", function()
        local rec, src = MPT.ResolvePBFrom(store, 2648, 12, nil)
        assert.are.equal(1400, rec.overall)
        assert.are.equal(12, src)                            -- exact hit: source == requested
        local rec2, src2 = MPT.ResolvePBFrom(store, 2648, 13, nil)
        assert.are.equal(1400, rec2.overall)
        assert.are.equal(12, src2)                           -- fallback: source is the record's level
    end)

    describe("PBFallbackMode", function()
        it("CLOSEST_LOWER prefers the level below even when a higher one is nearer", function()
            local s = { ["2648:8"]  = { best = { overall = 1000 } },
                        ["2648:13"] = { best = { overall = 1300 } } }
            local rec, src = MPT.ResolvePBFrom(s, 2648, 12, nil, "CLOSEST_LOWER")
            assert.are.equal(1000, rec.overall)              -- 8, not the nearer 13
            assert.are.equal(8, src)
        end)

        it("CLOSEST_LOWER falls back to the nearest higher when nothing is below", function()
            local rec, src = MPT.ResolvePBFrom(store, 2648, 9, nil, "CLOSEST_LOWER")
            assert.are.equal(1500, rec.overall)
            assert.are.equal(10, src)
        end)

        it("CLOSEST_HIGHER prefers the level above", function()
            local rec, src = MPT.ResolvePBFrom(store, 2648, 11, nil, "CLOSEST_HIGHER")
            assert.are.equal(1400, rec.overall)
            assert.are.equal(12, src)
        end)

        it("CLOSEST_HIGHER falls back to the nearest lower when nothing is above", function()
            local rec, src = MPT.ResolvePBFrom(store, 2648, 13, nil, "CLOSEST_HIGHER")
            assert.are.equal(1400, rec.overall)
            assert.are.equal(12, src)
        end)

        it("HIGHEST and LOWEST pick the extremes", function()
            local rec, src = MPT.ResolvePBFrom(store, 2648, 5, nil, "HIGHEST")
            assert.are.equal(1400, rec.overall)
            assert.are.equal(12, src)
            local rec2, src2 = MPT.ResolvePBFrom(store, 2648, 20, nil, "LOWEST")
            assert.are.equal(1500, rec2.overall)
            assert.are.equal(10, src2)
        end)

        it("OFF never falls back but still resolves an exact record", function()
            assert.is_nil(MPT.ResolvePBFrom(store, 2648, 11, nil, "OFF"))
            local rec = MPT.ResolvePBFrom(store, 2648, 12, nil, "OFF")
            assert.are.equal(1400, rec.overall)
        end)
    end)
end)

describe("loader failure is LOUD (regression guard for the old pcall swallow)", function()
    it("raises on a missing file instead of silently continuing", function()
        local ok, err = pcall(helpers.loadModule, "Modules/DoesNotExist/Nope.lua")
        assert.is_false(ok)
        assert.matches("loadfile failed", tostring(err))
    end)
end)

-- In-game self-check macro (fallback if busted is unavailable):
-- /run local M=KitnEssentials:GetModule("MythicPlusTimer"); local s={["2648:12"]={best={overall=1400}}}; print(M.ResolvePBFrom(s,2648,11,nil).overall)
-- (expects 1400)
