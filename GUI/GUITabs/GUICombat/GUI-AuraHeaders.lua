-- One builder, two pages. Both drive aura engine displays
-- (Modules/Combat/AuraHeaders.lua), so the options are identical apart
-- from the debuff-only school-colour toggle.
--
-- There are deliberately NO sorting options: this feature is skinning, and
-- the header is fixed to Blizzard's own order. Spacing is the one layout
-- control that earns its place.
---@class KE
local KE = select(2, ...)

local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM

local table_insert = table.insert
local ipairs, pairs = ipairs, pairs

local function BuildPage(opts)
    GUIFrame:RegisterContent(opts.contentID, function(scrollChild, yOffset)
        local db = KE.db and KE.db.profile[opts.dbKey]
        if not db then
            local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
            errorCard:AddLabel("Database not available")
            return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
        end

        local allWidgets = {}
        local subCards = {}
        local decimalBelow

        local function ApplySettings()
            local mod = KitnEssentials and KitnEssentials:GetModule(opts.moduleName, true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end

        local function UpdateAllWidgetStates()
            local enabled = db.Enabled == true
            for _, c in ipairs(subCards) do
                if c.SetAlpha then c:SetAlpha(enabled and 1 or 0.4) end
            end
            for _, w in ipairs(allWidgets) do
                if w.SetEnabled then w:SetEnabled(enabled) end
            end
        end

        --------------------------------------------------------------
        -- Card 1: Master Enable
        --------------------------------------------------------------
        local card1 = GUIFrame:CreateCard(scrollChild, opts.title, yOffset)
        card1:AddHeaderToggle(db.Enabled == true, function(checked)
            db.Enabled = checked
            if checked then
                KitnEssentials:EnableModule(opts.moduleName)
            else
                KitnEssentials:DisableModule(opts.moduleName)
            end
            GUIFrame:RefreshContent()
            -- Both directions need a reload: enabling has to hide Blizzard's
            -- frame before ours takes over, and disabling cannot revive it
            -- mid-session. Without this the user is left with no auras at all.
            KE:CreateReloadPrompt("This change needs a UI reload to take effect.")
        end)
        card1:AddLabel(opts.blurb)

        if db.Enabled ~= true then
            return yOffset + card1:GetContentHeight() + Theme.paddingSmall
        end
        yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

        --------------------------------------------------------------
        -- Card 2: Layout
        --------------------------------------------------------------
        local card2 = GUIFrame:CreateCard(scrollChild, "Layout", yOffset)
        table_insert(subCards, card2)

        local rowA = GUIFrame:CreateRow(card2.content, 40)
        local size = GUIFrame:CreateSlider(rowA, "Icon Size", {
            min = 16, max = 64, step = 1, value = db.IconSize,
            callback = function(v) db.IconSize = v; ApplySettings() end,
        })
        rowA:AddWidget(size, 0.5)
        local spacing = GUIFrame:CreateSlider(rowA, "Icon Spacing", {
            min = 0, max = 20, step = 1, value = db.IconSpacing,
            callback = function(v) db.IconSpacing = v; ApplySettings() end,
        })
        rowA:AddWidget(spacing, 0.5)
        table_insert(allWidgets, size)
        table_insert(allWidgets, spacing)
        card2:AddRow(rowA, 40)

        local rowB = GUIFrame:CreateRow(card2.content, 40)
        local perRow = GUIFrame:CreateSlider(rowB, "Icons Per Row", {
            min = 1, max = 20, step = 1, value = db.IconsPerRow,
            callback = function(v) db.IconsPerRow = v; ApplySettings() end,
        })
        rowB:AddWidget(perRow, 0.5)
        local rows = GUIFrame:CreateSlider(rowB, "Max Rows", {
            min = 1, max = 8, step = 1, value = db.MaxRows,
            callback = function(v) db.MaxRows = v; ApplySettings() end,
        })
        rowB:AddWidget(rows, 0.5)
        table_insert(allWidgets, perRow)
        table_insert(allWidgets, rows)
        card2:AddRow(rowB, 40)

        local rowC = GUIFrame:CreateRow(card2.content, 40)
        local growH = GUIFrame:CreateDropdown(rowC, "Grow Sideways", {
            options = {
                { text = "Right", value = "RIGHT" },
                { text = "Left",  value = "LEFT" },
            },
            value = db.GrowHorizontal,
            callback = function(v) db.GrowHorizontal = v; ApplySettings() end,
        })
        rowC:AddWidget(growH, 0.34)
        local growV = GUIFrame:CreateDropdown(rowC, "Grow Vertically", {
            options = {
                { text = "Down", value = "DOWN" },
                { text = "Up",   value = "UP" },
            },
            value = db.GrowVertical,
            callback = function(v) db.GrowVertical = v; ApplySettings() end,
        })
        rowC:AddWidget(growV, 0.33)
        local growAxis = GUIFrame:CreateDropdown(rowC, "Fill Direction", {
            options = {
                { text = "Rows first",    value = "HORIZONTAL" },
                { text = "Columns first", value = "VERTICAL" },
            },
            value = db.GrowAxis,
            callback = function(v) db.GrowAxis = v; ApplySettings() end,
        })
        rowC:AddWidget(growAxis, 0.33)
        table_insert(allWidgets, growH)
        table_insert(allWidgets, growV)
        table_insert(allWidgets, growAxis)
        card2:AddRow(rowC, 40)
        yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

        --------------------------------------------------------------
        -- Card 3: Appearance
        --------------------------------------------------------------
        local card3 = GUIFrame:CreateCard(scrollChild, "Appearance", yOffset)
        table_insert(subCards, card3)

        local rowD = GUIFrame:CreateRow(card3.content, 40)
        local swipe = GUIFrame:CreateCheckbox(rowD, "Swipe", {
            value = db.Swipe ~= false,
            callback = function(c) db.Swipe = c; ApplySettings() end,
        })
        rowD:AddWidget(swipe, 0.34)
        local reverse = GUIFrame:CreateCheckbox(rowD, "Reverse", {
            value = db.Reverse == true,
            callback = function(c) db.Reverse = c; ApplySettings() end,
        })
        rowD:AddWidget(reverse, 0.33)
        local timer = GUIFrame:CreateCheckbox(rowD, "Show Timer", {
            value = db.ShowTimer ~= false,
            callback = function(c) db.ShowTimer = c; ApplySettings() end,
        })
        rowD:AddWidget(timer, 0.33)
        table_insert(allWidgets, swipe)
        table_insert(allWidgets, reverse)
        table_insert(allWidgets, timer)
        card3:AddRow(rowD, 40)

        local rowD2 = GUIFrame:CreateRow(card3.content, 40)
        local decimalCheck = GUIFrame:CreateCheckbox(rowD2, "Decimal Timer", {
            value = db.ShowDecimalSeconds == true,
            callback = function(c)
                db.ShowDecimalSeconds = c
                ApplySettings()
                decimalBelow:SetEnabled(c)
            end,
        })
        rowD2:AddWidget(decimalCheck, 0.5)
        decimalBelow = GUIFrame:CreateSlider(rowD2, "Decimal Below", {
            min = 1, max = 10, step = 1,
            value = db.DecimalThreshold or 3,
            callback = function(v) db.DecimalThreshold = v; ApplySettings() end,
        })
        rowD2:AddWidget(decimalBelow, 0.5)
        -- The threshold stays out of allWidgets: UpdateAllWidgetStates sets
        -- every entry from db.Enabled alone and would undo the toggle below.
        table_insert(allWidgets, decimalCheck)
        card3:AddRow(rowD2, 40)

        local rowE = GUIFrame:CreateRow(card3.content, 40)
        local tips = GUIFrame:CreateCheckbox(rowE, "Show Tooltips", {
            value = db.ShowTooltips ~= false,
            callback = function(c) db.ShowTooltips = c; ApplySettings() end,
        })
        rowE:AddWidget(tips, opts.colorByType and 0.5 or 1)
        table_insert(allWidgets, tips)
        if opts.colorByType then
            local byType = GUIFrame:CreateCheckbox(rowE, "Color Border By Debuff Type", {
                value = db.BorderColorMode == "dispel",
                callback = function(c) db.BorderColorMode = c and "dispel" or "flat"; ApplySettings() end,
            })
            rowE:AddWidget(byType, 0.5)
            table_insert(allWidgets, byType)
        end
        card3:AddRow(rowE, 40)

        local rowF = GUIFrame:CreateRow(card3.content, 46)
        local border = GUIFrame:CreateColorPicker(rowF, "Border Color", {
            color = db.BorderColor,
            callback = function(r, g, b, a) db.BorderColor = { r, g, b, a }; ApplySettings() end,
        })
        rowF:AddWidget(border, opts.weapons and 0.34 or 0.5)
        table_insert(allWidgets, border)
        if opts.weapons then
            local ench = GUIFrame:CreateColorPicker(rowF, "Weapon Enchant Border", {
                color = db.EnchantBorderColor,
                callback = function(r, g, b, a) db.EnchantBorderColor = { r, g, b, a }; ApplySettings() end,
            })
            rowF:AddWidget(ench, 0.33)
            table_insert(allWidgets, ench)
        end
        local countCol = GUIFrame:CreateColorPicker(rowF, "Stack Color", {
            color = db.StackColor,
            callback = function(r, g, b, a) db.StackColor = { r, g, b, a }; ApplySettings() end,
        })
        rowF:AddWidget(countCol, opts.weapons and 0.33 or 0.5)
        table_insert(allWidgets, countCol)
        card3:AddRow(rowF, 46)
        yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

        --------------------------------------------------------------
        -- Card 4: Font
        --------------------------------------------------------------
        local card4 = GUIFrame:CreateCard(scrollChild, "Font", yOffset)
        table_insert(subCards, card4)

        local fontList = {}
        if LSM then
            for name in pairs(LSM:HashTable("font")) do
                table_insert(fontList, { key = name, text = name })
            end
            table.sort(fontList, function(a, b) return a.text < b.text end)
        else
            table_insert(fontList, { key = "Friz Quadrata TT", text = "Friz Quadrata TT" })
        end

        local rowG = GUIFrame:CreateRow(card4.content, 40)
        local fontDrop = GUIFrame:CreateDropdown(rowG, "Font", {
            options = KE:AddFollowGlobalFont(fontList),
            searchable = true,
            value = db.FontFace or KE.FONT_FOLLOW_GLOBAL,
            callback = function(v) db.FontFace = KE:StoredFontFace(v); ApplySettings() end,
        })
        rowG:AddWidget(fontDrop, 0.5)
        local outline = GUIFrame:CreateDropdown(rowG, "Outline", {
            options = {
                { key = "NONE",         text = "None" },
                { key = "OUTLINE",      text = "Outline" },
                { key = "THICKOUTLINE", text = "Thick" },
            },
            value = KE:NormalizeFontOutline(db.FontOutline),
            callback = function(v) db.FontOutline = v; ApplySettings() end,
        })
        rowG:AddWidget(outline, 0.5)
        table_insert(allWidgets, fontDrop)
        table_insert(allWidgets, outline)
        card4:AddRow(rowG, 40)

        local rowH = GUIFrame:CreateRow(card4.content, 40)
        local timerSize = GUIFrame:CreateSlider(rowH, "Timer Font Size", {
            min = 6, max = 24, step = 1, value = db.TimerFontSize,
            callback = function(v) db.TimerFontSize = v; ApplySettings() end,
        })
        rowH:AddWidget(timerSize, 0.5)
        local countSize = GUIFrame:CreateSlider(rowH, "Stack Font Size", {
            min = 6, max = 24, step = 1, value = db.FontSize,
            callback = function(v) db.FontSize = v; ApplySettings() end,
        })
        rowH:AddWidget(countSize, 0.5)
        table_insert(allWidgets, timerSize)
        table_insert(allWidgets, countSize)
        card4:AddRow(rowH, 40)
        yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

        --------------------------------------------------------------
        -- Position
        --------------------------------------------------------------
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
        table_insert(subCards, posCard)
        yOffset = posOffset

        UpdateAllWidgetStates()
        decimalBelow:SetEnabled(db.ShowDecimalSeconds == true)
        return yOffset
    end)
end

BuildPage({
    contentID  = "AuraHeaders_Buffs",
    moduleName = "BuffTracking",
    dbKey      = "BuffTracking",
    title      = "Player Buffs",
    blurb      = "Replaces Blizzard's buff frame.",
    weapons    = true,
})

BuildPage({
    contentID   = "AuraHeaders_Debuffs",
    moduleName  = "PlayerDebuffTracking",
    dbKey       = "PlayerDebuffTracking",
    title       = "Player Debuffs",
    blurb       = "Replaces Blizzard's debuff frame.",
    colorByType = true,
})
