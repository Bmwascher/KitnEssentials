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

        it("finds Flame Shock on Elemental", function()
            local C = loader.loadCursor({
                GetSpecializationInfo = function() return 262 end,
                C_SpellBook = {
                    IsSpellInSpellBook = function(id) return id == 188389 end,
                },
            })
            C:_TauntFindSpell()
            assert.equals(188389, C._tauntTrackedSpellID)
        end)

        it("ignores Flame Shock on Enhancement", function()
            local C = loader.loadCursor({
                GetSpecializationInfo = function() return 263 end,
                C_SpellBook = {
                    IsSpellInSpellBook = function(id) return id == 188389 end,
                },
            })
            C:_TauntFindSpell()
            assert.is_nil(C._tauntTrackedSpellID)
        end)

        it("finds Garrote on Assassination", function()
            local C = loader.loadCursor({
                GetSpecializationInfo = function() return 259 end,
                C_SpellBook = {
                    IsSpellInSpellBook = function(id) return id == 703 end,
                },
            })
            C:_TauntFindSpell()
            assert.equals(703, C._tauntTrackedSpellID)
        end)

        it("ignores Garrote on Outlaw", function()
            local C = loader.loadCursor({
                GetSpecializationInfo = function() return 260 end,
                C_SpellBook = {
                    IsSpellInSpellBook = function(id) return id == 703 end,
                },
            })
            C:_TauntFindSpell()
            assert.is_nil(C._tauntTrackedSpellID)
        end)

        it("finds a taunt on a damage spec of a class that has one", function()
            -- Retribution Paladin. The old role gate is what this pins:
            -- Hand of Reckoning is in the spellbook, and the spec is not a tank.
            local C = loader.loadCursor({
                GetSpecializationInfo = function() return 70 end,
                C_SpellBook = {
                    IsSpellInSpellBook = function(id) return id == 62124 end,
                },
            })
            C:_TauntFindSpell()
            assert.equals(62124, C._tauntTrackedSpellID)
        end)

        it("follows a talent override to the live spell id", function()
            -- The base id is absent from the book; only the replacement is
            -- there, which is what carries the cooldown.
            --
            -- 999999 is a synthetic override target, deliberately. Every REAL
            -- override target in TRACKED_SPELLS is also listed as a plain id
            -- beside its base (470411 sits next to 188389), so asserting on one
            -- would pass against an implementation that never resolved an
            -- override at all -- the plain-id loop would reach it anyway. An id
            -- reachable ONLY through the override lookup is the only version of
            -- this test that can fail.
            local C = loader.loadCursor({
                C_SpellBook = {
                    FindSpellOverrideByID = function(id)
                        if id == 355 then return 999999 end
                        return id
                    end,
                    IsSpellInSpellBook = function(id) return id == 999999 end,
                },
            })
            C:_TauntFindSpell()
            assert.equals(999999, C._tauntTrackedSpellID)
        end)

        it("falls back to the plain id when the override lookup misses", function()
            -- FindSpellOverrideByID answering something not in the book must
            -- not shadow a base id that is.
            local C = loader.loadCursor({
                C_SpellBook = {
                    FindSpellOverrideByID = function() return 999999 end,
                    IsSpellInSpellBook = function(id) return id == 355 end,
                },
            })
            C:_TauntFindSpell()
            assert.equals(355, C._tauntTrackedSpellID)
        end)
    end)

    describe("spellbook gate", function()
        it("activates when the spellbook has a tracked spell", function()
            local C = loader.loadCursor({
                C_SpellBook = { IsSpellInSpellBook = function(id) return id == 355 end },
            })
            C:_TauntEvaluateGate()
            assert.is_true(C._tauntActive)
        end)

        it("stays inactive when the spellbook has none", function()
            local C = loader.loadCursor({
                C_SpellBook = { IsSpellInSpellBook = function() return false end },
            })
            C:_TauntEvaluateGate()
            assert.is_false(C._tauntActive)
        end)

        it("activates on a damage spec that knows a taunt", function()
            -- Retribution Paladin: the case the old role gate refused.
            local C = loader.loadCursor({
                GetSpecializationInfo = function() return 70 end,
                C_SpellBook = { IsSpellInSpellBook = function(id) return id == 62124 end },
            })
            C:_TauntEvaluateGate()
            assert.is_true(C._tauntActive)
        end)

        it("deactivates when a spec swap loses the spell", function()
            local known = 703
            local C = loader.loadCursor({
                GetSpecializationInfo = function() return 259 end,
                C_SpellBook = { IsSpellInSpellBook = function(id) return id == known end },
            })
            C:_TauntEvaluateGate()
            assert.is_true(C._tauntActive)
            known = nil
            C:_TauntEvaluateGate()
            assert.is_false(C._tauntActive)
        end)

        it("deactivates when a spec swap makes the spell not want the cursor", function()
            -- Assassination to Outlaw. Garrote is still in the spellbook; the
            -- spec list is the only thing that can turn this off, so a gate
            -- that only asked the spellbook would wrongly stay active.
            local spec = 259
            local C = loader.loadCursor({
                GetSpecializationInfo = function() return spec end,
                C_SpellBook = { IsSpellInSpellBook = function(id) return id == 703 end },
            })
            C:_TauntEvaluateGate()
            assert.is_true(C._tauntActive)
            spec = 260
            C:_TauntEvaluateGate()
            assert.is_false(C._tauntActive)
        end)
    end)

    describe("repaired paths", function()
        it("re-resolves the spell when the spellbook populates late", function()
            local ready = false
            local C = loader.loadCursor({
                C_SpellBook = {
                    IsSpellInSpellBook = function(id) return ready and id == 6795 end,
                },
            })
            C:_TauntEvaluateGate()
            assert.is_false(C._tauntActive)
            ready = true
            C.UpdateVisibility = function() end
            C:_TauntSpellsChanged()
            assert.equals(6795, C._tauntTrackedSpellID)
            assert.is_true(C._tauntActive)
        end)

        it("keeps the spellbook listener alive while gated off", function()
            -- The regression this whole restructure exists to prevent: if the
            -- gate-in event were registered on the satellite frame, the
            -- inactive gate's _DetachTauntScripts would unregister it and the
            -- feature could never come back.
            local C = loader.loadCursor({
                C_SpellBook = { IsSpellInSpellBook = function() return false end },
            })
            -- Every stub OnEnable needs, given literally. The loader's noop
            -- frame returns nil from CreateTexture, so CreateCursorFrame
            -- cannot run here; these five replace exactly what it touches.
            local registered, unregistered = {}, {}
            C.cursorFrame = { SetScript = function() end }
            C.CreateCursorFrame = function() end
            C.ApplyCursorSettings = function() end
            C.UpdateVisibility = function() end
            C.RegisterEvent = function(_, ev, handler) registered[ev] = handler end
            C.UnregisterEvent = function(_, ev) unregistered[ev] = true end

            -- A tauntFrame MUST exist, or the negative gate skips its whole
            -- `if self.tauntFrame` teardown branch and this test proves
            -- nothing: the detachment it is supposed to survive never runs.
            -- The frame's teardown calls are RECORDED, not swallowed. Stubbed
            -- as no-ops, a gate that merely set _tauntActive = false without
            -- tearing the satellite down would satisfy every assertion below,
            -- and this test would prove only half of what it claims.
            local frameUnregisterAll, frameHidden = 0, 0
            C.tauntFrame = {
                UnregisterAllEvents = function() frameUnregisterAll = frameUnregisterAll + 1 end,
                SetScript = function() end,
                Hide = function() frameHidden = frameHidden + 1 end,
                cooldown = { Clear = function() end },
            }

            C:OnEnable()
            -- The HANDLER NAME, not merely that something was registered: a
            -- registration pointing at the wrong method would satisfy a
            -- truthiness check and still be dead.
            assert.equals("_TauntSpellsChanged", registered["SPELLS_CHANGED"])

            C:_TauntEvaluateGate()
            assert.is_false(C._tauntActive)
            -- The satellite really was torn down...
            assert.is_true(frameUnregisterAll > 0)
            assert.is_true(frameHidden > 0)
            -- ...and the MODULE listener survived that teardown. Only the two
            -- together are the regression this restructure exists to prevent.
            assert.is_nil(unregistered["SPELLS_CHANGED"])
            assert.equals("_TauntSpellsChanged", registered["SPELLS_CHANGED"])
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
            C:_TauntEvaluateGate()
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
            -- Count gate calls rather than reading _tauntActive. The flag's
            -- value is not the question here; whether the orphaned callback
            -- ran at all is, and only a call count answers that.
            local gateCalls = 0
            C._TauntEvaluateGate = function() gateCalls = gateCalls + 1 end
            pending[1]()
            assert.equals(0, gateCalls)
        end)
    end)
end)
