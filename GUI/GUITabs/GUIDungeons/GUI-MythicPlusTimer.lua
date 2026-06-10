-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-MythicPlusTimer.lua                                 ║
-- ║  GUI: Mythic+ Timer                                      ║
-- ║  Purpose: Configuration panel for the MythicPlusTimer    ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local pairs = pairs

local activeTab = "Timer"

local function GetMPT()
    return KitnEssentials and KitnEssentials:GetModule("MythicPlusTimer", true)
end

local function ApplySettings()
    local M = GetMPT()
    if M and M.ApplySettings then M:ApplySettings() end
end

-- Builds an LSM media hash {name = name} for searchable dropdowns.
local function MediaList(kind, fallback)
    local out = {}
    if LSM then
        for name in pairs(LSM:HashTable(kind)) do out[name] = name end
    else
        out[fallback] = fallback
    end
    return out
end

-- Shared color-picker row helper (used by Timer, Forces, and future tabs).
-- Signature: AddColor(card, db, manager, applyFn, label, key, default, isLast)
local function AddColor(card, db, manager, applyFn, label, key, default, isLast)
    local row = GUIFrame:CreateRow(card.content, isLast and Theme.rowHeightLast or Theme.rowHeight)
    local picker = GUIFrame:CreateColorPicker(row, label, {
        color = db[key] or default,
        callback = function(r, g, b) db[key] = { r, g, b }; applyFn() end,
    })
    row:AddWidget(picker, 1)
    manager:Register(picker, "all")
    card:AddRow(row, isLast and Theme.rowHeightLast or Theme.rowHeight, isLast and 0 or nil)
end

local FORCES_FORMAT_OPTIONS = {
    { key = "PERCENT",       text = "Percent  (82.52%)" },
    { key = "COUNT",         text = "Count  (198/240)" },
    { key = "COUNT_PERCENT", text = "Count + Percent  (198/240 - 82.52%)" },
    { key = "REMAINING",     text = "Remaining  (42 left)" },
    { key = "CUSTOM",        text = "Custom (token string)" },
}

local FORCES_PLACEMENT_OPTIONS = {
    { key = "CORNER", text = "Corner" },
    { key = "CENTER", text = "Centered" },
    { key = "BESIDE", text = "Beside Bar" },
}

local FORCES_BRACKET_OPTIONS = {
    { key = "NONE",   text = "None  (198/240)" },
    { key = "SQUARE", text = "Square  ([198/240])" },
    { key = "ROUND",  text = "Round  ((198/240))" },
}

-- Forward declarations — assigned in Tasks 5.5–5.10.
local BuildTimerTab, BuildForcesTab, BuildObjectivesTab, BuildDeathsTab, BuildOverlayTab, BuildGeneralTab -- luacheck: ignore 221

