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

local GROW_OPTIONS = {
    { key = "DOWN", text = "Down" },
    { key = "UP",   text = "Up" },
}

local SEEDS_PER_ROW = 3
local SEED_CELL_H = 24
local SEED_CELL_SPACING = 2

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
    card1:AddLabel("Shows each enemy held by a long crowd control (Polymorph, Hex, Repentance, " ..
        "Freezing Trap and more): the spell's icon, the time left on it, and the enemy's name.")
    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Tracked Crowd Control
    ----------------------------------------------------------------
    db.Groups = db.Groups or {}
    db.CustomIDs = db.CustomIDs or {}

    local card2 = GUIFrame:CreateCard(scrollChild, "Tracked Crowd Control", yOffset)
    -- A class pick releases the seed checkboxes, so they have a manager of
    -- their own, cleared with them; the page's manager never drives a released one.
    local seedManager = GUIFrame:CreateWidgetStateManager()

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
            seedManager:UpdateAll(true)
            ApplySettings()
        end,
    }), 0.5)
    card2:AddRow(row2a, Theme.rowHeight)
    card2:AddSeparator()

    local classTokens, listed = {}, {}
    for _, seed in ipairs(seeds) do
        if not listed[seed.group] then
            listed[seed.group] = true
            classTokens[#classTokens + 1] = seed.group
        end
    end

    local mark
    local DrawClass

    local function Redraw(classToken)
        local oldHeight = card2:GetContentHeight()
        card2:TruncateBody(mark)
        DrawClass(classToken)
        GUIFrame:ResizeCardInPlace(card2, oldHeight)
    end

    DrawClass = function(classToken)
        seedManager:Clear()
        seedManager:SetCondition("seeds", function() return db.EveryCC ~= true end)
        local classSeeds = {}
        for _, seed in ipairs(seeds) do
            if seed.group == classToken then classSeeds[#classSeeds + 1] = seed end
        end
        local seedRow
        for index, seed in ipairs(classSeeds) do
            local key = seed.key
            local texture = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(seed.ids[1])
            if not seedRow then seedRow = GUIFrame:CreateRow(card2.content, SEED_CELL_H) end
            local cell = GUIFrame:CreateCompactCheckbox(seedRow, GUIFrame.IconText(texture) .. seed.label, {
                value = Rules.SeedEnabled(seed, db.Groups),
                callback = function(checked)
                    db.Groups[key] = { enabled = checked }
                    ApplySettings()
                end,
            })
            seedRow:AddWidget(cell, 1 / SEEDS_PER_ROW)
            seedManager:Register(cell, "seeds")
            if index % SEEDS_PER_ROW == 0 or index == #classSeeds then
                card2:AddRow(seedRow, SEED_CELL_H,
                    index == #classSeeds and Theme.paddingSmall or SEED_CELL_SPACING)
                seedRow = nil
            end
        end
        seedManager:UpdateAll(true)
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
                GUIFrame:RefreshContent()
            end,
            onRemove = function(text)
                local id, reason = Rules.CanRemove(text, seeds, db.CustomIDs)
                if not id then
                    KE:Print(reason)
                    return
                end
                db.CustomIDs[id] = nil
                ApplySettings()
                GUIFrame:RefreshContent()
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
    end

    local classRow, shownClass = GUIFrame:CreateClassPickerRow(card2.content, {
        scope = "CCTracker",
        classTokens = classTokens,
        onPick = function(key) Redraw(key) end,
    })
    card2:AddRow(classRow, 36)
    mark = card2:MarkBody()
    DrawClass(shownClass)
    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Display
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display", yOffset)
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
    row3b:AddWidget(GUIFrame:CreateSlider(row3b, "Max Enemies", {
        min = 1, max = 40, step = 1,
        value = db.MaxEnemies or 15,
        callback = function(value)
            db.MaxEnemies = value
            ApplySettings()
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
    card3:AddNote("The stack stays on screen up to the screen's height. The box kept on screen " ..
        "is Max Enemies rows tall, so lower it or grow away from a nearby edge. In a stack " ..
        "taller than the screen, the first rows stay on screen and the rest can run off the edge.")
    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Time Left
    ----------------------------------------------------------------
    local fontCard, _, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Time Left",
        db = db,
        dbKeys = {
            fontFace    = "TimerFontFace",
            fontOutline = "TimerFontOutline",
        },
        fontSizes = {
            { label = "Font Size", dbKey = "TimerFontSize", default = 20 },
        },
        fontSizeRange = { 8, 40 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end

    -- The card's own last row is added with no trailing gap, so re-open the
    -- spacing before appending to it.
    fontCard:AddSpacing(Theme.paddingSmall)
    local decimalRow = GUIFrame:CreateRow(fontCard.content, Theme.rowHeightLast)
    local decimalSlider = GUIFrame:CreateSlider(decimalRow, "Show Decimals Below (sec)", {
        min = 0, max = 10, step = 1,
        value = KE.AuraRules.NormalizeDecimalThreshold(db.DecimalThreshold),
        callback = function(value)
            db.DecimalThreshold = value
            ApplySettings()
        end,
    })
    decimalRow:AddWidget(decimalSlider, 0.5)
    manager:Register(decimalSlider, "all")
    fontCard:AddRow(decimalRow, Theme.rowHeightLast, 0)
    fontCard:AddSpacing(Theme.paddingSmall)
    fontCard:AddNote("The font and outline are also used for the enemy name.")
    yOffset = fontCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Enemy Name
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
    -- Card 6: Position
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
