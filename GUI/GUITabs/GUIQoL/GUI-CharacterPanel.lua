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

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Character Panel", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Character Panel",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Adds optional decimal item level, race text, faction indicator, item track letters, missing enchant/gem warnings, and a gem socket helper.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Warning Display
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Warning Display", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local enchantCheck = GUIFrame:CreateCheckbox(row2a, "Show Missing Enchants", {
        value = db.ShowEnchants ~= false,
        callback = function(checked) db.ShowEnchants = checked; ApplySettings() end,
    })
    row2a:AddWidget(enchantCheck, 0.5)
    manager:Register(enchantCheck, "all")

    local gemCheck = GUIFrame:CreateCheckbox(row2a, "Show Missing Gems", {
        value = db.ShowMissingGems ~= false,
        callback = function(checked) db.ShowMissingGems = checked; ApplySettings() end,
    })
    row2a:AddWidget(gemCheck, 0.5)
    manager:Register(gemCheck, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local hideBGCheck = GUIFrame:CreateCheckbox(row2b, "Hide Character Panel Background", {
        value = db.HideCharacterBackground == true,
        callback = function(checked) db.HideCharacterBackground = checked; ApplySettings() end,
    })
    row2b:AddWidget(hideBGCheck, 1)
    manager:Register(hideBGCheck, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

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

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local decimalCheck = GUIFrame:CreateCheckbox(row3a, "Decimal Item Level", {
        value = db.DecimalItemLevel,
        callback = function(checked)
            db.DecimalItemLevel = checked
            local CP = GetModule()
            if CP then CP:UpdateItemLevelText() end
        end,
        tooltip = "Shows item level with 2 decimal places instead of rounded.",
    })
    row3a:AddWidget(decimalCheck, 0.5)
    manager:Register(decimalCheck, "elvuiOk")

    local raceCheck = GUIFrame:CreateCheckbox(row3a, "Show Race Text", {
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
    row3a:AddWidget(raceCheck, 0.5)
    manager:Register(raceCheck, "elvuiOk")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local factionCheck = GUIFrame:CreateCheckbox(row3b, "Show Faction on Level", {
        value = db.ShowFactionOnLevel,
        callback = function(checked)
            db.ShowFactionOnLevel = checked
            local CP = GetModule()
            if CP then CP:UpdateLevelTextWithFaction() end
        end,
        tooltip = "Appends (A)/(H) in faction color after the level text.",
    })
    row3b:AddWidget(factionCheck, 1)
    manager:Register(factionCheck, "elvuiOk")
    card3:AddRow(row3b, Theme.rowHeightLast, 0)

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
        end,
        tooltip = "Shows M/H/C/V/A letters on gear slots indicating Myth/Hero/Champion/Veteran/Adventurer tracks. Crafted gear auto-detects tier from item level.",
    })
    row4:AddWidget(trackCheck, 1)
    manager:Register(trackCheck, "all")
    card4:AddRow(row4, Theme.rowHeight)

    local noteRow4 = GUIFrame:CreateRow(card4.content, 30)
    local note4 = GUIFrame:CreateText(noteRow4, "",
        "Colors: |cffff8000M|r Myth · |cffc74dc7H|r Hero · |cff00b3ffC|r Champion · |cff00cc00V|r Veteran · |cffb3b3b3A|r Adventurer",
        30, "hide")
    noteRow4:AddWidget(note4, 1)
    card4:AddRow(noteRow4, 30, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Gem Socket Helper
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

    local row5c = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
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
    card5:AddRow(row5c, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Font Settings
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
        includeSoftOutline = true,
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

    RefreshStates()
    return yOffset
end)
