-- Pins that MPT:OnEnable calls ApplySettings after BuildHUD. BuildHUD returns
-- on an existing root and ProfileManager skips ApplySettings for modules it
-- just enabled, so a profile switch that turns the module on otherwise keeps
-- the previous profile's HUD look.
--
-- Loads the REAL Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua headlessly.
-- Collaborators from sibling files and Ace mixins are stubbed AFTER load: the
-- spec asserts the enable sequence, never those seams' behavior.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("MPT OnEnable settings pass", function()
    local MPT
    local calls

    before_each(function()
        mock.install({
            C_Timer = {
                After = function() end,
                NewTicker = function() return { Cancel = function() end } end,
            },
        })
        local modules = helpers.installAddonShim()
        _G.C_ChallengeMode = {
            GetActiveChallengeMapID = function() return nil end,
        }
        _G.GetInstanceInfo = function() return "Stormwind", "none", 0 end

        helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua",
            { Print = function() end, WarnRedundantAddon = function() end,
              db = { global = {}, profile = {} } })
        MPT = modules["MythicPlusTimer"]
        assert(MPT and MPT.OnEnable, "real MythicPlusTimer.lua did not load")

        calls = {}
        local function record(name)
            return function() calls[#calls + 1] = name end
        end
        -- Ace mixins and sibling-file seams — not under test.
        MPT.RegisterEvent = function() end
        MPT.InstallTickHook = function() end
        MPT.InitOverlay = function() end
        MPT.RegWithEditMode = function() end
        MPT.CheckForActiveRun = function() end
        MPT.IsEnabled = function() return true end
        MPT.BuildHUD = record("BuildHUD")
        MPT.ApplySettings = record("ApplySettings")
        MPT.db = { Enabled = true }
    end)

    it("applies settings once, after BuildHUD, on a prebuilt HUD", function()
        MPT.frames = { root = {} }
        MPT:OnEnable()
        assert.same({ "BuildHUD", "ApplySettings" }, calls)
    end)

    it("applies settings once, after BuildHUD, on a fresh HUD", function()
        MPT.frames = nil
        MPT:OnEnable()
        assert.same({ "BuildHUD", "ApplySettings" }, calls)
    end)

    it("does nothing while db.Enabled is off", function()
        MPT.db.Enabled = false
        MPT:OnEnable()
        assert.same({}, calls)
    end)
end)
