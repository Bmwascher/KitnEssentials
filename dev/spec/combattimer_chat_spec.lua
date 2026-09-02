-- Modules/Combat/CombatTimer.lua -- the chat-line refusal rule in CT:OnStop.
-- The frames, the OnUpdate ticker and the KE.CombatState event wiring are
-- verified in game; this is the one rule a later edit breaks silently.
local L = require("dev.spec._ke_loader")

describe("combat timer chat line", function()
    local CT, KE, printed

    local function newCT(combatState)
        CT, KE = L.loadCombatTimer({ CombatState = combatState })
        printed = 0
        KE.Print = function() printed = printed + 1 end
        CT.db = { Format = "MM:SS", ShowChatMessage = true }
        return CT
    end

    it("prints no chat line on reset, on a fight the player never joined, or when disabled", function()
        local cases = {
            { name = "reason is reset", reason = "reset", playerJoined = true, showChatMessage = true },
            { name = "PlayerJoined is false", reason = "combat", playerJoined = false, showChatMessage = true },
            { name = "ShowChatMessage is false", reason = "combat", playerJoined = true, showChatMessage = false },
        }
        for _, case in ipairs(cases) do
            newCT({
                PlayerJoined = function() return case.playerJoined end,
                GetDuration = function() return 12 end,
            })
            CT.db.ShowChatMessage = case.showChatMessage
            CT:OnStop(case.reason)
            assert.equals(0, printed, case.name)
        end
    end)

    it("prints a chat line on an ordinary combat end with all three conditions satisfied", function()
        newCT({
            PlayerJoined = function() return true end,
            GetDuration = function() return 12 end,
        })
        CT:OnStop("combat")
        assert.equals(1, printed)
    end)
end)
