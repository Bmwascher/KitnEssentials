-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local ST = KitnEssentials:NewModule("StasisTracker", "AceEvent-3.0")
ST.classRestriction = "EVOKER"

-- Localization
local CreateFrame = CreateFrame
local GetTime = GetTime
local C_Spell = C_Spell
local C_Timer = C_Timer
local math_floor = math.floor
local select = select
local issecretvalue = issecretvalue
local PlayerUtil = PlayerUtil
local UnitClass = UnitClass

-- Spell constants
local STASIS_STORE = 370537
local STASIS_RELEASE = 370564
local TTS = 370553 -- Temporal Transcendence

local TRACKED_SPELLS = {
    [361509] = true,  -- Living Flame
    [364343] = true,  -- Echo
    [360995] = true,  -- Verdant Embrace
    [366155] = true,  -- Reversion
    [1256581] = true, -- Merithras Blessing
    [355913] = true,  -- Emerald Blossom
    [374251] = true,  -- Cauterizing Flame
    [360823] = true,  -- Naturalize
    [373861] = true,  -- Temporal Anomaly
}

local DREAM_BREATH = { [355936] = true, [382614] = true }
local FIRE_BREATH = { [357208] = true, [382266] = true }

-- Spec ID
local PRESERVATION = 1468

-- Placeholder icon (question mark)
local PLACEHOLDER_ICON = 134400

-- Stasis duration (seconds)
local STASIS_DURATION = 30

-- Module state
ST.containerFrame = nil
ST.icons = {}
ST.bar = nil
ST.barBackground = nil
ST.countdownText = nil
ST.state = {
    showing = false,
    storedSpells = 0,
    fillTime = nil,
    ticker = nil,
    tts = false,
}

function ST:UpdateDB()
    self.db = KE.db.profile.StasisTracker
end

function ST:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function ST:IsValidSpec()
    local specId = PlayerUtil.GetCurrentSpecID()
    return specId == PRESERVATION
end

--------------------------------------------------------------------------------
-- Frame creation
--------------------------------------------------------------------------------
function ST:CreateFrames()
    if self.containerFrame then return end
    local db = self.db

    -- Container
    local container = CreateFrame("Frame", "KE_StasisTracker", UIParent)
    container:SetSize(1, 1)
    container:SetFrameStrata(db.Strata or "HIGH")
    container:EnableMouse(false)
    container:SetMouseClickEnabled(false)
    container:Hide()
    self.containerFrame = container

    -- Icons
    for i = 1, 3 do
        local icon = container:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(PLACEHOLDER_ICON)
        icon:Hide()
        self.icons[i] = icon
    end

    -- Status bar
    local bar = CreateFrame("StatusBar", nil, container)
    bar:SetMinMaxValues(0, STASIS_DURATION)
    bar:SetValue(0)
    self.bar = bar

    -- Bar background
    local barBG = bar:CreateTexture(nil, "BACKGROUND")
    barBG:SetAllPoints(bar)
    self.barBackground = barBG

    -- Countdown text
    local text = bar:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", bar, "CENTER")
    text:Hide()
    self.countdownText = text

    self:ApplySettings()
end

