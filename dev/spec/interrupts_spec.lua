-- Tier 1: pure data + accessors, zero WoW API. Core/Interrupts.lua.
local helpers = require("dev.spec._helpers")

describe("Interrupts (Core/Interrupts.lua)", function()
    local KE
    setup(function()
        KE = helpers.loadModule("Core/Interrupts.lua")
    end)

    it("returns the primary kick for Frost DK (spec 251)", function()
        local list = KE:GetInterruptCandidatesForSpec(251)
        assert.is_table(list)
        assert.equals(47528, list[1].id) -- Mind Freeze
        assert.equals(12, list[1].cd)
    end)

    it("normalizes a single primary into a one-entry candidate list", function()
        local list = KE:GetInterruptCandidatesForSpec(259) -- Assassination Rogue, Kick
        assert.equals(1, #list)
        assert.equals(1766, list[1].id)
    end)

    it("keeps warlock pet candidates in priority order", function()
        local list = KE:GetInterruptCandidatesForSpec(265) -- Affliction
        assert.equals(4, #list)
        assert.equals(19647, list[1].id) -- Spell Lock first
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

    it("returns nil for an unknown spec", function()
        assert.is_nil(KE:GetInterruptCandidatesForSpec(99999))
        assert.is_nil(KE:GetInterruptSpellSet(99999))
    end)
end)
