-- ╔══════════════════════════════════════════════════════════╗
-- ║  CursorCircle.lua                                        ║
-- ║  Module: Cursor Circle                                   ║
-- ║  Purpose: Cursor-following ring with GCD overlay and     ║
-- ║           multiple texture options.                      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CursorCircle: AceModule, AceEvent-3.0
local CC = KitnEssentials:NewModule("CursorCircle", "AceEvent-3.0")

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local GetCursorPosition = GetCursorPosition
local InCombatLockdown = InCombatLockdown
local IsMouseButtonDown = IsMouseButtonDown
local C_Spell = C_Spell
local UIParent = UIParent


local GCD_SPELL_ID = 61304

-- Available textures
CC.Textures = {
    ["Circle 1"] = "Interface\\AddOns\\KitnEssentials\\Media\\CursorCircles\\Circle.tga",
    ["Circle 2"] = "Interface\\AddOns\\KitnEssentials\\Media\\CursorCircles\\Aura73.tga",
    ["Circle 3"] = "Interface\\AddOns\\KitnEssentials\\Media\\CursorCircles\\Aura103.tga",
    ["Circle 4"] = "Interface\\AddOns\\KitnEssentials\\Media\\CursorCircles\\nauraThin.png",
    ["Circle 5"] = "Interface\\AddOns\\KitnEssentials\\Media\\CursorCircles\\nauraMedium.png",
    ["Circle 6"]    = "Interface\\AddOns\\KitnEssentials\\Media\\CursorCircles\\nauraThick.png",
}

CC.TextureOrder = { "Circle 1", "Circle 2", "Circle 3", "Circle 4", "Circle 5", "Circle 6" }

CC.GCDRingTextures = CC.Textures
CC.GCDRingTextureOrder = CC.TextureOrder

CC.GCDModeOptions = {
    { key = "disabled",   text = "Disabled" },
    { key = "integrated", text = "Integrated (overlay on circle)" },
    { key = "separate",   text = "Separate (own ring)" },
}

CC.VisibilityModeOptions = {
    { key = "always",    text = "Always Visible" },
    { key = "mouseDown", text = "Only When Mouse Button Held" },
}

CC.frame = nil
CC.gcdFrame = nil

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function CC:UpdateDB()
    self.db = KE.db.profile.CursorCircle
end

function CC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
local function GetGCDCooldown()
    local info = C_Spell.GetSpellCooldown(GCD_SPELL_ID)
    if info then
        return info.startTime, info.duration, info.modRate
    end
    return nil, nil, nil
end

