-- Tier 2: the settings-pages decision in GUI/GUIMain/GUI-Core.lua.
--
-- Opening settings decides from plain facts whether the pages addon is
-- ready, loads now, or is reported missing, mismatched or disabled. A wrong
-- answer loads pages from another version or names the wrong fix, and fails
-- nowhere but in game. The decision is pure, so it is tested directly; the
-- API reads around it are verified in game. The save after enabling a
-- disabled pages addon is a guard (an open AddOn List keeps its own
-- Okay or Cancel), tested against stubbed C_AddOns and AddonList.
local helpers = require("dev.spec._helpers")

describe("GUI-Core settings-pages decision", function()
    local GUIFrame, KE

    before_each(function()
        KE = { Theme = { headerHeight = 32, borderSize = 1 } }
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

    it("saves the enable after a load, unless the AddOn List is open", function()
        local savedAddOns, savedList = _G.C_AddOns, _G.AddonList
        finally(function() _G.C_AddOns, _G.AddonList = savedAddOns, savedList end)
        local saves
        GUIFrame.PagesLoadFailed = function() return false, false end
        KE.Print = function() end
        local cases = {
            { name = "loads, AddOn List closed", loads = true, listShown = false, wantSaves = 1 },
            { name = "loads, AddOn List open", loads = true, listShown = true, wantSaves = 0 },
            { name = "load fails", loads = false, listShown = false, wantSaves = 0 },
        }
        for _, case in ipairs(cases) do
            saves = 0
            _G.C_AddOns = {
                EnableAddOn = function() end,
                LoadAddOn = function() return case.loads end,
                SaveAddOns = function() saves = saves + 1 end,
            }
            _G.AddonList = { IsShown = function() return case.listShown end }
            GUIFrame:LoadDisabledPages("Player-1-00000001")
            assert.equals(case.wantSaves, saves, case.name)
        end
    end)
end)
