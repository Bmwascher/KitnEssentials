-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimersTexts.lua                              ║
-- ║  Purpose: DTimers_Texts sidebar page — global text       ║
-- ║  display settings (font, alignment, growth, position).   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

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

local SETTINGS_TEXT_ALIGN_OPTIONS = {
    { key = "LEFT",   text = "Left" },
    { key = "CENTER", text = "Center" },
    { key = "RIGHT",  text = "Right" },
}

local function GetSettingsDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.DungeonTimers
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
    if mod.ApplySettings then
        mod:ApplySettings()
    end
end

local function HideTextPreviews()
    local mod = GetModule()
    if mod and mod.HideSettingsTextPreviews then
        mod:HideSettingsTextPreviews()
    end
end

local function ShowSettingsTextPreviews()
    if not GUIFrame or not GUIFrame:IsShown() then return end
    if GUIFrame.selectedSidebarItem ~= "DTimers_Texts" then return end
    local mod = GetModule()
    if mod and mod.ShowSettingsTextPreviews then
        mod:ShowSettingsTextPreviews()
    end
end

local function RefreshTextPreviews()
    local mod = GetModule()
    if mod and mod.RefreshSettingsTextPreviews then
        mod:RefreshSettingsTextPreviews()
    end
end

KE.GUI.DungeonTimers.HideTextPreviews = HideTextPreviews
GUIFrame.onCloseCallbacks = GUIFrame.onCloseCallbacks or {}
GUIFrame.onCloseCallbacks["DTimers_Texts"] = HideTextPreviews

GUIFrame:RegisterContent("DTimers_Texts", function(scrollChild, yOffset)
    local Theme = KE.Theme

    -- Hide the sibling bar previews when this page activates.
    local DT_GUI = KE.GUI.DungeonTimers
    if DT_GUI.HideBarPreviews then DT_GUI.HideBarPreviews() end

    local db = GetSettingsDB()
    if not db then return yOffset end

    if not db.TextDisplay then db.TextDisplay = {} end
    if not db.TextGroup then db.TextGroup = {} end

    local isModuleDisabled = db.Enabled == false
    local manager = GUIFrame:CreateWidgetStateManager()

    local LSM = KE.LSM
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
        RefreshTextPreviews()
    end

    ShowSettingsTextPreviews()

    local displayCard = GUIFrame:CreateCard(scrollChild, "Text Display Settings", yOffset)
    manager:Register(displayCard, "all")

    local row1 = GUIFrame:CreateRow(displayCard.content, Theme.rowHeight)
    local fontDropdown = GUIFrame:CreateDropdown(row1, "Font", {
        options = fontList,
        value = db.TextDisplay.fontFace or "Expressway",
        callback = function(key) db.TextDisplay.fontFace = key; ApplyAndUpdate() end,
        searchable = true,
        isFontPreview = true,
    })
    row1:AddWidget(fontDropdown, 0.5)

    local fontSizeSlider = GUIFrame:CreateSlider(row1, "Font Size", {
        min = 8, max = 32, step = 1,
        value = db.TextDisplay.fontSize or 14,
        labelWidth = 60,
        callback = function(val) db.TextDisplay.fontSize = val; ApplyAndUpdate() end,
    })
    row1:AddWidget(fontSizeSlider, 0.5)
    displayCard:AddRow(row1, Theme.rowHeight)

    local row2 = GUIFrame:CreateRow(displayCard.content, Theme.rowHeightLast)
    local outlineDropdown = GUIFrame:CreateDropdown(row2, "Font Outline", {
        options = SETTINGS_TEXT_OUTLINE_OPTIONS,
        value = db.TextDisplay.fontOutline or "SOFTOUTLINE",
        callback = function(key) db.TextDisplay.fontOutline = key; ApplyAndUpdate() end,
    })
    row2:AddWidget(outlineDropdown, 0.5)

    local alignDropdown = GUIFrame:CreateDropdown(row2, "Text Align", {
        options = SETTINGS_TEXT_ALIGN_OPTIONS,
        value = db.TextDisplay.textAlign or "CENTER",
        callback = function(key)
            local freshDb = GetSettingsDB()
            if freshDb and freshDb.TextDisplay then
                freshDb.TextDisplay.textAlign = key
            end
            ApplyAndUpdate()
        end,
    })
    row2:AddWidget(alignDropdown, 0.5)
    displayCard:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = displayCard:GetNextOffset()

    local textGroupCard = GUIFrame:CreateCard(scrollChild, "Text Group", yOffset)
    manager:Register(textGroupCard, "all")

    local textRow1 = GUIFrame:CreateRow(textGroupCard.content, Theme.rowHeight)
    local textGrowthDropdown = GUIFrame:CreateDropdown(textRow1, "Growth Direction", {
        options = SETTINGS_GROWTH_OPTIONS,
        value = db.TextGroup.GrowthDirection or "DOWN",
        callback = function(key) db.TextGroup.GrowthDirection = key; ApplyAndUpdate() end,
    })
    textRow1:AddWidget(textGrowthDropdown, 0.5)

    local textSpacingSlider = GUIFrame:CreateSlider(textRow1, "Spacing", {
        min = 0, max = 20, step = 1,
        value = db.TextGroup.Spacing or 0,
        labelWidth = 50,
        callback = function(val) db.TextGroup.Spacing = val; ApplyAndUpdate() end,
    })
    textRow1:AddWidget(textSpacingSlider, 0.5)
    textGroupCard:AddRow(textRow1, Theme.rowHeight)

    local textRow2 = GUIFrame:CreateRow(textGroupCard.content, Theme.rowHeightLast)
    local textShowSlider = GUIFrame:CreateSlider(textRow2, "Reveal at (s remaining)", {
        min = 0, max = 30, step = 1,
        value = db.TextGroup.ShowAtSeconds or 0,
        labelWidth = 140,
        callback = function(val) db.TextGroup.ShowAtSeconds = val; ApplyAndUpdate() end,
    })
    textRow2:AddWidget(textShowSlider, 1)
    textGroupCard:AddRow(textRow2, Theme.rowHeightLast, 0)

    yOffset = textGroupCard:GetNextOffset()

    local textPosCard, textPosYOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Text Group Position",
        db = db.TextGroup,
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
        sliderRange = { -800, 800 },
        onChangeCallback = ApplyAndUpdate,
    })
    if textPosCard.positionWidgets then
        manager:RegisterGroup(textPosCard.positionWidgets, "all")
    end
    manager:Register(textPosCard, "all")
    yOffset = textPosYOffset

    manager:UpdateAll(not isModuleDisabled)

    return yOffset
end)
