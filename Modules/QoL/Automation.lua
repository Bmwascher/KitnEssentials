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
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local IsShiftKeyDown = IsShiftKeyDown
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
local StaticPopup_FindVisible = StaticPopup_FindVisible
local StaticPopup_Hide = StaticPopup_Hide
local GetLootRollItemLink = GetLootRollItemLink
local RollOnLoot = RollOnLoot
local ConfirmLootRoll = ConfirmLootRoll
local Item = Item
local Enum = Enum
local _G = _G
local string_format = string.format
local UnitClass = UnitClass
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local GetLootSpecialization = GetLootSpecialization
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local GetSpecializationInfoByID = GetSpecializationInfoByID
local AcceptResurrect = AcceptResurrect
local UnitAffectingCombat = UnitAffectingCombat
local UnitExists = UnitExists
local IsEncounterInProgress = IsEncounterInProgress
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetSpecializationRole = GetSpecializationRole

---------------------------------------------------------------------------------
-- Hide Helptips (runs at load time)
---------------------------------------------------------------------------------
C_CVar.RegisterCVar("hideHelptips", 1)
for index = 1, NUM_LE_FRAME_TUTORIALS do
    C_CVar.SetCVarBitfield("closedInfoFrames", index, true)
end
for index = 1, #Enum.FrameTutorialAccount do
    C_CVar.SetCVarBitfield("closedInfoFramesAccountWide", index, true)
end

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
        if not AU.db or not AU.db.Enabled then return end
        if KE:IsFullyRestricted() then return end
        if not AU.db.SkipCinematics then return end
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
        if not AU.db or not AU.db.Enabled then return end
        if AU.db.HideTalkingHead and frame then
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
            if not AU.db or not AU.db.Enabled then return end
            if not AU.db.HideEventToasts then return end
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
                if not AU.db or not AU.db.Enabled then return end
                if AU.db.HideZoneText then
                    self:Hide()
                end
            end)
        end
    end
end

-- Auto Sell Junk + Auto Repair --

