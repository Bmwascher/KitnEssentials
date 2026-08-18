-- ╔══════════════════════════════════════════════════════════╗
-- ║  AuraDebuffs.lua                                         ║
-- ║  Module: Aura Debuffs                                    ║
-- ║  Purpose: Declares the dispellable/important debuff      ║
-- ║           display to the aura engine (Modules/Combat/    ║
-- ║           AuraEngine/). Visibility is filter-driven; the ║
-- ║           engine owns the container, rendering, and the  ║
-- ║           live aura pipeline. This module owns the       ║
-- ║           dispel colour palette, since it is the only    ║
-- ║           display with dispel settings.                  ║
-- ║  Subsumes: BossDebuffs (migrated then deleted).           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class AuraDebuffs: AceModule, AceEvent-3.0
local AD = KitnEssentials:NewModule("AuraDebuffs", "AceEvent-3.0")

local C_CurveUtil = C_CurveUtil
local CreateColor = CreateColor
local pairs, ipairs = pairs, ipairs

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------

-- Default blocklist entries (populated once on first enable).
-- Non-boss Bloodlust variants the player never wants cluttering the display.
local DEFAULT_BLOCKLIST = {
    [390435] = { label = "BL (Hunter)", enabled = true, default = true },
    [57723]  = { label = "BL (Drums)",  enabled = true, default = true },
    [95809]  = { label = "BL (Hunter)", enabled = true, default = true },
    [80354]  = { label = "BL (Mage)",   enabled = true, default = true },
    [308312] = { label = "Time Trial",  enabled = true, default = true },
    [57724]  = { label = "BL (Shaman)", enabled = true, default = true },
    [160455] = { label = "BL (Hunter)", enabled = true, default = true },
    [264689] = { label = "BL (Hunter)", enabled = true, default = true },
}

-- Per-dispel-type defaults (matches the GUI's Dispel Type Colors card 1:1).
-- Used as fallback when user hasn't customized db.DispelColors[type]. Also
-- fed into the LuaCurveObject color curve so the curve has a value for
-- every dispel integer (encounter HARMFUL auras resolve correctly even
-- without user overrides).
local DISPEL_DEFAULTS = {
    None    = { 0.800, 0.000, 0.000, 1 },
    Magic   = { 0.000, 0.506, 1.000, 1 },
    Curse   = { 0.624, 0.024, 0.894, 1 },
    Disease = { 0.945, 0.416, 0.035, 1 },
    Poison  = { 0.482, 0.780, 0.000, 1 },
    Bleed   = { 0.722, 0.000, 0.059, 1 },
    Enrage  = { 0.953, 0.373, 0.961, 1 },
}

---------------------------------------------------------------------------------
-- LuaCurveObject-based dispel detection (taint-safe for encounter HARMFUL)
--
-- aura.dispelName is a secret string for encounter auras in 12.0, which makes
-- `==` and `:lower()` taint. The curve API (C_UnitAuras.GetAuraDispelTypeColor)
-- evaluates a LuaCurveObject against the aura's dispel-type integer internally
-- — no string operations on the secret value — so it resolves correctly for
-- encounter auras too. The engine's dispel ring (Style.lua) consumes this same
-- curve via the group's getDispelColorCurve accessor below.
--
-- Dispel-type integers come from the SpellDispelType db2 table:
-- https://wago.tools/db2/SpellDispelType — hardcoded here because
-- Blizzard's `Enum.DispelType` isn't reliably populated for addons.
--
-- _dispelColorCurve — the color curve mapping dispel integer → user color.
--                     Rebuilt on each ApplySettings so GUI edits to
--                     DispelColors take effect on the next reconfiguration.
---------------------------------------------------------------------------------

local DISPEL_TYPE_INDEX = {
    None    = 0,
    Magic   = 1,
    Curse   = 2,
    Disease = 3,
    Poison  = 4,
    Enrage  = 9,
    Bleed   = 11,
}

local _dispelColorCurve = nil

local function RebuildDispelColorCurve(db)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType and CreateColor) then
        return
    end
    if not _dispelColorCurve then
        _dispelColorCurve = C_CurveUtil.CreateColorCurve()
        _dispelColorCurve:SetType(Enum.LuaCurveType.Step)
    else
        _dispelColorCurve:ClearPoints()
    end

    -- Add a point for every dispel type we know about (including None) so
    -- the curve resolves to a color even for non-dispellable auras in
    -- "dispel" mode.
    local mappedTypes = { "None", "Magic", "Curse", "Disease", "Poison", "Bleed", "Enrage" }
    for _, name in ipairs(mappedTypes) do
        local typeInt = DISPEL_TYPE_INDEX[name]
        if typeInt ~= nil then
            local color = (db.DispelColors and db.DispelColors[name])
                       or DISPEL_DEFAULTS[name]
            if color then
                _dispelColorCurve:AddPoint(typeInt,
                    CreateColor(color[1], color[2], color[3], color[4] or 1))
            end
        end
    end
