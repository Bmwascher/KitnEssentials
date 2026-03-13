-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM

local table_insert = table.insert
local table_sort = table.sort
local wipe = wipe
local CreateFrame = CreateFrame
local ipairs, pairs = ipairs, pairs
local type = type
local math = math
local C_Timer = C_Timer
local C_Spell = C_Spell

-- Store current sub-tab
local currentSubTab = "raidBuffs"

-- Cached references
local cachedTabBar = nil
local cachedTabButtons = nil
local cachedPanel = nil

local allWidgets = {}

-- Sub-tab definitions
local SUB_TABS = {
    { id = "raidBuffs",   text = "Raid & General Buffs" },
    { id = "stances",     text = "Stance & Spec Buffs" },
    { id = "stanceTexts", text = "Stance Texts" },
}

local TAB_BAR_HEIGHT = 28

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("MissingBuffs", true)
    end
    return nil
end

local function GetMissingBuffsDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.MissingBuffs
end

local function ApplySettings()
    local mod = GetModule()
    if mod and mod.ApplySettings then mod:ApplySettings() end
end

local function Refresh()
    local mod = GetModule()
    if mod and mod.Refresh then mod:Refresh() end
end

local function UpdateAllWidgetStates()
    local db = GetMissingBuffsDB()
    if not db then return end
    local mainEnabled = db.Enabled ~= false
    for _, widget in ipairs(allWidgets) do
        if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
    end
end

local function ApplyMissingBuffsState(enabled)
    local MB = GetModule()
    if not MB then return end
    MB.db.Enabled = enabled
    if enabled then KitnEssentials:EnableModule("MissingBuffs")
    else KitnEssentials:DisableModule("MissingBuffs") end
end

-- Register cleanup
if not GUIFrame._missingBuffsCleanupRegistered then
    GUIFrame._missingBuffsCleanupRegistered = true
    GUIFrame:RegisterOnCloseCallback("missingBuffs", function()
        Refresh()
    end)
    GUIFrame:RegisterContentCleanup("missingBuffs", function()
        cachedPanel = nil
        cachedTabBar = nil
        cachedTabButtons = nil
        wipe(allWidgets)
    end)
end

--------------------------------------------------------------------------------
-- Icon Widget (for category/class/spec icons in rows)
--------------------------------------------------------------------------------
local function CreateIconWidget(parent, iconData, size)
    size = size or 40
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(size + 8, size)
    container.fixedWidth = size + 8

    local iconFrame = CreateFrame("Frame", nil, container)
    iconFrame:SetSize(size, size)
    iconFrame:SetPoint("LEFT", container, "LEFT", 4, 0)

    iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.texture:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    iconFrame.texture:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)

    local function ApplyZoom(tex, zoom)
        local texMin = 0.25 * zoom
        local texMax = 1 - 0.25 * zoom
        tex:SetTexCoord(texMin, texMax, texMin, texMax)
    end

    if type(iconData) == "table" then
        if iconData.atlas then
            iconFrame.texture:SetAtlas(iconData.atlas)
        elseif iconData.textureId then
            ApplyZoom(iconFrame.texture, 0.3)
            iconFrame.texture:SetTexture(iconData.textureId)
        elseif iconData.spellId then
            ApplyZoom(iconFrame.texture, 0.3)
            local texture = C_Spell.GetSpellTexture(iconData.spellId)
            iconFrame.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
    elseif type(iconData) == "number" then
        ApplyZoom(iconFrame.texture, 0.3)
        local texture = C_Spell.GetSpellTexture(iconData)
        iconFrame.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    else
        iconFrame.texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Borders (pixel-perfect)
    local borderTop = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderTop:SetHeight(1)
    borderTop:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", 0, 0)
    borderTop:SetColorTexture(0, 0, 0, 1)
    borderTop:SetTexelSnappingBias(0)
    borderTop:SetSnapToPixelGrid(false)

    local borderBottom = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderBottom:SetHeight(1)
    borderBottom:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetColorTexture(0, 0, 0, 1)
    borderBottom:SetTexelSnappingBias(0)
    borderBottom:SetSnapToPixelGrid(false)

    local borderLeft = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderLeft:SetWidth(1)
    borderLeft:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", 0, 0)
    borderLeft:SetColorTexture(0, 0, 0, 1)
    borderLeft:SetTexelSnappingBias(0)
    borderLeft:SetSnapToPixelGrid(false)

    local borderRight = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderRight:SetWidth(1)
    borderRight:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)
    borderRight:SetColorTexture(0, 0, 0, 1)
    borderRight:SetTexelSnappingBias(0)
    borderRight:SetSnapToPixelGrid(false)

    return container
end

--------------------------------------------------------------------------------
-- Category Icons
--------------------------------------------------------------------------------
local CATEGORY_ICONS = {
    Flask = 1235110,
    Food = 104280,
    MHEnchant = 180608,
    OHEnchant = 180608,
    Rune = 1264426,
    RaidBuffs = 1126,
    Poisons = 2823,
}

local CLASS_ICONS = {
    WARRIOR = { atlas = "classicon-warrior" },
    PALADIN = { atlas = "classicon-paladin" },
    DRUID   = { atlas = "classicon-druid" },
    PRIEST  = { atlas = "classicon-priest" },
    EVOKER  = { atlas = "classicon-evoker" },
}

