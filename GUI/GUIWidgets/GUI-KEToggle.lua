-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KEToggle.lua                                        ║
-- ║  Purpose: Toggle/checkbox widget for the settings panel. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Localization Setup
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local select = select

---------------------------------------------------------------------------------
-- Widget Creation
---------------------------------------------------------------------------------

-- Checkbox Widget — config-table API: { value, callback, msgPopup, msgText, msgOn, msgOff, tooltip }
function GUIFrame:CreateCheckbox(parent, labelText, config)
    config = config or {}
    local initialState = config.value
    local msgPopup = config.msgPopup
    local msgText = config.msgText
    local msgOn = config.msgOn
    local msgOff = config.msgOff
    local tooltip = config.tooltip
    local customHeight = nil
    local TOGGLE_WIDTH = 48
    local TOGGLE_HEIGHT = 24
    local KNOB_SIZE = 22
    local KNOB_CROSS = 22
    local KNOB_PADDING = 1
    local ANIMATION_DURATION = 0.18
    local checkText = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\ok-iconBlack.tga"
    local crossText = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\cross-small.png"

    local OFF_POSITION = KNOB_PADDING
    local ON_POSITION = TOGGLE_WIDTH - KNOB_SIZE - KNOB_PADDING

    local row = CreateFrame("Frame", nil, parent)
    local rowHeight = customHeight or 36
    row:SetHeight(rowHeight)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
    label:SetJustifyH("LEFT")
    KE:ApplyThemeFont(label, "small")
    label:SetText(labelText or "")
    label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    row.label = label

    local toggle = CreateFrame("Frame", nil, row, "BackdropTemplate")
    toggle:SetSize(TOGGLE_WIDTH, TOGGLE_HEIGHT)
    toggle:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    toggle:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    toggle:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)
    toggle:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local knob = CreateFrame("Frame", nil, toggle, "BackdropTemplate")
    knob:SetSize(KNOB_SIZE, KNOB_SIZE)
    knob:SetPoint("LEFT", toggle, "LEFT", OFF_POSITION, 0)
    knob:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = -1, right = -1, top = 0, bottom = 0 },
    })
    knob:SetBackdropColor(0, 0, 0, 1)
    knob:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local knobTexture = knob:CreateTexture(nil, "ARTWORK")
    knobTexture:SetAllPoints()
    knobTexture:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.6)
    knobTexture:SetTexelSnappingBias(0)
    knobTexture:SetSnapToPixelGrid(false)

    local checkmark = knob:CreateTexture(nil, "OVERLAY")
    checkmark:SetSize(KNOB_SIZE, KNOB_SIZE)
    checkmark:SetPoint("CENTER", knob, "CENTER", 0, 0)
    checkmark:SetTexture(checkText)
    checkmark:SetVertexColor(1, 1, 1, 1)
    checkmark:SetTexelSnappingBias(0)
    checkmark:SetSnapToPixelGrid(false)
    checkmark:Hide()

    local crossmark = knob:CreateTexture(nil, "OVERLAY")
    crossmark:SetSize(KNOB_CROSS, KNOB_CROSS)
    crossmark:SetPoint("CENTER", knob, "CENTER", 0, 0)
    crossmark:SetTexture(crossText)
    crossmark:SetVertexColor(1, 1, 1, 0.8)
    crossmark:SetTexelSnappingBias(0)
    crossmark:SetSnapToPixelGrid(false)
    crossmark:Hide()

    ---------------------------------------------------------------------------------
    -- Animation
    ---------------------------------------------------------------------------------

    local animGroup = knob:CreateAnimationGroup()
    local slideAnim = animGroup:CreateAnimation("Translation")
    slideAnim:SetDuration(ANIMATION_DURATION)
    slideAnim:SetSmoothing("OUT")

    local state = initialState or false
    local isAnimating = false
    local knobR, knobG, knobB, knobA = Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.6

    local colorAnimGroup = toggle:CreateAnimationGroup()
    colorAnimGroup:SetLooping("NONE")

    local colorAnim = colorAnimGroup:CreateAnimation("Animation")
    colorAnim:SetDuration(ANIMATION_DURATION)

    local colorFrom = {}
    local colorTo = {}

    local function AnyAnimating()
        return animGroup:IsPlaying() or colorAnimGroup:IsPlaying()
    end

    local function UpdateIcons()
        if state then
            checkmark:Show()
            crossmark:Hide()
            checkmark:SetVertexColor(1, 1, 1, 1)
        else
            checkmark:Hide()
            crossmark:Show()
            crossmark:SetVertexColor(1, 1, 1, 0.8)
        end
    end

    colorAnimGroup:SetScript("OnUpdate", function(self)
        local progress = self:GetProgress() or 0
        local r = colorFrom.bgR + (colorTo.bgR - colorFrom.bgR) * progress
        local g = colorFrom.bgG + (colorTo.bgG - colorFrom.bgG) * progress
        local b = colorFrom.bgB + (colorTo.bgB - colorFrom.bgB) * progress
        toggle:SetBackdropColor(r, g, b, 1)
        local rT = colorFrom.knobR + (colorTo.knobR - colorFrom.knobR) * progress
        local gT = colorFrom.knobG + (colorTo.knobG - colorFrom.knobG) * progress
        local bT = colorFrom.knobB + (colorTo.knobB - colorFrom.knobB) * progress
        local aT = colorFrom.knobA + (colorTo.knobA - colorFrom.knobA) * progress
        knobTexture:SetColorTexture(rT, gT, bT, aT)
        knobR, knobG, knobB, knobA = rT, gT, bT, aT
    end)

    colorAnimGroup:SetScript("OnFinished", function()
        toggle:SetBackdropColor(colorTo.bgR, colorTo.bgG, colorTo.bgB, 1)
        knobTexture:SetColorTexture(colorTo.knobR, colorTo.knobG, colorTo.knobB, colorTo.knobA)
        knobR, knobG, knobB, knobA = colorTo.knobR, colorTo.knobG, colorTo.knobB, colorTo.knobA
        UpdateIcons()
    end)

    local function UpdateColors(toState, instant)
        UpdateIcons()
        if instant then
            if toState then
                toggle:SetBackdropColor(Theme.accent[1] * 0.5, Theme.accent[2] * 0.5, Theme.accent[3] * 0.5, 1)
                knobTexture:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                knobR, knobG, knobB, knobA = Theme.accent[1], Theme.accent[2], Theme.accent[3], 1
            else
                toggle:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
                knobTexture:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.4)
                knobR, knobG, knobB, knobA = Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.4
            end
            knobR, knobG, knobB, knobA = knobTexture:GetVertexColor()
            UpdateIcons()
        else
            colorAnimGroup:Stop()
            colorFrom.bgR, colorFrom.bgG, colorFrom.bgB = toggle:GetBackdropColor()
            colorFrom.knobR, colorFrom.knobG, colorFrom.knobB, colorFrom.knobA = knobR, knobG, knobB, knobA
            colorTo.bgR = toState and Theme.accent[1] * 0.5 or Theme.bgDark[1]
            colorTo.bgG = toState and Theme.accent[2] * 0.5 or Theme.bgDark[2]
            colorTo.bgB = toState and Theme.accent[3] * 0.5 or Theme.bgDark[3]
            colorTo.knobR = Theme.accent[1]
            colorTo.knobG = Theme.accent[2]
            colorTo.knobB = Theme.accent[3]
            colorTo.knobA = toState and 1 or 0.4
            colorAnimGroup:Play()
            UpdateIcons()
        end
    end

    local function AnimateToState(toState, instant)
        if isAnimating and not instant then return end
        isAnimating = true
        state = toState
        local targetX = toState and ON_POSITION or OFF_POSITION
        local currentX = select(4, knob:GetPoint())
        local deltaX = targetX - currentX
        if instant or math.abs(deltaX) < 1 then
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", toggle, "LEFT", targetX, 0)
            UpdateColors(toState, true)
            isAnimating = false
        else
            UpdateColors(toState, false)
            animGroup:Stop()
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", toggle, "LEFT", currentX, 0)
            slideAnim:SetOffset(deltaX, 0)
            animGroup:SetScript("OnFinished", function()
                knob:ClearAllPoints()
                knob:SetPoint("LEFT", toggle, "LEFT", targetX, 0)
                isAnimating = false
                UpdateIcons()
            end)
            animGroup:Play()
        end
    end

    AnimateToState(state, true)

    local button = CreateFrame("Button", nil, toggle)
    button:SetAllPoints()
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function()
        if AnyAnimating() then return end
        local newState = not state
        AnimateToState(newState, false)
        if row._callback then
            C_Timer.After(ANIMATION_DURATION, function()
                if row._callback then
                    row._callback(newState, function(revert)
                        if revert then
                            AnimateToState(not newState, false)
                        end
                    end)
                end
            end)
        end
        if msgPopup then
            local toggleOnOrOff
            if newState then
                toggleOnOrOff = "|cff4DCC66" .. msgOn .. "|r"
            else
                toggleOnOrOff = "|cffE64D4D" .. msgOff .. "|r"
            end
            KE:Print(msgText .. ": " .. toggleOnOrOff)
        end
    end)

    button:SetScript("OnEnter", function(self)
        local hoverBrightness = 1.2
        knobTexture:SetColorTexture(
            Theme.accent[1] * hoverBrightness,
            Theme.accent[2] * hoverBrightness,
            Theme.accent[3] * hoverBrightness,
            state and 1 or 0.6
        )
        local baseA = state and 1 or 0.6
        knobR, knobG, knobB, knobA =
            Theme.accent[1] * hoverBrightness,
            Theme.accent[2] * hoverBrightness,
            Theme.accent[3] * hoverBrightness,
            baseA
        if tooltip then
            -- ANCHOR_CURSOR_RIGHT positions the tooltip top-right of the
            -- cursor, matching AE's tooltip style — keeps the description
            -- next to the pointer instead of obscuring the widget below.
            -- The 10/10 offset pushes the tooltip slightly out from the
            -- cursor so the pointer doesn't sit on the tooltip edge.
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 10, 10)
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function()
        if state then
            knobTexture:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            knobR, knobG, knobB, knobA = Theme.accent[1], Theme.accent[2], Theme.accent[3], 1
        else
            knobTexture:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.4)
            knobR, knobG, knobB, knobA = Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.4
        end
        GameTooltip:Hide()
    end)

    toggle.SetValue = function(_, value, instant)
        if value ~= state then
            AnimateToState(value, instant)
            if row._callback and not instant then
                C_Timer.After(ANIMATION_DURATION, function()
                    if row._callback then row._callback(value) end
                end)
            end
        end
    end

    toggle.GetValue = function()
        return state
    end

    function row:SetEnabled(enabled)
        if enabled then
            toggle:SetAlpha(1)
            label:SetAlpha(1)
            button:EnableMouse(true)
        else
            toggle:SetAlpha(0.5)
            label:SetAlpha(0.5)
            button:EnableMouse(false)
        end
    end

    -- Re-apply theme-tied state after KE:RefreshTheme replaces Theme color
    -- tables. Toggle is stateful — colors depend on the current on/off
    -- state (toggle bg uses accent*0.5 when on, bgDark when off; knob
    -- uses accent at full alpha when on, accent at 0.4 when off). Defer
    -- to UpdateColors(state, true) which handles both cases.
    function row:ApplyThemeColors()
        local TT = Theme
        label:SetTextColor(TT.textSecondary[1], TT.textSecondary[2], TT.textSecondary[3], 1)
        toggle:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], 1)
        knob:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], 1)
        UpdateColors(state, true)
    end

    row.toggle = toggle

    -- Pool-friendly callback slot. Internal scripts read row._callback at
    -- click time (late-bound), so consumers can swap the callback after
    -- creation by calling row:SetCallback(fn). Required for widget pooling
    -- where one widget instance is reused across renders bound to different
    -- data sources.
    row._callback = config.callback
    function row:SetCallback(fn)
        self._callback = fn
    end

    return row
