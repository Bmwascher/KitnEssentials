-- Tier 1: the module enable-default opt-in migration (Core/Defaults.lua).
-- Every module now ships disabled, so a profile saved under the old defaults
-- carries NO Enabled key for a module the user left on -- AceDB strips
-- default-equal leaves at logout. KE:MigrateModuleEnableDefaults reads the RAW
-- saved variables before AceDB:New and rewrites that absence as an explicit
-- true. Pins the run-once stamp (a second pass must never re-enable a module
-- the user has since switched off), the fresh-install branch (an unstamped new
-- file would be read as legacy on the following login), and the standing rule
-- that no module defaults on.
local helpers = require("dev.spec._helpers")

local STAMP = "ModuleEnableDefaultsMigrated"

-- Exempt from the modules-ship-off rule:
--   UseElvUI      -- not a module; it selects ElvUI media when ElvUI is present.
--   KeystoneHelper -- a container whose page has no master switch by design, so
--                     the container must stay reachable. Its three feature
--                     toggles are the switches that ship off (asserted below).
local SHIPS_ENABLED = { UseElvUI = true, KeystoneHelper = true }

local function migrateWith(sv)
    _G.KitnEssentialsDB = sv
    local KE = helpers.loadModule("Core/Defaults.lua")
    KE:MigrateModuleEnableDefaults()
    return _G.KitnEssentialsDB, KE
end

describe("module enable defaults", function()
    after_each(function()
        _G.KitnEssentialsDB = nil
    end)

    it("ships every module disabled", function()
        local _, KE = migrateWith(nil)
        for name, section in pairs(KE:GetDefaultDB().profile) do
            if type(section) == "table" and type(section.Enabled) == "boolean" then
                if not SHIPS_ENABLED[name] then
                    assert.is_false(section.Enabled, name .. " defaults enabled")
                end
            end
        end
    end)

    it("ships KeystoneHelper's feature switches off behind its always-on container", function()
        local _, KE = migrateWith(nil)
        local kh = KE:GetDefaultDB().profile.KeystoneHelper
        assert.is_true(kh.Enabled)
        assert.is_false(kh.ResetEnabled)
        assert.is_false(kh.RerollEnabled)
        assert.is_false(kh.YourKeyEnabled)
    end)

    it("keeps a module a legacy profile left on", function()
        local sv = migrateWith({ profiles = { Default = {} } })
        assert.is_true(sv.profiles.Default.CombatTexts.Enabled)
        assert.is_true(sv.profiles.Default.Skinning.LootRoll.Enabled)
        -- Module-owned defaults (not registered with AceDB) ride the same list.
        assert.is_true(sv.profiles.Default.DamageMeter.Enabled)
        assert.is_true(sv.profiles.Default.MythicPlusTimer.Enabled)
        -- KeystoneHelper migrates on its feature keys, not on the container.
        assert.is_true(sv.profiles.Default.KeystoneHelper.ResetEnabled)
        assert.is_true(sv.profiles.Default.KeystoneHelper.RerollEnabled)
        assert.is_true(sv.profiles.Default.KeystoneHelper.YourKeyEnabled)
        assert.is_nil(sv.profiles.Default.KeystoneHelper.Enabled)
    end)

    it("leaves a module the user switched off switched off", function()
        local sv = migrateWith({ profiles = { Default = { CombatTexts = { Enabled = false } } } })
        assert.is_false(sv.profiles.Default.CombatTexts.Enabled)
    end)

    it("does not enable a module that already shipped disabled", function()
        local sv = migrateWith({ profiles = { Default = {} } })
        assert.is_nil(sv.profiles.Default.CombatTimer)
        assert.is_nil(sv.profiles.Default.RangeChecker)
    end)

    it("preserves the rest of a module's saved settings", function()
        local sv = migrateWith({ profiles = { Default = { CombatTexts = { FontSize = 22 } } } })
        assert.equals(22, sv.profiles.Default.CombatTexts.FontSize)
        assert.is_true(sv.profiles.Default.CombatTexts.Enabled)
    end)

    it("migrates every profile in the file", function()
        local sv = migrateWith({ profiles = { Default = {}, Alt = { CombatTexts = { Enabled = false } } } })
        assert.is_true(sv.profiles.Default.CombatTexts.Enabled)
        assert.is_false(sv.profiles.Alt.CombatTexts.Enabled)
    end)

    it("runs once per saved-variables file", function()
        local sv, KE = migrateWith({ profiles = { Default = {} } })
        assert.is_true(sv[STAMP])
        sv.profiles.Default.CombatTexts.Enabled = false
        KE:MigrateModuleEnableDefaults()
        assert.is_false(sv.profiles.Default.CombatTexts.Enabled)
    end)

    it("stamps a fresh install so the next login is not read as legacy", function()
        local sv, KE = migrateWith(nil)
        assert.is_table(sv)
        assert.is_true(sv[STAMP])
        -- AceDB creates the profile on this same login; the next login must
        -- leave it alone.
        sv.profiles = { Default = {} }
        KE:MigrateModuleEnableDefaults()
        assert.is_nil(sv.profiles.Default.CombatTexts)
    end)

    it("leaves a corrupt non-table saved value alone", function()
        local sv = migrateWith({ profiles = { Default = { Skinning = "corrupt" } } })
        assert.equals("corrupt", sv.profiles.Default.Skinning)
    end)
end)
