-- Which states let the aggro line show. The combat, spec, instance and threat
-- reads that feed it are WoW calls and stay an in-game check.
local L = require("dev.spec._ke_loader")

describe("Combat Texts aggro rule", function()
    it("shows only in combat, off a tank spec, inside the gate, on a plain status of 2 or more", function()
        local CM = L.loadCombatTexts()
        local rows = {
            { name = "status 2, every gate met", db = {},
              inCombat = true, isTank = false, inInstance = true, threat = 2, secret = false, want = true },
            { name = "status 1", db = {},
              inCombat = true, isTank = false, inInstance = true, threat = 1, secret = false, want = false },
            { name = "no reading", db = {},
              inCombat = true, isTank = false, inInstance = true, threat = nil, secret = false, want = false },
            { name = "secret reading", db = {},
              inCombat = true, isTank = false, inInstance = true, threat = 2, secret = true, want = false },
            { name = "out of combat", db = {},
              inCombat = false, isTank = false, inInstance = true, threat = 2, secret = false, want = false },
            { name = "tank spec", db = {},
              inCombat = true, isTank = true, inInstance = true, threat = 2, secret = false, want = false },
            { name = "instances only, outside", db = { AggroInstanceOnly = true },
              inCombat = true, isTank = false, inInstance = false, threat = 2, secret = false, want = false },
            { name = "instances only off, outside", db = { AggroInstanceOnly = false },
              inCombat = true, isTank = false, inInstance = false, threat = 2, secret = false, want = true },
            { name = "line disabled", db = { AggroEnabled = false },
              inCombat = true, isTank = false, inInstance = true, threat = 2, secret = false, want = false },
        }
        for _, c in ipairs(rows) do
            assert.are.equal(c.want,
                CM.ShouldShowAggro(c.db, c.inCombat, c.isTank, c.inInstance, c.threat, c.secret), c.name)
        end
    end)
end)
