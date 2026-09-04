-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ThemePopup.lua                                      ║
-- ║  GUI: Customize Theme popup                              ║
-- ║  Purpose: Preset grid, custom colors and the tint         ║
-- ║  switch, in a persistent dialog over the settings window. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local CreateFrame = CreateFrame
local IsMouseButtonDown = IsMouseButtonDown
local ColorPickerFrame = ColorPickerFrame
local GetMouseFocus = GetMouseFocus
local GetMouseFoci = GetMouseFoci
local pairs = pairs

local HEADER_HEIGHT = 32

---------------------------------------------------------------------------------
-- Outside-click closing
---------------------------------------------------------------------------------

-- Frames a click on must not close the popup, in addition to the popup
-- itself and an open ColorPickerFrame. Populated automatically below rather
-- than by name: whatever frame the mouse is over when Show/Hide/Toggle runs
-- gets exempted, so any future opener button works without editing this file.
GUIFrame.themePopupOpeners = GUIFrame.themePopupOpeners or {}
GUIFrame.themePopupShown = false

local popup, titleText
local manager, currentMode
local presetSelector
local accentPicker, accentDimPicker, selectedBgPicker, selectedTextPicker
local tintCheckbox
local copyBtn, resetBtn

local function CurrentMouseFocus()
    if GetMouseFocus then
        return GetMouseFocus()
    elseif GetMouseFoci then
        local foci = GetMouseFoci()
        return foci and foci[1] or nil
    end
    return nil
end

-- Exempts whatever the mouse is over right now. Called from every public
-- entry point below so the click that opens, re-toggles or closes the popup
-- never also reads as "outside" to the checker below.
local function ExemptCurrentOpener()
    local focus = CurrentMouseFocus()
    if focus then
        GUIFrame.themePopupOpeners[focus] = true
    end
end

local function IsMouseOverThemePopup()
    if popup:IsMouseOver() then return true end
    for opener in pairs(GUIFrame.themePopupOpeners) do
        if opener and opener:IsMouseOver() then return true end
    end
    if ColorPickerFrame:IsShown() and ColorPickerFrame:IsMouseOver() then return true end
    return false
end

-- Global mouse-checker idiom, ported from GUI-KEDropdown.lua: watches for a
-- mouse-up transition and closes on release outside the popup, its openers,
-- and an open ColorPickerFrame.
local checker = CreateFrame("Frame", nil, UIParent)
checker:Hide()
checker.wasMouseDown = false

checker:SetScript("OnUpdate", function(self)
    if not (popup and popup:IsShown()) then
        self:Hide()
        return
    end
    local isDown = IsMouseButtonDown("LeftButton")
    if self.wasMouseDown and not isDown and not IsMouseOverThemePopup() then
        GUIFrame:HideThemePopup()
    end
    self.wasMouseDown = isDown
end)

---------------------------------------------------------------------------------
-- Silent resync helpers
---------------------------------------------------------------------------------

-- Pushes a saved colour into a picker row without firing its callback, which
-- writes to Theme.Custom and calls KE:RefreshTheme. Without this, opening the
-- popup or resyncing it after Reset Theme would rewrite the colours it is
-- only meant to display.
local function SilentSetColor(row, color, default)
    if not row then return end
    local c = color or default
    local callback = row._callback
    row:SetCallback(nil)
    row:SetColor(c[1], c[2], c[3], c[4] or 1)
    row:SetCallback(callback)
end

---------------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------------

