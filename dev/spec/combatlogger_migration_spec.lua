-- Tier 1: the Combat Logger key-rename migration (Core/Defaults.lua).
-- Two keys were renamed inside a block that is already live in shipped saved
-- variables: ScenarioTorghast became Scenario, and DisableACLPrompt became
-- PromptAdvanced with its polarity flipped. An absent old key means it held its
-- old default, because the build that wrote the file stripped default-equal
-- leaves at logout. AceDB fills and strips only what its defaults table
-- declares, so the retired keys survive it either way: reading them before
-- AceDB:New is sequencing, not a requirement.
local helpers = require("dev.spec._helpers")

local RECORD = "KeyRenames"
local SCENARIO_ID = "CombatLogger.ScenarioTorghast->Scenario"
local PROMPT_ID = "CombatLogger.DisableACLPrompt->PromptAdvanced"

local function migrateWith(sv)
    _G.KitnEssentialsDB = sv
    local KE = helpers.loadModule("Core/Defaults.lua")
    KE:MigrateCombatLoggerKeys()
    return _G.KitnEssentialsDB, KE
end

local function profileWith(block)
    return { profiles = { Default = { CombatLogger = block } } }
end

describe("combat logger key renames", function()
    after_each(function()
        _G.KitnEssentialsDB = nil
    end)

    it("ships the new keys and neither old one", function()
        -- Reads the defaults only, deliberately not through migrateWith: this
        -- assertion holds whether or not the migration exists.
        local KE = helpers.loadModule("Core/Defaults.lua")
        local block = KE:GetDefaultDB().profile.CombatLogger
        assert.is_false(block.Scenario)
        assert.is_true(block.PromptAdvanced)
        assert.is_nil(block.ScenarioTorghast)
        assert.is_nil(block.DisableACLPrompt)
    end)

    it("carries a Torghast opt-in onto every scenario", function()
        local sv = migrateWith(profileWith({ ScenarioTorghast = true }))
        assert.is_true(sv.profiles.Default.CombatLogger.Scenario)
    end)

    it("carries a Torghast opt-out", function()
        local sv = migrateWith(profileWith({ ScenarioTorghast = false }))
        assert.is_false(sv.profiles.Default.CombatLogger.Scenario)
    end)

    it("flips the prompt polarity", function()
        local sv = migrateWith(profileWith({ DisableACLPrompt = true }))
        assert.is_false(sv.profiles.Default.CombatLogger.PromptAdvanced)
    end)

    it("gives a block holding neither old key both new defaults", function()
        -- The commonest real profile: AceDB stripped both keys at logout
        -- because both sat at their old default, but the block itself survived
        -- on some other key.
        local sv = migrateWith(profileWith({ Enabled = true }))
        local block = sv.profiles.Default.CombatLogger
        assert.is_true(block.PromptAdvanced)
        assert.is_false(block.Scenario)
    end)

    it("clears both old keys after copying them", function()
        local sv = migrateWith(profileWith({
            ScenarioTorghast = true,
            DisableACLPrompt = true,
        }))
        local block = sv.profiles.Default.CombatLogger
        assert.is_nil(block.ScenarioTorghast)
        assert.is_nil(block.DisableACLPrompt)
    end)

    it("migrates every profile, not just the first", function()
        _G.KitnEssentialsDB = {
            profiles = {
                Default = { CombatLogger = { ScenarioTorghast = true } },
                Alt = { CombatLogger = { ScenarioTorghast = false } },
            },
        }
        local KE = helpers.loadModule("Core/Defaults.lua")
        KE:MigrateCombatLoggerKeys()
        local sv = _G.KitnEssentialsDB
        assert.is_true(sv.profiles.Default.CombatLogger.Scenario)
        assert.is_false(sv.profiles.Alt.CombatLogger.Scenario)
    end)

    it("leaves a profile with no CombatLogger block alone", function()
        local sv = migrateWith({ profiles = { Default = { Cursor = {} } } })
        assert.is_nil(sv.profiles.Default.CombatLogger)
    end)

    it("stamps both renames as done", function()
        local sv = migrateWith(profileWith({ ScenarioTorghast = true }))
        assert.is_true(sv[RECORD][SCENARIO_ID])
        assert.is_true(sv[RECORD][PROMPT_ID])
    end)

    it("stamps on a fresh install so the next login is not read as legacy", function()
        -- Without this the following login would find a brand-new profile whose
        -- old keys are absent, convert that absence, and overwrite whatever the
        -- user had just chosen.
        local sv = migrateWith(nil)
        assert.is_table(sv)
        assert.is_true(sv[RECORD][SCENARIO_ID])
        assert.is_true(sv[RECORD][PROMPT_ID])
    end)

    it("never runs twice over a value the user has since changed", function()
        local sv = profileWith({ Scenario = true })
        sv[RECORD] = { [SCENARIO_ID] = true, [PROMPT_ID] = true }
        _G.KitnEssentialsDB = sv
        local KE = helpers.loadModule("Core/Defaults.lua")
        KE:MigrateCombatLoggerKeys()
        assert.is_true(_G.KitnEssentialsDB.profiles.Default.CombatLogger.Scenario)
    end)

    it("does not disturb the enable-default record", function()
        -- The two migrations keep separate record tables; Core/Defaults.lua
        -- says why.
        local sv = profileWith({ ScenarioTorghast = true })
        sv.ModuleDefaultsOptIn = { ["CombatLogger.Enabled"] = true }
        _G.KitnEssentialsDB = sv
        local KE = helpers.loadModule("Core/Defaults.lua")
        KE:MigrateCombatLoggerKeys()
        local out = _G.KitnEssentialsDB
        assert.is_true(out.ModuleDefaultsOptIn["CombatLogger.Enabled"])
        assert.is_nil(out.ModuleDefaultsOptIn[SCENARIO_ID])
    end)
end)

