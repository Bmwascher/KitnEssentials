-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-EbonMightTracker.lua                                ║
-- ║  GUI: Ebon Might Tracker                                 ║
-- ║  Purpose: Configuration panel for the EbonMightTracker   ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert
local ipairs = ipairs
local pairs = pairs

GUIFrame:RegisterContent("EbonMightTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.EbonMightTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local EMT = KitnEssentials and KitnEssentials:GetModule("EbonMightTracker", true)
    local allWidgets = {}

    local function ApplySettings()
        if EMT and EMT.ApplySettings then EMT:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("EbonMightTracker", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("EbonMightTracker")
        else
            KitnEssentials:DisableModule("EbonMightTracker")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Ebon Might Tracker (Enable + Note)
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Ebon Might Tracker", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Ebon Might Tracker", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Ebon Might Tracker", "On", "Off"
    )
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, 36)

    -- Note
    local noteHeight = 65
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Augmentation Evoker only.\n"
            .. KE:ColorTextByTheme("-") .. " Tracks your Ebon Might duration with crit\n"
            .. "   and duped cast detection (Chronowarden + Double-time).",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Display Settings (Mode + Toggles)
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    table_insert(allWidgets, card2)

    -- Mode dropdown
    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local modeList = {
        { key = "icon", text = "Icon + Countdown" },
        { key = "text", text = "Border + State Label" },
    }
    local modeDropdown = GUIFrame:CreateDropdown(row2a, "Mode", modeList, db.Mode or "icon", 30,
        function(key)
            db.Mode = key
            ApplySettings()
        end)
    row2a:AddWidget(modeDropdown, 1)
    table_insert(allWidgets, modeDropdown)
    card2:AddRow(row2a, 40)

    -- Only Show on Crit + Combat Only
    local row2b = GUIFrame:CreateRow(card2.content, 36)
    local onlyCritCheck = GUIFrame:CreateCheckbox(row2b, "Only Show on Crit", db.OnlyShowCrit == true,
        function(checked)
            db.OnlyShowCrit = checked
            ApplySettings()
        end)
    row2b:AddWidget(onlyCritCheck, 0.5)
    table_insert(allWidgets, onlyCritCheck)

    local combatCheck = GUIFrame:CreateCheckbox(row2b, "Combat Only", db.CombatOnly == true,
        function(checked)
            db.CombatOnly = checked
            ApplySettings()
        end)
    row2b:AddWidget(combatCheck, 0.5)
    table_insert(allWidgets, combatCheck)
    card2:AddRow(row2b, 36)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Position Settings
    ---------------------------------------------------------------------------------
    local card3pos, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if card3pos.positionWidgets then
        for _, widget in ipairs(card3pos.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card3pos)
    yOffset = newOffset

    ---------------------------------------------------------------------------------
    -- Card 4: Font Settings
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card4)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    -- Font Face + Font Size
    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList, db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row4a, "Font Size", 8, 72, 1, db.FontSize or 22, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4a, 40)

    -- Outline + Icon Size
    local row4b = GUIFrame:CreateRow(card4.content, 40)
    local outlineList = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE", text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row4b, "Outline", outlineList, db.FontOutline or "OUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row4b:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)

    local iconSizeSlider = GUIFrame:CreateSlider(row4b, "Icon Size", 16, 128, 1, db.IconSize or 48, 60,
        function(val)
            db.IconSize = val
            ApplySettings()
        end)
    row4b:AddWidget(iconSizeSlider, 0.5)
    table_insert(allWidgets, iconSizeSlider)
    card4:AddRow(row4b, 40)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 5: Colors
    ---------------------------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card5)

    -- All three pickers in a single row (1/3 width each)
    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local basePicker = GUIFrame:CreateColorPicker(row5a, "Base Color", db.BaseColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.BaseColor = { r, g, b, a }
            ApplySettings()
        end)
    row5a:AddWidget(basePicker, 0.33)
    table_insert(allWidgets, basePicker)

    local critPicker = GUIFrame:CreateColorPicker(row5a, "Crit Color", db.CritColor or { 1, 0, 1, 1 },
        function(r, g, b, a)
            db.CritColor = { r, g, b, a }
            ApplySettings()
        end)
    row5a:AddWidget(critPicker, 0.33)
    table_insert(allWidgets, critPicker)

    local dupePicker = GUIFrame:CreateColorPicker(row5a, "Dupe Color", db.DupeColor or { 1, 0.5, 0, 1 },
        function(r, g, b, a)
            db.DupeColor = { r, g, b, a }
            ApplySettings()
        end)
    row5a:AddWidget(dupePicker, 0.34)
    table_insert(allWidgets, dupePicker)
    card5:AddRow(row5a, 40)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    return yOffset
end)
