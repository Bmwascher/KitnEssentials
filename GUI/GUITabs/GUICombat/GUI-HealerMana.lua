-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-HealerMana.lua                                      ║
-- ║  GUI: Healer Mana                                        ║
-- ║  Purpose: Configuration panel for the HealerMana module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetDB()
    return KE.db and KE.db.profile and KE.db.profile.Dungeons and KE.db.profile.Dungeons.HealerMana
end

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

-- Rebuild the page (same path Anchored To changes use) so row layout reflows.
local function RebuildPage()
    if GUIFrame.RefreshContent then
        C_Timer.After(0, function() GUIFrame:RefreshContent() end)
    end
end

-- Point the preview and the Edit Mode overlay at the context this tab edits.
-- The preview is started per SECTION, before any page in it renders, so it
-- can be drawn while previewContext is still nil -- and then GetActiveModeKey
-- falls through to the LIVE mode. Re-show when this render moves the context,
-- or when the tab is about to edit Raid keys with no preview on screen to
-- show them: ShowPreview clears isPreview whenever it finds a live party
-- healer, and a cleared flag makes GetActiveModeKey ignore previewContext.
-- No overlay label call here: the re-show always ends in UpdateHealerFrames,
-- which records what it drew and resyncs the label from that.
local function SyncContext(isRaidCtx)
    local mod = GetModule()
    if not mod then return end
    local wanted = isRaidCtx and "RAID" or "DUNGEON"
    local changed = mod.previewContext ~= wanted
    mod.previewContext = wanted
    if mod.ShowPreview and (changed or (isRaidCtx and not mod.isPreview)) then
        mod:ShowPreview()
    end
end

-- Which key a look control WRITES, and what it READS. A Raid twin only exists
-- once the split has been enabled, so an unseeded Raid tab must fall back the
-- same way the module does rather than hand a widget nil -- a slider given
-- nil silently shows its own floor and commits it on the first drag.
local function LookAccessors(db, isRaidCtx)
    local function lookKey(key)
        return (isRaidCtx and ("Raid" .. key)) or key
    end
    local function lookValue(key, fallback)
        local value
        -- Tested against nil, not truthiness: a stored `false` twin is a real
        -- setting and must not fall through to the shared key.
        if isRaidCtx then value = db["Raid" .. key] end
        if value == nil then value = db[key] end
        if value == nil then value = fallback end
        return value
    end
    return lookKey, lookValue
end

