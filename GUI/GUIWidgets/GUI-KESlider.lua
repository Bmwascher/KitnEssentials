-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KESlider.lua                                        ║
-- ║  Purpose: Slider widget with numeric input.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Localization Setup
local tonumber = tonumber
local tostring = tostring
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local math_floor, math_max, math_min = math.floor, math.max, math.min
local GetTime = GetTime

local STEPPER_TEXTURE = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.png"
local STEPPER_SIZE = 20
local THROTTLE_DELAY = 0.1 -- 100ms between updates

---------------------------------------------------------------------------------
-- Widget Creation
---------------------------------------------------------------------------------

-- Builds one slider. Range, step, value, label and bindings are applied by
-- ConfigureSlider, so a pooled slider can serve any setting.
local function ConstructSlider(parent)
    -- Row
    local row = CreateFrame("Frame", nil, parent)

    -- Label
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
    label:SetJustifyH("LEFT")
    row.label = label

    local sliderBG = CreateFrame("Frame", nil, row, "BackdropTemplate")
    sliderBG:SetHeight(8)
    sliderBG:SetPoint("TOPLEFT", row, "TOPLEFT", 68, -22)
    sliderBG:SetPoint("TOPRIGHT", row, "TOPRIGHT", -18, -22)
    sliderBG:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    sliderBG:EnableMouse(false)

    -- Slider
    local slider = CreateFrame("Slider", nil, row, "BackdropTemplate")
    slider:SetHeight(8)
    slider:SetPoint("TOPLEFT", row, "TOPLEFT", 77, -22)
    slider:SetPoint("TOPRIGHT", row, "TOPRIGHT", -27, -22) -- Make room for steppers + editbox
    slider:SetOrientation("HORIZONTAL")
    slider:SetObeyStepOnDrag(true)
    slider:SetHitRectInsets(-9, -9, -5, -5)

    -- Slider styling
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    slider:SetBackdropColor(0, 0, 0, 0)
    slider:SetBackdropBorderColor(0, 0, 0, 0)

    -- Fill texture
    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(6)
    fill:SetPoint("LEFT", sliderBG, "LEFT", 1, 0)
    fill:SetTexelSnappingBias(0)
    fill:SetSnapToPixelGrid(false)

    -- Thumb background frame (solid background layer)
    local thumbFrameBG = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    thumbFrameBG:SetSize(19, 12)
    thumbFrameBG:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    thumbFrameBG:SetBackdropBorderColor(0, 0, 0, 1)

    -- Thumb container frame (animated color layer)
    local thumbFrame = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    thumbFrame:SetSize(19, 12)
    thumbFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    thumbFrame:SetBackdropBorderColor(0, 0, 0, 1) -- Black border

    -- Use a transparent texture for the actual thumb
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(0, 0, 0, 0) -- Fully transparent
    slider:SetThumbTexture(thumb)

    -- Anchored once: both frames follow the thumb texture as the slider
    -- moves it.
    thumbFrameBG:SetPoint("CENTER", thumb, "CENTER", 0, 0)
    thumbFrame:SetPoint("CENTER", thumb, "CENTER", 0, 0)

    -- Hover fade animation for thumb color
    local hoverAnimGroup = slider:CreateAnimationGroup()
    local hoverAnim = hoverAnimGroup:CreateAnimation("Animation")
    hoverAnim:SetDuration(0.18)

    local borderColorFrom = {}
    local borderColorTo = {}

    -- Track current thumb color (including alpha)
    local thumbR, thumbG, thumbB, thumbA = Theme.thumbRest[1], Theme.thumbRest[2], Theme.thumbRest[3], 1

    local function AnimateThumbColor(toHover, toDrag)
        hoverAnimGroup:Stop()

        -- Use tracked color
        borderColorFrom.r = thumbR
        borderColorFrom.g = thumbG
        borderColorFrom.b = thumbB
        borderColorFrom.a = thumbA

        if toDrag then
            -- Dragging = accent color with alpha 1
            borderColorTo.r = Theme.accent[1]
            borderColorTo.g = Theme.accent[2]
            borderColorTo.b = Theme.accent[3]
            borderColorTo.a = 1
        elseif toHover then
            borderColorTo.r = Theme.thumbHover[1]
            borderColorTo.g = Theme.thumbHover[2]
            borderColorTo.b = Theme.thumbHover[3]
            borderColorTo.a = 1
        else
            borderColorTo.r = Theme.thumbRest[1]
            borderColorTo.g = Theme.thumbRest[2]
            borderColorTo.b = Theme.thumbRest[3]
            borderColorTo.a = 1
        end

        hoverAnimGroup:Play()
    end

    hoverAnimGroup:SetScript("OnUpdate", function(self)
        local progress = self:GetProgress() or 0
        local r = borderColorFrom.r + (borderColorTo.r - borderColorFrom.r) * progress
        local g = borderColorFrom.g + (borderColorTo.g - borderColorFrom.g) * progress
        local b = borderColorFrom.b + (borderColorTo.b - borderColorFrom.b) * progress
        local a = borderColorFrom.a + (borderColorTo.a - borderColorFrom.a) * progress
        thumbFrame:SetBackdropColor(r, g, b, a)
        -- Update tracked color
        thumbR, thumbG, thumbB, thumbA = r, g, b, a
    end)

    hoverAnimGroup:SetScript("OnFinished", function()
        thumbFrame:SetBackdropColor(borderColorTo.r, borderColorTo.g, borderColorTo.b, borderColorTo.a)
        -- Update tracked color to final value
        thumbR, thumbG, thumbB, thumbA = borderColorTo.r, borderColorTo.g, borderColorTo.b, borderColorTo.a
    end)

    local lastUpdate = 0
    -- Set when the throttle drops a change. Without the flush, the last step of
    -- a fast drag, click run or typed value never reaches the callback, and the
    -- db keeps the value before it.
    local dropped = false
    local function FlushDropped()
        if not dropped or not row._callback then return end
        dropped = false
        lastUpdate = GetTime()
        row._callback(slider:GetValue())
    end

    -- Left stepper (decrement) - arrow points left (rotated 90 clockwise)
    local leftStepper = CreateFrame("Button", nil, row)
    leftStepper:SetSize(STEPPER_SIZE, STEPPER_SIZE)
    leftStepper:SetPoint("RIGHT", sliderBG, "LEFT", 0, 0)

    -- Left arrow icon
    local leftIcon = leftStepper:CreateTexture(nil, "ARTWORK")
    leftIcon:SetAllPoints()
    leftIcon:SetTexture(STEPPER_TEXTURE)
    leftIcon:SetRotation(math.rad(-90)) -- Rotate to point left
    leftIcon:SetTexelSnappingBias(0)
    leftIcon:SetSnapToPixelGrid(false)
    leftStepper.icon = leftIcon

    -- Click handler
    leftStepper:SetScript("OnClick", function()
        local currentVal = slider:GetValue()
        local minVal = slider:GetMinMaxValues()
        local newVal = math_max(minVal, currentVal - (row._step or 1))
        slider:SetValue(newVal)
        FlushDropped()
    end)

    -- Left stepper hover animation
    local leftAnimGroup = leftStepper:CreateAnimationGroup()
    local leftAnim = leftAnimGroup:CreateAnimation("Animation")
    leftAnim:SetDuration(0.18)

    local leftColorFrom = {}
    local leftColorTo = {}
    local leftR, leftG, leftB = Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3]

    local function AnimateLeftStepperColor(toAccent)
        leftAnimGroup:Stop()
        leftColorFrom.r = leftR
        leftColorFrom.g = leftG
        leftColorFrom.b = leftB

        if toAccent then
            leftColorTo.r = Theme.accent[1]
            leftColorTo.g = Theme.accent[2]
            leftColorTo.b = Theme.accent[3]
        else
            leftColorTo.r = Theme.textSecondary[1]
            leftColorTo.g = Theme.textSecondary[2]
            leftColorTo.b = Theme.textSecondary[3]
        end
        leftAnimGroup:Play()
    end

    leftAnimGroup:SetScript("OnUpdate", function(self)
        local progress = self:GetProgress() or 0
        local r = leftColorFrom.r + (leftColorTo.r - leftColorFrom.r) * progress
        local g = leftColorFrom.g + (leftColorTo.g - leftColorFrom.g) * progress
        local b = leftColorFrom.b + (leftColorTo.b - leftColorFrom.b) * progress
        leftIcon:SetVertexColor(r, g, b, 1)
        leftR, leftG, leftB = r, g, b
    end)

    leftAnimGroup:SetScript("OnFinished", function()
        leftIcon:SetVertexColor(leftColorTo.r, leftColorTo.g, leftColorTo.b, 1)
        leftR, leftG, leftB = leftColorTo.r, leftColorTo.g, leftColorTo.b
    end)

    -- Hover effects
    leftStepper:SetScript("OnEnter", function(self)
        AnimateLeftStepperColor(true)
    end)

    -- Leave effects
    leftStepper:SetScript("OnLeave", function(self)
        AnimateLeftStepperColor(false)
    end)

    -- Right stepper (increment) - arrow points right (rotated 90 counter-clockwise)
    local rightStepper = CreateFrame("Button", nil, row)
    rightStepper:SetSize(STEPPER_SIZE, STEPPER_SIZE)
    rightStepper:SetPoint("LEFT", sliderBG, "RIGHT", 0, 0)

    -- Right arrow icon
    local rightIcon = rightStepper:CreateTexture(nil, "ARTWORK")
    rightIcon:SetAllPoints()
    rightIcon:SetTexture(STEPPER_TEXTURE)
    rightIcon:SetRotation(math.rad(90)) -- Rotate to point right
    rightIcon:SetTexelSnappingBias(0)
    rightIcon:SetSnapToPixelGrid(false)
    rightStepper.icon = rightIcon

    -- Click handler
    rightStepper:SetScript("OnClick", function()
        local currentVal = slider:GetValue()
        local _, maxVal = slider:GetMinMaxValues()
        local newVal = math_min(maxVal, currentVal + (row._step or 1))
        slider:SetValue(newVal)
        FlushDropped()
    end)

    -- Right stepper hover animation
    local rightAnimGroup = rightStepper:CreateAnimationGroup()
    local rightAnim = rightAnimGroup:CreateAnimation("Animation")
    rightAnim:SetDuration(0.18)

    local rightColorFrom = {}
    local rightColorTo = {}
    local rightR, rightG, rightB = Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3]

    local function AnimateRightStepperColor(toAccent)
        rightAnimGroup:Stop()
        rightColorFrom.r = rightR
        rightColorFrom.g = rightG
        rightColorFrom.b = rightB

        if toAccent then
            rightColorTo.r = Theme.accent[1]
            rightColorTo.g = Theme.accent[2]
            rightColorTo.b = Theme.accent[3]
        else
            rightColorTo.r = Theme.textSecondary[1]
            rightColorTo.g = Theme.textSecondary[2]
            rightColorTo.b = Theme.textSecondary[3]
        end
        rightAnimGroup:Play()
    end

    rightAnimGroup:SetScript("OnUpdate", function(self)
        local progress = self:GetProgress() or 0
        local r = rightColorFrom.r + (rightColorTo.r - rightColorFrom.r) * progress
        local g = rightColorFrom.g + (rightColorTo.g - rightColorFrom.g) * progress
        local b = rightColorFrom.b + (rightColorTo.b - rightColorFrom.b) * progress
        rightIcon:SetVertexColor(r, g, b, 1)
        rightR, rightG, rightB = r, g, b
    end)

    rightAnimGroup:SetScript("OnFinished", function()
        rightIcon:SetVertexColor(rightColorTo.r, rightColorTo.g, rightColorTo.b, 1)
        rightR, rightG, rightB = rightColorTo.r, rightColorTo.g, rightColorTo.b
    end)

    -- Hover effects
    rightStepper:SetScript("OnEnter", function(self)
        AnimateRightStepperColor(true)
    end)

    -- Leave effects
    rightStepper:SetScript("OnLeave", function(self)
        AnimateRightStepperColor(false)
    end)

    -- Store references
    row.leftStepper = leftStepper
    row.rightStepper = rightStepper

    ---------------------------------------------------------------------------------
    -- Input Handling
    ---------------------------------------------------------------------------------

    -- Value editbox
    local valueContainer = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    valueContainer:SetSize(48, 24)
    valueContainer:SetPoint("RIGHT", leftStepper, "LEFT", 0, 0)
    valueContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    -- EditBox border hover animation
    local editBoxAnimGroup = valueContainer:CreateAnimationGroup()
    local editBoxAnim = editBoxAnimGroup:CreateAnimation("Animation")
    editBoxAnim:SetDuration(0.18)

    local editBoxColorFrom = {}
    local editBoxColorTo = {}
    local editBoxR, editBoxG, editBoxB = Theme.fieldBorder[1], Theme.fieldBorder[2], Theme.fieldBorder[3]

    local function AnimateEditBoxBorder(toAccent)
        editBoxAnimGroup:Stop()
        editBoxColorFrom.r = editBoxR
        editBoxColorFrom.g = editBoxG
        editBoxColorFrom.b = editBoxB

        if toAccent then
            editBoxColorTo.r = Theme.accent[1]
            editBoxColorTo.g = Theme.accent[2]
            editBoxColorTo.b = Theme.accent[3]
        else
            editBoxColorTo.r = Theme.fieldBorder[1]
            editBoxColorTo.g = Theme.fieldBorder[2]
            editBoxColorTo.b = Theme.fieldBorder[3]
        end
        editBoxAnimGroup:Play()
    end

    editBoxAnimGroup:SetScript("OnUpdate", function(self)
        local progress = self:GetProgress() or 0
        local r = editBoxColorFrom.r + (editBoxColorTo.r - editBoxColorFrom.r) * progress
        local g = editBoxColorFrom.g + (editBoxColorTo.g - editBoxColorFrom.g) * progress
        local b = editBoxColorFrom.b + (editBoxColorTo.b - editBoxColorFrom.b) * progress
        valueContainer:SetBackdropBorderColor(r, g, b, 1)
        editBoxR, editBoxG, editBoxB = r, g, b
    end)

    editBoxAnimGroup:SetScript("OnFinished", function()
        valueContainer:SetBackdropBorderColor(editBoxColorTo.r, editBoxColorTo.g, editBoxColorTo.b, 1)
        editBoxR, editBoxG, editBoxB = editBoxColorTo.r, editBoxColorTo.g, editBoxColorTo.b
    end)

    -- Editable text box
    local valueEdit = CreateFrame("EditBox", nil, valueContainer)
    valueEdit:SetPoint("TOPLEFT", 0, 0)
    valueEdit:SetPoint("BOTTOMRIGHT", 0, 0)
    valueEdit:SetJustifyH("CENTER")
    valueEdit:SetAutoFocus(false)
    row.valueEdit = valueEdit

    local isUpdating = false

    -- Function to update fill width and editbox text
    local function UpdateFill()
        local val = slider:GetValue()
        local minVal, maxVal = slider:GetMinMaxValues()
        if maxVal == minVal then return end
        local pct = (val - minVal) / (maxVal - minVal)
        local width = math_max(1, (slider:GetWidth() - 2) * pct)
        fill:SetWidth(width)
        if not isUpdating then
            isUpdating = true
            if row._isPercent then
                -- Display as percentage: whole numbers as "65%", fractional as
                -- "65.5%" (one decimal). Avoids a trailing ".0" on integer percents
                -- while preserving sub-1% precision for callers that need it.
                local pctVal = math_floor(val * 1000 + 0.5) / 10
                if pctVal == math_floor(pctVal) then
                    valueEdit:SetText(math_floor(pctVal) .. "%")
                else
                    valueEdit:SetText(pctVal .. "%")
                end
            else
                valueEdit:SetText(tostring(math_floor(val * 100 + 0.5) / 100))
            end
            isUpdating = false
        end
    end

    slider:SetScript("OnValueChanged", function(self, val)
        UpdateFill()
        -- Read before either callback runs: one can rebuild the page and hand
        -- this slider to another setting.
        local callback, onValueChanged, gen = row._callback, row._onValueChanged, row._keGen
        -- Every change, silent ones included: a caller that mirrors the
        -- value, such as a live label, must follow neighbour cross-updates.
        if onValueChanged then
            onValueChanged(val)
            if row._keGen ~= gen then
                -- The throttle state now belongs to the new setting; the
                -- change itself still belongs to the old one.
                if callback then callback(val) end
                return
            end
        end
        -- Silent SetValue (row:SetValue(v, true) — e.g. a neighbour-slider
        -- cross-update) nils row._callback: refresh the fill/editbox but do NOT
        -- touch the throttle clock. Otherwise the silent call would reset
        -- lastUpdate and the slider's next REAL drag would swallow its first
        -- callback for up to THROTTLE_DELAY.
        if not callback then return end
        local currentTime = GetTime()
        if currentTime - lastUpdate < THROTTLE_DELAY then
            dropped = true
            return
        end
        lastUpdate = currentTime
        dropped = false
        callback(val)
    end)

    slider:SetScript("OnSizeChanged", UpdateFill)

    -- A typed value, clamped to the range, committed through the same
    -- throttled SetValue.
    local function CommitTyped(text)
        if row._isPercent then
            text = text:gsub("%%", "")
            local num = tonumber(text)
            if num then
                num = num / 100
                local minVal, maxVal = slider:GetMinMaxValues()
                num = math_max(minVal, math_min(maxVal, num))
                isUpdating = true
                slider:SetValue(num)
                isUpdating = false
            else
                UpdateFill()
            end
        else
            local num = tonumber(text)
            if num then
                local minVal, maxVal = slider:GetMinMaxValues()
                num = math_max(minVal, math_min(maxVal, num))
                isUpdating = true
                slider:SetValue(num)
                isUpdating = false
            else
                UpdateFill()
            end
        end
        FlushDropped()
    end

    -- Set while Escape clears focus, so the commit below is skipped.
    local cancelTyped = false

    valueEdit:SetScript("OnEscapePressed", function(self)
        cancelTyped = true
        self:ClearFocus()
        cancelTyped = false
        UpdateFill()
    end)

    -- The commit lives in OnEditFocusLost, which ClearFocus fires.
    valueEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    valueEdit:SetScript("OnEditFocusGained", function(self)
        editBoxAnimGroup:Stop()
        valueContainer:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        editBoxR, editBoxG, editBoxB = Theme.accent[1], Theme.accent[2], Theme.accent[3]
        self:HighlightText()
    end)

    valueEdit:SetScript("OnEditFocusLost", function(self)
        editBoxAnimGroup:Stop()
        valueContainer:SetBackdropBorderColor(Theme.fieldBorder[1], Theme.fieldBorder[2], Theme.fieldBorder[3], 1)
        editBoxR, editBoxG, editBoxB = Theme.fieldBorder[1], Theme.fieldBorder[2], Theme.fieldBorder[3]
        self:HighlightText(0, 0)
        if not cancelTyped then CommitTyped(self:GetText()) end
    end)

    -- Add hover animation for editbox
    valueEdit:SetScript("OnEnter", function(self)
        if not valueEdit:HasFocus() then
            AnimateEditBoxBorder(true)
        end
    end)

    valueEdit:SetScript("OnLeave", function(self)
        if not valueEdit:HasFocus() then
            AnimateEditBoxBorder(false)
        end
    end)

    local curDrag = false

    -- Mouse interaction scripts
    slider:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            hoverAnimGroup:Stop()
            thumbFrame:SetBackdropColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            thumbR, thumbG, thumbB, thumbA = Theme.accent[1], Theme.accent[2], Theme.accent[3], 1
            thumbFrame:SetBackdropBorderColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
            curDrag = true
        end
    end)

    slider:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            curDrag = false
            thumbFrame:SetBackdropBorderColor(0, 0, 0, 1)
            if self:IsMouseOver() then
                AnimateThumbColor(true, false)
            else
                AnimateThumbColor(false, false)
            end
            FlushDropped()
        end
    end)

    slider:SetScript("OnEnter", function(self)
        if not curDrag then
            AnimateThumbColor(true, false)
        end
        local tooltip = row._tooltip
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    slider:SetScript("OnLeave", function(self)
        if not curDrag then
            AnimateThumbColor(false, false)
        end
        GameTooltip:Hide()
    end)

    -- A hide can swallow the mouse-up or cut a fade short.
    --
    -- A step the throttle dropped is sent now, while the slider is still bound
    -- to its setting: a later send would reach whatever the slider serves next.
    slider:SetScript("OnHide", function()
        FlushDropped()
        curDrag = false
        hoverAnimGroup:Stop()
        local c = Theme.thumbRest
        thumbFrame:SetBackdropColor(c[1], c[2], c[3], 1)
        thumbFrame:SetBackdropBorderColor(0, 0, 0, 1)
        thumbR, thumbG, thumbB, thumbA = c[1], c[2], c[3], 1
    end)

    function row:SetValue(val, silent)
        if silent then
            -- A silent value supersedes a dropped change; the flush must not
            -- send it to the callback.
            dropped = false
            -- onValueChanged still runs and can rebind this slider to another
            -- setting; the old callback must not overwrite the new one.
            local saved, gen = row._callback, row._keGen
            row._callback = nil
            slider:SetValue(val)
            if row._keGen == gen then row._callback = saved end
        else
            slider:SetValue(val)
        end
    end

    function row:GetValue() return slider:GetValue() end

    function row:SetMinMaxValues(minVal, maxVal, silent)
        -- Blizzard's slider:SetMinMaxValues clamps the current value to the
        -- new range and fires OnValueChanged if a clamp occurs. For pooled
        -- callers reconfiguring a slider whose previous render's value is
        -- outside the new range, that callback would write the clamp value
        -- to db before any subsequent SetValue can restore the actual saved
        -- value — surfacing as "font size resets to max" when navigating
        -- between modules with different ranges. silent=true suppresses by
        -- the same save/clear/restore pattern row:SetValue uses.
        local gen = row._keGen
        if silent then
            dropped = false
            local saved = row._callback
            row._callback = nil
            slider:SetMinMaxValues(minVal, maxVal)
            if row._keGen == gen then row._callback = saved end
        else
            slider:SetMinMaxValues(minVal, maxVal)
        end
        -- A rebound slider was already drawn by its configure.
        if row._keGen == gen then UpdateFill() end
    end

    function row:SetEnabled(enabled)
        if enabled then
            row:SetAlpha(1)
            slider:EnableMouse(true)
            valueEdit:EnableMouse(true)
            valueContainer:EnableMouse(true)
            leftStepper:EnableMouse(true)
            rightStepper:EnableMouse(true)
        else
            row:SetAlpha(0.4)
            slider:EnableMouse(false)
            valueEdit:EnableMouse(false)
            valueContainer:EnableMouse(false)
            leftStepper:EnableMouse(false)
            rightStepper:EnableMouse(false)
        end
    end

    -- Re-apply theme-tied state after KE:RefreshTheme replaces Theme color
    -- tables. Construction-time copies go stale; hover/animation handlers
    -- read live values via Theme.accent[1] indexing each call so they
    -- self-recover. Every configure calls this.
    function row:ApplyThemeColors()
        local TT = Theme
        label:SetTextColor(TT.textSecondary[1], TT.textSecondary[2], TT.textSecondary[3], 1)
        sliderBG:SetBackdropColor(TT.fieldBg[1], TT.fieldBg[2], TT.fieldBg[3], TT.fieldBg[4])
        sliderBG:SetBackdropBorderColor(TT.fieldBorder[1], TT.fieldBorder[2], TT.fieldBorder[3], 1)
        fill:SetColorTexture(TT.accent[1], TT.accent[2], TT.accent[3], 1)
        thumbFrameBG:SetBackdropColor(TT.bgLight[1], TT.bgLight[2], TT.bgLight[3], 1)
        valueContainer:SetBackdropColor(TT.fieldBg[1], TT.fieldBg[2], TT.fieldBg[3], TT.fieldBg[4])
        valueContainer:SetBackdropBorderColor(TT.fieldBorder[1], TT.fieldBorder[2], TT.fieldBorder[3], 1)
        valueEdit:SetTextColor(TT.accent[1], TT.accent[2], TT.accent[3], 1)
        leftIcon:SetVertexColor(TT.textSecondary[1], TT.textSecondary[2], TT.textSecondary[3], 1)
        rightIcon:SetVertexColor(TT.textSecondary[1], TT.textSecondary[2], TT.textSecondary[3], 1)
        UpdateFill()
    end

    -- Back to rest: no focus, no animation, no pending flush, resting thumb.
    function row:_resetInteraction()
        valueEdit:ClearFocus()
        hoverAnimGroup:Stop()
        leftAnimGroup:Stop()
        rightAnimGroup:Stop()
        editBoxAnimGroup:Stop()
        curDrag = false
        dropped = false
        lastUpdate = 0
        isUpdating = false
        thumbR, thumbG, thumbB, thumbA = Theme.thumbRest[1], Theme.thumbRest[2], Theme.thumbRest[3], 1
        thumbFrame:SetBackdropColor(thumbR, thumbG, thumbB, thumbA)
        thumbFrame:SetBackdropBorderColor(0, 0, 0, 1)
        leftR, leftG, leftB = Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3]
        rightR, rightG, rightB = Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3]
        editBoxR, editBoxG, editBoxB = Theme.fieldBorder[1], Theme.fieldBorder[2], Theme.fieldBorder[3]
    end

    row.slider = slider
    row._updateFill = UpdateFill

    -- Pool-friendly callback slot; OnValueChanged reads late-bound.
    function row:SetCallback(fn)
        self._callback = fn
    end

    function row:SetOnValueChanged(fn)
        self._onValueChanged = fn
    end

    row._keOwned = {
        row, sliderBG, slider, thumbFrameBG, thumbFrame,
        leftStepper, rightStepper, valueContainer, valueEdit,
    }
    return row
