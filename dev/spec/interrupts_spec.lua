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

    it("gives a tracker-only kick to the tracker, never the castbar candidates (Balance Druid 102)", function()
        -- Expected values are read through the accessors, so no data cell is
        -- pinned.
        assert.is_nil(KE:GetInterruptCandidatesForSpec(102))
        local kick = KE:GetTrackedKickForSpec(102)
        assert.is_not_nil(kick)
        assert.equals(kick.cd, KE:GetKickCooldownForSpec(102, kick.id))
        assert.equals(kick.cd, KE:GetKickCooldownCap(kick.id))
        assert.is_true(KE:GetInterruptKickSpellSet()[kick.id])
        assert.is_true(KE:GetInterruptSpellSet(102)[kick.id])
    end)

    it("builds the kick set from kicks, never announce extras", function()
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

    it("finds a kick's cooldown for a spec, and nil for a kick it lacks", function()
        -- The expected cd is read from the spec's own Axe Toss entry, so no
        -- data cell is pinned.
        local axeToss
        for _, c in ipairs(KE:GetInterruptCandidatesForSpec(266)) do
            if c.id == 89766 then axeToss = c end
        end
        assert.is_not_nil(axeToss)
        assert.equals(axeToss.cd, KE:GetKickCooldownForSpec(266, 89766))
        assert.is_nil(KE:GetKickCooldownForSpec(71, 19647))       -- a warrior has no Spell Lock
    end)

    it("caps a kick at its largest table cooldown, extra kicks included", function()
        -- Expected values are read through the accessors, so no data cell is
        -- pinned. Wind Shear's cd differs by shaman spec, so "largest" is tested.
        local windShearMax = 0
        for _, specID in ipairs({ 262, 263, 264 }) do
            for _, c in ipairs(KE:GetInterruptCandidatesForSpec(specID) or {}) do
                if c.id == 57994 and c.cd > windShearMax then windShearMax = c.cd end
            end
        end
        assert.is_true(windShearMax > 0)
        assert.equals(windShearMax, KE:GetKickCooldownCap(57994))
        assert.equals(KE:GetExtraKick(64382).cd, KE:GetKickCooldownCap(64382))  -- Shattering Throw
        assert.is_nil(KE:GetKickCooldownCap(1))
    end)
end)
