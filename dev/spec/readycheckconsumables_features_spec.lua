-- The low-duration warning. The predicate is strictly under a threshold
-- and never fires on a nil remaining or a nil threshold; a slot whose aura
-- expiry is secret paints no timer, no warning colour and no glow. The
-- slot button is a recording stub because the paint is read back from its
-- text and colour.

local L = require("dev.spec._ke_loader")

local function recordingButton()
    local btn = {
        statusTexture = { SetTexture = function(t, tex) t.tex = tex end, Show = function() end, Hide = function() end },
        texture = { SetDesaturated = function() end, SetTexture = function() end },
        timeLeft = {},
        countText = { SetText = function() end },
    }
    btn.timeLeft.SetText = function(_, s) btn.text = s end
    btn.timeLeft.SetTextColor = function(_, r, g, b) btn.color = { r, g, b } end
    return btn
end

describe("ReadyCheckConsumables low-duration predicate", function()
    it("warns strictly under the threshold and never on a nil side", function()
        local RCC = L.loadReadyCheckConsumables()
        local cases = {
            { remain = 599, threshold = 600, low = true },
            { remain = 600, threshold = 600, low = false },
            { remain = 601, threshold = 600, low = false },
            { remain = nil, threshold = 600, low = false },
            { remain = 30,  threshold = nil, low = false },
        }
        for i, c in ipairs(cases) do
            assert.equals(c.low, RCC._IsLowDuration(c.remain, c.threshold), "case " .. i)
        end
    end)
end)

describe("ReadyCheckConsumables low-duration paint", function()
    it("paints no timer, no warning colour and no glow when the aura's expiry is secret", function()
        local RCC, _, seams = L.loadReadyCheckConsumables({ GetTime = function() return 1000 end })
        RCC.db.LowDurationWarning = true
        RCC.db.LowDurationMinutes = 10
        RCC.db.DurationColor = { 0.5, 0.5, 0.5, 1 }
        local btn = recordingButton()
        RCC.buttons = { food = btn }
        local FOOD_BUFF = 1284616

        RCC:UpdateFood({ [FOOD_BUFF] = { spellId = FOOD_BUFF, expirationTime = seams.SECRET } })
        assert.equals("", btn.text)
        assert.same({ 0.5, 0.5, 0.5 }, btn.color)
        assert.equals(0, seams.glow.starts)

        RCC:UpdateFood({ [FOOD_BUFF] = { spellId = FOOD_BUFF, expirationTime = 1300 } })
        assert.equals("5m", btn.text)
        assert.same({ 1, 0.3, 0.3 }, btn.color)
        assert.equals(1, seams.glow.starts)
    end)
end)
