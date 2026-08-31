-- ╔══════════════════════════════════════════════════════════╗
-- ║  AuraMovement.lua                                        ║
-- ║  Module: Aura Movement                                   ║
-- ║  Purpose: Displays movement-speed buffs on the player    ║
-- ║           (Sprint, Dash, etc.) via the allowlist.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class AuraMovement: AceModule, AceEvent-3.0
local AM = KitnEssentials:NewModule("AuraMovement", "AceEvent-3.0")

local PREVIEW_ICONS = { 132307, 132120, 135968 }

local function BuildMovementCandidates(settings)
    return {
        includeSpellIDs = KE.AuraRules.BuildIncludeSpellIDs(settings and settings.Allowlist),
    }
end

local function BuildMovementPreview(_, total)
    local entries = {}
    for i = 1, total do
        entries[i] = {
            icon = PREVIEW_ICONS[((i - 1) % #PREVIEW_ICONS) + 1],
            groupKey = "movement",
            count = 0,
        }
    end
    return entries
end

local DECLARATION = {
    key = "AuraMovement",
    dbKey = "AuraMovement",
    displayName = "Movement Buffs",
    sortMethod = "AuraInstanceIDOnly",
    defaultIconsPerRow = 3,

    groups = {
        {
            key = "movement",
            buildFilter = function() return "HELPFUL" end,
            buildCandidates = BuildMovementCandidates,
            capabilities = {
                hasBorder = true,
                hasDispelBadge = false,
                hasDispelRing = false,
                hasGlow = true,
            },
        },
    },

    splitLimit = function(total)
        return { movement = total }
    end,

    sounds = {
        buildSpellIDs = function(settings)
            return KE.AuraRules.BuildSoundSpellIDs(settings and settings.Allowlist)
        end,
        unit = "player",
        settingKeys = { enabled = "SoundEnabled", name = "SoundName" },
    },

    buildPreview = BuildMovementPreview,
}

function AM:UpdateDB()
    self.db = KE.db.profile.AuraMovement
end

function AM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function AM:OnEnable()
    self:UpdateDB()

    if not self.display then
        self.display = KE.AuraEngine.Register(self, DECLARATION, function() return self.db end)
    else
        KE.AuraEngine.RegisterEvents(self.display)
    end

    KE.AuraEngine.ApplySettings(self.display)
end

function AM:OnDisable()
    KE.AuraEngine.SetModuleEnabled(self.display, false)
end

function AM:ApplySettings()
    self:UpdateDB()
    KE.AuraEngine.ApplySettings(self.display)
end

function AM:ShowPreview()
    KE.AuraEngine.ShowPreview(self.display)
end

function AM:HidePreview()
    KE.AuraEngine.HidePreview(self.display)
end
