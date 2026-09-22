-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KeystoneHelper.lua                                  ║
-- ║  GUI: Keystone Helper                                    ║
-- ║  Purpose: Container page over three tabs. General hosts   ║
-- ║           the three group-finder pages, which are not     ║
-- ║           keystone features but are dungeon tools with    ║
-- ║           no sidebar row of their own. Instance Reset is   ║
-- ║           the announcer. Reminders holds both reminder     ║
-- ║           switches and the one look, position and glow    ║
-- ║           they share.                                     ║
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
    cardReset:AddLabel("Sends your reset message to the group when you reset the instance, so nobody " ..
        "wonders whether it took.")

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
-- Reminders: the two switches, then the look, position and glow they share
----------------------------------------------------------------
GUIFrame:RegisterContent("KeystoneHelperReminders", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return MissingDB(scrollChild, yOffset) end

    local cardReroll = GUIFrame:CreateCard(scrollChild, "Reroll Key Reminder", yOffset)
    cardReroll:AddHeaderToggle(db.RerollEnabled ~= false, function(checked)
        db.RerollEnabled = checked
        ApplySettings()
    end)
    cardReroll:AddLabel("Shown after you finish a keystone in time, while your own key can still be rerolled. Hides itself after five minutes.")
    yOffset = cardReroll:GetNextOffset()

    local cardYourKey = GUIFrame:CreateCard(scrollChild, "Your Key Reminder", yOffset)
    cardYourKey:AddHeaderToggle(db.YourKeyEnabled ~= false, function(checked)
        db.YourKeyEnabled = checked
        ApplySettings()
    end)
    cardYourKey:AddLabel("Shown while you stand in a Mythic 0 of the dungeon your own keystone points at, so you remember to slot it. Hides itself after five minutes.")
    yOffset = cardYourKey:GetNextOffset()

    -- Both switches off: nothing to style, so the shared cards stay away.
    if db.RerollEnabled == false and db.YourKeyEnabled == false then return yOffset end

    local manager = GUIFrame:CreateWidgetStateManager()

    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
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
        value = db.Size or 64,
        callback = function(val) db.Size = val; ApplySettings() end,
    })
    rowL1:AddWidget(sizeSlider, 1)
    manager:Register(sizeSlider, "all")
    cardLook:AddRow(rowL1, Theme.rowHeight)

    local rowL2 = GUIFrame:CreateRow(cardLook.content, Theme.rowHeightLast)
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
    cardLook:AddRow(rowL2, Theme.rowHeightLast, 0)

    yOffset = cardLook:GetNextOffset()

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

    local cardGlow = GUIFrame:CreateCard(scrollChild, "Reminder Glow", yOffset)
    manager:Register(cardGlow, "all")

    local rowG1 = GUIFrame:CreateRow(cardGlow.content, Theme.rowHeight)
    local glowEnableCheck = GUIFrame:CreateCheckbox(rowG1, "Enable Glow", {
        value = db.GlowEnabled ~= false,
        callback = function(checked) db.GlowEnabled = checked; ApplySettings() end,
    })
    rowG1:AddWidget(glowEnableCheck, 0.5)
    manager:Register(glowEnableCheck, "all")

    local glowColor = GUIFrame:CreateColorPicker(rowG1, "Glow Color", {
        color = db.GlowColor or { 0, 1, 0, 1 },
        callback = function(r, g, b, a)
            db.GlowColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowG1:AddWidget(glowColor, 0.5)
    manager:Register(glowColor, "all")
    cardGlow:AddRow(rowG1, Theme.rowHeight)

    local rowG2 = GUIFrame:CreateRow(cardGlow.content, Theme.rowHeight)
    local glowLines = GUIFrame:CreateSlider(rowG2, "Lines", {
        min = 1, max = 16, step = 1,
        value = db.GlowLines or 5,
        callback = function(val) db.GlowLines = val; ApplySettings() end,
    })
    rowG2:AddWidget(glowLines, 0.5)
    manager:Register(glowLines, "all")

    local glowLength = GUIFrame:CreateSlider(rowG2, "Length", {
        min = 1, max = 20, step = 1,
        value = db.GlowLength or 10,
        callback = function(val) db.GlowLength = val; ApplySettings() end,
    })
    rowG2:AddWidget(glowLength, 0.5)
    manager:Register(glowLength, "all")
    cardGlow:AddRow(rowG2, Theme.rowHeight)

    local rowG3 = GUIFrame:CreateRow(cardGlow.content, Theme.rowHeightLast)
    local glowFrequency = GUIFrame:CreateSlider(rowG3, "Speed", {
        min = 0.05, max = 1, step = 0.05,
        value = db.GlowFrequency or 0.25,
        callback = function(val) db.GlowFrequency = val; ApplySettings() end,
    })
    rowG3:AddWidget(glowFrequency, 0.5)
    manager:Register(glowFrequency, "all")

    local glowThickness = GUIFrame:CreateSlider(rowG3, "Thickness", {
        min = 1, max = 8, step = 1,
        value = db.GlowThickness or 2,
        callback = function(val) db.GlowThickness = val; ApplySettings() end,
    })
    rowG3:AddWidget(glowThickness, 0.5)
    manager:Register(glowThickness, "all")
    cardGlow:AddRow(rowG3, Theme.rowHeightLast, 0)

    yOffset = cardGlow:GetNextOffset()

    manager:UpdateAll(true)
    return yOffset
end)

-- No header card and no master toggle: each feature owns its own switch, so a
-- shared one here would be a second switch for nothing.
GUIFrame:RegisterTabbedContent("KeystoneHelper", {
    { id = "KeystoneHelperGeneral",   label = "General" },
    { id = "KeystoneHelperReset",     label = "Instance Reset" },
    { id = "KeystoneHelperReminders", label = "Reminders" },
})
