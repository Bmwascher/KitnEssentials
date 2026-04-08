-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Automation.lua                                      ║
-- ║  GUI: Automation                                         ║
-- ║  Purpose: Configuration panel for the Automation module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local table_insert = table.insert
local ipairs = ipairs

local function GetAutomationModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("Automation", true)
    end
    return nil
end

GUIFrame:RegisterContent("Automation", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Automation
    if not db then return yOffset end

    local AU = GetAutomationModule()
    local function ApplySettings()
        if AU then AU:ApplySettings() end
    end

    local allWidgets = {}

    local function ApplyAutomationState(enabled)
        if not AU then return end
        AU.db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("Automation")
        else KitnEssentials:DisableModule("Automation") end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Automation", yOffset)
    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Automation", db.Enabled ~= false,
        function(checked) db.Enabled = checked; ApplyAutomationState(checked); UpdateAllWidgetStates() end,
        true, "Automation", "On", "Off")
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)
    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Cinematics & Dialogs
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Cinematics & Dialogs", yOffset)
    table_insert(allWidgets, card2)

    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local skipCinematicsCheck = GUIFrame:CreateCheckbox(row2a, "Skip Cinematics & Movies", db.SkipCinematics ~= false,
        function(checked) db.SkipCinematics = checked; ApplySettings() end)
    row2a:AddWidget(skipCinematicsCheck, 0.5)
    table_insert(allWidgets, skipCinematicsCheck)

    local hideTalkingHeadCheck = GUIFrame:CreateCheckbox(row2a, "Hide Talking Head Frame", db.HideTalkingHead ~= false,
        function(checked) db.HideTalkingHead = checked; ApplySettings() end)
    row2a:AddWidget(hideTalkingHeadCheck, 0.5)
    table_insert(allWidgets, hideTalkingHeadCheck)
    card2:AddRow(row2a, 40)

    local row2b = GUIFrame:CreateRow(card2.content, 40)
    local hideEventToastsCheck = GUIFrame:CreateCheckbox(row2b, "Hide Event Toasts", db.HideEventToasts == true,
        function(checked) db.HideEventToasts = checked; ApplySettings() end)
    row2b:AddWidget(hideEventToastsCheck, 0.5)
    table_insert(allWidgets, hideEventToastsCheck)

    local hideZoneTextCheck = GUIFrame:CreateCheckbox(row2b, "Hide Zone Text", db.HideZoneText == true,
        function(checked) db.HideZoneText = checked; ApplySettings() end)
    row2b:AddWidget(hideZoneTextCheck, 0.5)
    table_insert(allWidgets, hideZoneTextCheck)
    card2:AddRow(row2b, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Merchant Automation
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Merchant Automation", yOffset)
    table_insert(allWidgets, card3)

    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local autoSellCheck = GUIFrame:CreateCheckbox(row3a, "Auto Sell Junk (Grey Items)", db.AutoSellJunk ~= false,
        function(checked) db.AutoSellJunk = checked; ApplySettings() end)
    row3a:AddWidget(autoSellCheck, 0.5)
    table_insert(allWidgets, autoSellCheck)

    local autoRepairCheck = GUIFrame:CreateCheckbox(row3a, "Auto Repair Gear", db.AutoRepair ~= false,
        function(checked) db.AutoRepair = checked; ApplySettings() end)
    row3a:AddWidget(autoRepairCheck, 0.5)
    table_insert(allWidgets, autoRepairCheck)
    card3:AddRow(row3a, 40)

    local row3b = GUIFrame:CreateRow(card3.content, 40)
    local useGuildCheck = GUIFrame:CreateCheckbox(row3b, "Use Guild Funds for Repair", db.UseGuildFunds ~= false,
        function(checked) db.UseGuildFunds = checked; ApplySettings() end)
    row3b:AddWidget(useGuildCheck, 0.5)
    table_insert(allWidgets, useGuildCheck)

    card3:AddRow(row3b, 40)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Group Finder
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Group Finder", yOffset)
    table_insert(allWidgets, card4)

    local row4 = GUIFrame:CreateRow(card4.content, 40)
    local autoRoleCheck = GUIFrame:CreateCheckbox(row4, "Auto Accept Role Check", db.AutoRoleCheck ~= false,
        function(checked) db.AutoRoleCheck = checked; ApplySettings() end)
    row4:AddWidget(autoRoleCheck, 0.5)
    table_insert(allWidgets, autoRoleCheck)

    local autoQueueCheck = GUIFrame:CreateCheckbox(row4, "Auto Confirm Queue", db.AutoQueueConfirm ~= false,
        function(checked) db.AutoQueueConfirm = checked; ApplySettings() end)
    row4:AddWidget(autoQueueCheck, 0.5)
    table_insert(allWidgets, autoQueueCheck)
    card4:AddRow(row4, 40)

    local row4b = GUIFrame:CreateRow(card4.content, 40)
    local autoKeystoneCheck = GUIFrame:CreateCheckbox(row4b, "Auto Slot Keystone", db.AutoSlotKeystone ~= false,
        function(checked) db.AutoSlotKeystone = checked; ApplySettings() end)
    row4b:AddWidget(autoKeystoneCheck, 0.5)
    table_insert(allWidgets, autoKeystoneCheck)
    card4:AddRow(row4b, 40)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 5: Quest Automation
    ---------------------------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Quest Automation", yOffset)
    table_insert(allWidgets, card5)

    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local autoAcceptCheck = GUIFrame:CreateCheckbox(row5a, "Auto Accept Quests", db.AutoAcceptQuests == true,
        function(checked) db.AutoAcceptQuests = checked; ApplySettings() end)
    row5a:AddWidget(autoAcceptCheck, 0.5)
    table_insert(allWidgets, autoAcceptCheck)

    local autoTurnInCheck = GUIFrame:CreateCheckbox(row5a, "Auto Turn In Quests", db.AutoTurnInQuests == true,
        function(checked) db.AutoTurnInQuests = checked; ApplySettings() end)
    row5a:AddWidget(autoTurnInCheck, 0.5)
    table_insert(allWidgets, autoTurnInCheck)
    card5:AddRow(row5a, 40)

    local row5b = GUIFrame:CreateRow(card5.content, 36)
    local modifierOptions = {
        { value = "SHIFT", text = "Shift" },
        { value = "CTRL", text = "Ctrl" },
        { value = "ALT", text = "Alt" },
        { value = "NONE", text = "None" },
    }
    local modDropdown = GUIFrame:CreateDropdown(row5b, "Hold to Pause Auto-Quest", modifierOptions,
        db.QuestModifier or "SHIFT", nil, function(val) db.QuestModifier = val end)
    row5b:AddWidget(modDropdown, 1)
    table_insert(allWidgets, modDropdown)
    card5:AddRow(row5b, 36)

    card5:AddLabel("|cff888888Hold the selected modifier key when talking to an NPC to pause auto-quest. Multiple rewards will always prompt.|r")

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 6: Social
    ---------------------------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Social", yOffset)
    table_insert(allWidgets, card6)

    local row6a = GUIFrame:CreateRow(card6.content, 40)
    local autoDeclineDuelsCheck = GUIFrame:CreateCheckbox(row6a, "Auto Decline Duels", db.AutoDeclineDuels == true,
        function(checked) db.AutoDeclineDuels = checked; ApplySettings() end)
    row6a:AddWidget(autoDeclineDuelsCheck, 0.5)
    table_insert(allWidgets, autoDeclineDuelsCheck)

    local autoDeclinePetCheck = GUIFrame:CreateCheckbox(row6a, "Auto Decline Pet Battle Duels", db.AutoDeclinePetBattles == true,
        function(checked) db.AutoDeclinePetBattles = checked; ApplySettings() end)
    row6a:AddWidget(autoDeclinePetCheck, 0.5)
    table_insert(allWidgets, autoDeclinePetCheck)
    card6:AddRow(row6a, 40)

    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 7: Convenience
    ---------------------------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Convenience", yOffset)
    table_insert(allWidgets, card7)

    local row7a = GUIFrame:CreateRow(card7.content, 40)
    local autoFillDeleteCheck = GUIFrame:CreateCheckbox(row7a, "Auto-Fill DELETE Text", db.AutoFillDelete ~= false,
        function(checked) db.AutoFillDelete = checked; ApplySettings() end)
    row7a:AddWidget(autoFillDeleteCheck, 0.5)
    table_insert(allWidgets, autoFillDeleteCheck)

    local autoLootCheck = GUIFrame:CreateCheckbox(row7a, "Auto Loot", db.AutoLoot ~= false,
        function(checked) db.AutoLoot = checked; ApplySettings() end)
    row7a:AddWidget(autoLootCheck, 0.5)
    table_insert(allWidgets, autoLootCheck)
    card7:AddRow(row7a, 40)

    yOffset = yOffset + card7:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 8: Vantus Rune Withdrawer
    ---------------------------------------------------------------------------------
    local vrDB = KE.db and KE.db.profile.VantusRune
    if vrDB then
        local VR = KitnEssentials and KitnEssentials:GetModule("VantusRune", true)

        local function ApplyVRState(enabled)
            if not VR then return end
            vrDB.Enabled = enabled
            if enabled then KitnEssentials:EnableModule("VantusRune")
            else KitnEssentials:DisableModule("VantusRune") end
        end

        local card8 = GUIFrame:CreateCard(scrollChild, "Vantus Rune Withdrawer", yOffset)
        table_insert(allWidgets, card8)

        local row8a = GUIFrame:CreateRow(card8.content, 40)
        local vrEnableCheck = GUIFrame:CreateCheckbox(row8a, "Enable Vantus Rune", vrDB.Enabled ~= false,
            function(checked) ApplyVRState(checked) end)
        row8a:AddWidget(vrEnableCheck, 0.5)
        table_insert(allWidgets, vrEnableCheck)

        local vrChatCheck = GUIFrame:CreateCheckbox(row8a, "Show Chat Messages", vrDB.ShowChatMessages ~= false,
            function(checked) vrDB.ShowChatMessages = checked end)
        row8a:AddWidget(vrChatCheck, 0.5)
        table_insert(allWidgets, vrChatCheck)
        card8:AddRow(row8a, 40)

        local row8b = GUIFrame:CreateRow(card8.content, 40)
        local vrTimeoutSlider = GUIFrame:CreateSlider(row8b, "Confirm Timeout", 5, 30, 1, vrDB.ConfirmationTimeout or 15, 50,
            function(val) vrDB.ConfirmationTimeout = val end)
        row8b:AddWidget(vrTimeoutSlider, 0.5)
        table_insert(allWidgets, vrTimeoutSlider)
        card8:AddRow(row8b, 40)

        card8:AddLabel("|cff888888Adds a button to the Guild Bank to withdraw one Vantus Rune.\nPriority: Radiant Gold (245880) > Radiant Silver (245879).\nYou must be on the same realm as your guild to withdraw.|r")

        yOffset = yOffset + card8:GetContentHeight() + Theme.paddingSmall
    end

    ---------------------------------------------------------------------------------
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)