function CC:CreateFrame()
    if self.frame then return end

    local db = self.db
    local mainTexPath = CC.Textures[db.Texture] or CC.Textures["Circle 3"]

    local f = CreateFrame("Frame", "KE_CursorCircleFrame", UIParent)
    f:SetSize(db.Size or 50, db.Size or 50)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(9999)
    f:EnableMouse(false)

    f.texture = f:CreateTexture(nil, "BACKGROUND")
    f.texture:SetAllPoints()
    f.texture:SetTexture(mainTexPath)
    f:Hide()

    -- Create integrated GCD cooldown overlay (on main circle)
    local gcdIntegrated = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    gcdIntegrated:SetAllPoints()
    gcdIntegrated:EnableMouse(false)
    gcdIntegrated:SetDrawSwipe(true)
    gcdIntegrated:SetDrawEdge(false)
    gcdIntegrated:SetHideCountdownNumbers(true)
    if gcdIntegrated.SetDrawBling then gcdIntegrated:SetDrawBling(false) end
    if gcdIntegrated.SetUseCircularEdge then gcdIntegrated:SetUseCircularEdge(true) end

    if gcdIntegrated.SetSwipeTexture then
        -- White modulation (1,1,1,1) is a visual no-op vs the texture's
        -- own colors. Args are non-nilable per the API spec.
        gcdIntegrated:SetSwipeTexture(mainTexPath, 1, 1, 1, 1)
    end
    gcdIntegrated:SetFrameLevel(f:GetFrameLevel() + 2)
    gcdIntegrated:Hide()
    f.gcdCooldown = gcdIntegrated

    -- Single OnUpdate drives both the main circle and the GCD ring.
    -- GCD frame has no OnUpdate of its own (positioning + mouse-down color
    -- are done here when the GCD frame is visible).
    local updateElapsed = 0
    local mouseHoldTime = 0
    -- Position cache: skip the ClearAllPoints+SetPoint pair when the cursor
    -- and effective scale are unchanged. Idle CPU here was 73% of total KE
    -- idle CPU before this gate (every-frame layout work on a stationary
    -- cursor). Sentinel -1 ensures the first tick always positions.
    local lastX, lastY, lastScale = -1, -1, -1
    f:SetScript("OnUpdate", function(frame, elapsed)
        if db.UseUpdateInterval then
            local updateInterval = db.UpdateInterval or 0.016
            updateElapsed = updateElapsed + elapsed
            if updateElapsed < updateInterval then return end
            updateElapsed = 0
        end

        local gcdFrame = self.gcdFrame

        if (db.VisibilityMode or "always") == "mouseDown" then
            local isMouseDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
            if isMouseDown then
                mouseHoldTime = mouseHoldTime + elapsed
            else
                mouseHoldTime = 0
            end
            local shown = isMouseDown and mouseHoldTime >= 0.15

            local r, g, b, a = KE:GetAccentColor(db.ColorMode, db.Color)
            frame.texture:SetVertexColor(r, g, b, shown and a or 0)

            if gcdFrame and gcdFrame.texture then
                local gcd = db.GCD or {}
                local gr, gg, gb, ga = KE:GetAccentColor(gcd.RingColorMode or "theme", gcd.RingColor)
                gcdFrame.texture:SetVertexColor(gr, gg, gb, shown and ga or 0)
            end

            -- Invisible: skip position work; invalidate cache so the next
            -- shown tick repositions even if the cursor pixel-coord matches.
            if not shown then
                lastX, lastY, lastScale = -1, -1, -1
                return
            end
        end

        local x, y = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        if x == lastX and y == lastY and scale == lastScale then return end
        lastX, lastY, lastScale = x, y, scale

        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)

        if gcdFrame then
            local gcdScale = gcdFrame:GetEffectiveScale()
            gcdFrame:ClearAllPoints()
            gcdFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / gcdScale, y / gcdScale)
        end
    end)

    self.frame = f
    self:ApplyColor()
    self:CreateGCDRing()
end

function CC:CreateGCDRing()
    if self.gcdFrame then return end

    local db = self.db
    local gcdSettings = db.GCD or {}
    local texPath = CC.GCDRingTextures[gcdSettings.Texture] or CC.GCDRingTextures["Circle 5"]

    local gf = CreateFrame("Frame", "KE_GCDRingFrame", UIParent)
    gf:SetSize(gcdSettings.Size or 25, gcdSettings.Size or 25)
    gf:SetFrameStrata("FULLSCREEN_DIALOG")
    gf:SetFrameLevel(9998)
    gf:EnableMouse(false)

    gf.texture = gf:CreateTexture(nil, "BACKGROUND")
    gf.texture:SetAllPoints()
    gf.texture:SetTexture(texPath)

    local gcdCooldown = CreateFrame("Cooldown", nil, gf, "CooldownFrameTemplate")
    gcdCooldown:SetAllPoints()
    gcdCooldown:EnableMouse(false)
    gcdCooldown:SetDrawSwipe(true)
    gcdCooldown:SetDrawEdge(false)
    gcdCooldown:SetHideCountdownNumbers(true)
    if gcdCooldown.SetDrawBling then gcdCooldown:SetDrawBling(false) end
    if gcdCooldown.SetUseCircularEdge then gcdCooldown:SetUseCircularEdge(true) end
    if gcdCooldown.SetSwipeTexture then
        gcdCooldown:SetSwipeTexture(texPath, 1, 1, 1, 1)
    end
    gcdCooldown:SetFrameLevel(gf:GetFrameLevel() + 2)
    gf.gcdCooldown = gcdCooldown
    gf:Hide()

    -- Positioning + mouse-down color are driven by the main frame's OnUpdate
    -- (see CC:CreateFrame). No OnUpdate script on the GCD frame.

    self.gcdFrame = gf
    self:ApplyGCDColor()
