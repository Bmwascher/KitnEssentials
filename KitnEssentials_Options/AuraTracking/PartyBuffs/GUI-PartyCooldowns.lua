-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyCooldowns.lua                                  ║
-- ║  GUI: Party Cooldowns, Cooldowns tab                     ║
-- ║  Purpose: every setting of the Party Cooldowns module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

local LIST_TABS = {
    { id = "ClassCooldowns", label = "Class Cooldowns" },
    { id = "ListTrinkets",   label = "Trinkets" },
    { id = "ListExternals",  label = "Externals" },
}

local SIDE_OPTIONS = {
    { key = "LEFT",   text = "Left, Outside" },
    { key = "RIGHT",  text = "Right, Outside" },
    { key = "ABOVE",  text = "Above" },
    { key = "BELOW",  text = "Below" },
    { key = "INSIDE", text = "Inside, Bottom-Right" },
}

-- Each side's own choices, in order, come from PartyBuffsRules.LAYOUTS.
local GROW_TEXT = {
    CENTER = "Center",
    DOWN   = "Down",
    UP     = "Up",
    RIGHT  = "Right",
    LEFT   = "Left",
}
local GROW_TOOLTIP = "Which way the icons run and wrap. The choices follow Side of the Frame and never point " ..
    "at the party frame. Left or Right: Center keeps the icons centered on the frame, Down starts them at its " ..
    "top edge, Up at its bottom edge. Above or Below: Right starts them at the frame's left edge, Left at its " ..
    "right edge. Inside has one layout."

-- state: the picker's one state group, when not colorsOn.
local COLOR_PICKERS = {
    { key = "ColorExternal",     label = "Externals" },
    { key = "ColorBigDefensive", label = "Defensive CDs", state = "defensiveOn" },
    { key = "ColorBurst",        label = "Offensive CDs" },
    { key = "ColorPotion",       label = "Potion" },
    { key = "ColorTrinket",      label = "Trinket" },
}

local PICK_COLUMNS = 3
local PICK_HEIGHT = 24
local PICK_SPACING = 2

local ICON_SIZE_MIN, ICON_SIZE_MAX = 16, 72

local HEALER_KEY, PLACEMENT_PAIR = {}, {}
for _, pair in ipairs(KE.PartyBuffsRules.PLACEMENT_KEYS) do
    HEALER_KEY[pair[1]] = pair[2]
    PLACEMENT_PAIR[pair[1]] = pair
end

-- Both survive the page rebuild a tab switch triggers. activePlacement stays
-- nil until the first render picks the view the player's spec uses.
local activeList = "ClassCooldowns"
local activePlacement

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("PartyBuffs", true) end

local ShippedList = KE.PartyCooldownsPage.ShippedList

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

