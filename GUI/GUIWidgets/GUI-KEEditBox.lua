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

---------------------------------------------------------------------------------
-- Widget Creation
---------------------------------------------------------------------------------

-- Builds one edit box. Label, height, value and bindings are applied by
-- ConfigureEditBox, so a pooled box can serve any setting.
local function ConstructEditBox(parent)
    local row = CreateFrame("Frame", nil, parent)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetJustifyH("LEFT")
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

    ---------------------------------------------------------------------------------
    -- Animation
    ---------------------------------------------------------------------------------

    -- EditBox border hover animation
    local editBoxAnimGroup = container:CreateAnimationGroup()
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
    editBox:SetAutoFocus(false)

    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    editBox:SetScript("OnEnterPressed", function(self)
        -- Read first: ClearFocus fires OnEditFocusLost, whose callback can
        -- rebuild the page and hand this box to another setting.
        local callback, text = row._callback, self:GetText()
        self:ClearFocus()
        if callback then callback(text) end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        container:SetBackdropBorderColor(Theme.fieldBorder[1], Theme.fieldBorder[2], Theme.fieldBorder[3], 1)
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
        local tooltip = row._tooltip
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
        local tooltip = row._tooltip
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    container:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Pools reuse a hidden box without repainting it, so a hover fade still
    -- in flight at hide time is dropped here.
    container:SetScript("OnHide", function()
        editBoxAnimGroup:Stop()
        container:SetBackdropBorderColor(Theme.fieldBorder[1], Theme.fieldBorder[2], Theme.fieldBorder[3], 1)
        editBoxR, editBoxG, editBoxB = Theme.fieldBorder[1], Theme.fieldBorder[2], Theme.fieldBorder[3]
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
    -- indexing each call so they self-recover. Every configure calls this.
    function row:ApplyThemeColors()
        local TT = Theme
        label:SetTextColor(TT.textSecondary[1], TT.textSecondary[2], TT.textSecondary[3], 1)
        container:SetBackdropColor(TT.fieldBg[1], TT.fieldBg[2], TT.fieldBg[3], TT.fieldBg[4])
        container:SetBackdropBorderColor(TT.fieldBorder[1], TT.fieldBorder[2], TT.fieldBorder[3], 1)
        editBox:SetTextColor(TT.accent[1], TT.accent[2], TT.accent[3], 1)
    end

    -- Back to rest: no focus and no border fade.
    function row:_resetInteraction()
        editBox:ClearFocus()
        editBoxAnimGroup:Stop()
        editBoxR, editBoxG, editBoxB = Theme.fieldBorder[1], Theme.fieldBorder[2], Theme.fieldBorder[3]
    end

    row.editBox = editBox
    row.container = container

    -- Pool-friendly callback slots; OnEnterPressed/OnEditFocusLost read
    -- _callback late-bound, OnTextChanged reads _onTextChanged per keystroke.
    function row:SetCallback(fn)
        self._callback = fn
    end

    function row:SetOnTextChanged(fn)
        self._onTextChanged = fn
    end

    -- Live typing waits out a short debounce. Only the latest keystroke's call
    -- does anything when it runs, and a page rebuild in between runs it early
    -- (GUIFrame:DeferWidgetCallback). userInput=false (programmatic SetText)
    -- is ignored.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local fn = row._onTextChanged
        if not fn then return end
        local text = self:GetText()
        local function Fire()
            if row._pendingText ~= Fire then return end
            row._pendingText = nil
            fn(text)
        end
        row._pendingText = Fire
        GUIFrame:DeferWidgetCallback(row._textChangedDelay or 0.15, Fire)
    end)

    row._keOwned = { row, container, editBox }
    return row
end

-- EditBox widget — config-table API:
--   { value, callback, tooltip, height, onTextChanged, textChangedDelay }
-- onTextChanged: optional debounced callback that fires DURING typing (not
-- on Enter/blur — that's `callback`'s job). Useful for live filters like the
-- BigWigs spell-search box. Debounce defaults to 150ms; override via
-- textChangedDelay.
local function ConfigureEditBox(row, labelText, config)
    row:SetHeight(config.height or 34)
    local label = row.label
    KE:ApplyThemeFont(label, "small")
    label:SetText(labelText or "")
    -- Own font, not a Blizzard font object: the global font sweep resizes
    -- those, and the addon's config window must not follow a game-wide setting.
    KE:ApplyThemeFont(row.editBox, "normal")
    row._tooltip = config.tooltip
    row:_resetInteraction()
    row:SetValue(tostring(config.value or ""), true)
    row:SetEnabled(true)
    row:ApplyThemeColors()
    row._callback = config.callback
    row._onTextChanged = config.onTextChanged
    row._textChangedDelay = config.textChangedDelay or 0.15
end

local editBoxPool = GUIFrame:NewWidgetPool("editbox", ConstructEditBox, function(row)
    row:_resetInteraction()
end)

function GUIFrame:CreateEditBox(parent, labelText, config)
    config = config or {}
    local row
    if self:IsPoolParent(parent) then
        row = editBoxPool:Acquire(parent)
    else
        row = ConstructEditBox(parent)
    end
    ConfigureEditBox(row, labelText, config)
    return row
end
