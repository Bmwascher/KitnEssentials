-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-AuraDebuffs.lua                                     ║
-- ║  GUI: Aura Debuffs                                       ║
-- ║  Purpose: Configuration panel for the AuraDebuffs        ║
-- ║           module (dispellable / important debuff icons).  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("AuraDebuffs", true) end

GUIFrame:RegisterContent("AuraDebuffs", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.AuraDebuffs
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local AD = GetModule()

    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if AD and AD.ApplySettings then AD:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("AuraDebuffs", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("AuraDebuffs")
        else
            KitnEssentials:DisableModule("AuraDebuffs")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Aura Debuffs", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Aura Debuffs", {
        value = db.Enabled ~= false,
        callback = function(checked)
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText  = "Aura Debuffs",
        msgOn    = "On",
        msgOff   = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType  = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint        = "AnchorFrom",
            anchorPoint      = "AnchorTo",
            xOffset          = "XOffset",
            yOffset          = "YOffset",
            strata           = "Strata",
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
    -- Card 3: Visibility
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Visibility", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local visiDropdown = GUIFrame:CreateDropdown(row3a, "Visibility Mode", {
        options = {
            { key = "boss",     text = "Boss only" },
            { key = "instance", text = "Instance combat" },
            { key = "always",   text = "Always (in combat)" },
        },
        value = db.VisibilityMode or "boss",
        callback = function(key) db.VisibilityMode = key; ApplySettings() end,
    })
    row3a:AddWidget(visiDropdown, 1)
    manager:Register(visiDropdown, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local rowBlacklistNote = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local blacklistNote = GUIFrame:CreateText(rowBlacklistNote,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Encounter Blacklist — comma-separated encounter IDs to exclude (boss mode only).",
        Theme.rowHeight, "hide")
    rowBlacklistNote:AddWidget(blacklistNote, 1)
    manager:Register(blacklistNote, "all")
    card3:AddRow(rowBlacklistNote, Theme.rowHeight)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local blUpdating = false
    local blBox
    blBox = GUIFrame:CreateEditBox(row3c, "e.g. 3306,3454", {
        value = db.EncounterBlacklist or "",
        callback = function(text)
            if blUpdating then return end
            local valid = {}
            for entry in text:gmatch("[^,]+") do
                local trimmed = entry:match("^%s*(.-)%s*$")
                if trimmed and trimmed ~= "" then
                    if tonumber(trimmed) then
                        valid[#valid + 1] = trimmed
                    else
                        KE:Print("Aura Debuffs: Ignored '" .. trimmed .. "' — use numeric encounter IDs only.")
                    end
                end
            end
            local cleaned = table.concat(valid, ",")
            db.EncounterBlacklist = cleaned
            blUpdating = true
            if blBox then blBox:SetValue(cleaned) end
            blUpdating = false
            if AD and AD.RefreshEncounterBlacklist then AD:RefreshEncounterBlacklist() end
        end,
    })
    row3c:AddWidget(blBox, 1)
    manager:Register(blBox, "all")
    card3:AddRow(row3c, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Display
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Display", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local iconSizeSlider = GUIFrame:CreateSlider(row4a, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = db.IconSize or 32,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row4a:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(row4a, "Spacing", {
        min = 0, max = 10, step = 1,
        value = db.IconSpacing or 1,
        callback = function(val) db.IconSpacing = val; ApplySettings() end,
    })
    row4a:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local iconsPerRowSlider = GUIFrame:CreateSlider(row4b, "Icons Per Row", {
        min = 1, max = 12, step = 1,
        value = db.IconsPerRow or 8,
        callback = function(val) db.IconsPerRow = val; ApplySettings() end,
    })
    row4b:AddWidget(iconsPerRowSlider, 0.5)
    manager:Register(iconsPerRowSlider, "all")

    local maxRowsSlider = GUIFrame:CreateSlider(row4b, "Max Rows", {
        min = 1, max = 3, step = 1,
        value = db.MaxRows or 1,
        callback = function(val) db.MaxRows = val; ApplySettings() end,
    })
    row4b:AddWidget(maxRowsSlider, 0.5)
    manager:Register(maxRowsSlider, "all")
    card4:AddRow(row4b, Theme.rowHeight)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local iconZoomSlider = GUIFrame:CreateSlider(row4c, "Icon Zoom", {
        min = 0, max = 0.5, step = 0.05,
        value = db.IconZoom or 0.30,
        callback = function(val) db.IconZoom = val; ApplySettings() end,
    })
    row4c:AddWidget(iconZoomSlider, 0.5)
    manager:Register(iconZoomSlider, "all")

    local growHorizDropdown = GUIFrame:CreateDropdown(row4c, "Grow Horizontal", {
        options = {
            { key = "LEFT",  text = "Left" },
            { key = "RIGHT", text = "Right" },
        },
        value = db.GrowHorizontal or "RIGHT",
        callback = function(key) db.GrowHorizontal = key; ApplySettings() end,
    })
    row4c:AddWidget(growHorizDropdown, 0.5)
    manager:Register(growHorizDropdown, "all")
    card4:AddRow(row4c, Theme.rowHeight)

    local row4d = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local swipeCheck = GUIFrame:CreateCheckbox(row4d, "Swipe (Cooldown Spiral)", {
        value = db.Swipe ~= false,
        callback = function(checked) db.Swipe = checked; ApplySettings() end,
    })
    row4d:AddWidget(swipeCheck, 0.5)
    manager:Register(swipeCheck, "all")

    local growVertDropdown = GUIFrame:CreateDropdown(row4d, "Grow Vertical", {
        options = {
            { key = "UP",   text = "Up" },
            { key = "DOWN", text = "Down" },
        },
        value = db.GrowVertical or "DOWN",
        callback = function(key) db.GrowVertical = key; ApplySettings() end,
    })
    row4d:AddWidget(growVertDropdown, 0.5)
    manager:Register(growVertDropdown, "all")
    card4:AddRow(row4d, Theme.rowHeightLast)

    local row4e = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local reverseCheck = GUIFrame:CreateCheckbox(row4e, "Reverse Cooldown Direction", {
        value = db.Reverse ~= false,
        callback = function(checked) db.Reverse = checked; ApplySettings() end,
    })
    row4e:AddWidget(reverseCheck, 1)
    manager:Register(reverseCheck, "all")
    card4:AddRow(row4e, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Filters
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Filters", yOffset)
    manager:Register(card5, "all")

    -- Human-readable labels per FILTER_KEY
    local FILTER_LABELS = {
        PLAYER                  = "Player-cast",
        RAID                    = "Raid-cast",
        CANCELABLE              = "Cancelable",
        NOT_CANCELABLE          = "Not cancelable",
        INCLUDE_NAME_PLATE_ONLY = "Nameplate-only",
        EXTERNAL_DEFENSIVE      = "External defensive",
        CROWD_CONTROL           = "Crowd control",
        RAID_IN_COMBAT          = "Raid (in combat)",
        RAID_PLAYER_DISPELLABLE = "Player-dispellable",
        BIG_DEFENSIVE           = "Big defensive",
        IMPORTANT               = "Important",
    }

    -- Lay out in pairs (2 columns). The FILTER_KEYS order from the module:
    local FILTER_KEYS = {
        "PLAYER", "RAID",
        "CANCELABLE", "NOT_CANCELABLE",
        "INCLUDE_NAME_PLATE_ONLY", "EXTERNAL_DEFENSIVE",
        "CROWD_CONTROL", "RAID_IN_COMBAT",
        "RAID_PLAYER_DISPELLABLE", "BIG_DEFENSIVE",
        "IMPORTANT",
    }

    local filters = db.Filters or {}
    local numKeys = #FILTER_KEYS
    local i = 1
    while i <= numKeys do
        local keyA = FILTER_KEYS[i]
        local keyB = FILTER_KEYS[i + 1]
        local isLast = (i + 1 > numKeys) or (i + 2 > numKeys and not keyB)
        local rowH = isLast and Theme.rowHeightLast or Theme.rowHeight

        local filterRow = GUIFrame:CreateRow(card5.content, rowH)

        -- Left widget
        local checkA = GUIFrame:CreateCheckbox(filterRow, FILTER_LABELS[keyA] or keyA, {
            value    = filters[keyA] == true,
            callback = function(checked) filters[keyA] = checked; ApplySettings() end,
        })
        filterRow:AddWidget(checkA, 0.5)
        manager:Register(checkA, "all")

        -- Right widget (may be absent for the last odd entry)
        if keyB then
            local checkB = GUIFrame:CreateCheckbox(filterRow, FILTER_LABELS[keyB] or keyB, {
                value    = filters[keyB] == true,
                callback = function(checked) filters[keyB] = checked; ApplySettings() end,
            })
            filterRow:AddWidget(checkB, 0.5)
            manager:Register(checkB, "all")
        end

        local addedH = (i + 1 > numKeys) and Theme.rowHeightLast or Theme.rowHeight
        if keyB and i + 2 > numKeys then addedH = Theme.rowHeightLast end
        card5:AddRow(filterRow, addedH, keyB and (i + 2 > numKeys and 0 or nil) or 0)

        i = i + 2
    end

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Dispel Types
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Dispel Types", yOffset)
    manager:Register(card6, "all")

    -- Default colors per dispel type (for the color picker initial value)
    local DISPEL_DEFAULTS = {
        Magic   = { 0.2,  0.5,  1.0,  1 },
        Curse   = { 0.6,  0.0,  1.0,  1 },
        Disease = { 0.6,  0.4,  0.0,  1 },
        Poison  = { 0.0,  0.7,  0.0,  1 },
        Bleed   = { 0.8,  0.0,  0.1,  1 },
    }
    local DISPEL_TYPES = { "Magic", "Curse", "Disease", "Poison", "Bleed" }

    local dispelTypes  = db.DispelTypes  or {}
    local dispelColors = db.DispelColors or {}

    for idx, dtype in ipairs(DISPEL_TYPES) do
        local isLastType = (idx == #DISPEL_TYPES)
        local rowH = isLastType and Theme.rowHeightLast or Theme.rowHeight

        local dtRow = GUIFrame:CreateRow(card6.content, rowH)

        local dtCheck = GUIFrame:CreateCheckbox(dtRow, dtype, {
            -- nil = enabled (default), false = hidden
            value    = (dispelTypes[dtype] ~= false),
            callback = function(checked)
                -- nil means "show" (default), false means "hide"
                dispelTypes[dtype] = checked and nil or false
                ApplySettings()
            end,
        })
        dtRow:AddWidget(dtCheck, 0.5)
        manager:Register(dtCheck, "all")

        local dtColor = GUIFrame:CreateColorPicker(dtRow, dtype .. " Color", {
            color    = dispelColors[dtype] or DISPEL_DEFAULTS[dtype] or { 1, 1, 1, 1 },
            callback = function(r, g, b, a)
                dispelColors[dtype] = { r, g, b, a }
                ApplySettings()
            end,
        })
        dtRow:AddWidget(dtColor, 0.5)
        manager:Register(dtColor, "all")

        card6:AddRow(dtRow, rowH, isLastType and 0 or nil)
    end

    yOffset = card6:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Border Color
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Border Color", yOffset)
    manager:Register(card7, "all")

    local row7a = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local borderModeDropdown = GUIFrame:CreateDropdown(row7a, "Border Color Mode", {
        options = {
            { key = "dispel", text = "Color by dispel type" },
            { key = "custom", text = "Custom color" },
        },
        value = db.BorderColorMode or "dispel",
        callback = function(key) db.BorderColorMode = key; ApplySettings() end,
    })
    row7a:AddWidget(borderModeDropdown, 1)
    manager:Register(borderModeDropdown, "all")
    card7:AddRow(row7a, Theme.rowHeight)

    local row7b = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
    local borderColorPicker = GUIFrame:CreateColorPicker(row7b, "Custom Border Color", {
        color = db.BorderColor or { 0.8, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row7b:AddWidget(borderColorPicker, 1)
    manager:Register(borderColorPicker, "all")
    card7:AddRow(row7b, Theme.rowHeightLast, 0)

    yOffset = card7:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 8: Spell Blocklist
    -- TODO: A scrollable per-entry list with Remove buttons would be ideal.
    -- For now this card lets users see and manage blocklist entries via a
    -- text summary and a "Restore Defaults" button. Full edit-list UI can
    -- be added in a future pass once a scrollable list widget is available.
    ----------------------------------------------------------------
    local card8 = GUIFrame:CreateCard(scrollChild, "Spell Blocklist", yOffset)
    manager:Register(card8, "all")

    local row8note = GUIFrame:CreateRow(card8.content, 48)
    local noteText = GUIFrame:CreateText(row8note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Blocked spells are filtered from the display.\n" ..
        KE:ColorTextByTheme("-") .. " Use the button below to restore the default block entries.",
        48, "hide")
    row8note:AddWidget(noteText, 1)
    manager:Register(noteText, "all")
    card8:AddRow(row8note, 48)

    -- Show count of currently blocked entries
    local blocklist = db.Blocklist or {}
    local totalEntries = 0
    local enabledEntries = 0
    for _, entry in pairs(blocklist) do
        totalEntries = totalEntries + 1
        if entry.enabled then enabledEntries = enabledEntries + 1 end
    end

    local row8count = GUIFrame:CreateRow(card8.content, Theme.rowHeight)
    local countLabel = GUIFrame:CreateText(row8count,
        KE:ColorTextByTheme("Blocked Spells"),
        enabledEntries .. " active / " .. totalEntries .. " total entries",
        Theme.rowHeight, "hide")
    row8count:AddWidget(countLabel, 1)
    manager:Register(countLabel, "all")
    card8:AddRow(row8count, Theme.rowHeight)

    local row8btn = GUIFrame:CreateRow(card8.content, Theme.rowHeightLast)
    local restoreBtn = GUIFrame:CreateButton(row8btn, "Restore Default Entries", {
        height   = 24,
        callback = function()
            if AD and AD.RestoreBlocklistDefaults then
                AD:RestoreBlocklistDefaults()
                ApplySettings()
                KE:Print("Aura Debuffs: Default blocklist entries restored.")
            end
        end,
    })
    row8btn:AddWidget(restoreBtn, 1)
    manager:Register(restoreBtn, "all")
    card8:AddRow(row8btn, Theme.rowHeightLast, 0)

    yOffset = card8:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 9: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db    = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Label Size", dbKey = "FontSize",      default = 14 },
            { label = "Timer Size", dbKey = "TimerFontSize", default = 16 },
        },
        fontSizeRange      = { 8, 48 },
        includeSoftOutline = true,
        onChangeCallback   = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 10: Timer Position
    ----------------------------------------------------------------
    local card10 = GUIFrame:CreateCard(scrollChild, "Timer Position", yOffset)
    manager:Register(card10, "all")

    local tp = db.TimerPosition or {}

    local row10a = GUIFrame:CreateRow(card10.content, Theme.rowHeight)
    local tpFromDropdown = GUIFrame:CreateDropdown(row10a, "Anchor From", {
        options = {
            { key = "TOPLEFT",     text = "Top Left" },
            { key = "TOP",         text = "Top" },
            { key = "TOPRIGHT",    text = "Top Right" },
            { key = "LEFT",        text = "Left" },
            { key = "CENTER",      text = "Center" },
            { key = "RIGHT",       text = "Right" },
            { key = "BOTTOMLEFT",  text = "Bottom Left" },
            { key = "BOTTOM",      text = "Bottom" },
            { key = "BOTTOMRIGHT", text = "Bottom Right" },
        },
        value = tp.AnchorFrom or "CENTER",
        callback = function(key) db.TimerPosition.AnchorFrom = key; ApplySettings() end,
    })
    row10a:AddWidget(tpFromDropdown, 0.5)
    manager:Register(tpFromDropdown, "all")

    local tpToDropdown = GUIFrame:CreateDropdown(row10a, "Anchor To", {
        options = {
            { key = "TOPLEFT",     text = "Top Left" },
            { key = "TOP",         text = "Top" },
            { key = "TOPRIGHT",    text = "Top Right" },
            { key = "LEFT",        text = "Left" },
            { key = "CENTER",      text = "Center" },
            { key = "RIGHT",       text = "Right" },
            { key = "BOTTOMLEFT",  text = "Bottom Left" },
            { key = "BOTTOM",      text = "Bottom" },
            { key = "BOTTOMRIGHT", text = "Bottom Right" },
        },
        value = tp.AnchorTo or "CENTER",
        callback = function(key) db.TimerPosition.AnchorTo = key; ApplySettings() end,
    })
    row10a:AddWidget(tpToDropdown, 0.5)
    manager:Register(tpToDropdown, "all")
    card10:AddRow(row10a, Theme.rowHeight)

    local row10b = GUIFrame:CreateRow(card10.content, Theme.rowHeightLast)
    local tpXSlider = GUIFrame:CreateSlider(row10b, "X Offset", {
        min = -200, max = 200, step = 1,
        value = tp.XOffset or 0,
        callback = function(val) db.TimerPosition.XOffset = val; ApplySettings() end,
    })
    row10b:AddWidget(tpXSlider, 0.5)
    manager:Register(tpXSlider, "all")

    local tpYSlider = GUIFrame:CreateSlider(row10b, "Y Offset", {
        min = -200, max = 200, step = 1,
        value = tp.YOffset or 0,
        callback = function(val) db.TimerPosition.YOffset = val; ApplySettings() end,
    })
    row10b:AddWidget(tpYSlider, 0.5)
    manager:Register(tpYSlider, "all")
    card10:AddRow(row10b, Theme.rowHeightLast, 0)

    yOffset = card10:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 11: Stack Position
    ----------------------------------------------------------------
    local card11 = GUIFrame:CreateCard(scrollChild, "Stack Count Position", yOffset)
    manager:Register(card11, "all")

    local sp = db.StackPosition or {}

    local row11a = GUIFrame:CreateRow(card11.content, Theme.rowHeight)
    local spFromDropdown = GUIFrame:CreateDropdown(row11a, "Anchor From", {
        options = {
            { key = "TOPLEFT",     text = "Top Left" },
            { key = "TOP",         text = "Top" },
            { key = "TOPRIGHT",    text = "Top Right" },
            { key = "LEFT",        text = "Left" },
            { key = "CENTER",      text = "Center" },
            { key = "RIGHT",       text = "Right" },
            { key = "BOTTOMLEFT",  text = "Bottom Left" },
            { key = "BOTTOM",      text = "Bottom" },
            { key = "BOTTOMRIGHT", text = "Bottom Right" },
        },
        value = sp.AnchorFrom or "BOTTOMRIGHT",
        callback = function(key) db.StackPosition.AnchorFrom = key; ApplySettings() end,
    })
    row11a:AddWidget(spFromDropdown, 0.5)
    manager:Register(spFromDropdown, "all")

    local spToDropdown = GUIFrame:CreateDropdown(row11a, "Anchor To", {
        options = {
            { key = "TOPLEFT",     text = "Top Left" },
            { key = "TOP",         text = "Top" },
            { key = "TOPRIGHT",    text = "Top Right" },
            { key = "LEFT",        text = "Left" },
            { key = "CENTER",      text = "Center" },
            { key = "RIGHT",       text = "Right" },
            { key = "BOTTOMLEFT",  text = "Bottom Left" },
            { key = "BOTTOM",      text = "Bottom" },
            { key = "BOTTOMRIGHT", text = "Bottom Right" },
        },
        value = sp.AnchorTo or "BOTTOMRIGHT",
        callback = function(key) db.StackPosition.AnchorTo = key; ApplySettings() end,
    })
    row11a:AddWidget(spToDropdown, 0.5)
    manager:Register(spToDropdown, "all")
    card11:AddRow(row11a, Theme.rowHeight)

    local row11b = GUIFrame:CreateRow(card11.content, Theme.rowHeightLast)
    local spXSlider = GUIFrame:CreateSlider(row11b, "X Offset", {
        min = -200, max = 200, step = 1,
        value = sp.XOffset or 0,
        callback = function(val) db.StackPosition.XOffset = val; ApplySettings() end,
    })
    row11b:AddWidget(spXSlider, 0.5)
    manager:Register(spXSlider, "all")

    local spYSlider = GUIFrame:CreateSlider(row11b, "Y Offset", {
        min = -200, max = 200, step = 1,
        value = sp.YOffset or 2,
        callback = function(val) db.StackPosition.YOffset = val; ApplySettings() end,
    })
    row11b:AddWidget(spYSlider, 0.5)
    manager:Register(spYSlider, "all")
    card11:AddRow(row11b, Theme.rowHeightLast, 0)

    yOffset = card11:GetNextOffset()

    RefreshStates()
    return yOffset
end)