GUIFrame:RegisterContent("PartyBuffsCooldowns", function(scrollChild, yOffset)
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

    -- A color or glow drag calls back on every mouse move.
    local function QueueApply()
        if PB and PB.QueueApplySettings then PB:QueueApplySettings() end
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
    manager:SetCondition("classOn", function() return db.TrackBurst == true end)
    manager:SetCondition("racialsOn", function() return db.ShowRacials == true end)
    -- Without the sensor file the cooldown cells do not exist, and their
    -- settings are grayed. Only the cells use the defensive color.
    manager:SetCondition("cellsOn", function() return KE.PartyCooldownsSensor ~= nil end)
    manager:SetCondition("defensiveOn", function()
        return db.CategoryColors == true and KE.PartyCooldownsSensor ~= nil
    end)

    local function CheckConfig(key, tooltip, onChange)
        return {
            value = db[key] == true,
            callback = function(checked)
                db[key] = checked
                ApplySettings()
                if onChange then onChange() end
            end,
            tooltip = tooltip,
        }
    end

    local function AddCheck(row, label, key, tooltip, onChange, width)
        local check = GUIFrame:CreateCheckbox(row, label, CheckConfig(key, tooltip, onChange))
        row:AddWidget(check, width or 0.5)
        return check
    end

    -- picks: { label, key, tooltip, onChange } each; isLast ends the card.
    local function AddPicks(card, picks, isLast)
        for i = 1, #picks, PICK_COLUMNS do
            local row = GUIFrame:CreateRow(card.content, PICK_HEIGHT)
            for j = i, math.min(i + PICK_COLUMNS - 1, #picks) do
                local pick = picks[j]
                row:AddWidget(GUIFrame:CreateCompactCheckbox(row, pick[1],
                    CheckConfig(pick[2], pick[3], pick[4])), 1 / PICK_COLUMNS)
            end
            local lastRow = isLast and i + PICK_COLUMNS > #picks
            card:AddRow(row, PICK_HEIGHT, lastRow and 0 or PICK_SPACING)
        end
    end

    -- value, when given, is shown in place of db[key].
    local function AddSlider(row, label, key, low, high, value, tooltip)
        if value == nil then value = db[key] end
        local slider = GUIFrame:CreateSlider(row, label, {
            min = low, max = high, step = 1,
            value = value,
            callback = function(val) db[key] = val; ApplySettings() end,
            tooltip = tooltip,
        })
        row:AddWidget(slider, 0.5)
        return slider
    end

    local function AddDropdown(row, label, key, options, value, tooltip, onChange)
        if value == nil then value = db[key] end
        local dropdown = GUIFrame:CreateDropdown(row, label, {
            options = options,
            value = value,
            callback = function(choice)
                db[key] = choice
                ApplySettings()
                if onChange then onChange() end
            end,
            tooltip = tooltip,
        })
        row:AddWidget(dropdown, 0.5)
        return dropdown
    end

    local function AddColor(row, spec)
        local picker = GUIFrame:CreateColorPicker(row, spec.label, {
            color = db[spec.key],
            callback = function(r, g, b, a)
                db[spec.key] = { r, g, b, a }
                QueueApply()
            end,
        })
        row:AddWidget(picker, 1 / 3)
        manager:Register(picker, spec.state or "colorsOn")
    end

    ----------------------------------------------------------------
    -- Card: Tracked
    ----------------------------------------------------------------
    local cardTracked = GUIFrame:CreateCard(scrollChild, "Tracked", yOffset)
    AddPicks(cardTracked, {
        { "Class Cooldowns", "TrackBurst",
            "Each party member's offensive and personal defensive cooldowns, by spec.", RefreshStates },
        { "Trinkets", "TrackTrinket", nil, RefreshStates },
        { "Externals", "TrackExternal" },
        { "Potions", "TrackPotion", "Shows a potion's icon while its buff is up. The list is on the Potions tab." },
        { "Racials", "ShowRacials",
            "The racial of a party member who is a Dwarf, Dark Iron Dwarf or Night Elf.", RefreshStates },
    })
    local rowTSep = GUIFrame:CreateRow(cardTracked.content, Theme.rowHeightSeparator)
    rowTSep:AddWidget(GUIFrame:CreateSeparator(rowTSep), 1)
    cardTracked:AddRow(rowTSep, Theme.rowHeightSeparator)
    local rowT3 = GUIFrame:CreateRow(cardTracked.content, Theme.rowHeightLast)
    AddCheck(rowT3, "Include Yourself", "IncludeSelf", "Adds the same row to your own party frame.")
    cardTracked:AddRow(rowT3, Theme.rowHeightLast, 0)
    yOffset = cardTracked:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Where It Shows
    ----------------------------------------------------------------
    local cardPlaces = GUIFrame:CreateCard(scrollChild, "Where It Shows", yOffset)
    cardPlaces:AddLabel("Not shown in raids, battlegrounds or other raid groups.")
    AddPicks(cardPlaces, {
        { "Mythic+", "ShowInKeys" },
        { "All Other Dungeon Types", "ShowInDungeons" },
        { "Delves", "ShowInDelves" },
        { "Open World", "ShowInWorld" },
        { "Arenas", "ShowInArenas" },
    }, true)
    yOffset = cardPlaces:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Display
    ----------------------------------------------------------------
    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Display", yOffset)
    local rowD1 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddSlider(rowD1, "Icon Size", "IconSize", ICON_SIZE_MIN, ICON_SIZE_MAX, nil,
        "In a healer spec with Use in Healer Specs on, the Healer tab's Icon Size is used.")
    AddSlider(rowD1, "Icon Spacing", "IconSpacing", 0, 10)
    cardDisplay:AddRow(rowD1, Theme.rowHeight)
    local rowD2 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    manager:Register(AddSlider(rowD2, "Max Cooldown Icons", "MaxCooldownIcons", 1,
        KE.PartyBuffsRules.MAX_COOLDOWN_ICONS), "cellsOn")
    AddSlider(rowD2, "Max Active Buff Icons", "MaxPerMember", 1, KE.PartyBuffsRules.MAX_BUFF_ICONS)
    cardDisplay:AddRow(rowD2, Theme.rowHeight)

    local rowDSep = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightSeparator)
    rowDSep:AddWidget(GUIFrame:CreateSeparator(rowDSep), 1)
    cardDisplay:AddRow(rowDSep, Theme.rowHeightSeparator)

    local rowD3 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddCheck(rowD3, "Timer Text", "ShowTimer", nil, nil, 1 / 3)
    manager:Register(AddCheck(rowD3, "Cooldown Text", "ShowCooldownText",
        "The time left on a gray icon after its buff falls, in the Font Settings font and Timer Size.",
        nil, 1 / 3), "cellsOn")
    AddCheck(rowD3, "Time-Left Swipe", "Swipe", nil, nil, 1 / 3)
    cardDisplay:AddRow(rowD3, Theme.rowHeight)

    local rowDSep2 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightSeparator)
    rowDSep2:AddWidget(GUIFrame:CreateSeparator(rowDSep2), 1)
    cardDisplay:AddRow(rowDSep2, Theme.rowHeightSeparator)

    local rowD4 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddCheck(rowD4, "Border Color by Category", "CategoryColors", nil, RefreshStates, 1 / 3)
    for i = 1, 2 do AddColor(rowD4, COLOR_PICKERS[i]) end
    cardDisplay:AddRow(rowD4, Theme.rowHeight)
    local rowD5 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightLast)
    for i = 3, 5 do AddColor(rowD5, COLOR_PICKERS[i]) end
    cardDisplay:AddRow(rowD5, Theme.rowHeightLast, 0)
    yOffset = cardDisplay:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Glow While Active
    ----------------------------------------------------------------
    local glowCard, glowOffset = GUIFrame:CreateAuraGlowCard(scrollChild, yOffset, {
        title = "Glow While Active",
        db = db,
        types = {
            { key = "pixel",    text = "Pixel" },
            { key = "ants",     text = "Ants" },
            { key = "procloop", text = "Proc Loop" },
            { key = "alert",    text = "Alert" },
            { key = "border",   text = "Pulse Border" },
        },
        -- The pulse runs at a fixed rhythm.
        showSpeed = function(glowType) return glowType ~= "border" end,
        onChangeCallback = QueueApply,
        onHeightChange = RebuildPage,
    })
    -- The buff icons glow too, so the card applies without the cooldown cells.
    manager:Register(glowCard, "all")
    yOffset = glowOffset

    ----------------------------------------------------------------
    -- Card: Font Settings (the timer, the cooldown text and the stack
    -- count share the font and outline)
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
    -- Card: Position, one view per placement
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
        tabs = GUIFrame.HEALER_VIEW_TABS,
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
        return KE.PartyBuffsRules.PlacementValue(db, PLACEMENT_PAIR[key], healerView)
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
        cardPosition:AddRow(rowX0, Theme.rowHeight)
    end
    local rowX1 = GUIFrame:CreateRow(cardPosition.content, Theme.rowHeight)
    -- A side change redraws the page, so Grow lists the new side's choices.
    AddPlacement(AddDropdown(rowX1, "Side of the Frame", PlacementKey("Side"), SIDE_OPTIONS, PlacementValue("Side"),
        nil, RebuildPage))
    local layout, layouts = KE.PartyBuffsRules.Layout(PlacementValue("Side"), PlacementValue("Grow"))
    local growOptions = {}
    for i = 1, #layouts do
        growOptions[i] = { key = layouts[i].grow, text = GROW_TEXT[layouts[i].grow] }
    end
    -- One group for both reasons to gray it: a widget in two groups is set at random.
    manager:SetCondition("growOn", function()
        return #layouts > 1 and (not healerView or db.UseHealerPlacement == true)
    end)
    manager:Register(AddDropdown(rowX1, "Grow", PlacementKey("Grow"), growOptions, layout.grow, GROW_TOOLTIP),
        "growOn")
    cardPosition:AddRow(rowX1, Theme.rowHeight)
    local rowX2 = GUIFrame:CreateRow(cardPosition.content, Theme.rowHeight)
    AddPlacement(AddSlider(rowX2, "X Offset", PlacementKey("XOffset"), -100, 100, PlacementValue("XOffset")))
    AddPlacement(AddSlider(rowX2, "Y Offset", PlacementKey("YOffset"), -100, 100, PlacementValue("YOffset")))
    cardPosition:AddRow(rowX2, Theme.rowHeight)
    local rowX3 = GUIFrame:CreateRow(cardPosition.content, Theme.rowHeightLast)
    AddPlacement(AddSlider(rowX3, "Icons Per Row", PlacementKey("IconsPerRow"), 1,
        KE.PartyBuffsRules.MAX_PER_ROW, PlacementValue("IconsPerRow"),
        "Icons on one line before the row wraps. At " .. KE.PartyBuffsRules.MAX_PER_ROW
            .. " it never wraps."))
    if healerView then
        AddPlacement(AddSlider(rowX3, "Icon Size", PlacementKey("IconSize"), ICON_SIZE_MIN, ICON_SIZE_MAX,
            PlacementValue("IconSize"), "Icon size in a healer spec. Other specs use Icon Size on the Display card."))
    end
    cardPosition:AddRow(rowX3, Theme.rowHeightLast, 0)
    yOffset = cardPosition:GetNextOffset()

    ----------------------------------------------------------------
    -- Spell lists: one card for the active sub-tab
    ----------------------------------------------------------------
    local _, tabOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = LIST_TABS,
        activeId = activeList,
        onSwitch = function(newId) activeList = newId end,
        fill = true,
    })
    yOffset = tabOffset

    if activeList == "ClassCooldowns" then
        local classCard, classOffset = KE.PartyCooldownsPage.ClassCooldownsCard(scrollChild, yOffset, {
            db = db,
            apply = ApplySettings,
        })
        manager:Register(classCard, "classOn")
        yOffset = classOffset
        local racialCard, racialOffset = KE.PartyCooldownsPage.RacialsCard(scrollChild, yOffset, {
            db = db,
            apply = ApplySettings,
        })
        manager:Register(racialCard, "racialsOn")
        yOffset = racialOffset
    else
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
            infoText = "An icon in this category shows only when its spell is on this list and its row is switched on. Only helpful auras on your party members can be matched this way.",
            restoreActions = restoreActions,
            onChangeCallback = ApplySettings,
        })
        yOffset = listOffset
    end

    RefreshStates()
    return yOffset
end)
