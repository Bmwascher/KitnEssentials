-- ╔══════════════════════════════════════════════════════════╗
-- ║  DisintegrateTicks.lua                                   ║
-- ║  Module: Disintegrate Ticks                              ║
-- ║  Purpose: Displays tick marks on cast bar during         ║
-- ║           Disintegrate channels.                         ║
-- ║  Note: Evoker only (Devastation/Preservation).           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local DT = KitnEssentials:NewModule("DisintegrateTicks", "AceEvent-3.0")
DT.classRestriction = "EVOKER"

local CreateFrame = CreateFrame
local GetTime = GetTime
local C_SpellBook = C_SpellBook
local C_Spell = C_Spell
local C_AddOns = C_AddOns
local PlayerUtil = PlayerUtil
local hooksecurefunc = hooksecurefunc
local math_ceil = math.ceil
local math_max = math.max
local UnitChannelInfo = UnitChannelInfo
local UnitSpellHaste = UnitSpellHaste


---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local DISINTEGRATE = 356995
local MASS_DISINTEGRATE = 436335
local DISINTEGRATE_TALENT = 1219723 -- gives 5th tick
local FIRE_BREATH = 357208
local FIRE_BREATH_FONT = 382266
local ETERNITY_SURGE = 359073
local ETERNITY_SURGE_FONT = 382411
local NATURAL_CONVERGENCE = 369913
local STACK_EXPIRY = 15

local DEVASTATION = 1467
local PRESERVATION = 1468

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
DT.ticks = {}
DT.maxTicks = 4
DT.channeling = false
DT.massDisintegrateStacks = 0
DT.lastGainedStack = 0
DT.hasTipTheScalesActive = false
DT.chaining = false
DT.lastStart = 0
DT.firstTick = 0
DT.prevEndTime = nil
DT.prevHastedTickInterval = nil
DT.castBarInfo = { width = 0, height = 0, anchor = nil }
DT.hooksInstalled = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function DT:UpdateDB()
    self.db = KE.db.profile.DisintegrateTicks
end

function DT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

local function IsEmpower(spellId)
    return spellId == FIRE_BREATH
        or spellId == FIRE_BREATH_FONT
        or spellId == ETERNITY_SURGE
        or spellId == ETERNITY_SURGE_FONT
end

local function KnowsMassDisintegrate()
    return C_SpellBook.IsSpellKnownOrInSpellBook(MASS_DISINTEGRATE)
end

function DT:IsValidSpec()
    local specId = PlayerUtil.GetCurrentSpecID()
    return specId == DEVASTATION or specId == PRESERVATION
end

function DT:QueryTalentsAndHide()
    self.maxTicks = C_SpellBook.IsSpellKnown(DISINTEGRATE_TALENT) and 5 or 4
    self:HideTicks()
end

---------------------------------------------------------------------------------
-- Cast Bar Discovery
---------------------------------------------------------------------------------
function DT:DiscoverCastBar()
    if self.castBarInfo.anchor then return self.castBarInfo.anchor end

    -- UUF (most common for KitnUI users)
    if UUF_Player_CastBar then
        self:SetCastBarAnchor(UUF_Player_CastBar)
        return self.castBarInfo.anchor
    end

    -- BCDM
    if BCDM_CastBar and BCDM_CastBar.Status then
        self:SetCastBarAnchor(BCDM_CastBar.Status)
        return self.castBarInfo.anchor
    end

    -- Ayije CDM
    if Ayije_CastBar and Ayije_CastBar.castBar then
        self:SetCastBarAnchor(Ayije_CastBar.castBar)
        return self.castBarInfo.anchor
    end

    -- Blizzard default
    if PlayerCastingBarFrame then
        self:SetCastBarAnchor(PlayerCastingBarFrame)
        return self.castBarInfo.anchor
    end

    return nil
end

function DT:SetCastBarAnchor(anchor)
    if self.castBarInfo.anchor == anchor then return end
    self.castBarInfo.anchor = anchor
    local w, h = anchor:GetSize()
    self.castBarInfo.width = math_ceil(w)
    self.castBarInfo.height = math_ceil(h)
    self:HideTicks()
    self:UpdateWarningPosition()
end

function DT:AdjustDimensions(width, height)
    width = math_ceil(width)
    height = math_ceil(height)
    if width ~= self.castBarInfo.width or height ~= self.castBarInfo.height then
        self.castBarInfo.width = width
        self.castBarInfo.height = height
        self:QueryTalentsAndHide()
    end
end

