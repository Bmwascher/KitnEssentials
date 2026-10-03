-- Tier 2: the settings-pages decision in GUI/GUIMain/GUI-Core.lua.
--
-- Opening settings decides from plain facts whether the pages addon is
-- ready, loads now, or is reported missing, mismatched or disabled. A wrong
-- answer loads pages from another version or names the wrong fix, and fails
-- nowhere but in game. The decision is pure, so it is tested directly; the
-- API reads around it are verified in game.
local helpers = require("dev.spec._helpers")

describe("GUI-Core settings-pages decision", function()
    local GUIFrame

    before_each(function()
        local KE = { Theme = { headerHeight = 32, borderSize = 1 } }
        helpers.loadModule("GUI/GUIMain/GUI-Core.lua", KE)
        GUIFrame = KE.GUIFrame
    end)

    it("picks one action from the facts, checking the version before the enable state", function()
        local function facts(loaded, enabled, coreVersion, pagesVersion)
            return {
                loaded = loaded, exists = true, enabled = enabled,
                coreVersion = coreVersion, pagesVersion = pagesVersion,
            }
        end
        local loading = facts(false, true, "4.9.0", "4.9.0")
        loading.loading = true
        local cases = {
            { name = "already loaded", state = facts(true, true, "4.9.0", "4.9.0"), want = "ready" },
            { name = "still loading", state = loading, want = "loading" },
            { name = "not loaded yet, or after a failed load", state = facts(false, true, "4.9.0", "4.9.0"), want = "load" },
            { name = "folder absent", state = { exists = false }, want = "missing" },
            { name = "other version", state = facts(false, true, "4.9.0", "4.8.24"), want = "mismatch" },
            { name = "no version readable", state = facts(false, true, nil, nil), want = "mismatch" },
            { name = "disabled", state = facts(false, false, "4.9.0", "4.9.0"), want = "disabled" },
            { name = "disabled and other version", state = facts(false, false, "4.9.0", "4.8.24"), want = "mismatch" },
        }
        for _, case in ipairs(cases) do
            assert.equals(case.want, GUIFrame.PagesLoadAction(case.state), case.name)
        end
    end)
end)
