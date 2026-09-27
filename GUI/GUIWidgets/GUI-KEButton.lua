-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KEButton.lua                                        ║
-- ║  Purpose: Custom button widget for the settings panel.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Localization Setup
local CreateFrame = CreateFrame
local type = type

---------------------------------------------------------------------------------
-- Widget Creation
---------------------------------------------------------------------------------

-- Builds one button, parented straight to the caller's frame: a wrapping
-- container is never returned to the caller, so parenting through one would
-- just leave an empty frame behind on every call.
-- Label, image, size and bindings are applied by ConfigureButton.
local function ConstructButton(parent)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    -- Hover fade animation for border color
    local hoverAnimGroup = button:CreateAnimationGroup()
    local hoverAnim = hoverAnimGroup:CreateAnimation("Animation")
    hoverAnim:SetDuration(0.15)

    local borderColorFrom = {}
    local borderColorTo = {}

    hoverAnimGroup:SetScript("OnUpdate", function(self)
        local progress = self:GetProgress() or 0
        local r = borderColorFrom.r + (borderColorTo.r - borderColorFrom.r) * progress
        local g = borderColorFrom.g + (borderColorTo.g - borderColorFrom.g) * progress
        local b = borderColorFrom.b + (borderColorTo.b - borderColorFrom.b) * progress
        button:SetBackdropBorderColor(r, g, b, 1)
    end)

    hoverAnimGroup:SetScript("OnFinished", function()
        button:SetBackdropBorderColor(borderColorTo.r, borderColorTo.g, borderColorTo.b, 1)
    end)

    local function AnimateBorderColor(toAccent)
        hoverAnimGroup:Stop()

        local currentR, currentG, currentB = button:GetBackdropBorderColor()
        borderColorFrom.r = currentR
        borderColorFrom.g = currentG
        borderColorFrom.b = currentB

        if toAccent then
            borderColorTo.r = Theme.accent[1]
            borderColorTo.g = Theme.accent[2]
            borderColorTo.b = Theme.accent[3]
        else
            borderColorTo.r = Theme.border[1]
            borderColorTo.g = Theme.border[2]
            borderColorTo.b = Theme.border[3]
        end

        hoverAnimGroup:Play()
    end

    -- Built once and shown only while the caller passes an image.
    local iconWidget = button:CreateTexture(nil, "ARTWORK")
    iconWidget:Hide()
    local textWidget = button:CreateFontString(nil, "OVERLAY")

    button:SetScript("OnEnter", function(self)
        AnimateBorderColor(true)
        local tooltip = self._tooltip
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function(self)
        AnimateBorderColor(false)
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        self._callback()
    end)

    function button:SetLabel(newLabel)
        textWidget:SetText(newLabel)
    end

    function button:SetImage(newImage)
        if self._hasImage then
            iconWidget:SetTexture(newImage)
        end
    end

    function button:SetEnabled(enabled)
        if enabled then
            button:Enable()
            button:SetAlpha(1)
            button:EnableMouse(true)
            textWidget:SetAlpha(1)
            iconWidget:SetAlpha(1)
        else
            button:Disable()
            button:SetAlpha(0.5)
            button:EnableMouse(false)
            textWidget:SetAlpha(0.5)
            iconWidget:SetAlpha(0.5)
        end
    end

    -- Re-apply theme-tied state after KE:RefreshTheme replaces Theme color
    -- tables. Hover animation handlers read live values so they self-recover.
    -- Every configure calls this.
    function button:ApplyThemeColors()
        local TT = Theme
        button:SetBackdropColor(TT.bgButton[1], TT.bgButton[2], TT.bgButton[3], TT.bgButton[4])
        button:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], 1)
        textWidget:SetTextColor(TT.accent[1], TT.accent[2], TT.accent[3], 1)
    end

    button._iconWidget = iconWidget
    button._hoverAnimGroup = hoverAnimGroup
    button.text = textWidget
    button._keOwned = { button }
    return button
end

local function ConfigureButton(button, labelText, config)
    local label = labelText or "Button"
    local image = config.image
    local imageSize = config.imageSize or 16

    button:SetWidth(config.width or 120)
    button:SetHeight(config.height or 24)
    if config.height then
        button.explicitHeight = true
    end
    button._tooltip = config.tooltip
    button._callback = config.callback
    button._hasImage = image ~= nil

    local iconWidget, textWidget = button._iconWidget, button.text
    iconWidget:ClearAllPoints()
    textWidget:ClearAllPoints()

    local contentWidth = 0
    if image then
        iconWidget:SetSize(imageSize, imageSize)
        iconWidget:SetTexture(image)
        iconWidget:Show()
        contentWidth = contentWidth + imageSize
        button.icon = iconWidget
    else
        iconWidget:Hide()
    end

    KE:ApplyThemeFont(textWidget, "normal")
    textWidget:SetText(label)
    contentWidth = contentWidth + textWidget:GetStringWidth()

    if image and label ~= "" then
        contentWidth = contentWidth + 6
    end

    if image then
        iconWidget:SetPoint("LEFT", button, "CENTER", -contentWidth / 2, 0)
        textWidget:SetPoint("LEFT", iconWidget, "RIGHT", 6, 0)
    else
        textWidget:SetPoint("CENTER")
    end

    button:SetEnabled(true)
    button:ApplyThemeColors()
end

local buttonPool = GUIFrame:NewWidgetPool("button", ConstructButton, function(button)
    button._hoverAnimGroup:Stop()
end)

function GUIFrame:CreateButton(parent, labelText, config)
    if type(config) ~= "table" then
        config = {}
    end
    local button
    if self:IsPoolParent(parent) then
        button = buttonPool:Acquire(parent)
    else
        button = ConstructButton(parent)
    end
    ConfigureButton(button, labelText, config)
    return button
end
