-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs

-- Helper to get modules
local function GetBlizzardMouseoverModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBlizzardMouseover", true)
    end
    return nil
end

local function GetActionBarsModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinActionBars", true)
    end
    return nil
end

local function GetMicroMenuModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBlizzardMicroMenu", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinMouseover", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Mouseover
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local BMO = GetBlizzardMouseoverModule()
    local abDB = KE.db and KE.db.profile.Skinning.ActionBars
    local mmDB = KE.db and KE.db.profile.Skinning.MicroMenu

    -- Track widgets for enable/disable logic
    local allWidgets = {}
    local bagWidgets = {}

    local function ApplySettings()
        if BMO then BMO:ApplySettings() end
    end

    local function ApplyMouseoverState(enabled)
        if not BMO then return end
        BMO.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinBlizzardMouseover")
        else
            KitnEssentials:DisableModule("SkinBlizzardMouseover")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        local bagEnabled = db.BagMouseover and db.BagMouseover.Enabled ~= false

        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end

        if mainEnabled then
            for _, widget in ipairs(bagWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(bagEnabled)
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable + About
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Blizzard Mouseover", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 40)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Blizzard Mouseover", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyMouseoverState(checked)
            UpdateAllWidgetStates()
        end,
        true,
        "Blizzard Mouseover",
        "On",
        "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 40)

    -- Separator
    local rowSep1 = GUIFrame:CreateRow(card1.content, 8)
    local sep1 = GUIFrame:CreateSeparator(rowSep1)
    rowSep1:AddWidget(sep1, 1)
    table_insert(allWidgets, sep1)
    card1:AddRow(rowSep1, 8)

    -- Description
    local descRowSize = 30
    local rowDesc = GUIFrame:CreateRow(card1.content, descRowSize)
    local descText = GUIFrame:CreateText(rowDesc,
        KE:ColorTextByTheme("About"),
        "Fades supported Blizzard UI elements until you mouseover them.",
        descRowSize, "hide")
    rowDesc:AddWidget(descText, 1)
    table_insert(allWidgets, descText)
    card1:AddRow(rowDesc, descRowSize)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Bag Bar (owned by this module — full settings here)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Bag Bar", yOffset)
    table_insert(allWidgets, card2)

    -- Bag enable toggle
    local rowBagEnable = GUIFrame:CreateRow(card2.content, 40)
    local bagEnableCheck = GUIFrame:CreateCheckbox(rowBagEnable, "Enable BagBar Mouseover",
        db.BagMouseover.Enabled ~= false,
        function(checked)
            db.BagMouseover.Enabled = checked
            if BMO then
                BMO:ToggleElement("bags", checked)
                ApplySettings()
            end
            UpdateAllWidgetStates()
        end)
    rowBagEnable:AddWidget(bagEnableCheck, 1)
    table_insert(allWidgets, bagEnableCheck)
    card2:AddRow(rowBagEnable, 40)

    -- Alpha when not hovered
    local rowAlpha = GUIFrame:CreateRow(card2.content, 40)
    local nonMouseoverAlpha = GUIFrame:CreateSlider(rowAlpha, "Alpha When No Mouseover", 0, 1, 0.1, db.Alpha, _,
        function(val)
            db.Alpha = val
            ApplySettings()
        end)
    rowAlpha:AddWidget(nonMouseoverAlpha, 1)
    table_insert(allWidgets, nonMouseoverAlpha)
    table_insert(bagWidgets, nonMouseoverAlpha)
    card2:AddRow(rowAlpha, 40)

    -- Fade durations
    local rowFade = GUIFrame:CreateRow(card2.content, 36)
    local fadeInSlider = GUIFrame:CreateSlider(rowFade, "Fade In Duration", 0, 10, 0.1, db.FadeInDuration, _,
        function(val)
            db.FadeInDuration = val
        end)
    rowFade:AddWidget(fadeInSlider, 0.5)
    table_insert(allWidgets, fadeInSlider)
    table_insert(bagWidgets, fadeInSlider)

    local fadeOutSlider = GUIFrame:CreateSlider(rowFade, "Fade Out Duration", 0, 10, 0.1, db.FadeOutDuration, _,
        function(val)
            db.FadeOutDuration = val
        end)
    rowFade:AddWidget(fadeOutSlider, 0.5)
    table_insert(allWidgets, fadeOutSlider)
    table_insert(bagWidgets, fadeOutSlider)

    card2:AddRow(rowFade, 36)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Other Elements (cross-module toggles)
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Other Elements", yOffset)
    table_insert(allWidgets, card3)

    -- Info text explaining these are cross-module toggles
    local infoRowSize = 30
    local rowInfo = GUIFrame:CreateRow(card3.content, infoRowSize)
    local infoText = GUIFrame:CreateText(rowInfo,
        KE:ColorTextByTheme("Quick Toggles"),
        KE:ColorTextByTheme("• ") .. "These elements have their own mouseover settings in their respective pages.",
        infoRowSize, "hide")
    rowInfo:AddWidget(infoText, 1)
    table_insert(allWidgets, infoText)
    card3:AddRow(rowInfo, infoRowSize)

    -- Separator between info text and toggles
    local rowSep2 = GUIFrame:CreateRow(card3.content, 8)
    local sep2 = GUIFrame:CreateSeparator(rowSep2)
    rowSep2:AddWidget(sep2, 1)
    table_insert(allWidgets, sep2)
    card3:AddRow(rowSep2, 8)

    -- ActionBars mouseover toggle
    if abDB then
        local rowAB = GUIFrame:CreateRow(card3.content, 40)
        local abMouseoverEnabled = abDB.Mouseover and abDB.Mouseover.Enabled ~= false
        local abCheck = GUIFrame:CreateCheckbox(rowAB, "Action Bars Mouseover", abMouseoverEnabled,
            function(checked)
                if abDB.Mouseover then
                    abDB.Mouseover.Enabled = checked
                end
                local abModule = GetActionBarsModule()
                if abModule and abModule.UpdateSettings then
                    abModule:UpdateSettings("mouseover")
                end
            end)
        rowAB:AddWidget(abCheck, 1)
        table_insert(allWidgets, abCheck)
        card3:AddRow(rowAB, 40)
    end

    -- MicroMenu mouseover toggle
    if mmDB then
        local rowMM = GUIFrame:CreateRow(card3.content, 40)
        local mmMouseoverEnabled = mmDB.Mouseover and mmDB.Mouseover.Enabled ~= false
        local mmCheck = GUIFrame:CreateCheckbox(rowMM, "Micro Menu Mouseover", mmMouseoverEnabled,
            function(checked)
                if mmDB.Mouseover then
                    mmDB.Mouseover.Enabled = checked
                end
                local mmModule = GetMicroMenuModule()
                if mmModule and mmModule.UpdateAlpha then
                    mmModule:UpdateAlpha()
                end
            end)
        rowMM:AddWidget(mmCheck, 1)
        table_insert(allWidgets, mmCheck)
        card3:AddRow(rowMM, 40)
    end

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)
