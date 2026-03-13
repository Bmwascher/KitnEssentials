-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Localization
local table_insert = table.insert
local ipairs = ipairs

-- Helper to get details backdrop module
local function GetDetailsBackdropModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinDetailsBackdrop", true)
    end
    return nil
end

-- Register Content
GUIFrame:RegisterContent("SkinDetails", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Details
    if not db then return yOffset end

    -- Get module
    local DBG = GetDetailsBackdropModule()

    -- Track widgets for enable/disable logic
    local allWidgets = {}
    local masterOnlyWidgets = {} -- Only disabled by master toggle, not per-backdrop
    local autoSizeOnlyWidgets = {}
    local manualSizeWidgets = {}
    local card3

    -- Apply pending context from EditMode navigation
    if GUIFrame.pendingContext then
        local ctx = GUIFrame.pendingContext
        if ctx == "bgOne" or ctx == "bgTwo" then
            db.currentEdit = ctx
        end
        GUIFrame.pendingContext = nil
    end

    -- Initialize current edit selection
    local curEdit = db.currentEdit or "bgOne"

    -- Helper to get current backdrop DB
    local function GetCurrentBackdropDB()
        if curEdit == "bgTwo" then
            return db.backDropTwo
        else
            return db.backDropOne
        end
    end

    local function ApplyAll()
        if DBG then
            DBG:UpdateDetailsBackdropOne()
            DBG:UpdateDetailsBackdropTwo()
        end
    end

    local function ApplySettings()
        if DBG then
            if curEdit == "bgOne" then
                DBG:UpdateDetailsBackdropOne()
            else
                DBG:UpdateDetailsBackdropTwo()
            end
        end
    end

    local function ApplyDetailsBackdropState(enabled)
        if not DBG then return end
        DBG.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinDetailsBackdrop")
        else
            KitnEssentials:DisableModule("SkinDetailsBackdrop")
        end
    end

    -- Comprehensive widget state update
    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        local currentDB = GetCurrentBackdropDB()
        local perEnabled = currentDB.Enabled ~= false
        local bothEnabled = mainEnabled and perEnabled
        local autoSizeEnabled = currentDB.autoSize

        -- Master-only widgets: respond to master enable only
        for _, widget in ipairs(masterOnlyWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end

        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(bothEnabled)
            end
        end

        if card3 and card3.SetAnchorsOnlyEnabled then
            local shouldAnchorsWork = bothEnabled and (not autoSizeEnabled)
            card3:SetAnchorsOnlyEnabled(shouldAnchorsWork)
        end

        for _, widget in ipairs(autoSizeOnlyWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(bothEnabled and autoSizeEnabled)
            end
        end

        for _, widget in ipairs(manualSizeWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(bothEnabled and not autoSizeEnabled)
            end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Details Backdrop Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Details Backdrop", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Details Backdrop", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyDetailsBackdropState(checked)
            UpdateAllWidgetStates()
            if not checked then
                KE:SkinningReloadPrompt()
            end
        end,
        true,
        "Details Backdrop",
        "On",
        "Off"
    )
    row1:AddWidget(enableCheck, 0.5)

    local editList = {
        { key = "bgOne", text = "Backdrop One" },
        { key = "bgTwo", text = "Backdrop Two" },
    }
    local editDropdown = GUIFrame:CreateDropdown(row1, "Select Backdrop To Edit", editList, curEdit, nil,
        function(key)
            curEdit = key
            db.currentEdit = key
            GUIFrame:RefreshContent()
        end)
    row1:AddWidget(editDropdown, 0.5)
    table_insert(masterOnlyWidgets, editDropdown)

    card1:AddRow(row1, 36)

    -- Separator
    local row1sep = GUIFrame:CreateRow(card1.content, 8)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    table_insert(allWidgets, sep1)
    card1:AddRow(row1sep, 8)

    -- Per-backdrop enable checkbox
    local backdropLabel = curEdit == "bgTwo" and "Backdrop Two" or "Backdrop One"
    local row1b = GUIFrame:CreateRow(card1.content, 36)
    local perEnableCheck = GUIFrame:CreateCheckbox(row1b, "Enable " .. backdropLabel,
        GetCurrentBackdropDB().Enabled ~= false,
        function(checked)
            GetCurrentBackdropDB().Enabled = checked
            if DBG then
                DBG:ApplySettings()
            end
            UpdateAllWidgetStates()
            if not checked then
                KE:SkinningReloadPrompt()
            end
        end)
    row1b:AddWidget(perEnableCheck, 1)
    table_insert(masterOnlyWidgets, perEnableCheck)
    card1:AddRow(row1b, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Size Mode
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Size Mode", yOffset)
    table_insert(allWidgets, card2)
    local currentDB = GetCurrentBackdropDB()

    local row2 = GUIFrame:CreateRow(card2.content, 40)
    local autoSizeCheck = GUIFrame:CreateCheckbox(row2, "Auto Size to Parent Frame",
        currentDB.autoSize,
        function(checked, revert)
            if not checked then
                GetCurrentBackdropDB().autoSize = checked
                ApplySettings()
                UpdateAllWidgetStates()
                return
            end

            KE:CreatePrompt(
                "Details Override",
                "This will override your current Details sizing, are you sure you want to use this feature?",
                false, nil, false, nil, nil, nil, nil,
                function()
                    GetCurrentBackdropDB().autoSize = checked
                    ApplySettings()
                    UpdateAllWidgetStates()
                end,
                function()
                    revert(true)
                end,
                "Yes",
                "Cancel"
            )
        end
    )
    row2:AddWidget(autoSizeCheck, 1)
    table_insert(allWidgets, autoSizeCheck)
    card2:AddRow(row2, 40)

    -- Details Bars + Bar Height
    local row2b = GUIFrame:CreateRow(card2.content, 40)
    local detailsBarsSlider = GUIFrame:CreateSlider(row2b, "Amount of bars to show", 1, 25, 1,
        currentDB.detailsBars or db.detailsBars or 7, nil,
        function(val)
            GetCurrentBackdropDB().detailsBars = val
            ApplySettings()
        end)
    row2b:AddWidget(detailsBarsSlider, 0.5)
    table_insert(allWidgets, detailsBarsSlider)
    table_insert(autoSizeOnlyWidgets, detailsBarsSlider)

    local detailsBarHSlider = GUIFrame:CreateSlider(row2b, "Your current Details bar height", 1, 50, 1,
        db.detailsBarH, nil,
        function(val)
            db.detailsBarH = val
            ApplyAll()
        end)
    row2b:AddWidget(detailsBarHSlider, 0.5)
    table_insert(allWidgets, detailsBarHSlider)
    table_insert(autoSizeOnlyWidgets, detailsBarHSlider)
    card2:AddRow(row2b, 40)

    -- Titlebar Height + Spacing
    local row2c = GUIFrame:CreateRow(card2.content, 40)
    local detailsTitelHSlider = GUIFrame:CreateSlider(row2c, "Your current Details titlebar height", 1, 25, 1,
        db.detailsTitelH, nil,
        function(val)
            db.detailsTitelH = val
            ApplyAll()
        end)
    row2c:AddWidget(detailsTitelHSlider, 0.5)
    table_insert(allWidgets, detailsTitelHSlider)
    table_insert(autoSizeOnlyWidgets, detailsTitelHSlider)

    local detailsSpacingSlider = GUIFrame:CreateSlider(row2c, "Your current Details spacing", 1, 50, 1,
        db.detailsSpacing, nil,
        function(val)
            db.detailsSpacing = val
            ApplyAll()
        end)
    row2c:AddWidget(detailsSpacingSlider, 0.5)
    table_insert(allWidgets, detailsSpacingSlider)
    table_insert(autoSizeOnlyWidgets, detailsSpacingSlider)
    card2:AddRow(row2c, 40)

    -- Width
    local row2d = GUIFrame:CreateRow(card2.content, 36)
    local detailsWidthSlider = GUIFrame:CreateSlider(row2d, "Details Width", 50, 1000, 1,
        db.detailsWidth, nil,
        function(val)
            db.detailsWidth = val
            ApplyAll()
        end)
    row2d:AddWidget(detailsWidthSlider, 1)
    table_insert(allWidgets, detailsWidthSlider)
    table_insert(autoSizeOnlyWidgets, detailsWidthSlider)
    card2:AddRow(row2d, 36)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Backdrop Color
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Backdrop Color", yOffset)
    table_insert(allWidgets, card5)

    local row4 = GUIFrame:CreateRow(card5.content, 40)
    local bgColorPicker = GUIFrame:CreateColorPicker(row4, "Backdrop Color",
        GetCurrentBackdropDB().BackgroundColor,
        function(r, g, b, a)
            GetCurrentBackdropDB().BackgroundColor = { r, g, b, a }
            ApplySettings()
        end)
    row4:AddWidget(bgColorPicker, 1)
    table_insert(allWidgets, bgColorPicker)
    card5:AddRow(row4, 40)

    local row5 = GUIFrame:CreateRow(card5.content, 34)
    local borderColorPicker = GUIFrame:CreateColorPicker(row5, "Backdrop Border Color",
        GetCurrentBackdropDB().BorderColor,
        function(r, g, b, a)
            GetCurrentBackdropDB().BorderColor = { r, g, b, a }
            ApplySettings()
        end)
    row5:AddWidget(borderColorPicker, 1)
    table_insert(allWidgets, borderColorPicker)
    card5:AddRow(row5, 34)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    local newOffset
    card3, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = GetCurrentBackdropDB(),
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = false,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if card3.positionWidgets then
        for _, widget in ipairs(card3.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card3)
    yOffset = newOffset

    ----------------------------------------------------------------
    -- Card 4: Manual Backdrop Size
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Backdrop Size (Manual)", yOffset)
    table_insert(allWidgets, card4)
    table_insert(manualSizeWidgets, card4)

    local row3 = GUIFrame:CreateRow(card4.content, 36)
    local backdropWidthSlider = GUIFrame:CreateSlider(row3, "Backdrop Width", 10, 1000, 1,
        GetCurrentBackdropDB().width, nil,
        function(val)
            GetCurrentBackdropDB().width = val
            ApplySettings()
        end)
    row3:AddWidget(backdropWidthSlider, 0.5)
    table_insert(allWidgets, backdropWidthSlider)
    table_insert(manualSizeWidgets, backdropWidthSlider)

    local backdropHeightSlider = GUIFrame:CreateSlider(row3, "Backdrop Height", 10, 1000, 1,
        GetCurrentBackdropDB().height, nil,
        function(val)
            GetCurrentBackdropDB().height = val
            ApplySettings()
        end)
    row3:AddWidget(backdropHeightSlider, 0.5)
    table_insert(allWidgets, backdropHeightSlider)
    table_insert(manualSizeWidgets, backdropHeightSlider)
    card4:AddRow(row3, 36)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
