-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert

GUIFrame:RegisterContent("KickTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.KickTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local KT = KitnEssentials and KitnEssentials:GetModule("KickTracker", true)
    local allWidgets = {}
    local classOnlyWidgets = {}  -- widgets only relevant in "class" color mode

    local function ApplySettings()
        if KT and KT.ApplySettings then KT:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("KickTracker", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("KickTracker")
        else
            KitnEssentials:DisableModule("KickTracker")
        end
    end

    local coolingColorWidget = nil  -- tracked separately for compound condition

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        local isClassMode = db.ColorMode ~= "dark"
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
        for _, widget in ipairs(classOnlyWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled and isClassMode) end
        end
        -- Cooling color only relevant when class mode + ClassColorCooling is OFF
        if coolingColorWidget and coolingColorWidget.SetEnabled then
            coolingColorWidget:SetEnabled(mainEnabled and isClassMode and not db.ClassColorCooling)
        end
    end

    -- Build LSM lists
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local statusbarList = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do statusbarList[name] = name end
    else
        statusbarList["Blizzard"] = "Blizzard"
    end

    local outlineList = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
    }

    ----------------------------------------------------------------
    -- Card 1: Interrupt Tracker (Enable)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Interrupt Tracker", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Interrupt Tracker", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Interrupt Tracker", "On", "Off"
    )
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, 36)

    card1:AddLabel("|cff888888" .. KE:ColorTextByTheme("-") .. " Tracks party interrupt cooldowns in real-time using status bars.\n" .. KE:ColorTextByTheme("-") .. " Only active in 5-player dungeons.|r")

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        dbKeys = { selfPoint = "AnchorFrom", anchorPoint = "AnchorTo", xOffset = "XOffset", yOffset = "YOffset" },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    -- Disable standard position card when healer override is active for a healer spec
    local isHealerActive = db.UseHealerPosition and KE.IsPlayerHealerSpec and KE:IsPlayerHealerSpec()
    if isHealerActive then posCard:SetEnabled(false) end
    yOffset = posOffset + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2b: Healer Position Override
    ----------------------------------------------------------------
    local healerCard = GUIFrame:CreateCard(scrollChild, "Healer Position Override", yOffset)

    local healerRow1 = GUIFrame:CreateRow(healerCard.content, 36)
    local healerEnableCheck = GUIFrame:CreateCheckbox(healerRow1, "Use Healer Position",
        db.UseHealerPosition == true,
        function(checked)
            db.UseHealerPosition = checked
            ApplySettings()
            C_Timer.After(0.05, function() GUIFrame:RefreshContent() end)
        end)
    healerRow1:AddWidget(healerEnableCheck, 1)
    healerCard:AddRow(healerRow1, 36)

    healerCard:AddLabel("|cff888888" .. KE:ColorTextByTheme("-") .. " Auto-swap to a separate position when playing a healer spec.|r")

    yOffset = yOffset + healerCard:GetContentHeight() + Theme.paddingSmall

    if db.UseHealerPosition then
        -- Metatable wrapper so CreatePositionCard reads/writes healer keys
        local healerDb = setmetatable({
            Position = db.HealerPosition,
        }, {
            __index = function(_, k)
                if k == "anchorFrameType" then return db.HealerAnchorFrameType
                elseif k == "ParentFrame" then return db.HealerParentFrame
                elseif k == "Strata" then return db.HealerStrata
                else return db[k] end
            end,
            __newindex = function(t, k, v)
                if k == "anchorFrameType" then db.HealerAnchorFrameType = v
                elseif k == "ParentFrame" then db.HealerParentFrame = v
                elseif k == "Strata" then db.HealerStrata = v
                else rawset(t, k, v) end
            end,
        })

        local _, healerPosOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
            title = "Healer Position",
            db = healerDb,
            dbKeys = { selfPoint = "AnchorFrom", anchorPoint = "AnchorTo", xOffset = "XOffset", yOffset = "YOffset" },
            showAnchorFrameType = true,
            showStrata = true,
            onChangeCallback = ApplySettings,
        })
        yOffset = healerPosOffset + Theme.paddingSmall
    end

    ----------------------------------------------------------------
    -- Card 3: Bar Appearance
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Bar Appearance", yOffset)

    -- Width + Height
    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local widthSlider = GUIFrame:CreateSlider(row3a, "Bar Width", 80, 400, 1, db.BarWidth or 180, nil,
        function(val)
            db.BarWidth = val
            ApplySettings()
        end)
    row3a:AddWidget(widthSlider, 0.5)
    table_insert(allWidgets, widthSlider)

    local heightSlider = GUIFrame:CreateSlider(row3a, "Bar Height", 12, 40, 1, db.BarHeight or 20, nil,
        function(val)
            db.BarHeight = val
            ApplySettings()
        end)
    row3a:AddWidget(heightSlider, 0.5)
    table_insert(allWidgets, heightSlider)
    card3:AddRow(row3a, 40)

    -- Growth Direction + Max Bars
    local row3b = GUIFrame:CreateRow(card3.content, 40)
    local growList = {
        { key = "DOWN", text = "Down" },
        { key = "UP", text = "Up" },
    }
    local growDropdown = GUIFrame:CreateDropdown(row3b, "Growth Direction", growList, db.GrowthDirection or "DOWN", 30,
        function(key)
            db.GrowthDirection = key
            ApplySettings()
        end)
    row3b:AddWidget(growDropdown, 0.5)
    table_insert(allWidgets, growDropdown)

    local maxBarsSlider = GUIFrame:CreateSlider(row3b, "Max Bars", 1, 5, 1, db.MaxBars or 5, nil,
        function(val)
            db.MaxBars = val
            ApplySettings()
        end)
    row3b:AddWidget(maxBarsSlider, 0.5)
    table_insert(allWidgets, maxBarsSlider)
    card3:AddRow(row3b, 40)

    -- Spacing + Bar Texture
    local row3c = GUIFrame:CreateRow(card3.content, 40)
    local spacingSlider = GUIFrame:CreateSlider(row3c, "Bar Spacing", 0, 10, 1, db.BarSpacing or 2, nil,
        function(val)
            db.BarSpacing = val
            ApplySettings()
        end)
    row3c:AddWidget(spacingSlider, 0.5)
    table_insert(allWidgets, spacingSlider)

    local statusbarDropdown = GUIFrame:CreateDropdown(row3c, "Bar Texture", statusbarList,
        db.StatusBarTexture or "KitnUI", 70,
        function(key)
            db.StatusBarTexture = key
            ApplySettings()
        end)
    row3c:AddWidget(statusbarDropdown, 0.5)
    table_insert(allWidgets, statusbarDropdown)
    card3:AddRow(row3c, 40)

    -- Show Icon + Icon Size + Icon Side
    local row3d = GUIFrame:CreateRow(card3.content, 40)
    local iconCheck = GUIFrame:CreateCheckbox(row3d, "Show Icon", db.ShowIcon ~= false,
        function(checked)
            db.ShowIcon = checked
            ApplySettings()
        end)
    row3d:AddWidget(iconCheck, 0.33)
    table_insert(allWidgets, iconCheck)

    local iconSizeSlider = GUIFrame:CreateSlider(row3d, "Icon Size", 12, 40, 1, db.IconSize or 20, nil,
        function(val)
            db.IconSize = val
            ApplySettings()
        end)
    row3d:AddWidget(iconSizeSlider, 0.33)
    table_insert(allWidgets, iconSizeSlider)

    local sideList = {
        { key = "LEFT", text = "Left" },
        { key = "RIGHT", text = "Right" },
    }
    local sideDropdown = GUIFrame:CreateDropdown(row3d, "Icon Side", sideList, db.IconSide or "LEFT", 30,
        function(key)
            db.IconSide = key
            ApplySettings()
        end)
    row3d:AddWidget(sideDropdown, 0.34)
    table_insert(allWidgets, sideDropdown)
    card3:AddRow(row3d, 40)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Text Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Text Settings", yOffset)

    -- Show Name + Show Timer
    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local nameCheck = GUIFrame:CreateCheckbox(row4a, "Show Player Name", db.ShowName ~= false,
        function(checked)
            db.ShowName = checked
            ApplySettings()
        end)
    row4a:AddWidget(nameCheck, 0.5)
    table_insert(allWidgets, nameCheck)

    local timerCheck = GUIFrame:CreateCheckbox(row4a, "Show Timer", db.ShowTimer ~= false,
        function(checked)
            db.ShowTimer = checked
            ApplySettings()
        end)
    row4a:AddWidget(timerCheck, 0.5)
    table_insert(allWidgets, timerCheck)
    card4:AddRow(row4a, 40)

    -- Font + Font Size + Outline (shared for name and timer)
    local row4b = GUIFrame:CreateRow(card4.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row4b, "Font", fontList, db.FontFace or "Expressway", 70,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row4b:AddWidget(fontDropdown, 0.4)
    table_insert(allWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", 8, 24, 1, db.FontSize or 11, nil,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4b:AddWidget(fontSizeSlider, 0.3)
    table_insert(allWidgets, fontSizeSlider)

    local fontOutlineDropdown = GUIFrame:CreateDropdown(row4b, "Outline", outlineList, db.FontOutline or "SOFTOUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row4b:AddWidget(fontOutlineDropdown, 0.3)
    table_insert(allWidgets, fontOutlineDropdown)
    card4:AddRow(row4b, 40)

    -- Show Ready Text + Ready Text
    local row4c = GUIFrame:CreateRow(card4.content, 40)
    local readyCheck = GUIFrame:CreateCheckbox(row4c, "Show Ready Text", db.ShowReadyText ~= false,
        function(checked)
            db.ShowReadyText = checked
            ApplySettings()
        end)
    row4c:AddWidget(readyCheck, 0.5)
    table_insert(allWidgets, readyCheck)

    local readyTextInput = GUIFrame:CreateEditBox(row4c, "Ready Text", db.ReadyText or "Ready",
        function(text)
            db.ReadyText = text
            ApplySettings()
        end)
    row4c:AddWidget(readyTextInput, 0.5)
    table_insert(allWidgets, readyTextInput)

    card4:AddRow(row4c, 40)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)

    -- Color Mode dropdown + Class Color Cooling toggle
    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local colorModeList = {
        { key = "class", text = "Class Colored Bars" },
        { key = "dark",  text = "Dark Bars" },
    }
    local colorModeDropdown = GUIFrame:CreateDropdown(row5a, "Color Mode", colorModeList, db.ColorMode or "class", 50,
        function(key)
            db.ColorMode = key
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row5a:AddWidget(colorModeDropdown, 0.5)
    table_insert(allWidgets, colorModeDropdown)

    local classColorCDCheck = GUIFrame:CreateCheckbox(row5a, "Class Color While Cooling", db.ClassColorCooling == true,
        function(checked)
            db.ClassColorCooling = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row5a:AddWidget(classColorCDCheck, 0.5)
    table_insert(classOnlyWidgets, classColorCDCheck)
    card5:AddRow(row5a, 40)

    card5:AddLabel("|cff888888" .. KE:ColorTextByTheme("Class Colored") .. " - Class-colored bars with white names.\n" .. KE:ColorTextByTheme("Dark") .. " - Dark bars with class-colored names.|r")

    -- Cooling color + Ready color (class mode only) + Background color (always)
    local row5b = GUIFrame:CreateRow(card5.content, 40)
    local coolingPicker = GUIFrame:CreateColorPicker(row5b, "Cooling Color", db.CoolingColor or { 0.8, 0.2, 0.2, 1 },
        function(r, g, b, a)
            db.CoolingColor = { r, g, b, a }
            ApplySettings()
        end)
    row5b:AddWidget(coolingPicker, 0.33)
    coolingColorWidget = coolingPicker

    local readyPicker = GUIFrame:CreateColorPicker(row5b, "Ready Color", db.ReadyColor or { 0.2, 0.8, 0.2, 1 },
        function(r, g, b, a)
            db.ReadyColor = { r, g, b, a }
            ApplySettings()
        end)
    row5b:AddWidget(readyPicker, 0.33)
    table_insert(classOnlyWidgets, readyPicker)

    local bgPicker = GUIFrame:CreateColorPicker(row5b, "Background Color", db.BackgroundColor or { 0.031, 0.031, 0.031, 0.80 },
        function(r, g, b, a)
            db.BackgroundColor = { r, g, b, a }
            ApplySettings()
        end)
    row5b:AddWidget(bgPicker, 0.34)
    table_insert(allWidgets, bgPicker)
    card5:AddRow(row5b, 40)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 6: Sort Priority
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Sort Priority", yOffset)

    card6:AddLabel("|cff888888Ready bars sorted by role priority, cooling bars sorted by remaining time (shortest first).|r")

    local row6a = GUIFrame:CreateRow(card6.content, 40)
    local tankSlider = GUIFrame:CreateSlider(row6a, "Tank Priority", 1, 3, 1, db.SortTankPriority or 1, nil,
        function(val)
            db.SortTankPriority = val
            ApplySettings()
        end)
    row6a:AddWidget(tankSlider, 0.33)
    table_insert(allWidgets, tankSlider)

    local healerSlider = GUIFrame:CreateSlider(row6a, "Healer Priority", 1, 3, 1, db.SortHealerPriority or 2, nil,
        function(val)
            db.SortHealerPriority = val
            ApplySettings()
        end)
    row6a:AddWidget(healerSlider, 0.33)
    table_insert(allWidgets, healerSlider)

    local dpsSlider = GUIFrame:CreateSlider(row6a, "DPS Priority", 1, 3, 1, db.SortDPSPriority or 3, nil,
        function(val)
            db.SortDPSPriority = val
            ApplySettings()
        end)
    row6a:AddWidget(dpsSlider, 0.34)
    table_insert(allWidgets, dpsSlider)
    card6:AddRow(row6a, 40)

    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()

    return yOffset
end)
