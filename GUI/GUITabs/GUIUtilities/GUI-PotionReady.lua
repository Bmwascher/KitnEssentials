-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PotionReady.lua                                     ║
-- ║  GUI: Combat Potion Ready                                ║
-- ║  Purpose: Configuration panel for the PotionReady module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme
local LSM      = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert

GUIFrame:RegisterContent("PotionReady", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PotionReady
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}
    local customColorWidgets = {}

    local function ApplySettings()
        local mod = KitnEssentials and KitnEssentials:GetModule("PotionReady", true)
        if mod and mod.ApplySettings then mod:ApplySettings() end
        if mod and mod.CheckPotions  then mod:CheckPotions()  end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("PotionReady", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("PotionReady")
        else
            KitnEssentials:DisableModule("PotionReady")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        local isCustomColor = (db.ColorMode or "custom") == "custom"
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
        if mainEnabled then
            for _, widget in ipairs(customColorWidgets) do
                if widget.SetEnabled then widget:SetEnabled(isCustomColor) end
            end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Combat Potion Ready (Enable only)
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Potion Ready", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a,
        "Enable Combat Potion Ready", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Combat Potion Ready", "On", "Off"
    )
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Display & Visibility (Display Text + 3-column toggle row)
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display & Visibility", yOffset)
    table_insert(allWidgets, card2)

    -- Display text
    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local textBox = GUIFrame:CreateEditBox(row2a, "Display Text",
        db.Text or "Potion Ready",
        function(text)
            db.Text = text
            ApplySettings()
        end)
    row2a:AddWidget(textBox, 1)
    table_insert(allWidgets, textBox)
    card2:AddRow(row2a, 40)

    -- Three visibility toggles on one row (1/3 width each)
    local row2b = GUIFrame:CreateRow(card2.content, 36)
    local instanceCheck = GUIFrame:CreateCheckbox(row2b,
        "Instances Only", db.InstanceOnly ~= false,
        function(checked)
            db.InstanceOnly = checked
            ApplySettings()
        end
    )
    row2b:AddWidget(instanceCheck, 1/3)
    table_insert(allWidgets, instanceCheck)

    local combatCheck = GUIFrame:CreateCheckbox(row2b,
        "In Combat Only", db.CombatOnly,
        function(checked)
            db.CombatOnly = checked
            ApplySettings()
        end
    )
    row2b:AddWidget(combatCheck, 1/3)
    table_insert(allWidgets, combatCheck)

    local healerCheck = GUIFrame:CreateCheckbox(row2b,
        "Hide for Healers", db.DisableOnHealer,
        function(checked)
            db.DisableOnHealer = checked
            ApplySettings()
        end
    )
    row2b:AddWidget(healerCheck, 1/3)
    table_insert(allWidgets, healerCheck)
    card2:AddRow(row2b, 36)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Position Settings
    ---------------------------------------------------------------------------------
    local card3, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint  = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset    = "XOffset",
            yOffset    = "YOffset",
            strata     = "Strata",
        },
        showAnchorFrameType = true,
        showStrata          = true,
        onChangeCallback    = ApplySettings,
    })

    if card3.positionWidgets then
        for _, widget in ipairs(card3.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card3)
    yOffset = newOffset

    ---------------------------------------------------------------------------------
    -- Card 4: Font Settings
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card4)

    -- Font face and size on one row
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList,
        db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row4a, "Font Size", 8, 72, 1,
        db.FontSize or 20, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4a, 40)

    -- Outline dropdown
    local row4b = GUIFrame:CreateRow(card4.content, 37)
    local outlineList = {
        { key = "NONE",         text = "None"  },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft"  },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row4b, "Outline", outlineList,
        db.FontOutline or "OUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row4b:AddWidget(outlineDropdown, 1)
    table_insert(allWidgets, outlineDropdown)
    card4:AddRow(row4b, 37)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 5: Colors
    ---------------------------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card5)

    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local colorModeDropdown = GUIFrame:CreateDropdown(row5a, "Color Mode", KE.ColorModeOptions,
        db.ColorMode or "custom", 70,
        function(key)
            db.ColorMode = key
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row5a:AddWidget(colorModeDropdown, 0.5)
    table_insert(allWidgets, colorModeDropdown)

    local colorPicker = GUIFrame:CreateColorPicker(row5a, "Custom Color",
        db.Color or { 0, 1, 0, 1 },
        function(r, g, b, a2)
            db.Color = { r, g, b, a2 }
            ApplySettings()
        end)
    row5a:AddWidget(colorPicker, 0.5)
    table_insert(allWidgets, colorPicker)
    table_insert(customColorWidgets, colorPicker)
    card5:AddRow(row5a, 40)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
