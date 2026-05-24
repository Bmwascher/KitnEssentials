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
-- Instance / context helpers
---------------------------------------------------------------------------------
function C:InRealInstancedContent()
    local _, instanceType, difficultyID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0
    if difficultyID == 0 then return false end
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
        return false
    end
    return instanceType == "party" or instanceType == "raid"
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

-- Shared follow-cursor OnUpdate factory for detached satellites.
-- Each satellite gets its own closure so it has independent _lastX/_lastY.
local function _makeFollowCursorOnUpdate()
    local lastX, lastY = -1, -1
    return function(self)
        local s = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x, y = floor(x / s + 0.5), floor(y / s + 0.5)
        if x == lastX and y == lastY then return end
        lastX, lastY = x, y
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    end
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

---------------------------------------------------------------------------------
-- GCD satellite
---------------------------------------------------------------------------------
local _gcdFollowCursor = nil  -- assigned on first detached use

local function _getActiveGCDCooldown()
    local db = C.db.GCD
    if db.Mode == "integrated" then
        return C.cursorFrame and C.cursorFrame.gcdCooldown
    end
    return C.gcdFrame and C.gcdFrame.cooldown
end

local function _gcdOnEvent(self, event, unit, _, _)
    if unit ~= "player" then return end
    local db = C.db.GCD
    if not db.Enabled then return end
    if db.InstanceOnly and not C:InRealInstancedContent() then return end

    if event == "UNIT_SPELLCAST_FAILED"
       or event == "UNIT_SPELLCAST_INTERRUPTED"
       or event == "UNIT_SPELLCAST_STOP" then
        -- Check if GCD got reset (cancelled cast might not have triggered GCD)
        local cdData = GetSpellCooldown(GCD_SPELL_ID)
        if not cdData or not cdData.duration or cdData.duration <= 0
                or not cdData.startTime or cdData.startTime <= 0 then
            local cd = _getActiveGCDCooldown()
            if cd then cd:Clear() end
        end
        return
    end

    -- SUCCESS or START: GCD may have started. Wrap in pcall — duration MAY be
    -- a secret number in 12.0 (defensive, matches EUI pattern).
    local cdData = GetSpellCooldown(GCD_SPELL_ID)
    if not cdData or not cdData.startTime then return end
    local ok, dur, start = pcall(function()
        local d = cdData.duration
        local s = cdData.startTime
        if d and d > 0 and d <= 1.6 and s and s > 0 then
            return d, s
        end
    end)
    if ok and dur and start then
        local cd = _getActiveGCDCooldown()
        if cd then
            cd:SetCooldown(start, dur)
            if db.Reverse then cd:SetReverse(true) end
            cd:Show()
        end
    end
end

function C:CreateGCDSatellite()
    if self.gcdFrame then return end
    local db = self.db.GCD
    local size = db.Size or 50

    local gf = CreateFrame("Frame", "KE_CursorGCDRing", UIParent)
    gf:SetSize(size, size)
    gf:SetFrameStrata("TOOLTIP")
    gf:SetFrameLevel(9998)
    gf:EnableMouse(false)

    -- Ring texture
    gf.texture = gf:CreateTexture(nil, "BACKGROUND")
    gf.texture:SetAllPoints(gf)
    gf.texture:SetTexture(RING_TEXTURES[db.Texture] or RING_TEXTURES.ring_light)

    -- Cooldown swipe overlay
    gf.cooldown = CreateFrame("Cooldown", nil, gf, "CooldownFrameTemplate")
    gf.cooldown:SetAllPoints(gf)
    gf.cooldown:EnableMouse(false)
    gf.cooldown:SetDrawSwipe(true)
    gf.cooldown:SetDrawEdge(false)
    gf.cooldown:SetHideCountdownNumbers(true)
    if gf.cooldown.SetDrawBling then gf.cooldown:SetDrawBling(false) end
    if gf.cooldown.SetUseCircularEdge then gf.cooldown:SetUseCircularEdge(true) end
    if gf.cooldown.SetSwipeTexture then
        gf.cooldown:SetSwipeTexture(RING_TEXTURES[db.Texture] or RING_TEXTURES.ring_light, 1, 1, 1, 1)
    end
    gf.cooldown:SetFrameLevel(gf:GetFrameLevel() + 2)

    gf:SetScript("OnEvent", _gcdOnEvent)
    gf:Hide()
    self.gcdFrame = gf
end

function C:_AttachGCDScripts()
    local gf = self.gcdFrame
    if not gf then return end
    gf:UnregisterAllEvents()  -- idempotent
    gf:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",   "player")
    gf:RegisterUnitEvent("UNIT_SPELLCAST_START",       "player")
    gf:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",      "player")
    gf:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    gf:RegisterUnitEvent("UNIT_SPELLCAST_STOP",        "player")
end

function C:_DetachGCDScripts()
    local gf = self.gcdFrame
    if not gf then return end
    gf:UnregisterAllEvents()
    gf:SetScript("OnUpdate", nil)
end