BuildTimerTab = function(scrollChild, yOffset, db, manager)
    manager:SetCondition("backdrop", function()
        return db.Enabled ~= false and db.BackdropEnabled == true
    end)

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("MythicPlusTimer", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("MythicPlusTimer")
        else KitnEssentials:DisableModule("MythicPlusTimer") end
    end

    -- Card 1: Enable
    local card1 = GUIFrame:CreateCard(scrollChild, "Mythic+ Timer", yOffset)
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Mythic+ Timer", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            manager:UpdateAll(db.Enabled ~= false)
        end,
        msgPopup = true, msgText = "Mythic+ Timer", msgOn = "On", msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight, 0)
    yOffset = card1:GetNextOffset()

    -- Card 2: Position Settings
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        dbKeys = {
            selfPoint = "SelfPoint", anchorPoint = "AnchorPoint",
            xOffset = "XOffset", yOffset = "YOffset", strata = "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if posCard.positionWidgets then manager:RegisterGroup(posCard.positionWidgets, "all") end
    manager:Register(posCard, "all")
    yOffset = posOffset

    -- Card 3: Format
    local fmtCard = GUIFrame:CreateCard(scrollChild, "Format", yOffset)
    manager:Register(fmtCard, "all")
    local rowF = GUIFrame:CreateRow(fmtCard.content, Theme.rowHeight)
    local fmtDrop = GUIFrame:CreateDropdown(rowF, "Timer Format", {
        options = {
            { key = "ELAPSED_TOTAL",   text = "Elapsed / Total  (15:00 / 35:00)" },
            { key = "REMAINING",       text = "Remaining  (20:00)" },
            { key = "REMAINING_TOTAL", text = "Remaining / Total  (20:00 / 35:00)" },
            { key = "ELAPSED",         text = "Elapsed  (15:00)" },
            { key = "ELAPSED_DETAIL",  text = "Elapsed (Remaining/Total)  (21:23 (11:37/33:00))" },
        },
        value = db.TimerFormat or "ELAPSED_TOTAL",
        callback = function(key) db.TimerFormat = key; ApplySettings() end,
    })
    rowF:AddWidget(fmtDrop, 0.5)
    manager:Register(fmtDrop, "all")
    local msCheck = GUIFrame:CreateCheckbox(rowF, "Show Milliseconds", {
        value = db.ShowMilliseconds == true,
        callback = function(checked) db.ShowMilliseconds = checked; ApplySettings() end,
    })
    rowF:AddWidget(msCheck, 0.5)
    manager:Register(msCheck, "all")
    fmtCard:AddRow(rowF, Theme.rowHeight)

    local rowF2 = GUIFrame:CreateRow(fmtCard.content, Theme.rowHeightLast)
    local scaleSlider = GUIFrame:CreateSlider(rowF2, "HUD Scale", {
        min = 0.5, max = 2.0, step = 0.05,
        value = db.Scale or 1.0,
        callback = function(val) db.Scale = val; ApplySettings() end,
    })
    rowF2:AddWidget(scaleSlider, 1)
    manager:Register(scaleSlider, "all")
    fmtCard:AddRow(rowF2, Theme.rowHeightLast, 0)
    yOffset = fmtCard:GetNextOffset()

    -- Card 4: Font Settings
    local fontCard = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    manager:Register(fontCard, "all")
    local rowFn = GUIFrame:CreateRow(fontCard.content, Theme.rowHeight)
    local fontDrop = GUIFrame:CreateDropdown(rowFn, "Font", {
        options = MediaList("font", "Expressway"),
        value = db.FontFace or "Expressway",
        callback = function(key) db.FontFace = key; ApplySettings() end,
        searchable = true, isFontPreview = true,
    })
    rowFn:AddWidget(fontDrop, 0.5)
    manager:Register(fontDrop, "all")
    local sizeSlider = GUIFrame:CreateSlider(rowFn, "Size", {
        min = 8, max = 36, step = 1,
        value = db.FontSize or 13,
        callback = function(val) db.FontSize = val; ApplySettings() end,
    })
    rowFn:AddWidget(sizeSlider, 0.5)
    manager:Register(sizeSlider, "all")
    fontCard:AddRow(rowFn, Theme.rowHeight)

    local rowFn2 = GUIFrame:CreateRow(fontCard.content, Theme.rowHeightLast)
    local outlineDrop = GUIFrame:CreateDropdown(rowFn2, "Outline", {
        options = KE:GetFontOutlineOptions(),
        value = db.FontOutline or "OUTLINE",
        callback = function(key) db.FontOutline = key; ApplySettings() end,
    })
    rowFn2:AddWidget(outlineDrop, 1)
    manager:Register(outlineDrop, "all")
    fontCard:AddRow(rowFn2, Theme.rowHeightLast, 0)
    yOffset = fontCard:GetNextOffset()

    -- Card 5: Layout
    local layoutCard = GUIFrame:CreateCard(scrollChild, "Layout", yOffset)
    manager:Register(layoutCard, "all")
    local rowL = GUIFrame:CreateRow(layoutCard.content, Theme.rowHeight)
    local texDrop = GUIFrame:CreateDropdown(rowL, "Bar Texture", {
        options = MediaList("statusbar", "KitnUI"),
        value = db.BarTexture or "KitnUI",
        callback = function(key) db.BarTexture = key; ApplySettings() end,
        searchable = true,
    })
    rowL:AddWidget(texDrop, 1)
    manager:Register(texDrop, "all")
    layoutCard:AddRow(rowL, Theme.rowHeight)

    local rowL2 = GUIFrame:CreateRow(layoutCard.content, Theme.rowHeight)
    local wSlider = GUIFrame:CreateSlider(rowL2, "Bar Width", {
        min = 150, max = 500, step = 1, value = db.BarWidth or 300,
        callback = function(val) db.BarWidth = val; ApplySettings() end,
    })
    rowL2:AddWidget(wSlider, 0.5)
    manager:Register(wSlider, "all")
    local hSlider = GUIFrame:CreateSlider(rowL2, "Bar Height", {
        min = 6, max = 40, step = 1, value = db.BarHeight or 14,
        callback = function(val) db.BarHeight = val; ApplySettings() end,
    })
    rowL2:AddWidget(hSlider, 0.5)
    manager:Register(hSlider, "all")
    layoutCard:AddRow(rowL2, Theme.rowHeight)

    local rowL3 = GUIFrame:CreateRow(layoutCard.content, Theme.rowHeightLast)
    local threshCheck = GUIFrame:CreateCheckbox(rowL3, "Show Threshold Labels", {
        value = db.ShowThresholdLabels ~= false,
        callback = function(checked) db.ShowThresholdLabels = checked; ApplySettings() end,
    })
    rowL3:AddWidget(threshCheck, 0.5)
    manager:Register(threshCheck, "all")
    local stateFillCheck = GUIFrame:CreateCheckbox(rowL3, "State-Colored Fill", {
        value = db.StateColorFill == true,
        callback = function(checked) db.StateColorFill = checked; ApplySettings() end,
    })
    rowL3:AddWidget(stateFillCheck, 0.5)
    manager:Register(stateFillCheck, "all")
    layoutCard:AddRow(rowL3, Theme.rowHeightLast, 0)
    yOffset = layoutCard:GetNextOffset()

    -- Card 6: Colors
    local colorsCard = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(colorsCard, "all")
    AddColor(colorsCard, db, manager, ApplySettings, "Timer (running)",  "TimerColor",        { 1, 1, 1 })
    AddColor(colorsCard, db, manager, ApplySettings, "Timer (timed)",    "TimerSuccessColor", { 1, 0.83, 0.22 })
    AddColor(colorsCard, db, manager, ApplySettings, "Timer (depleted)", "TimerExpiredColor", { 1, 0.16, 0.18 })
    AddColor(colorsCard, db, manager, ApplySettings, "Bar Fill",         "BarColor",          { 0.56, 0.56, 0.56 })
    AddColor(colorsCard, db, manager, ApplySettings, "Threshold Ticks",  "TickColor",         { 1, 1, 1 }, true)
    yOffset = colorsCard:GetNextOffset()

    -- Card 7: Backdrop
    local bgCard = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    manager:Register(bgCard, "all")
    local rowB = GUIFrame:CreateRow(bgCard.content, Theme.rowHeight)
    local bgCheck = GUIFrame:CreateCheckbox(rowB, "Enable Backdrop", {
        value = db.BackdropEnabled == true,
        callback = function(checked)
            db.BackdropEnabled = checked
            ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    rowB:AddWidget(bgCheck, 1)
    manager:Register(bgCheck, "all")
    bgCard:AddRow(rowB, Theme.rowHeight)

    local rowB2 = GUIFrame:CreateRow(bgCard.content, Theme.rowHeightLast)
    local bgColor = GUIFrame:CreateColorPicker(rowB2, "Color", {
        color = db.BackdropColor or { 0, 0, 0 },
        callback = function(r, g, b) db.BackdropColor = { r, g, b }; ApplySettings() end,
    })
    rowB2:AddWidget(bgColor, 0.5)
    manager:Register(bgColor, "backdrop")
    local bgOpacity = GUIFrame:CreateSlider(rowB2, "Opacity", {
        min = 0, max = 1, step = 0.05, value = db.BackdropOpacity or 0.6,
        callback = function(val) db.BackdropOpacity = val; ApplySettings() end,
    })
    rowB2:AddWidget(bgOpacity, 0.5)
    manager:Register(bgOpacity, "backdrop")
    bgCard:AddRow(rowB2, Theme.rowHeightLast, 0)
    yOffset = bgCard:GetNextOffset()

    return yOffset
end

BuildForcesTab = function(scrollChild, yOffset, db, manager)
    manager:SetCondition("forcesCustom", function()
        return db.Enabled ~= false and db.ShowForces ~= false and (db.ForcesFormat == "CUSTOM")
    end)
    manager:SetCondition("forcesBanded", function()
        return db.Enabled ~= false and db.ShowForces ~= false and db.ForcesBandedColors == true
    end)

    -- Card 1: Enable
    local card1 = GUIFrame:CreateCard(scrollChild, "Forces", yOffset)
    manager:Register(card1, "all")
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local showCheck = GUIFrame:CreateCheckbox(row1, "Show Forces", {
        value = db.ShowForces ~= false,
        callback = function(checked)
            db.ShowForces = checked; ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    row1:AddWidget(showCheck, 1)
    manager:Register(showCheck, "all")
    card1:AddRow(row1, Theme.rowHeightLast, 0)
    yOffset = card1:GetNextOffset()

    -- Card 2: Format
    local fmtCard = GUIFrame:CreateCard(scrollChild, "Format", yOffset)
    manager:Register(fmtCard, "all")
    local row2 = GUIFrame:CreateRow(fmtCard.content, Theme.rowHeight)
    local fmtDrop = GUIFrame:CreateDropdown(row2, "Text Format", {
        options = FORCES_FORMAT_OPTIONS,
        value = db.ForcesFormat or "PERCENT",
        callback = function(key)
            db.ForcesFormat = key; ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    row2:AddWidget(fmtDrop, 0.5)
    manager:Register(fmtDrop, "all")
    local placeDrop = GUIFrame:CreateDropdown(row2, "Placement", {
        options = FORCES_PLACEMENT_OPTIONS,
        value = db.ForcesPlacement or "CORNER",
        callback = function(key) db.ForcesPlacement = key; ApplySettings() end,
    })
    row2:AddWidget(placeDrop, 0.5)
    manager:Register(placeDrop, "all")
    fmtCard:AddRow(row2, Theme.rowHeight)

    local rowBr = GUIFrame:CreateRow(fmtCard.content, Theme.rowHeight)
    local bracketDrop = GUIFrame:CreateDropdown(rowBr, "Bracket Style", {
        options = FORCES_BRACKET_OPTIONS,
        value = db.ForcesBracketStyle or "NONE",
        callback = function(key) db.ForcesBracketStyle = key; ApplySettings() end,
    })
    rowBr:AddWidget(bracketDrop, 1)
    manager:Register(bracketDrop, "all")
    fmtCard:AddRow(rowBr, Theme.rowHeight)

    local row3 = GUIFrame:CreateRow(fmtCard.content, Theme.rowHeight)
    local customBox = GUIFrame:CreateEditBox(row3, "Custom Format", {
        value = db.ForcesCustomFormat or ":count:/:totalcount: :percent:",
        -- Empty string would render a blank forces label (the backend's `or`
        -- fallback only fires on nil) — store nil so the default token string wins.
        callback = function(text)
            db.ForcesCustomFormat = (text ~= "" and text) or nil
            ApplySettings()
        end,
    })
    row3:AddWidget(customBox, 1)
    manager:Register(customBox, "forcesCustom")
    fmtCard:AddRow(row3, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(fmtCard.content, 78)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Tokens"),
        KE:ColorTextByTheme(":percent:") .. " current %  " ..
        KE:ColorTextByTheme(":count:") .. " current count\n" ..
        KE:ColorTextByTheme(":totalcount:") .. " total  " ..
        KE:ColorTextByTheme(":remainingcount:") .. " count remaining\n" ..
        KE:ColorTextByTheme(":remainingpercent:") .. " % remaining",
        78, "hide")
    noteRow:AddWidget(noteText, 1)
    manager:Register(noteText, "all")
    fmtCard:AddRow(noteRow, 78, 0)
    yOffset = fmtCard:GetNextOffset()

    -- Card 3: Colors
    local colorsCard = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(colorsCard, "all")
    AddColor(colorsCard, db, manager, ApplySettings, "Forces Bar",       "ForcesColor",         { 0.73, 0.62, 0.13 })
    AddColor(colorsCard, db, manager, ApplySettings, "Forces Complete",  "ForcesCompleteColor", { 0.2, 0.82, 0.31 })

    local bandedRow = GUIFrame:CreateRow(colorsCard.content, Theme.rowHeight)
    local bandedCheck = GUIFrame:CreateCheckbox(bandedRow, "Banded Colors (by % bracket)", {
        value = db.ForcesBandedColors == true,
        callback = function(checked)
            db.ForcesBandedColors = checked; ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    bandedRow:AddWidget(bandedCheck, 1)
    manager:Register(bandedCheck, "all")
    colorsCard:AddRow(bandedRow, Theme.rowHeight)

    local BAND_LABELS = { "0-20%", "20-40%", "40-60%", "60-80%", "80-100%" }
    local function AddBandPicker(row, i, frac)
        local picker = GUIFrame:CreateColorPicker(row, "Band " .. BAND_LABELS[i], {
            color = (db.ForcesBandPalette and db.ForcesBandPalette[i]) or { 1, 1, 1 },
            callback = function(r, g, b)
                db.ForcesBandPalette = db.ForcesBandPalette or {}
                db.ForcesBandPalette[i] = { r, g, b }
                ApplySettings()
            end,
        })
        row:AddWidget(picker, frac)
        manager:Register(picker, "forcesBanded")
    end

    local bandRowA = GUIFrame:CreateRow(colorsCard.content, Theme.rowHeight)
    AddBandPicker(bandRowA, 1, 1 / 3)
    AddBandPicker(bandRowA, 2, 1 / 3)
    AddBandPicker(bandRowA, 3, 1 / 3)
    colorsCard:AddRow(bandRowA, Theme.rowHeight)

    local bandRowB = GUIFrame:CreateRow(colorsCard.content, Theme.rowHeightLast)
    AddBandPicker(bandRowB, 4, 0.5)
    AddBandPicker(bandRowB, 5, 0.5)
    colorsCard:AddRow(bandRowB, Theme.rowHeightLast, 0)
    yOffset = colorsCard:GetNextOffset()
    return yOffset
end

GUIFrame:RegisterContent("MythicPlusTimer", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.MythicPlusTimer
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local _, newOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = {
            { id = "Timer",      label = "Timer" },
            { id = "Forces",     label = "Forces" },
            { id = "Objectives", label = "Objectives" },
            { id = "Deaths",     label = "Deaths" },
            { id = "Overlay",    label = "Enemy Overlay" },
            { id = "General",    label = "General" },
        },
        activeId = activeTab,
        onSwitch = function(newId) activeTab = newId end,
        fill = true,
    })
    yOffset = newOffset

    local manager = GUIFrame:CreateWidgetStateManager()

    if activeTab == "Timer" then
        yOffset = BuildTimerTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Forces" then
        yOffset = BuildForcesTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Objectives" then
        yOffset = BuildObjectivesTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Deaths" then
        yOffset = BuildDeathsTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Overlay" then
        yOffset = BuildOverlayTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "General" then
        yOffset = BuildGeneralTab(scrollChild, yOffset, db, manager)
    end

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)
