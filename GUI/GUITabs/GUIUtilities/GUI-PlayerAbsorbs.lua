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

    -- Contextual spacing sliders: Row Spacing applies to the stacked/adjacent
    -- directions, Separation only to Split L/R. Each greys out when it does nothing.
    manager:SetCondition("nonSplit", function() return (db.GrowthDirection or "DOWN") ~= "SPLIT" end)
    manager:SetCondition("splitOnly", function() return db.GrowthDirection == "SPLIT" end)
    -- Icon Side only applies to the stacked Down/Up directions.
    manager:SetCondition("stackedOnly", function()
        local d = db.GrowthDirection or "DOWN"
        return d == "DOWN" or d == "UP"
    end)

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Player Absorbs", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        KE:Print("Player Absorbs: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

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

    -- Behavior note explaining the Abbreviate toggle, then a divider before the
    -- layout settings below. The theme's text tiers are all white, so dim this note
    -- explicitly to read as gray helper text distinct from the row labels.
    local behaviorNote = card3:AddLabel("Abbreviate off shows full numbers that persist while a shield is up and clear instantly at 0; on shows 1.2M numbers that fade the Fade Duration after the last change.")
    behaviorNote:SetTextColor(0.6, 0.6, 0.6, 1)
    card3:AddSeparator()

    local row3grow = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local growDropdown = GUIFrame:CreateDropdown(row3grow, "Growth Direction", {
        options = {
            { key = "DOWN",  text = "Down" },
            { key = "UP",    text = "Up" },
            { key = "RIGHT", text = "Right" },
            { key = "LEFT",  text = "Left" },
            { key = "SPLIT", text = "Split L/R" },
        },
        value = db.GrowthDirection or "DOWN",
        callback = function(key) db.GrowthDirection = key; ApplySettings(); RefreshStates() end,
        tooltip = "Which way the heal-absorb row grows when both absorbs are active. Split L/R flanks them on opposite sides of the anchor (gap = Separation). A lone absorb centers on the anchor (exact while abbreviating; fixed slots with full numbers).",
    })
    row3grow:AddWidget(growDropdown, 0.5)
    manager:Register(growDropdown, "all")
    local iconSideDropdown = GUIFrame:CreateDropdown(row3grow, "Icon Side", {
        options = {
            { key = "LEFT",  text = "Left" },
            { key = "RIGHT", text = "Right" },
        },
        value = db.IconSide or "LEFT",
        callback = function(key) db.IconSide = key; ApplySettings() end,
        tooltip = "Which side of the number the icon sits on. Applies to the Down/Up stacked directions; the side-by-side and Split directions set it automatically.",
    })
    row3grow:AddWidget(iconSideDropdown, 0.5)
    manager:Register(iconSideDropdown, "stackedOnly")
    card3:AddRow(row3grow, Theme.rowHeight)

    -- Sizing
    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
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
    card3:AddRow(row3b, Theme.rowHeight)

    -- Spacing
    local row3space = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local iconSpaceSlider = GUIFrame:CreateSlider(row3space, "Icon Spacing", {
        min = 0, max = 20, step = 1,
        value = db.IconSpacing or 4,
        callback = function(val) db.IconSpacing = val; ApplySettings() end,
    })
    row3space:AddWidget(iconSpaceSlider, 0.5)
    manager:Register(iconSpaceSlider, "all")
    local rowSpaceSlider = GUIFrame:CreateSlider(row3space, "Row Spacing", {
        min = 0, max = 20, step = 1,
        value = db.RowSpacing or 4,
        callback = function(val) db.RowSpacing = val; ApplySettings() end,
    })
    row3space:AddWidget(rowSpaceSlider, 0.5)
    manager:Register(rowSpaceSlider, "nonSplit")
    card3:AddRow(row3space, Theme.rowHeight)

    local row3sep = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local sepSlider = GUIFrame:CreateSlider(row3sep, "Separation", {
        min = 0, max = 200, step = 1,
        value = db.Separation or 40,
        callback = function(val) db.Separation = val; ApplySettings() end,
        tooltip = "Gap between the two sides when Growth Direction is Split L/R. No effect in the other directions.",
    })
    row3sep:AddWidget(sepSlider, 0.5)
    manager:Register(sepSlider, "splitOnly")
    local splitLeadCheck = GUIFrame:CreateCheckbox(row3sep, "Icon Leads Number", {
        value = db.SplitIconLead == true,
        callback = function(checked) db.SplitIconLead = checked; ApplySettings() end,
        tooltip = "Split L/R only. On: both readouts lead with the icon ([S] 1.2M  [H] 340K). Off: the icons bracket the center gap and the numbers grow outward (1.2M [S]  [H] 340K).",
    })
    row3sep:AddWidget(splitLeadCheck, 0.5)
    manager:Register(splitLeadCheck, "splitOnly")
    card3:AddRow(row3sep, Theme.rowHeightLast, 0)

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
