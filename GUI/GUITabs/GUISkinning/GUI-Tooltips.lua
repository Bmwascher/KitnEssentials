-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Tooltips.lua                                        ║
-- ║  GUI: Blizzard Tooltips                                  ║
-- ║  Purpose: Configuration panel for the Tooltips module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local pairs = pairs
local string_format = string.format

local function AccentText(text)
    local a = KE.Theme.accent
    return string_format("|cff%02x%02x%02x%s|r", a[1] * 255, a[2] * 255, a[3] * 255, text)
end

local SETTINGS_OUTLINE_OPTIONS = {
    { key = "NONE",         text = "None" },
    { key = "OUTLINE",      text = "Outline" },
    { key = "THICKOUTLINE", text = "Thick" },
}

local function GetTooltipsModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinTooltips", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinTooltips", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Tooltips
    if not db then return yOffset end

    local TT = GetTooltipsModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if TT then TT:Refresh() end
    end

    local function ApplyTooltipState(enabled)
        if not TT then return end
        TT.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinTooltips")
        else
            KitnEssentials:DisableModule("SkinTooltips")
        end
    end

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    ----------------------------------------------------------------
    -- Card 1: Enable + Info
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Tooltip Skinning", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Tooltip Skinning", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyTooltipState(checked)
            manager:UpdateAll(checked)
            if not checked then
                KE:CreateReloadPrompt("Enabling Blizzard UI elements requires a reload to take full effect.")
            end
        end,
        msgPopup = true,
        msgText = "Tooltip Skinning",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, Theme.rowHeight)

    local sepRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(sepRow)
    sepRow:AddWidget(sep1, 1)
    card1:AddRow(sepRow, Theme.rowHeightSeparator)

    local textRowSize = 140
    local row1b = GUIFrame:CreateRow(card1.content, textRowSize)
    local ttInfoText = GUIFrame:CreateText(row1b,
        AccentText("Important Tooltip Info"),
        AccentText("- ") ..
        "As of 1/24/2026, Blizzard themselves have issues with tooltip errors. Tooltip skinning by this addon has protected checks so errors are most likely caused by Blizzard.\n\n" ..
        AccentText("These are some common Blizzard errors:\n") ..
        AccentText("- ") .. "Blizzard_SharedXML/Backdrop.lua" .. "\n" ..
        AccentText("- ") .. "Blizzard_MoneyFrame/Mainline/MoneyFrame.lua" .. "\n" ..
        AccentText("- ") .. "Blizzard_SharedXML/Tooltip/TooltipComparisonManager.lua",
        textRowSize, "hide")
    row1b:AddWidget(ttInfoText, 1)
    manager:Register(ttInfoText, "all")
    card1:AddRow(row1b, textRowSize, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: General Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local hideHealthCheck = GUIFrame:CreateCheckbox(row2, "Hide Health Bar", {
        value = db.HideHealthBar ~= false,
        callback = function(checked)
            db.HideHealthBar = checked
            ApplySettings()
            if not checked then
                KE:CreateReloadPrompt("Enabling Blizzard UI elements requires a reload to take full effect.")
            end
        end,
    })
    row2:AddWidget(hideHealthCheck, 1)
    manager:Register(hideHealthCheck, "all")
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position",
        db = db.Position,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        showAnchorFrameType = false,
        showStrata = false,
        onChangeCallback = function()
            if TT and TT.TTAnchor then
                TT.TTAnchor:ClearAllPoints()
                TT.TTAnchor:SetPoint(db.Position.AnchorFrom, UIParent, db.Position.AnchorTo, db.Position.XOffset, db.Position.YOffset)
            end
        end,
    })
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Font Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    manager:Register(card4, "all")

    local rowFont = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local fontDropdown = GUIFrame:CreateDropdown(rowFont, "Font", {
        options = fontList,
        value = db.FontFace or "Expressway",
        callback = function(key)
            db.FontFace = key
            ApplySettings()
        end,
        searchable = true,
        isFontPreview = true,
    })
    rowFont:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "all")

    local outlineDropdown = GUIFrame:CreateDropdown(rowFont, "Outline", {
        options = SETTINGS_OUTLINE_OPTIONS,
        value = db.FontOutline or "OUTLINE",
        callback = function(key)
            db.FontOutline = key
            ApplySettings()
        end,
    })
    rowFont:AddWidget(outlineDropdown, 0.5)
    manager:Register(outlineDropdown, "all")
    card4:AddRow(rowFont, Theme.rowHeight)

    local fontSepRow = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local fontSep = GUIFrame:CreateSeparator(fontSepRow)
    fontSepRow:AddWidget(fontSep, 1)
    card4:AddRow(fontSepRow, Theme.rowHeightSeparator)

    local fontSizeDefs = {
        { key = "NameFontSize",      label = "Player Name Font Size",  default = 17 },
        { key = "GuildFontSize",     label = "Guild Font Size",        default = 14 },
        { key = "RaceLevelFontSize", label = "Race & Level Font Size", default = 14 },
        { key = "SpecFontSize",      label = "Spec Font Size",         default = 14 },
        { key = "FactionFontSize",   label = "Faction Font Size",      default = 14 },
    }

    for i, def in ipairs(fontSizeDefs) do
        local isLast = i == #fontSizeDefs
        local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(card4.content, rowHeight)
        local slider = GUIFrame:CreateSlider(row, def.label, {
            min = 8, max = 72, step = 1,
            value = db[def.key] or def.default,
            labelWidth = 60,
            callback = function(val)
                db[def.key] = val
                ApplySettings()
            end,
        })
        row:AddWidget(slider, 1)
        manager:Register(slider, "all")
        if isLast then
            card4:AddRow(row, rowHeight, 0)
        else
            card4:AddRow(row, rowHeight)
        end
    end

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Backdrop
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local bgColorPicker = GUIFrame:CreateColorPicker(row5a, "Background Color", {
        color = db.BackgroundColor or { 0, 0, 0, 0.8 },
        callback = function(r, g, b, a)
            db.BackgroundColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5a:AddWidget(bgColorPicker, 1)
    manager:Register(bgColorPicker, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local borderColorPicker = GUIFrame:CreateColorPicker(row5b, "Border Color", {
        color = db.BorderColor or { 0, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(borderColorPicker, 0.5)
    manager:Register(borderColorPicker, "all")

    local borderSlider = GUIFrame:CreateSlider(row5b, "Border Size", {
        min = 0, max = 4, step = 1,
        value = db.BorderSize or 1,
        labelWidth = 60,
        callback = function(value)
            db.BorderSize = value
            ApplySettings()
        end,
    })
    row5b:AddWidget(borderSlider, 0.5)
    manager:Register(borderSlider, "all")
    card5:AddRow(row5b, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)
