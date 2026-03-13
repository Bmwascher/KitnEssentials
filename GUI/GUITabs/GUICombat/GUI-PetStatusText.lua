-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert

GUIFrame:RegisterContent("PetStatusText", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PetStatusText
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}

    local function ApplySettings()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("PetStatusText", true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("PetStatusText", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("PetStatusText")
        else
            KitnEssentials:DisableModule("PetStatusText")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false

        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Pet Status Texts (Enable)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Pet Status Texts", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Pet Status Texts", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Pet Status Texts", "On", "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
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

    ----------------------------------------------------------------
    -- Card 3: Font Settings
    ----------------------------------------------------------------
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

    local fontSizeSlider = GUIFrame:CreateSlider(row3a, "Font Size", 8, 72, 1, db.FontSize or 14, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row3a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card3:AddRow(row3a, 40)

    -- Font Outline
    local row3b = GUIFrame:CreateRow(card3.content, 37)
    local outlineList = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE", text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row3b, "Outline", outlineList, db.FontOutline or "SOFTOUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row3b:AddWidget(outlineDropdown, 1)
    table_insert(allWidgets, outlineDropdown)
    card3:AddRow(row3b, 37)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: State Settings (Missing, Dead, Passive)
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "State Settings", yOffset)
    table_insert(allWidgets, card4)

    -- Pet Missing: Text + Color
    local row4a = GUIFrame:CreateRow(card4.content, 38)
    local petMissingInput = GUIFrame:CreateEditBox(row4a, "Pet Missing Text", db.PetMissing or "PET MISSING",
        function(val)
            db.PetMissing = val
            ApplySettings()
        end)
    row4a:AddWidget(petMissingInput, 0.5)
    table_insert(allWidgets, petMissingInput)

    local missingColorPicker = GUIFrame:CreateColorPicker(row4a, "Missing Color",
        db.MissingColor or { 1, 0.82, 0, 1 },
        function(r, g, b, a)
            db.MissingColor = { r, g, b, a }
            ApplySettings()
        end)
    row4a:AddWidget(missingColorPicker, 0.5)
    table_insert(allWidgets, missingColorPicker)
    card4:AddRow(row4a, 38)

    -- Pet Dead: Text + Color
    local row4b = GUIFrame:CreateRow(card4.content, 38)
    local petDeadInput = GUIFrame:CreateEditBox(row4b, "Pet Dead Text", db.PetDead or "PET DEAD",
        function(val)
            db.PetDead = val
            ApplySettings()
        end)
    row4b:AddWidget(petDeadInput, 0.5)
    table_insert(allWidgets, petDeadInput)

    local deadColorPicker = GUIFrame:CreateColorPicker(row4b, "Dead Color",
        db.DeadColor or { 1, 0.2, 0.2, 1 },
        function(r, g, b, a)
            db.DeadColor = { r, g, b, a }
            ApplySettings()
        end)
    row4b:AddWidget(deadColorPicker, 0.5)
    table_insert(allWidgets, deadColorPicker)
    card4:AddRow(row4b, 38)

    -- Pet Passive: Text + Color
    local row4c = GUIFrame:CreateRow(card4.content, 38)
    local petPassiveInput = GUIFrame:CreateEditBox(row4c, "Pet Passive Text", db.PetPassive or "PET PASSIVE",
        function(val)
            db.PetPassive = val
            ApplySettings()
        end)
    row4c:AddWidget(petPassiveInput, 0.5)
    table_insert(allWidgets, petPassiveInput)

    local passiveColorPicker = GUIFrame:CreateColorPicker(row4c, "Passive Color",
        db.PassiveColor or { 0.3, 0.7, 1, 1 },
        function(r, g, b, a)
            db.PassiveColor = { r, g, b, a }
            ApplySettings()
        end)
    row4c:AddWidget(passiveColorPicker, 0.5)
    table_insert(allWidgets, passiveColorPicker)
    card4:AddRow(row4c, 38)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