local SPEC_ICONS = {
    WARRIOR = {
        Arms = { textureId = 132355 },
        Fury = { textureId = 132347 },
        Protection = { textureId = 132341 },
    },
    PALADIN = {
        Holy = { textureId = 135920 },
        Protection = { textureId = 236264 },
        Retribution = { textureId = 535595 },
    },
    DRUID = {
        Balance = { textureId = 136096 },
        Feral = { textureId = 132115 },
        Guardian = { textureId = 132276 },
    },
    PRIEST = {
        Shadow = { textureId = 136207 },
    },
    EVOKER = {
        Augmentation = { textureId = 5198700 },
    },
}

local LOAD_CONDITIONS = {
    { key = "ALWAYS",   text = "Always" },
    { key = "ANYGROUP", text = "Any Group" },
    { key = "PARTY",    text = "In Party" },
    { key = "RAID",     text = "In Raid" },
    { key = "NOGROUP",  text = "No Group" },
}

local STANCE_OPTIONS = {
    WARRIOR = {
        Arms = {
            { key = "386164", text = "Battle Stance" },
            { key = "386196", text = "Berserker Stance" },
            { key = "386208", text = "Defensive Stance" },
        },
        Fury = {
            { key = "386164", text = "Battle Stance" },
            { key = "386196", text = "Berserker Stance" },
            { key = "386208", text = "Defensive Stance" },
        },
        Protection = {
            { key = "386164", text = "Battle Stance" },
            { key = "386196", text = "Berserker Stance" },
            { key = "386208", text = "Defensive Stance" },
        },
    },
    PALADIN = {
        Holy = {
            { key = "465",    text = "Devotion Aura" },
            { key = "317920", text = "Concentration Aura" },
            { key = "32223",  text = "Crusader Aura" },
        },
        Protection = {
            { key = "465",    text = "Devotion Aura" },
            { key = "317920", text = "Concentration Aura" },
            { key = "32223",  text = "Crusader Aura" },
        },
        Retribution = {
            { key = "465",    text = "Devotion Aura" },
            { key = "317920", text = "Concentration Aura" },
            { key = "32223",  text = "Crusader Aura" },
        },
    },
    DRUID = {
        Balance = {
            { key = "24858", text = "Moonkin Form" },
            { key = "768",   text = "Cat Form" },
            { key = "5487",  text = "Bear Form" },
        },
        Feral = {
            { key = "768",   text = "Cat Form" },
            { key = "24858", text = "Moonkin Form" },
            { key = "5487",  text = "Bear Form" },
        },
        Guardian = {
            { key = "5487",  text = "Bear Form" },
            { key = "768",   text = "Cat Form" },
            { key = "24858", text = "Moonkin Form" },
        },
    },
    EVOKER = {
        Augmentation = {
            { key = "403264", text = "Black Attunement" },
            { key = "403265", text = "Bronze Attunement" },
        },
    },
}

local STANCE_TEXT_DATA = {
    WARRIOR = {
        { key = "386164", text = "Battle Stance",    textureId = 132349 },
        { key = "386196", text = "Berserker Stance", textureId = 132275 },
        { key = "386208", text = "Defensive Stance", textureId = 132341 },
    },
    PALADIN = {
        { key = "465",    text = "Devotion Aura",      textureId = 135893 },
        { key = "317920", text = "Concentration Aura", textureId = 135933 },
        { key = "32223",  text = "Crusader Aura",      textureId = 135890 },
    },
}

--------------------------------------------------------------------------------
-- Helper: Category row (icon + checkbox + load dropdown)
--------------------------------------------------------------------------------
local function CreateCategoryRow(card, categoryKey, label, iconSpellId, db, isFirst)
    if not isFirst then
        local sepRow = GUIFrame:CreateRow(card.content, 8)
        local sep = GUIFrame:CreateSeparator(sepRow)
        sepRow:AddWidget(sep, 1)
        table_insert(allWidgets, sep)
        card:AddRow(sepRow, 8)
    end

    local row = GUIFrame:CreateRow(card.content, 40)

    local iconWidget = CreateIconWidget(row, iconSpellId, 40)
    row:AddWidget(iconWidget, 0.1)

    local enableCheck = GUIFrame:CreateCheckbox(row, label,
        db[categoryKey] and db[categoryKey].Enabled ~= false,
        function(checked)
            db[categoryKey] = db[categoryKey] or {}
            db[categoryKey].Enabled = checked
            Refresh()
        end)
    row:AddWidget(enableCheck, 0.5)
    table_insert(allWidgets, enableCheck)

    local loadDropdown = GUIFrame:CreateDropdown(row, "Load", LOAD_CONDITIONS,
        (db[categoryKey] and db[categoryKey].LoadCondition) or "ALWAYS", 60,
        function(key)
            db[categoryKey] = db[categoryKey] or {}
            db[categoryKey].LoadCondition = key
            Refresh()
        end)
    row:AddWidget(loadDropdown, 0.4)
    table_insert(allWidgets, loadDropdown)

    card:AddRow(row, 40)
end

