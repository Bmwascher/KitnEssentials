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
local PREVIEW_ICONS     = { 135936, 572025, 135966, 627485, 4622478, 237542 }
local PREVIEW_ICONS_BIG = { 136097, 615341, 136120 }

-- The BIG defensives group still leans on Blizzard's own curation, so it takes
-- the exclude set alone. The externals group is user-defined instead, and its
-- whitelist is what bounds it.
local function BuildCandidates()
    return { excludeSpellIDs = KE.AuraRules.BuildExcludeSpellIDs(nil) }
end

local function BuildExternalCandidates(settings)
    return {
        excludeSpellIDs = KE.AuraRules.BuildExcludeSpellIDs(nil),
        includeSpellIDs = KE.AuraRules.BuildIncludeSpellIDs(settings.Allowlist),
        -- Evaluated outside the container's identity permission, unlike the
        -- spell-id sets above, so it holds in combat and in a keystone where
        -- reading the caster in Lua does not.
        isFromPlayerOrPlayerPet = KE.AuraRules.SelfCastFilterValue(settings.HideSelfCast),
    }
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
            -- EXTERNAL_DEFENSIVE is deliberately absent. The candidate
            -- whitelist can only NARROW what the filter string admits, so
            -- keeping Blizzard's component would make the user's list an
            -- intersection with it rather than a replacement for it, and an
            -- added spell would never appear.
            buildFilter  = function() return "HELPFUL" end,
            buildCandidates = BuildExternalCandidates,
            capabilities = { hasBorder = true, hasDispelBadge = false, hasDispelRing = false, hasGlow = true },
        },
        {
            key          = "big",
            buildFilter  = function() return "HELPFUL|BIG_DEFENSIVE" end,
            buildCandidates = BuildCandidates,
            -- Only the externals group glows. Big defensives are shown
            -- un-glowed, and creating a host for both would silently start
            -- glowing personal cooldowns for every user with that option on.
            capabilities = { hasBorder = true, hasDispelBadge = false, hasDispelRing = false, hasGlow = false },
        },
    },

    splitLimit = function(total, settings)
        return KE.AuraRules.SplitExternalsLimit(total, settings.ShowBigDefensives)
    end,

    sounds = {
        -- Follows the allowlist rather than a fixed list. Blizzard's sound
        -- trigger takes one spell id, never a filter, so the registry is one
        -- registration per enabled row and grows with what the user adds.
        --
        -- HideSelfCast is deliberately NOT read here. UnitAuraSoundInfo carries
        -- a unit token and a spell id and nothing about who applied the aura,
        -- so a registration fires however the spell landed. Reading the caster
        -- in Lua instead is blocked while aura identities are hidden, which is
        -- every case that matters. The card says so.
        buildSpellIDs = function(settings)
            return KE.AuraRules.BuildSoundSpellIDs(settings and settings.Allowlist)
        end,
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
