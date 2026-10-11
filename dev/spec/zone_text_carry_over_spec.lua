-- Tier 1: the rule that merges the two Hide Zone Text settings
-- (Core/Defaults.lua, KE.ZoneTextCarryOver). Profiles are raw saved tables,
-- so an absent key stands for its default.
local helpers = require("dev.spec._helpers")

describe("zone text carry-over", function()
    it("ticks Hide Zone Text only where an old setting was hiding zone text", function()
        local KE = helpers.loadModule("Core/Defaults.lua")
        local rows = {
            {
                name = "Automation on with its box ticked",
                profile = { Automation = { Enabled = true, HideZoneText = true } },
                want = true,
            },
            {
                name = "Automation on with its box unticked, no Messages hide",
                profile = { Automation = { Enabled = true } },
                want = false,
            },
            {
                name = "Automation off with its box ticked, no Messages hide",
                profile = { Automation = { HideZoneText = true } },
                want = false,
            },
            {
                name = "Messages on with Hide ticked, ElvUI not loaded",
                profile = { Skinning = { Messages = { Enabled = true, ZoneText = { Hide = true } } } },
                want = true,
            },
            {
                name = "Messages on with Hide unticked",
                profile = { Skinning = { Messages = { Enabled = true, ZoneText = { Hide = false } } } },
                want = false,
            },
            {
                name = "Messages on with Hide ticked, ElvUI loaded, UseElvUI at its default",
                profile = { Skinning = { Messages = { Enabled = true, ZoneText = { Hide = true } } } },
                elvui = true,
                want = false,
            },
            {
                name = "Messages on with Hide ticked, ElvUI loaded, UseElvUI off",
                profile = {
                    UseElvUI = { Enabled = false },
                    Skinning = { Messages = { Enabled = true, ZoneText = { Hide = true } } },
                },
                elvui = true,
                want = true,
            },
            {
                name = "Messages off with Hide ticked",
                profile = { Skinning = { Messages = { ZoneText = { Hide = true } } } },
                want = false,
            },
            {
                name = "empty profile",
                profile = {},
                want = false,
            },
            {
                name = "import without the old Messages key is left untouched",
                profile = { Automation = { HideZoneText = true } },
                import = true,
                want = nil,
            },
            {
                name = "import carrying the old Messages key is converted",
                profile = { Skinning = { Messages = { Enabled = true, ZoneText = { Hide = true } } } },
                import = true,
                want = true,
            },
        }
        for _, row in ipairs(rows) do
            local got = KE.ZoneTextCarryOver(row.profile, row.elvui == true, row.import == true)
            assert(got == row.want, row.name .. ": expected " .. tostring(row.want) .. ", got " .. tostring(got))
        end
    end)
end)

describe("zone text carry-over appliers", function()
    after_each(function()
        _G.KitnEssentialsDB = nil
    end)

    it("converts an imported profile that carries the old key", function()
        local KE = helpers.loadModule("Core/Defaults.lua")
        local profile = {
            Skinning = { Messages = { Enabled = true, ZoneText = { Hide = true, SubZone = { Size = 20 } } } },
        }
        KE:MigrateProfileKeys(profile)
        assert.is_true(profile.Automation.HideZoneText)
        assert.is_nil(profile.Skinning.Messages.ZoneText.Hide)
        assert.equals(20, profile.Skinning.Messages.ZoneText.SubZone.Size)
    end)

    it("leaves an imported profile without the old key as exported", function()
        local KE = helpers.loadModule("Core/Defaults.lua")
        local profile = { Automation = { HideZoneText = true } }
        KE:MigrateProfileKeys(profile)
        assert.is_true(profile.Automation.HideZoneText)
    end)

    it("converts every saved profile at login and creates no table for a false result", function()
        local KE = helpers.loadModule("Core/Defaults.lua")
        local ticked = { Automation = { HideZoneText = true } }
        local empty = {}
        _G.KitnEssentialsDB = { profiles = { Ticked = ticked, Empty = empty } }
        KE:MigrateCombatLoggerKeys()
        assert.is_nil(ticked.Automation.HideZoneText)
        assert.is_nil(empty.Automation)
        assert.is_true(_G.KitnEssentialsDB.KeyRenames["ZoneText.HideMerge"])
    end)
end)
