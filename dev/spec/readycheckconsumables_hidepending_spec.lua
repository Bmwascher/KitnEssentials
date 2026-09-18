-- The deferred-hide flag on ReadyCheckConsumables. Two guard rules a later
-- edit breaks silently: every in-combat HideFrame queues a closure on the
-- combat-exit queue and only the first to run may tear down; and while a
-- hide is pending, event repaints refuse unless forced with the literal
-- true. The one stateful fake is KE.RunAfterCombat: the guard is defined by
-- when that queue delivers, and only the queue can deliver it, so the spec
-- captures its closures and drains them itself.

local L = require("dev.spec._ke_loader")

describe("ReadyCheckConsumables _hidePending", function()
    local RCC, seams, frameHides, clickHides

    local function drain()
        local fns = seams.queue
        seams.queue = {}
        for i = 1, #fns do fns[i]() end
    end

    before_each(function()
        local loaded = { L.loadReadyCheckConsumables() }
        RCC, seams = loaded[1], loaded[3]
        frameHides, clickHides = 0, 0
        RCC.frame = setmetatable({
            Hide = function() frameHides = frameHides + 1 end,
            SetAlpha = function() end,
            IsVisible = function() return true end,
            stateFrame = {},
        }, { __index = function() return function() end end })
        RCC.buttons = {}
        RCC.stateDriverActive = true
    end)

    it("collapses two in-combat hides into one teardown at combat exit", function()
        RCC.buttons[1] = { click = { Hide = function() clickHides = clickHides + 1 end } }
        seams.combat.inCombat = true
        RCC:HideFrame()
        RCC:HideFrame()
        assert.equals(2, #seams.queue)
        assert.is_true(RCC._hidePending)

        seams.combat.inCombat = false
        drain()
        assert.equals(1, seams.counts.driverUnregistered)
        assert.equals(1, frameHides)
        assert.equals(1, clickHides)
        assert.is_nil(RCC._hidePending)
        assert.is_false(RCC.stateDriverActive)
    end)

    it("refuses event repaints while a hide is pending unless forced with true", function()
        RCC._hidePending = true
        local cases = {
            { arg = nil,                     scans = 0 },
            { arg = "PLAYER_REGEN_ENABLED",  scans = 0 },
            { arg = true,                    scans = 1 },
        }
        for _, c in ipairs(cases) do
            seams.counts.scans = 0
            RCC:UpdateAllIcons(c.arg)
            assert.equals(c.scans, seams.counts.scans, "force=" .. tostring(c.arg))
        end
    end)
end)
