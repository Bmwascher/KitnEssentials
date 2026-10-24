-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyCooldowns.lua                                  ║
-- ║  GUI: Party Cooldowns, Cooldowns tab                     ║
-- ║  Purpose: the party frame icons' settings.               ║
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
    CENTER      = "Center",
    DOWN        = "Down",
    UP          = "Up",
    RIGHT       = "Right",
    LEFT        = "Left",
    CENTER_ROW  = "Center",
    COLUMN_UP   = "Up",
    COLUMN_DOWN = "Down",
}
local GROW_TOOLTIP = "Which way the icons run and wrap. The choices follow Side of the Frame and never point " ..
    "at the party frame. Left or Right: Center centers the first line on the frame with further lines below " ..
    "it, Down starts at its top edge, Up at its bottom edge. Above or Below: Right starts at the frame's left " ..
    "edge, Left at its right edge, Center centers the cooldown icons on the frame with the active buffs on " ..
    "the next line, Up or Down stacks the icons in a column centered on the frame, further columns to its " ..
    "right. Inside has one layout."

local ICON_SIZE_MIN, ICON_SIZE_MAX = 16, 72

----------------------------------------------------------------
-- Icon Order strip: drag an icon to a new place
----------------------------------------------------------------
local ORDER_ICON = 36
local ORDER_CELL = 96
local ORDER_HEIGHT = ORDER_ICON + 22
local ORDER_SLOTS = #KE.PartyBuffsRules.CELL_CATEGORIES
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Labeled as their Party Frame Icons picks.
local ORDER_LABELS = { spells = "Class Cooldowns", racial = "Racials", trinket = "Trinkets" }

-- Each category's picture, read when drawn: your class icon, the first
-- tracked racial's spell icon, the empty trinket slot. One that cannot be
-- read shows a question mark. A slot changes category on a reorder, so the
-- atlas's texture coordinates are reset first.
local function SetOrderIcon(tex, key)
    tex:SetTexCoord(0, 1, 0, 1)
    if key == "spells" then
        local _, classFile = UnitClass("player")
        local atlas = type(classFile) == "string" and ("classicon-" .. strlower(classFile))
        if atlas and C_Texture.GetAtlasInfo(atlas) then
            tex:SetAtlas(atlas)
            return
        end
    elseif key == "racial" then
        local racials = KE.PartyCooldownsData and KE.PartyCooldownsData.RACIALS
        local icon = racials and racials[1] and C_Spell.GetSpellTexture(racials[1].id)
        if icon then
            tex:SetTexture(icon)
            return
        end
    else
        local _, icon = C_PaperDollInfo.GetInventorySlotInfo("Trinket0Slot")
        if icon then
            tex:SetTexture(icon)
            return
        end
    end
    tex:SetTexture(QUESTION_MARK)
end

local function OrderDropIndex(strip, cursorX)
    local left = strip:GetLeft()
    if not left then return 1 end
    local idx = math.floor((cursorX - left) / ORDER_CELL) + 1
    return math.max(1, math.min(ORDER_SLOTS, idx))
end

local function LayoutOrder(strip)
    for i, slot in ipairs(strip._slots) do
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", strip, "TOPLEFT", (i - 1) * ORDER_CELL, 0)
        SetOrderIcon(slot.icon, slot.key)
        slot.label:SetText(ORDER_LABELS[slot.key])
        slot:SetAlpha(1)
    end
end

local function SaveOrder(strip)
    local onOrderChanged = strip._onOrderChanged
    if not onOrderChanged then return end
    local list = {}
    for i, slot in ipairs(strip._slots) do list[i] = slot.key end
    onOrderChanged(list)
end

-- Attached to the held icon for the length of the drag only.
local function OrderDragUpdate(slot)
    local strip = slot._strip
    local cursorX, cursorY = GetCursorPosition()
    local scale = strip:GetEffectiveScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale
    local ghost = strip._ghost
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX, cursorY)
    local dropLine = strip._dropLine
    dropLine:ClearAllPoints()
    dropLine:SetPoint("CENTER", strip, "TOPLEFT",
        (OrderDropIndex(strip, cursorX) - 1) * ORDER_CELL + (ORDER_CELL - ORDER_ICON) / 2 - 4, -(ORDER_ICON / 2 + 2))
    dropLine:Show()
end

