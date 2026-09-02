-- Tier 1: pure data + accessors, zero WoW API. Core/Interrupts.lua.
local helpers = require("dev.spec._helpers")

describe("Interrupts (Core/Interrupts.lua)", function()
    local KE
    setup(function()
        KE = helpers.loadModule("Core/Interrupts.lua")
    end)

    it("builds an announce set including announceExtras", function()
        local set = KE:GetInterruptSpellSet(66) -- Prot Paladin
        assert.is_true(set[96231]) -- Rebuke (primary)
        assert.is_true(set[31935]) -- Avenger's Shield (announceExtra)
        assert.is_true(set[375576])
    end)

    it("handles a spec with no single-target kick (Balance Druid 102)", function()
        -- primary = nil, only an announce extra (Solar Beam) -> empty candidate list
        assert.is_nil(KE:GetInterruptCandidatesForSpec(102))
        local set = KE:GetInterruptSpellSet(102)
        assert.is_true(set[78675])
    end)
end)
