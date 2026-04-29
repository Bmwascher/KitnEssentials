-- ╔══════════════════════════════════════════════════════════╗
-- ║  BlizzardMicroMenu.lua                                   ║
-- ║  Module: Micro Menu                                      ║
-- ║  Purpose: Micro menu bar appearance customization        ║
-- ║           with dark theme.                               ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local SK = KitnEssentials:NewModule("SkinBlizzardMicroMenu", "AceEvent-3.0")

local UIFrameFadeOut = UIFrameFadeOut
local UIFrameFadeIn = UIFrameFadeIn
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local ipairs = ipairs
local unpack = unpack
local _G = _G

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------

local microButtons = {
    "CharacterMicroButton",
    "SpellbookMicroButton",
    "TalentMicroButton",
    "AchievementMicroButton",
    "QuestLogMicroButton",
    "GuildMicroButton",
    "LFDMicroButton",
    "CollectionsMicroButton",
    "EJMicroButton",
    "StoreMicroButton",
    "MainMenuMicroButton",
    "HelpMicroButton",
    "ProfessionMicroButton",
    "PlayerSpellsMicroButton",
    "HousingMicroButton",
}

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

local hooksApplied = false
local microBar

---------------------------------------------------------------------------------
-- Styling Helpers
---------------------------------------------------------------------------------

-- Border helper lives in Core/Widgets.lua as KE:AddBorders. Call sites use it directly.

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.MicroMenu
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------

function SK:GetParentFrame()
    if not self.db.Enabled then return end
    local anchorType = self.db.anchorFrameType
    if anchorType == "SCREEN" or anchorType == "UIPARENT" then
        return UIParent
    else
        local parentName = self.db.ParentFrame
        return _G[parentName] or UIParent
    end
end

function SK:CreateMicroBarFrame()
    if microBar then return end
    microBar = CreateFrame("Frame", "KE_MicroBar", UIParent)
    microBar:SetSize(250, 40)
    SK:UpdatePosition()
    self.microBar = microBar
end

function SK:CreateMicroBar()
    if microBar.initialized then return end

    local backdrop = CreateFrame("Frame", nil, microBar, "BackdropTemplate")
    backdrop:SetFrameLevel(microBar:GetFrameLevel() - 1)
    backdrop:SetAllPoints(microBar)
    backdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    backdrop:SetBackdropColor(unpack(self.db.BackdropColor))
    microBar.backdrop = backdrop

    local borderFrame = CreateFrame("Frame", nil, backdrop)
    borderFrame:SetAllPoints(backdrop)
    borderFrame:SetFrameStrata("DIALOG")
    borderFrame:SetFrameLevel(microBar:GetFrameLevel() + 1)
    KE:AddBorders(backdrop, self.db.BackdropBorderColor, borderFrame)

    microBar.borderFrame = borderFrame
    microBar.initialized = true
end

function SK:ReparentButtons()
    if InCombatLockdown() then
        SK:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    for _, name in ipairs(microButtons) do
        local button = _G[name]
        if button then
            button:SetParent(microBar)
        end
    end
end

---------------------------------------------------------------------------------
-- Button Layout
---------------------------------------------------------------------------------

function SK:UpdateMicroBar()
    if not microBar then return end
    if InCombatLockdown() then
        SK:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local visibleButtons = {}

    for _, name in ipairs(microButtons) do
        local button = _G[name]
        if button and button:IsShown() then
            table.insert(visibleButtons, button)

            if button.Background then
                button.Background:SetTexture(nil)
                button.Background:Hide()
            end
            if button.PushedBackground then
                button.PushedBackground:SetTexture(nil)
                button.PushedBackground:Hide()
            end
        end
    end

    local numButtons = #visibleButtons
    if numButtons == 0 then
        microBar:SetSize(100, 40)
        return
    end

    local buttonPerRow = 15

    local cols = math.min(numButtons, buttonPerRow)
    local rows = math.ceil(numButtons / buttonPerRow)
    local width = (self.db.ButtonWidth * cols) + (self.db.ButtonSpacing * math.max(0, cols - 1)) +
        (self.db.BackdropSpacing * 2)
    local height = (self.db.ButtonHeight * rows) + (self.db.ButtonSpacing * math.max(0, rows - 1)) +
        (self.db.BackdropSpacing * 2)

    microBar:SetSize(width, height)

    for i, button in ipairs(visibleButtons) do
        button:ClearAllPoints()
        button:SetSize(self.db.ButtonWidth, self.db.ButtonHeight)
        local col = (i - 1) % buttonPerRow
        if i == 1 then
            button:SetPoint("TOPLEFT", microBar, "TOPLEFT", self.db.BackdropSpacing, -self.db.BackdropSpacing)
        elseif col == 0 then
            button:SetPoint("TOPLEFT", visibleButtons[i - buttonPerRow], "BOTTOMLEFT", 0, -self.db.ButtonSpacing)
        else
            button:SetPoint("LEFT", visibleButtons[i - 1], "RIGHT", self.db.ButtonSpacing, 0)
        end
    end

    -- Hide performance bar
    MainMenuMicroButton.MainMenuBarPerformanceBar:SetAlpha(0)
    MainMenuMicroButton.MainMenuBarPerformanceBar:SetScale(0.0001)

    if microBar and microBar.backdrop then
        microBar.backdrop:SetShown(self.db.ShowBackdrop ~= false)
        local bgr, bgg, bgb, bga = KE:ResolveColor(self.db.BackdropColor, { 0, 0, 0, 0.8 })
        microBar.backdrop:SetBackdropColor(bgr, bgg, bgb, bga)

        local bdr, bdg, bdb, bda = KE:ResolveColor(self.db.BackdropBorderColor, { 0, 0, 0, 1 })
        microBar.backdrop:SetBorderColor(bdr, bdg, bdb, bda)
    end

    SK:UpdateAlpha()
    SK:UpdatePosition()
