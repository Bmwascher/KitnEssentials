-- Tier 1: Core/EUIUnlockBridge.lua position translation. Pure table shuffling
-- between KE's stored anchor shape and EllesmereUI's mover arguments.
local L = require("dev.spec._ke_loader")

describe("EUIUnlockBridge position translation", function()
    local KE
    before_each(function()
        KE = L.loadEUIUnlockBridge()
    end)

    it("maps a KE position table to EUI mover fields", function()
        local out = KE.EUIUnlock.ToEUIPosition({
            AnchorFrom = "BOTTOMLEFT",
            AnchorTo = "BOTTOMLEFT",
            XOffset = 1,
            YOffset = 2,
        })
        assert.same({ point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 1, y = 2 }, out)
    end)

    it("defaults missing anchor fields to CENTER and zero", function()
        local out = KE.EUIUnlock.ToEUIPosition({})
        assert.same({ point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }, out)
    end)

    it("returns nil when handed something that is not a table", function()
        assert.is_nil(KE.EUIUnlock.ToEUIPosition(nil))
        assert.is_nil(KE.EUIUnlock.ToEUIPosition("BOTTOMLEFT"))
    end)

    it("maps EUI mover arguments back to a KE position table", function()
        local out = KE.EUIUnlock.FromEUIPosition("TOPRIGHT", "TOPLEFT", -5, 12)
        assert.same({
            AnchorFrom = "TOPRIGHT",
            AnchorTo = "TOPLEFT",
            XOffset = -5,
            YOffset = 12,
        }, out)
    end)

    it("defaults missing EUI mover arguments the same way", function()
        local out = KE.EUIUnlock.FromEUIPosition(nil, nil, nil, nil)
        assert.same({
            AnchorFrom = "CENTER",
            AnchorTo = "CENTER",
            XOffset = 0,
            YOffset = 0,
        }, out)
    end)

    it("round-trips a position unchanged", function()
        local original = {
            AnchorFrom = "BOTTOM",
            AnchorTo = "TOP",
            XOffset = 7,
            YOffset = -3,
        }
        local eui = KE.EUIUnlock.ToEUIPosition(original)
        local back = KE.EUIUnlock.FromEUIPosition(eui.point, eui.relPoint, eui.x, eui.y)
        assert.same(original, back)
    end)
end)
