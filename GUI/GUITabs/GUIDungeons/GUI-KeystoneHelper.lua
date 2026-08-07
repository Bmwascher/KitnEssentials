-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KeystoneHelper.lua                                  ║
-- ║  GUI: Keystone Helper                                    ║
-- ║  Purpose: Container page over four tabs. General hosts    ║
-- ║           the three group-finder pages, which are not     ║
-- ║           keystone features but are dungeon tools with    ║
-- ║           no sidebar row of their own. The other three    ║
-- ║           are the module's features, each with its own    ║
-- ║           switch and its own appearance.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("KeystoneHelper", true)
end

local function GetDB()
    return KE.db and KE.db.profile.KeystoneHelper
end

local function ApplySettings()
    local KH = GetModule()
    if KH and KH.ApplySettings then KH:ApplySettings() end
end

-- Tells the module which reminder holds the Edit Mode mover while the two
-- share a position. GUI depends on the module, never the reverse.
local function FocusReminder(prefix)
    local KH = GetModule()
    if KH and KH.SetEditModeFocus then KH:SetEditModeFocus(prefix) end
end

-- Every tab needs the same guard, and a tab that silently renders nothing is
-- worse than one that says why.
local function MissingDB(scrollChild, yOffset)
    local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
    errorCard:AddLabel("Database not available.")
    return errorCard:GetNextOffset()
end

----------------------------------------------------------------
-- General: the three group-finder pages
--
-- Chained, not re-registered: each builder takes (scrollChild, yOffset) and
-- returns the next offset, which is the same contract RegisterTabbedContent
-- uses. Resolved live so GUI.xml load order does not matter. None of the three
-- reads this page's db, so there is no guard here.
----------------------------------------------------------------
GUIFrame:RegisterContent("KeystoneHelperGeneral", function(scrollChild, yOffset)
    for _, id in ipairs({ "GroupFinderPanel", "LFGQuickCreate", "LFGReminder" }) do
        local builder = GUIFrame.registeredContent and GUIFrame.registeredContent[id]
        if builder then yOffset = builder(scrollChild, yOffset) end
    end
    return yOffset
end)

----------------------------------------------------------------
-- Instance Reset: Instance Reset Announcer
----------------------------------------------------------------
GUIFrame:RegisterContent("KeystoneHelperReset", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return MissingDB(scrollChild, yOffset) end

    local manager = GUIFrame:CreateWidgetStateManager()

    local cardReset = GUIFrame:CreateCard(scrollChild, "Instance Reset Announcer", yOffset)
    manager:Register(cardReset, "all")

    local rowReset1 = GUIFrame:CreateRow(cardReset.content, Theme.rowHeight)
    local resetEnableCheck = GUIFrame:CreateCheckbox(rowReset1, "Announce on Instance Reset", {
        value = db.ResetEnabled ~= false,
        callback = function(checked) db.ResetEnabled = checked; ApplySettings() end,
        msgPopup = true,
        msgText = "Reset Announcer",
        msgOn = "On",
        msgOff = "Off",
    })
    rowReset1:AddWidget(resetEnableCheck, 1)
    manager:Register(resetEnableCheck, "all")
    cardReset:AddRow(rowReset1, Theme.rowHeight)

    local rowReset2 = GUIFrame:CreateRow(cardReset.content, Theme.rowHeightLast)
    local resetMessageBox = GUIFrame:CreateEditBox(rowReset2, "Chat Message", {
        value = db.ResetMessage or "Instance reset!",
        callback = function(val)
            db.ResetMessage = (val ~= "" and val) or "Instance reset!"
            ApplySettings()
        end,
    })
    rowReset2:AddWidget(resetMessageBox, 1)
    manager:Register(resetMessageBox, "all")
    cardReset:AddRow(rowReset2, Theme.rowHeightLast, 0)

    yOffset = cardReset:GetNextOffset()

    manager:UpdateAll(true)
    return yOffset
end)