--------------------------------------------------------------------------------
-- Helper: Class stance card with per-spec toggles + dropdowns
--------------------------------------------------------------------------------
local function CreateClassStanceCard(scrollChild, yOffset, classKey, title, iconData, db, activeCards)
    db[classKey] = db[classKey] or {}

    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)
    table_insert(activeCards, card)
    table_insert(allWidgets, card)

    local specWidgets = {}

    local function UpdateSpecWidgetStates()
        for specName, widgets in pairs(specWidgets) do
            local specEnabled = db[classKey][specName .. "Enabled"] == true
            if widgets.dropdown and widgets.dropdown.SetEnabled then
                widgets.dropdown:SetEnabled(specEnabled)
            end
            if widgets.reverseIcon and widgets.reverseIcon.SetEnabled then
                widgets.reverseIcon:SetEnabled(specEnabled)
            end
        end
    end

    local specOptions = STANCE_OPTIONS[classKey]
    local specIcons = SPEC_ICONS[classKey]

    if specOptions then
        local isFirst = true
        for specName, options in pairs(specOptions) do
            if not isFirst then
                local sepRow = GUIFrame:CreateRow(card.content, 8)
                local sep = GUIFrame:CreateSeparator(sepRow)
                sepRow:AddWidget(sep, 1)
                table_insert(allWidgets, sep)
                card:AddRow(sepRow, 8)
            end
            isFirst = false

            local specRow = GUIFrame:CreateRow(card.content, 40)

            local specIconId = specIcons and specIcons[specName]
            local specIconWidget = CreateIconWidget(specRow, specIconId or 134400, 32)
            specRow:AddWidget(specIconWidget, 0.1)

            local specEnabledKey = specName .. "Enabled"
            local specToggle = GUIFrame:CreateCheckbox(specRow, specName,
                db[classKey][specEnabledKey] == true,
                function(checked)
                    db[classKey][specEnabledKey] = checked
                    UpdateSpecWidgetStates()
                    Refresh()
                end)
            specRow:AddWidget(specToggle, 0.35)
            table_insert(allWidgets, specToggle)

            local reverseIconKey = specName .. "ReverseIcon"
            local reverseToggle = GUIFrame:CreateCheckbox(specRow, "Reverse Icon",
                db[classKey][reverseIconKey] == true,
                function(checked)
                    db[classKey][reverseIconKey] = checked
                    Refresh()
                end)
            specRow:AddWidget(reverseToggle, 0.25)
            table_insert(allWidgets, reverseToggle)

            local specDropdown = GUIFrame:CreateDropdown(specRow, "Required", options,
                db[classKey][specName] or options[1].key, 80,
                function(key)
                    db[classKey][specName] = key
                    Refresh()
                end)
            specRow:AddWidget(specDropdown, 0.3)
            table_insert(allWidgets, specDropdown)

            specWidgets[specName] = { toggle = specToggle, dropdown = specDropdown, reverseIcon = reverseToggle }

            card:AddRow(specRow, 40)
        end

        C_Timer.After(0, UpdateSpecWidgetStates)
    end

    return yOffset + card:GetContentHeight() + Theme.paddingSmall
end

--------------------------------------------------------------------------------
-- Helper: Stance text card with per-stance settings
--------------------------------------------------------------------------------
local function CreateStanceTextCard(scrollChild, yOffset, classKey, title, iconData, db, activeCards)
    db[classKey] = db[classKey] or {}

    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)
    table_insert(activeCards, card)
    table_insert(allWidgets, card)

    local stances = STANCE_TEXT_DATA[classKey]
    if not stances then
        return yOffset + card:GetContentHeight() + Theme.paddingSmall
    end

    local isFirst = true
    for _, stance in ipairs(stances) do
        if not isFirst then
            local sepRow = GUIFrame:CreateRow(card.content, 8)
            local sep = GUIFrame:CreateSeparator(sepRow)
            sepRow:AddWidget(sep, 1)
            table_insert(allWidgets, sep)
            card:AddRow(sepRow, 8)
        end
        isFirst = false

        db[classKey][stance.key] = db[classKey][stance.key] or {}
        if not db[classKey][stance.key].Text then
            db[classKey][stance.key].Text = stance.text
        end

        local row = GUIFrame:CreateRow(card.content, 40)

        local iconWidget = CreateIconWidget(row, { textureId = stance.textureId }, 36)
        row:AddWidget(iconWidget, 0.1)

        local enableToggle = GUIFrame:CreateCheckbox(row, "Show",
            db[classKey][stance.key].Enabled == true,
            function(checked)
                db[classKey][stance.key].Enabled = checked
                Refresh()
            end)
        row:AddWidget(enableToggle, 0.15)
        table_insert(allWidgets, enableToggle)

        local colorPicker = GUIFrame:CreateColorPicker(row, "Color",
            db[classKey][stance.key].Color or { 1, 1, 1, 1 },
            function(r, g, b, a)
                db[classKey][stance.key].Color = { r, g, b, a }
                ApplySettings()
            end)
        row:AddWidget(colorPicker, 0.25)
        table_insert(allWidgets, colorPicker)

        local textInput = GUIFrame:CreateEditBox(row, "Text",
            db[classKey][stance.key].Text or stance.text,
            function(text)
                db[classKey][stance.key].Text = text
                ApplySettings()
            end)
        row:AddWidget(textInput, 0.5)
        table_insert(allWidgets, textInput)

        card:AddRow(row, 40)
    end

    return yOffset + card:GetContentHeight() + Theme.paddingSmall
