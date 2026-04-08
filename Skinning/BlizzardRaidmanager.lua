-- ╔══════════════════════════════════════════════════════════╗
-- ║  BlizzardRaidmanager.lua                                 ║
-- ║  Module: Raid Manager Panel                              ║
-- ║  Purpose: Raid manager panel appearance with dark        ║
-- ║           theme styling.                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class SkinBlizzardRaidmanager: AceModule, AceEvent-3.0
local SK = KitnEssentials:NewModule("SkinBlizzardRaidmanager", "AceEvent-3.0")

local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local MouseIsOver = MouseIsOver

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.RaidManager
end

---------------------------------------------------------------------------------
-- Fade Logic
---------------------------------------------------------------------------------

local function FadeIn()
    if not SK:IsEnabled() then return end
    if CompactRaidFrameManager._isMouseOver then return end
    CompactRaidFrameManager._isMouseOver = true
    local dur = SK.db.FadeInDuration
    if InCombatLockdown() then
        dur = 0.1
    end
    KE:CombatSafeFade(CompactRaidFrameManager, 1, dur)
end

local function FadeOut()
    if not SK:IsEnabled() then return end
    if not CompactRaidFrameManager._isMouseOver then return end
    CompactRaidFrameManager._isMouseOver = false

    if not SK.db.FadeOnMouseOut then
        CompactRaidFrameManager:SetAlpha(1)
        return
    end

    KE:CombatSafeFade(CompactRaidFrameManager, SK.db.Alpha, SK.db.FadeOutDuration)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------

function SK:ApplyPosition()
    local point, relTo, relPoint, x = CompactRaidFrameManager:GetPoint()
    if point then
        CompactRaidFrameManager:ClearAllPoints()
        CompactRaidFrameManager:SetPoint(point, relTo, relPoint, x, self.db.Position.YOffset)
    end
end

function SK:SetupRaidManager()
    if not CompactRaidFrameManager or SK._raidManagerHooked then return end

    CompactRaidFrameManager:SetFrameStrata(self.db.Strata)

    if not SK._raidManagerHooked then
        CompactRaidFrameManager:HookScript("OnEnter", function()
            FadeIn()
        end)

        CompactRaidFrameManager:HookScript("OnLeave", function()
            if not MouseIsOver(CompactRaidFrameManager) then
                FadeOut()
            end
        end)

        hooksecurefunc("CompactRaidFrameManager_Toggle", function()
            if not SK:IsEnabled() then return end
            SK:ApplyPosition()
            if MouseIsOver(CompactRaidFrameManager) then
                FadeIn()
            else
                C_Timer.After(0.1, function()
                    if not MouseIsOver(CompactRaidFrameManager) then
                        FadeOut()
                    end
                end)
            end
        end)

        SK._raidManagerHooked = true
    end

    -- Initial state: fade out if mouse isn't over
    if not MouseIsOver(CompactRaidFrameManager) then
        CompactRaidFrameManager:SetAlpha(self.db.Alpha)
        CompactRaidFrameManager._isMouseOver = false
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------

function SK:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    self:SetupRaidManager()
    self:ApplyPosition()
    if CompactRaidFrameManager then
        if self.db.FadeOnMouseOut then
            CompactRaidFrameManager:SetAlpha(self.db.Alpha)
        else
            CompactRaidFrameManager:SetAlpha(1)
        end
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function SK:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function SK:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    C_Timer.After(1, function()
        self:ApplySettings()
    end)
end

function SK:OnDisable()
    if CompactRaidFrameManager then
        CompactRaidFrameManager:SetAlpha(1)
        CompactRaidFrameManager._isMouseOver = nil
        CompactRaidFrameManager:SetFrameStrata("HIGH")
    end
end