end

---------------------------------------------------------------------------------
-- Compact Checkbox Widget
---------------------------------------------------------------------------------

-- A square checkbox for DENSE lists, where the sliding toggle above is too tall
-- and too wide to fit three to a row. Config-table API, matching every other
-- widget here: { value, tooltip, callback, disabled }.
--
-- The disabled state belongs to the widget, not the caller: it owns the alpha
-- and the click refusal so no call site has to remember both. The fill is
-- Theme.accent so it tracks the user's chosen theme.
function GUIFrame:CreateCompactCheckbox(parent, labelText, config)
    config = config or {}
    local BOX = 16
    local CELL = 22

    local cell = CreateFrame("Button", nil, parent)
    cell:SetHeight(CELL)
    -- Tells row:AddWidget to leave the height alone; without it the cell
    -- stretches to the row height and the box floats.
    cell.explicitHeight = CELL

    local box = CreateFrame("Frame", nil, cell, "BackdropTemplate")
    box:SetSize(BOX, BOX)
    box:SetPoint("LEFT", cell, "LEFT", 0, 0)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    box:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)
    box:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    -- Inset 2, not 3: at 3 the fill reads as a floating dot rather than a check.
    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
    fill:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.9)

    local label = cell:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    -- No wrap: a wrapped label would overflow a 22px cell into the row below.
    -- A name too long for its column clips instead, which is why the three-column
    -- list carries no per-row suffixes.
    label:SetWordWrap(false)
    -- One point above "small". These grids pack three columns at 22px a row and
    -- the small size reads thin there. Derived from the theme's own small size
    -- rather than the "normal" step, which is not guaranteed to be one point up.
    KE:ApplyThemeFont(label, (Theme.fontSizeSmall or 11) + 1)
    label:SetText(labelText or "")
    label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.9)

    cell._checked = config.value and true or false
    cell._enabled = true
    fill:SetShown(cell._checked)

    function cell:SetChecked(state)
        self._checked = state and true or false
        fill:SetShown(self._checked)
    end

    function cell:GetChecked() return self._checked end

    -- Same name as the sliding toggle's row:SetEnabled, so the grid can disable
    -- either widget the same way. Shadows Button's own
    -- SetEnabled deliberately: that one stops the click but leaves the row at
    -- full opacity, which reads as "locked on" rather than "does not apply".
    --
    -- Mouse input stays ON while disabled. The obvious EnableMouse(false) would
    -- make the row unhoverable, and the tooltip is the ONLY place a greyed row
    -- says WHY it is greyed once the per-row text marker is gone. The refusal
    -- lives in OnClick instead, where it is one explicit branch rather than an
    -- absence of input.
    function cell:SetEnabled(enabled)
        self._enabled = enabled and true or false
        self:SetAlpha(self._enabled and 1 or 0.35)
    end

    cell:SetScript("OnClick", function(self)
        -- The refusal rule. A fully suppressed row must not be writable: its
        -- saved value is the user's real choice, kept intact until EllesmereUI
        -- stops covering that window.
        if not self._enabled then return end
        self:SetChecked(not self._checked)
        if config.callback then config.callback(self._checked) end
    end)

    cell:SetScript("OnEnter", function(self)
        -- Hover STYLING is for live rows only -- a greyed row that lit up on
        -- hover would read as clickable. The tooltip is not styling and shows
        -- either way; on a greyed row it is the whole explanation.
        if self._enabled then
            label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
            box:SetBackdropBorderColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 0.8)
        end
        if config.tooltip then
            -- ANCHOR_CURSOR_RIGHT with a 10/10 offset, matching CreateCheckbox
            -- above so both widgets tip identically.
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 10, 10)
            GameTooltip:SetText(config.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    cell:SetScript("OnLeave", function()
        label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.9)
        box:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        GameTooltip:Hide()
    end)

    -- Re-tint after KE:RefreshTheme swaps the Theme colour tables. Unlike the
    -- sliding toggle this widget is not stateful in colour -- the fill is the
    -- accent whether checked or not, and only its visibility tracks state -- so
    -- a straight re-apply is enough.
    function cell:ApplyThemeColors()
        local TT = Theme
        box:SetBackdropColor(TT.bgMedium[1], TT.bgMedium[2], TT.bgMedium[3], 1)
        box:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], 1)
        fill:SetColorTexture(TT.accent[1], TT.accent[2], TT.accent[3], 0.9)
        label:SetTextColor(TT.textSecondary[1], TT.textSecondary[2], TT.textSecondary[3], 0.9)
    end

    if config.disabled then cell:SetEnabled(false) end

    return cell
end
