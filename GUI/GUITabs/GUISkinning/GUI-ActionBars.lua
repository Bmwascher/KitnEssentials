-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ActionBars.lua                                      ║
-- ║  GUI: Action Bars                                        ║
-- ║  Purpose: Configuration panel for the ActionBars module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local table_insert = table.insert
local ipairs = ipairs
local pairs = pairs
local CreateFrame = CreateFrame

local currentSubTab = "global"
local cachedTabBar = nil
local cachedTabButtons = nil
local currentManager = nil

local SUB_TABS = {
    { id = "global",   text = "Global" },
    { id = "position", text = "General & Position" },
    { id = "text",     text = "Texts" },
    { id = "backdrop", text = "Backdrop" },
}

local TAB_BAR_HEIGHT = 28

local BAR_LIST = {
    { key = "Bar1",      text = "Action Bar 1" },
    { key = "Bar2",      text = "Action Bar 2" },
    { key = "Bar3",      text = "Action Bar 3" },
    { key = "Bar4",      text = "Action Bar 4" },
    { key = "Bar5",      text = "Action Bar 5" },
    { key = "Bar6",      text = "Action Bar 6" },
    { key = "Bar7",      text = "Action Bar 7" },
    { key = "Bar8",      text = "Action Bar 8" },
    { key = "PetBar",    text = "Pet Bar" },
    { key = "StanceBar", text = "Stance Bar" },
}

local BAR_LIST_KV = {}
for _, bar in ipairs(BAR_LIST) do
    BAR_LIST_KV[bar.key] = bar.text
end

local ANCHOR_OPTIONS = {
    { key = "TOPLEFT",     text = "Top Left" },
    { key = "TOP",         text = "Top" },
    { key = "TOPRIGHT",    text = "Top Right" },
    { key = "LEFT",        text = "Left" },
    { key = "CENTER",      text = "Center" },
    { key = "RIGHT",       text = "Right" },
    { key = "BOTTOMLEFT",  text = "Bottom Left" },
    { key = "BOTTOM",      text = "Bottom" },
    { key = "BOTTOMRIGHT", text = "Bottom Right" },
}

local OUTLINE_OPTIONS = {
    { key = "NONE",         text = "None" },
    { key = "OUTLINE",      text = "Outline" },
    { key = "THICKOUTLINE", text = "Thick" },
}

local LAYOUT_OPTIONS = {
    { key = "HORIZONTAL", text = "Horizontal" },
    { key = "VERTICAL",   text = "Vertical" },
}

local GROWTH_OPTIONS = {
    { key = "RIGHT", text = "Grow Right" },
    { key = "LEFT",  text = "Grow Left" },
}

local function GetActionBarsModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinActionBars", true)
    end
    return nil
end

local function GetActionBarsDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.Skinning.ActionBars
end

local function GetCurrentBarKey()
    local db = GetActionBarsDB()
    if not db then return "Bar1" end
    local curEdit = db.currentEdit or "Bar1"
    if not db.Bars[curEdit] then curEdit = "Bar1" end
    return curEdit
end

local function GetCurrentBarDB()
    local db = GetActionBarsDB()
    if not db then return nil end
    return db.Bars[GetCurrentBarKey()]
end

local function ApplyFonts()
    local SK = GetActionBarsModule()
    if SK then SK:UpdateSettings("fonts") end
end

local function ApplyProfTextures()
    local SK = GetActionBarsModule()
    if SK then SK:UpdateSettings("profTextures") end
end

local function ApplyBarSettings()
    local SK = GetActionBarsModule()
    local curEdit = GetCurrentBarKey()
    if SK then
        SK:UpdateSettings("layout", curEdit)
        SK:UpdateSettings("positions", curEdit)
        SK:UpdateSettings("mouseover", curEdit)
        SK:UpdateSettings("fonts")
        SK:UpdateSettings("backdrops", curEdit)
    end
end

local function ApplyAllBars()
    local SK = GetActionBarsModule()
    if SK then SK:UpdateSettings("all") end
end

local function ApplyActionBarsState(enabled)
    local SK = GetActionBarsModule()
    if not SK then return end
    local db = GetActionBarsDB()
    if db then db.Enabled = enabled end
    if enabled then
        KitnEssentials:EnableModule("SkinActionBars")
    else
        KitnEssentials:DisableModule("SkinActionBars")
    end
end

local function UpdateAllWidgetStates()
    if not currentManager then return end
    local db = GetActionBarsDB()
    if not db then return end
    currentManager:UpdateAll(db.Enabled ~= false)
end

local function CreateTabManager()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("bar", function()
        local barDB = GetCurrentBarDB()
        return barDB and barDB.Enabled ~= false
    end)
    return manager
end