local merchantFrame
local function SetupAutoSellRepair()
    if merchantFrame then return end
    merchantFrame = CreateFrame("Frame")
    merchantFrame:RegisterEvent("MERCHANT_SHOW")
    merchantFrame:SetScript("OnEvent", function()
        if not AU.db or not AU.db.Enabled then return end
        if KE:IsFullyRestricted() then return end
        if AU.db.AutoSellJunk and not IsShiftKeyDown() and C_MerchantFrame.GetNumJunkItems() > 0 then
            C_MerchantFrame.SellAllJunkItems()
        end
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
-- Selects the player's role from their assigned group role, falling back to
-- their current spec, then auto-accepts the LFD role-check popup. Each role
-- button is gated on :IsEnabled() because the popup disables roles the player
-- can't fill. When the role can't be resolved we leave the popup's pre-filled
-- selection (the LFG queue choice) untouched and simply accept it.

local function SetRoleCheckButton(button, checked)
    if button and button.checkButton and button.checkButton:IsEnabled() then
        button.checkButton:SetChecked(checked)
    end
end

local function SetupAutoRoleCheck()
    if not AU.db.AutoRoleCheck then return end
    if AU._lfdHooked then return end
    AU._lfdHooked = true
    if LFDRoleCheckPopup then
        LFDRoleCheckPopup:HookScript("OnShow", function()
            if not AU.db or not AU.db.Enabled then return end
            if KE:IsFullyRestricted() then return end
            if not AU.db.AutoRoleCheck then return end

            local role = UnitGroupRolesAssigned("player")
            if role == "NONE" then
                local specIndex = GetSpecialization()
                if specIndex then
                    role = GetSpecializationRole(specIndex)
                end
            end

            -- Only override the pre-filled selection when we resolved a real
            -- role; otherwise leave whatever the popup pre-checked in place.
            if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
                SetRoleCheckButton(LFDRoleCheckPopupRoleButtonTank, role == "TANK")
                SetRoleCheckButton(LFDRoleCheckPopupRoleButtonHealer, role == "HEALER")
                SetRoleCheckButton(LFDRoleCheckPopupRoleButtonDPS, role == "DAMAGER")
            end

            if LFDRoleCheckPopupAcceptButton then
                LFDRoleCheckPopupAcceptButton:Enable()
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
        if not AU.db or not AU.db.Enabled then return end
        if KE:IsFullyRestricted() then return end
        if not AU.db.AutoQueueConfirm then return end
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
            if not AU.db or not AU.db.Enabled then return end
            if not AU.db.AutoSlotKeystone then return end
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
        if not AU.db or not AU.db.Enabled then return end
        if not AU.db.AutoFillDelete then return end
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

-- Auto-Confirm Loot Roll Popup --
-- Hooks StaticPopup_Show to auto-click "Yes" on CONFIRM_LOOT_ROLL (the
-- "[item] will become Soulbound. Continue?" prompt that appears after
-- Need rolls on BoP items). Defers via C_Timer.After(0) so the popup
-- frame exists before we try to find/click it.

local autoConfirmHooked = false
local function SetupAutoConfirmLootRoll()
    if autoConfirmHooked then return end
    autoConfirmHooked = true
    hooksecurefunc("StaticPopup_Show", function(which)
        if not AU.db or not AU.db.Enabled then return end
        if not AU.db.AutoConfirmLootRoll then return end
        if which ~= "CONFIRM_LOOT_ROLL" then return end
        C_Timer.After(0, function()
            local popup = StaticPopup_FindVisible and StaticPopup_FindVisible("CONFIRM_LOOT_ROLL")
            if popup and popup.button1 and popup.button1:IsEnabled() then
                popup.button1:Click()
            end
        end)
    end)
end

-- Auto-Pass Housing Items --
-- Listens for START_LOOT_ROLL, filters by Enum.ItemClass.Housing, then calls
-- RollOnLoot + ConfirmLootRoll with the configured mode (PASS or NEED).
-- Item-load fallback handles the case where GetItemInfo's class fields aren't
-- cached yet on the first event. Adapted from Caboodle Utilities.lua "Roll
-- Away" feature, simplified — no instance-type gating, no loot-history hide.

local AUTO_ROLL_MAP = { PASS = 0, NEED = 1 }

local lootRollFrame
local function SetupAutoPassHousing()
    if lootRollFrame then return end
    lootRollFrame = CreateFrame("Frame")
    lootRollFrame:RegisterEvent("START_LOOT_ROLL")
    lootRollFrame:SetScript("OnEvent", function(self, event, ...)
        local rollID = ...
        if not AU.db or not AU.db.Enabled then return end
        if not AU.db.AutoPassHousing then return end

        local link = GetLootRollItemLink(rollID)
        if not link then return end

        local HOUSING_CLASS = (Enum.ItemClass and Enum.ItemClass.Housing) or 20
        local mode = AUTO_ROLL_MAP[AU.db.AutoPassHousingMode] or 0

        local function execute(classID)
            if classID ~= HOUSING_CLASS then return end
            local ok = pcall(RollOnLoot, rollID, mode)
            if not ok then return end
            if ConfirmLootRoll then pcall(ConfirmLootRoll, rollID, mode) end
            -- Dismiss the secondary CONFIRM_LOOT_ROLL popup defensively (matches
            -- Caboodle Utilities.lua:425-428). RollOnLoot+ConfirmLootRoll already
            -- went through programmatically; the popup is just stale UI to clear.
            -- This makes housing auto-roll work end-to-end without requiring the
            -- separate Auto-Confirm Loot Roll Popup toggle.
            C_Timer.After(0.1, function()
                if StaticPopup_FindVisible and StaticPopup_FindVisible("CONFIRM_LOOT_ROLL") then
                    StaticPopup_Hide("CONFIRM_LOOT_ROLL")
                end
            end)
        end

        local info = { C_Item.GetItemInfo(link) }
        if info[12] then
            execute(info[12])
            return
        end

        -- Item not yet cached — defer via ContinueOnItemLoad
        if Item and Item.CreateFromItemLink then
            local ok, item = pcall(Item.CreateFromItemLink, Item, link)
            if ok and item then
                item:ContinueOnItemLoad(function()
                    if not GetLootRollItemLink(rollID) then return end
                    local info2 = { C_Item.GetItemInfo(link) }
                    if info2[12] then execute(info2[12]) end
                end)
            end
        end
    end)
end

-- Confirm Bonus Roll --
-- Hooks BonusRollFrame's Roll button to show a confirmation dialog before
-- the bonus roll commits, preventing accidental clicks on the costly action.
-- The Pass-button confirm code is left in place but commented out — uncomment
-- the pass branch in HookBonusChild to re-enable it.

-- Returns "Loot Spec: |c<class>|T<icon>:0|t <name>|r" for the active loot spec.
-- Mirrors GreatVaultAlert:GetLootSpecInfo: GetLootSpecialization() returns 0
-- when the player is set to "use current spec," so fall back to the active
-- talent spec in that case.
local function BuildLootSpecLine()
    local specID = GetLootSpecialization and GetLootSpecialization()
    local name, icon
    if specID == 0 then
        local index = GetSpecialization and GetSpecialization()
        if index then
            local info = { GetSpecializationInfo(index) }
            name = info[2]
            icon = info[4]
        end
    elseif specID then
        local info = { GetSpecializationInfoByID(specID) }
        name = info[2]
        icon = info[4]
    end
    if not name then return "" end
    local _, class = UnitClass("player")
    local color = (RAID_CLASS_COLORS[class] and RAID_CLASS_COLORS[class].colorStr) or "ffffffff"
    return string_format("Loot Spec: |c%s|T%d:0|t %s|r", color, icon or 0, name)
end

StaticPopupDialogs["KE_BONUS_ROLL_CONFIRM"] = {
    text    = "Use your bonus roll?",  -- replaced per-click with spec line appended
    button1 = "Confirm",
    button2 = "Cancel",
    OnAccept = nil,  -- filled in per-click
    OnCancel = function() end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Pass-button dialog kept defined for symmetry with the commented-out hook
-- branch below. Activates only if the pass branch in HookBonusChild is uncommented.
StaticPopupDialogs["KE_BONUS_PASS_CONFIRM"] = {
    text    = "Pass on this bonus roll?",
    button1 = "Confirm",
    button2 = "Cancel",
    OnAccept = nil,
    OnCancel = function() end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

local bonusFrameHooked = false

local function HookBonusChild(child, isRoll)
    if not child or child._keBonusHooked then return end
    if not child:IsObjectType("Button") then return end
    local orig = child:GetScript("OnClick")
    if not orig then return end
    child._keBonusHooked = true

    -- Roll-button confirm (active).
    if isRoll then
        child:SetScript("OnClick", function(self, btn, down)
            if not AU.db or not AU.db.Enabled then orig(self, btn, down); return end
            if not AU.db.ConfirmBonusRoll then orig(self, btn, down); return end
            local specLine = BuildLootSpecLine()
            local dlg = StaticPopupDialogs["KE_BONUS_ROLL_CONFIRM"]
            dlg.text = (specLine ~= "" and ("Use your bonus roll?\n\n" .. specLine))
                or "Use your bonus roll?"
            dlg.OnAccept = function() orig(self, btn, down) end
            StaticPopup_Show("KE_BONUS_ROLL_CONFIRM")
        end)
    end

    -- Pass-button confirm — disabled by default. Uncomment the block below
    -- (and the matching KE_BONUS_PASS_CONFIRM dialog) to re-enable.
    --[[
    if not isRoll then
        child:SetScript("OnClick", function(self, btn, down)
            if not AU.db or not AU.db.Enabled then orig(self, btn, down); return end
            if not AU.db.ConfirmBonusRoll then orig(self, btn, down); return end
            StaticPopupDialogs["KE_BONUS_PASS_CONFIRM"].OnAccept =
                function() orig(self, btn, down) end
            StaticPopup_Show("KE_BONUS_PASS_CONFIRM")
        end)
    end
    --]]
end

local function HookBonusFrame()
    if bonusFrameHooked or not BonusRollFrame then return end
    local rollBtn = (BonusRollFrame.PromptFrame and BonusRollFrame.PromptFrame.RollButton)
                 or BonusRollFrame.RollButton
    local function Walk(frame)
        for i = 1, frame:GetNumChildren() do
            local child = select(i, frame:GetChildren())
            HookBonusChild(child, child == rollBtn)
            Walk(child)
        end
    end
    Walk(BonusRollFrame)
    bonusFrameHooked = true
end

local bonusInitFrame
local function SetupConfirmBonusRoll()
    if bonusInitFrame then return end
    if BonusRollFrame_StartBonusRoll then
        hooksecurefunc("BonusRollFrame_StartBonusRoll", HookBonusFrame)
    end
    bonusInitFrame = CreateFrame("Frame")
    bonusInitFrame:RegisterEvent("BONUS_ROLL_STARTED")
    bonusInitFrame:SetScript("OnEvent", function(self, event)
        HookBonusFrame()
        self:UnregisterAllEvents()
    end)
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

-- Targeted weekly quests handled by their own per-quest auto-handler. The
-- generic SetupAutoQuests path yields to these on GOSSIP_SHOW (via
-- ShouldSkipForVoidcores) so its "select first available quest" branch
-- doesn't grab the wrong one and skip the priority quest's dedicated logic.
local VOIDCORES_GOLD_QUEST_ID = 95279  -- Nebulous Voidcores: Gold (Decimus weekly)

local function ShouldSkipForVoidcores(quests)
    if not AU.db.AutoVoidcoresGold then return false end
    if C_QuestLog.IsQuestFlaggedCompleted(VOIDCORES_GOLD_QUEST_ID) then return false end
    if not quests then return false end
    for _, quest in ipairs(quests) do
        if quest.questID == VOIDCORES_GOLD_QUEST_ID then return true end
    end
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
        if not AU.db or not AU.db.Enabled then return end
        if KE:IsFullyRestricted() then return end
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
                -- Yield to the voidcores handler so its priority pick isn't
                -- overridden by the generic "select first available" path.
                if ShouldSkipForVoidcores(availableQuests) then return end
                if #availableQuests > 0 then
                    C_GossipInfo.SelectAvailableQuest(availableQuests[1].questID)
                end
            end
        end
    end)
end

-- Auto Voidcores: Gold (Decimus Weekly) --
-- Dedicated end-to-end handler for the single weekly quest "Nebulous
-- Voidcores: Gold." Walks the gossip → accept → complete chain without
-- requiring the generic auto-accept/turn-in toggles to be on. Respects
-- the same QuestModifier as the generic handler.
local voidcoresFrame
local function SetupAutoVoidcoresGold()
    if not AU.db.AutoVoidcoresGold then return end
    if voidcoresFrame then return end
    voidcoresFrame = CreateFrame("Frame")
    voidcoresFrame:RegisterEvent("GOSSIP_SHOW")
    voidcoresFrame:RegisterEvent("QUEST_DETAIL")
    voidcoresFrame:RegisterEvent("QUEST_PROGRESS")
    voidcoresFrame:SetScript("OnEvent", function(_, event)
        if not AU.db or not AU.db.Enabled then return end
        if KE:IsFullyRestricted() then return end
        if not AU.db.AutoVoidcoresGold then return end
        if IsQuestModifierHeld() then return end
        if C_QuestLog.IsQuestFlaggedCompleted(VOIDCORES_GOLD_QUEST_ID) then return end

        if event == "GOSSIP_SHOW" then
            -- Active turn-in path: quest already accepted, now ready to hand in
            local activeQuests = C_GossipInfo.GetActiveQuests()
            if activeQuests then
                for _, quest in ipairs(activeQuests) do
                    if quest.questID == VOIDCORES_GOLD_QUEST_ID and quest.isComplete then
                        C_GossipInfo.SelectActiveQuest(VOIDCORES_GOLD_QUEST_ID)
                        return
                    end
                end
            end
            -- Available accept path: quest offered, not yet picked up
            local availableQuests = C_GossipInfo.GetAvailableQuests()
            if availableQuests then
                for _, quest in ipairs(availableQuests) do
                    if quest.questID == VOIDCORES_GOLD_QUEST_ID then
                        C_GossipInfo.SelectAvailableQuest(VOIDCORES_GOLD_QUEST_ID)
                        return
                    end
                end
            end
        elseif event == "QUEST_DETAIL" then
            if GetQuestID() == VOIDCORES_GOLD_QUEST_ID then
                AcceptQuest()
            end
        elseif event == "QUEST_PROGRESS" then
            if GetQuestID() == VOIDCORES_GOLD_QUEST_ID and IsQuestCompletable() then
                CompleteQuest()
            end
        end
    end)
end

-- Hidden Quest Cleanup --
-- Unwatches quests flagged as hidden (account-wide / auto-tracked entries that
-- clutter the objective tracker). Runs on entering the world and immediately
-- when the toggle is flipped on. Silent — no chat output.

local function RunHiddenQuestCleanup()
    if not AU.db or not AU.db.Enabled then return end
    if not AU.db.AutoUnwatchHidden then return end
    if KE:IsFullyRestricted() then return end

    local numShownEntries, numQuests = C_QuestLog.GetNumQuestLogEntries()
    if numShownEntries <= numQuests then return end

    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHidden and not info.isHeader then
            C_QuestLog.RemoveQuestWatch(info.questID)
        end
    end
end

local hiddenQuestFrame
local function SetupHiddenQuestCleanup()
    if hiddenQuestFrame then
        RunHiddenQuestCleanup()
        return
    end
    hiddenQuestFrame = CreateFrame("Frame")
    hiddenQuestFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hiddenQuestFrame:SetScript("OnEvent", RunHiddenQuestCleanup)
    RunHiddenQuestCleanup()
end

-- Auto Decline Duels / Pet Battles --

local duelFrame
local function SetupAutoDeclineDuels()
    if duelFrame then return end
    duelFrame = CreateFrame("Frame")
    duelFrame:RegisterEvent("DUEL_REQUESTED")
    duelFrame:SetScript("OnEvent", function()
        if not AU.db or not AU.db.Enabled then return end
        if AU.db.AutoDeclineDuels then
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
        if not AU.db or not AU.db.Enabled then return end
        if AU.db.AutoDeclinePetBattles then
            C_PetBattles.CancelPVPDuel()
        end
    end)
end

---------------------------------------------------------------------------------
-- Auto Accept Resurrection (out-of-combat only)
--
-- Mirrors the ElvUI_WindTools/Misc/Automation.lua pattern: explicit
-- battle-res detection via boss1-in-combat + inviter-in-combat, rather than
-- relying solely on IsEncounterInProgress (which has corner cases on
-- multi-phase encounters). Auto-accept fires ONLY for peaceful, fully
-- out-of-combat resurrections.
--
-- Refuses to auto-accept if ANY of:
--   * Player is in combat (UnitAffectingCombat)
--   * Combat lockdown is active (InCombatLockdown)
--   * Encounter API reports an active encounter (IsEncounterInProgress)
--   * boss1 unit exists AND is in combat (raid-encounter active even if
--     encounter API is silent, e.g. M+ pulls without ENCOUNTER_START)
--   * The inviter (sender) is themselves in combat — the caster is
--     mid-fight, this is almost certainly a battle-res
---------------------------------------------------------------------------------
local resFrame = nil

local function HandleResurrectRequest(_, _, inviterName)
    if not AU.db or not AU.db.Enabled then return end
    if not AU.db.AutoAcceptRes then return end
    if UnitAffectingCombat("player") then return end
    if InCombatLockdown() then return end
    if IsEncounterInProgress() then return end

    -- boss1 visible + in combat = encounter is live regardless of API state.
    if UnitExists("boss1") and UnitAffectingCombat("boss1") then return end

    -- Inviter-in-combat = mid-fight battle-res. inviterName is a name string
    -- (e.g. "Bobthepriest" or "Bobthepriest-Realm"), not a unit token, so
    -- pcall-guard the lookup — if the name doesn't resolve to a unit, fall
    -- through and let the other guards decide.
    if inviterName and inviterName ~= "" then
        local ok, inCombat = pcall(UnitAffectingCombat, inviterName)
        if ok and inCombat then return end
    end

    AcceptResurrect()
    -- Hide both popup variants: RESURRECT_NO_TIMER (Soulstone-style) and
    -- RESURRECT (priest/druid Resurrection with countdown). AcceptResurrect
    -- usually dismisses the active one, but Blizzard sometimes leaves the
    -- other queued popup visible.
    StaticPopup_Hide("RESURRECT_NO_TIMER")
    StaticPopup_Hide("RESURRECT")
end

local function SetupAutoAcceptRes()
    if not resFrame then
        resFrame = CreateFrame("Frame")
        resFrame:SetScript("OnEvent", HandleResurrectRequest)
    end
    if AU.db.AutoAcceptRes then
        resFrame:RegisterEvent("RESURRECT_REQUEST")
    else
        resFrame:UnregisterAllEvents()
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function AU:CVAR_UPDATE(_, cvarName)
    local matched = false
    for _, def in ipairs(self.CVAR_DEFS) do
        if def.key == cvarName then
            local current = C_CVar.GetCVar(cvarName)
            self.db[cvarName] = FromCVarValue(current, def.type)
            matched = true
        end
    end
    for _, def in ipairs(self.CVAR_SLIDER_DEFS) do
        if def.key == cvarName then
            local current = C_CVar.GetCVar(cvarName)
            self.db[cvarName] = tonumber(current) or 0
            matched = true
        end
    end
    -- 2026-06-12 leak fix: this refresh used to be UNCONDITIONAL — every
    -- CVAR_UPDATE delivery (any addon touching any event-named CVar, GUI
    -- open or closed) forced a full page rebuild, orphaning a page of cards
    -- each time. RefreshContent now refuses to run hidden as well, but keep
    -- this caller honest: only refresh for CVars this module displays, only
    -- when the GUI is shown, and collapse bursts (ApplyCVars writes every
    -- managed CVar back-to-back) into a single deferred rebuild.
    if not matched or self._suppressCVarUpdate then return end
    if not (KE.GUIFrame and KE.GUIFrame:IsShown()) then return end
    if self._cvarRefreshQueued then return end
    self._cvarRefreshQueued = true
    C_Timer.After(0.1, function()
        self._cvarRefreshQueued = false
        if KE.GUIFrame and KE.GUIFrame:IsShown() then
            KE.GUIFrame:RefreshContent()
        end
    end)
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
    SetupAutoConfirmLootRoll()
    SetupAutoPassHousing()
    SetupConfirmBonusRoll()
    SetupAutoQuests()
    SetupAutoVoidcoresGold()
    SetupHiddenQuestCleanup()
    SetupAutoDeclineDuels()
    SetupAutoDeclinePetBattles()
    SetupAutoAcceptRes()
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
