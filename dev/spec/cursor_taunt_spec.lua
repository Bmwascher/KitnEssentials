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

    describe("tank gate", function()
        it("activates on a tank spec", function()
            local C = loader.loadCursor({
                GetSpecializationRole = function() return "TANK" end,
                C_SpellBook = { IsSpellInSpellBook = function(id) return id == 355 end },
            })
            C:_TauntEvaluateGate()
            assert.is_true(C._tauntActive)
        end)

        it("stays inactive on a damage spec", function()
            local C = loader.loadCursor({
                GetSpecializationRole = function() return "DAMAGER" end,
                C_SpellBook = { IsSpellInSpellBook = function(id) return id == 355 end },
            })
            C:_TauntEvaluateGate()
            assert.is_false(C._tauntActive)
        end)

        it("deactivates when the player swaps off a tank spec", function()
            local role = "TANK"
            local C = loader.loadCursor({
                GetSpecializationRole = function() return role end,
                C_SpellBook = { IsSpellInSpellBook = function(id) return id == 355 end },
            })
            C:_TauntEvaluateGate()
            assert.is_true(C._tauntActive)
            role = "HEALER"
            C:_TauntEvaluateGate()
            assert.is_false(C._tauntActive)
        end)
    end)

    describe("repaired paths", function()
        it("re-resolves the spell when the spellbook populates late", function()
            local ready = false
            local C, _, seams = loader.loadCursor({
                C_SpellBook = {
                    IsSpellInSpellBook = function(id) return ready and id == 6795 end,
                },
            })
            C:_TauntFindSpell()
            assert.is_nil(C._tauntTrackedSpellID)
            ready = true
            -- A REAL frame is required: after re-resolving, the handler falls
            -- through to the cooldown branch and calls self.cooldown:Clear().
            -- Passing a bare table errors there instead of asserting.
            C:CreateTauntSatellite()

            -- Pin the REGISTRATION as well as the handler branch. Invoking the
            -- seam directly proves the branch works but would still pass if
            -- _AttachTauntScripts never registered the event, leaving the whole
            -- path dead in game.
            local registered = {}
            C.tauntFrame.RegisterEvent = function(_, ev) registered[ev] = true end
            C:_AttachTauntScripts()
            assert.is_true(registered["SPELLS_CHANGED"])

            seams.tauntOnEvent(C.tauntFrame, "SPELLS_CHANGED")
            assert.equals(6795, C._tauntTrackedSpellID)
        end)

        it("renders the current cooldown as soon as the satellite applies", function()
            local applied = 0
            local C = loader.loadCursor({
                C_SpellBook = { IsSpellInSpellBook = function(id) return id == 355 end },
                C_Spell = {
                    GetSpellCooldown = function() return nil end,
                    GetSpellCooldownDuration = function() return { fake = true } end,
                },
            })
            C.db.Taunt.Enabled = true
            C:CreateTauntSatellite()
            C.tauntFrame.cooldown.SetCooldownFromDurationObject = function()
                applied = applied + 1
            end
            C.tauntFrame.cooldown.Clear = function() end
            C:ApplyTauntSatellite()
            assert.is_true(applied > 0)
        end)

        it("does not let an older preview callback clear a newer preview", function()
            local pending = {}
            local C = loader.loadCursor({
                C_Timer = {
                    After = function(_, fn) pending[#pending + 1] = fn end,
                    NewTicker = function() return { Cancel = function() end } end,
                    NewTimer = function() return { Cancel = function() end } end,
                },
            })
            C:TauntPreview()
            C:TauntPreview()
            assert.equals(2, #pending)
            pending[1]()                              -- the stale one fires
            assert.is_true(C._tauntPreviewActive)     -- newer preview survives
        end)

        it("ignores a preview callback that lands after disable", function()
            local pending = {}
            local C = loader.loadCursor({
                C_Timer = {
                    After = function(_, fn) pending[#pending + 1] = fn end,
                    NewTicker = function() return { Cancel = function() end } end,
                    NewTimer = function() return { Cancel = function() end } end,
                },
            })
            -- The addon shim returns a bare module table with no AceEvent
            -- methods, and OnDisable ends by calling UnregisterAllEvents.
            C.UnregisterAllEvents = function() end
            C:TauntPreview()
            assert.equals(1, #pending)
            C:OnDisable()
            -- Count gate calls rather than reading _tauntActive. The loader
            -- defaults to a TANK role, so a wrongly-executed callback would run
            -- the gate's tank branch and SET _tauntActive true -- making an
            -- is_true assertion pass on both the correct and the broken path.
            local gateCalls = 0
            C._TauntEvaluateGate = function() gateCalls = gateCalls + 1 end
            pending[1]()
            assert.equals(0, gateCalls)
        end)
    end)
end)
