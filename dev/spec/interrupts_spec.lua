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

    it("builds the kick set from candidates only", function()
        local kicks = KE:GetInterruptKickSpellSet()
        assert.is_true(kicks[96231])   -- Rebuke, a candidate
        assert.is_nil(kicks[31935])    -- Avenger's Shield, an announce extra
    end)

    it("picks the named tracked candidate, else the first, and nil for a spec without a kick", function()
        -- A fixture list, so no data cell is pinned; naming the second and the
        -- third candidate tells the tracked branch from any fixed position.
        local list = { { id = 1, cd = 10 }, { id = 2, cd = 20 }, { id = 3, cd = 30 } }
        local rows = {
            { name = "tracked names the second", tracked = 2, want = 2 },
            { name = "tracked names the third", tracked = 3, want = 3 },
            { name = "no tracked kick", tracked = nil, want = 1 },
            { name = "tracked kick not in the list", tracked = 9, want = 1 },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KE:PickTrackedKick(list, row.tracked).id, row.name)
        end
        assert.is_nil(KE:GetTrackedKickForSpec(105))            -- no kick
    end)
end)
