local L = require("dev.spec._ke_loader")

local GRIMOIRE = 196099

-- Spec IDs that are NOT the two CheckPetStatus branches on: 254 is MM Hunter
-- (pet-replacing talents) and 266 is Demo Warlock (the Felguard check). Using
-- any other id keeps a case on the plain Dead/Passive/Missing path.
local AFFLICTION = 265
local BEAST_MASTERY = 253

describe("PetStatusText missing-pet verdict", function()
    it("accuses a Warlock with no pet and no Grimoire while identities are readable", function()
        -- Positive control. Without it, an implementation that never accuses
        -- anyone would pass every refusal case below.
        local PS, rec = L.loadPetStatusText({ class = "WARLOCK", specID = AFFLICTION, hasPet = false })
        PS:UpdatePetText()
        assert.equal("PET MISSING", rec.text)
        assert.is_true(rec.shown)
    end)

    it("stays silent for a Warlock whose Grimoire is readable and present", function()
        local PS, rec = L.loadPetStatusText({
            class = "WARLOCK", specID = AFFLICTION, hasPet = false, aura = { spellId = GRIMOIRE },
        })
        PS:UpdatePetText()
        assert.is_nil(rec.text)
        assert.is_false(rec.shown)
    end)

    it("says nothing when the pet is alive", function()
        local PS, rec = L.loadPetStatusText({ class = "WARLOCK", specID = AFFLICTION, hasPet = true })
        PS:UpdatePetText()
        assert.is_nil(rec.text)
        assert.is_false(rec.shown)
    end)

    it("REFUSES to accuse a Warlock while aura identities are hidden", function()
        -- The defect. The Grimoire search cannot succeed here, so the old code
        -- read its own blindness as proof the pet was missing and said so for
        -- the whole pull.
        local PS, rec = L.loadPetStatusText({
            class = "WARLOCK", specID = AFFLICTION, hasPet = false, aurasHidden = true,
        })
        PS:UpdatePetText()
        assert.is_nil(rec.text)
        assert.is_false(rec.shown)
    end)

    it("still accuses a HUNTER while identities are hidden", function()
        -- The class-scope control, and the reason the guard is not blanket. No
        -- Hunter can be holding Grimoire, so the unreadable aura is irrelevant
        -- to them and their warning must survive the fix.
        local PS, rec = L.loadPetStatusText({
            class = "HUNTER", specID = BEAST_MASTERY, hasPet = false, aurasHidden = true,
        })
        PS:UpdatePetText()
        assert.equal("PET MISSING", rec.text)
        assert.is_true(rec.shown)
    end)

end)

describe("pet status per-spell secrecy", function()
    local function secrets(spellSecret)
        return { ShouldSpellAuraBeSecret = function() return spellSecret end,
                 ShouldAurasBeSecret = function() return true end }
    end

    it("refuses when the exact predicate says the sacrifice aura is secret", function()
        local PS, rec = L.loadPetStatusText({
            class = "WARLOCK", specID = 265, hasPet = false,
            aurasHidden = false, C_Secrets = secrets(true),
        })
        PS:UpdatePetText()
        assert.is_false(rec.shown)
    end)

    it("does NOT refuse when the exact predicate says it is readable, even though the broad state says hidden", function()
        local PS, rec = L.loadPetStatusText({
            class = "WARLOCK", specID = 265, hasPet = false,
            aurasHidden = true, C_Secrets = secrets(false),
        })
        PS:UpdatePetText()
        assert.is_true(rec.shown)
    end)
end)
