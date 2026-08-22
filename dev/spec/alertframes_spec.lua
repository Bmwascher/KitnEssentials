local loader = require("dev.spec._ke_loader")

describe("Modules/QoL/AlertFrames.lua", function()

    describe("ShouldGrowUp", function()
        local shouldGrowUp

        before_each(function()
            local _, _, seams = loader.loadAlertFrames()
            shouldGrowUp = seams.shouldGrowUp
        end)

        it("grows up when the centre is below half the screen height and there is no perks anchor", function()
            assert.is_true(shouldGrowUp(100, 1000, false))
        end)

        it("grows down when the centre is above half the screen height and there is no perks anchor", function()
            assert.is_false(shouldGrowUp(900, 1000, false))
        end)

        it("always grows up when the Trading Post has re-based the stack, even above half screen", function()
            assert.is_true(shouldGrowUp(900, 1000, true))
        end)

        it("fails safe to grow down when the centre is nil and there is no perks anchor", function()
            assert.is_false(shouldGrowUp(nil, 1000, false))
        end)
    end)

    -- The refusal half is the one that matters: claiming a subsystem alert drops
    -- it out of the chain UpdateAnchors just built and it renders on top of the
    -- alert before it.
    describe("IsDirectAlertFrame", function()
        local isDirect

        local function named(name)
            return { GetName = function() return name end }
        end

        before_each(function()
            local _, _, seams = loader.loadAlertFrames()
            isDirect = seams.isDirectAlertFrame
        end)

        it("claims the bonus roll loot toast", function()
            assert.is_true(isDirect(named("BonusRollLootWonFrame")))
        end)

        it("claims the bonus roll money toast", function()
            assert.is_true(isDirect(named("BonusRollMoneyWonFrame")))
        end)

        it("refuses a subsystem alert, which UpdateAnchors has already chained", function()
            assert.is_false(isDirect(named("AchievementAlertFrame1")))
            assert.is_false(isDirect(named("LootWonAlertFrame1")))
        end)

        it("refuses an anonymous frame rather than indexing with nil", function()
            assert.is_false(isDirect(named(nil)))
        end)

        it("refuses a frame that cannot report a name, and a missing frame", function()
            assert.is_false(isDirect({}))
            assert.is_false(isDirect(nil))
        end)
    end)
end)