----------------------------------------------------------------
-- Sub-Tab: Global Settings
----------------------------------------------------------------
local function RenderGlobalTab(scrollChild, yOffset, activeCards)
    local db = GetActionBarsDB()
    if not db then return yOffset end

    local manager = CreateTabManager()
    currentManager = manager

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    ----------------------------------------------------------------
    -- Card 1: ActionBars Master Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Action Bars", yOffset)
    table_insert(activeCards, card1)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Action Bars Skinning", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyActionBarsState(checked)
            UpdateAllWidgetStates()
            KE:CreateReloadPrompt("Enabling/Disabling Action Bars requires a reload to take full effect.")
        end,
        msgPopup = true,
        msgText = "Action Bars",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: General Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    table_insert(activeCards, card2)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local hideProfCheck = GUIFrame:CreateCheckbox(row2, "Hide Profession Texture", {
        value = db.HideProfTexture == true,
        callback = function(checked)
            db.HideProfTexture = checked
            ApplyProfTextures()
        end,
    })
    row2:AddWidget(hideProfCheck, 0.5)
    manager:Register(hideProfCheck, "all")

    local hideMacroCheck = GUIFrame:CreateCheckbox(row2, "Hide Macro Text", {
        value = db.HideMacroText == true,
        callback = function(checked)
            db.HideMacroText = checked
            ApplyFonts()
        end,
    })
    row2:AddWidget(hideMacroCheck, 0.5)
    manager:Register(hideMacroCheck, "all")
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Global Font Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Global Font Settings", yOffset)
    table_insert(activeCards, card3)
    manager:Register(card3, "all")

    db.FontSizes = db.FontSizes or {}

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local fontDropdown = GUIFrame:CreateDropdown(row3a, "Font", {
        options = fontList,
        value = db.FontFace,
        callback = function(key)
            db.FontFace = key
            ApplyFonts()
        end,
        searchable = true,
        isFontPreview = true,
    })
    row3a:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "all")

    local outlineDropdown = GUIFrame:CreateDropdown(row3a, "Outline", {
        options = OUTLINE_OPTIONS,
        value = db.FontOutline or "OUTLINE",
        callback = function(key)
            db.FontOutline = key
            ApplyFonts()
        end,
    })
    row3a:AddWidget(outlineDropdown, 0.5)
    manager:Register(outlineDropdown, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3sep = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    row3sep:AddWidget(GUIFrame:CreateSeparator(row3sep), 1)
    card3:AddRow(row3sep, Theme.rowHeightSeparator)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local keybindSize = GUIFrame:CreateSlider(row3b, "Keybind Size", {
        min = 6, max = 24, step = 1,
        value = db.FontSizes.KeybindSize or 12,
        callback = function(val)
            db.FontSizes.KeybindSize = val
            ApplyFonts()
        end,
    })
    row3b:AddWidget(keybindSize, 0.5)
    manager:Register(keybindSize, "all")

    local cooldownSize = GUIFrame:CreateSlider(row3b, "Cooldown Size", {
        min = 6, max = 24, step = 1,
        value = db.FontSizes.CooldownSize or 14,
        callback = function(val)
            db.FontSizes.CooldownSize = val
            ApplyFonts()
        end,
    })
    row3b:AddWidget(cooldownSize, 0.5)
    manager:Register(cooldownSize, "all")
    card3:AddRow(row3b, Theme.rowHeight)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local chargeSize = GUIFrame:CreateSlider(row3c, "Charge Size", {
        min = 6, max = 24, step = 1,
        value = db.FontSizes.ChargeSize or 12,
        callback = function(val)
            db.FontSizes.ChargeSize = val
            ApplyFonts()
        end,
    })
    row3c:AddWidget(chargeSize, 0.5)
    manager:Register(chargeSize, "all")

    local macroSize = GUIFrame:CreateSlider(row3c, "Macro Size", {
        min = 6, max = 24, step = 1,
        value = db.FontSizes.MacroSize or 10,
        callback = function(val)
            db.FontSizes.MacroSize = val
            ApplyFonts()
        end,
    })
    row3c:AddWidget(macroSize, 0.5)
    manager:Register(macroSize, "all")
    card3:AddRow(row3c, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Global Mouseover Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Global Mouseover Settings", yOffset)
    table_insert(activeCards, card4)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local globalMouseoverCheck = GUIFrame:CreateCheckbox(row4a, "Enable Global Mouseover", {
        value = db.Mouseover and db.Mouseover.Enabled == true,
        callback = function(checked)
            db.Mouseover = db.Mouseover or {}
            db.Mouseover.Enabled = checked
            ApplyAllBars()
        end,
    })
    row4a:AddWidget(globalMouseoverCheck, 0.5)
    manager:Register(globalMouseoverCheck, "all")

    local mouseoverOverrideCheck = GUIFrame:CreateCheckbox(row4a, "Override When Mounted/Vehicle", {
        value = db.MouseoverOverride == true,
        callback = function(checked)
            db.MouseoverOverride = checked
            local SK = GetActionBarsModule()
            if SK then SK:UpdateBonusBarOverride() end
        end,
    })
    row4a:AddWidget(mouseoverOverrideCheck, 0.5)
    manager:Register(mouseoverOverrideCheck, "all")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4sep = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    row4sep:AddWidget(GUIFrame:CreateSeparator(row4sep), 1)
    card4:AddRow(row4sep, Theme.rowHeightSeparator)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local globalAlpha = GUIFrame:CreateSlider(row4b, "Fade Out Alpha", {
        min = 0, max = 1, step = 0.05,
        value = db.Mouseover and db.Mouseover.Alpha or 0,
        callback = function(val)
            db.Mouseover = db.Mouseover or {}
            db.Mouseover.Alpha = val
            ApplyAllBars()
        end,
    })
    row4b:AddWidget(globalAlpha, 1)
    manager:Register(globalAlpha, "all")
    card4:AddRow(row4b, Theme.rowHeight)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local fadeIn = GUIFrame:CreateSlider(row4c, "Fade In Duration", {
        min = 0, max = 2, step = 0.1,
        value = db.Mouseover and db.Mouseover.FadeInDuration or 0.3,
        callback = function(val)
            db.Mouseover = db.Mouseover or {}
            db.Mouseover.FadeInDuration = val
            ApplyAllBars()
        end,
    })
    row4c:AddWidget(fadeIn, 0.5)
    manager:Register(fadeIn, "all")

    local fadeOut = GUIFrame:CreateSlider(row4c, "Fade Out Duration", {
        min = 0, max = 2, step = 0.1,
        value = db.Mouseover and db.Mouseover.FadeOutDuration or 1,
        callback = function(val)
            db.Mouseover = db.Mouseover or {}
            db.Mouseover.FadeOutDuration = val
            ApplyAllBars()
        end,
    })
    row4c:AddWidget(fadeOut, 0.5)
    manager:Register(fadeOut, "all")
    card4:AddRow(row4c, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Bar Enable/Disable
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Bar Enable/Disable", yOffset)
    table_insert(activeCards, card5)
    manager:Register(card5, "all")

    local barIndex = 1
    local numRows = math.ceil(#BAR_LIST / 2)
    local rowsAdded = 0
    while barIndex <= #BAR_LIST do
        rowsAdded = rowsAdded + 1
        local isLast = rowsAdded == numRows
        local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(card5.content, rowHeight)

        local bar1 = BAR_LIST[barIndex]
        if bar1 then
            local barDB1 = db.Bars[bar1.key]
            local check1 = GUIFrame:CreateCheckbox(row, bar1.text, {
                value = barDB1 and barDB1.Enabled ~= false,
                callback = function(checked)
                    if db.Bars[bar1.key] then
                        db.Bars[bar1.key].Enabled = checked
                        local SK = GetActionBarsModule()
                        if SK then SK:UpdateSettings("enabled", bar1.key) end
                        if checked then
                            KE:CreateReloadPrompt("Enabling bars requires a reload to take full effect.")
                        end
                    end
                end,
            })
            row:AddWidget(check1, 0.5)
            manager:Register(check1, "all")
        end

        barIndex = barIndex + 1
        local bar2 = BAR_LIST[barIndex]
        if bar2 then
            local barDB2 = db.Bars[bar2.key]
            local check2 = GUIFrame:CreateCheckbox(row, bar2.text, {
                value = barDB2 and barDB2.Enabled ~= false,
                callback = function(checked)
                    if db.Bars[bar2.key] then
                        db.Bars[bar2.key].Enabled = checked
                        local SK = GetActionBarsModule()
                        if SK then SK:UpdateSettings("enabled", bar2.key) end
                        if checked then
                            KE:CreateReloadPrompt("Enabling bars requires a reload to take full effect.")
                        end
                    end
                end,
            })
            row:AddWidget(check2, 0.5)
            manager:Register(check2, "all")
        end

        if isLast then
            card5:AddRow(row, rowHeight, 0)
        else
            card5:AddRow(row, rowHeight)
        end
        barIndex = barIndex + 1
    end

    yOffset = card5:GetNextOffset()

    UpdateAllWidgetStates()
    return yOffset
end

----------------------------------------------------------------
-- Sub-Tab: Position Settings
----------------------------------------------------------------
local function RenderPositionTab(scrollChild, yOffset, activeCards)
    local db = GetActionBarsDB()
    if not db then return yOffset end

    local manager = CreateTabManager()
    currentManager = manager

    local curEdit = GetCurrentBarKey()
    local barDB = GetCurrentBarDB()

    ----------------------------------------------------------------
    -- Card 1: Bar Selection
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Select Bar", yOffset)
    table_insert(activeCards, card1)
    manager:Register(card1, "all")

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local barDropdown = GUIFrame:CreateDropdown(row1, "Select Bar to Edit", {
        options = BAR_LIST_KV,
        value = curEdit,
        callback = function(key)
            db.currentEdit = key
            C_Timer.After(0.2, function()
                GUIFrame:RefreshContent()
            end)
        end,
    })
    row1:AddWidget(barDropdown, 1)
    manager:Register(barDropdown, "all")
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Layout Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild,
        "Layout: " .. "|cffFFFFFF" .. (BAR_LIST_KV[curEdit] or curEdit) .. "|r", yOffset)
    table_insert(activeCards, card2)
    manager:Register(card2, "bar")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local buttonSizeSlider = GUIFrame:CreateSlider(row2a, "Button Size", {
        min = 20, max = 80, step = 1,
        value = barDB and barDB.ButtonSize or 40,
        callback = function(val)
            local bdb = GetCurrentBarDB()
            if bdb then bdb.ButtonSize = val end
            ApplyBarSettings()
        end,
    })
    row2a:AddWidget(buttonSizeSlider, 0.5)
    manager:Register(buttonSizeSlider, "bar")

    local spacingSlider = GUIFrame:CreateSlider(row2a, "Spacing", {
        min = 0, max = 20, step = 1,
        value = barDB and barDB.Spacing or 1,
        callback = function(val)
            local bdb = GetCurrentBarDB()
            if bdb then bdb.Spacing = val end
            ApplyBarSettings()
        end,
    })
    row2a:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "bar")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local totalButtonsSlider = GUIFrame:CreateSlider(row2b, "Total Buttons", {
        min = 1, max = 12, step = 1,
        value = barDB and barDB.TotalButtons or 12,
        callback = function(val)
            local bdb = GetCurrentBarDB()
            if bdb then bdb.TotalButtons = val end
            ApplyBarSettings()
        end,
    })
    row2b:AddWidget(totalButtonsSlider, 0.5)
    manager:Register(totalButtonsSlider, "bar")

    local buttonsPerLineSlider = GUIFrame:CreateSlider(row2b, "Buttons Per Line", {
        min = 1, max = 12, step = 1,
        value = barDB and barDB.ButtonsPerLine or 12,
        callback = function(val)
            local bdb = GetCurrentBarDB()
            if bdb then bdb.ButtonsPerLine = val end
            ApplyBarSettings()
        end,
    })
    row2b:AddWidget(buttonsPerLineSlider, 0.5)
    manager:Register(buttonsPerLineSlider, "bar")
    card2:AddRow(row2b, Theme.rowHeight)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local layoutDropdown = GUIFrame:CreateDropdown(row2c, "Layout Direction", {
        options = LAYOUT_OPTIONS,
        value = barDB and barDB.Layout or "HORIZONTAL",
        callback = function(key)
            local bdb = GetCurrentBarDB()
            if bdb then bdb.Layout = key end
            ApplyBarSettings()
        end,
    })
    row2c:AddWidget(layoutDropdown, 0.5)
    manager:Register(layoutDropdown, "bar")

    local growthDropdown = GUIFrame:CreateDropdown(row2c, "Growth Direction", {
        options = GROWTH_OPTIONS,
        value = barDB and barDB.GrowthDirection or "RIGHT",
        callback = function(key)
            local bdb = GetCurrentBarDB()
            if bdb then bdb.GrowthDirection = key end
            ApplyBarSettings()
        end,
    })
    row2c:AddWidget(growthDropdown, 0.5)
    manager:Register(growthDropdown, "bar")
    card2:AddRow(row2c, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position: " .. "|cffFFFFFF" .. (BAR_LIST_KV[curEdit] or curEdit) .. "|r",
        db = barDB and barDB.Position or {},
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        showAnchorFrameType = false,
        showStrata = false,
        onChangeCallback = ApplyBarSettings,
    })
    table_insert(activeCards, posCard)
    manager:Register(posCard, "bar")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Mouseover Settings (Per-Bar)
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild,
        "Mouseover: " .. "|cffFFFFFF" .. (BAR_LIST_KV[curEdit] or curEdit) .. "|r", yOffset)
    table_insert(activeCards, card4)
    manager:Register(card4, "bar")

    if barDB then barDB.Mouseover = barDB.Mouseover or {} end

    local useGlobalMouseover = barDB and barDB.Mouseover and barDB.Mouseover.GlobalOverride == true

    local row4a = GUIFrame:CreateRow(card4.content, useGlobalMouseover and Theme.rowHeightLast or Theme.rowHeight)
    local useGlobalMouseoverCheck = GUIFrame:CreateCheckbox(row4a, "Use Global Mouseover", {
        value = barDB and barDB.Mouseover and barDB.Mouseover.GlobalOverride == true,
        callback = function(checked)
            local bdb = GetCurrentBarDB()
            if bdb then
                bdb.Mouseover = bdb.Mouseover or {}
                bdb.Mouseover.GlobalOverride = checked
            end
            ApplyBarSettings()
            C_Timer.After(0.2, function() GUIFrame:RefreshContent() end)
        end,
    })
    row4a:AddWidget(useGlobalMouseoverCheck, 0.5)
    manager:Register(useGlobalMouseoverCheck, "bar")

    local barMouseoverCheck = GUIFrame:CreateCheckbox(row4a, "Enable Mouseover", {
        value = barDB and barDB.Mouseover and barDB.Mouseover.Enabled == true,
        callback = function(checked)
            local bdb = GetCurrentBarDB()
            if bdb then
                bdb.Mouseover = bdb.Mouseover or {}
                bdb.Mouseover.Enabled = checked
            end
            ApplyBarSettings()
        end,
    })
    row4a:AddWidget(barMouseoverCheck, 0.5)
    manager:Register(barMouseoverCheck, "bar")

    if useGlobalMouseover then
        card4:AddRow(row4a, Theme.rowHeightLast, 0)
    else
        card4:AddRow(row4a, Theme.rowHeight)

        local row4sep = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
        row4sep:AddWidget(GUIFrame:CreateSeparator(row4sep), 1)
        card4:AddRow(row4sep, Theme.rowHeightSeparator)

        local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
        local barAlpha = GUIFrame:CreateSlider(row4b, "Fade Out Alpha", {
            min = 0, max = 1, step = 0.05,
            value = barDB and barDB.Mouseover and barDB.Mouseover.Alpha or 0,
            callback = function(val)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.Mouseover = bdb.Mouseover or {}
                    bdb.Mouseover.Alpha = val
                end
                ApplyBarSettings()
            end,
        })
        row4b:AddWidget(barAlpha, 1)
        manager:Register(barAlpha, "bar")
        card4:AddRow(row4b, Theme.rowHeightLast, 0)
    end

    yOffset = card4:GetNextOffset()

    UpdateAllWidgetStates()
    return yOffset
