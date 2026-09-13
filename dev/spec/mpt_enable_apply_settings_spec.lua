-- Lifecycle spec for MythicPlusTimer's OnEnable settings pass.
--
-- BuildHUD returns as soon as frames.root exists, and ProfileManager skips
-- ApplySettings for modules it just enabled ("newly-enabled modules apply
-- settings inside their own OnEnable"). A profile switch that turns the module
-- on therefore reaches a HUD still configured under the previous profile unless
-- OnEnable itself re-applies. This pins that OnEnable calls ApplySettings after
-- BuildHUD, on a prebuilt HUD and on a fresh one (whose bar background is seeded
-- from a constant, not the profile).
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
