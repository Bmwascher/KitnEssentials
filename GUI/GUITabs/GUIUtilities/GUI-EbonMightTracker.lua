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
    -- Card 1: Ebon Might Tracker (Enable + Options)
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

    card1:AddLabel("|cff888888Displays Ebon Might duration with crit and duped cast detection. Augmentation Evoker only.|r")

    -- Mode dropdown
    local row1b = GUIFrame:CreateRow(card1.content, 40)
    local modeList = {
        { key = "icon", text = "Icon + Countdown" },
        { key = "text", text = "Border + State Label" },
    }
    local modeDropdown = GUIFrame:CreateDropdown(row1b, "Mode", modeList, db.Mode or "icon", 30,
        function(key)
            db.Mode = key
            ApplySettings()
        end)
    row1b:AddWidget(modeDropdown, 1)
    table_insert(allWidgets, modeDropdown)
    card1:AddRow(row1b, 40)

    -- Only Show on Crit + Combat Only
    local row1c = GUIFrame:CreateRow(card1.content, 36)
    local onlyCritCheck = GUIFrame:CreateCheckbox(row1c, "Only Show on Crit", db.OnlyShowCrit == true,
        function(checked)
            db.OnlyShowCrit = checked
            ApplySettings()
        end)
    row1c:AddWidget(onlyCritCheck, 0.5)
    table_insert(allWidgets, onlyCritCheck)

    local combatCheck = GUIFrame:CreateCheckbox(row1c, "Combat Only", db.CombatOnly == true,
        function(checked)
            db.CombatOnly = checked
            ApplySettings()
        end)
    row1c:AddWidget(combatCheck, 0.5)
    table_insert(allWidgets, combatCheck)
    card1:AddRow(row1c, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Position Settings
    ---------------------------------------------------------------------------------
    local card2, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
    if card2.positionWidgets then
        for _, widget in ipairs(card2.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card2)
    yOffset = newOffset

    ---------------------------------------------------------------------------------
    -- Card 3: Font Settings
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card3)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    -- Font Face + Font Size
    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row3a, "Font", fontList, db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row3a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row3a, "Font Size", 8, 72, 1, db.FontSize or 22, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row3a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card3:AddRow(row3a, 40)

    -- Outline + Icon Size
    local row3b = GUIFrame:CreateRow(card3.content, 40)
    local outlineList = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE", text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row3b, "Outline", outlineList, db.FontOutline or "OUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row3b:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)

    local iconSizeSlider = GUIFrame:CreateSlider(row3b, "Icon Size", 16, 128, 1, db.IconSize or 48, 60,
        function(val)
            db.IconSize = val
            ApplySettings()
        end)
    row3b:AddWidget(iconSizeSlider, 0.5)
    table_insert(allWidgets, iconSizeSlider)
    card3:AddRow(row3b, 40)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Colors
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card4)

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local basePicker = GUIFrame:CreateColorPicker(row4a, "Base Color", db.BaseColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.BaseColor = { r, g, b, a }
            ApplySettings()
        end)
    row4a:AddWidget(basePicker, 1)
    table_insert(allWidgets, basePicker)
    card4:AddRow(row4a, 40)

    local row4b = GUIFrame:CreateRow(card4.content, 40)
    local critPicker = GUIFrame:CreateColorPicker(row4b, "Crit Color", db.CritColor or { 1, 0, 1, 1 },
        function(r, g, b, a)
            db.CritColor = { r, g, b, a }
            ApplySettings()
        end)
    row4b:AddWidget(critPicker, 1)
    table_insert(allWidgets, critPicker)
    card4:AddRow(row4b, 40)

    local row4c = GUIFrame:CreateRow(card4.content, 40)
    local dupePicker = GUIFrame:CreateColorPicker(row4c, "Dupe Color", db.DupeColor or { 1, 0.5, 0, 1 },
        function(r, g, b, a)
            db.DupeColor = { r, g, b, a }
            ApplySettings()
        end)
    row4c:AddWidget(dupePicker, 1)
    table_insert(allWidgets, dupePicker)
    card4:AddRow(row4c, 40)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    return yOffset
end)
