-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local LSM = KE.LSM
local table_insert = table.insert
local pairs, ipairs = pairs, ipairs
local tonumber = tonumber
local tostring = tostring
local CreateFrame = CreateFrame
local C_Spell = C_Spell
local C_Item = C_Item

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("BuffBars", true)
    end
    return nil
end

local selectedTrackerIndex = nil
local isPreviewActive = false

-- Helper: icon with spell name and ID labels
local function CreateIconWithLabels(parent, spellOrItemID, isItem, size)
    size = size or 32
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(size)

    local iconFrame = CreateFrame("Frame", nil, container)
    iconFrame:SetSize(size, size)
    iconFrame:SetPoint("LEFT", container, "LEFT", 4, 0)

    iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.texture:SetPoint("TOPLEFT", 1, -1)
    iconFrame.texture:SetPoint("BOTTOMRIGHT", -1, 1)

    local lo = 0.25 * 0.3
    local hi = 1 - lo
    iconFrame.texture:SetTexCoord(lo, hi, lo, hi)

    local texture, spellName
    if isItem then
        texture = C_Item.GetItemIconByID(spellOrItemID)
        local itemInfo = C_Item.GetItemInfo(spellOrItemID)
        spellName = itemInfo or "Unknown Item"
    else
        texture = C_Spell.GetSpellTexture(spellOrItemID)
        local spellInfo = C_Spell.GetSpellInfo(spellOrItemID)
        spellName = spellInfo and spellInfo.name or "Unknown Spell"
    end

    iconFrame.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", "SetHeight", 1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight", 1 },
    }) do
        local t = iconFrame:CreateTexture(nil, "OVERLAY")
        t[edge[3]](t, edge[4])
        t:SetPoint(edge[1], iconFrame, edge[1], 0, 0)
        t:SetPoint(edge[2], iconFrame, edge[2], 0, 0)
        t:SetColorTexture(0, 0, 0, 1)
    end
    for _, edge in ipairs({
        { "TOPLEFT", "BOTTOMLEFT", "SetWidth", 1 },
        { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth", 1 },
    }) do
        local t = iconFrame:CreateTexture(nil, "OVERLAY")
        t[edge[3]](t, edge[4])
        t:SetPoint(edge[1], iconFrame, edge[1], 0, 0)
        t:SetPoint(edge[2], iconFrame, edge[2], 0, 0)
        t:SetColorTexture(0, 0, 0, 1)
    end

    local nameLabel = container:CreateFontString(nil, "OVERLAY")
    nameLabel:SetPoint("LEFT", iconFrame, "RIGHT", 5, 6)
    nameLabel:SetFont(STANDARD_TEXT_FONT, Theme.fontSizeSmall, "OUTLINE")
    nameLabel:SetShadowOffset(0, 0)
    nameLabel:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    nameLabel:SetText(spellName)

    local typeLabel = isItem and "Item" or "Spell"
    local idLabel = container:CreateFontString(nil, "OVERLAY")
    idLabel:SetPoint("LEFT", iconFrame, "RIGHT", 5, -6)
    idLabel:SetFont(STANDARD_TEXT_FONT, Theme.fontSizeSmall, "OUTLINE")
    idLabel:SetShadowOffset(0, 0)
    idLabel:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    idLabel:SetText(typeLabel .. " ID: " .. (spellOrItemID or 0))

    return container
end

GUIFrame:RegisterContent("BuffBars", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.BuffBars
    if not db then return yOffset end

    if not db.Trackers then db.Trackers = {} end
    if not db.Defaults then db.Defaults = {} end
    if not db.Position then db.Position = {} end

    local allWidgets = {}

    local function ApplySettings()
        local mod = GetModule()
        if mod and mod.ApplySettings then mod:ApplySettings() end
        if isPreviewActive and mod and mod.PreviewAll then mod:PreviewAll() end
    end

    local function ApplyPosition()
        local mod = GetModule()
        if mod and mod.ApplyPosition then mod:ApplyPosition() end
    end

    local function RefreshContent()
        C_Timer.After(0.1, function() GUIFrame:RefreshContent() end)
    end

    local function ApplyModuleState(enabled)
        local mod = GetModule()
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("BuffBars")
        else
            KitnEssentials:DisableModule("BuffBars")
        end
    end

    GUIFrame.contentCleanupCallbacks = GUIFrame.contentCleanupCallbacks or {}
    GUIFrame.contentCleanupCallbacks["BuffBars"] = function()
        isPreviewActive = false
        local mod = GetModule()
        if mod and mod.HideAll then mod:HideAll() end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    local function GetTrackerList()
        local list = {}
        for index, tracker in pairs(db.Trackers) do
            if tracker.SpellID then
                local name = tracker.SpellText
                if not name or name == "" then
                    if tracker.Type == "Item" then
                        local itemInfo = C_Item.GetItemInfo(tracker.SpellID)
                        name = itemInfo or "Unknown Item"
                    else
                        local spellInfo = C_Spell.GetSpellInfo(tracker.SpellID)
                        name = spellInfo and spellInfo.name or "Unknown Spell"
                    end
                end
                local typeLabel = tracker.Type == "Item" and "Item" or "Spell"
                table_insert(list, {
                    key = tostring(index),
                    text = name .. " (" .. typeLabel .. ": " .. tracker.SpellID .. ")",
                })
            end
        end
        table.sort(list, function(a, b) return tonumber(a.key) < tonumber(b.key) end)
        return list
    end

    if selectedTrackerIndex and not db.Trackers[selectedTrackerIndex] then
        selectedTrackerIndex = nil
    end

    local selectedTracker = selectedTrackerIndex and db.Trackers[selectedTrackerIndex] or nil

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Buff Bars", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Buff Bars", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Buff Bars", "On", "Off")
    row1:AddWidget(enableCheck, 0.5)

    local previewBtn = GUIFrame:CreateButton(row1, "Preview All", {
        width = 100,
        callback = function()
            isPreviewActive = true
            local mod = GetModule()
            if mod and mod.PreviewAll then mod:PreviewAll() end
        end,
    })
    row1:AddWidget(previewBtn, 0.5, nil, 0, -2)
    table_insert(allWidgets, previewBtn)

    card1:AddRow(row1, 36)
    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Tracker Selection
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Tracker Selection", yOffset)
    table_insert(allWidgets, card2)

    local row2 = GUIFrame:CreateRow(card2.content, 36)

    local addBtn = GUIFrame:CreateButton(row2, "Add New Tracker", {
        width = 140,
        callback = function()
            local nextIndex = 1
            for i = 1, 100 do
                if not db.Trackers[i] then nextIndex = i; break end
            end
            db.Trackers[nextIndex] = { Enabled = true, SpellID = 0, Duration = 10, SpellText = "" }
            selectedTrackerIndex = nextIndex
            ApplySettings()
            RefreshContent()
        end,
    })
    row2:AddWidget(addBtn, 0.5, nil, 0, -2)
    table_insert(allWidgets, addBtn)

    local trackerList = GetTrackerList()
    if #trackerList > 0 then
        local currentSelection = selectedTrackerIndex and tostring(selectedTrackerIndex) or trackerList[1].key
        if not selectedTrackerIndex then
            selectedTrackerIndex = tonumber(trackerList[1].key)
            selectedTracker = db.Trackers[selectedTrackerIndex]
        end

        local trackerDropdown = GUIFrame:CreateDropdown(row2, "Edit Tracker", trackerList, currentSelection, 70,
            function(key)
                selectedTrackerIndex = tonumber(key)
                RefreshContent()
            end)
        row2:AddWidget(trackerDropdown, 0.5)
        table_insert(allWidgets, trackerDropdown)
    end

    card2:AddRow(row2, 36)
    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Selected Tracker Settings
    ----------------------------------------------------------------
    if selectedTracker then
        local card3 = GUIFrame:CreateCard(scrollChild, "Tracker Settings", yOffset)
        table_insert(allWidgets, card3)

        -- Icon + Enable + Delete
        local row3a = GUIFrame:CreateRow(card3.content, 40)
        local isItem = selectedTracker.Type == "Item"
        local iconWidget = CreateIconWithLabels(row3a, selectedTracker.SpellID or 0, isItem, 36)
        row3a:AddWidget(iconWidget, 0.5)

        local trackerEnableCheck = GUIFrame:CreateCheckbox(row3a, "Enabled", selectedTracker.Enabled ~= false,
            function(checked)
                selectedTracker.Enabled = checked
                ApplySettings()
            end)
        row3a:AddWidget(trackerEnableCheck, 0.2)
        table_insert(allWidgets, trackerEnableCheck)

        local deleteBtn = GUIFrame:CreateButton(row3a, "Delete", {
            width = 70,
            callback = function()
                db.Trackers[selectedTrackerIndex] = nil
                selectedTrackerIndex = nil
                ApplySettings()
                RefreshContent()
            end,
        })
        row3a:AddWidget(deleteBtn, 0.3)
        table_insert(allWidgets, deleteBtn)
        card3:AddRow(row3a, 40)

        local sepRow = GUIFrame:CreateRow(card3.content, 8)
        local sep = GUIFrame:CreateSeparator(sepRow)
        sepRow:AddWidget(sep, 1)
        card3:AddRow(sepRow, 8)

        -- Type + ID
        local row3b = GUIFrame:CreateRow(card3.content, 40)
        local typeOptions = {
            { key = "Spell", text = "Spell" },
            { key = "Item",  text = "Item" },
        }
        local typeDropdown = GUIFrame:CreateDropdown(row3b, "Type", typeOptions, selectedTracker.Type or "Spell", 40,
            function(key)
                selectedTracker.Type = key
                ApplySettings()
                RefreshContent()
            end)
        row3b:AddWidget(typeDropdown, 0.5)
        table_insert(allWidgets, typeDropdown)

        local idLabel = (selectedTracker.Type == "Item") and "Item ID" or "Spell ID"
        local spellIDInput = GUIFrame:CreateEditBox(row3b, idLabel, tostring(selectedTracker.SpellID or ""),
            function(text)
                local newID = tonumber(text)
                if newID and newID > 0 then
                    selectedTracker.SpellID = newID
                    ApplySettings()
                    RefreshContent()
                end
            end)
        spellIDInput.editBox:SetNumeric(true)
        row3b:AddWidget(spellIDInput, 0.5)
        table_insert(allWidgets, spellIDInput)
        card3:AddRow(row3b, 40)

        -- Display Name + Duration + Bar Color
        local row3c = GUIFrame:CreateRow(card3.content, 40)
        local nameInput = GUIFrame:CreateEditBox(row3c, "Display Name", selectedTracker.SpellText or "",
            function(text)
                selectedTracker.SpellText = text
                ApplySettings()
            end)
        row3c:AddWidget(nameInput, 0.5)
        table_insert(allWidgets, nameInput)

        local durationInput = GUIFrame:CreateEditBox(row3c, "Duration (sec)", tostring(selectedTracker.Duration or 10),
            function(text)
                local newDur = tonumber(text)
                if newDur and newDur > 0 then
                    selectedTracker.Duration = newDur
                    ApplySettings()
                end
            end)
        row3c:AddWidget(durationInput, 0.2)
        table_insert(allWidgets, durationInput)

        local defaults = db.Defaults or {}
        local barColor = selectedTracker.BarColor or defaults.BarColor or { 0.65, 0.65, 0.65, 1 }
        local barColorPicker = GUIFrame:CreateColorPicker(row3c, "Bar Color", barColor,
            function(r, g, b, a)
                selectedTracker.BarColor = { r, g, b, a }
                ApplySettings()
            end)
        row3c:AddWidget(barColorPicker, 0.3)
        table_insert(allWidgets, barColorPicker)
        card3:AddRow(row3c, 40)

        -- Show Icon + Reverse
        local row3d = GUIFrame:CreateRow(card3.content, 36)
        local showIconCheck = GUIFrame:CreateCheckbox(row3d, "Show Icon", selectedTracker.ShowIcon ~= false,
            function(checked)
                selectedTracker.ShowIcon = checked
                ApplySettings()
            end)
        row3d:AddWidget(showIconCheck, 0.5)
        table_insert(allWidgets, showIconCheck)

        local reverseCheck = GUIFrame:CreateCheckbox(row3d, "Reverse Fill", selectedTracker.Reverse == true,
            function(checked)
                selectedTracker.Reverse = checked
                ApplySettings()
            end)
        row3d:AddWidget(reverseCheck, 0.5)
        table_insert(allWidgets, reverseCheck)
        card3:AddRow(row3d, 36)

        yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall
    else
        local card3 = GUIFrame:CreateCard(scrollChild, "Tracker Settings", yOffset)
        table_insert(allWidgets, card3)
        card3:AddLabel("No trackers configured. Click 'Add New Tracker' to create one.")
        yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall
    end

    ----------------------------------------------------------------
    -- Card 4: General Bar Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "General Bar Settings", yOffset)
    table_insert(allWidgets, card4)
    local defaults = db.Defaults or {}

    local row4a = GUIFrame:CreateRow(card4.content, 36)
    local widthSlider = GUIFrame:CreateSlider(row4a, "Bar Width", 50, 500, 1, defaults.BarWidth or 200, 80,
        function(val)
            db.Defaults.BarWidth = val
            ApplySettings()
        end)
    row4a:AddWidget(widthSlider, 0.5)
    table_insert(allWidgets, widthSlider)

    local heightSlider = GUIFrame:CreateSlider(row4a, "Bar Height", 1, 100, 1, defaults.BarHeight or 20, 80,
        function(val)
            db.Defaults.BarHeight = val
            ApplySettings()
        end)
    row4a:AddWidget(heightSlider, 0.5)
    table_insert(allWidgets, heightSlider)
    card4:AddRow(row4a, 36)

    local row4b = GUIFrame:CreateRow(card4.content, 36)
    local defaultBarColorPicker = GUIFrame:CreateColorPicker(row4b, "Bar Color",
        defaults.BarColor or { 0.65, 0.65, 0.65, 1 },
        function(r, g, b, a)
            db.Defaults.BarColor = { r, g, b, a }
            ApplySettings()
        end)
    row4b:AddWidget(defaultBarColorPicker, 0.5)
    table_insert(allWidgets, defaultBarColorPicker)

    local bgColorPicker = GUIFrame:CreateColorPicker(row4b, "Background",
        defaults.BackgroundColor or { 0, 0, 0, 0.8 },
        function(r, g, b, a)
            db.Defaults.BackgroundColor = { r, g, b, a }
            ApplySettings()
        end)
    row4b:AddWidget(bgColorPicker, 0.5)
    table_insert(allWidgets, bgColorPicker)
    card4:AddRow(row4b, 36)

    local row4c = GUIFrame:CreateRow(card4.content, 36)
    local statusbarList = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do statusbarList[name] = name end
    else
        statusbarList["Blizzard"] = "Blizzard"
    end
    local statusbarDropdown = GUIFrame:CreateDropdown(row4c, "Bar Texture", statusbarList,
        defaults.StatusBarTexture or "Blizzard", 70,
        function(key)
            db.Defaults.StatusBarTexture = key
            ApplySettings()
        end)
    row4c:AddWidget(statusbarDropdown, 1)
    table_insert(allWidgets, statusbarDropdown)
    card4:AddRow(row4c, 36)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Position & Growth
    ----------------------------------------------------------------
    local posCard, newYOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position & Growth",
        db = db,
        showAnchorFrameType = true,
        showStrata = false,
        sliderRange = { -1000, 1000 },
        onChangeCallback = function()
            ApplyPosition()
        end,
    })
    table_insert(allWidgets, posCard)
    yOffset = newYOffset

    local growthCard = GUIFrame:CreateCard(scrollChild, "Growth Direction", yOffset)
    table_insert(allWidgets, growthCard)

    local growthRow = GUIFrame:CreateRow(growthCard.content, 36)

    local growthOptions = {
        { key = "DOWN",   text = "Down" },
        { key = "UP",     text = "Up" },
        { key = "LEFT",   text = "Left" },
        { key = "RIGHT",  text = "Right" },
        { key = "CENTER", text = "Center (Horizontal)" },
    }
    local growthDropdown = GUIFrame:CreateDropdown(growthRow, "Growth Direction", growthOptions,
        db.GrowthDirection or "DOWN", 100,
        function(key)
            db.GrowthDirection = key
            ApplySettings()
        end)
    growthRow:AddWidget(growthDropdown, 0.5)
    table_insert(allWidgets, growthDropdown)

    local spacingSlider = GUIFrame:CreateSlider(growthRow, "Spacing", 0, 20, 1, db.Spacing or 2, 60,
        function(val)
            db.Spacing = val
            ApplySettings()
        end)
    growthRow:AddWidget(spacingSlider, 0.5)
    table_insert(allWidgets, spacingSlider)

    growthCard:AddRow(growthRow, 36)
    yOffset = yOffset + growthCard:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
