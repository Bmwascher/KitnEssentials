-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KickTracker.lua                                     ║
-- ║  GUI: Interrupt Tracker                                  ║
-- ║  Purpose: Configuration panel for the KickTracker module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
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
    -- "position" group is enabled when main is on AND healer override isn't
    -- currently overriding the standard position (i.e. user is not playing
    -- healer or hasn't enabled healer override).
    manager:SetCondition("position", function()
        local healerActive = db.UseHealerPosition
            and KE.IsPlayerHealerSpec and KE:IsPlayerHealerSpec()
        return not healerActive
    end)
    -- "classOnly": widgets only meaningful when ColorMode is "class"
    manager:SetCondition("classOnly", function()
        return db.ColorMode ~= "dark"
    end)
    -- "cooling": cooling color picker requires class mode AND ClassColorCooling off
    manager:SetCondition("cooling", function()
        return db.ColorMode ~= "dark" and not db.ClassColorCooling
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

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Interrupt Tracker", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Interrupt Tracker",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Tracks party interrupt cooldowns in real-time using status bars.\n" ..
        KE:ColorTextByTheme("-") .. " Only active in 5-player dungeons.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings (gated by "position" condition so the
    -- healer override can hide/disable it when active for a healer spec)
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "position")
    end
    manager:Register(posCard, "position")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 2b: Healer Position Override
    ----------------------------------------------------------------
    local healerCard = GUIFrame:CreateCard(scrollChild, "Healer Position Override", yOffset)

    local healerRow1 = GUIFrame:CreateRow(healerCard.content, Theme.rowHeightLast)
    local healerEnableCheck = GUIFrame:CreateCheckbox(healerRow1, "Use Healer Position", {
        value = db.UseHealerPosition == true,
        callback = function(checked)
            db.UseHealerPosition = checked
            ApplySettings()
            -- Re-render so healer position card appears/disappears
            C_Timer.After(0.05, function() GUIFrame:RefreshContent() end)
        end,
    })
    healerRow1:AddWidget(healerEnableCheck, 1)
    healerCard:AddRow(healerRow1, Theme.rowHeightLast)

    local healerNoteRow = GUIFrame:CreateRow(healerCard.content, Theme.rowHeight)
    local healerNote = GUIFrame:CreateText(healerNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Auto-swap to a separate position when playing a healer spec.",
        Theme.rowHeight, "hide")
    healerNoteRow:AddWidget(healerNote, 1)
    healerCard:AddRow(healerNoteRow, Theme.rowHeight, 0)

    yOffset = healerCard:GetNextOffset()

    if db.UseHealerPosition then
        -- Metatable wrapper so CreatePositionCard reads/writes healer keys
        -- via the same dbKeys mapping as the standard position card.
        local healerDb = setmetatable({
            Position = db.HealerPosition,
        }, {
            __index = function(_, k)
                if k == "anchorFrameType" then return db.HealerAnchorFrameType
                elseif k == "ParentFrame" then return db.HealerParentFrame
                elseif k == "Strata" then return db.HealerStrata
                else return db[k] end
            end,
            __newindex = function(t, k, v)
                if k == "anchorFrameType" then db.HealerAnchorFrameType = v
                elseif k == "ParentFrame" then db.HealerParentFrame = v
                elseif k == "Strata" then db.HealerStrata = v
                else rawset(t, k, v) end
            end,
        })

        local healerPosCard, healerPosOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
            title = "Healer Position",
            db = healerDb,
            dbKeys = {
                selfPoint = "AnchorFrom",
                anchorPoint = "AnchorTo",
                xOffset = "XOffset",
                yOffset = "YOffset",
            },
            showAnchorFrameType = true,
            showStrata = true,
            onChangeCallback = ApplySettings,
        })
        if healerPosCard.positionWidgets then
            manager:RegisterGroup(healerPosCard.positionWidgets, "all")
        end
        manager:Register(healerPosCard, "all")
        yOffset = healerPosOffset
    end

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
    local maxBarsSlider = GUIFrame:CreateSlider(row3b, "Max Bars", {
        min = 1, max = 5, step = 1,
        value = db.MaxBars or 5,
        callback = function(val) db.MaxBars = val; ApplySettings() end,
    })
    row3b:AddWidget(maxBarsSlider, 0.5)
    manager:Register(maxBarsSlider, "all")

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
    -- Outline list intentionally excludes SOFTOUTLINE — bar text is small
    -- and SOFTOUTLINE produces visible halo artifacts on tiny text.
    -- Default is still SOFTOUTLINE for backward compat with existing saves.
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
        options = fontList,
        value = db.FontFace or "Expressway",
        callback = function(key) db.FontFace = key; ApplySettings() end,
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
        options = {
            { key = "NONE",         text = "None" },
            { key = "OUTLINE",      text = "Outline" },
            { key = "THICKOUTLINE", text = "Thick" },
        },
        value = db.FontOutline or "SOFTOUTLINE",
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

    local row5note = GUIFrame:CreateRow(card5.content, 50)
    local note5 = GUIFrame:CreateText(row5note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("Class Colored") .. " — class-colored bars with white names.\n" ..
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("Dark") .. " — dark bars with class-colored names.",
        50, "hide")
    row5note:AddWidget(note5, 1)
    manager:Register(note5, "all")
    card5:AddRow(row5note, 50)

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
