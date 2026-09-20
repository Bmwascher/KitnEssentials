-- The expiry timer on ReadyCheckConsumables. _ScheduleExpiry arms one
-- C_Timer.After per shown check and the callback closes the row and the
-- Blizzard popup at zero, but only for the check that armed it, only while
-- the row is live, and only when the popup is still shown. The one stateful
-- fake is ReadyCheckFrame: the third clause asks the popup whether it is
-- shown, and only a frame can answer that. READY_CHECK_FINISHED is replaced
-- with a counter on the module table the loader builds fresh per case.

local L = require("dev.spec._ke_loader")

describe("ReadyCheckConsumables _ScheduleExpiry", function()
    local STUBBED = { "ReadyCheckFrame" }
    local RCC, seams, saved, finished, popup, rowVisible

    before_each(function()
        saved = {}
        for _, key in ipairs(STUBBED) do saved[key] = _G[key] end
        local loaded = { L.loadReadyCheckConsumables() }
        RCC, seams = loaded[1], loaded[3]
        finished, rowVisible = 0, true
        RCC.READY_CHECK_FINISHED = function() finished = finished + 1 end
        RCC.frame = setmetatable({
            IsVisible = function() return rowVisible end,
        }, { __index = function() return function() end end })
        popup = { shown = true, hides = 0 }
        function popup:IsShown() return self.shown end
        function popup:Hide() self.hides = self.hides + 1 end
        _G.ReadyCheckFrame = popup
    end)

    after_each(function()
        for _, key in ipairs(STUBBED) do _G[key] = saved[key] end
    end)

    it("ignores a timer whose check has been superseded", function()
        RCC:_ScheduleExpiry(30)
        RCC:_ScheduleExpiry(30)
        assert.equals(2, #seams.timers)
        seams.timers[1]()
        assert.equals(0, finished)
        assert.equals(0, popup.hides)
    end)

    it("ignores a timer once the row is no longer live", function()
        RCC:_ScheduleExpiry(30)
        rowVisible = false
        seams.timers[1]()
        assert.equals(0, finished)
        assert.equals(0, popup.hides)
    end)

    it("closes the row and a shown popup for the live matching check", function()
        RCC:_ScheduleExpiry(30)
        seams.timers[1]()
        assert.equals(1, finished)
        assert.equals(1, popup.hides)

        finished, popup.shown = 0, false
        RCC:_ScheduleExpiry(30)
        seams.timers[2]()
        assert.equals(1, finished)
        assert.equals(1, popup.hides, "hid a popup that was not shown")
    end)

    it("bumps the serial without arming when the duration is unknown", function()
        local serial = RCC._checkSerial
        RCC:_ScheduleExpiry(nil)
        assert.equals(0, #seams.timers)
        assert.equals(serial + 1, RCC._checkSerial)
    end)
end)
