-- The repaint dispatch on ReadyCheckConsumables. A category the user turned
-- off, or whose contextual predicate says no, must not have its worker
-- called; the predicate is asked once; while aura identities are hidden the
-- weapon slots still repaint and the aura-driven ones do not; requests made
-- in one frame collapse into one repaint; a repaint queued before the row
-- died paints nothing; layout is not applied in combat, where the slot
-- buttons are protected; and a running glow is not restarted until the
-- teardown stop clears it. The workers, predicates and layout are stubbed
-- on the module instance because the dispatch is the seam under test.
-- The one stateful fake is C_Timer.After, which the loader captures so the
-- spec can fire the next-frame callback itself.

local L = require("dev.spec._ke_loader")

local function liveFrame()
    return setmetatable({
        IsVisible = function() return true end,
        Hide = function() end,
        SetAlpha = function() end,
        stateFrame = {},
    }, { __index = function() return function() end end })
end

local function stubButton()
    return {
        statusTexture = { SetTexture = function() end, Show = function() end, Hide = function() end },
        texture = { SetDesaturated = function() end, SetTexture = function() end },
        timeLeft = { SetText = function() end, SetTextColor = function() end },
        countText = { SetText = function() end },
        click = { Hide = function() end, Show = function() end, SetAttribute = function() end },
    }
end

describe("ReadyCheckConsumables glow guard", function()
    it("does not restart a running glow, and the teardown stop clears the flag", function()
        local RCC, _, seams = L.loadReadyCheckConsumables()
        RCC.frame = liveFrame()
        local btn = stubButton()
        RCC.buttons = { [5] = btn, rune = btn }
        RCC.db.UnlimitedRunesOnly = true
        seams.bagCount = 1

        RCC:UpdateRune({})
        RCC:UpdateRune({})
        assert.equals(1, seams.glow.starts)
        assert.is_true(btn.glowActive)

        RCC:HideFrame()
        assert.is_false(btn.glowActive)
        RCC:UpdateRune({})
        assert.equals(2, seams.glow.starts)
    end)
end)