local function ConstructOrderStrip(parent)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(ORDER_SLOTS * ORDER_CELL, ORDER_HEIGHT)
    strip._enabled = true

    local ghost = strip:CreateTexture(nil, "OVERLAY", nil, 7)
    ghost:SetSize(ORDER_ICON, ORDER_ICON)
    ghost:SetAlpha(0.7)
    ghost:Hide()
    strip._ghost = ghost

    local dropLine = strip:CreateTexture(nil, "OVERLAY", nil, 6)
    dropLine:SetSize(2, ORDER_ICON + 4)
    dropLine:Hide()
    strip._dropLine = dropLine

    local slots = {}
    strip._slots = slots
    local owned = { strip }

    for i = 1, ORDER_SLOTS do
        local slot = CreateFrame("Button", nil, strip)
        slot:SetSize(ORDER_CELL, ORDER_HEIGHT)
        slot._strip = strip

        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ORDER_ICON, ORDER_ICON)
        icon:SetPoint("TOP", slot, "TOP", 0, -2)
        slot.icon = icon

        local highlight = slot:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(icon)
        slot.highlight = highlight

        local label = slot:CreateFontString(nil, "OVERLAY")
        KE:ApplyThemeFont(label, "small")
        label:SetShadowColor(0, 0, 0, 0)
        label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        label:SetPoint("TOP", icon, "BOTTOM", 0, -4)
        slot.label = label

        slot:EnableMouse(true)
        slot:RegisterForDrag("LeftButton")

        local function EndDrag()
            slot:SetScript("OnUpdate", nil)
            slot:SetAlpha(1)
            strip._dragSlot = nil
            ghost:Hide()
            dropLine:Hide()
        end
        slot._endDrag = EndDrag

        slot:SetScript("OnDragStart", function(self)
            if not strip._enabled then return end
            local unfinished = strip._dragSlot
            if unfinished and unfinished ~= self then unfinished._endDrag() end
            strip._dragSlot = self
            SetOrderIcon(ghost, self.key)
            ghost:Show()
            self:SetAlpha(0.3)
            slot:SetScript("OnUpdate", OrderDragUpdate)
        end)

        slot:SetScript("OnDragStop", function(self)
            if strip._dragSlot ~= self then return end
            EndDrag()
            local cursorX = GetCursorPosition()
            local dropIdx = OrderDropIndex(strip, cursorX / strip:GetEffectiveScale())
            local fromIdx
            for idx, s in ipairs(slots) do
                if s == self then
                    fromIdx = idx
                    break
                end
            end
            if fromIdx and dropIdx ~= fromIdx then
                table.insert(slots, dropIdx, table.remove(slots, fromIdx))
                LayoutOrder(strip)
                SaveOrder(strip)
            end
        end)

        slots[i] = slot
        owned[#owned + 1] = slot
    end

    -- The page's state manager calls this.
    function strip:SetEnabled(enabled)
        self._enabled = enabled == true
        if not self._enabled and self._dragSlot then self._dragSlot._endDrag() end
        self:SetAlpha(self._enabled and 1 or 0.4)
    end

    -- Closing the settings hides the page without releasing it, and no
    -- OnDragStop reaches a hidden icon.
    strip:SetScript("OnHide", function(self)
        if self._dragSlot then self._dragSlot._endDrag() end
    end)

    function strip:Configure(order, onOrderChanged)
        self._onOrderChanged = onOrderChanged
        dropLine:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.9)
        for i, slot in ipairs(slots) do
            slot.key = order[i]
            slot.highlight:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.3)
        end
        self:SetEnabled(true)
        LayoutOrder(self)
    end

    strip._keOwned = owned
    return strip
end

