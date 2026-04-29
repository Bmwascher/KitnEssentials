-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-EnemyCounter.lua                                    ║
-- ║  GUI: Enemy Counter                                      ║
-- ║  Purpose: Configuration panel for the EnemyCounter       ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

GUIFrame:RegisterContent("EnemyCounter", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Dungeons.EnemyCounter
    if not db then return yOffset end

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("customColor", function()
        return (db.ColorMode or "custom") == "custom"
    end)

    local function ApplySettings()
        local mod = KitnEssentials and KitnEssentials:GetModule("EnemyCounter", true)
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("EnemyCounter", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("EnemyCounter")
        else
            KitnEssentials:DisableModule("EnemyCounter")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Enemy Counter", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Enemy Counter", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Enemy Counter",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows the number of attackable enemies currently visible on nameplates.\n" ..
        KE:ColorTextByTheme("-") .. " Useful for pull sizing in M+ and group content.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: General Settings
    ----------------------------------------------------------------
    local cardGen = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    manager:Register(cardGen, "all")

    local rowGen1 = GUIFrame:CreateRow(cardGen.content, Theme.rowHeight)
    local combatCheck = GUIFrame:CreateCheckbox(rowGen1, "Combat Only", {
        value = db.CombatOnly,
        callback = function(checked)
            db.CombatOnly = checked
            ApplySettings()
        end,
    })
    rowGen1:AddWidget(combatCheck, 1)
    manager:Register(combatCheck, "all")
    cardGen:AddRow(rowGen1, Theme.rowHeight)

    local rowGen2 = GUIFrame:CreateRow(cardGen.content, Theme.rowHeightLast)
    local prefixCheck = GUIFrame:CreateCheckbox(rowGen2, "Show Prefix", {
        value = db.ShowPrefix ~= false,
        callback = function(checked)
            db.ShowPrefix = checked
            ApplySettings()
        end,
    })
    rowGen2:AddWidget(prefixCheck, 0.35)
    manager:Register(prefixCheck, "all")

    local prefixBox = GUIFrame:CreateEditBox(rowGen2, "Prefix Text", {
        value = db.Prefix or "Enemies:",
        callback = function(text)
            db.Prefix = text
            ApplySettings()
        end,
    })
    rowGen2:AddWidget(prefixBox, 0.65)
    manager:Register(prefixBox, "all")
    cardGen:AddRow(rowGen2, Theme.rowHeightLast, 0)

    yOffset = cardGen:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint  = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset    = "XOffset",
            yOffset    = "YOffset",
            strata     = "Strata",
        },
        showAnchorFrameType = true,
        showStrata          = true,
        showPixelSnap       = true,
        onChangeCallback    = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

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
        includeSoftOutline = true,
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
    local card4 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local colorModeDropdown = GUIFrame:CreateDropdown(row4a, "Color Mode", {
        options = KE.ColorModeOptions,
        value = db.ColorMode or "custom",
        callback = function(key)
            db.ColorMode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row4a:AddWidget(colorModeDropdown, 0.5)
    manager:Register(colorModeDropdown, "all")

    local colorPicker = GUIFrame:CreateColorPicker(row4a, "Custom Color", {
        color = db.Color or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4a:AddWidget(colorPicker, 0.5)
    manager:Register(colorPicker, "customColor")
    card4:AddRow(row4a, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    RefreshStates()
    return yOffset
end)
