-- Modules/DungeonTools/KicksCasts/KickTracker.lua: the own-kick guard. A secret unit or spell
-- ID on UNIT_SPELLCAST_SUCCEEDED is never compared or used as a table key, so
-- it never confirms a kick. The mock cannot make a real secret, so each refusal
-- row declares secret a plain value that would otherwise confirm.
local L = require("dev.spec._ke_loader")

local KICK = 1766 -- Rogue Kick, a known interrupt

describe("KickTracker own-kick guard", function()
    it("confirms a plain known interrupt and refuses a secret unit or spell ID", function()
        local rows = {
            { name = "plain player kick", secret = function() return false end, confirms = 1 },
            { name = "secret spell ID", secret = function(v) return v == KICK end, confirms = 0 },
            { name = "secret unit", secret = function(v) return v == "player" end, confirms = 0 },
        }
        for _, row in ipairs(rows) do
            local KT = L.loadKickTracker({ issecretvalue = row.secret })
            KT.db = { Enabled = true }
            KT.isActive, KT.isPreview = true, false
            local confirmed = 0
            KT.ConfirmKick = function() confirmed = confirmed + 1 end
            KT:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", KICK)
            assert.equals(row.confirms, confirmed, row.name)
        end
    end)
end)

describe("KickTracker own success reduction", function()
    it("takes the success reduction off a running own clock once per cast", function()
        local KT = L.loadKickTracker({ issecretvalue = function() return false end })
        KT.db = { Enabled = true }
        local guid = UnitGUID("player")
        KT.partyMembers[guid] = { unit = "player", interruptData = { id = 47528 },
                                  kickStart = GetTime(), kickDuration = 15 }
        KT.OwnKickCooldown = function(_, _, succeeded) return succeeded and 12 or 15 end
        local reductions = 0
        KT.ConfirmKick = function() reductions = reductions + 1 end
        KT.ClearKick = function() reductions = reductions + 1 end
        KT:ApplyOwnSuccess()
        KT:ApplyOwnSuccess()
        assert.equals(1, reductions)
    end)
end)
