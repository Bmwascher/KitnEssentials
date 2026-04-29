-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-StanceText.lua                                      ║
-- ║  GUI: Stance Text                                        ║
-- ║  Purpose: Configuration panel for the StanceText module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local CreateFrame = CreateFrame

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

local function CreateIconWidget(parent, textureId, size)
    size = size or 36
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(size + 8, size)
    container.fixedWidth = size + 8

    local iconFrame = CreateFrame("Frame", nil, container)
    iconFrame:SetSize(size, size)
    iconFrame:SetPoint("LEFT", container, "LEFT", 4, 0)

    local tex = iconFrame:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    tex:SetTexture(textureId)
    KE:ApplyIconZoom(tex)
    KE:AddIconBorders(iconFrame)

    return container
end

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("StanceText", true)
    end
    return nil
end

local function CreateStanceCard(scrollChild, yOffset, classKey, title, db, manager)
    db[classKey] = db[classKey] or {}

    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)
    manager:Register(card, "all")

    local stances = STANCE_TEXT_DATA[classKey]
    if not stances then return card:GetNextOffset() end

    local function ApplySettings()
        local mod = GetModule()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function Refresh()
        local mod = GetModule()
        if mod and mod.Refresh then mod:Refresh() end
    end

    for i, stance in ipairs(stances) do
        local isLast = i == #stances

        if i > 1 then
            local sepRow = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
            local sep = GUIFrame:CreateSeparator(sepRow)
            sepRow:AddWidget(sep, 1)
            manager:Register(sep, "all")
            card:AddRow(sepRow, Theme.rowHeightSeparator)
        end

        db[classKey][stance.key] = db[classKey][stance.key] or {}
        if not db[classKey][stance.key].Text then
            db[classKey][stance.key].Text = stance.text
        end

        local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(card.content, rowHeight)

        local iconWidget = CreateIconWidget(row, stance.textureId, 36)
        row:AddWidget(iconWidget, 0.1)

        local enableToggle = GUIFrame:CreateCheckbox(row, "Show", {
            value = db[classKey][stance.key].Enabled == true,
            callback = function(checked)
                db[classKey][stance.key].Enabled = checked
                Refresh()
            end,
        })
        row:AddWidget(enableToggle, 0.15)
        manager:Register(enableToggle, "all")

        local colorPicker = GUIFrame:CreateColorPicker(row, "Color", {
            color = db[classKey][stance.key].Color or { 1, 1, 1, 1 },
            callback = function(r, g, b, a)
                db[classKey][stance.key].Color = { r, g, b, a }
                ApplySettings()
            end,
        })
        row:AddWidget(colorPicker, 0.25)
        manager:Register(colorPicker, "all")

        local textInput = GUIFrame:CreateEditBox(row, "Text", {
            value = db[classKey][stance.key].Text or stance.text,
            callback = function(text)
                db[classKey][stance.key].Text = text
                ApplySettings()
            end,
        })
        row:AddWidget(textInput, 0.5)
        manager:Register(textInput, "all")

        if isLast then
            card:AddRow(row, rowHeight, 0)
        else
            card:AddRow(row, rowHeight)
        end
    end

    return card:GetNextOffset()
end

GUIFrame:RegisterContent("StanceText", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.StanceText
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local mod = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("StanceText")
        else
            KitnEssentials:DisableModule("StanceText")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled == true)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Class Stance Texts", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Stance Text", {
        value = db.Enabled == true,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Stance Text",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
        showPixelSnap = true,
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 32 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Cards 4–6: Per-class stance text editors
    ----------------------------------------------------------------
    yOffset = CreateStanceCard(scrollChild, yOffset, "WARRIOR", "Warrior Stance Texts", db, manager)
    yOffset = CreateStanceCard(scrollChild, yOffset, "PALADIN", "Paladin Aura Texts", db, manager)
    yOffset = CreateStanceCard(scrollChild, yOffset, "EVOKER", "Evoker Attunement Texts", db, manager)

    RefreshStates()
    return yOffset
end)
