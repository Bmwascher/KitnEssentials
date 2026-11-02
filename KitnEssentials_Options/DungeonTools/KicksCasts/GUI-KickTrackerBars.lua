-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KickTrackerBars.lua                                 ║
-- ║  GUI: Interrupt Tracker > Bars                           ║
-- ║  Purpose: the cooldown bars' settings tab.               ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local pairs = pairs

GUIFrame:RegisterContent("KickTrackerBars", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.KickTracker
    if not db then return yOffset end

    local KT = KitnEssentials and KitnEssentials:GetModule("KickTracker", true)

    local manager = GUIFrame:CreateWidgetStateManager()
    -- "all" is the bar cards' group: grayed while Show Bars is off.
    manager:SetCondition("all", function()
        return db.ShowBars ~= false
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
    -- Bars: the display switch, then what each bar shows
    ----------------------------------------------------------------
    local cardBars = GUIFrame:CreateCard(scrollChild, "Bars", yOffset)
    cardBars:AddHeaderToggle(db.ShowBars ~= false, function(checked)
        db.ShowBars = checked
        ApplySettings()
    end)

    local rowBars1 = GUIFrame:CreateRow(cardBars.content, Theme.rowHeight)
    local nameCheck = GUIFrame:CreateCheckbox(rowBars1, "Show Player Name", {
        value = db.ShowName ~= false,
        callback = function(checked) db.ShowName = checked; ApplySettings() end,
    })
    rowBars1:AddWidget(nameCheck, 0.5)
    manager:Register(nameCheck, "all")

    local timerCheck = GUIFrame:CreateCheckbox(rowBars1, "Show Timer", {
        value = db.ShowTimer ~= false,
        callback = function(checked) db.ShowTimer = checked; ApplySettings() end,
    })
    rowBars1:AddWidget(timerCheck, 0.5)
    manager:Register(timerCheck, "all")
    cardBars:AddRow(rowBars1, Theme.rowHeight)

    local rowBars2 = GUIFrame:CreateRow(cardBars.content, Theme.rowHeight)
    local iconCheck = GUIFrame:CreateCheckbox(rowBars2, "Show Kick Icon", {
        value = db.ShowIcon ~= false,
        callback = function(checked) db.ShowIcon = checked; ApplySettings() end,
    })
    rowBars2:AddWidget(iconCheck, 0.5)
    manager:Register(iconCheck, "all")

    local nickCheck = GUIFrame:CreateCheckbox(rowBars2, "Use Nicknames", {
        value = db.UseNicknames ~= false,
        tooltip = "Bar names use NSRT nicknames while NSRT's nickname switch is on.",
        callback = function(checked) db.UseNicknames = checked; ApplySettings() end,
    })
    rowBars2:AddWidget(nickCheck, 0.5)
    manager:Register(nickCheck, "all")
    cardBars:AddRow(rowBars2, Theme.rowHeight)

    local rowBars3 = GUIFrame:CreateRow(cardBars.content, Theme.rowHeightLast)
    local readyCheck = GUIFrame:CreateCheckbox(rowBars3, "Show Ready Text", {
        value = db.ShowReadyText ~= false,
        callback = function(checked) db.ShowReadyText = checked; ApplySettings() end,
    })
    rowBars3:AddWidget(readyCheck, 0.5)
    manager:Register(readyCheck, "all")

    local readyTextInput = GUIFrame:CreateEditBox(rowBars3, "Ready Text", {
        value = db.ReadyText or "Ready",
        callback = function(text) db.ReadyText = text; ApplySettings() end,
    })
    rowBars3:AddWidget(readyTextInput, 0.5)
    manager:Register(readyTextInput, "all")
    cardBars:AddRow(rowBars3, Theme.rowHeightLast, 0)

    yOffset = cardBars:GetNextOffset()

    ----------------------------------------------------------------
    -- Sort Priority
    ----------------------------------------------------------------
    local cardSort = GUIFrame:CreateCard(scrollChild, "Sort Priority", yOffset)
    manager:Register(cardSort, "all")

    local row6note = GUIFrame:CreateRow(cardSort.content, Theme.rowHeight)
    local note6 = GUIFrame:CreateText(row6note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Ready bars sorted by role priority, cooling bars sorted by remaining time (shortest first).",
        Theme.rowHeight, "hide")
    row6note:AddWidget(note6, 1)
    manager:Register(note6, "all")
    cardSort:AddRow(row6note, Theme.rowHeight)

    local row6a = GUIFrame:CreateRow(cardSort.content, Theme.rowHeightLast)
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
    cardSort:AddRow(row6a, Theme.rowHeightLast, 0)

    yOffset = cardSort:GetNextOffset()

    ----------------------------------------------------------------
    -- Display Settings
    ----------------------------------------------------------------
    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(cardDisplay, "all")

    local rowD1 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    local widthSlider = GUIFrame:CreateSlider(rowD1, "Bar Width", {
        min = 80, max = 400, step = 1,
        value = db.BarWidth or 180,
        callback = function(val) db.BarWidth = val; ApplySettings() end,
    })
    rowD1:AddWidget(widthSlider, 0.5)
    manager:Register(widthSlider, "all")

    local heightSlider = GUIFrame:CreateSlider(rowD1, "Bar Height", {
        min = 12, max = 40, step = 1,
        value = db.BarHeight or 20,
        callback = function(val) db.BarHeight = val; ApplySettings() end,
    })
    rowD1:AddWidget(heightSlider, 0.5)
    manager:Register(heightSlider, "all")
    cardDisplay:AddRow(rowD1, Theme.rowHeight)

    local rowD2 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    local spacingSlider = GUIFrame:CreateSlider(rowD2, "Bar Spacing", {
        min = 0, max = 10, step = 1,
        value = db.BarSpacing or 2,
        callback = function(val) db.BarSpacing = val; ApplySettings() end,
    })
    rowD2:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")

    local iconSizeSlider = GUIFrame:CreateSlider(rowD2, "Kick Icon Size", {
        min = 12, max = 40, step = 1,
        value = db.IconSize or 20,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    rowD2:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")
    cardDisplay:AddRow(rowD2, Theme.rowHeight)

    local rowD3 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    local growDropdown = GUIFrame:CreateDropdown(rowD3, "Growth Direction", {
        options = {
            { key = "DOWN", text = "Down" },
            { key = "UP",   text = "Up" },
        },
        value = db.GrowthDirection or "DOWN",
        callback = function(key) db.GrowthDirection = key; ApplySettings() end,
    })
    rowD3:AddWidget(growDropdown, 0.5)
    manager:Register(growDropdown, "all")

    local sideDropdown = GUIFrame:CreateDropdown(rowD3, "Kick Icon Side", {
        options = {
            { key = "LEFT",  text = "Left" },
            { key = "RIGHT", text = "Right" },
        },
        value = db.IconSide or "LEFT",
        callback = function(key) db.IconSide = key; ApplySettings() end,
    })
    rowD3:AddWidget(sideDropdown, 0.5)
    manager:Register(sideDropdown, "all")
    cardDisplay:AddRow(rowD3, Theme.rowHeight)

    local rowD4 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    local statusbarDropdown = GUIFrame:CreateDropdown(rowD4, "Bar Texture", {
        options = statusbarList,
        value = db.StatusBarTexture or "KitnUI",
        callback = function(key) db.StatusBarTexture = key; ApplySettings() end,
        searchable = true,
    })
    rowD4:AddWidget(statusbarDropdown, 1)
    manager:Register(statusbarDropdown, "all")
    cardDisplay:AddRow(rowD4, Theme.rowHeight)
    cardDisplay:AddNote("The " .. KE:Gold("Default") .. " and " .. KE:Gold("Healer") ..
        " views below change only the bar position.")

    yOffset = cardDisplay:GetNextOffset()

    ----------------------------------------------------------------
    -- Position, one view per position
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
    -- Position Settings (the view's keys: Default vs Healer)
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
    -- Font Settings
    ----------------------------------------------------------------
    local cardFont = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    manager:Register(cardFont, "all")

    local rowF1 = GUIFrame:CreateRow(cardFont.content, Theme.rowHeight)
    local fontDropdown = GUIFrame:CreateDropdown(rowF1, "Font", {
        options = KE:AddFollowGlobalFont(fontList),
        value = db.FontFace or KE.FONT_FOLLOW_GLOBAL,
        callback = function(key) db.FontFace = KE:StoredFontFace(key); ApplySettings() end,
        searchable = true,
        isFontPreview = true,
    })
    rowF1:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "all")

    local fontSizeSlider = GUIFrame:CreateSlider(rowF1, "Font Size", {
        min = 8, max = 24, step = 1,
        value = db.FontSize or 11,
        callback = function(val) db.FontSize = val; ApplySettings() end,
    })
    rowF1:AddWidget(fontSizeSlider, 0.5)
    manager:Register(fontSizeSlider, "all")
    cardFont:AddRow(rowF1, Theme.rowHeight)

    local rowF2 = GUIFrame:CreateRow(cardFont.content, Theme.rowHeightLast)
    local fontOutlineDropdown = GUIFrame:CreateDropdown(rowF2, "Font Outline", {
        options = KE:GetFontOutlineOptions(),
        value = KE:NormalizeFontOutline(db.FontOutline or "OUTLINE"),
        callback = function(key) db.FontOutline = key; ApplySettings() end,
    })
    rowF2:AddWidget(fontOutlineDropdown, 1)
    manager:Register(fontOutlineDropdown, "all")
    cardFont:AddRow(rowF2, Theme.rowHeightLast, 0)

    yOffset = cardFont:GetNextOffset()

    ----------------------------------------------------------------
    -- Colors
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

    RefreshStates()
    return yOffset
end)
