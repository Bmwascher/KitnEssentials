-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DoTTracker.lua                                      ║
-- ║  GUI: DoT Tracker                                        ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           DoTTracker module.                             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DoTTracker", true)
    end
    return nil
end

local GROW_OPTIONS = {
    { key = "DOWN",  text = "Down" },
    { key = "UP",    text = "Up" },
    { key = "LEFT",  text = "Left" },
    { key = "RIGHT", text = "Right" },
}

local COUNT_POSITIONS = {
    { key = "CENTER", text = "On Icon" },
    { key = "RIGHT",  text = "Right Of Icon" },
    { key = "LEFT",   text = "Left Of Icon" },
    { key = "TOP",    text = "Above Icon" },
    { key = "BOTTOM", text = "Below Icon" },
}

local COUNT_FORMATS = {
    { key = "FRACTION", text = "Fraction (3/6)" },
    { key = "COUNT",    text = "Count (3)" },
    { key = "MISSING",  text = "Missing (3)" },
}

local function SpellLabel(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return name or ("Spell " .. id)
end

-- A row's `talent` is one id or a list: "A", "A or B", "A, B or C".
local function TalentTooltip(talent)
    if type(talent) ~= "table" then
        return "Shows only while " .. SpellLabel(talent) .. " is known."
    end
    local names = SpellLabel(talent[1])
    for i = 2, #talent do
        names = names .. (i == #talent and " or " or ", ") .. SpellLabel(talent[i])
    end
    return "Shows only while " .. names .. " is known."
end

local function SpellExists(id)
    local ok, name = pcall(C_Spell.GetSpellName, id)
    return ok and name or nil
end

local function SpecInfo(specId)
    if GetSpecializationInfoForSpecID then
        local _, name, _, icon = GetSpecializationInfoForSpecID(specId)
        if name then return name, icon end
    end
    return "Spec " .. specId, nil
end

local function RefreshPage()
    GUIFrame:RefreshContent()
end

GUIFrame:RegisterContent("DoTTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DoTTracker
    if not db then return yOffset end

    local DT = GetModule()
    local Rules = KE.DoTTrackerRules
    local seeds = KE.DOT_TRACKER_SEEDS
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("icon", function() return db.ShowIcon ~= false end)

    local function ApplySettings()
        if DT then DT:ApplySettings() end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "DoT Tracker", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if DT then
            if checked then KitnEssentials:EnableModule("DoTTracker")
            else KitnEssentials:DisableModule("DoTTracker") end
        end
    end)
    card1:AddLabel("Counts how many of the enemies you are fighting carry each of your DoTs, " ..
        "shown as \"3/6\" beside the DoT's icon. Works in combat and in keys. It cannot say " ..
        "which enemy is missing it.")

    if db.Enabled == true then
        local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
        row1:AddWidget(GUIFrame:CreateCheckbox(row1, "Only In Combat", {
            value = db.OnlyInCombat ~= false,
            callback = function(checked)
                db.OnlyInCombat = checked
                ApplySettings()
            end,
        }), 1 / 3)
        card1:AddRow(row1, Theme.rowHeight)
    end
    yOffset = card1:GetNextOffset()

    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Your DoTs
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Your DoTs", yOffset)
    card2:AddLabel("Every specialization of the selected class, with the DoTs it applies. " ..
        "Unticking a DoT stops counting it on that spec only.")

    db.Spells = db.Spells or {}
    local _, playerClass = UnitClass("player")
    local classSpecs = GUIFrame.GetClassSpecs()
    -- Every class, not only those with shipped DoTs, so any spec can take an
    -- added one.
    local classTokens = {}
    for token in pairs(classSpecs) do classTokens[#classTokens + 1] = token end

    local mark
    local DrawClass

    local function Redraw(classToken)
        local oldHeight = card2:GetContentHeight()
        card2:TruncateBody(mark)
        DrawClass(classToken)
        GUIFrame:ResizeCardInPlace(card2, oldHeight)
    end

    local function DrawSpec(classToken, specId, currentSpecId)
        local specName, specIcon = SpecInfo(specId)
        local header = GUIFrame:CreateRow(card2.content, 26)
        header:AddWidget(GUIFrame:CreateSpecHeaderRow(header, specName, {
            icon = specIcon,
            current = specId == currentSpecId and classToken == playerClass,
        }), 1)
        card2:AddRow(header, 26)

        local entries = {}
        local byClass = seeds[classToken]
        for _, row in ipairs(byClass and byClass[specId] or {}) do
            entries[#entries + 1] = { id = row.id, row = row }
        end
        for _, id in ipairs(Rules.CustomIds(db.Spells, specId)) do
            if not Rules.IsSeed(seeds, classToken, specId, id) then
                entries[#entries + 1] = { id = id, custom = true }
            end
        end
        if #entries == 0 then
            card2:AddLabel("No DoTs listed for this spec.")
            return
        end

        local pending, PER_ROW = nil, 3
        for index, entry in ipairs(entries) do
            local key = Rules.SpellKey(specId, entry.id)
            local saved = db.Spells[key]
            local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.id)
            local label = GUIFrame.IconText(texture) .. SpellLabel(entry.id)
            if entry.custom then label = label .. " (custom)" end
            local tooltip
            if entry.row and entry.row.talent then
                tooltip = TalentTooltip(entry.row.talent)
            elseif entry.row and entry.row.replacedBy then
                tooltip = "Hidden while " .. SpellLabel(entry.row.replacedBy) .. " is known."
            end
            if not pending then pending = GUIFrame:CreateRow(card2.content, 36) end
            pending:AddWidget(GUIFrame:CreateCheckbox(pending, label, {
                value = Rules.IsEnabled(saved, entry.row),
                tooltip = tooltip,
                callback = function(checked)
                    local current = db.Spells[key]
                    if type(current) == "table" then
                        current.enabled = checked
                    else
                        db.Spells[key] = { enabled = checked }
                    end
                    ApplySettings()
                end,
            }), 1 / PER_ROW)
            if index % PER_ROW == 0 or index == #entries then
                card2:AddRow(pending, 36)
                pending = nil
            end
        end
    end

    DrawClass = function(classToken)
        local currentSpecId = KE:GetPlayerSpecId()
        local specIds = classSpecs[classToken] or {}
        for _, specId in ipairs(specIds) do
            DrawSpec(classToken, specId, currentSpecId)
        end

        card2:AddRow(GUIFrame:CreateSeparator(card2.content), Theme.rowHeightSeparator)

        local specOptions = {}
        for _, specId in ipairs(specIds) do
            local specName, specIcon = SpecInfo(specId)
            specOptions[#specOptions + 1] = { key = specId, text = GUIFrame.IconText(specIcon) .. specName }
        end
        local chosenSpec = specIds[1]
        if classToken == playerClass and currentSpecId then chosenSpec = currentSpecId end

        local addRow = GUIFrame:CreateSpellAddRow(card2.content, {
            picker = {
                label = "Spec",
                options = specOptions,
                value = chosenSpec,
                callback = function(key) chosenSpec = key end,
            },
            idLabel = "Debuff Spell ID",
            onAdd = function(text)
                local id, reason = Rules.CanAdd(seeds, db.Spells, classToken, chosenSpec, text, SpellExists)
                if not id then
                    KE:Print(reason)
                    return
                end
                db.Spells[Rules.SpellKey(chosenSpec, id)] = { enabled = true, custom = true }
                Redraw(classToken)
                ApplySettings()
            end,
            onRemove = function(text)
                local key, reason = Rules.CanRemove(seeds, db.Spells, classToken, chosenSpec, text)
                if not key then
                    KE:Print(reason)
                    return
                end
                db.Spells[key] = nil
                Redraw(classToken)
                ApplySettings()
            end,
        })
        card2:AddRow(addRow, Theme.rowHeight)

        card2:AddNote("Adds to the chosen class and spec. Use the DEBUFF's id, which for many " ..
            "spells differs from the button you press. Remove takes off only DoTs you added; " ..
            "untick a shipped one instead.")
    end

    local classRow, shownClass = GUIFrame:CreateClassPickerRow(card2.content, {
        scope = "DoTTracker",
        classTokens = classTokens,
        onPick = function(key) Redraw(key) end,
    })
    card2:AddRow(classRow, 36)
    mark = card2:MarkBody()
    DrawClass(shownClass)
    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Who Counts
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Who Counts", yOffset)
    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    row3:AddWidget(GUIFrame:CreateCheckbox(row3, "Only Enemies In Combat", {
        value = db.OnlyEnemiesInCombat ~= false,
        callback = function(checked)
            db.OnlyEnemiesInCombat = checked
            ApplySettings()
        end,
    }), 0.5)
    row3:AddWidget(GUIFrame:CreateSlider(row3, "Most Enemies Counted", {
        min = 1, max = 40, step = 1,
        value = db.MaxEnemies or 20,
        callback = function(value)
            db.MaxEnemies = value
            ApplySettings()
        end,
    }), 0.5)
    card3:AddRow(row3, Theme.rowHeight)
    card3:AddNote("Attackable, alive enemies with a nameplate. On training dummies, which flag " ..
        "neither rule, every attackable enemy counts.")
    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Layout
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Layout", yOffset)
    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    row4a:AddWidget(GUIFrame:CreateSlider(row4a, "Icon Size", {
        min = 16, max = 80, step = 1,
        value = db.IconSize or 40,
        callback = function(value)
            db.IconSize = value
            ApplySettings()
        end,
    }), 0.5)
    row4a:AddWidget(GUIFrame:CreateSlider(row4a, "Spacing", {
        min = 0, max = 20, step = 1,
        value = db.Spacing or 4,
        callback = function(value)
            db.Spacing = value
            ApplySettings()
        end,
    }), 0.5)
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    row4b:AddWidget(GUIFrame:CreateDropdown(row4b, "Grow", {
        options = GROW_OPTIONS,
        value = db.GrowDirection or "DOWN",
        callback = function(key)
            db.GrowDirection = key
            ApplySettings()
        end,
    }), 0.5)
    -- With the icon hidden the count is the cell, so it has no side to take.
    local countPosition = GUIFrame:CreateDropdown(row4b, "Count Position", {
        options = COUNT_POSITIONS,
        value = db.CountPosition or "RIGHT",
        callback = function(key)
            db.CountPosition = key
            ApplySettings()
        end,
    })
    row4b:AddWidget(countPosition, 0.5)
    manager:Register(countPosition, "icon")
    card4:AddRow(row4b, Theme.rowHeight)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    row4c:AddWidget(GUIFrame:CreateSlider(row4c, "Count X", {
        min = -50, max = 50, step = 1,
        value = db.CountX or 0,
        callback = function(value)
            db.CountX = value
            ApplySettings()
        end,
    }), 1 / 3)
    row4c:AddWidget(GUIFrame:CreateSlider(row4c, "Count Y", {
        min = -50, max = 50, step = 1,
        value = db.CountY or 0,
        callback = function(value)
            db.CountY = value
            ApplySettings()
        end,
    }), 1 / 3)
    row4c:AddWidget(GUIFrame:CreateCheckbox(row4c, "Show Icon", {
        value = db.ShowIcon ~= false,
        callback = function(checked)
            db.ShowIcon = checked
            manager:UpdateAll(true)
            ApplySettings()
        end,
    }), 1 / 3)
    card4:AddRow(row4c, Theme.rowHeight)
    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Count Text, then its font
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Count Text", yOffset)
    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    row5a:AddWidget(GUIFrame:CreateDropdown(row5a, "Format", {
        options = COUNT_FORMATS,
        value = db.CountFormat or "FRACTION",
        callback = function(key)
            db.CountFormat = key
            ApplySettings()
        end,
    }), 0.5)
    card5:AddRow(row5a, Theme.rowHeight)
    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    row5b:AddWidget(GUIFrame:CreateColorPicker(row5b, "Some Have It", {
        color = db.SomeColor,
        callback = function(r, g, b, a)
            db.SomeColor = { r, g, b, a }
            ApplySettings()
        end,
    }), 0.5)
    row5b:AddWidget(GUIFrame:CreateColorPicker(row5b, "All Have It", {
        color = db.AllColor,
        callback = function(r, g, b, a)
            db.AllColor = { r, g, b, a }
            ApplySettings()
        end,
    }), 0.5)
    card5:AddRow(row5b, Theme.rowHeight)
    yOffset = card5:GetNextOffset()

    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Count Font",
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 40 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 6: Target Timer
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Target Timer", yOffset)
    card6:AddHeaderToggle(db.TimerEnabled ~= false, function(checked)
        db.TimerEnabled = checked
        ApplySettings()
    end)
    card6:AddLabel("Your DoT's time left on your current target, centered on the icon. " ..
        "Hidden when the target does not have it.")
    local row6a = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    row6a:AddWidget(GUIFrame:CreateSlider(row6a, "Font Size", {
        min = 8, max = 40, step = 1,
        value = db.TimerFontSize or 18,
        callback = function(value)
            db.TimerFontSize = value
            ApplySettings()
        end,
    }), 0.5)
    row6a:AddWidget(GUIFrame:CreateColorPicker(row6a, "Color", {
        color = db.TimerColor,
        callback = function(r, g, b, a)
            db.TimerColor = { r, g, b, a }
            ApplySettings()
        end,
    }), 0.5)
    card6:AddRow(row6a, Theme.rowHeight)
    local row6b = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    row6b:AddWidget(GUIFrame:CreateSlider(row6b, "Timer X", {
        min = -50, max = 50, step = 1,
        value = db.TimerX or 0,
        callback = function(value)
            db.TimerX = value
            ApplySettings()
        end,
    }), 0.5)
    row6b:AddWidget(GUIFrame:CreateSlider(row6b, "Timer Y", {
        min = -50, max = 50, step = 1,
        value = db.TimerY or 0,
        callback = function(value)
            db.TimerY = value
            ApplySettings()
        end,
    }), 0.5)
    card6:AddRow(row6b, Theme.rowHeight)
    yOffset = card6:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Glow (engine styles)
    ----------------------------------------------------------------
    local glowCard, glowOffset = GUIFrame:CreateGlowSettingsCard(scrollChild, yOffset, {
        title = "Glow",
        db = db,
        dbKeys = {
            enabled   = "GlowEnabled",
            type      = "GlowType",
            color     = "GlowColor",
            lines     = "GlowLines",
            frequency = "GlowFrequency",
            thickness = "GlowThickness",
            pulse     = "GlowPulse",
            duration  = "GlowDuration",
        },
        types = {
            { key = "pixel",    text = "Pixel" },
            { key = "border",   text = "Pulse Border" },
            { key = "ants",     text = "Ants" },
            { key = "procloop", text = "Proc Loop" },
            { key = "alert",    text = "Alert" },
        },
        resolveType = KE.AuraGlowRules.ResolveType,
        typeTooltip = "Shows on a DoT's icon while every counted enemy has it (6/6).",
        typeRows = function(rows)
            return {
                pixel       = rows.pixel,
                unsupported = rows.pixelExtras,
                autocast    = rows.autocast,
                proc        = rows.proc,
                border      = rows.border,
            }
        end,
        showSpeed = function() return true end,
        speedAdapter = {
            read = function(readDb, readKeys)
                return KE.AuraGlowRules.NormalizeFrequency(
                    KE.AuraGlowRules.ReadSpeed(readDb, readKeys), 0.05, 1)
            end,
            write   = KE.AuraGlowRules.WriteSpeed,
            setType = KE.AuraGlowRules.SetType,
            min     = 0.05,
            max     = 1,
        },
        onChangeCallback = ApplySettings,
        -- Pixel and Pulse Border show a row of controls and the sheet styles
        -- none; the cards below sit at fixed offsets, so the page is rebuilt.
        onHeightChange = function() C_Timer.After(0, RefreshPage) end,
    })
    manager:Register(glowCard, "all")
    yOffset = glowOffset

    ----------------------------------------------------------------
    -- Card 8: Position
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        positionKey = "Position",
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    manager:UpdateAll(true)
    return yOffset
end)
