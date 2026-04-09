-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-EnemyCounter.lua                                    ║
-- ║  GUI: Enemy Counter                                      ║
-- ║  Purpose: Configuration panel for the EnemyCounter       ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme
local LSM      = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert

GUIFrame:RegisterContent("EnemyCounter", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Dungeons.EnemyCounter
    if not db then return yOffset end

    local allWidgets = {}
    local customColorWidgets = {}

    local function ApplySettings()
        local mod = KitnEssentials and KitnEssentials:GetModule("EnemyCounter", true)
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("EnemyCounter", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("EnemyCounter")
        else
            KitnEssentials:DisableModule("EnemyCounter")
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
    -- Card 1: Enable + Text
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Enemy Counter", yOffset)

    -- Enable toggle
    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a,
        "Enable Enemy Counter", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Enemy Counter", "On", "Off"
    )
    row1a:AddWidget(enableCheck, 0.5)

    local combatCheck = GUIFrame:CreateCheckbox(row1a,
        "Combat Only", db.CombatOnly,
        function(checked)
            db.CombatOnly = checked
            ApplySettings()
        end
    )
    row1a:AddWidget(combatCheck, 0.5)
    table_insert(allWidgets, combatCheck)
    card1:AddRow(row1a, 36)

    -- Separator
    local row1sep = GUIFrame:CreateRow(card1.content, 8)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    table_insert(allWidgets, sep1)
    card1:AddRow(row1sep, 8)

    -- Show prefix toggle + prefix text
    local row1b = GUIFrame:CreateRow(card1.content, 40)
    local prefixCheck = GUIFrame:CreateCheckbox(row1b,
        "Show Prefix", db.ShowPrefix ~= false,
        function(checked)
            db.ShowPrefix = checked
            ApplySettings()
        end
    )
    row1b:AddWidget(prefixCheck, 0.35)
    table_insert(allWidgets, prefixCheck)

    local prefixBox = GUIFrame:CreateEditBox(row1b, "Prefix Text",
        db.Prefix or "Enemies:",
        function(text)
            db.Prefix = text
            ApplySettings()
        end)
    row1b:AddWidget(prefixBox, 0.65)
    table_insert(allWidgets, prefixBox)
    card1:AddRow(row1b, 40)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Position Settings
    ---------------------------------------------------------------------------------
    local card2, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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

    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row3a, "Font", fontList,
        db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row3a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row3a, "Font Size", 8, 72, 1,
        db.FontSize or 20, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row3a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card3:AddRow(row3a, 40)

    local row3b = GUIFrame:CreateRow(card3.content, 37)
    local outlineList = {
        { key = "NONE",         text = "None"  },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft"  },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row3b, "Outline", outlineList,
        db.FontOutline or "OUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row3b:AddWidget(outlineDropdown, 1)
    table_insert(allWidgets, outlineDropdown)
    card3:AddRow(row3b, 37)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Colors
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card4)

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local colorModeDropdown = GUIFrame:CreateDropdown(row4a, "Color Mode", KE.ColorModeOptions,
        db.ColorMode or "custom", 70,
        function(key)
            db.ColorMode = key
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row4a:AddWidget(colorModeDropdown, 0.5)
    table_insert(allWidgets, colorModeDropdown)

    local colorPicker = GUIFrame:CreateColorPicker(row4a, "Custom Color",
        db.Color or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.Color = { r, g, b, a }
            ApplySettings()
        end)
    row4a:AddWidget(colorPicker, 0.5)
    table_insert(allWidgets, colorPicker)
    table_insert(customColorWidgets, colorPicker)
    card4:AddRow(row4a, 40)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
