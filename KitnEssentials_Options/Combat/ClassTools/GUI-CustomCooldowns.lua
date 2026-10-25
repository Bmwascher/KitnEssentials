-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CustomCooldowns.lua                                 ║
-- ║  GUI: Custom Cooldowns                                   ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║         CustomCooldowns module.                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("CustomCooldowns", true)
    end
    return nil
end

local GROW_DIRECTIONS = GUIFrame.GrowDirectionOptions
-- The Spec picker's All Specs choice; any other choice is a spec id.
local ALL_SPECS = "ALL"

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

GUIFrame:RegisterContent("CustomCooldowns", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CustomCooldowns
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local Rules = KE.CustomCooldownsRules
    local CCD = GetModule()
    -- The real attachment, not the saved box: with Combat Texts off the
    -- display stands alone and needs its own layout, position and font.
    local attached = CCD ~= nil and CCD:IsAttached()
    local function ApplySettings()
        if CCD then CCD:ApplySettings() end
    end

    ------------------------------------------------------------------
    -- Card 1: Module
    ------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Custom Cooldowns", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        ApplySettings()
    end)

    if db.Enabled ~= true then
        return yOffset + card1:GetContentHeight() + Theme.paddingSmall
    end
    card1:AddLabel("Tracks the cooldowns of spells you add for each class, as lines you can stack under Combat Texts.")
    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ------------------------------------------------------------------
    -- Card 2: Your Spells
    ------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Your Spells", yOffset)

    db.Spells = db.Spells or {}
    local _, playerClass = UnitClass("player")
    local classSpecs = GUIFrame.GetClassSpecs()
    local classTokens = {}
    for token in pairs(classSpecs) do classTokens[#classTokens + 1] = token end

    local mark
    local DrawClass
    -- The Spec pick per class, kept across the redraws Add and Remove make
    -- while the page stays drawn.
    local picked = {}

    local function Redraw(classToken)
        local oldHeight = card2:GetContentHeight()
        card2:TruncateBody(mark)
        DrawClass(classToken)
        GUIFrame:ResizeCardInPlace(card2, oldHeight)
    end

    -- A header and a checkbox per listed spell; a group with none draws nothing.
    local function DrawGroup(scope, title, icon, current)
        local ids = Rules.ScopeIds(db.Spells, scope)
        if #ids == 0 then return false end
        local header = GUIFrame:CreateRow(card2.content, 26)
        header:AddWidget(GUIFrame:CreateSpecHeaderRow(header, title, {
            icon = icon,
            current = current,
        }), 1)
        card2:AddRow(header, 26)
        for _, id in ipairs(ids) do
            local key = Rules.SpellKey(scope, id)
            local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
            local label = GUIFrame.IconText(texture) .. (SpellExists(id) or ("Spell " .. id))
            local line = GUIFrame:CreateRow(card2.content, 40)
            line:AddWidget(GUIFrame:CreateCheckbox(line, label, {
                value = db.Spells[key].enabled ~= false,
                callback = function(checked)
                    local entry = db.Spells[key]
                    if type(entry) == "table" then entry.enabled = checked end
                    ApplySettings()
                end,
            }), 1)
            card2:AddRow(line, 40)
        end
        return true
    end

    DrawClass = function(classToken)
        local currentSpecId = KE:GetPlayerSpecId()
        local specIds = classSpecs[classToken] or {}
        local any = DrawGroup(classToken, "All Specs", nil, false)
        for _, specId in ipairs(specIds) do
            local specName, specIcon = SpecInfo(specId)
            local current = specId == currentSpecId and classToken == playerClass
            if DrawGroup(specId, specName, specIcon, current) then any = true end
        end
        if not any then card2:AddLabel("No spells added for this class.") end

        card2:AddRow(GUIFrame:CreateSeparator(card2.content), Theme.rowHeightSeparator)

        local specOptions = { { key = ALL_SPECS, text = "All Specs" } }
        for _, specId in ipairs(specIds) do
            local specName, specIcon = SpecInfo(specId)
            specOptions[#specOptions + 1] = { key = specId, text = GUIFrame.IconText(specIcon) .. specName }
        end
        local chosen = picked[classToken] or ALL_SPECS
        local function ChosenSpec()
            if chosen == ALL_SPECS then return nil end
            return chosen
        end

        local addRow = GUIFrame:CreateSpellAddRow(card2.content, {
            picker = {
                label = "Spec",
                options = specOptions,
                value = chosen,
                callback = function(key)
                    chosen = key
                    picked[classToken] = key
                end,
            },
            idLabel = "Spell ID",
            onAdd = function(text)
                local spec = ChosenSpec()
                local id, reason = Rules.CanAdd(db.Spells, classToken, spec, text, SpellExists)
                if not id then
                    KE:Print(reason)
                    return
                end
                db.Spells[Rules.SpellKey(spec or classToken, id)] = { enabled = true }
                Redraw(classToken)
                ApplySettings()
            end,
            onRemove = function(text)
                local key, reason = Rules.CanRemove(db.Spells, classToken, ChosenSpec(), text)
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

        card2:AddNote("All Specs adds to every spec of the class; a spec adds to that spec only. " ..
            "A spell shows only where it is known.")
    end

    local classRow, shownClass = GUIFrame:CreateClassPickerRow(card2.content, {
        scope = "CustomCooldowns",
        classTokens = classTokens,
        onPick = function(key) Redraw(key) end,
    })
    card2:AddRow(classRow, 36)
    mark = card2:MarkBody()
    DrawClass(shownClass)
    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ------------------------------------------------------------------
    -- Card 3: Display Settings
    ------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)

    -- Attached, the lines are members of the Combat Texts stack and follow its order.
    if not attached then
        local row1 = GUIFrame:CreateRow(card3.content, 36)
        row1:AddWidget(GUIFrame:CreateDropdown(row1, "Growth Direction", {
            options = GROW_DIRECTIONS,
            value = db.GrowDirection or "DOWN",
            callback = function(key) db.GrowDirection = key; ApplySettings() end,
        }), 1)
        card3:AddRow(row1, 36)
    end

    local row2 = GUIFrame:CreateRow(card3.content, 40)
    row2:AddWidget(GUIFrame:CreateCheckbox(row2, "Show When Ready", {
        value = db.ShowWhenReady == true,
        callback = function(v) db.ShowWhenReady = v; ApplySettings() end,
    }), 0.5)
    row2:AddWidget(GUIFrame:CreateCheckbox(row2, "Hide Out of Combat", {
        value = db.HideOutOfCombat == true,
        callback = function(v) db.HideOutOfCombat = v; ApplySettings() end,
    }), 0.5)
    card3:AddRow(row2, 40)

    -- Spacing and Scale come from Combat Texts while attached.
    if not attached then
        local row3 = GUIFrame:CreateRow(card3.content, 44)
        row3:AddWidget(GUIFrame:CreateSlider(row3, "Spacing", {
            min = 0, max = 20, step = 1, value = db.Spacing or 2,
            callback = function(v) db.Spacing = v; ApplySettings() end,
        }), 0.5)
        row3:AddWidget(GUIFrame:CreateSlider(row3, "Scale", {
            min = 0.5, max = 2, step = 0.05, value = db.Scale or 1,
            callback = function(v) db.Scale = v; ApplySettings() end,
        }), 0.5)
        card3:AddRow(row3, 44)
    end

    local attachRow = GUIFrame:CreateRow(card3.content, 40)
    local attachCheck = GUIFrame:CreateCheckbox(attachRow, "Attach to Combat Texts", {
        value = db.AttachToCombatTexts == true,
        tooltip = "Stack the lines underneath the Combat Texts messages and move with them, instead of using a separate anchor.",
        callback = function(v)
            db.AttachToCombatTexts = v
            ApplySettings()
            GUIFrame:RefreshContent()
        end,
    })
    attachRow:AddWidget(attachCheck, 1)
    card3:AddRow(attachRow, 40)
    if db.AttachToCombatTexts and CCD ~= nil and not attached then
        GUIFrame:AddAttachOffNote(card3)
    end
    if attached then
        GUIFrame:CreateAttachSizeRow(card3, db, {
            sizeKey = "FontSize", default = 16, range = { 8, 48 },
            onChange = ApplySettings, isLast = true,
        })
    end

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ------------------------------------------------------------------
    -- Card 4: Position -- skipped while attached: Combat Texts owns it.
    ------------------------------------------------------------------
    if not attached then
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
    end

    ------------------------------------------------------------------
    -- Card 5: Font Settings -- from Combat Texts while attached.
    ------------------------------------------------------------------
    if not attached then
        local _, fontOffset = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
            title = "Font Settings",
            db = db,
            dbKeys = { fontFace = "FontFace", fontSize = "FontSize", fontOutline = "FontOutline" },
            fontSizeRange = { 8, 48 },
            onChangeCallback = ApplySettings,
        })
        yOffset = fontOffset
    end

    ------------------------------------------------------------------
    -- Card 6: Colors
    ------------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)

    local modeRow = GUIFrame:CreateRow(card6.content, 40)
    modeRow:AddWidget(GUIFrame:CreateDropdown(modeRow, "Color Mode", {
        options = {
            { key = "CUSTOM", text = "Custom" },
            { key = "THEME",  text = "Match Theme" },
        },
        value = db.ColorMode or "CUSTOM",
        tooltip = "Match Theme paints the name, timer and separator with the addon accent color, and hides the three pickers.",
        callback = function(v) db.ColorMode = v; ApplySettings(); GUIFrame:RefreshContent() end,
    }), 1)
    card6:AddRow(modeRow, 40)

    -- Hidden rather than grayed in theme mode: a disabled swatch still shows a
    -- color, which reads as the one in use.
    if db.ColorMode ~= "THEME" then
        local colorRow = GUIFrame:CreateRow(card6.content, 46)
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
        card6:AddRow(colorRow, 46)
    end

    local sepRow = GUIFrame:CreateRow(card6.content, 40)
    sepRow:AddWidget(GUIFrame:CreateEditBox(sepRow, "Separator", {
        value = db.Separator or "-",
        callback = function(text) db.Separator = text; ApplySettings() end,
    }), 1)
    card6:AddRow(sepRow, 40)

    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    ------------------------------------------------------------------
    -- Card 7: Sound
    ------------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Sound", yOffset)
    local soundRow = GUIFrame:CreateRow(card7.content, 40)
    soundRow:AddWidget(GUIFrame:CreateCheckbox(soundRow, "Play Sound When Ready", {
        value = db.SoundEnabled == true,
        callback = function(v) db.SoundEnabled = v; ApplySettings(); GUIFrame:RefreshContent() end,
    }), 0.5)
    if db.SoundEnabled then
        soundRow:AddWidget(GUIFrame:CreateDropdown(soundRow, "Sound", {
            options = GUIFrame.BuildSoundOptions(),
            searchable = true,
            value = db.Sound or "None",
            callback = function(key) db.Sound = key; ApplySettings() end,
        }), 0.5)
    end
    card7:AddRow(soundRow, 40)
    yOffset = yOffset + card7:GetContentHeight() + Theme.paddingMedium

    return yOffset
end)
