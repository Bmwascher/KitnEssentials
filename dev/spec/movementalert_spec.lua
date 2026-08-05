-- Modules/Utilities/NoMovementAlert.lua -- the resolution layer only. The
-- tracking engine, the frames and the event wiring are a verbatim port and are
-- verified in game; what is tested here is the one rule a later edit breaks
-- silently: which spells count as enabled, and for which spec.
local L = require("dev.spec._ke_loader")

describe("movement alert spell resolution", function()
    local NMA, KE

    before_each(function()
        NMA, KE = L.loadMovementAlert()
    end)

    describe("the exported tables", function()
        it("publishes the four names the page needs", function()
            assert.is_table(KE.MOVEMENT_ABILITIES)
            assert.is_table(KE.MOVEMENT_BUFF_ACTIVE)
            assert.is_table(KE.MOVEMENT_DEFAULT_OFF)
            assert.is_function(KE.MOVEMENT_SPELL_KEY)
        end)

        it("keys spell overrides as specID:spellID", function()
            assert.equals("102:1850", KE.MOVEMENT_SPELL_KEY(102, 1850))
        end)

        it("treats a missing spec as spec zero rather than erroring", function()
            assert.equals("0:1850", KE.MOVEMENT_SPELL_KEY(nil, 1850))
        end)
    end)

    describe("effective enable state", function()
        -- SpellEnabled is a file-local, so it is reached through the module's
        -- own resolution rather than called directly. NMA.db is assigned here
        -- the way the module assigns it in UpdateDB.
        local function enabled(db, spellId, specId)
            return NMA:IsSpellEnabled(db, spellId, specId)
        end

        it("counts an untouched preset as on", function()
            assert.is_true(enabled({ Spells = {} }, 102401, 102))
        end)

        it("counts a default-off preset as off when untouched", function()
            -- Dash ships unchecked.
            assert.is_false(enabled({ Spells = {} }, 1850, 102))
        end)

        it("lets an explicit per-spec tick turn a default-off preset on", function()
            local db = { Spells = { ["102:1850"] = { enabled = true } } }
            assert.is_true(enabled(db, 1850, 102))
        end)

        it("lets an explicit per-spec untick turn a default-on preset off", function()
            local db = { Spells = { ["102:102401"] = { enabled = false } } }
            assert.is_false(enabled(db, 102401, 102))
        end)

        it("keeps one spec's choice out of another spec's answer", function()
            local db = { Spells = { ["102:102401"] = { enabled = false } } }
            assert.is_false(enabled(db, 102401, 102))
            assert.is_true(enabled(db, 102401, 103))
        end)

        it("still honours the older account-wide key as a fallback", function()
            local db = { Spells = { ["102401"] = { enabled = false } } }
            assert.is_false(enabled(db, 102401, 102))
        end)

        it("lets a per-spec key win over the older account-wide one", function()
            local db = {
                Spells = {
                    ["102401"] = { enabled = false },
                    ["102:102401"] = { enabled = true },
                },
            }
            assert.is_true(enabled(db, 102401, 102))
            -- The other spec has no per-spec key, so it still reads the old one.
            assert.is_false(enabled(db, 102401, 103))
        end)
    end)

    describe("category duration", function()
        it("returns a listed duration directly", function()
            assert.equals(18, NMA:GetCategoryDuration(1850))
        end)

        it("finds a duration through an alias group when the id has none", function()
            -- 77764 is in Stampeding Roar's alias group and carries no listed
            -- duration of its own; only 106898 and 77761 do. Two mechanisms can
            -- answer: the load-time back-fill that copies a sibling's duration
            -- onto every id in the group, and the group walk inside
            -- CategoryDuration itself. This example does not distinguish them
            -- and does not claim to — it fails only if BOTH are gone, which is
            -- exactly the breakage worth catching, since either one alone is
            -- sufficient and neither is safe to delete blind.
            assert.equals(120, NMA:GetCategoryDuration(77764))
        end)

        it("returns zero for a spell in no group and no table", function()
            assert.equals(0, NMA:GetCategoryDuration(6544))
        end)
    end)
end)