--------------------------------------------------------------------------------
-- Layout — handles Horizontal / Vertical growth
--------------------------------------------------------------------------------
function ST:LayoutFrames()
    if not self.containerFrame then return end
    local db = self.db
    local iconSize = db.IconSize or 40
    local spacing = db.IconSpacing or 2
    local barHeight = db.BarHeight or 15
    local direction = db.GrowthDirection or "Horizontal"
    local barSide = db.BarSide or "start"

    for i = 1, 3 do
        self.icons[i]:SetSize(iconSize, iconSize)
    end

    if direction == "Vertical" then
        local iconsHeight = (3 * iconSize) + (2 * spacing)
        self.containerFrame:SetSize(iconSize + barHeight, iconsHeight)

        self.bar:ClearAllPoints()
        self.bar:SetSize(barHeight, iconsHeight)
        self.bar:SetOrientation("VERTICAL")

        if barSide == "end" then
            -- Bar on right, icons on left
            self.bar:SetPoint("BOTTOMRIGHT", self.containerFrame, "BOTTOMRIGHT", 0, 0)
            for i = 1, 3 do
                self.icons[i]:ClearAllPoints()
                local offset = (i - 1) * (iconSize + spacing)
                self.icons[i]:SetPoint("BOTTOMLEFT", self.containerFrame, "BOTTOMLEFT", 0, offset)
            end
        else
            -- Bar on left, icons on right
            self.bar:SetPoint("BOTTOMLEFT", self.containerFrame, "BOTTOMLEFT", 0, 0)
            for i = 1, 3 do
                self.icons[i]:ClearAllPoints()
                local offset = (i - 1) * (iconSize + spacing)
                self.icons[i]:SetPoint("BOTTOMRIGHT", self.containerFrame, "BOTTOMRIGHT", 0, offset)
            end
        end
    else
        local iconsWidth = (3 * iconSize) + (2 * spacing)
        self.containerFrame:SetSize(iconsWidth, iconSize + barHeight)

        self.bar:ClearAllPoints()
        self.bar:SetSize(iconsWidth, barHeight)
        self.bar:SetOrientation("HORIZONTAL")

        if barSide == "end" then
            -- Bar on bottom, icons on top
            self.bar:SetPoint("BOTTOMLEFT", self.containerFrame, "BOTTOMLEFT", 0, 0)
            for i = 1, 3 do
                self.icons[i]:ClearAllPoints()
                local offset = (i - 1) * (iconSize + spacing)
                self.icons[i]:SetPoint("BOTTOMLEFT", self.bar, "TOPLEFT", offset, 0)
            end
        else
            -- Bar on top, icons below
            self.bar:SetPoint("TOPLEFT", self.containerFrame, "TOPLEFT", 0, 0)
            for i = 1, 3 do
                self.icons[i]:ClearAllPoints()
                local offset = (i - 1) * (iconSize + spacing)
                self.icons[i]:SetPoint("TOPLEFT", self.bar, "BOTTOMLEFT", offset, 0)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Apply settings
--------------------------------------------------------------------------------
function ST:ApplySettings()
    if not self.containerFrame then return end
    local db = self.db

    -- Strata
    self.containerFrame:SetFrameStrata(db.Strata or "HIGH")
    self.bar:SetFrameStrata(db.Strata or "HIGH")

    -- Bar texture
    local texturePath = KE.LSM and KE.LSM:Fetch("statusbar", db.BarTexture or "KitnUI")
        or "Interface/Buttons/WHITE8x8"
    self.bar:SetStatusBarTexture(texturePath)

    -- Bar color
    local r, g, b, a = KE:GetAccentColor(db.ColorMode, db.Color)
    self.bar:SetStatusBarColor(r, g, b, a)

    -- Bar background
    local bg = db.BarBackgroundColor or { 0, 0, 0, 0.8 }
    self.barBackground:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 0.8)

    -- Font
    KE:ApplyFontToText(self.countdownText,
        db.FontFace or "Expressway",
        db.FontSize or 14,
        db.FontOutline or "OUTLINE"
    )

    -- Hide soft outline shadows when not actively showing
    if not self.isPreview and not self.state.showing then
        self.countdownText:Hide()
        if self.countdownText.softOutline then
            self.countdownText.softOutline:SetShown(false)
        end
    end

    self:LayoutFrames()
    self:ApplyPosition()
end

function ST:ApplyPosition()
    if not self.containerFrame or not self.db then return end
    KE:ApplyFramePosition(self.containerFrame, self.db.Position, self.db)
end

--------------------------------------------------------------------------------
-- Stasis state machine
--------------------------------------------------------------------------------
function ST:StartStasis()
    self.state.storedSpells = 0
    self.state.showing = true
    self.state.tts = false

    for i = 1, 3 do
        self.icons[i]:SetTexture(PLACEHOLDER_ICON)
        self.icons[i]:Show()
    end

    self.bar:SetValue(0)
    self.countdownText:SetText("")
    self.countdownText:Show()
    if self.countdownText.softOutline then
        local outline = self.db.FontOutline or "OUTLINE"
        self.countdownText.softOutline:SetShown(outline == "SOFTOUTLINE")
    end

    self.containerFrame:Show()
end

