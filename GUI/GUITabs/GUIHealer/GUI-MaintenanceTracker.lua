-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-MaintenanceTracker.lua                              ║
-- ║  GUI: Maintenance Tracker                                ║
-- ║  Purpose: Configuration panel for the MaintenanceTracker ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local pairs = pairs

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("MaintenanceTracker", true)
end

GUIFrame:RegisterContent("MaintenanceTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.MaintenanceTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available.")
        return errorCard:GetNextOffset()
    end

    -- Class-gate notice: the module silently does nothing on unsupported classes.
    local mtGate = GetModule()
    if mtGate and mtGate.isSupported == false then
        local noticeCard = GUIFrame:CreateCard(scrollChild, "Maintenance Tracker", yOffset)
        noticeCard:AddLabel(
            "Maintenance Tracker supports |cffffd100Discipline Priest|r, " ..
            "|cffffd100Mistweaver Monk|r, |cffffd100Restoration Druid|r, " ..
            "|cffffd100Restoration Shaman|r, and |cffffd100Preservation Evoker|r.\n\n" ..
            "Your current class does not have a tracked maintenance buff, so the " ..
            "tracker is inactive on this character. Settings are saved to your profile " ..
            "and will take effect automatically if you switch to a supported healer spec."
        )
        return noticeCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        local mod = GetModule()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function UpdateAllWidgetStates()
        manager:UpdateAll(db.Enabled == true)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Maintenance Tracker", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if GetModule() then
            if checked then KitnEssentials:EnableModule("MaintenanceTracker")
            else KitnEssentials:DisableModule("MaintenanceTracker") end
        end
        KE:Print("Maintenance Tracker: " ..
            (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    card1:AddLabel(
        "Shows an icon per tracked maintenance buff with the " ..
        KE:ColorTextByTheme("count") .. " of affected group members and the " ..
        KE:ColorTextByTheme("lowest remaining duration") .. " across all targets. Tracks " ..
        "|cff99e6ffAtonement|r for Discipline Priest, " ..
        "|cff80ff80Renewing Mist|r + |cff80ff80Enveloping Mist|r for Mistweaver Monk, " ..
        "|cffff7d0aRejuvenation|r (incl. Germination) for Restoration Druid, " ..
        "|cff0070deRiptide|r for Restoration Shaman, and " ..
        "|cff33937fEcho|r for Preservation Evoker. " ..
        "Multi-spell specs render icons side-by-side using the layout settings below.")

    yOffset = card1:GetNextOffset()

    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Position
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = function()
            local mod = GetModule()
            if mod then mod:ApplyPosition() end
        end,
    })
    manager:Register(posCard, "all")
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Display
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card3, "all")

    -- Icon Size
    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(row3a, "Icon Size", {
        min = 24, max = 120, step = 1,
        value = db.IconSize or 40,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row3a:AddWidget(sizeSlider, 1)
    manager:Register(sizeSlider, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local rowSep3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3 = GUIFrame:CreateSeparator(rowSep3)
    rowSep3:AddWidget(sep3, 1)
    card3:AddRow(rowSep3, Theme.rowHeightSeparator)

    -- Count Font Size + Count Color (paired)
    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local countSizeSlider = GUIFrame:CreateSlider(row3b, "Count Font Size", {
        min = 8, max = 48, step = 1,
        value = db.CountFontSize or 24,
        callback = function(val) db.CountFontSize = val; ApplySettings() end,
    })
    row3b:AddWidget(countSizeSlider, 0.5)
    manager:Register(countSizeSlider, "all")

    local countColorPicker = GUIFrame:CreateColorPicker(row3b, "Count Color", {
        color = db.CountColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.CountColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row3b:AddWidget(countColorPicker, 0.5)
    manager:Register(countColorPicker, "all")
    card3:AddRow(row3b, Theme.rowHeight)

    -- Show Lowest Duration + Duration Font Size
    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local showLowestCheck = GUIFrame:CreateCheckbox(row3c, "Show Lowest Duration", {
        value = db.ShowLowest ~= false,
        callback = function(checked) db.ShowLowest = checked; ApplySettings() end,
    })
    row3c:AddWidget(showLowestCheck, 0.5)
    manager:Register(showLowestCheck, "all")

    local lowestSizeSlider = GUIFrame:CreateSlider(row3c, "Duration Font Size", {
        min = 8, max = 32, step = 1,
        value = db.LowestFontSize or 14,
        callback = function(val) db.LowestFontSize = val; ApplySettings() end,
    })
    row3c:AddWidget(lowestSizeSlider, 0.5)
    manager:Register(lowestSizeSlider, "all")
    card3:AddRow(row3c, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Font (face + outline only; count/duration sizes live
    -- in the Display card)
    ----------------------------------------------------------------
    local fontCard = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    manager:Register(fontCard, "all")

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Expressway"] = "Expressway"
    end

    local rowFont = GUIFrame:CreateRow(fontCard.content, Theme.rowHeightLast)
    local fontFaceDropdown = GUIFrame:CreateDropdown(rowFont, "Font", {
        options = KE:AddFollowGlobalFont(fontList),
        value = db.FontFace or KE.FONT_FOLLOW_GLOBAL,
        searchable = true,
        isFontPreview = true,
        callback = function(key) db.FontFace = KE:StoredFontFace(key); ApplySettings() end,
    })
    rowFont:AddWidget(fontFaceDropdown, 0.5)
    manager:Register(fontFaceDropdown, "all")

    local outlineDropdown = GUIFrame:CreateDropdown(rowFont, "Outline", {
        options = KE:GetFontOutlineOptions(),
        value = KE:NormalizeFontOutline(db.FontOutline or "OUTLINE"),
        callback = function(key) db.FontOutline = key; ApplySettings() end,
    })
    rowFont:AddWidget(outlineDropdown, 0.5)
    manager:Register(outlineDropdown, "all")
    fontCard:AddRow(rowFont, Theme.rowHeightLast, 0)

    yOffset = fontCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Multi-Spell Layout
    -- Only visually meaningful for specs with more than one tracked
    -- spell (currently just Mistweaver). Settings are saved regardless
    -- and apply automatically when on a multi-spell spec.
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Multi-Spell Layout", yOffset)
    manager:Register(card4, "all")

    local GROWTH_OPTIONS = {
        { key = "RIGHT", text = "Right" },
        { key = "LEFT",  text = "Left"  },
        { key = "UP",    text = "Up"    },
        { key = "DOWN",  text = "Down"  },
    }

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local growthDropdown = GUIFrame:CreateDropdown(row4a, "Growth Direction", {
        options  = GROWTH_OPTIONS,
        value    = db.GrowthDirection or "RIGHT",
        callback = function(key) db.GrowthDirection = key; ApplySettings() end,
    })
    row4a:AddWidget(growthDropdown, 0.5)
    manager:Register(growthDropdown, "all")

    local spacingSlider = GUIFrame:CreateSlider(row4a, "Spacing (px)", {
        min = 0, max = 40, step = 1,
        value = db.Spacing or 4,
        callback = function(val) db.Spacing = val; ApplySettings() end,
    })
    row4a:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card4:AddRow(row4a, Theme.rowHeight, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Duration Colors
    -- The lowest-remaining-duration text changes color as it counts
    -- down. Three bands keyed off two thresholds: <= Low, <= Mid, > Mid.
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Duration Colors", yOffset)
    manager:Register(card5, "all")

    -- Threshold sliders
    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local lowThrSlider = GUIFrame:CreateSlider(row5a, "Low Threshold (sec)", {
        min = 1, max = 10, step = 0.5,
        value = db.LowThreshold or 3,
        callback = function(val) db.LowThreshold = val; ApplySettings() end,
    })
    row5a:AddWidget(lowThrSlider, 0.5)
    manager:Register(lowThrSlider, "all")

    local midThrSlider = GUIFrame:CreateSlider(row5a, "Mid Threshold (sec)", {
        min = 2, max = 20, step = 0.5,
        value = db.MidThreshold or 6,
        callback = function(val) db.MidThreshold = val; ApplySettings() end,
    })
    row5a:AddWidget(midThrSlider, 0.5)
    manager:Register(midThrSlider, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local rowSep5 = GUIFrame:CreateRow(card5.content, Theme.rowHeightSeparator)
    local sep5 = GUIFrame:CreateSeparator(rowSep5)
    rowSep5:AddWidget(sep5, 1)
    card5:AddRow(rowSep5, Theme.rowHeightSeparator)

    -- Color pickers: Low / Mid / High
    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local lowColorPicker = GUIFrame:CreateColorPicker(row5b, "Low (urgent)", {
        color = db.LowDurationColor or { 1, 0.3, 0.3, 1 },
        callback = function(r, g, b, a)
            db.LowDurationColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(lowColorPicker, 0.34)
    manager:Register(lowColorPicker, "all")

    local midColorPicker = GUIFrame:CreateColorPicker(row5b, "Mid (refresh soon)", {
        color = db.MidDurationColor or { 1, 0.75, 0.2, 1 },
        callback = function(r, g, b, a)
            db.MidDurationColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(midColorPicker, 0.33)
    manager:Register(midColorPicker, "all")

    local highColorPicker = GUIFrame:CreateColorPicker(row5b, "High (safe)", {
        color = db.HighDurationColor or { 1, 0.85, 0.4, 1 },
        callback = function(r, g, b, a)
            db.HighDurationColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(highColorPicker, 0.33)
    manager:Register(highColorPicker, "all")
    card5:AddRow(row5b, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    UpdateAllWidgetStates()

    return yOffset
end)