end

local function ConfigureSlider(row, labelText, config)
    local min = tonumber(config.min) or 0
    local max = tonumber(config.max) or 100
    local step = tonumber(config.step) or 1
    local value = tonumber(config.value) or min

    -- Every use: row:AddWidget sizes a widget to its row.
    row:SetHeight(36)
    local label = row.label
    KE:ApplyThemeFont(label, "small")
    label:SetText(labelText or "")
    -- Own font, not a Blizzard font object: the global font sweep resizes
    -- those, and the addon's config window must not follow a game-wide setting.
    KE:ApplyThemeFont(row.valueEdit, "normal")

    row._tooltip = config.tooltip
    row._isPercent = config.isPercent
    row._step = step
    row:_resetInteraction()
    row.slider:SetValueStep(step)
    -- Silent: nothing is bound yet, and a clamp must not write anywhere.
    row:SetMinMaxValues(min, max, true)
    row:SetValue(value, true)
    row:SetEnabled(true)
    row:ApplyThemeColors()
    row._callback = config.callback
    row._onValueChanged = config.onValueChanged
    C_Timer.After(0, row._updateFill)
end

local sliderPool = GUIFrame:NewWidgetPool("slider", ConstructSlider, function(row)
    row:_resetInteraction()
end)

-- Slider widget — config-table API: { min, max, step, value, callback,
-- onValueChanged, tooltip, isPercent }
-- TODO: `labelWidth` is accepted in the API but not yet wired into the widget
-- body. Callers (e.g. `labelWidth = 60`) won't see
-- the effect — config key passes silently. Implement when needed.
function GUIFrame:CreateSlider(parent, labelText, config)
    config = config or {}
    local row
    if self:IsPoolParent(parent) then
        row = sliderPool:Acquire(parent)
    else
        row = ConstructSlider(parent)
    end
    ConfigureSlider(row, labelText, config)
    return row
end
