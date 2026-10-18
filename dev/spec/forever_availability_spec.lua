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
            { load = "baseline",            seed = BASELINE,             id = "SkinTooltips",     want = false },
            { load = "baseline",            seed = BASELINE,             id = "LibDualSpec",      want = false },
            { load = "baseline",            seed = BASELINE,             id = "NotAFeature",      want = false },
            { load = "baseline",            seed = BASELINE,             id = nil,                want = false },
            { load = "baseline, no iface",  seed = BASELINE_UNREADABLE,  id = "HomePage",         want = true },
            { load = "baseline, no iface",  seed = BASELINE_UNREADABLE,  id = "LibDualSpec",      want = false },
            { load = "baseline, no iface",  seed = BASELINE_UNREADABLE,  id = "NicknameProvider", want = false },
            { load = "retail",              seed = RETAIL,               id = "SkinTooltips",     want = true },
            { load = "retail",              seed = RETAIL,               id = "NotAFeature",      want = true },
            { load = "retail, Forever iface", seed = RETAIL_FOREVER_IFACE, id = "SkinTooltips",   want = true },
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
                profile = { Skinning = { Tooltips = { Enabled = true } } },
                isLoaded = function(name) return name == "TipTac" end,
                shouldNotLoad = false,
            })
            assert.equals(row.prompts, #queue, row.name)
        end
    end)
end)
