-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimersBars.lua                               ║
-- ║  Purpose: DT_Bars sidebar page — global bar display      ║
-- ║  settings (texture, font, growth, position).             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local table_insert = table.insert
local ipairs = ipairs
local pairs = pairs

KE.GUI = KE.GUI or {}
KE.GUI.DungeonTimers = KE.GUI.DungeonTimers or {}

local SETTINGS_GROWTH_OPTIONS = {
    { key = "DOWN", text = "Down" },
    { key = "UP",   text = "Up" },
}

local SETTINGS_TEXT_OUTLINE_OPTIONS = {
    { key = "NONE",         text = "None" },
    { key = "OUTLINE",      text = "Outline" },
    { key = "THICKOUTLINE", text = "Thick" },
    { key = "SOFTOUTLINE",  text = "Soft" },
}

local function GetSettingsDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.Dungeons and KE.db.profile.Dungeons.DungeonTimers
end

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DungeonTimers", true)
    end
    return nil
end

local function ApplySettingsChanges()
    local mod = GetModule()
    if not mod then return end
    if mod.UpdateFrameVisuals then
        mod:UpdateFrameVisuals()
    elseif mod.ApplySettings then
        mod:ApplySettings()
    end
end

local function HideBarPreviews()
    local mod = GetModule()
    if mod and mod.HideSettingsBarPreviews then
        mod:HideSettingsBarPreviews()
    end
end

local function ShowSettingsBarPreviews()
    if not GUIFrame or not GUIFrame:IsShown() then return end
    if GUIFrame.selectedSidebarItem ~= "DT_Bars" then return end

    local mod = GetModule()
    if mod and mod.ShowSettingsBarPreviews then
        mod:ShowSettingsBarPreviews()
    end
end

local function RefreshBarPreviews()
    local mod = GetModule()
    if mod and mod.RefreshSettingsBarPreviews then
        mod:RefreshSettingsBarPreviews()
    end
end

KE.GUI.DungeonTimers.HideBarPreviews = HideBarPreviews
GUIFrame.onCloseCallbacks = GUIFrame.onCloseCallbacks or {}
GUIFrame.onCloseCallbacks["DT_Bars"] = HideBarPreviews

