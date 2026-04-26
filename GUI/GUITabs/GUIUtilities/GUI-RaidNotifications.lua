-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-RaidNotifications.lua                               ║
-- ║  GUI: Raid Notifications                                 ║
-- ║  Purpose: Configuration panel for the RaidNotifications  ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert

GUIFrame:RegisterContent("RaidNotifications", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.RaidNotifications
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}

    local function ApplySettings()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("RaidNotifications", true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("RaidNotifications", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("RaidNotifications")
        else
            KitnEssentials:DisableModule("RaidNotifications")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Raid Notifications (Enable)
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Raid Notifications", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Raid Notifications", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Raid Notifications", "On", "Off"
    )
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Alert Settings
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Alert Settings", yOffset)
    table_insert(allWidgets, card2)

    local a = Theme.accent
    local accentDash = string.format("|cff%02x%02x%02x—|r", a[1]*255, a[2]*255, a[3]*255)

    -- Row: Gateway + Reset Boss + Loot Boss toggles
    local row2a = GUIFrame:CreateRow(card2.content, 36)
    local grey = "|cff888888"

    local gatewayCheck = GUIFrame:CreateCheckbox(row2a, "Gateway  " .. grey .. "- Shows when Demonic Gateway is usable.|r", db.GatewayEnabled ~= false,
        function(checked)
            db.GatewayEnabled = checked
            ApplySettings()
        end)
    row2a:AddWidget(gatewayCheck, 1)
    table_insert(allWidgets, gatewayCheck)
    card2:AddRow(row2a, 36)

    local row2a2 = GUIFrame:CreateRow(card2.content, 36)
    local resetBossCheck = GUIFrame:CreateCheckbox(row2a2, "Reset Boss  " .. grey .. "- Reminder when lust debuff is active between pulls.|r", db.ResetBossEnabled ~= false,
        function(checked)
            db.ResetBossEnabled = checked
            ApplySettings()
        end)
    row2a2:AddWidget(resetBossCheck, 1)
    table_insert(allWidgets, resetBossCheck)
    card2:AddRow(row2a2, 36)

    local row2a3 = GUIFrame:CreateRow(card2.content, 36)
    local lootBossCheck = GUIFrame:CreateCheckbox(row2a3, "Loot Boss  " .. grey .. "- Reminder to loot after a boss kill.|r", db.LootBossEnabled ~= false,
        function(checked)
            db.LootBossEnabled = checked
            ApplySettings()
        end)
    row2a3:AddWidget(lootBossCheck, 1)
    table_insert(allWidgets, lootBossCheck)
    card2:AddRow(row2a3, 36)

    -- Row: Show Icons + Alert Duration
    local row2b = GUIFrame:CreateRow(card2.content, 40)
    local iconToggle = GUIFrame:CreateCheckbox(row2b, "Show Icons", db.ShowIcons ~= false,
        function(checked)
            db.ShowIcons = checked
            ApplySettings()
        end)
    row2b:AddWidget(iconToggle, 0.35)
    table_insert(allWidgets, iconToggle)

    local durationSlider = GUIFrame:CreateSlider(row2b, "Alert Duration", 5, 120, 1, db.AlertDuration or 40, 60,
        function(val)
            db.AlertDuration = val
        end)
    row2b:AddWidget(durationSlider, 0.65)
    table_insert(allWidgets, durationSlider)
    card2:AddRow(row2b, 40)

    card2:AddLabel(accentDash .. " |cff888888Duration applies to Reset Boss and Loot Boss alerts.|r")

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Position Settings
    ---------------------------------------------------------------------------------
    local card3, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
        showPixelSnap = true,
        onChangeCallback = ApplySettings,
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

    local fontSizeSlider = GUIFrame:CreateSlider(row4a, "Font Size", 8, 72, 1, db.FontSize or 16, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4a, 40)

    -- Font Outline
    local row4b = GUIFrame:CreateRow(card4.content, 37)
    local outlineList = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE", text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row4b, "Outline", outlineList, db.FontOutline or "SOFTOUTLINE", 45,
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

    local customColorWidgets = {}

    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local colorModeDropdown = GUIFrame:CreateDropdown(row5a, "Color Mode", KE.ColorModeOptions,
        db.ColorMode or "custom", 70,
        function(key)
            db.ColorMode = key
            ApplySettings()
            local isCustom = key == "custom"
            for _, w in ipairs(customColorWidgets) do
                if w.SetEnabled then w:SetEnabled(isCustom) end
            end
        end)
    row5a:AddWidget(colorModeDropdown, 0.5)
    table_insert(allWidgets, colorModeDropdown)

    local colorPicker = GUIFrame:CreateColorPicker(row5a, "Custom Color", db.Color or { 0.969, 0.027, 0.945, 1 },
        function(r, g, b, a2)
            db.Color = { r, g, b, a2 }
            ApplySettings()
        end)
    row5a:AddWidget(colorPicker, 0.5)
    table_insert(allWidgets, colorPicker)
    table_insert(customColorWidgets, colorPicker)
    card5:AddRow(row5a, 40)

    -- Set initial custom color widget state
    if (db.ColorMode or "custom") ~= "custom" then
        for _, w in ipairs(customColorWidgets) do
            if w.SetEnabled then w:SetEnabled(false) end
        end
    end

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
