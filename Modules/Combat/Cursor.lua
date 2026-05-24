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

function C:OnInitialize()
    self:UpdateDB()
    -- SchemaVersion cleanup wired up in Task 12
    self:SetEnabledState(self.db.Enabled)
end

function C:OnEnable()
    -- Wired up in Task 2+
end

function C:OnDisable()
    -- Wired up in Task 2+
end
