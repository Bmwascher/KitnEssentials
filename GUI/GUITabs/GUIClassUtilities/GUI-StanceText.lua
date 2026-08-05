-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-StanceText.lua                                      ║
-- ║  GUI: Stance Text                                        ║
-- ║  Purpose: Configuration panel for the StanceText module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM

local table_insert = table.insert
local ipairs, pairs = ipairs, pairs
local tostring = tostring

local CLASS_TITLES = {
    WARRIOR = "Warrior Stances",
    PALADIN = "Paladin Auras",
    DRUID   = "Druid Forms",
    PRIEST  = "Priest Shadowform",
    EVOKER  = "Evoker Attunement",
}

-- Icon plus name, drawn above each spec's controls so a card of five near
-- identical rows reads as a list of specs rather than a wall of checkboxes.
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

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("StanceText", true)
end

local function ApplySettings()
    local mod = GetModule()
    if mod and mod.ApplySettings then mod:ApplySettings() end
end

GUIFrame:RegisterContent("StanceText", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.StanceText
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local mod = GetModule()
    local allWidgets = {}
    local subCards = {}

    local function UpdateAllWidgetStates()
        local enabled = db.Enabled == true
        for _, c in ipairs(subCards) do
            if c.SetAlpha then c:SetAlpha(enabled and 1 or 0.4) end
        end
        for _, w in ipairs(allWidgets) do
            if w.SetEnabled then w:SetEnabled(enabled) end
        end
    end

    ------------------------------------------------------------------
    -- Card 1: Master Enable
    ------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Stance Text", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if checked then
            KitnEssentials:EnableModule("StanceText")
        else
            KitnEssentials:DisableModule("StanceText")
        end
        GUIFrame:RefreshContent()
    end)
    card1:AddLabel("Shows an icon when your spec is not in the form, stance or aura it should be in.")

    if db.Enabled ~= true then
        return yOffset + card1:GetContentHeight() + Theme.paddingSmall
    end
    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ------------------------------------------------------------------
    -- Card 2: Icon
    ------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Icon", yOffset)
    table_insert(subCards, card2)

    local row2 = GUIFrame:CreateRow(card2.content, 40)
    local sizeSlider = GUIFrame:CreateSlider(row2, "Icon Size", {
        min = 20, max = 100, step = 1, value = db.IconSize or 44,
        callback = function(v) db.IconSize = v; ApplySettings() end,
    })
    row2:AddWidget(sizeSlider, 0.5)
    local alphaSlider = GUIFrame:CreateSlider(row2, "Opacity", {
        min = 0.1, max = 1, step = 0.05, value = db.Alpha or 1,
        callback = function(v) db.Alpha = v; ApplySettings() end,
    })
    row2:AddWidget(alphaSlider, 0.5)
    table_insert(allWidgets, sizeSlider)
    table_insert(allWidgets, alphaSlider)
    card2:AddRow(row2, 40)

    -- No background colour option: the icon texture fills the frame, so a
    -- background behind it is never visible. Border only.
    local row2b = GUIFrame:CreateRow(card2.content, 46)
    local borderColor = GUIFrame:CreateColorPicker(row2b, "Border Color", {
        color = db.BorderColor,
        callback = function(r, g, b, a) db.BorderColor = { r, g, b, a }; ApplySettings() end,
    })
    row2b:AddWidget(borderColor, 0.5)
    table_insert(allWidgets, borderColor)
    card2:AddRow(row2b, 46)

    -- No Preview button: PreviewManager shows this module whenever the page is
    -- open or edit mode is on.
    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ------------------------------------------------------------------
    -- Card 3: Text
    ------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Text", yOffset)
    table_insert(subCards, card3)

    local rowT = GUIFrame:CreateRow(card3.content, 40)
    local showText = GUIFrame:CreateCheckbox(rowT, "Show Text", {
        value = db.ShowText ~= false,
        callback = function(checked) db.ShowText = checked; ApplySettings() end,
    })
    rowT:AddWidget(showText, 0.5)
    local textColor = GUIFrame:CreateColorPicker(rowT, "Text Color", {
        color = db.TextColor,
        callback = function(r, g, b, a) db.TextColor = { r, g, b, a }; ApplySettings() end,
    })
    rowT:AddWidget(textColor, 0.5)
    table_insert(allWidgets, showText)
    table_insert(allWidgets, textColor)
    card3:AddRow(rowT, 40)

    local rowT2 = GUIFrame:CreateRow(card3.content, 40)
    local textInput = GUIFrame:CreateEditBox(rowT2, "Text", {
        value = db.Text or "MISSING",
        callback = function(value) db.Text = value; ApplySettings() end,
    })
    rowT2:AddWidget(textInput, 1)
    table_insert(allWidgets, textInput)
    card3:AddRow(rowT2, 40)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            table_insert(fontList, { key = name, text = name })
        end
        table.sort(fontList, function(a, b) return a.text < b.text end)
    else
        table_insert(fontList, { key = "Friz Quadrata TT", text = "Friz Quadrata TT" })
    end

    local rowT3 = GUIFrame:CreateRow(card3.content, 40)
    local fontDrop = GUIFrame:CreateDropdown(rowT3, "Font", {
        options = fontList,
        value = db.FontFace,
        callback = function(value) db.FontFace = value; ApplySettings() end,
    })
    rowT3:AddWidget(fontDrop, 0.34)
    local fontSize = GUIFrame:CreateSlider(rowT3, "Font Size", {
        min = 8, max = 32, step = 1, value = db.FontSize or 14,
        callback = function(v) db.FontSize = v; ApplySettings() end,
    })
    rowT3:AddWidget(fontSize, 0.33)
    -- Soft Outline is added here for the caption's own renderer
    -- (KE:ApplyFontToText), which the reference does not have.
    local outlineDrop = GUIFrame:CreateDropdown(rowT3, "Outline", {
        options = {
            { key = "NONE",         text = "None" },
            { key = "OUTLINE",      text = "Outline" },
            { key = "THICKOUTLINE", text = "Thick" },
            { key = "SOFTOUTLINE",  text = "Soft Outline" },
        },
        value = db.FontOutline,
        callback = function(value) db.FontOutline = value; ApplySettings() end,
    })
    rowT3:AddWidget(outlineDrop, 0.33)
    table_insert(allWidgets, fontDrop)
    table_insert(allWidgets, fontSize)
    table_insert(allWidgets, outlineDrop)
    card3:AddRow(rowT3, 40)
    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ------------------------------------------------------------------
    -- One card per class, ALL classes -- settings can be prepared for an
    -- alt without logging into it.
    ------------------------------------------------------------------
    local currentSpecId
    if GetSpecialization and GetSpecializationInfo then
        local idx = GetSpecialization()
        if idx and idx > 0 then currentSpecId = GetSpecializationInfo(idx) end
    end

    if mod and mod.CLASS_ORDER then
        for _, classKey in ipairs(mod.CLASS_ORDER) do
            local card = GUIFrame:CreateCard(scrollChild, CLASS_TITLES[classKey] or classKey, yOffset)
            table_insert(subCards, card)

            for _, specID in ipairs(mod.CLASS_SPECS[classKey]) do
                local entry = mod.SPECS[specID]
                local key = tostring(specID)
                local specName = mod.SPEC_NAMES[specID] or key
                local wantedName = mod.SPELL_NAMES[entry.spellID] or ""

                local specIcon
                if GetSpecializationInfoByID then
                    local _, n, _, icon = GetSpecializationInfoByID(specID)
                    if n then specName = n end
                    specIcon = icon
                end
                local headerText = specName
                if specID == currentSpecId then
                    headerText = headerText .. "  " .. KE:ColorTextByTheme("(current)")
                end
                local header = GUIFrame:CreateRow(card.content, 26)
                header:AddWidget(SpecHeader(header, specIcon, headerText), 1)
                card:AddRow(header, 26)

                local row = GUIFrame:CreateRow(card.content, 40)
                local check = GUIFrame:CreateCheckbox(row,
                    wantedName ~= "" and wantedName or specName, {
                        value = db[key .. "Enabled"] ~= false,
                        callback = function(checked) db[key .. "Enabled"] = checked; ApplySettings() end,
                    })
                row:AddWidget(check, 0.4)

                local combat = GUIFrame:CreateCheckbox(row, "Only In Combat", {
                    value = db[key .. "CombatOnly"] == true,
                    callback = function(checked) db[key .. "CombatOnly"] = checked; ApplySettings() end,
                })
                row:AddWidget(combat, 0.3)

                local reverse = GUIFrame:CreateCheckbox(row, "Reverse Icon", {
                    value = db[key .. "ReverseIcon"] == true,
                    tooltip = "Show the form you are currently in instead of the one you are missing.",
                    callback = function(checked) db[key .. "ReverseIcon"] = checked; ApplySettings() end,
                })
                row:AddWidget(reverse, 0.3)

                table_insert(allWidgets, check)
                table_insert(allWidgets, combat)
                table_insert(allWidgets, reverse)
                card:AddRow(row, 40)

                -- Only classes with more than one valid answer get a choice.
                if entry.options then
                    local list = {}
                    for _, spellID in ipairs(entry.options) do
                        list[#list + 1] = {
                            key = tostring(spellID),
                            text = mod.SPELL_NAMES[spellID] or tostring(spellID),
                        }
                    end
                    local dropRow = GUIFrame:CreateRow(card.content, 34)
                    local drop = GUIFrame:CreateDropdown(dropRow, "Required", {
                        options = list,
                        value = tostring(db[key .. "Spell"] or entry.spellID),
                        callback = function(value) db[key .. "Spell"] = value; ApplySettings() end,
                    })
                    dropRow:AddWidget(drop, 1)
                    table_insert(allWidgets, drop)
                    card:AddRow(dropRow, 34)
                end
            end

            yOffset = yOffset + card:GetContentHeight() + Theme.paddingSmall
        end
    end

    ------------------------------------------------------------------
    -- Position
    ------------------------------------------------------------------
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
    return yOffset
end)
