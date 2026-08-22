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

    -- GroupLootFrame.lua puts a winnings toast into the container on the line
    -- before it calls AddAlertFrame on the same frame, so "already ours to
    -- place" and "already the container's" both look like a direct alert.
    describe("IsHeldByLootContainer", function()
        local isHeld

        before_each(function()
            local _, _, seams = loader.loadAlertFrames()
            isHeld = seams.isHeldByLootContainer
            _G.GroupLootContainer = nil
        end)

        after_each(function()
            _G.GroupLootContainer = nil
        end)

        it("claims a frame the container is holding", function()
            local toast = {}
            _G.GroupLootContainer = { rollFrames = { [2] = toast } }
            assert.is_true(isHeld(toast))
        end)

        it("refuses a frame the container is not holding", function()
            _G.GroupLootContainer = { rollFrames = { [1] = {} } }
            assert.is_false(isHeld({}))
        end)

        it("refuses everything when the container has no roll frames yet", function()
            _G.GroupLootContainer = {}
            assert.is_false(isHeld({}))
        end)

        it("refuses everything when the container does not exist", function()
            assert.is_false(isHeld({}))
        end)
    end)

    -- Blizzard's externally anchored subsystems exist to be passed through, not
    -- moved: replacing their AdjustAnchors drags a frame something else owns
    -- onto the toast stack and overwrites the position the player set.
    describe("AdjustSubSystem", function()
        local adjust

        before_each(function()
            local _, _, seams = loader.loadAlertFrames()
            adjust = seams.adjustSubSystem
            _G.AlertFrameExternallyAnchoredMixin = nil
        end)

        after_each(function()
            _G.AlertFrameExternallyAnchoredMixin = nil
        end)

        it("leaves an externally anchored subsystem alone", function()
            local passThrough = function() end
            _G.AlertFrameExternallyAnchoredMixin = { AdjustAnchors = passThrough }
            local sys = { anchorFrame = {}, AdjustAnchors = passThrough }
            adjust(sys)
            assert.equal(passThrough, sys.AdjustAnchors)
        end)

        it("takes over an auto-anchored subsystem, which shares the anchorFrame shape", function()
            _G.AlertFrameExternallyAnchoredMixin = { AdjustAnchors = function() end }
            local own = function() end
            local sys = { anchorFrame = {}, AdjustAnchors = own }
            adjust(sys)
            assert.not_equal(own, sys.AdjustAnchors)
        end)

        it("takes over a pooled subsystem", function()
            _G.AlertFrameExternallyAnchoredMixin = { AdjustAnchors = function() end }
            local sys = { alertFramePool = {} }
            adjust(sys)
            assert.is_function(sys.AdjustAnchors)
        end)

        it("takes over everything when the mixin global is absent", function()
            local own = function() end
            local sys = { anchorFrame = {}, AdjustAnchors = own }
            adjust(sys)
            assert.not_equal(own, sys.AdjustAnchors)
        end)
    end)

    -- The hook itself, not its predicates. Testing the predicates alone leaves
    -- every guard inside the hook deletable with the suite still green, which
    -- is the shape of check this file is meant to prevent.
    describe("the AddAlertFrame post-hook", function()
        local AF, hook, calls

        local function alert(name)
            local f = { clears = 0, points = 0 }
            f.GetName = function() return name end
            f.ClearAllPoints = function() f.clears = f.clears + 1 end
            f.SetPoint = function() f.points = f.points + 1 end
            return f
        end

        local function placed(f)
            return f.points > 0
        end

        before_each(function()
            AF, hook, calls = loader.loadAlertFramesWithHooks()
        end)

        after_each(function()
            _G.GroupLootContainer = nil
            _G.AlertFrame = nil
        end)

        it("is installed at all", function()
            assert.is_function(hook)
        end)

        it("places a direct winnings toast the container is not holding", function()
            local f = alert("BonusRollLootWonFrame")
            hook(_G.AlertFrame, f)
            assert.is_true(placed(f))
            assert.equal(1, calls.postAlertMove)
        end)

        it("stands aside when the container is holding that same toast", function()
            local f = alert("BonusRollLootWonFrame")
            _G.GroupLootContainer = { rollFrames = { [1] = f } }
            hook(_G.AlertFrame, f)
            assert.is_false(placed(f))
            assert.equal(0, calls.postAlertMove)
        end)

        it("stands aside for a subsystem alert, which UpdateAnchors already chained", function()
            local f = alert("AchievementAlertFrame1")
            hook(_G.AlertFrame, f)
            assert.is_false(placed(f))
            assert.equal(0, calls.postAlertMove)
        end)

        it("stands aside while the module is disabled", function()
            AF.IsEnabled = function() return false end
            local f = alert("BonusRollLootWonFrame")
            hook(_G.AlertFrame, f)
            assert.is_false(placed(f))
        end)
    end)
end)