end

--------------------------------------------------------------------------------
-- Shared font/outline helpers
--------------------------------------------------------------------------------
local function BuildFontList()
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            table_insert(fontList, { key = name, text = name })
        end
        table_sort(fontList, function(a, b) return a.text < b.text end)
    else
        table_insert(fontList, { key = "Friz Quadrata TT", text = "Friz Quadrata TT" })
    end
    return fontList
end

local OUTLINE_LIST = {
    { key = "NONE",         text = "None" },
    { key = "OUTLINE",      text = "Outline" },
    { key = "THICKOUTLINE", text = "Thick" },
    { key = "SOFTOUTLINE",  text = "Soft" },
}

----------------------------------------------------------------
-- Sub-Tab 1: Raid & General Buffs
----------------------------------------------------------------
local function RenderRaidBuffsTab(scrollChild, yOffset, activeCards)
    local db = GetMissingBuffsDB()
    if not db then return yOffset end

    -- Card 1: Enable
    local card1 = GUIFrame:CreateCard(scrollChild, "Missing Buffs", yOffset)
    table_insert(activeCards, card1)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Missing Buffs", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyMissingBuffsState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Missing Buffs", "On", "Off")
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    -- Card 2: Consumable & Buff Tracking
    local card2 = GUIFrame:CreateCard(scrollChild, "Consumable & Buff Tracking", yOffset)
    table_insert(activeCards, card2)
    table_insert(allWidgets, card2)
    db.Consumables = db.Consumables or {}

    CreateCategoryRow(card2, "Flask", "Flask", CATEGORY_ICONS.Flask, db.Consumables, true)
    CreateCategoryRow(card2, "Food", "Food Buff", CATEGORY_ICONS.Food, db.Consumables, false)
    CreateCategoryRow(card2, "MHEnchant", "Main Hand Enchant", CATEGORY_ICONS.MHEnchant, db.Consumables, false)
    CreateCategoryRow(card2, "OHEnchant", "Off Hand Enchant", CATEGORY_ICONS.OHEnchant, db.Consumables, false)
    CreateCategoryRow(card2, "Rune", "Augment Rune", CATEGORY_ICONS.Rune, db.Consumables, false)
    CreateCategoryRow(card2, "RaidBuffs", "Raid Buffs", CATEGORY_ICONS.RaidBuffs, db.Consumables, false)
    CreateCategoryRow(card2, "Poisons", "Rogue Poisons", CATEGORY_ICONS.Poisons, db.Consumables, false)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    -- Card 3: Display Settings
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    table_insert(activeCards, card3)
    table_insert(allWidgets, card3)
    db.RaidBuffDisplay = db.RaidBuffDisplay or {}

    local row3a = GUIFrame:CreateRow(card3.content, 36)
    local iconSizeSlider = GUIFrame:CreateSlider(row3a, "Icon Size", 24, 96, 1,
        db.RaidBuffDisplay.IconSize or 48, 60,
        function(val) db.RaidBuffDisplay.IconSize = val; ApplySettings() end)
    row3a:AddWidget(iconSizeSlider, 0.5)
    table_insert(allWidgets, iconSizeSlider)

    local iconSpacingSlider = GUIFrame:CreateSlider(row3a, "Icon Spacing", 0, 32, 1,
        db.RaidBuffDisplay.IconSpacing or 8, 60,
        function(val) db.RaidBuffDisplay.IconSpacing = val; ApplySettings() end)
    row3a:AddWidget(iconSpacingSlider, 0.5)
    table_insert(allWidgets, iconSpacingSlider)
    card3:AddRow(row3a, 36)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    -- Card 4: Font Settings
    local card4 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(activeCards, card4)
    table_insert(allWidgets, card4)

    local fontList = BuildFontList()

    local row4a = GUIFrame:CreateRow(card4.content, 36)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList,
        db.RaidBuffDisplay.FontFace or "Expressway", 120,
        function(key) db.RaidBuffDisplay.FontFace = key; ApplySettings() end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineDropdown = GUIFrame:CreateDropdown(row4a, "Outline", OUTLINE_LIST,
        db.RaidBuffDisplay.FontOutline or "SOFTOUTLINE", 80,
        function(key) db.RaidBuffDisplay.FontOutline = key; ApplySettings() end)
    row4a:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    card4:AddRow(row4a, 36)

    local row4b = GUIFrame:CreateRow(card4.content, 36)
    local fontSizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", 8, 32, 1,
        db.RaidBuffDisplay.FontSize or 20, 60,
        function(val) db.RaidBuffDisplay.FontSize = val; ApplySettings() end)
    row4b:AddWidget(fontSizeSlider, 1)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4b, 36)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    -- Card 5: Position Settings
    db.RaidBuffDisplay.Position = db.RaidBuffDisplay.Position or {}
    local positionCard
    positionCard, yOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db.RaidBuffDisplay,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        defaults = {
            selfPoint = "CENTER",
            anchorPoint = "CENTER",
            xOffset = 0,
            yOffset = 200,
        },
        showAnchorFrameType = false,
        showStrata = false,
        onChangeCallback = ApplySettings,
    })
    table_insert(activeCards, positionCard)

    if positionCard.positionWidgets then
        for _, widget in ipairs(positionCard.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, positionCard)

    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 4)
    return yOffset
