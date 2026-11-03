-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Executioner.lua                                     ║
-- ║  GUI: Executioner Stacks                                 ║
-- ║  Purpose: Configuration panel for the Executioner        ║
-- ║           module, a sub-tab of the Warrior tab.          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
-- Absent on WoW Forever, which does not load the module files.
local Rules = KE.ExecutionerRules

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("Executioner", true)
end

local MODES = {
    { key = "BARS",     text = "Bars" },
    { key = "PIPS",     text = "Pips" },
    { key = "ICON",     text = "Icon" },
    { key = "CUE_ONLY", text = "Cancel Icon Only" },
}

local GROW_DIRECTIONS = {
    { key = "DOWN", text = "Down" },
    { key = "UP",   text = "Up" },
}

-- U+00B7, the middle dot, kept out of the source as raw bytes.
local DOT = " \194\183 "
-- The Test Run row is the button's height, so the card ends just under it.
local TEST_BUTTON_HEIGHT = 26

local function Hex(color)
    return KE:RGBAToHex(color and color[1], color and color[2], color and color[3])
end

GUIFrame:RegisterContent("Executioner", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Executioner
    if not (db and Rules) then return yOffset end
    local cue = db.Cue

    local EX = GetModule()
    local mode = db.DisplayMode or "BARS"
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("glow", function() return cue.GlowEnabled == true end)
    manager:SetCondition("cueText", function() return cue.ShowText == true end)
    -- Tracker controls, grayed where nothing draws them; not gated on the
    -- Cancel icon. The mode dropdown rebuilds the page, so `mode` is fixed.
    local display = GUIFrame:CreateWidgetStateManager()
    display:SetCondition("stackColor", function() return mode == "BARS" or mode == "PIPS" end)
    display:SetCondition("hiddenColor", function() return mode ~= "CUE_ONLY" and db.ShowHidden ~= false end)
    display:SetCondition("fontSize", function() return mode ~= "CUE_ONLY" end)
    display:SetCondition("hiddenMarks", function() return db.ShowHidden ~= false end)
    display:SetCondition("countSize", function() return db.ShowStackCount ~= false end)
    display:SetCondition("iconSwipe", function() return db.IconSwipe ~= false end)

    local function Regray()
        manager:UpdateAll(cue.Enabled == true)
        display:UpdateAll(true)
    end

    local function ApplySettings()
        if EX then EX:ApplySettings() end
    end
    -- For controls that add or remove rows.
    local function ApplyAndRedraw()
        ApplySettings()
        GUIFrame:RefreshContent()
    end

    -- `regray` is for a box that other controls gray out with.
    local function AddCheckbox(row, label, target, key, width, regray)
        local box = GUIFrame:CreateCheckbox(row, label, {
            value = target[key] == true,
            callback = function(v)
                target[key] = v
                ApplySettings()
                if regray then Regray() end
            end,
        })
        row:AddWidget(box, width)
        return box
    end

    local function AddSlider(row, label, target, key, range, width)
        local slider = GUIFrame:CreateSlider(row, label, {
            min = range[1], max = range[2], step = range[3] or 1, value = target[key],
            callback = function(v) target[key] = v; ApplySettings() end,
        })
        row:AddWidget(slider, width)
        return slider
    end

    ----------------------------------------------------------------
    -- Card 1: module
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Executioner Stacks", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if EX then
            if checked then KitnEssentials:EnableModule("Executioner")
            else KitnEssentials:DisableModule("Executioner") end
        end
    end)
    card1:AddLabel(KE:Gold("Warriors with Slayer's Dominance only.") .. " Shows your Executioner stacks and "
        .. "the hidden timers that procs at 5 stacks start, so you see when each stack drops.\n\n"
        .. "The game hides the buff's timers in combat, so KitnEssentials counts them from your "
        .. "Slayer's Strike procs and checks the count against the real buff whenever the game shows it, "
        .. "usually out of combat.\n\n"
        .. "A right-click cancel on the buff is usually not seen until you leave combat; cancel with the "
        .. "macro on this page instead.")

    if db.Enabled ~= true then return card1:GetNextOffset() end

    local known, length = false, Rules.Length(false)
    if EX then known, length = EX:TalentStatus() end
    if known then
        local focus = length > Rules.BASE and " (Deadly Focus)" or ""
        card1:AddNote("Slayer's Dominance known" .. DOT .. "timers " .. length .. " s" .. focus)
    else
        local red = Theme.error
        card1:AddNote(KE:WrapColor("Slayer's Dominance not known on this character: nothing will show.",
            red[1], red[2], red[3]))
    end

    card1:AddSeparator()
    local testRow = GUIFrame:CreateRow(card1.content, TEST_BUTTON_HEIGHT)
    testRow:AddWidget(GUIFrame:CreateButton(testRow, "Test Run", {
        height = TEST_BUTTON_HEIGHT,
        tooltip = "Plays 11 sample procs over 22 s on screen, on any class.",
        callback = function() if EX then EX:Test() end end,
    }), 1)
    card1:AddRow(testRow, TEST_BUTTON_HEIGHT, 0)
    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Cancel Icon. The macro button and text box stay usable
    -- while the icon is off: the macro works without it.
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Cancel Icon", yOffset)
    -- The header widget rebuilds the page after this callback.
    card2:AddHeaderToggle(cue.Enabled == true, function(checked)
        cue.Enabled = checked
        ApplySettings()
    end)
    card2:AddLabel("Canceling the buff wipes your stacks and every hidden timer, so your next procs build real "
        .. "stacks again. The icon shows when that gains damage: at least one hidden timer, and hidden timers at "
        .. "least your stacks minus one (3 stacks + 2 hidden, 5 + 4). Spend Sudden Death first, then press the macro.")
    card2:AddSeparator()

    local waitRow = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    manager:Register(AddCheckbox(waitRow, "Wait While Sudden Death Is Up", cue, "WaitSuddenDeath", 1), "cue")
    card2:AddRow(waitRow, Theme.rowHeight)

    local cueSizeRow = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    manager:Register(AddSlider(cueSizeRow, "Cancel Icon Size", cue, "Size", { 16, 120 }, 0.5), "cue")
    manager:Register(AddCheckbox(cueSizeRow, "Show \"Cancel\" Text", cue, "ShowText", 0.5, true), "cue")
    card2:AddRow(cueSizeRow, Theme.rowHeight)

    -- Above the button, so the button's note ends the card with no
    -- control under it.
    local textRow = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local textBox
    textBox = GUIFrame:CreateEditBox(textRow, "Macro Text (click it, Ctrl+A, then Ctrl+C)", {
        value = Rules.MACRO_BODY,
        callback = function()
            if textBox then textBox:SetValue(Rules.MACRO_BODY) end
        end,
    })
    textRow:AddWidget(textBox, 1)
    card2:AddRow(textRow, Theme.rowHeight)

    local macroRow = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    macroRow:AddWidget(GUIFrame:CreateButton(macroRow, "Create Macro", {
        callback = function()
            if not EX then return end
            local _, message = EX:CreateCancelMacro()
            KE:Print(Rules.LABEL .. ": " .. message)
        end,
    }), 0.4)
    card2:AddRow(macroRow, Theme.rowHeight)
    card2:AddNote("Makes " .. KE:Gold(Rules.MACRO_NAME) .. " and puts it on your cursor. Not in combat.")
    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Display Settings: the chosen mode's legend (none in
    -- Cancel Icon Only), then only that mode's options
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    if mode ~= "CUE_ONLY" then
        local stack, hidden = Hex(db.StackColor), Hex(db.HiddenColor)
        if mode == "PIPS" then
            card3:AddLabel("|cff" .. stack .. "[ 12 ]|r  A stack segment, with that stack's seconds inside. "
                .. "The leftmost drops next; up to five.")
            local sample = db.ShowHiddenLabel ~= false and "hidden [17]" or "[17]"
            card3:AddLabel("|cff" .. hidden .. sample .. "|r  A hidden timer: a mark in the row under the "
                .. "segments, with its seconds inside. When it runs out it takes away a stack.")
        elseif mode == "ICON" then
            card3:AddLabel("3 |cff" .. hidden .. "+2|r  The count is your stacks; the center seconds and the "
                .. "dark swipe are the next stack's drop; the \"+2\" badge is how many hidden timers run. Their "
                .. "times are not shown in this mode.")
        else
            card3:AddLabel("|cff" .. stack .. "1   12|r  A stack. Its bar ends when you lose that stack; the "
                .. "first bar, where the bars start growing, is the next to drop.")
            card3:AddLabel("|cff" .. hidden .. "hidden   17|r  A hidden timer from a proc at 5 stacks. When it "
                .. "runs out it takes away a stack, so it eats the stacks your next procs give.")
        end
        card3:AddSeparator()
    end
    local modeRow = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    modeRow:AddWidget(GUIFrame:CreateDropdown(modeRow, "Display Mode", {
        options = MODES,
        value = mode,
        callback = function(key) db.DisplayMode = key; ApplyAndRedraw() end,
    }), 0.5)
    card3:AddRow(modeRow, Theme.rowHeight)

    if mode == "BARS" then
        local r1 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        AddCheckbox(r1, "Show Hidden Timers", db, "ShowHidden", 0.34, true)
        AddCheckbox(r1, "Show Labels", db, "ShowLabels", 0.33)
        AddCheckbox(r1, "Show Seconds", db, "ShowSeconds", 0.33)
        card3:AddRow(r1, Theme.rowHeight)
        local r2 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        r2:AddWidget(GUIFrame:CreateDropdown(r2, "Growth Direction", {
            options = GROW_DIRECTIONS,
            value = db.GrowDirection or "DOWN",
            callback = function(key) db.GrowDirection = key; ApplySettings() end,
        }), 0.5)
        AddSlider(r2, "Spacing", db, "Spacing", { 0, 10 }, 0.5)
        card3:AddRow(r2, Theme.rowHeight)
        local r3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
        AddSlider(r3, "Bar Width", db, "BarWidth", { 60, 400 }, 0.5)
        AddSlider(r3, "Bar Height", db, "BarHeight", { 6, 40 }, 0.5)
        card3:AddRow(r3, Theme.rowHeightLast, 0)
    elseif mode == "PIPS" then
        local r1 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        AddCheckbox(r1, "Show Hidden Timers", db, "ShowHidden", 0.34, true)
        AddCheckbox(r1, "Show Seconds", db, "ShowSeconds", 0.33)
        AddCheckbox(r1, "Show Stack Count", db, "ShowStackCount", 0.33, true)
        card3:AddRow(r1, Theme.rowHeight)
        local r2 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        AddSlider(r2, "Pip Width", db, "PipWidth", { 16, 80 }, 0.5)
        AddSlider(r2, "Pip Height", db, "PipHeight", { 8, 40 }, 0.5)
        card3:AddRow(r2, Theme.rowHeight)
        local r3 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        AddSlider(r3, "Spacing", db, "PipSpacing", { 0, 10 }, 0.5)
        display:Register(AddSlider(r3, "Stack Count Size", db, "StackCountSize", { 12, 48 }, 0.5), "countSize")
        card3:AddRow(r3, Theme.rowHeight)
        local r4 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        display:Register(AddSlider(r4, "Hidden Mark Width", db, "HiddenMarkWidth", { 16, 80 }, 0.5), "hiddenMarks")
        display:Register(AddSlider(r4, "Hidden Mark Height", db, "HiddenMarkHeight", { 8, 40 }, 0.5), "hiddenMarks")
        card3:AddRow(r4, Theme.rowHeight)
        local r5 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        -- Redraws: the legend's sample follows the switch.
        local labelBox = GUIFrame:CreateCheckbox(r5, "Show \"hidden\" Label", {
            value = db.ShowHiddenLabel == true,
            callback = function(v) db.ShowHiddenLabel = v; ApplyAndRedraw() end,
        })
        r5:AddWidget(labelBox, 0.5)
        display:Register(labelBox, "hiddenMarks")
        card3:AddRow(r5, Theme.rowHeight)
        card3:AddNote("Hidden timers sit in a row under the segments, one mark each (up to seven), "
            .. "oldest first, each with its seconds inside.")
    elseif mode == "ICON" then
        local r1 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        AddCheckbox(r1, "Show Hidden Count", db, "ShowHidden", 0.5, true)
        AddCheckbox(r1, "Show Seconds", db, "ShowSeconds", 0.5)
        card3:AddRow(r1, Theme.rowHeight)
        local r2 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        AddSlider(r2, "Icon Size", db, "IconSize", { 24, 120 }, 0.5)
        card3:AddRow(r2, Theme.rowHeight)
        local r3 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        AddCheckbox(r3, "Enable Swipe", db, "IconSwipe", 0.5, true)
        display:Register(AddCheckbox(r3, "Reverse Swipe", db, "IconReverse", 0.5), "iconSwipe")
        card3:AddRow(r3, Theme.rowHeight)
        card3:AddNote("The icon shows only the next stack's drop and how many hidden timers run, not each "
            .. "timer's time.")
    else
        card3:AddNote("Cancel Icon Only: nothing but the cancel icon shows. Stacks and hidden timers are still "
            .. "counted for it.")
    end
    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Cards 4 and 5: positions
    ----------------------------------------------------------------
    local positionKeys = {
        selfPoint   = "AnchorFrom",
        anchorPoint = "AnchorTo",
        xOffset     = "XOffset",
        yOffset     = "YOffset",
    }
    if mode ~= "CUE_ONLY" then
        local _, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
            title = "Tracker Position",
            db = db,
            positionKey = "Position",
            dbKeys = positionKeys,
            showStrata = false,
            onChangeCallback = ApplySettings,
        })
        yOffset = posOffset
    end
    if cue.Enabled == true then
        local _, cuePosOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
            title = "Cancel Icon Position",
            db = cue,
            positionKey = "Position",
            dbKeys = positionKeys,
            showStrata = false,
            onChangeCallback = ApplySettings,
        })
        yOffset = cuePosOffset
    end

    ----------------------------------------------------------------
    -- Card 6: Font Settings
    ----------------------------------------------------------------
    local _, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontSize    = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 6, 24 },
        onChangeCallback = ApplySettings,
    })
    -- Font, Outline, then Font Size. The "Cancel" text has a fixed size, and
    -- in Cancel Icon Only it is the only text drawn.
    if fontWidgets then
        display:Register(fontWidgets[3], "fontSize")
        if mode == "CUE_ONLY" then
            manager:Register(fontWidgets[1], "cueText")
            manager:Register(fontWidgets[2], "cueText")
        end
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 7: Colors. The stack and hidden colors redraw the legend.
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    local colorRow = GUIFrame:CreateRow(card7.content, 46)
    local stackColor = GUIFrame:CreateColorPicker(colorRow, "Stack Color", {
        color = db.StackColor,
        callback = function(r, g, b, a) db.StackColor = { r, g, b, a }; ApplyAndRedraw() end,
    })
    colorRow:AddWidget(stackColor, 0.34)
    display:Register(stackColor, "stackColor")
    local hiddenColor = GUIFrame:CreateColorPicker(colorRow, "Hidden Timer Color", {
        color = db.HiddenColor,
        callback = function(r, g, b, a) db.HiddenColor = { r, g, b, a }; ApplyAndRedraw() end,
    })
    colorRow:AddWidget(hiddenColor, 0.33)
    display:Register(hiddenColor, "hiddenColor")
    local cueTextColor = GUIFrame:CreateColorPicker(colorRow, "Cancel Text Color", {
        color = cue.TextColor,
        callback = function(r, g, b, a) cue.TextColor = { r, g, b, a }; ApplySettings() end,
    })
    colorRow:AddWidget(cueTextColor, 0.33)
    manager:Register(cueTextColor, "cueText")
    card7:AddRow(colorRow, 46, 0)
    yOffset = card7:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 8: Glow (cancel icon)
    ----------------------------------------------------------------
    local card8 = GUIFrame:CreateCard(scrollChild, "Glow", yOffset)
    local g1 = GUIFrame:CreateRow(card8.content, Theme.rowHeight)
    manager:Register(AddCheckbox(g1, "Enable Glow", cue, "GlowEnabled", 0.5, true), "cue")
    local glowColor = GUIFrame:CreateColorPicker(g1, "Glow Color", {
        color = cue.GlowColor,
        callback = function(r, g, b, a) cue.GlowColor = { r, g, b, a }; ApplySettings() end,
    })
    g1:AddWidget(glowColor, 0.5)
    manager:Register(glowColor, "glow")
    card8:AddRow(g1, Theme.rowHeight)
    local g2 = GUIFrame:CreateRow(card8.content, Theme.rowHeight)
    manager:Register(AddSlider(g2, "Lines", cue, "GlowLines", { 1, 16 }, 0.5), "glow")
    manager:Register(AddSlider(g2, "Length", cue, "GlowLength", { 1, 20 }, 0.5), "glow")
    card8:AddRow(g2, Theme.rowHeight)
    local g3 = GUIFrame:CreateRow(card8.content, Theme.rowHeightLast)
    manager:Register(AddSlider(g3, "Speed", cue, "GlowFrequency", { 0.05, 1, 0.05 }, 0.5), "glow")
    manager:Register(AddSlider(g3, "Thickness", cue, "GlowThickness", { 1, 5 }, 0.5), "glow")
    card8:AddRow(g3, Theme.rowHeightLast, 0)
    yOffset = card8:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 9: Sound (cancel icon)
    ----------------------------------------------------------------
    local card9 = GUIFrame:CreateCard(scrollChild, "Sound", yOffset)
    local soundRow = GUIFrame:CreateRow(card9.content, Theme.rowHeightLast)
    local soundDropdown = GUIFrame:CreateDropdown(soundRow, "Sound", {
        options = GUIFrame.BuildSoundOptions(),
        searchable = true,
        value = cue.Sound or "None",
        callback = function(key) cue.Sound = key; ApplySettings() end,
    })
    soundRow:AddWidget(soundDropdown, 0.5)
    manager:Register(soundDropdown, "cue")
    -- y = -12 centers the 28 px button on the dropdown's bar.
    local soundTestBtn = GUIFrame:CreateButton(soundRow, "Test", {
        height = 28,
        callback = function() if EX then EX:TestCueSound() end end,
    })
    soundRow:AddWidget(soundTestBtn, 0.5, nil, 0, -12)
    manager:Register(soundTestBtn, "cue")
    card9:AddRow(soundRow, Theme.rowHeightLast, 0)
    yOffset = card9:GetNextOffset()

    Regray()
    return yOffset
end)
