-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PIMacroBuilder.lua                                  ║
-- ║  GUI: PI Macro Builder                                   ║
-- ║  Purpose: Configuration panel for the PIMacroBuilder     ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs
local tostring = tostring
local tonumber = tonumber
local C_Spell = C_Spell
local C_Item = C_Item
local GetInventoryItemTexture = GetInventoryItemTexture

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PIMacroBuilder", true)
    end
    return nil
end

GUIFrame:RegisterContent("PIMacroBuilder", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PIMacroBuilder
    if not db then return yOffset end

    local PI = GetModule()
    local allWidgets = {}

    local function ApplySettings()
        if PI and PI.ApplySettings then PI:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not PI then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("PIMacroBuilder")
        else KitnEssentials:DisableModule("PIMacroBuilder") end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    -- Icon helpers
    local function SpellIcon(spellID, displayName)
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.iconID then
            return "|T" .. info.iconID .. ":18:18:0:0|t " .. displayName
        end
        return displayName
    end

    local function TrinketIcon(slot)
        local icon = GetInventoryItemTexture("player", slot)
        if icon then
            return "|T" .. icon .. ":18:18:0:0|t "
        end
        return ""
    end

    local function ItemIcon(itemID, displayName)
        local icon = C_Item.GetItemIconByID(itemID)
        if icon then
            return "|T" .. icon .. ":18:18:0:0|t " .. displayName
        end
        return displayName
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Power Infusion", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Power Infusion", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Power Infusion", "On", "Off")
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    local noteHeight = 50
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Auto-creates a macro for Power Infusion with optional extras.\n" ..
        KE:ColorTextByTheme("-") .. " Drag the macro from " .. KE:ColorTextByTheme("/macro") .. " to your action bar.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: How to Use
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "How to Use", yOffset)
    table_insert(allWidgets, card2)

    local usageHeight = 85
    local usageRow = GUIFrame:CreateRow(card2.content, usageHeight)
    local usageText = GUIFrame:CreateText(usageRow,
        "",
        KE:ColorTextByTheme("-") .. " Configure the macro options below to customize your PI macro.\n" ..
        KE:ColorTextByTheme("-") .. " Use " .. KE:ColorTextByTheme("/kitn pi") .. " while hovering or targeting a friendly player to update the macro target.\n" ..
        "   (out of combat only)\n" ..
        KE:ColorTextByTheme("-") .. " We recommend creating a helper macro containing " .. KE:ColorTextByTheme("/kitn pi") .. "\n" ..
        "   for easy instant target updating!",
        usageHeight, "hide")
    usageRow:AddWidget(usageText, 1)
    card2:AddRow(usageRow, usageHeight)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Core Abilities
    ---------------------------------------------------------------------------------
    local card3a = GUIFrame:CreateCard(scrollChild, "Core Abilities", yOffset)
    table_insert(allWidgets, card3a)

    local abilityDefs = {
        { key = "Trinket1", label = TrinketIcon(13) .. "Trinket 1  |cff888888- Add /use 13 to the macro.|r", default = true },
        { key = "Trinket2", label = TrinketIcon(14) .. "Trinket 2  |cff888888- Add /use 14 to the macro.|r", default = false },
        { key = "VampiricEmbrace", label = SpellIcon(15286, "Vampiric Embrace") .. "  |cff888888- Add Vampiric Embrace to the macro.|r", default = true },
    }

    for _, def in ipairs(abilityDefs) do
        local checked = db[def.key]
        if checked == nil then checked = def.default end
        local row = GUIFrame:CreateRow(card3a.content, 42)
        local checkbox = GUIFrame:CreateCheckbox(row, def.label, checked,
            function(val) db[def.key] = val; ApplySettings() end)
        row:AddWidget(checkbox, 1)
        table_insert(allWidgets, checkbox)
        card3a:AddRow(row, 42)
    end

    yOffset = yOffset + card3a:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Optional Extras
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Optional Extras", yOffset)
    table_insert(allWidgets, card3)

    -- Racial dropdown
    local racialOptions = {
        { value = "", text = "None" },
        { value = "Ancestral Call", text = SpellIcon(274738, "Ancestral Call") },
        { value = "Berserking", text = SpellIcon(26297, "Berserking") },
        { value = "Blood Fury", text = SpellIcon(20572, "Blood Fury") },
        { value = "Fireblood", text = SpellIcon(265221, "Fireblood") },
    }

    local racialDropdown = GUIFrame:CreateDropdown(card3.content, "Racial", racialOptions, db.Racial or "", 40, function(val)
        db.Racial = val; ApplySettings()
    end)
    table_insert(allWidgets, racialDropdown)
    card3:AddRow(racialDropdown, 40)

    -- Potion dropdown
    local potionOptions = {
        { value = "", text = "None" },
        { value = "item:241309", text = ItemIcon(241309, "Light's Potential (Silver)") },
        { value = "item:241308", text = ItemIcon(241308, "Light's Potential (Gold)") },
        { value = "item:241289", text = ItemIcon(241289, "Potion of Recklessness (Silver)") },
        { value = "item:241288", text = ItemIcon(241288, "Potion of Recklessness (Gold)") },
        { value = "item:241293", text = ItemIcon(241293, "Draught of Rampant Abandon (Silver)") },
        { value = "item:241292", text = ItemIcon(241292, "Draught of Rampant Abandon (Gold)") },
    }

    local potionDropdown = GUIFrame:CreateDropdown(card3.content, "Potion", potionOptions, db.Potion or "", 70, function(val)
        db.Potion = val; ApplySettings()
    end)
    table_insert(allWidgets, potionDropdown)
    card3:AddRow(potionDropdown, 40)

    -- Fleeting Potion dropdown
    local fleetingOptions = {
        { value = "", text = "None" },
        { value = "item:245897", text = ItemIcon(245897, "Fleeting Light's Potential (Silver)") },
        { value = "item:245898", text = ItemIcon(245898, "Fleeting Light's Potential (Gold)") },
        { value = "item:245903", text = ItemIcon(245903, "Fleeting Potion of Recklessness (Silver)") },
        { value = "item:245902", text = ItemIcon(245902, "Fleeting Potion of Recklessness (Gold)") },
        { value = "item:245911", text = ItemIcon(245911, "Fleeting Draught of Rampant Abandon (Silver)") },
        { value = "item:245910", text = ItemIcon(245910, "Fleeting Draught of Rampant Abandon (Gold)") },
    }

    local fleetingDropdown = GUIFrame:CreateDropdown(card3.content, "Fleeting Potion", fleetingOptions, db.FleetingPotion or "", 70, function(val)
        db.FleetingPotion = val; ApplySettings()
    end)
    table_insert(allWidgets, fleetingDropdown)
    card3:AddRow(fleetingDropdown, 40)

    card3:AddLabel("|cff888888Fleeting potions are placed first in the macro so they are used before regular potions when available.|r")

    -- Additional /use line
    local rowCustom = GUIFrame:CreateRow(card3.content, 30)
    local customInput = GUIFrame:CreateEditBox(rowCustom, "Additional /use Line", db.Custom or "", function(val)
        db.Custom = val; ApplySettings()
    end)
    rowCustom:AddWidget(customInput, 1)
    table_insert(allWidgets, customInput)
    card3:AddRow(rowCustom, 30)

    card3:AddSpacing(4)
    card3:AddLabel("|cff888888Add any spell or item to the macro. Example: " .. KE:ColorTextByTheme("Shadowfiend") .. " or " .. KE:ColorTextByTheme("item:12345") .. "|r")

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Advanced
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Advanced", yOffset)
    table_insert(allWidgets, card4)

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local nameEditBox = GUIFrame:CreateEditBox(row4a, "Macro Name", db.MacroName or "PI",
        function(val)
            if val and val ~= "" then
                db.MacroName = val
            else
                db.MacroName = "PI"
            end
            ApplySettings()
        end)
    row4a:AddWidget(nameEditBox, 0.5)
    table_insert(allWidgets, nameEditBox)

    local iconEditBox = GUIFrame:CreateEditBox(row4a, "Macro Icon ID", tostring(db.MacroIcon or 135939),
        function(val)
            local num = tonumber(val)
            if num then
                db.MacroIcon = num
                ApplySettings()
            end
        end)
    row4a:AddWidget(iconEditBox, 0.5)
    table_insert(allWidgets, iconEditBox)
    card4:AddRow(row4a, 40)

    local advNoteHeight = 55
    local advNoteRow = GUIFrame:CreateRow(card4.content, advNoteHeight)
    local advNoteText = GUIFrame:CreateText(advNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Macro icon accepts numeric icon IDs. Default is " .. KE:ColorTextByTheme("135939") .. " (Power Infusion).\n   " ..
        KE:ColorTextByTheme(">") .. " Find IDs by clicking any spell or item icon on Wowhead.",
        advNoteHeight, "hide")
    advNoteRow:AddWidget(advNoteText, 1)
    card4:AddRow(advNoteRow, advNoteHeight)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