----------------------------------------------------------------
-- Reroll Key: switch, font, appearance, position, glow
----------------------------------------------------------------
GUIFrame:RegisterContent("KeystoneHelperReroll", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return MissingDB(scrollChild, yOffset) end

    FocusReminder("Reroll")

    local cardMain = GUIFrame:CreateCard(scrollChild, "Reroll Key Reminder", yOffset)
    cardMain:AddHeaderToggle(db.RerollEnabled ~= false, function(checked)
        db.RerollEnabled = checked
        ApplySettings()
        KE:Print("Reroll Reminder: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    -- Lone header bar: a disabled reminder shows its switch and nothing else.
    if db.RerollEnabled == false then return cardMain:GetNextOffset() end

    cardMain:AddLabel("Shown after you finish a keystone in time, while your own key can still be rerolled. Hides itself after five minutes.")
    yOffset = cardMain:GetNextOffset()

    local manager = GUIFrame:CreateWidgetStateManager()

    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "RerollFontFace",
            fontSize = "RerollFontSize",
            fontOutline = "RerollFontOutline",
        },
        fontSizeRange = { 16, 72 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then manager:RegisterGroup(fontWidgets, "all") end
    yOffset = fontOffset

    local cardLook = GUIFrame:CreateCard(scrollChild, "Reminder Appearance", yOffset)
    manager:Register(cardLook, "all")

    local rowL1 = GUIFrame:CreateRow(cardLook.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(rowL1, "Icon Size", {
        min = 20, max = 120, step = 1,
        value = db.RerollSize or 64,
        callback = function(val) db.RerollSize = val; ApplySettings() end,
    })
    rowL1:AddWidget(sizeSlider, 1)
    manager:Register(sizeSlider, "all")
    cardLook:AddRow(rowL1, Theme.rowHeight)

    local rowL2 = GUIFrame:CreateRow(cardLook.content, Theme.rowHeightLast)
    local titleColorPicker = GUIFrame:CreateColorPicker(rowL2, "Title Color", {
        color = db.RerollFontColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.RerollFontColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowL2:AddWidget(titleColorPicker, 0.5)
    manager:Register(titleColorPicker, "all")

    local keyColorPicker = GUIFrame:CreateColorPicker(rowL2, "Key Text Color", {
        color = db.RerollFontColorKey or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.RerollFontColorKey = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowL2:AddWidget(keyColorPicker, 0.5)
    manager:Register(keyColorPicker, "all")
    cardLook:AddRow(rowL2, Theme.rowHeightLast, 0)

    yOffset = cardLook:GetNextOffset()

    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Reminder Position",
        db = db,
        positionKey = "RerollPosition",
        dbKeys = {
            anchorFrameType = "RerollAnchorFrameType",
            anchorFrameFrame = "RerollParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "RerollStrata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(posCard, "all")
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    yOffset = posOffset

    local cardRerollGlow = GUIFrame:CreateCard(scrollChild, "Reroll Glow", yOffset)
    manager:Register(cardRerollGlow, "all")

    local rowRG1 = GUIFrame:CreateRow(cardRerollGlow.content, Theme.rowHeight)
    local rerollGlowEnableCheck = GUIFrame:CreateCheckbox(rowRG1, "Enable Glow", {
        value = db.RerollGlowEnabled ~= false,
        callback = function(checked) db.RerollGlowEnabled = checked; ApplySettings() end,
    })
    rowRG1:AddWidget(rerollGlowEnableCheck, 0.5)
    manager:Register(rerollGlowEnableCheck, "all")

    local rerollGlowColor = GUIFrame:CreateColorPicker(rowRG1, "Glow Color", {
        color = db.RerollGlowColor or { 0, 1, 0, 1 },
        callback = function(r, g, b, a)
            db.RerollGlowColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowRG1:AddWidget(rerollGlowColor, 0.5)
    manager:Register(rerollGlowColor, "all")
    cardRerollGlow:AddRow(rowRG1, Theme.rowHeight)

    local rowRG2 = GUIFrame:CreateRow(cardRerollGlow.content, Theme.rowHeight)
    local rerollGlowLines = GUIFrame:CreateSlider(rowRG2, "Lines", {
        min = 1, max = 16, step = 1,
        value = db.RerollGlowLines or 5,
        callback = function(val) db.RerollGlowLines = val; ApplySettings() end,
    })
    rowRG2:AddWidget(rerollGlowLines, 0.5)
    manager:Register(rerollGlowLines, "all")

    local rerollGlowLength = GUIFrame:CreateSlider(rowRG2, "Length", {
        min = 1, max = 20, step = 1,
        value = db.RerollGlowLength or 10,
        callback = function(val) db.RerollGlowLength = val; ApplySettings() end,
    })
    rowRG2:AddWidget(rerollGlowLength, 0.5)
    manager:Register(rerollGlowLength, "all")
    cardRerollGlow:AddRow(rowRG2, Theme.rowHeight)

    local rowRG3 = GUIFrame:CreateRow(cardRerollGlow.content, Theme.rowHeightLast)
    local rerollGlowFrequency = GUIFrame:CreateSlider(rowRG3, "Speed", {
        min = 0.05, max = 1, step = 0.05,
        value = db.RerollGlowFrequency or 0.25,
        callback = function(val) db.RerollGlowFrequency = val; ApplySettings() end,
    })
    rowRG3:AddWidget(rerollGlowFrequency, 0.5)
    manager:Register(rerollGlowFrequency, "all")

    local rerollGlowThickness = GUIFrame:CreateSlider(rowRG3, "Thickness", {
        min = 1, max = 8, step = 1,
        value = db.RerollGlowThickness or 2,
        callback = function(val) db.RerollGlowThickness = val; ApplySettings() end,
    })
    rowRG3:AddWidget(rerollGlowThickness, 0.5)
    manager:Register(rerollGlowThickness, "all")
    cardRerollGlow:AddRow(rowRG3, Theme.rowHeightLast, 0)

    yOffset = cardRerollGlow:GetNextOffset()

    manager:UpdateAll(true)
    return yOffset
end)

----------------------------------------------------------------
-- Your Key: switch, font, appearance, position source, position, glow
----------------------------------------------------------------
GUIFrame:RegisterContent("KeystoneHelperYourKey", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return MissingDB(scrollChild, yOffset) end

    FocusReminder("YourKey")

    local cardMain = GUIFrame:CreateCard(scrollChild, "Your Key Reminder", yOffset)
    cardMain:AddHeaderToggle(db.YourKeyEnabled ~= false, function(checked)
        db.YourKeyEnabled = checked
        ApplySettings()
        KE:Print("Your Key Reminder: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    if db.YourKeyEnabled == false then return cardMain:GetNextOffset() end

    cardMain:AddLabel("Shown while you stand in a Mythic 0 of the dungeon your own keystone points at, so you remember to slot it. Hides itself after five minutes.")
    yOffset = cardMain:GetNextOffset()

    local manager = GUIFrame:CreateWidgetStateManager()
    -- The position card is the one group with a condition: following the Reroll
    -- position means these controls do nothing, so they read as locked.
    manager:SetCondition("ownposition", function()
        return db.YourKeyUseRerollPosition == false
    end)

    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "YourKeyFontFace",
            fontSize = "YourKeyFontSize",
            fontOutline = "YourKeyFontOutline",
        },
        fontSizeRange = { 16, 72 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then manager:RegisterGroup(fontWidgets, "all") end
    yOffset = fontOffset

    local cardLook = GUIFrame:CreateCard(scrollChild, "Reminder Appearance", yOffset)
    manager:Register(cardLook, "all")

    local rowL1 = GUIFrame:CreateRow(cardLook.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(rowL1, "Icon Size", {
        min = 20, max = 120, step = 1,
        value = db.YourKeySize or 64,
        callback = function(val) db.YourKeySize = val; ApplySettings() end,
    })
    rowL1:AddWidget(sizeSlider, 1)
    manager:Register(sizeSlider, "all")
    cardLook:AddRow(rowL1, Theme.rowHeight)

    local rowL2 = GUIFrame:CreateRow(cardLook.content, Theme.rowHeightLast)
    local titleColorPicker = GUIFrame:CreateColorPicker(rowL2, "Title Color", {
        color = db.YourKeyFontColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.YourKeyFontColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowL2:AddWidget(titleColorPicker, 0.5)
    manager:Register(titleColorPicker, "all")

    local keyColorPicker = GUIFrame:CreateColorPicker(rowL2, "Key Text Color", {
        color = db.YourKeyFontColorKey or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.YourKeyFontColorKey = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowL2:AddWidget(keyColorPicker, 0.5)
    manager:Register(keyColorPicker, "all")
    cardLook:AddRow(rowL2, Theme.rowHeightLast, 0)

    yOffset = cardLook:GetNextOffset()

    local cardSource = GUIFrame:CreateCard(scrollChild, "Position Source", yOffset)
    manager:Register(cardSource, "all")

    local rowSrc = GUIFrame:CreateRow(cardSource.content, Theme.rowHeight)
    local followCheck = GUIFrame:CreateCheckbox(rowSrc, "Use the Reroll Key position", {
        value = db.YourKeyUseRerollPosition ~= false,
        callback = function(checked)
            db.YourKeyUseRerollPosition = checked
            ApplySettings()
            manager:UpdateAll(true)
        end,
    })
    rowSrc:AddWidget(followCheck, 1)
    manager:Register(followCheck, "all")
    cardSource:AddRow(rowSrc, Theme.rowHeight)

    local noteRowSrc = GUIFrame:CreateRow(cardSource.content, Theme.rowHeightNote)
    local sourceNote = GUIFrame:CreateText(noteRowSrc,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " On: this reminder sits exactly where the Reroll " ..
        "Key reminder sits, and the Position card below is locked. Off: it keeps " ..
        "its own position and gets its own mover in Edit Mode.",
        50, "hide")
    noteRowSrc:AddWidget(sourceNote, 1)
    cardSource:AddRow(noteRowSrc, Theme.rowHeightNote, 0)

    yOffset = cardSource:GetNextOffset()

    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Reminder Position",
        db = db,
        positionKey = "YourKeyPosition",
        dbKeys = {
            anchorFrameType = "YourKeyAnchorFrameType",
            anchorFrameFrame = "YourKeyParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "YourKeyStrata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(posCard, "ownposition")
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "ownposition")
    end
    yOffset = posOffset

    local cardYourKeyGlow = GUIFrame:CreateCard(scrollChild, "Your Key Glow", yOffset)
    manager:Register(cardYourKeyGlow, "all")

    local rowYG1 = GUIFrame:CreateRow(cardYourKeyGlow.content, Theme.rowHeight)
    local yourKeyGlowEnableCheck = GUIFrame:CreateCheckbox(rowYG1, "Enable Glow", {
        value = db.YourKeyGlowEnabled ~= false,
        callback = function(checked) db.YourKeyGlowEnabled = checked; ApplySettings() end,
    })
    rowYG1:AddWidget(yourKeyGlowEnableCheck, 0.5)
    manager:Register(yourKeyGlowEnableCheck, "all")

    local yourKeyGlowColor = GUIFrame:CreateColorPicker(rowYG1, "Glow Color", {
        color = db.YourKeyGlowColor or { 0.2, 0.6, 1, 1 },
        callback = function(r, g, b, a)
            db.YourKeyGlowColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowYG1:AddWidget(yourKeyGlowColor, 0.5)
    manager:Register(yourKeyGlowColor, "all")
    cardYourKeyGlow:AddRow(rowYG1, Theme.rowHeight)

    local rowYG2 = GUIFrame:CreateRow(cardYourKeyGlow.content, Theme.rowHeight)
    local yourKeyGlowLines = GUIFrame:CreateSlider(rowYG2, "Lines", {
        min = 1, max = 16, step = 1,
        value = db.YourKeyGlowLines or 5,
        callback = function(val) db.YourKeyGlowLines = val; ApplySettings() end,
    })
    rowYG2:AddWidget(yourKeyGlowLines, 0.5)
    manager:Register(yourKeyGlowLines, "all")

    local yourKeyGlowLength = GUIFrame:CreateSlider(rowYG2, "Length", {
        min = 1, max = 20, step = 1,
        value = db.YourKeyGlowLength or 10,
        callback = function(val) db.YourKeyGlowLength = val; ApplySettings() end,
    })
    rowYG2:AddWidget(yourKeyGlowLength, 0.5)
    manager:Register(yourKeyGlowLength, "all")
    cardYourKeyGlow:AddRow(rowYG2, Theme.rowHeight)

    local rowYG3 = GUIFrame:CreateRow(cardYourKeyGlow.content, Theme.rowHeightLast)
    local yourKeyGlowFrequency = GUIFrame:CreateSlider(rowYG3, "Speed", {
        min = 0.05, max = 1, step = 0.05,
        value = db.YourKeyGlowFrequency or 0.25,
        callback = function(val) db.YourKeyGlowFrequency = val; ApplySettings() end,
    })
    rowYG3:AddWidget(yourKeyGlowFrequency, 0.5)
    manager:Register(yourKeyGlowFrequency, "all")

    local yourKeyGlowThickness = GUIFrame:CreateSlider(rowYG3, "Thickness", {
        min = 1, max = 8, step = 1,
        value = db.YourKeyGlowThickness or 2,
        callback = function(val) db.YourKeyGlowThickness = val; ApplySettings() end,
    })
    rowYG3:AddWidget(yourKeyGlowThickness, 0.5)
    manager:Register(yourKeyGlowThickness, "all")
    cardYourKeyGlow:AddRow(rowYG3, Theme.rowHeightLast, 0)

    yOffset = cardYourKeyGlow:GetNextOffset()

    manager:UpdateAll(true)
    return yOffset
end)

-- No header card and no master toggle: each tab owns its own switch, so a
-- shared one here would be a second switch for nothing.
GUIFrame:RegisterTabbedContent("KeystoneHelper", {
    { id = "KeystoneHelperGeneral",  label = "General" },
    { id = "KeystoneHelperReset",    label = "Instance Reset" },
    { id = "KeystoneHelperReroll",   label = "Reroll Key" },
    { id = "KeystoneHelperYourKey",  label = "Your Key" },
})
