-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Localization
local table_insert = table.insert
local ipairs = ipairs

-- Helper to get module
local function GetRaidManagerModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBlizzardRaidmanager", true)
    end
    return nil
end

-- Register Content
GUIFrame:RegisterContent("SkinRaidManager", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.RaidManager
    if not db then return yOffset end

    local BRMG = GetRaidManagerModule()
    local allWidgets = {}

    local function ApplySettings()
        if BRMG then
            BRMG:ApplySettings()
        end
    end

    local function ApplyModuleState(enabled)
        if not BRMG then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinBlizzardRaidmanager")
        else
            KitnEssentials:DisableModule("SkinBlizzardRaidmanager")
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
    -- Card 1: Raid Manager (Enable)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Raid Manager", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 40)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Raid Manager Styling", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
            if not checked then
                KE:SkinningReloadPrompt()
            end
        end,
        true, "Raid Manager Styling", "On", "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 40)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Position Settings", yOffset)
    table_insert(allWidgets, card2)

    local row2 = GUIFrame:CreateRow(card2.content, 40)
    local ySlider = GUIFrame:CreateSlider(row2, "Y Offset", -1100, 100, 1,
        db.Position.YOffset, nil,
        function(val)
            db.Position.YOffset = val
            ApplySettings()
        end)
    row2:AddWidget(ySlider, 1)
    table_insert(allWidgets, ySlider)
    card2:AddRow(row2, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Mouseover Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Mouseover Settings", yOffset)
    table_insert(allWidgets, card3)

    -- Toggle mouseover
    local row3 = GUIFrame:CreateRow(card3.content, 40)
    local useFade = GUIFrame:CreateCheckbox(row3, "Enable Mouseover", db.FadeOnMouseOut ~= false,
        function(checked)
            db.FadeOnMouseOut = checked
            ApplySettings()
        end)
    row3:AddWidget(useFade, 1)
    table_insert(allWidgets, useFade)
    card3:AddRow(row3, 40)

    -- Separator
    local row3sep = GUIFrame:CreateRow(card3.content, 8)
    local sep3 = GUIFrame:CreateSeparator(row3sep)
    row3sep:AddWidget(sep3, 1)
    table_insert(allWidgets, sep3)
    card3:AddRow(row3sep, 8)

    -- Fade in/out durations
    local row4 = GUIFrame:CreateRow(card3.content, 40)
    local fadeInSlider = GUIFrame:CreateSlider(row4, "Fade In Duration", 0, 20, 0.1,
        db.FadeInDuration, nil,
        function(val)
            db.FadeInDuration = val
            ApplySettings()
        end)
    row4:AddWidget(fadeInSlider, 0.5)
    table_insert(allWidgets, fadeInSlider)

    local fadeOutSlider = GUIFrame:CreateSlider(row4, "Fade Out Duration", 0, 20, 0.1,
        db.FadeOutDuration, nil,
        function(val)
            db.FadeOutDuration = val
            ApplySettings()
        end)
    row4:AddWidget(fadeOutSlider, 0.5)
    table_insert(allWidgets, fadeOutSlider)
    card3:AddRow(row4, 40)

    -- Alpha slider
    local row5 = GUIFrame:CreateRow(card3.content, 40)
    local alphaSlider = GUIFrame:CreateSlider(row5, "Alpha", 0, 1, 0.1,
        db.Alpha, nil,
        function(val)
            db.Alpha = val
            ApplySettings()
        end)
    row5:AddWidget(alphaSlider, 1)
    table_insert(allWidgets, alphaSlider)
    card3:AddRow(row5, 40)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)
