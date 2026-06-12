-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-MythicPlusTimer.lua                                 ║
-- ║  GUI: Mythic+ Timer                                      ║
-- ║  Purpose: Configuration panel for the MythicPlusTimer    ║
-- ║           module. Four tabs (2026-06-11 restructure,     ║
-- ║           was six): General (the HUD frame itself),      ║
-- ║           Features (per-element toggles + behavior),     ║
-- ║           Display (all colors, then all fonts),          ║
-- ║           Enemy Overlay (nameplate/tooltip subsystem).   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local pairs = pairs

local activeTab = "General"

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

-- PB target source when the current key level has no stored record
-- (db.PBFallbackMode, resolved in MPT.ResolvePBFrom step 3).
local PB_FALLBACK_OPTIONS = {
    { key = "CLOSEST",        text = "Closest Level" },
    { key = "CLOSEST_LOWER",  text = "Closest Lower First" },
    { key = "CLOSEST_HIGHER", text = "Closest Higher First" },
    { key = "HIGHEST",        text = "Highest Recorded" },
    { key = "LOWEST",         text = "Lowest Recorded" },
    { key = "OFF",            text = "Off (Exact Level Only)" },
}

-- Forward declarations — one builder per tab.
local BuildGeneralTab, BuildFeaturesTab, BuildDisplayTab, BuildOverlayTab

---------------------------------------------------------------------------------
-- Tab 1: General — the HUD frame itself (enable, position, layout, thresholds,
-- timer format, backdrop, QoL).
---------------------------------------------------------------------------------