-- Position, Appearance and Font for one context. Every widget joins `group`.
local function BuildContextCards(scrollChild, yOffset, db, manager, isRaidCtx, group)
    local lookKey, lookValue = LookAccessors(db, isRaidCtx)

    ----------------------------------------------------------------
    -- Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
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
        manager:RegisterGroup(posCard.positionWidgets, group)
    end
    manager:Register(posCard, group)
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Appearance
    ----------------------------------------------------------------
    local cardAppearance = GUIFrame:CreateCard(scrollChild, "Appearance", yOffset)
    manager:Register(cardAppearance, group)

    local rowAppearance1 = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeight)
    local iconSlider = GUIFrame:CreateSlider(rowAppearance1, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = lookValue("IconSize", 24),
        callback = function(value) db[lookKey("IconSize")] = value; Refresh() end,
    })
    rowAppearance1:AddWidget(iconSlider, 0.5)
    manager:Register(iconSlider, group)

    local iconTypeDropdown = GUIFrame:CreateDropdown(rowAppearance1, "Icon Type", {
        options = {
            { key = "spec",  text = "Spec Icon" },
            { key = "class", text = "Class Icon" },
        },
        value = lookValue("IconType", "spec"),
        callback = function(key) db[lookKey("IconType")] = key; Refresh() end,
    })
    rowAppearance1:AddWidget(iconTypeDropdown, 0.5)
    manager:Register(iconTypeDropdown, group)
    cardAppearance:AddRow(rowAppearance1, Theme.rowHeight)

    local rowAppearance2 = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeight)
    local manaColorPicker = GUIFrame:CreateColorPicker(rowAppearance2, "Mana Text Color", {
        color = lookValue("HighManaColor", { 1, 1, 1, 1 }),
        callback = function(r, g, b, a)
            db[lookKey("HighManaColor")] = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowAppearance2:AddWidget(manaColorPicker, 0.5)
    manager:Register(manaColorPicker, group)
    cardAppearance:AddRow(rowAppearance2, Theme.rowHeight)

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
    manager:Register(nameXSlider, group)
    local nameYSlider = GUIFrame:CreateSlider(rowNameOffset, "Name Y Offset", {
        min = -40, max = 40, step = 1,
        value = lookValue("NameYOffset", 0),
        callback = function(value) db[lookKey("NameYOffset")] = value; Refresh() end,
    })
    rowNameOffset:AddWidget(nameYSlider, 0.5)
    manager:Register(nameYSlider, group)
    cardAppearance:AddRow(rowNameOffset, Theme.rowHeight)

    local rowManaOffset = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeightLast)
    local manaXSlider = GUIFrame:CreateSlider(rowManaOffset, "Mana X Offset", {
        min = -40, max = 40, step = 1,
        value = lookValue("ManaXOffset", 0),
        callback = function(value) db[lookKey("ManaXOffset")] = value; Refresh() end,
    })
    rowManaOffset:AddWidget(manaXSlider, 0.5)
    manager:Register(manaXSlider, group)
    local manaYSlider = GUIFrame:CreateSlider(rowManaOffset, "Mana Y Offset", {
        min = -40, max = 40, step = 1,
        value = lookValue("ManaYOffset", 0),
        callback = function(value) db[lookKey("ManaYOffset")] = value; Refresh() end,
    })
    rowManaOffset:AddWidget(manaYSlider, 0.5)
    manager:Register(manaYSlider, group)
    cardAppearance:AddRow(rowManaOffset, Theme.rowHeightLast, 0)

    yOffset = cardAppearance:GetNextOffset()

    ----------------------------------------------------------------
    -- Font Settings (all four keys are twinned)
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
        -- Follow Global stores nil, and nil is exactly what HM:Look treats as
        -- "this mode follows Dungeon". Storing it on the Raid twin would make
        -- Raid inherit Party's face instead of the global font, with no way
        -- back once Party has one. Raid stores false for that choice: false is
        -- a value Look returns rather than falls through, and GetFontPath
        -- resolves it to the global font.
        getValue = function(key, default)
            local value = lookValue(key, default)
            if isRaidCtx and key == "FontFace" and value == false then
                return KE.FONT_FOLLOW_GLOBAL
            end
            return value
        end,
        setValue = function(key, val)
            if isRaidCtx and key == "FontFace" and val == nil then val = false end
            db[lookKey(key)] = val
        end,
    })
    manager:Register(fontCard, group)
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, group)
    end
    return fontOffset
end

----------------------------------------------------------------
-- Party tab
----------------------------------------------------------------
GUIFrame:RegisterContent("HealerManaParty", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end
    local manager = GUIFrame:CreateWidgetStateManager()
    SyncContext(false)

    local card = GUIFrame:CreateCard(scrollChild, "Party Mode", yOffset)
    manager:Register(card, "all")
    local row = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local hideOnHealerCheck = GUIFrame:CreateCheckbox(row, "Hide when my spec is a healer", {
        value = db.DisableOnHealer == true,
        callback = function(checked) db.DisableOnHealer = checked; Refresh() end,
    })
    row:AddWidget(hideOnHealerCheck, 1)
    manager:Register(hideOnHealerCheck, "all")
    card:AddRow(row, Theme.rowHeightLast, 0)
    yOffset = card:GetNextOffset()

    yOffset = BuildContextCards(scrollChild, yOffset, db, manager, false, "all")

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)