GUIFrame:RegisterContent("DT_Bars", function(scrollChild, yOffset)
    local Theme = KE.Theme

    -- Hide other DT preview before showing ours
    local DT_GUI = KE.GUI.DungeonTimers
    if DT_GUI.HideTextPreviews then DT_GUI.HideTextPreviews() end

    local db = GetSettingsDB()
    if not db then return yOffset end
    if not db.BarDisplay then db.BarDisplay = {} end
    if not db.BarGroup then db.BarGroup = {} end

    local isModuleDisabled = db.Enabled == false
    local manager = GUIFrame:CreateWidgetStateManager()

    local LSM = KE.LSM
    local TEXTURE_OPTIONS = {}
    if LSM then
        local textures = LSM:List("statusbar")
        for _, name in ipairs(textures) do
            table_insert(TEXTURE_OPTIONS, { key = name, text = name })
        end
    else
        TEXTURE_OPTIONS = { { key = "KitnUI", text = "KitnUI" } }
    end

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            fontList[name] = name
        end
    else
        fontList["Expressway"] = "Expressway"
    end

    local function ApplyAndUpdate()
        ApplySettingsChanges()
        RefreshBarPreviews()
    end

    ShowSettingsBarPreviews()

    local displayCard = GUIFrame:CreateCard(scrollChild, "Bar Display Settings", yOffset)
    manager:Register(displayCard, "all")

    local row1 = GUIFrame:CreateRow(displayCard.content, Theme.rowHeight)
    local widthSlider = GUIFrame:CreateSlider(row1, "Bar Width", {
        min = 100, max = 400, step = 1,
        value = db.BarDisplay.barWidth or 200,
        labelWidth = 60,
        callback = function(val) db.BarDisplay.barWidth = val; ApplyAndUpdate() end,
    })
    row1:AddWidget(widthSlider, 0.5)

    local heightSlider = GUIFrame:CreateSlider(row1, "Bar Height", {
        min = 12, max = 40, step = 1,
        value = db.BarDisplay.barHeight or 20,
        labelWidth = 60,
        callback = function(val) db.BarDisplay.barHeight = val; ApplyAndUpdate() end,
    })
    row1:AddWidget(heightSlider, 0.5)
    displayCard:AddRow(row1, Theme.rowHeight)

    local row2 = GUIFrame:CreateRow(displayCard.content, Theme.rowHeight)
    local fontDropdown = GUIFrame:CreateDropdown(row2, "Font", {
        options = fontList,
        value = db.BarDisplay.fontFace or "Expressway",
        callback = function(key) db.BarDisplay.fontFace = key; ApplyAndUpdate() end,
        searchable = true,
        isFontPreview = true,
    })
    row2:AddWidget(fontDropdown, 0.5)

    local fontSizeSlider = GUIFrame:CreateSlider(row2, "Font Size", {
        min = 8, max = 24, step = 1,
        value = db.BarDisplay.fontSize or 12,
        labelWidth = 60,
        callback = function(val) db.BarDisplay.fontSize = val; ApplyAndUpdate() end,
    })
    row2:AddWidget(fontSizeSlider, 0.5)
    displayCard:AddRow(row2, Theme.rowHeight)

    local row3 = GUIFrame:CreateRow(displayCard.content, Theme.rowHeight)
    local outlineDropdown = GUIFrame:CreateDropdown(row3, "Font Outline", {
        options = SETTINGS_TEXT_OUTLINE_OPTIONS,
        value = db.BarDisplay.fontOutline or "OUTLINE",
        callback = function(key) db.BarDisplay.fontOutline = key; ApplyAndUpdate() end,
    })
    row3:AddWidget(outlineDropdown, 0.5)

    local textureDropdown = GUIFrame:CreateDropdown(row3, "Bar Texture", {
        options = TEXTURE_OPTIONS,
        value = db.BarDisplay.barTexture or "KitnUI",
        callback = function(key) db.BarDisplay.barTexture = key; ApplyAndUpdate() end,
        searchable = true,
    })
    row3:AddWidget(textureDropdown, 0.5)
    displayCard:AddRow(row3, Theme.rowHeight)

    local row4 = GUIFrame:CreateRow(displayCard.content, Theme.rowHeightLast)
    local iconCheck = GUIFrame:CreateCheckbox(row4, "Show Icon", {
        value = db.BarDisplay.iconEnabled ~= false,
        callback = function(checked) db.BarDisplay.iconEnabled = checked; ApplyAndUpdate() end,
    })
    row4:AddWidget(iconCheck, 1)
    displayCard:AddRow(row4, Theme.rowHeightLast, 0)

    yOffset = displayCard:GetNextOffset()

    local barGroupCard = GUIFrame:CreateCard(scrollChild, "Bar Group", yOffset)
    manager:Register(barGroupCard, "all")

    local barRow1 = GUIFrame:CreateRow(barGroupCard.content, Theme.rowHeightLast)
    local barGrowthDropdown = GUIFrame:CreateDropdown(barRow1, "Growth Direction", {
        options = SETTINGS_GROWTH_OPTIONS,
        value = db.BarGroup.GrowthDirection or "DOWN",
        callback = function(key) db.BarGroup.GrowthDirection = key; ApplyAndUpdate() end,
    })
    barRow1:AddWidget(barGrowthDropdown, 0.5)

    local barSpacingSlider = GUIFrame:CreateSlider(barRow1, "Spacing", {
        min = 0, max = 20, step = 1,
        value = db.BarGroup.Spacing or 2,
        labelWidth = 50,
        callback = function(val) db.BarGroup.Spacing = val; ApplyAndUpdate() end,
    })
    barRow1:AddWidget(barSpacingSlider, 0.5)
    barGroupCard:AddRow(barRow1, Theme.rowHeightLast, 0)

    yOffset = barGroupCard:GetNextOffset()

    db.BarGroup.Position = db.BarGroup.Position or {}

    local barPosCard, barPosYOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Bar Group Position",
        db = db.BarGroup.Position,
        defaults = {
            xOffset = 0,
            yOffset = 100,
            selfPoint = "CENTER",
            anchorPoint = "CENTER",
        },
        showAnchorFrameType = false,
        showStrata = false,
        sliderRange = { -800, 800 },
        onChangeCallback = ApplyAndUpdate,
    })
    manager:Register(barPosCard, "all")
    yOffset = barPosYOffset

    manager:UpdateAll(not isModuleDisabled)

    return yOffset
end)