-- The same helper now carries two more shapes. A visibility mode is converted
-- IN PLACE, where the old and new key are the same string, and the retired
-- cursor satellite modes sit one level deeper than a block can reach.
describe("visibility mode retirement", function()
    local CROSS_ID = "CombatCross.AlwaysShow->Visibility"
    local CURSOR_ID = "Cursor.Visibility.RetireGroupModes"
    local GCD_ID = "Cursor.GCD.VisibilityOverride.RetireGroupModes"

    after_each(function()
        _G.KitnEssentialsDB = nil
    end)

    local function migrate(profile)
        _G.KitnEssentialsDB = { profiles = { Default = profile } }
        local KE = helpers.loadModule("Core/Defaults.lua")
        KE:MigrateCombatLoggerKeys()
        return _G.KitnEssentialsDB.profiles.Default
    end

    it("ships Visibility and no AlwaysShow", function()
        local KE = helpers.loadModule("Core/Defaults.lua")
        local block = KE:GetDefaultDB().profile.CombatCross
        assert.are.equal("in_combat", block.Visibility)
        assert.is_nil(block.AlwaysShow)
    end)

    it("turns an Always Show crosshair into the always mode", function()
        local out = migrate({ CombatCross = { AlwaysShow = true } })
        assert.are.equal("always", out.CombatCross.Visibility)
        assert.is_nil(out.CombatCross.AlwaysShow)
    end)

    it("turns a combat-only crosshair into the in_combat mode", function()
        local out = migrate({ CombatCross = { AlwaysShow = false } })
        assert.are.equal("in_combat", out.CombatCross.Visibility)
    end)

    -- The defect this shape exists to prevent: writing the converted value and
    -- then deleting the key it was written to, because old and new match.
    it("keeps an in-place conversion instead of deleting it", function()
        local out = migrate({ Cursor = { Visibility = "in_raid" } })
        assert.are.equal("in_instance", out.Cursor.Visibility)
    end)

    it("leaves a mode that was not retired alone", function()
        local out = migrate({ Cursor = { Visibility = "mouseDown" } })
        assert.are.equal("mouseDown", out.Cursor.Visibility)
    end)

    it("converts the retired modes on every cursor satellite", function()
        local out = migrate({
            Cursor = {
                GCD    = { VisibilityOverride = "in_party" },
                Cast   = { VisibilityOverride = "in_raid" },
                Trail  = { VisibilityOverride = "in_raid" },
                Dispel = { VisibilityOverride = "in_party" },
                Taunt  = { VisibilityOverride = "in_raid" },
            },
        })
        assert.are.equal("in_instance", out.Cursor.GCD.VisibilityOverride)
        assert.are.equal("in_instance", out.Cursor.Cast.VisibilityOverride)
        assert.are.equal("in_instance", out.Cursor.Trail.VisibilityOverride)
        assert.are.equal("in_instance", out.Cursor.Dispel.VisibilityOverride)
        assert.are.equal("in_instance", out.Cursor.Taunt.VisibilityOverride)
    end)

    -- ResolveParentTable builds the chain it walks, so a profile that never
    -- touched the cursor comes out holding empty satellite tables. Inert --
    -- AceDB serves defaults through the metatable -- and asserted so a later
    -- reader meets it here rather than in a diff.
    it("creates the empty parents it walks through", function()
        local out = migrate({ CombatCross = { AlwaysShow = false } })
        assert.is_table(out.Cursor)
        assert.is_table(out.Cursor.GCD)
        assert.is_nil(out.Cursor.GCD.VisibilityOverride)
    end)

    it("runs once and leaves a later hand edit alone", function()
        local sv = { profiles = { Default = { Cursor = { Visibility = "in_raid" } } } }
        sv[RECORD] = { [CROSS_ID] = true, [CURSOR_ID] = true, [GCD_ID] = true }
        _G.KitnEssentialsDB = sv
        local KE = helpers.loadModule("Core/Defaults.lua")
        KE:MigrateCombatLoggerKeys()
        assert.are.equal("in_raid", _G.KitnEssentialsDB.profiles.Default.Cursor.Visibility)
    end)
end)
