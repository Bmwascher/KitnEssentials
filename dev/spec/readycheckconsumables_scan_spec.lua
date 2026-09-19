-- The weapon-enchant read on ReadyCheckConsumables: a slot that returns
-- nothing is "no enchant", painted not-ready without an error.

local L = require("dev.spec._ke_loader")

describe("ReadyCheckConsumables UpdateWeaponEnchant", function()
    it("paints not-ready without erroring when the slot returns nothing", function()
        local RCC = L.loadReadyCheckConsumables()
        local desaturated, timeText
        RCC.buttons = {
            oil = {
                statusTexture = { SetTexture = function() end, Show = function() end },
                texture = { SetDesaturated = function(_, on) desaturated = on end },
                timeLeft = { SetText = function(_, s) timeText = s end },
                countText = { SetText = function() end },
            },
        }
        RCC:UpdateWeaponEnchant("oil", 16)
        assert.is_true(desaturated)
        assert.equals("", timeText)
    end)
end)
