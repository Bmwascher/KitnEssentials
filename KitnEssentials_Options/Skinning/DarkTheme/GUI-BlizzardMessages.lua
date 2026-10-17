-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BlizzardMessages.lua                                ║
-- ║  GUI: Blizzard Text and On-Screen Messages               ║
-- ║  Purpose: Fonts sub-tabs for the BlizzardFonts and       ║
-- ║           BlizzardMessages modules.                      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
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

local OUTLINE_OPTIONS = KE:GetFontOutlineOptions()

local function GetBlizzardMessagesModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBlizzardMessages", true)
    end
    return nil
end

----------------------------------------------------------------
-- Blizzard Text: the font-object sweep and its sizes
----------------------------------------------------------------
GUIFrame:RegisterContent("SkinBlizzardFramesFontsBlizzard", function(scrollChild, yOffset)
    local fontsDb = KE.db and KE.db.profile.Skinning.BlizzardFonts
    if not fontsDb then return yOffset end
    -- The base size is stored in the frame-skin table because the skin engine
    -- reads it from there.
    local framesDb = KE.db.profile.Skinning.BlizzardFrames
    fontsDb.Sizes = fontsDb.Sizes or {}
    local sizes = fontsDb.Sizes

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("sweep", function() return fontsDb.Enabled == true end)

    local function RefreshStates()
        manager:UpdateAll(true)
    end

    local function ReapplyFonts()
        local bf = KitnEssentials:GetModule("BlizzardFonts", true)
        if bf and fontsDb.Enabled and bf.ApplyAll then bf:ApplyAll() end
    end

    local cardAll = GUIFrame:CreateCard(scrollChild, "Blizzard Text Everywhere", yOffset)
    cardAll:AddLabel("Quest text, the objective tracker, mail and numbers, in the skinned-window font. Base Size also sizes the Blizzard Fonts row on Frame Skins.")

    local rowAll = GUIFrame:CreateRow(cardAll.content, Theme.rowHeightLast)
    rowAll:AddWidget(GUIFrame:CreateCheckbox(rowAll, "Replace All Blizzard Fonts", {
        value = fontsDb.Enabled == true,
        callback = function(checked)
            fontsDb.Enabled = checked
            local bf = KitnEssentials:GetModule("BlizzardFonts", true)
            if checked then
                KitnEssentials:EnableModule("BlizzardFonts")
                if bf then bf:ApplyAll() end
            else
                KitnEssentials:DisableModule("BlizzardFonts")
                KE:FlagReloadNeeded()
            end
            RefreshStates()
        end,
    }), 0.5)

    -- Not gated by Replace All: the window-skin font sweep scales from it too.
    if framesDb then
        rowAll:AddWidget(GUIFrame:CreateSlider(rowAll, "Base Size", {
            min = 8, max = 18, step = 1, value = framesDb.FontBaseSize or 12,
            tooltip = "Base size every Blizzard font object scales from unless it has a size of its own below. 12 is Blizzard's baseline.",
            callback = function(val)
                framesDb.FontBaseSize = val
                if KE.Skins and KE.Skins.ApplyGlobalFonts then
                    KE.Skins.ApplyGlobalFonts()
                end
                -- The font sweep scales every unoverridden font object off this
                -- same base, so it has to re-run or the two systems drift apart.
                ReapplyFonts()
            end,
        }), 0.5)
    end
    cardAll:AddRow(rowAll, Theme.rowHeightLast, 0)

    yOffset = cardAll:GetNextOffset()

    local cardSizes = GUIFrame:CreateCard(scrollChild, "Category Sizes", yOffset)
    manager:Register(cardSizes, "sweep")
    cardSizes:AddLabel("One size per category, overriding Base Size. Grayed while Replace All Blizzard Fonts is off.")

    local rowA = GUIFrame:CreateRow(cardSizes.content, Theme.rowHeight)
    rowA:AddWidget(GUIFrame:CreateSlider(rowA, "Objective Tracker", {
        min = 8, max = 20, step = 1, value = sizes.Objective or 13,
        callback = function(val) sizes.Objective = val; ReapplyFonts() end,
    }), 0.5)
    rowA:AddWidget(GUIFrame:CreateSlider(rowA, "Mail Body", {
        min = 8, max = 20, step = 1, value = sizes.MailBody or 13,
        callback = function(val) sizes.MailBody = val; ReapplyFonts() end,
    }), 0.5)
    cardSizes:AddRow(rowA, Theme.rowHeight)

    local rowB = GUIFrame:CreateRow(cardSizes.content, Theme.rowHeight)
    rowB:AddWidget(GUIFrame:CreateSlider(rowB, "Quest Title", {
        min = 8, max = 24, step = 1, value = sizes.QuestTitle or 14,
        callback = function(val) sizes.QuestTitle = val; ReapplyFonts() end,
    }), 0.5)
    rowB:AddWidget(GUIFrame:CreateSlider(rowB, "Quest Text", {
        min = 8, max = 20, step = 1, value = sizes.QuestText or 13,
        callback = function(val) sizes.QuestText = val; ReapplyFonts() end,
    }), 0.5)
    cardSizes:AddRow(rowB, Theme.rowHeight)

    local rowC = GUIFrame:CreateRow(cardSizes.content, Theme.rowHeightLast)
    rowC:AddWidget(GUIFrame:CreateSlider(rowC, "Quest Text (Small)", {
        min = 8, max = 18, step = 1, value = sizes.QuestSmall or 12,
        callback = function(val) sizes.QuestSmall = val; ReapplyFonts() end,
    }), 0.5)
    cardSizes:AddRow(rowC, Theme.rowHeightLast, 0)

    yOffset = cardSizes:GetNextOffset()

    RefreshStates()
    return yOffset
end)

