-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KeystoneHelper.lua                                  ║
-- ║  GUI: Keystone Helper                                    ║
-- ║  Purpose: Configuration panel for the KeystoneHelper     ║
-- ║           module (Instance Reset Announcer, Reroll Key   ║
-- ║           Reminder, and "Your Key?" Reminder). The two   ║
-- ║           reminders share one appearance/font/position   ║
-- ║           block; only their glows are configured apart.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("KeystoneHelper", true)
end

GUIFrame:RegisterContent("KeystoneHelper", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.KeystoneHelper
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available.")
        return errorCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        local KH = GetModule()
        if KH and KH.ApplySettings then KH:ApplySettings() end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Keystone Helper", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        local KH = GetModule()
        if KH then
            if checked then KitnEssentials:EnableModule("KeystoneHelper")
            else KitnEssentials:DisableModule("KeystoneHelper") end
        end
        KE:Print("Keystone Helper: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightNote)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Bundles three Mythic+ QoL reminders: instance reset " ..
        "announce, reroll-your-key, and \"is this your key?\".",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, Theme.rowHeightNote, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    local cardReminders = GUIFrame:CreateCard(scrollChild, "Reminders", yOffset)
    manager:Register(cardReminders, "all")

    local row2 = GUIFrame:CreateRow(cardReminders.content, Theme.rowHeightLast)
    local rerollEnableCheck = GUIFrame:CreateCheckbox(row2, "Enable Reroll Reminder", {
        value = db.RerollEnabled ~= false,
        callback = function(checked) db.RerollEnabled = checked; ApplySettings() end,
        msgPopup = true,
        msgText = "Reroll Reminder",
        msgOn = "On",
        msgOff = "Off",
    })
    row2:AddWidget(rerollEnableCheck, 0.5)
    manager:Register(rerollEnableCheck, "all")

    local yourKeyEnableCheck = GUIFrame:CreateCheckbox(row2, "Enable Your Key Reminder", {
        value = db.YourKeyEnabled ~= false,
        callback = function(checked) db.YourKeyEnabled = checked; ApplySettings() end,
        msgPopup = true,
        msgText = "Your Key Reminder",
        msgOn = "On",
        msgOff = "Off",
    })
    row2:AddWidget(yourKeyEnableCheck, 0.5)
    manager:Register(yourKeyEnableCheck, "all")
    cardReminders:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = cardReminders:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Instance Reset Announcer
    ----------------------------------------------------------------
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

    ----------------------------------------------------------------
    -- Card 3: Font (shared — one size drives title and key line)
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 16, 72 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then manager:RegisterGroup(fontWidgets, "all") end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 4: Reminder Appearance (shared by both reminders) — sits
    -- directly above Position so its preview note reads in context.
    ----------------------------------------------------------------
    local cardLook = GUIFrame:CreateCard(scrollChild, "Reminder Appearance", yOffset)
    manager:Register(cardLook, "all")

    local rowL1 = GUIFrame:CreateRow(cardLook.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(rowL1, "Icon Size", {
        min = 20, max = 120, step = 1,
        value = db.Size or 64,
        callback = function(val) db.Size = val; ApplySettings() end,
    })
    rowL1:AddWidget(sizeSlider, 1)
    manager:Register(sizeSlider, "all")
    cardLook:AddRow(rowL1, Theme.rowHeight)

    local rowL2 = GUIFrame:CreateRow(cardLook.content, Theme.rowHeight)
    local titleColorPicker = GUIFrame:CreateColorPicker(rowL2, "Title Color", {
        color = db.FontColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.FontColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowL2:AddWidget(titleColorPicker, 0.5)
    manager:Register(titleColorPicker, "all")

    local keyColorPicker = GUIFrame:CreateColorPicker(rowL2, "Key Text Color", {
        color = db.FontColorKey or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.FontColorKey = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowL2:AddWidget(keyColorPicker, 0.5)
    manager:Register(keyColorPicker, "all")
    cardLook:AddRow(rowL2, Theme.rowHeight)

    local noteRowL = GUIFrame:CreateRow(cardLook.content, Theme.rowHeightNote)
    local posNote = GUIFrame:CreateText(noteRowL,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " The preview shows both reminders side by side: the left copy " ..
        "follows the Position settings below; the right copy only previews the look.",
        50, "hide")
    noteRowL:AddWidget(posNote, 1)
    cardLook:AddRow(noteRowL, Theme.rowHeightNote, 0)

    yOffset = cardLook:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Position (shared — the reminders never coexist live)
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Reminder Position",
        db = db,
        positionKey = "Position",
        dbKeys = {
            anchorFrameType = "AnchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
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

    ----------------------------------------------------------------
    -- Card 6: Reroll Glow
    ----------------------------------------------------------------
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

    ----------------------------------------------------------------
    -- Card 7: Your Key Glow
    ----------------------------------------------------------------
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

    RefreshStates()
    return yOffset
end)
