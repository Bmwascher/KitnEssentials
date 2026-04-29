-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BlizzardMessages.lua                                ║
-- ║  GUI: Blizzard Texts                                     ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           BlizzardMessages module.                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local pairs = pairs

local ANCHOR_POINTS = {
    { key = "TOPLEFT",     text = "Top Left" },
    { key = "TOP",         text = "Top" },
    { key = "TOPRIGHT",    text = "Top Right" },
    { key = "LEFT",        text = "Left" },
    { key = "CENTER",      text = "Center" },
    { key = "RIGHT",       text = "Right" },
    { key = "BOTTOMLEFT",  text = "Bottom Left" },
    { key = "BOTTOM",      text = "Bottom" },
    { key = "BOTTOMRIGHT", text = "Bottom Right" },
}

local OUTLINE_OPTIONS = {
    { key = "NONE",         text = "None" },
    { key = "OUTLINE",      text = "Outline" },
    { key = "THICKOUTLINE", text = "Thick" },
}

local function GetBlizzardMessagesModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBlizzardMessages", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinMessages", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Messages
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local BM = GetBlizzardMessagesModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if BM and BM:IsEnabled() then
            BM:ApplySettings()
        end
    end

    local function ShowErrorPreview()
        if BM then BM:PreviewUIErrors() end
    end
    local function ShowZonePreview()
        if BM then BM:PreviewZone() end
    end
    local function ShowActionStatusPreview()
        if BM then BM:PreviewActionStatus() end
    end

    manager:SetCondition("error", function()
        return db.UIErrorsFrame and db.UIErrorsFrame.Hide == false
    end)
    manager:SetCondition("action", function()
        return db.ActionStatusText and db.ActionStatusText.Hide == false
    end)
    manager:SetCondition("bubble", function()
        return db.ChatBubbles and db.ChatBubbles.Enabled ~= false
    end)
    manager:SetCondition("objective", function()
        return db.ObjectiveTracker and db.ObjectiveTracker.Enabled ~= false
    end)
    manager:SetCondition("zone", function()
        return db.ZoneText and db.ZoneText.Hide == false
    end)

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    ----------------------------------------------------------------
    -- Card 1: Master Toggle
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Blizzard Texts", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Blizzard Text Skinning", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            if checked then
                KitnEssentials:EnableModule("SkinBlizzardMessages")
                ApplySettings()
            else
                KitnEssentials:DisableModule("SkinBlizzardMessages")
                KE:SkinningReloadPrompt()
            end
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Blizzard Text Skinning",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Global Font Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Font Settings For Blizzard Texts", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local fontDropdown = GUIFrame:CreateDropdown(row2a, "Font", {
        options = fontList,
        value = db.Font or "Friz Quadrata TT",
        callback = function(key)
            db.Font = key
            ApplySettings()
        end,
        searchable = true,
        isFontPreview = true,
    })
    row2a:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "all")

    local outlineDropdown = GUIFrame:CreateDropdown(row2a, "Outline", {
        options = OUTLINE_OPTIONS,
        value = db.FontOutline or "OUTLINE",
        callback = function(key)
            db.FontOutline = key
            ApplySettings()
        end,
    })
    row2a:AddWidget(outlineDropdown, 0.5)
    manager:Register(outlineDropdown, "all")
    card2:AddRow(row2a, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Error Messages (UIErrorsFrame)
    ----------------------------------------------------------------
    local errDb = db.UIErrorsFrame
    local card3 = GUIFrame:CreateCard(scrollChild, "Error Messages (Red Text)", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local hideErrCheck = GUIFrame:CreateCheckbox(row3a, "Hide Error Messages", {
        value = errDb.Hide == true,
        callback = function(checked)
            errDb.Hide = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row3a:AddWidget(hideErrCheck, 0.5)
    manager:Register(hideErrCheck, "all")

    local previewErrBtn = GUIFrame:CreateButton(row3a, "Preview", {
        callback = ShowErrorPreview,
        width = 80,
    })
    row3a:AddWidget(previewErrBtn, 0.5)
    manager:Register(previewErrBtn, "error")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local errSizeSlider = GUIFrame:CreateSlider(row3b, "Font Size", {
        min = 8, max = 24, step = 1,
        value = errDb.Size or 14,
        labelWidth = 60,
        callback = function(val)
            errDb.Size = val
            ApplySettings()
        end,
    })
    row3b:AddWidget(errSizeSlider, 1)
    manager:Register(errSizeSlider, "error")
    card3:AddRow(row3b, Theme.rowHeight)

    local row3sep = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3 = GUIFrame:CreateSeparator(row3sep)
    row3sep:AddWidget(sep3, 1)
    card3:AddRow(row3sep, Theme.rowHeightSeparator)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local errAnchorDropdown = GUIFrame:CreateDropdown(row3c, "Anchor", {
        options = ANCHOR_POINTS,
        value = errDb.Position.Anchor or "TOP",
        callback = function(key)
            errDb.Position.Anchor = key
            ApplySettings()
        end,
    })
    row3c:AddWidget(errAnchorDropdown, 1)
    manager:Register(errAnchorDropdown, "error")
    card3:AddRow(row3c, Theme.rowHeight)

    local row3d = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local errXSlider = GUIFrame:CreateSlider(row3d, "X Offset", {
        min = -500, max = 500, step = 1,
        value = errDb.Position.X or 0,
        labelWidth = 50,
        callback = function(val)
            errDb.Position.X = val
            ApplySettings()
        end,
    })
    row3d:AddWidget(errXSlider, 0.5)
    manager:Register(errXSlider, "error")

    local errYSlider = GUIFrame:CreateSlider(row3d, "Y Offset", {
        min = -500, max = 500, step = 1,
        value = errDb.Position.Y or -281,
        labelWidth = 50,
        callback = function(val)
            errDb.Position.Y = val
            ApplySettings()
        end,
    })
    row3d:AddWidget(errYSlider, 0.5)
    manager:Register(errYSlider, "error")
    card3:AddRow(row3d, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Action Status Text
    ----------------------------------------------------------------
    local actDb = db.ActionStatusText
    local card4 = GUIFrame:CreateCard(scrollChild, "Action Status Text (Yellow Text)", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local hideActCheck = GUIFrame:CreateCheckbox(row4a, "Hide Action Status", {
        value = actDb.Hide == true,
        callback = function(checked)
            actDb.Hide = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row4a:AddWidget(hideActCheck, 0.5)
    manager:Register(hideActCheck, "all")

    local previewActBtn = GUIFrame:CreateButton(row4a, "Preview", {
        callback = ShowActionStatusPreview,
        width = 80,
    })
    row4a:AddWidget(previewActBtn, 0.5)
    manager:Register(previewActBtn, "action")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local actSizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", {
        min = 8, max = 24, step = 1,
        value = actDb.Size or 14,
        labelWidth = 60,
        callback = function(val)
            actDb.Size = val
            ApplySettings()
        end,
    })
    row4b:AddWidget(actSizeSlider, 1)
    manager:Register(actSizeSlider, "action")
    card4:AddRow(row4b, Theme.rowHeight)

    local row4sep = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local sep4 = GUIFrame:CreateSeparator(row4sep)
    row4sep:AddWidget(sep4, 1)
    card4:AddRow(row4sep, Theme.rowHeightSeparator)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local actAnchorDropdown = GUIFrame:CreateDropdown(row4c, "Anchor", {
        options = ANCHOR_POINTS,
        value = actDb.Position.Anchor or "TOP",
        callback = function(key)
            actDb.Position.Anchor = key
            ApplySettings()
        end,
    })
    row4c:AddWidget(actAnchorDropdown, 1)
    manager:Register(actAnchorDropdown, "action")
    card4:AddRow(row4c, Theme.rowHeight)

    local row4d = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local actXSlider = GUIFrame:CreateSlider(row4d, "X Offset", {
        min = -500, max = 500, step = 1,
        value = actDb.Position.X or 0,
        labelWidth = 50,
        callback = function(val)
            actDb.Position.X = val
            ApplySettings()
        end,
    })
    row4d:AddWidget(actXSlider, 0.5)
    manager:Register(actXSlider, "action")

    local actYSlider = GUIFrame:CreateSlider(row4d, "Y Offset", {
        min = -500, max = 500, step = 1,
        value = actDb.Position.Y or -251,
        labelWidth = 50,
        callback = function(val)
            actDb.Position.Y = val
            ApplySettings()
        end,
    })
    row4d:AddWidget(actYSlider, 0.5)
    manager:Register(actYSlider, "action")
    card4:AddRow(row4d, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Chat Bubbles
    ----------------------------------------------------------------
    local bubbleDb = db.ChatBubbles
    local card5 = GUIFrame:CreateCard(scrollChild, "Chat Bubbles", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local enableBubblesCheck = GUIFrame:CreateCheckbox(row5a, "Enable Chat Bubble Styling", {
        value = bubbleDb.Enabled ~= false,
        callback = function(checked)
            bubbleDb.Enabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row5a:AddWidget(enableBubblesCheck, 0.5)
    manager:Register(enableBubblesCheck, "all")

    local bubbleSizeSlider = GUIFrame:CreateSlider(row5a, "Font Size", {
        min = 6, max = 18, step = 1,
        value = bubbleDb.Size or 8,
        labelWidth = 60,
        callback = function(val)
            bubbleDb.Size = val
            ApplySettings()
        end,
    })
    row5a:AddWidget(bubbleSizeSlider, 0.5)
    manager:Register(bubbleSizeSlider, "bubble")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5sep = GUIFrame:CreateRow(card5.content, Theme.rowHeightSeparator)
    local sep5 = GUIFrame:CreateSeparator(row5sep)
    row5sep:AddWidget(sep5, 1)
    card5:AddRow(row5sep, Theme.rowHeightSeparator)

    local textRow5Size = 145
    local row5b = GUIFrame:CreateRow(card5.content, textRow5Size)
    local chatBubbleText = GUIFrame:CreateText(row5b,
        KE:ColorTextByTheme("Recommended"),
        ("ChatBubbleReplacements by " .. "|cff00e0ffLuckyone. |r" ..
            "\nReplaces backdrop with custom styling.\n\n" ..
            KE:ColorTextByTheme("Available modes") .. "\n" ..
            KE:ColorTextByTheme("• ") .. "Invisible Backdrop" ..
            "\n" .. KE:ColorTextByTheme("• ") .. "Small Backdrop" ..
            "\n" .. KE:ColorTextByTheme("• ") .. "Medium Backdrop" ..
            "\n" .. KE:ColorTextByTheme("• ") .. "Large Backdrop"),
        textRow5Size, "hide")
    row5b:AddWidget(chatBubbleText, 0.5)
    manager:Register(chatBubbleText, "bubble")

    local getLinkBtn = GUIFrame:CreateButton(row5b, "Get Skin Here", {
        callback = function()
            KE:CreatePrompt(
                "ChatBubbleReplacements By |cff00e0ffLuckyone|r",
                "https://github.com/Luckyone961/ChatBubbleReplacements",
                true,
                "Copy to clipboard by pressing CTRL + C",
                true
            )
        end,
        width = 80,
        height = 40,
    })
    row5b:AddWidget(getLinkBtn, 0.5)
    manager:Register(getLinkBtn, "bubble")
    card5:AddRow(row5b, textRow5Size, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Objective Tracker
    ----------------------------------------------------------------
    local objDb = db.ObjectiveTracker
    local card6 = GUIFrame:CreateCard(scrollChild, "Objective Tracker", yOffset)
    manager:Register(card6, "all")

    local row6a = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local enableObjCheck = GUIFrame:CreateCheckbox(row6a, "Enable Objective Tracker Styling", {
        value = objDb.Enabled ~= false,
        callback = function(checked)
            objDb.Enabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row6a:AddWidget(enableObjCheck, 1)
    manager:Register(enableObjCheck, "all")
    card6:AddRow(row6a, Theme.rowHeight)

    local row6b = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local questTitleSlider = GUIFrame:CreateSlider(row6b, "Quest Title Size", {
        min = 8, max = 20, step = 1,
        value = objDb.QuestTitleSize or 13,
        labelWidth = 80,
        callback = function(val)
            objDb.QuestTitleSize = val
            ApplySettings()
        end,
    })
    row6b:AddWidget(questTitleSlider, 0.5)
    manager:Register(questTitleSlider, "objective")

    local questTextSlider = GUIFrame:CreateSlider(row6b, "Quest Text Size", {
        min = 8, max = 20, step = 1,
        value = objDb.QuestTextSize or 12,
        labelWidth = 80,
        callback = function(val)
            objDb.QuestTextSize = val
            ApplySettings()
        end,
    })
    row6b:AddWidget(questTextSlider, 0.5)
    manager:Register(questTextSlider, "objective")
    card6:AddRow(row6b, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Zone Texts
    ----------------------------------------------------------------
    local zoneDB = db.ZoneText
    local card7 = GUIFrame:CreateCard(scrollChild, "Zone Texts", yOffset)
    manager:Register(card7, "all")

    local row7 = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local zoneHideCheck = GUIFrame:CreateCheckbox(row7, "Hide Zone Texts", {
        value = zoneDB.Hide == true,
        callback = function(checked)
            zoneDB.Hide = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row7:AddWidget(zoneHideCheck, 0.5)
    manager:Register(zoneHideCheck, "all")

    local previewZoneBtn = GUIFrame:CreateButton(row7, "Preview", {
        callback = ShowZonePreview,
        width = 80,
    })
    row7:AddWidget(previewZoneBtn, 0.5)
    manager:Register(previewZoneBtn, "zone")
    card7:AddRow(row7, Theme.rowHeight)

    local row8 = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local mainZoneSlider = GUIFrame:CreateSlider(row8, "Main Zone Size", {
        min = 8, max = 100, step = 1,
        value = zoneDB.MainZone.Size,
        labelWidth = 80,
        callback = function(val)
            zoneDB.MainZone.Size = val
            ApplySettings()
        end,
    })
    row8:AddWidget(mainZoneSlider, 0.5)
    manager:Register(mainZoneSlider, "zone")

    local subZoneSlider = GUIFrame:CreateSlider(row8, "Sub Zone Size", {
        min = 8, max = 100, step = 1,
        value = zoneDB.SubZone.Size,
        callback = function(val)
            zoneDB.SubZone.Size = val
            ApplySettings()
        end,
    })
    row8:AddWidget(subZoneSlider, 0.5)
    manager:Register(subZoneSlider, "zone")
    card7:AddRow(row8, Theme.rowHeight)

    local row7sep = GUIFrame:CreateRow(card7.content, Theme.rowHeightSeparator)
    local sep7 = GUIFrame:CreateSeparator(row7sep)
    row7sep:AddWidget(sep7, 1)
    card7:AddRow(row7sep, Theme.rowHeightSeparator)

    local row9 = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local zoneAnchorDropdown = GUIFrame:CreateDropdown(row9, "Anchor", {
        options = ANCHOR_POINTS,
        value = zoneDB.MainZone.Anchor or "TOP",
        callback = function(key)
            zoneDB.MainZone.Anchor = key
            ApplySettings()
        end,
    })
    row9:AddWidget(zoneAnchorDropdown, 1)
    manager:Register(zoneAnchorDropdown, "zone")
    card7:AddRow(row9, Theme.rowHeight)

    local row10 = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
    local zoneXSlider = GUIFrame:CreateSlider(row10, "X Offset", {
        min = -500, max = 500, step = 1,
        value = zoneDB.MainZone.X,
        labelWidth = 50,
        callback = function(val)
            zoneDB.MainZone.X = val
            ApplySettings()
        end,
    })
    row10:AddWidget(zoneXSlider, 0.5)
    manager:Register(zoneXSlider, "zone")

    local zoneYSlider = GUIFrame:CreateSlider(row10, "Y Offset", {
        min = -500, max = 500, step = 1,
        value = zoneDB.MainZone.Y,
        labelWidth = 50,
        callback = function(val)
            zoneDB.MainZone.Y = val
            ApplySettings()
        end,
    })
    row10:AddWidget(zoneYSlider, 0.5)
    manager:Register(zoneYSlider, "zone")
    card7:AddRow(row10, Theme.rowHeightLast, 0)

    yOffset = card7:GetNextOffset()

    RefreshStates()
    return yOffset
end)
