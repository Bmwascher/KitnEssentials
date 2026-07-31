local loader = require("dev.spec._ke_loader")

describe("Cursor module", function()
    it("loads in the spec harness", function()
        local C = loader.loadCursor()
        assert.is_table(C)
        assert.is_table(C.db)
        assert.is_table(C.db.Taunt)
    end)

    describe("taunt spell lookup", function()
        it("selects the taunt present in the spellbook", function()
            local C = loader.loadCursor({
                C_SpellBook = {
                    IsSpellInSpellBook = function(id) return id == 115546 end,
                },
            })
            C:_TauntFindSpell()
            assert.equals(115546, C._tauntTrackedSpellID)
        end)

        it("selects nil when the character has no taunt", function()
            local C = loader.loadCursor({
                C_SpellBook = {
                    IsSpellInSpellBook = function() return false end,
                },
            })
            C:_TauntFindSpell()
            assert.is_nil(C._tauntTrackedSpellID)
        end)

        it("clears a stale tracked spell on re-lookup", function()
            local present = true
            local C = loader.loadCursor({
                C_SpellBook = {
                    IsSpellInSpellBook = function(id) return present and id == 355 end,
                },
            })
            C:_TauntFindSpell()
            assert.equals(355, C._tauntTrackedSpellID)
            present = false
            C:_TauntFindSpell()
            assert.is_nil(C._tauntTrackedSpellID)
        end)
    end)
end)
