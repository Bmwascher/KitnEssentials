-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CCTracker.lua                                       ║
-- ║  GUI: CC Tracker                                         ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           CCTracker module.                              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local pairs, pcall, type = pairs, pcall, type
local table_sort = table.sort

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("CCTracker", true)
    end
    return nil
end

local SOURCE_OPTIONS = {
    { key = "ANYONE", text = "Anyone" },
    { key = "MINE",   text = "Mine Only" },
}

local GROW_OPTIONS = GUIFrame.GrowVerticalOptions

local FOOTER_HEIGHT = 28

local function SpellName(id)
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok then return name end
    return nil
end

GUIFrame:RegisterContent("CCTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CCTracker
    if not db then return yOffset end

    local CC = GetModule()
    local Rules = KE.CCTrackerRules
    local seeds = KE.CC_TRACKER_SEEDS
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if CC then CC:ApplySettings() end
    end

    manager:SetCondition("name", function() return db.NameEnabled ~= false end)
    manager:SetCondition("timer", function() return db.ShowTimer ~= false end)

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "CC Tracker", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if CC then
            if checked then KitnEssentials:EnableModule("CCTracker")
            else KitnEssentials:DisableModule("CCTracker") end
        end
    end)
    card1:AddLabel(KE.IS_FOREVER
        and ("Shows each enemy held by a long crowd control (Polymorph, Repentance, Freezing Trap, " ..
            "Sap and more): the spell's icon, the time left on it, and the enemy's name.")
        or ("Shows each enemy held by a long crowd control (Polymorph, Hex, Repentance, " ..
            "Freezing Trap and more): the spell's icon, the time left on it, and the enemy's name."))
    yOffset = card1:GetNextOffset()

    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Tracked Crowd Control
    ----------------------------------------------------------------
    db.Groups = db.Groups or {}
    db.CustomIDs = db.CustomIDs or {}

    local card2 = GUIFrame:CreateCard(scrollChild, "Tracked Crowd Control", yOffset)
    -- A redraw releases the class rows, so they have a manager of their own,
    -- cleared with them; the page's manager never drives a released one.
    local seedManager = GUIFrame:CreateWidgetStateManager()
    local mark, DrawRows

    local function Redraw()
        local oldHeight = card2:GetContentHeight()
        card2:TruncateBody(mark)
        DrawRows()
        GUIFrame:ResizeCardInPlace(card2, oldHeight)
    end

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    row2a:AddWidget(GUIFrame:CreateDropdown(row2a, "Count Crowd Control From", {
        options = SOURCE_OPTIONS,
        value = db.Source or "ANYONE",
        callback = function(key)
            db.Source = key
            ApplySettings()
        end,
    }), 0.5)
    row2a:AddWidget(GUIFrame:CreateCheckbox(row2a, "Every Crowd Control (Short Stuns Too)", {
        value = db.EveryCC == true,
        tooltip = "Counts any crowd control the game flags on an enemy, short stuns included, " ..
            "and ignores the list below.",
        callback = function(checked)
            db.EveryCC = checked
            ApplySettings()
            -- The note under the list comes and goes with it.
            Redraw()
        end,
    }), 0.5)
    card2:AddRow(row2a, Theme.rowHeight)
    card2:AddSeparator()

    DrawRows = function()
        seedManager:Clear()
        seedManager:SetCondition("seeds", function() return db.EveryCC ~= true end)
        local picks = {}
        for _, seed in ipairs(seeds) do
            local key = seed.key
            local texture = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(seed.ids[1])
            picks[#picks + 1] = {
                class = seed.group,
                label = GUIFrame.IconText(texture) .. seed.label,
                value = Rules.SeedEnabled(seed, db.Groups),
                onChange = function(checked)
                    db.Groups[key] = { enabled = checked }
                    ApplySettings()
                end,
            }
        end
        local rows = KE.ClassSpellRows.Add(card2, picks)
        seedManager:RegisterGroup(rows.widgets, "seeds")
        seedManager:UpdateAll(true)
        if db.EveryCC == true then
            card2:AddNote("Every Crowd Control is on, so the list is ignored.")
        end
        card2:AddSeparator()

        local addRow = GUIFrame:CreateSpellAddRow(card2.content, {
            idLabel = "Debuff Spell ID",
            onAdd = function(text)
                local id, reason = Rules.CanAdd(text, seeds, db.CustomIDs, SpellName)
                if not id then
                    KE:Print(reason)
                    return
                end
                db.CustomIDs[id] = true
                ApplySettings()
                -- The rebuild releases the pressed button, so it waits a
                -- frame.
                C_Timer.After(0, function() GUIFrame:RefreshContent() end)
            end,
            onRemove = function(text)
                local id, reason = Rules.CanRemove(text, seeds, db.CustomIDs)
                if not id then
                    KE:Print(reason)
                    return
                end
                db.CustomIDs[id] = nil
                ApplySettings()
                C_Timer.After(0, function() GUIFrame:RefreshContent() end)
            end,
        })
        card2:AddRow(addRow, Theme.rowHeight)

        local added = {}
        for id, on in pairs(db.CustomIDs) do
            if on == true and type(id) == "number" then added[#added + 1] = id end
        end
        table_sort(added)
        local entries = {}
        for i, id in ipairs(added) do
            local name = SpellName(id)
            local texture = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
            entries[i] = GUIFrame.IconText(texture) .. (name and (name .. " (" .. id .. ")") or ("Spell " .. id))
        end
        card2:AddNote(#entries == 0 and "Added: none." or ("Added: " .. table.concat(entries, ", ") .. "."))

        local footer = GUIFrame:CreateRow(card2.content, FOOTER_HEIGHT)
        footer:AddWidget(GUIFrame:CreateButton(footer, "Kitn Defaults", {
            tooltip = "Sets every listed crowd control back to how it ships. Spells added by ID stay.",
            -- The pressed button is released by the redraw, so the redraw
            -- waits a frame.
            callback = function()
                db.Groups = {}
                ApplySettings()
                C_Timer.After(0, Redraw)
            end,
        }), 0.3)
        card2:AddRow(footer, FOOTER_HEIGHT, 0)
    end

    mark = card2:MarkBody()
    DrawRows()
    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Enemy Name
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Enemy Name", yOffset)
    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    row5a:AddWidget(GUIFrame:CreateCheckbox(row5a, "Show Name", {
        value = db.NameEnabled ~= false,
        callback = function(checked)
            db.NameEnabled = checked
            manager:UpdateAll(true)
            ApplySettings()
        end,
    }), 0.5)
    local nameColor = GUIFrame:CreateColorPicker(row5a, "Name Color", {
        color = db.NameColor,
        callback = function(r, g, b, a)
            db.NameColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5a:AddWidget(nameColor, 0.5)
    manager:Register(nameColor, "name")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local nameSize = GUIFrame:CreateSlider(row5b, "Font Size", {
        min = 8, max = 30, step = 1,
        value = db.NameFontSize or 14,
        callback = function(value)
            db.NameFontSize = value
            ApplySettings()
        end,
    })
    row5b:AddWidget(nameSize, 0.5)
    manager:Register(nameSize, "name")
    local nameWidth = GUIFrame:CreateSlider(row5b, "Name Width", {
        min = 40, max = 300, step = 1,
        value = db.NameWidth or 150,
        callback = function(value)
            db.NameWidth = value
            ApplySettings()
        end,
    })
    row5b:AddWidget(nameWidth, 0.5)
    manager:Register(nameWidth, "name")
    card5:AddRow(row5b, Theme.rowHeight)
    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Display Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    row3a:AddWidget(GUIFrame:CreateSlider(row3a, "Icon Size", {
        min = 16, max = 80, step = 1,
        value = db.IconSize or 40,
        callback = function(value)
            db.IconSize = value
            ApplySettings()
        end,
    }), 0.5)
    row3a:AddWidget(GUIFrame:CreateSlider(row3a, "Row Spacing", {
        min = 0, max = 20, step = 1,
        value = db.RowSpacing or 2,
        callback = function(value)
            db.RowSpacing = value
            ApplySettings()
        end,
    }), 0.5)
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    row3b:AddWidget(GUIFrame:CreateSlider(row3b, "Enemy CCs Shown", {
        min = 1, max = Rules.TRACKED_ENEMIES, step = 1,
        value = Rules.NormalizeShown(db.ShownRows),
        callback = function(value)
            db.ShownRows = value
            if CC then CC:ApplyShown() end
        end,
    }), 0.5)
    row3b:AddWidget(GUIFrame:CreateDropdown(row3b, "Grow Direction", {
        options = GROW_OPTIONS,
        value = db.GrowDirection or "DOWN",
        callback = function(key)
            db.GrowDirection = key
            ApplySettings()
        end,
    }), 0.5)
    card3:AddRow(row3b, Theme.rowHeight)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    row3c:AddWidget(GUIFrame:CreateCheckbox(row3c, "Show Time Left", {
        value = db.ShowTimer ~= false,
        callback = function(checked)
            db.ShowTimer = checked
            manager:UpdateAll(true)
            ApplySettings()
        end,
    }), 0.5)
    row3c:AddWidget(GUIFrame:CreateCheckbox(row3c, "Swipe", {
        value = db.Swipe ~= false,
        tooltip = "Sweeps the icon as the crowd control runs out. Shows on live rows only, not on the preview.",
        callback = function(checked)
            db.Swipe = checked
            ApplySettings()
        end,
    }), 0.5)
    card3:AddRow(row3c, Theme.rowHeight)
    card3:AddNote("Up to " .. Rules.TRACKED_ENEMIES .. " enemies are tracked. " .. KE:Gold("Enemy CCs Shown") ..
        " sets how many show at once; the rest come into view as shown ones end. The stack stays on " ..
        "screen, so lower Enemy CCs Shown near a screen edge.")
    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Position Settings
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

    ----------------------------------------------------------------
    -- Card 6: Time Left Font
    ----------------------------------------------------------------
    local fontCard, _, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Time Left Font",
        db = db,
        dbKeys = {
            fontFace    = "TimerFontFace",
            fontOutline = "TimerFontOutline",
        },
        fontSizes = {
            { label = "Font Size", dbKey = "TimerFontSize", default = 20 },
        },
        extraSlider = {
            label = "Show Decimals Below (sec)",
            dbKey = "DecimalThreshold",
            min = 0, max = 10, step = 1,
            value = KE.AuraRules.NormalizeDecimalThreshold(db.DecimalThreshold),
        },
        fontSizeRange = { 8, 40 },
        onChangeCallback = ApplySettings,
    })
    -- Font and Outline also style the enemy name, so only the timer's own
    -- size, decimals and color follow Show Time Left. The legacy font card
    -- returns face, outline, the size slider, then the extra slider.
    if fontWidgets then
        manager:Register(fontWidgets[3], "timer")
        manager:Register(fontWidgets[4], "timer")
    end

    -- The card's own last row is added with no trailing gap, so re-open the
    -- spacing before appending to it.
    fontCard:AddSpacing(Theme.paddingSmall)
    local rowColor = GUIFrame:CreateRow(fontCard.content, Theme.rowHeight)
    local timerColor = GUIFrame:CreateColorPicker(rowColor, "Time Left Color", {
        color = db.TimerTextColor,
        callback = function(r, g, b, a)
            db.TimerTextColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowColor:AddWidget(timerColor, 0.5)
    manager:Register(timerColor, "timer")
    fontCard:AddRow(rowColor, Theme.rowHeight)
    fontCard:AddNote(KE:Gold("Font") .. " and " .. KE:Gold("Outline") .. " also style the enemy name.")
    yOffset = fontCard:GetNextOffset()

    manager:UpdateAll(true)
    return yOffset
end)
