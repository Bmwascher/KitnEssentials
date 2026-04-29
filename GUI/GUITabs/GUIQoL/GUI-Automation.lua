-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Automation.lua                                      ║
-- ║  GUI: Automation                                         ║
-- ║  Purpose: Configuration panel for the Automation module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("Automation", true)
    end
    return nil
end

GUIFrame:RegisterContent("Automation", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Automation
    if not db then return yOffset end

    local AU = GetModule()
    local autoManager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if AU then AU:ApplySettings() end
    end

    local function ApplyAutomationState(enabled)
        if not AU then return end
        AU.db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("Automation")
        else KitnEssentials:DisableModule("Automation") end
    end

    local function RefreshAutoStates()
        autoManager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Automation", yOffset)
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Automation", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyAutomationState(checked)
            RefreshAutoStates()
        end,
        msgPopup = true,
        msgText = "Automation",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Cinematics & Dialogs
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Cinematics & Dialogs", yOffset)
    autoManager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local skipCinematicsCheck = GUIFrame:CreateCheckbox(row2a, "Skip Cinematics & Movies", {
        value = db.SkipCinematics ~= false,
        callback = function(checked) db.SkipCinematics = checked; ApplySettings() end,
    })
    row2a:AddWidget(skipCinematicsCheck, 0.5)
    autoManager:Register(skipCinematicsCheck, "all")

    local hideTalkingHeadCheck = GUIFrame:CreateCheckbox(row2a, "Hide Talking Head Frame", {
        value = db.HideTalkingHead ~= false,
        callback = function(checked) db.HideTalkingHead = checked; ApplySettings() end,
    })
    row2a:AddWidget(hideTalkingHeadCheck, 0.5)
    autoManager:Register(hideTalkingHeadCheck, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local hideEventToastsCheck = GUIFrame:CreateCheckbox(row2b, "Hide Event Toasts", {
        value = db.HideEventToasts == true,
        callback = function(checked) db.HideEventToasts = checked; ApplySettings() end,
    })
    row2b:AddWidget(hideEventToastsCheck, 0.5)
    autoManager:Register(hideEventToastsCheck, "all")

    local hideZoneTextCheck = GUIFrame:CreateCheckbox(row2b, "Hide Zone Text", {
        value = db.HideZoneText == true,
        callback = function(checked) db.HideZoneText = checked; ApplySettings() end,
    })
    row2b:AddWidget(hideZoneTextCheck, 0.5)
    autoManager:Register(hideZoneTextCheck, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Merchant Automation
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Merchant Automation", yOffset)
    autoManager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local autoSellCheck = GUIFrame:CreateCheckbox(row3a, "Auto Sell Junk (Grey Items)", {
        value = db.AutoSellJunk ~= false,
        callback = function(checked) db.AutoSellJunk = checked; ApplySettings() end,
    })
    row3a:AddWidget(autoSellCheck, 0.5)
    autoManager:Register(autoSellCheck, "all")

    local autoRepairCheck = GUIFrame:CreateCheckbox(row3a, "Auto Repair Gear", {
        value = db.AutoRepair ~= false,
        callback = function(checked) db.AutoRepair = checked; ApplySettings() end,
    })
    row3a:AddWidget(autoRepairCheck, 0.5)
    autoManager:Register(autoRepairCheck, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local useGuildCheck = GUIFrame:CreateCheckbox(row3b, "Use Guild Funds for Repair", {
        value = db.UseGuildFunds ~= false,
        callback = function(checked) db.UseGuildFunds = checked; ApplySettings() end,
    })
    row3b:AddWidget(useGuildCheck, 0.5)
    autoManager:Register(useGuildCheck, "all")
    card3:AddRow(row3b, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Group Finder
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Group Finder", yOffset)
    autoManager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local autoRoleCheck = GUIFrame:CreateCheckbox(row4a, "Auto Accept Role Check", {
        value = db.AutoRoleCheck ~= false,
        callback = function(checked) db.AutoRoleCheck = checked; ApplySettings() end,
    })
    row4a:AddWidget(autoRoleCheck, 0.5)
    autoManager:Register(autoRoleCheck, "all")

    local autoQueueCheck = GUIFrame:CreateCheckbox(row4a, "Auto Confirm Queue", {
        value = db.AutoQueueConfirm ~= false,
        callback = function(checked) db.AutoQueueConfirm = checked; ApplySettings() end,
    })
    row4a:AddWidget(autoQueueCheck, 0.5)
    autoManager:Register(autoQueueCheck, "all")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local autoKeystoneCheck = GUIFrame:CreateCheckbox(row4b, "Auto Slot Keystone", {
        value = db.AutoSlotKeystone ~= false,
        callback = function(checked) db.AutoSlotKeystone = checked; ApplySettings() end,
    })
    row4b:AddWidget(autoKeystoneCheck, 0.5)
    autoManager:Register(autoKeystoneCheck, "all")
    card4:AddRow(row4b, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Quest Automation
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Quest Automation", yOffset)
    autoManager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local autoAcceptCheck = GUIFrame:CreateCheckbox(row5a, "Auto Accept Quests", {
        value = db.AutoAcceptQuests == true,
        callback = function(checked) db.AutoAcceptQuests = checked; ApplySettings() end,
    })
    row5a:AddWidget(autoAcceptCheck, 0.5)
    autoManager:Register(autoAcceptCheck, "all")

    local autoTurnInCheck = GUIFrame:CreateCheckbox(row5a, "Auto Turn In Quests", {
        value = db.AutoTurnInQuests == true,
        callback = function(checked) db.AutoTurnInQuests = checked; ApplySettings() end,
    })
    row5a:AddWidget(autoTurnInCheck, 0.5)
    autoManager:Register(autoTurnInCheck, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local modDropdown = GUIFrame:CreateDropdown(row5b, "Hold to Pause Auto-Quest", {
        options = {
            { key = "SHIFT", text = "Shift" },
            { key = "CTRL",  text = "Ctrl" },
            { key = "ALT",   text = "Alt" },
            { key = "NONE",  text = "None" },
        },
        value = db.QuestModifier or "SHIFT",
        callback = function(val) db.QuestModifier = val end,
    })
    row5b:AddWidget(modDropdown, 1)
    autoManager:Register(modDropdown, "all")
    card5:AddRow(row5b, Theme.rowHeightLast, 0)

    card5:AddLabel("|cff888888Hold the selected modifier key when talking to an NPC to pause auto-quest. Multiple rewards will always prompt.|r")

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Social
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Social", yOffset)
    autoManager:Register(card6, "all")

    local row6 = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local autoDeclineDuelsCheck = GUIFrame:CreateCheckbox(row6, "Auto Decline Duels", {
        value = db.AutoDeclineDuels == true,
        callback = function(checked) db.AutoDeclineDuels = checked; ApplySettings() end,
    })
    row6:AddWidget(autoDeclineDuelsCheck, 0.5)
    autoManager:Register(autoDeclineDuelsCheck, "all")

    local autoDeclinePetCheck = GUIFrame:CreateCheckbox(row6, "Auto Decline Pet Battle Duels", {
        value = db.AutoDeclinePetBattles == true,
        callback = function(checked) db.AutoDeclinePetBattles = checked; ApplySettings() end,
    })
    row6:AddWidget(autoDeclinePetCheck, 0.5)
    autoManager:Register(autoDeclinePetCheck, "all")
    card6:AddRow(row6, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Convenience
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Convenience", yOffset)
    autoManager:Register(card7, "all")

    local row7 = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
    local autoFillDeleteCheck = GUIFrame:CreateCheckbox(row7, "Auto-Fill DELETE Text", {
        value = db.AutoFillDelete ~= false,
        callback = function(checked) db.AutoFillDelete = checked; ApplySettings() end,
    })
    row7:AddWidget(autoFillDeleteCheck, 0.5)
    autoManager:Register(autoFillDeleteCheck, "all")

    local autoLootCheck = GUIFrame:CreateCheckbox(row7, "Auto Loot", {
        value = db.AutoLoot ~= false,
        callback = function(checked) db.AutoLoot = checked; ApplySettings() end,
    })
    row7:AddWidget(autoLootCheck, 0.5)
    autoManager:Register(autoLootCheck, "all")
    card7:AddRow(row7, Theme.rowHeightLast, 0)

    yOffset = card7:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 8: Vantus Rune Withdrawer (independent module — own cascade)
    ----------------------------------------------------------------
    local vrDB = KE.db and KE.db.profile.VantusRune
    if vrDB then
        local vrManager = GUIFrame:CreateWidgetStateManager()

        local function ApplyVRState(enabled)
            vrDB.Enabled = enabled
            if enabled then KitnEssentials:EnableModule("VantusRune")
            else KitnEssentials:DisableModule("VantusRune") end
        end

        local function RefreshVRStates()
            vrManager:UpdateAll(vrDB.Enabled ~= false)
        end

        local card8 = GUIFrame:CreateCard(scrollChild, "Vantus Rune Withdrawer", yOffset)
        vrManager:Register(card8, "all")

        local row8a = GUIFrame:CreateRow(card8.content, Theme.rowHeight)
        local vrEnableCheck = GUIFrame:CreateCheckbox(row8a, "Enable Vantus Rune", {
            value = vrDB.Enabled ~= false,
            callback = function(checked)
                ApplyVRState(checked)
                RefreshVRStates()
            end,
            msgPopup = true,
            msgText = "Vantus Rune Withdrawer",
            msgOn = "On",
            msgOff = "Off",
        })
        row8a:AddWidget(vrEnableCheck, 0.5)

        local vrChatCheck = GUIFrame:CreateCheckbox(row8a, "Show Chat Messages", {
            value = vrDB.ShowChatMessages ~= false,
            callback = function(checked) vrDB.ShowChatMessages = checked end,
        })
        row8a:AddWidget(vrChatCheck, 0.5)
        vrManager:Register(vrChatCheck, "all")
        card8:AddRow(row8a, Theme.rowHeight)

        local row8b = GUIFrame:CreateRow(card8.content, Theme.rowHeightLast)
        local vrTimeoutSlider = GUIFrame:CreateSlider(row8b, "Confirm Timeout", {
            min = 5, max = 30, step = 1,
            value = vrDB.ConfirmationTimeout or 15,
            callback = function(val) vrDB.ConfirmationTimeout = val end,
        })
        row8b:AddWidget(vrTimeoutSlider, 0.5)
        vrManager:Register(vrTimeoutSlider, "all")
        card8:AddRow(row8b, Theme.rowHeightLast, 0)

        card8:AddLabel("|cff888888Adds a button to the Guild Bank to withdraw one Vantus Rune.\nPriority: Radiant Gold (245880) > Radiant Silver (245879).\nYou must be on the same realm as your guild to withdraw.|r")

        yOffset = card8:GetNextOffset()

        RefreshVRStates()
    end

    RefreshAutoStates()
    return yOffset
end)
