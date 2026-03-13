-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("SlashCommands", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.SlashCommands
    if not db then return yOffset end

    ----------------------------------------------------------------
    -- Card 1: Cooldown Manager (/cd, /wa)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Cooldown Manager Slash Commands", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local cdmCheck = GUIFrame:CreateCheckbox(row1, "Enable /cd and /wa", db.CDMEnabled ~= false,
        function(checked)
            db.CDMEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "CDM Slash Commands", "On", "Off")
    row1:AddWidget(cdmCheck, 1)
    card1:AddRow(row1, 36)

    card1:AddLabel("|cff888888Registers " .. KE:ColorTextByTheme("/cd") .. " (and " .. KE:ColorTextByTheme("/wa") .. " if WeakAuras is not loaded) to toggle the Blizzard Cooldown Manager settings panel.|r")

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: SetPITarget
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "PI Macro Builder", yOffset)

    local row2 = GUIFrame:CreateRow(card2.content, 36)
    local piCheck = GUIFrame:CreateCheckbox(row2, "Enable SetPITarget()", db.SetPITargetEnabled ~= false,
        function(checked)
            db.SetPITargetEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "PI Macro Builder", "On", "Off")
    row2:AddWidget(piCheck, 1)
    card2:AddRow(row2, 36)

    card2:AddSpacing(4)

    card2:AddLabel("|cffFF4444>> Requires a macro named " .. KE:ColorTextByTheme("PI") .. "|cffFF4444. <<|r")
    card2:AddLabel("|cff888888Use " .. KE:ColorTextByTheme("/kitn pi") .. " while hovering or targeting a friendly player.|r")
    card2:AddLabel("|cff888888" .. KE:ColorTextByTheme("Tip:") .. " Create a helper macro containing " .. KE:ColorTextByTheme("/kitn pi") .. " for quick target updates.|r")

    -- Icon helpers
    local function SpellIcon(spellID, displayName)
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.iconID then
            return "|T" .. info.iconID .. ":18:18:0:0|t " .. displayName
        end
        return displayName
    end

    local function TrinketLabel(slot)
        local icon = GetInventoryItemTexture("player", slot)
        local label = "Trinket " .. (slot - 12) .. " (/use " .. slot .. ")"
        if icon then
            return "|T" .. icon .. ":18:18:0:0|t " .. label
        end
        return label
    end

    -- Trinket toggles
    local row2b = GUIFrame:CreateRow(card2.content, 36)
    local t1Check = GUIFrame:CreateCheckbox(row2b, TrinketLabel(13), db.PITrinket1 ~= false,
        function(checked) db.PITrinket1 = checked end)
    row2b:AddWidget(t1Check, 0.5)

    local t2Check = GUIFrame:CreateCheckbox(row2b, TrinketLabel(14), db.PITrinket2 == true,
        function(checked) db.PITrinket2 = checked end)
    row2b:AddWidget(t2Check, 0.5)
    card2:AddRow(row2b, 36)

    card2:AddSpacing(4)

    -- Vampiric Embrace toggle
    local row2c = GUIFrame:CreateRow(card2.content, 36)
    local veCheck = GUIFrame:CreateCheckbox(row2c, SpellIcon(15286, "Vampiric Embrace"), db.PIVampiricEmbrace ~= false,
        function(checked) db.PIVampiricEmbrace = checked end)
    row2c:AddWidget(veCheck, 1)
    card2:AddRow(row2c, 36)

    -- Helper: build icon text for an item ID
    local function ItemIcon(itemID, displayName)
        local icon = C_Item.GetItemIconByID(itemID)
        if icon then
            return "|T" .. icon .. ":18:18:0:0|t " .. displayName
        end
        return displayName
    end

    card2:AddLabel("|cff888888" .. KE:ColorTextByTheme("Optional Extras") .. ":|r")

    -- Racial dropdown
    local racialOptions = {
        { value = "", text = "None" },
        { value = "Ancestral Call", text = SpellIcon(274738, "Ancestral Call") },
        { value = "Berserking", text = SpellIcon(26297, "Berserking") },
        { value = "Blood Fury", text = SpellIcon(20572, "Blood Fury") },
        { value = "Fireblood", text = SpellIcon(265221, "Fireblood") },
    }

    local racialDropdown = GUIFrame:CreateDropdown(card2.content, "Racial", racialOptions, db.PIRacial or "", 40, function(val)
        db.PIRacial = val
    end)
    card2:AddRow(racialDropdown, 40)

    -- Consumable dropdown
    local consumableOptions = {
        { value = "", text = "None" },
        { value = "item:241309", text = ItemIcon(241309, "Light's Potential (Silver)") },
        { value = "item:241308", text = ItemIcon(241308, "Light's Potential (Gold)") },
        { value = "item:241289", text = ItemIcon(241289, "Potion of Recklessness (Silver)") },
        { value = "item:241288", text = ItemIcon(241288, "Potion of Recklessness (Gold)") },
        { value = "item:241293", text = ItemIcon(241293, "Draught of Rampant Abandon (Silver)") },
        { value = "item:241292", text = ItemIcon(241292, "Draught of Rampant Abandon (Gold)") },
        { value = "item:245897", text = ItemIcon(245897, "Fleeting Light's Potential (Silver)") },
        { value = "item:245898", text = ItemIcon(245898, "Fleeting Light's Potential (Gold)") },
    }

    local consumableDropdown = GUIFrame:CreateDropdown(card2.content, "Consumable", consumableOptions, db.PIConsumable or "", 70, function(val)
        db.PIConsumable = val
    end)
    card2:AddRow(consumableDropdown, 40)

    -- Custom /use line
    local row2d = GUIFrame:CreateRow(card2.content, 30)
    local customInput = GUIFrame:CreateEditBox(row2d, "Custom /use line", db.PICustom or "", function(val)
        db.PICustom = val
    end)
    row2d:AddWidget(customInput, 1)
    card2:AddRow(row2d, 30)

    card2:AddSpacing(4)

    card2:AddLabel("|cff888888Example: " .. KE:ColorTextByTheme("Shadowfiend") .. " or " .. KE:ColorTextByTheme("item:12345") .. "|r")

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Shortcut Commands (/rl, /fs)
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Shortcut Commands", yOffset)

    local row3 = GUIFrame:CreateRow(card3.content, 36)
    local rlCheck = GUIFrame:CreateCheckbox(row3, "Enable /rl", db.RLEnabled ~= false,
        function(checked)
            db.RLEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Reload Shortcut", "On", "Off")
    row3:AddWidget(rlCheck, 0.5)

    local fsCheck = GUIFrame:CreateCheckbox(row3, "Enable /fs", db.FSEnabled ~= false,
        function(checked)
            db.FSEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Frame Stack", "On", "Off")
    row3:AddWidget(fsCheck, 0.5)
    card3:AddRow(row3, 36)

    card3:AddLabel("|cff888888" .. KE:ColorTextByTheme("/rl") .. " reloads the UI.|r")
    card3:AddLabel("|cff888888" .. KE:ColorTextByTheme("/fs") .. " opens the Frame Stack inspector.|r")

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Party & Instance (/leave, /drop, /reset)
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Party & Instance", yOffset)

    local row4 = GUIFrame:CreateRow(card4.content, 36)
    local leaveCheck = GUIFrame:CreateCheckbox(row4, "Enable /leave + /drop", db.LeavePartyEnabled ~= false,
        function(checked)
            db.LeavePartyEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Leave Party", "On", "Off")
    row4:AddWidget(leaveCheck, 0.5)

    local resetCheck = GUIFrame:CreateCheckbox(row4, "Enable /reset", db.ResetInstancesEnabled ~= false,
        function(checked)
            db.ResetInstancesEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Reset Instances", "On", "Off")
    row4:AddWidget(resetCheck, 0.5)
    card4:AddRow(row4, 36)

    card4:AddLabel("|cff888888" .. KE:ColorTextByTheme("/leave") .. " or " .. KE:ColorTextByTheme("/drop") .. " leaves your group.|r")
    card4:AddLabel("|cff888888" .. KE:ColorTextByTheme("/reset") .. " resets all instances (leader only).|r")

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Sound Toggles (/mute, /music)
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Sound Toggles", yOffset)

    local row5 = GUIFrame:CreateRow(card5.content, 36)
    local muteCheck = GUIFrame:CreateCheckbox(row5, "Enable /mute", db.MuteEnabled ~= false,
        function(checked)
            db.MuteEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Mute Sound", "On", "Off")
    row5:AddWidget(muteCheck, 0.5)

    local musicCheck = GUIFrame:CreateCheckbox(row5, "Enable /music", db.MusicEnabled ~= false,
        function(checked)
            db.MusicEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Toggle Music", "On", "Off")
    row5:AddWidget(musicCheck, 0.5)
    card5:AddRow(row5, 36)

    card5:AddLabel("|cff888888" .. KE:ColorTextByTheme("/mute") .. " toggles all sound on/off.|r")
    card5:AddLabel("|cff888888" .. KE:ColorTextByTheme("/music") .. " toggles music on/off.|r")

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 6: /kitn Commands (info-only)
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "/kitn Subcommands", yOffset)

    card6:AddLabel("|cff888888These commands are always available via " .. KE:ColorTextByTheme("/kitn <command>") .. ":|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn essentials") .. "  |cff888888— Open KitnEssentials settings|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn cd") .. "  |cff888888— Toggle Cooldown Manager panel|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn edit") .. "  |cff888888— Toggle KitnEssentials Edit Mode|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn pi") .. "  |cff888888— Set PI macro target (mouseover or target)|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn clearchat") .. "  |cff888888— Clear all chat frames|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn chatbubbles") .. "  |cff888888— Toggle chat bubbles|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn nameplates") .. "  |cff888888— Toggle |cffFF4444enemy|r|cff888888 nameplates|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn friendplates") .. "  |cff888888— Toggle |cff44FF44friendly|r|cff888888 nameplates|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn actioncam") .. "  |cff888888— Toggle action camera|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn errors") .. "  |cff888888— Toggle Lua error display|r")

    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
