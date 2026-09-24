-- Modules/Combat/CombatTimer.lua -- the chat-line refusal rule in CT:OnStop.
-- The frames, the paint ticker and the event wiring are verified in game;
-- this is the one rule a later edit breaks silently.
local L = require("dev.spec._ke_loader")

describe("combat timer chat line", function()
    local CT, KE, printed, lastLine

    local function newCT()
        CT, KE = L.loadCombatTimer()
        printed, lastLine = 0, nil
        KE.Print = function(_, msg)
            printed = printed + 1
            lastLine = msg
        end
        CT.db = { Format = "MM:SS", ShowChatMessage = true }
        CT.span = 12
        return CT
    end

    it("prints no chat line on a loading-screen reset or when disabled", function()
        local cases = {
            { name = "reason is reset", reason = "reset", showChatMessage = true },
            { name = "ShowChatMessage is false", reason = "stop", showChatMessage = false },
        }
        for _, case in ipairs(cases) do
            newCT()
            CT.db.ShowChatMessage = case.showChatMessage
            CT:OnStop(case.reason)
            assert.equals(0, printed, case.name)
        end
    end)

    it("prints the stopped span on an ordinary stop", function()
        newCT()
        CT:OnStop("stop")
        assert.equals(1, printed)
        assert.equals("Combat lasted [00:12]", lastLine)
    end)
end)
