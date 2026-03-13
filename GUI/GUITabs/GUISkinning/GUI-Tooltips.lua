-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

-- Localization
local table_insert = table.insert
local string_format = string.format

-- Helper to color text with theme accent
local function AccentText(text)
    local a = KE.Theme.accent
    return string_format("|cff%02x%02x%02x%s|r", a[1] * 255, a[2] * 255, a[3] * 255, text)
end

-- Helper to get Tooltips module
local function GetTooltipsModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinTooltips", true)
    end
    return nil
end

-- Register Content
GUIFrame:RegisterContent("SkinTooltips", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Tooltips
    if not db then return yOffset end

    local TT = GetTooltipsModule()

    -- Track widgets for enable/disable logic
    local allWidgets = {}

    local function ApplySettings()
        if TT then
            TT:Refresh()
        end
    end

    local function ApplyTooltipState(enabled)
        if not TT then return end
        TT.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinTooltips")
        else
            KitnEssentials:DisableModule("SkinTooltips")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable + General Settings
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Tooltip Skinning", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 40)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Tooltip Skinning", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyTooltipState(checked)
            UpdateAllWidgetStates()
            if not checked then
                KE:CreateReloadPrompt("Enabling Blizzard UI elements requires a reload to take full effect.")
            end
        end,
        true,
        "Tooltip Skinning",
        "On",
        "Off"
    )
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 40)

    -- Separator
    local row1sep = GUIFrame:CreateRow(card1.content, 8)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    table_insert(allWidgets, sep1)
    card1:AddRow(row1sep, 8)

    -- Info text
    local textRow1Size = 140
    local row1b = GUIFrame:CreateRow(card1.content, textRow1Size)
    local ttInfoText = GUIFrame:CreateText(row1b,
        AccentText("Important Tooltip Info"),
        AccentText("- ") ..
        "As of 1/24/2026, Blizzard themselves have issues with tooltip errors. Tooltip skinning by this addon has protected checks so errors are most likely caused by Blizzard.\n\n" ..
        AccentText("These are some common Blizzard errors:\n") ..
        AccentText("- ") .. "Blizzard_SharedXML/Backdrop.lua" .. "\n" ..
        AccentText("- ") .. "Blizzard_MoneyFrame/Mainline/MoneyFrame.lua" .. "\n" ..
        AccentText("- ") .. "Blizzard_SharedXML/Tooltip/TooltipComparisonManager.lua",
        textRow1Size, "hide")
    row1b:AddWidget(ttInfoText, 1)
    table_insert(allWidgets, ttInfoText)
    card1:AddRow(row1b, textRow1Size)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 1b: General Settings
    ----------------------------------------------------------------
    local card1b = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    table_insert(allWidgets, card1b)

    local row1c = GUIFrame:CreateRow(card1b.content, 34)
    local hideHealthCheck = GUIFrame:CreateCheckbox(row1c, "Hide Health Bar", db.HideHealthBar ~= false,
        function(checked)
            db.HideHealthBar = checked
            ApplySettings()
            if not checked then
                KE:CreateReloadPrompt("Enabling Blizzard UI elements requires a reload to take full effect.")
            end
        end)
    row1c:AddWidget(hideHealthCheck, 1)
    table_insert(allWidgets, hideHealthCheck)
    card1b:AddRow(row1c, 34)

    yOffset = yOffset + card1b:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local card2, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position",
        db = db.Position,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        showAnchorFrameType = false,
        showStrata = false,
        onChangeCallback = function()
            if TT and TT.TTAnchor then
                TT.TTAnchor:ClearAllPoints()
                TT.TTAnchor:SetPoint(db.Position.AnchorFrom, UIParent, db.Position.AnchorTo, db.Position.XOffset, db.Position.YOffset)
            end
        end,
    })
    table_insert(allWidgets, card2)
    if card2.positionWidgets then
        for _, widget in ipairs(card2.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    yOffset = newOffset

    ----------------------------------------------------------------
    -- Card 3: Font Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card3)

    -- Font Face + Outline
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row3a, "Font", fontList, db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row3a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row3a, "Outline", outlineList, db.FontOutline or "OUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row3a:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    card3:AddRow(row3a, 40)

    -- Separator
    local row3sep = GUIFrame:CreateRow(card3.content, 8)
    local sep3 = GUIFrame:CreateSeparator(row3sep)
    row3sep:AddWidget(sep3, 1)
    table_insert(allWidgets, sep3)
    card3:AddRow(row3sep, 8)

    -- Name Font Size
    local row3b = GUIFrame:CreateRow(card3.content, 40)
    local nameSizeSlider = GUIFrame:CreateSlider(row3b, "Player Name Font Size", 8, 72, 1, db.NameFontSize or 17, 60,
        function(val)
            db.NameFontSize = val
            ApplySettings()
        end)
    row3b:AddWidget(nameSizeSlider, 1)
    table_insert(allWidgets, nameSizeSlider)
    card3:AddRow(row3b, 40)

    -- Separator
    local row3bsep = GUIFrame:CreateRow(card3.content, 8)
    local sep3b = GUIFrame:CreateSeparator(row3bsep)
    row3bsep:AddWidget(sep3b, 1)
    table_insert(allWidgets, sep3b)
    card3:AddRow(row3bsep, 8)

    -- Guild Font Size
    local row3c = GUIFrame:CreateRow(card3.content, 40)
    local guildSizeSlider = GUIFrame:CreateSlider(row3c, "Guild Font Size", 8, 72, 1, db.GuildFontSize or 14, 60,
        function(val)
            db.GuildFontSize = val
            ApplySettings()
        end)
    row3c:AddWidget(guildSizeSlider, 1)
    table_insert(allWidgets, guildSizeSlider)
    card3:AddRow(row3c, 40)

    -- Separator
    local row3csep = GUIFrame:CreateRow(card3.content, 8)
    local sep3c = GUIFrame:CreateSeparator(row3csep)
    row3csep:AddWidget(sep3c, 1)
    table_insert(allWidgets, sep3c)
    card3:AddRow(row3csep, 8)

    -- Race & Level Font Size
    local row3d = GUIFrame:CreateRow(card3.content, 40)
    local raceLevelSizeSlider = GUIFrame:CreateSlider(row3d, "Race & Level Font Size", 8, 72, 1, db.RaceLevelFontSize or 14, 60,
        function(val)
            db.RaceLevelFontSize = val
            ApplySettings()
        end)
    row3d:AddWidget(raceLevelSizeSlider, 1)
    table_insert(allWidgets, raceLevelSizeSlider)
    card3:AddRow(row3d, 40)

    -- Separator
    local row3dsep = GUIFrame:CreateRow(card3.content, 8)
    local sep3d = GUIFrame:CreateSeparator(row3dsep)
    row3dsep:AddWidget(sep3d, 1)
    table_insert(allWidgets, sep3d)
    card3:AddRow(row3dsep, 8)

    -- Spec Font Size
    local row3e = GUIFrame:CreateRow(card3.content, 40)
    local specSizeSlider = GUIFrame:CreateSlider(row3e, "Spec Font Size", 8, 72, 1, db.SpecFontSize or 14, 60,
        function(val)
            db.SpecFontSize = val
            ApplySettings()
        end)
    row3e:AddWidget(specSizeSlider, 1)
    table_insert(allWidgets, specSizeSlider)
    card3:AddRow(row3e, 40)

    -- Separator
    local row3esep = GUIFrame:CreateRow(card3.content, 8)
    local sep3e = GUIFrame:CreateSeparator(row3esep)
    row3esep:AddWidget(sep3e, 1)
    table_insert(allWidgets, sep3e)
    card3:AddRow(row3esep, 8)

    -- Faction Font Size
    local row3f = GUIFrame:CreateRow(card3.content, 40)
    local factionSizeSlider = GUIFrame:CreateSlider(row3f, "Faction Font Size", 8, 72, 1, db.FactionFontSize or 14, 60,
        function(val)
            db.FactionFontSize = val
            ApplySettings()
        end)
    row3f:AddWidget(factionSizeSlider, 1)
    table_insert(allWidgets, factionSizeSlider)
    card3:AddRow(row3f, 40)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Backdrop
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    table_insert(allWidgets, card4)

    -- Background Color
    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local bgColor = db.BackgroundColor or { 0, 0, 0, 0.8 }
    local bgColorPicker = GUIFrame:CreateColorPicker(row4a, "Background Color", bgColor, function(r, g, b, a)
        db.BackgroundColor = { r, g, b, a }
        ApplySettings()
    end)
    row4a:AddWidget(bgColorPicker, 1)
    table_insert(allWidgets, bgColorPicker)
    card4:AddRow(row4a, 40)

    -- Border Color + Border Size
    local row4b = GUIFrame:CreateRow(card4.content, 34)
    local borderColor = db.BorderColor or { 0, 0, 0, 1 }
    local borderColorPicker = GUIFrame:CreateColorPicker(row4b, "Border Color", borderColor, function(r, g, b, a)
        db.BorderColor = { r, g, b, a }
        ApplySettings()
    end)
    row4b:AddWidget(borderColorPicker, 0.5)
    table_insert(allWidgets, borderColorPicker)

    local borderSlider = GUIFrame:CreateSlider(row4b, "Border Size", 0, 4, 1, db.BorderSize or 1, 60,
        function(value)
            db.BorderSize = value
            ApplySettings()
        end)
    row4b:AddWidget(borderSlider, 0.5)
    table_insert(allWidgets, borderSlider)
    card4:AddRow(row4b, 34)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
