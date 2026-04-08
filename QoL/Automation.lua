-- ╔══════════════════════════════════════════════════════════╗
-- ║  Automation.lua                                          ║
-- ║  Module: Automation                                      ║
-- ║  Purpose: Auto-repair, auto-sell, auto-confirm queue,    ║
-- ║           auto-slot keystone, skip cinematics, hide      ║
-- ║           event toasts/zone text, and more.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class Automation: AceModule, AceEvent-3.0, AceHook-3.0
local AU = KitnEssentials:NewModule("Automation", "AceEvent-3.0", "AceHook-3.0")

local pcall = pcall
local ipairs = ipairs
local select = select
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local RepairAllItems = RepairAllItems
local CanMerchantRepair = CanMerchantRepair
local GetRepairAllCost = GetRepairAllCost
local CanGuildBankRepair = CanGuildBankRepair
local GetMoney = GetMoney
local GetGuildBankWithdrawMoney = GetGuildBankWithdrawMoney
local CinematicFrame_CancelCinematic = CinematicFrame_CancelCinematic
local GameMovieFinished = GameMovieFinished
local C_Container = C_Container
local C_Item = C_Item
local C_CVar = C_CVar
local C_Timer = C_Timer
local StaticPopupDialogs = StaticPopupDialogs
local _G = _G

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
AU.CVAR_DEFS = {
    -- Floating Combat Text
    {
        key = "enableFloatingCombatText",
        label = "Floating Combat Text: |cFF8080FFPlayer|r",
        desc = "Floating |cFFFF4040Damage|r / |cFF40FF40Healing|r received.",
        type = "boolean",
    },
    {
        key = "floatingCombatTextCombatDamage_v2",
        label = "Floating Combat Text: |cFFFF4040Damage|r",
        desc = "Displays Floating Combat Damage.",
        type = "boolean",
    },
    {
        key = "floatingCombatTextCombatHealing_v2",
        label = "Floating Combat Text: |cFF40FF40Healing|r",
        desc = "Displays Floating Combat Healing.",
        type = "boolean",
    },
    {
        key = "floatingCombatTextReactives_v2",
        label = "Floating Combat Text: |cFFFFCC00Reactives|r",
        desc = "Displays Reactive Ability Notifications.",
        type = "boolean",
    },
    -- Character Visibility
    {
        key = "findYourselfModeOutline",
        label = "Find Yourself Anywhere: |cFF8080FFOutline|r",
        desc = "Adds Outline to Your Player Character.",
        type = "boolean",
    },
    {
        key = "occludedSilhouettePlayer",
        label = "Obstruction Silhouette",
        desc = "Display a Silhouette of your Character when Obstructed.",
        type = "boolean",
    },
    -- Effects
    {
        key = "ffxDeath",
        label = "Death Effects",
        desc = "Displays Death Overlay / Desaturation.",
        type = "boolean",
    },
    {
        key = "ffxGlow",
        label = "Fullscreen Glow",
        desc = "Displays Fullscreen Glow Effect. Can be a small FPS improvement.",
        type = "boolean",
    },
    {
        key = "ResampleAlwaysSharpen",
        label = "Sharpen Textures",
        desc = "Sharpens Up Textures.",
        type = "boolean",
    },
    -- Tooltips
    {
        key = "alwaysCompareItems",
        label = "Always Compare Items",
        desc = "Always show item comparison tooltips. Disable to require Shift.",
        type = "boolean",
    },
    -- Nameplates
    {
        key = "nameplateShowOnlyNameForFriendlyPlayerUnits",
        label = "Show Only Friendly Names",
        type = "boolean",
    },
    {
        key = "nameplateUseClassColorForFriendlyPlayerUnitNames",
        label = "Class Colored Friendly Names",
        type = "boolean",
    },
}

AU.CVAR_SLIDER_DEFS = {
    {
        key = "SpellQueueWindow",
        label = "Spell Queue Window",
        type = "number",
        min = 0, max = 400, step = 1,
    },
    {
        key = "RAIDWaterDetail",
        label = "Raid: Water Detail",
        type = "number",
        min = 0, max = 3, step = 1,
    },
    {
        key = "RAIDweatherDensity",
        label = "Raid: Weather Density",
        type = "number",
        min = 0, max = 3, step = 1,
    },
    {
        key = "autoLootRate",
        label = "Auto Loot: Rate",
        type = "number",
        min = 0, max = 150, step = 1,
    },
}

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
AU._suppressCVarUpdate = false

---------------------------------------------------------------------------------
-- CVar Helpers
---------------------------------------------------------------------------------
local function ToCVarValue(value, cvarType)
    if cvarType == "boolean" then
        return value and 1 or 0
    end
    return value