---------------------------------------------------------------------------------
-- Haste / Tick Helpers
---------------------------------------------------------------------------------
function DT:GetHaste()
    return 1 + UnitSpellHaste("player") / 100
end

function DT:GetTickInterval()
    local base = 1
    -- Azure Celerity reduces tick interval by 25%
    if C_SpellBook.IsSpellKnown(DISINTEGRATE_TALENT) then
        base = base * 0.75
    end
    -- Natural Convergence reduces total cast time by 20%
    if C_SpellBook.IsSpellKnown(NATURAL_CONVERGENCE) then
        base = base * 0.8
    end
    return base
end

---------------------------------------------------------------------------------
-- Tick Management
---------------------------------------------------------------------------------
function DT:CreateTick(index)
    local anchor = self.castBarInfo.anchor
    if not anchor then return nil end

    local db = self.db
    local color = db.TickColor or { 1, 1, 1, 0.8 }
    local tick = anchor:CreateTexture("KE_DisintegrateTick" .. index, "OVERLAY")
    tick:SetColorTexture(color[1], color[2], color[3], color[4])
    tick:Hide()
    return tick
end

function DT:HideTicks()
    for _, tick in next, self.ticks do
        tick:Hide()
    end
end

function DT:UpdateTicks(castBarFrame, duration)
    self:HideTicks()
    if not castBarFrame then return end

    local db = self.db
    local tickWidth = db.TickWidth or 2
    local hastedTickInterval = self:GetTickInterval() / self:GetHaste()
    local pixelsPerSecond = self.castBarInfo.width / duration

    for i = 1, self.maxTicks do
        local tick = self.ticks[i]

        if tick == nil or tick:GetParent() ~= castBarFrame then
            tick = self:CreateTick(i)
            self.ticks[i] = tick
        end

        if tick then
            tick:SetSize(tickWidth, self.castBarInfo.height * 0.95)
            tick:ClearAllPoints()

            local tickTime = i * hastedTickInterval

            if self.chaining then
                local interval = (duration - self.firstTick) / (self.maxTicks - 1)
                tickTime = self.firstTick + (i - 1) * interval
            end

            tick:SetPoint("CENTER", castBarFrame, "LEFT", (duration - tickTime) * pixelsPerSecond, 0)

            if tickTime < duration * 0.99 then
                tick:Show()
            else
                tick:Hide()
            end
        end
    end
end

function DT:ApplyTickColor()
    local db = self.db
    local color = db.TickColor or { 1, 1, 1, 0.8 }
    for _, tick in next, self.ticks do
        tick:SetColorTexture(color[1], color[2], color[3], color[4])
    end
end

---------------------------------------------------------------------------------
-- Warning Frame
---------------------------------------------------------------------------------
function DT:CreateWarningFrame()
    if self.warningFrame then return end

    local f = CreateFrame("Frame", "KE_DisintegrateTicksFrame", UIParent)
    f:SetSize(200, 30)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:SetMouseClickEnabled(false)

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    text:Hide()

    f:Hide()

    self.warningFrame = f
    self.warningText = text

    self:ApplyWarningSettings()
end

function DT:ApplyWarningSettings()
    if not self.warningText then return end
    local db = self.db
    local cw = db.ClipWarning or {}

    KE:ApplyFontToText(self.warningText,
        cw.FontFace or "Expressway",
        cw.FontSize or 16,
        cw.FontOutline or "SOFTOUTLINE"
    )

    self.warningText:SetText(cw.Text or "DON'T CLIP")
    local color = cw.Color or { 1, 0, 0, 1 }
    self.warningText:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    -- ApplyFontToText may create/show soft outline shadows — hide them
    -- ShowWarning() will re-show when actually needed during combat
    if not self.isPreview then
        self:HideWarning()
    end
end

function DT:UpdateWarningPosition()
    if not self.warningFrame then return end
    KE:ApplyFramePosition(self.warningFrame, self.db.Position, self.db)
end

function DT:ShowWarning()
    if not self.warningText then return end
    local cw = self.db.ClipWarning or {}
    if not cw.Enabled then return end
    if self.warningFrame then
        self.warningFrame:Show()
    end
    self.warningText:Show()
    if self.warningText.softOutline then
        self.warningText.softOutline:SetShown(true)
    end
end

function DT:HideWarning()
    if not self.warningText then return end
    self.warningText:Hide()
    if self.warningText.softOutline then
        self.warningText.softOutline:SetShown(false)
    end
    if self.warningFrame then
        self.warningFrame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Cast Bar Hooks
