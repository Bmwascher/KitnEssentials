-- Tier 1: the Combat Logger key-rename migration (Core/Defaults.lua).
-- Two keys were renamed inside a block that is already live in shipped saved
-- variables: ScenarioTorghast became Scenario, and DisableACLPrompt became
-- PromptAdvanced with its polarity flipped. Both reads happen on the RAW saved
-- variables before AceDB:New, because AceDB strips default-equal leaves at
-- logout and an absent key is the only evidence that the user never touched it.
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
        -- Reads the defaults only. Deliberately does NOT go through
        -- migrateWith, so this one assertion still runs before the migration
        -- exists and pins Task 1's rename from the file where the rename story
        -- lives.
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
        -- The two migrations keep separate record tables on purpose: an id here
        -- is a rename, and an id there is a dotted profile path, and one table
        -- would make them indistinguishable to a later reader.
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
