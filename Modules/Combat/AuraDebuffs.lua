-- ╔══════════════════════════════════════════════════════════╗
-- ║  AuraDebuffs.lua                                         ║
-- ║  Module: Aura Debuffs                                    ║
-- ║  Purpose: Displays dispellable/important debuffs on the  ║
-- ║           player. Visibility is filter-driven — the      ║
-- ║           module is always active when Enabled and lets  ║
-- ║           the Filters card decide which auras to show.   ║
-- ║  Subsumes: BossDebuffs (migrated then deleted).          ║
-- ║                                                          ║
-- ║  Aura pipeline:                                          ║
-- ║   - GetUnitAuraInstanceIDs / GetAuraDataByAuraInstanceID ║
-- ║   - ShouldShowAura with per-filter IsAuraFilteredOutBy*  ║
-- ║     AND-check (so multi-filter intersection is correct)  ║
-- ║   - UNIT_AURA updateInfo for incremental                 ║
-- ║     ProcessAuraUpdate; falls back to QueueFullRefresh    ║
-- ║     on isFullUpdate or missing updateInfo                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class AuraDebuffs: AceModule, AceEvent-3.0
local AD = KitnEssentials:NewModule("AuraDebuffs", "AceEvent-3.0")

local C_UnitAuras         = C_UnitAuras
local C_CurveUtil         = C_CurveUtil
local CreateFrame         = CreateFrame
local CreateColor         = CreateColor
local UIParent            = UIParent
local GameTooltip         = GameTooltip
local GetTime             = GetTime
local C_Timer             = C_Timer
local pairs, ipairs       = pairs, ipairs
local wipe                = wipe
local tinsert             = table.insert
local tsort               = table.sort
local math_min            = math.min
local math_floor          = math.floor
local issecretvalue       = issecretvalue

local UNIT = "player"

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

-- Dispel-type overlays using Blizzard's raid-frame atlases.
-- Keyed by canonical dispel-type STRING (not Enum.DispelType.*) because
-- Enum.DispelType is not guaranteed populated at file-parse time on every
-- patch — referencing it during file load throws "attempt to index field
-- 'DispelType' (a nil value)" and kills the rest of the module. String keys
-- bypass that entirely.
local DISPEL_ICON_ATLASES = {
    Magic   = "RaidFrame-Icon-DebuffMagic",
    Curse   = "RaidFrame-Icon-DebuffCurse",
    Disease = "RaidFrame-Icon-DebuffDisease",
    Poison  = "RaidFrame-Icon-DebuffPoison",
    Bleed   = "RaidFrame-Icon-DebuffBleed",
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

-- Ordered list of dispel types KE renders. "None" omitted from atlas/curve
-- iteration (no atlas for non-dispellable, and curve evaluation of "None"
-- isn't needed since alpha curves only fire for the 5 dispellable types
-- plus Enrage). Iteration order is deterministic so we always resolve the
-- same way.
local DISPEL_TYPE_ORDER = { "Magic", "Curse", "Disease", "Poison", "Bleed", "Enrage" }

---------------------------------------------------------------------------------
-- LuaCurveObject-based dispel detection (taint-safe for encounter HARMFUL)
--
-- aura.dispelName is a secret string for encounter auras in 12.0, which makes
-- `==` and `:lower()` taint. The curve API (C_UnitAuras.GetAuraDispelTypeColor)
-- evaluates a LuaCurveObject against the aura's dispel-type integer internally
-- — no string operations on the secret value — so it resolves correctly for
-- encounter auras too. Pattern ported from AE v4 (Utils/Curves.lua + Utils/
-- Colors.lua:GetDispelColorCurve).
--
-- Dispel-type integers come from the SpellDispelType db2 table:
-- https://wago.tools/db2/SpellDispelType — hardcoded here because
-- Blizzard's `Enum.DispelType` isn't reliably populated for addons. AE
-- ships the same hardcoded map for the same reason.
--
-- _dispelColorCurve  — main border-color curve mapping dispel integer → user
--                      color. Rebuilt on each ApplySettings so GUI edits to
--                      DispelColors take effect.
-- _dispelAlphaCurves — one per dispellable type. Each evaluates to alpha 1
--                      for its matching dispel integer and 0 for all others,
--                      so iterating them tells us which type the aura is.
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
local _dispelAlphaCurves = nil

local function BuildDispelAlphaCurves()
    if _dispelAlphaCurves then return end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType and CreateColor) then
        return
    end
    local visible     = CreateColor(1, 1, 1, 1)
    local transparent = CreateColor(1, 1, 1, 0)

    _dispelAlphaCurves = {}
    for _, name in ipairs(DISPEL_TYPE_ORDER) do
        local target = DISPEL_TYPE_INDEX[name]
        if target ~= nil then
            local curve = C_CurveUtil.CreateColorCurve()
            curve:SetType(Enum.LuaCurveType.Step)
            for _, idx in pairs(DISPEL_TYPE_INDEX) do
                curve:AddPoint(idx, idx == target and visible or transparent)
            end
            _dispelAlphaCurves[name] = curve
        end
    end