function ST:ReleaseStasis()
    if self.state.ticker then
        self.state.ticker:Cancel()
        self.state.ticker = nil
    end
    self.state.showing = false
    self.state.tts = false
    self.state.storedSpells = 0
    self.state.fillTime = nil

    if self.countdownText then
        self.countdownText:Hide()
        if self.countdownText.softOutline then
            self.countdownText.softOutline:SetShown(false)
        end
    end
    if self.containerFrame then
        self.containerFrame:Hide()
    end
end

function ST:AddSpell(spellId)
    self.state.storedSpells = self.state.storedSpells + 1
    local index = self.state.storedSpells
    if self.icons[index] then
        local texture = C_Spell.GetSpellTexture(spellId)
        if texture then
            self.icons[index]:SetTexture(texture)
        end
    end
    if self.state.storedSpells >= 3 then
        self:StartCountdown()
    end
end

function ST:StartCountdown()
    self.state.fillTime = GetTime()
    self.state.ticker = C_Timer.NewTicker(0.1, function()
        if not self.state.fillTime then return end
        local timeLeft = self.state.fillTime + STASIS_DURATION - GetTime()
        if timeLeft <= 0 then
            self:ReleaseStasis()
            return
        end
        self.countdownText:SetText(math_floor(timeLeft))
        self.bar:SetValue(timeLeft)
    end)
end

--------------------------------------------------------------------------------
-- Event handling
--------------------------------------------------------------------------------
function ST:OnEvent(event, unit, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        local _, spellId = ...
        if issecretvalue(spellId) then return end

        if not self.state.showing and spellId == STASIS_STORE then
            self:StartStasis()
        elseif self.state.showing and self.state.storedSpells < 3 then
            if TRACKED_SPELLS[spellId] then
                self:AddSpell(spellId)
            elseif spellId == TTS and not self.state.tts then
                self.state.tts = true
            elseif self.state.tts then
                if DREAM_BREATH[spellId] then
                    self.state.tts = false
                    self:AddSpell(spellId)
                elseif FIRE_BREATH[spellId] then
                    self.state.tts = false
                end
            end
        elseif self.state.showing and spellId == STASIS_RELEASE then
            self:ReleaseStasis()
        end

    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        if unit ~= "player" then return end
        if not self.state.showing or self.state.storedSpells >= 3 then return end
        local _, spellId, success = ...
        if issecretvalue(spellId) then return end
        if success and DREAM_BREATH[spellId] then
            self:AddSpell(spellId)
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if self:IsValidSpec() then
            self:RegisterSpellEvents()
        else
            self:UnregisterSpellEvents()
            self:ReleaseStasis()
        end
    end
end

function ST:RegisterSpellEvents()
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnEvent")
    self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP", "OnEvent")
end

function ST:UnregisterSpellEvents()
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:UnregisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
end

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------
function ST:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "StasisTracker",
            displayName = "Stasis Tracker",
            frame = self.containerFrame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; self:ApplyPosition() end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "StasisTracker",
        })
        self.editModeRegistered = true
    end
end

--------------------------------------------------------------------------------
-- Preview
--------------------------------------------------------------------------------
function ST:ShowPreview()
    self:CreateFrames()
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()

    for i = 1, 3 do
        self.icons[i]:SetTexture(PLACEHOLDER_ICON)
        self.icons[i]:Show()
    end
    self.bar:SetValue(15)
    self.countdownText:SetText("15")
    self.countdownText:Show()
    if self.countdownText.softOutline then
        local outline = self.db.FontOutline or "OUTLINE"
        self.countdownText.softOutline:SetShown(outline == "SOFTOUTLINE")
    end
    self.containerFrame:Show()
end

function ST:HidePreview()
    self.isPreview = false
    if self.countdownText then
        self.countdownText:Hide()
        if self.countdownText.softOutline then
            self.countdownText.softOutline:SetShown(false)
        end
    end
    if self.containerFrame then
        self.containerFrame:Hide()
    end
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------
function ST:OnEnable()
    if not self.db.Enabled then return end

    -- Evoker only
    if select(3, UnitClass("player")) ~= Constants.UICharacterClasses.Evoker then
        return
    end

    self:CreateFrames()
    self:RegWithEditMode()
    self:ApplySettings()
    self:ReleaseStasis()

    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnEvent")

    if self:IsValidSpec() then
        self:RegisterSpellEvents()
    end
end

function ST:OnDisable()
    self:ReleaseStasis()
    self.isPreview = false
    self:UnregisterAllEvents()
end
