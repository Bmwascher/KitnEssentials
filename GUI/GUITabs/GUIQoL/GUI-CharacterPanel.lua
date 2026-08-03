-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CharacterPanel.lua                                  ║
-- ║  GUI: Character Panel                                    ║
-- ║  Purpose: Configuration panel for the CharacterPanel     ║
-- ║           module (warnings, character text styling,      ║
-- ║           track indicators, gem socket helper).          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("CharacterPanel", true)
    end
    return nil
end

GUIFrame:RegisterContent("CharacterPanel", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CharacterPanel
    if not db then return yOffset end

    local CP = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    manager:SetCondition("elvuiOk", function()
        return not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ElvUI"))
    end)
    manager:SetCondition("socketHelperOn", function() return db.SocketHelperEnabled end)
    manager:SetCondition("trackOn", function() return db.TrackIndicatorsEnabled end)

    local function ApplySettings()
        if CP then CP:Refresh() end
    end

    local function ApplyModuleState(enabled)
        if not CP then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("CharacterPanel")
        else
            KitnEssentials:DisableModule("CharacterPanel")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Character Panel", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        KE:Print("Character Panel: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Adds optional decimal item level, race text, faction indicator, item track letters, missing enchant/gem warnings, and a gem socket helper.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    -- Wrapped (not an early return) so Card 8 below -- a separate module --
    -- still renders while Character Panel itself is off.
    if db.Enabled ~= false then

    ----------------------------------------------------------------
    -- Card 2: Warning Display
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Warning Display", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local enchantCheck = GUIFrame:CreateCheckbox(row2, "Show Missing Enchants", {
        value = db.ShowEnchants ~= false,
        callback = function(checked) db.ShowEnchants = checked; ApplySettings() end,
    })
    row2:AddWidget(enchantCheck, 1 / 3)
    manager:Register(enchantCheck, "all")

    local gemCheck = GUIFrame:CreateCheckbox(row2, "Show Missing Gems", {
        value = db.ShowMissingGems ~= false,
        callback = function(checked) db.ShowMissingGems = checked; ApplySettings() end,
    })
    row2:AddWidget(gemCheck, 1 / 3)
    manager:Register(gemCheck, "all")

    local hideBGCheck = GUIFrame:CreateCheckbox(row2, "Hide Panel Background", {
        value = db.HideCharacterBackground == true,
        callback = function(checked) db.HideCharacterBackground = checked; ApplySettings() end,
    })
    row2:AddWidget(hideBGCheck, 1 / 3)
    manager:Register(hideBGCheck, "all")
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Character Panel Display (ElvUI-gated)
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Character Panel Display", yOffset)
    manager:Register(card3, "elvuiOk")

    local elvuiLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ElvUI")
    if elvuiLoaded then
        local elvuiNoteRow = GUIFrame:CreateRow(card3.content, 24)
        local elvuiNote = GUIFrame:CreateText(elvuiNoteRow,
            "", "|cffff5555Disabled while ElvUI is loaded — ElvUI handles this.|r",
            24, "hide")
        elvuiNoteRow:AddWidget(elvuiNote, 1)
        card3:AddRow(elvuiNoteRow, 24)
    end

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local decimalCheck = GUIFrame:CreateCheckbox(row3, "Decimal Item Level", {
        value = db.DecimalItemLevel,
        callback = function(checked)
            db.DecimalItemLevel = checked
            local CP = GetModule()
            if CP then CP:UpdateItemLevelText() end
        end,
        tooltip = "Shows item level with 2 decimal places instead of rounded.",
    })
    row3:AddWidget(decimalCheck, 1 / 3)
    manager:Register(decimalCheck, "elvuiOk")

    local raceCheck = GUIFrame:CreateCheckbox(row3, "Show Race Text", {
        value = db.ShowRaceText,
        callback = function(checked)
            db.ShowRaceText = checked
            local CP = GetModule()
            if CP then
                if checked then CP:ShowRaceText() else CP:HideRaceText() end
            end
        end,
        tooltip = "Shows your character's race below the level text.",
    })
    row3:AddWidget(raceCheck, 1 / 3)
    manager:Register(raceCheck, "elvuiOk")

    local factionCheck = GUIFrame:CreateCheckbox(row3, "Show Faction on Level", {
        value = db.ShowFactionOnLevel,
        callback = function(checked)
            db.ShowFactionOnLevel = checked
            local CP = GetModule()
            if CP then CP:UpdateLevelTextWithFaction() end
        end,
        tooltip = "Appends (A)/(H) in faction color after the level text.",
    })
    row3:AddWidget(factionCheck, 1 / 3)
    manager:Register(factionCheck, "elvuiOk")
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Item Track Indicators
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Item Track Indicators", yOffset)
    manager:Register(card4, "all")

    local row4 = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local trackCheck = GUIFrame:CreateCheckbox(row4, "Show Track Letters", {
        value = db.TrackIndicatorsEnabled,
        callback = function(checked)
            db.TrackIndicatorsEnabled = checked
            local CP = GetModule()
            if CP then
                if checked then
                    CP:SetupTrackIndicators()
                    CP:UpdateAllTrackIndicators()
                else
                    CP:HideAllTrackIndicators()
                end
            end
            RefreshStates()
        end,
        tooltip = "Shows M/H/C/V/A letters on gear slots indicating Myth/Hero/Champion/Veteran/Adventurer tracks. Crafted gear auto-detects tier from item level.",
    })
    row4:AddWidget(trackCheck, 1)
    manager:Register(trackCheck, "all")
    card4:AddRow(row4, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local trackSizeSlider = GUIFrame:CreateSlider(row4b, "Letter Size", {
        min = 8, max = 24, step = 1,
        value = db.TrackLetterSize,
        callback = function(val)
            db.TrackLetterSize = val
            local CP = GetModule()
            if CP then CP:UpdateAllTrackIndicators() end
        end,
    })
    row4b:AddWidget(trackSizeSlider, 1)
    manager:Register(trackSizeSlider, "trackOn")
    card4:AddRow(row4b, Theme.rowHeight)

    local noteRow4 = GUIFrame:CreateRow(card4.content, 30)
    local note4 = GUIFrame:CreateText(noteRow4, "",
        "Colors: |cffff8000M|r Myth · |cffc74dc7H|r Hero · |cff00b3ffC|r Champion · |cff00cc00V|r Veteran · |cffb3b3b3A|r Adventurer",
        30, "hide")
    noteRow4:AddWidget(note4, 1)
    card4:AddRow(noteRow4, 30, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Slot Details
    ----------------------------------------------------------------
    local cardSD = GUIFrame:CreateCard(scrollChild, "Slot Details", yOffset)
    manager:Register(cardSD, "all")

    local rowSD1 = GUIFrame:CreateRow(cardSD.content, Theme.rowHeight)
    local ilvlCheck = GUIFrame:CreateCheckbox(rowSD1, "Show Item Level", {
        value = db.ShowSlotItemLevel,
        callback = function(checked)
            db.ShowSlotItemLevel = checked
            local CP = GetModule()
            if CP then CP:UpdateAllSlotDetails() end
        end,
        tooltip = "Shows the item level on each equipped gear slot.",
    })
    rowSD1:AddWidget(ilvlCheck, 1 / 3)
    manager:Register(ilvlCheck, "all")

    local enchantNameCheck = GUIFrame:CreateCheckbox(rowSD1, "Show Enchant Names", {
        value = db.ShowEnchantNames,
        callback = function(checked)
            db.ShowEnchantNames = checked
            local CP = GetModule()
            if CP then CP:UpdateAllSlotDetails() end
        end,
        tooltip = "Shows the enchant name on enchantable gear slots.",
    })
    rowSD1:AddWidget(enchantNameCheck, 1 / 3)
    manager:Register(enchantNameCheck, "all")

    local slotGemsCheck = GUIFrame:CreateCheckbox(rowSD1, "Show Gems", {
        value = db.ShowSlotGems,
        callback = function(checked)
            db.ShowSlotGems = checked
            local CP = GetModule()
            if CP then CP:UpdateAllSlotDetails() end
        end,
        tooltip = "Shows equipped gem icons on each gear slot.",
    })
    rowSD1:AddWidget(slotGemsCheck, 1 / 3)
    manager:Register(slotGemsCheck, "all")
    cardSD:AddRow(rowSD1, Theme.rowHeight)

    local rowSD2 = GUIFrame:CreateRow(cardSD.content, Theme.rowHeightLast)
    local infoSizeSlider = GUIFrame:CreateSlider(rowSD2, "Info Text Size", {
        min = 8, max = 18, step = 1,
        value = db.SlotInfoFontSize,
        callback = function(val)
            db.SlotInfoFontSize = val
            local CP = GetModule()
            if CP then CP:UpdateAllSlotDetails() end
        end,
    })
    rowSD2:AddWidget(infoSizeSlider, 1)
    manager:Register(infoSizeSlider, "all")
    cardSD:AddRow(rowSD2, Theme.rowHeightLast, 0)

    yOffset = cardSD:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Gem Socket Helper
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Gem Socket Helper", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local socketEnableCheck = GUIFrame:CreateCheckbox(row5a, "Enable Socket Helper", {
        value = db.SocketHelperEnabled,
        callback = function(checked)
            db.SocketHelperEnabled = checked
            local CP = GetModule()
            if CP then
                if checked then
                    CP:SetupGemSocketHelper()
                    CP:RefreshSocketButtons()
                else
                    CP:DisableGemSocketHelper()
                end
            end
            RefreshStates()
        end,
        tooltip = "Shows equipped gem sockets beside the character panel tabs with quick gem replacement on hover.",
    })
    row5a:AddWidget(socketEnableCheck, 1)
    manager:Register(socketEnableCheck, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local sep5 = GUIFrame:CreateSeparator(card5.content)
    card5:AddRow(sep5, Theme.rowHeightSeparator)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(row5b, "Socket Button Size", {
        min = 16, max = 48, step = 1,
        value = db.SocketButtonSize,
        callback = function(val)
            db.SocketButtonSize = val
            local CP = GetModule()
            if CP then CP:RefreshSocketButtons() end
        end,
    })
    row5b:AddWidget(sizeSlider, 0.5)
    manager:Register(sizeSlider, "socketHelperOn")

    local spacingSlider = GUIFrame:CreateSlider(row5b, "Button Spacing", {
        min = 0, max = 10, step = 1,
        value = db.SocketButtonSpacing,
        callback = function(val)
            db.SocketButtonSpacing = val
            local CP = GetModule()
            if CP then CP:RefreshSocketButtons() end
        end,
    })
    row5b:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "socketHelperOn")
    card5:AddRow(row5b, Theme.rowHeight)

    local row5c = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local emptyOnlyCheck = GUIFrame:CreateCheckbox(row5c, "Show Only Empty Sockets", {
        value = db.ShowOnlyEmptySockets,
        callback = function(checked)
            db.ShowOnlyEmptySockets = checked
            local CP = GetModule()
            if CP then CP:RefreshSocketButtons() end
        end,
        tooltip = "Only show sockets that don't have a gem equipped.",
    })
    row5c:AddWidget(emptyOnlyCheck, 1)
    manager:Register(emptyOnlyCheck, "socketHelperOn")
    card5:AddRow(row5c, Theme.rowHeight)

    local row5d = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local enchantHelperCheck = GUIFrame:CreateCheckbox(row5d, "Enable Enchant Helper", {
        value = db.EnchantHelperEnabled,
        callback = function(checked)
            db.EnchantHelperEnabled = checked
            local CP = GetModule()
            if CP then CP:RefreshSocketButtons() end
        end,
        tooltip = "Adds a button at the end of the socket bar listing every enchant in your bags. "
            .. "Clicking one picks it up so you can click the item you want it on.",
    })
    row5d:AddWidget(enchantHelperCheck, 1)
    manager:Register(enchantHelperCheck, "socketHelperOn")
    card5:AddRow(row5d, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Warning Text",      dbKey = "FontSize"          },
            { label = "Level Text",        dbKey = "LevelTextSize",    elvuiGated = true },
            { label = "Name Text",         dbKey = "NameTextSize",     elvuiGated = true },
            { label = "Stats",             dbKey = "StatsFontSize",    elvuiGated = true },
            { label = "Stat Categories",   dbKey = "CategoryFontSize", elvuiGated = true },
            { label = "Item Level Value",  dbKey = "IlvlValueSize",    elvuiGated = true },
        },
        fontSizeRange = { 8, 24 },
        -- SOFTOUTLINE renders as solid black on Blizzard's character-panel
        -- FontStrings, so it's not offered for this module.
        includeSoftOutline = false,
        manager = manager,
        onChangeCallback = function()
            local CP = GetModule()
            if CP then
                CP:Refresh()
                CP:ApplySettings()
            end
        end,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then manager:RegisterGroup(fontWidgets, "all") end
    yOffset = fontOffset

    end

    RefreshStates()

    ----------------------------------------------------------------
    -- Card 8: Compare Header (independent module — own cascade)
    ----------------------------------------------------------------
    local chDB = KE.db and KE.db.profile.CompareHeader
    if chDB then
        local function GetCompareHeaderModule()
            if KitnEssentials then
                return KitnEssentials:GetModule("CompareHeader", true)
            end
            return nil
        end

        local card8 = GUIFrame:CreateCard(scrollChild, "Compare Header", yOffset)

        local row8 = GUIFrame:CreateRow(card8.content, Theme.rowHeightLast)
        local compareHeaderCheck = GUIFrame:CreateCheckbox(row8, "Style Compare Header", {
            value = chDB.Enabled == true,
            callback = function(checked)
                chDB.Enabled = checked
                local CH = GetCompareHeaderModule()
                if CH then CH:ApplySettings() end
                -- Turning it ON styles the header immediately; turning it OFF
                -- cannot un-style it, so that direction needs a reload. Same
                -- helper and same one-directional idiom as
                -- GUI/GUITabs/GUISkinning/GUI-UIWidgets.lua:75.
                if not checked then KE:SkinningReloadPrompt() end
            end,
            tooltip = "Styles the \"Equipped\" header on item comparison tooltips to match the rest of the tooltip skin. Turning it off needs a reload.",
        })
        row8:AddWidget(compareHeaderCheck, 1)
        card8:AddRow(row8, Theme.rowHeightLast, 0)

        yOffset = card8:GetNextOffset()
    end

    return yOffset
end)