end

local function FromCVarValue(value, cvarType)
    if cvarType == "boolean" then
        return value == "1"
    end
    return value
end

function AU:ApplyCVars()
    if not self.db.CVarsEnabled then return end
    -- Boolean CVars
    for _, def in ipairs(self.CVAR_DEFS) do
        local key = def.key
        local dbValue = self.db[key]
        local currentCVar = C_CVar.GetCVar(key)
        local currentValue = FromCVarValue(currentCVar, def.type)
        if dbValue == nil then
            self.db[key] = currentValue
        elseif dbValue ~= currentValue then
            C_CVar.SetCVar(key, ToCVarValue(dbValue, def.type))
        end
    end
    -- Slider CVars
    for _, def in ipairs(self.CVAR_SLIDER_DEFS) do
        local key = def.key
        local dbValue = self.db[key]
        local currentCVar = C_CVar.GetCVar(key)
        local currentValue = FromCVarValue(currentCVar, def.type)
        if dbValue == nil then
            self.db[key] = tonumber(currentValue) or 0
        elseif tostring(dbValue) ~= tostring(currentValue) then
            C_CVar.SetCVar(key, tostring(dbValue))
        end
    end
end

function AU:SyncFromCVars()
    for _, def in ipairs(self.CVAR_DEFS) do
        local current = C_CVar.GetCVar(def.key)
        self.db[def.key] = FromCVarValue(current, def.type)
    end
    for _, def in ipairs(self.CVAR_SLIDER_DEFS) do
        local current = C_CVar.GetCVar(def.key)
        self.db[def.key] = tonumber(current) or 0
    end
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function AU:UpdateDB()
    self.db = KE.db.profile.Automation
end

function AU:OnInitialize()
    self:UpdateDB()
    self:SyncFromCVars()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------

-- Skip Cinematics --

local cinematicFrame
local function SetupSkipCinematics()
    if not AU.db.SkipCinematics then return end
    if cinematicFrame then return end
    cinematicFrame = CreateFrame("Frame")
    cinematicFrame:RegisterEvent("CINEMATIC_START")
    cinematicFrame:RegisterEvent("PLAY_MOVIE")
    cinematicFrame:SetScript("OnEvent", function(_, event)
        if event == "CINEMATIC_START" then
            CinematicFrame_CancelCinematic()
        elseif event == "PLAY_MOVIE" then
            pcall(GameMovieFinished)
        end
    end)
end

-- Hide Talking Head --

function AU:SetupTalkingHeadHider()
    if self._talkingHeadHooked then return end
    local function HideTalkingHead(frame)
        if AU.db and AU.db.HideTalkingHead and frame then
            frame:Hide()
        end
    end
    if _G.TalkingHeadFrame then
        self:SecureHook(_G.TalkingHeadFrame, "PlayCurrent", HideTalkingHead)
        self:SecureHook(_G.TalkingHeadFrame, "Reset", HideTalkingHead)
    else
        self:SecureHook("TalkingHead_LoadUI", function()
            if _G.TalkingHeadFrame then
                self:SecureHook(_G.TalkingHeadFrame, "PlayCurrent", HideTalkingHead)
                self:SecureHook(_G.TalkingHeadFrame, "Reset", HideTalkingHead)
            end
        end)
    end
    self._talkingHeadHooked = true
end

-- Hide Event Toasts --

local function SetupHideEventToasts()
    if AU._eventToastsHooked then return end
    AU._eventToastsHooked = true
    if not EventToastManagerFrame then return end
    if EventToastManagerFrame.DisplayToast then
        hooksecurefunc(EventToastManagerFrame, "DisplayToast", function(self)
            if not AU.db or not AU.db.HideEventToasts then return end
            C_Timer.After(0.05, function()
                if self:IsShown() then
                    self:CloseActiveToasts()
                end
            end)
        end)
    end
end

-- Hide Zone Text --

local function SetupHideZoneText()
    if AU._zoneTextHooked then return end
    AU._zoneTextHooked = true
    local frames = { ZoneTextFrame, SubZoneTextFrame }
    for _, frame in ipairs(frames) do
        if frame then
            hooksecurefunc(frame, "Show", function(self)
                if AU.db and AU.db.HideZoneText then
                    self:Hide()
                end
            end)
        end
    end
end

-- Auto Sell Junk + Auto Repair --