end

function SK:UpdatePosition()
    if not microBar then return end
    microBar:ClearAllPoints()
    local pos = self.db.Position
    local parent = SK:GetParentFrame()
    microBar:SetPoint(
        pos.AnchorFrom or "CENTER",
        parent,
        pos.AnchorTo or "CENTER",
        pos.XOffset or 0,
        pos.YOffset or 0
    )
    microBar:SetFrameStrata(self.db.Strata or "HIGH")
end

function SK:UpdateAlpha()
    if not microBar then return end
    if not self.db.Mouseover.Enabled then
        microBar:SetAlpha(1.0)
    else
        microBar:SetAlpha(microBar.IsMouseOvered and 1.0 or self.db.Mouseover.Alpha)
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------

function SK:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    SK:UpdatePosition()
    SK:UpdateMicroBar()
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------

-- Mouseover polling handler
local watcher = 0
local function OnUpdate(self, elapsed)
    if watcher > 0.1 then
        if not self:IsMouseOver() then
            self.IsMouseOvered = nil
            self:SetScript("OnUpdate", nil)
            if SK.db.Mouseover.Enabled then
                UIFrameFadeOut(microBar, SK.db.Mouseover.FadeOutDuration, microBar:GetAlpha(), SK.db.Mouseover.Alpha)
            end
        end
        watcher = 0
    else
        watcher = watcher + elapsed
    end
end

local function OnEnter()
    if SK.db.Mouseover.Enabled and not microBar.IsMouseOvered then
        microBar.IsMouseOvered = true
        microBar:SetScript("OnUpdate", OnUpdate)
        UIFrameFadeIn(microBar, SK.db.Mouseover.FadeInDuration, microBar:GetAlpha(), 1.0)
    end
end

function SK:SetupMouseover()
    if hooksApplied then return end
    if not self.db.Mouseover.Enabled then return end
    for _, name in ipairs(microButtons) do
        local button = _G[name]
        if button then
            button:HookScript("OnEnter", OnEnter)
        end
    end
    hooksApplied = true
end

function SK:PLAYER_REGEN_ENABLED()
    SK:UnregisterEvent("PLAYER_REGEN_ENABLED")
    SK:ReparentButtons()
    SK:UpdateMicroBar()
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
        SK:CreateMicroBarFrame()
        SK:CreateMicroBar()
        SK:ReparentButtons()
        SK:SetupMouseover()
        SK:UpdateMicroBar()

        local config = {
            key = "MicroBarModule",
            displayName = "Microbar",
            frame = self.microBar,
            getPosition = function()
                return self.db.Position
            end,
            setPosition = function(pos)
                self.db.Position.AnchorFrom = pos.AnchorFrom
                self.db.Position.AnchorTo = pos.AnchorTo
                self.db.Position.XOffset = pos.XOffset
                self.db.Position.YOffset = pos.YOffset

                local parent = SK:GetParentFrame()
                self.microBar:ClearAllPoints()
                self.microBar:SetPoint(pos.AnchorFrom, parent, pos.AnchorTo, pos.XOffset, pos.YOffset)
            end,
            getParentFrame = function()
                return SK:GetParentFrame()
            end,
            guiPath = "SkinMicroMenu",
        }
        KE.EditMode:RegisterElement(config)
    end)
end

function SK:OnDisable()
    if microBar then
        microBar:Hide()
        microBar:SetAlpha(1.0)
        microBar.IsMouseOvered = nil
        microBar:SetScript("OnUpdate", nil)
    end
    if not InCombatLockdown() then
        for _, name in ipairs(microButtons) do
            local button = _G[name]
            if button then
                button:SetParent(UIParent)
            end
        end
    end
    hooksApplied = false
end
