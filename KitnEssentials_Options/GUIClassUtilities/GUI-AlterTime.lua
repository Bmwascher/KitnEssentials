-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-AlterTime.lua                                       ║
-- ║  GUI: Alter Time                                         ║
-- ║  Purpose: Configuration panel for the AlterTime module.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local ATTACH_OPTIONS = {
    { key = "ICON",   text = "Cooldown Manager Icon" },
    { key = "SCREEN", text = "Screen Position" },
}

local ICON_POSITIONS = {
    { key = "ABOVE",  text = "Above" },
    { key = "CENTER", text = "Center" },
    { key = "BELOW",  text = "Below" },
}

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("AlterTime", true)
    end
    return nil
end

GUIFrame:RegisterContent("AlterTime", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.AlterTime
    if not db then return yOffset end

    local AT = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("onIcon", function()
        return db.AttachTo ~= "SCREEN"
    end)
    manager:SetCondition("customColor", function()
        return (db.ColorMode or "custom") == "custom"
    end)

    local function ApplySettings()
        if AT then AT:ApplySettings() end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled == true)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Alter Time", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if AT then
            if checked then KitnEssentials:EnableModule("AlterTime")
            else KitnEssentials:DisableModule("AlterTime") end
        end
    end)

    card1:AddLabel("Shows your health at the moment you cast Alter Time, so you know what it will " ..
        "return you to. The number sits on Alter Time's icon in Blizzard's Cooldown Manager, or at " ..
        "its own screen position when the Cooldown Manager does not show Alter Time.")

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Placement
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Placement", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local attachDropdown = GUIFrame:CreateDropdown(row2a, "Attach To", {
        options = ATTACH_OPTIONS,
        value = db.AttachTo or "ICON",
        callback = function(key)
            db.AttachTo = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row2a:AddWidget(attachDropdown, 0.5)
    manager:Register(attachDropdown, "all")
    local positionDropdown = GUIFrame:CreateDropdown(row2a, "Position on Icon", {
        options = ICON_POSITIONS,
        value = db.IconPosition or "ABOVE",
        callback = function(key)
            db.IconPosition = key
            ApplySettings()
        end,
    })
    row2a:AddWidget(positionDropdown, 0.5)
    manager:Register(positionDropdown, "onIcon")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local xSlider = GUIFrame:CreateSlider(row2b, "X Offset", {
        min = -50, max = 50, step = 1,
        value = db.IconX or 0,
        callback = function(value)
            db.IconX = value
            ApplySettings()
        end,
    })
    row2b:AddWidget(xSlider, 0.5)
    manager:Register(xSlider, "onIcon")
    local ySlider = GUIFrame:CreateSlider(row2b, "Y Offset", {
        min = -50, max = 50, step = 1,
        value = db.IconY or 2,
        callback = function(value)
            db.IconY = value
            ApplySettings()
        end,
    })
    row2b:AddWidget(ySlider, 0.5)
    manager:Register(ySlider, "onIcon")
    card2:AddRow(row2b, Theme.rowHeight)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local note = GUIFrame:CreateText(row2c, KE:ColorTextByTheme("Note"),
        "Add Alter Time to the Cooldown Manager's Tracked Buffs (icons). Without it, the number " ..
        "uses the Position Settings card below.", 40, "hide")
    row2c:AddWidget(note, 1)
    manager:Register(note, "all")
    card2:AddRow(row2c, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 40 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 4: Colors
    ----------------------------------------------------------------
    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {
        db         = db,
        manager    = manager,
        onChange   = ApplySettings,
        stateGroup = "all",
        colorMode  = { key = "ColorMode", onChange = RefreshStates },
        colors     = {
            { label = "Custom Color", key = "Color", default = { 0.25, 0.78, 0.92, 1 }, group = "customColor" },
        },
    })

    ----------------------------------------------------------------
    -- Card 5: Position Settings
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
        onChangeCallback = ApplySettings,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    RefreshStates()
    return yOffset
end)
