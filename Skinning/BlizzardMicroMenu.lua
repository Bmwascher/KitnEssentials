-- KitnEssentials namespace
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

-- MicroMenu buttons
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

-- Track if hooks are applied
local hooksApplied = false

-- Custom microBar reference
local microBar

-- 1px pixel-perfect border helper (same pattern as ActionBars)
local function AddBorders(frame, color, borderParent)
    if not frame then return end
    color = color or { 0, 0, 0, 1 }
    borderParent = borderParent or frame

    frame.borders = frame.borders or {}

    local function CreateBorder(point1, point2, width, height)
        local tex = borderParent:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(unpack(color))
        tex:SetTexelSnappingBias(0)
        tex:SetSnapToPixelGrid(false)
        if width then
            tex:SetWidth(width)
            tex:SetPoint("TOPLEFT", frame, point1, 0, 0)
            tex:SetPoint("BOTTOMLEFT", frame, point2, 0, 0)
        else
            tex:SetHeight(height)
            tex:SetPoint("TOPLEFT", frame, point1, 0, 0)
            tex:SetPoint("TOPRIGHT", frame, point2, 0, 0)
        end
        return tex
    end

    frame.borders.top = CreateBorder("TOPLEFT", "TOPRIGHT", nil, 1)

    frame.borders.bottom = borderParent:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.borders.bottom:SetHeight(1)
    frame.borders.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.borders.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.borders.bottom:SetColorTexture(unpack(color))
    frame.borders.bottom:SetTexelSnappingBias(0)
    frame.borders.bottom:SetSnapToPixelGrid(false)

    frame.borders.left = CreateBorder("TOPLEFT", "BOTTOMLEFT", 1, nil)

    frame.borders.right = borderParent:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.borders.right:SetWidth(1)
    frame.borders.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.borders.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.borders.right:SetColorTexture(unpack(color))
    frame.borders.right:SetTexelSnappingBias(0)
    frame.borders.right:SetSnapToPixelGrid(false)

    function frame:SetBorderColor(r, g, b, a)
        if not self.borders then return end
        for _, tex in pairs(self.borders) do
            tex:SetColorTexture(r, g, b, a or 1)
        end
    end

    return frame
end

-- Update db, used for profile changes
function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.MicroMenu
end

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

-- Get parent frame based on anchor type
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

-- Create the custom microBar frame
function SK:CreateMicroBarFrame()
    if microBar then return end
    microBar = CreateFrame("Frame", "KE_MicroBar", UIParent)
    microBar:SetSize(250, 40)
    SK:UpdatePosition()
    self.microBar = microBar
end

-- Create backdrop and borders on the microBar
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
    AddBorders(backdrop, self.db.BackdropBorderColor, borderFrame)

    microBar.borderFrame = borderFrame
    microBar.initialized = true
end

-- Reparent all micro buttons to custom frame
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

-- Update microbar layout and styling
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

            -- Strip Blizzard textures
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

    -- Calculate dimensions
    local cols = math.min(numButtons, buttonPerRow)
    local rows = math.ceil(numButtons / buttonPerRow)
    local width = (self.db.ButtonWidth * cols) + (self.db.ButtonSpacing * math.max(0, cols - 1)) +
        (self.db.BackdropSpacing * 2)
    local height = (self.db.ButtonHeight * rows) + (self.db.ButtonSpacing * math.max(0, rows - 1)) +
        (self.db.BackdropSpacing * 2)

    microBar:SetSize(width, height)

    -- Position buttons
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

    -- Update backdrop
    if microBar and microBar.backdrop then
        microBar.backdrop:SetShown(self.db.ShowBackdrop ~= false)
        microBar.backdrop:SetBackdropColor(unpack(self.db.BackdropColor))

        local borderColor = self.db.BackdropBorderColor
        microBar.backdrop:SetBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    end

    SK:UpdateAlpha()
    SK:UpdatePosition()
end

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

-- Mouseover onEnter
local function OnEnter()
    if SK.db.Mouseover.Enabled and not microBar.IsMouseOvered then
        microBar.IsMouseOvered = true
        microBar:SetScript("OnUpdate", OnUpdate)
        UIFrameFadeIn(microBar, SK.db.Mouseover.FadeInDuration, microBar:GetAlpha(), 1.0)
    end
end

-- Setup mouseover hooks
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

-- Update position
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

-- Update alpha based on mouseover state
function SK:UpdateAlpha()
    if not microBar then return end
    if not self.db.Mouseover.Enabled then
        microBar:SetAlpha(1.0)
    else
        microBar:SetAlpha(microBar.IsMouseOvered and 1.0 or self.db.Mouseover.Alpha)
    end
end

-- Apply all settings
function SK:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    SK:UpdatePosition()
    SK:UpdateMicroBar()
end

-- Handle combat lockdown
function SK:PLAYER_REGEN_ENABLED()
    SK:UnregisterEvent("PLAYER_REGEN_ENABLED")
    SK:ReparentButtons()
    SK:UpdateMicroBar()
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
