-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-HavocTracker.lua                                    ║
-- ║  GUI: Havoc Tracker                                      ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           HavocTracker module.                           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("HavocTracker", true)
    end
    return nil
end

GUIFrame:RegisterContent("HavocTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.HavocTracker
    if not db then return yOffset end

    local HT = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if HT then HT:ApplySettings() end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Havoc Tracker", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if HT then
            if checked then KitnEssentials:EnableModule("HavocTracker")
            else KitnEssentials:DisableModule("HavocTracker") end
        end
        KE:Print("Havoc Tracker: " ..
            (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteRow = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        "|cffffd100Destruction Warlock only.|r Warns you when your Havoc is sitting on the target you are hitting, which wastes it.",
        40, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, Theme.rowHeight, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Display
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display", yOffset)

    local textRow = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local textBox = GUIFrame:CreateEditBox(textRow, "Text", {
        value = db.WarningText or "Havoc Target",
        -- ApplySettings as well as the reload flag: the live display is built by
        -- the game and only reads this when it is created, but the preview is
        -- ours and updates now.
        callback = function(value)
            db.WarningText = value
            KE:FlagReloadNeeded()
            ApplySettings()
        end,
    })
    textRow:AddWidget(textBox, 1)
    manager:Register(textBox, "all")
    card2:AddRow(textRow, Theme.rowHeight)

    local noteRow2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local noteText2 = GUIFrame:CreateText(noteRow2,
        KE:ColorTextByTheme("Note"),
        "Changing the text or its size needs a reload, since the game builds this display itself.",
        40, "hide")
    noteRow2:AddWidget(noteText2, 1)
    card2:AddRow(noteRow2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    -- The module db, with positionKey routing the coordinates into
    -- WarningPosition. Strata is a ROOT key of this card, so handing it the
    -- sub-table instead would put strata out of reach and leave the module's
    -- SetFrameStrata call unreachable from the GUI.
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        positionKey = "WarningPosition",
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
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

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "WarningFontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 10, 48 },
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
    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {
        db = db,
        manager = manager,
        onChange = ApplySettings,
        colors = {
            { label = "Warning Color", key = "WarningColor", default = { 1, 0.1, 0.1, 1 } },
        },
        isLast = true,
    })

    manager:UpdateAll(true)
    return yOffset
end)