-- A strip released mid-drag would keep its OnUpdate running on a hidden page.
GUIFrame:NewWidgetPool("pcd:orderstrip", ConstructOrderStrip, function(strip)
    local dragging = strip._dragSlot
    if dragging then dragging._endDrag() end
end)

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

    -- A glow drag calls back on every mouse move.
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

    -- Party Frame Icons off grays every setting of the rows beside party
    -- frames; Potion bars and the raid cooldowns box keep theirs live.
    manager:SetCondition("iconsOn", function() return db.FrameIcons == true end)
    manager:SetCondition("healerOn", function()
        return db.UseHealerPlacement == true and db.FrameIcons == true
    end)
    manager:SetCondition("classOn", function() return db.TrackBurst == true and db.FrameIcons == true end)
    manager:SetCondition("racialsOn", function() return db.ShowRacials == true and db.FrameIcons == true end)
    -- Without the sensor file the cooldown cells do not exist, and their
    -- settings are grayed.
    manager:SetCondition("cellsOn", function()
        return KE.PartyCooldownsSensor ~= nil and db.FrameIcons == true
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

    -- picks: { label, key, tooltip, onChange } each; isLast ends the card;
    -- state, when given, is each pick's one state group.
    local function AddPicks(card, picks, isLast, state)
        local grid = {}
        for i, pick in ipairs(picks) do
            grid[i] = { label = pick[1], config = CheckConfig(pick[2], pick[3], pick[4]) }
        end
        local cells = card:AddCheckboxGrid(grid, { isLast = isLast })
        if state then manager:RegisterGroup(cells, state) end
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

    ----------------------------------------------------------------
    -- Card: Party Frame Icons, the switch for everything beside the party
    -- frames
    ----------------------------------------------------------------
    local cardTracked = GUIFrame:CreateCard(scrollChild, "Party Frame Icons", yOffset)
    cardTracked:AddHeaderToggle(db.FrameIcons == true, function(checked)
        db.FrameIcons = checked
        ApplySettings()
    end)
    cardTracked:AddLabel("Cooldown and active buff icons beside each party frame. "
        .. "Potion bars and Raid Cooldowns work with this off.")
    AddPicks(cardTracked, {
        { "Class Cooldowns", "TrackBurst",
            "Each party member's offensive and personal defensive cooldowns, by spec.", RefreshStates },
        { "Trinkets", "TrackTrinket", nil, RefreshStates },
        { "Externals", "TrackExternal" },
        { "Potions", "TrackPotion", "Shows a potion's icon while its buff is up. The list is on the Potions tab." },
        { "Racials", "ShowRacials",
            "The racial of a party member who is a Dwarf, Dark Iron Dwarf or Night Elf.", RefreshStates },
    }, nil, "iconsOn")
    local rowTSep = GUIFrame:CreateRow(cardTracked.content, Theme.rowHeightSeparator)
    rowTSep:AddWidget(GUIFrame:CreateSeparator(rowTSep), 1)
    cardTracked:AddRow(rowTSep, Theme.rowHeightSeparator)
    local rowT3 = GUIFrame:CreateRow(cardTracked.content, Theme.rowHeightLast)
    manager:Register(AddCheck(rowT3, "Include Yourself", "IncludeSelf", "Adds the same row to your own party frame."),
        "iconsOn")
    cardTracked:AddRow(rowT3, Theme.rowHeightLast, 0)
    yOffset = cardTracked:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Icon Order, the cooldown categories' order on each row
    ----------------------------------------------------------------
    local cardOrder = GUIFrame:CreateCard(scrollChild, "Icon Order", yOffset)
    manager:Register(cardOrder, "cellsOn")
    cardOrder:AddLabel("Drag an icon to set the order of the cooldown icons on each row; "
        .. KE:Gold("Max Cooldown Icons") .. " drops icons from the end. Active buffs (externals, potions "
        .. "and trinket buffs) always show after these, in a fixed order.")
    local rowStrip = GUIFrame:CreateRow(cardOrder.content, ORDER_HEIGHT)
    local strip = GUIFrame:AcquirePooled("pcd:orderstrip", rowStrip)
    strip:ClearAllPoints()
    strip:SetPoint("CENTER", rowStrip, "CENTER", 0, 0)
    strip:Configure(KE.PartyBuffsRules.CategoryOrder(db.CooldownCategoryOrder), function(list)
        db.CooldownCategoryOrder = list
        ApplySettings()
    end)
    manager:Register(strip, "cellsOn")
    cardOrder:AddRow(rowStrip, ORDER_HEIGHT)
    local rowOrderReset = GUIFrame:CreateRow(cardOrder.content, Theme.rowHeightLast)
    local orderReset = GUIFrame:CreateButton(rowOrderReset, "Kitn Defaults", {
        height = 24,
        tooltip = "Class cooldowns, then racials, then trinkets.",
        callback = function()
            db.CooldownCategoryOrder = nil
            ApplySettings()
            RebuildPage()
        end,
    })
    rowOrderReset:AddWidget(orderReset, 0.5)
    manager:Register(orderReset, "cellsOn")
    cardOrder:AddRow(rowOrderReset, Theme.rowHeightLast, 0)
    yOffset = cardOrder:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Display Settings
    ----------------------------------------------------------------
    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    local rowD1 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    manager:Register(AddSlider(rowD1, "Icon Size", "IconSize", ICON_SIZE_MIN, ICON_SIZE_MAX, nil,
        "In a healer spec with Use in Healer Specs on, the Healer tab's Icon Size is used."), "iconsOn")
    manager:Register(AddSlider(rowD1, "Icon Spacing", "IconSpacing", -1, 10), "iconsOn")
    cardDisplay:AddRow(rowD1, Theme.rowHeight)
    local rowD2 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    manager:Register(AddSlider(rowD2, "Max Cooldown Icons", "MaxCooldownIcons", 1,
        KE.PartyBuffsRules.MAX_COOLDOWN_ICONS, nil,
        "Cooldown icons per member, in the Icon Order card's order. Past this count, icons drop from the end."),
        "cellsOn")
    manager:Register(AddSlider(rowD2, "Max Active Buff Icons", "MaxPerMember", 1,
        KE.PartyBuffsRules.MAX_BUFF_ICONS, nil,
        "Active buffs per member (trinket buffs, potions, externals), after the cooldown icons. "
            .. "The row keeps room for all of them. Icons Per Row counts both kinds; once a row "
            .. "wraps, the buffs start a line of their own."), "iconsOn")
    cardDisplay:AddRow(rowD2, Theme.rowHeight)

    local rowDSep = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightSeparator)
    rowDSep:AddWidget(GUIFrame:CreateSeparator(rowDSep), 1)
    cardDisplay:AddRow(rowDSep, Theme.rowHeightSeparator)

    local rowD3 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    manager:Register(AddCheck(rowD3, "Timer Text", "ShowTimer", nil, nil, 1 / 3), "iconsOn")
    manager:Register(AddCheck(rowD3, "Cooldown Text", "ShowCooldownText",
        "The time left on a gray icon after its buff falls, in the General tab's Font Settings font and this "
            .. "card's Timer Size.",
        nil, 1 / 3), "cellsOn")
    manager:Register(AddCheck(rowD3, "Time-Left Swipe", "Swipe", nil, nil, 1 / 3), "iconsOn")
    cardDisplay:AddRow(rowD3, Theme.rowHeight)
    -- The timer, the cooldown text and the stack count share this size.
    local rowD4 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightLast)
    manager:Register(AddSlider(rowD4, "Timer Size", "TimerFontSize", 8, 48), "iconsOn")
    manager:Register(AddSlider(rowD4, "Show Decimals Below (sec)", "DecimalThreshold", 0, 10,
        KE.AuraRules.NormalizeDecimalThreshold(db.DecimalThreshold)), "iconsOn")
    cardDisplay:AddRow(rowD4, Theme.rowHeightLast, 0)
    yOffset = cardDisplay:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Glow, while a buff is active
    ----------------------------------------------------------------
    local glowCard, glowOffset = GUIFrame:CreateAuraGlowCard(scrollChild, yOffset, {
        title = "Glow",
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
    manager:Register(glowCard, "iconsOn")
    yOffset = glowOffset

    ----------------------------------------------------------------
    -- Card: Icon Position, one view per placement
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
        manager:Register(widget, healerView and "healerOn" or "iconsOn")
    end

    local cardPosition = GUIFrame:CreateCard(scrollChild, "Icon Position", yOffset)
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
        manager:Register(healerToggle, "iconsOn")
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
        return db.FrameIcons == true and #layouts > 1 and (not healerView or db.UseHealerPlacement == true)
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
        "Icons on one line before the row wraps; in an Up or Down column, icons per column. At "
            .. KE.PartyBuffsRules.MAX_PER_ROW .. " it never wraps."))
    if healerView then
        AddPlacement(AddSlider(rowX3, "Icon Size", PlacementKey("IconSize"), ICON_SIZE_MIN, ICON_SIZE_MAX,
            PlacementValue("IconSize"),
            "Icon size in a healer spec. Other specs use Icon Size on the Display Settings card."))
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

        local listCard, listOffset = GUIFrame:CreateAuraAllowlistCard(scrollChild, yOffset, {
            title = ListLabel(listKey),
            allowlist = db[listKey],
            getDefaults = function() return ShippedList(listKey) end,
            infoTitle = "Spell List Info",
            infoText = "An icon in this category shows only when its spell is on this list and its row is switched on. Only helpful auras on your party members can be matched this way.",
            restoreActions = restoreActions,
            onChangeCallback = ApplySettings,
        })
        manager:Register(listCard, "iconsOn")
        yOffset = listOffset
    end

    RefreshStates()
    return yOffset
end)