local function SellJunkItems()
    if not AU.db.AutoSellJunk then return end
    for bagID = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bagID) do
            local itemLink = C_Container.GetContainerItemLink(bagID, slot)
            if itemLink then
                local itemQuality = select(3, C_Item.GetItemInfo(itemLink))
                local itemSellPrice = select(11, C_Item.GetItemInfo(itemLink))
                if itemQuality == 0 and itemSellPrice and itemSellPrice > 0 then
                    C_Container.UseContainerItem(bagID, slot)
                end
            end
        end
    end
end

local merchantFrame
local function SetupAutoSellRepair()
    if merchantFrame then return end
    merchantFrame = CreateFrame("Frame")
    merchantFrame:RegisterEvent("MERCHANT_SHOW")
    merchantFrame:SetScript("OnEvent", function()
        if AU.db.AutoSellJunk then SellJunkItems() end
        if AU.db.AutoRepair and CanMerchantRepair() then
            local repairCost, canRepair = GetRepairAllCost()
            if repairCost and canRepair and repairCost > 0 then
                if AU.db.UseGuildFunds and CanGuildBankRepair() then
                    local guildBankMoney = GetGuildBankWithdrawMoney()
                    if guildBankMoney >= repairCost then
                        RepairAllItems(true)
                        return
                    end
                end
                if GetMoney() >= repairCost then
                    RepairAllItems(false)
                end
            end
        end
    end)
end

-- Auto Role Check --

local function SetupAutoRoleCheck()
    if not AU.db.AutoRoleCheck then return end
    if AU._lfdHooked then return end
    AU._lfdHooked = true
    if LFDRoleCheckPopup then
        LFDRoleCheckPopup:HookScript("OnShow", function()
            if LFDRoleCheckPopupAcceptButton then
                LFDRoleCheckPopupAcceptButton:Click()
            end
        end)
    end
end

-- Auto Queue Confirm --

local function SetupAutoQueueConfirm()
    if AU._lfgHooked then return end
    AU._lfgHooked = true
    local dialog = LFGListApplicationDialog
    if not dialog then return end
    dialog:HookScript("OnShow", function(dlg)
        if not AU.db or not AU.db.AutoQueueConfirm then return end
        if IsControlKeyDown() then return end
        local confirmBtn = dlg.SignUpButton
        if confirmBtn and confirmBtn:IsEnabled() then
            confirmBtn:Click()
        end
    end)
end

-- Auto Slot Keystone --

local function SetupAutoSlotKeystone()
    if AU._keystoneHooked then return end
    AU._keystoneHooked = true

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(self, event, loaded)
        if loaded ~= "Blizzard_ChallengesUI" then return end
        self:UnregisterEvent("ADDON_LOADED")

        local keystoneUI = ChallengesKeystoneFrame
        if not keystoneUI then return end

        keystoneUI:HookScript("OnShow", function()
            if not AU.db or not AU.db.AutoSlotKeystone then return end
            if C_ChallengeMode.HasSlottedKeystone() then return end

            local reagentType = Enum.ItemClass.Reagent
            local keystoneType = Enum.ItemReagentSubclass.Keystone

            for bag = 0, (NUM_BAG_FRAMES or 4) do
                local slots = C_Container.GetContainerNumSlots(bag)
                for slot = 1, slots do
                    local itemID = C_Container.GetContainerItemID(bag, slot)
                    if itemID then
                        local _, _, _, _, _, _, _, _, _, _, _, itemClass, itemSub = C_Item.GetItemInfo(itemID)
                        if itemClass == reagentType and itemSub == keystoneType then
                            C_Container.PickupContainerItem(bag, slot)
                            if C_Cursor.GetCursorItem() then
                                C_ChallengeMode.SlotKeystone()
                                return
                            end
                        end
                    end
                end
            end
        end)
    end)
end

-- Auto Fill DELETE --

local function SetupAutoFillDelete()
    if not AU.db.AutoFillDelete then return end
    if AU._deleteHooked then return end
    AU._deleteHooked = true
    hooksecurefunc(StaticPopupDialogs["DELETE_GOOD_ITEM"], "OnShow", function(self)
        if self.EditBox then
            self.EditBox:SetText("DELETE")
        end
    end)
end

-- Auto Loot --

local function ApplyAutoLoot()
    if not AU.db.AutoLoot then return end
    C_CVar.SetCVar("autoLootDefault", AU.db.AutoLoot and "1" or "0")
end

-- Quest Automation --

local function IsQuestModifierHeld()
    local mod = AU.db.QuestModifier
    if not mod or mod == "" or mod == "NONE" then return false end
    if mod == "CTRL" then return IsControlKeyDown() end
    if mod == "ALT" then return IsAltKeyDown() end
    if mod == "SHIFT" then return IsShiftKeyDown() end
    return false
end

