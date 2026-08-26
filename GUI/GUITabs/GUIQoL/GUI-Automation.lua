-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Automation.lua                                      ║
-- ║  GUI: Automation                                         ║
-- ║  Purpose: Configuration panel for the Automation module, ║
-- ║           split across four tabs (General, Interface,    ║
-- ║           Quests & Social, Vendors & Bags) behind a      ║
-- ║           shared header toggle. Three independent        ║
-- ║           modules with their own switches live here and  ║
-- ║           have no other route: Vantus Rune Withdrawer on ║
-- ║           General, Auction House Filter and Merchant     ║
-- ║           Pages on Vendors & Bags. Those two tabs are    ║
-- ║           therefore offered even while the master is off.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local ipairs = ipairs

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("Automation", true)
    end
    return nil
end

local function GetDB()
    return KE.db and KE.db.profile.Automation
end

local function ApplySettings()
    local AU = GetModule()
    if AU then AU:ApplySettings() end
end

-- Renders above the tab strip. Never collapses: the tab list already drops
-- to Vendors & Bags alone while the master is off, and collapsing here as
-- well would take Auction House Filter, Vantus Rune Withdrawer and Merchant
-- Pages down with a table this page alone owns.
--
-- Hide Helptips lives here, not on a gated tab, because it is
-- master-independent (still applies while Automation itself is off) and this
-- card is the only surface that renders in every state.
local function BuildHeader(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset, false end

    local function ApplyAutomationState(enabled)
        local AU = GetModule()
        if not AU then return end
        AU.db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("Automation")
        else KitnEssentials:DisableModule("Automation") end
    end

    local card1 = GUIFrame:CreateCard(scrollChild, "Automation", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyAutomationState(checked)
        KE:Print("Automation: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    return card1:GetNextOffset(), false
end

----------------------------------------------------------------
-- General: Convenience, Housing Item Auto-Roll, Vantus Rune Withdrawer
----------------------------------------------------------------
-- Survives master-off because Vantus Rune Withdrawer is an independent module
-- and this is its only route. Convenience and Housing Item Auto-Roll gate on
-- the master; Vantus Rune always renders, even when db (the Automation table
-- itself) is missing entirely.
GUIFrame:RegisterContent("AutomationGeneral", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end

    local manager = GUIFrame:CreateWidgetStateManager()

    local card = GUIFrame:CreateCard(scrollChild, "Convenience", yOffset)
    manager:Register(card, "all")

    local row1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local autoFillDeleteCheck = GUIFrame:CreateCheckbox(row1, "Auto-Fill DELETE Text", {
        value = db.AutoFillDelete ~= false,
        callback = function(checked) db.AutoFillDelete = checked; ApplySettings() end,
    })
    row1:AddWidget(autoFillDeleteCheck, 0.5)
    manager:Register(autoFillDeleteCheck, "all")

    local autoLootCheck = GUIFrame:CreateCheckbox(row1, "Auto Loot", {
        value = db.AutoLoot ~= false,
        callback = function(checked) db.AutoLoot = checked; ApplySettings() end,
    })
    row1:AddWidget(autoLootCheck, 0.5)
    manager:Register(autoLootCheck, "all")
    card:AddRow(row1, Theme.rowHeight)

    local row2 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local autoConfirmLootRollCheck = GUIFrame:CreateCheckbox(row2, "Auto-Confirm Loot Roll Popup", {
        value = db.AutoConfirmLootRoll == true,
        callback = function(checked) db.AutoConfirmLootRoll = checked; ApplySettings() end,
    })
    row2:AddWidget(autoConfirmLootRollCheck, 0.5)
    manager:Register(autoConfirmLootRollCheck, "all")

    local confirmBonusRollCheck = GUIFrame:CreateCheckbox(row2, "Confirm Bonus Rolls", {
        value = db.ConfirmBonusRoll == true,
        callback = function(checked) db.ConfirmBonusRoll = checked; ApplySettings() end,
    })
    row2:AddWidget(confirmBonusRollCheck, 0.5)
    manager:Register(confirmBonusRollCheck, "all")
    card:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card:GetNextOffset()

    -- Master-gated, like the Convenience card above it.
    if db.Enabled ~= false then
        ----------------------------------------------------------------
        -- Housing Item Auto-Roll
        ----------------------------------------------------------------
        local cardHousing = GUIFrame:CreateCard(scrollChild, "Housing Item Auto-Roll", yOffset)
        manager:Register(cardHousing, "all")

        local rowHousing = GUIFrame:CreateRow(cardHousing.content, Theme.rowHeightLast)
        local autoPassHousingCheck = GUIFrame:CreateCheckbox(rowHousing, "Auto-Roll on Housing Items", {
            value = db.AutoPassHousing == true,
            callback = function(checked) db.AutoPassHousing = checked; ApplySettings() end,
        })
        rowHousing:AddWidget(autoPassHousingCheck, 0.5)
        manager:Register(autoPassHousingCheck, "all")

        local rollModeDropdown = GUIFrame:CreateDropdown(rowHousing, "Roll Type", {
            options = {
                { key = "PASS", text = "Pass" },
                { key = "NEED", text = "Need" },
            },
            value = db.AutoPassHousingMode or "PASS",
            callback = function(val) db.AutoPassHousingMode = val end,
        })
        rowHousing:AddWidget(rollModeDropdown, 0.5)
        manager:Register(rollModeDropdown, "all")
        cardHousing:AddRow(rowHousing, Theme.rowHeightLast, 0)

        cardHousing:AddLabel("|cff888888Auto-rolls on Housing items based on your roll type selection. Useful in raids/dungeons where housing decor drops aren't gear upgrades.|r")

        yOffset = cardHousing:GetNextOffset()
    end

    manager:UpdateAll(true)

    ----------------------------------------------------------------
    -- Vantus Rune Withdrawer (independent module — own cascade)
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

        local cardVR = GUIFrame:CreateCard(scrollChild, "Vantus Rune Withdrawer", yOffset)
        cardVR:AddHeaderToggle(vrDB.Enabled ~= false, function(checked)
            ApplyVRState(checked)
            KE:Print("Vantus Rune Withdrawer: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
        end)
        yOffset = cardVR:GetNextOffset()

        if vrDB.Enabled ~= false then
            local rowVR1 = GUIFrame:CreateRow(cardVR.content, Theme.rowHeight)
            local vrChatCheck = GUIFrame:CreateCheckbox(rowVR1, "Show Chat Messages", {
                value = vrDB.ShowChatMessages ~= false,
                callback = function(checked) vrDB.ShowChatMessages = checked end,
            })
            rowVR1:AddWidget(vrChatCheck, 1)
            vrManager:Register(vrChatCheck, "all")
            cardVR:AddRow(rowVR1, Theme.rowHeight)

            local rowVR2 = GUIFrame:CreateRow(cardVR.content, Theme.rowHeightLast)
            local vrTimeoutSlider = GUIFrame:CreateSlider(rowVR2, "Confirm Timeout", {
                min = 5, max = 30, step = 1,
                value = vrDB.ConfirmationTimeout or 15,
                callback = function(val) vrDB.ConfirmationTimeout = val end,
            })
            rowVR2:AddWidget(vrTimeoutSlider, 0.5)
            vrManager:Register(vrTimeoutSlider, "all")
            cardVR:AddRow(rowVR2, Theme.rowHeightLast, 0)

            cardVR:AddLabel("|cff888888Adds a button to the Guild Bank to withdraw one Vantus Rune.\nThe highest-quality current-tier rune is chosen first.\nYou must be on the same realm as your guild to withdraw.|r")

            yOffset = cardVR:GetNextOffset()
        end

        RefreshVRStates()
    end

    return yOffset
end)

----------------------------------------------------------------
-- Interface: Cinematics & Dialogs, Interface Cleanup, Hide Transform Items
----------------------------------------------------------------
GUIFrame:RegisterContent("AutomationInterface", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end

    local AU = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    ----------------------------------------------------------------
    -- Cinematics & Dialogs
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Cinematics & Dialogs", yOffset)
    manager:Register(card1, "all")

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local skipCinematicsCheck = GUIFrame:CreateCheckbox(row1a, "Skip Cinematics & Movies", {
        value = db.SkipCinematics ~= false,
        callback = function(checked) db.SkipCinematics = checked; ApplySettings() end,
    })
    row1a:AddWidget(skipCinematicsCheck, 0.5)
    manager:Register(skipCinematicsCheck, "all")

    local hideTalkingHeadCheck = GUIFrame:CreateCheckbox(row1a, "Hide Talking Head Frame", {
        value = db.HideTalkingHead ~= false,
        callback = function(checked) db.HideTalkingHead = checked; ApplySettings() end,
    })
    row1a:AddWidget(hideTalkingHeadCheck, 0.5)
    manager:Register(hideTalkingHeadCheck, "all")
    card1:AddRow(row1a, Theme.rowHeight)

    local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local hideEventToastsCheck = GUIFrame:CreateCheckbox(row1b, "Hide Event Toasts", {
        value = db.HideEventToasts == true,
        callback = function(checked) db.HideEventToasts = checked; ApplySettings() end,
    })
    row1b:AddWidget(hideEventToastsCheck, 0.5)
    manager:Register(hideEventToastsCheck, "all")

    local hideZoneTextCheck = GUIFrame:CreateCheckbox(row1b, "Hide Zone Text", {
        value = db.HideZoneText == true,
        callback = function(checked) db.HideZoneText = checked; ApplySettings() end,
    })
    row1b:AddWidget(hideZoneTextCheck, 0.5)
    manager:Register(hideZoneTextCheck, "all")
    card1:AddRow(row1b, Theme.rowHeight)

    local row1c = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local hideBossBannerLootCheck = GUIFrame:CreateCheckbox(row1c, "Hide Boss Banner Loot", {
        value = db.HideBossBannerLoot == true,
        callback = function(checked) db.HideBossBannerLoot = checked; ApplySettings() end,
    })
    row1c:AddWidget(hideBossBannerLootCheck, 1)
    manager:Register(hideBossBannerLootCheck, "all")
    card1:AddRow(row1c, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Interface Cleanup
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Interface Cleanup", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local hideScreenshotStatusCheck = GUIFrame:CreateCheckbox(row2, "Hide Screenshot Status", {
        value = db.HideScreenshotStatus == true,
        tooltip = "Hides the screenshot status text that appears after taking a screenshot.",
        callback = function(checked) db.HideScreenshotStatus = checked; ApplySettings() end,
    })
    row2:AddWidget(hideScreenshotStatusCheck, 0.5)
    manager:Register(hideScreenshotStatusCheck, "all")

    local hideErrorMessagesCheck = GUIFrame:CreateCheckbox(row2, "Hide Error Messages", {
        value = db.HideErrorMessages == true,
        tooltip = "Hides red error text spam. Full bags, a full quest log, group-kick notices, and dead pet or player errors always stay visible. Fully reversible.",
        callback = function(checked) db.HideErrorMessages = checked; ApplySettings() end,
    })
    row2:AddWidget(hideErrorMessagesCheck, 0.5)
    manager:Register(hideErrorMessagesCheck, "all")
    card2:AddRow(row2, Theme.rowHeight)

    -- Hide Helptips is NOT registered with the manager: it is master-independent
    -- and keeps working while Automation is off, so it must never be greyed out
    -- alongside the switches that do follow the master.
    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local hideHelptipsCheck = GUIFrame:CreateCheckbox(row2b, "Hide Helptips", {
        value = db.HideHelptips ~= false,
        tooltip = "Suppresses Blizzard's tutorial and \"Did you know\" popups. Works whether or not Automation itself is on -- but this switch is only reachable while Automation is on.",
        callback = function(checked)
            db.HideHelptips = checked
            ApplySettings()
        end,
    })
    row2b:AddWidget(hideHelptipsCheck, 1)
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Hide Transform Items
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Hide Transform Items", yOffset)
    manager:Register(card3, "all")

    local showGrid = db.HideTransforms == true and AU ~= nil and AU.HideTransformsData ~= nil

    local row3 = GUIFrame:CreateRow(card3.content, showGrid and Theme.rowHeight or Theme.rowHeightLast)
    local hideTransformsCheck = GUIFrame:CreateCheckbox(row3, "Auto-Cancel Transforms", {
        value = db.HideTransforms == true,
        tooltip = "Automatically cancels cosmetic transform effects, such as profession gear, holiday costumes and prank toys, picked below.",
        callback = function(checked)
            db.HideTransforms = checked
            ApplySettings()
            GUIFrame:RefreshContent()
        end,
    })
    row3:AddWidget(hideTransformsCheck, 1)
    manager:Register(hideTransformsCheck, "all")
    if showGrid then
        card3:AddRow(row3, Theme.rowHeight)
    else
        card3:AddRow(row3, Theme.rowHeightLast, 0)
    end

    if showGrid then
        local data = AU.HideTransformsData
        local PER_ROW = 3
        local CELL_H = 24
        local HEADING_H = 22
        local CELL_SPACING = 2

        -- Bucket items by category once, then walk AU.HideTransformsData.order
        -- so the heading rows appear in the frozen category order regardless
        -- of how TRANSFORMS itself is laid out.
        local byCategory = {}
        for _, item in ipairs(data.items) do
            byCategory[item.cat] = byCategory[item.cat] or {}
            local list = byCategory[item.cat]
            list[#list + 1] = item
        end

        local categories = {}
        for _, catKey in ipairs(data.order) do
            if byCategory[catKey] then
                categories[#categories + 1] = catKey
            end
        end

        for catIdx, catKey in ipairs(categories) do
            local items = byCategory[catKey]

            local headingRow = GUIFrame:CreateRow(card3.content, HEADING_H)
            local headingText = headingRow:CreateFontString(nil, "OVERLAY")
            headingText:SetPoint("TOPLEFT", headingRow, "TOPLEFT", 0, 0)
            headingText:SetPoint("BOTTOMRIGHT", headingRow, "BOTTOMRIGHT", 0, 0)
            headingText:SetJustifyH("LEFT")
            KE:ApplyThemeFont(headingText, "normal")
            headingText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            headingText:SetText(data.labels[catKey] or catKey)
            card3:AddRow(headingRow, HEADING_H)

            local i = 1
            while i <= #items do
                local isLastGridRow = (catIdx == #categories) and (i + PER_ROW) > #items
                local gridRow = GUIFrame:CreateRow(card3.content, CELL_H)
                for c = 0, PER_ROW - 1 do
                    local item = items[i + c]
                    if item then
                        local itemKey = item.key
                        local check = GUIFrame:CreateCompactCheckbox(gridRow, item.label, {
                            value = AU.GetHideTransformItem(itemKey),
                            callback = function(checked)
                                AU:SetHideTransformItem(itemKey, checked)
                            end,
                        })
                        gridRow:AddWidget(check, 1 / PER_ROW)
                        manager:Register(check, "all")
                    end
                end
                card3:AddRow(gridRow, CELL_H, isLastGridRow and 0 or CELL_SPACING)
                i = i + PER_ROW
            end
        end
    end

    yOffset = card3:GetNextOffset()

    manager:UpdateAll(true)
    return yOffset
end)

----------------------------------------------------------------
-- Quests & Social: Quest Automation, Group Finder, Social
----------------------------------------------------------------
GUIFrame:RegisterContent("AutomationQuests", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end

    local manager = GUIFrame:CreateWidgetStateManager()

    ----------------------------------------------------------------
    -- Quest Automation
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Quest Automation", yOffset)
    manager:Register(card1, "all")

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local autoAcceptCheck = GUIFrame:CreateCheckbox(row1a, "Auto Accept Quests", {
        value = db.AutoAcceptQuests == true,
        callback = function(checked) db.AutoAcceptQuests = checked; ApplySettings() end,
    })
    row1a:AddWidget(autoAcceptCheck, 0.5)
    manager:Register(autoAcceptCheck, "all")

    local autoTurnInCheck = GUIFrame:CreateCheckbox(row1a, "Auto Turn In Quests", {
        value = db.AutoTurnInQuests == true,
        callback = function(checked) db.AutoTurnInQuests = checked; ApplySettings() end,
    })
    row1a:AddWidget(autoTurnInCheck, 0.5)
    manager:Register(autoTurnInCheck, "all")
    card1:AddRow(row1a, Theme.rowHeight)

    local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local autoVoidcoresCheck = GUIFrame:CreateCheckbox(row1b, "Auto Voidcores: Gold (Decimus)", {
        value = db.AutoVoidcoresGold == true,
        callback = function(checked) db.AutoVoidcoresGold = checked; ApplySettings() end,
    })
    row1b:AddWidget(autoVoidcoresCheck, 0.5)
    manager:Register(autoVoidcoresCheck, "all")

    local unwatchHiddenCheck = GUIFrame:CreateCheckbox(row1b, "Unwatch Hidden Quests on Login", {
        value = db.AutoUnwatchHidden ~= false,
        callback = function(checked) db.AutoUnwatchHidden = checked; ApplySettings() end,
    })
    row1b:AddWidget(unwatchHiddenCheck, 0.5)
    manager:Register(unwatchHiddenCheck, "all")
    card1:AddRow(row1b, Theme.rowHeight)

    local row1c = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local modDropdown = GUIFrame:CreateDropdown(row1c, "Hold to Pause Auto-Quest", {
        options = {
            { key = "SHIFT", text = "Shift" },
            { key = "CTRL",  text = "Ctrl" },
            { key = "ALT",   text = "Alt" },
            { key = "NONE",  text = "None" },
        },
        value = db.QuestModifier or "SHIFT",
        callback = function(val) db.QuestModifier = val end,
    })
    row1c:AddWidget(modDropdown, 1)
    manager:Register(modDropdown, "all")
    card1:AddRow(row1c, Theme.rowHeightLast, 0)

    card1:AddLabel("|cff888888Hold the selected modifier key when talking to an NPC to pause auto-quest. Multiple rewards will always prompt.\nAuto Voidcores: Automatically accepts and completes the weekly quest from Decimus for gold, even when general auto-accept/turn-in is off (Hold to Pause modifier is respected still).|r")

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Group Finder
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Group Finder", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local autoRoleCheck = GUIFrame:CreateCheckbox(row2a, "Auto Accept Role Check", {
        value = db.AutoRoleCheck ~= false,
        callback = function(checked) db.AutoRoleCheck = checked; ApplySettings() end,
    })
    row2a:AddWidget(autoRoleCheck, 0.5)
    manager:Register(autoRoleCheck, "all")

    local autoQueueCheck = GUIFrame:CreateCheckbox(row2a, "Auto Confirm Queue", {
        value = db.AutoQueueConfirm ~= false,
        callback = function(checked) db.AutoQueueConfirm = checked; ApplySettings() end,
    })
    row2a:AddWidget(autoQueueCheck, 0.5)
    manager:Register(autoQueueCheck, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local autoKeystoneCheck = GUIFrame:CreateCheckbox(row2b, "Auto Slot Keystone", {
        value = db.AutoSlotKeystone ~= false,
        callback = function(checked) db.AutoSlotKeystone = checked; ApplySettings() end,
    })
    row2b:AddWidget(autoKeystoneCheck, 0.5)
    manager:Register(autoKeystoneCheck, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Social
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Social", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local autoDeclineDuelsCheck = GUIFrame:CreateCheckbox(row3a, "Auto Decline Duels", {
        value = db.AutoDeclineDuels == true,
        callback = function(checked) db.AutoDeclineDuels = checked; ApplySettings() end,
    })
    row3a:AddWidget(autoDeclineDuelsCheck, 0.5)
    manager:Register(autoDeclineDuelsCheck, "all")

    local autoDeclinePetCheck = GUIFrame:CreateCheckbox(row3a, "Auto Decline Pet Battle Duels", {
        value = db.AutoDeclinePetBattles == true,
        callback = function(checked) db.AutoDeclinePetBattles = checked; ApplySettings() end,
    })
    row3a:AddWidget(autoDeclinePetCheck, 0.5)
    manager:Register(autoDeclinePetCheck, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local autoAcceptResCheck = GUIFrame:CreateCheckbox(row3b, "Auto Accept Resurrection (out of combat)", {
        value = db.AutoAcceptRes == true,
        callback = function(checked)
            db.AutoAcceptRes = checked
            ApplySettings()
        end,
        msgPopup = true,
        msgText = "Auto Accept Resurrection",
        msgOn = "Enabled",
        msgOff = "Disabled",
    })
    row3b:AddWidget(autoAcceptResCheck, 1)
    manager:Register(autoAcceptResCheck, "all")
    card3:AddRow(row3b, Theme.rowHeightLast, 0)

    card3:AddLabel("|cff888888Combat res / Soulstone are never auto-accepted; you stay in control during encounters.|r")

    yOffset = card3:GetNextOffset()

    manager:UpdateAll(true)
    return yOffset
end)

----------------------------------------------------------------
-- Vendors & Bags: Merchant Automation, Merchant Pages,
-- Auction House Filter, Collections & Bags
----------------------------------------------------------------
-- Also survives master-off. Merchant Automation and Collections & Bags gate on
-- the master; Auction House Filter and Merchant Pages are independent modules
-- and always render, even when db (the Automation table itself) is missing
-- entirely.
GUIFrame:RegisterContent("AutomationVendors", function(scrollChild, yOffset)
    local db = GetDB()
    local gated = db and db.Enabled == true

    local manager = GUIFrame:CreateWidgetStateManager()

    if gated then
        ----------------------------------------------------------------
        -- Merchant Automation
        ----------------------------------------------------------------
        local card1 = GUIFrame:CreateCard(scrollChild, "Merchant Automation", yOffset)
        manager:Register(card1, "all")

        local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
        local autoSellCheck = GUIFrame:CreateCheckbox(row1a, "Auto Sell Junk (Grey Items)", {
            value = db.AutoSellJunk ~= false,
            callback = function(checked) db.AutoSellJunk = checked; ApplySettings() end,
        })
        row1a:AddWidget(autoSellCheck, 0.5)
        manager:Register(autoSellCheck, "all")

        local autoRepairCheck = GUIFrame:CreateCheckbox(row1a, "Auto Repair Gear", {
            value = db.AutoRepair ~= false,
            callback = function(checked) db.AutoRepair = checked; ApplySettings() end,
        })
        row1a:AddWidget(autoRepairCheck, 0.5)
        manager:Register(autoRepairCheck, "all")
        card1:AddRow(row1a, Theme.rowHeight)

        local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
        local useGuildCheck = GUIFrame:CreateCheckbox(row1b, "Use Guild Funds for Repair", {
            value = db.UseGuildFunds ~= false,
            callback = function(checked) db.UseGuildFunds = checked; ApplySettings() end,
        })
        row1b:AddWidget(useGuildCheck, 0.5)
        manager:Register(useGuildCheck, "all")

        local repairReportCheck = GUIFrame:CreateCheckbox(row1b, "Announce Repair Cost", {
            value = db.RepairReport ~= false,
            callback = function(checked) db.RepairReport = checked; ApplySettings() end,
        })
        row1b:AddWidget(repairReportCheck, 0.5)
        manager:Register(repairReportCheck, "all")
        card1:AddRow(row1b, Theme.rowHeightLast, 0)

        yOffset = card1:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Merchant Pages (independent module — own cascade)
    ----------------------------------------------------------------
    local mpDB = KE.db and KE.db.profile.MerchantPages
    if mpDB then
        local mpManager = GUIFrame:CreateWidgetStateManager()

        local function GetMerchantPagesModule()
            if KitnEssentials then
                return KitnEssentials:GetModule("MerchantPages", true)
            end
            return nil
        end

        local MP = GetMerchantPagesModule()

        local function ApplyMPState(enabled)
            if not MP then return end
            mpDB.Enabled = enabled
            if enabled then KitnEssentials:EnableModule("MerchantPages")
            else KitnEssentials:DisableModule("MerchantPages") end
        end

        local function RefreshMPStates()
            mpManager:UpdateAll(mpDB.Enabled ~= false)
        end

        local cardMP = GUIFrame:CreateCard(scrollChild, "Merchant Pages", yOffset)
        cardMP:AddHeaderToggle(mpDB.Enabled ~= false, function(checked)
            mpDB.Enabled = checked
            ApplyMPState(checked)
            -- The MERCHANT_ITEMS_PER_PAGE global write, the created Blizzard-named
            -- MerchantItem<N> frames, and the hooksecurefunc hooks this module
            -- installs cannot be undone: turning the toggle off would otherwise
            -- leave the vendor window overridden by a module that reports itself
            -- off.
            if not checked then
                KE:CreateReloadPrompt("Turning off extended vendor pages requires a UI reload to restore Blizzard's window.")
            end
            KE:Print("Merchant Pages: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
        end)

        -- Pages lives in this card, not its own: one module, one card.
        if mpDB.Enabled ~= false then
            local rowPages = GUIFrame:CreateRow(cardMP.content, Theme.rowHeight)
            local mpPagesSlider = GUIFrame:CreateSlider(rowPages, "Pages", {
                min = 2, max = 4, step = 1,
                value = mpDB.Pages or 2,
                callback = function(val)
                    mpDB.Pages = val
                    -- The frame count is fixed at Setup and cannot change live --
                    -- same reload idiom the skinning pages use for a setting
                    -- that only takes effect on the next load.
                    KE:CreateReloadPrompt("Changing the vendor page count requires a UI reload to take effect.")
                end,
            })
            rowPages:AddWidget(mpPagesSlider, 1)
            mpManager:Register(mpPagesSlider, "all")
            cardMP:AddRow(rowPages, Theme.rowHeight)
        end

        local mpNoteHeight = 90
        local mpNoteRow = GUIFrame:CreateRow(cardMP.content, mpNoteHeight)
        local mpNoteText = GUIFrame:CreateText(mpNoteRow,
            KE:ColorTextByTheme("Note"),
            KE:ColorTextByTheme("-") ..
            " Widens the vendor window to show several pages at once. This " ..
            "changes Blizzard's own merchant frames, which can make some later " ..
            "tooltips stop working until you reload. Turn it off and reload if " ..
            "you see that. Skipped automatically if you run a dedicated vendor " ..
            "addon. Turning it off needs a reload.",
            mpNoteHeight, "hide")
        mpNoteRow:AddWidget(mpNoteText, 1)
        cardMP:AddRow(mpNoteRow, mpNoteHeight, 0)

        yOffset = cardMP:GetNextOffset()

        RefreshMPStates()
    end

    ----------------------------------------------------------------
    -- Auction House Filter (independent module — own cascade)
    ----------------------------------------------------------------
    local ahfDB = KE.db and KE.db.profile.AuctionHouseFilter
    if ahfDB then
        local ahfManager = GUIFrame:CreateWidgetStateManager()

        local function ApplyAHFState(enabled)
            ahfDB.Enabled = enabled
            if enabled then KitnEssentials:EnableModule("AuctionHouseFilter")
            else KitnEssentials:DisableModule("AuctionHouseFilter") end
        end

        local function RefreshAHFStates()
            ahfManager:UpdateAll(ahfDB.Enabled ~= false)
        end

        local cardAHF = GUIFrame:CreateCard(scrollChild, "Auction House Filter", yOffset)
        cardAHF:AddHeaderToggle(ahfDB.Enabled ~= false, function(checked)
            ApplyAHFState(checked)
            KE:Print("Auction House Filter: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
        end)
        yOffset = cardAHF:GetNextOffset()

        if ahfDB.Enabled ~= false then
            local rowAHF1 = GUIFrame:CreateRow(cardAHF.content, Theme.rowHeight)
            local ahCurExpCheck = GUIFrame:CreateCheckbox(rowAHF1, "Blizzard AH: Current Expansion Only", {
                value = ahfDB.AuctionHouse.CurrentExpansion ~= false,
                callback = function(checked) ahfDB.AuctionHouse.CurrentExpansion = checked end,
            })
            rowAHF1:AddWidget(ahCurExpCheck, 0.5)
            ahfManager:Register(ahCurExpCheck, "all")

            local ahFocusCheck = GUIFrame:CreateCheckbox(rowAHF1, "Blizzard AH: Focus Search Bar", {
                value = ahfDB.AuctionHouse.FocusSearchBar == true,
                callback = function(checked) ahfDB.AuctionHouse.FocusSearchBar = checked end,
            })
            rowAHF1:AddWidget(ahFocusCheck, 0.5)
            ahfManager:Register(ahFocusCheck, "all")
            cardAHF:AddRow(rowAHF1, Theme.rowHeight)

            local rowAHF2 = GUIFrame:CreateRow(cardAHF.content, Theme.rowHeightLast)
            local coCurExpCheck = GUIFrame:CreateCheckbox(rowAHF2, "Craft Orders: Current Expansion Only", {
                value = ahfDB.CraftOrders.CurrentExpansion ~= false,
                callback = function(checked) ahfDB.CraftOrders.CurrentExpansion = checked end,
            })
            rowAHF2:AddWidget(coCurExpCheck, 0.5)
            ahfManager:Register(coCurExpCheck, "all")

            local coFocusCheck = GUIFrame:CreateCheckbox(rowAHF2, "Craft Orders: Focus Search Bar", {
                value = ahfDB.CraftOrders.FocusSearchBar == true,
                callback = function(checked) ahfDB.CraftOrders.FocusSearchBar = checked end,
            })
            rowAHF2:AddWidget(coFocusCheck, 0.5)
            ahfManager:Register(coFocusCheck, "all")
            cardAHF:AddRow(rowAHF2, Theme.rowHeightLast, 0)

            yOffset = cardAHF:GetNextOffset()
        end

        RefreshAHFStates()
    end

    if gated then
        ----------------------------------------------------------------
        -- Collections & Bags
        ----------------------------------------------------------------
        local card2 = GUIFrame:CreateCard(scrollChild, "Collections & Bags", yOffset)
        manager:Register(card2, "all")

        local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
        local autoUnwrapCheck = GUIFrame:CreateCheckbox(row2, "Auto Unwrap Collections", {
            value = db.AutoUnwrapCollections == true,
            tooltip = "Automatically dismisses the new mount, pet or toy fanfare wrap and the Collections micro-button alert.",
            callback = function(checked) db.AutoUnwrapCollections = checked; ApplySettings() end,
        })
        row2:AddWidget(autoUnwrapCheck, 0.5)
        manager:Register(autoUnwrapCheck, "all")

        local trainAllCheck = GUIFrame:CreateCheckbox(row2, "Train All Button", {
            value = db.TrainAllButton == true,
            tooltip = "Adds a Train All button to the class trainer window that buys every skill you can afford, respecting your gold and free profession slots.",
            callback = function(checked) db.TrainAllButton = checked; ApplySettings() end,
        })
        row2:AddWidget(trainAllCheck, 0.5)
        manager:Register(trainAllCheck, "all")
        card2:AddRow(row2, Theme.rowHeightLast, 0)

        yOffset = card2:GetNextOffset()

    end


    manager:UpdateAll(true)
    return yOffset
end)

-- Three cards here are separate modules with their own switches, and this page
-- is the only route to them: Vantus Rune Withdrawer on General, Auction House
-- Filter and Merchant Pages on Vendors & Bags. Turning Automation off must not
-- take them away, so both of those tabs survive it.
GUIFrame:RegisterTabbedContent("Automation", function()
    local db = KE.db and KE.db.profile.Automation

    local GENERAL   = { id = "AutomationGeneral",   label = "General" }
    local INTERFACE = { id = "AutomationInterface", label = "Interface" }
    local QUESTS    = { id = "AutomationQuests",    label = "Quests & Social" }
    local VENDORS   = { id = "AutomationVendors",   label = "Vendors & Bags" }

    if not db or db.Enabled == false then
        return { GENERAL, VENDORS }
    end

    return { GENERAL, INTERFACE, QUESTS, VENDORS }
end, { headerBuilder = BuildHeader })
