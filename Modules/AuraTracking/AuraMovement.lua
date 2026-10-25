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

-- Own casts take the odd slot: most movement buffs are your own.
local function SplitLimit(total, settings)
    local split = KE.AuraRules.SplitOwnCastLimit(total, KE.AuraRules.IsOwnNameSplit(settings), true)
    return { movement = split.others, movementOwn = split.own }
end

local function BuildMovementPreview(settings, total)
    local limits = SplitLimit(total, settings)
    local entries = {}
    local function append(groupKey)
        for i = 1, limits[groupKey] do
            entries[#entries + 1] = {
                icon = PREVIEW_ICONS[((i - 1) % #PREVIEW_ICONS) + 1],
                groupKey = groupKey,
                count = 0,
            }
        end
    end
    append("movement")
    append("movementOwn")
    return entries
end

local DECLARATION = {
    key = "AuraMovement",
    dbKey = "AuraMovement",
    displayName = "Movement Buffs",
    sortMethod = "AuraInstanceIDOnly",
    defaultIconsPerRow = 3,

    -- Registration order is the on-screen block order: others' buffs first,
    -- your own next.
    groups = {
        {
            key = "movement",
            buildFilter = function(settings) return KE.AuraRules.OthersFilterString(settings) end,
            buildCandidates = BuildMovementCandidates,
            capabilities = {
                hasBorder = true,
                hasDispelBadge = false,
                hasDispelRing = false,
                hasGlow = true,
                hasCasterName = true,
            },
        },
        {
            -- Your own movement buffs while Hide My Own Name is on, with no
            -- name region, so the game never writes your name under them.
            -- Zero icons otherwise.
            key = "movementOwn",
            buildFilter = function() return KE.AuraRules.OWN_FILTER end,
            buildCandidates = BuildMovementCandidates,
            capabilities = {
                hasBorder = true,
                hasDispelBadge = false,
                hasDispelRing = false,
                hasGlow = true,
            },
        },
    },

    splitLimit = SplitLimit,

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
    if not self.db or not self.db.Enabled then return end

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