function C:ApplyGCDColor()
    local gf = self.gcdFrame
    if not gf then return end
    local db = self.db.GCD
    local rr, rg, rb, ra = KE:GetAccentColor(db.RingColorMode or "theme", db.RingColor)
    local sr, sg, sb, sa = KE:GetAccentColor(db.SwipeColorMode or "custom", db.SwipeColor)
    if gf.texture then gf.texture:SetVertexColor(rr, rg, rb, ra) end
    if gf.cooldown then
        gf.cooldown:SetSwipeColor(sr, sg, sb, sa)
        if gf.cooldown.SetSwipeTexture then
            local tex = RING_TEXTURES[db.Texture] or RING_TEXTURES.ring_light
            gf.cooldown:SetSwipeTexture(tex, sr, sg, sb, sa)
        end
        if gf.cooldown.SetReverse then gf.cooldown:SetReverse(db.Reverse or false) end
    end
end

function C:ApplyGCDSatellite()
    local db = self.db.GCD
    if not db.Enabled then
        if self.gcdFrame then
            self:_DetachGCDScripts()
            self.gcdFrame:Hide()
        end
        return
    end

    if db.Mode == "integrated" then
        -- Integrated: separate frame stays hidden, but we still need events to fire.
        -- _gcdOnEvent dispatches to cursorFrame.gcdCooldown when Mode == "integrated".
        if not self.gcdFrame then self:CreateGCDSatellite() end
        self:_AttachGCDScripts()
        self.gcdFrame:Hide()
        if self.cursorFrame and self.cursorFrame.gcdCooldown then
            local sr, sg, sb, sa = KE:GetAccentColor(db.SwipeColorMode or "custom", db.SwipeColor)
            self.cursorFrame.gcdCooldown:SetSwipeColor(sr, sg, sb, sa)
            if self.cursorFrame.gcdCooldown.SetSwipeTexture then
                self.cursorFrame.gcdCooldown:SetSwipeTexture(
                    RING_TEXTURES[self.db.Texture] or RING_TEXTURES.ring_normal,
                    sr, sg, sb, sa)
            end
            if self.cursorFrame.gcdCooldown.SetReverse then
                self.cursorFrame.gcdCooldown:SetReverse(db.Reverse or false)
            end
        end
        return
    end

    if not self.gcdFrame then self:CreateGCDSatellite() end
    self:_AttachGCDScripts()

    -- Style
    local size = db.Size or 50
    self.gcdFrame:SetSize(size, size)
    if self.gcdFrame.texture then
        self.gcdFrame.texture:SetTexture(RING_TEXTURES[db.Texture] or RING_TEXTURES.ring_light)
    end
    self:ApplyGCDColor()

    -- Position: attached anchors to cursor frame; detached gets own OnUpdate
    if db.Attached and self.cursorFrame and self.cursorFrame:IsShown() then
        self.gcdFrame:SetScript("OnUpdate", nil)
        self.gcdFrame:ClearAllPoints()
        self.gcdFrame:SetPoint("CENTER", self.cursorFrame, "CENTER", 0, 0)
    else
        if not _gcdFollowCursor then _gcdFollowCursor = _makeFollowCursorOnUpdate() end
        self.gcdFrame:SetScript("OnUpdate", _gcdFollowCursor)
        -- Initial position so it doesn't snap-from-origin
        local s = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        self.gcdFrame:ClearAllPoints()
        self.gcdFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
            floor(x / s + 0.5), floor(y / s + 0.5))
    end
    self.gcdFrame:Show()
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

    -- Integrated GCD swipe overlay (only used when db.GCD.Mode == "integrated")
    f.gcdCooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.gcdCooldown:SetAllPoints(f)
    f.gcdCooldown:EnableMouse(false)
    f.gcdCooldown:SetDrawSwipe(true)
    f.gcdCooldown:SetDrawEdge(false)
    f.gcdCooldown:SetHideCountdownNumbers(true)
    if f.gcdCooldown.SetDrawBling then f.gcdCooldown:SetDrawBling(false) end
    if f.gcdCooldown.SetUseCircularEdge then f.gcdCooldown:SetUseCircularEdge(true) end
    f.gcdCooldown:SetFrameLevel(f:GetFrameLevel() + 2)
    f.gcdCooldown:Hide()

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

    -- Defer satellite creation 0.5s (matches EUI; lets other addons finish init)
    C_Timer.After(0.5, function()
        if not self.db or not self.db.Enabled then return end
        self:ApplyGCDSatellite()
        -- Other satellites added in later tasks
    end)
end

function C:OnDisable()
    if self.cursorFrame then
        self.cursorFrame:SetScript("OnUpdate", nil)
        self.cursorFrame:Hide()
    end
    if self.gcdFrame then
        self:_DetachGCDScripts()
        self.gcdFrame:Hide()
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
    local gcd = self.db.GCD or {}
    if gcd.RingColorMode == "theme" or gcd.SwipeColorMode == "theme" then
        self:ApplyGCDColor()
    end
end
