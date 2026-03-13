-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

-- Localization Setup
local table_insert = table.insert
local ipairs = ipairs
local pairs = pairs

-- Helper to get Auras module
local function GetAurasModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinAuras", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinAuras", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Auras
    if not db then return yOffset end

    local AURAS = GetAurasModule()

    -- Track widgets for enable/disable logic
    local allWidgets = {}

    local function ApplySettings()
        if not AURAS or not AURAS:IsEnabled() then return end
        AURAS:Refresh()
    end

    local function ApplyAurasState(enabled)
        if not AURAS then return end
        AURAS.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinAuras")
        else
            KitnEssentials:DisableModule("SkinAuras")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Buffs, Debuffs & Externals", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Buffs, Debuffs & Externals Skinning", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyAurasState(checked)
            UpdateAllWidgetStates()
            if not checked then
                KE:CreateReloadPrompt("Enabling/Disabling this UI element requires a reload to take full effect.")
            end
        end,
        true,
        "Buffs, Debuffs & Externals Skinning",
        "On",
        "Off"
    )
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    card1:AddLabel("|cff888888" .. KE:ColorTextByTheme("Tip:") .. " Use Blizzard Edit Mode to adjust icon size and positioning.|r")

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: General Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)

    -- Disable flashing checkbox
    local row2 = GUIFrame:CreateRow(card2.content, 40)
    local disableFlashing = GUIFrame:CreateCheckbox(row2, "Disable flashing when low duration",
        db.disableFlashing ~= false,
        function(checked)
            db.disableFlashing = checked
            ApplySettings()
            if not checked then
                KE:CreateReloadPrompt("Disabling this UI element requires a reload to take full effect.")
            end
        end)
    row2:AddWidget(disableFlashing, 0.5)
    table_insert(allWidgets, disableFlashing)
    card2:AddRow(row2, 40)

    -- Separator
    local row2sep = GUIFrame:CreateRow(card2.content, 8)
    local sepWidget = GUIFrame:CreateSeparator(row2sep)
    row2sep:AddWidget(sepWidget, 1)
    table_insert(allWidgets, sepWidget)
    card2:AddRow(row2sep, 8)

    -- Font color
    local row2c = GUIFrame:CreateRow(card2.content, 40)
    local fontColor = GUIFrame:CreateColorPicker(row2c, "Font color", db.FontColor,
        function(r, g, b, a)
            db.FontColor = { r, g, b, a }
            ApplySettings()
        end)
    row2c:AddWidget(fontColor, 1)
    table_insert(allWidgets, fontColor)
    card2:AddRow(row2c, 40)

    -- Font face + outline dropdowns
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row2a, "Font", fontList, db.FontFace, 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row2a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row2a, "Outline", outlineList, db.FontOutline or "OUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row2a:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    card2:AddRow(row2a, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Buff Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Buff Settings", yOffset)

    local row3 = GUIFrame:CreateRow(card3.content, 39)
    local buffBorderColor = GUIFrame:CreateColorPicker(row3, "Buff border color", db.buffBorderColor,
        function(r, g, b, a)
            db.buffBorderColor = { r, g, b, a }
            ApplySettings()
        end)
    row3:AddWidget(buffBorderColor, 0.5)
    table_insert(allWidgets, buffBorderColor)
    card3:AddRow(row3, 36)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Debuff Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Debuff Settings", yOffset)

    local row4 = GUIFrame:CreateRow(card4.content, 39)
    local debuffBorderColor = GUIFrame:CreateColorPicker(row4, "Debuff border color", db.debuffBorderColor,
        function(r, g, b, a)
            db.debuffBorderColor = { r, g, b, a }
            ApplySettings()
        end)
    row4:AddWidget(debuffBorderColor, 0.5)
    table_insert(allWidgets, debuffBorderColor)
    card4:AddRow(row4, 36)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: External Defensive Settings
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "External Defensive Settings", yOffset)

    local row5 = GUIFrame:CreateRow(card5.content, 39)
    local defBorderColor = GUIFrame:CreateColorPicker(row5, "External Defensive border color", db.defBorderColor,
        function(r, g, b, a)
            db.defBorderColor = { r, g, b, a }
            ApplySettings()
        end)
    row5:AddWidget(defBorderColor, 0.5)
    table_insert(allWidgets, defBorderColor)
    card5:AddRow(row5, 36)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
