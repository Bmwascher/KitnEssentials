-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer_Overlay.lua                             ║
-- ║  Module: Mythic+ Timer — enemy overlay                   ║
-- ║  Purpose: Folded ex-WarpDepleteForces nameplate enemy-%  ║
-- ║           + tooltip count via                            ║
-- ║           C_ScenarioInfo.GetUnitCriteriaProgressValues.  ║
-- ║           Per-unit read is format-passthrough only       ║
-- ║           (truthy check, NO math) — secret-safe.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local MPT = KitnEssentials:GetModule("MythicPlusTimer")

-- One-time migration: carry retired WarpDepleteForces overlay settings into
-- this module's flat Overlay* keys. Guarded by a persistent OverlayMigrated
-- flag — NOT by the old table being nil, because AceDB/FillProfileDefaults
-- resurrect profile.Dungeons.WarpDepleteForces (with default values) on
-- every login until Task 4.8 removes the Core/Defaults.lua block.
-- Maps old WDF key -> new MPT Overlay* key. Death-log persistence is dropped
-- (the new module keeps deaths transient in MPT.run.deathLog).
function MPT:MigrateLegacyOverlayDB()
    if self.db.OverlayMigrated then return end
    self.db.OverlayMigrated = true   -- unconditional set: fresh installs are marked done too

    local profile = KE.db and KE.db.profile
    local old = profile and profile.Dungeons and profile.Dungeons.WarpDepleteForces
    if not old then return end

    local map = {
        Tooltip              = "OverlayTooltipEnabled",
        NameplatePercent     = "OverlayNameplateEnabled",
        NameplateCombatOnly  = "OverlayCombatOnly",
        NameplateFontFace    = "OverlayFontFace",
        NameplateFontSize    = "OverlayFontSize",
        NameplateFontOutline = "OverlayFontOutline",
        NameplateColorMode   = "OverlayColorMode",
        NameplateColor       = "OverlayColor",
        NameplateAnchor      = "OverlayAnchor",
        NameplateXOffset     = "OverlayXOffset",
        NameplateYOffset     = "OverlayYOffset",
    }
    for oldKey, newKey in pairs(map) do
        if old[oldKey] ~= nil then
            self.db[newKey] = old[oldKey]
        end
    end

    -- Old table is fully retired (Instance Reset Announcer + DeathLog drop with it).
    -- Deliberately NOT nil-ing profile.Dungeons.WarpDepleteForces here: the live
    -- WDF module re-binds self.db to that slot on every profile switch
    -- (ProfileManager duck-types UpdateDB) and would crash on a nil section.
    -- Task 4.8 removes the WDF module + its Defaults.lua block; the slot dies there.
end
