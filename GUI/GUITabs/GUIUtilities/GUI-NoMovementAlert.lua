-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-NoMovementAlert.lua                                 ║
-- ║  GUI: No Movement Alert                                  ║
-- ║  Purpose: Configuration panel for the NoMovementAlert    ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("NoMovementAlert", true)
    end
    return nil
end

local GROW_DIRECTIONS = {
    { key = "DOWN",  text = "Down" },
    { key = "UP",    text = "Up" },
    { key = "LEFT",  text = "Left" },
    { key = "RIGHT", text = "Right" },
}

-- Spec header with a 1px black border around the icon.
local function SpecHeader(parent, iconPath, labelText)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(26)

    local border = row:CreateTexture(nil, "BACKGROUND")
    border:SetSize(20, 20)
    border:SetPoint("LEFT", row, "LEFT", 0, 0)
    border:SetColorTexture(0, 0, 0, 1)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", border, "CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if iconPath then icon:SetTexture(iconPath) else border:Hide() end

    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("LEFT", border, "RIGHT", 6, 0)
    fs:SetJustifyH("LEFT")
    KE:ApplyThemeFont(fs, "large")
    fs:SetText(labelText)
    fs:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)

    return row
end

local function BuildSoundOptions()
    local out = { { key = "None", text = "None" } }
    if KE.LSM then
        for _, name in ipairs(KE.LSM:List("sound")) do
            out[#out + 1] = { key = name, text = name }
        end
    end
    return out
end

GUIFrame:RegisterContent("NoMovementAlert", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.NoMovementAlert
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local NMA = GetModule()
    local function ApplySettings()
        if NMA then NMA:ApplySettings() end
    end

    ------------------------------------------------------------------
    -- Card 1: Module
    ------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "No Movement Alert", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        ApplySettings()
        GUIFrame:RefreshContent()
    end)
    card1:AddLabel("Tracks your specialization's mobility cooldowns on screen, so you always know when your gap-closer or escape is back up. Spells with no cooldown are tracked by their buff instead.")

    if db.Enabled ~= true then
        return yOffset + card1:GetContentHeight() + Theme.paddingSmall
    end
    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ------------------------------------------------------------------
    -- Card 2: Display Settings
    ------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)

    -- Growth direction is Combat Texts' business while attached: our
    -- lines are members of its stack, so they follow its order.
    if not db.AttachToCombatTexts then
        local row1 = GUIFrame:CreateRow(card2.content, 36)
        row1:AddWidget(GUIFrame:CreateDropdown(row1, "Growth Direction", {
            options = GROW_DIRECTIONS,
            value = db.GrowDirection or "DOWN",
            callback = function(key) db.GrowDirection = key; ApplySettings() end,
        }), 1)
        card2:AddRow(row1, 36)
    end

    local row2 = GUIFrame:CreateRow(card2.content, 40)
    row2:AddWidget(GUIFrame:CreateCheckbox(row2, "Show When Ready", {
        value = db.ShowWhenReady == true,
        callback = function(v) db.ShowWhenReady = v; ApplySettings() end,
    }), 0.5)
    row2:AddWidget(GUIFrame:CreateCheckbox(row2, "Hide Out of Combat", {
        value = db.HideOutOfCombat == true,
        callback = function(v) db.HideOutOfCombat = v; ApplySettings() end,
    }), 0.5)
    card2:AddRow(row2, 40)

    -- Spacing/Scale are inherited from Combat Texts while attached.
    if not db.AttachToCombatTexts then
        local row3 = GUIFrame:CreateRow(card2.content, 44)
        row3:AddWidget(GUIFrame:CreateSlider(row3, "Spacing", {
            min = 0, max = 20, step = 1, value = db.Spacing or 2,
            callback = function(v) db.Spacing = v; ApplySettings() end,
        }), 0.5)
        row3:AddWidget(GUIFrame:CreateSlider(row3, "Scale", {
            min = 0.5, max = 2, step = 0.05, value = db.Scale or 1,
            callback = function(v) db.Scale = v; ApplySettings() end,
        }), 0.5)
        card2:AddRow(row3, 44)
    end

    local attachRow = GUIFrame:CreateRow(card2.content, 40)
    local attachCheck = GUIFrame:CreateCheckbox(attachRow, "Attach to Combat Texts", {
        value = db.AttachToCombatTexts == true,
        tooltip = "Stack the alerts underneath the Combat Texts messages and move with them, instead of using a separate anchor.",
        callback = function(v)
            db.AttachToCombatTexts = v
            ApplySettings()
            GUIFrame:RefreshContent()
        end,
    })
    attachRow:AddWidget(attachCheck, 1)
    card2:AddRow(attachRow, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ------------------------------------------------------------------
    -- Card 3: Position -- skipped entirely while attached, since Combat
    -- Texts owns the anchor and these values would write to nothing.
    ------------------------------------------------------------------
    if not db.AttachToCombatTexts then
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
    end

    ------------------------------------------------------------------
    -- Card 4: Font -- inherited from Combat Texts while attached.
    ------------------------------------------------------------------
    if not db.AttachToCombatTexts then
        local _, fontOffset = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
            title = "Font",
            db = db,
            dbKeys = { fontFace = "FontFace", fontSize = "FontSize", fontOutline = "FontOutline" },
            fontSizeRange = { 8, 48 },
            onChangeCallback = ApplySettings,
        })
        yOffset = fontOffset
    end

    ------------------------------------------------------------------
    -- Card 5: Colors
    ------------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    local colorRow = GUIFrame:CreateRow(card5.content, 46)
    colorRow:AddWidget(GUIFrame:CreateColorPicker(colorRow, "Text Color", {
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
    card5:AddRow(colorRow, 46)

    local sepRow = GUIFrame:CreateRow(card5.content, 40)
    sepRow:AddWidget(GUIFrame:CreateEditBox(sepRow, "Separator", {
        value = db.Separator or "-",
        callback = function(text) db.Separator = text; ApplySettings() end,
    }), 1)
    card5:AddRow(sepRow, 40)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ------------------------------------------------------------------
    -- Card 6: Sound
    ------------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Sound", yOffset)
    local soundRow = GUIFrame:CreateRow(card6.content, 40)
    soundRow:AddWidget(GUIFrame:CreateCheckbox(soundRow, "Play Sound When Ready", {
        value = db.SoundEnabled == true,
        callback = function(v) db.SoundEnabled = v; ApplySettings(); GUIFrame:RefreshContent() end,
    }), 0.5)
    if db.SoundEnabled then
        soundRow:AddWidget(GUIFrame:CreateDropdown(soundRow, "Sound", {
            options = BuildSoundOptions(),
            value = db.Sound or "None",
            callback = function(key) db.Sound = key; ApplySettings() end,
        }), 0.5)
    end
    card6:AddRow(soundRow, 40)
    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    ------------------------------------------------------------------
    -- Card 7: Tracked Spells
    -- The drift escape hatch: hardcoded spell IDs go stale every patch,
    -- so users can untick a preset or re-enable one we ship disabled
    -- without waiting on a build.
    ------------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Tracked Spells", yOffset)
    -- Every spec of the class, not just the active one -- you should be
    -- able to set up your off-specs without respeccing first. Overrides
    -- are keyed by spellID, so a spell shared across specs (Roll on all
    -- three Monk specs) is one setting shown in each place.
    card7:AddLabel("All specializations for the selected class. Unticking a spell stops tracking it on that spec only; other specs keep their own setting.")

    db.Spells = db.Spells or {}
    local _, playerClass = UnitClass("player")
    local currentSpecId
    if GetSpecialization then
        local idx = GetSpecialization()
        if idx and idx > 0 and GetSpecializationInfo then currentSpecId = GetSpecializationInfo(idx) end
    end

    -- Class picker -- overrides are account/profile data, not character
    -- data, so an author building a profile for subscribers needs to
    -- reach every class, not just the one they happen to be on.
    local classOptions = {}
    for token in pairs(KE.MOVEMENT_ABILITIES or {}) do
        local label = (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[token]) or token
        if token == playerClass then label = label .. "  " .. KE:ColorTextByTheme("(current)") end
        classOptions[#classOptions + 1] = { key = token, text = label }
    end
    table.sort(classOptions, function(a, b) return a.text < b.text end)

    db.SpellEditorClass = db.SpellEditorClass or playerClass
    local shownClass = db.SpellEditorClass
    if not (KE.MOVEMENT_ABILITIES and KE.MOVEMENT_ABILITIES[shownClass]) then
        shownClass = playerClass
    end

    local classRow = GUIFrame:CreateRow(card7.content, 36)
    local classDropdown
    classDropdown = GUIFrame:CreateDropdown(classRow, "Class", {
        options = classOptions,
        value = shownClass,
        callback = function(key)
            db.SpellEditorClass = key
            -- Close the list instantly, THEN rebuild a frame later: the
            -- animated close was still running when the rebuild hit, and
            -- the orphaned list frame flashed at the bottom of the screen.
            if classDropdown and classDropdown._closeDropdown then
                classDropdown._closeDropdown(true)
            end
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end,
    })
    classRow:AddWidget(classDropdown, 1)
    card7:AddRow(classRow, 36)

    local byClass = KE.MOVEMENT_ABILITIES and KE.MOVEMENT_ABILITIES[shownClass]

    if byClass then
        local specIds = {}
        for specId in pairs(byClass) do
            if type(specId) == "number" then specIds[#specIds + 1] = specId end
        end
        table.sort(specIds)

        for _, specId in ipairs(specIds) do
            local specName, specIcon = "Spec " .. specId, nil
            if GetSpecializationInfoByID then
                local _, n, _, icon = GetSpecializationInfoByID(specId)
                if n then specName = n end
                specIcon = icon
            end
            local headerText = specName
            if specId == currentSpecId and shownClass == playerClass then
                headerText = headerText .. "  " .. KE:ColorTextByTheme("(current)")
            end
            local header = GUIFrame:CreateRow(card7.content, 26)
            header:AddWidget(SpecHeader(header, specIcon, headerText), 1)
            card7:AddRow(header, 26)

            -- Collapse by NAME. Several presets are the same ability under
            -- different IDs (Wild Charge has a spell per form; Death
            -- Charge ships two) -- listing each ID showed the user "Wild
            -- Charge" three times. One row per ability, and the checkbox
            -- writes every ID behind that name so the alias group stays
            -- consistent.
            local order, byName = {}, {}
            for _, spellId in ipairs(byClass[specId]) do
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
                local name = (info and info.name) or ("Spell " .. spellId)
                if not byName[name] then
                    byName[name] = {}
                    order[#order + 1] = name
                end
                table.insert(byName[name], spellId)
            end

            -- Three per row: these are short labels and the card is wide.
            local pending, PER_ROW = nil, 3
            for idx, name in ipairs(order) do
                local ids = byName[name]
                local key1 = KE.MOVEMENT_SPELL_KEY(specId, ids[1])
                local override = db.Spells[key1] or db.Spells[tostring(ids[1])]
                local enabled
                if override and override.enabled ~= nil then
                    enabled = override.enabled ~= false
                else
                    enabled = not (KE.MOVEMENT_DEFAULT_OFF and KE.MOVEMENT_DEFAULT_OFF[ids[1]])
                end

                if not pending then pending = GUIFrame:CreateRow(card7.content, 36) end
                pending:AddWidget(GUIFrame:CreateCheckbox(pending, name, {
                    value = enabled,
                    callback = function(v)
                        for _, id in ipairs(ids) do
                            local k = KE.MOVEMENT_SPELL_KEY(specId, id)
                            db.Spells[k] = db.Spells[k] or {}
                            db.Spells[k].enabled = v
                            -- The legacy account-wide key is LEFT IN PLACE.
                            -- Deleting it here would silently rewrite every
                            -- OTHER spec: they have no per-spec entry yet
                            -- and are resolving through that legacy value,
                            -- so removing it drops them to the preset
                            -- default -- ticking Wild Charge on Balance
                            -- would turn it on for Feral and Guardian too.
                            -- Keeping it makes it exactly what it should
                            -- be: the fallback for specs the user has not
                            -- set explicitly.
                        end
                        ApplySettings()
                        C_Timer.After(0, function() GUIFrame:RefreshContent() end)
                    end,
                }), 1 / PER_ROW)

                if idx % PER_ROW == 0 or idx == #order then
                    card7:AddRow(pending, 36)
                    pending = nil
                end
            end
        end
    else
        card7:AddLabel("No mobility presets for this class.")
    end
    yOffset = yOffset + card7:GetContentHeight() + Theme.paddingMedium

    return yOffset
end)
