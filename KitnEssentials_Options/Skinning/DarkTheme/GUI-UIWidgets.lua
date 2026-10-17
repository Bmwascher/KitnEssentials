-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-UIWidgets.lua                                        ║
-- ║  GUI: UI Widgets                                          ║
-- ║  Purpose: Configuration panel for the                     ║
-- ║           UIWidgets module.                                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM

-- Localization Setup
local pairs = pairs
local table_insert = table.insert
local table_sort = table.sort

local OUTLINE_OPTIONS = KE:GetFontOutlineOptions()

GUIFrame:RegisterContent("SkinBlizzardFramesWidgets", function(scrollChild, yOffset)
    -- As a nested tab a nil return would reach the outer builder, which then
    -- draws a placeholder over the header card and tab strips.
    if KE:ShouldNotLoadModule() then return yOffset end
    local db = KE.db and KE.db.profile.Skinning.UIWidgets
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    -- Apply settings through module
    local function ApplySettings()
        local UIW = KitnEssentials:GetModule("UIWidgets", true)
        if UIW and UIW:IsEnabled() then UIW:ApplySettings() end
    end

    local barDB = db.StatusBar
    local textDB = db.TextWidget
    local tcDB = db.TopCenter

    -- The same test UIW.FontSizeForRole applies before a size is used.
    manager:SetCondition("barlabel", function()
        return barDB.Enabled ~= false and barDB.StyleLabel ~= false
    end)
    manager:SetCondition("bartext", function()
        return barDB.Enabled ~= false and barDB.StyleBarText ~= false
    end)
    -- The module draws the fill, backdrop and border only while StripTextures is on.
    manager:SetCondition("striptex", function()
        return barDB.Enabled ~= false and barDB.StripTextures ~= false
    end)
    manager:SetCondition("topcenter", function()
        return tcDB.Enabled == true
    end)

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    -- Build font list
    local function GetFontList()
        local fontList = {}
        if LSM then
            for name in pairs(LSM:HashTable("font")) do
                table_insert(fontList, { key = name, text = name })
            end
            table_sort(fontList, function(a, b) return a.text < b.text end)
        else
            table_insert(fontList, { key = "Friz Quadrata TT", text = "Friz Quadrata TT" })
        end
        return fontList
    end
    local fontList = GetFontList()

    ----------------------------------------------------------------
    -- Card 1: UI Widgets
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "UI Widgets", yOffset)

    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        if not checked then KE:FlagReloadNeeded() end -- un-skin needs /reload
        if checked then
            KitnEssentials:EnableModule("UIWidgets")
            ApplySettings()
        else
            KitnEssentials:DisableModule("UIWidgets")
        end
        RefreshStates()
    end)

    -- Lone header bar: settings only render while the module is enabled.
    if db.Enabled == false then return card1:GetNextOffset() end

    card1:AddLabel("Restyles Blizzard's status bar and text widgets (M+ timer, power bars, event banners) and spell icons.")
    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Font
    ----------------------------------------------------------------
    local cardFont = GUIFrame:CreateCard(scrollChild, "Font", yOffset)
    manager:Register(cardFont, "all")

    local rowFace = GUIFrame:CreateRow(cardFont.content, Theme.rowHeight)
    local fontDropdown = GUIFrame:CreateDropdown(rowFace, "Font", {
        options = KE:AddFollowGlobalFont(fontList),
        value = db.FontFace or KE.FONT_FOLLOW_GLOBAL,
        callback = function(key)
            db.FontFace = KE:StoredFontFace(key)
            ApplySettings()
        end,
        searchable = true,
        isFontPreview = true
    })
    rowFace:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "all")

    local outlineDropdown = GUIFrame:CreateDropdown(rowFace, "Outline", {
        options = OUTLINE_OPTIONS,
        value = KE:NormalizeFontOutline(db.FontOutline or "OUTLINE"),
        callback = function(key)
            db.FontOutline = key
            ApplySettings()
        end
    })
    rowFace:AddWidget(outlineDropdown, 0.5)
    manager:Register(outlineDropdown, "all")
    cardFont:AddRow(rowFace, Theme.rowHeight)

    local rowSizes = GUIFrame:CreateRow(cardFont.content, Theme.rowHeightLast)
    local labelSizeSlider = GUIFrame:CreateSlider(rowSizes, "Bar Label Size", {
        min = 8,
        max = 24,
        step = 1,
        value = barDB.LabelSize or 14,
        callback = function(val)
            barDB.LabelSize = val
            ApplySettings()
        end
    })
    rowSizes:AddWidget(labelSizeSlider, 0.5)
    manager:Register(labelSizeSlider, "barlabel")

    local barTextSizeSlider = GUIFrame:CreateSlider(rowSizes, "Bar Text Size", {
        min = 8,
        max = 24,
        step = 1,
        value = barDB.BarTextSize or 12,
        callback = function(val)
            barDB.BarTextSize = val
            ApplySettings()
        end
    })
    rowSizes:AddWidget(barTextSizeSlider, 0.5)
    manager:Register(barTextSizeSlider, "bartext")
    cardFont:AddRow(rowSizes, Theme.rowHeightLast, 0)

    yOffset = cardFont:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Status Bars
    ----------------------------------------------------------------
    local cardBars = GUIFrame:CreateCard(scrollChild, "Status Bars", yOffset)
    manager:Register(cardBars, "all")
    cardBars:AddHeaderToggle(barDB.Enabled ~= false, function(checked)
        barDB.Enabled = checked
        if not checked then KE:FlagReloadNeeded() end -- un-skin needs /reload
        ApplySettings()
    end)

    if barDB.Enabled ~= false then
        local rowStyle = GUIFrame:CreateRow(cardBars.content, Theme.rowHeight)
        local styleLabelCheck = GUIFrame:CreateCheckbox(rowStyle, "Restyle Bar Label", {
            value = barDB.StyleLabel ~= false,
            callback = function(checked)
                barDB.StyleLabel = checked
                ApplySettings()
                RefreshStates()
            end,
        })
        rowStyle:AddWidget(styleLabelCheck, 0.34)
        manager:Register(styleLabelCheck, "all")

        local styleBarTextCheck = GUIFrame:CreateCheckbox(rowStyle, "Restyle Bar Text", {
            value = barDB.StyleBarText ~= false,
            callback = function(checked)
                barDB.StyleBarText = checked
                ApplySettings()
                RefreshStates()
            end,
        })
        rowStyle:AddWidget(styleBarTextCheck, 0.33)
        manager:Register(styleBarTextCheck, "all")

        local stripTexturesCheck = GUIFrame:CreateCheckbox(rowStyle, "Flat Bar + Backdrop", {
            value = barDB.StripTextures ~= false,
            callback = function(checked)
                barDB.StripTextures = checked
                if not checked then KE:FlagReloadNeeded() end -- un-skin needs /reload
                ApplySettings()
                RefreshStates()
            end,
        })
        rowStyle:AddWidget(stripTexturesCheck, 0.33)
        manager:Register(stripTexturesCheck, "all")
        cardBars:AddRow(rowStyle, Theme.rowHeight)

        local statusbarList = {}
        if LSM then
            for name in pairs(LSM:HashTable("statusbar")) do statusbarList[name] = name end
        else
            statusbarList["KitnUI"] = "KitnUI"
        end

        local rowLook = GUIFrame:CreateRow(cardBars.content, Theme.rowHeight)
        local barTextureDropdown = GUIFrame:CreateDropdown(rowLook, "Bar Texture", {
            options = statusbarList,
            value = barDB.BarTexture or "KitnUI",
            callback = function(key)
                barDB.BarTexture = key
                ApplySettings()
            end,
            searchable = true,
        })
        rowLook:AddWidget(barTextureDropdown, 0.34)
        manager:Register(barTextureDropdown, "striptex")

        local backdropColorPicker = GUIFrame:CreateColorPicker(rowLook, "Backdrop", {
            color = barDB.BackdropColor,
            callback = function(r, g, b, a)
                barDB.BackdropColor = { r, g, b, a }
                ApplySettings()
            end
        })
        rowLook:AddWidget(backdropColorPicker, 0.33)
        manager:Register(backdropColorPicker, "striptex")

        local borderColorPicker = GUIFrame:CreateColorPicker(rowLook, "Border", {
            color = barDB.BorderColor,
            callback = function(r, g, b, a)
                barDB.BorderColor = { r, g, b, a }
                ApplySettings()
            end
        })
        rowLook:AddWidget(borderColorPicker, 0.33)
        manager:Register(borderColorPicker, "striptex")
        cardBars:AddRow(rowLook, Theme.rowHeight)

        local rowWidth = GUIFrame:CreateRow(cardBars.content, Theme.rowHeightLast)
        local barWidthSlider = GUIFrame:CreateSlider(rowWidth, "Fixed Bar Width (0 = Blizzard's)", {
            min = 0,
            max = 400,
            step = 1,
            value = barDB.Width or 0,
            tooltip = "Fixed bar width. Blizzard resizes the bar on every update and the width is put back a moment later, so a non-zero value can flicker. 0 keeps Blizzard's size.",
            callback = function(val)
                barDB.Width = val
                ApplySettings()
            end
        })
        rowWidth:AddWidget(barWidthSlider, 0.5)
        manager:Register(barWidthSlider, "all")
        cardBars:AddRow(rowWidth, Theme.rowHeightLast, 0)
    end

    yOffset = cardBars:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Text Widgets
    ----------------------------------------------------------------
    -- One switch over two keys, since either one off leaves the text
    -- unstyled. On sets both, so a profile with only StyleText off does
    -- not read off again after the rebuild.
    local textOn = textDB.Enabled ~= false and textDB.StyleText ~= false
    local cardText = GUIFrame:CreateCard(scrollChild, "Text Widgets", yOffset)
    manager:Register(cardText, "all")
    cardText:AddHeaderToggle(textOn, function(checked)
        if checked then
            textDB.Enabled = true
            textDB.StyleText = true
        else
            textDB.Enabled = false
            KE:FlagReloadNeeded() -- un-skin needs /reload
        end
        ApplySettings()
    end)

    if textOn then
        local rowText = GUIFrame:CreateRow(cardText.content, Theme.rowHeightLast)
        local textSizeSlider = GUIFrame:CreateSlider(rowText, "Text Size", {
            min = 8,
            max = 24,
            step = 1,
            value = textDB.Size or 17,
            tooltip = "Smallest size for text widgets. Text Blizzard draws larger keeps its own size, and any icon in it keeps its size too.",
            callback = function(val)
                textDB.Size = val
                ApplySettings()
            end
        })
        rowText:AddWidget(textSizeSlider, 0.5)
        manager:Register(textSizeSlider, "all")

        local centerTextCheck = GUIFrame:CreateCheckbox(rowText, "Center Text", {
            value = textDB.CenterText ~= false,
            callback = function(checked)
                textDB.CenterText = checked
                ApplySettings()
            end,
        })
        rowText:AddWidget(centerTextCheck, 0.5)
        manager:Register(centerTextCheck, "all")
        cardText:AddRow(rowText, Theme.rowHeightLast, 0)
    end

    yOffset = cardText:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Spell Icons (its switch is the whole card)
    ----------------------------------------------------------------
    local cardIcons = GUIFrame:CreateCard(scrollChild, "Spell Icons", yOffset)
    manager:Register(cardIcons, "all")
    cardIcons:AddHeaderToggle(db.SkinIcons ~= false, function(checked)
        db.SkinIcons = checked
        if not checked then KE:FlagReloadNeeded() end -- un-skin needs /reload
        ApplySettings()
    end)

    yOffset = cardIcons:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Top-Center Container
    ----------------------------------------------------------------
    local function ApplyTopCenter()
        local UIW = KitnEssentials:GetModule("UIWidgets", true)
        if UIW and UIW:IsEnabled() then UIW:ApplyTopCenter() end
    end

    local cardTC = GUIFrame:CreateCard(scrollChild, "Top-Center Container", yOffset)
    manager:Register(cardTC, "all")
    cardTC:AddHeaderToggle(tcDB.Enabled == true, function(checked)
        tcDB.Enabled = checked
        ApplyTopCenter()
        if KE.EditMode then KE.EditMode:RefreshLiveState() end
    end)

    if tcDB.Enabled == true then
        cardTC:AddLabel("Moves, scales or hides the top-center widget container (M+ objective line, delve and event bars) in every zone.")

        local rowTC = GUIFrame:CreateRow(cardTC.content, Theme.rowHeightLast)
        local tcHideCheck = GUIFrame:CreateCheckbox(rowTC, "Hide (All Zones)", {
            value = tcDB.Hide == true,
            callback = function(checked)
                tcDB.Hide = checked
                ApplyTopCenter()
            end,
        })
        rowTC:AddWidget(tcHideCheck, 0.5)
        manager:Register(tcHideCheck, "all")

        local tcScaleSlider = GUIFrame:CreateSlider(rowTC, "Scale", {
            min = 0.5, max = 2.0, step = 0.05,
            value = tcDB.Scale or 1.0,
            callback = function(val)
                tcDB.Scale = val
                ApplyTopCenter()
            end,
        })
        rowTC:AddWidget(tcScaleSlider, 0.5)
        manager:Register(tcScaleSlider, "all")
        cardTC:AddRow(rowTC, Theme.rowHeightLast, 0)
    end

    yOffset = cardTC:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Top-Center Position
    ----------------------------------------------------------------
    -- db is the TopCenter sub-table, so the card's root keys
    -- (anchorFrameType/ParentFrame/Strata) land there, not on the module root.
    local tcPosCard, tcPosOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Top-Center Position",
        db = tcDB,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplyTopCenter,
    })

    if tcPosCard.positionWidgets then
        manager:RegisterGroup(tcPosCard.positionWidgets, "topcenter")
    end
    manager:Register(tcPosCard, "topcenter")
    yOffset = tcPosOffset

    RefreshStates()
    return yOffset
end)
