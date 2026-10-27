-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KickTracker.lua                                     ║
-- ║  GUI: Interrupt Tracker                                  ║
-- ║  Purpose: Configuration panel for the KickTracker module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local pairs = pairs

GUIFrame:RegisterContent("KickTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.KickTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local KT = KitnEssentials and KitnEssentials:GetModule("KickTracker", true)

    local manager = GUIFrame:CreateWidgetStateManager()
    -- "all" is the bar cards' group: grayed while Show Bars is off.
    manager:SetCondition("all", function()
        return db.ShowBars ~= false
    end)
    local platesHeld = KT and KT.PlateIconsHeld
    manager:SetCondition("plates", function()
        return db.PlateIcons ~= false and not platesHeld
    end)
    manager:SetCondition("platesSwitch", function()
        return not platesHeld
    end)
    local premarkHeld = KT and KT.PremarkHeld
    manager:SetCondition("premark", function()
        return db.PlateIcons ~= false and not platesHeld and not premarkHeld
    end)
    manager:SetCondition("plateTimer", function()
        return db.PlateIcons ~= false and not platesHeld and db.PlateShowTimer ~= false
    end)
    -- "classOnly": widgets only meaningful when ColorMode is "class"
    manager:SetCondition("classOnly", function()
        return db.ShowBars ~= false and db.ColorMode ~= "dark"
    end)
    -- "cooling": cooling color picker requires class mode AND ClassColorCooling off
    manager:SetCondition("cooling", function()
        return db.ShowBars ~= false and db.ColorMode ~= "dark" and not db.ClassColorCooling
    end)

    local function ApplySettings()
        if KT and KT.ApplySettings then KT:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("KickTracker", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("KickTracker")
        else
            KitnEssentials:DisableModule("KickTracker")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    -- Build LSM lists
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local statusbarList = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do statusbarList[name] = name end
    else
        statusbarList["Blizzard"] = "Blizzard"
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Interrupt Tracker", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)

    card1:AddLabel("Tracks your party's interrupts as cooldown bars, one per teammate with a kick, and " ..
        "as icons on enemy nameplates. Only active in 5-player dungeons.\n\n" ..
        "A kick goes on the kicker's bar, and the bar reads " .. KE:ColorTextByTheme("Ready") ..
        " when the tracker's timing says the kick is back. The kicker's icon goes on the nameplate of " ..
        "the mob they stopped; yours goes on your target's nameplate as you cast." ..
        (premarkHeld and "" or " Before a key starts, the focus markers teammates announce are read, " ..
        "so their icon can wait on their marked mob.") .. "\n\n" ..
        "In a dungeon the game often hides who kicked. The Damage Meter then names the kicker when it " ..
        "can. When it cannot, each teammate who could have kicked gets a copy of their bar on cooldown, " ..
        "and the mob a hidden icon of theirs, that the game shows only for the teammate who really kicked.")

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return card1:GetNextOffset() end

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local showBarsCheck = GUIFrame:CreateCheckbox(row1a, "Show Bars", {
        value = db.ShowBars ~= false,
        tooltip = "The cooldown bars, and their box in Edit Mode. With this off the nameplate icons still show.",
        callback = function(checked) db.ShowBars = checked; ApplySettings(); RefreshStates() end,
    })
    row1a:AddWidget(showBarsCheck, 0.5)
    manager:Register(showBarsCheck, "module")

    local plateIconsCheck = GUIFrame:CreateCheckbox(row1a, "Nameplate Icons", {
        value = db.PlateIcons ~= false and not platesHeld,
        tooltip = "Each kicker's icon, with their kick's cooldown, on the nameplate of the mob they stopped.",
        callback = function(checked) db.PlateIcons = checked; ApplySettings(); RefreshStates() end,
    })
    row1a:AddWidget(plateIconsCheck, 0.5)
    manager:Register(plateIconsCheck, platesHeld and "platesSwitch" or "module")
    card1:AddRow(row1a, Theme.rowHeight)
    if platesHeld then
        card1:AddLabel("Nameplate Icons is off in this version while a game freeze it can trigger is " ..
            "fixed. Your setting is kept for when it returns; the bars work as before.")
    end

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 1b: Nameplate Icons
    ----------------------------------------------------------------
    local cardPlates = GUIFrame:CreateCard(scrollChild, "Nameplate Icons", yOffset)
    manager:Register(cardPlates, "plates")

    local function PlateSwitch(row, key, label, tooltip, refresh)
        local switch = GUIFrame:CreateCheckbox(row, label, {
            value = db[key] ~= false,
            tooltip = tooltip,
            callback = function(checked)
                db[key] = checked
                ApplySettings()
                if refresh then RefreshStates() end
            end,
        })
        row:AddWidget(switch, 0.5)
        manager:Register(switch, "plates")
    end

    if premarkHeld then
        cardPlates:AddLabel("Icons on Marked Mobs is off in this version while a game freeze it can " ..
            "trigger is fixed. Your setting is kept for when it returns.")
    end
    local rowB = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    local premarkSwitch = GUIFrame:CreateCheckbox(rowB, "Icons on Marked Mobs", {
        value = db.PlatePremark ~= false and not premarkHeld,
        tooltip = "Before any kick, a teammate's icon sits on the mob carrying the focus marker " ..
            "they announced, until their own icon is on a nameplate.",
        callback = function(checked) db.PlatePremark = checked; ApplySettings() end,
    })
    rowB:AddWidget(premarkSwitch, 0.5)
    manager:Register(premarkSwitch, "premark")
    PlateSwitch(rowB, "PlateAboveOverlap", "Show Above Overlapping Nameplates",
        "The icons draw over every other nameplate, so an overlapping plate never hides " ..
        "one. When off, an icon stays inside its own nameplate, behind any plate that covers it.")
    cardPlates:AddRow(rowB, Theme.rowHeight)
    cardPlates:AddSeparator()

    local rowP1 = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    local plateStyleDropdown = GUIFrame:CreateDropdown(rowP1, "Icon", {
        options = {
            { key = "kick",  text = "Kick Spell" },
            { key = "spec",  text = "Spec" },
            { key = "class", text = "Class" },
        },
        value = db.PlateIconStyle or "kick",
        callback = function(key) db.PlateIconStyle = key; ApplySettings() end,
    })
    rowP1:AddWidget(plateStyleDropdown, 0.5)
    manager:Register(plateStyleDropdown, "plates")

    local plateSizeSlider = GUIFrame:CreateSlider(rowP1, "Icon Size", {
        min = 16, max = 48, step = 1,
        value = db.PlateIconSize or 30,
        callback = function(val) db.PlateIconSize = val; ApplySettings() end,
    })
    rowP1:AddWidget(plateSizeSlider, 0.5)
    manager:Register(plateSizeSlider, "plates")
    cardPlates:AddRow(rowP1, Theme.rowHeight)

    local rowL = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    PlateSwitch(rowL, "PlateClassBorder", "Class Color Border")
    PlateSwitch(rowL, "PlateSwipe", "Show Cooldown Swipe")
    cardPlates:AddRow(rowL, Theme.rowHeight)
    cardPlates:AddSeparator()

    local rowP2 = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    local plateSideDropdown = GUIFrame:CreateDropdown(rowP2, "Side", {
        options = {
            { key = "LEFT",   text = "Left" },
            { key = "RIGHT",  text = "Right" },
            { key = "TOP",    text = "Top" },
            { key = "BOTTOM", text = "Bottom" },
        },
        value = db.PlateSide or "LEFT",
        callback = function(key) db.PlateSide = key; ApplySettings() end,
    })
    rowP2:AddWidget(plateSideDropdown, 0.5)
    manager:Register(plateSideDropdown, "plates")

    local plateGapSlider = GUIFrame:CreateSlider(rowP2, "Gap to Health Bar", {
        min = 0, max = 20, step = 1,
        value = db.PlateBarGap or 4,
        callback = function(val) db.PlateBarGap = val; ApplySettings() end,
    })
    rowP2:AddWidget(plateGapSlider, 0.5)
    manager:Register(plateGapSlider, "plates")
    cardPlates:AddRow(rowP2, Theme.rowHeight)

    local rowP3 = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    local plateSpacingSlider = GUIFrame:CreateSlider(rowP3, "Icon Spacing", {
        min = 0, max = 10, step = 1,
        value = db.PlateSpacing or 1,
        callback = function(val) db.PlateSpacing = val; ApplySettings() end,
    })
    rowP3:AddWidget(plateSpacingSlider, 0.5)
    manager:Register(plateSpacingSlider, "plates")
    cardPlates:AddRow(rowP3, Theme.rowHeight)

    local rowP4 = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    local plateXSlider = GUIFrame:CreateSlider(rowP4, "X Offset", {
        min = -100, max = 100, step = 1,
        value = db.PlateOffsetX or 0,
        callback = function(val) db.PlateOffsetX = val; ApplySettings() end,
    })
    rowP4:AddWidget(plateXSlider, 0.5)
    manager:Register(plateXSlider, "plates")

    local plateYSlider = GUIFrame:CreateSlider(rowP4, "Y Offset", {
        min = -100, max = 100, step = 1,
        value = db.PlateOffsetY or 0,
        callback = function(val) db.PlateOffsetY = val; ApplySettings() end,
    })
    rowP4:AddWidget(plateYSlider, 0.5)
    manager:Register(plateYSlider, "plates")
    cardPlates:AddRow(rowP4, Theme.rowHeight)
    cardPlates:AddSeparator()

    local rowT = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    PlateSwitch(rowT, "PlateShowTimer", "Show Timer", nil, true)
    local plateTimerSlider = GUIFrame:CreateSlider(rowT, "Timer Size", {
        min = 6, max = 24, step = 1,
        value = db.PlateTimerSize or 13,
        callback = function(val) db.PlateTimerSize = val; ApplySettings() end,
    })
    rowT:AddWidget(plateTimerSlider, 0.5)
    manager:Register(plateTimerSlider, "plateTimer")
    cardPlates:AddRow(rowT, Theme.rowHeight)

    local rowPF = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    local plateFontDropdown = GUIFrame:CreateDropdown(rowPF, "Font", {
        options = KE:AddFollowGlobalFont(fontList),
        value = db.PlateFontFace or KE.FONT_FOLLOW_GLOBAL,
        callback = function(key) db.PlateFontFace = KE:StoredFontFace(key); ApplySettings() end,
        searchable = true,
        isFontPreview = true,
    })
    rowPF:AddWidget(plateFontDropdown, 0.5)
    manager:Register(plateFontDropdown, "plateTimer")

    local plateOutlineDropdown = GUIFrame:CreateDropdown(rowPF, "Font Outline", {
        options = KE:GetFontOutlineOptions(),
        value = KE:NormalizeFontOutline(db.PlateFontOutline or "OUTLINE"),
        callback = function(key) db.PlateFontOutline = key; ApplySettings() end,
    })
    rowPF:AddWidget(plateOutlineDropdown, 0.5)
    manager:Register(plateOutlineDropdown, "plateTimer")
    cardPlates:AddRow(rowPF, Theme.rowHeight)

    -- EllesmereUI's own test for its kick plate icons; the handle is nil while that addon is not loaded.
    local eui = _G._EMT_AceDB
    local euiKT = eui and eui.profile and eui.profile.kickTracker
    if type(euiKT) == "table" and euiKT.enabled == true and euiKT.showPlates ~= false then
        cardPlates:AddNote(KE:Gold("EllesmereUI") .. "'s Kick Tracker is showing its own nameplate icons too. " ..
            "With both on, two rows sit beside the same health bar: turn one off, or move these with the offsets.")
    end

    yOffset = cardPlates:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position, one view per position
    ----------------------------------------------------------------
    -- guiConfigContext is a transient module field (not saved) so the view
    -- survives the page rebuild a switch triggers. First open after /reload:
    -- start on the position the player's spec uses, so the page matches the
    -- spec-driven preview.
    if KT and KT.guiConfigContext == nil then
        KT.guiConfigContext = (db.UseHealerPosition and KE.IsPlayerHealerSpec and KE:IsPlayerHealerSpec())
            and "HEALER" or "DEFAULT"
    end
    local isHealerView = KT and KT.guiConfigContext == "HEALER" or false
    if KT then KT.previewContext = (db.UseHealerPosition and isHealerView) and "HEALER" or "DEFAULT" end

    local function RebuildPage()
        if GUIFrame.RefreshContent then
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end
    end

    -- A switch moves the preview and the Edit Mode overlay to that view's
    -- position while it applies; the strip rebuilds the page itself.
    local _, viewOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = GUIFrame.HEALER_VIEW_TABS,
        activeId = isHealerView and "HEALER" or "DEFAULT",
        onSwitch = function(key)
            if not KT then return end
            KT.guiConfigContext = key
            KT.previewContext = key
            if KT.isPreview then KT:ShowPreview() end
            if KT.RefreshEditMode then KT:RefreshEditMode() end
        end,
        fill = true,
    })
    yOffset = viewOffset

    manager:SetCondition("healerConfig", function()
        return db.ShowBars ~= false and db.UseHealerPosition == true
    end)

    if isHealerView then
        local cardHealer = GUIFrame:CreateCard(scrollChild, "Healer Position", yOffset)
        manager:Register(cardHealer, "all")
        local rowHealer = GUIFrame:CreateRow(cardHealer.content, Theme.rowHeightLast)
        -- The checkbox sits in the Healer view, so either answer moves the
        -- preview and the Edit Mode overlay to what this view now shows.
        local healerToggle = GUIFrame:CreateCheckbox(rowHealer, "Use Healer Position", {
            value = db.UseHealerPosition == true,
            callback = function(checked)
                db.UseHealerPosition = checked
                if KT then
                    KT.previewContext = checked and "HEALER" or "DEFAULT"
                    if KT.isPreview then KT:ShowPreview() end
                    if KT.RefreshEditMode then KT:RefreshEditMode() end
                end
                ApplySettings()
                RebuildPage()
            end,
        })
        rowHealer:AddWidget(healerToggle, 0.5)
        manager:Register(healerToggle, "all")
        local healerNote = GUIFrame:CreateText(rowHealer,
            KE:ColorTextByTheme("Note"),
            "Used while you are in a healer spec.",
            Theme.rowHeight, "hide")
        rowHealer:AddWidget(healerNote, 0.5)
        cardHealer:AddRow(rowHealer, Theme.rowHeightLast, 0)
        yOffset = cardHealer:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 3: Position Settings (the view's keys: Default vs Healer)
    ----------------------------------------------------------------
    -- Grayed in the Healer view while Use Healer Position is off.
    local posGroup = isHealerView and "healerConfig" or "all"
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        positionKey = isHealerView and "HealerPosition" or "Position",
        dbKeys = {
            -- Anchored To + Strata split per context (KickTracker has Healer*
            -- root keys). Anchor From sets horizontal alignment; its vertical
            -- component is overridden by GrowthDirection so the bar stack and
            -- edit-mode overlay stay aligned on a growth flip.
            anchorFrameType = isHealerView and "HealerAnchorFrameType" or "anchorFrameType",
            anchorFrameFrame = isHealerView and "HealerParentFrame" or "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = isHealerView and "HealerStrata" or "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, posGroup)
    end
    manager:Register(posCard, posGroup)
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Frame Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Frame Settings", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local widthSlider = GUIFrame:CreateSlider(row3a, "Bar Width", {
        min = 80, max = 400, step = 1,
        value = db.BarWidth or 180,
        callback = function(val) db.BarWidth = val; ApplySettings() end,
    })
    row3a:AddWidget(widthSlider, 0.5)
    manager:Register(widthSlider, "all")

    local heightSlider = GUIFrame:CreateSlider(row3a, "Bar Height", {
        min = 12, max = 40, step = 1,
        value = db.BarHeight or 20,
        callback = function(val) db.BarHeight = val; ApplySettings() end,
    })
    row3a:AddWidget(heightSlider, 0.5)
    manager:Register(heightSlider, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local spacingSlider = GUIFrame:CreateSlider(row3b, "Bar Spacing", {
        min = 0, max = 10, step = 1,
        value = db.BarSpacing or 2,
        callback = function(val) db.BarSpacing = val; ApplySettings() end,
    })
    row3b:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card3:AddRow(row3b, Theme.rowHeight)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local growDropdown = GUIFrame:CreateDropdown(row3c, "Growth Direction", {
        options = {
            { key = "DOWN", text = "Down" },
            { key = "UP",   text = "Up" },
        },
        value = db.GrowthDirection or "DOWN",
        callback = function(key) db.GrowthDirection = key; ApplySettings() end,
    })
    row3c:AddWidget(growDropdown, 0.5)
    manager:Register(growDropdown, "all")

    local sideDropdown = GUIFrame:CreateDropdown(row3c, "Icon Side", {
        options = {
            { key = "LEFT",  text = "Left" },
            { key = "RIGHT", text = "Right" },
        },
        value = db.IconSide or "LEFT",
        callback = function(key) db.IconSide = key; ApplySettings() end,
    })
    row3c:AddWidget(sideDropdown, 0.5)
    manager:Register(sideDropdown, "all")
    card3:AddRow(row3c, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Bar Appearance
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Bar Appearance", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local statusbarDropdown = GUIFrame:CreateDropdown(row4a, "Bar Texture", {
        options = statusbarList,
        value = db.StatusBarTexture or "KitnUI",
        callback = function(key) db.StatusBarTexture = key; ApplySettings() end,
        searchable = true,
    })
    row4a:AddWidget(statusbarDropdown, 1)
    manager:Register(statusbarDropdown, "all")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local fontDropdown = GUIFrame:CreateDropdown(row4b, "Font", {
        options = KE:AddFollowGlobalFont(fontList),
        value = db.FontFace or KE.FONT_FOLLOW_GLOBAL,
        callback = function(key) db.FontFace = KE:StoredFontFace(key); ApplySettings() end,
        searchable = true,
        isFontPreview = true,
    })
    row4b:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "all")

    local fontSizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", {
        min = 8, max = 24, step = 1,
        value = db.FontSize or 11,
        callback = function(val) db.FontSize = val; ApplySettings() end,
    })
    row4b:AddWidget(fontSizeSlider, 0.5)
    manager:Register(fontSizeSlider, "all")
    card4:AddRow(row4b, Theme.rowHeight)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local fontOutlineDropdown = GUIFrame:CreateDropdown(row4c, "Font Outline", {
        options = KE:GetFontOutlineOptions(),
        value = KE:NormalizeFontOutline(db.FontOutline or "OUTLINE"),
        callback = function(key) db.FontOutline = key; ApplySettings() end,
    })
    row4c:AddWidget(fontOutlineDropdown, 1)
    manager:Register(fontOutlineDropdown, "all")
    card4:AddRow(row4c, Theme.rowHeight)

    local rowSep4 = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local sep4 = GUIFrame:CreateSeparator(rowSep4)
    rowSep4:AddWidget(sep4, 1)
    manager:Register(sep4, "all")
    card4:AddRow(rowSep4, Theme.rowHeightSeparator)

    local row4d = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local nameCheck = GUIFrame:CreateCheckbox(row4d, "Show Player Name", {
        value = db.ShowName ~= false,
        callback = function(checked) db.ShowName = checked; ApplySettings() end,
    })
    row4d:AddWidget(nameCheck, 0.5)
    manager:Register(nameCheck, "all")

    local timerCheck = GUIFrame:CreateCheckbox(row4d, "Show Timer", {
        value = db.ShowTimer ~= false,
        callback = function(checked) db.ShowTimer = checked; ApplySettings() end,
    })
    row4d:AddWidget(timerCheck, 0.5)
    manager:Register(timerCheck, "all")
    card4:AddRow(row4d, Theme.rowHeight)

    local row4e = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local iconCheck = GUIFrame:CreateCheckbox(row4e, "Show Kick Icon", {
        value = db.ShowIcon ~= false,
        callback = function(checked) db.ShowIcon = checked; ApplySettings() end,
    })
    row4e:AddWidget(iconCheck, 0.5)
    manager:Register(iconCheck, "all")

    local readyCheck = GUIFrame:CreateCheckbox(row4e, "Show Ready Text", {
        value = db.ShowReadyText ~= false,
        callback = function(checked) db.ShowReadyText = checked; ApplySettings() end,
    })
    row4e:AddWidget(readyCheck, 0.5)
    manager:Register(readyCheck, "all")
    card4:AddRow(row4e, Theme.rowHeight)

    local row4n = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local nickCheck = GUIFrame:CreateCheckbox(row4n, "Use Nicknames", {
        value = db.UseNicknames ~= false,
        tooltip = "Bar names use NSRT nicknames while NSRT's nickname switch is on.",
        callback = function(checked) db.UseNicknames = checked; ApplySettings() end,
    })
    row4n:AddWidget(nickCheck, 0.5)
    manager:Register(nickCheck, "all")
    card4:AddRow(row4n, Theme.rowHeight)

    local row4f = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local iconSizeSlider = GUIFrame:CreateSlider(row4f, "Icon Size", {
        min = 12, max = 40, step = 1,
        value = db.IconSize or 20,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row4f:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")

    local readyTextInput = GUIFrame:CreateEditBox(row4f, "Ready Text", {
        value = db.ReadyText or "Ready",
        callback = function(text) db.ReadyText = text; ApplySettings() end,
    })
    row4f:AddWidget(readyTextInput, 0.5)
    manager:Register(readyTextInput, "all")
    card4:AddRow(row4f, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local colorModeDropdown = GUIFrame:CreateDropdown(row5a, "Color Mode", {
        options = {
            { key = "class", text = "Class Colored Bars" },
            { key = "dark",  text = "Dark Bars" },
        },
        value = db.ColorMode or "class",
        callback = function(key)
            db.ColorMode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row5a:AddWidget(colorModeDropdown, 0.5)
    manager:Register(colorModeDropdown, "all")

    local classColorCDCheck = GUIFrame:CreateCheckbox(row5a, "Class Color While Cooling", {
        value = db.ClassColorCooling == true,
        callback = function(checked)
            db.ClassColorCooling = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row5a:AddWidget(classColorCDCheck, 0.5)
    manager:Register(classColorCDCheck, "classOnly")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5note = GUIFrame:CreateRow(card5.content, Theme.rowHeightNote)
    local note5 = GUIFrame:CreateText(row5note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("Class Colored") .. " — class-colored bars with white names.\n" ..
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("Dark") .. " — dark bars with class-colored names.",
        50, "hide")
    row5note:AddWidget(note5, 1)
    manager:Register(note5, "all")
    card5:AddRow(row5note, Theme.rowHeightNote)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local coolingPicker = GUIFrame:CreateColorPicker(row5b, "Cooling Color", {
        color = db.CoolingColor or { 0.8, 0.2, 0.2, 1 },
        callback = function(r, g, b, a)
            db.CoolingColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(coolingPicker, 0.33)
    manager:Register(coolingPicker, "cooling")

    local readyPicker = GUIFrame:CreateColorPicker(row5b, "Ready Color", {
        color = db.ReadyColor or { 0.2, 0.8, 0.2, 1 },
        callback = function(r, g, b, a)
            db.ReadyColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(readyPicker, 0.33)
    manager:Register(readyPicker, "classOnly")

    local bgPicker = GUIFrame:CreateColorPicker(row5b, "Background Color", {
        color = db.BackgroundColor or { 0.031, 0.031, 0.031, 0.80 },
        callback = function(r, g, b, a)
            db.BackgroundColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(bgPicker, 0.34)
    manager:Register(bgPicker, "all")
    card5:AddRow(row5b, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Sort Priority
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Sort Priority", yOffset)
    manager:Register(card6, "all")

    local row6note = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local note6 = GUIFrame:CreateText(row6note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Ready bars sorted by role priority, cooling bars sorted by remaining time (shortest first).",
        Theme.rowHeight, "hide")
    row6note:AddWidget(note6, 1)
    manager:Register(note6, "all")
    card6:AddRow(row6note, Theme.rowHeight)

    local row6a = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local tankSlider = GUIFrame:CreateSlider(row6a, "Tank", {
        min = 1, max = 3, step = 1,
        value = db.SortTankPriority or 1,
        callback = function(val) db.SortTankPriority = val; ApplySettings() end,
    })
    row6a:AddWidget(tankSlider, 0.33)
    manager:Register(tankSlider, "all")

    local healerSlider = GUIFrame:CreateSlider(row6a, "Healer", {
        min = 1, max = 3, step = 1,
        value = db.SortHealerPriority or 2,
        callback = function(val) db.SortHealerPriority = val; ApplySettings() end,
    })
    row6a:AddWidget(healerSlider, 0.33)
    manager:Register(healerSlider, "all")

    local dpsSlider = GUIFrame:CreateSlider(row6a, "DPS", {
        min = 1, max = 3, step = 1,
        value = db.SortDPSPriority or 3,
        callback = function(val) db.SortDPSPriority = val; ApplySettings() end,
    })
    row6a:AddWidget(dpsSlider, 0.34)
    manager:Register(dpsSlider, "all")
    card6:AddRow(row6a, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    RefreshStates()
    return yOffset
end)
