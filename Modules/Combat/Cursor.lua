-- ╔══════════════════════════════════════════════════════════╗
-- ║  Cursor.lua                                              ║
-- ║  Module: Cursor (unified)                                ║
-- ║  Purpose: Cursor circle + GCD ring + cast circle + trail ║
-- ║           + dispel countdown text — all anchor-inherited ║
-- ║           from a single cursor frame for zero satellite  ║
-- ║           OnUpdate cost when attached.                   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class Cursor: AceModule, AceEvent-3.0
local C = KitnEssentials:NewModule("Cursor", "AceEvent-3.0")

local CreateFrame      = CreateFrame
local UIParent         = UIParent
local GetCursorPosition = GetCursorPosition
local GetTime          = GetTime
local GetSpellCooldown = C_Spell.GetSpellCooldown
local UnitCastingInfo  = UnitCastingInfo
local UnitChannelInfo  = UnitChannelInfo
local IsMouseButtonDown = IsMouseButtonDown
local IsInRaid         = IsInRaid
local IsInGroup        = IsInGroup
local GetInstanceInfo  = GetInstanceInfo
local InCombatLockdown = InCombatLockdown
local floor            = math.floor
local sin, cos         = math.sin, math.cos
local rad              = math.rad
local max              = math.max
local ipairs           = ipairs
local pcall            = pcall

local GCD_SPELL_ID = 61304

local TEX_BASE = "Interface\\AddOns\\KitnEssentials\\Media\\Cursor\\"
local RING_TEXTURES = {
    ring_thin   = TEX_BASE .. "ring_thin.tga",
    ring_light  = TEX_BASE .. "ring_light.tga",
    ring_normal = TEX_BASE .. "ring_normal.tga",
    ring_heavy  = TEX_BASE .. "ring_heavy.tga",
    ring_thick  = TEX_BASE .. "ring_thick.tga",
    circle      = "Interface\\AddOns\\KitnEssentials\\Media\\CursorCircles\\Circle.tga",
}

-- Spark orbit centerline ratio per ring texture (from EUI measurements;
-- re-measure when commissioned KE art replaces borrowed EUI rings).
local RING_INNER = {
    ring_thin   = 0.92,
    ring_light  = 0.85,
    ring_normal = 0.78,
    ring_heavy  = 0.68,
    ring_thick  = 0.58,
    circle      = 0.50,  -- non-ring fallback
}

C.RING_TEXTURES   = RING_TEXTURES
C.TEXTURE_ORDER   = { "ring_thin", "ring_light", "ring_normal", "ring_heavy", "ring_thick", "circle" }
C.TEXTURE_LABELS  = {
    ring_thin   = "Ring (thin)",
    ring_light  = "Ring (light)",
    ring_normal = "Ring (normal)",
    ring_heavy  = "Ring (heavy)",
    ring_thick  = "Ring (thick)",
    circle      = "Soft Glow",
}

C.VISIBILITY_MODES = {
    { key = "always",         text = "Always Visible" },
    { key = "mouseDown",      text = "Only When Mouse Button Held" },
    { key = "in_combat",      text = "In Combat" },
    { key = "out_of_combat",  text = "Out of Combat" },
    { key = "in_instance",    text = "In Instance (Dungeon/Raid)" },
    { key = "in_raid",        text = "In Raid" },
    { key = "in_party",       text = "In Party" },
    { key = "solo",           text = "Solo" },
    { key = "never",          text = "Hidden" },
}

C.GCD_MODE_OPTIONS = {
    { key = "integrated", text = "Integrated (overlay on cursor)" },
    { key = "separate",   text = "Separate (own ring)" },
}

-- Frame references (created lazily)
C.cursorFrame   = nil
C.gcdFrame      = nil
C.castFrame     = nil
C.trailFrame    = nil
C.dispelFrame   = nil

-- Cached visibility state used by satellites (updated by UpdateVisibility)
C._cursorShown        = false
C._trail_instanceOK   = true
C._trail_cursorShown  = false

---------------------------------------------------------------------------------
-- DB helper
---------------------------------------------------------------------------------
function C:UpdateDB()
    self.db = KE.db.profile.Cursor
end

---------------------------------------------------------------------------------
-- Cursor frame
---------------------------------------------------------------------------------
local _lastX, _lastY = -1, -1

local function _cursorOnUpdate(f)
    local s = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = floor(x / s + 0.5), floor(y / s + 0.5)
    if x == _lastX and y == _lastY then return end
    _lastX, _lastY = x, y
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

-- Color cache: avoid re-applying SetVertexColor on every Apply call when
-- nothing changed. Invalidated on theme change.
local _lastColorMode, _lastHex, _lastClassFlag
local _lastR, _lastG, _lastB, _lastA = -1, -1, -1, -1

local function _invalidateColorCache()
    _lastColorMode, _lastHex, _lastClassFlag = nil, nil, nil
    _lastR, _lastG, _lastB, _lastA = -1, -1, -1, -1
end

function C:ApplyCursorColor()
    if not self.cursorFrame or not self.cursorFrame.texture then return end
    local db = self.db
    local mode = db.ColorMode or "class"
    local color = db.Color or { 1, 1, 1, 1 }
    local r, g, b, a = KE:GetAccentColor(mode, color)
    if r ~= _lastR or g ~= _lastG or b ~= _lastB or a ~= _lastA
            or mode ~= _lastColorMode then
        _lastColorMode = mode
        _lastR, _lastG, _lastB, _lastA = r, g, b, a
        self.cursorFrame.texture:SetVertexColor(r, g, b, a)
    end
end

function C:ApplyCursorSettings()
    if not self.cursorFrame then return end
    local db = self.db
    self.cursorFrame:SetSize(db.Size or 50, db.Size or 50)
    self.cursorFrame.texture:SetTexture(RING_TEXTURES[db.Texture] or RING_TEXTURES.ring_normal)
    self:ApplyCursorColor()
end

function C:CreateCursorFrame()
    if self.cursorFrame then return end
    local f = CreateFrame("Frame", "KE_CursorFrame", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(9999)
    f:EnableMouse(false)
    f:SetSize(self.db.Size or 50, self.db.Size or 50)
    f:SetPoint("CENTER")

    f.texture = f:CreateTexture(nil, "OVERLAY")
    f.texture:SetAllPoints(f)
    f.texture:SetTexture(RING_TEXTURES[self.db.Texture] or RING_TEXTURES.ring_normal)

    f:SetScript("OnUpdate", _cursorOnUpdate)
    f:Hide()  -- shown by UpdateVisibility
    self.cursorFrame = f
end

function C:OnInitialize()
    self:UpdateDB()
    -- SchemaVersion cleanup wired up in Task 12
    self:SetEnabledState(self.db.Enabled)
end

function C:OnEnable()
    if not self.db.Enabled then return end
    self:CreateCursorFrame()
    self:ApplyCursorSettings()
    self.cursorFrame:Show()
    self._cursorShown = true
end

function C:OnDisable()
    if self.cursorFrame then
        self.cursorFrame:SetScript("OnUpdate", nil)
        self.cursorFrame:Hide()
    end
    self._cursorShown = false
    self:UnregisterAllEvents()
end

function C:OnThemeChanged()
    if not self.db or not self.db.Enabled then return end
    _invalidateColorCache()
    if self.db.ColorMode == "theme" then
        self:ApplyCursorColor()
    end
    -- Satellite color re-apply added in later tasks
end
