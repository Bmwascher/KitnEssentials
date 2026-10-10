-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ShamanProcCooldowns.lua                             ║
-- ║  GUI: Shaman Proc Cooldowns                              ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           ShamanProcCooldowns module.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local Rules = KE.ShamanProcRules

local ipairs = ipairs

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("ShamanProcCooldowns", true)
end

local MODES = {
    { key = "TEXT",  text = "Text" },
    { key = "ICONS", text = "Icons" },
}

local GROW_DIRECTIONS = {
    { key = "DOWN",  text = "Down" },
    { key = "UP",    text = "Up" },
    { key = "LEFT",  text = "Left" },
    { key = "RIGHT", text = "Right" },
}

local function BuildSoundOptions()
    local out = { { key = "None", text = "None" } }
    if KE.LSM then
        for _, name in ipairs(KE.LSM:List("sound")) do
            out[#out + 1] = { key = name, text = name }
        end
    end
    return out
end

-- The talent's name and a gray tag: the length its next proc would count, or
-- that the character lacks the talent.
local function TalentLabel(module, tracker)
    local length = module and module:NextLength(tracker)
    local tag = length and (length .. " s") or "not talented"
    return tracker.name .. "  |cff808080" .. tag .. "|r"
end

local function AddSeparator(card)
    local row = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
    row:AddWidget(GUIFrame:CreateSeparator(row), 1)
    card:AddRow(row, Theme.rowHeightSeparator)
end

GUIFrame:RegisterContent("ShamanProcCooldowns", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.ShamanProcCooldowns
    if not db then return yOffset end

    local SPC = GetModule()
    local function ApplySettings()
        if SPC then SPC:ApplySettings() end
    end
    -- For controls that add or remove rows.
    local function ApplyAndRedraw()
        ApplySettings()
        GUIFrame:RefreshContent()
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Shaman Proc Cooldowns", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if SPC then
            if checked then KitnEssentials:EnableModule("ShamanProcCooldowns")
            else KitnEssentials:DisableModule("ShamanProcCooldowns") end
        end
    end)
    card1:AddLabel("|cffffd100Shaman only.|r Counts down the internal cooldowns of Nature's Guardian " ..
        "and Thunderous Paws, which Blizzard's Cooldown Manager cannot show. A tracker appears " ..
        "only while you have its talent.")
    yOffset = card1:GetNextOffset()

    if db.Enabled ~= true then return yOffset end

    local icons = db.DisplayMode == "ICONS"
    -- The module's own predicate, not the saved box: with Combat Texts off the
    -- display keeps its own position and font, so their controls must show.
    local attached = SPC ~= nil and SPC:IsAttached()

    ----------------------------------------------------------------
    -- Card 2: Tracked Talents
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Tracked Talents", yOffset)
    local talentRow = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    for _, tracker in ipairs(Rules.TRACKERS) do
        local dbKey = tracker.dbKey
        talentRow:AddWidget(GUIFrame:CreateCheckbox(talentRow, TalentLabel(SPC, tracker), {
            value = db[dbKey] == true,
            callback = function(v) db[dbKey] = v; ApplySettings() end,
        }), 0.5)
    end
    card2:AddRow(talentRow, Theme.rowHeightLast, 0)
    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Display Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)

    local modeRow = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    modeRow:AddWidget(GUIFrame:CreateDropdown(modeRow, "Display Mode", {
        options = MODES,
        value = icons and "ICONS" or "TEXT",
        callback = function(key) db.DisplayMode = key; ApplyAndRedraw() end,
    }), 0.5)
    modeRow:AddWidget(GUIFrame:CreateCheckbox(modeRow, "Show When Ready", {
        value = db.ShowWhenReady == true,
        tooltip = "Keep a tracker on screen while it is ready, not only while it counts down.",
        callback = function(v) db.ShowWhenReady = v; ApplySettings() end,
    }), 0.5)
    card3:AddRow(modeRow, Theme.rowHeight)

    local combatRow = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    combatRow:AddWidget(GUIFrame:CreateCheckbox(combatRow, "Hide Out of Combat", {
        value = db.HideOutOfCombat == true,
        callback = function(v) db.HideOutOfCombat = v; ApplySettings() end,
    }), 0.5)
    card3:AddRow(combatRow, Theme.rowHeight)

    if icons then
        AddSeparator(card3)

        local sizeRow = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        sizeRow:AddWidget(GUIFrame:CreateSlider(sizeRow, "Icon Size", {
            min = 20, max = 100, step = 1, value = db.IconSize or 44,
            callback = function(v) db.IconSize = v; ApplySettings() end,
        }), 0.5)
        sizeRow:AddWidget(GUIFrame:CreateSlider(sizeRow, "Icon Spacing", {
            min = 0, max = 20, step = 1, value = db.IconSpacing or 2,
            callback = function(v) db.IconSpacing = v; ApplySettings() end,
        }), 0.5)
        card3:AddRow(sizeRow, Theme.rowHeight)

        local growRow = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
        growRow:AddWidget(GUIFrame:CreateDropdown(growRow, "Growth Direction", {
            options = GROW_DIRECTIONS,
            value = db.IconGrowDirection or "RIGHT",
            callback = function(key) db.IconGrowDirection = key; ApplySettings() end,
        }), 0.5)
        growRow:AddWidget(GUIFrame:CreateSlider(growRow, "Show Decimals Below (sec)", {
            min = 0, max = 10, step = 1, value = db.DecimalThreshold or 5,
            callback = function(v) db.DecimalThreshold = v; ApplySettings() end,
        }), 0.5)
        card3:AddRow(growRow, Theme.rowHeightLast, 0)
    else
        -- Attached, the lines follow the Combat Texts stack.
        if not attached then
            AddSeparator(card3)

            local layoutRow = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
            layoutRow:AddWidget(GUIFrame:CreateDropdown(layoutRow, "Growth Direction", {
                options = GROW_DIRECTIONS,
                value = db.GrowDirection or "DOWN",
                callback = function(key) db.GrowDirection = key; ApplySettings() end,
            }), 0.5)
            layoutRow:AddWidget(GUIFrame:CreateSlider(layoutRow, "Spacing", {
                min = 0, max = 20, step = 1, value = db.Spacing or 2,
                callback = function(v) db.Spacing = v; ApplySettings() end,
            }), 0.5)
            card3:AddRow(layoutRow, Theme.rowHeight)
        end

        local attachRow = GUIFrame:CreateRow(card3.content, attached and Theme.rowHeight or Theme.rowHeightLast)
        attachRow:AddWidget(GUIFrame:CreateCheckbox(attachRow, "Attach to Combat Texts", {
            value = db.AttachToCombatTexts == true,
            tooltip = "Show the lines in the Combat Texts stack and move with it, instead of using a separate anchor.",
            callback = function(v) db.AttachToCombatTexts = v; ApplyAndRedraw() end,
        }), 1)
        if attached then
            card3:AddRow(attachRow, Theme.rowHeight)
            GUIFrame:CreateAttachSizeRow(card3, db, {
                sizeKey = "FontSize", default = 16, range = { 8, 48 },
                onChange = ApplySettings, isLast = true,
            })
        else
            card3:AddRow(attachRow, Theme.rowHeightLast, 0)
        end
    end
    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Cards 4 and 5: Position and Font. Combat Texts owns both while
    -- attached.
    ----------------------------------------------------------------
    if not attached then
        local _, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
            db = db.Position,
            dbKeys = {
                selfPoint   = "AnchorFrom",
                anchorPoint = "AnchorTo",
                xOffset     = "XOffset",
                yOffset     = "YOffset",
            },
            showAnchorFrameType = false,
            showStrata = false,
            onChangeCallback = ApplySettings,
        })
        yOffset = posOffset

        local _, fontOffset = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
            title = "Font",
            db = db,
            dbKeys = {
                fontFace    = "FontFace",
                fontSize    = icons and "TimerFontSize" or "FontSize",
                fontOutline = "FontOutline",
            },
            fontSizeRange = icons and { 8, 32 } or { 8, 48 },
            onChangeCallback = ApplySettings,
        })
        yOffset = fontOffset
    end

    ----------------------------------------------------------------
    -- Card 6: Colors (text mode)
    ----------------------------------------------------------------
    if not icons then
        local card6 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)

        local colorRow = GUIFrame:CreateRow(card6.content, 46)
        colorRow:AddWidget(GUIFrame:CreateColorPicker(colorRow, "Name Color", {
            color = db.TextColor,
            callback = function(r, g, b, a) db.TextColor = { r, g, b, a }; ApplySettings() end,
        }), 0.34)
        colorRow:AddWidget(GUIFrame:CreateColorPicker(colorRow, "Timer Color", {
            color = db.TimerColor,
            callback = function(r, g, b, a) db.TimerColor = { r, g, b, a }; ApplySettings() end,
        }), 0.33)
        colorRow:AddWidget(GUIFrame:CreateColorPicker(colorRow, "Separator Color", {
            color = db.SeparatorColor,
            callback = function(r, g, b, a) db.SeparatorColor = { r, g, b, a }; ApplySettings() end,
        }), 0.33)
        card6:AddRow(colorRow, 46)

        local readyRow = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
        readyRow:AddWidget(GUIFrame:CreateColorPicker(readyRow, "Ready Color", {
            color = db.ReadyColor,
            callback = function(r, g, b, a) db.ReadyColor = { r, g, b, a }; ApplySettings() end,
        }), 0.5)
        readyRow:AddWidget(GUIFrame:CreateEditBox(readyRow, "Separator", {
            value = db.Separator or "-",
            callback = function(text) db.Separator = text; ApplySettings() end,
        }), 0.5)
        card6:AddRow(readyRow, Theme.rowHeightLast, 0)

        yOffset = card6:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 7: Sound
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Sound", yOffset)
    local soundRow = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
    soundRow:AddWidget(GUIFrame:CreateCheckbox(soundRow, "Play Sound When Ready", {
        value = db.SoundEnabled == true,
        callback = function(v) db.SoundEnabled = v; ApplyAndRedraw() end,
    }), 0.5)
    if db.SoundEnabled then
        soundRow:AddWidget(GUIFrame:CreateDropdown(soundRow, "Sound", {
            options = BuildSoundOptions(),
            searchable = true,
            value = db.Sound or "None",
            callback = function(key) db.Sound = key; ApplySettings() end,
        }), 0.5)
    end
    card7:AddRow(soundRow, Theme.rowHeightLast, 0)
    yOffset = card7:GetNextOffset()

    return yOffset
end)
