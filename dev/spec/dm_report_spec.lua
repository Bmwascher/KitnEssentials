-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_report_spec.lua                             ║
-- ║  Damage Meter report: the chat-lock refusal.             ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- WHY THIS EARNS A SPEC: a refusal rule. Under a chat lock the send raises a
-- blocked-action error, and a report that skips the guard fails silently in
-- review. The session path is stubbed on the DM instance so an unlocked report
-- reaches the send; that row is what makes the locked row falsifiable. The
-- lock is declared through KE, never the client's.
local L = require("dev.spec._ke_loader")

describe("DamageMeter report under a chat lock", function()
    it("prints one refusal and sends nothing under the lock, and sends without it", function()
        for _, locked in ipairs({ true, false }) do
            local sent, printed = {}, {}
            local DM, KE = L.loadDMCore({
                C_ChatInfo = {
                    SendChatMessage = function(msg, channel)
                        sent[#sent + 1] = { msg, channel }
                    end,
                },
            })
            KE.Print = function(_, msg) printed[#printed + 1] = msg end
            KE.IsChatMessagingLocked = function() return locked end
            DM.ResolveWindowConfig = function() return {} end
            DM.EffectiveMeterType = function() return nil end
            DM.FormatWindowLabel = function() return "Damage Done" end
            DM.GetSession = function()
                return {
                    totalAmount = 100,
                    combatSources = { { name = "Tank", totalAmount = 60, amountPerSecond = 6 } },
                }
            end

            DM:ReportView("")

            if locked then
                assert.equals(1, #printed, "locked: printed lines")
                assert.equals(0, #sent, "locked: sends")
            else
                assert.equals(0, #printed, "unlocked: printed lines")
                assert.is_true(#sent > 0, "unlocked: sends")
            end
        end
    end)
end)
