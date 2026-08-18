local loader = require("dev.spec._ke_loader")

local EBON_MIGHT_SELF   = 395296
local EBON_MIGHT_OTHERS = 395152
local SELF_NAME   = "Spell " .. EBON_MIGHT_SELF
local OTHERS_NAME = "Spell " .. EBON_MIGHT_OTHERS

-- Drives KE:IsAuraHiddenForSpell's per-spell answer from a name-keyed table,
-- matching how the guarded scan queries -- by name, not id. The broad answer
-- stays false throughout so it cannot explain any result here.
local function secrecy(inGroup, hiddenNames)
    return {
        inGroup = inGroup,
        aurasHidden = false,
        C_Secrets = {
            ShouldSpellAuraBeSecret = function(name) return hiddenNames[name] == true end,
        },
    }
end

describe("EbonMightTracker aura scan gate", function()
    it("scans solo when the self spell is readable", function()
        local EMT = loader.loadEbonMightTracker(secrecy(false, {}))
        assert.is_true(EMT:CanScanAllEbonMightSpells())
    end)

    it("refuses solo when the self spell is hidden", function()
        local EMT = loader.loadEbonMightTracker(secrecy(false, { [SELF_NAME] = true }))
        assert.is_false(EMT:CanScanAllEbonMightSpells())
    end)

    it("scans grouped when both the self and allies spells are readable", function()
        local EMT = loader.loadEbonMightTracker(secrecy(true, {}))
        assert.is_true(EMT:CanScanAllEbonMightSpells())
    end)

    it("refuses grouped when the self spell is readable but the allies spell is hidden -- scanning here would clear the ally list and rebuild nothing into it", function()
        local EMT = loader.loadEbonMightTracker(secrecy(true, { [OTHERS_NAME] = true }))
        assert.is_false(EMT:CanScanAllEbonMightSpells())
    end)

    it("refuses when the self spell has no resolved name", function()
        local EMT = loader.loadEbonMightTracker({
            inGroup = false,
            aurasHidden = false,
            C_Spell = {
                GetSpellName = function(id)
                    if id == EBON_MIGHT_SELF then return nil end
                    return "Spell " .. tostring(id)
                end,
            },
        })
        assert.is_false(EMT:CanScanAllEbonMightSpells())
    end)
end)
