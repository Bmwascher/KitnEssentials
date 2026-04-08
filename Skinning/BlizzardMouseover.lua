-- ╔══════════════════════════════════════════════════════════╗
-- ║  BlizzardMouseover.lua                                   ║
-- ║  Module: Blizzard Mouseover                              ║
-- ║  Purpose: Highlight and tooltip behavior tweaks          ║
-- ║           for Blizzard frames.                           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local SK = KitnEssentials:NewModule("SkinBlizzardMouseover", "AceEvent-3.0")

local UIFrameFadeOut = UIFrameFadeOut
local UIFrameFadeIn = UIFrameFadeIn
local ipairs = ipairs
local pairs = pairs
local BagsBar = BagsBar

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

local appliedHooks = {
    bags = false,
}

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.Mouseover
end

---------------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------------

function SK:SetupAllHooks()
    self:SetupBagHooks()
end

function SK:SetupBagHooks()
    if appliedHooks.bags or not BagsBar then return end
    if not self.db.BagMouseover.Enabled then return end

    for _, child in ipairs({ BagsBar:GetChildren() }) do
        if child:IsObjectType("Button") then
            child:HookScript("OnEnter", function()
                if self.db.Enabled and self.db.BagMouseover.Enabled then
                    UIFrameFadeIn(BagsBar, self.db.FadeInDuration, BagsBar:GetAlpha(), 1.0)
                end
            end)
            child:HookScript("OnLeave", function()
                if self.db.Enabled and self.db.BagMouseover.Enabled then
                    C_Timer.After(self.db.FadeOutDuration, function()
                        UIFrameFadeOut(BagsBar, self.db.FadeOutDuration, BagsBar:GetAlpha(), self.db.Alpha)
                    end)
                end
            end)
        end
    end
    appliedHooks.bags = true
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------

function SK:UpdateAllAlpha()
    self:UpdateBagAlpha()
end

function SK:UpdateBagAlpha()
    if not BagsBar then return end
    if not self.db.Enabled or not self.db.BagMouseover.Enabled then
        BagsBar:SetAlpha(1.0)
    else
        BagsBar:SetAlpha(self.db.Alpha)
    end
end

function SK:ToggleElement(elementName, enabled)
    if elementName == "bags" then
        self.db.BagMouseover.Enabled = enabled
        if enabled and not appliedHooks.bags then
            self:SetupBagHooks()
        end
        self:UpdateBagAlpha()
    end
end

function SK:Reset()
    if BagsBar then BagsBar:SetAlpha(1.0) end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------

function SK:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    if self.db.Enabled then
        self:UpdateAllAlpha()
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
    C_Timer.After(0.5, function()
        self:SetupAllHooks()
        self:UpdateAllAlpha()
    end)
end

function SK:OnDisable()
    self:Reset()
    for key in pairs(appliedHooks) do
        appliedHooks[key] = false
    end
end
