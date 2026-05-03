-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KEEditBox.lua                                       ║
-- ║  Purpose: Text input widget with validation.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Localization Setup
local tostring = tostring
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetTime = GetTime

---------------------------------------------------------------------------------
-- Widget Creation
---------------------------------------------------------------------------------

-- EditBox widget — config-table API:
--   { value, callback, tooltip, height, onTextChanged, textChangedDelay }
-- onTextChanged: optional debounced callback that fires DURING typing (not
-- on Enter/blur — that's `callback`'s job). Useful for live filters like the
-- BigWigs spell-search box. Debounce defaults to 150ms; override via
-- textChangedDelay. Pool-friendly: stored in row._onTextChanged and
-- swappable via row:SetOnTextChanged(fn).
function GUIFrame:CreateEditBox(parent, labelText, config)
    config = config or {}
    local value = tostring(config.value or "")
    local tooltip = config.tooltip
    local customHeight = config.height

    local rowHeight = customHeight or 34
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(rowHeight)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetJustifyH("LEFT")
    KE:ApplyThemeFont(label, "small")
    label:SetText(labelText or "")
    label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    row.label = label

    local container = CreateFrame("Frame", nil, row, "BackdropTemplate")
    container:SetHeight(24)
    container:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    container:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -14)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    container:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
    container:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    ---------------------------------------------------------------------------------
    -- Animation
    ---------------------------------------------------------------------------------

    -- EditBox border hover animation
    local editBoxAnimGroup = container:CreateAnimationGroup()
    local editBoxAnim = editBoxAnimGroup:CreateAnimation("Animation")
    editBoxAnim:SetDuration(0.18)

    local editBoxColorFrom = {}
    local editBoxColorTo = {}
    local editBoxR, editBoxG, editBoxB = Theme.border[1], Theme.border[2], Theme.border[3]

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
            editBoxColorTo.r = Theme.border[1]
            editBoxColorTo.g = Theme.border[2]
            editBoxColorTo.b = Theme.border[3]
        end
        editBoxAnimGroup:Play()
    end

    editBoxAnimGroup:SetScript("OnUpdate", function(self)
        local progress = self:GetProgress() or 0
        local r = editBoxColorFrom.r + (editBoxColorTo.r - editBoxColorFrom.r) * progress
        local g = editBoxColorFrom.g + (editBoxColorTo.g - editBoxColorFrom.g) * progress
        local b = editBoxColorFrom.b + (editBoxColorTo.b - editBoxColorFrom.b) * progress
        container:SetBackdropBorderColor(r, g, b, 1)
        editBoxR, editBoxG, editBoxB = r, g, b
    end)

    editBoxAnimGroup:SetScript("OnFinished", function()
        container:SetBackdropBorderColor(editBoxColorTo.r, editBoxColorTo.g, editBoxColorTo.b, 1)
        editBoxR, editBoxG, editBoxB = editBoxColorTo.r, editBoxColorTo.g, editBoxColorTo.b
    end)

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -4)
    editBox:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 4)
    editBox:SetFontObject("GameFontNormal")
    editBox:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    editBox:SetAutoFocus(false)
    editBox:SetText(value or "")

    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if row._callback then row._callback(self:GetText()) end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        container:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        if row._callback then row._callback(self:GetText()) end
    end)

    editBox:SetScript("OnEditFocusGained", function()
        container:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end)

    -- Add tooltip support for the editBox itself
    editBox:SetScript("OnEnter", function()
        if not editBox:HasFocus() then
            AnimateEditBoxBorder(true)
        end
        if tooltip then
            GameTooltip:SetOwner(container, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    editBox:SetScript("OnLeave", function()
        if not editBox:HasFocus() then
            AnimateEditBoxBorder(false)
        end
        GameTooltip:Hide()
    end)

    -- Add tooltip support for the container
    container:EnableMouse(true)
    container:SetScript("OnEnter", function(self)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    container:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- silent: suppress the OnTextChanged debounce + pool-bound _onTextChanged
    -- callback. EditBox:SetText fires OnTextChanged with userInput=false, but
    -- we already gate on userInput so silent only matters if a future change
    -- ever lifts that gate. Cheap to track and matches Slider/Dropdown API.
    function row:SetValue(val, silent)
        local saved
        if silent then
            saved = row._onTextChanged
            row._onTextChanged = nil
        end
        editBox:SetText(val or "")
        if silent then
            row._onTextChanged = saved
        end
    end

    function row:GetValue() return editBox:GetText() end

    function row:SetEnabled(enabled)
        if enabled then
            row:SetAlpha(1)
            editBox:EnableMouse(true)
            editBox:EnableKeyboard(true)
        else
            row:SetAlpha(0.4)
            editBox:EnableMouse(false)
            editBox:EnableKeyboard(false)
            editBox:ClearFocus()
        end
    end

    -- Re-apply theme-tied state after KE:RefreshTheme replaces Theme color
    -- tables. Hover/focus handlers read live values via Theme.accent[1]
    -- indexing each call so they self-recover. Pool consumers call this
    -- when KE._themeVersion has advanced.
    function row:ApplyThemeColors()
        local TT = Theme
        label:SetTextColor(TT.textSecondary[1], TT.textSecondary[2], TT.textSecondary[3], 1)
        container:SetBackdropColor(TT.bgDark[1], TT.bgDark[2], TT.bgDark[3], 1)
        container:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], 1)
        editBox:SetTextColor(TT.accent[1], TT.accent[2], TT.accent[3], 1)
    end

    row.editBox = editBox
    row.container = container

    -- Pool-friendly callback slots; OnEnterPressed/OnEditFocusLost read
    -- _callback late-bound, OnTextChanged reads _onTextChanged late-bound.
    row._callback = config.callback
    function row:SetCallback(fn)
        self._callback = fn
    end

    row._onTextChanged = config.onTextChanged
    row._textChangedDelay = config.textChangedDelay or 0.15
    function row:SetOnTextChanged(fn)
        self._onTextChanged = fn
    end

    -- Live-typing OnTextChanged: wired ONCE at factory time and reads the
    -- _onTextChanged slot late-bound, so a pooled editbox kit can swap its
    -- live-filter callback per render without re-binding scripts. Debounced
    -- via fire-token: each keystroke schedules one C_Timer.After; intermediate
    -- strokes invalidate prior tokens by bumping lastFireToken (no cancel API
    -- needed). userInput=false (programmatic SetText) is ignored.
    local lastFireToken = 0
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        if not row._onTextChanged then return end
        local fireToken = GetTime()
        lastFireToken = fireToken
        local text = self:GetText()
        local delay = row._textChangedDelay or 0.15
        C_Timer.After(delay, function()
            if lastFireToken == fireToken then
                local fn = row._onTextChanged
                if fn then fn(text) end
            end
        end)
    end)

    return row
end