end

----------------------------------------------------------------
-- Sub-Tab: Text Settings
----------------------------------------------------------------
local function RenderTextTab(scrollChild, yOffset, activeCards)
    local db = GetActionBarsDB()
    if not db then return yOffset end

    local manager = CreateTabManager()
    currentManager = manager

    local curEdit = GetCurrentBarKey()
    local barDB = GetCurrentBarDB()

    ----------------------------------------------------------------
    -- Card 1: Bar Selection
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Select Bar", yOffset)
    table_insert(activeCards, card1)
    manager:Register(card1, "all")

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local barDropdown = GUIFrame:CreateDropdown(row1, "Select Bar to Edit", {
        options = BAR_LIST_KV,
        value = curEdit,
        callback = function(key)
            db.currentEdit = key
            C_Timer.After(0.2, function()
                GUIFrame:RefreshContent()
            end)
        end,
    })
    row1:AddWidget(barDropdown, 1)
    manager:Register(barDropdown, "all")
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Global Override Toggle
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild,
        "Text Settings: " .. "|cffFFFFFF" .. (BAR_LIST_KV[curEdit] or curEdit) .. "|r", yOffset)
    table_insert(activeCards, card2)
    manager:Register(card2, "bar")

    if barDB then
        barDB.FontSizes = barDB.FontSizes or {}
        barDB.TextPositions = barDB.TextPositions or {}
    end

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local useGlobalFontCheck = GUIFrame:CreateCheckbox(row2a, "Use Global Font Sizes", {
        value = barDB and barDB.FontSizes and barDB.FontSizes.GlobalOverride == true,
        callback = function(checked)
            local bdb = GetCurrentBarDB()
            if bdb then
                bdb.FontSizes = bdb.FontSizes or {}
                bdb.FontSizes.GlobalOverride = checked
            end
            ApplyBarSettings()
            C_Timer.After(0.2, function() GUIFrame:RefreshContent() end)
        end,
    })
    row2a:AddWidget(useGlobalFontCheck, 0.5)
    manager:Register(useGlobalFontCheck, "bar")

    local useGlobalPosCheck = GUIFrame:CreateCheckbox(row2a, "Use Global Text Positions", {
        value = barDB and barDB.TextPositions and barDB.TextPositions.GlobalOverride == true,
        callback = function(checked)
            local bdb = GetCurrentBarDB()
            if bdb then
                bdb.TextPositions = bdb.TextPositions or {}
                bdb.TextPositions.GlobalOverride = checked
            end
            ApplyBarSettings()
            C_Timer.After(0.2, function() GUIFrame:RefreshContent() end)
        end,
    })
    row2a:AddWidget(useGlobalPosCheck, 0.5)
    manager:Register(useGlobalPosCheck, "bar")
    card2:AddRow(row2a, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Per-Bar Font Sizes (only if not using global)
    ----------------------------------------------------------------
    local useGlobalFonts = barDB and barDB.FontSizes and barDB.FontSizes.GlobalOverride == true
    if not useGlobalFonts then
        local card3 = GUIFrame:CreateCard(scrollChild,
            "Font Sizes: " .. "|cffFFFFFF" .. (BAR_LIST_KV[curEdit] or curEdit) .. "|r", yOffset)
        table_insert(activeCards, card3)
        manager:Register(card3, "bar")

        local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        local barKeybindSize = GUIFrame:CreateSlider(row3a, "Keybind Size", {
            min = 6, max = 24, step = 1,
            value = barDB and barDB.FontSizes and barDB.FontSizes.KeybindSize or 12,
            callback = function(val)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.FontSizes = bdb.FontSizes or {}
                    bdb.FontSizes.KeybindSize = val
                end
                ApplyBarSettings()
            end,
        })
        row3a:AddWidget(barKeybindSize, 0.5)
        manager:Register(barKeybindSize, "bar")

        local barCooldownSize = GUIFrame:CreateSlider(row3a, "Cooldown Size", {
            min = 6, max = 24, step = 1,
            value = barDB and barDB.FontSizes and barDB.FontSizes.CooldownSize or 14,
            callback = function(val)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.FontSizes = bdb.FontSizes or {}
                    bdb.FontSizes.CooldownSize = val
                end
                ApplyBarSettings()
            end,
        })
        row3a:AddWidget(barCooldownSize, 0.5)
        manager:Register(barCooldownSize, "bar")
        card3:AddRow(row3a, Theme.rowHeight)

        local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
        local barChargeSize = GUIFrame:CreateSlider(row3b, "Charge Size", {
            min = 6, max = 24, step = 1,
            value = barDB and barDB.FontSizes and barDB.FontSizes.ChargeSize or 12,
            callback = function(val)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.FontSizes = bdb.FontSizes or {}
                    bdb.FontSizes.ChargeSize = val
                end
                ApplyBarSettings()
            end,
        })
        row3b:AddWidget(barChargeSize, 0.5)
        manager:Register(barChargeSize, "bar")

        local barMacroSize = GUIFrame:CreateSlider(row3b, "Macro Size", {
            min = 6, max = 24, step = 1,
            value = barDB and barDB.FontSizes and barDB.FontSizes.MacroSize or 10,
            callback = function(val)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.FontSizes = bdb.FontSizes or {}
                    bdb.FontSizes.MacroSize = val
                end
                ApplyBarSettings()
            end,
        })
        row3b:AddWidget(barMacroSize, 0.5)
        manager:Register(barMacroSize, "bar")
        card3:AddRow(row3b, Theme.rowHeightLast, 0)

        yOffset = card3:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 4: Per-Bar Text Positions (only if not using global)
    ----------------------------------------------------------------
    local useGlobalPos = barDB and barDB.TextPositions and barDB.TextPositions.GlobalOverride == true
    if not useGlobalPos then
        local card4 = GUIFrame:CreateCard(scrollChild,
            "Text Positions: " .. "|cffFFFFFF" .. (BAR_LIST_KV[curEdit] or curEdit) .. "|r", yOffset)
        table_insert(activeCards, card4)
        manager:Register(card4, "bar")

        local tp = barDB and barDB.TextPositions or {}

        -- Keybind Position
        local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
        local keybindAnchor = GUIFrame:CreateDropdown(row4a, "Keybind Anchor", {
            options = ANCHOR_OPTIONS,
            value = tp.KeybindAnchor or "TOPRIGHT",
            callback = function(key)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.TextPositions = bdb.TextPositions or {}
                    bdb.TextPositions.KeybindAnchor = key
                end
                ApplyBarSettings()
            end,
        })
        row4a:AddWidget(keybindAnchor, 0.34)
        manager:Register(keybindAnchor, "bar")

        local keybindX = GUIFrame:CreateSlider(row4a, "X", {
            min = -20, max = 20, step = 1,
            value = tp.KeybindXOffset or -2,
            labelWidth = 30,
            callback = function(val)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.TextPositions = bdb.TextPositions or {}
                    bdb.TextPositions.KeybindXOffset = val
                end
                ApplyBarSettings()
            end,
        })
        row4a:AddWidget(keybindX, 0.33)
        manager:Register(keybindX, "bar")

        local keybindY = GUIFrame:CreateSlider(row4a, "Y", {
            min = -20, max = 20, step = 1,
            value = tp.KeybindYOffset or -2,
            labelWidth = 30,
            callback = function(val)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.TextPositions = bdb.TextPositions or {}
                    bdb.TextPositions.KeybindYOffset = val
                end
                ApplyBarSettings()
            end,
        })
        row4a:AddWidget(keybindY, 0.33)
        manager:Register(keybindY, "bar")
        card4:AddRow(row4a, Theme.rowHeight)

        local row4sep1 = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
        row4sep1:AddWidget(GUIFrame:CreateSeparator(row4sep1), 1)
        card4:AddRow(row4sep1, Theme.rowHeightSeparator)

        -- Charge Position
        local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
        local chargeAnchor = GUIFrame:CreateDropdown(row4b, "Charge Anchor", {
            options = ANCHOR_OPTIONS,
            value = tp.ChargeAnchor or "BOTTOMRIGHT",
            callback = function(key)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.TextPositions = bdb.TextPositions or {}
                    bdb.TextPositions.ChargeAnchor = key
                end
                ApplyBarSettings()
            end,
        })
        row4b:AddWidget(chargeAnchor, 0.34)
        manager:Register(chargeAnchor, "bar")

        local chargeX = GUIFrame:CreateSlider(row4b, "X", {
            min = -20, max = 20, step = 1,
            value = tp.ChargeXOffset or -2,
            labelWidth = 30,
            callback = function(val)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.TextPositions = bdb.TextPositions or {}
                    bdb.TextPositions.ChargeXOffset = val
                end
                ApplyBarSettings()
            end,
        })
        row4b:AddWidget(chargeX, 0.33)
        manager:Register(chargeX, "bar")

        local chargeY = GUIFrame:CreateSlider(row4b, "Y", {
            min = -20, max = 20, step = 1,
            value = tp.ChargeYOffset or 2,
            labelWidth = 30,
            callback = function(val)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.TextPositions = bdb.TextPositions or {}
                    bdb.TextPositions.ChargeYOffset = val
                end
                ApplyBarSettings()
            end,
        })
        row4b:AddWidget(chargeY, 0.33)
        manager:Register(chargeY, "bar")
        card4:AddRow(row4b, Theme.rowHeight)

        local row4sep2 = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
        row4sep2:AddWidget(GUIFrame:CreateSeparator(row4sep2), 1)
        card4:AddRow(row4sep2, Theme.rowHeightSeparator)

        -- Macro Position
        local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
        local macroAnchor = GUIFrame:CreateDropdown(row4c, "Macro Anchor", {
            options = ANCHOR_OPTIONS,
            value = tp.MacroAnchor or "BOTTOM",
            callback = function(key)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.TextPositions = bdb.TextPositions or {}
                    bdb.TextPositions.MacroAnchor = key
                end
                ApplyBarSettings()
            end,
        })
        row4c:AddWidget(macroAnchor, 0.34)
        manager:Register(macroAnchor, "bar")

        local macroX = GUIFrame:CreateSlider(row4c, "X", {
            min = -20, max = 20, step = 1,
            value = tp.MacroXOffset or 0,
            labelWidth = 30,
            callback = function(val)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.TextPositions = bdb.TextPositions or {}
                    bdb.TextPositions.MacroXOffset = val
                end
                ApplyBarSettings()
            end,
        })
        row4c:AddWidget(macroX, 0.33)
        manager:Register(macroX, "bar")

        local macroY = GUIFrame:CreateSlider(row4c, "Y", {
            min = -20, max = 20, step = 1,
            value = tp.MacroYOffset or -2,
            labelWidth = 30,
            callback = function(val)
                local bdb = GetCurrentBarDB()
                if bdb then
                    bdb.TextPositions = bdb.TextPositions or {}
                    bdb.TextPositions.MacroYOffset = val
                end
                ApplyBarSettings()
            end,
        })
        row4c:AddWidget(macroY, 0.33)
        manager:Register(macroY, "bar")
        card4:AddRow(row4c, Theme.rowHeightLast, 0)

        yOffset = card4:GetNextOffset()
    end

    UpdateAllWidgetStates()
    return yOffset
end

----------------------------------------------------------------
-- Sub-Tab: Backdrop Settings
----------------------------------------------------------------
local function RenderBackdropTab(scrollChild, yOffset, activeCards)
    local db = GetActionBarsDB()
    if not db then return yOffset end

    local manager = CreateTabManager()
    currentManager = manager

    local curEdit = GetCurrentBarKey()
    local barDB = GetCurrentBarDB()

    ----------------------------------------------------------------
    -- Card 1: Bar Selection
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Select Bar", yOffset)
    table_insert(activeCards, card1)
    manager:Register(card1, "all")

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local barDropdown = GUIFrame:CreateDropdown(row1, "Select Bar to Edit", {
        options = BAR_LIST_KV,
        value = curEdit,
        callback = function(key)
            db.currentEdit = key
            C_Timer.After(0.2, function()
                GUIFrame:RefreshContent()
            end)
        end,
    })
    row1:AddWidget(barDropdown, 1)
    manager:Register(barDropdown, "all")
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Backdrop Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild,
        "Backdrop: " .. "|cffFFFFFF" .. (BAR_LIST_KV[curEdit] or curEdit) .. "|r", yOffset)
    table_insert(activeCards, card2)
    manager:Register(card2, "bar")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local hideEmptyCheck = GUIFrame:CreateCheckbox(row2a, "Hide Empty Backdrops", {
        value = barDB and barDB.HideEmptyBackdrops == true,
        callback = function(checked)
            local bdb = GetCurrentBarDB()
            if bdb then bdb.HideEmptyBackdrops = checked end
            ApplyBarSettings()
        end,
    })
    row2a:AddWidget(hideEmptyCheck, 1)
    manager:Register(hideEmptyCheck, "bar")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2sep = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    row2sep:AddWidget(GUIFrame:CreateSeparator(row2sep), 1)
    card2:AddRow(row2sep, Theme.rowHeightSeparator)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local backdropColor = GUIFrame:CreateColorPicker(row2b, "Backdrop Color", {
        color = barDB and barDB.BackdropColor or { 0, 0, 0, 0.8 },
        callback = function(r, g, b, a)
            local bdb = GetCurrentBarDB()
            if bdb then bdb.BackdropColor = { r, g, b, a } end
            ApplyBarSettings()
        end,
    })
    row2b:AddWidget(backdropColor, 0.5)
    manager:Register(backdropColor, "bar")

    local borderColor = GUIFrame:CreateColorPicker(row2b, "Border Color", {
        color = barDB and barDB.BorderColor or { 0, 0, 0, 1 },
        callback = function(r, g, b, a)
            local bdb = GetCurrentBarDB()
            if bdb then bdb.BorderColor = { r, g, b, a } end
            ApplyBarSettings()
        end,
    })
    row2b:AddWidget(borderColor, 0.5)
    manager:Register(borderColor, "bar")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    UpdateAllWidgetStates()
    return yOffset
