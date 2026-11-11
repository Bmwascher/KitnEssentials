-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-RestedXPWindow.lua                                  ║
-- ║  GUI: RestedXP, Guide Window tab                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local Rules = KE.RestedXPRules
local ipairs, pairs = ipairs, pairs

GUIFrame.RestedXPTabs = GUIFrame.RestedXPTabs or {}

local UNDER_TITLE_OPTIONS = {
    { key = "bar", text = "Progress Bar" },
    { key = "rule", text = "Line" },
    { key = "none", text = "Nothing" },
}
local SKIP_OPTIONS = {
    { key = "shift", text = "Shift-click" },
    { key = "click", text = "Click" },
    { key = "off", text = "Off" },
}
local WINDOW_COLOR_OPTIONS = {
    { key = "accent", text = "From the Accent" },
    { key = "custom", text = "Custom" },
}
local CUSTOM_COLORS = {
    { label = "Title", key = "ColorTitle", default = { 1, 1, 1, 1 } },
    { label = "Text", key = "ColorText", default = { 1, 1, 1, 1 } },
    { label = "Line", key = "ColorLine", default = { 1, 1, 1, 0.28 } },
    -- Step Box Opacity owns this color's alpha.
    { label = "Step Box", key = "ColorBox", default = { 0.031, 0.031, 0.031, 1 }, noOpacity = true },
    { label = "Border", key = "ColorBorder", default = { 0, 0, 0, 1 } },
    { label = "Bar", key = "ColorBarFill", default = { 1, 0, 0.549, 1 } },
    { label = "Bar Background", key = "ColorBarBack", default = { 1, 1, 1, 0.28 } },
}

local function FontOptions()
    local list = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do list[name] = name end
    else
        list["Expressway"] = "Expressway"
    end
    return KE:AddFollowGlobalFont(list)
end

-- Shadow is this window's own choice on top of the shared outline list.
local function OutlineOptions()
    local list = { { key = "shadow", text = "Shadow" } }
    for _, option in ipairs(KE:GetFontOutlineOptions()) do list[#list + 1] = option end
    return list
end

local function AddShowIn(scrollChild, yOffset, page)
    local db, manager = page.db, page.manager
    local card = GUIFrame:CreateCard(scrollChild, "Show In", yOffset)
    manager:Register(card, "all")
    manager:RegisterGroup(card:AddCheckboxGrid({
        { label = "Open World", config = { value = db.ShowOpenWorld ~= false, callback = page.Setter("ShowOpenWorld") } },
        { label = "Dungeons", config = { value = db.ShowDungeons ~= false, callback = page.Setter("ShowDungeons") } },
        { label = "Raids", config = { value = db.ShowRaids == true, callback = page.Setter("ShowRaids") } },
        { label = "Battlegrounds and Arenas", config = { value = db.ShowPvP == true, callback = page.Setter("ShowPvP") } },
    }), "all")
    page.Separator(card)
    local row = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local fade = GUIFrame:CreateSlider(row, "Fade in Combat, percent", {
        min = 0, max = 100, step = 5,
        value = db.CombatFade or 50,
        callback = page.Setter("CombatFade"),
    })
    row:AddWidget(fade, 1)
    manager:Register(fade, "all")
    card:AddRow(row, Theme.rowHeightLast, 0)
    return card:GetNextOffset()
end

local function AddDisplay(scrollChild, yOffset, page)
    local db, manager = page.db, page.manager
    local card = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card, "all")

    local sizeRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local listed = GUIFrame:CreateSlider(sizeRow, "Listed Steps", {
        min = 0, max = 12, step = 1,
        value = db.ListedSteps or 6,
        callback = page.Setter("ListedSteps"),
    })
    sizeRow:AddWidget(listed, 1 / 2)
    manager:Register(listed, "all")
    local scale = GUIFrame:CreateSlider(sizeRow, "Scale, percent", {
        min = 60, max = 200, step = 5,
        value = db.Scale or 100,
        callback = function(value) KE.RestedXPWindow.SetScale(value) end,
    })
    sizeRow:AddWidget(scale, 1 / 2)
    manager:Register(scale, "all")
    card:AddRow(sizeRow, Theme.rowHeight)

    local dropRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    for _, def in ipairs({
        { label = "Under the Title", key = "UnderTitle", options = UNDER_TITLE_OPTIONS, default = "bar" },
        { label = "Skipping Steps", key = "Skip", options = SKIP_OPTIONS, default = "shift" },
    }) do
        local drop = GUIFrame:CreateDropdown(dropRow, def.label, {
            options = def.options,
            value = db[def.key] or def.default,
            callback = page.Setter(def.key),
        })
        dropRow:AddWidget(drop, 1 / 2)
        manager:Register(drop, "all")
    end
    card:AddRow(dropRow, Theme.rowHeight)

    for i, group in ipairs({
        { { "Yards on the Step Box", "StepYards", true }, { "Flash When the Guide Moves On", "StepFlash", true } },
        { { "Keep the Objective When Folded", "FoldObjective", true }, { "Show Tooltips", "Tips", true } },
        { { "Show the KE Mark", "ShowMark", true }, { "Show Scroll Bar", "ScrollBar", false } },
        { { "Lock Window", "Lock", false }, { "Click a Line's Icon to Skip It", "LineSkip", true } },
    }) do
        local last = i == 4
        local height = last and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(card.content, height)
        for _, def in ipairs(group) do
            local value = db[def[2]]
            if value == nil then value = def[3] end
            local check = GUIFrame:CreateCheckbox(row, def[1], { value = value, callback = page.Setter(def[2]) })
            row:AddWidget(check, 1 / 2)
            manager:Register(check, "all")
        end
        card:AddRow(row, height, last and 0 or nil)
    end
    return card:GetNextOffset()
