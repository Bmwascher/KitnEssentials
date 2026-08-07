-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-EbonMightTracker.lua                                ║
-- ║  GUI: Ebon Might Tracker                                 ║
-- ║  Purpose: Configuration panel for the EbonMightTracker   ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("EbonMightTracker", true)
    end
    return nil
end

GUIFrame:RegisterContent("EbonMightTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.EbonMightTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local EMT = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if EMT and EMT.ApplySettings then EMT:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not EMT then return end
        EMT.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("EbonMightTracker")
        else
            KitnEssentials:DisableModule("EbonMightTracker")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Ebon Might Tracker", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        KE:Print("Ebon Might Tracker: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteRow = GUIFrame:CreateRow(card1.content, 65)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Augmentation Evoker only.\n" ..
        KE:ColorTextByTheme("-") .. " Tracks your Ebon Might duration with crit and duped cast detection\n" ..
        "   (Chronowarden + Double-time).",
        65, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 65, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Main Stat
    -- 12.0.5 encounters return UnitStat as a secret value, so crit
    -- detection can't read it live. The module saves mainstat on combat
    -- exit and /reload; the Update button is a manual fallback.
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Main Stat", yOffset)
    manager:Register(card2, "all")

    local statusRow = GUIFrame:CreateRow(card2.content, 52)
    local statusText = GUIFrame:CreateText(statusRow, "Saved Value", "", 52, "hide")
    statusRow:AddWidget(statusText, 1)
    card2:AddRow(statusRow, 52)

    local function RefreshStatus()
        local label = statusText.container and statusText.container.label
        if not label then return end
        local stat = db.MainStat or 0
        if stat > 0 then
            label:SetText(("Set: %d"):format(stat))
            label:SetTextColor(0.3, 0.9, 0.3, 1)
        else
            label:SetText("Not set — open the options out of combat and click Update.")
            label:SetTextColor(0.95, 0.35, 0.35, 1)
        end
    end
    RefreshStatus()

    local updateRow = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local updateBtn = GUIFrame:CreateButton(updateRow, "Update from Current Stat", {
        width = 200,
        callback = function()
            if EMT and EMT.UpdateMainStat then
                EMT:UpdateMainStat()
            end
            RefreshStatus()
        end,
        tooltip = "Manual fallback. Auto-saves on combat exit and /reload — click this if auto-save missed a gear/stat change. Arcane Intellect is divided out automatically, safe with it up.",
    })
    updateRow:AddWidget(updateBtn, 1)
    manager:Register(updateBtn, "all")
    card2:AddRow(updateRow, Theme.rowHeight)

    local rowMSNote = GUIFrame:CreateRow(card2.content, Theme.rowHeightNote)
    local msNote = GUIFrame:CreateText(rowMSNote,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Auto-saves on combat exit and /reload. Button is a manual fallback.\n" ..
        KE:ColorTextByTheme("-") .. " Arcane Intellect is factored out automatically. Food and Augment Runes are not.",
        50, "hide")
    rowMSNote:AddWidget(msNote, 1)
    manager:Register(msNote, "all")
    card2:AddRow(rowMSNote, Theme.rowHeightNote, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Display Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local modeDropdown = GUIFrame:CreateDropdown(row3a, "Mode", {
        options = {
            { key = "icon", text = "Icon + Countdown" },
            { key = "text", text = "Border + State Label" },
        },
        value = db.Mode or "icon",
        callback = function(key) db.Mode = key; ApplySettings() end,
    })
    row3a:AddWidget(modeDropdown, 0.5)
    manager:Register(modeDropdown, "all")

    local iconSizeSlider = GUIFrame:CreateSlider(row3a, "Icon Size", {
        min = 16, max = 128, step = 1,
        value = db.IconSize or 48,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row3a:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local onlyCritCheck = GUIFrame:CreateCheckbox(row3b, "Only Show on Crit", {
        value = db.OnlyShowCrit == true,
        callback = function(checked) db.OnlyShowCrit = checked; ApplySettings() end,
    })
    row3b:AddWidget(onlyCritCheck, 0.5)
    manager:Register(onlyCritCheck, "all")

    local combatCheck = GUIFrame:CreateCheckbox(row3b, "Combat Only", {
        value = db.CombatOnly == true,
        callback = function(checked) db.CombatOnly = checked; ApplySettings() end,
    })
    row3b:AddWidget(combatCheck, 0.5)
    manager:Register(combatCheck, "all")
    card3:AddRow(row3b, Theme.rowHeight)

    local rowSep = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(rowSep)
    rowSep:AddWidget(sep1, 1)
    manager:Register(sep1, "all")
    card3:AddRow(rowSep, Theme.rowHeightSeparator)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local pandemicCheck = GUIFrame:CreateCheckbox(row3c, "Pandemic Highlight", {
        value = db.PandemicHighlight == true,
        callback = function(checked) db.PandemicHighlight = checked; ApplySettings() end,
    })
    row3c:AddWidget(pandemicCheck, 0.5)
    manager:Register(pandemicCheck, "all")

    local glowDropdown = GUIFrame:CreateDropdown(row3c, "Glow Style", {
        options = {
            { key = "pixel",    text = "Pixel" },
            { key = "autocast", text = "Autocast" },
            { key = "button",   text = "Button" },
            { key = "proc",     text = "Proc" },
        },
        value = db.PandemicGlowType or "pixel",
        callback = function(key) db.PandemicGlowType = key; ApplySettings() end,
    })
    row3c:AddWidget(glowDropdown, 0.5)
    manager:Register(glowDropdown, "all")
    card3:AddRow(row3c, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Position Settings
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
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 5: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 6: Colors
    ----------------------------------------------------------------
    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {
        db = db,
        manager = manager,
        onChange = ApplySettings,
        colors = {
            { label = "Base Color", key = "BaseColor", default = { 1, 1, 1, 1 } },
            { label = "Crit Color", key = "CritColor", default = { 1, 0, 1, 1 } },
            { label = "Dupe Color", key = "DupeColor", default = { 1, 0.5, 0, 1 } },
            { label = "Pandemic Color", key = "PandemicColor", default = { 1, 1, 0, 1 } },
        },
        isLast = true,
    })

    RefreshStates()
    return yOffset
end)