end

----------------------------------------------------------------
-- Sub-Tab 2: Stance & Spec Buffs
----------------------------------------------------------------
local function RenderStancesTab(scrollChild, yOffset, activeCards)
    local db = GetMissingBuffsDB()
    if not db then return yOffset end
    db.Stances = db.Stances or {}

    -- Info Card
    local infoCard = GUIFrame:CreateCard(scrollChild, "Stance & Form Tracking", yOffset)
    table_insert(activeCards, infoCard)
    table_insert(allWidgets, infoCard)

    local infoTextHeight = 90
    local infoRow = GUIFrame:CreateRow(infoCard.content, infoTextHeight)
    local infoText = GUIFrame:CreateText(infoRow,
        KE:ColorTextByTheme("How it works"),
        (KE:ColorTextByTheme("* ") .. "Spec toggles: Enable/disable stance tracking for each spec\n" ..
            KE:ColorTextByTheme("* ") .. "Required dropdown: Choose which stance is required for that spec\n" ..
            KE:ColorTextByTheme("* ") .. "Reverse Icon: Show current stance icon instead of required stance, hides missing text"),
        infoTextHeight, "hide")
    infoRow:AddWidget(infoText, 1)
    table_insert(allWidgets, infoText)
    infoCard:AddRow(infoRow, infoTextHeight)

    local restedRow = GUIFrame:CreateRow(infoCard.content, 36)
    local restedCheck = GUIFrame:CreateCheckbox(restedRow, "Hide in Rested Areas",
        db.Stances.HideInRestedArea == true,
        function(checked)
            db.Stances.HideInRestedArea = checked
            Refresh()
        end,
        true, "Rested Area", "On", "Off")
    restedRow:AddWidget(restedCheck, 1)
    table_insert(allWidgets, restedCheck)
    infoCard:AddRow(restedRow, 36)

    yOffset = yOffset + infoCard:GetContentHeight() + Theme.paddingSmall

    -- Warrior
    yOffset = CreateClassStanceCard(scrollChild, yOffset, "WARRIOR", "Warrior Stances",
        CLASS_ICONS.WARRIOR, db.Stances, activeCards)

    -- Paladin
    yOffset = CreateClassStanceCard(scrollChild, yOffset, "PALADIN", "Paladin Auras",
        CLASS_ICONS.PALADIN, db.Stances, activeCards)

    -- Druid Forms (simple toggles per spec)
    db.Stances.DRUID = db.Stances.DRUID or {}
    local druidCard = GUIFrame:CreateCard(scrollChild, "Druid Forms", yOffset)
    table_insert(activeCards, druidCard)
    table_insert(allWidgets, druidCard)

    local balanceRow = GUIFrame:CreateRow(druidCard.content, 40)
    local balanceIcon = CreateIconWidget(balanceRow, SPEC_ICONS.DRUID.Balance, 40)
    balanceRow:AddWidget(balanceIcon, 0.1)
    local balanceToggle = GUIFrame:CreateCheckbox(balanceRow, "Balance: Require Moonkin Form",
        db.Stances.DRUID.BalanceEnabled == true,
        function(checked) db.Stances.DRUID.BalanceEnabled = checked; Refresh() end)
    balanceRow:AddWidget(balanceToggle, 0.9)
    table_insert(allWidgets, balanceToggle)
    druidCard:AddRow(balanceRow, 40)

    local druidSep1 = GUIFrame:CreateRow(druidCard.content, 8)
    local druidSep1Widget = GUIFrame:CreateSeparator(druidSep1)
    druidSep1:AddWidget(druidSep1Widget, 1)
    table_insert(allWidgets, druidSep1Widget)
    druidCard:AddRow(druidSep1, 8)

    local feralRow = GUIFrame:CreateRow(druidCard.content, 40)
    local feralIcon = CreateIconWidget(feralRow, SPEC_ICONS.DRUID.Feral, 40)
    feralRow:AddWidget(feralIcon, 0.1)
    local feralToggle = GUIFrame:CreateCheckbox(feralRow, "Feral: Require Cat Form",
        db.Stances.DRUID.FeralEnabled == true,
        function(checked) db.Stances.DRUID.FeralEnabled = checked; Refresh() end)
    feralRow:AddWidget(feralToggle, 0.9)
    table_insert(allWidgets, feralToggle)
    druidCard:AddRow(feralRow, 40)

    local druidSep2 = GUIFrame:CreateRow(druidCard.content, 8)
    local druidSep2Widget = GUIFrame:CreateSeparator(druidSep2)
    druidSep2:AddWidget(druidSep2Widget, 1)
    table_insert(allWidgets, druidSep2Widget)
    druidCard:AddRow(druidSep2, 8)

    local guardianRow = GUIFrame:CreateRow(druidCard.content, 40)
    local guardianIcon = CreateIconWidget(guardianRow, SPEC_ICONS.DRUID.Guardian, 40)
    guardianRow:AddWidget(guardianIcon, 0.1)
    local guardianToggle = GUIFrame:CreateCheckbox(guardianRow, "Guardian: Require Bear Form",
        db.Stances.DRUID.GuardianEnabled == true,
        function(checked) db.Stances.DRUID.GuardianEnabled = checked; Refresh() end)
    guardianRow:AddWidget(guardianToggle, 0.9)
    table_insert(allWidgets, guardianToggle)
    druidCard:AddRow(guardianRow, 40)

    yOffset = yOffset + druidCard:GetContentHeight() + Theme.paddingSmall

    -- Evoker Attunement
    db.Stances.EVOKER = db.Stances.EVOKER or {}
    local evokerCard = GUIFrame:CreateCard(scrollChild, "Augmentation Evoker Attunement", yOffset)
    table_insert(activeCards, evokerCard)
    table_insert(allWidgets, evokerCard)

    local evokerRow = GUIFrame:CreateRow(evokerCard.content, 40)
    local evokerIcon = CreateIconWidget(evokerRow, SPEC_ICONS.EVOKER.Augmentation, 40)
    evokerRow:AddWidget(evokerIcon, 0.1)
    local evokerToggle = GUIFrame:CreateCheckbox(evokerRow, "Require Attunement",
        db.Stances.EVOKER.AugmentationEnabled == true,
        function(checked) db.Stances.EVOKER.AugmentationEnabled = checked; Refresh() end)
    evokerRow:AddWidget(evokerToggle, 0.5)
    table_insert(allWidgets, evokerToggle)

    local attunementOptions = {
        { key = "403264", text = "Black Attunement" },
        { key = "403265", text = "Bronze Attunement" },
    }
    local evokerDropdown = GUIFrame:CreateDropdown(evokerRow, "Required", attunementOptions,
        db.Stances.EVOKER.Augmentation or "403264", 100,
        function(key) db.Stances.EVOKER.Augmentation = key; Refresh() end)
    evokerRow:AddWidget(evokerDropdown, 0.4)
    table_insert(allWidgets, evokerDropdown)
    evokerCard:AddRow(evokerRow, 40)

    yOffset = yOffset + evokerCard:GetContentHeight() + Theme.paddingSmall

    -- Priest (Shadow only)
    db.Stances.PRIEST = db.Stances.PRIEST or {}
    local priestCard = GUIFrame:CreateCard(scrollChild, "Shadow Priest Shadowform", yOffset)
    table_insert(activeCards, priestCard)
    table_insert(allWidgets, priestCard)

    local priestRow = GUIFrame:CreateRow(priestCard.content, 40)
    local priestIcon = CreateIconWidget(priestRow, SPEC_ICONS.PRIEST.Shadow, 40)
    priestRow:AddWidget(priestIcon, 0.1)
    local priestToggle = GUIFrame:CreateCheckbox(priestRow, "Require Shadowform",
        db.Stances.PRIEST.ShadowEnabled == true,
        function(checked) db.Stances.PRIEST.ShadowEnabled = checked; Refresh() end)
    priestRow:AddWidget(priestToggle, 0.9)
    table_insert(allWidgets, priestToggle)
    priestCard:AddRow(priestRow, 40)

    yOffset = yOffset + priestCard:GetContentHeight() + Theme.paddingSmall

    -- Display Settings
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    table_insert(activeCards, card3)
    table_insert(allWidgets, card3)
    db.StanceDisplay = db.StanceDisplay or {}

    local row3a = GUIFrame:CreateRow(card3.content, 36)
    local iconSizeSlider = GUIFrame:CreateSlider(row3a, "Icon Size", 24, 96, 1,
        db.StanceDisplay.IconSize or 48, 60,
        function(val) db.StanceDisplay.IconSize = val; ApplySettings() end)
    row3a:AddWidget(iconSizeSlider, 1)
    table_insert(allWidgets, iconSizeSlider)
    card3:AddRow(row3a, 36)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    -- Font Settings
    local card4 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(activeCards, card4)
    table_insert(allWidgets, card4)

    local fontList = BuildFontList()

    local row4a = GUIFrame:CreateRow(card4.content, 36)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList,
        db.StanceDisplay.FontFace or "Expressway", 120,
        function(key) db.StanceDisplay.FontFace = key; ApplySettings() end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineDropdown = GUIFrame:CreateDropdown(row4a, "Outline", OUTLINE_LIST,
        db.StanceDisplay.FontOutline or "SOFTOUTLINE", 80,
        function(key) db.StanceDisplay.FontOutline = key; ApplySettings() end)
    row4a:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    card4:AddRow(row4a, 36)

    local row4b = GUIFrame:CreateRow(card4.content, 36)
    local fontSizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", 8, 32, 1,
        db.StanceDisplay.FontSize or 13, 60,
        function(val) db.StanceDisplay.FontSize = val; ApplySettings() end)
    row4b:AddWidget(fontSizeSlider, 1)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4b, 36)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    -- Position Settings
    db.StanceDisplay.Position = db.StanceDisplay.Position or {}
    local positionCard
    positionCard, yOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db.StanceDisplay,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        defaults = {
            selfPoint = "CENTER",
            anchorPoint = "CENTER",
            xOffset = 0,
            yOffset = 150,
        },
        showAnchorFrameType = false,
        showStrata = false,
        onChangeCallback = ApplySettings,
    })
    table_insert(activeCards, positionCard)

    if positionCard.positionWidgets then
        for _, widget in ipairs(positionCard.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, positionCard)

    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 4)
    return yOffset
