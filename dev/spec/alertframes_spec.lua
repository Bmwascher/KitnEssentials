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

    -- Replace-mode Loot Roll anchors the prompt to its own bar stack from the
    -- same post-hook; this module must stand aside for it there or the two
    -- fight over one frame. The winnings toasts are this module's in every mode.
    describe("PlacesBonusRollFrame", function()
        local places

        before_each(function()
            local _, _, seams = loader.loadAlertFrames()
            places = seams.placesBonusRollFrame
        end)

        it("yields only the prompt, and only to Replace-mode Loot Roll", function()
            local cases = {
                { "BonusRollFrame",         true,  false },
                { "BonusRollFrame",         false, true  },
                { "BonusRollLootWonFrame",  true,  true  },
                { "BonusRollLootWonFrame",  false, true  },
                { "BonusRollMoneyWonFrame", true,  true  },
                { "BonusRollMoneyWonFrame", false, true  },
            }
            for _, c in ipairs(cases) do
                assert.equal(c[3], places(c[1], c[2]), c[1] .. " replace=" .. tostring(c[2]))
            end
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
            _G.GroupLootContainer = nil
        end)

        it("leaves an externally anchored subsystem alone", function()
            local passThrough = function() end
            _G.AlertFrameExternallyAnchoredMixin = { AdjustAnchors = passThrough }
            local sys = { anchorFrame = {}, AdjustAnchors = passThrough }
            adjust(sys)
            assert.equal(passThrough, sys.AdjustAnchors)
        end)

        -- The loot container is the one externally anchored subsystem this
        -- module does replace: Blizzard's own AdjustAnchors returns the
        -- container whenever it is shown, which is the bottom of the screen
        -- once the managed layout owns it, and every alert behind it would
        -- chain from there.
        it("routes the loot container's subsystem through the bonus stack", function()
            local passThrough = function() end
            _G.AlertFrameExternallyAnchoredMixin = { AdjustAnchors = passThrough }
            _G.GroupLootContainer = {}
            local sys = { anchorFrame = _G.GroupLootContainer, AdjustAnchors = passThrough }
            adjust(sys)
            assert.is_function(sys.AdjustAnchors)
            assert.not_equal(passThrough, sys.AdjustAnchors)
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

    -- The chain function itself, driven through the placer so the top-of-stack
    -- bookkeeping is exercised on the way: an alert arriving while a prompt
    -- is up must stack above the prompt, not on top of it, and must ignore a
    -- prompt Loot Roll owns.
    describe("the loot container's replaced AdjustAnchors", function()
        local AF, chain, relative

        local function bonusFrame(shown)
            local f = { shown = shown, points = {} }
            f.IsShown = function() return f.shown end
            f.ClearAllPoints = function() end
            f.SetPoint = function(_, ...) f.points[#f.points + 1] = { ... } end
            f.HookScript = function() end
            return f
        end

        before_each(function()
            local af, _, seams = loader.loadAlertFrames()
            AF = af
            AF.holder = {}
            relative = {}
            local sys = { anchorFrame = {}, AdjustAnchors = function() end }
            _G.GroupLootContainer = sys.anchorFrame
            _G.AlertFrameExternallyAnchoredMixin = { AdjustAnchors = sys.AdjustAnchors }
            seams.adjustSubSystem(sys)
            chain = function() return sys.AdjustAnchors(sys, relative) end
        end)

        after_each(function()
            _G.GroupLootContainer = nil
            _G.AlertFrameExternallyAnchoredMixin = nil
            _G.BonusRollFrame = nil
            _G.BonusRollLootWonFrame = nil
            _G.BonusRollMoneyWonFrame = nil
            local LR = _G.KitnEssentials:GetModule("LootRoll")
            LR.db, LR.IsEnabled = nil, nil
        end)

        it("returns the top placed frame, or passes the chain through when it placed none", function()
            local cases = {
                { name = "prompt up, Loot Roll not replacing", prompt = true, won = false, replace = false, top = "prompt" },
                { name = "prompt and won toast up", prompt = true, won = true, replace = false, top = "won" },
                { name = "prompt up but Loot Roll owns it", prompt = true, won = false, replace = true, top = "relative" },
                { name = "nothing shown", prompt = false, won = false, replace = false, top = "relative" },
                { name = "placed top hidden since", prompt = true, won = false, replace = false, hideAfter = true, top = "relative" },
                -- A profile switch rebinds Loot Roll's db but defers its enable
                -- state to /reload, so the running state is what its own
                -- prompt anchor reads, and this module must read the same.
                { name = "Loot Roll disabled by profile, still running", prompt = true, won = false, replace = true, running = true, dbEnabled = false, top = "relative" },
                { name = "Loot Roll enabled by profile, not yet running", prompt = true, won = false, replace = true, running = false, dbEnabled = true, top = "prompt" },
            }
            for _, c in ipairs(cases) do
                local prompt, won = bonusFrame(c.prompt), bonusFrame(c.won)
                _G.BonusRollFrame = prompt
                _G.BonusRollLootWonFrame = won
                local LR = _G.KitnEssentials:GetModule("LootRoll")
                local running = c.running
                if running == nil then running = true end
                LR.IsEnabled = function() return running end
                LR.db = { Enabled = c.dbEnabled ~= false, Replace = c.replace }
                AF:PositionBonusRollToasts()
                if c.hideAfter then prompt.shown = false end
                local expected = ({ prompt = prompt, won = won, relative = relative })[c.top]
                assert.equal(expected, chain(), c.name)
            end
        end)

        -- Alerts already on screen sit where the last UpdateAnchors left them,
        -- so a prompt placed under them overlaps until Blizzard re-walks the
        -- chain; the placer asks for that walk itself, and only when the top
        -- actually moved, since every walk re-anchors every alert.
        it("re-walks the alert chain only when the top of the bonus stack changes", function()
            local walks = 0
            _G.AlertFrame = { UpdateAnchors = function() walks = walks + 1 end }
            _G.BonusRollFrame = bonusFrame(true)
            _G.KitnEssentials:GetModule("LootRoll").IsEnabled = function() return false end
            AF:PositionBonusRollToasts()
            AF:PositionBonusRollToasts()
            assert.equal(1, walks)
            _G.BonusRollFrame.shown = false
            AF:PositionBonusRollToasts()
            assert.equal(2, walks)
            _G.AlertFrame = nil
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
            f.IsShown = function() return true end
            f.HookScript = function() end
            f.ClearAllPoints = function() f.clears = f.clears + 1 end
            f.SetPoint = function() f.points = f.points + 1 end
            _G[name] = f
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
            _G.BonusRollLootWonFrame = nil
            _G.AchievementAlertFrame1 = nil
        end)

        -- A winnings toast reaches AddAlertFrame already inside rollFrames when
        -- the bonus roll was a group roll, and outside it when it was not;
        -- both roads end on the alert stack now, so neither is yielded.
        it("places a winnings toast whether or not the container still holds it", function()
            for _, held in ipairs({ true, false }) do
                local f = alert("BonusRollLootWonFrame")
                _G.GroupLootContainer = held and { rollFrames = { [1] = f } } or nil
                hook(_G.AlertFrame, f)
                assert.is_true(placed(f), "held=" .. tostring(held))
            end
            assert.equal(2, calls.postAlertMove)
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