local questFrame
local function SetupAutoQuests()
    if not AU.db.AutoAcceptQuests and not AU.db.AutoTurnInQuests then return end
    if questFrame then return end
    questFrame = CreateFrame("Frame")
    questFrame:RegisterEvent("QUEST_DETAIL")
    questFrame:RegisterEvent("QUEST_PROGRESS")
    questFrame:RegisterEvent("QUEST_COMPLETE")
    questFrame:RegisterEvent("QUEST_GREETING")
    questFrame:RegisterEvent("GOSSIP_SHOW")
    questFrame:SetScript("OnEvent", function(_, event)
        if IsQuestModifierHeld() then return end

        if event == "QUEST_DETAIL" then
            if AU.db.AutoAcceptQuests then
                AcceptQuest()
            end
        elseif event == "QUEST_PROGRESS" then
            if AU.db.AutoTurnInQuests and IsQuestCompletable() then
                CompleteQuest()
            end
        elseif event == "QUEST_COMPLETE" then
            if AU.db.AutoTurnInQuests then
                local numChoices = GetNumQuestChoices()
                if numChoices <= 1 then
                    GetQuestReward(numChoices)
                end
            end
        elseif event == "QUEST_GREETING" then
            if AU.db.AutoTurnInQuests then
                for i = 1, GetNumActiveQuests() do
                    local _, isComplete = GetActiveTitle(i)
                    if isComplete then
                        SelectActiveQuest(i)
                        return
                    end
                end
            end
            if AU.db.AutoAcceptQuests then
                if GetNumAvailableQuests() > 0 then
                    SelectAvailableQuest(1)
                end
            end
        elseif event == "GOSSIP_SHOW" then
            if AU.db.AutoTurnInQuests then
                local activeQuests = C_GossipInfo.GetActiveQuests()
                for _, quest in ipairs(activeQuests) do
                    if quest.isComplete then
                        C_GossipInfo.SelectActiveQuest(quest.questID)
                        return
                    end
                end
            end
            if AU.db.AutoAcceptQuests then
                local availableQuests = C_GossipInfo.GetAvailableQuests()
                if #availableQuests > 0 then
                    C_GossipInfo.SelectAvailableQuest(availableQuests[1].questID)
                end
            end
        end
    end)
end

-- Auto Decline Duels / Pet Battles --

local duelFrame
local function SetupAutoDeclineDuels()
    if duelFrame then return end
    duelFrame = CreateFrame("Frame")
    duelFrame:RegisterEvent("DUEL_REQUESTED")
    duelFrame:SetScript("OnEvent", function()
        if AU.db and AU.db.AutoDeclineDuels then
            CancelDuel()
            StaticPopup_Hide("DUEL_REQUESTED")
        end
    end)
end

local petDuelFrame
local function SetupAutoDeclinePetBattles()
    if petDuelFrame then return end
    petDuelFrame = CreateFrame("Frame")
    petDuelFrame:RegisterEvent("PET_BATTLE_PVP_DUEL_REQUESTED")
    petDuelFrame:SetScript("OnEvent", function()
        if AU.db and AU.db.AutoDeclinePetBattles then
            C_PetBattles.CancelPVPDuel()
        end
    end)
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function AU:CVAR_UPDATE(_, cvarName)
    for _, def in ipairs(self.CVAR_DEFS) do
        if def.key == cvarName then
            local current = C_CVar.GetCVar(cvarName)
            self.db[cvarName] = FromCVarValue(current, def.type)
        end
    end
    for _, def in ipairs(self.CVAR_SLIDER_DEFS) do
        if def.key == cvarName then
            local current = C_CVar.GetCVar(cvarName)
            self.db[cvarName] = tonumber(current) or 0
        end
    end
    if KE.GUIFrame and not self._suppressCVarUpdate then
        KE.GUIFrame:RefreshContent()
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function AU:ApplySettings()
    if not self.db.Enabled then return end
    SetupSkipCinematics()
    self:SetupTalkingHeadHider()
    SetupHideEventToasts()
    SetupHideZoneText()
    SetupAutoSellRepair()
    SetupAutoRoleCheck()
    SetupAutoQueueConfirm()
    SetupAutoSlotKeystone()
    SetupAutoFillDelete()
    ApplyAutoLoot()
    SetupAutoQuests()
    SetupAutoDeclineDuels()
    SetupAutoDeclinePetBattles()
    self:ApplyCVars()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function AU:OnEnable()
    if not self.db.Enabled then return end
    self:RegisterEvent("CVAR_UPDATE")
    C_Timer.After(1.0, function()
        self:ApplySettings()
    end)
end

function AU:OnDisable()
    self:UnregisterAllEvents()
end