end

----------------------------------------------------------------
-- Sub-Tab 3: Stance Texts
----------------------------------------------------------------
local function RenderStanceTextsTab(scrollChild, yOffset, activeCards)
    local db = GetMissingBuffsDB()
    if not db then return yOffset end
    db.StanceText = db.StanceText or {}

    -- Card 1: Enable
    local card1 = GUIFrame:CreateCard(scrollChild, "Stance Text Display", yOffset)
    table_insert(activeCards, card1)
    table_insert(allWidgets, card1)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Stance Text", db.StanceText.Enabled == true,
        function(checked)
            db.StanceText.Enabled = checked
            Refresh()
            UpdateAllWidgetStates()
        end)
    row1:AddWidget(enableCheck, 1)
    table_insert(allWidgets, enableCheck)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    -- Warrior Stance Texts
    yOffset = CreateStanceTextCard(scrollChild, yOffset, "WARRIOR", "Warrior Stance Texts",
        CLASS_ICONS.WARRIOR, db.StanceText, activeCards)

    -- Paladin Aura Texts
    yOffset = CreateStanceTextCard(scrollChild, yOffset, "PALADIN", "Paladin Aura Texts",
        CLASS_ICONS.PALADIN, db.StanceText, activeCards)

    -- Font Settings
    local fontList = BuildFontList()

    local card4 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(activeCards, card4)
    table_insert(allWidgets, card4)

    local row4a = GUIFrame:CreateRow(card4.content, 36)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList,
        db.StanceText.FontFace or "Expressway", 120,
        function(key) db.StanceText.FontFace = key; ApplySettings() end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineDropdown = GUIFrame:CreateDropdown(row4a, "Outline", OUTLINE_LIST,
        db.StanceText.FontOutline or "SOFTOUTLINE", 80,
        function(key) db.StanceText.FontOutline = key; ApplySettings() end)
    row4a:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    card4:AddRow(row4a, 36)

    local row4b = GUIFrame:CreateRow(card4.content, 36)
    local fontSizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", 8, 32, 1,
        db.StanceText.FontSize or 14, 60,
        function(val) db.StanceText.FontSize = val; ApplySettings() end)
    row4b:AddWidget(fontSizeSlider, 1)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4b, 36)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    -- Position Settings
    db.StanceText.Position = db.StanceText.Position or {}
    local positionCard
    positionCard, yOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db.StanceText,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        defaults = {
            anchorFrameType = "UIPARENT",
            selfPoint = "CENTER",
            anchorPoint = "CENTER",
            xOffset = 0,
            yOffset = 100,
            strata = "HIGH",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    table_insert(activeCards, positionCard)

    if positionCard.positionWidgets then
        for _, widget in ipairs(positionCard.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, positionCard)

    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 4)
    return yOffset
