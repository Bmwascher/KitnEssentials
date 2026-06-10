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

local function ApplyOverlaySettings()
    local M = GetMPT()
    if M and M.ApplyOverlaySettings then M:ApplyOverlaySettings() end
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

-- Multi-up color-picker row: items = { {label, key, default}, ... } placed
-- 1/n each. Used by every Colors card on this page.
local function AddColorRow(card, db, manager, applyFn, items, isLast)
    local h = isLast and Theme.rowHeightLast or Theme.rowHeight
    local row = GUIFrame:CreateRow(card.content, h)
    local frac = 1 / #items
    for _, it in ipairs(items) do
        local label, key, default = it[1], it[2], it[3]
        local picker = GUIFrame:CreateColorPicker(row, label, {
            color = db[key] or default,
            callback = function(r, g, b) db[key] = { r, g, b }; applyFn() end,
        })
        row:AddWidget(picker, frac)
        manager:Register(picker, "all")
    end
    card:AddRow(row, h, isLast and 0 or nil)
end

-- Shared per-section font card: one 3-up row (Font | Size | Outline) writing
-- <prefix>FontFace/<prefix>FontSize/<prefix>FontOutline. prefix "" edits the
-- global default keys (the fallback for affix/key/PB/threshold text).
-- opts: title, maxSize, group, includeMono, note/noteHeight, applyFn.
local function AddFontCard(scrollChild, yOffset, db, manager, prefix, opts)
    opts = opts or {}
    local applyFn  = opts.applyFn or ApplySettings
    local group    = opts.group or "all"
    local faceKey, sizeKey, outlineKey =
        prefix .. "FontFace", prefix .. "FontSize", prefix .. "FontOutline"

    local card = GUIFrame:CreateCard(scrollChild, opts.title or "Font Settings", yOffset)
    manager:Register(card, group)

    local rowH = opts.note and Theme.rowHeight or Theme.rowHeightLast
    local row = GUIFrame:CreateRow(card.content, rowH)
    local fontDrop = GUIFrame:CreateDropdown(row, "Font", {
        options = MediaList("font", "Expressway"),
        value = db[faceKey] or db.FontFace or "Expressway",
        callback = function(key) db[faceKey] = key; applyFn() end,
        searchable = true, isFontPreview = true,
    })
    row:AddWidget(fontDrop, 1 / 3)
    manager:Register(fontDrop, group)
    local sizeSlider = GUIFrame:CreateSlider(row, "Size", {
        min = 8, max = opts.maxSize or 36, step = 1,
        value = db[sizeKey] or db.FontSize or 13,
        callback = function(val) db[sizeKey] = val; applyFn() end,
    })
    row:AddWidget(sizeSlider, 1 / 3)
    manager:Register(sizeSlider, group)
    local outlineDrop = GUIFrame:CreateDropdown(row, "Outline", {
        options = opts.includeMono and KE:GetFontOutlineOptions{ includeMono = true }
                                    or KE:GetFontOutlineOptions(),
        value = db[outlineKey] or db.FontOutline or "OUTLINE",
        callback = function(key) db[outlineKey] = key; applyFn() end,
    })
    row:AddWidget(outlineDrop, 1 / 3)
    manager:Register(outlineDrop, group)
    card:AddRow(row, rowH, (not opts.note) and 0 or nil)

    if opts.note then
        local noteH = opts.noteHeight or 30
        local noteRow = GUIFrame:CreateRow(card.content, noteH)
        local noteText = GUIFrame:CreateText(noteRow,
            KE:ColorTextByTheme("Note"), opts.note, noteH, "hide")
        noteRow:AddWidget(noteText, 1)
        manager:Register(noteText, group)
        card:AddRow(noteRow, noteH, 0)
    end

    return card:GetNextOffset()
end

local FORCES_FORMAT_OPTIONS = {
    { key = "PERCENT",       text = "Percent  (82.52%)" },
    { key = "COUNT",         text = "Count  (198/240)" },
    { key = "COUNT_PERCENT", text = "Count + Percent  (198/240 - 82.52%)" },
    { key = "REMAINING",     text = "Remaining  (42 left)" },
    { key = "CUSTOM",        text = "Custom (token string)" },
}