end

---------------------------------------------------------------------------------
-- Color
---------------------------------------------------------------------------------
function CC:ApplyColor()
    if not self.frame or not self.frame.texture then return end
    local db = self.db
    local r, g, b, a = KE:GetAccentColor(db.ColorMode, db.Color)

    -- If mouseDown mode, start with alpha 0
    local visMode = db.VisibilityMode or "always"
    if visMode == "mouseDown" then
        self.frame.texture:SetVertexColor(r, g, b, 0)
    else
        self.frame.texture:SetVertexColor(r, g, b, a)
    end
end

function CC:ApplyGCDColor()
    local db = self.db
    local gcd = db.GCD or {}

    local ringR, ringG, ringB, ringA = KE:GetAccentColor(gcd.RingColorMode or "theme", gcd.RingColor)
    local swipeR, swipeG, swipeB, swipeA = KE:GetAccentColor(gcd.SwipeColorMode or "custom", gcd.SwipeColor)

    -- Check visibility mode
    local visMode = db.VisibilityMode or "always"

    -- Apply to separate GCD frame
    if self.gcdFrame then
        if self.gcdFrame.texture then
            if visMode == "mouseDown" then
                self.gcdFrame.texture:SetVertexColor(ringR, ringG, ringB, 0)
            else
                self.gcdFrame.texture:SetVertexColor(ringR, ringG, ringB, ringA)
            end
        end
        if self.gcdFrame.gcdCooldown then
            self.gcdFrame.gcdCooldown:SetSwipeColor(swipeR, swipeG, swipeB, swipeA)
            if self.gcdFrame.gcdCooldown.SetSwipeTexture then
                local texPath = CC.GCDRingTextures[gcd.Texture] or CC.GCDRingTextures["Circle 5"]
                self.gcdFrame.gcdCooldown:SetSwipeTexture(texPath)
            end
            if self.gcdFrame.gcdCooldown.SetReverse then
                self.gcdFrame.gcdCooldown:SetReverse(gcd.Reverse or false)
            end
        end
    end

    -- Apply to integrated GCD cooldown
    if self.frame and self.frame.gcdCooldown then
        self.frame.gcdCooldown:SetSwipeColor(swipeR, swipeG, swipeB, swipeA)
        if self.frame.gcdCooldown.SetSwipeTexture then
            local texPath = CC.Textures[db.Texture] or CC.Textures["Circle 3"]
            self.frame.gcdCooldown:SetSwipeTexture(texPath)
        end
        if self.frame.gcdCooldown.SetReverse then
            self.frame.gcdCooldown:SetReverse(gcd.Reverse or false)
        end
    end
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function CC:ApplySettings()
    local db = self.db
    if not self.frame then self:CreateFrame() end
    if not self.frame then return end

    -- Update main circle
    self.frame:SetSize(db.Size or 50, db.Size or 50)
    local texPath = CC.Textures[db.Texture] or CC.Textures["Circle 3"]
    self.frame.texture:SetTexture(texPath)
    if self.frame.gcdCooldown and self.frame.gcdCooldown.SetSwipeTexture then
        self.frame.gcdCooldown:SetSwipeTexture(texPath)
    end

    self:ApplyColor()

    -- Update GCD ring
    local gcd = db.GCD or {}
    if not self.gcdFrame then self:CreateGCDRing() end
    if self.gcdFrame then
        self.gcdFrame:SetSize(gcd.Size or 25, gcd.Size or 25)
        local gcdTexPath = CC.GCDRingTextures[gcd.Texture] or CC.GCDRingTextures["Circle 5"]
        if self.gcdFrame.texture then
            self.gcdFrame.texture:SetTexture(gcdTexPath)
        end
    end

    self:ApplyGCDColor()
    self:UpdateGCDVisibility()

    if db.Enabled then
        self.frame:Show()
    else
        self.frame:Hide()
    end
