-- Tier 2: the settings-pages decision in GUI/GUIMain/GUI-Core.lua.
--
-- Opening settings decides from plain facts whether the pages addon is
-- ready, loads now, or is reported missing, mismatched or disabled. A wrong
-- answer loads pages from another version or names the wrong fix, and fails
-- nowhere but in game. The decision is pure, so it is tested directly; the
-- API reads around it are verified in game. The save after enabling a
-- disabled pages addon is a guard (an open AddOn List or another staged
-- change keeps the player's own Okay or Cancel): its pending test is pure,
-- and the save rule runs against stubbed C_AddOns and AddonList.
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

    it("counts another addon as changed but unsaved only when its state contradicts its load", function()
        local cases = {
            { name = "staged enable", args = { "Other", true, false, false, true }, want = true },
            { name = "staged disable", args = { "Other", false, true, false, nil }, want = true },
            { name = "load-on-demand, staged disable", args = { "Other", false, true, true, nil }, want = true },
            { name = "enabled but unloadable", args = { "Other", true, false, false, false }, want = false },
            { name = "load-on-demand, not loaded yet", args = { "Other", true, false, true, nil }, want = false },
            { name = "enabled and loaded", args = { "Other", true, true, false, nil }, want = false },
            { name = "the pages addon itself", args = { "KitnEssentials_Options", false, true, false, nil }, want = false },
        }
        for _, case in ipairs(cases) do
            assert.equals(case.want, GUIFrame.AddOnChangePending(unpack(case.args)), case.name)
        end
    end)

    it("saves the enable unless the AddOn List is open or another change looks staged", function()
        local savedAddOns, savedList, savedEnum = _G.C_AddOns, _G.AddonList, _G.Enum
        finally(function() _G.C_AddOns, _G.AddonList, _G.Enum = savedAddOns, savedList, savedEnum end)
        local saves
        GUIFrame.PagesLoadFailed = function() return false, false end
        KE.Print = function() end
        _G.Enum = { AddOnEnableState = { None = 0 } }
        local cases = {
            { name = "nothing else staged, list closed", loads = true, listShown = false, staged = false, wantSaves = 1 },
            { name = "AddOn List open", loads = true, listShown = true, staged = false, wantSaves = 0 },
            { name = "another addon staged", loads = true, listShown = false, staged = true, wantSaves = 0 },
            { name = "load fails, still saved for the retry", loads = false, listShown = false, staged = false, wantSaves = 1 },
        }
        for _, case in ipairs(cases) do
            saves = 0
            _G.C_AddOns = {
                GetNumAddOns = function() return 1 end,
                GetAddOnName = function() return "Other" end,
                GetAddOnEnableState = function() return case.staged and 2 or 0 end,
                IsAddOnLoaded = function() return false, false end,
                IsAddOnLoadOnDemand = function() return false end,
                IsAddOnLoadable = function() return true end,
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