local FORCES_PLACEMENT_OPTIONS = {
    { key = "EDGE",   text = "On Bar Edge (half-in)" },
    { key = "CORNER", text = "Below Bar" },
    { key = "CENTER", text = "Centered" },
    { key = "BESIDE", text = "Beside Bar" },
}

local FORCES_BRACKET_OPTIONS = {
    { key = "NONE",   text = "None  (198/240)" },
    { key = "SQUARE", text = "Square  ([198/240])" },
    { key = "ROUND",  text = "Round  ((198/240))" },
}

-- Forward declarations — assigned in Tasks 5.5–5.10.
local BuildTimerTab, BuildForcesTab, BuildObjectivesTab, BuildDeathsTab, BuildOverlayTab, BuildGeneralTab

BuildTimerTab = function(scrollChild, yOffset, db, manager)
    manager:SetCondition("backdrop", function()
        return db.Enabled ~= false and db.BackdropEnabled == true
    end)
    manager:SetCondition("threshLabels", function()
        return db.Enabled ~= false and db.ShowThresholdLabels ~= false
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
    local rowF = GUIFrame:CreateRow(fmtCard.content, Theme.rowHeightLast)
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
    fmtCard:AddRow(rowF, Theme.rowHeightLast, 0)
    yOffset = fmtCard:GetNextOffset()

    -- Card 4: Font Settings (the big timer text — TimerFont* keys)
    yOffset = AddFontCard(scrollChild, yOffset, db, manager, "Timer", { maxSize = 48 })

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
    rowL:AddWidget(texDrop, 0.5)
    manager:Register(texDrop, "all")
    local scaleSlider = GUIFrame:CreateSlider(rowL, "HUD Scale", {
        min = 0.5, max = 2.0, step = 0.05,
        value = db.Scale or 1.0,
        callback = function(val) db.Scale = val; ApplySettings() end,
    })
    rowL:AddWidget(scaleSlider, 0.5)
    manager:Register(scaleSlider, "all")
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
        callback = function(checked)
            db.ShowThresholdLabels = checked; ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    rowL3:AddWidget(threshCheck, 1 / 3)
    manager:Register(threshCheck, "all")
    local threshPlaceDrop = GUIFrame:CreateDropdown(rowL3, "Label Position", {
        options = {
            { key = "EDGE",   text = "On Bar Edge (half-in)" },
            { key = "ABOVE",  text = "Above Bar" },
            { key = "INSIDE", text = "In Bar" },
        },
        value = db.ThresholdPlacement or "EDGE",
        callback = function(key) db.ThresholdPlacement = key; ApplySettings() end,
    })
    rowL3:AddWidget(threshPlaceDrop, 1 / 3)
    manager:Register(threshPlaceDrop, "threshLabels")
    local stateFillCheck = GUIFrame:CreateCheckbox(rowL3, "State-Colored Fill", {
        value = db.StateColorFill == true,
        callback = function(checked) db.StateColorFill = checked; ApplySettings() end,
    })
    rowL3:AddWidget(stateFillCheck, 1 / 3)
    manager:Register(stateFillCheck, "all")
    layoutCard:AddRow(rowL3, Theme.rowHeightLast, 0)
    yOffset = layoutCard:GetNextOffset()

    -- Card 6: Colors
    local colorsCard = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(colorsCard, "all")
    AddColorRow(colorsCard, db, manager, ApplySettings, {
        { "Timer (running)",  "TimerColor",        { 1, 1, 1 } },
        { "Timer (timed)",    "TimerSuccessColor", { 1, 0.83, 0.22 } },
        { "Timer (depleted)", "TimerExpiredColor", { 1, 0.16, 0.18 } },
    })
    AddColorRow(colorsCard, db, manager, ApplySettings, {
        { "Bar Fill",        "BarColor",           { 0.56, 0.56, 0.56 } },
        { "Bar Background",  "BarBackgroundColor", { 0.12, 0.12, 0.12 } },
        { "Threshold Ticks", "TickColor",          { 1, 1, 1 } },
    }, true)
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
    row2:AddWidget(fmtDrop, 1 / 3)
    manager:Register(fmtDrop, "all")
    local placeDrop = GUIFrame:CreateDropdown(row2, "Placement", {
        options = FORCES_PLACEMENT_OPTIONS,
        value = db.ForcesPlacement or "EDGE",
        callback = function(key) db.ForcesPlacement = key; ApplySettings() end,
    })
    row2:AddWidget(placeDrop, 1 / 3)
    manager:Register(placeDrop, "all")
    local bracketDrop = GUIFrame:CreateDropdown(row2, "Bracket Style", {
        options = FORCES_BRACKET_OPTIONS,
        value = db.ForcesBracketStyle or "NONE",
        callback = function(key) db.ForcesBracketStyle = key; ApplySettings() end,
    })
    row2:AddWidget(bracketDrop, 1 / 3)
    manager:Register(bracketDrop, "all")
    fmtCard:AddRow(row2, Theme.rowHeight)

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

    -- Card 3: Font Settings (forces text — ForcesFont* keys)
    yOffset = AddFontCard(scrollChild, yOffset, db, manager, "Forces")

    -- Card 4: Colors
    local colorsCard = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(colorsCard, "all")
    AddColorRow(colorsCard, db, manager, ApplySettings, {
        { "Forces Bar",      "ForcesColor",         { 0.73, 0.62, 0.13 } },
        { "Forces Complete", "ForcesCompleteColor", { 0.2, 0.82, 0.31 } },
    })

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

BuildObjectivesTab = function(scrollChild, yOffset, db, manager)
    -- Card 1: Enable + display toggles
    local card1 = GUIFrame:CreateCard(scrollChild, "Objectives", yOffset)
    manager:Register(card1, "all")
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local showCheck = GUIFrame:CreateCheckbox(row1, "Show Boss List", {
        value = db.ShowObjectives ~= false,
        callback = function(checked) db.ShowObjectives = checked; ApplySettings() end,
    })
    row1:AddWidget(showCheck, 0.5)
    manager:Register(showCheck, "all")
    local timesCheck = GUIFrame:CreateCheckbox(row1, "Show Clear Times", {
        value = db.ShowObjectiveTimes ~= false,
        callback = function(checked) db.ShowObjectiveTimes = checked; ApplySettings() end,
    })
    row1:AddWidget(timesCheck, 0.5)
    manager:Register(timesCheck, "all")
    card1:AddRow(row1, Theme.rowHeight)

    local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local pbCheck = GUIFrame:CreateCheckbox(row1b, "Show PB Delta", {
        value = db.ShowPBDelta ~= false,
        callback = function(checked) db.ShowPBDelta = checked; ApplySettings() end,
    })
    row1b:AddWidget(pbCheck, 0.5)
    manager:Register(pbCheck, "all")
    local upcomingCheck = GUIFrame:CreateCheckbox(row1b, "Show PB Targets", {
        value = db.ShowUpcomingPB ~= false,
        callback = function(checked) db.ShowUpcomingPB = checked; ApplySettings() end,
    })
    row1b:AddWidget(upcomingCheck, 0.5)
    manager:Register(upcomingCheck, "all")
    card1:AddRow(row1b, Theme.rowHeightLast, 0)
    yOffset = card1:GetNextOffset()

    -- Card 2: Font Settings (boss-list rows — ObjectiveFont* keys)
    yOffset = AddFontCard(scrollChild, yOffset, db, manager, "Objective")

    -- Card 3: Colors (objective + split deltas + PB)
    local colorsCard = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(colorsCard, "all")
    AddColorRow(colorsCard, db, manager, ApplySettings, {
        { "Objective (pending)", "ObjectiveColor",     { 0.85, 0.85, 0.85 } },
        { "Objective (done)",    "ObjectiveDoneColor", { 0.2, 0.82, 0.31 } },
    })
    AddColorRow(colorsCard, db, manager, ApplySettings, {
        { "Split Ahead",  "SplitAheadColor",  { 0.25, 0.88, 0.82 } },
        { "Split Behind", "SplitBehindColor", { 1, 0.42, 0.42 } },
        { "PB Target",    "PBColor",          { 0.85, 0.79, 0.54 } },
    })

    local rowOp = GUIFrame:CreateRow(colorsCard.content, Theme.rowHeightLast)
    local opSlider = GUIFrame:CreateSlider(rowOp, "PB Opacity", {
        min = 0.1, max = 1.0, step = 0.05, value = db.PBOpacity or 1.0,
        callback = function(val) db.PBOpacity = val; ApplySettings() end,
    })
    rowOp:AddWidget(opSlider, 1)
    manager:Register(opSlider, "all")
    colorsCard:AddRow(rowOp, Theme.rowHeightLast, 0)
    yOffset = colorsCard:GetNextOffset()
    return yOffset
end

BuildDeathsTab = function(scrollChild, yOffset, db, manager)
    -- Card 1: Enable + tooltip toggle
    local card1 = GUIFrame:CreateCard(scrollChild, "Deaths", yOffset)
    manager:Register(card1, "all")
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local showCheck = GUIFrame:CreateCheckbox(row1, "Show Deaths Line", {
        value = db.ShowDeaths ~= false,
        callback = function(checked) db.ShowDeaths = checked; ApplySettings() end,
    })
    row1:AddWidget(showCheck, 0.5)
    manager:Register(showCheck, "all")
    local tipCheck = GUIFrame:CreateCheckbox(row1, "Hover Death Log", {
        value = db.ShowDeathTooltip ~= false,
        callback = function(checked) db.ShowDeathTooltip = checked; ApplySettings() end,
    })
    row1:AddWidget(tipCheck, 0.5)
    manager:Register(tipCheck, "all")
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Count and time-penalty read from Blizzard's authoritative death tracker.\n" ..
        KE:ColorTextByTheme("-") .. " Hover the deaths line for a class-colored, timestamped log.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    manager:Register(noteText, "all")
    card1:AddRow(noteRow, 50, 0)
    yOffset = card1:GetNextOffset()

    -- Card 2: Font Settings (deaths line — DeathsFont* keys)
    yOffset = AddFontCard(scrollChild, yOffset, db, manager, "Deaths")

    -- Card 3: Colors
    local colorsCard = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(colorsCard, "all")
    AddColorRow(colorsCard, db, manager, ApplySettings, {
        { "Deaths Text",  "DeathsColor",       { 0.85, 0.85, 0.85 } },
        { "Time Penalty", "DeathPenaltyColor", { 1, 0.42, 0.42 } },
    }, true)
    yOffset = colorsCard:GetNextOffset()
    return yOffset
end

BuildOverlayTab = function(scrollChild, yOffset, db, manager)
    manager:SetCondition("overlayNP", function()
        return db.Enabled ~= false and db.OverlayNameplateEnabled == true
    end)
    manager:SetCondition("overlayCustomColor", function()
        return db.Enabled ~= false and db.OverlayNameplateEnabled == true
            and (db.OverlayColorMode or "theme") == "custom"
    end)

    -- Card 1: Enable (nameplate % + tooltip count + combat-only)
    local card1 = GUIFrame:CreateCard(scrollChild, "Enemy Overlay", yOffset)
    manager:Register(card1, "all")
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local npCheck = GUIFrame:CreateCheckbox(row1, "Show % on Nameplates", {
        value = db.OverlayNameplateEnabled == true,
        -- ApplyOverlaySettings re-wires the whole nameplate subsystem from DB
        -- (superset of SetOverlayActive, which is the run-state entry point).
        callback = function(checked)
            db.OverlayNameplateEnabled = checked
            ApplyOverlaySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    row1:AddWidget(npCheck, 1 / 3)
    manager:Register(npCheck, "all")
    local tipCheck = GUIFrame:CreateCheckbox(row1, "Enemy Count on Tooltip", {
        value = db.OverlayTooltipEnabled ~= false,
        callback = function(checked) db.OverlayTooltipEnabled = checked; ApplyOverlaySettings() end,
    })
    row1:AddWidget(tipCheck, 1 / 3)
    manager:Register(tipCheck, "all")
    local combatOnlyCheck = GUIFrame:CreateCheckbox(row1, "Only in Combat", {
        value = db.OverlayCombatOnly ~= false,
        callback = function(checked) db.OverlayCombatOnly = checked; ApplyOverlaySettings() end,
    })
    row1:AddWidget(combatOnlyCheck, 1 / 3)
    manager:Register(combatOnlyCheck, "overlayNP")
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 64)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Per-mob forces count on enemy tooltips (12.0.5 API).\n" ..
        KE:ColorTextByTheme("-") .. " Optional per-pull % overlay on nameplates (Mythic+ only).\n" ..
        KE:ColorTextByTheme("-") .. " Replaces the standalone WarpDeplete+ overlay; no external addon needed.",
        64, "hide")
    noteRow:AddWidget(noteText, 1)
    manager:Register(noteText, "all")
    card1:AddRow(noteRow, 64, 0)
    yOffset = card1:GetNextOffset()

    -- Card 2: Nameplate % — Position
    local card2 = GUIFrame:CreateCard(scrollChild, "Nameplate % — Position", yOffset)
    manager:Register(card2, "overlayNP")

    local anchorOptions = {
        { key = "CENTER",      text = "Center"       },
        { key = "TOP",         text = "Top"          },
        { key = "BOTTOM",      text = "Bottom"       },
        { key = "LEFT",        text = "Left"         },
        { key = "RIGHT",       text = "Right"        },
        { key = "TOPLEFT",     text = "Top Left"     },
        { key = "TOPRIGHT",    text = "Top Right"    },
        { key = "BOTTOMLEFT",  text = "Bottom Left"  },
        { key = "BOTTOMRIGHT", text = "Bottom Right" },
    }

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local anchorDropdown = GUIFrame:CreateDropdown(row2a, "Anchor", {
        options = anchorOptions,
        value = db.OverlayAnchor or "TOPRIGHT",
        callback = function(key) db.OverlayAnchor = key; ApplyOverlaySettings() end,
    })
    row2a:AddWidget(anchorDropdown, 1 / 3)
    manager:Register(anchorDropdown, "overlayNP")
    local xSlider = GUIFrame:CreateSlider(row2a, "X Offset", {
        min = -100, max = 100, step = 1,
        value = db.OverlayXOffset or -20,
        callback = function(val) db.OverlayXOffset = val; ApplyOverlaySettings() end,
    })
    row2a:AddWidget(xSlider, 1 / 3)
    manager:Register(xSlider, "overlayNP")
    local ySlider = GUIFrame:CreateSlider(row2a, "Y Offset", {
        min = -100, max = 100, step = 1,
        value = db.OverlayYOffset or 2,
        callback = function(val) db.OverlayYOffset = val; ApplyOverlaySettings() end,
    })
    row2a:AddWidget(ySlider, 1 / 3)
    manager:Register(ySlider, "overlayNP")
    card2:AddRow(row2a, Theme.rowHeightLast, 0)
    yOffset = card2:GetNextOffset()

    -- Card 3: Nameplate % — Font Settings (OverlayFont* keys)
    yOffset = AddFontCard(scrollChild, yOffset, db, manager, "Overlay", {
        title = "Nameplate % — Font Settings",
        group = "overlayNP",
        maxSize = 20,
        includeMono = true,
        applyFn = ApplyOverlaySettings,
    })

    -- Card 4: Nameplate % — Colors
    local card4 = GUIFrame:CreateCard(scrollChild, "Nameplate % — Colors", yOffset)
    manager:Register(card4, "overlayNP")
    local row4 = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local colorModeDropdown = GUIFrame:CreateDropdown(row4, "Color Mode", {
        options = KE.ColorModeOptions,
        value = db.OverlayColorMode or "theme",
        callback = function(key)
            db.OverlayColorMode = key
            ApplyOverlaySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    row4:AddWidget(colorModeDropdown, 0.5)
    manager:Register(colorModeDropdown, "overlayNP")
    local colorPicker = GUIFrame:CreateColorPicker(row4, "Custom Color", {
        color = db.OverlayColor or { 1, 1, 1 },
        callback = function(r, g, b) db.OverlayColor = { r, g, b }; ApplyOverlaySettings() end,
    })
    row4:AddWidget(colorPicker, 0.5)
    manager:Register(colorPicker, "overlayCustomColor")
    card4:AddRow(row4, Theme.rowHeightLast, 0)
    yOffset = card4:GetNextOffset()
    return yOffset
end

BuildGeneralTab = function(scrollChild, yOffset, db, manager)
    -- Card 1: Quality of Life toggles
    local card1 = GUIFrame:CreateCard(scrollChild, "Quality of Life", yOffset)
    manager:Register(card1, "all")
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local keyCheck = GUIFrame:CreateCheckbox(row1, "Auto-Insert Keystone", {
        value = db.AutoInsertKeystone ~= false,
        callback = function(checked) db.AutoInsertKeystone = checked end,
    })
    row1:AddWidget(keyCheck, 1 / 3)
    manager:Register(keyCheck, "all")
    local trackerCheck = GUIFrame:CreateCheckbox(row1, "Hide Blizzard Tracker", {
        value = db.HideBlizzardTracker ~= false,
        callback = function(checked)
            db.HideBlizzardTracker = checked
            local M = GetMPT()
            if M and M.ApplyTrackerVisibility then M:ApplyTrackerVisibility() end
        end,
    })
    row1:AddWidget(trackerCheck, 1 / 3)
    manager:Register(trackerCheck, "all")
    local chatCheck = GUIFrame:CreateCheckbox(row1, "Post Boss Splits to Chat", {
        value = db.ChatOutputSplits == true,
        callback = function(checked) db.ChatOutputSplits = checked end,
    })
    row1:AddWidget(chatCheck, 1 / 3)
    manager:Register(chatCheck, "all")
    card1:AddRow(row1, Theme.rowHeightLast, 0)
    yOffset = card1:GetNextOffset()

    -- Card 2: Affixes & Key display + colors
    local card2 = GUIFrame:CreateCard(scrollChild, "Affixes & Key", yOffset)
    manager:Register(card2, "all")
    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local affixCheck = GUIFrame:CreateCheckbox(row2a, "Show Affixes", {
        value = db.ShowAffixes ~= false,
        callback = function(checked) db.ShowAffixes = checked; ApplySettings() end,
    })
    row2a:AddWidget(affixCheck, 1 / 3)
    manager:Register(affixCheck, "all")
    local keyLvlCheck = GUIFrame:CreateCheckbox(row2a, "Show Key Level", {
        value = db.ShowKeyLevel ~= false,
        callback = function(checked) db.ShowKeyLevel = checked; ApplySettings() end,
    })
    row2a:AddWidget(keyLvlCheck, 1 / 3)
    manager:Register(keyLvlCheck, "all")
    local affixModeDrop = GUIFrame:CreateDropdown(row2a, "Affix Display", {
        options = { { key = "TEXT", text = "Text" }, { key = "ICON", text = "Icons" } },
        value = db.AffixMode or "TEXT",
        callback = function(key) db.AffixMode = key; ApplySettings() end,
    })
    row2a:AddWidget(affixModeDrop, 1 / 3)
    manager:Register(affixModeDrop, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    AddColorRow(card2, db, manager, ApplySettings, {
        { "Affix Text", "AffixColor", { 0.69, 0.69, 0.69 } },
        { "Key Level",  "KeyColor",   { 0.69, 0.69, 0.69 } },
    }, true)
    yOffset = card2:GetNextOffset()

    -- Card 3: Default Font (global FontFace/FontSize/FontOutline — the
    -- fallback for every HUD element without its own font card).
    yOffset = AddFontCard(scrollChild, yOffset, db, manager, "", {
        title = "Default Font",
        note = "Applies to the affix line, key level, PB text, and threshold labels.",
    })

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
