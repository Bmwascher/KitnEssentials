-- ╔══════════════════════════════════════════════════════════╗
-- ║  BurningRush.lua                                         ║
-- ║  Module: Burning Rush (Warlock)                          ║
-- ║  Purpose: Glowing icon while Burning Rush (111400) is     ║
-- ║           active. Warlock-only, spell-known gated.        ║
-- ║  Credit: Ported from NorskenUI ClassUtil/BurningRush.     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class BurningRush: AceModule, AceEvent-3.0
local BURN = KitnEssentials:NewModule("BurningRush", "AceEvent-3.0")

local LCG = LibStub("LibCustomGlow-1.0", true)

local CreateFrame = CreateFrame
local UnitClass = UnitClass
local IsSpellKnown = IsSpellKnown
local C_Timer = C_Timer
local UIParent = UIParent

local BURNING_RUSH_SPELL = 111400
local BURNING_RUSH_ICON = 538043

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function BURN:UpdateDB()
    self.db = KE.db.profile.BurningRush
end

function BURN:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------------
function BURN:CreateFrame()
    if self.frame then return end

    local db = self.db
    local size = db.IconSize or 40

    local f = CreateFrame("Frame", "KE_BurningRushIcon", UIParent)
    f:SetSize(size, size)
    f:EnableMouse(false)
    f:SetMouseClickEnabled(false)
    f:Hide()

    KE:AddIconBorders(f)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    KE:ApplyIconZoom(f.icon)
    f.icon:SetTexture(BURNING_RUSH_ICON)

    self.frame = f
    self.icon = f.icon

    self:ApplySettings()
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function BURN:ApplySettings()
    if not self.frame then return end
    local db = self.db

    self.frame:SetSize(db.IconSize, db.IconSize)
    self.icon:SetAllPoints(self.frame)

    self:ApplyPosition()

    if self.glowActive then
        self:StopGlow()
        self:StartGlow()
    elseif db.GlowEnabled and self.frame:IsShown() then
        self:StartGlow()
    end
end

function BURN:ApplyPosition()
    if not self.db.Enabled then return end
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Glow (reads the GUI-GlowSettingsCard db keys so its sliders take effect)
---------------------------------------------------------------------------------
function BURN:StartGlow()
    if not self.frame then return end
    if not self.db.GlowEnabled then return end
    if not LCG then return end

    local db = self.db
    if db.GlowType == "pixel" then
        LCG.PixelGlow_Start(self.frame, db.GlowColor, db.GlowLines, db.GlowFrequency,
            db.GlowLength, db.GlowThickness, db.GlowXOffset, db.GlowYOffset, db.GlowBorder, nil)
    elseif db.GlowType == "autocast" then
        LCG.AutoCastGlow_Start(self.frame, db.GlowColor, db.GlowLines, db.GlowFrequency,
            db.GlowScale, db.GlowXOffset, db.GlowYOffset, nil)
    elseif db.GlowType == "button" then
        LCG.ButtonGlow_Start(self.frame, db.GlowColor, db.GlowFrequency)
    elseif db.GlowType == "proc" then
        LCG.ProcGlow_Start(self.frame, {
            color = db.GlowColor,
            startAnim = db.GlowStartAnim,
            duration = db.GlowDuration,
            xOffset = db.GlowXOffset,
            yOffset = db.GlowYOffset,
        })
    end

    self.glowActive = true
end

function BURN:StopGlow()
    if not self.frame then return end
    if not LCG then return end

    LCG.PixelGlow_Stop(self.frame)
    LCG.AutoCastGlow_Stop(self.frame)
    LCG.ButtonGlow_Stop(self.frame)
    LCG.ProcGlow_Stop(self.frame)

    self.glowActive = false
end

---------------------------------------------------------------------------------
-- Show / Hide
---------------------------------------------------------------------------------
function BURN:ShowDisplay()
    if not self.frame then self:CreateFrame() end
    if not self.frame then return end
    self:StartGlow()
    self.frame:Show()
end

function BURN:HideDisplay()
    if not self.frame then return end
    self:StopGlow()
    self.frame:Hide()
end

function BURN:SetActive(active)
    if self.isPreview then return end
    self.active = active
    if active then self:ShowDisplay() else self:HideDisplay() end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function BURN:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "BurningRush", displayName = "Burning Rush", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "BurningRush",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function BURN:ShowPreview()
    if not self.frame then self:CreateFrame() end
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()
    self:StartGlow()
    self.frame:Show()
end

function BURN:HidePreview()
    self.isPreview = false
    self:StopGlow()
    if self.frame then self.frame:Hide() end
    if self.active then self:ShowDisplay() end
end

function BURN:TogglePreview()
    if self.isPreview then self:HidePreview() else self:ShowPreview() end
    return self.isPreview
end

function BURN:IsPreviewActive()
    return self.isPreview == true
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function BURN:OnEnable()
    -- Warlock-only + spell known. (Corrects NUI's dead `not className == "WARLOCK"`
    -- precedence bug.) Silent no-op for everyone else.
    local _, class = UnitClass("player")
    if class ~= "WARLOCK" or not IsSpellKnown(BURNING_RUSH_SPELL) then return end
    if not self.db or not self.db.Enabled then return end

    self:CreateFrame()
    self:RegWithEditMode()
    C_Timer.After(0.5, function() self:ApplyPosition() end)

    -- AceEvent RegisterEvent + manual unit filter (KE convention — no RegisterUnitEvent).
    -- UNIT_SPELLCAST_SUCCEEDED payload: (unitTarget, castGUID, spellID).
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
        if unit ~= "player" then return end
        if spellID ~= BURNING_RUSH_SPELL then return end
        self:SetActive(true)
    end)
    -- SPELL_ACTIVATION_OVERLAY_GLOW_HIDE payload: (spellID).
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, spellID)
        if spellID ~= BURNING_RUSH_SPELL then return end
        self:SetActive(false)
    end)
    self:RegisterEvent("PLAYER_DEAD", function()
        self.active = false
        self:HideDisplay()
    end)
end

function BURN:OnDisable()
    if self.frame then
        self:StopGlow()
        self.frame:Hide()
    end
    self.active = false
    self.isPreview = false
    self.glowActive = false
    self:UnregisterAllEvents()
    if KE.EditMode then KE.EditMode:UnregisterElement("BurningRush") end
end