end

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

-- Per-type alpha for a real aura. Returns the curve's Color object (with
-- alpha 1 for matching dispel type, 0 otherwise) or nil if the curve
-- isn't available. The Color's r/g/b/a may be SECRET on encounter HARMFUL
-- auras — do not compare or do arithmetic on them; only pass them through
-- to Blizzard APIs that accept secrets (SetAlpha, SetColorTexture, etc.).
local function GetDispelAlphaColor(auraInstanceID, name)
    BuildDispelAlphaCurves()
    if not _dispelAlphaCurves then return nil end
    local curve = _dispelAlphaCurves[name]
    if not curve then return nil end
    return C_UnitAuras.GetAuraDispelTypeColor(UNIT, auraInstanceID, curve)
end

-- Main color curve query. Returns the Color object directly (don't unpack
-- into {r,g,b,a} here — the values may be secret and a `local color = {...}`
-- table preserves them, but later arithmetic / compare would taint. Callers
-- pass the Color straight into SetColorTexture / SetVertexColor instead.)
local function GetDispelColor(auraInstanceID)
    if not _dispelColorCurve then return nil end
    return C_UnitAuras.GetAuraDispelTypeColor(UNIT, auraInstanceID, _dispelColorCurve)
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

-- Valid Blizzard AuraFilters tokens for HARMFUL aura filtering, per
-- AuraUtil.AuraFilters in Blizzard_FrameXMLUtil/AuraUtil.lua. The remaining
-- tokens in that table (CANCELABLE, NOT_CANCELABLE, EXTERNAL_DEFENSIVE,
-- BIG_DEFENSIVE, MAW) are HELPFUL-side concepts and don't apply to HARMFUL
-- aura filtering — using them would always return zero auras.
--
-- Semantics: each enabled filter REMOVES matching auras from tracking
-- (i.e., "select filter(s) that you want to remove from tracking"), so
-- ShouldShowAura returns false for any aura that matches an enabled filter.
local FILTER_KEYS = {
    "PLAYER",
    "RAID",
    "CROWD_CONTROL",
    "IMPORTANT",
    "RAID_PLAYER_DISPELLABLE",
    "INCLUDE_NAME_PLATE_ONLY",
    -- RAID_IN_COMBAT excluded: per AuraUtil.AuraFilters it's intended for
    -- HELPFUL self-cast HoT detection (combat-only raid-frame helpfuls), so
    -- it doesn't meaningfully filter HARMFUL debuffs.
}

-- Preview icons + dispel sequence used to populate the live grid when the
-- user opens the GUI page. Dispel sequence is None → Magic → Curse →
-- Disease → Poison → Bleed (None has no atlas overlay). Built dynamically
-- per Refresh so the user sees the full grid up to IconsPerRow * MaxRows
-- by cycling the 6-icon source.
local PREVIEW_ICONS        = { 7548988, 136188, 136137, 1029009, 132104, 132090 }
local PREVIEW_DISPEL_TYPES = { "None", "Magic", "Curse", "Disease", "Poison", "Bleed" }

