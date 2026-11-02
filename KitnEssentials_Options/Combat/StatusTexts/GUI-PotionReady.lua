-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PotionReady.lua                                     ║
-- ║  GUI: Combat Potion Ready                                ║
-- ║  Purpose: Configuration panel for the PotionReady module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PotionReady", true)
    end
    return nil
end

GUIFrame:RegisterContent("PotionReady", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PotionReady
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local mod = GetModule()
    -- Forever keeps today's page: no Display Mode, no stat, no icon.
    local retail = not KE.IS_FOREVER
    local iconMode = retail and db.DisplayMode == "icon"
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("customColor", function()
        return not iconMode and (db.ColorMode or "custom") == "custom"
    end)
    manager:SetCondition("textMode", function()
        return not iconMode
    end)
    manager:SetCondition("reckStat", function()
        return db.ReckStat ~= nil and db.ReckStat.Enabled == true
    end)
    manager:SetCondition("reckPrefix", function()
        return db.ReckStat ~= nil and db.ReckStat.Enabled == true and db.ReckStat.ShowPrefix ~= false
    end)
    manager:SetCondition("iconCount", function()
        return db.ShowCount ~= false
    end)

    local function ApplySettings()
        if mod and mod.ApplySettings then mod:ApplySettings() end
        if mod and mod.CheckPotions then mod:CheckPotions() end
    end

    local function ApplyModuleState(enabled)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("PotionReady")
        else
            KitnEssentials:DisableModule("PotionReady")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Potion Ready", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)

    if retail then
        card1:AddLabel("Shows a Potion Ready text, or the potion's icon, while a combat potion is in your bags. " ..
            "With a Potion of Recklessness it can also show the stat that potion would raise right now. " ..
            "Can be limited to instances or to combat, and hidden on a healing spec.")
    else
        card1:AddLabel("Shows a Potion Ready text while a combat potion is in your bags and off cooldown. " ..
            "Can be limited to instances or to combat, and hidden on a healing spec.")
    end

    yOffset = card1:GetNextOffset()

    -- A disabled module shows only this card: its switch and description.
    if db.Enabled == false then return yOffset end

    local ticked = db.AttachToCombatTexts == true
    -- The real attachment, not the saved box: with Combat Texts off the text
    -- stands alone and needs its own position and font.
    local attached = mod ~= nil and mod:IsAttached()
    local attachNote = ticked and mod ~= nil and not attached
    if iconMode then
        card1:AddNote("Icon mode stands alone: it does not join the Combat Texts stack.")
    else
        local attachRow = GUIFrame:CreateRow(card1.content,
            (attached or attachNote) and Theme.rowHeight or Theme.rowHeightLast)
        local attachCheck = GUIFrame:CreateCheckbox(attachRow, "Attach to Combat Texts", {
            value = ticked,
            tooltip = "Show the text as a row of the Combat Texts messages and move with them, "
                .. "instead of using a separate anchor.",
            callback = function(checked)
                db.AttachToCombatTexts = checked
                ApplySettings()
                GUIFrame:RefreshContent()
            end,
        })
        attachRow:AddWidget(attachCheck, 1)
        manager:Register(attachCheck, "all")
        if attached then
            card1:AddRow(attachRow, Theme.rowHeight)
            for _, widget in ipairs(GUIFrame:CreateAttachSizeRow(card1, db, {
                sizeKey = "FontSize", default = 20, range = { 8, 72 },
                onChange = ApplySettings, isLast = true,
            })) do
                manager:Register(widget, "all")
            end
        elseif attachNote then
            card1:AddRow(attachRow, Theme.rowHeight)
            GUIFrame:AddAttachOffNote(card1)
        else
            card1:AddRow(attachRow, Theme.rowHeightLast, 0)
        end
    end
    yOffset = card1:GetNextOffset()

    if retail then
        db.ReckStat = db.ReckStat or {}
        local rs = db.ReckStat
        rs.Colors = rs.Colors or {}

        ----------------------------------------------------------------
        -- Recklessness Stat
        ----------------------------------------------------------------
        local cardReck = GUIFrame:CreateCard(scrollChild, "Recklessness Stat", yOffset)
        manager:Register(cardReck, "all")

        local rowReckA = GUIFrame:CreateRow(cardReck.content, Theme.rowHeight)
        local reckCheck = GUIFrame:CreateCheckbox(rowReckA, "Show Recklessness Stat", {
            value = rs.Enabled == true,
            tooltip = "Name the secondary stat a Potion of Recklessness would raise right now.",
            callback = function(checked)
                rs.Enabled = checked
                ApplySettings()
                RefreshStates()
            end,
        })
        rowReckA:AddWidget(reckCheck, 0.35)
        manager:Register(reckCheck, "all")

        local prefixCheck = GUIFrame:CreateCheckbox(rowReckA, "Show Prefix", {
            value = rs.ShowPrefix ~= false,
            callback = function(checked)
                rs.ShowPrefix = checked
                ApplySettings()
                RefreshStates()
            end,
        })
        rowReckA:AddWidget(prefixCheck, 0.25)
        manager:Register(prefixCheck, "reckStat")

        local prefixBox = GUIFrame:CreateEditBox(rowReckA, "Prefix", {
            value = rs.Prefix or "Reck:",
            callback = function(text) rs.Prefix = text; ApplySettings() end,
        })
        rowReckA:AddWidget(prefixBox, 0.4)
        manager:Register(prefixBox, "reckPrefix")
        cardReck:AddRow(rowReckA, Theme.rowHeight)

        local rowReckSep = GUIFrame:CreateRow(cardReck.content, Theme.rowHeightSeparator)
        local sepReck = GUIFrame:CreateSeparator(rowReckSep)
        rowReckSep:AddWidget(sepReck, 1)
        manager:Register(sepReck, "reckStat")
        cardReck:AddRow(rowReckSep, Theme.rowHeightSeparator)

        local rowReckColors = GUIFrame:CreateRow(cardReck.content, Theme.rowHeight)
        for _, stat in ipairs({
            { key = "crit", label = "Crit" },
            { key = "haste", label = "Haste" },
            { key = "mastery", label = "Mastery" },
            { key = "vers", label = "Vers" },
        }) do
            local hue = KE:CreateColor(KE.SecondaryStatHex[stat.key])
            local picker = GUIFrame:CreateColorPicker(rowReckColors, stat.label, {
                color = rs.Colors[stat.key] or { hue.r, hue.g, hue.b, 1 },
                callback = function(r, g, b, a)
                    rs.Colors[stat.key] = { r, g, b, a }
                    ApplySettings()
                end,
            })
            rowReckColors:AddWidget(picker, 0.2)
            manager:Register(picker, "reckStat")
        end
        local prefixColor = GUIFrame:CreateColorPicker(rowReckColors, "Prefix", {
            color = rs.PrefixColor or { 1, 1, 1, 1 },
            callback = function(r, g, b, a)
                rs.PrefixColor = { r, g, b, a }
                ApplySettings()
            end,
        })
        rowReckColors:AddWidget(prefixColor, 0.2)
        manager:Register(prefixColor, "reckPrefix")
        cardReck:AddRow(rowReckColors, Theme.rowHeight)

        if iconMode then
            local rowReckIcon = GUIFrame:CreateRow(cardReck.content, Theme.rowHeight)
            local positionDropdown = GUIFrame:CreateDropdown(rowReckIcon, "Stat Position", {
                options = {
                    { key = "ABOVE", text = "Above" },
                    { key = "BELOW", text = "Below" },
                    { key = "LEFT",  text = "Left" },
                    { key = "RIGHT", text = "Right" },
                },
                value = rs.Position or "ABOVE",
                callback = function(key) rs.Position = key; ApplySettings() end,
            })
            rowReckIcon:AddWidget(positionDropdown, 0.5)
            manager:Register(positionDropdown, "reckStat")

            local statSizeSlider = GUIFrame:CreateSlider(rowReckIcon, "Stat Text Size", {
                min = 8, max = 40, step = 1,
                value = rs.FontSize or 14,
                callback = function(v) rs.FontSize = v; ApplySettings() end,
            })
            rowReckIcon:AddWidget(statSizeSlider, 0.5)
            manager:Register(statSizeSlider, "reckStat")
            cardReck:AddRow(rowReckIcon, Theme.rowHeight)
        end

        cardReck:AddNote("Shows only while a Potion of Recklessness is in your bags. Your highest "
            .. "secondary rating wins, procs included; a tie goes to Crit, then Haste, Mastery, Vers. "
            .. "If the game hides your ratings and KE cannot compare them, the stat stays hidden "
            .. "rather than guess.")
        yOffset = cardReck:GetNextOffset()

        ----------------------------------------------------------------
        -- Recklessness Stat per Specialization
        ----------------------------------------------------------------
        local specCard, specOffset = GUIFrame:CreateSpecEnableCard(scrollChild, yOffset, {
            db = rs,
            title = "Recklessness Stat per Specialization",
            note = "Untick a specialization to stop showing the Recklessness stat there; KE then "
                .. "reads no ratings on that spec. Potion Ready itself keeps the checkboxes in "
                .. KE:Gold("Display Settings") .. ".",
            scope = "PotionReadyReck",
            onChange = ApplySettings,
        })
        manager:Register(specCard, "all")
        yOffset = specOffset

        ----------------------------------------------------------------
        -- Icon
        ----------------------------------------------------------------
        if iconMode then
            local cardIcon = GUIFrame:CreateCard(scrollChild, "Icon", yOffset)
            manager:Register(cardIcon, "all")

            local rowIconA = GUIFrame:CreateRow(cardIcon.content, Theme.rowHeight)
            local widthSlider = GUIFrame:CreateSlider(rowIconA, "Icon Width", {
                min = 16, max = 128, step = 1,
                value = db.IconWidth or 40,
                callback = function(v) db.IconWidth = v; ApplySettings() end,
            })
            rowIconA:AddWidget(widthSlider, 0.5)
            manager:Register(widthSlider, "all")
            local heightSlider = GUIFrame:CreateSlider(rowIconA, "Icon Height", {
                min = 16, max = 128, step = 1,
                value = db.IconHeight or 40,
                callback = function(v) db.IconHeight = v; ApplySettings() end,
            })
            rowIconA:AddWidget(heightSlider, 0.5)
            manager:Register(heightSlider, "all")
            cardIcon:AddRow(rowIconA, Theme.rowHeight)

            local rowIconB = GUIFrame:CreateRow(cardIcon.content, Theme.rowHeight)
            local countCheck = GUIFrame:CreateCheckbox(rowIconB, "Show Count", {
                value = db.ShowCount ~= false,
                callback = function(checked)
                    db.ShowCount = checked
                    ApplySettings()
                    RefreshStates()
                end,
            })
            rowIconB:AddWidget(countCheck, 0.5)
            manager:Register(countCheck, "all")
            local countSize = GUIFrame:CreateSlider(rowIconB, "Count Text Size", {
                min = 8, max = 32, step = 1,
                value = db.CountSize or 12,
                callback = function(v) db.CountSize = v; ApplySettings() end,
            })
            rowIconB:AddWidget(countSize, 0.5)
            manager:Register(countSize, "iconCount")
            cardIcon:AddRow(rowIconB, Theme.rowHeight)

            local rowIconC = GUIFrame:CreateRow(cardIcon.content, Theme.rowHeightLast)
            local cooldownCheck = GUIFrame:CreateCheckbox(rowIconC, "Show Cooldown", {
                value = db.ShowCooldown ~= false,
                callback = function(checked) db.ShowCooldown = checked; ApplySettings() end,
            })
            rowIconC:AddWidget(cooldownCheck, 0.5)
            manager:Register(cooldownCheck, "all")
            local readyCheck = GUIFrame:CreateCheckbox(rowIconC, "Only While Ready", {
                value = db.OnlyWhileReady == true,
                tooltip = "Hide the icon while the potion is on cooldown, as the text does.",
                callback = function(checked) db.OnlyWhileReady = checked; ApplySettings() end,
            })
            rowIconC:AddWidget(readyCheck, 0.5)
            manager:Register(readyCheck, "all")
            cardIcon:AddRow(rowIconC, Theme.rowHeightLast)

            cardIcon:AddNote("The picture is the potion the display answers for: a Recklessness potion "
                .. "when you carry one, otherwise the first combat potion in your bags. The count adds "
                .. "its gold, silver and fleeting copies.")
            yOffset = cardIcon:GetNextOffset()
        end
    end

    ----------------------------------------------------------------
    -- Card 2: Display Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local textWidth = 1
    if retail then
        local modeDropdown = GUIFrame:CreateDropdown(row2a, "Display Mode", {
            options = {
                { key = "text", text = "Text" },
                { key = "icon", text = "Icon" },
            },
            value = iconMode and "icon" or "text",
            callback = function(key)
                db.DisplayMode = key
                ApplySettings()
                GUIFrame:RefreshContent()
            end,
        })
        row2a:AddWidget(modeDropdown, iconMode and 1 or 0.4)
        manager:Register(modeDropdown, "all")
        textWidth = 0.6
    end
    if not iconMode then
        local textBox = GUIFrame:CreateEditBox(row2a, "Display Text", {
            value = db.Text or "Potion Ready",
            callback = function(text) db.Text = text; ApplySettings() end,
        })
        row2a:AddWidget(textBox, textWidth)
        manager:Register(textBox, "all")
    end
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local instanceCheck = GUIFrame:CreateCheckbox(row2b, "Instances Only", {
        value = db.InstanceOnly ~= false,
        callback = function(checked) db.InstanceOnly = checked; ApplySettings() end,
    })
    row2b:AddWidget(instanceCheck, 1/3)
    manager:Register(instanceCheck, "all")

    local combatCheck = GUIFrame:CreateCheckbox(row2b, "In Combat Only", {
        value = db.CombatOnly,
        callback = function(checked) db.CombatOnly = checked; ApplySettings() end,
    })
    row2b:AddWidget(combatCheck, 1/3)
    manager:Register(combatCheck, "all")

    local healerCheck = GUIFrame:CreateCheckbox(row2b, "Hide for Healers", {
        value = db.DisableOnHealer,
        callback = function(checked) db.DisableOnHealer = checked; ApplySettings() end,
    })
    row2b:AddWidget(healerCheck, 1/3)
    manager:Register(healerCheck, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    -- Combat Texts owns the anchor and the font while attached.
    if not attached then
        ----------------------------------------------------------------
        -- Card 3: Position Settings
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
        -- Card 4: Font Settings
        ----------------------------------------------------------------
        local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
            db = db,
            dbKeys = {
                fontFace = "FontFace",
                fontSize = "FontSize",
                fontOutline = "FontOutline",
            },
            onChangeCallback = ApplySettings,
            showSize = not iconMode,
        })
        manager:Register(fontCard, "all")
        if fontWidgets then
            manager:RegisterGroup(fontWidgets, "all")
        end
        yOffset = fontOffset
    end

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {
        db         = db,
        manager    = manager,
        onChange   = ApplySettings,
        stateGroup = "textMode",
        isLast     = true,
        colorMode  = { key = "ColorMode", onChange = RefreshStates },
        colors     = {
            { label = "Custom Color", key = "Color", default = { 0, 1, 0, 1 }, group = "customColor" },
        },
    })

    RefreshStates()
    return yOffset
end)
