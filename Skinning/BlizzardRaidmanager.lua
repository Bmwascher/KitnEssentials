-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Create module
---@class SkinBlizzardRaidmanager: AceModule, AceEvent-3.0
local SK = KitnEssentials:NewModule("SkinBlizzardRaidmanager", "AceEvent-3.0")

-- Localization
local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local MouseIsOver = MouseIsOver


-- Update db
function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.RaidManager
end

-- Module init
function SK:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- Fade in function
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

-- Fade out function
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

-- Apply Y position
function SK:ApplyPosition()
    local point, relTo, relPoint, x = CompactRaidFrameManager:GetPoint()
    if point then
        CompactRaidFrameManager:ClearAllPoints()
        CompactRaidFrameManager:SetPoint(point, relTo, relPoint, x, self.db.Position.YOffset)
    end
end

-- Setup styling and hooks
function SK:SetupRaidManager()
    if not CompactRaidFrameManager or SK._raidManagerHooked then return end

    -- Apply Strata
    CompactRaidFrameManager:SetFrameStrata(self.db.Strata)

    -- Hook fade updates
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

-- Module OnEnable
function SK:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    C_Timer.After(1, function()
        self:ApplySettings()
    end)
end

-- Module OnDisable
function SK:OnDisable()
    if CompactRaidFrameManager then
        CompactRaidFrameManager:SetAlpha(1)
        CompactRaidFrameManager._isMouseOver = nil
        CompactRaidFrameManager:SetFrameStrata("HIGH")
    end
end