end

-- Public accessor so sibling modules reuse the same dispel palette the user
-- configures here, instead of duplicating the curve. Lazily
-- builds from this module's DB so it resolves even when AuraDebuffs itself is
-- disabled (the palette still lives in the profile). Returns a LuaCurveObject
-- (or nil if the curve API is unavailable); callers pass it straight to
-- C_UnitAuras.GetAuraDispelTypeColor.
function AD:GetDispelColorCurve()
    if not _dispelColorCurve then
        local db = self.db or (KE.db and KE.db.profile and KE.db.profile.AuraDebuffs)
        if db then RebuildDispelColorCurve(db) end
    end
    return _dispelColorCurve
end

-- Preview-only counterpart to the curve above: resolves a flat RGBA for one
-- dispel type instead of feeding Blizzard's per-aura repaint, since a preview
-- frame accepts no such registration. Mirrors the curve's own resolution
-- order so the preview always matches what the live ring would show.
local function ResolveDispelPreviewColor(settings, dispelType, palette)
    if settings.BorderColorMode == "dispel" then
        local pal   = palette or settings.DispelColors
        local color = (pal and pal[dispelType]) or DISPEL_DEFAULTS[dispelType]
        if color then
            return KE:ResolveColor(color, { 0.8, 0, 0, 1 })
        end
    end
    return KE:ResolveColor(settings.BorderColor, { 0.8, 0, 0, 1 })
end

-- Preview counterpart to GetDispelColorCurve, exposed for the same reason:
-- another display borrows this palette for its ring, so its preview has to
-- resolve the same colours the live ring will. The caller's own settings still
-- decide the colour mode and the flat fallback; only the palette is borrowed.
function AD:GetDispelPreviewColor(settings, dispelType)
    return ResolveDispelPreviewColor(settings, dispelType, self.db and self.db.DispelColors)
end

-- Preview icons + dispel sequence used to populate the live grid when the
-- user opens the GUI page. Dispel sequence is None → Magic → Curse →
-- Disease → Poison → Bleed (None has no atlas overlay). Cycled by
-- DECLARATION.buildPreview below.
local PREVIEW_ICONS        = { 7548988, 136188, 136137, 1029009, 132104, 132090 }
local PREVIEW_DISPEL_TYPES = { "None", "Magic", "Curse", "Disease", "Poison", "Bleed" }

---------------------------------------------------------------------------------
-- One-shot Migration: BossDebuffs → AuraDebuffs
---------------------------------------------------------------------------------

local function MigrateFromBossDebuffs(profile)
    local oldBD = profile.BossDebuffs
    local ad    = profile.AuraDebuffs
    if not oldBD or not ad or ad._migratedFromBD then return end
    ad._migratedFromBD = true

    -- AuraDebuffs is filter-driven now (no VisibilityMode / EncounterBlacklist),
    -- so we only carry forward keys that still exist on the new module.
    if oldBD.Enabled            then ad.Enabled        = true end
    ad.Position           = oldBD.Position           or ad.Position
    ad.anchorFrameType    = oldBD.anchorFrameType    or ad.anchorFrameType
    ad.IconSize           = oldBD.IconSize           or ad.IconSize
    ad.Strata             = oldBD.Strata             or ad.Strata
end

---------------------------------------------------------------------------------
-- Engine declaration
---------------------------------------------------------------------------------