----------------------------------------------------------------
-- Raid tab
----------------------------------------------------------------
GUIFrame:RegisterContent("HealerManaRaid", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end
    local manager = GUIFrame:CreateWidgetStateManager()

    -- With the split on this tab edits the Raid twins. The preview follows
    -- only while Raid Mode can actually run; otherwise it keeps showing Party.
    local editsRaid = db.SplitPositioning == true
    SyncContext(editsRaid and db.EnableInRaid ~= false)
    local lookKey, lookValue = LookAccessors(db, editsRaid)

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    local card = GUIFrame:CreateCard(scrollChild, "Raid Mode", yOffset)
    manager:Register(card, "all")

    local rowRaid1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local enableRaidCheck = GUIFrame:CreateCheckbox(rowRaid1, "Enable in Raid", {
        value = db.EnableInRaid ~= false,
        callback = function(checked)
            db.EnableInRaid = checked
            -- Unconditional, and on BOTH edges. This flag is half the mode
            -- predicate, so ticking it ON in a raid group flips the held mode
            -- and moves the frame to the Raid anchor and sizes.
            local mod = GetModule()
            if mod and mod.ShowPreview then mod:ShowPreview() end
            ApplySettings()
            RefreshStates()
            RebuildPage()  -- the preview context and the greyed set both move
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
    card:AddRow(rowRaid1, Theme.rowHeight)

    local rowRaid2 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
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
    card:AddRow(rowRaid2, Theme.rowHeight)

    -- Bench filter: hide healers parked in subgroups 7-8 (the conventional
    -- bench in a 20-player mythic roster). Mirrors the Bench Alert convention.
    local rowRaid3 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local excludeBenchCheck = GUIFrame:CreateCheckbox(rowRaid3, "Ignore Bench Healers (Groups 7-8)", {
        value = db.ExcludeBenchGroups ~= false,
        callback = function(checked) db.ExcludeBenchGroups = checked; Refresh() end,
    })
    rowRaid3:AddWidget(excludeBenchCheck, 0.5)
    manager:Register(excludeBenchCheck, "raidConfig")

    -- Same label as Party's DisableOnHealer: both mean "do not show me". Party
    -- tracks one healer, so hiding the player's row empties the tracker; Raid
    -- has other rows to keep.
    local excludeSelfCheck = GUIFrame:CreateCheckbox(rowRaid3, "Hide when my spec is a healer", {
        value = db.ExcludeSelfHealer == true,
        callback = function(checked) db.ExcludeSelfHealer = checked; Refresh() end,
    })
    rowRaid3:AddWidget(excludeSelfCheck, 0.5)
    manager:Register(excludeSelfCheck, "raidConfig")
    card:AddRow(rowRaid3, Theme.rowHeight)

    card:AddSeparator()

    local rowRaid5 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local splitToggle = GUIFrame:CreateCheckbox(rowRaid5, "Separate Raid Settings", {
        value = editsRaid,
        callback = function(checked)
            db.SplitPositioning = checked
            local mod = GetModule()
            if checked and mod and mod.SeedRaidLook then mod:SeedRaidLook() end
            ApplySettings()
            RebuildPage()  -- the rebuilt tab moves the preview and adds or drops the cards
        end,
    })
    rowRaid5:AddWidget(splitToggle, 0.5)
    manager:Register(splitToggle, "raidConfig")

    local splitNote = GUIFrame:CreateText(rowRaid5,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " " .. (editsRaid
            and "Raid keeps its own position, appearance and font."
            or "Raid follows the Party tab. Turn on for its own position, appearance and font."),
        Theme.rowHeight, "hide", true)
    rowRaid5:AddWidget(splitNote, 0.5)
    card:AddRow(rowRaid5, Theme.rowHeight, 0)

    -- raidConfig gates everything but Enable in Raid on that flag (UpdateAll
    -- also gates on the module's master Enabled toggle).
    manager:SetCondition("raidConfig", function() return db.EnableInRaid ~= false end)
    yOffset = card:GetNextOffset()

    if editsRaid then
        yOffset = BuildContextCards(scrollChild, yOffset, db, manager, true, "raidConfig")
    end

    RefreshStates()
    return yOffset
end)

----------------------------------------------------------------
-- Host: header toggle above a Party | Raid strip
----------------------------------------------------------------
GUIFrame:RegisterTabbedContent("HealerMana", {
    { id = "HealerManaParty", label = "Party" },
    { id = "HealerManaRaid",  label = "Raid" },
}, {
    headerBuilder = function(scrollChild, yOffset)
        local db = GetDB()
        if not db then
            local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
            errorCard:AddLabel("Database not available")
            return errorCard:GetNextOffset(), true
        end

        local card = GUIFrame:CreateCard(scrollChild, "Healer Mana Tracker", yOffset)
        card:AddHeaderToggle(db.Enabled == true, function(checked)
            db.Enabled = checked
            if GetModule() then
                if checked then KitnEssentials:EnableModule("HealerMana")
                else KitnEssentials:DisableModule("HealerMana") end
            end
            KE:Print("Healer Mana: " ..
                (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
        end)
        -- collapse = true suppresses the tab strip and all tab content.
        return card:GetNextOffset(), db.Enabled ~= true
    end,
})
