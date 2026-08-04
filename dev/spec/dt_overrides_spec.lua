-- Tier 2: DungeonTimers override precedence + accessor surface — the pure
-- db-table logic behind the per-spell/per-phase GUI (show-at chain, clear-on-
-- default setters, curator-vs-user disable, role gating, phase rule keys,
-- override bookkeeping). Modules/DungeonTimers/DungeonTimers.lua loads for
-- real via L.loadDungeonTimers(); DT is a file-local handed back through the
-- addon-shim registry. All override state is driven through the public
-- Set*/Reset* accessors — a raw write to a mistyped db key silently no-ops
-- (every getter nil-guards its table) and would green-wash the spec.
local L = require("dev.spec._ke_loader")

describe("DungeonTimers override accessors", function()
    local DT, KE

    before_each(function()
        DT, KE = L.loadDungeonTimers()
        -- Fixture encounter: one spell per curated role, plus curated-disabled
        -- (222), curated-showAt bar-mode (111), and untagged (555) entries.
        -- Installed on the module's live KE.EncounterData table, then the
        -- lookup is built explicitly so no accessor sees a stale cache.
        KE.EncounterData[9001] = {
            name = "Fixture Boss",
            dungeon = "FIX",
            spells = {
                [111] = { role = "tank", display = "bar", displayText = "TANK", showAtSeconds = 12 },
                [222] = { role = "heal", disabled = true },
                [333] = { role = "kick" },
                [444] = { role = "move" },
                [555] = {},                                  -- untagged; no curator showAt; display defaults to "text"
                [666] = { role = "mechanic" },
                [777] = { role = "other", display = "bar" }, -- bar-mode group-default path
            },
            phases = {
                { unit = "boss1", threshold = 70, lead = 5 },
                { unit = "boss1", threshold = 30, lead = 5 },
            },
        }
        DT:BuildSpellLookup()
        -- In-game wiring: DT:UpdateDB derives DT.db from KE.db.profile.DungeonTimers.
        -- BarGroup/TextGroup ShowAtSeconds are the group-level effective defaults
        -- SetSpellShowAtOverride falls back to for uncurated spells (:698-700).
        KE.db = { profile = { DungeonTimers = {
            BarGroup  = { ShowAtSeconds = 5 },
            TextGroup = { ShowAtSeconds = 7 },
        } } }
        DT:UpdateDB()
    end)

    describe("GetSpellShowAtSeconds precedence", function()
        it("returns the curator showAtSeconds when no override is stored", function()
            assert.equals(12, DT:GetSpellShowAtSeconds(111))
        end)

        it("a stored user override beats the curator value", function()
            DT:SetSpellShowAtOverride(111, 20)
            assert.equals(20, DT:GetSpellShowAtSeconds(111))
        end)

        it("an explicit 0 override beats the truthy-test fallback (:674 rule)", function()
            -- 0 means "always visible"; a naive `override or curator` refactor
            -- would silently resurrect the curator's 12 here.
            DT:SetSpellShowAtOverride(111, 0)
            assert.equals(0, DT:GetSpellShowAtSeconds(111))
        end)

        it("returns nil when neither an override nor a curator value exists", function()
            assert.is_nil(DT:GetSpellShowAtSeconds(555))
        end)
    end)

    describe("clear-on-default setters", function()
        it("SetSpellShowAtOverride stores nothing when the value equals the curator default", function()
            DT:SetSpellShowAtOverride(111, 12)
            assert.is_nil(DT:GetSpellShowAtOverride(111))
            assert.is_false(DT:HasSpellOverrides(111))
            assert.equals(12, DT:GetSpellShowAtSeconds(111))  -- effective unchanged via curator
        end)

        it("uncurated spells prune against the display-mode group ShowAtSeconds", function()
            -- text-mode 555 → TextGroup (7); bar-mode 777 → BarGroup (5).
            DT:SetSpellShowAtOverride(555, 7)
            assert.is_nil(DT:GetSpellShowAtOverride(555))
            DT:SetSpellShowAtOverride(555, 9)
            assert.equals(9, DT:GetSpellShowAtOverride(555))
            DT:SetSpellShowAtOverride(777, 5)
            assert.is_nil(DT:GetSpellShowAtOverride(777))
            DT:SetSpellShowAtOverride(777, 6)
            assert.equals(6, DT:GetSpellShowAtOverride(777))
        end)

        it("a display override flips which group default the prune compares against", function()
            -- GetSpellDisplay honors SpellDisplayOverrides, so switching 555 to
            -- bar mode makes BarGroup (5) the effective default, not TextGroup (7).
            DT:SetSpellDisplayOverride(555, "bar")
            DT:SetSpellShowAtOverride(555, 5)
            assert.is_nil(DT:GetSpellShowAtOverride(555))
            DT:SetSpellShowAtOverride(555, 7)
            assert.equals(7, DT:GetSpellShowAtOverride(555))
        end)

        it("falls to 0 as the effective default when the group config has no ShowAtSeconds", function()
            DT.db.TextGroup.ShowAtSeconds = nil
            DT:SetSpellShowAtOverride(555, 0)
            assert.is_nil(DT:GetSpellShowAtOverride(555))
            DT:SetSpellShowAtOverride(555, 3)
            assert.equals(3, DT:GetSpellShowAtOverride(555))
        end)

        it("GetSpellDecimalThreshold defaults to 30 when untouched", function()
            assert.equals(30, DT:GetSpellDecimalThreshold(111))
        end)

        it("SetSpellDecimalThreshold stores a deviation and clears it at the default", function()
            DT:SetSpellDecimalThreshold(111, 10)
            assert.equals(10, DT:GetSpellDecimalThreshold(111))
            assert.is_true(DT:HasSpellOverrides(111))
            DT:SetSpellDecimalThreshold(111, 30)  -- DECIMAL_THRESHOLD_DEFAULT (:185)
            assert.equals(30, DT:GetSpellDecimalThreshold(111))
            assert.is_false(DT:HasSpellOverrides(111))
            -- The setter created this table itself; the key must be gone, not false.
            assert.is_nil(next(DT.db.SpellDecimalThresholds))
        end)

        it("SetSpellDisplayTextOverride prunes preset-equivalent and blank input", function()
            -- "tank" and curator "TANK" resolve to the same preset → no override.
            DT:SetSpellDisplayTextOverride(111, "tank")
            assert.is_nil(DT:GetSpellDisplayTextOverride(111))
            DT:SetSpellDisplayTextOverride(111, "   ")
            assert.is_nil(DT:GetSpellDisplayTextOverride(111))
            DT:SetSpellDisplayTextOverride(111, "CUSTOM")
            assert.equals("CUSTOM", DT:GetSpellDisplayTextOverride(111))
            assert.equals("CUSTOM", DT:GetSpellDisplayText(111))
        end)
    end)

    describe("IsSpellDisabled / ShouldShowSpell", function()
        it("curator disabled=true holds until the user stores an explicit false", function()
            assert.is_true(DT:IsSpellDisabled(222))
            DT:SetSpellDisabled(222, false)
            assert.is_false(DT:IsSpellDisabled(222))
            assert.is_false(DT.db.SpellDisabled[222])  -- stored explicitly, not pruned
        end)

        it("SetSpellDisabled prunes when the value equals curated, in both directions", function()
            DT:SetSpellDisabled(222, true)   -- matches curated disabled=true
            assert.is_nil(next(DT.db.SpellDisabled))
            assert.is_true(DT:IsSpellDisabled(222))   -- still true via curator fallthrough
            DT:SetSpellDisabled(111, false)  -- matches curated enabled
            assert.is_nil(next(DT.db.SpellDisabled))
            assert.is_false(DT:IsSpellDisabled(111))
        end)

        it("ShouldShowSpell is false for a disabled spell regardless of role filter", function()
            assert.is_false(DT:ShouldShowSpell(222))
            DT.db.RoleFilterEnabled = true  -- plain settings flag read at :742 (no accessor)
            assert.is_false(DT:ShouldShowSpell(222))
        end)

        it("role filter off passes role-mismatched spells", function()
            -- Default playerRole is DAMAGER (:716); tank spell passes anyway.
            assert.is_true(DT:ShouldShowSpell(111))
        end)

        it("role filter on composes the LibSpec-reported role", function()
            DT.db.RoleFilterEnabled = true
            assert.is_false(DT:ShouldShowSpell(111))  -- tank spell hidden from DAMAGER
            DT:OnLibSpecGroupUpdate(nil, "TANK", nil, UnitName("player"))
            assert.is_true(DT:ShouldShowSpell(111))
            -- Another player's spec update must not move our role.
            DT:OnLibSpecGroupUpdate(nil, "HEALER", nil, "SomeoneElse")
            assert.is_true(DT:ShouldShowSpell(111))
        end)

        it("nil and unknown spellIds resolve to safe defaults", function()
            assert.is_false(DT:IsSpellDisabled(nil))
            assert.is_false(DT:IsSpellDisabled(99999))  -- uncurated → curator false
            assert.is_true(DT:ShouldShowSpell(99999))
        end)
    end)

    describe("phase rule keys", function()
        it("round-trips Make → Parse → Is", function()
            local key = DT:MakePhaseRuleKey(9001, 2)
            assert.equals("phase:9001:2", key)
            local enc, idx = DT:ParsePhaseRuleKey(key)
            assert.equals(9001, enc)
            assert.equals(2, idx)
            assert.is_true(DT:IsPhaseRuleKey(key))
        end)

        it("MakePhaseRuleKey requires both ids", function()
            assert.is_nil(DT:MakePhaseRuleKey(nil, 1))
            assert.is_nil(DT:MakePhaseRuleKey(9001, nil))
        end)

        it("rejects malformed string keys", function()
            local bad = {
                "phase:9001",   -- missing rule index
                "phase:9001:",  -- empty index
                "phase:a:2",    -- non-numeric encounter
                "phase:1:2:3",  -- trailing segment ($-anchored pattern)
                "xphase:1:2",   -- prefix garbage (^-anchored)
                "PHASE:1:2",    -- scheme is case-sensitive
                "phase:1:2 ",   -- trailing whitespace
                "",
            }
            for _, key in ipairs(bad) do
                assert.is_false(DT:IsPhaseRuleKey(key), key)
                local enc, idx = DT:ParsePhaseRuleKey(key)
                assert.is_nil(enc, key)
                assert.is_nil(idx, key)
            end
        end)

        it("rejects non-string keys — numeric spellIds share the same db tables (:331)", function()
            assert.is_false(DT:IsPhaseRuleKey(111))
            assert.is_false(DT:IsPhaseRuleKey(nil))
            assert.is_nil((DT:ParsePhaseRuleKey(12345)))
        end)
    end)

    describe("IsSpellAllowedForRole", function()
        -- Expected visibility per (curated role × player token), transcribed
        -- from ROLE_ALLOW_LIST (DungeonTimers.lua).
        local MATRIX = {
            { spell = 111, role = "tank",     TANK = true,  HEALER = false, DAMAGER = false },
            { spell = 222, role = "heal",     TANK = false, HEALER = true,  DAMAGER = false },
            { spell = 333, role = "kick",     TANK = true,  HEALER = false, DAMAGER = true  },
            { spell = 444, role = "move",     TANK = false, HEALER = true,  DAMAGER = true  },
            { spell = 666, role = "mechanic", TANK = true,  HEALER = true,  DAMAGER = true  },
            { spell = 777, role = "other",    TANK = true,  HEALER = true,  DAMAGER = true  },
        }
        local TOKENS = { "TANK", "HEALER", "DAMAGER" }

        it("matches the curated allow-list for every role × token pair", function()
            for _, row in ipairs(MATRIX) do
                for _, token in ipairs(TOKENS) do
                    assert.equals(row[token], DT:IsSpellAllowedForRole(row.spell, token),
                        row.role .. " x " .. token)
                end
            end
        end)

        it("untagged spells fail open for every token", function()
            for _, token in ipairs(TOKENS) do
                assert.is_true(DT:IsSpellAllowedForRole(555, token), token)
            end
        end)

        it("an unknown or nil player token fails open (:736)", function()
            assert.is_true(DT:IsSpellAllowedForRole(111, "NONE"))
            assert.is_true(DT:IsSpellAllowedForRole(111, nil))
        end)

        it("a user role override beats the curated verdict in both directions", function()
            DT:SetSpellRoleOverride(111, "DAMAGER", true)   -- curated hides tank from DAMAGER
            assert.is_true(DT:IsSpellAllowedForRole(111, "DAMAGER"))
            assert.is_false(DT:IsSpellAllowedForRole(111, "HEALER"))  -- untouched token → curated
            DT:SetSpellRoleOverride(555, "TANK", false)     -- untagged curated verdict is fail-open true
            assert.is_false(DT:IsSpellAllowedForRole(555, "TANK"))
        end)

        it("SetSpellRoleOverride prunes the entry once every stored token matches curated (:752)", function()
            DT:SetSpellRoleOverride(111, "DAMAGER", true)
            assert.is_true(DT:HasSpellOverrides(111))
            DT:SetSpellRoleOverride(111, "DAMAGER", false)  -- back to curated → prune walk drops the entry
            assert.is_false(DT:IsSpellAllowedForRole(111, "DAMAGER"))
            assert.is_false(DT:HasSpellOverrides(111))
            assert.is_nil(DT.db.SpellRoleOverrides[111])
        end)
    end)

    describe("HasSpellOverrides / ResetSpellOverrides symmetry", function()
        -- One entry per persisted override slot HasSpellOverrides walks
        -- (:825-859); slot names double as the raw-table empty check after
        -- reset — a typo there indexes nil and fails loudly.
        local OVERRIDE_KINDS = {
            { slot = "SpellDisabled",             set = function() DT:SetSpellDisabled(111, true) end },
            { slot = "SpellShowAtOverrides",      set = function() DT:SetSpellShowAtOverride(111, 20) end },
            { slot = "SpellTimeOffsets",          set = function() DT:SetSpellTimeOffset(111, 1.5) end },
            { slot = "SpellDisplayOverrides",     set = function() DT:SetSpellDisplayOverride(111, "text") end },
            { slot = "SpellDisplayTextOverrides", set = function() DT:SetSpellDisplayTextOverride(111, "CUSTOM") end },
            { slot = "SpellDecimalThresholds",    set = function() DT:SetSpellDecimalThreshold(111, 10) end },
            { slot = "SpellColorOverrides",       set = function() DT:SetSpellColorOverride(111, { 1, 0, 0 }) end },
            { slot = "SpellSoundsOnShow",         set = function() DT:SetSpellSoundOnShow(111, "Ding") end },
            { slot = "SpellSoundsOnHide",         set = function() DT:SetSpellSoundOnHide(111, "Dong") end },
            { slot = "SpellRoleOverrides",        set = function() DT:SetSpellRoleOverride(111, "DAMAGER", true) end },
        }

        it("each override kind alone flips HasSpellOverrides and reset clears it", function()
            for _, kind in ipairs(OVERRIDE_KINDS) do
                assert.is_false(DT:HasSpellOverrides(111), kind.slot .. " leaked from previous kind")
                kind.set()
                assert.is_true(DT:HasSpellOverrides(111), kind.slot .. " did not register")
                DT:ResetSpellOverrides(111)
                assert.is_false(DT:HasSpellOverrides(111), kind.slot .. " survived reset")
            end
        end)

        it("reset after setting every kind empties every persisted slot", function()
            for _, kind in ipairs(OVERRIDE_KINDS) do kind.set() end
            assert.is_true(DT:HasSpellOverrides(111))
            DT:ResetSpellOverrides(111)
            assert.is_false(DT:HasSpellOverrides(111))
            for _, kind in ipairs(OVERRIDE_KINDS) do
                assert.is_nil(next(DT.db[kind.slot]), kind.slot .. " not empty")
            end
        end)

        it("getters fall back to curator/default values after reset", function()
            for _, kind in ipairs(OVERRIDE_KINDS) do kind.set() end
            DT:ResetSpellOverrides(111)
            assert.equals(12, DT:GetSpellShowAtSeconds(111))
            assert.equals(30, DT:GetSpellDecimalThreshold(111))
            assert.is_false(DT:IsSpellDisabled(111))
            assert.equals("bar", DT:GetSpellDisplay(111))
            assert.equals("TANK", DT:GetSpellDisplayText(111))
            assert.is_nil(DT:GetSpellColorOverride(111))
            assert.is_nil(DT:GetSpellTimeOffset(111))
            assert.is_nil(DT:GetSpellSoundOnShow(111))
            assert.is_nil(DT:GetSpellSoundOnHide(111))
            assert.is_false(DT:IsSpellAllowedForRole(111, "DAMAGER"))
        end)

        it("reset touches only the given spell", function()
            DT:SetSpellShowAtOverride(111, 20)
            DT:SetSpellShowAtOverride(333, 4)
            DT:ResetSpellOverrides(111)
            assert.is_false(DT:HasSpellOverrides(111))
            assert.is_true(DT:HasSpellOverrides(333))
            assert.equals(4, DT:GetSpellShowAtSeconds(333))
        end)

        it("accessors are nil-safe without a db", function()
            DT.db = nil
            assert.is_false(DT:HasSpellOverrides(111))
            assert.equals(30, DT:GetSpellDecimalThreshold(111))
            assert.has_no.errors(function()
                DT:SetSpellShowAtOverride(111, 5)
                DT:SetSpellDecimalThreshold(111, 5)
                DT:SetSpellDisabled(111, true)
                DT:ResetSpellOverrides(111)
            end)
            assert.is_nil(DT:GetSpellShowAtOverride(111))
        end)
    end)
end)