local DECLARATION = {
    key                = "AuraDebuffs",
    dbKey              = "AuraDebuffs",
    -- Edit Mode falls back to the key when this is absent, which would label
    -- the mover with the unspaced identifier instead of its display name.
    displayName        = "Aura Debuffs",
    sortMethod         = "AuraInstanceIDOnly",
    defaultIconsPerRow = 8,   -- this module's existing fallback; Externals uses 6

    groups = {
        {
            key         = "debuffs",
            buildFilter = function(settings)
                return KE.AuraRules.BuildDebuffFilter(settings.Filters)
            end,
            buildCandidates = function(settings)
                return { excludeSpellIDs = KE.AuraRules.BuildExcludeSpellIDs(settings.Blocklist) }
            end,
            capabilities = { hasBorder = true, hasDispelBadge = true, hasDispelRing = true, hasGlow = false },

            -- The dispel texture registration needs this, and only this
            -- display has the colours. The rebuild mutates the existing
            -- curve object in place rather than replacing it, so a palette
            -- edit is already visible through it even when a settings
            -- reapplication defers before reaching the re-registration step.
            getDispelColorCurve = function() return AD:GetDispelColorCurve() end,

            -- group.getDispelPreviewColor(settings, dispelType) -> r, g, b, a
            -- Optional, declared only by a group that has a per-type palette.
            -- Absent means the preview falls back to the flat border colour,
            -- which is correct for a group with no palette.
            getDispelPreviewColor = ResolveDispelPreviewColor,
        },
    },

    -- One group, so the whole limit goes to it. splitLimit still returns a
    -- table keyed by group so the engine has one shape to apply.
    splitLimit = function(total)
        return { debuffs = total }
    end,

    -- No sounds table at all: this display registers nothing and never sets
    -- the sound pending flag, even under restriction.

    buildPreview = function(_, total)
        local entries = {}
        for i = 1, total do
            local idx = ((i - 1) % #PREVIEW_ICONS) + 1
            entries[i] = {
                icon       = PREVIEW_ICONS[idx],
                dispelType = PREVIEW_DISPEL_TYPES[idx],
                groupKey   = "debuffs",
                count      = (i % 4 == 1 and 2) or (i % 4 == 2 and 5) or 0,
            }
        end
        return entries
    end,
}

---------------------------------------------------------------------------------
-- DB Helpers
---------------------------------------------------------------------------------

function AD:UpdateDB()
    self.db = KE.db.profile.AuraDebuffs
end

function AD:ApplyDefaultBlocklist()
    local bl = self.db.Blocklist
    if not bl then self.db.Blocklist = {}; bl = self.db.Blocklist end
    for sid, entry in pairs(DEFAULT_BLOCKLIST) do
        if bl[sid] == nil then
            bl[sid] = { label = entry.label, enabled = entry.enabled, default = entry.default }
        end
    end
end

function AD:RestoreBlocklistDefaults()
    local bl = self.db.Blocklist
    if not bl then self.db.Blocklist = {}; bl = self.db.Blocklist end
    for sid, entry in pairs(DEFAULT_BLOCKLIST) do
        bl[sid] = { label = entry.label, enabled = entry.enabled, default = entry.default }
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function AD:OnInitialize()
    MigrateFromBossDebuffs(KE.db.profile)
    self:UpdateDB()
    self:ApplyDefaultBlocklist()
    self:SetEnabledState(false)
end

-- AceAddon calls OnEnable on EVERY enable, including a re-enable after the
-- user switches the module off and on. Registering unguarded would build a
-- second display and a second container with the same frame names. AceEvent
-- unregisters the module's events on disable, so a re-enable has to put them
-- back — which is why this is a guard plus a re-registration, not a plain
-- early return.
function AD:OnEnable()
    self:UpdateDB()
    self:ApplyDefaultBlocklist()
    -- Rebuild the dispel color curve up front so the very first paint has
    -- correct per-type colors: the engine reads the curve through
    -- getDispelColorCurve during container creation below.
    RebuildDispelColorCurve(self.db)

    if not self.display then
        self.display = KE.AuraEngine.Register(self, DECLARATION, function() return self.db end)
    else
        KE.AuraEngine.RegisterEvents(self.display)
    end

    KE.AuraEngine.ApplySettings(self.display)
end

function AD:OnDisable()
    KE.AuraEngine.SetModuleEnabled(self.display, false)
end

function AD:ApplySettings()
    self:UpdateDB()
    self:ApplyDefaultBlocklist()
    -- Rebuild the dispel color curve so any GUI edits to DispelColors are
    -- picked up on the next reconfiguration, before the engine reads it.
    RebuildDispelColorCurve(self.db)
    KE.AuraEngine.ApplySettings(self.display)
end

function AD:ShowPreview()
    KE.AuraEngine.ShowPreview(self.display)
end

function AD:HidePreview()
    KE.AuraEngine.HidePreview(self.display)
end
