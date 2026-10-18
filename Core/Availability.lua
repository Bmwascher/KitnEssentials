-- ╔══════════════════════════════════════════════════════════╗
-- ║  Availability.lua                                        ║
-- ║  Purpose: Which features this client runs: one answer    ║
-- ║           for loading, settings, previews and refresh.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

-- The policy follows the lists the TOC loaded, never the interface version:
-- after a baseline load (Core/BaselineLoad.lua) only the baseline runs, after
-- a retail load everything does, so policy and loaded files cannot disagree.
local RETAIL = KE.BASELINE_LOAD ~= true

-- The only features of a baseline load until each category is admitted. A
-- saved Enabled flag or an imported profile never adds to the list.
local FOREVER_ALLOWED = {
    HomePage = true,
    Profiles = true,
    ProfilesMain = true,
    ProfilesSharing = true,
    ProfilesReset = true,
}

-- Ids are module names, sidebar rows, sub-tabs and optional integrations.
-- A retail load admits every id; a baseline load refuses any id not above.
---@param featureId string?
---@return boolean available
---@return string? reason
function KE:IsFeatureAvailable(featureId)
    if RETAIL then return true end
    if featureId and FOREVER_ALLOWED[featureId] then return true end
    return false, "withheld on this client"
end
