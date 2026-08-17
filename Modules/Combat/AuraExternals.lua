-- ╔══════════════════════════════════════════════════════════╗
-- ║  AuraExternals.lua                                       ║
-- ║  Module: Aura Externals                                  ║
-- ║  Purpose: Displays external defensives cast on the       ║
-- ║           player (Pain Suppression, Ironbark, etc.) with ║
-- ║           optional glow on EXTERNAL_DEFENSIVE auras.     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class AuraExternals: AceModule, AceEvent-3.0
local AX = KitnEssentials:NewModule("AuraExternals", "AceEvent-3.0")

-- Preview icon sets used to populate the GUI page preview.
--   PREVIEW_ICONS     — all-external set
--   PREVIEW_ICONS_BIG — big-defensives-only set
local PREVIEW_ICONS     = { 135936, 572025, 135966, 627485, 4622478, 237542 }
local PREVIEW_ICONS_BIG = { 136097, 615341, 136120 }

-- Externals has no user blocklist, so this is the hardcoded set alone. It is
-- still routed through the shared rule rather than being built here, so both
-- displays exclude the same nine and one change reaches both.
local function BuildCandidates()
    return { excludeSpellIDs = KE.AuraRules.BuildExcludeSpellIDs(nil) }
end

local DECLARATION = {
    key                = "AuraExternals",
    dbKey              = "AuraExternals",
    -- Edit Mode falls back to the key when this is absent, which would label
    -- the mover with the unspaced identifier instead of its display name.
    displayName        = "Aura Externals",
    sortMethod         = "AuraInstanceIDOnly",
    defaultIconsPerRow = 6,   -- this module's existing fallback; Debuffs uses 8

    -- ORDER IS LOAD-BEARING. Registration order is the on-screen block order,
    -- so externals must be declared first.
    groups = {
        {
            key          = "external",
            buildFilter  = function() return "HELPFUL|EXTERNAL_DEFENSIVE" end,
            buildCandidates = BuildCandidates,
            capabilities = { hasBorder = true, hasDispel = false, hasGlow = true },
        },
        {
            key          = "big",
            buildFilter  = function() return "HELPFUL|BIG_DEFENSIVE" end,
            buildCandidates = BuildCandidates,
            capabilities = { hasBorder = true, hasDispel = false, hasGlow = false },
        },
    },

    splitLimit = function(total, settings)
        return KE.AuraRules.SplitExternalsLimit(total, settings.ShowBigDefensives)
    end,

    -- Only the externals group glows. Big defensives are shown un-glowed, and
    -- creating a host for both would silently start glowing personal
    -- cooldowns for every user with that option on.
    sounds = {
        spellIDs    = { 6940, 47788, 255312, 102342, 116849, 357170, 53480 },
        unit        = "player",
        settingKeys = { enabled = "SoundEnabled", name = "SoundName" },
    },

    buildPreview = function(settings, total)
        return KE.AuraRules.BuildExternalsPreview(
            PREVIEW_ICONS, PREVIEW_ICONS_BIG, total, settings.ShowBigDefensives)
    end,
}

function AX:UpdateDB()
    self.db = KE.db.profile.AuraExternals
end

function AX:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- AceAddon calls OnEnable on EVERY enable, including a re-enable after the
-- user switches the module off and on. Registering unguarded would build a
-- second display and a second container with the same frame names. AceEvent
-- unregisters the module's events on disable, so a re-enable has to put them
-- back — which is why this is a guard plus a re-registration, not a plain
-- early return.
function AX:OnEnable()
    self:UpdateDB()

    if not self.display then
        self.display = KE.AuraEngine.Register(self, DECLARATION, function() return self.db end)
    else
        KE.AuraEngine.RegisterEvents(self.display)
    end

    KE.AuraEngine.ApplySettings(self.display)
end

function AX:OnDisable()
    KE.AuraEngine.SetModuleEnabled(self.display, false)
end

function AX:ApplySettings()
    self:UpdateDB()
    KE.AuraEngine.ApplySettings(self.display)
end

function AX:ShowPreview()
    KE.AuraEngine.ShowPreview(self.display)
end

function AX:HidePreview()
    KE.AuraEngine.HidePreview(self.display)
end
