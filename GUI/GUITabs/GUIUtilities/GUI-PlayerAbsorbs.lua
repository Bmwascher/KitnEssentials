-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PlayerAbsorbs.lua                                   ║
-- ║  GUI: Player Absorbs                                     ║
-- ║  Purpose: Configuration panel for the PlayerAbsorbs      ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PlayerAbsorbs", true)
    end
    return nil
end

GUIFrame:RegisterContent("PlayerAbsorbs", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PlayerAbsorbs
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local PA = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if PA and PA.ApplySettings then PA:ApplySettings() end
    end

    local function ApplyPosition()
        if PA and PA.ApplyPosition then PA:ApplyPosition() end
    end

    local function ApplyModuleState(enabled)
        if not PA then return end
        PA.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("PlayerAbsorbs")
        else
            KitnEssentials:DisableModule("PlayerAbsorbs")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Player Absorbs", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Player Absorbs", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Player Absorbs",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplyPosition,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Display Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local abbrevCheck = GUIFrame:CreateCheckbox(row3a, "Abbreviate Numbers", {
        value = db.AbbreviateNumber == true,
        callback = function(checked) db.AbbreviateNumber = checked; ApplySettings() end,
        tooltip = "On: 1.2M-style numbers that fade after the Fade Duration. Off: full numbers that stay while a shield is up and clear instantly at 0.",
    })
    row3a:AddWidget(abbrevCheck, 0.5)
    manager:Register(abbrevCheck, "all")
    local iconCheck = GUIFrame:CreateCheckbox(row3a, "Show Icon", {
        value = db.ShowIcon ~= false,
        callback = function(checked) db.ShowIcon = checked; ApplySettings() end,
    })
    row3a:AddWidget(iconCheck, 0.5)
    manager:Register(iconCheck, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3grow = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local growDropdown = GUIFrame:CreateDropdown(row3grow, "Growth Direction", {
        options = {
            { key = "DOWN",  text = "Down" },
            { key = "UP",    text = "Up" },
            { key = "RIGHT", text = "Right" },
            { key = "LEFT",  text = "Left" },
        },
        value = db.GrowthDirection or "DOWN",
        callback = function(key) db.GrowthDirection = key; ApplySettings() end,
        tooltip = "Which way the heal-absorb row grows when both absorbs are active. A lone absorb centers on the anchor (exact while abbreviating; fixed slots with full numbers).",
    })
    row3grow:AddWidget(growDropdown, 0.5)
    manager:Register(growDropdown, "all")
    card3:AddRow(row3grow, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local iconSizeSlider = GUIFrame:CreateSlider(row3b, "Icon Size", {
        min = 8, max = 48, step = 1,
        value = db.IconSize or 18,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row3b:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")
    local fadeSlider = GUIFrame:CreateSlider(row3b, "Fade Duration (sec)", {
        min = 2, max = 20, step = 1,
        value = db.FadeTime or 10,
        callback = function(val) db.FadeTime = val; ApplySettings() end,
    })
    row3b:AddWidget(fadeSlider, 0.5)
    manager:Register(fadeSlider, "all")
    card3:AddRow(row3b, Theme.rowHeightLast, 0)

    card3:AddLabel("Abbreviate off shows full numbers that persist while a shield is up and clear instantly at 0; on shows 1.2M numbers that fade the Fade Duration after the last change.")

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font",
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 36 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card5, "all")

    local row5 = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local shieldColor = GUIFrame:CreateColorPicker(row5, "Shield Color", {
        color = db.ShieldColor or { 0.37, 0.82, 1, 1 },
        callback = function(r, g, b, a)
            db.ShieldColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5:AddWidget(shieldColor, 0.5)
    manager:Register(shieldColor, "all")
    local healColor = GUIFrame:CreateColorPicker(row5, "Heal-Absorb Color", {
        color = db.HealAbsorbColor or { 1, 0.48, 0.48, 1 },
        callback = function(r, g, b, a)
            db.HealAbsorbColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5:AddWidget(healColor, 0.5)
    manager:Register(healColor, "all")
    card5:AddRow(row5, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
