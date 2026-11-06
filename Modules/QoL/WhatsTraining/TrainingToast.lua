-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrainingToast.lua                                       ║
-- ║  Purpose: The level-up toast: what the new level costs,  ║
-- ║           with a button that opens the panel.            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local T = KE.Training or {}
KE.Training = T

local Rules = KE.TrainingRules

local C_Spell, C_Timer = C_Spell, C_Timer
local CreateFrame = CreateFrame
local UIParent = UIParent
local min = math.min

local Toast = {}
T.Toast = Toast

local WIDTH, HEIGHT, PAD = 440, 130, 10
local ICON_SIZE, ICON_GAP, MAX_ICONS = 24, 4, 10
local BUTTON_WIDTH, BUTTON_HEIGHT = 120, 22
local HOLD_SECONDS = 20
local FALLBACK_ICON = 134400
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
local PLACEMENT = { anchorFrameType = "UIPARENT", Strata = "DIALOG" }

local frame
local icons = {}
local generation = 0
local dragging, expired = false, false

function Toast.Hide()
    generation = generation + 1
    expired = false
    if frame then frame:Hide() end
end

local function SavePosition(self)
    local point, _, relativePoint, x, y = self:GetPoint(1)
    local position = T.db.ToastPosition
    position.AnchorFrom, position.AnchorTo, position.XOffset, position.YOffset = point, relativePoint, x, y
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "KitnEssentialsTrainingToast", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0.031, 0.031, 0.031, 0.98)
    frame:SetScript("OnDragStart", function(self)
        dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        dragging = false
        self:StopMovingOrSizing()
        SavePosition(self)
        if expired then Toast.Hide() end
    end)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(frame.title, "large")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
    frame.line = frame:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(frame.line, "normal")
    frame.line:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
    frame.line:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    frame.line:SetJustifyH("LEFT")
    frame.line:SetJustifyV("TOP")

    local MakeButton = T.Panel.MakeButton
    frame.planner = MakeButton(frame, "Open Planner", BUTTON_WIDTH, BUTTON_HEIGHT, function()
        Toast.Hide()
        T.Panel.Open()
    end)
    frame.planner:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
    frame.dismiss = MakeButton(frame, "Dismiss", BUTTON_WIDTH, BUTTON_HEIGHT, function()
        Toast.Hide()
    end)
    frame.dismiss:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
end

local function DrawIcons(rows)
    local shown = min(#rows, MAX_ICONS)
    for index = 1, shown do
        local icon = icons[index]
        if not icon then
            icon = frame:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ICON_SIZE, ICON_SIZE)
            icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",
                PAD + (index - 1) * (ICON_SIZE + ICON_GAP), PAD + BUTTON_HEIGHT + 8)
            icons[index] = icon
        end
        icon:SetTexture(C_Spell.GetSpellTexture(rows[index].id) or FALLBACK_ICON)
        icon:Show()
    end
    for index = shown + 1, #icons do icons[index]:Hide() end
end

function Toast.Show(level)
    local plan = T.plan
    if not plan then return end
    Build()
    local accent = KE.Theme.accent
    frame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    frame.title:SetText("Level " .. level)
    frame.line:SetText(Rules.ToastLine(plan, plan.gold, T.Coins))
    DrawIcons(plan.now.rows)
    if not dragging then
        KE:ApplyFramePosition(frame, T.db.ToastPosition, PLACEMENT, false)
    end
    frame:Show()
    generation = generation + 1
    expired = false
    local mine = generation
    C_Timer.After(HOLD_SECONDS, function()
        if mine ~= generation then return end
        if dragging then
            expired = true
        else
            Toast.Hide()
        end
    end)
end
