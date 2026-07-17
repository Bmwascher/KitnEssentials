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
local BagsBar = BagsBar

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

local appliedHooks = {
    bags = false,
}

-- Bumped on every enter/leave; a pending fade-out only fires if it is still
-- the newest intent (prevents a stale timer fading the bar while the cursor
-- has re-entered).
local bagFadeGen = 0

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
                    bagFadeGen = bagFadeGen + 1
                    UIFrameFadeIn(BagsBar, self.db.FadeInDuration, BagsBar:GetAlpha(), 1.0)
                end
            end)
            child:HookScript("OnLeave", function()
                if self.db.Enabled and self.db.BagMouseover.Enabled then
                    bagFadeGen = bagFadeGen + 1
                    local gen = bagFadeGen
                    C_Timer.After(self.db.FadeOutDuration, function()
                        if gen ~= bagFadeGen then return end
                        if not self:IsEnabled() then return end
                        if not (self.db.Enabled and self.db.BagMouseover.Enabled) then return end
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
    bagFadeGen = bagFadeGen + 1
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
        if not self:IsEnabled() or not self.db.Enabled then return end
        self:SetupAllHooks()
        self:UpdateAllAlpha()
    end)
end

function SK:OnDisable()
    self:Reset()
    -- Invalidate pending fade-out timers; without this a timer queued before
    -- disable fires against the next enable cycle's state.
    bagFadeGen = bagFadeGen + 1
end