end

local function AddFont(scrollChild, yOffset, page)
    local db, manager = page.db, page.manager
    local card = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    manager:Register(card, "all")

    local faceRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local face = GUIFrame:CreateDropdown(faceRow, "Font", {
        options = FontOptions(),
        searchable = true,
        value = db.FontFace or KE.FONT_FOLLOW_GLOBAL,
        callback = function(value)
            db.FontFace = KE:StoredFontFace(value)
            page.Apply()
        end,
    })
    faceRow:AddWidget(face, 1 / 2)
    manager:Register(face, "all")
    local outline = GUIFrame:CreateDropdown(faceRow, "Outline", {
        options = OutlineOptions(),
        value = db.FontOutline or "OUTLINE",
        callback = page.Setter("FontOutline"),
    })
    faceRow:AddWidget(outline, 1 / 2)
    manager:Register(outline, "all")
    card:AddRow(faceRow, Theme.rowHeight)

    local sizeRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    for _, def in ipairs({
        { label = "Title Size", key = "TitleSize", min = 10, max = 28, default = 16 },
        { label = "Step Text Size", key = "StepSize", min = 8, max = 24, default = 13 },
        { label = "List Text Size", key = "ListSize", min = 8, max = 24, default = 12 },
    }) do
        local slider = GUIFrame:CreateSlider(sizeRow, def.label, {
            min = def.min, max = def.max, step = 1,
            value = db[def.key] or def.default,
            callback = page.Setter(def.key),
        })
        sizeRow:AddWidget(slider, 1 / 3)
        manager:Register(slider, "all")
    end
    card:AddRow(sizeRow, Theme.rowHeight)
    page.Note(card, "This window doesn't use Slug, so it stays crisp with Slug on elsewhere.")
    return card:GetNextOffset()
end

