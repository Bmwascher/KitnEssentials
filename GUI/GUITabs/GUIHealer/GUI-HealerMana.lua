-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-HealerMana.lua                                      ║
-- ║  GUI: Healer Mana                                        ║
-- ║  Purpose: Configuration panel for the HealerMana module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("HealerMana", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile and KE.db.profile.Dungeons and KE.db.profile.Dungeons.HealerMana
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    local function GetModule()
        if KitnEssentials then
            return KitnEssentials:GetModule("HealerMana", true)
        end
        return nil
    end

    local function ApplySettings()
        local mod = GetModule()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function Refresh()
        local mod = GetModule()
        if mod and mod.Refresh then mod:Refresh() end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Healer Mana Tracker", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if GetModule() then
            if checked then KitnEssentials:EnableModule("HealerMana")
            else KitnEssentials:DisableModule("HealerMana") end
        end
        KE:Print("Healer Mana: " ..
            (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)
    yOffset = card1:GetNextOffset()

    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Position Mode (split toggle + configure-for context)
    ----------------------------------------------------------------
    -- Which context the Position Settings card edits this render. Only "RAID"
    -- when split is on AND the module remembers Raid was selected; otherwise
    -- Dungeon. guiConfigContext is a transient module field (not saved) so it
    -- survives the page rebuild a context switch triggers.
    local activeMod = GetModule()
    local isRaidCtx = db.SplitPositioning and activeMod and activeMod.guiConfigContext == "RAID" or false
    if activeMod then activeMod.previewContext = isRaidCtx and "RAID" or "DUNGEON" end

    -- Per-context Anchored To lives in distinct root DB keys so Dungeon and
    -- Raid can anchor to different frames. Strata stays a shared root key.
    -- Switching context rebuilds the page (same path Anchored To changes use)
    -- so row layout reflows correctly — no in-place resize needed.
    local function RebuildPage()
        if GUIFrame.RefreshContent then
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end
    end

    local cardPosMode = GUIFrame:CreateCard(scrollChild, "Position Mode", yOffset)
    manager:Register(cardPosMode, "all")
    local rowPosMode = GUIFrame:CreateRow(cardPosMode.content, Theme.rowHeightLast)

    local splitToggle = GUIFrame:CreateCheckbox(rowPosMode, "Split Positioning", {
        value = db.SplitPositioning == true,
        callback = function(checked)
            db.SplitPositioning = checked
            local mod = GetModule()
            if mod then
                if not checked then mod.guiConfigContext = "DUNGEON" end
                mod.previewContext = (checked and mod.guiConfigContext == "RAID") and "RAID" or "DUNGEON"
                if mod.isPreview then mod:ShowPreview() end
                if mod.RefreshEditMode then mod:RefreshEditMode() end
            end
            ApplySettings()
            RebuildPage()  -- rebuild so Position Settings reflects split on/off
        end,
    })
    rowPosMode:AddWidget(splitToggle, 0.5)
    -- Split positioning only matters when Raid Mode exists, so it shares the
    -- raidConfig group (greyed unless Enable in Raid is on).
    manager:Register(splitToggle, "raidConfig")

    -- Configure For: chooses which context (Dungeon/Raid) the card below edits.
    -- Rebuilds the page so the card shows that context's anchor/offset values,
    -- and moves the preview to that mode.
    local configureForDropdown = GUIFrame:CreateDropdown(rowPosMode, "Configure For", {
        options = {
            { key = "DUNGEON", text = "Dungeon" },
            { key = "RAID",    text = "Raid" },
        },
        value = isRaidCtx and "RAID" or "DUNGEON",
        callback = function(key)
            local mod = GetModule()
            if mod then
                mod.guiConfigContext = key
                mod.previewContext = key
                if mod.isPreview then mod:ShowPreview() end
                if mod.RefreshEditMode then mod:RefreshEditMode() end
            end
            RebuildPage()
        end,
    })
    rowPosMode:AddWidget(configureForDropdown, 0.5)
    manager:Register(configureForDropdown, "splitConfig")  -- greyed when split off
    cardPosMode:AddRow(rowPosMode, Theme.rowHeight)

    -- Clarify the scope of these controls: they only affect Position Settings,
    -- not Appearance / Raid Mode / Font (those are shared across both modes).
    local posModeNoteRow = GUIFrame:CreateRow(cardPosMode.content, Theme.rowHeightNote)
    local posModeNote = GUIFrame:CreateText(posModeNoteRow,
        KE:ColorTextByTheme("Note"),
        "These controls only affect the Position Settings below. Appearance, " ..
        "Raid Mode, and Font settings are shared between Dungeon and Raid.",
        50, "hide")
    posModeNoteRow:AddWidget(posModeNote, 1)
    cardPosMode:AddRow(posModeNoteRow, Theme.rowHeightNote, 0)
    yOffset = cardPosMode:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Position Settings (context-driven: Dungeon vs Raid keys)
    ----------------------------------------------------------------
    local posTitle = "Position Settings"
    if db.SplitPositioning then
        posTitle = isRaidCtx and "Position Settings — Raid" or "Position Settings — Dungeon"
    end
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = posTitle,
        db = db,
        positionKey = isRaidCtx and "RaidPosition" or "Position",
        dbKeys = {
            -- Anchored To: separate root keys per context. Strata: shared.
            anchorFrameType = isRaidCtx and "RaidAnchorFrameType" or "anchorFrameType",
            anchorFrameFrame = isRaidCtx and "RaidParentFrame" or "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
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

    -- Configure For needs Raid Mode enabled AND split on to be meaningful.
    manager:SetCondition("splitConfig", function()
        return db.EnableInRaid ~= false and db.SplitPositioning == true
    end)

    ----------------------------------------------------------------
    -- Card 4: Raid Mode (enable + stacking)
    ----------------------------------------------------------------
    local cardRaid = GUIFrame:CreateCard(scrollChild, "Raid Mode", yOffset)
    manager:Register(cardRaid, "all")

    local rowRaid1 = GUIFrame:CreateRow(cardRaid.content, Theme.rowHeight)
    local enableRaidCheck = GUIFrame:CreateCheckbox(rowRaid1, "Enable in Raid", {
        value = db.EnableInRaid ~= false,
        callback = function(checked)
            db.EnableInRaid = checked
            local mod = GetModule()
            local wasRaidCtx = mod and mod.guiConfigContext == "RAID"
            if not checked and mod then
                -- Raid Mode off -> no Raid context to edit; fall back to Dungeon.
                mod.guiConfigContext = "DUNGEON"
                mod.previewContext = "DUNGEON"
                if mod.isPreview then mod:ShowPreview() end
                if mod.RefreshEditMode then mod:RefreshEditMode() end
            end
            ApplySettings()
            RefreshStates()  -- grey/ungrey Split Positioning + raid-only settings
            if not checked and wasRaidCtx then RebuildPage() end  -- collapse to Dungeon
        end,
    })
    rowRaid1:AddWidget(enableRaidCheck, 0.5)
    manager:Register(enableRaidCheck, "all")

    local maxHealersSlider = GUIFrame:CreateSlider(rowRaid1, "Max Healers", {
        min = 1, max = 8, step = 1,
        value = db.MaxHealers or 6,
        callback = function(value) db.MaxHealers = value; Refresh() end,
    })
    rowRaid1:AddWidget(maxHealersSlider, 0.5)
    manager:Register(maxHealersSlider, "raidConfig")
    cardRaid:AddRow(rowRaid1, Theme.rowHeight)

    local rowRaid2 = GUIFrame:CreateRow(cardRaid.content, Theme.rowHeightLast)
    local spacingSlider = GUIFrame:CreateSlider(rowRaid2, "Frame Spacing", {
        min = 0, max = 20, step = 1,
        value = db.FrameSpacing or 4,
        callback = function(value) db.FrameSpacing = value; Refresh() end,
    })
    rowRaid2:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "raidConfig")

    local growDropdown = GUIFrame:CreateDropdown(rowRaid2, "Grow Direction", {
        options = {
            { key = "DOWN", text = "Down" },
            { key = "UP",   text = "Up" },
        },
        value = db.GrowDirection or "DOWN",
        callback = function(key) db.GrowDirection = key; Refresh() end,
    })
    rowRaid2:AddWidget(growDropdown, 0.5)
    manager:Register(growDropdown, "raidConfig")
    cardRaid:AddRow(rowRaid2, Theme.rowHeight)

    -- Bench filter: hide healers parked in subgroups 7-8 (the conventional
    -- bench in a 20-player mythic roster). Mirrors the Bench Alert convention.
    local rowRaid3 = GUIFrame:CreateRow(cardRaid.content, Theme.rowHeightLast)
    local excludeBenchCheck = GUIFrame:CreateCheckbox(rowRaid3, "Ignore Bench Healers (Groups 7-8)", {
        value = db.ExcludeBenchGroups ~= false,
        callback = function(checked) db.ExcludeBenchGroups = checked; Refresh() end,
    })
    rowRaid3:AddWidget(excludeBenchCheck, 1)
    manager:Register(excludeBenchCheck, "raidConfig")
    cardRaid:AddRow(rowRaid3, Theme.rowHeightLast, 0)

    -- raidConfig gates Split Positioning + the stacking settings on Enable in
    -- Raid (UpdateAll also gates on the module's master Enabled toggle).
    manager:SetCondition("raidConfig", function() return db.EnableInRaid ~= false end)

    yOffset = cardRaid:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Appearance (icon size, icon type, mana color, hide on healer)
    ----------------------------------------------------------------
    local cardAppearance = GUIFrame:CreateCard(scrollChild, "Appearance", yOffset)
    manager:Register(cardAppearance, "all")

    local rowAppearance1 = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeight)
    local iconSlider = GUIFrame:CreateSlider(rowAppearance1, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = db.IconSize or 24,
        callback = function(value) db.IconSize = value; Refresh() end,
    })
    rowAppearance1:AddWidget(iconSlider, 0.5)
    manager:Register(iconSlider, "all")

    local iconTypeDropdown = GUIFrame:CreateDropdown(rowAppearance1, "Icon Type", {
        options = {
            { key = "spec",  text = "Spec Icon" },
            { key = "class", text = "Class Icon" },
        },
        value = db.IconType or "spec",
        callback = function(key) db.IconType = key; Refresh() end,
    })
    rowAppearance1:AddWidget(iconTypeDropdown, 0.5)
    manager:Register(iconTypeDropdown, "all")
    cardAppearance:AddRow(rowAppearance1, Theme.rowHeight)

    local rowAppearance2 = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeightLast)
    local manaColorPicker = GUIFrame:CreateColorPicker(rowAppearance2, "Mana Text Color", {
        color = db.HighManaColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.HighManaColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowAppearance2:AddWidget(manaColorPicker, 0.5)
    manager:Register(manaColorPicker, "all")

    local disableOnHealerCheck = GUIFrame:CreateCheckbox(rowAppearance2, "Hide when my spec is a healer", {
        value = db.DisableOnHealer == true,
        callback = function(checked) db.DisableOnHealer = checked; Refresh() end,
    })
    rowAppearance2:AddWidget(disableOnHealerCheck, 0.5)
    manager:Register(disableOnHealerCheck, "all")
    cardAppearance:AddRow(rowAppearance2, Theme.rowHeight)

    -- Separator before text-offset settings
    local rowAppSep = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeightSeparator)
    GUIFrame:CreateSeparator(rowAppSep)
    cardAppearance:AddRow(rowAppSep, Theme.rowHeightSeparator)

    local rowNameOffset = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeight)
    local nameXSlider = GUIFrame:CreateSlider(rowNameOffset, "Name X Offset", {
        min = -40, max = 40, step = 1,
        value = db.NameXOffset or 0,
        callback = function(value) db.NameXOffset = value; Refresh() end,
    })
    rowNameOffset:AddWidget(nameXSlider, 0.5)
    manager:Register(nameXSlider, "all")
    local nameYSlider = GUIFrame:CreateSlider(rowNameOffset, "Name Y Offset", {
        min = -40, max = 40, step = 1,
        value = db.NameYOffset or 0,
        callback = function(value) db.NameYOffset = value; Refresh() end,
    })
    rowNameOffset:AddWidget(nameYSlider, 0.5)
    manager:Register(nameYSlider, "all")
    cardAppearance:AddRow(rowNameOffset, Theme.rowHeight)

    local rowManaOffset = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeightLast)
    local manaXSlider = GUIFrame:CreateSlider(rowManaOffset, "Mana X Offset", {
        min = -40, max = 40, step = 1,
        value = db.ManaXOffset or 0,
        callback = function(value) db.ManaXOffset = value; Refresh() end,
    })
    rowManaOffset:AddWidget(manaXSlider, 0.5)
    manager:Register(manaXSlider, "all")
    local manaYSlider = GUIFrame:CreateSlider(rowManaOffset, "Mana Y Offset", {
        min = -40, max = 40, step = 1,
        value = db.ManaYOffset or 0,
        callback = function(value) db.ManaYOffset = value; Refresh() end,
    })
    rowManaOffset:AddWidget(manaYSlider, 0.5)
    manager:Register(manaYSlider, "all")
    cardAppearance:AddRow(rowManaOffset, Theme.rowHeightLast, 0)

    yOffset = cardAppearance:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Font Settings (font face / outline + per-text sizes)
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Name Size", dbKey = "NameFontSize" },
            { label = "Mana Size", dbKey = "ManaFontSize" },
        },
        fontSizeRange = { 8, 44 },
        onChangeCallback = Refresh,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    RefreshStates()
    return yOffset
end)
