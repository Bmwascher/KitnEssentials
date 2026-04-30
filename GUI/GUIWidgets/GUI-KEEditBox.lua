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

-- EditBox widget — config-table API: { value, callback, tooltip, height,
--   onTextChanged, textChangedDelay }.
-- onTextChanged: optional debounced callback that fires DURING typing
-- (not on Enter/blur — that's `callback`'s job). Useful for live filters
-- like the BigWigs spell-search box. Debounce defaults to 150ms;
-- override via textChangedDelay.
function GUIFrame:CreateEditBox(parent, labelText, config)
    config = config or {}
    local value = tostring(config.value or "")
    local tooltip = config.tooltip
    local customHeight = config.height
    local onTextChanged = config.onTextChanged
    local textChangedDelay = config.textChangedDelay or 0.15

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

    -- Live-typing callback: only wired when the consumer asked for it.
    -- Debounced via fire-token so each keystroke schedules ONE pending
    -- C_Timer.After; intermediate strokes invalidate prior tokens by
    -- bumping `lastFireToken`. No timer-cancel API needed.
    if onTextChanged then
        local lastFireToken = 0
        editBox:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local fireToken = GetTime()
            lastFireToken = fireToken
            local text = self:GetText()
            C_Timer.After(textChangedDelay, function()
                if lastFireToken == fireToken then
                    onTextChanged(text)
                end
            end)
        end)
    end

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

    function row:SetValue(val) editBox:SetText(val or "") end

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

    row.editBox = editBox
    row.container = container

    -- Pool-friendly callback slot; OnEnterPressed/OnEditFocusLost read late-bound.
    row._callback = config.callback
    function row:SetCallback(fn)
        self._callback = fn
    end

    return row
end