---------------------------------------------------------------------------------
function DT:InstallCastBarHooks()
    if self.hooksInstalled then return end
    self.hooksInstalled = true

    local self_ = self

    -- UUF
    if C_AddOns.IsAddOnLoaded("UnhaltedUnitFrames") and UUF_Player_CastBar then
        hooksecurefunc(UUF_Player_CastBar, "Show", function(cb)
            local w, h = cb:GetSize()
            self_:AdjustDimensions(w, h)
            self_:SetCastBarAnchor(cb)
        end)
    end

    -- BCDM
    if C_AddOns.IsAddOnLoaded("BetterCooldownManager") and BCDM_CastBar then
        hooksecurefunc(BCDM_CastBar, "Show", function(cb)
            local w, h = cb:GetSize()
            self_:AdjustDimensions(w, h)
            if cb.Status then self_:SetCastBarAnchor(cb.Status) end
        end)
    end

    -- Ayije CDM
    if C_AddOns.IsAddOnLoaded("Ayije_CDM") and Ayije_CastBar then
        hooksecurefunc(Ayije_CastBar, "Show", function(cb)
            local w, h = cb:GetSize()
            self_:AdjustDimensions(w, h)
            if cb.castBar then self_:SetCastBarAnchor(cb.castBar) end
        end)
    end

    -- Blizzard EditMode resize
    if EditModeManagerFrame then
        hooksecurefunc(EditModeManagerFrame, "UpdateLayoutInfo", function()
            if not PlayerCastingBarFrame then return end
            local locked = PlayerCastingBarFrame:IsAttachedToPlayerFrame()
            self_:AdjustDimensions(locked and 150 or 208, locked and 10 or 11)
        end)
    end

    -- ActionBarsEnhanced resize
    if C_AddOns.IsAddOnLoaded("ActionBarsEnhanced") and PlayerCastingBarFrame then
        PlayerCastingBarFrame:HookScript("OnSizeChanged", function(cb)
            if self_.castBarInfo.anchor ~= cb then return end
            local w, h = cb:GetSize()
            self_:AdjustDimensions(w, h)
        end)
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function DT:OnEvent(event, unit, ...)
    -- Filter unit-specific events to player only
    if event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
    end

    if event == "LOADING_SCREEN_DISABLED" then
        self:DiscoverCastBar()
        self:QueryTalentsAndHide()
        self:HideWarning()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if self:IsValidSpec() then
            self:RegisterSpecEvents()
            self:QueryTalentsAndHide()
        else
            self:UnregisterSpecEvents()
            self:HideTicks()
            self:HideWarning()
        end

    elseif event == "PLAYER_DEAD" then
        self.massDisintegrateStacks = 0

    elseif event == "TRAIT_CONFIG_UPDATED" then
        self:QueryTalentsAndHide()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, spellId = ...  -- castGUID, spellID (unit already captured)
        if self.hasTipTheScalesActive and IsEmpower(spellId) and KnowsMassDisintegrate() then
            self.hasTipTheScalesActive = false
            self.massDisintegrateStacks = self.massDisintegrateStacks + 1
            self.lastGainedStack = GetTime()
        end

    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        local _, spellId, complete = ...  -- castGUID, spellID, complete
        if not complete or not IsEmpower(spellId) or not KnowsMassDisintegrate() then
            return
        end
        self.massDisintegrateStacks = self.massDisintegrateStacks + 1
        self.lastGainedStack = GetTime()

    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        local _, spellId = ...
        if spellId ~= DISINTEGRATE then return end

        local endTimeMS = select(5, UnitChannelInfo("player"))
        if endTimeMS ~= nil then
            self.prevEndTime = endTimeMS / 1000
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local _, spellId = ...
        if spellId ~= DISINTEGRATE then return end

        local _, _, _, startTimeMS, endTimeMS = UnitChannelInfo("player")
        local startTime = startTimeMS / 1000

        -- Hover mid-Disintegrate triggers another CHANNEL_START — deduplicate
        if startTime - self.lastStart < 0.5 then
            return
        end

        self.lastStart = startTime

        local cw = self.db.ClipWarning or {}

        if cw.Enabled and self.massDisintegrateStacks > 0 then
            local expired = GetTime() - self.lastGainedStack > STACK_EXPIRY
            if expired then
                self.massDisintegrateStacks = 0
            else
                self:ShowWarning()
                self.massDisintegrateStacks = self.massDisintegrateStacks - 1

                -- Update cast bar text to show Mass Disintegrate name
                local anchor = self.castBarInfo.anchor
                if anchor and anchor.Text then
                    anchor.Text:SetText(C_Spell.GetSpellName(MASS_DISINTEGRATE))
                end
            end
        else
            self:HideWarning()
        end

        -- Discover cast bar if we haven't yet
        if not self.castBarInfo.anchor then
            self:DiscoverCastBar()
        end

        local nextEndTime = endTimeMS / 1000
        local hastedTickInterval = self:GetTickInterval() / self:GetHaste()

        self.firstTick = 0

        if self.channeling and self.prevEndTime and self.prevHastedTickInterval then
            local remaining = self.prevEndTime - startTime
            -- modulo gives time to the next tick that would've fired, not just the last
            self.firstTick = math_max(0, math.fmod(remaining, self.prevHastedTickInterval))
        end

        self.prevEndTime = nextEndTime
        self.prevHastedTickInterval = hastedTickInterval
        self.chaining = self.channeling
        self.channeling = true

        self:UpdateTicks(self.castBarInfo.anchor, nextEndTime - startTime)

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        -- unit param captures spellId for non-unit events
        if not self.hasTipTheScalesActive and IsEmpower(unit) then
            self.hasTipTheScalesActive = true
        end

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if self.hasTipTheScalesActive and IsEmpower(unit) then
            self.hasTipTheScalesActive = false
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local _, spellId = ...
        if spellId ~= DISINTEGRATE then return end

        self:HideWarning()
        self:HideTicks()
        self.channeling = false
        self.chaining = false
    end