local function BuildThemePopup()
    local T = Theme
    local mainFrame = GUIFrame.mainFrame
    local db = KE.db and KE.db.global and KE.db.global.Theme

    popup = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    popup:SetSize(490, 352)
    popup:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
    popup:SetFrameStrata("DIALOG")
    -- Above the content tree, following the card mouse blocker's +100 idiom
    -- (GUI-Core.lua). Not TOOLTIP: a TOOLTIP popup would paint over the
    -- DIALOG-strata ColorPickerFrame its own pickers open.
    popup:SetFrameLevel(mainFrame:GetFrameLevel() + 200)
    popup:EnableMouse(true)
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = T.borderSize,
    })
    popup:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], T.bgDark[4])
    popup:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4])
    popup:Hide()

    -- A child keeps IsShown() true through its parent's hide, so without this
    -- the popup springs back on the next GUIFrame:Show(), including the
    -- automatic reopen after combat.
    mainFrame:HookScript("OnHide", function()
        popup:Hide()
    end)

    ----------------------------------------------------------------
    -- Header, styled like a card header
    ----------------------------------------------------------------
    local header = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = T.borderSize,
    })
    header:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], T.bgMedium[4])
    header:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4])

    titleText = header:CreateFontString(nil, "OVERLAY")
    titleText:SetPoint("LEFT", header, "LEFT", T.paddingMedium, 0)
    KE:ApplyThemeFont(titleText, "large")
    titleText:SetText("Customize Theme")
    titleText:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    closeBtn:SetScript("OnClick", function() GUIFrame:HideThemePopup() end)
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetAllPoints()
    closeIcon:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png")
    closeIcon:SetRotation(math.rad(45))
    closeIcon:SetVertexColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], T.textPrimary[4])
    closeBtn:SetScript("OnEnter", function()
        closeIcon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeIcon:SetVertexColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], T.textPrimary[4])
    end)

    ----------------------------------------------------------------
    -- Body
    ----------------------------------------------------------------
    local content = CreateFrame("Frame", nil, popup)
    content:SetPoint("TOPLEFT", popup, "TOPLEFT", T.paddingMedium, -HEADER_HEIGHT - T.paddingMedium)
    content:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -T.paddingMedium, -HEADER_HEIGHT - T.paddingMedium)

    manager = GUIFrame:CreateWidgetStateManager()
    currentMode = (db and db.Mode) or "preset"
    manager:SetCondition("preset", function() return currentMode == "preset" end)
    manager:SetCondition("class", function() return currentMode == "class" end)
    manager:SetCondition("custom", function() return currentMode == "custom" end)

    local currentY = 0
    local function AdvanceY(height, spacing)
        currentY = currentY + height + (spacing or T.paddingSmall)
    end

    -- 1. Preset grid
    presetSelector = GUIFrame:CreatePresetSwatches(content, {
        value = (db and db.Preset) or "KitnUI",
        callback = function(presetName) KE:SetThemePreset(presetName) end,
    })
    local selectorHeight = presetSelector:GetHeight() + 4
    local presetRow = CreateFrame("Frame", nil, content)
    presetRow:SetHeight(selectorHeight)
    presetRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -currentY)
    presetRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -currentY)
    presetSelector:SetParent(presetRow)
    presetSelector:SetPoint("TOPLEFT", presetRow, "TOPLEFT", 0, 0)
    presetSelector:SetPoint("TOPRIGHT", presetRow, "TOPRIGHT", 0, 0)
    manager:Register(presetSelector, "preset")
    AdvanceY(selectorHeight)

    -- 2. Class-colour note, shown only in class mode
    local classRow = GUIFrame:CreateRow(content, T.rowHeightLast)
    classRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -currentY)
    classRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -currentY)
    local classColor = KE:GetPlayerClassColor()
    local classSwatchFrame = CreateFrame("Frame", nil, classRow, "BackdropTemplate")
    classSwatchFrame:SetSize(24, 24)
    classSwatchFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    classSwatchFrame:SetBackdropColor(classColor[1], classColor[2], classColor[3], 1)
    classSwatchFrame:SetBackdropBorderColor(0, 0, 0, 1)
    classRow:AddWidget(classSwatchFrame, 0.1)
    local classLabel = GUIFrame:CreateText(classRow,
        "Your class color will be used as the theme accent.",
        "Background colors remain dark.",
        T.rowHeightLast, "hide")
    classRow:AddWidget(classLabel, 0.9)
    function classRow:SetEnabled(enabled)
        self:SetAlpha(enabled and 1 or 0.4)
    end
    manager:Register(classRow, "class")
    AdvanceY(T.rowHeightLast)

    -- 3. Four colour pickers
    local pickerRow1 = GUIFrame:CreateRow(content, T.rowHeight)
    pickerRow1:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -currentY)
    pickerRow1:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -currentY)
    accentPicker = GUIFrame:CreateColorPicker(pickerRow1, "Accent Color", {
        color = (db and db.Custom and db.Custom.accent) or KE.ThemeDefaults.accent,
        callback = function(r, g, b, a) KE:SetCustomColor("accent", r, g, b, a) end,
    })
    pickerRow1:AddWidget(accentPicker, 0.5)
    manager:Register(accentPicker, "custom")

    accentDimPicker = GUIFrame:CreateColorPicker(pickerRow1, "Accent Dim", {
        color = (db and db.Custom and db.Custom.accentDim) or KE.ThemeDefaults.accentDim,
        callback = function(r, g, b, a) KE:SetCustomColor("accentDim", r, g, b, a) end,
    })
    pickerRow1:AddWidget(accentDimPicker, 0.5)
    manager:Register(accentDimPicker, "custom")
    AdvanceY(T.rowHeight)

    local pickerRow2 = GUIFrame:CreateRow(content, T.rowHeight)
    pickerRow2:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -currentY)
    pickerRow2:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -currentY)
    selectedBgPicker = GUIFrame:CreateColorPicker(pickerRow2, "Selected Background", {
        color = (db and db.Custom and db.Custom.selectedBg) or KE.ThemeDefaults.selectedBg,
        callback = function(r, g, b, a) KE:SetCustomColor("selectedBg", r, g, b, a) end,
    })
    pickerRow2:AddWidget(selectedBgPicker, 0.5)
    manager:Register(selectedBgPicker, "custom")

    selectedTextPicker = GUIFrame:CreateColorPicker(pickerRow2, "Selected Text", {
        color = (db and db.Custom and db.Custom.selectedText) or KE.ThemeDefaults.selectedText,
        callback = function(r, g, b, a) KE:SetCustomColor("selectedText", r, g, b, a) end,
    })
    pickerRow2:AddWidget(selectedTextPicker, 0.5)
    manager:Register(selectedTextPicker, "custom")
    AdvanceY(T.rowHeight)

    -- 4. Separator
    local sepRow = GUIFrame:CreateRow(content, T.rowHeightSeparator)
    sepRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -currentY)
    sepRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -currentY)
    local sep = GUIFrame:CreateSeparator(sepRow)
    sepRow:AddWidget(sep, 1)
    AdvanceY(T.rowHeightSeparator)

    -- 5. Tint switch, ungated: it applies regardless of theme mode
    local tintRow = GUIFrame:CreateRow(content, T.rowHeight)
    tintRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -currentY)
    tintRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -currentY)
    tintCheckbox = GUIFrame:CreateCheckbox(tintRow, "Also Tint Skinned Frames", {
        value = not db or db.TintSkins ~= false,
        callback = function(value) KE:SetTintSkins(value) end,
    })
    tintRow:AddWidget(tintCheckbox, 1)
    AdvanceY(T.rowHeight)

    -- 6. Copy From Current Preset and Reset Theme
    local actionRow = GUIFrame:CreateRow(content, T.rowHeightLast)
    actionRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -currentY)
    actionRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -currentY)
    copyBtn = GUIFrame:CreateButton(actionRow, "Copy From Current Preset", {
        callback = function()
            -- CopyPresetToCustom writes the table but does not refresh.
            KE:CopyPresetToCustom()
            KE:RefreshTheme()
        end,
    })
    actionRow:AddWidget(copyBtn, 0.5)
    manager:Register(copyBtn, "custom")

    resetBtn = GUIFrame:CreateButton(actionRow, "Reset Theme", {
        callback = function() KE:ResetTheme() end,
    })
    actionRow:AddWidget(resetBtn, 0.5)
    manager:Register(resetBtn, "custom")

    manager:UpdateAll(true)
