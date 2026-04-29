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
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if ME then ME:Refresh() end
    end

    local function ApplyModuleState(enabled)
        if not ME then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("MissingEnchants")
        else
            KitnEssentials:DisableModule("MissingEnchants")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Missing Enchants/Gems", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Missing Enchants/Gems", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Missing Enchants/Gems",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Displays red warnings for missing enchants and empty gem sockets.\n" ..
        KE:ColorTextByTheme("-") .. " Only shows at max level on the character panel.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: General Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local enchantCheck = GUIFrame:CreateCheckbox(row2a, "Show Missing Enchants", {
        value = db.ShowEnchants ~= false,
        callback = function(checked) db.ShowEnchants = checked; ApplySettings() end,
    })
    row2a:AddWidget(enchantCheck, 0.5)
    manager:Register(enchantCheck, "all")

    local gemCheck = GUIFrame:CreateCheckbox(row2a, "Show Missing Gems", {
        value = db.GemEnabled ~= false,
        callback = function(checked) db.GemEnabled = checked; ApplySettings() end,
    })
    row2a:AddWidget(gemCheck, 0.5)
    manager:Register(gemCheck, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local hideBGCheck = GUIFrame:CreateCheckbox(row2b, "Hide Character Panel Background", {
        value = db.HideCharacterBackground == true,
        callback = function(checked) db.HideCharacterBackground = checked; ApplySettings() end,
    })
    row2b:AddWidget(hideBGCheck, 1)
    manager:Register(hideBGCheck, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 24 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    RefreshStates()
    return yOffset
end)
