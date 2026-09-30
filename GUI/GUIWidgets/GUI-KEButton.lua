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

    local function PaintRest()
        local c, e = Theme.controlBg, Theme.controlBorder
        button:SetBackdropColor(c[1], c[2], c[3], c[4])
        button:SetBackdropBorderColor(e[1], e[2], e[3], 1)
    end

    local function PaintHover()
        local h = Theme.controlHover
        button:SetBackdropColor(h[1], h[2], h[3], h[4])
        button:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end

    -- Hover fade animation for border and plate color
    local hoverAnimGroup = button:CreateAnimationGroup()
    local hoverAnim = hoverAnimGroup:CreateAnimation("Animation")
    hoverAnim:SetDuration(0.15)

    local borderColorFrom = {}
    local borderColorTo = {}
    local plateFrom = {}
    local plateTo = {}

    hoverAnimGroup:SetScript("OnUpdate", function(self)
        local progress = self:GetProgress() or 0
        local r = borderColorFrom.r + (borderColorTo.r - borderColorFrom.r) * progress
        local g = borderColorFrom.g + (borderColorTo.g - borderColorFrom.g) * progress
        local b = borderColorFrom.b + (borderColorTo.b - borderColorFrom.b) * progress
        button:SetBackdropBorderColor(r, g, b, 1)
        button:SetBackdropColor(
            plateFrom.r + (plateTo.r - plateFrom.r) * progress,
            plateFrom.g + (plateTo.g - plateFrom.g) * progress,
            plateFrom.b + (plateTo.b - plateFrom.b) * progress, 1)
    end)

    hoverAnimGroup:SetScript("OnFinished", function()
        button:SetBackdropBorderColor(borderColorTo.r, borderColorTo.g, borderColorTo.b, 1)
        button:SetBackdropColor(plateTo.r, plateTo.g, plateTo.b, 1)
    end)

    local function AnimateBorderColor(toAccent)
        hoverAnimGroup:Stop()

        local currentR, currentG, currentB = button:GetBackdropBorderColor()
        borderColorFrom.r = currentR
        borderColorFrom.g = currentG
        borderColorFrom.b = currentB
        plateFrom.r, plateFrom.g, plateFrom.b = button:GetBackdropColor()
        local plate = toAccent and Theme.controlHover or Theme.controlBg
        plateTo.r, plateTo.g, plateTo.b = plate[1], plate[2], plate[3]

        if toAccent then
            borderColorTo.r = Theme.accent[1]
            borderColorTo.g = Theme.accent[2]
            borderColorTo.b = Theme.accent[3]
        else
            borderColorTo.r = Theme.controlBorder[1]
            borderColorTo.g = Theme.controlBorder[2]
            borderColorTo.b = Theme.controlBorder[3]
        end

        hoverAnimGroup:Play()
    end

    -- Built once and shown only while the caller passes an image.
    local iconWidget = button:CreateTexture(nil, "ARTWORK")
    iconWidget:Hide()
    local textWidget = button:CreateFontString(nil, "OVERLAY")
    -- Inside the border, under an image.
    local selectedFill = button:CreateTexture(nil, "ARTWORK", nil, -1)
    selectedFill:SetPoint("TOPLEFT", 1, -1)
    selectedFill:SetPoint("BOTTOMRIGHT", -1, 1)
    selectedFill:Hide()

    -- The label anchors to the icon when there is one, so only the lead
    -- element moves while the button is held down.
    function button:PlaceContent(dy)
        if self._hasImage then
            iconWidget:ClearAllPoints()
            iconWidget:SetPoint("LEFT", button, "CENTER", -(self._contentWidth or 0) / 2, dy)
        else
            textWidget:ClearAllPoints()
            textWidget:SetPoint("CENTER", button, "CENTER", 0, dy)
        end
    end

    button:SetScript("OnEnter", function(self)
        AnimateBorderColor(true)
        local tooltip = self._tooltip
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    local pressed = false

    local function Release()
        if not pressed then return end
        pressed = false
        button:PlaceContent(0)
    end

    local function ResetVisual()
        hoverAnimGroup:Stop()
        Release()
        PaintRest()
    end

    button:SetScript("OnLeave", function(self)
        Release()
        AnimateBorderColor(false)
        GameTooltip:Hide()
    end)

    button:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton ~= "LeftButton" or not self:IsEnabled() then return end
        hoverAnimGroup:Stop()
        pressed = true
        local p = Theme.controlPressed
        self:SetBackdropColor(p[1], p[2], p[3], p[4])
        self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        self:PlaceContent(-1)
    end)

    button:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton ~= "LeftButton" or not pressed then return end
        Release()
        if self:IsMouseOver() then
            PaintHover()
        else
            AnimateBorderColor(false)
        end
    end)

    -- A press, hover or fade still in flight when the button hides is dropped
    -- here, so a reused button starts at rest.
    button:SetScript("OnHide", ResetVisual)

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

    function button:SetSelected(selected)
        selectedFill:SetShown(selected)
    end

    function button:SetEnabled(enabled)
        if enabled then
            button:Enable()
            button:SetAlpha(1)
            button:EnableMouse(true)
            textWidget:SetAlpha(1)
            iconWidget:SetAlpha(1)
        else
            ResetVisual()
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
        -- A repaint while this button holds the pointer (a click whose
        -- callback changes the theme) keeps the hover look. Motion focus, not
        -- a rectangle test: a button rebuilt under the theme popup must rest.
        hoverAnimGroup:Stop()
        if button:IsEnabled() and button:IsVisible() and button:IsMouseMotionFocus() then
            PaintHover()
        else
            PaintRest()
        end
        local TT = Theme
        textWidget:SetTextColor(TT.accent[1], TT.accent[2], TT.accent[3], 1)
        selectedFill:SetColorTexture(TT.selectedBg[1], TT.selectedBg[2], TT.selectedBg[3], TT.selectedBg[4])
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
    button._contentWidth = contentWidth

    if image then
        textWidget:SetPoint("LEFT", iconWidget, "RIGHT", 6, 0)
    end
    button:PlaceContent(0)

    button:SetEnabled(true)
    button:SetSelected(false)
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
