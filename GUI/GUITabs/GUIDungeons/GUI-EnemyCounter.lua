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
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        KE:Print("Enemy Counter: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightNote)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows the number of attackable enemies currently visible on nameplates.\n" ..
        KE:ColorTextByTheme("-") .. " Useful for pull sizing in M+ and group content.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, Theme.rowHeightNote, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

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
        isLast     = true,
        colorMode  = { key = "ColorMode", onChange = RefreshStates },
        colors     = {
            { label = "Custom Color", key = "Color", default = { 1, 1, 1, 1 }, group = "customColor" },
        },
    })

    RefreshStates()
    return yOffset
end)
