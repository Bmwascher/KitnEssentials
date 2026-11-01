-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SpellReflect.lua                                    ║
-- ║  GUI: Spell Reflect                                      ║
-- ║  Purpose: Configuration panel for the SpellReflect       ║
-- ║           module (Class Tools > Warrior).                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local Rules = KE.SpellReflectRules

local math_min = math.min
local type = type

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("SpellReflect", true)
end

local DISPLAY_MODES = {
    { key = "ICON", text = "Icon" },
    { key = "TEXT", text = "Text" },
}

local SPELL_MODES = {
    { key = "ALWAYS", text = "Always" },
    { key = "READY",  text = "When Reflect is ready" },
    { key = "OFF",    text = "Off" },
}

local function SpellLabel(data, spellId)
    if not data then return "Spell " .. spellId .. "  |cff808080(no boss data)|r" end
    return (data.name or "?") .. " - " .. (data.boss or "?")
end

GUIFrame:RegisterContent("SpellReflect", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.SpellReflect
    if not db then return yOffset end

    local SR = GetModule()
    local function ApplySettings()
        if SR then SR:ApplySettings() end
    end
    -- For controls that add or remove rows.
    local function ApplyAndRedraw()
        ApplySettings()
        GUIFrame:RefreshContent()
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Spell Reflect", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if SR then
            if checked then KitnEssentials:EnableModule("SpellReflect")
            else KitnEssentials:DisableModule("SpellReflect") end
        end
    end)
    card1:AddLabel(KE:Gold("Warrior only.") .. " Counts down to the boss casts this season that Spell " ..
        "Reflection can catch, turns green while a press would still be up when the hit lands, and turns " ..
        "red with NO REFLECT while Spell Reflection is on cooldown.\n\n" ..
        "Needs " .. KE:Gold("BigWigs") .. " with its dungeon modules (" .. KE:Gold("LittleWigs") ..
        ") in its default timer mode.")
    if not BigWigsLoader then
        card1:AddNote(KE:Gold("BigWigs") .. " is not loaded, so no cue will show.")
    end
    if db.Enabled ~= true then return card1:GetNextOffset() end

    local testRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    testRow:AddWidget(GUIFrame:CreateButton(testRow, "Test", {
        width = 160,
        height = 26,
        tooltip = "Runs a 6 second Void Blast countdown. Press Spell Reflection while it is green to see it hide.",
        callback = function()
            if SR then SR:Test() end
        end,
    }), 1)
    card1:AddRow(testRow, Theme.rowHeightLast, 0)
    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Spells
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Spells", yOffset)
    local index = Rules.Index(KE.EncounterData)
    local spells = Rules.SPELLS
    for i = 1, #spells, 2 do
        local last = i + 2 > #spells
        local height = last and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(card2.content, height)
        for j = i, math_min(i + 1, #spells) do
            local spellId = spells[j].id
            row:AddWidget(GUIFrame:CreateDropdown(row, SpellLabel(index[spellId], spellId), {
                options = SPELL_MODES,
                value = Rules.ModeOf(db.Modes, spellId),
                callback = function(key)
                    if type(db.Modes) ~= "table" then db.Modes = {} end
                    Rules.SetMode(db.Modes, spellId, key)
                    ApplySettings()
                end,
            }), 0.5)
        end
        card2:AddRow(row, height, last and 0 or nil)
    end
    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Display Settings
    ----------------------------------------------------------------
    local textMode = db.DisplayMode == "TEXT"
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)

    local modeHeight = textMode and Theme.rowHeightLast or Theme.rowHeight
    local modeRow = GUIFrame:CreateRow(card3.content, modeHeight)
    modeRow:AddWidget(GUIFrame:CreateDropdown(modeRow, "Display Mode", {
        options = DISPLAY_MODES,
        value = textMode and "TEXT" or "ICON",
        callback = function(key) db.DisplayMode = key; ApplyAndRedraw() end,
    }), 0.5)
    modeRow:AddWidget(GUIFrame:CreateSlider(modeRow, "Show Before Cast (sec)", {
        min = 5, max = 15, step = 1, value = db.Lead or 5,
        callback = function(v) db.Lead = v; ApplySettings() end,
    }), 0.5)
    card3:AddRow(modeRow, modeHeight, textMode and 0 or nil)

    if not textMode then
        local sizeRow = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        sizeRow:AddWidget(GUIFrame:CreateSlider(sizeRow, "Icon Size", {
            min = 24, max = 120, step = 1, value = db.IconSize or 56,
            callback = function(v) db.IconSize = v; ApplySettings() end,
        }), 0.5)
        sizeRow:AddWidget(GUIFrame:CreateSlider(sizeRow, "Spell Name Size", {
            min = 8, max = 32, step = 1, value = db.NameFontSize or 14,
            callback = function(v) db.NameFontSize = v; ApplySettings() end,
        }), 0.5)
        card3:AddRow(sizeRow, Theme.rowHeight)

        local nameRow = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
        nameRow:AddWidget(GUIFrame:CreateCheckbox(nameRow, "Show Spell Name", {
            value = db.ShowSpellName ~= false,
            callback = function(v) db.ShowSpellName = v; ApplySettings() end,
        }), 0.5)
        nameRow:AddWidget(GUIFrame:CreateCheckbox(nameRow, "Spell Icons Beside Name", {
            value = db.ShowNameIcons ~= false,
            callback = function(v) db.ShowNameIcons = v; ApplySettings() end,
        }), 0.5)
        card3:AddRow(nameRow, Theme.rowHeightLast, 0)
    end
    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Cards 4 and 5: Position and Font
    ----------------------------------------------------------------
    local _, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        positionKey = "Position",
        dbKeys = {
            selfPoint   = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset     = "XOffset",
            yOffset     = "YOffset",
        },
        showStrata = false,
        onChangeCallback = ApplySettings,
    })
    yOffset = posOffset

    local _, fontOffset = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontSize    = textMode and "TextSize" or "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = textMode and { 12, 48 } or { 8, 48 },
        onChangeCallback = ApplySettings,
    })
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 6: Colors
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    local colorRow = GUIFrame:CreateRow(card6.content, 46)
    colorRow:AddWidget(GUIFrame:CreateColorPicker(colorRow, "Text Color", {
        color = db.TextColor,
        callback = function(r, g, b, a) db.TextColor = { r, g, b, a }; ApplySettings() end,
    }), 0.5)
    colorRow:AddWidget(GUIFrame:CreateColorPicker(colorRow, "In Window Color", {
        color = db.GoColor,
        callback = function(r, g, b, a) db.GoColor = { r, g, b, a }; ApplySettings() end,
    }), 0.5)
    card6:AddRow(colorRow, 46, 0)
    yOffset = card6:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Glow (icon mode; text mode draws no glow)
    ----------------------------------------------------------------
    if not textMode then
        local card7 = GUIFrame:CreateCard(scrollChild, "Glow", yOffset)
        local glowRow = GUIFrame:CreateRow(card7.content, 46)
        glowRow:AddWidget(GUIFrame:CreateCheckbox(glowRow, "Glow In Window", {
            value = db.Glow ~= false,
            callback = function(v) db.Glow = v; ApplySettings() end,
        }), 0.5)
        glowRow:AddWidget(GUIFrame:CreateColorPicker(glowRow, "Glow Color", {
            color = db.GlowColor,
            callback = function(r, g, b, a) db.GlowColor = { r, g, b, a }; ApplySettings() end,
        }), 0.5)
        card7:AddRow(glowRow, 46, 0)
        yOffset = card7:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 8: Sound
    ----------------------------------------------------------------
    local card8 = GUIFrame:CreateCard(scrollChild, "Sound", yOffset)
    local soundRow = GUIFrame:CreateRow(card8.content, Theme.rowHeightLast)
    soundRow:AddWidget(GUIFrame:CreateDropdown(soundRow, "Window Opens", {
        options = GUIFrame.BuildSoundOptions(),
        searchable = true,
        value = db.ReadySound or "None",
        callback = function(key) db.ReadySound = key; ApplySettings() end,
    }), 0.5)
    soundRow:AddWidget(GUIFrame:CreateDropdown(soundRow, "Window Opens, Reflect Not Ready", {
        options = GUIFrame.BuildSoundOptions(),
        searchable = true,
        value = db.NotReadySound or "None",
        callback = function(key) db.NotReadySound = key; ApplySettings() end,
    }), 0.5)
    card8:AddRow(soundRow, Theme.rowHeightLast, 0)
    yOffset = card8:GetNextOffset()

    return yOffset
end)