end

----------------------------------------------------------------
-- Create ActionBars Panel (with secondary tab bar)
----------------------------------------------------------------
local function CreateActionBarsPanel(container)
    local panel = CreateFrame("Frame", nil, container)
    panel:SetAllPoints()

    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetHeight(TAB_BAR_HEIGHT)
    tabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)

    local tabBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBarBg:SetAllPoints()
    tabBarBg:SetColorTexture(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)

    local tabBarBorder = tabBar:CreateTexture(nil, "ARTWORK")
    tabBarBorder:SetHeight(1)
    tabBarBorder:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    tabBarBorder:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    tabBarBorder:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    cachedTabBar = tabBar

    local scrollbarWidth = Theme.scrollbarWidth or 16
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -1)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    if scrollFrame.ScrollBar then
        local sb = scrollFrame.ScrollBar
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -(TAB_BAR_HEIGHT + Theme.paddingSmall + 13))
        sb:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, Theme.paddingSmall + 13)
        sb:SetWidth(scrollbarWidth - 4)

        if sb.Background then sb.Background:Hide() end
        if sb.Top then sb.Top:Hide() end
        if sb.Middle then sb.Middle:Hide() end
        if sb.Bottom then sb.Bottom:Hide() end
        if sb.trackBG then sb.trackBG:Hide() end
        if sb.ScrollUpButton then sb.ScrollUpButton:Hide() end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:SetAlpha(0)

        local isSnapping = false
        local PIXEL_STEP = 8 / 15
        sb:HookScript("OnValueChanged", function(self, value)
            if isSnapping then return end
            local scale = scrollFrame:GetEffectiveScale()
            local screenPixels = value * scale
            local snappedPixels = math.floor(screenPixels / PIXEL_STEP + 0.5) * PIXEL_STEP
            local snappedValue = snappedPixels / scale
            if math.abs(value - snappedValue) > 0.001 then
                isSnapping = true
                self:SetValue(snappedValue)
                isSnapping = false
            end
        end)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local scrollbarVisible = false
    local baseWidth = Theme.contentWidth

    local function UpdateScrollChildWidth()
        if scrollbarVisible then
            scrollChild:SetWidth(baseWidth - scrollbarWidth)
        else
            scrollChild:SetWidth(baseWidth)
        end
    end

    local function UpdateScrollBarVisibility()
        if scrollFrame.ScrollBar then
            local contentHeight = scrollChild:GetHeight()
            local frameHeight = scrollFrame:GetHeight()
            local needsScrollbar = contentHeight > frameHeight

            scrollbarVisible = needsScrollbar
            scrollFrame.ScrollBar:SetAlpha(needsScrollbar and 1 or 0)
            UpdateScrollChildWidth()
        end
    end

    UpdateScrollChildWidth()

    scrollFrame:HookScript("OnScrollRangeChanged", UpdateScrollBarVisibility)
    scrollChild:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
    scrollFrame:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
    scrollFrame:HookScript("OnShow", function()
        C_Timer.After(0, UpdateScrollBarVisibility)
    end)

    local activeCards = {}

    local function UpdateCardWidths()
        local newWidth = scrollChild:GetWidth()
        for _, card in ipairs(activeCards) do
            if card and card.SetWidth then
                card:SetWidth(newWidth)
            end
        end
    end

    scrollChild:HookScript("OnSizeChanged", function(self, width, height)
        UpdateCardWidths()
    end)

    local function RenderContentIntoScrollChild(tabId)
        currentManager = nil
        for i = #activeCards, 1, -1 do
            activeCards[i] = nil
        end

        for _, child in ipairs({ scrollChild:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end

        for _, region in ipairs({ scrollChild:GetRegions() }) do
            if region:GetObjectType() == "FontString" or region:GetObjectType() == "Texture" then
                region:Hide()
            end
        end

        local yOffset = Theme.paddingMedium

        if tabId == "global" then
            yOffset = RenderGlobalTab(scrollChild, yOffset, activeCards)
        elseif tabId == "position" then
            yOffset = RenderPositionTab(scrollChild, yOffset, activeCards)
        elseif tabId == "text" then
            yOffset = RenderTextTab(scrollChild, yOffset, activeCards)
        elseif tabId == "backdrop" then
            yOffset = RenderBackdropTab(scrollChild, yOffset, activeCards)
        end

        scrollChild:SetHeight(yOffset + Theme.paddingLarge)
    end

    local function UpdateTabVisuals(buttons, selectedId)
        for _, btn in ipairs(buttons) do
            if btn.tabId == selectedId then
                btn.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                btn.underline:Show()
                btn.selectedOverlay:Show()
            else
                btn.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
                btn.underline:Hide()
                btn.selectedOverlay:Hide()
            end
        end
    end

    local tabButtons = {}
    local minPadding = Theme.paddingMedium * 2
    local totalTextWidth = 0

    for i, tabDef in ipairs(SUB_TABS) do
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetHeight(TAB_BAR_HEIGHT)
        btn.tabId = tabDef.id
        btn.tabIndex = i

        local hoverBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        hoverBg:SetAllPoints()
        hoverBg:SetColorTexture(1, 1, 1, 0.05)
        hoverBg:Hide()
        btn.hoverBg = hoverBg

        local selectedOverlay = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
        selectedOverlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        selectedOverlay:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        selectedOverlay:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.1)
        selectedOverlay:Hide()
        btn.selectedOverlay = selectedOverlay

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(label, "small")
        else
            label:SetFontObject("GameFontNormalSmall")
        end
        label:SetText(tabDef.text)
        label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        btn.label = label

        local textWidth = label:GetStringWidth()
        btn.textWidth = textWidth
        totalTextWidth = totalTextWidth + textWidth

        local underline = btn:CreateTexture(nil, "OVERLAY")
        underline:SetHeight(2)
        underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        underline:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        underline:Hide()
        btn.underline = underline

        btn:SetScript("OnEnter", function(self)
            if currentSubTab ~= self.tabId then
                self.hoverBg:Show()
            end
        end)

        btn:SetScript("OnLeave", function(self)
            self.hoverBg:Hide()
        end)

        btn:SetScript("OnClick", function(self)
            if currentSubTab ~= self.tabId then
                currentSubTab = self.tabId
                UpdateTabVisuals(cachedTabButtons, currentSubTab)
                RenderContentIntoScrollChild(currentSubTab)
            end
        end)

        table_insert(tabButtons, btn)
    end

    cachedTabButtons = tabButtons

    local function LayoutTabs(barWidth)
        if barWidth <= 0 then return end

        local numTabs = #tabButtons
        local totalMinWidth = totalTextWidth + (minPadding * numTabs)
        local extraSpace = math.max(0, barWidth - totalMinWidth)
        local extraPerTab = extraSpace / numTabs

        local xOffset = 0
        for _, btn in ipairs(tabButtons) do
            local tabWidth = btn.textWidth + minPadding + extraPerTab

            btn:ClearAllPoints()
            btn:SetPoint("TOP", tabBar, "TOP", 0, 0)
            btn:SetPoint("BOTTOM", tabBar, "BOTTOM", 0, 0)
            btn:SetPoint("LEFT", tabBar, "LEFT", xOffset, 0)
            btn:SetWidth(tabWidth)

            xOffset = xOffset + tabWidth
        end
    end

    LayoutTabs(tabBar:GetWidth())

    tabBar:SetScript("OnSizeChanged", function(self, width, height)
        LayoutTabs(width)
    end)

    UpdateTabVisuals(tabButtons, currentSubTab)
    RenderContentIntoScrollChild(currentSubTab)
    UpdateAllWidgetStates()

    return panel
end

----------------------------------------------------------------
-- Register Content (takes over content area with panel)
----------------------------------------------------------------
GUIFrame:RegisterContent("SkinActionBars", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end

    if GUIFrame.pendingContext then
        local ctx = GUIFrame.pendingContext
        local db = GetActionBarsDB()
        if db and BAR_LIST_KV[ctx] then
            db.currentEdit = ctx
            currentSubTab = "position"
        end
        GUIFrame.pendingContext = nil
    end

    if GUIFrame.contentArea and GUIFrame.contentArea.scrollFrame then
        GUIFrame.contentArea.scrollFrame:Hide()
    end

    local panel = CreateActionBarsPanel(GUIFrame.contentArea)
    GUIFrame.contentArea._customPanel = panel

    return yOffset
end)
