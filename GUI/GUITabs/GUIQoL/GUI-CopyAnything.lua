-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local table_insert = table.insert
local ipairs = ipairs

local function GetCopyAnythingModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("CopyAnything", true)
    end
    return nil
end

GUIFrame:RegisterContent("CopyAnything", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CopyAnything
    if not db then return yOffset end

    local CA = GetCopyAnythingModule()
    local allWidgets = {}

    local function ApplyState(enabled)
        if not CA then return end
        CA.db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("CopyAnything")
        else KitnEssentials:DisableModule("CopyAnything") end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable + Info
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Copy Anything", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 40)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Copy Anything", db.Enabled ~= false,
        function(checked) db.Enabled = checked; ApplyState(checked); UpdateAllWidgetStates() end,
        true, "Copy Anything", "On", "Off")
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 40)

    local row1sep = GUIFrame:CreateRow(card1.content, 8)
    local sep = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep, 1)
    table_insert(allWidgets, sep)
    card1:AddRow(row1sep, 8)

    local textRowSize = 50
    local row1b = GUIFrame:CreateRow(card1.content, textRowSize)
    local infoText = GUIFrame:CreateText(row1b,
        KE:ColorTextByTheme("Functionality Info"),
        (KE:ColorTextByTheme("• ") .. "Copies SpellID, ItemID, AuraID, MacroID and Unitnames on mouseover\n" ..
            KE:ColorTextByTheme("• ") .. "Limited functionality in certain environments because of secret values."),
        textRowSize, "hide")
    row1b:AddWidget(infoText, 1)
    table_insert(allWidgets, infoText)
    card1:AddRow(row1b, textRowSize)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Keybinding
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Keybinding", yOffset)
    table_insert(allWidgets, card2)

    local row2 = GUIFrame:CreateRow(card2.content, 38)
    local modList = {
        ["ctrl"] = "Ctrl",
        ["shift"] = "Shift",
        ["alt"] = "Alt",
        ["ctrl+shift"] = "Ctrl + Shift",
        ["ctrl+alt"] = "Ctrl + Alt",
        ["ctrl+shift+alt"] = "Ctrl + Shift + Alt",
    }
    local modDropdown = GUIFrame:CreateDropdown(row2, "Copy Modifier Key(s)", modList, db.mod, nil,
        function(key) db.mod = key end)
    row2:AddWidget(modDropdown, 0.5)
    table_insert(allWidgets, modDropdown)

    local keyBox = GUIFrame:CreateEditBox(row2, "Copy Keybind, Supports Single Letter Only", db.key, function(val)
        db.key = val
    end)
    row2:AddWidget(keyBox, 0.1)
    table_insert(allWidgets, keyBox)
    card2:AddRow(row2, 38)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
