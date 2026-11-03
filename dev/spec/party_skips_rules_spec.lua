-- Tier 1: the skip bars' pure rule
-- (Modules/AuraTracking/PartyBuffs/PartySkipsRules.lua): whose Shroud the bar
-- reads.
local L = require("dev.spec._ke_loader")

describe("PartySkipsRules.RogueToken", function()
    it("takes you on a rogue, else the first party rogue, and no one without a known rogue", function()
        local R = L.loadPartySkipsRules()
        local cases = {
            { name = "you on a rogue", player = "ROGUE", classes = { "ROGUE", false, false, false },
              want = "player" },
            { name = "first party rogue", player = "WARRIOR", classes = { "MAGE", "ROGUE", false, "ROGUE" },
              want = "party2" },
            { name = "no known rogue", player = false, classes = { false, "PRIEST", false, false },
              want = nil },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.RogueToken(case.player, case.classes), case.name)
        end
    end)
end)
