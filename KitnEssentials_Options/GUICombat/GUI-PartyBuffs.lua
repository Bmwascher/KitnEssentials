-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyBuffs.lua                                      ║
-- ║  GUI: Party Buffs                                        ║
-- ║  Purpose: Configuration panel for the PartyBuffs module  ║
-- ║           (teammates' big buffs beside party frames).    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

local LIST_TABS = {
    { id = "ListBurst",     label = "Offensive CDs" },
    { id = "ListPotions",   label = "Potions" },
    { id = "ListTrinkets",  label = "Trinkets" },
    { id = "ListExternals", label = "Externals" },
}

local SIDE_OPTIONS = {
    { key = "LEFT",   text = "Left, Outside" },
    { key = "RIGHT",  text = "Right, Outside" },
    { key = "ABOVE",  text = "Above" },
    { key = "BELOW",  text = "Below" },
    { key = "INSIDE", text = "Inside, Bottom-Right" },
}

local STRATA_OPTIONS = {
    { key = "FRAME",  text = "Same as the Party Frame" },
    { key = "LOW",    text = "Low" },
    { key = "MEDIUM", text = "Medium" },
    { key = "HIGH",   text = "High" },
    { key = "DIALOG", text = "Dialog" },
}

local COLOR_PICKERS = {
    { key = "ColorExternal",     label = "Externals" },
    { key = "ColorBigDefensive", label = "Big Defensive" },
    { key = "ColorBurst",        label = "Offensive CDs" },
    { key = "ColorPotion",       label = "Potion" },
    { key = "ColorTrinket",      label = "Trinket" },
}

local PLACEMENT_TABS = {
    { id = "DEFAULT", label = "Default" },
    { id = "HEALER",  label = "Healer" },
}

-- Each placement key's healer copy, taken from the module's own list.
local HEALER_KEY = {}
for _, pair in ipairs(KE.PartyBuffsRules.PLACEMENT_KEYS) do HEALER_KEY[pair[1]] = pair[2] end

-- Both survive the page rebuild a tab switch triggers. activePlacement stays
-- nil until the first render picks the view the player's spec uses.
local activeList = "ListBurst"
local activePlacement

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("PartyBuffs", true) end

local function ShippedList(listKey)
    if not KE.GetDefaultDB then return {} end
    local root = KE:GetDefaultDB()
    local section = root and root.profile and root.profile.PartyBuffs
    return (section and section[listKey]) or {}
end

local function ListLabel(listKey)
    for i = 1, #LIST_TABS do
        if LIST_TABS[i].id == listKey then return LIST_TABS[i].label end
    end
    return listKey
end

local function BlizzardFlagged(spellID)
    local ok, flagged = pcall(C_Spell.IsExternalDefensive, spellID)
    return ok and flagged
end

GUIFrame:RegisterContent("PartyBuffs", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PartyBuffs
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local PB = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if PB and PB.ApplySettings then PB:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("PartyBuffs")
        else
            KitnEssentials:DisableModule("PartyBuffs")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled == true)
    end

    local function RebuildPage()
        if GUIFrame.RefreshContent then
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end
    end

    manager:SetCondition("colorsOn", function() return db.CategoryColors == true end)
    manager:SetCondition("healerOn", function() return db.UseHealerPlacement == true end)

    local function AddCheck(row, label, key, tooltip, onChange)
        local check = GUIFrame:CreateCheckbox(row, label, {
            value = db[key] == true,
            callback = function(checked)
                db[key] = checked
                ApplySettings()
                if onChange then onChange() end
            end,
            tooltip = tooltip,
        })
        row:AddWidget(check, 0.5)
    end

    -- value, when given, is shown in place of db[key].
    local function AddSlider(row, label, key, low, high, value)
        if value == nil then value = db[key] end
        local slider = GUIFrame:CreateSlider(row, label, {
            min = low, max = high, step = 1,
            value = value,
            callback = function(val) db[key] = val; ApplySettings() end,
        })
        row:AddWidget(slider, 0.5)
        return slider
    end

    local function AddDropdown(row, label, key, options, value)
        if value == nil then value = db[key] end
        local dropdown = GUIFrame:CreateDropdown(row, label, {
            options = options,
            value = value,
            callback = function(choice) db[key] = choice; ApplySettings() end,
        })
        row:AddWidget(dropdown, 0.5)
        return dropdown
    end

    local function AddColor(row, spec)
        local picker = GUIFrame:CreateColorPicker(row, spec.label, {
            color = db[spec.key],
            callback = function(r, g, b, a)
                db[spec.key] = { r, g, b, a }
                ApplySettings()
            end,
        })
        row:AddWidget(picker, 1 / 3)
        manager:Register(picker, "colorsOn")
    end

    ----------------------------------------------------------------
    -- Card 1: Party Buffs
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Party Buffs", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        ApplyModuleState(checked)
    end)
    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return yOffset end

    card1:AddLabel("Shows your party members' big cooldown buffs as icons beside their party frames while each " ..
        "buff is up: externals, defensives, offensive cooldowns, potions and trinkets. Works on Blizzard's " ..
        "party frames and on EllesmereUI frames. Where it shows is chosen below.")
    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Tracked Buffs
    ----------------------------------------------------------------
    local cardTracked = GUIFrame:CreateCard(scrollChild, "Tracked Buffs", yOffset)
    local rowT1 = GUIFrame:CreateRow(cardTracked.content, Theme.rowHeight)
    AddCheck(rowT1, "Externals", "TrackExternal")
    AddCheck(rowT1, "Big Defensives", "TrackBigDefensive",
        "Blizzard's and EllesmereUI's party frames already show these in the frame center.")
    cardTracked:AddRow(rowT1, Theme.rowHeight)
    local rowT2 = GUIFrame:CreateRow(cardTracked.content, Theme.rowHeight)
    AddCheck(rowT2, "Offensive CDs", "TrackBurst")
    AddCheck(rowT2, "Potions", "TrackPotion")
    cardTracked:AddRow(rowT2, Theme.rowHeight)
    local rowT3 = GUIFrame:CreateRow(cardTracked.content, Theme.rowHeightLast)
    AddCheck(rowT3, "Trinkets", "TrackTrinket")
    cardTracked:AddRow(rowT3, Theme.rowHeightLast, 0)
    yOffset = cardTracked:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Where It Shows
    ----------------------------------------------------------------
    local cardPlaces = GUIFrame:CreateCard(scrollChild, "Where It Shows", yOffset)
    cardPlaces:AddLabel("Not shown in raids, battlegrounds or other raid groups.")
    local rowP1 = GUIFrame:CreateRow(cardPlaces.content, Theme.rowHeight)
    AddCheck(rowP1, "Mythic+", "ShowInKeys")
    AddCheck(rowP1, "All Other Dungeon Types", "ShowInDungeons")
    cardPlaces:AddRow(rowP1, Theme.rowHeight)
    local rowP2 = GUIFrame:CreateRow(cardPlaces.content, Theme.rowHeight)
    AddCheck(rowP2, "Delves", "ShowInDelves")
    AddCheck(rowP2, "Open World", "ShowInWorld")
    cardPlaces:AddRow(rowP2, Theme.rowHeight)
    local rowP3 = GUIFrame:CreateRow(cardPlaces.content, Theme.rowHeightLast)
    AddCheck(rowP3, "Arenas", "ShowInArenas")
    cardPlaces:AddRow(rowP3, Theme.rowHeightLast, 0)
    yOffset = cardPlaces:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Display
    ----------------------------------------------------------------
    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Display", yOffset)
    local rowD1 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddSlider(rowD1, "Icon Size", "IconSize", 16, 72)
    AddSlider(rowD1, "Icon Spacing", "IconSpacing", 0, 10)
    cardDisplay:AddRow(rowD1, Theme.rowHeight)
    local rowD2 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddSlider(rowD2, "Max Icons Per Member", "MaxPerMember", 1, 8)
    cardDisplay:AddRow(rowD2, Theme.rowHeight)

    local rowDSep = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightSeparator)
    rowDSep:AddWidget(GUIFrame:CreateSeparator(rowDSep), 1)
    cardDisplay:AddRow(rowDSep, Theme.rowHeightSeparator)

    local rowD3 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddCheck(rowD3, "Time-Left Swipe", "Swipe")
    AddCheck(rowD3, "Timer Text", "ShowTimer")
    cardDisplay:AddRow(rowD3, Theme.rowHeight)
    local rowD3b = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddCheck(rowD3b, "Border Color by Category", "CategoryColors", nil, RefreshStates)
    cardDisplay:AddRow(rowD3b, Theme.rowHeight)
    local rowD4 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    for i = 1, 3 do AddColor(rowD4, COLOR_PICKERS[i]) end
    cardDisplay:AddRow(rowD4, Theme.rowHeight)
    local rowD5 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightLast)
    for i = 4, 5 do AddColor(rowD5, COLOR_PICKERS[i]) end
    cardDisplay:AddRow(rowD5, Theme.rowHeightLast, 0)
    yOffset = cardDisplay:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Font Settings (the timer text; the stack count shares the
    -- font and outline)
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Timer Size", dbKey = "TimerFontSize", default = 12 },
        },
        fontSizeRange = { 8, 48 },
        extraSlider = {
            label = "Show Decimals Below (sec)",
            dbKey = "DecimalThreshold",
            min = 0, max = 10, step = 1,
            value = KE.AuraRules.NormalizeDecimalThreshold(db.DecimalThreshold),
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end

    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 6: Position, one view per placement
    ----------------------------------------------------------------
    if activePlacement == nil then
        activePlacement = (db.UseHealerPlacement == true and KE:IsPlayerHealerSpec()) and "HEALER" or "DEFAULT"
    end
    local healerView = activePlacement == "HEALER"

    -- With the toggle off the healer copy never applies, so the Healer view
    -- previews Default.
    local previewContext = (healerView and db.UseHealerPlacement == true) and "HEALER" or "DEFAULT"
    if PB and PB.previewContext ~= previewContext then
        PB.previewContext = previewContext
        if PB.previewing then PB:ShowPreview() end
    end

    local _, placementOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = PLACEMENT_TABS,
        activeId = activePlacement,
        onSwitch = function(newId) activePlacement = newId end,
        fill = true,
    })
    yOffset = placementOffset

    -- The Healer view writes the healer keys and shows each default value
    -- until its healer copy exists, as the module reads them.
    local function PlacementKey(key)
        return healerView and HEALER_KEY[key] or key
    end

    local function PlacementValue(key)
        local value
        if healerView then value = db[HEALER_KEY[key]] end
        if value == nil then value = db[key] end
        return value
    end

    local function AddPlacement(widget)
        if healerView then manager:Register(widget, "healerOn") end
    end

    local cardPosition = GUIFrame:CreateCard(scrollChild, "Position", yOffset)
    if healerView then
        local rowX0 = GUIFrame:CreateRow(cardPosition.content, Theme.rowHeight)
        local healerToggle = GUIFrame:CreateCheckbox(rowX0, "Use in Healer Specs", {
            value = db.UseHealerPlacement == true,
            callback = function(checked)
                db.UseHealerPlacement = checked
                if checked and PB and PB.SeedHealerPlacement then PB:SeedHealerPlacement() end
                ApplySettings()
                RebuildPage()
            end,
        })
        rowX0:AddWidget(healerToggle, 0.5)
        local healerNote = GUIFrame:CreateText(rowX0,
            KE:ColorTextByTheme("Note"),
            db.UseHealerPlacement == true
                and "While your spec is a healer spec, the icons use this placement."
                or "Off: every spec uses the Default placement.",
            Theme.rowHeight, "hide")
        rowX0:AddWidget(healerNote, 0.5)
        cardPosition:AddRow(rowX0, Theme.rowHeight)
    end
    local rowX1 = GUIFrame:CreateRow(cardPosition.content, Theme.rowHeight)
    AddPlacement(AddDropdown(rowX1, "Side of the Frame", PlacementKey("Side"), SIDE_OPTIONS, PlacementValue("Side")))
    AddPlacement(AddDropdown(rowX1, "Frame Strata", PlacementKey("Strata"), STRATA_OPTIONS, PlacementValue("Strata")))
    cardPosition:AddRow(rowX1, Theme.rowHeight)
    local rowX2 = GUIFrame:CreateRow(cardPosition.content, Theme.rowHeightLast)
    AddPlacement(AddSlider(rowX2, "X Offset", PlacementKey("XOffset"), -100, 100, PlacementValue("XOffset")))
    AddPlacement(AddSlider(rowX2, "Y Offset", PlacementKey("YOffset"), -100, 100, PlacementValue("YOffset")))
    cardPosition:AddRow(rowX2, Theme.rowHeightLast, 0)
    yOffset = cardPosition:GetNextOffset()

    ----------------------------------------------------------------
    -- Spell Lists: one card for the active tab
    ----------------------------------------------------------------
    local _, tabOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = LIST_TABS,
        activeId = activeList,
        onSwitch = function(newId) activeList = newId end,
        fill = true,
    })
    yOffset = tabOffset

    local listKey = activeList
    db[listKey] = db[listKey] or {}
    local restoreActions = { { label = "Kitn Defaults" } }
    if listKey == "ListExternals" then
        restoreActions[2] = {
            label = "Blizzard Flagged",
            tooltip = "Enables only the spells this client flags as external defensives, and switches the rest off without deleting them.",
            resolveEnabled = BlizzardFlagged,
        }
    end

    local _, listOffset = GUIFrame:CreateAuraAllowlistCard(scrollChild, yOffset, {
        title = ListLabel(listKey),
        allowlist = db[listKey],
        getDefaults = function() return ShippedList(listKey) end,
        infoTitle = "Spell List Info",
        infoText = "A buff in this category shows only when its spell is on this list and its row is switched on. Only helpful auras on your party members can be matched this way.",
        restoreActions = restoreActions,
        onChangeCallback = ApplySettings,
    })
    yOffset = listOffset

    RefreshStates()
    return yOffset
end)