-- Built here, not by the shared card: its mode dropdown holds other choices. The
-- custom colors take their room only on Custom, so picking a mode rebuilds the page.
local function AddColors(scrollChild, yOffset, page)
    local db, manager = page.db, page.manager
    manager:SetCondition("followSwitch", function() return db.WindowColors ~= "custom" end)
    manager:SetCondition("backgroundColor", function()
        return db.Panel ~= false and not Rules.Washed(db.FollowAccent, db.WindowColors)
    end)
    local card = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card, "all")

    local followRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local follow = GUIFrame:CreateCheckbox(followRow, "Backdrop and Highlights Follow the Accent", {
        value = db.FollowAccent == true,
        callback = page.Setter("FollowAccent"),
    })
    followRow:AddWidget(follow, 1)
    manager:Register(follow, "followSwitch")
    card:AddRow(followRow, Theme.rowHeight)

    local switchRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local panel = GUIFrame:CreateCheckbox(switchRow, "Window Background", {
        value = db.Panel ~= false,
        callback = page.Setter("Panel"),
    })
    switchRow:AddWidget(panel, 1 / 2)
    manager:Register(panel, "all")
    local border = GUIFrame:CreateCheckbox(switchRow, "Window Border", {
        value = db.Border ~= false,
        callback = page.Setter("Border"),
    })
    switchRow:AddWidget(border, 1 / 2)
    manager:Register(border, "all")
    card:AddRow(switchRow, Theme.rowHeight)

    local colorRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local stored = db.PanelColor or { 0.031, 0.031, 0.031, 0.8 }
    local picker = GUIFrame:CreateColorPicker(colorRow, "Background Color", {
        color = { stored[1], stored[2], stored[3], stored[4] },
        callback = function(r, g, b, a)
            db.PanelColor = { r, g, b, a }
            page.ThemeChanged()
        end,
    })
    colorRow:AddWidget(picker, 1 / 2)
    manager:Register(picker, "backgroundColor")
    local opacity = GUIFrame:CreateSlider(colorRow, "Step Box Opacity", {
        min = 0, max = 100, step = 1,
        value = db.BoxOpacity or 55,
        callback = page.Setter("BoxOpacity"),
    })
    colorRow:AddWidget(opacity, 1 / 2)
    manager:Register(opacity, "all")
    card:AddRow(colorRow, Theme.rowHeight)
    page.Separator(card)

    local modeRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local mode = GUIFrame:CreateDropdown(modeRow, "Window Colors", {
        options = WINDOW_COLOR_OPTIONS,
        value = Rules.Option("WindowColors", db.WindowColors),
        callback = function(key)
            db.WindowColors = key
            page.Apply()
            page.Rebuild()
        end,
    })
    modeRow:AddWidget(mode, 1 / 2)
    manager:Register(mode, "all")
    card:AddRow(modeRow, Theme.rowHeight)

    if db.WindowColors ~= "custom" then
        page.Note(card, "Starts on the same color as Chat and the Damage Meter. Choosing " .. KE:Gold("Custom") ..
            " shows seven more colors here.")
        return card:GetNextOffset()
    end

    for i = 1, #CUSTOM_COLORS, 2 do
        local row = GUIFrame:CreateRow(card.content, Theme.rowHeight)
        for slot = i, i + 1 do
            local entry = CUSTOM_COLORS[slot]
            if entry then
                local r, g, b, a = KE:ReadCardColor(db, entry)
                local customPicker = GUIFrame:CreateColorPicker(row, entry.label, {
                    color = { r, g, b, a },
                    noOpacity = entry.noOpacity,
                    callback = function(nr, ng, nb, na)
                        KE:WriteCardColor(db, entry, nr, ng, nb, na)
                        page.Apply()
                    end,
                })
                row:AddWidget(customPicker, 1 / 2)
                manager:Register(customPicker, "all")
            end
        end
        card:AddRow(row, Theme.rowHeight)
    end
    page.Note(card, "Custom replaces the accent's wash, so " ..
        KE:Gold("Backdrop and Highlights Follow the Accent") .. " waits until you choose From the Accent.")
    return card:GetNextOffset()
end

local function AddReset(scrollChild, yOffset, page)
    local card = GUIFrame:CreateCard(scrollChild, "Reset", yOffset)
    page.manager:Register(card, "all")
    local row = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local button = GUIFrame:CreateButton(row, "Reset to Defaults", {
        height = 26,
        callback = function()
            KE:CreatePrompt(
                "Reset RestedXP",
                "Reset this page's window, arrow and color settings to their defaults? RestedXP's own settings " ..
                    "do not change.",
                false, nil, false, nil, nil, nil, nil,
                function()
                    if page.module then page.module:ResetToDefaults() end
                    -- The prompt can outlast this page being in view.
                    if GUIFrame.selectedSidebarItem == "SkinRestedXP" then GUIFrame:RefreshContent() end
                end,
                nil, "Reset", "Cancel")
        end,
    })
    button.text:SetTextColor(0.9, 0.2, 0.2, 1)
    row:AddWidget(button, 1)
    page.manager:Register(button, "all")
    card:AddRow(row, Theme.rowHeightLast, 0)
    return card:GetNextOffset()
end

function GUIFrame.RestedXPTabs.Window(scrollChild, yOffset, page)
    yOffset = AddShowIn(scrollChild, yOffset, page)
    yOffset = AddDisplay(scrollChild, yOffset, page)
    yOffset = AddFont(scrollChild, yOffset, page)
    yOffset = AddColors(scrollChild, yOffset, page)
    return AddReset(scrollChild, yOffset, page)
end