----------------------------------------------------------------
-- On-Screen Messages: the BlizzardMessages module
----------------------------------------------------------------
GUIFrame:RegisterContent("SkinMessages", function(scrollChild, yOffset)
    -- Return the offset, not nil: as a tab, nil propagates out of
    -- RegisterTabbedContent and the outer builder draws a placeholder over
    -- the header card and tab strips. The strip never offers this tab under
    -- ElvUI, so this only keeps the page safe if that gating changes.
    if KE:ShouldNotLoadModule() then return yOffset end
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

    local card = GUIFrame:CreateCard(scrollChild, "On-Screen Messages", yOffset)
    card:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        if checked then
            KitnEssentials:EnableModule("SkinBlizzardMessages")
            ApplySettings()
        else
            KitnEssentials:DisableModule("SkinBlizzardMessages")
            KE:FlagReloadNeeded()
        end
    end)

    -- Lone header bar: a disabled module shows only its switch.
    if db.Enabled == false then return card:GetNextOffset() end

    card:AddLabel("The red error line, the yellow action text, zone names and chat bubbles.")

    local rowFace = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local fontDropdown = GUIFrame:CreateDropdown(rowFace, "Font", {
        options = KE:AddFollowGlobalFont(fontList),
        value = db.Font or KE.FONT_FOLLOW_GLOBAL,
        callback = function(key)
            db.Font = KE:StoredFontFace(key)
            ApplySettings()
        end,
        searchable = true,
        isFontPreview = true,
    })
    rowFace:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "all")

    local outlineDropdown = GUIFrame:CreateDropdown(rowFace, "Outline", {
        options = OUTLINE_OPTIONS,
        value = KE:NormalizeFontOutline(db.FontOutline or "OUTLINE"),
        callback = function(key)
            db.FontOutline = key
            ApplySettings()
        end,
    })
    rowFace:AddWidget(outlineDropdown, 0.5)
    manager:Register(outlineDropdown, "all")
    card:AddRow(rowFace, Theme.rowHeight)

    local function AddHeading(text)
        card:AddSeparator()
        card:AddLabel(KE:ColorTextByTheme(text))
    end

    ----------------------------------------------------------------
    -- Error messages (UIErrorsFrame)
    ----------------------------------------------------------------
    local errDb = db.UIErrorsFrame
    AddHeading("Error messages (red)")

    local rowErr = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local hideErrCheck = GUIFrame:CreateCheckbox(rowErr, "Hide", {
        value = errDb.Hide == true,
        callback = function(checked)
            errDb.Hide = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    rowErr:AddWidget(hideErrCheck, 0.25)
    manager:Register(hideErrCheck, "all")

    local errSizeSlider = GUIFrame:CreateSlider(rowErr, "Size", {
        min = 8, max = 24, step = 1,
        value = errDb.Size or 14,
        callback = function(val)
            errDb.Size = val
            ApplySettings()
        end,
    })
    rowErr:AddWidget(errSizeSlider, 0.5)
    manager:Register(errSizeSlider, "error")

    local previewErrBtn = GUIFrame:CreateButton(rowErr, "Preview", {
        callback = ShowErrorPreview,
        width = 80,
    })
    rowErr:AddWidget(previewErrBtn, 0.25)
    manager:Register(previewErrBtn, "error")
    card:AddRow(rowErr, Theme.rowHeight)

    local rowErrPos = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local errAnchorDropdown = GUIFrame:CreateDropdown(rowErrPos, "Anchor", {
        options = ANCHOR_POINTS,
        value = errDb.Position.Anchor or "TOP",
        callback = function(key)
            errDb.Position.Anchor = key
            ApplySettings()
        end,
    })
    rowErrPos:AddWidget(errAnchorDropdown, 0.34)
    manager:Register(errAnchorDropdown, "error")

    local errXSlider = GUIFrame:CreateSlider(rowErrPos, "X Offset", {
        min = -500, max = 500, step = 1,
        value = errDb.Position.X or 0,
        callback = function(val)
            errDb.Position.X = val
            ApplySettings()
        end,
    })
    rowErrPos:AddWidget(errXSlider, 0.33)
    manager:Register(errXSlider, "error")

    local errYSlider = GUIFrame:CreateSlider(rowErrPos, "Y Offset", {
        min = -500, max = 500, step = 1,
        value = errDb.Position.Y or -281,
        callback = function(val)
            errDb.Position.Y = val
            ApplySettings()
        end,
    })
    rowErrPos:AddWidget(errYSlider, 0.33)
    manager:Register(errYSlider, "error")
    card:AddRow(rowErrPos, Theme.rowHeight)

    ----------------------------------------------------------------
    -- Action status (ActionStatusText)
    ----------------------------------------------------------------
    local actDb = db.ActionStatusText
    AddHeading("Action status (yellow)")

    local rowAct = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local hideActCheck = GUIFrame:CreateCheckbox(rowAct, "Hide", {
        value = actDb.Hide == true,
        callback = function(checked)
            actDb.Hide = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    rowAct:AddWidget(hideActCheck, 0.25)
    manager:Register(hideActCheck, "all")

    local actSizeSlider = GUIFrame:CreateSlider(rowAct, "Size", {
        min = 8, max = 24, step = 1,
        value = actDb.Size or 14,
        callback = function(val)
            actDb.Size = val
            ApplySettings()
        end,
    })
    rowAct:AddWidget(actSizeSlider, 0.5)
    manager:Register(actSizeSlider, "action")

    local previewActBtn = GUIFrame:CreateButton(rowAct, "Preview", {
        callback = ShowActionStatusPreview,
        width = 80,
    })
    rowAct:AddWidget(previewActBtn, 0.25)
    manager:Register(previewActBtn, "action")
    card:AddRow(rowAct, Theme.rowHeight)

    local rowActPos = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local actAnchorDropdown = GUIFrame:CreateDropdown(rowActPos, "Anchor", {
        options = ANCHOR_POINTS,
        value = actDb.Position.Anchor or "TOP",
        callback = function(key)
            actDb.Position.Anchor = key
            ApplySettings()
        end,
    })
    rowActPos:AddWidget(actAnchorDropdown, 0.34)
    manager:Register(actAnchorDropdown, "action")

    local actXSlider = GUIFrame:CreateSlider(rowActPos, "X Offset", {
        min = -500, max = 500, step = 1,
        value = actDb.Position.X or 0,
        callback = function(val)
            actDb.Position.X = val
            ApplySettings()
        end,
    })
    rowActPos:AddWidget(actXSlider, 0.33)
    manager:Register(actXSlider, "action")

    local actYSlider = GUIFrame:CreateSlider(rowActPos, "Y Offset", {
        min = -500, max = 500, step = 1,
        value = actDb.Position.Y or -251,
        callback = function(val)
            actDb.Position.Y = val
            ApplySettings()
        end,
    })
    rowActPos:AddWidget(actYSlider, 0.33)
    manager:Register(actYSlider, "action")
    card:AddRow(rowActPos, Theme.rowHeight)

    ----------------------------------------------------------------
    -- Zone names (ZoneTextFrame)
    ----------------------------------------------------------------
    local zoneDB = db.ZoneText
    AddHeading("Zone names")

    local rowZone = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local zoneHideCheck = GUIFrame:CreateCheckbox(rowZone, "Hide", {
        value = zoneDB.Hide == true,
        callback = function(checked)
            zoneDB.Hide = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    rowZone:AddWidget(zoneHideCheck, 0.25)
    manager:Register(zoneHideCheck, "all")

    local mainZoneSlider = GUIFrame:CreateSlider(rowZone, "Main Size", {
        min = 8, max = 100, step = 1,
        value = zoneDB.MainZone.Size,
        callback = function(val)
            zoneDB.MainZone.Size = val
            ApplySettings()
        end,
    })
    rowZone:AddWidget(mainZoneSlider, 0.25)
    manager:Register(mainZoneSlider, "zone")

    local subZoneSlider = GUIFrame:CreateSlider(rowZone, "Sub Size", {
        min = 8, max = 100, step = 1,
        value = zoneDB.SubZone.Size,
        callback = function(val)
            zoneDB.SubZone.Size = val
            ApplySettings()
        end,
    })
    rowZone:AddWidget(subZoneSlider, 0.25)
    manager:Register(subZoneSlider, "zone")

    local previewZoneBtn = GUIFrame:CreateButton(rowZone, "Preview", {
        callback = ShowZonePreview,
        width = 80,
    })
    rowZone:AddWidget(previewZoneBtn, 0.25)
    manager:Register(previewZoneBtn, "zone")
    card:AddRow(rowZone, Theme.rowHeight)

    local rowZonePos = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local zoneAnchorDropdown = GUIFrame:CreateDropdown(rowZonePos, "Anchor", {
        options = ANCHOR_POINTS,
        value = zoneDB.MainZone.Anchor or "TOP",
        callback = function(key)
            zoneDB.MainZone.Anchor = key
            ApplySettings()
        end,
    })
    rowZonePos:AddWidget(zoneAnchorDropdown, 0.34)
    manager:Register(zoneAnchorDropdown, "zone")

    local zoneXSlider = GUIFrame:CreateSlider(rowZonePos, "X Offset", {
        min = -500, max = 500, step = 1,
        value = zoneDB.MainZone.X,
        callback = function(val)
            zoneDB.MainZone.X = val
            ApplySettings()
        end,
    })
    rowZonePos:AddWidget(zoneXSlider, 0.33)
    manager:Register(zoneXSlider, "zone")

    local zoneYSlider = GUIFrame:CreateSlider(rowZonePos, "Y Offset", {
        min = -500, max = 500, step = 1,
        value = zoneDB.MainZone.Y,
        callback = function(val)
            zoneDB.MainZone.Y = val
            ApplySettings()
        end,
    })
    rowZonePos:AddWidget(zoneYSlider, 0.33)
    manager:Register(zoneYSlider, "zone")
    card:AddRow(rowZonePos, Theme.rowHeight)

    ----------------------------------------------------------------
    -- Chat bubbles
    ----------------------------------------------------------------
    local bubbleDb = db.ChatBubbles
    AddHeading("Chat bubbles")

    local rowBubble = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local enableBubblesCheck = GUIFrame:CreateCheckbox(rowBubble, "Style Bubbles", {
        value = bubbleDb.Enabled ~= false,
        callback = function(checked)
            bubbleDb.Enabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    rowBubble:AddWidget(enableBubblesCheck, 0.25)
    manager:Register(enableBubblesCheck, "all")

    local bubbleSizeSlider = GUIFrame:CreateSlider(rowBubble, "Size", {
        min = 6, max = 18, step = 1,
        value = bubbleDb.Size or 8,
        callback = function(val)
            bubbleDb.Size = val
            ApplySettings()
        end,
    })
    rowBubble:AddWidget(bubbleSizeSlider, 0.5)
    manager:Register(bubbleSizeSlider, "bubble")

    local getLinkBtn = GUIFrame:CreateButton(rowBubble, "Get Skin", {
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
    })
    rowBubble:AddWidget(getLinkBtn, 0.25)
    manager:Register(getLinkBtn, "bubble")
    card:AddRow(rowBubble, Theme.rowHeight)

    card:AddNote("Recommended: ChatBubbleReplacements by Luckyone swaps the bubble backdrop (invisible, small, medium or large).")

    yOffset = card:GetNextOffset()

    RefreshStates()
    return yOffset
end)
