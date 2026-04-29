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
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if PI and PI.ApplySettings then PI:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not PI then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("PIMacroBuilder")
        else KitnEssentials:DisableModule("PIMacroBuilder") end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

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

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Power Infusion", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Power Infusion", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Power Infusion",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Auto-creates a macro for Power Infusion with optional extras.\n" ..
        KE:ColorTextByTheme("-") .. " Drag the macro from " .. KE:ColorTextByTheme("/macro") .. " to your action bar.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: How to Use
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "How to Use", yOffset)
    manager:Register(card2, "all")

    local usageRow = GUIFrame:CreateRow(card2.content, 70)
    local usageText = GUIFrame:CreateText(usageRow,
        "",
        KE:ColorTextByTheme("-") .. " Configure the macro options below to customize your PI macro.\n" ..
        KE:ColorTextByTheme("-") .. " Use " .. KE:ColorTextByTheme("/kitn pi") .. " while hovering or targeting a friendly player to update the macro target.\n" ..
        "   (out of combat only)\n" ..
        KE:ColorTextByTheme("-") .. " We recommend creating a helper macro containing " .. KE:ColorTextByTheme("/kitn pi") .. " for easy instant target updating!",
        70, "hide")
    usageRow:AddWidget(usageText, 1)
    card2:AddRow(usageRow, 70, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Core Abilities
    ----------------------------------------------------------------
    local cardCore = GUIFrame:CreateCard(scrollChild, "Core Abilities", yOffset)
    manager:Register(cardCore, "all")

    local abilityDefs = {
        { key = "Trinket1", label = TrinketIcon(13) .. "Trinket 1  |cff888888- Add /use 13 to the macro.|r", default = true },
        { key = "Trinket2", label = TrinketIcon(14) .. "Trinket 2  |cff888888- Add /use 14 to the macro.|r", default = false },
        { key = "VampiricEmbrace", label = SpellIcon(15286, "Vampiric Embrace") .. "  |cff888888- Add Vampiric Embrace to the macro.|r", default = true },
    }

    for i, def in ipairs(abilityDefs) do
        local checked = db[def.key]
        if checked == nil then checked = def.default end
        local isLast = i == #abilityDefs
        local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(cardCore.content, rowHeight)
        local checkbox = GUIFrame:CreateCheckbox(row, def.label, {
            value = checked,
            callback = function(val) db[def.key] = val; ApplySettings() end,
        })
        row:AddWidget(checkbox, 1)
        manager:Register(checkbox, "all")
        if isLast then
            cardCore:AddRow(row, rowHeight, 0)
        else
            cardCore:AddRow(row, rowHeight)
        end
    end

    yOffset = cardCore:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Optional Extras
    ----------------------------------------------------------------
    local cardExtras = GUIFrame:CreateCard(scrollChild, "Optional Extras", yOffset)
    manager:Register(cardExtras, "all")

    local racialOptions = {
        { key = "", text = "None" },
        { key = "Ancestral Call", text = SpellIcon(274738, "Ancestral Call") },
        { key = "Berserking", text = SpellIcon(26297, "Berserking") },
        { key = "Blood Fury", text = SpellIcon(20572, "Blood Fury") },
        { key = "Fireblood", text = SpellIcon(265221, "Fireblood") },
    }
    local rowRacial = GUIFrame:CreateRow(cardExtras.content, Theme.rowHeight)
    local racialDropdown = GUIFrame:CreateDropdown(rowRacial, "Racial", {
        options = racialOptions,
        value = db.Racial or "",
        callback = function(val) db.Racial = val; ApplySettings() end,
    })
    rowRacial:AddWidget(racialDropdown, 1)
    manager:Register(racialDropdown, "all")
    cardExtras:AddRow(rowRacial, Theme.rowHeight)

    local potionOptions = {
        { key = "", text = "None" },
        { key = "item:241309", text = ItemIcon(241309, "Light's Potential (Silver)") },
        { key = "item:241308", text = ItemIcon(241308, "Light's Potential (Gold)") },
        { key = "item:241289", text = ItemIcon(241289, "Potion of Recklessness (Silver)") },
        { key = "item:241288", text = ItemIcon(241288, "Potion of Recklessness (Gold)") },
        { key = "item:241293", text = ItemIcon(241293, "Draught of Rampant Abandon (Silver)") },
        { key = "item:241292", text = ItemIcon(241292, "Draught of Rampant Abandon (Gold)") },
    }
    local rowPotion = GUIFrame:CreateRow(cardExtras.content, Theme.rowHeight)
    local potionDropdown = GUIFrame:CreateDropdown(rowPotion, "Potion", {
        options = potionOptions,
        value = db.Potion or "",
        callback = function(val) db.Potion = val; ApplySettings() end,
    })
    rowPotion:AddWidget(potionDropdown, 1)
    manager:Register(potionDropdown, "all")
    cardExtras:AddRow(rowPotion, Theme.rowHeight)

    local fleetingOptions = {
        { key = "", text = "None" },
        { key = "item:245897", text = ItemIcon(245897, "Fleeting Light's Potential (Silver)") },
        { key = "item:245898", text = ItemIcon(245898, "Fleeting Light's Potential (Gold)") },
        { key = "item:245903", text = ItemIcon(245903, "Fleeting Potion of Recklessness (Silver)") },
        { key = "item:245902", text = ItemIcon(245902, "Fleeting Potion of Recklessness (Gold)") },
        { key = "item:245911", text = ItemIcon(245911, "Fleeting Draught of Rampant Abandon (Silver)") },
        { key = "item:245910", text = ItemIcon(245910, "Fleeting Draught of Rampant Abandon (Gold)") },
    }
    local rowFleeting = GUIFrame:CreateRow(cardExtras.content, Theme.rowHeight)
    local fleetingDropdown = GUIFrame:CreateDropdown(rowFleeting, "Fleeting Potion", {
        options = fleetingOptions,
        value = db.FleetingPotion or "",
        callback = function(val) db.FleetingPotion = val; ApplySettings() end,
    })
    rowFleeting:AddWidget(fleetingDropdown, 1)
    manager:Register(fleetingDropdown, "all")
    cardExtras:AddRow(rowFleeting, Theme.rowHeight)

    local rowFleetNote = GUIFrame:CreateRow(cardExtras.content, Theme.rowHeight)
    local fleetNote = GUIFrame:CreateText(rowFleetNote,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Fleeting potions are placed first in the macro so they are used before regular potions when available.",
        Theme.rowHeight, "hide")
    rowFleetNote:AddWidget(fleetNote, 1)
    manager:Register(fleetNote, "all")
    cardExtras:AddRow(rowFleetNote, Theme.rowHeight)

    local rowCustom = GUIFrame:CreateRow(cardExtras.content, Theme.rowHeight)
    local customInput = GUIFrame:CreateEditBox(rowCustom, "Additional /use Line", {
        value = db.Custom or "",
        callback = function(val) db.Custom = val; ApplySettings() end,
    })
    rowCustom:AddWidget(customInput, 1)
    manager:Register(customInput, "all")
    cardExtras:AddRow(rowCustom, Theme.rowHeight)

    local rowCustomNote = GUIFrame:CreateRow(cardExtras.content, Theme.rowHeight)
    local customNote = GUIFrame:CreateText(rowCustomNote,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Add any spell or item to the macro. Example: " .. KE:ColorTextByTheme("Shadowfiend") .. " or " .. KE:ColorTextByTheme("item:12345"),
        Theme.rowHeight, "hide")
    rowCustomNote:AddWidget(customNote, 1)
    manager:Register(customNote, "all")
    cardExtras:AddRow(rowCustomNote, Theme.rowHeight, 0)

    yOffset = cardExtras:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Advanced
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Advanced", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local nameEditBox = GUIFrame:CreateEditBox(row5a, "Macro Name", {
        value = db.MacroName or "PI",
        callback = function(val)
            if val and val ~= "" then
                db.MacroName = val
            else
                db.MacroName = "PI"
            end
            ApplySettings()
        end,
    })
    row5a:AddWidget(nameEditBox, 0.5)
    manager:Register(nameEditBox, "all")

    local iconEditBox = GUIFrame:CreateEditBox(row5a, "Macro Icon ID", {
        value = tostring(db.MacroIcon or 135939),
        callback = function(val)
            local num = tonumber(val)
            if num then
                db.MacroIcon = num
                ApplySettings()
            end
        end,
    })
    row5a:AddWidget(iconEditBox, 0.5)
    manager:Register(iconEditBox, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local advNoteRow = GUIFrame:CreateRow(card5.content, 55)
    local advNoteText = GUIFrame:CreateText(advNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Macro icon accepts numeric icon IDs. Default is " .. KE:ColorTextByTheme("135939") .. " (Power Infusion).\n   " ..
        KE:ColorTextByTheme(">") .. " Find IDs by clicking any spell or item icon on Wowhead.",
        55, "hide")
    advNoteRow:AddWidget(advNoteText, 1)
    card5:AddRow(advNoteRow, 55, 0)

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