end

---------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------

function GUIFrame:ShowThemePopup()
    if not self.mainFrame then return end
    ExemptCurrentOpener()
    if not popup then
        BuildThemePopup()
    end
    popup:Show()
    self.themePopupShown = true
    checker.wasMouseDown = false
    checker:Show()
    self:RefreshThemePopup()
end

function GUIFrame:HideThemePopup()
    if not popup then return end
    ExemptCurrentOpener()
    popup:Hide()
    self.themePopupShown = false
    checker:Hide()
end

function GUIFrame:ToggleThemePopup()
    if popup and popup:IsShown() then
        self:HideThemePopup()
    else
        self:ShowThemePopup()
    end
end

-- Full database-to-widget resync. The popup is built once and reused, so
-- unlike a rebuilt page no widget here is ever told its value changed except
-- by this call. Every write goes through a silent route (SetCallback(nil),
-- SetValue(..., true), or a callback-free SetValue), so this can never write
-- settings while reading them and can never recurse.
function GUIFrame:RefreshThemePopup()
    if not popup or not popup:IsShown() then return end
    local db = KE.db and KE.db.global and KE.db.global.Theme
    if not db then return end

    currentMode = db.Mode or "preset"

    if presetSelector then
        presetSelector:SetValue(db.Preset or "KitnUI")
    end

    SilentSetColor(accentPicker, db.Custom and db.Custom.accent, KE.ThemeDefaults.accent)
    SilentSetColor(accentDimPicker, db.Custom and db.Custom.accentDim, KE.ThemeDefaults.accentDim)
    SilentSetColor(selectedBgPicker, db.Custom and db.Custom.selectedBg, KE.ThemeDefaults.selectedBg)
    SilentSetColor(selectedTextPicker, db.Custom and db.Custom.selectedText, KE.ThemeDefaults.selectedText)

    if tintCheckbox and tintCheckbox.toggle then
        tintCheckbox.toggle:SetValue(db.TintSkins ~= false, true)
    end

    -- Theme-tied chrome captured at build time, which a persistent popup
    -- never rebuilds to pick up on its own (mirrors card:ApplyThemeColors).
    if titleText then
        titleText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end
    if tintCheckbox and tintCheckbox.ApplyThemeColors then
        tintCheckbox:ApplyThemeColors()
    end
    if copyBtn and copyBtn.ApplyThemeColors then
        copyBtn:ApplyThemeColors()
    end
    if resetBtn and resetBtn.ApplyThemeColors then
        resetBtn:ApplyThemeColors()
    end

    manager:UpdateAll(true)
end
