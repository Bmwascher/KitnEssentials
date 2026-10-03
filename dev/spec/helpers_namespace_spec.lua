-- The settings pages ship as their own addon and reach the addon's table
-- through KitnEssentials:GetNamespace(). loadModule answers that call with
-- the table the spec passes, and leaves the KitnEssentials global as it found
-- it, so a page's file-scope `KitnEssentials and ...` lines read as before.
local helpers = require("dev.spec._helpers")

local PAGE = "KitnEssentials_Options/GUIQoL/GUI-MoveFrames.lua"

describe("spec helper: settings page namespace", function()
    after_each(function()
        _G.KitnEssentials = nil
    end)

    it("hands a page the table the spec passed, with no addon global or with the shim", function()
        local cases = {
            { name = "no addon global", shim = false },
            { name = "shim installed first", shim = true },
        }
        for _, case in ipairs(cases) do
            _G.KitnEssentials = nil
            if case.shim then helpers.installAddonShim() end
            local GUIFrame = {
                registeredContent = {},
                RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
                RegisterTabbedContent = function() end,
            }
            helpers.loadModule(PAGE, { GUIFrame = GUIFrame, Theme = {}, db = { profile = {} } })
            assert.is_function(GUIFrame.registeredContent.MoveFrames, case.name)
            assert.equals(case.shim, _G.KitnEssentials ~= nil, case.name)
        end
    end)
end)
