-- Tier 1: Core/EUIUnlockBridge.lua's opt-in match child. A registration that
-- hands over size setters becomes one; every other registration keeps the
-- refusal the bridge spec pins. Each rule fails silently when wrong: a missing
-- setter hides the match buttons, a missing hold lets unlock mode re-place the
-- frame against the screen, and a missing pull leaves a match inert.
local L = require("dev.spec._ke_loader")

local function publish(opts, eui)
    local KE = L.loadEUIUnlockBridge()
    local captured
    _G.EllesmereUI = eui or {}
    _G.EllesmereUI.MakeUnlockElement = function(element) return element end
    _G.EllesmereUI.RegisterUnlockElements = function(_, batch) captured = batch[1] end
    KE.EUIUnlock:Register({
        key = "Thing",
        frame = { GetWidth = function() return 100 end,
                  GetHeight = function() return 50 end },
        getPosition = function() return nil end,
        setPosition = function() end,
    }, opts)
    return captured, KE
end

describe("EUIUnlockBridge match child", function()
    after_each(function()
        _G.EllesmereUI = nil
    end)

    it("hands over setters, unrefused and held, only for a registration that gives one", function()
        for _, row in ipairs({
            { name = "no setter", opts = nil, child = false },
            { name = "width setter", opts = { setWidth = function() end }, child = true },
            { name = "height setter", opts = { setHeight = function() end }, child = true },
        }) do
            local element = publish(row.opts)
            assert.equals(row.child, element.matchUnavailable == nil, row.name)
            assert.equals(row.child, element.isPositionHeld ~= nil, row.name)
            assert.is_nil(element.noResize, row.name)
        end
    end)

    it("passes the module's setter the size alone", function()
        local got = {}
        local element = publish({
            setWidth = function(w) got.w = w end,
            setHeight = function(h) got.h = h end,
        })
        element.setWidth("KE_Thing", 240)
        element.setHeight("KE_Thing", 34)
        assert.same({ w = 240, h = 34 }, got)
    end)

    it("contains a setter that raises, and reports it", function()
        local element = publish({ setWidth = function() error("boom") end })
        local reported
        _G.geterrorhandler = function() return function(err) reported = err end end
        assert.has_no.errors(function() element.setWidth("KE_Thing", 240) end)
        assert.is_truthy(reported and tostring(reported):find("boom", 1, true))
    end)

    it("holds the position only while no unlock anchor places the element", function()
        for _, anchored in ipairs({ true, false }) do
            local element = publish({ setWidth = function() end },
                { IsAnchored = function() return anchored end })
            assert.equals(not anchored, element.isPositionHeld("KE_Thing"))
        end
    end)

    it("pulls from the target of each axis a setter was given for, and never pulls without one", function()
        for _, row in ipairs({
            { name = "no setter", opts = nil, want = {} },
            { name = "width setter only", opts = { setWidth = function() end }, want = { "w:ERB_Health" } },
        }) do
            local pulled = {}
            local _, KE = publish(row.opts, {
                GetWidthMatchTarget = function(key) return key == "KE_Thing" and "ERB_Health" or nil end,
                GetHeightMatchTarget = function() return "ERB_Power" end,
                PropagateWidthMatch = function(key) pulled[#pulled + 1] = "w:" .. key end,
                PropagateHeightMatch = function(key) pulled[#pulled + 1] = "h:" .. key end,
            })
            KE.EUIUnlock.PullMatchesToUs()
            assert.same(row.want, pulled, row.name)
        end
    end)
end)