end

function DT:RegisterSpecEvents()
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "OnEvent")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "OnEvent")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnEvent")
    self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP", "OnEvent")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnEvent")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnEvent")
    self:RegisterEvent("PLAYER_DEAD", "OnEvent")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnEvent")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "OnEvent")
end

function DT:UnregisterSpecEvents()
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    self:UnregisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:UnregisterEvent("PLAYER_DEAD")
    self:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    self:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function DT:ApplySettings()
    self:ApplyTickColor()
    self:ApplyWarningSettings()
    self:UpdateWarningPosition()
end

function DT:ApplyPosition()
    if not self.db.Enabled then return end
    self:UpdateWarningPosition()
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function DT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "DisintegrateTicks",
            displayName = "Disintegrate Warning",
            frame = self.warningFrame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; self:UpdateWarningPosition() end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "DisintegrateTicks",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function DT:ShowPreview()
    self:CreateWarningFrame()
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()
    self.warningFrame:Show()

    -- Show warning text in preview
    self.warningText:Show()
    if self.warningText.softOutline then
        self.warningText.softOutline:SetShown((self.db.ClipWarning or {}).FontOutline == "SOFTOUTLINE")
    end

    -- Try to show ticks on the cast bar
    self:DiscoverCastBar()
    if self.castBarInfo.anchor then
        local w, h = self.castBarInfo.anchor:GetSize()
        self.castBarInfo.width = math_ceil(w)
        self.castBarInfo.height = math_ceil(h)
        local previewDuration = self.maxTicks * (self:GetTickInterval() / self:GetHaste())
        self:UpdateTicks(self.castBarInfo.anchor, previewDuration)
    end
end

function DT:HidePreview()
    self.isPreview = false
    self:HideWarning()
    self:HideTicks()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function DT:OnEnable()
    if not self.db.Enabled then return end

    -- Only Evokers
    if select(3, UnitClass("player")) ~= Constants.UICharacterClasses.Evoker then
        return
    end

    self:CreateWarningFrame()
    self:RegWithEditMode()
    self:ApplySettings()
    self:HideWarning()

    -- Event routing
    self:RegisterEvent("LOADING_SCREEN_DISABLED", "OnEvent")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnEvent")

    -- Install cast bar hooks once
    C_Timer.After(0.5, function()
        self:DiscoverCastBar()
        self:InstallCastBarHooks()
        self:ApplyPosition()
    end)

    -- Register spec events if valid spec
    if self:IsValidSpec() then
        self:RegisterSpecEvents()
        self:QueryTalentsAndHide()
    end
end

function DT:OnDisable()
    self:HideTicks()
    self:HideWarning()
    if self.warningFrame then
        self.warningFrame:Hide()
    end
    self.isPreview = false
    self.channeling = false
    self.chaining = false
    self.prevEndTime = nil
    self.prevHastedTickInterval = nil
    self.massDisintegrateStacks = 0
    self:UnregisterAllEvents()
end
