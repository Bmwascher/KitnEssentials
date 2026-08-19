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

describe("EUIUnlockBridge anchor rebasing", function()
    local KE
    before_each(function()
        KE = L.loadEUIUnlockBridge()
    end)

    -- A 1920x1080 screen holding a 400x200 frame, used by every case below.
    local UI_W, UI_H = 1920, 1080
    local F_W, F_H = 400, 200

    describe("AnchorOffset", function()
        it("puts CENTER at the middle", function()
            local x, y = KE.EUIUnlock.AnchorOffset("CENTER", F_W, F_H)
            assert.equal(0, x)
            assert.equal(0, y)
        end)

        it("reads each edge independently", function()
            local x, y = KE.EUIUnlock.AnchorOffset("LEFT", F_W, F_H)
            assert.equal(-200, x)
            assert.equal(0, y)

            x, y = KE.EUIUnlock.AnchorOffset("TOP", F_W, F_H)
            assert.equal(0, x)
            assert.equal(100, y)
        end)

        it("reads a corner as both of its halves", function()
            local x, y = KE.EUIUnlock.AnchorOffset("BOTTOMLEFT", F_W, F_H)
            assert.equal(-200, x)
            assert.equal(-100, y)

            x, y = KE.EUIUnlock.AnchorOffset("TOPRIGHT", F_W, F_H)
            assert.equal(200, x)
            assert.equal(100, y)
        end)

        it("treats a nil or non-string anchor as the centre", function()
            local x, y = KE.EUIUnlock.AnchorOffset(nil, F_W, F_H)
            assert.equal(0, x)
            assert.equal(0, y)
        end)
    end)

    describe("RebaseFromCenter", function()
        it("is the identity for a CENTER/CENTER pair", function()
            local x, y = KE.EUIUnlock.RebaseFromCenter(37, -12, "CENTER", "CENTER",
                F_W, F_H, UI_W, UI_H)
            assert.equal(37, x)
            assert.equal(-12, y)
        end)

        it("re-expresses a centred frame against BOTTOMLEFT/BOTTOMLEFT", function()
            -- Frame dead centre of the screen. Its bottom-left corner then sits
            -- half the screen minus half the frame in from the screen corner.
            local x, y = KE.EUIUnlock.RebaseFromCenter(0, 0, "BOTTOMLEFT", "BOTTOMLEFT",
                F_W, F_H, UI_W, UI_H)
            assert.equal(760, x)   -- 1920/2 - 400/2
            assert.equal(440, y)   -- 1080/2 - 200/2
        end)

        it("round-trips a stored edge position through the centre form", function()
            -- Start from the chat default, BOTTOMLEFT/BOTTOMLEFT at +1,+1.
            -- Its centre relative to the screen centre is what unlock mode
            -- would hand back for an untouched frame.
            local cx = 1 + F_W / 2 - UI_W / 2
            local cy = 1 + F_H / 2 - UI_H / 2
            local x, y = KE.EUIUnlock.RebaseFromCenter(cx, cy, "BOTTOMLEFT", "BOTTOMLEFT",
                F_W, F_H, UI_W, UI_H)
            assert.equal(1, x)
            assert.equal(1, y)
        end)

        it("handles a mixed pair, frame TOPRIGHT against screen BOTTOMLEFT", function()
            local x, y = KE.EUIUnlock.RebaseFromCenter(0, 0, "TOPRIGHT", "BOTTOMLEFT",
                F_W, F_H, UI_W, UI_H)
            assert.equal(1160, x)  -- 0 + 200 - (-960)
            assert.equal(640, y)   -- 0 + 100 - (-540)
        end)
    end)
end)
