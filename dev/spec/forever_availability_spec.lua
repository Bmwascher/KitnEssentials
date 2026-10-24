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
            -- A page's tabs are ids of their own: an admitted page with a
            -- refused tab renders its header alone.
            { load = "baseline",            seed = BASELINE,             id = "DamageMeter_Windows",      want = true },
            { load = "baseline",            seed = BASELINE,             id = "DamageMeter_Appearance",   want = true },
            { load = "baseline",            seed = BASELINE,             id = "DamageMeter_Behavior",     want = true },
            { load = "baseline",            seed = BASELINE,             id = "DamageMeter_SpellHistory", want = true },
            { load = "baseline",            seed = BASELINE,             id = "MythicPlusTimer",  want = false },
            { load = "baseline",            seed = BASELINE,             id = "LibDualSpec",      want = false },
            { load = "baseline",            seed = BASELINE,             id = "NotAFeature",      want = false },
            { load = "baseline",            seed = BASELINE,             id = nil,                want = false },
            { load = "baseline, no iface",  seed = BASELINE_UNREADABLE,  id = "HomePage",         want = true },
            { load = "baseline, no iface",  seed = BASELINE_UNREADABLE,  id = "LibDualSpec",      want = false },
            { load = "baseline, no iface",  seed = BASELINE_UNREADABLE,  id = "NicknameProvider", want = false },
            { load = "retail",              seed = RETAIL,               id = "MythicPlusTimer",  want = true },
            { load = "retail",              seed = RETAIL,               id = "NotAFeature",      want = true },
            { load = "retail, Forever iface", seed = RETAIL_FOREVER_IFACE, id = "MythicPlusTimer", want = true },
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
                profile = { MythicPlusTimer = { Enabled = true } },
                isLoaded = function(name) return name == "EllesmereUIMythicTimer" end,
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
    -- Mythic+ Timer stands for any withheld page and sits first, so a
    -- missing filter renders it in every row.
    it("lands a withheld remembered, nested or default tab on the first admitted tab", function()
        local rendered
        local GUIFrame = {
            registeredContent = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            CreateSubTabs = function(_, _, yOffset) return nil, yOffset end,
        }
        local KE = helpers.loadModule("Core/Availability.lua", { BASELINE_LOAD = true, IS_FOREVER = true, GUIFrame = GUIFrame })
        helpers.loadModule("GUI/GUIMain/GUI-TabbedContent.lua", KE)
        for _, id in ipairs({ "MythicPlusTimer", "ProfilesSharing", "ProfilesMain" }) do
            GUIFrame.registeredContent[id] = function(_, yOffset)
                rendered = id
                return yOffset
            end
        end
        GUIFrame:RegisterNestedTabs("MythicPlusTimer", { "MythicPlusTimerForms" })
        local TABS = {
            { id = "MythicPlusTimer", label = "Withheld" },
            { id = "ProfilesSharing", label = "Sharing" },
            { id = "ProfilesMain",    label = "Profile" },
        }
        for _, row in ipairs({
            { name = "remembered", remembered = "MythicPlusTimer" },
            { name = "nested",     remembered = "MythicPlusTimerForms" },
            { name = "default",    default = "MythicPlusTimer" },
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
    -- Mail stands for an admitted window, ContextMenus for an admitted row
    -- backed by its own module, and Friends for a withheld one.
    it("admits only the listed skin keys after a baseline load and every key after a retail load", function()
        for _, row in ipairs({
            { load = "baseline", baseline = true, key = "Mail",         want = true },
            { load = "baseline", baseline = true, key = "Friends",      want = false },
            { load = "baseline", baseline = true, key = "ContextMenus", want = true },
            { load = "baseline", baseline = true, key = nil,            want = false },
            { load = "retail",   baseline = nil,  key = "Friends",      want = true },
            { load = "retail",   baseline = nil,  key = "ContextMenus", want = true },
        }) do
            local KE = helpers.loadModule("Core/Availability.lua", { BASELINE_LOAD = row.baseline })
            assert.equals(row.want, KE:IsFrameSkinAvailable(row.key), row.load .. " " .. tostring(row.key))
        end
    end)
end)
