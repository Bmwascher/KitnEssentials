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
        guiPath = "Thing",
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

    it("checks once a frame and rebuilds its own open page only when the match differs from the one it shows", function()
        local target
        local element, KE = publish({ setWidth = function() end }, {
            GetWidthMatchTarget = function() return target end,
        })
        local queued, rebuilt = {}, 0
        _G.C_Timer = { After = function(_, fn) queued[#queued + 1] = fn end }
        local function build() KE.EUIUnlock:ShownMatchTargets("Thing") end
        KE.GUIFrame = {
            mainFrame = { IsShown = function() return true end },
            selectedSidebarItem = "Thing",
            RefreshContent = function()
                rebuilt = rebuilt + 1
                build()
            end,
        }
        build()
        local function settle()
            local run = queued
            queued = {}
            for _, fn in ipairs(run) do fn() end
        end

        element.setWidth("KE_Thing", 240)
        element.setWidth("KE_Thing", 240)
        assert.equals(1, #queued)
        settle()
        assert.equals(0, rebuilt)

        target = "ERB_Health"
        element.setWidth("KE_Thing", 240)
        settle()
        assert.equals(1, rebuilt)

        element.setWidth("KE_Thing", 240)
        settle()
        assert.equals(1, rebuilt)

        -- Made with the window closed, so no check ran; the page then opens on
        -- it, and the match is cleared under the open page.
        target = "ERB_Power"
        build()
        target = nil
        element.setWidth("KE_Thing", 240)
        settle()
        assert.equals(2, rebuilt)

        KE.GUIFrame.selectedSidebarItem = "Other"
        target = "ERB_Health"
        element.setWidth("KE_Thing", 240)
        settle()
        assert.equals(2, rebuilt)
    end)

    it("does not pull while EllesmereUI is applying a match", function()
        for _, row in ipairs({
            { name = "applying", applying = true, want = 0 },
            { name = "idle", applying = false, want = 1 },
        }) do
            local pulls = 0
            local _, KE = publish({ setWidth = function() end }, {
                _propagatingMatch = row.applying,
                GetWidthMatchTarget = function() return "ERB_Health" end,
                PropagateWidthMatch = function() pulls = pulls + 1 end,
            })
            KE.EUIUnlock:PullMatch("Thing", "width")
            assert.equals(row.want, pulls, row.name)
        end
    end)

    it("counts a pull of the axis being applied as done, and makes a refused one a frame later unless it runs first", function()
        for _, row in ipairs({
            { name = "made a frame later", pullFirst = false },
            { name = "pulled before then", pullFirst = true },
        }) do
            local pulls, answers = 0, {}
            local eui = {
                GetWidthMatchTarget = function() return "ERB_Health" end,
                PropagateWidthMatch = function() pulls = pulls + 1 end,
            }
            local element, KE
            element, KE = publish({
                setWidth = function() end,
                setHeight = function()
                    answers.height = KE.EUIUnlock:PullMatch("Thing", "height")
                    answers.width = KE.EUIUnlock:PullMatch("Thing", "width")
                end,
            }, eui)
            local queued = {}
            _G.C_Timer = { After = function(_, fn) queued[#queued + 1] = fn end }
            eui._propagatingMatch = true
            element.setHeight("KE_Thing", 34)
            eui._propagatingMatch = false
            assert.is_true(answers.height, row.name)
            assert.is_false(answers.width, row.name)
            if row.pullFirst then KE.EUIUnlock:PullMatch("Thing", "width") end
            for _, fn in ipairs(queued) do fn() end
            assert.equals(1, pulls, row.name)
        end
    end)
end)
