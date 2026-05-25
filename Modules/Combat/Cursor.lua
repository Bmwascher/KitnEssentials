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

local DISPEL_SPELL_IDS = {
    115450, 4987, 527, 360823, 88423, 77130,            -- Healer dispels
    119905, 213634, 218164, 213644, 2782, 475, 365585, 51886,  -- DPS/Tank dispels
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

local _mouseHoldTime = 0  -- mouseDown mode hold timer

local function _cursorOnUpdate(f, elapsed)
    local db = C.db
    if not db then return end

    -- mouseDown mode: gate alpha on hold time (≥0.15s feathered show).
    -- Apply alpha to cursorFrame (cascades to texture + integrated GCD swipe child)
    -- AND to each separate satellite frame (GCD/Cast/Dispel are UIParent-parented
    -- siblings, so cursor frame alpha doesn't reach them — set explicitly).
    -- Don't early-return — keep position updates running so satellite anchors track.
    if db.Visibility == "mouseDown" then
        local isDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        if isDown then
            _mouseHoldTime = _mouseHoldTime + (elapsed or 0)
        else
            _mouseHoldTime = 0
        end
        local shown = isDown and _mouseHoldTime >= 0.15
        local targetAlpha = shown and 1 or 0
        if f:GetAlpha() ~= targetAlpha then
            f:SetAlpha(targetAlpha)
        end
        if C.gcdFrame and C.gcdFrame:GetAlpha() ~= targetAlpha then
            C.gcdFrame:SetAlpha(targetAlpha)
        end
        if C.castFrame and C.castFrame:GetAlpha() ~= targetAlpha then
            C.castFrame:SetAlpha(targetAlpha)
        end
        if C.dispelFrame and C.dispelFrame:GetAlpha() ~= targetAlpha then
            C.dispelFrame:SetAlpha(targetAlpha)
        end
        -- Trail spawn gate follows hold state too (else dots spawn while cursor invisible).
        -- UpdateVisibility resets this from masterShown when mode changes off mouseDown.
        -- NOTE: trail + mouseDown is largely ineffective in practice — WoW locks the
        -- cursor position while L/R mouse is held, so the cursor doesn't move and
        -- new dots can't spawn beyond the first frame's spawn at the click location.
        C._trail_cursorShown = shown
    end

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
local _lastColorMode
local _lastR, _lastG, _lastB, _lastA = -1, -1, -1, -1

local function _invalidateColorCache()
    _lastColorMode = nil
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

    -- Always attach to cursor frame when shown (anchor inheritance, free).
    -- Fall back to own follow-cursor OnUpdate only when cursor is hidden
    -- (e.g. master Visibility="never" but GCD VisibilityOverride="always").
    if self.cursorFrame and self.cursorFrame:IsShown() then
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

---------------------------------------------------------------------------------
-- Cast circle satellite
---------------------------------------------------------------------------------
local _castFollowCursor = nil
local _activeCastID = nil  -- track current cast for STOP/FAILED dispatch

local function _sparkOnUpdate(overlay)
    -- overlay is _sparkOverlay; its parent is castRoot (cf)
    local castRoot = overlay:GetParent()
    if not castRoot or not castRoot.cooldown then return end
    local maxDur = castRoot._castMaxDur
    if not maxDur or maxDur <= 0 then return end
    local now = GetTime()
    local elapsed = now - (castRoot._castStart or now)
    if elapsed >= maxDur then
        overlay:SetScript("OnUpdate", nil)  -- self-detach when done
        return
    end
    local db = C.db.Cast
    local pct = elapsed / maxDur
    local ringRadius = (db.Size or 72) / 2
    local innerRatio = RING_INNER[db.Texture or "ring_normal"] or 0.78
    local orbitR = ringRadius * (1 + innerRatio) * 0.5
    local angleDeg = 90 - (pct * 360)
    local sx = cos(rad(angleDeg)) * orbitR
    local sy = sin(rad(angleDeg)) * orbitR
    local rot = rad(angleDeg - 90)

    local spark = castRoot._spark
    if spark then
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", castRoot, "CENTER", sx, sy)
        spark:SetRotation(rot)
    end
    local glow = castRoot._sparkGlow
    if glow then
        glow:ClearAllPoints()
        glow:SetPoint("CENTER", castRoot, "CENTER", sx, sy)
        glow:SetRotation(rot)
    end
end

local function _castStartSweep(cf, startMS, endMS)
    local elapsed = GetTime() - startMS * 0.001
    local total = (endMS - startMS) * 0.001
    cf._castStart = GetTime() - elapsed
    cf._castDur = elapsed
    cf._castMaxDur = total
    cf.cooldown:SetCooldown(GetTime() - elapsed, total)
    cf.cooldown:Show()
    if C.db.Cast.SparkEnabled and cf._spark then
        cf._spark:Show()
        if cf._sparkGlow then cf._sparkGlow:Show() end
        cf._sparkOverlay:SetScript("OnUpdate", _sparkOnUpdate)  -- attach only during cast
    end
end

local function _castStopSweep(cf)
    cf.cooldown:Hide()
    cf._castStart, cf._castDur, cf._castMaxDur = nil, nil, nil
    if cf._spark then cf._spark:Hide() end
    if cf._sparkGlow then cf._sparkGlow:Hide() end
    if cf._sparkOverlay then cf._sparkOverlay:SetScript("OnUpdate", nil) end  -- detach!
    _activeCastID = nil
end

local function _castOnEvent(self, event, unit, castID)
    if unit ~= "player" then return end
    local db = C.db.Cast
    if not db.Enabled then return end
    if db.InstanceOnly and not C:InRealInstancedContent() then return end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        local name, _, _, startMS, endMS, _, cID = UnitCastingInfo("player")
        if name then
            _activeCastID = cID
            _castStartSweep(self, startMS, endMS)
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
            or event == "UNIT_SPELLCAST_EMPOWER_START"
            or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        local name, _, _, startMS, endMS, _, _, _, _, numStages = UnitChannelInfo("player")
        if name then
            _activeCastID = nil
            if numStages and numStages > 0 and GetUnitEmpowerHoldAtMaxTime then
                endMS = endMS + GetUnitEmpowerHoldAtMaxTime("player")
            end
            _castStartSweep(self, startMS, endMS)
        end
    elseif event == "UNIT_SPELLCAST_STOP" then
        if castID == _activeCastID then
            _castStopSweep(self)
        end
    else  -- FAILED, INTERRUPTED, CHANNEL_STOP, EMPOWER_STOP
        if not castID or castID == _activeCastID then
            _castStopSweep(self)
        end
    end
end

function C:CreateCastSatellite()
    if self.castFrame then return end
    local db = self.db.Cast
    local size = db.Size or 72

    local cf = CreateFrame("Frame", "KE_CursorCastRing", UIParent)
    cf:SetSize(size, size)
    cf:SetFrameStrata("TOOLTIP")
    cf:SetFrameLevel(9988)
    cf:EnableMouse(false)

    -- Ring texture
    cf.texture = cf:CreateTexture(nil, "BACKGROUND")
    cf.texture:SetAllPoints(cf)
    cf.texture:SetTexture(RING_TEXTURES[db.Texture] or RING_TEXTURES.ring_normal)

    -- Cooldown swipe
    cf.cooldown = CreateFrame("Cooldown", nil, cf, "CooldownFrameTemplate")
    cf.cooldown:SetAllPoints(cf)
    cf.cooldown:EnableMouse(false)
    cf.cooldown:SetDrawSwipe(true)
    cf.cooldown:SetDrawEdge(false)
    cf.cooldown:SetHideCountdownNumbers(true)
    if cf.cooldown.SetDrawBling then cf.cooldown:SetDrawBling(false) end
    if cf.cooldown.SetUseCircularEdge then cf.cooldown:SetUseCircularEdge(true) end
    if cf.cooldown.SetSwipeTexture then
        cf.cooldown:SetSwipeTexture(RING_TEXTURES[db.Texture] or RING_TEXTURES.ring_normal, 1, 1, 1, 1)
    end
    cf.cooldown:SetFrameLevel(cf:GetFrameLevel() + 2)
    cf.cooldown:Hide()

    -- Spark overlay child (its OnUpdate attaches only during active cast)
    cf._sparkOverlay = CreateFrame("Frame", nil, cf)
    cf._sparkOverlay:SetAllPoints(cf)
    cf._sparkOverlay:SetFrameLevel(cf:GetFrameLevel() + 3)

    cf._spark = cf._sparkOverlay:CreateTexture(nil, "OVERLAY")
    cf._spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    cf._spark:SetBlendMode("ADD")
    cf._spark:SetSize(size * 0.6, size * 0.6)
    cf._spark:Hide()

    cf._sparkGlow = cf._sparkOverlay:CreateTexture(nil, "OVERLAY", nil, -1)
    cf._sparkGlow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    cf._sparkGlow:SetBlendMode("ADD")
    cf._sparkGlow:SetSize(size * 0.9, size * 0.9)
    cf._sparkGlow:SetAlpha(0.5)
    cf._sparkGlow:Hide()

    cf:SetScript("OnEvent", _castOnEvent)
    cf:Hide()
    self.castFrame = cf
end

function C:_AttachCastScripts()
    local cf = self.castFrame
    if not cf then return end
    cf:UnregisterAllEvents()
    cf:RegisterUnitEvent("UNIT_SPELLCAST_START",          "player")
    cf:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED",        "player")
    cf:RegisterUnitEvent("UNIT_SPELLCAST_STOP",           "player")
    cf:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",         "player")
    cf:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED",    "player")
    cf:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START",  "player")
    cf:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    cf:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP",   "player")
    if GetUnitEmpowerHoldAtMaxTime then
        cf:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START",  "player")
        cf:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
        cf:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP",   "player")
    end
end

function C:_DetachCastScripts()
    local cf = self.castFrame
    if not cf then return end
    cf:UnregisterAllEvents()
    cf:SetScript("OnUpdate", nil)
    if cf._sparkOverlay then cf._sparkOverlay:SetScript("OnUpdate", nil) end
end

function C:ApplyCastColor()
    local cf = self.castFrame
    if not cf then return end
    local db = self.db.Cast
    local rr, rg, rb, ra = KE:GetAccentColor(db.RingColorMode or "class", db.RingColor)
    local sr, sg, sb, sa = KE:GetAccentColor(db.SwipeColorMode or "theme", db.SwipeColor)
    if cf.texture then cf.texture:SetVertexColor(rr, rg, rb, ra) end
    if cf.cooldown then
        cf.cooldown:SetSwipeColor(sr, sg, sb, sa)
        if cf.cooldown.SetSwipeTexture then
            cf.cooldown:SetSwipeTexture(RING_TEXTURES[db.Texture] or RING_TEXTURES.ring_normal, sr, sg, sb, sa)
        end
    end
    if cf._spark and db.SparkEnabled then
        local sxr, sxg, sxb
        if db.SparkColorMode == "ring" then
            sxr, sxg, sxb = rr, rg, rb
        else
            sxr, sxg, sxb = KE:GetAccentColor("custom", db.SparkColor)
        end
        cf._spark:SetVertexColor(sxr, sxg, sxb, 1)
        if cf._sparkGlow then
            cf._sparkGlow:SetVertexColor(sxr, sxg, sxb, 1)
            cf._sparkGlow:SetAlpha(0.5)
        end
    end
end

function C:ApplyCastSatellite()
    local db = self.db.Cast
    if not db.Enabled then
        if self.castFrame then
            self:_DetachCastScripts()
            self.castFrame:Hide()
        end
        return
    end
    if not self.castFrame then self:CreateCastSatellite() end
    self:_AttachCastScripts()

    local size = db.Size or 72
    self.castFrame:SetSize(size, size)
    if self.castFrame.texture then
        self.castFrame.texture:SetTexture(RING_TEXTURES[db.Texture] or RING_TEXTURES.ring_normal)
    end
    if self.castFrame._spark then
        self.castFrame._spark:SetSize(size * 0.6, size * 0.6)
        self.castFrame._sparkGlow:SetSize(size * 0.9, size * 0.9)
    end
    self:ApplyCastColor()

    -- Always attach to cursor frame when it's shown (anchor inheritance, free).
    -- Fall back to own follow-cursor OnUpdate only when cursor is hidden (e.g.
    -- master Visibility="never" but cast satellite has VisibilityOverride="always").
    if self.cursorFrame and self.cursorFrame:IsShown() then
        self.castFrame:SetScript("OnUpdate", nil)
        self.castFrame:ClearAllPoints()
        self.castFrame:SetPoint("CENTER", self.cursorFrame, "CENTER", 0, 0)
    else
        if not _castFollowCursor then _castFollowCursor = _makeFollowCursorOnUpdate() end
        self.castFrame:SetScript("OnUpdate", _castFollowCursor)
        local s = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        self.castFrame:ClearAllPoints()
        self.castFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
            floor(x / s + 0.5), floor(y / s + 0.5))
    end
    self.castFrame:Show()
end

---------------------------------------------------------------------------------
-- Trail satellite
---------------------------------------------------------------------------------
local TRAIL_POOL_SIZE = 150
local _trailDots = {}        -- texture pool (inactive)
local _trailActive = {}      -- active entries: { tex, life, maxLife }
local _trailEntryPool = {}   -- recycled entry tables
local _trailTimer = 0
local _trailLastCX, _trailLastCY = 0, 0

local function _initTrailDotPool(container)
    for i = 1, TRAIL_POOL_SIZE do
        local dot = container:CreateTexture(nil, "ARTWORK")
        dot:SetTexture(RING_TEXTURES.ring_normal)
        dot:SetBlendMode("ADD")
        dot:Hide()
        _trailDots[i] = dot
    end
end

local function _spawnTrailDot(cx, cy)
    if #_trailDots == 0 then return end
    local db = C.db.Trail
    local dot = _trailDots[#_trailDots]
    _trailDots[#_trailDots] = nil

    local s = UIParent:GetEffectiveScale()
    local r, g, b, a
    if db.ColorInherit then
        r, g, b, a = KE:GetAccentColor(C.db.ColorMode or "class", C.db.Color)
    else
        r, g, b, a = KE:GetAccentColor("custom", db.Color)
    end
    local baseSize = (db.DotBaseSize or 40) * 0.8
    dot:SetVertexColor(r, g, b, a)
    dot:SetSize(baseSize, baseSize)
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", C.trailFrame, "BOTTOMLEFT", cx / s, cy / s)
    dot:SetAlpha(1)
    dot:Show()

    local entry = table.remove(_trailEntryPool) or {}
    entry.tex = dot
    entry.life = db.DotDuration or 0.5
    entry.maxLife = db.DotDuration or 0.5
    _trailActive[#_trailActive + 1] = entry
end

local function _updateTrailDots(elapsed)
    for i = #_trailActive, 1, -1 do
        local e = _trailActive[i]
        e.life = e.life - elapsed
        if e.life <= 0 then
            e.tex:Hide()
            _trailDots[#_trailDots + 1] = e.tex
            e.tex = nil
            _trailEntryPool[#_trailEntryPool + 1] = e
            _trailActive[i] = _trailActive[#_trailActive]
            _trailActive[#_trailActive] = nil
        else
            local pct = e.life / e.maxLife
            local sz = max(2, (C.db.Trail.DotBaseSize or 40) * 0.8 * pct)
            e.tex:SetSize(sz, sz)
            e.tex:SetAlpha(pct)
        end
    end
end

local function _hideAllTrailDots()
    for i = #_trailActive, 1, -1 do
        local e = _trailActive[i]
        e.tex:Hide()
        _trailDots[#_trailDots + 1] = e.tex
        e.tex = nil
        _trailEntryPool[#_trailEntryPool + 1] = e
        _trailActive[i] = nil
    end
end

local function _trailOnUpdate(_, elapsed)
    if not C._trail_instanceOK or not C._trail_cursorShown then
        _updateTrailDots(elapsed)  -- still fade existing dots
        return
    end
    local db = C.db.Trail
    local cx, cy = GetCursorPosition()
    _trailTimer = _trailTimer + elapsed
    local dx = cx - _trailLastCX
    local dy = cy - _trailLastCY
    local movedSq = dx * dx + dy * dy
    if _trailTimer >= (db.Density or 0.016) and movedSq >= 0.25 then
        _trailTimer = 0
        _spawnTrailDot(cx, cy)
        _trailLastCX, _trailLastCY = cx, cy
    end
    _updateTrailDots(elapsed)
end

function C:CreateTrailSatellite()
    if self.trailFrame then return end
    local tc = CreateFrame("Frame", "KE_CursorTrailContainer", UIParent)
    tc:SetAllPoints(UIParent)
    tc:SetFrameStrata("TOOLTIP")
    tc:SetFrameLevel(9990)
    tc:EnableMouse(false)
    _initTrailDotPool(tc)
    self.trailFrame = tc
end

function C:ApplyTrailSatellite()
    local db = self.db.Trail
    if not db.Enabled then
        if self.trailFrame then
            self.trailFrame:SetScript("OnUpdate", nil)
            _hideAllTrailDots()
        end
        return
    end
    if not self.trailFrame then self:CreateTrailSatellite() end
    -- Trail OnUpdate must always run when enabled (to fade existing dots)
    self.trailFrame:SetScript("OnUpdate", _trailOnUpdate)
end

---------------------------------------------------------------------------------
-- Dispel text satellite (absorbed from old DispelCursor)
---------------------------------------------------------------------------------
local _dispelFollowCursor = nil
local _dispelTrackedSpellID = nil

local function _dispelFindSpell()
    _dispelTrackedSpellID = nil
    if not C_SpellBook or not C_SpellBook.IsSpellInSpellBook then return end
    for _, spellID in ipairs(DISPEL_SPELL_IDS) do
        if C_SpellBook.IsSpellInSpellBook(spellID) then
            _dispelTrackedSpellID = spellID
            return
        end
    end
end

local function _dispelOnEvent(self, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        _dispelFindSpell()
    end
    -- Don't clobber an active test preview. SPELL_UPDATE_COOLDOWN fires from
    -- background sources (potion/hearthstone ticks, other addons) and would
    -- otherwise wipe the 7-second test cooldown set by DispelPreview.
    if C._dispelPreviewActive then return end
    if not _dispelTrackedSpellID then
        self.cooldown:Clear()
        return
    end
    local duration = C_Spell.GetSpellCooldownDuration(_dispelTrackedSpellID)
    if duration then
        self.cooldown:SetCooldownFromDurationObject(duration, false)
    else
        self.cooldown:Clear()
    end
end

function C:CreateDispelSatellite()
    if self.dispelFrame then return end
    local db = self.db.Dispel

    local df = CreateFrame("Frame", "KE_CursorDispelText", UIParent)
    df:SetFrameStrata("TOOLTIP")
    df:SetSize(1, 1)

    -- Hidden CooldownFrameTemplate to drive countdown text
    df.cooldown = CreateFrame("Cooldown", nil, df, "CooldownFrameTemplate")
    df.cooldown:SetSize(1, 1)
    df.cooldown:SetDrawSwipe(false)
    df.cooldown:SetDrawEdge(false)
    if df.cooldown.SetDrawBling then df.cooldown:SetDrawBling(false) end
    df.cooldown:SetHideCountdownNumbers(false)

    -- Find the countdown FontString region inside the Cooldown
    local cooldownText = nil
    for _, region in ipairs({ df.cooldown:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            cooldownText = region
            break
        end
    end
    if not cooldownText then
        cooldownText = df:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    end
    df.text = cooldownText
    local fontPath = KE:GetFontPath(db.FontFace) or KE.FONT
    df.text:SetFont(fontPath, db.FontSize or 18, "OUTLINE")
    df.text:SetTextColor(unpack(db.TextColor or { 1, 1, 1, 1 }))

    df:SetScript("OnEvent", _dispelOnEvent)
    df:Hide()
    self.dispelFrame = df
end

function C:_AttachDispelScripts()
    local df = self.dispelFrame
    if not df then return end
    df:UnregisterAllEvents()
    df:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    df:RegisterEvent("PLAYER_ENTERING_WORLD")
    df:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

function C:_DetachDispelScripts()
    local df = self.dispelFrame
    if not df then return end
    df:UnregisterAllEvents()
    df:SetScript("OnUpdate", nil)
end

function C:ApplyDispelSatellite()
    local db = self.db.Dispel
    if not db.Enabled then
        -- During an active test preview, keep the frame visible and refresh
        -- visuals so slider tweaks (offsets/font/color) take effect live.
        if self._dispelPreviewActive and self.dispelFrame then
            local fontPath = KE:GetFontPath(db.FontFace) or KE.FONT
            self.dispelFrame.text:SetFont(fontPath, db.FontSize or 18, "OUTLINE")
            self.dispelFrame.text:SetTextColor(unpack(db.TextColor or { 1, 1, 1, 1 }))
            self.dispelFrame.text:ClearAllPoints()
            if self.cursorFrame and self.cursorFrame:IsShown() then
                self.dispelFrame.text:SetPoint(db.AnchorPoint or "BOTTOM",
                    self.cursorFrame, db.AnchorPoint or "BOTTOM",
                    db.XOffset or 0, db.YOffset or 0)
            else
                self.dispelFrame.text:SetPoint(db.AnchorPoint or "BOTTOM",
                    self.dispelFrame, "CENTER",
                    db.XOffset or 0, db.YOffset or 0)
            end
            return
        end
        if self.dispelFrame then
            self:_DetachDispelScripts()
            self.dispelFrame:Hide()
        end
        return
    end
    if not self.dispelFrame then self:CreateDispelSatellite() end
    self:_AttachDispelScripts()

    local fontPath = KE:GetFontPath(db.FontFace) or KE.FONT
    self.dispelFrame.text:SetFont(fontPath, db.FontSize or 18, "OUTLINE")
    self.dispelFrame.text:SetTextColor(unpack(db.TextColor or { 1, 1, 1, 1 }))

    -- Always attach text to cursor frame when shown (anchor inheritance, free).
    -- Fall back to own OnUpdate only when cursor hidden (per-satellite override case).
    if self.cursorFrame and self.cursorFrame:IsShown() then
        self.dispelFrame:SetScript("OnUpdate", nil)
        self.dispelFrame.text:ClearAllPoints()
        self.dispelFrame.text:SetPoint(db.AnchorPoint or "BOTTOMLEFT",
            self.cursorFrame, db.AnchorPoint or "BOTTOMLEFT",
            db.XOffset or 10, db.YOffset or 10)
    else
        -- Detached: anchor text to dispelFrame, which the OnUpdate moves with the cursor.
        -- (Anchoring to UIParent with static coords would freeze the text.)
        if not _dispelFollowCursor then _dispelFollowCursor = _makeFollowCursorOnUpdate() end
        self.dispelFrame:SetScript("OnUpdate", _dispelFollowCursor)
        self.dispelFrame.text:ClearAllPoints()
        self.dispelFrame.text:SetPoint(db.AnchorPoint or "BOTTOMLEFT",
            self.dispelFrame, "CENTER",
            db.XOffset or 10, db.YOffset or 10)
    end

    _dispelFindSpell()
    self.dispelFrame:Show()
end

---------------------------------------------------------------------------------
-- Visibility system
---------------------------------------------------------------------------------
-- Internal combat flag driven by PLAYER_REGEN_DISABLED/ENABLED events.
-- InCombatLockdown() timing during the regen events is unreliable; tracking the
-- transition explicitly from the events themselves is the canonical addon pattern.
local _inCombat = false

local function _shouldShowByMode(mode)
    if mode == "always" then return true end
    if mode == "never"  then return false end
    if mode == "in_combat"     then return _inCombat end
    if mode == "out_of_combat" then return not _inCombat end
    if mode == "in_instance"   then return C:InRealInstancedContent() end
    if mode == "in_raid"       then return IsInRaid() end
    if mode == "in_party"      then return IsInGroup() and not IsInRaid() end
    if mode == "solo"          then return not IsInGroup() end
    if mode == "mouseDown"     then
        -- mouseDown handled separately in cursor OnUpdate (alpha-gated)
        return true  -- frame shown, alpha animates with hold
    end
    return true
end

function C:UpdateVisibility(event)
    -- Track combat state directly from the events that drive it
    if event == "PLAYER_REGEN_DISABLED" then
        _inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        _inCombat = false
    elseif event == nil or event == "PLAYER_ENTERING_WORLD" then
        -- Initial call (or world entry): fall back to API; accurate outside regen handlers
        _inCombat = InCombatLockdown() and true or false
    end

    if not self.db or not self.db.Enabled then
        self._cursorShown = false
        self._trail_cursorShown = false
        if self.cursorFrame then self.cursorFrame:Hide() end
        return
    end

    local masterShown = _shouldShowByMode(self.db.Visibility or "always")
    self._cursorShown = masterShown
    self._trail_cursorShown = masterShown
    self._trail_instanceOK = (not (self.db.Trail and self.db.Trail.InstanceOnly))
        or self:InRealInstancedContent()

    if self.cursorFrame then
        if masterShown then
            self.cursorFrame:Show()
        else
            self.cursorFrame:Hide()
        end
        -- Reset frame alphas when leaving mouseDown mode (else stay at 0 from hold-gate)
        if (self.db.Visibility or "always") ~= "mouseDown" then
            self.cursorFrame:SetAlpha(1)
            if self.gcdFrame    then self.gcdFrame:SetAlpha(1)    end
            if self.castFrame   then self.castFrame:SetAlpha(1)   end
            if self.dispelFrame then self.dispelFrame:SetAlpha(1) end
        end
    end

    -- For each satellite: respect VisibilityOverride if set, else inherit master
    local function satShouldShow(satDB)
        if not satDB or not satDB.Enabled then return false end
        local mode = satDB.VisibilityOverride
        local ok = (mode and _shouldShowByMode(mode)) or (not mode and masterShown)
        if satDB.InstanceOnly and not self:InRealInstancedContent() then ok = false end
        return ok
    end

    if self.gcdFrame then
        if satShouldShow(self.db.GCD) then
            self:ApplyGCDSatellite()
        else
            self:_DetachGCDScripts()
            self.gcdFrame:Hide()
            -- Integrated mode draws the swipe on cursorFrame.gcdCooldown (not gcdFrame),
            -- so the hide above doesn't suppress it — clear/hide the integrated child too.
            if self.cursorFrame and self.cursorFrame.gcdCooldown then
                self.cursorFrame.gcdCooldown:Clear()
                self.cursorFrame.gcdCooldown:Hide()
            end
        end
    end
    if self.castFrame then
        if satShouldShow(self.db.Cast) then
            self:ApplyCastSatellite()
        else
            self:_DetachCastScripts()
            self.castFrame:Hide()
        end
    end
    if self.dispelFrame then
        if satShouldShow(self.db.Dispel) then
            self:ApplyDispelSatellite()
        elseif not self._dispelPreviewActive then
            -- Don't hide during an active test preview — random events
            -- (GROUP_ROSTER_UPDATE, etc.) call UpdateVisibility and would
            -- otherwise wipe the 7-second preview the user just started.
            self:_DetachDispelScripts()
            self.dispelFrame:Hide()
        end
    end
    if self.trailFrame and self.db.Trail.Enabled and not masterShown then
        _hideAllTrailDots()  -- suppress dot fade-in when cursor hidden
    end
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
    -- Always (re-)attach OnUpdate — CreateCursorFrame early-returns when the frame
    -- already exists (e.g. on disable/re-enable cycle), so SetScript needs to run
    -- here to restore the follow-cursor behavior after OnDisable detached it.
    self.cursorFrame:SetScript("OnUpdate", _cursorOnUpdate)
    self:ApplyCursorSettings()

    -- Module-level visibility events (all global state changes)
    self:RegisterEvent("PLAYER_ENTERING_WORLD",  "UpdateVisibility")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA",  "UpdateVisibility")
    self:RegisterEvent("PLAYER_REGEN_DISABLED",  "UpdateVisibility")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",   "UpdateVisibility")
    self:RegisterEvent("GROUP_ROSTER_UPDATE",    "UpdateVisibility")

    -- Initial visibility decision for cursor (before satellites exist)
    self:UpdateVisibility()

    -- Defer satellite creation 0.5s (matches EUI; lets other addons finish init)
    C_Timer.After(0.5, function()
        if not self.db or not self.db.Enabled then return end
        self:ApplyGCDSatellite()
        self:ApplyCastSatellite()
        self:ApplyTrailSatellite()
        self:ApplyDispelSatellite()
        self:UpdateVisibility()  -- re-decide now that satellites exist
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
    if self.castFrame then
        self:_DetachCastScripts()
        self.castFrame:Hide()
    end
    if self.trailFrame then
        self.trailFrame:SetScript("OnUpdate", nil)
        _hideAllTrailDots()
    end
    if self.dispelFrame then
        self:_DetachDispelScripts()
        self.dispelFrame:Hide()
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
    local cast = self.db.Cast or {}
    if cast.RingColorMode == "theme" or cast.SwipeColorMode == "theme" then
        self:ApplyCastColor()
    end
end

---------------------------------------------------------------------------------
-- Preview support (called by PreviewManager when GUI Combat section is active)
---------------------------------------------------------------------------------
function C:ShowPreview()
    if not self.cursorFrame then self:CreateCursorFrame() end
    self:ApplyCursorSettings()
    self.cursorFrame:SetAlpha(1)  -- override any leftover mouseDown alpha
    self.cursorFrame:Show()
    self._cursorShown = true
    self._trail_cursorShown = true
    self._trail_instanceOK = true

    if self.db.GCD.Enabled then
        if not self.gcdFrame then self:CreateGCDSatellite() end
        self:ApplyGCDSatellite()
        self.gcdFrame:SetAlpha(1)
    end
    if self.db.Cast.Enabled then
        if not self.castFrame then self:CreateCastSatellite() end
        self:ApplyCastSatellite()
        self.castFrame:SetAlpha(1)
    end
    if self.db.Trail.Enabled then
        if not self.trailFrame then self:CreateTrailSatellite() end
        self:ApplyTrailSatellite()
    end
    if self.db.Dispel.Enabled then
        if not self.dispelFrame then self:CreateDispelSatellite() end
        self:ApplyDispelSatellite()
        self.dispelFrame:SetAlpha(1)
    end
end

function C:HidePreview()
    -- Restore actual visibility decision (or hide everything if module disabled)
    if not self.db or not self.db.Enabled then
        if self.cursorFrame then self.cursorFrame:Hide() end
        if self.gcdFrame    then self.gcdFrame:Hide() end
        if self.castFrame   then self.castFrame:Hide() end
        if self.trailFrame  then _hideAllTrailDots(); self.trailFrame:SetScript("OnUpdate", nil) end
        if self.dispelFrame then self.dispelFrame:Hide() end
        return
    end
    self:UpdateVisibility()
end

function C:Refresh()
    self:ApplyCursorSettings()
    -- Always call each Apply*Satellite — the function handles both create
    -- (when feature just got enabled) and teardown (when disabled). Gating on
    -- frame existence here would skip first-time enable from the GUI.
    self:ApplyGCDSatellite()
    self:ApplyCastSatellite()
    self:ApplyTrailSatellite()
    self:ApplyDispelSatellite()
    self:UpdateVisibility()
end

-- Test mode: force-show the dispel countdown for 7 seconds so users can
-- visually verify anchor/offset/font settings without waiting for a real CD.
-- Sets _dispelPreviewActive so ApplyDispelSatellite re-applies visuals (instead
-- of hiding) when the user tweaks sliders/pickers during the preview window.
function C:DispelPreview()
    if not self.dispelFrame then self:CreateDispelSatellite() end
    if not self.dispelFrame or not self.dispelFrame.cooldown then return end

    self._dispelPreviewActive = true

    local db = self.db.Dispel
    local fontPath = KE:GetFontPath(db.FontFace) or KE.FONT
    self.dispelFrame.text:SetFont(fontPath, db.FontSize or 18, "OUTLINE")
    self.dispelFrame.text:SetTextColor(unpack(db.TextColor or { 1, 1, 1, 1 }))

    self.dispelFrame.text:ClearAllPoints()
    if self.cursorFrame and self.cursorFrame:IsShown() then
        self.dispelFrame.text:SetPoint(db.AnchorPoint or "BOTTOM",
            self.cursorFrame, db.AnchorPoint or "BOTTOM",
            db.XOffset or 0, db.YOffset or 0)
    else
        if not _dispelFollowCursor then _dispelFollowCursor = _makeFollowCursorOnUpdate() end
        self.dispelFrame:SetScript("OnUpdate", _dispelFollowCursor)
        self.dispelFrame.text:SetPoint(db.AnchorPoint or "BOTTOM",
            self.dispelFrame, "CENTER",
            db.XOffset or 0, db.YOffset or 0)
    end

    self.dispelFrame:Show()
    self.dispelFrame.cooldown:SetCooldown(GetTime(), 7)

    -- Auto-hide after the countdown completes UNLESS the user enabled Dispel
    -- in the meantime (in which case the normal Apply path handles visibility).
    C_Timer.After(7.5, function()
        self._dispelPreviewActive = false
        if not self.db.Dispel.Enabled and self.dispelFrame then
            self.dispelFrame.cooldown:Clear()
            self.dispelFrame:Hide()
        end
    end)
end
