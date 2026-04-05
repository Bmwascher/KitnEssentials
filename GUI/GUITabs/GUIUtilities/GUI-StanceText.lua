-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert
local table_sort = table.sort
local CreateFrame = CreateFrame
local C_Spell = C_Spell

--------------------------------------------------------------------------------
-- Stance text data (spell key → display label + icon)
--------------------------------------------------------------------------------
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
    EVOKER = {
        { key = "403264", text = "Black Attunement",  textureId = 5199619 },
        { key = "403265", text = "Bronze Attunement", textureId = 5199623 },
    },
}

--------------------------------------------------------------------------------
-- Icon widget helper
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
        end
    elseif type(iconData) == "number" then
        ApplyZoom(iconFrame.texture, 0.3)
        iconFrame.texture:SetTexture(iconData)
    end

    -- Borders
    local sides = {
        { "TOPLEFT", "TOPRIGHT", "SetHeight", 1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight", 1 },
    }
    for _, s in ipairs(sides) do
        local b = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        b[s[3]](b, s[4])
        b:SetPoint(s[1], iconFrame, s[1], 0, 0)
        b:SetPoint(s[2], iconFrame, s[2], 0, 0)
        b:SetColorTexture(0, 0, 0, 1)
        b:SetTexelSnappingBias(0)
        b:SetSnapToPixelGrid(false)
    end
    local verticals = {
        { "TOPLEFT", "BOTTOMLEFT" },
        { "TOPRIGHT", "BOTTOMRIGHT" },
    }
    for _, v in ipairs(verticals) do
        local b = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        b:SetWidth(1)
        b:SetPoint(v[1], iconFrame, v[1], 0, 0)
        b:SetPoint(v[2], iconFrame, v[2], 0, 0)
        b:SetColorTexture(0, 0, 0, 1)
        b:SetTexelSnappingBias(0)
        b:SetSnapToPixelGrid(false)
    end

    return container
end

--------------------------------------------------------------------------------
-- Font / Outline helpers
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

--------------------------------------------------------------------------------
-- Stance text card builder (per-class)
--------------------------------------------------------------------------------
local function CreateStanceTextCard(scrollChild, yOffset, classKey, title, db, allWidgets)
    db[classKey] = db[classKey] or {}

    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)
    table_insert(allWidgets, card)

    local stances = STANCE_TEXT_DATA[classKey]
    if not stances then
        return yOffset + card:GetContentHeight() + Theme.paddingSmall
    end

    local function ApplySettings()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("StanceText", true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
    end

    local function Refresh()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("StanceText", true)
            if mod and mod.Refresh then mod:Refresh() end
        end
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
-- Main content registration
--------------------------------------------------------------------------------
GUIFrame:RegisterContent("StanceText", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.StanceText
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}

    local function ApplySettings()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("StanceText", true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("StanceText", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("StanceText")
        else
            KitnEssentials:DisableModule("StanceText")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Class Stance Texts", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Stance Text", db.Enabled == true,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end)
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    db.Position = db.Position or {}
    local positionCard
    positionCard, yOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
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
        onChangeCallback = function() ApplySettings() end,
    })
    if positionCard.positionWidgets then
        for _, widget in ipairs(positionCard.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, positionCard)

    ----------------------------------------------------------------
    -- Card 3: Font Settings
    ----------------------------------------------------------------
    local fontList = BuildFontList()

    local card3 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card3)

    local row3a = GUIFrame:CreateRow(card3.content, 36)
    local fontDropdown = GUIFrame:CreateDropdown(row3a, "Font", fontList,
        db.FontFace or "Expressway", 120,
        function(key) db.FontFace = key; ApplySettings() end)
    row3a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineDropdown = GUIFrame:CreateDropdown(row3a, "Outline", OUTLINE_LIST,
        db.FontOutline or "SOFTOUTLINE", 80,
        function(key) db.FontOutline = key; ApplySettings() end)
    row3a:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    card3:AddRow(row3a, 36)

    local row3b = GUIFrame:CreateRow(card3.content, 36)
    local fontSizeSlider = GUIFrame:CreateSlider(row3b, "Font Size", 8, 32, 1,
        db.FontSize or 14, 60,
        function(val) db.FontSize = val; ApplySettings() end)
    row3b:AddWidget(fontSizeSlider, 1)
    table_insert(allWidgets, fontSizeSlider)
    card3:AddRow(row3b, 36)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Warrior Stance Texts
    ----------------------------------------------------------------
    yOffset = CreateStanceTextCard(scrollChild, yOffset, "WARRIOR", "Warrior Stance Texts", db, allWidgets)

    ----------------------------------------------------------------
    -- Card 5: Paladin Aura Texts
    ----------------------------------------------------------------
    yOffset = CreateStanceTextCard(scrollChild, yOffset, "PALADIN", "Paladin Aura Texts", db, allWidgets)

    ----------------------------------------------------------------
    -- Card 6: Evoker Attunement Texts
    ----------------------------------------------------------------
    yOffset = CreateStanceTextCard(scrollChild, yOffset, "EVOKER", "Evoker Attunement Texts", db, allWidgets)

    UpdateAllWidgetStates()
    return yOffset
end)
