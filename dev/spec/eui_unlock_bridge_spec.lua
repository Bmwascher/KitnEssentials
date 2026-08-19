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

-- The save branch is a refusal rule: it decides when unlock mode's centre-form
-- result may overwrite the anchor pair the user chose, and it fails silently
-- when wrong. The arithmetic itself is NOT retested here -- it belongs to
-- KE:ResolveAnchorOffsets and has its own spec. What is pinned here is which
-- branch runs, and that the coordinates handed to that helper are lifted out of
-- unlock mode's parent-centre space into the absolute space the helper expects.
describe("EUIUnlockBridge save branch", function()
    local UI_W, UI_H = 1920, 1080
    local F_W, F_H = 400, 200

    -- Returns the element unlock mode would have been handed, plus a record of
    -- what the module was asked to store and how the offsets were resolved.
    local function buildElement(storedPos, frameW, frameH, opts)
        opts = opts or {}
        local KE = L.loadEUIUnlockBridge()
        local record = { resolveCalls = {} }

        KE.ResolveAnchorOffsets = function(_, cx, cy, from, to, fw, fh, pl, pb, pw, ph)
            record.resolveCalls[#record.resolveCalls + 1] = {
                cx = cx, cy = cy, from = from, to = to,
                fw = fw, fh = fh, pl = pl, pb = pb, pw = pw, ph = ph,
            }
            return 111, 222
        end

        local originX = opts.originX or 0
        local originY = opts.originY or 0
        _G.UIParent = {
            GetWidth = function() return UI_W end,
            GetHeight = function() return UI_H end,
            GetLeft = function() return originX end,
            GetBottom = function() return originY end,
        }

        local frame = {
            GetWidth = function() return frameW end,
            GetHeight = function() return frameH end,
        }

        _G.EllesmereUI = {
            MakeUnlockElement = function(element) return element end,
            RegisterUnlockElements = function(_, batch) record.element = batch[1] end,
        }

        KE.EUIUnlock:Register({
            key = "Thing",
            displayName = "Thing",
            frame = frame,
            getPosition = function() return storedPos end,
            setPosition = function(pos) record.stored = pos end,
            getParentFrame = opts.getParentFrame,
        })

        return record
    end

    it("rebases onto the stored pair, in absolute coordinates", function()
        local r = buildElement(
            { AnchorFrom = "BOTTOMLEFT", AnchorTo = "BOTTOMLEFT", XOffset = 1, YOffset = 1 },
            F_W, F_H)
        r.element.savePos(nil, "CENTER", "CENTER", -759, -439)

        assert.equal(1, #r.resolveCalls)
        local call = r.resolveCalls[1]
        -- unlock mode measures from the parent's centre; the helper wants absolute
        assert.equal(0 + UI_W / 2 + -759, call.cx)
        assert.equal(0 + UI_H / 2 + -439, call.cy)
        assert.equal("BOTTOMLEFT", call.from)
        assert.equal("BOTTOMLEFT", call.to)
        assert.equal(F_W, call.fw)
        assert.equal(UI_W, call.pw)

        assert.same({ AnchorFrom = "BOTTOMLEFT", AnchorTo = "BOTTOMLEFT",
                      XOffset = 111, YOffset = 222 }, r.stored)
    end)

    it("stores a non-CENTER result verbatim, which is the cancel restore", function()
        local r = buildElement(
            { AnchorFrom = "BOTTOMLEFT", AnchorTo = "BOTTOMLEFT", XOffset = 1, YOffset = 1 },
            F_W, F_H)
        r.element.savePos(nil, "TOPRIGHT", "TOPRIGHT", 5, 6)

        assert.equal(0, #r.resolveCalls)
        assert.same({ AnchorFrom = "TOPRIGHT", AnchorTo = "TOPRIGHT",
                      XOffset = 5, YOffset = 6 }, r.stored)
    end)

    it("stores verbatim when there is no stored pair to preserve", function()
        local r = buildElement(nil, F_W, F_H)
        r.element.savePos(nil, "CENTER", "CENTER", 10, 20)

        assert.equal(0, #r.resolveCalls)
        assert.same({ AnchorFrom = "CENTER", AnchorTo = "CENTER",
                      XOffset = 10, YOffset = 20 }, r.stored)
    end)

    it("stores verbatim when the stored pair is already CENTER/CENTER", function()
        local r = buildElement(
            { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = 0, YOffset = 0 },
            F_W, F_H)
        r.element.savePos(nil, "CENTER", "CENTER", 10, 20)

        assert.equal(0, #r.resolveCalls)
        assert.same({ AnchorFrom = "CENTER", AnchorTo = "CENTER",
                      XOffset = 10, YOffset = 20 }, r.stored)
    end)

    it("refuses to rebase off a frame that measures zero", function()
        local r = buildElement(
            { AnchorFrom = "BOTTOMLEFT", AnchorTo = "BOTTOMLEFT", XOffset = 1, YOffset = 1 },
            0, 0)
        r.element.savePos(nil, "CENTER", "CENTER", 10, 20)

        assert.equal(0, #r.resolveCalls)
        assert.same({ AnchorFrom = "CENTER", AnchorTo = "CENTER",
                      XOffset = 10, YOffset = 20 }, r.stored)
    end)

    it("lifts by the screen origin, not just by half the screen", function()
        -- Every other case runs at origin zero, where a lift that forgot the
        -- origin would still pass. This one cannot.
        local r = buildElement(
            { AnchorFrom = "BOTTOMLEFT", AnchorTo = "BOTTOMLEFT", XOffset = 1, YOffset = 1 },
            F_W, F_H, { originX = 64, originY = 32 })
        r.element.savePos(nil, "CENTER", "CENTER", -759, -439)

        local call = r.resolveCalls[1]
        assert.equal(64 + UI_W / 2 + -759, call.cx)
        assert.equal(32 + UI_H / 2 + -439, call.cy)
        assert.equal(64, call.pl)
        assert.equal(32, call.pb)
    end)

    it("refuses the write entirely when the element is not screen-anchored", function()
        -- Unlock mode's coordinates are screen-relative. An element KE anchors
        -- to something else would be placed somewhere else entirely, so the
        -- write is refused rather than converted.
        local other = {}
        local r = buildElement(
            { AnchorFrom = "BOTTOMLEFT", AnchorTo = "BOTTOMLEFT", XOffset = 1, YOffset = 1 },
            F_W, F_H, { getParentFrame = function() return other end })
        r.element.savePos(nil, "CENTER", "CENTER", -759, -439)

        assert.equal(0, #r.resolveCalls)
        assert.is_nil(r.stored)
    end)

    it("stores the same offsets when unlock mode saves twice", function()
        local r = buildElement(
            { AnchorFrom = "BOTTOMLEFT", AnchorTo = "BOTTOMLEFT", XOffset = 1, YOffset = 1 },
            F_W, F_H)
        r.element.savePos(nil, "CENTER", "CENTER", -759, -439)
        local first = r.stored
        r.element.savePos(nil, "CENTER", "CENTER", -759, -439)

        assert.same(first, r.stored)
        assert.equal(2, #r.resolveCalls)
        assert.same(r.resolveCalls[1], r.resolveCalls[2])
    end)
end)