local function BuildPreviewAuras(db)
    local list = {}
    local previewCount = (db.IconsPerRow or 8) * (db.MaxRows or 1)
    local now = GetTime()
    for i = 1, previewCount do
        local idx       = ((i - 1) % #PREVIEW_ICONS) + 1
        local duration  = 10 + ((i * 5) % 30)
        local startTime = now - (duration * (0.2 + (i % 5) * 0.1))
        -- Show a few different stack counts so the stack-text positioning
        -- is visible (sparse-count pattern).
        local count
        if i % 4 == 1 then count = 2
        elseif i % 4 == 2 then count = 5
        else count = 0 end
        list[i] = {
            auraInstanceID = i,                     -- synthetic; never collides with real IDs
            spellId        = 0,
            icon           = PREVIEW_ICONS[idx],
            duration       = duration,
            expirationTime = startTime + duration,
            count          = count,
            dispelType     = PREVIEW_DISPEL_TYPES[idx],
        }
    end
    return list
end

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

AD.buttons            = {}
AD.frame              = nil
AD.isPreview          = false
AD.editModeRegistered = false
AD._pendingFullRefresh = false
AD.activeAuras        = {}  -- auraInstanceID -> true (currently displayed)
AD.auraCache          = {}  -- ordered array of aura data for last RefreshAllAuras
AD.filterStrings      = {}  -- built by BuildFilterStrings

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
-- DB Helpers
---------------------------------------------------------------------------------

function AD:UpdateDB()
    self.db = KE.db.profile.AuraDebuffs
    self:BuildFilterStrings()
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

-- Build ONE filter string per active filter key
-- (`{"HARMFUL|PLAYER", "HARMFUL|RAID", ...}`). ShouldShowAura then AND-checks
-- each filter separately via IsAuraFilteredOutByInstanceID. Concatenating all
-- selected filters into a single string would compose the wrong logical
-- relation (most token combos AND inside one string, but PLAYER+RAID for
-- example would produce an empty intersection on real auras).
function AD:BuildFilterStrings()
    self.filterStrings = wipe(self.filterStrings or {})
    if not self.db or not self.db.Filters then return end
    for _, key in ipairs(FILTER_KEYS) do
        if self.db.Filters[key] then
            tinsert(self.filterStrings, "HARMFUL|" .. key)
        end
    end
end

---------------------------------------------------------------------------------
-- Visibility — module is filter-driven; show whenever enabled and let the
-- filter set (PLAYER, RAID, CROWD_CONTROL, ...) decide which auras qualify.
-- Preview always passes.
---------------------------------------------------------------------------------

function AD:ShouldShow()
    if self.isPreview then return true end
    return self.db.Enabled == true
end

-- ShouldShowAura pipeline:
--   1. Generic HARMFUL sanity check — skip auras that are NOT harmful. The
--      UNIT_AURA `addedAuras` path delivers HELPFUL events too, so we
--      explicitly reject anything the HARMFUL filter reports as filtered
--      out (= a buff). Secret returns (encounter debuffs are commonly
--      secret here) are trusted through.
--   2. Blocklist (skip if spellId came back secret).
--   3. Per-filter AND-check (secret-guarded). Each enabled filter REMOVES
--      auras that match the combined filter (e.g. PLAYER removes
--      "HARMFUL|PLAYER" auras). IsAuraFilteredOutByInstanceID returns
--      false when the aura matches the full token set, so `not filtered → skip`.
--
-- API semantics reminder: IsAuraFilteredOutByInstanceID returns true when
-- the aura is filtered OUT (excluded) by the filter. false means the aura
-- matches/passes the filter.
local function ShouldShowAura(auraInstanceID, aura, db, filterStrings)
    if not aura then return false end

    -- HARMFUL sanity check. isFiltered=true means the aura is excluded by
    -- the HARMFUL filter — i.e. it's a buff — so skip it. Trust secret
    -- returns through (don't reject a possible debuff just because the
    -- check came back tainted).
    local isFiltered = C_UnitAuras.IsAuraFilteredOutByInstanceID(UNIT, auraInstanceID, "HARMFUL")
    if not (issecretvalue and issecretvalue(isFiltered)) and isFiltered then
        return false
    end

    -- Blocklist (skip if spellId came back secret).
    local spellId = aura.spellId
    if spellId and not (issecretvalue and issecretvalue(spellId)) then
        local entry = db.Blocklist and db.Blocklist[spellId]
        if entry and entry.enabled then return false end
    end

    -- Per-filter AND-check: each filter REMOVES auras that match it.
    if filterStrings and #filterStrings > 0 then
        for _, filter in ipairs(filterStrings) do
            local filtered = C_UnitAuras.IsAuraFilteredOutByInstanceID(UNIT, auraInstanceID, filter)
            if not (issecretvalue and issecretvalue(filtered)) and not filtered then
                return false
            end
        end
    end

    return true
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

function AD:OnEnable()
    self:UpdateDB()
    -- Build the dispel color curve up front so the very first paint has
    -- correct per-type colors (RefreshAllAuras runs below). The alpha
    -- curves used by ResolveDispelTypeName build themselves lazily on
    -- first call.
    RebuildDispelColorCurve(self.db)
    self._pendingFullRefresh = false
    wipe(self.activeAuras)
    wipe(self.auraCache)
    if not self.frame then self:CreateContainer() end

    self:RegisterEvent("UNIT_AURA",              "OnUnitAura")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",   "QueueFullRefresh")

    self:RefreshAllAuras()
end

function AD:OnDisable()
    self:UnregisterAllEvents()
    if self.frame then self.frame:Hide() end
    for _, b in pairs(self.buttons) do
        if b.cooldown then b.cooldown:Clear() end
        if b.stack then b.stack:SetText("") end
        b:Hide()
    end
    wipe(self.activeAuras)
    wipe(self.auraCache)
end

-- Sizing the container to the actual icon grid (rather than 1x1) gives the
-- EditMode mover a real hitbox to grab; the icons themselves still anchor
-- off self.frame's anchor corner via LayoutButtons.
local function GetFrameSize(db)
    local cols = db.IconsPerRow or 8
    local rows = db.MaxRows or 1
    local w = cols * db.IconSize + (cols - 1) * db.IconSpacing
    local h = rows * db.IconSize + (rows - 1) * db.IconSpacing
    return w, h
end

function AD:ApplySettings()
    self:UpdateDB()
    self:ApplyDefaultBlocklist()
    -- Rebuild the dispel color curve so any GUI edits to DispelColors are
    -- picked up by ResolveDispelColorRGBA on the next paint.
    RebuildDispelColorCurve(self.db)
    if self.frame then
        self.frame:SetSize(GetFrameSize(self.db))
        KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
        self.frame:SetFrameStrata(self.db.Strata or "MEDIUM")
    end
    self:RefreshAllAuras()

    -- The overlay box is computed from these settings and is only recomputed on
    -- request, so it would otherwise keep the previous numbers until something
    -- unrelated refreshed it.
    if KE.EditMode then KE.EditMode:RefreshLiveState() end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------

-- Debounced full refresh (one Refresh per frame max).
function AD:QueueFullRefresh()
    if self._pendingFullRefresh then return end
    self._pendingFullRefresh = true
    C_Timer.After(0, function()
        AD._pendingFullRefresh = false
        AD:RefreshAllAuras()
    end)
end

-- UNIT_AURA handler with updateInfo support. Falls back to QueueFullRefresh
-- when updateInfo is missing or isFullUpdate is true (zone change, /reload).
function AD:OnUnitAura(_, unit, updateInfo)
    if unit ~= UNIT then return end
    if not self.frame then return end

    if not updateInfo or updateInfo.isFullUpdate then
        self:QueueFullRefresh()
        return
    end

    -- If there's no incremental data, nothing to do.
    if not updateInfo.addedAuras
        and not updateInfo.updatedAuraInstanceIDs
        and not updateInfo.removedAuraInstanceIDs then
        return
    end

    self:ProcessAuraUpdate(updateInfo.addedAuras,
                           updateInfo.updatedAuraInstanceIDs,
                           updateInfo.removedAuraInstanceIDs)
end

---------------------------------------------------------------------------------
-- Container + EditMode
---------------------------------------------------------------------------------

function AD:CreateContainer()
    if self.frame then return end
    local frame = CreateFrame("Frame", "KE_AuraDebuffs", UIParent)
    frame:SetSize(GetFrameSize(self.db))
    frame:SetFrameStrata(self.db.Strata or "MEDIUM")
    self.frame = frame
    KE:ApplyFramePosition(frame, self.db.Position, self.db)
    self:RegWithEditMode()
end

function AD:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key         = "AuraDebuffs",
            module      = self,
            displayName = "Aura Debuffs",
            frame       = self.frame,
            getPosition = function()
                return self.db.Position
            end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
            end,
            -- The container is sized to the grid, but the grid is pinned to the
            -- module's anchor corner and grows from there, so a growth setting
            -- that opposes the anchor slides every icon out of the frame. Read
            -- at call time: a value captured at registration goes stale the
            -- moment the user changes a growth direction.
            getOverlayInset = function()
                local db = self.db
                if not db then return 0, 0, 0, 0 end
                return KE:GetGridOverlayInset(
                    db.IconsPerRow or 8,
                    db.MaxRows or 1,
                    db.IconSize,
                    db.IconSpacing,
                    (db.Position and db.Position.AnchorFrom) or "CENTER",
                    db.GrowHorizontal == "LEFT",
                    db.GrowVertical == "UP"
                )
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "AuraDebuffs",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Button Factory
---------------------------------------------------------------------------------

local function OnButtonEnter(button)
    if not button.auraInstanceID then return end
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetUnitAuraByAuraInstanceID(UNIT, button.auraInstanceID)
    GameTooltip:Show()
end

local function OnButtonLeave()
    GameTooltip:Hide()
end

-- Creates a raw button frame with all child widgets wired. Font anchors are
-- intentionally NOT set here — UpdateButtonAppearance handles those every Refresh.
local function CreateButton(parent, db)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(db.IconSize, db.IconSize)
    b:EnableMouse(true)
    b:SetScript("OnEnter", OnButtonEnter)
    b:SetScript("OnLeave", OnButtonLeave)

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(b)
    KE:ApplyIconZoom(tex)  -- KES standard crop (0.3 / 7.5%)
    b.icon = tex

    -- Two-layer border: 1px black outer ring + 1px colored inner band.
    -- Outer is static black (provides crisp definition against any background);
    -- inner is the dispel-colored band — SetBorderColor only repaints the
    -- inner set per-aura, so b.borders points to the inner textures.
    KE:AddIconBorders(b, { 0, 0, 0, 1 })
    b.outerBorders = b.borders
    b.borders = nil

    do
        local px = KE:GetPixelSize()
        local function MakeInner(p1, r1, p2, r2, w, h, ox1, oy1, ox2, oy2)
            local t = b:CreateTexture(nil, "OVERLAY", nil, 6)
            t:SetTexelSnappingBias(0)
            t:SetSnapToPixelGrid(false)
            t:SetPoint(p1, b, r1, ox1, oy1)
            t:SetPoint(p2, b, r2, ox2, oy2)
            if w then t:SetWidth(w) end
            if h then t:SetHeight(h) end
            return t
        end
        -- Inner band thickness = 2*px (2 pixels) for a chunkier dispel ring.
        local innerPx = 2 * px
        b.borders = {
            top    = MakeInner("TOPLEFT",    "TOPLEFT",    "TOPRIGHT",    "TOPRIGHT",    nil, innerPx,  px, -px, -px, -px),
            bottom = MakeInner("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, innerPx,  px,  px, -px,  px),
            left   = MakeInner("TOPLEFT",    "TOPLEFT",    "BOTTOMLEFT",  "BOTTOMLEFT",  innerPx, nil,  px, -px,  px,  px),
            right  = MakeInner("TOPRIGHT",   "TOPRIGHT",   "BOTTOMRIGHT", "BOTTOMRIGHT", innerPx, nil, -px, -px, -px,  px),
        }
        -- Seed with the configured BorderColor; per-aura repaint happens in
        -- UpdateButtonAppearance via SetBorderColor + ResolveBorderColor.
        local r, g, bc, a = KE:ResolveColor(db.BorderColor, { 0.8, 0, 0, 1 })
        b.borders.top:SetColorTexture(r, g, bc, a)
        b.borders.bottom:SetColorTexture(r, g, bc, a)
        b.borders.left:SetColorTexture(r, g, bc, a)
        b.borders.right:SetColorTexture(r, g, bc, a)
    end

    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(b)
    cd:SetDrawEdge(false)
    cd:SetReverse(db.Reverse)
    -- Use Blizzard's built-in countdown text (taint-safe via
    -- SetCooldownFromDurationObject). KE's custom 0.1s ticker can't render
    -- timer text on encounter HARMFUL auras because aura.duration /
    -- aura.expirationTime come back secret. The built-in cooldown text is
    -- driven by the duration object, which is taint-safe.
    cd:SetHideCountdownNumbers(false)
    b.cooldown = cd

    -- b.timer aliases the cooldown's built-in countdown FontString
    -- (CooldownFrameTemplate creates a single text region accessible via
    -- :GetRegions()). UpdateButtonAppearance re-applies font + position
    -- every refresh.
    local timer = cd:GetRegions() --[[@as FontString]]
    b.timer = timer

    -- Dispel atlas overlays — one texture per dispellable type. Per-type
    -- alpha curves drive each one's :SetAlpha() directly; we never inspect
    -- the alpha number itself (it may be secret for encounter HARMFUL auras
    -- and comparing it taints). Only the matching type renders at alpha 1;
    -- the others stay at alpha 0. Same architecture as AE v4.
    --
    -- Hosted on a dedicated Frame parented to the button with a frame level
    -- ABOVE the cooldown's, so the swipe doesn't desaturate the atlas as it
    -- passes over the corner.
    local dispelOverlay = CreateFrame("Frame", nil, b)
    dispelOverlay:SetAllPoints(b)
    dispelOverlay:SetFrameLevel(cd:GetFrameLevel() + 1)
    b.dispelOverlay = dispelOverlay

    local dispelSize = math_floor(db.IconSize * 0.40)
    b.dispelTextures = {}
    for _, name in ipairs(DISPEL_TYPE_ORDER) do
        local atlas = DISPEL_ICON_ATLASES[name]
        if atlas then
            local dtex = dispelOverlay:CreateTexture(nil, "OVERLAY")
            dtex:SetAtlas(atlas)
            dtex:SetSize(dispelSize, dispelSize)
            dtex:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
            dtex:SetAlpha(0)
            b.dispelTextures[name] = dtex
        end
    end

    local stack = b:CreateFontString(nil, "OVERLAY")
    b.stack = stack

    -- Seed fonts. SetText on a fontless FontString errors "Font not set"
    -- and taints. LayoutAndPaint runs SetText on this button BEFORE
    -- UpdateButtonAppearance does the per-Refresh re-apply, so the very
    -- first paint needs fonts in place.
    if timer and timer.SetFont then
        KE:ApplyFontToText(timer, db.FontFace, db.TimerFontSize, db.FontOutline)
        if timer.SetShadowOffset then timer:SetShadowOffset(0, 0) end
    end
    KE:ApplyFontToText(stack, db.FontFace, db.FontSize, db.FontOutline)

    b.auraInstanceID = nil
    b:Hide()
    return b
end

function AD:GetOrCreateButton(index)
    local b = self.buttons[index]
    if b then return b end
    b = CreateButton(self.frame, self.db)
    self.buttons[index] = b
    return b
end

-- Apply r,g,b,a to all four inner border textures. Both code paths funnel
-- through here. SetColorTexture accepts secret-value arguments (the Color
-- API surface explicitly supports "AllowedWhenTainted") so this works on
-- encounter HARMFUL auras whose curve color is secret.
-- SetColorTexture re-enables Blizzard's per-texture pixel-grid snap, so each
-- recolor re-asserts SetSnapToPixelGrid(false) to keep the inner band crisp.
-- (Formerly handled by the global TextureSnap metatable hook, removed because
-- it billed the whole game's texture churn to KE — see Core/TextureSnap.lua.)
-- SetSnapToPixelGrid is AllowedWhenUntainted and we pass a literal false (never
-- a secret), so this stays taint-safe even when r,g,bc,a are secret curve values.
local function ApplyBorderRGBA(b, r, g, bc, a)
    if not b.borders then return end
    if b.borders.top    then b.borders.top:SetColorTexture(r, g, bc, a);    b.borders.top:SetSnapToPixelGrid(false) end
    if b.borders.bottom then b.borders.bottom:SetColorTexture(r, g, bc, a); b.borders.bottom:SetSnapToPixelGrid(false) end
    if b.borders.left   then b.borders.left:SetColorTexture(r, g, bc, a);   b.borders.left:SetSnapToPixelGrid(false) end
    if b.borders.right  then b.borders.right:SetColorTexture(r, g, bc, a);  b.borders.right:SetSnapToPixelGrid(false) end
end

-- Paint the border for a button. In "dispel" mode for a real aura we
-- query the color curve and pass its Color object's RGBA straight through
-- — those values may be secret but SetColorTexture handles them. For
-- preview (synthetic auraInstanceID), curve API returns nil; we fall back
-- to the per-type table lookup using the known preview dispelType. For
-- "custom" mode or any miss, fall back to db.BorderColor.
local function PaintBorder(b, db, previewDispelType)
    if db.BorderColorMode == "dispel" then
        local c = b.auraInstanceID and GetDispelColor(b.auraInstanceID) or nil
        if c then
            -- Pass the secret/concrete RGBA through unchanged.
            ApplyBorderRGBA(b, c:GetRGBA())
            return
        end
        if previewDispelType then
            local col = (db.DispelColors and db.DispelColors[previewDispelType])
                     or DISPEL_DEFAULTS[previewDispelType]
            if col then
                local r, g, bb, a = KE:ResolveColor(col, { 0.8, 0, 0, 1 })
                ApplyBorderRGBA(b, r, g, bb, a)
                return
            end
        end
    end
    local r, g, bb, a = KE:ResolveColor(db.BorderColor, { 0.8, 0, 0, 1 })
    ApplyBorderRGBA(b, r, g, bb, a)
end

function AD:UpdateButtonAppearance(count)
    local db = self.db
    local tp = db.TimerPosition
    local sp = db.StackPosition
    local dp = db.DispelPosition

    for i = 1, count do
        local b = self.buttons[i]
        if b then
            -- Resize the button frame to match db.IconSize. Without this,
            -- existing buttons keep the size they were created at and
            -- LayoutButtons' new spacing (based on the smaller IconSize)
            -- causes the larger buttons to overlap.
            b:SetSize(db.IconSize, db.IconSize)
            if b.icon then
                KE:ApplyIconZoom(b.icon)  -- KES standard crop
            end
            -- b.timer is the cooldown's built-in countdown FontString (via
            -- cd:GetRegions() in CreateButton). Re-apply font + anchor each
            -- Refresh so user edits take effect immediately. Anchor to the
            -- button (not the cooldown frame) so TimerPosition behaves the
            -- same way as the old custom-FontString implementation.
            if b.timer and b.timer.SetFont then
                KE:ApplyFontToText(b.timer, db.FontFace, db.TimerFontSize, db.FontOutline)
                if b.timer.SetShadowOffset then b.timer:SetShadowOffset(0, 0) end
                b.timer:ClearAllPoints()
                b.timer:SetPoint(tp.AnchorFrom, b, tp.AnchorTo, tp.XOffset, tp.YOffset)
            end
            if b.stack then
                KE:ApplyFontToText(b.stack, db.FontFace, db.FontSize, db.FontOutline)
                b.stack:ClearAllPoints()
                b.stack:SetPoint(sp.AnchorFrom, b, sp.AnchorTo, sp.XOffset, sp.YOffset)
            end
            if b.dispelTextures then
                local dispelSize = math_floor(db.IconSize * 0.40)
                for _, tex in pairs(b.dispelTextures) do
                    tex:SetSize(dispelSize, dispelSize)
                    tex:ClearAllPoints()
                    if dp then
                        tex:SetPoint(dp.AnchorFrom, b, dp.AnchorTo, dp.XOffset, dp.YOffset)
                    else
                        tex:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
                    end
                end
            end
            if b.cooldown then
                b.cooldown:SetDrawSwipe(db.Swipe ~= false)
            end
            -- Border color via curve (dispel mode + real aura) or table
            -- fallback (custom mode / preview).
            PaintBorder(b, db, b._previewDispelType)
        end
    end
end

---------------------------------------------------------------------------------
-- Aura Collection
---------------------------------------------------------------------------------

local function SortAuras(a, b)
    -- Sort by auraInstanceID (newer applications have higher IDs).
    -- We can't sort by dispelType for encounter
    -- HARMFUL auras (dispelName is secret), and aura.expirationTime is
    -- secret for the same auras (comparison would taint).
    return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
end

-- Build the aura record stored in auraCache. Pulled out so RefreshAllAuras
-- and ProcessAuraUpdate share the same record shape. We deliberately do
-- NOT store a dispelType string: aura.dispelName is secret for encounter
-- HARMFUL auras, and the curve-based detection produces a secret alpha
-- that can't be compared in Lua. Instead, the per-type dispel atlas
-- textures get their alphas set directly from per-type alpha curves
-- (AE pattern) — no string-name detection needed at any layer.
local function BuildAuraRecord(aura)
    return {
        auraInstanceID = aura.auraInstanceID,
        spellId        = aura.spellId,
        icon           = aura.icon,
        duration       = aura.duration,
        expirationTime = aura.expirationTime,
        count          = aura.applications,
    }
end

-- Full re-scan: enumerate all HARMFUL aura instance IDs, fetch each, run
-- ShouldShowAura, rebuild auraCache + activeAuras.
function AD:RefreshAllAuras()
    if not self.frame then return end

    if not self:ShouldShow() then
        for _, b in pairs(self.buttons) do b:Hide() end
        self.frame:Hide()
        wipe(self.activeAuras)
        wipe(self.auraCache)
        return
    end
    self.frame:Show()

    local db = self.db
    wipe(self.auraCache)
    wipe(self.activeAuras)

    if self.isPreview then
        for _, preview in ipairs(BuildPreviewAuras(db)) do
            tinsert(self.auraCache, preview)
        end
    else
        local auraInstanceIDs = C_UnitAuras.GetUnitAuraInstanceIDs(UNIT, "HARMFUL")
        if auraInstanceIDs then
            for _, instanceID in ipairs(auraInstanceIDs) do
                local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(UNIT, instanceID)
                if aura and ShouldShowAura(instanceID, aura, db, self.filterStrings) then
                    self.activeAuras[instanceID] = true
                    tinsert(self.auraCache, BuildAuraRecord(aura))
                end
            end
            if #self.auraCache > 1 then tsort(self.auraCache, SortAuras) end
        end
    end

    self:LayoutAndPaint()
end

-- Incremental update: process added / updated / removed aura instance IDs
-- from UNIT_AURA's updateInfo. Falls back to a full refresh if anything
-- materially changed.
function AD:ProcessAuraUpdate(addedAuras, updatedIDs, removedIDs)
    if not self.frame then return end
    if not self:ShouldShow() then return end

    local db = self.db
    local changed = false

    if removedIDs then
        for _, instanceID in ipairs(removedIDs) do
            if self.activeAuras[instanceID] then
                self.activeAuras[instanceID] = nil
                changed = true
            end
        end
    end

    if addedAuras then
        for _, aura in ipairs(addedAuras) do
            if ShouldShowAura(aura.auraInstanceID, aura, db, self.filterStrings) then
                self.activeAuras[aura.auraInstanceID] = true
                changed = true
            end
        end
    end

    if updatedIDs then
        for _, instanceID in ipairs(updatedIDs) do
            local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(UNIT, instanceID)
            local shouldShow = aura and ShouldShowAura(instanceID, aura, db, self.filterStrings)
            local wasShowing = self.activeAuras[instanceID]
            if shouldShow and not wasShowing then
                self.activeAuras[instanceID] = true
                changed = true
            elseif not shouldShow and wasShowing then
                self.activeAuras[instanceID] = nil
                changed = true
            elseif shouldShow and wasShowing then
                -- duration/stack/icon may have changed; need a repaint
                changed = true
            end
        end
    end

    if changed then
        -- Rebuild auraCache from activeAuras. (We can't trust incremental
        -- ordering for the sort, so do a fresh pull of each surviving entry.)
        wipe(self.auraCache)
        for instanceID in pairs(self.activeAuras) do
            local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(UNIT, instanceID)
            if aura then
                tinsert(self.auraCache, BuildAuraRecord(aura))
            else
                -- Aura disappeared between updateInfo and now; drop it.
                self.activeAuras[instanceID] = nil
            end
        end
        if #self.auraCache > 1 then tsort(self.auraCache, SortAuras) end
        self:LayoutAndPaint()
    end
end

---------------------------------------------------------------------------------
-- Layout + paint shared between full and incremental refreshes
---------------------------------------------------------------------------------

function AD:LayoutAndPaint()
    local db    = self.db
    local cap   = math_min(#self.auraCache, (db.IconsPerRow or 8) * (db.MaxRows or 1))

    for i = 1, cap do
        local aura = self.auraCache[i]
        local b    = self:GetOrCreateButton(i)
        b.auraInstanceID = aura.auraInstanceID
        -- aura.dispelType is only set on PREVIEW records (BuildPreviewAuras
        -- stores PREVIEW_DISPEL_TYPES[idx] directly). Real auras never have
        -- this field because dispelName is secret on encounter HARMFUL auras
        -- and we can't determine the type via string. PaintBorder uses this
        -- as the preview-only fallback path.
        b._previewDispelType = aura.dispelType
        b.icon:SetTexture(aura.icon)

        -- Cooldown + countdown text both driven by the duration object (or
        -- synthetic start/duration in preview). The duration object is
        -- taint-safe so the spiral AND Blizzard's built-in countdown
        -- numbers render correctly even on encounter HARMFUL auras where
        -- the raw aura.duration is secret.
        local durationObj = C_UnitAuras.GetAuraDuration and
            C_UnitAuras.GetAuraDuration(UNIT, aura.auraInstanceID)
        if durationObj then
            b.cooldown:SetCooldownFromDurationObject(durationObj)
            b.cooldown:Show()
        elseif aura.duration and aura.expirationTime
            and not (issecretvalue and (issecretvalue(aura.duration) or issecretvalue(aura.expirationTime)))
            and aura.duration > 0 then
            -- Preview path (synthetic auraInstanceIDs): GetAuraDuration
            -- returns nil because no real aura matches, so fall back to the
            -- synthetic numeric times so the countdown text + spiral both
            -- render on the preview.
            b.cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
            b.cooldown:Show()
        else
            b.cooldown:Clear()
        end

        -- Stack count: GetAuraApplicationDisplayCount handles the
        -- "show when >= 2, cap 999" rule internally via the min/max args
        -- and returns either a number or "" (empty string) — pass straight
        -- to SetText without comparison so a secret-number count doesn't
        -- taint (matches AE's pattern). For synthetic preview IDs the API
        -- returns "" since no real aura matches; preview records carry
        -- count directly so use the manual path for those.
        if aura.dispelType then
            -- Preview path: aura.count is set from BuildPreviewAuras.
            if type(aura.count) == "number" and aura.count > 1 then
                b.stack:SetText(tostring(aura.count))
            else
                b.stack:SetText("")
            end
        elseif C_UnitAuras.GetAuraApplicationDisplayCount then
            b.stack:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(UNIT, aura.auraInstanceID, 2, 999) or "")
        else
            b.stack:SetText("")
        end

        -- Dispel atlas overlays. For real auras, drive each per-type
        -- texture's :SetAlpha() from the corresponding alpha curve — only
        -- the matching type's texture ends up visible (alpha 1), others
        -- stay at 0. The alpha value may be SECRET on encounter HARMFUL
        -- auras but :SetAlpha() accepts secrets so this works regardless.
        -- For preview (synthetic auraInstanceID, curve API returns nil),
        -- set alphas manually from the known PREVIEW_DISPEL_TYPES.
        if b.dispelTextures then
            if aura.dispelType then
                -- Preview path: manual.
                for name, tex in pairs(b.dispelTextures) do
                    tex:SetAlpha(name == aura.dispelType and 1 or 0)
                end
            else
                -- Real-aura path: curves.
                for name, tex in pairs(b.dispelTextures) do
                    local c = GetDispelAlphaColor(aura.auraInstanceID, name)
                    if c then
                        local _, _, _, a = c:GetRGBA()
                        tex:SetAlpha(a)
                    else
                        tex:SetAlpha(0)
                    end
                end
            end
        end

        b:Show()
    end

    for i = cap + 1, #self.buttons do
        self.buttons[i]:Hide()
    end

    self:UpdateButtonAppearance(cap)
    self:LayoutButtons(cap)
end

function AD:LayoutButtons(count)
    local db     = self.db
    local dx     = (db.IconSize + db.IconSpacing) * (db.GrowHorizontal == "LEFT" and -1 or 1)
    local dy     = (db.IconSize + db.IconSpacing) * (db.GrowVertical == "UP" and 1 or -1)
    local perRow = db.IconsPerRow or 8

    -- Button[1]'s anchor corner matches the module's Position.AnchorFrom so
    -- the icon grid actually starts at the user-selected anchor point. Both
    -- the button-side AND frame-side anchor point to the same corner: now
    -- that the frame is sized to the grid extent (rather than 1x1), the
    -- frame-side corner picks where in the frame the grid origin sits.
    -- Button[1] at AnchorFrom-to-AnchorFrom places its anchor corner flush
    -- with the frame's matching corner (= the parent's anchor point, per
    -- ApplyFramePosition).
    local pin = (db.Position and db.Position.AnchorFrom) or "CENTER"

    for i = 1, count do
        local b   = self.buttons[i]
        local row = math_floor((i - 1) / perRow)
        local col = (i - 1) % perRow
        b:ClearAllPoints()
        b:SetPoint(pin, self.frame, pin, col * dx, row * dy)
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------

function AD:ShowPreview()
    self.isPreview = true
    if not self.frame then self:CreateContainer() end
    self:RefreshAllAuras()
end

function AD:HidePreview()
    self.isPreview = false
    self:RefreshAllAuras()
    if not self.db.Enabled and self.frame then
        self.frame:Hide()
    end
end