end

----------------------------------------------------------------
-- Create Missing Buffs Panel (sub-tab system)
----------------------------------------------------------------
local function CreateMissingBuffsPanel(container)
    local panel = CreateFrame("Frame", nil, container)
    panel:SetAllPoints()

    -- Tab bar at top
    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetHeight(TAB_BAR_HEIGHT)
    tabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)

    local tabBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBarBg:SetAllPoints()
    tabBarBg:SetColorTexture(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)

    local tabBarBorder = tabBar:CreateTexture(nil, "ARTWORK")
    tabBarBorder:SetHeight(1)
    tabBarBorder:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    tabBarBorder:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    tabBarBorder:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    cachedTabBar = tabBar

    -- Scroll frame below tab bar
    local scrollbarWidth = Theme.scrollbarWidth or 16
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -1)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    -- Style scrollbar
    if scrollFrame.ScrollBar then
        local sb = scrollFrame.ScrollBar
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -(TAB_BAR_HEIGHT + Theme.paddingSmall + 13))
        sb:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, Theme.paddingSmall + 13)
        sb:SetWidth(scrollbarWidth - 4)

        if sb.Background then sb.Background:Hide() end
        if sb.Top then sb.Top:Hide() end
        if sb.Middle then sb.Middle:Hide() end
        if sb.Bottom then sb.Bottom:Hide() end
        if sb.trackBG then sb.trackBG:Hide() end
        if sb.ScrollUpButton then sb.ScrollUpButton:Hide() end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:SetAlpha(0)
    end

    -- Scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Scrollbar visibility management
    local scrollbarVisible = false
    local baseWidth = Theme.contentWidth

    local function UpdateScrollChildWidth()
        if scrollbarVisible then
            scrollChild:SetWidth(baseWidth - scrollbarWidth)
        else
            scrollChild:SetWidth(baseWidth)
        end
    end

    local function UpdateScrollBarVisibility()
        if scrollFrame.ScrollBar then
            local contentHeight = scrollChild:GetHeight()
            local frameHeight = scrollFrame:GetHeight()
            local needsScrollbar = contentHeight > frameHeight
            scrollbarVisible = needsScrollbar
            scrollFrame.ScrollBar:SetAlpha(needsScrollbar and 1 or 0)
            UpdateScrollChildWidth()
        end
    end

    UpdateScrollChildWidth()

    scrollFrame:HookScript("OnScrollRangeChanged", UpdateScrollBarVisibility)
    scrollChild:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
    scrollFrame:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
    scrollFrame:HookScript("OnShow", function()
        C_Timer.After(0, UpdateScrollBarVisibility)
    end)

    -- Track active cards for width updates
    local activeCards = {}

    local function UpdateCardWidths()
        local newWidth = scrollChild:GetWidth()
        for _, card in ipairs(activeCards) do
            if card and card.SetWidth then card:SetWidth(newWidth) end
        end
    end

    scrollChild:HookScript("OnSizeChanged", function(_, width, height)
        UpdateCardWidths()
    end)

    -- Render content into scroll child
    local function RenderContentIntoScrollChild(tabId)
        wipe(allWidgets)
        wipe(activeCards)

        for _, child in ipairs({ scrollChild:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end
        for _, region in ipairs({ scrollChild:GetRegions() }) do
            if region:GetObjectType() == "FontString" or region:GetObjectType() == "Texture" then
                region:Hide()
            end
        end

        local yOffset = Theme.paddingMedium

        if tabId == "raidBuffs" then
            yOffset = RenderRaidBuffsTab(scrollChild, yOffset, activeCards)
        elseif tabId == "stances" then
            yOffset = RenderStancesTab(scrollChild, yOffset, activeCards)
        elseif tabId == "stanceTexts" then
            yOffset = RenderStanceTextsTab(scrollChild, yOffset, activeCards)
        end

        scrollChild:SetHeight(yOffset + Theme.paddingLarge)
    end

    -- Tab visual update
    local function UpdateTabVisuals(buttons, selectedId)
        for _, btn in ipairs(buttons) do
            if btn.tabId == selectedId then
                btn.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                btn.underline:Show()
                btn.selectedOverlay:Show()
            else
                btn.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
                btn.underline:Hide()
                btn.selectedOverlay:Hide()
            end
        end
    end

    -- Create tab buttons
    local tabButtons = {}
    local minPadding = Theme.paddingMedium * 2
    local totalTextWidth = 0

    for i, tabDef in ipairs(SUB_TABS) do
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetHeight(TAB_BAR_HEIGHT)
        btn.tabId = tabDef.id
        btn.tabIndex = i

        local hoverBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        hoverBg:SetAllPoints()
        hoverBg:SetColorTexture(1, 1, 1, 0.05)
        hoverBg:Hide()
        btn.hoverBg = hoverBg

        local selectedOverlay = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
        selectedOverlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        selectedOverlay:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        selectedOverlay:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.1)
        selectedOverlay:Hide()
        btn.selectedOverlay = selectedOverlay

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        KE:ApplyThemeFont(label, "small")
        label:SetText(tabDef.text)
        label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        btn.label = label

        local textWidth = label:GetStringWidth()
        btn.textWidth = textWidth
        totalTextWidth = totalTextWidth + textWidth

        local underline = btn:CreateTexture(nil, "OVERLAY")
        underline:SetHeight(2)
        underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        underline:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        underline:Hide()
        btn.underline = underline

        btn:SetScript("OnEnter", function(self)
            if currentSubTab ~= self.tabId then self.hoverBg:Show() end
        end)
        btn:SetScript("OnLeave", function(self)
            self.hoverBg:Hide()
        end)
        btn:SetScript("OnClick", function(self)
            if currentSubTab ~= self.tabId then
                currentSubTab = self.tabId
                UpdateTabVisuals(cachedTabButtons, currentSubTab)
                RenderContentIntoScrollChild(currentSubTab)
            end
        end)

        table_insert(tabButtons, btn)
    end

    cachedTabButtons = tabButtons

    -- Proportional tab layout
    local function LayoutTabs(barWidth)
        if barWidth <= 0 then return end
        local numTabs = #tabButtons
        local totalMinWidth = totalTextWidth + (minPadding * numTabs)
        local extraSpace = math.max(0, barWidth - totalMinWidth)
        local extraPerTab = extraSpace / numTabs

        local xOffset = 0
        for _, btn in ipairs(tabButtons) do
            local tabWidth = btn.textWidth + minPadding + extraPerTab
            btn:ClearAllPoints()
            btn:SetPoint("TOP", tabBar, "TOP", 0, 0)
            btn:SetPoint("BOTTOM", tabBar, "BOTTOM", 0, 0)
            btn:SetPoint("LEFT", tabBar, "LEFT", xOffset, 0)
            btn:SetWidth(tabWidth)
            xOffset = xOffset + tabWidth
        end
    end

    LayoutTabs(tabBar:GetWidth())

    tabBar:SetScript("OnSizeChanged", function(self, width)
        LayoutTabs(width)
    end)

    UpdateTabVisuals(tabButtons, currentSubTab)
    RenderContentIntoScrollChild(currentSubTab)
    UpdateAllWidgetStates()

    return panel
end

----------------------------------------------------------------
-- Register Content (takes over content area with panel)
----------------------------------------------------------------
GUIFrame:RegisterContent("MissingBuffs", function(scrollChild, yOffset)
    -- Hide the default scroll frame — we use our own panel with tab bar + scroll
    if GUIFrame.contentArea and GUIFrame.contentArea.scrollFrame then
        GUIFrame.contentArea.scrollFrame:Hide()
    end

    -- Create panel in the content area and track as _customPanel for cleanup
    cachedPanel = CreateMissingBuffsPanel(GUIFrame.contentArea)
    GUIFrame.contentArea._customPanel = cachedPanel

    -- Return a dummy yOffset so RefreshContent doesn't error
    return yOffset
end)
