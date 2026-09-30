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

-- Button widgt
function GUIFrame:CreateButton(parent, labelText, config)
    local customHeight = nil
    -- Ensure config is a table
    if type(config) ~= "table" then
        config = {}
    end
    local label = labelText or "Button"
    local tooltip = config.tooltip
    local callback = config.callback
    local image = config.image
    local imageSize = config.imageSize or 16
    local explicitWidth = config.width
    local height = config.height or 24

    -- CREATE ROW CONTAINER
    local rowHeight = customHeight or 34
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(rowHeight)

    local button = CreateFrame("Button", nil, row, "BackdropTemplate")
    button:SetHeight(height)
    if config.height then
        button.explicitHeight = true
    end

    if explicitWidth then
        button:SetWidth(explicitWidth)
    else
        button:SetWidth(120)
    end


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
    PaintRest()

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

    local contentWidth = 0
    local iconWidget, textWidget

    if image then
        iconWidget = button:CreateTexture(nil, "ARTWORK")
        iconWidget:SetSize(imageSize, imageSize)
        iconWidget:SetTexture(image)
        contentWidth = contentWidth + imageSize
    end

    textWidget = button:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(textWidget, "normal")
    textWidget:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    textWidget:SetText(label)
    contentWidth = contentWidth + textWidget:GetStringWidth()

    if image and label and label ~= "" then
        contentWidth = contentWidth + 6
    end

    -- The label anchors to the icon when there is one, so only the lead
    -- element moves while the button is held down.
    local function PlaceContent(dy)
        if iconWidget then
            iconWidget:ClearAllPoints()
            iconWidget:SetPoint("LEFT", button, "CENTER", -contentWidth / 2, dy)
        else
            textWidget:ClearAllPoints()
            textWidget:SetPoint("CENTER", button, "CENTER", 0, dy)
        end
    end
    if iconWidget then
        textWidget:SetPoint("LEFT", iconWidget, "RIGHT", 6, 0)
    end
    PlaceContent(0)

    button:SetScript("OnEnter", function(self)
        AnimateBorderColor(true)
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
        PlaceContent(0)
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
        PlaceContent(-1)
    end)

    button:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton ~= "LeftButton" or not pressed then return end
        Release()
        if self:IsMouseOver() then
            local h = Theme.controlHover
            self:SetBackdropColor(h[1], h[2], h[3], h[4])
            self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        else
            AnimateBorderColor(false)
        end
    end)

    -- Pools reuse a hidden button without repainting it, so a press, hover or
    -- fade still in flight at hide time is dropped here.
    button:SetScript("OnHide", function()
        hoverAnimGroup:Stop()
        Release()
        PaintRest()
    end)

    button:SetScript("OnClick", function(self)
        callback()
    end)

    function button:SetLabel(newLabel)
        textWidget:SetText(newLabel)
    end

    function button:SetImage(newImage)
        if iconWidget then
            iconWidget:SetTexture(newImage)
        end
    end

    function button:SetEnabled(enabled)
        if enabled then
            button:Enable()
            button:SetAlpha(1)
            button:EnableMouse(true)
            if textWidget then
                textWidget:SetAlpha(1)
            end
            if iconWidget then
                iconWidget:SetAlpha(1)
            end
        else
            hoverAnimGroup:Stop()
            Release()
            PaintRest()
            button:Disable()
            button:SetAlpha(0.5)
            button:EnableMouse(false)
            if textWidget then
                textWidget:SetAlpha(0.5)
            end
            if iconWidget then
                iconWidget:SetAlpha(0.5)
            end
        end
    end

    -- Re-apply theme-tied state after KE:RefreshTheme replaces Theme color
    -- tables. Hover animation handlers read live values so they self-recover.
    -- Pool consumers call this when KE._themeVersion has advanced.
    function button:ApplyThemeColors()
        PaintRest()
        if textWidget then
            textWidget:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        end
    end

    button.icon = iconWidget
    button.text = textWidget
    return button
end
