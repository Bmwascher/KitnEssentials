-- Which settings let the potion text show. The combat, instance and healer
-- reads that feed it are WoW calls and stay an in-game check.
local L = require("dev.spec._ke_loader")

describe("PotionReady gates", function()
    it("passes only when every gate that is on is met", function()
        local PR = L.loadPotionReady()
        local cases = {
            { name = "no gate on", db = {},
              inInstance = false, inCombat = false, isHealer = true, want = true },
            { name = "instances only, outside", db = { InstanceOnly = true },
              inInstance = false, inCombat = true, isHealer = false, want = false },
            { name = "instances only, inside", db = { InstanceOnly = true },
              inInstance = true, inCombat = false, isHealer = false, want = true },
            { name = "in combat only, out of combat", db = { CombatOnly = true },
              inInstance = true, inCombat = false, isHealer = false, want = false },
            { name = "in combat only, in combat", db = { CombatOnly = true },
              inInstance = false, inCombat = true, isHealer = false, want = true },
            { name = "hide for healers, as a healer", db = { DisableOnHealer = true },
              inInstance = true, inCombat = true, isHealer = true, want = false },
            { name = "hide for healers, not a healer", db = { DisableOnHealer = true },
              inInstance = false, inCombat = false, isHealer = false, want = true },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c.want,
                PR.PassesGates(c.db, c.inInstance, c.inCombat, c.isHealer), c.name)
        end
    end)
end)
