-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-RareAlert.lua                                       ║
-- ║  GUI: Rare Alert                                         ║
-- ║  Purpose: Configuration panel for the RareAlert module.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("RareAlert", true)
    end
    return nil
end

GUIFrame:RegisterContent("RareAlert", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.RareAlert
    if not db then return yOffset end

    local RA = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("backdrop", function() return db.Backdrop and db.Backdrop.Enabled == true end)
    manager:SetCondition("sound", function() return db.PlaySound ~= false end)

    local function ApplySettings()
        if RA then RA:ApplySettings() end
    end

    local function ApplyState(enabled)
        if not RA then return end
        if enabled then
            KitnEssentials:EnableModule("RareAlert")
        else
            KitnEssentials:DisableModule("RareAlert")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    -- A box that only changes a saved value and what the card shows.
    local function Pick(label, key)
        return {
            label = label,
            config = {
                value = db[key] ~= false,
                callback = function(checked)
                    db[key] = checked
                    ApplySettings()
                end,
            },
        }
    end

    ----------------------------------------------------------------
    -- Card 1: Rare Alert
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Rare Alert", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyState(checked)
    end)

    card1:AddLabel("A card warns you when a rare is near in the open world: its portrait, an arrow and " ..
        "yards, health, danger color and best drop. Left-click targets it, and right-click closes it. " ..
        "Nothing runs in dungeons, raids or battlegrounds.")

    -- A disabled module shows only this card: its switch and description.
    if db.Enabled == false then return card1:GetNextOffset() end

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local testButton = GUIFrame:CreateButton(row1, "Test Alert", {
        width = 160,
        height = 28,
        tooltip = "Shows the sample with its sound and flash.",
        callback = function() if RA then RA:TestAlert() end end,
    })
    row1:AddWidget(testButton, 0.5)
    manager:Register(testButton, "all")
    local resetButton = GUIFrame:CreateButton(row1, "Reset Position", {
        width = 160,
        height = 28,
        callback = function()
            if RA then RA:ResetPosition() end
            GUIFrame:RefreshContent()
        end,
    })
    row1:AddWidget(resetButton, 0.5)
    manager:Register(resetButton, "all")
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: What Fires
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "What Fires", yOffset)
    manager:Register(card2, "all")
    -- Read once per build. Only a plain false proves the setting is off.
    local enemyPlates = C_CVar.GetCVarBool("nameplateShowEnemies")
    if not KE:IsSecretValue(enemyPlates) and enemyPlates == false then
        card2:AddLabel("Enemy nameplates are off, so a rare with no minimap icon shows only when you " ..
            "target or mouse over it.")
    end
    manager:RegisterGroup(card2:AddCheckboxGrid({
        Pick("Vignettes on the minimap", "FireVignette"),
        Pick("Nameplates", "FirePlate"),
        Pick("Target and mouseover", "FireTarget"),
    }, { isLast = true }), "all")
    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Loud For
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Loud For", yOffset)
    manager:Register(card3, "all")
    card3:AddLabel("A rare alive and not listed here is always loud. Tick a box to make that kind loud too.")
    manager:RegisterGroup(card3:AddCheckboxGrid({
        Pick("Rares that are gray to you", "LoudGray"),
        Pick("Rares already tapped", "LoudTapped"),
        Pick("Found by your target or mouseover", "LoudFound"),
    }, { columns = 2 }), "all")

    local row3sep = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3 = GUIFrame:CreateSeparator(row3sep)
    row3sep:AddWidget(sep3, 1)
    manager:Register(sep3, "all")
    card3:AddRow(row3sep, Theme.rowHeightSeparator)

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local quietCheck = GUIFrame:CreateCheckbox(row3, "Show Quiet Cards", {
        value = db.ShowQuiet ~= false,
        tooltip = "Off, a rare that is not loud shows no card at all.",
        callback = function(checked) db.ShowQuiet = checked end,
    })
    row3:AddWidget(quietCheck, 1)
    manager:Register(quietCheck, "all")
    card3:AddRow(row3, Theme.rowHeightLast, 0)
    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Click and Party
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Click and Party", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local skullCheck = GUIFrame:CreateCheckbox(row4a, "Skull on Click", {
        value = db.SkullOnClick == true,
        callback = function(checked)
            db.SkullOnClick = checked
            ApplySettings()
        end,
    })
    row4a:AddWidget(skullCheck, 1)
    manager:Register(skullCheck, "all")
    card4:AddRow(row4a, Theme.rowHeight)

    card4:AddLabel("To target from a key, bind a macro holding this line: " ..
        KE:Gold("/click KE_RareAlertTarget"))

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local partyCheck = GUIFrame:CreateCheckbox(row4b, "Announce to Party", {
        value = db.AnnounceParty == true,
        callback = function(checked) db.AnnounceParty = checked end,
    })
    row4b:AddWidget(partyCheck, 1)
    manager:Register(partyCheck, "all")
    card4:AddRow(row4b, Theme.rowHeight)

    card4:AddLabel("One line per loud alert, in a party and out of combat, such as: " ..
        "Rare: Humar the Pridelord, level 23 elite, at 62.0, 33.4")
    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Display Settings
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card5, "all")

    local row5 = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local staysSlider = GUIFrame:CreateSlider(row5, "Stays For", {
        min = 5, max = 60, step = 1,
        value = db.StaysFor,
        callback = function(val) db.StaysFor = val end,
    })
    row5:AddWidget(staysSlider, 0.5)
    manager:Register(staysSlider, "all")
    local sizeSlider = GUIFrame:CreateSlider(row5, "Size", {
        min = 50, max = 200, step = 1,
        value = db.Size,
        callback = function(val)
            db.Size = val
            ApplySettings()
        end,
    })
    row5:AddWidget(sizeSlider, 0.5)
    manager:Register(sizeSlider, "all")
    card5:AddRow(row5, Theme.rowHeight)

    manager:RegisterGroup(card5:AddCheckboxGrid({
        Pick("Direction and Yards", "ShowDirection"),
        Pick("Health", "ShowHealth"),
        Pick("Best Drop", "ShowDrop"),
    }, { isLast = true }), "all")
    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
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

    ----------------------------------------------------------------
    -- Card 7: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 14, 24 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 8: Backdrop
    ----------------------------------------------------------------
    local card8 = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    manager:Register(card8, "all")

    local row8a = GUIFrame:CreateRow(card8.content, Theme.rowHeight)
    local backdropCheck = GUIFrame:CreateCheckbox(row8a, "Enable Backdrop", {
        value = db.Backdrop.Enabled ~= false,
        callback = function(checked)
            db.Backdrop.Enabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row8a:AddWidget(backdropCheck, 1)
    manager:Register(backdropCheck, "all")
    card8:AddRow(row8a, Theme.rowHeight)

    local row8b = GUIFrame:CreateRow(card8.content, Theme.rowHeightLast)
    local bgColor = GUIFrame:CreateColorPicker(row8b, "Color", {
        color = db.Backdrop.Color,
        callback = function(r, g, b, a)
            db.Backdrop.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row8b:AddWidget(bgColor, 0.25)
    manager:Register(bgColor, "backdrop")
    local borderSize = GUIFrame:CreateSlider(row8b, "Border Size", {
        min = 1, max = 10, step = 1,
        value = db.Backdrop.BorderSize or 1,
        callback = function(val)
            db.Backdrop.BorderSize = val
            ApplySettings()
        end,
    })
    row8b:AddWidget(borderSize, 0.5)
    manager:Register(borderSize, "backdrop")
    local borderColor = GUIFrame:CreateColorPicker(row8b, "Border Color", {
        color = db.Backdrop.BorderColor,
        callback = function(r, g, b, a)
            db.Backdrop.BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row8b:AddWidget(borderColor, 0.25)
    manager:Register(borderColor, "backdrop")
    card8:AddRow(row8b, Theme.rowHeightLast, 0)
    yOffset = card8:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 9: Sound
    ----------------------------------------------------------------
    local card9 = GUIFrame:CreateCard(scrollChild, "Sound", yOffset)
    manager:Register(card9, "all")

    local row9a = GUIFrame:CreateRow(card9.content, Theme.rowHeight)
    local playCheck = GUIFrame:CreateCheckbox(row9a, "Play Sound", {
        value = db.PlaySound ~= false,
        callback = function(checked)
            db.PlaySound = checked
            RefreshStates()
        end,
    })
    row9a:AddWidget(playCheck, 0.5)
    manager:Register(playCheck, "all")
    local flashCheck = GUIFrame:CreateCheckbox(row9a, "Flash Taskbar Icon", {
        value = db.FlashTaskbar ~= false,
        callback = function(checked) db.FlashTaskbar = checked end,
    })
    row9a:AddWidget(flashCheck, 0.5)
    manager:Register(flashCheck, "all")
    card9:AddRow(row9a, Theme.rowHeight)

    -- The horn is this page's own entry: registering it with the library would
    -- list it in every other module's dropdown.
    local soundList = GUIFrame.BuildSoundOptions()
    if RA then
        table.insert(soundList, 2, { key = RA.HORN_SOUND, text = RA.HORN_SOUND })
    end

    local row9b = GUIFrame:CreateRow(card9.content, Theme.rowHeightLast)
    local soundDropdown = GUIFrame:CreateDropdown(row9b, "Sound", {
        options = soundList,
        searchable = true,
        value = db.SoundName,
        callback = function(key) db.SoundName = key end,
    })
    row9b:AddWidget(soundDropdown, 0.5)
    manager:Register(soundDropdown, "sound")
    local playButton = GUIFrame:CreateButton(row9b, "Play", {
        width = 100,
        height = 28,
        callback = function() if RA then RA:PlayAlertSound() end end,
    })
    row9b:AddWidget(playButton, 0.5, nil, 0, -12)
    manager:Register(playButton, "sound")
    card9:AddRow(row9b, Theme.rowHeightLast, 0)
    yOffset = card9:GetNextOffset()

    RefreshStates()
    return yOffset
end)
