-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ImminentDemise.lua                                  ║
-- ║  GUI: Imminent Demise Counter                            ║
-- ║  Purpose: Configuration panel for the ImminentDemise     ║
-- ║           module, a sub-tab of the Warrior tab.          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
-- Absent on WoW Forever, which does not load the module files.
local Rules = KE.ImminentDemiseRules

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("ImminentDemise", true)
end

local MODES = {
    { key = "ICON", text = "Icon" },
    { key = "PIPS", text = "Pips" },
    { key = "TEXT", text = "Text" },
}

local LEGEND = {
    [0] = "No strike counted since the last Sudden Death.",
    [1] = "One strike counted.",
    [2] = "Your next Slayer's Strike gives Sudden Death.",
}

-- The button row is the buttons' height, so the card ends just under it.
local BUTTON_HEIGHT = 26

GUIFrame:RegisterContent("ImminentDemise", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.ImminentDemise
    if not (db and Rules) then return yOffset end

    local ID = GetModule()
    local mode = db.DisplayMode or "ICON"
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("attach", function() return db.AttachToCDM == true end)
    -- Pips with Show Count off draws no text. The mode dropdown rebuilds the
    -- page, so `mode` is fixed.
    manager:SetCondition("countText", function() return mode ~= "PIPS" or db.ShowCount ~= false end)

    local function Regray()
        manager:UpdateAll(true)
    end

    local function ApplySettings()
        if ID then ID:ApplySettings() end
    end
    -- For controls that add or remove rows.
    local function ApplyAndRedraw()
        ApplySettings()
        GUIFrame:RefreshContent()
    end

    -- `regray` is for a box that other controls gray out with.
    local function AddCheckbox(row, label, key, width, regray)
        local box = GUIFrame:CreateCheckbox(row, label, {
            value = db[key] == true,
            callback = function(v)
                db[key] = v
                ApplySettings()
                if regray then Regray() end
            end,
        })
        row:AddWidget(box, width)
        return box
    end

    local function AddSlider(row, label, key, range, width)
        local slider = GUIFrame:CreateSlider(row, label, {
            min = range[1], max = range[2], step = 1, value = db[key],
            callback = function(v) db[key] = v; ApplySettings() end,
        })
        row:AddWidget(slider, width)
        return slider
    end

    local function AddDropdown(row, label, key, options, width)
        local dropdown = GUIFrame:CreateDropdown(row, label, {
            options = options,
            value = db[key],
            callback = function(v) db[key] = v; ApplySettings() end,
        })
        row:AddWidget(dropdown, width)
        return dropdown
    end

    ----------------------------------------------------------------
    -- Card 1: module
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Imminent Demise Counter", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if ID then
            if checked then KitnEssentials:EnableModule("ImminentDemise")
            else KitnEssentials:DisableModule("ImminentDemise") end
        end
    end)
    card1:AddLabel(KE:Gold("Slayer warriors with Imminent Demise only.") .. " Every third Slayer's Strike "
        .. "gives you Sudden Death. This counts your strikes so you see which strike is the one: at 2/3 "
        .. "your next strike gives Sudden Death.\n\n"
        .. "The count is kept by KitnEssentials, since the game does not show it. It starts at 0/3 after a "
        .. "/reload and sets itself right the next time a strike gives Sudden Death.")

    if db.Enabled ~= true then return card1:GetNextOffset() end

    if ID and ID:TalentStatus() then
        card1:AddNote("Imminent Demise known")
    else
        local red = Theme.error
        card1:AddNote(KE:WrapColor("Imminent Demise not known on this character: nothing will show.",
            red[1], red[2], red[3]))
    end

    card1:AddSeparator()
    local buttonRow = GUIFrame:CreateRow(card1.content, BUTTON_HEIGHT)
    buttonRow:AddWidget(GUIFrame:CreateButton(buttonRow, "Test Run", {
        height = BUTTON_HEIGHT,
        tooltip = "Plays 0/3, 1/3, 2/3 and the wrap over 6 s, on any class. Your real count is kept.",
        callback = function() if ID then ID:Test() end end,
    }), 0.5)
    buttonRow:AddWidget(GUIFrame:CreateButton(buttonRow, "Reset Count", {
        height = BUTTON_HEIGHT,
        tooltip = "Sets your real count to 0/3. While this page is open the preview keeps showing 2/3.",
        callback = function() if ID then ID:ResetCount() end end,
    }), 0.5)
    card1:AddRow(buttonRow, BUTTON_HEIGHT, 0)
    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Display Settings: the legend, then only the chosen
    -- mode's options
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    for n = 0, Rules.TOTAL - 1 do
        local r, g, b = KE:ResolveColor(db[Rules.COLOR_KEYS[n]], Rules.COLORS[n])
        card2:AddLabel("|cff" .. KE:RGBAToHex(r, g, b) .. Rules.Text(n) .. "|r  " .. LEGEND[n])
    end
    card2:AddSeparator()
    local modeRow = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    modeRow:AddWidget(GUIFrame:CreateDropdown(modeRow, "Display Mode", {
        options = MODES,
        value = mode,
        callback = function(key) db.DisplayMode = key; ApplyAndRedraw() end,
    }), 0.5)
    AddCheckbox(modeRow, "Hide at 0/3", "HideAtZero", 0.5)
    card2:AddRow(modeRow, Theme.rowHeight)

    if mode == "PIPS" then
        local r1 = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
        AddSlider(r1, "Pip Width", "PipWidth", { 16, 80 }, 0.5)
        AddSlider(r1, "Pip Height", "PipHeight", { 8, 40 }, 0.5)
        card2:AddRow(r1, Theme.rowHeight)
        local r2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
        AddSlider(r2, "Spacing", "PipSpacing", { 0, 10 }, 0.5)
        AddCheckbox(r2, "Show Count", "ShowCount", 0.5, true)
        card2:AddRow(r2, Theme.rowHeightLast, 0)
    elseif mode == "TEXT" then
        local r1 = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
        AddCheckbox(r1, "Attach to Cooldown Manager", "AttachToCDM", 0.5, true)
        manager:Register(AddDropdown(r1, "Position on Icon", "IconPosition",
            GUIFrame.IconPositionOptions, 0.5), "attach")
        card2:AddRow(r1, Theme.rowHeight)
        local r2 = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
        manager:Register(AddSlider(r2, "X Offset", "IconX", { -50, 50 }, 0.5), "attach")
        manager:Register(AddSlider(r2, "Y Offset", "IconY", { -50, 50 }, 0.5), "attach")
        card2:AddRow(r2, Theme.rowHeight)
        card2:AddNote("Add Execute to the Cooldown Manager's Essential or Utility row and the count sits on "
            .. "its icon. Without it, or while the Cooldown Manager is hidden, the count uses the "
            .. KE:Gold("Counter Position") .. " card. With " .. KE:Gold("EllesmereUI") .. "'s Cooldown "
            .. "Manager on, the count goes where that addon draws Blizzard's Execute icon, and hides when "
            .. "it hides it.")
    else
        local r1 = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
        AddSlider(r1, "Icon Size", "IconSize", { 20, 96 }, 0.5)
        AddDropdown(r1, "Count Position", "CountPosition", Rules.SPOT_OPTIONS, 0.5)
        card2:AddRow(r1, Theme.rowHeight)
        local r2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
        AddSlider(r2, "Count Offset X", "CountX", { -40, 40 }, 0.5)
        AddSlider(r2, "Count Offset Y", "CountY", { -40, 40 }, 0.5)
        card2:AddRow(r2, Theme.rowHeightLast, 0)
    end
    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Counter Position
    ----------------------------------------------------------------
    local _, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Counter Position",
        db = db,
        positionKey = "Position",
        dbKeys = {
            selfPoint   = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset     = "XOffset",
            yOffset     = "YOffset",
        },
        showStrata = false,
        onChangeCallback = ApplySettings,
    })
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Font Settings
    ----------------------------------------------------------------
    local _, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontSize    = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 48 },
        onChangeCallback = ApplySettings,
    })
    if fontWidgets then manager:RegisterGroup(fontWidgets, "countText") end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Colors. Each color redraws the legend.
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    local colorRow = GUIFrame:CreateRow(card5.content, 46)
    for n = 0, Rules.TOTAL - 1 do
        local key = Rules.COLOR_KEYS[n]
        colorRow:AddWidget(GUIFrame:CreateColorPicker(colorRow, "Color at " .. Rules.Text(n), {
            color = db[key],
            callback = function(r, g, b, a) db[key] = { r, g, b, a }; ApplyAndRedraw() end,
        }), n == 0 and 0.34 or 0.33)
    end
    card5:AddRow(colorRow, 46, 0)
    yOffset = card5:GetNextOffset()

    Regray()
    return yOffset
end)
