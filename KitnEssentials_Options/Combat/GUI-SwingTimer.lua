-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SwingTimer.lua                                      ║
-- ║  GUI: Swing Timer                                        ║
-- ║  Purpose: Configuration panel for the SwingTimer module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local ipairs, pairs = ipairs, pairs

local function GetModule()
    return KitnEssentials:GetModule("SwingTimer", true)
end

GUIFrame:RegisterContent("SwingTimer", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.SwingTimer
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local mod = GetModule()
    local Rules = KE.SwingTimerRules
    local PROOF = Rules.PROOF
    local _, classFile = UnitClass("player")
    local isGuideClass = Rules.IsGuideClass(classFile)
    local hasQueue = Rules.QueueEventWanted(classFile, true)
    local isPaladin = classFile == "PALADIN"

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("window", function() return db.EndWindow == true end)
    manager:SetCondition("guideClass", function() return isGuideClass end)
    manager:SetCondition("castTickRanged", function()
        return not (isGuideClass and db.RangedGuide and db.HunterStyle == "windup")
    end)
    manager:SetCondition("queueClass", function() return hasQueue end)
    manager:SetCondition("queueColor", function() return hasQueue and db.QueueColors == true end)
    manager:SetCondition("sealClass", function() return isPaladin end)
    manager:SetCondition("sealColor", function() return isPaladin and db.SealColors == true end)

    local function ApplySettings()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyPosition()
        if mod and mod.ApplyPosition then mod:ApplyPosition() end
    end

    local function ApplyModuleState(enabled)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SwingTimer")
        else
            KitnEssentials:DisableModule("SwingTimer")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    local function AddSwitch(card, label, key, group, tooltip, isLast)
        local height = isLast and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(card.content, height)
        local check = GUIFrame:CreateCheckbox(row, label, {
            value = db[key] == true,
            tooltip = tooltip,
            callback = function(checked)
                db[key] = checked
                ApplySettings()
                RefreshStates()
            end,
        })
        row:AddWidget(check, 1)
        manager:Register(check, group)
        card:AddRow(row, height, isLast and 0 or nil)
    end

    local function AddPicker(row, label, key, group, weight)
        local picker = GUIFrame:CreateColorPicker(row, label, {
            color = db[key],
            callback = function(r, g, b, a)
                db[key] = { r, g, b, a }
                ApplySettings()
            end,
        })
        row:AddWidget(picker, weight)
        manager:Register(picker, group)
    end

    local statusbarList = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do statusbarList[name] = name end
    else
        statusbarList["Blizzard"] = "Blizzard"
    end

    local description = "One bar per weapon that shows when your swing lands, whether one is waiting on you, " ..
        "whether it will reach, and, for hunters and wand users, when to stand still."
    if PROOF.BLIZZARD_BUTTON then
        if PROOF.EDIT_MODE_CHECKBOX then
            description = description .. "\n\nA Blizzard bar hidden from this page stays hidden, even with this " ..
                "module off, until you bring it back here or Shift-click Swing Timer in " .. KE:Gold("Blizzard's Edit Mode") .. "."
        else
            description = description .. "\n\nA Blizzard bar hidden from this page stays hidden, even with this " ..
                "module off, until you bring it back here."
        end
    end

    ----------------------------------------------------------------
    -- Swing Timer
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Swing Timer", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)
    card1:AddLabel(description)
    yOffset = card1:GetNextOffset()

    -- A disabled module shows only this card: its switch and description.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Show In
    ----------------------------------------------------------------
    local showCard = GUIFrame:CreateCard(scrollChild, "Show In", yOffset)
    manager:Register(showCard, "all")

    local showRow = GUIFrame:CreateRow(showCard.content, Theme.rowHeight)
    local visibilityDropdown = GUIFrame:CreateDropdown(showRow, "Show Bars", {
        options = {
            { key = "combat", text = "In Combat" },
            { key = "always", text = "Always" },
            { key = "idle", text = "While a Swing Is Live" },
        },
        value = db.Visibility or "combat",
        callback = function(key)
            db.Visibility = key
            ApplySettings()
        end,
    })
    showRow:AddWidget(visibilityDropdown, 1)
    manager:Register(visibilityDropdown, "all")
    showCard:AddRow(showRow, Theme.rowHeight)

    AddSwitch(showCard, "Show a Second Weapon Only When It Swings", "ShowWhenSwings", "all",
        "A warrior's gun or a hunter's melee weapon shows from its first swing until combat ends.", true)
    yOffset = showCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Blizzard's Swing Bar
    ----------------------------------------------------------------
    local blizzardShown, blizzardAction = false, nil
    if mod then blizzardShown, blizzardAction = mod:BlizzardButtonState() end
    if blizzardShown then
        local blizzardCard = GUIFrame:CreateCard(scrollChild, "Blizzard's Swing Bar", yOffset)
        manager:Register(blizzardCard, "all")
        if PROOF.BLIZZARD_BUTTON then
            local buttonRow = GUIFrame:CreateRow(blizzardCard.content, Theme.rowHeight)
            local toggleButton = GUIFrame:CreateButton(buttonRow,
                blizzardAction == "hide" and "Hide Blizzard's Bar" or "Show Blizzard's Bar", {
                    width = 180,
                    height = 28,
                    callback = function()
                        mod:ToggleBlizzardBar()
                        GUIFrame:RefreshContent()
                    end,
                })
            buttonRow:AddWidget(toggleButton, 1)
            manager:Register(toggleButton, "all")
            blizzardCard:AddRow(buttonRow, Theme.rowHeight)
            if PROOF.EDIT_MODE_CHECKBOX then
                blizzardCard:AddNote("This changes the game's own setting. It stays that way until you change it " ..
                    "here or Shift-click Swing Timer in " .. KE:Gold("Blizzard's Edit Mode") .. ".")
            else
                blizzardCard:AddNote("This changes the game's own setting. It stays that way until you change it " ..
                    "here. Swing Timer in " .. KE:Gold("Blizzard's Edit Mode") .. " is the game's own control for its bar.")
            end
        elseif blizzardAction == "hide" then
            blizzardCard:AddNote("Blizzard's own swing bar is on, so both bars can show. Swing Timer in " ..
                KE:Gold("Blizzard's Edit Mode") .. " is the game's own control for it.")
        else
            blizzardCard:AddNote("Blizzard's own swing bar is off. Swing Timer in " ..
                KE:Gold("Blizzard's Edit Mode") .. " is the game's own control for it.")
        end
        yOffset = blizzardCard:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Bars
    ----------------------------------------------------------------
    local barsCard = GUIFrame:CreateCard(scrollChild, "Bars", yOffset)
    manager:Register(barsCard, "all")
    AddSwitch(barsCard, "Drain Instead of Fill", "Deplete", "all")
    AddSwitch(barsCard, "Show Countdown", "ShowTime", "all")
    AddSwitch(barsCard, "Dim When Out of Range", "RangeCheck", "all", nil, PROOF.RANGE_SEES_DEAD_ZONE)
    if not PROOF.RANGE_SEES_DEAD_ZONE then
        barsCard:AddNote("The Ranged bar may not warn about a hunter's dead zone.")
    end
    yOffset = barsCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Melee Assists
    ----------------------------------------------------------------
    local meleeCard = GUIFrame:CreateCard(scrollChild, "Melee Assists", yOffset)
    manager:Register(meleeCard, "all")
    AddSwitch(meleeCard, "Brighten the End of the Swing", "EndWindow", "all")

    local windowRow = GUIFrame:CreateRow(meleeCard.content, Theme.rowHeight)
    local windowSlider = GUIFrame:CreateSlider(windowRow, "End Window Seconds", {
        min = 0.1, max = 2, step = 0.05,
        value = db.EndWindowSeconds or 0.4,
        callback = function(val)
            db.EndWindowSeconds = val
            ApplySettings()
        end,
    })
    windowRow:AddWidget(windowSlider, 1)
    manager:Register(windowSlider, "window")
    meleeCard:AddRow(windowRow, Theme.rowHeight)

    AddSwitch(meleeCard, "Add Latency to the Window", "AddLatency", "window")
    AddSwitch(meleeCard, "Show a Tick Where a Cast Ends", "CastTickMelee", "all", nil, true)
    yOffset = meleeCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Ranged Guide
    ----------------------------------------------------------------
    local guideCard = GUIFrame:CreateCard(scrollChild, "Ranged Guide", yOffset)
    manager:Register(guideCard, "all")
    AddSwitch(guideCard, "Guide When to Stand Still", "RangedGuide", "guideClass",
        "For hunters, mages, priests and warlocks. The aim before a shot has no Blizzard source, so the " ..
        "stop-by line is an estimate.")

    local styleRow = GUIFrame:CreateRow(guideCard.content, Theme.rowHeight)
    local styleDropdown = GUIFrame:CreateDropdown(styleRow, "Hunter Style", {
        options = {
            { key = "zones", text = "Zones" },
            { key = "windup", text = "Wind-Up" },
        },
        value = db.HunterStyle or "zones",
        callback = function(key)
            db.HunterStyle = key
            ApplySettings()
            RefreshStates()
        end,
    })
    styleRow:AddWidget(styleDropdown, 1)
    manager:Register(styleDropdown, "guideClass")
    guideCard:AddRow(styleRow, Theme.rowHeight)

    AddSwitch(guideCard, "Show a Tick Where a Cast Ends", "CastTickRanged", "castTickRanged", nil, true)
    yOffset = guideCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Queued Attacks
    ----------------------------------------------------------------
    local queueCard = GUIFrame:CreateCard(scrollChild, "Queued Attacks", yOffset)
    manager:Register(queueCard, "all")
    AddSwitch(queueCard, "Color a Bar While an Attack Is Queued", "QueueColors", "queueClass")

    local queueRow = GUIFrame:CreateRow(queueCard.content, Theme.rowHeightLast)
    AddPicker(queueRow, "Queued Attack", "ColorQueue", "queueColor", 0.5)
    AddPicker(queueRow, "Cleave", "ColorCleave", "queueColor", 0.5)
    queueCard:AddRow(queueRow, Theme.rowHeightLast, 0)
    yOffset = queueCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Target Estimate
    ----------------------------------------------------------------
    if PROOF.TARGET_BAR then
        local targetCard = GUIFrame:CreateCard(scrollChild, "Target Estimate", yOffset)
        manager:Register(targetCard, "all")
        AddSwitch(targetCard, "Show the Target's Estimated Swing", "TargetEstimate", "all")

        local targetRow = GUIFrame:CreateRow(targetCard.content, Theme.rowHeight)
        AddPicker(targetRow, "Target Bar", "ColorTarget", "all", 1)
        targetCard:AddRow(targetRow, Theme.rowHeight)

        targetCard:AddNote("This is an estimate from hits you take, so it starts on the second hit. A hit on you " ..
            "from another enemy, a miss the game does not report, or a stun can throw it off.")
        yOffset = targetCard:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Display Settings
    ----------------------------------------------------------------
    local displayCard = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(displayCard, "all")

    -- Unlock mode pulls a matched axis straight back to its target, so that
    -- slider would do nothing here.
    local unlock = KE.EUIUnlock
    local widthMatched = unlock ~= nil and unlock:MatchTarget("SwingTimer", "width") ~= nil
    local heightMatched = unlock ~= nil and unlock:MatchTarget("SwingTimer", "height") ~= nil
    manager:SetCondition("widthFree", function() return not widthMatched end)
    manager:SetCondition("heightFree", function() return not heightMatched end)

    local sizeRow = GUIFrame:CreateRow(displayCard.content, Theme.rowHeight)
    -- A size matched or typed in EllesmereUI's unlock mode can lie outside the
    -- ranges below, so each range widens to show the size the bars have.
    local width, height = db.Width or 240, db.Height or 16
    local widthSlider = GUIFrame:CreateSlider(sizeRow, "Width", {
        min = math.min(100, math.floor(width)), max = math.max(600, math.ceil(width)), step = 1,
        value = width,
        callback = function(val)
            db.Width = val
            ApplySettings()
        end,
    })
    sizeRow:AddWidget(widthSlider, 0.5)
    manager:Register(widthSlider, "widthFree")
    local heightSlider = GUIFrame:CreateSlider(sizeRow, "Height", {
        min = math.min(8, math.floor(height)), max = math.max(40, math.ceil(height)), step = 1,
        value = height,
        callback = function(val)
            db.Height = val
            ApplySettings()
        end,
    })
    sizeRow:AddWidget(heightSlider, 0.5)
    manager:Register(heightSlider, "heightFree")
    displayCard:AddRow(sizeRow, Theme.rowHeight)

    local matchNote = widthMatched or heightMatched
    local lookHeight = matchNote and Theme.rowHeight or Theme.rowHeightLast
    local lookRow = GUIFrame:CreateRow(displayCard.content, lookHeight)
    local spacingSlider = GUIFrame:CreateSlider(lookRow, "Spacing", {
        min = 0, max = 20, step = 1,
        value = db.Spacing or 2,
        callback = function(val)
            db.Spacing = val
            ApplySettings()
        end,
    })
    lookRow:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    local textureDropdown = GUIFrame:CreateDropdown(lookRow, "Bar Texture", {
        options = statusbarList,
        value = db.StatusBarTexture or "KitnUI",
        callback = function(key)
            db.StatusBarTexture = key
            ApplySettings()
        end,
        searchable = true,
    })
    lookRow:AddWidget(textureDropdown, 0.5)
    manager:Register(textureDropdown, "all")
    displayCard:AddRow(lookRow, lookHeight, (not matchNote) and 0 or nil)
    if matchNote then
        local which = (widthMatched and heightMatched) and "Width and Height follow"
            or (widthMatched and "Width follows" or "Height follows")
        displayCard:AddNote(which .. " a size match in " .. KE:Gold("EllesmereUI's unlock mode") ..
            ". Clear the match there to set it here.")
    end
    yOffset = displayCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplyPosition,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 24 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Colors
    ----------------------------------------------------------------
    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {
        db = db,
        manager = manager,
        onChange = ApplySettings,
        stateGroup = "all",
        colors = {
            { label = "Main Hand", key = "ColorMH", default = { 0.624, 0.749, 1, 1 } },
            { label = "Off Hand", key = "ColorOH", default = { 0.475, 0.586, 0.812, 1 } },
            { label = "Ranged", key = "ColorR", default = { 0.624, 0.749, 1, 1 } },
            { label = "End Window", key = "ColorWindow", default = { 1, 1, 1, 0.34 } },
            { label = "Stand Still", key = "ColorStill", default = { 1, 0.82, 0.25, 1 } },
            { label = "Stop", key = "ColorStop", default = { 0.95, 0.20, 0.20, 1 } },
            { label = "Text", key = "TextColor", default = { 1, 1, 1, 1 } },
            { label = "Background", key = "BackdropColor", default = { 0, 0, 0, 0.8 } },
            { label = "Border", key = "BorderColor", default = { 0, 0, 0, 1 } },
        },
    })

    ----------------------------------------------------------------
    -- Seal Colors
    ----------------------------------------------------------------
    local sealCard = GUIFrame:CreateCard(scrollChild, "Seal Colors", yOffset)
    manager:Register(sealCard, "all")
    AddSwitch(sealCard, "Color Melee Bars by Your Seal", "SealColors", "sealClass")

    local sealRow
    for index, seal in ipairs(Rules.SEALS) do
        if index % 2 == 1 then
            sealRow = GUIFrame:CreateRow(sealCard.content, Theme.rowHeight)
            sealCard:AddRow(sealRow, Theme.rowHeight)
        end
        AddPicker(sealRow, seal.label, seal.colorKey, "sealColor", 0.5)
    end
    sealCard:AddNote("In combat the color is the last seal you cast, since auras cannot be read then.")
    yOffset = sealCard:GetNextOffset()

    RefreshStates()
    return yOffset
end)