BuildGeneralTab = function(scrollChild, yOffset, db, manager)
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

    -- Card 3: Layout (bar geometry + texture + scale)
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

    local rowL2 = GUIFrame:CreateRow(layoutCard.content, Theme.rowHeightLast)
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
    layoutCard:AddRow(rowL2, Theme.rowHeightLast, 0)
    yOffset = layoutCard:GetNextOffset()

    -- Card 4: Thresholds (+3 / +2 / +1 chest timers — split out of Layout,
    -- 2026-06-11 restructure feedback)
    local threshCard = GUIFrame:CreateCard(scrollChild, "Thresholds (+3 / +2 / +1 Timers)", yOffset)
    manager:Register(threshCard, "all")
    local rowT = GUIFrame:CreateRow(threshCard.content, Theme.rowHeight)
    local threshCheck = GUIFrame:CreateCheckbox(rowT, "Show Threshold Labels", {
        value = db.ShowThresholdLabels ~= false,
        callback = function(checked)
            db.ShowThresholdLabels = checked; ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    rowT:AddWidget(threshCheck, 0.5)
    manager:Register(threshCheck, "all")
    local threshPlaceDrop = GUIFrame:CreateDropdown(rowT, "Label Position", {
        options = {
            { key = "EDGE",   text = "On Bar Edge (half-in)" },
            { key = "ABOVE",  text = "Above Bar" },
            { key = "INSIDE", text = "In Bar" },
        },
        value = db.ThresholdPlacement or "EDGE",
        callback = function(key) db.ThresholdPlacement = key; ApplySettings() end,
    })
    rowT:AddWidget(threshPlaceDrop, 0.5)
    manager:Register(threshPlaceDrop, "threshLabels")
    threshCard:AddRow(rowT, Theme.rowHeight)

    local rowTSep = GUIFrame:CreateRow(threshCard.content, Theme.rowHeightSeparator)
    local tSep = GUIFrame:CreateSeparator(rowTSep)
    rowTSep:AddWidget(tSep, 1)
    manager:Register(tSep, "all")
    threshCard:AddRow(rowTSep, Theme.rowHeightSeparator)

    local rowT2 = GUIFrame:CreateRow(threshCard.content, Theme.rowHeight)
    local stateFillCheck = GUIFrame:CreateCheckbox(rowT2, "State-Colored Fill", {
        value = db.StateColorFill == true,
        callback = function(checked) db.StateColorFill = checked; ApplySettings() end,
    })
    rowT2:AddWidget(stateFillCheck, 1)
    manager:Register(stateFillCheck, "all")
    threshCard:AddRow(rowT2, Theme.rowHeight)

    local rowTNote = GUIFrame:CreateRow(threshCard.content, 48)
    local tNote = GUIFrame:CreateText(rowTNote,
        KE:ColorTextByTheme("State-Colored Fill"),
        "Recolors the timer bar by chest state: |cff66ff66green|r while +3 is live, " ..
        "|cff4dccffblue|r once +3 is lost, |cffb059ccpurple|r once +2 is lost.\n" ..
        "Overrides the Bar Fill color (including at completion).",
        48, "hide")
    rowTNote:AddWidget(tNote, 1)
    manager:Register(tNote, "all")
    threshCard:AddRow(rowTNote, 48, 0)
    yOffset = threshCard:GetNextOffset()

    -- Card 5: Timer Format
    local fmtCard = GUIFrame:CreateCard(scrollChild, "Timer Format", yOffset)
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

    -- Card 6: Backdrop
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

    -- Card 7: Quality of Life
    local qolCard = GUIFrame:CreateCard(scrollChild, "Quality of Life", yOffset)
    manager:Register(qolCard, "all")
    local rowQ = GUIFrame:CreateRow(qolCard.content, Theme.rowHeight)
    local keyCheck = GUIFrame:CreateCheckbox(rowQ, "Auto-Insert Keystone", {
        value = db.AutoInsertKeystone ~= false,
        callback = function(checked) db.AutoInsertKeystone = checked end,
    })
    rowQ:AddWidget(keyCheck, 1 / 3)
    manager:Register(keyCheck, "all")
    local trackerCheck = GUIFrame:CreateCheckbox(rowQ, "Hide Blizzard Tracker", {
        value = db.HideBlizzardTracker ~= false,
        callback = function(checked)
            db.HideBlizzardTracker = checked
            local M = GetMPT()
            if M and M.ApplyTrackerVisibility then M:ApplyTrackerVisibility() end
        end,
    })
    rowQ:AddWidget(trackerCheck, 1 / 3)
    manager:Register(trackerCheck, "all")
    local chatCheck = GUIFrame:CreateCheckbox(rowQ, "Post Boss Splits to Chat", {
        value = db.ChatOutputSplits == true,
        callback = function(checked) db.ChatOutputSplits = checked end,
    })
    rowQ:AddWidget(chatCheck, 1 / 3)
    manager:Register(chatCheck, "all")
    qolCard:AddRow(rowQ, Theme.rowHeight)

    local rowQ2 = GUIFrame:CreateRow(qolCard.content, Theme.rowHeight)
    local keepCheck = GUIFrame:CreateCheckbox(rowQ2, "Keep Timer After Key Ends", {
        value = db.KeepSummaryAfterRun ~= false,
        callback = function(checked)
            db.KeepSummaryAfterRun = checked
            -- Unchecking while a persisted summary is up (outside the
            -- dungeon) clears it immediately; the run-state guards make
            -- this a no-op in every other situation.
            local M = GetMPT()
            if M and M.CheckForActiveRun then M:CheckForActiveRun() end
        end,
    })
    rowQ2:AddWidget(keepCheck, 1 / 3)
    manager:Register(keepCheck, "all")
    qolCard:AddRow(rowQ2, Theme.rowHeight)

    local qolNoteH = 48  -- "Note" header (~18px) + two wrapped text lines
    local rowQn = GUIFrame:CreateRow(qolCard.content, qolNoteH)
    local qolNote = GUIFrame:CreateText(rowQn,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("Keep Timer After Key Ends")
            .. " holds the final summary on screen after you leave the dungeon, until the next key begins.",
        qolNoteH, "hide")
    rowQn:AddWidget(qolNote, 1)
    manager:Register(qolNote, "all")
    qolCard:AddRow(rowQn, qolNoteH, 0)
    yOffset = qolCard:GetNextOffset()

    return yOffset
end

---------------------------------------------------------------------------------
-- Tab 2: Features — per-element toggles + behavior (forces, objectives/splits,
-- deaths, affixes & key). Colors/fonts for these live on the Display tab.
---------------------------------------------------------------------------------

BuildFeaturesTab = function(scrollChild, yOffset, db, manager)
    manager:SetCondition("forcesCustom", function()
        return db.Enabled ~= false and db.ShowForces ~= false and (db.ForcesFormat == "CUSTOM")
    end)

    -- Card 1: Forces (toggle + text format + placement + custom tokens)
    local forcesCard = GUIFrame:CreateCard(scrollChild, "Forces", yOffset)
    manager:Register(forcesCard, "all")
    local rowFo1 = GUIFrame:CreateRow(forcesCard.content, Theme.rowHeight)
    local showForcesCheck = GUIFrame:CreateCheckbox(rowFo1, "Show Forces Bar", {
        value = db.ShowForces ~= false,
        callback = function(checked)
            db.ShowForces = checked; ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    rowFo1:AddWidget(showForcesCheck, 1)
    manager:Register(showForcesCheck, "all")
    forcesCard:AddRow(rowFo1, Theme.rowHeight)

    local rowFo2 = GUIFrame:CreateRow(forcesCard.content, Theme.rowHeight)
    local forcesFmtDrop = GUIFrame:CreateDropdown(rowFo2, "Text Format", {
        options = FORCES_FORMAT_OPTIONS,
        value = db.ForcesFormat or "PERCENT",
        callback = function(key)
            db.ForcesFormat = key; ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    rowFo2:AddWidget(forcesFmtDrop, 1 / 3)
    manager:Register(forcesFmtDrop, "all")
    local placeDrop = GUIFrame:CreateDropdown(rowFo2, "Placement", {
        options = FORCES_PLACEMENT_OPTIONS,
        value = db.ForcesPlacement or "EDGE",
        callback = function(key) db.ForcesPlacement = key; ApplySettings() end,
    })
    rowFo2:AddWidget(placeDrop, 1 / 3)
    manager:Register(placeDrop, "all")
    local bracketDrop = GUIFrame:CreateDropdown(rowFo2, "Bracket Style", {
        options = FORCES_BRACKET_OPTIONS,
        value = db.ForcesBracketStyle or "NONE",
        callback = function(key) db.ForcesBracketStyle = key; ApplySettings() end,
    })
    rowFo2:AddWidget(bracketDrop, 1 / 3)
    manager:Register(bracketDrop, "all")
    forcesCard:AddRow(rowFo2, Theme.rowHeight)

    local rowFo3 = GUIFrame:CreateRow(forcesCard.content, Theme.rowHeight)
    local customBox = GUIFrame:CreateEditBox(rowFo3, "Custom Format", {
        value = db.ForcesCustomFormat or ":count:/:totalcount: :percent:",
        -- Empty string would render a blank forces label (the backend's `or`
        -- fallback only fires on nil) — store nil so the default token string wins.
        callback = function(text)
            db.ForcesCustomFormat = (text ~= "" and text) or nil
            ApplySettings()
        end,
    })
    rowFo3:AddWidget(customBox, 1)
    manager:Register(customBox, "forcesCustom")
    forcesCard:AddRow(rowFo3, Theme.rowHeight)

    local fNoteRow = GUIFrame:CreateRow(forcesCard.content, 78)
    local fNoteText = GUIFrame:CreateText(fNoteRow,
        KE:ColorTextByTheme("Tokens"),
        KE:ColorTextByTheme(":percent:") .. " current %  " ..
        KE:ColorTextByTheme(":count:") .. " current count\n" ..
        KE:ColorTextByTheme(":totalcount:") .. " total  " ..
        KE:ColorTextByTheme(":remainingcount:") .. " count remaining\n" ..
        KE:ColorTextByTheme(":remainingpercent:") .. " % remaining",
        78, "hide")
    fNoteRow:AddWidget(fNoteText, 1)
    manager:Register(fNoteText, "all")
    forcesCard:AddRow(fNoteRow, 78, 0)
    yOffset = forcesCard:GetNextOffset()

    -- Card 2: Objectives & Splits (boss list + clear times + PB toggles + fallback)
    local objCard = GUIFrame:CreateCard(scrollChild, "Objectives & Splits", yOffset)
    manager:Register(objCard, "all")
    local rowO1 = GUIFrame:CreateRow(objCard.content, Theme.rowHeight)
    local showObjCheck = GUIFrame:CreateCheckbox(rowO1, "Show Boss List", {
        value = db.ShowObjectives ~= false,
        callback = function(checked) db.ShowObjectives = checked; ApplySettings() end,
    })
    rowO1:AddWidget(showObjCheck, 0.5)
    manager:Register(showObjCheck, "all")
    local timesCheck = GUIFrame:CreateCheckbox(rowO1, "Show Clear Times", {
        value = db.ShowObjectiveTimes ~= false,
        callback = function(checked) db.ShowObjectiveTimes = checked; ApplySettings() end,
    })
    rowO1:AddWidget(timesCheck, 0.5)
    manager:Register(timesCheck, "all")
    objCard:AddRow(rowO1, Theme.rowHeight)

    local rowO2 = GUIFrame:CreateRow(objCard.content, Theme.rowHeight)
    local pbCheck = GUIFrame:CreateCheckbox(rowO2, "Show PB Delta", {
        value = db.ShowPBDelta ~= false,
        callback = function(checked) db.ShowPBDelta = checked; ApplySettings() end,
    })
    rowO2:AddWidget(pbCheck, 0.5)
    manager:Register(pbCheck, "all")
    local upcomingCheck = GUIFrame:CreateCheckbox(rowO2, "Show PB Targets", {
        value = db.ShowUpcomingPB ~= false,
        callback = function(checked) db.ShowUpcomingPB = checked; ApplySettings() end,
    })
    rowO2:AddWidget(upcomingCheck, 0.5)
    manager:Register(upcomingCheck, "all")
    objCard:AddRow(rowO2, Theme.rowHeight)

    -- PB fallback: which stored level the targets come from when the current
    -- key level has no record (the overall PB line tags a fallback source
    -- with its level, e.g. "PB 25:30 [11]").
    local rowO3 = GUIFrame:CreateRow(objCard.content, Theme.rowHeightLast)
    local fbDrop = GUIFrame:CreateDropdown(rowO3, "PB Fallback (no record at this level)", {
        options = PB_FALLBACK_OPTIONS,
        value = db.PBFallbackMode or "CLOSEST",
        callback = function(key)
            db.PBFallbackMode = key
            -- Re-resolve a live run against the new mode (LoadSplits re-reads
            -- pbRec/pbSourceLevel/bestOverall; no-op outside a run).
            local mod = KitnEssentials:GetModule("MythicPlusTimer")
            if mod then
                mod.run.pbRec = nil
                mod.run.pbSourceLevel = nil
                if mod.LoadSplits then mod:LoadSplits() end
                if mod.UpdateSplits then mod:UpdateSplits() end
            end
            ApplySettings()
        end,
    })
    rowO3:AddWidget(fbDrop, 0.5)
    manager:Register(fbDrop, "all")
    objCard:AddRow(rowO3, Theme.rowHeightLast, 0)
    yOffset = objCard:GetNextOffset()

    -- Card 3: Deaths (line + hover log)
    local deathsCard = GUIFrame:CreateCard(scrollChild, "Deaths", yOffset)
    manager:Register(deathsCard, "all")
    local rowD1 = GUIFrame:CreateRow(deathsCard.content, Theme.rowHeight)
    local showDeathsCheck = GUIFrame:CreateCheckbox(rowD1, "Show Deaths Line", {
        value = db.ShowDeaths ~= false,
        callback = function(checked) db.ShowDeaths = checked; ApplySettings() end,
    })
    rowD1:AddWidget(showDeathsCheck, 0.5)
    manager:Register(showDeathsCheck, "all")
    local tipCheck = GUIFrame:CreateCheckbox(rowD1, "Hover Death Log", {
        value = db.ShowDeathTooltip ~= false,
        callback = function(checked) db.ShowDeathTooltip = checked; ApplySettings() end,
    })
    rowD1:AddWidget(tipCheck, 0.5)
    manager:Register(tipCheck, "all")
    deathsCard:AddRow(rowD1, Theme.rowHeight)

    local dNoteRow = GUIFrame:CreateRow(deathsCard.content, 50)
    local dNoteText = GUIFrame:CreateText(dNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Count and time-penalty read from Blizzard's authoritative death tracker.\n" ..
        KE:ColorTextByTheme("-") .. " Hover the deaths line for a class-colored, timestamped log.",
        50, "hide")
    dNoteRow:AddWidget(dNoteText, 1)
    manager:Register(dNoteText, "all")
    deathsCard:AddRow(dNoteRow, 50, 0)
    yOffset = deathsCard:GetNextOffset()

    -- Card 4: Affixes & Key (display toggles; colors live on the Display tab)
    local affixCard = GUIFrame:CreateCard(scrollChild, "Affixes & Key", yOffset)
    manager:Register(affixCard, "all")
    local rowA1 = GUIFrame:CreateRow(affixCard.content, Theme.rowHeightLast)
    local affixCheck = GUIFrame:CreateCheckbox(rowA1, "Show Affixes", {
        value = db.ShowAffixes ~= false,
        callback = function(checked) db.ShowAffixes = checked; ApplySettings() end,
    })
    rowA1:AddWidget(affixCheck, 1 / 3)
    manager:Register(affixCheck, "all")
    local keyLvlCheck = GUIFrame:CreateCheckbox(rowA1, "Show Key Level", {
        value = db.ShowKeyLevel ~= false,
        callback = function(checked) db.ShowKeyLevel = checked; ApplySettings() end,
    })
    rowA1:AddWidget(keyLvlCheck, 1 / 3)
    manager:Register(keyLvlCheck, "all")
    local affixModeDrop = GUIFrame:CreateDropdown(rowA1, "Affix Display", {
        options = { { key = "TEXT", text = "Text" }, { key = "ICON", text = "Icons" } },
        value = db.AffixMode or "TEXT",
        callback = function(key) db.AffixMode = key; ApplySettings() end,
    })
    rowA1:AddWidget(affixModeDrop, 1 / 3)
    manager:Register(affixModeDrop, "all")
    affixCard:AddRow(rowA1, Theme.rowHeightLast, 0)
    yOffset = affixCard:GetNextOffset()

    return yOffset
end

---------------------------------------------------------------------------------
-- Tab 3: Display — every color picker (per-section cards), then every font
-- card (Default + Timer/Forces/Objectives/Deaths).
---------------------------------------------------------------------------------

BuildDisplayTab = function(scrollChild, yOffset, db, manager)
    manager:SetCondition("forcesBanded", function()
        return db.Enabled ~= false and db.ShowForces ~= false and db.ForcesBandedColors == true
    end)

    -- Card 1: Timer — Colors
    local timerColors = GUIFrame:CreateCard(scrollChild, "Timer — Colors", yOffset)
    manager:Register(timerColors, "all")
    AddColorRow(timerColors, db, manager, ApplySettings, {
        { "Timer (running)",  "TimerColor",        { 1, 1, 1 } },
        { "Timer (timed)",    "TimerSuccessColor", { 1, 0.83, 0.22 } },
        { "Timer (depleted)", "TimerExpiredColor", { 1, 0.16, 0.18 } },
    })
    AddColorRow(timerColors, db, manager, ApplySettings, {
        { "Bar Fill",        "BarColor",           { 0.56, 0.56, 0.56 } },
        { "Bar Background",  "BarBackgroundColor", { 0.031, 0.031, 0.031 } },
        { "Threshold Ticks", "TickColor",          { 1, 1, 1 } },
    }, true)
    yOffset = timerColors:GetNextOffset()

    -- Card 2: Forces — Colors
    local forcesColors = GUIFrame:CreateCard(scrollChild, "Forces — Colors", yOffset)
    manager:Register(forcesColors, "all")
    AddColorRow(forcesColors, db, manager, ApplySettings, {
        { "Forces Bar",      "ForcesColor",         { 0.73, 0.62, 0.13 } },
        { "Forces Complete", "ForcesCompleteColor", { 0.2, 0.82, 0.31 } },
        { "Forces Text",     "ForcesTextColor",     { 1, 1, 1 } },
    })

    local bandedRow = GUIFrame:CreateRow(forcesColors.content, Theme.rowHeight)
    local bandedCheck = GUIFrame:CreateCheckbox(bandedRow, "Banded Colors (by % bracket)", {
        value = db.ForcesBandedColors == true,
        callback = function(checked)
            db.ForcesBandedColors = checked; ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    bandedRow:AddWidget(bandedCheck, 1)
    manager:Register(bandedCheck, "all")
    forcesColors:AddRow(bandedRow, Theme.rowHeight)

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

    local bandRowA = GUIFrame:CreateRow(forcesColors.content, Theme.rowHeight)
    AddBandPicker(bandRowA, 1, 1 / 3)
    AddBandPicker(bandRowA, 2, 1 / 3)
    AddBandPicker(bandRowA, 3, 1 / 3)
    forcesColors:AddRow(bandRowA, Theme.rowHeight)

    local bandRowB = GUIFrame:CreateRow(forcesColors.content, Theme.rowHeightLast)
    AddBandPicker(bandRowB, 4, 0.5)
    AddBandPicker(bandRowB, 5, 0.5)
    forcesColors:AddRow(bandRowB, Theme.rowHeightLast, 0)
    yOffset = forcesColors:GetNextOffset()

    -- Card 3: Objectives & Splits — Colors
    local objColors = GUIFrame:CreateCard(scrollChild, "Objectives & Splits — Colors", yOffset)
    manager:Register(objColors, "all")
    AddColorRow(objColors, db, manager, ApplySettings, {
        { "Objective (pending)", "ObjectiveColor",     { 0.85, 0.85, 0.85 } },
        { "Objective (done)",    "ObjectiveDoneColor", { 0.2, 0.82, 0.31 } },
    })
    AddColorRow(objColors, db, manager, ApplySettings, {
        { "Split Ahead",  "SplitAheadColor",  { 0.25, 0.88, 0.82 } },
        { "Split Behind", "SplitBehindColor", { 1, 0.42, 0.42 } },
        { "PB Target",    "PBColor",          { 0.85, 0.79, 0.54 } },
    })

    local rowOp = GUIFrame:CreateRow(objColors.content, Theme.rowHeightLast)
    local opSlider = GUIFrame:CreateSlider(rowOp, "PB Opacity", {
        min = 0.1, max = 1.0, step = 0.05, value = db.PBOpacity or 1.0,
        callback = function(val) db.PBOpacity = val; ApplySettings() end,
    })
    rowOp:AddWidget(opSlider, 1)
    manager:Register(opSlider, "all")
    objColors:AddRow(rowOp, Theme.rowHeightLast, 0)
    yOffset = objColors:GetNextOffset()

    -- Card 4: Deaths — Colors
    local deathsColors = GUIFrame:CreateCard(scrollChild, "Deaths — Colors", yOffset)
    manager:Register(deathsColors, "all")
    AddColorRow(deathsColors, db, manager, ApplySettings, {
        { "Deaths Text",  "DeathsColor",       { 0.85, 0.85, 0.85 } },
        { "Time Penalty", "DeathPenaltyColor", { 1, 0.42, 0.42 } },
    }, true)
    yOffset = deathsColors:GetNextOffset()

    -- Card 5: Affixes & Key — Colors
    local affixColors = GUIFrame:CreateCard(scrollChild, "Affixes & Key — Colors", yOffset)
    manager:Register(affixColors, "all")
    AddColorRow(affixColors, db, manager, ApplySettings, {
        { "Affix Text", "AffixColor", { 0.69, 0.69, 0.69 } },
        { "Key Level",  "KeyColor",   { 0.69, 0.69, 0.69 } },
    }, true)
    yOffset = affixColors:GetNextOffset()

    -- Font cards: global default first, then one per HUD section.
    yOffset = AddFontCard(scrollChild, yOffset, db, manager, "", {
        title = "Default Font",
        note = "Applies to the affix line, key level, PB text, and threshold labels.",
    })
    yOffset = AddFontCard(scrollChild, yOffset, db, manager, "Timer", {
        title = "Timer — Font", maxSize = 48,
    })
    yOffset = AddFontCard(scrollChild, yOffset, db, manager, "Forces", {
        title = "Forces — Font",
    })
    yOffset = AddFontCard(scrollChild, yOffset, db, manager, "Objective", {
        title = "Objectives — Font",
    })
    yOffset = AddFontCard(scrollChild, yOffset, db, manager, "Deaths", {
        title = "Deaths — Font",
    })

    return yOffset
end

---------------------------------------------------------------------------------
-- Tab 4: Enemy Overlay — nameplate % / tooltip count subsystem (own position,
-- font, and colors; deliberately NOT merged into Display — it styles nameplate
-- text, not the HUD).
---------------------------------------------------------------------------------

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
        KE:ColorTextByTheme("-") .. " Optional per-pull % overlay on nameplates (Mythic+ only).\n",
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

GUIFrame:RegisterContent("MythicPlusTimer", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.MythicPlusTimer
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local _, newOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = {
            { id = "General",  label = "General" },
            { id = "Features", label = "Features" },
            { id = "Display",  label = "Display" },
            { id = "Overlay",  label = "Enemy Overlay" },
        },
        activeId = activeTab,
        onSwitch = function(newId) activeTab = newId end,
        fill = true,
    })
    yOffset = newOffset

    local manager = GUIFrame:CreateWidgetStateManager()

    if activeTab == "General" then
        yOffset = BuildGeneralTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Features" then
        yOffset = BuildFeaturesTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Display" then
        yOffset = BuildDisplayTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Overlay" then
        yOffset = BuildOverlayTab(scrollChild, yOffset, db, manager)
    end

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)
