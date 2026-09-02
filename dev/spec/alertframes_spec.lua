local loader = require("dev.spec._ke_loader")

describe("Modules/QoL/AlertFrames.lua", function()

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

        it("claims both bonus roll toasts", function()
            assert.is_true(isDirect(named("BonusRollLootWonFrame")))
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

        it("takes over auto-anchored, pooled, and mixin-absent subsystems alike", function()
            local variants = {
                -- auto-anchored: shares the anchorFrame shape
                function()
                    _G.AlertFrameExternallyAnchoredMixin = { AdjustAnchors = function() end }
                    local own = function() end
                    return { anchorFrame = {}, AdjustAnchors = own }, own
                end,
                -- pooled
                function()
                    _G.AlertFrameExternallyAnchoredMixin = { AdjustAnchors = function() end }
                    return { alertFramePool = {} }, nil
                end,
                -- mixin global absent entirely
                function()
                    _G.AlertFrameExternallyAnchoredMixin = nil
                    local own = function() end
                    return { anchorFrame = {}, AdjustAnchors = own }, own
                end,
            }

            for _, setup in ipairs(variants) do
                local sys, own = setup()
                adjust(sys)
                assert.is_function(sys.AdjustAnchors)
                if own then
                    assert.not_equal(own, sys.AdjustAnchors)
                end
            end
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
