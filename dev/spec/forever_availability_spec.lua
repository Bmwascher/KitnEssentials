-- Tier 1: refusal rules for the client availability policy
-- (Core/Availability.lua) and the consumers that must apply it. A withheld
-- feature has to stay off whatever its saved flag or a profile says, and a
-- broken gate shows nothing on retail, where every id is admitted.
local helpers = require("dev.spec._helpers")
local L = require("dev.spec._ke_loader")

describe("Forever availability: admission", function()
    -- The lists the TOC loaded decide, never the interface: a policy that
    -- disagreed with the load would run withheld files or refuse loaded ones.
    it("admits only the baseline after a baseline load, whatever the interface or a saved flag says", function()
        local BASELINE = { BASELINE_LOAD = true, IS_FOREVER = true }
        local BASELINE_UNREADABLE = { BASELINE_LOAD = true, IS_FOREVER = false }
        local RETAIL = { IS_FOREVER = false }
        local RETAIL_FOREVER_IFACE = { IS_FOREVER = true }
        for _, row in ipairs({
            { load = "baseline",            seed = BASELINE,             id = "HomePage",         want = true },
            { load = "baseline",            seed = BASELINE,             id = "Profiles",         want = true },
            { load = "baseline",            seed = BASELINE,             id = "ProfilesReset",    want = true },
            { load = "baseline",            seed = BASELINE,             id = "Chat",             want = false },
            { load = "baseline",            seed = BASELINE,             id = "LibDualSpec",      want = false },
            { load = "baseline",            seed = BASELINE,             id = "NotAFeature",      want = false },
            { load = "baseline",            seed = BASELINE,             id = nil,                want = false },
            { load = "baseline, no iface",  seed = BASELINE_UNREADABLE,  id = "HomePage",         want = true },
            { load = "baseline, no iface",  seed = BASELINE_UNREADABLE,  id = "LibDualSpec",      want = false },
            { load = "baseline, no iface",  seed = BASELINE_UNREADABLE,  id = "NicknameProvider", want = false },
            { load = "retail",              seed = RETAIL,               id = "Chat",             want = true },
            { load = "retail",              seed = RETAIL,               id = "NotAFeature",      want = true },
            { load = "retail, Forever iface", seed = RETAIL_FOREVER_IFACE, id = "Chat",           want = true },
        }) do
            local seed = { BASELINE_LOAD = row.seed.BASELINE_LOAD, IS_FOREVER = row.seed.IS_FOREVER }
            local KE = helpers.loadModule("Core/Availability.lua", seed)
            assert.equals(row.want, (KE:IsFeatureAvailable(row.id)), row.load .. " " .. tostring(row.id))
        end

        -- The conflict scan reads the saved flag. Answering a prompt for a
        -- module that never loaded would disable the rival addon for nothing.
        for _, row in ipairs({
            { name = "baseline load", forever = true,  prompts = 0 },
            { name = "retail load",   forever = false, prompts = 1 },
        }) do
            local KE = L.loadConflicts(nil, { forever = row.forever })
            local queue = KE:BuildConflictQueue({
                profile = { Skinning = { Chat = { Enabled = true } } },
                isLoaded = function(name) return name == "Prat-3.0" end,
                shouldNotLoad = false,
            })
            assert.equals(row.prompts, #queue, row.name)
        end
    end)
end)

describe("Forever availability: refresh and previews", function()
    -- Two states a withheld module can be in: dormant with its flag on, and
    -- running under its own enable management. Neither may be enabled,
    -- re-applied or previewed; the rebind still runs, as the refresh
    -- contract requires for every loaded module.
    it("rebinds a withheld module on a profile refresh but never enables, applies or previews it", function()
        for _, row in ipairs({
            { name = "dormant with its flag on", enabled = false },
            { name = "running, self-managed",    enabled = true, selfManaged = true },
        }) do
            local KE = L.loadGlobals(nil, { forever = true })
            local calls = {}
            local module = {
                db = { Enabled = true },
                keSelfManagedEnable = row.selfManaged,
                IsEnabled = function() return row.enabled end,
                UpdateDB = function() calls[#calls + 1] = "rebind" end,
                ApplySettings = function() calls[#calls + 1] = "apply" end,
                ShowPreview = function() calls[#calls + 1] = "preview" end,
                HidePreview = function() end,
            }
            _G.KitnEssentials = {
                IterateModules = function() return pairs({ CombatTimer = module }) end,
                GetModule = function(_, name) return name == "CombatTimer" and module or nil end,
                EnableModule = function(_, name) calls[#calls + 1] = "enable " .. name end,
                DisableModule = function(_, name) calls[#calls + 1] = "disable " .. name end,
            }
            helpers.loadModule("Core/ProfileManager.lua", KE)
            KE.ProfileManager:RefreshAllModules()
            KE.PreviewManager:ShowModules({ "CombatTimer" })
            KE.PreviewManager:ShowSectionPreviews("combat_section")
            assert.same({ "rebind" }, calls, row.name)
        end
    end)
end)

describe("Forever availability: dual-spec profiles", function()
    -- KE.LDS is set by hand to stand for a copy another addon loaded: the
    -- library lookup finds either, so presence alone must not decide.
    it("enhances the database only where dual-spec profiles are admitted", function()
        for _, row in ipairs({
            { name = "Forever", forever = true,  calls = 0, enhanced = false },
            { name = "retail",  forever = false, calls = 1, enhanced = true },
        }) do
            local KE = L.loadGlobals(nil, { forever = row.forever })
            local calls = 0
            KE.LDS = { EnhanceDatabase = function() calls = calls + 1 end }
            assert.equals(row.enhanced, KE:EnhanceDualSpec({}), row.name)
            assert.equals(row.calls, calls, row.name)
        end
    end)
end)

describe("Forever availability: tab resolution", function()
    -- Chat stands for any withheld page and sits first, so a missing
    -- filter renders it in every row.
    it("lands a withheld remembered, nested or default tab on the first admitted tab", function()
        local rendered
        local GUIFrame = {
            registeredContent = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            CreateSubTabs = function(_, _, yOffset) return nil, yOffset end,
        }
        local KE = helpers.loadModule("Core/Availability.lua", { BASELINE_LOAD = true, IS_FOREVER = true, GUIFrame = GUIFrame })
        helpers.loadModule("GUI/GUIMain/GUI-TabbedContent.lua", KE)
        for _, id in ipairs({ "Chat", "ProfilesSharing", "ProfilesMain" }) do
            GUIFrame.registeredContent[id] = function(_, yOffset)
                rendered = id
                return yOffset
            end
        end
        GUIFrame:RegisterNestedTabs("Chat", { "ChatForms" })
        local TABS = {
            { id = "Chat",            label = "Withheld" },
            { id = "ProfilesSharing", label = "Sharing" },
            { id = "ProfilesMain",    label = "Profile" },
        }
        for _, row in ipairs({
            { name = "remembered", remembered = "Chat" },
            { name = "nested",     remembered = "ChatForms" },
            { name = "default",    default = "Chat" },
        }) do
            rendered = nil
            GUIFrame.tabbedPageState["Profiles"] = row.remembered
            GUIFrame:RegisterTabbedContent("Profiles", TABS, row.default and {
                defaultTab = function() return row.default end,
            } or nil)
            GUIFrame.registeredContent["Profiles"](nil, 0)
            assert.equals("ProfilesSharing", rendered, row.name)
        end
    end)
end)

describe("Forever availability: frame skins", function()
    -- Mail stands for an admitted window, Friends for a withheld one and
    -- ContextMenus for a row backed by its own module.
    it("admits only the listed skin keys after a baseline load and every key after a retail load", function()
        for _, row in ipairs({
            { load = "baseline", baseline = true, key = "Mail",         want = true },
            { load = "baseline", baseline = true, key = "Friends",      want = false },
            { load = "baseline", baseline = true, key = "ContextMenus", want = false },
            { load = "baseline", baseline = true, key = nil,            want = false },
            { load = "retail",   baseline = nil,  key = "Friends",      want = true },
            { load = "retail",   baseline = nil,  key = "ContextMenus", want = true },
        }) do
            local KE = helpers.loadModule("Core/Availability.lua", { BASELINE_LOAD = row.baseline })
            assert.equals(row.want, KE:IsFrameSkinAvailable(row.key), row.load .. " " .. tostring(row.key))
        end
    end)
end)
