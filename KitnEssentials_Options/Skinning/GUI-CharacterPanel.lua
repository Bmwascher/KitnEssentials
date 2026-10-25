-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CharacterPanel.lua                                  ║
-- ║  GUI: Character Panel                                    ║
-- ║  Purpose: Configuration panel for the CharacterPanel     ║
-- ║           module (warnings, character text styling,      ║
-- ║           track indicators, gem socket helper).          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Options a client can withhold, read once. A headless load without the
-- availability policy reads as retail.
local function Admitted(id)
    return not KE.IsFeatureAvailable or KE:IsFeatureAvailable(id) == true
end
local MYTHIC_PLUS = Admitted("CharacterPanelMythicPlus")
local TRACKS = Admitted("CharacterPanelTracks")
local SOCKETS = Admitted("CharacterPanelSockets")
local ENCHANT_RANK = Admitted("CharacterPanelEnchantRank")
local WIDEN = Admitted("CharacterPanelWiden")
local WINDOW_BUTTONS = Admitted("CharacterPanelWindowButtons")

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("CharacterPanel", true)
    end
    return nil
end

local function BuildHeader(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CharacterPanel
    if not db then return yOffset, true end

    local CP = GetModule()

    local function ApplyModuleState(enabled)
        if not CP then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("CharacterPanel")
        else
            KitnEssentials:DisableModule("CharacterPanel")
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Character Panel", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)

    card1:AddLabel(KE.IS_FOREVER
        and "Adds to the character panel a decimal item level, item level and enchant text on each " ..
            "slot, a faction indicator and warnings for missing enchants. The same per-slot readout " ..
            "can be drawn on the inspect window."
        or "Adds to the character panel a decimal item level, your Mythic+ score, a faction " ..
            "indicator, upgrade track letters on each slot, warnings for missing enchants and gems, and " ..
            "a helper for socketing gems. The same per-slot readout can be drawn on the inspect window, " ..
            "with an optional talent tree beside it.")

    -- Never collapses: the Extras tab stays reachable while Character Panel is off.
    return card1:GetNextOffset(), false
end

GUIFrame:RegisterContent("CharacterPanelCharacter", function(scrollChild, yOffset)
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

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

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
    local warnWidth = SOCKETS and 1 / 3 or 1 / 2
    row2:AddWidget(enchantCheck, warnWidth)
    manager:Register(enchantCheck, "all")

    if SOCKETS then
        local gemCheck = GUIFrame:CreateCheckbox(row2, "Show Missing Gems", {
            value = db.ShowMissingGems ~= false,
            callback = function(checked) db.ShowMissingGems = checked; ApplySettings() end,
        })
        row2:AddWidget(gemCheck, warnWidth)
        manager:Register(gemCheck, "all")
    end

    local hideBGCheck = GUIFrame:CreateCheckbox(row2, "Hide Panel Background", {
        value = db.HideCharacterBackground == true,
        callback = function(checked) db.HideCharacterBackground = checked; ApplySettings() end,
    })
    row2:AddWidget(hideBGCheck, warnWidth)
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

    if WIDEN then
        local rowWW = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        local widerCheck = GUIFrame:CreateCheckbox(rowWW, "Widen Character Window", {
            value = db.WiderFrame == true,
            callback = function(checked)
                db.WiderFrame = checked
                -- The layout hooks install once per session and cannot be removed,
                -- so neither direction settles without a reload.
                KE:FlagReloadNeeded()
            end,
            tooltip = "Makes the character window wider so the item level and enchant text have room clear of the model. Moves the right-hand slot column outward. Needs a reload, and has no effect while ElvUI or an EllesmereUI themed character sheet is in use.",
        })
        rowWW:AddWidget(widerCheck, 1)
        manager:Register(widerCheck, "elvuiOk")
        card3:AddRow(rowWW, Theme.rowHeight)
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
    local row3Width = MYTHIC_PLUS and 1 / 3 or 1 / 2
    row3:AddWidget(decimalCheck, row3Width)
    manager:Register(decimalCheck, "elvuiOk")

    if MYTHIC_PLUS then
        local raceCheck = GUIFrame:CreateCheckbox(row3, "Show M+ Score", {
            value = db.ShowRaceText,
            callback = function(checked)
                db.ShowRaceText = checked
                local CP = GetModule()
                if CP then
                    if checked then CP:ShowRaceText() else CP:HideRaceText() end
                end
            end,
            tooltip = "Shows your overall Mythic+ score below the level text.",
        })
        row3:AddWidget(raceCheck, row3Width)
        manager:Register(raceCheck, "elvuiOk")
    end

    local factionCheck = GUIFrame:CreateCheckbox(row3, "Show Faction on Level", {
        value = db.ShowFactionOnLevel,
        callback = function(checked)
            db.ShowFactionOnLevel = checked
            local CP = GetModule()
            if CP then CP:UpdateLevelTextWithFaction() end
        end,
        tooltip = "Appends (A)/(H) in faction color after the level text.",
    })
    row3:AddWidget(factionCheck, row3Width)
    manager:Register(factionCheck, "elvuiOk")
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    if TRACKS then
    ----------------------------------------------------------------
    -- Card 4: Item Track Indicators
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Item Track Indicators", yOffset)
    manager:Register(card4, "all")

    local row4 = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local upgradeCheck = GUIFrame:CreateCheckbox(row4, "Show Upgrade Progress", {
        value = db.ShowUpgradeProgress ~= false,
        callback = function(checked)
            db.ShowUpgradeProgress = checked
            ApplySettings()
            if CP then CP:RefreshSlotDisplays() end
        end,
        tooltip = "While an item is still upgrading, shows how far along it is next to its item level, e.g. 334 M4/6. A fully upgraded item goes back to the plain track letter in the corner.",
    })
    row4:AddWidget(upgradeCheck, 0.5)
    -- "all", NOT "trackOn". The two toggles are independent by design: letters
    -- off with progress on is a specified state that renders the count without a
    -- letter. Gating this control on the letters toggle would gray it out in
    -- exactly that state, so the player could not leave it without first turning
    -- letters back on.
    manager:Register(upgradeCheck, "all")

    local trackCheck = GUIFrame:CreateCheckbox(row4, "Show Track Letters", {
        value = db.TrackIndicatorsEnabled,
        callback = function(checked)
            db.TrackIndicatorsEnabled = checked
            local CP = GetModule()
            if CP then
                if checked then CP:SetupTrackIndicators() end
                CP:RefreshSlotDisplays()
            end
            RefreshStates()
        end,
        tooltip = "Shows M/H/C/V/A letters on gear slots indicating Myth/Hero/Champion/Veteran/Adventurer tracks. Crafted gear auto-detects tier from item level.",
    })
    row4:AddWidget(trackCheck, 0.5)
    manager:Register(trackCheck, "all")
    card4:AddRow(row4, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local trackSizeSlider = GUIFrame:CreateSlider(row4b, "Letter Size", {
        min = 8, max = 24, step = 1,
        value = db.TrackLetterSize,
        callback = function(val)
            db.TrackLetterSize = val
            local CP = GetModule()
            if CP then CP:RefreshSlotDisplays() end
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
    end

    ----------------------------------------------------------------
    -- Card 5: Slot Details
    ----------------------------------------------------------------
    local cardSD = GUIFrame:CreateCard(scrollChild, "Slot Details", yOffset)
    manager:Register(cardSD, "all")

    local function SlotPick(label, key, value, tooltip)
        return {
            label = label,
            config = {
                value = value,
                callback = function(checked)
                    db[key] = checked
                    local CP = GetModule()
                    if CP then CP:RefreshSlotDisplays() end
                end,
                tooltip = tooltip,
            },
        }
    end

    local slotPicks = {
        SlotPick("Show Item Level", "ShowSlotItemLevel", db.ShowSlotItemLevel,
            "Shows the item level on each equipped gear slot."),
        SlotPick("Show Enchant Names", "ShowEnchantNames", db.ShowEnchantNames,
            "Shows the enchant name on enchantable gear slots."),
    }
    if SOCKETS then
        slotPicks[#slotPicks + 1] = SlotPick("Show Gems", "ShowSlotGems", db.ShowSlotGems,
            "Shows equipped gem icons on each gear slot.")
    end
    if ENCHANT_RANK then
        slotPicks[#slotPicks + 1] = SlotPick("Show Enchant Rank", "ShowEnchantRank", db.ShowEnchantRank == true,
            "Adds the crafted enchant's tier after its name, so a rank 1 enchant reads apart from a rank 3.")
    end
    manager:RegisterGroup(cardSD:AddCheckboxGrid(slotPicks), "all")

    local rowSDSep = GUIFrame:CreateRow(cardSD.content, Theme.rowHeightSeparator)
    local sepSD = GUIFrame:CreateSeparator(rowSDSep)
    rowSDSep:AddWidget(sepSD, 1)
    manager:Register(sepSD, "all")
    cardSD:AddRow(rowSDSep, Theme.rowHeightSeparator)

    local rowSDStyle = GUIFrame:CreateRow(cardSD.content, Theme.rowHeight)
    local enchantStyleDrop = GUIFrame:CreateDropdown(rowSDStyle, "Enchant Name Style", {
        value = db.EnchantNameStyle or "short",
        options = {
            { key = "short",   text = "Short" },
            { key = "verbose", text = "Verbose" },
            { key = "full",    text = "Full" },
        },
        callback = function(key)
            db.EnchantNameStyle = key
            ApplySettings()
            if CP then CP:RefreshSlotDisplays() end
        end,
        tooltip = "For Mark of the Magister: Short reads \"Int & Mana\", Verbose reads \"Intellect & Mana\", Full reads \"Mark of the Magister\". Enchants that give less than their full version read \"Minor\".",
    })
    rowSDStyle:AddWidget(enchantStyleDrop, 0.5)
    manager:Register(enchantStyleDrop, "all")
    cardSD:AddRow(rowSDStyle, Theme.rowHeight)

    local rowSD2 = GUIFrame:CreateRow(cardSD.content, Theme.rowHeightLast)
    local infoSizeSlider = GUIFrame:CreateSlider(rowSD2, "Info Text Size", {
        min = 8, max = 18, step = 1,
        value = db.SlotInfoFontSize,
        callback = function(val)
            db.SlotInfoFontSize = val
            local CP = GetModule()
            if CP then CP:RefreshSlotDisplays() end
        end,
    })
    rowSD2:AddWidget(infoSizeSlider, 1)
    manager:Register(infoSizeSlider, "all")
    cardSD:AddRow(rowSD2, Theme.rowHeightLast, 0)

    yOffset = cardSD:GetNextOffset()

    if SOCKETS then
    ----------------------------------------------------------------
    -- Card 6: Socket & Enchant Helpers
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Socket & Enchant Helpers", yOffset)
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
    row5a:AddWidget(socketEnableCheck, 0.5)
    manager:Register(socketEnableCheck, "all")

    local enchantHelperCheck = GUIFrame:CreateCheckbox(row5a, "Enable Enchant Helper", {
        value = db.EnchantHelperEnabled,
        callback = function(checked)
            db.EnchantHelperEnabled = checked
            local CP = GetModule()
            if CP then CP:RefreshSocketButtons() end
        end,
        tooltip = "Adds a button at the end of the socket bar listing every enchant in your bags. "
            .. "Clicking one picks it up so you can click the item you want it on.",
    })
    row5a:AddWidget(enchantHelperCheck, 0.5)
    -- The enchant button is drawn on the socket bar, so it needs the socket
    -- helper running even though it sits beside its master toggle.
    manager:Register(enchantHelperCheck, "socketHelperOn")
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
    end

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
        manager = manager,
        onChangeCallback = function()
            local CP = GetModule()
            if CP then CP:Refresh() end   -- Refresh ends in ApplySettings
        end,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then manager:RegisterGroup(fontWidgets, "all") end
    yOffset = fontOffset

    RefreshStates()
    return yOffset
end)

GUIFrame:RegisterContent("CharacterPanelInspect", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CharacterPanel
    if not db then return yOffset end

    local CP = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card: Inspect Frame
    ----------------------------------------------------------------
    local cardIF = GUIFrame:CreateCard(scrollChild, "Inspect Frame", yOffset)
    manager:Register(cardIF, "all")

    local rowIF = GUIFrame:CreateRow(cardIF.content, Theme.rowHeightLast)
    local inspectCheck = GUIFrame:CreateCheckbox(rowIF, "Show on Inspect Frame", {
        value = db.InspectPanelEnabled ~= false,
        callback = function(checked)
            db.InspectPanelEnabled = checked
            if CP then CP:ApplyInspectPanelState() end
        end,
        tooltip = KE.IS_FOREVER
            and "Draws the same per-slot item levels and enchants on the inspect window when you inspect another player."
            or "Draws the same per-slot item levels, enchants and gems on the inspect window when you inspect another player.",
    })
    rowIF:AddWidget(inspectCheck, 1)
    manager:Register(inspectCheck, "all")
    cardIF:AddRow(rowIF, Theme.rowHeightLast, 0)

    yOffset = cardIF:GetNextOffset()

    if Admitted("InspectTalents") then
    ----------------------------------------------------------------
    -- Card: Inspect Talents (its own module, cascaded from this one)
    ----------------------------------------------------------------
    local function TalentsModule()
        return KitnEssentials and KitnEssentials:GetModule("InspectTalents", true)
    end

    manager:SetCondition("talentsOn", function() return db.InspectTalentsEnabled ~= false end)

    local cardIT = GUIFrame:CreateCard(scrollChild, "Inspect Talents", yOffset)
    manager:Register(cardIT, "all")

    local rowIT1 = GUIFrame:CreateRow(cardIT.content, Theme.rowHeight)
    local talentsCheck = GUIFrame:CreateCheckbox(rowIT1, "Show Talents Beside Inspect", {
        value = db.InspectTalentsEnabled ~= false,
        callback = function(checked)
            db.InspectTalentsEnabled = checked
            if CP then CP:ApplyInspectTalentsState() end
            RefreshStates()
        end,
        tooltip = "Adds a panel beside the inspect window with the player's class, hero and spec talents.",
    })
    rowIT1:AddWidget(talentsCheck, 1)
    manager:Register(talentsCheck, "all")
    cardIT:AddRow(rowIT1, Theme.rowHeight)

    local rowIT2 = GUIFrame:CreateRow(cardIT.content, Theme.rowHeight)
    local autoCheck = GUIFrame:CreateCheckbox(rowIT2, "Open Automatically", {
        value = db.InspectTalentsAutoOpen ~= false,
        callback = function(checked)
            db.InspectTalentsAutoOpen = checked
            local IT = TalentsModule()
            if IT then IT:Refresh() end
        end,
        tooltip = "Opens the talent panel on every inspect. Off: click the arrow under the inspect window's close button.",
    })
    rowIT2:AddWidget(autoCheck, 1 / 3)
    manager:Register(autoCheck, "talentsOn")

    local statsCheck = GUIFrame:CreateCheckbox(rowIT2, "Show Gear Stats", {
        value = db.InspectTalentsShowStats ~= false,
        callback = function(checked)
            db.InspectTalentsShowStats = checked
            local IT = TalentsModule()
            if IT then IT:RequestStats() end
        end,
        tooltip = "Shows the player's haste, mastery, crit and versatility rating, summed from their gear.",
    })
    rowIT2:AddWidget(statsCheck, 1 / 3)
    manager:Register(statsCheck, "talentsOn")

    local compareCheck = GUIFrame:CreateCheckbox(rowIT2, "Compare With My Talents", {
        value = db.InspectTalentsCompare ~= false,
        callback = function(checked)
            db.InspectTalentsCompare = checked
            local IT = TalentsModule()
            if IT then IT:RequestCompare() end
        end,
        tooltip = "Marks talents where their build differs from yours. Only when you share their spec.",
    })
    rowIT2:AddWidget(compareCheck, 1 / 3)
    manager:Register(compareCheck, "talentsOn")
    cardIT:AddRow(rowIT2, Theme.rowHeight)

    local rowIT3 = GUIFrame:CreateRow(cardIT.content, Theme.rowHeightLast)
    local nodeSizeSlider = GUIFrame:CreateSlider(rowIT3, "Node Size", {
        min = 16, max = 32, step = 1,
        value = db.InspectTalentsNodeSize,
        callback = function(val)
            db.InspectTalentsNodeSize = val
            local IT = TalentsModule()
            if IT then IT:Refresh() end
        end,
    })
    rowIT3:AddWidget(nodeSizeSlider, 1)
    manager:Register(nodeSizeSlider, "talentsOn")
    cardIT:AddRow(rowIT3, Theme.rowHeightLast, 0)

    yOffset = cardIT:GetNextOffset()
    end

    RefreshStates()
    return yOffset
end)

-- Window Buttons, Character Skin and Compare Header belong to other modules
-- and keep working with Character Panel off, so this tab is offered in both
-- states.
GUIFrame:RegisterContent("CharacterPanelExtras", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CharacterPanel
    if not db then return yOffset end

    ----------------------------------------------------------------
    -- Card 8: Window Buttons (Automation keys, own cascade)
    ----------------------------------------------------------------
    local auDB = KE.db and KE.db.profile.Automation
    if auDB and WINDOW_BUTTONS then
        local function ApplyAutomation()
            local AU = KitnEssentials and KitnEssentials:GetModule("Automation", true)
            if AU and AU.ApplyFromPage then AU:ApplyFromPage() end
        end

        local cardWB = GUIFrame:CreateCard(scrollChild, "Window Buttons", yOffset)

        cardWB:AddCheckboxGrid({
            {
                label = "Omnium Foil",
                config = {
                    value = auDB.OmniumCharButton == true,
                    callback = function(checked) auDB.OmniumCharButton = checked; ApplyAutomation() end,
                    tooltip = "Hides the Omnium Foil minimap button and puts it in the bottom right of the character window instead. Only available at max level.",
                },
            },
            {
                label = "Great Vault",
                config = {
                    value = auDB.VaultCharButton == true,
                    callback = function(checked) auDB.VaultCharButton = checked; ApplyAutomation() end,
                    tooltip = "Adds a Great Vault button beside the Omnium Foil button. Only available at max level.",
                },
            },
        })

        local rowWBSep = GUIFrame:CreateRow(cardWB.content, Theme.rowHeightSeparator)
        rowWBSep:AddWidget(GUIFrame:CreateSeparator(rowWBSep), 1)
        cardWB:AddRow(rowWBSep, Theme.rowHeightSeparator)

        local rowWB2 = GUIFrame:CreateRow(cardWB.content, Theme.rowHeightLast)
        local wbSizeSlider = GUIFrame:CreateSlider(rowWB2, "Button Size", {
            min = 16, max = 48, step = 1,
            value = auDB.WindowButtonSize,
            callback = function(val) auDB.WindowButtonSize = val; ApplyAutomation() end,
        })
        rowWB2:AddWidget(wbSizeSlider, 1)
        cardWB:AddRow(rowWB2, Theme.rowHeightLast, 0)

        yOffset = cardWB:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 9: Character Skin (Skinning module keys -- own cascade)
    ----------------------------------------------------------------
    local cardCS = GUIFrame:CreateCard(scrollChild, "Character Skin", yOffset)

    local rowSDQual = GUIFrame:CreateRow(cardCS.content, Theme.rowHeightLast)
    local qualityBorderCheck = GUIFrame:CreateCheckbox(rowSDQual, "Item Rarity Borders", {
        value = db.SlotQualityBorders ~= false,
        callback = function(checked)
            db.SlotQualityBorders = checked
            -- The skin latches per frame and installs hooks that cannot be
            -- removed for the session, so neither direction can take effect
            -- live.
            KE:FlagReloadNeeded()
        end,
        tooltip = "Colors each equipped slot's border by item rarity, the way a bag addon does. Off leaves the standard dark border. Needs a reload, and has no effect while ElvUI is skinning the character sheet.",
    })
    rowSDQual:AddWidget(qualityBorderCheck, 1)
    -- Set directly: this tab has no widget state manager, and one would apply
    -- CharacterPanel.Enabled to a control that works with the module off.
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ElvUI") then
        qualityBorderCheck:SetEnabled(false)
    end
    cardCS:AddRow(rowSDQual, Theme.rowHeightLast, 0)
    yOffset = cardCS:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 10: Compare Header (independent module — own cascade)
    ----------------------------------------------------------------
    local chDB = KE.db and KE.db.profile.CompareHeader
    if chDB then
        local function GetCompareHeaderModule()
            if KitnEssentials then
                return KitnEssentials:GetModule("CompareHeader", true)
            end
            return nil
        end

        local cardCH = GUIFrame:CreateCard(scrollChild, "Compare Header", yOffset)

        local rowCH = GUIFrame:CreateRow(cardCH.content, Theme.rowHeightLast)
        local compareHeaderCheck = GUIFrame:CreateCheckbox(rowCH, "Style Compare Header", {
            value = chDB.Enabled == true,
            callback = function(checked)
                chDB.Enabled = checked
                local CH = GetCompareHeaderModule()
                if CH then CH:ApplySettings() end
                -- Turning it ON styles the header immediately; turning it OFF
                -- cannot un-style it, so that direction needs a reload.
                if not checked then KE:FlagReloadNeeded() end
            end,
            tooltip = "Styles the \"Equipped\" header on item comparison tooltips to match the rest of the tooltip skin. Turning it off needs a reload.",
        })
        rowCH:AddWidget(compareHeaderCheck, 1)
        cardCH:AddRow(rowCH, Theme.rowHeightLast, 0)

        yOffset = cardCH:GetNextOffset()
    end

    return yOffset
end)

GUIFrame:RegisterTabbedContent("CharacterPanel", function()
    local db = KE.db and KE.db.profile.CharacterPanel
    local EXTRAS = { id = "CharacterPanelExtras", label = "Extras" }
    if not db or db.Enabled == false then
        return { EXTRAS }
    end
    return {
        { id = "CharacterPanelCharacter", label = "Character" },
        { id = "CharacterPanelInspect",   label = "Inspect" },
        EXTRAS,
    }
end, {
    headerBuilder = BuildHeader,
})
