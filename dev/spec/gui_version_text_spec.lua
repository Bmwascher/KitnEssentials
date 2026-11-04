-- Tier 2: the settings window's bottom bar text in GUI/GUIMain/GUI-Core.lua.
-- The word Forever is a client gate on a line every retail player sees.
local helpers = require("dev.spec._helpers")

describe("GUI-Core RefreshVersionText", function()
    local CASES = {
        { name = "retail, current",   forever = false, newer = nil,      want = "|cff888888v4.16.0|r" },
        { name = "retail, outdated",  forever = false, newer = "v4.17.0",
          want = "|cff888888v4.16.0|r|cff888888, |r|cff7fff7fv4.17.0 available|r" },
        { name = "Forever, current",  forever = true,  newer = nil,      want = "|cff888888v4.16.0|r <Forever>" },
        { name = "Forever, outdated", forever = true,  newer = "v4.17.0",
          want = "|cff888888v4.16.0|r <Forever>|cff888888, |r|cff7fff7fv4.17.0 available|r" },
    }

    for _, case in ipairs(CASES) do
        it("reads correctly on " .. case.name, function()
            local KE = { Theme = { headerHeight = 32, borderSize = 1 } }
            helpers.loadModule("Core/Availability.lua", KE)
            helpers.loadModule("GUI/GUIMain/GUI-Core.lua", KE)
            KE.Version = "4.16.0"
            KE.IS_FOREVER = case.forever
            function KE:ColorTextByTheme(text) return "<" .. text .. ">" end
            function KE:GetNewerVersion() return case.newer end

            local shown
            KE.GUIFrame.versionText = { SetText = function(_, text) shown = text end }
            KE.GUIFrame:RefreshVersionText()

            assert.equals(case.want, shown)
        end)
    end
end)
