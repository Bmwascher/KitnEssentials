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
