-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KEColorPicker.lua                                   ║
-- ║  Purpose: Color picker widget with hex input.            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Localization Setup
local CreateFrame = CreateFrame
local ColorPickerFrame = ColorPickerFrame

local ANIMATION_DURATION = 0.18
local SWATCH_BG_TEXTURE = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnColorPickerBG.png"

---------------------------------------------------------------------------------
-- Widget Creation
---------------------------------------------------------------------------------

-- Builds one colour picker. Label, colour and bindings are applied by
-- ConfigureColorPicker, so a pooled picker can serve any setting.
local function ConstructColorPicker(parent)
    local row = CreateFrame("Frame", nil, parent)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
    label:SetJustifyH("LEFT")
    row.label = label

    -- Backdrop texture to easier see current alpha value
    local swatchBg = row:CreateTexture(nil, "BACKGROUND")
    swatchBg:SetSize(48, 24)
    swatchBg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    swatchBg:SetTexture(SWATCH_BG_TEXTURE)
    swatchBg:SetAlpha(0.8)
    swatchBg:SetTexelSnappingBias(0)
    swatchBg:SetSnapToPixelGrid(false)

    local swatch = CreateFrame("Button", nil, row, "BackdropTemplate")
    swatch:SetSize(48, 24)
    swatch:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    swatch:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    -- Hex code display
    local hexText = row:CreateFontString(nil, "OVERLAY")
    hexText:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    row.hexText = hexText

    local function SetSwatch(r, g, b, a)
        swatch.r, swatch.g, swatch.b, swatch.a = r, g, b, a or 1
        swatch:SetBackdropColor(r, g, b, a or 1)
        hexText:SetText("#" .. KE:RGBAToHex(r, g, b))
    end

    -- Hover fade animation for border color
    local hoverAnimGroup = swatch:CreateAnimationGroup()
    local hoverAnim = hoverAnimGroup:CreateAnimation("Animation")
    hoverAnim:SetDuration(ANIMATION_DURATION)

    local borderColorFrom = {}
    local borderColorTo = {}

    hoverAnimGroup:SetScript("OnUpdate", function(self)
        local progress = self:GetProgress() or 0
        local r = borderColorFrom.r + (borderColorTo.r - borderColorFrom.r) * progress
        local g = borderColorFrom.g + (borderColorTo.g - borderColorFrom.g) * progress
        local b = borderColorFrom.b + (borderColorTo.b - borderColorFrom.b) * progress
        swatch:SetBackdropBorderColor(r, g, b, 1)
    end)

    hoverAnimGroup:SetScript("OnFinished", function()
        swatch:SetBackdropBorderColor(borderColorTo.r, borderColorTo.g, borderColorTo.b, 1)
    end)

    local function AnimateBorderColor(toAccent)
        hoverAnimGroup:Stop()

        local currentR, currentG, currentB = swatch:GetBackdropBorderColor()
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

    swatch:SetScript("OnEnter", function(self)
        AnimateBorderColor(true)
        local tooltip = row._tooltip
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    swatch:SetScript("OnLeave", function(self)
        AnimateBorderColor(false)
        GameTooltip:Hide()
    end)

    ---------------------------------------------------------------------------------
    -- Color Logic
    ---------------------------------------------------------------------------------

    swatch:SetScript("OnClick", function()
        local prevR, prevG, prevB, prevA = swatch.r, swatch.g, swatch.b, swatch.a
        -- Bound for this one open: a rebuild while the picker is up must not
        -- send its colour to another setting, nor repaint a reused swatch.
        local callback, gen = row._callback, row._keGen
        local function Apply(r, g, b, a)
            if row._keGen == gen then SetSwatch(r, g, b, a) end
            if callback then callback(r, g, b, a or 1) end
        end
        local info = {
            r = prevR,
            g = prevG,
            b = prevB,
            opacity = prevA,
            hasOpacity = true
        }
        info.swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame:GetColorAlpha()
            Apply(r or 1, g or 1, b or 1, a or 1)
        end
        info.opacityFunc = info.swatchFunc
        info.cancelFunc = function()
            Apply(prevR, prevG, prevB, prevA)
        end
        row._openSwatchFunc = info.swatchFunc
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    -- Busy while Blizzard's picker is still open on this widget's colour: the
    -- pool retires it rather than hand an open edit to another setting.
    function row:_keIsBusy()
        local open = self._openSwatchFunc
        return open ~= nil and ColorPickerFrame:IsShown() and ColorPickerFrame.swatchFunc == open
    end

    function row:SetColor(r, g, b, a)
        SetSwatch(r, g, b, a)
        if row._callback then row._callback(r, g, b, a or 1) end
    end

    function row:GetColor() return swatch.r, swatch.g, swatch.b, swatch.a end

    function row:SetEnabled(enabled)
        if enabled then
            row:SetAlpha(1)
            swatch:EnableMouse(true)
        else
            row:SetAlpha(0.4)
            swatch:EnableMouse(false)
        end
    end

    row._setSwatch = SetSwatch
    row._hoverAnimGroup = hoverAnimGroup
    row.swatch = swatch

    -- Pool-friendly callback slot; SetColor reads late-bound.
    function row:SetCallback(fn)
        self._callback = fn
    end

    row._keOwned = { row, swatch }
    return row
end

-- ColorPicker widget — config-table API: { color = {r,g,b,a}, callback, tooltip }
local function ConfigureColorPicker(row, labelText, config)
    local color = config.color or { 1, 1, 1, 1 }
    local TT = Theme
    -- Every use: row:AddWidget sizes a widget to its row.
    row:SetHeight(34)
    local label = row.label
    KE:ApplyThemeFont(label, "small")
    label:SetText(labelText or "")
    label:SetTextColor(TT.textSecondary[1], TT.textSecondary[2], TT.textSecondary[3], 1)
    KE:ApplyThemeFont(row.hexText, "small")
    row.hexText:SetTextColor(TT.textSecondary[1], TT.textSecondary[2], TT.textSecondary[3], 1)
    -- After the font: ApplyThemeFont sets the theme's shadow.
    row.hexText:SetShadowColor(0, 0, 0, 0)
    row._tooltip = config.tooltip
    row._hoverAnimGroup:Stop()
    row._setSwatch(color[1], color[2], color[3], color[4] or 1)
    row.swatch:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], 1)
    row:SetEnabled(true)
    row._callback = config.callback
end

local colorPickerPool = GUIFrame:NewWidgetPool("colorpicker", ConstructColorPicker, function(row)
    row._hoverAnimGroup:Stop()
end)

function GUIFrame:CreateColorPicker(parent, labelText, config)
    config = config or {}
    local row
    if self:IsPoolParent(parent) then
        row = colorPickerPool:Acquire(parent)
    else
        row = ConstructColorPicker(parent)
    end
    ConfigureColorPicker(row, labelText, config)
    return row
end
