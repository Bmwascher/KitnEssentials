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
    -- Card 2: Raid Customization (split toggle + configure-for context)
    ----------------------------------------------------------------
    -- Which context the look/layout controls edit this render. Only "RAID"
    -- when split is on AND the module remembers Raid was selected; otherwise
    -- Dungeon. guiConfigContext is a transient module field (not saved) so it
    -- survives the page rebuild a context switch triggers.
    local activeMod = GetModule()
    local isRaidCtx = db.SplitPositioning and activeMod and activeMod.guiConfigContext == "RAID" or false
    if activeMod then
        local wanted = isRaidCtx and "RAID" or "DUNGEON"
        local changed = activeMod.previewContext ~= wanted
        activeMod.previewContext = wanted
        -- The preview is started per SECTION, before any page in it renders, so
        -- it can be drawn while previewContext is still nil -- and then
        -- GetActiveModeKey falls through to the LIVE mode. In a raid with the
        -- split on, that draws Raid geometry before this page has said which
        -- context it edits. Re-show when this render moves the context, or when
        -- the page is about to edit Raid keys with no preview on screen to
        -- show them.
        if activeMod.ShowPreview
            and (changed or (isRaidCtx and not activeMod.isPreview)) then
            activeMod:ShowPreview()
        end
    end

    -- Which key the look controls WRITE. The switcher decides, not the live
    -- mode: the page must be able to edit Raid settings from a party.
    local lookKey = function(key)
        return (isRaidCtx and ("Raid" .. key)) or key
    end

    -- What the look controls READ. A Raid twin only exists once the split has
    -- been enabled, so an unseeded Raid page must fall back the same way the
    -- module does rather than hand a widget nil -- a slider given nil silently
    -- shows its own floor and commits it on the first drag.
    local lookValue = function(key, fallback)
        local value
        -- Tested against nil, not truthiness: a stored `false` twin is a real
        -- setting and must not fall through to the shared key.
        if isRaidCtx then value = db["Raid" .. key] end
        if value == nil then value = db[key] end
        if value == nil then value = fallback end
        return value
    end

    -- The font card edits four keys; only three of them are twinned.
    local FONT_SPLIT = { FontOutline = true, NameFontSize = true, ManaFontSize = true }

    -- Per-context Anchored To lives in distinct root DB keys so Dungeon and
    -- Raid can anchor to different frames. Strata stays a shared root key.
    -- Switching context rebuilds the page (same path Anchored To changes use)
    -- so row layout reflows correctly — no in-place resize needed.
    local function RebuildPage()
        if GUIFrame.RefreshContent then
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end
    end

    local cardPosMode = GUIFrame:CreateCard(scrollChild, "Raid Customization", yOffset)
    manager:Register(cardPosMode, "all")
    local rowPosMode = GUIFrame:CreateRow(cardPosMode.content, Theme.rowHeightLast)

    local splitToggle = GUIFrame:CreateCheckbox(rowPosMode, "Separate Raid Settings", {
        value = db.SplitPositioning == true,
        callback = function(checked)
            db.SplitPositioning = checked
            local mod = GetModule()
            if mod then
                if checked then mod:SeedRaidLook() end
                if not checked then mod.guiConfigContext = "DUNGEON" end
                mod.previewContext = (checked and mod.guiConfigContext == "RAID") and "RAID" or "DUNGEON"
                -- Unconditional for the same reason as the Configure For
                -- callback: a live party healer clears isPreview, and the
                -- cleared flag makes GetActiveModeKey ignore previewContext.
                -- guiConfigContext survives a profile switch, so turning the
                -- split on can resurrect a RAID context here.
                if mod.ShowPreview then mod:ShowPreview() end
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
                -- Unconditional, NOT gated on isPreview: ShowPreview clears
                -- that flag whenever it finds a live party healer, and a
                -- cleared flag makes GetActiveModeKey ignore previewContext
                -- and answer with the live mode. The page would then edit
                -- Raid keys while the frame kept rendering Dungeon ones.
                if mod.ShowPreview then mod:ShowPreview() end
                if mod.RefreshEditMode then mod:RefreshEditMode() end
            end
            RebuildPage()
        end,
    })
    rowPosMode:AddWidget(configureForDropdown, 0.5)
    manager:Register(configureForDropdown, "splitConfig")  -- greyed when split off
    cardPosMode:AddRow(rowPosMode, Theme.rowHeight)

    -- Clarify the scope: the switcher reaches Position, Appearance and Font.
    -- Max Healers, Ignore Bench Healers and Enable in Raid stay shared.
    local posModeNoteRow = GUIFrame:CreateRow(cardPosMode.content, Theme.rowHeightNote)
    local posModeNote = GUIFrame:CreateText(posModeNoteRow,
        KE:ColorTextByTheme("Note"),
        "Turning this on also gives Raid its own sizes, fonts, and colors, " ..
        "separate from Dungeon. \"Configure For\" chooses which set the " ..
        "controls below edit.",
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
            if not checked and mod then
                -- Raid Mode off -> no Raid context to edit; fall back to Dungeon.
                mod.guiConfigContext = "DUNGEON"
                mod.previewContext = "DUNGEON"
                if mod.RefreshEditMode then mod:RefreshEditMode() end
            end
            -- Unconditional, and on BOTH edges. This flag is half the mode
            -- predicate, so ticking it ON in a raid group flips the held mode
            -- and moves the frame to the Raid anchor and sizes while the page
            -- goes on editing the plain keys.
            if mod and mod.ShowPreview then mod:ShowPreview() end
            ApplySettings()
            RefreshStates()  -- grey/ungrey Split Positioning + raid-only settings
            RebuildPage()  -- the page's context and control set both move
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
        value = lookValue("FrameSpacing", 4),
        callback = function(value) db[lookKey("FrameSpacing")] = value; Refresh() end,
    })
    rowRaid2:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "raidConfig")

    local growDropdown = GUIFrame:CreateDropdown(rowRaid2, "Grow Direction", {
        options = {
            { key = "DOWN", text = "Down" },
            { key = "UP",   text = "Up" },
        },
        value = lookValue("GrowDirection", "DOWN"),
        callback = function(key) db[lookKey("GrowDirection")] = key; Refresh() end,
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
        value = lookValue("IconSize", 24),
        callback = function(value) db[lookKey("IconSize")] = value; Refresh() end,
    })
    rowAppearance1:AddWidget(iconSlider, 0.5)
    manager:Register(iconSlider, "all")

    local iconTypeDropdown = GUIFrame:CreateDropdown(rowAppearance1, "Icon Type", {
        options = {
            { key = "spec",  text = "Spec Icon" },
            { key = "class", text = "Class Icon" },
        },
        value = lookValue("IconType", "spec"),
        callback = function(key) db[lookKey("IconType")] = key; Refresh() end,
    })
    rowAppearance1:AddWidget(iconTypeDropdown, 0.5)
    manager:Register(iconTypeDropdown, "all")
    cardAppearance:AddRow(rowAppearance1, Theme.rowHeight)

    local rowAppearance2 = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeightLast)
    local manaColorPicker = GUIFrame:CreateColorPicker(rowAppearance2, "Mana Text Color", {
        color = lookValue("HighManaColor", { 1, 1, 1, 1 }),
        callback = function(r, g, b, a)
            db[lookKey("HighManaColor")] = { r, g, b, a }
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
        value = lookValue("NameXOffset", 0),
        callback = function(value) db[lookKey("NameXOffset")] = value; Refresh() end,
    })
    rowNameOffset:AddWidget(nameXSlider, 0.5)
    manager:Register(nameXSlider, "all")
    local nameYSlider = GUIFrame:CreateSlider(rowNameOffset, "Name Y Offset", {
        min = -40, max = 40, step = 1,
        value = lookValue("NameYOffset", 0),
        callback = function(value) db[lookKey("NameYOffset")] = value; Refresh() end,
    })
    rowNameOffset:AddWidget(nameYSlider, 0.5)
    manager:Register(nameYSlider, "all")
    cardAppearance:AddRow(rowNameOffset, Theme.rowHeight)

    local rowManaOffset = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeightLast)
    local manaXSlider = GUIFrame:CreateSlider(rowManaOffset, "Mana X Offset", {
        min = -40, max = 40, step = 1,
        value = lookValue("ManaXOffset", 0),
        callback = function(value) db[lookKey("ManaXOffset")] = value; Refresh() end,
    })
    rowManaOffset:AddWidget(manaXSlider, 0.5)
    manager:Register(manaXSlider, "all")
    local manaYSlider = GUIFrame:CreateSlider(rowManaOffset, "Mana Y Offset", {
        min = -40, max = 40, step = 1,
        value = lookValue("ManaYOffset", 0),
        callback = function(value) db[lookKey("ManaYOffset")] = value; Refresh() end,
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
        getValue = function(key, default)
            if FONT_SPLIT[key] then return lookValue(key, default) end
            local value = db[key]
            if value == nil then return default end
            return value
        end,
        setValue = function(key, val)
            db[FONT_SPLIT[key] and lookKey(key) or key] = val
        end,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    RefreshStates()
    return yOffset
end)