end

---------------------------------------------------------------------------------
-- GCD Logic
---------------------------------------------------------------------------------
function CC:UpdateGCDVisibility()
    local db = self.db
    local gcd = db.GCD or {}
    local mode = gcd.Mode or "integrated"

    local shouldShow = db.Enabled
    if gcd.HideOutOfCombat and not InCombatLockdown() then
        shouldShow = false
    end

    if self.gcdFrame then
        if mode == "separate" and shouldShow then
            self.gcdFrame:Show()
        else
            self.gcdFrame:Hide()
        end
    end
end

function CC:UpdateGCDCooldown()
    local db = self.db
    local gcd = db.GCD or {}
    local mode = gcd.Mode or "integrated"

    if mode == "disabled" then
        if self.frame and self.frame.gcdCooldown then
            self.frame.gcdCooldown:Hide()
        end
        if self.gcdFrame and self.gcdFrame.gcdCooldown then
            self.gcdFrame.gcdCooldown:Hide()
        end
        return
    end

    if gcd.HideOutOfCombat and not InCombatLockdown() then
        if self.frame and self.frame.gcdCooldown then
            self.frame.gcdCooldown:Hide()
        end
        if self.gcdFrame then
            self.gcdFrame:Hide()
        end
        return
    end

    local start, duration, modRate = GetGCDCooldown()

    if start and duration and duration > 0 then
        if mode == "integrated" and self.frame and self.frame.gcdCooldown then
            self.frame.gcdCooldown:Show()
            if modRate then
                self.frame.gcdCooldown:SetCooldown(start, duration, modRate)
            else
                self.frame.gcdCooldown:SetCooldown(start, duration)
            end
        elseif mode == "separate" and self.gcdFrame and self.gcdFrame.gcdCooldown then
            if db.Enabled then
                self.gcdFrame:Show()
            end
            self.gcdFrame.gcdCooldown:Show()
            if modRate then
                self.gcdFrame.gcdCooldown:SetCooldown(start, duration, modRate)
            else
                self.gcdFrame.gcdCooldown:SetCooldown(start, duration)
            end
        end
    else
        if self.frame and self.frame.gcdCooldown then
            self.frame.gcdCooldown:Hide()
        end
        if self.gcdFrame and self.gcdFrame.gcdCooldown then
            self.gcdFrame.gcdCooldown:Hide()
        end
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function CC:OnCombatStart()
    self:UpdateGCDVisibility()
    self:UpdateGCDCooldown()
end

function CC:OnCombatEnd()
    self:UpdateGCDVisibility()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function CC:OnEnable()
    if not self.db.Enabled then return end

    self:CreateFrame()
    self:ApplySettings()

    -- Register events
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "UpdateGCDCooldown")
    self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", "UpdateGCDCooldown")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    if self.db.Enabled then self.frame:Show() end
end

function CC:UNIT_SPELLCAST_SUCCEEDED(_, unit)
    if unit ~= "player" then return end
    local gcd = self.db.GCD or {}
    if gcd.Mode == "disabled" then return end
    self:UpdateGCDCooldown()
end

function CC:OnThemeChanged()
    if not self.db or not self.db.Enabled then return end
    if self.db.ColorMode == "theme" then
        self:ApplyColor()
    end
    local gcd = self.db.GCD or {}
    if gcd.RingColorMode == "theme" or gcd.SwipeColorMode == "theme" then
        self:ApplyGCDColor()
    end
end

function CC:OnDisable()
    if self.frame then
        self.frame:Hide()
    end
    if self.gcdFrame then
        self.gcdFrame:Hide()
    end
    self:UnregisterAllEvents()
end
