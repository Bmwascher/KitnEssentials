-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-HavocTracker.lua                                    ║
-- ║  GUI: Havoc Tracker                                      ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           HavocTracker module.                           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
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

    -- The game builds the live warning once and reads its text, font and color
    -- only then, so those changes need a reload; the preview is ours and
    -- updates now.
    local function ApplyWithReload()
        KE:FlagReloadNeeded()
        ApplySettings()
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
    end)

    card1:AddLabel("|cffffd100Destruction Warlock only.|r Warns you when your Havoc is sitting on the " ..
        "target you are hitting, which wastes it.")

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return yOffset end

    local attached = db.AttachToCombatTexts == true
    local attachRow = GUIFrame:CreateRow(card1.content, attached and Theme.rowHeight or Theme.rowHeightLast)
    local attachCheck = GUIFrame:CreateCheckbox(attachRow, "Attach to Combat Texts", {
        value = attached,
        tooltip = "Show the warning last in the Combat Texts stack and move with it, "
            .. "instead of using a separate anchor.",
        callback = function(checked)
            db.AttachToCombatTexts = checked
            ApplyWithReload()
            GUIFrame:RefreshContent()
        end,
    })
    attachRow:AddWidget(attachCheck, 1)
    manager:Register(attachCheck, "all")
    if attached then
        card1:AddRow(attachRow, Theme.rowHeight)
        for _, widget in ipairs(GUIFrame:CreateAttachSizeRow(card1, db, {
            sizeKey = "WarningFontSize", default = 24, range = { 10, 48 },
            onChange = ApplyWithReload, isLast = true,
        })) do
            manager:Register(widget, "all")
        end
    else
        card1:AddRow(attachRow, Theme.rowHeightLast, 0)
    end
    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Display
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display", yOffset)

    local textRow = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local textBox = GUIFrame:CreateEditBox(textRow, "Text", {
        value = db.WarningText or "Havoc Target",
        callback = function(value)
            db.WarningText = value
            ApplyWithReload()
        end,
    })
    textRow:AddWidget(textBox, 1)
    manager:Register(textBox, "all")
    card2:AddRow(textRow, Theme.rowHeight)

    local noteRow2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local noteText2 = GUIFrame:CreateText(noteRow2,
        KE:ColorTextByTheme("Note"),
        "Changing the text, font, size, outline or color needs a reload, since the game builds "
            .. "this display itself.",
        40, "hide")
    noteRow2:AddWidget(noteText2, 1)
    card2:AddRow(noteRow2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    -- Combat Texts owns the anchor and the font while attached.
    if not attached then
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
            onChangeCallback = ApplyWithReload,
        })
        manager:Register(fontCard, "all")
        if fontWidgets then
            manager:RegisterGroup(fontWidgets, "all")
        end
        yOffset = fontOffset
    end

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {
        db = db,
        manager = manager,
        onChange = ApplyWithReload,
        colors = {
            { label = "Warning Color", key = "WarningColor", default = { 1, 0.1, 0.1, 1 } },
        },
        isLast = true,
    })

    manager:UpdateAll(true)
    return yOffset
end)
