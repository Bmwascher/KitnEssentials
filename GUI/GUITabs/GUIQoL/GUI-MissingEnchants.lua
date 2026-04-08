-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-MissingEnchants.lua                                 ║
-- ║  GUI: Missing Enchants/Gems                              ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           MissingEnchants module.                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub and LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert
local pairs = pairs

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("MissingEnchants", true)
    end
    return nil
end

GUIFrame:RegisterContent("MissingEnchants", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.MissingEnchants
    if not db then return yOffset end

    local ME = GetModule()
    local allWidgets = {}

    local function ApplySettings()
        if ME then ME:Refresh() end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Enable Toggles
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Missing Enchants/Gems", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Show Missing Enchants",
        db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row1:AddWidget(enableCheck, 0.5)

    local gemCheck = GUIFrame:CreateCheckbox(row1, "Show Missing Gems",
        db.GemEnabled ~= false,
        function(checked)
            db.GemEnabled = checked
            ApplySettings()
        end)
    row1:AddWidget(gemCheck, 0.5)
    table_insert(allWidgets, gemCheck)
    card1:AddRow(row1, 36)

    local row1b = GUIFrame:CreateRow(card1.content, 36)
    local hideBGCheck = GUIFrame:CreateCheckbox(row1b, "Hide Character Panel Background",
        db.HideCharacterBackground == true,
        function(checked)
            db.HideCharacterBackground = checked
            ApplySettings()
        end)
    row1b:AddWidget(hideBGCheck, 1)
    table_insert(allWidgets, hideBGCheck)
    card1:AddRow(row1b, 36)

    local noteHeight = 50
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Displays red warnings for missing enchants and empty gem sockets.\n" ..
        KE:ColorTextByTheme("-") .. " Only shows at max level on the character panel.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Font Settings
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card2)

    -- Font face and size
    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local fontDropdown = GUIFrame:CreateDropdown(row2a, "Font", fontList,
        db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row2a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(card2.content, "Font Size", 8, 24, 1,
        db.FontSize or 13, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row2a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card2:AddRow(row2a, 40)

    -- Font outline
    local row2b = GUIFrame:CreateRow(card2.content, 37)
    local outlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row2b, "Outline", outlineList,
        db.FontOutline or "OUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row2b:AddWidget(outlineDropdown, 1)
    table_insert(allWidgets, outlineDropdown)
    card2:AddRow(row2b, 37)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)
