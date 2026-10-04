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

    it("stays silent for a Warlock without the talent whose Grimoire is readable and present", function()
        local PS, rec = L.loadPetStatusText({
            class = "WARLOCK", specID = AFFLICTION, hasPet = false, aura = { spellId = GRIMOIRE },
            unknownSpells = { [108503] = true },
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

    it("REFUSES to accuse a Warlock without the talent while aura identities are hidden", function()
        -- The defect. The Grimoire search cannot succeed here, so the old code
        -- read its own blindness as proof the pet was missing and said so for
        -- the whole pull. Without the talent, so the Missing branch's own guard
        -- is what refuses; a talent holder returns earlier.
        local PS, rec = L.loadPetStatusText({
            class = "WARLOCK", specID = AFFLICTION, hasPet = false, aurasHidden = true,
            unknownSpells = { [108503] = true },
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

    it("refuses a Warlock without the talent when the exact predicate says the sacrifice aura is secret", function()
        local PS, rec = L.loadPetStatusText({
            class = "WARLOCK", specID = 265, hasPet = false,
            aurasHidden = false, C_Secrets = secrets(true),
            unknownSpells = { [108503] = true },
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

describe("PetStatusText Grimoire of Sacrifice after a death", function()
    it("silences a remembered death only where the sacrifice explains it", function()
        local rows = {
            { name = "buff present after the sacrifice, no pet",
              state = { hasPet = false, petDead = false, aura = { spellId = GRIMOIRE } }, expect = nil },
            { name = "buff present while the dead pet still exists",
              state = { hasPet = true, petDead = true, aura = { spellId = GRIMOIRE } }, expect = nil },
            { name = "buff hidden, no pet, after the death",
              state = { hasPet = false, petDead = false, aurasHidden = true }, expect = nil },
            { name = "buff hidden while the dead pet still exists",
              state = { hasPet = true, petDead = true, aurasHidden = true }, expect = "PET DEAD" },
            { name = "buff absent after a real death",
              state = { hasPet = false, petDead = false }, expect = "PET DEAD" },
            { name = "talent not known, buff hidden, no pet, after the death",
              state = { hasPet = false, petDead = false, aurasHidden = true, unknownSpells = { [108503] = true } },
              expect = "PET DEAD" },
        }
        for _, row in ipairs(rows) do
            local overrides = {
                class = "WARLOCK", specID = AFFLICTION, hasPet = true, petDead = true,
                db = {
                    Enabled = true,
                    PetMissing = "PET MISSING", MissingColor = { 1, 1, 1, 1 },
                    PetDead = "PET DEAD", DeadColor = { 1, 1, 1, 1 },
                },
            }
            local PS, rec = L.loadPetStatusText(overrides)
            PS:UpdatePetText()
            assert.equal("PET DEAD", rec.text, row.name .. ": the real death is painted first")

            for key, value in pairs(row.state) do overrides[key] = value end
            rec.text = nil
            PS:UpdatePetText()
            assert.equal(row.expect, rec.text, row.name)
            assert.equal(row.expect ~= nil, rec.shown, row.name)
        end
    end)
end)

describe("Demonology expected pet", function()
    it("expects the pet each context calls for", function()
        local PS = L.loadPetStatusText()
        local FELHUNTER, FELGUARD, IMP = 417, 17252, 416
        local rows = {
            { FELHUNTER, "key", true },
            { FELGUARD, "key", false },
            { FELGUARD, "other", true },
            { FELHUNTER, "other", false },
            { FELHUNTER, "mythicIdle", true },
            { FELGUARD, "mythicIdle", true },
            { IMP, "mythicIdle", false },
            { nil, "key", nil },
            { nil, "mythicIdle", nil },
            { nil, "other", nil },
            { FELHUNTER, "world", nil },
            { FELGUARD, "world", nil },
            { IMP, "world", nil },
        }
        for _, r in ipairs(rows) do
            assert.equals(r[3], PS.DemoPetExpected(r[1], r[2]), tostring(r[1]) .. " in " .. r[2])
        end
    end)
end)
