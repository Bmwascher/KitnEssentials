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
local C_CurrencyInfo = C_CurrencyInfo
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
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local GetSpecializationInfoByID = GetSpecializationInfoByID
local AcceptResurrect = AcceptResurrect
local UnitAffectingCombat = UnitAffectingCombat
local UnitExists = UnitExists
local IsEncounterInProgress = IsEncounterInProgress
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetSpecializationRole = GetSpecializationRole

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

-- Hide Helptips --
-- Suppresses Blizzard's tutorial / "Did you know" popups. Fully
-- live-toggleable and reversible: HelpTip pool hides (acknowledging each
-- tip's cvarBitfield so it stays dismissed), "i" help-plate buttons
-- matched by mixin-method fingerprint and alpha-hidden (restored on
-- disable), HelpPlate tooltip hooks, and the hideHelptips/showTutorials
-- CVars. Hooks install once, only when the feature is first enabled.
--
-- Master-independent: this suppression must apply even while the
-- Automation master switch is off, so it is defined above OnInitialize
-- and called from OnInitialize directly, ahead of the module ever being
-- enabled.

local tutorialsCoreHooked = false
local tutorialsTooltipHooked = false
local tutorialsWeSetCVar = false
local tutorialsSwept = false
local tutorialsFingerprint
local tutorialsHidden = setmetatable({}, { __mode = "k" })

local function TutorialsEnabled()
    return AU.db and AU.db.HideHelptips
end

local function GetTutorialFingerprint()
    if not tutorialsFingerprint and MainHelpPlateButtonMixin then
        tutorialsFingerprint = MainHelpPlateButtonMixin.ShowTooltip
    end
    return tutorialsFingerprint
end

local function TutorialHideButton(btn)
    btn:SetAlpha(0)
    -- Recorded BETWEEN the two: after the change that actually needs undoing,
    -- and before the protected EnableMouse, which can fail on a frame this
    -- addon does not own. Either end records the wrong set -- afterwards
    -- leaves a transparent button restore cannot find, before leaves an
    -- untouched button restore would alter.
    tutorialsHidden[btn] = true
    btn:EnableMouse(false)
end

-- Hoisted out of the pcall: one function, no per-call closure alloc
local function DoHideOpenTips()
    for tip in HelpTip.framePool:EnumerateActive() do
        if tip:IsShown() then
            local info = tip.info
            if info and info.cvarBitfield and info.bitfieldFlag then
                SetCVarBitfield(info.cvarBitfield, info.bitfieldFlag, true)
            end
            tip:Hide()
        end
    end
end
local function HideOpenTips()
    if not (HelpTip and HelpTip.framePool and HelpTip.framePool.EnumerateActive) then return end
    pcall(DoHideOpenTips)
end

-- Queued, not recursive: the old vararg recursion held every level's siblings on
-- the Lua stack, and a talent tree or map canvas overflowed it and killed the
-- client. The depth cap is only about cost; a "?" is panel chrome, never buried
-- deep.
local TUTORIAL_MAX_DEPTH = 4

local function TutorialHideButtonsUnder(root)
    if not root then return end
    local fp = GetTutorialFingerprint()
    if not fp then return end

    -- Node/depth pairs drained from the front; tail starts past the two already
    -- queued.
    local queue, head, tail = { root, 1 }, 1, 3

    while head < tail do
        local node, depth = queue[head], queue[head + 1]
        queue[head], queue[head + 1] = nil, nil
        head = head + 2

        -- Hostile input by definition: Blizzard can restrict any node here.
        if node and not (node.IsForbidden and node:IsForbidden()) then
            if node.ShowTooltip == fp then TutorialHideButton(node) end

            if depth < TUTORIAL_MAX_DEPTH and node.GetChildren then
                local ok, kids = pcall(function() return { node:GetChildren() } end)
                if ok and kids then
                    for i = 1, #kids do
                        queue[tail] = kids[i]
                        queue[tail + 1] = depth + 1
                        tail = tail + 2
                    end
                end
            end
        end
    end
end

-- One-time full walk to catch panels already open at enable time.
--
-- This visits EVERY frame the client knows about, not just KE's or Blizzard's,
-- so its cost scales with the player's whole addon set -- far enough to trip
-- the script watchdog in a single pass. Sliced across frames instead: the
-- watchdog measures one uninterrupted run, and nothing here is urgent enough
-- to justify one. The guard keeps a second ApplySettings from starting a
-- parallel walk over the same list.
-- Two bounds per slice. The count keeps one tick's work finite even where
-- inspection is nearly free; the millisecond budget is the one that protects
-- the frame rate -- node cost varies by orders of magnitude across the list
-- (a forbidden stretch throws on every read), so a fixed count alone can
-- still hold a render frame past 100ms.
local TUTORIAL_SWEEP_SLICE = 500
local TUTORIAL_SWEEP_BUDGET_MS = 1.5
local tutorialSweeping = false
local tutorialSweepGen = 0

-- Inspect one frame. Both steps can throw and neither is this addon's frame:
-- a forbidden frame throws on the fingerprint read, object security is a
-- secret aspect in 12.1 so the access check's own answer can be a secret
-- boolean, and hiding calls a protected function. Callers run this under
-- pcall per frame so one bad node costs one node. The fingerprint read must
-- come first: the access check is a per-call security query expensive enough
-- that asking it of every frame in the client holds login at single-digit
-- FPS for seconds -- only a matched button may pay for it.
local function TutorialInspectFrame(frame, fp)
    if frame.ShowTooltip ~= fp then return end
    if frame.CanBeAccessedInContext and not frame:CanBeAccessedInContext() then return end
    TutorialHideButton(frame)
end

-- Returns the first frame of the next slice, or nil at the end of the list.
local function TutorialSweepSlice(frame, fp)
    local enumerate = EnumerateFrames
    local clock = debugprofilestop
    local deadline = clock() + TUTORIAL_SWEEP_BUDGET_MS
    local visited = 0
    while frame and visited < TUTORIAL_SWEEP_SLICE and clock() < deadline do
        pcall(TutorialInspectFrame, frame, fp)
        frame = enumerate(frame)
        visited = visited + 1
    end
    return frame
end

-- An abandoned walk is NOT a completed one: clearing the done flag too is what
-- makes "the next apply retries" true rather than a comforting comment.
local function TutorialSweepAbort()
    tutorialSweeping = false
    tutorialsSwept = false
end

local function TutorialSweepStep(frame, fp, gen)
    -- Retired by a toggle-off that already ran the restore pass. Touch no
    -- state: a newer walk may own these flags now.
    if gen ~= tutorialSweepGen then return end
    if not TutorialsEnabled() then
        TutorialSweepAbort()
        return
    end
    local ok, nextFrame = pcall(TutorialSweepSlice, frame, fp)
    if not ok then
        TutorialSweepAbort()
        return
    end
    if not nextFrame then
        tutorialSweeping = false
        tutorialsSwept = true
        return
    end
    if not pcall(C_Timer.After, 0, function() TutorialSweepStep(nextFrame, fp, gen) end) then
        TutorialSweepAbort()
    end
end

-- Owns its own once-per-enable bookkeeping. ApplySettings runs for every
-- module on every PLAYER_ENTERING_WORLD and this walks every frame in the
-- game, so only a walk that actually finished counts as done -- a missing
-- fingerprint or a throw leaves it to the next apply.
local function TutorialSweepAll()
    if tutorialSweeping or tutorialsSwept then return end
    local fp = GetTutorialFingerprint()
    if not fp then return end
    tutorialSweeping = true
    local ok, first = pcall(EnumerateFrames)
    if not ok then
        TutorialSweepAbort()
        return
    end
    TutorialSweepStep(first, fp, tutorialSweepGen)
end

local function TutorialRestoreButton(btn)
    btn:SetAlpha(1)
    btn:EnableMouse(true)
end

local function TutorialRestoreButtons()
    for btn in pairs(tutorialsHidden) do
        -- Restored under pcall so one button that refuses cannot abort the
        -- restore of every button behind it, and dropped only on success:
        -- EnableMouse is protected, and forgetting a button that is still
        -- hidden would strand it. A later apply picks the failures back up.
        if pcall(TutorialRestoreButton, btn) then
            tutorialsHidden[btn] = nil
        end
    end
end

local function InstallTutorialCoreHooks()
    if tutorialsCoreHooked then return end
    tutorialsCoreHooked = true
    if HelpTip and HelpTip.Show then
        hooksecurefunc(HelpTip, "Show", function()
            if TutorialsEnabled() then HideOpenTips() end
        end)
    end
    if ShowUIPanel then
        hooksecurefunc("ShowUIPanel", function(frame)
            if TutorialsEnabled() and frame then
                TutorialHideButtonsUnder(frame)
                HideOpenTips()
            end
        end)
    end
end

local function InstallTutorialTooltipHook()
    if tutorialsTooltipHooked or not HelpPlateTooltip then return end
    tutorialsTooltipHooked = true
    if HelpPlate and HelpPlate.ShowTutorialTooltip then
        hooksecurefunc(HelpPlate, "ShowTutorialTooltip", function()
            if TutorialsEnabled() and HelpPlateTooltip then HelpPlateTooltip:Hide() end
        end)
    end
    if HelpPlateTooltip.Init then
        hooksecurefunc(HelpPlateTooltip, "Init", function(self)
            if TutorialsEnabled() then self:Hide() end
        end)
    end
end

local function ApplyHideHelptips()
    if TutorialsEnabled() then
        InstallTutorialCoreHooks()
        InstallTutorialTooltipHook()
        pcall(SetCVar, "hideHelptips", "1")
        pcall(SetCVar, "showTutorials", "0")
        tutorialsWeSetCVar = true
        TutorialSweepAll()
        HideOpenTips()
    else
        if tutorialsWeSetCVar then
            pcall(SetCVar, "hideHelptips", "0")
            pcall(SetCVar, "showTutorials", "1")
            tutorialsWeSetCVar = false
        end
        -- Retire any queued slice before restoring, and free the guard now so a
        -- re-enable in the same frame is not refused by a walk that no longer
        -- owns anything. The retired continuation returns without touching
        -- state.
        tutorialSweepGen = tutorialSweepGen + 1
        tutorialSweeping = false
        tutorialsSwept = false
        TutorialRestoreButtons()
    end
end

function AU:OnInitialize()
    self:UpdateDB()
    ApplyHideHelptips()
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

-- Repair Cost Report --
-- Independent of the two auto-repair toggles above: the bill is announced
-- whoever paid it and whatever triggered it, so a hand-clicked repair, a single
-- item dragged onto the merchant, and another addon's auto-repair all report.

-- Announcing a repair means proving one happened, and the bill is the only
-- honest witness. It falls by exactly what was paid, it does not move when the
-- repair is refused for lack of funds, and it is blind to who paid -- so a
-- guild-funded repair reports its figure without claiming a payer that cannot
-- be verified from here. A RISE means gear was equipped, not repaired.
--
-- Residual: unequipping damaged gear at a merchant also lowers the bill and is
-- announced as a repair. Nothing readable separates the two, and the trade is
-- deliberate -- the alternative loses every guild-funded repair, which is far
-- more common.
function AU:RepairSpend(before, after)
    if type(before) ~= "number" or type(after) ~= "number" then return end
    local spent = before - after
    if spent <= 0 then return end
    return spent
end

local repairReportFrame, repairBill

-- canRepair answers "does this merchant repair", not "is anything damaged", so
-- it stays true across the repair that zeroes the bill. Nil means the bill is
-- unreadable, which disarms rather than reading as zero -- zero would announce
-- the whole outstanding bill as though it had just been paid.
local function ReadRepairBill()
    if not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or type(cost) ~= "number" then return end
    return cost
end

local function SetupRepairReport()
    if repairReportFrame then return end
    repairReportFrame = CreateFrame("Frame")
    repairReportFrame:RegisterEvent("MERCHANT_SHOW")
    repairReportFrame:RegisterEvent("MERCHANT_CLOSED")
    repairReportFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    repairReportFrame:SetScript("OnEvent", function(_, event)
        if not AU.db or not AU.db.Enabled or not AU.db.RepairReport then
            repairBill = nil
            return
        end

        if event == "MERCHANT_CLOSED" then
            repairBill = nil
            return
        end

        if event == "MERCHANT_SHOW" then
            repairBill = ReadRepairBill()
            return
        end

        -- Durability moves for plenty of reasons away from a merchant; only a
        -- window this frame armed on can be reporting a repair.
        if repairBill == nil then return end

        local bill = ReadRepairBill()
        if bill == nil then
            repairBill = nil
            return
        end

        local spent = AU:RepairSpend(repairBill, bill)
        repairBill = bill
        if not spent then return end

        local money = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
            and C_CurrencyInfo.GetCoinTextureString(spent)
        if money then
            KE:Print(string_format("Repaired for %s.", money))
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
            -- Caboodle Utilities.lua). RollOnLoot+ConfirmLootRoll already
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

-- Hide Boss Banner Loot --
-- Stops the boss-kill loot banner from replaying every drop after a kill.
-- The kill banner itself still plays; only the loot scroll is silenced.
-- Reversible with no reload.

local function ApplyNoBossLoot()
    local banner = _G.BossBanner
    if not banner then return end
    local on = AU.db.Enabled and AU.db.HideBossBannerLoot
    if on then
        banner:UnregisterEvent("ENCOUNTER_LOOT_RECEIVED")
    else
        banner:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
    end
end

-- Auto Unwrap Collections --
-- Dismisses the "new mount/pet/toy" fanfare wrap and micro-button alert
-- automatically.

local unwrapFrame
local unwrapInstalled = false
local function SetupAutoUnwrapCollections()
    local on = AU.db.Enabled and AU.db.AutoUnwrapCollections

    if not unwrapInstalled then
        if not on then return end
        unwrapInstalled = true

        local busy = false

        local function AckMountAlerts()
            if not C_MountJournal then return false end
            local pending = C_MountJournal.GetNumMountsNeedingFanfare
                and C_MountJournal.GetNumMountsNeedingFanfare()
            if not pending or pending <= 0 then return false end
            -- Snapshot active filters, force "collected only", sweep, restore
            local snapshot = {}
            for i = LE_MOUNT_JOURNAL_FILTER_COLLECTED, LE_MOUNT_JOURNAL_FILTER_UNUSABLE do
                snapshot[i] = C_MountJournal.GetCollectedFilterSetting(i) and true or false
                C_MountJournal.SetCollectedFilterSetting(i, i == LE_MOUNT_JOURNAL_FILTER_COLLECTED)
            end
            for i = 1, C_MountJournal.GetNumDisplayedMounts() do
                local id = C_MountJournal.GetDisplayedMountID(i)
                if id and C_MountJournal.NeedsFanfare(id) then
                    C_MountJournal.ClearFanfare(id)
                end
            end
            for i = LE_MOUNT_JOURNAL_FILTER_COLLECTED, LE_MOUNT_JOURNAL_FILTER_UNUSABLE do
                C_MountJournal.SetCollectedFilterSetting(i, snapshot[i])
            end
            return true
        end

        local function AckPetAlerts()
            if not C_PetJournal or not C_PetJournal.GetNumPetsNeedingFanfare then return false end
            if (C_PetJournal.GetNumPetsNeedingFanfare() or 0) == 0 then return false end
            local any = false
            for _, id in ipairs(C_PetJournal.GetOwnedPetIDs and C_PetJournal.GetOwnedPetIDs() or {}) do
                if id and C_PetJournal.PetNeedsFanfare and C_PetJournal.PetNeedsFanfare(id) then
                    if C_PetJournal.ClearFanfare then C_PetJournal.ClearFanfare(id) end
                    any = true
                end
            end
            return any
        end

        local function AckToyAlerts()
            if not C_ToyBoxInfo or not C_ToyBoxInfo.ClearFanfare then return false end
            local any = false
            -- Fast path via ToyBox.fanfareToys lookup table
            if ToyBox and ToyBox.fanfareToys then
                for id, needs in pairs(ToyBox.fanfareToys) do
                    if needs and id and C_ToyBoxInfo.NeedsFanfare and C_ToyBoxInfo.NeedsFanfare(id) then
                        C_ToyBoxInfo.ClearFanfare(id)
                        any = true
                    end
                end
                if any then return true end
            end
            -- Fallback: full scan
            if C_ToyBox and C_ToyBox.GetNumToys and C_ToyBox.GetToyFromIndex then
                for i = 1, C_ToyBox.GetNumToys() do
                    local id = C_ToyBox.GetToyFromIndex(i)
                    if id and C_ToyBoxInfo.NeedsFanfare and C_ToyBoxInfo.NeedsFanfare(id) then
                        C_ToyBoxInfo.ClearFanfare(id)
                        any = true
                    end
                end
            end
            return any
        end

        local function DismissCollectionAlerts()
            if not (AU.db.Enabled and AU.db.AutoUnwrapCollections) then return end
            if busy then return end
            busy = true
            C_Timer.After(0.2, function()
                busy = false
                if not (AU.db.Enabled and AU.db.AutoUnwrapCollections) then return end
                local changed = AckMountAlerts() or AckPetAlerts() or AckToyAlerts()
                if changed then
                    if CollectionsMicroButton and MainMenuMicroButton_HideAlert then
                        MainMenuMicroButton_HideAlert(CollectionsMicroButton)
                    end
                    if CollectionsMicroButton_SetAlertShown then
                        CollectionsMicroButton_SetAlertShown(false)
                    end
                end
            end)
        end

        hooksecurefunc("MainMenuMicroButton_ShowAlert", function(_, text)
            if not (AU.db.Enabled and AU.db.AutoUnwrapCollections) then return end
            if text == COLLECTION_UNOPENED_PLURAL or text == COLLECTION_UNOPENED_SINGULAR then
                DismissCollectionAlerts()
            end
        end)

        unwrapFrame = CreateFrame("Frame")
        unwrapFrame:SetScript("OnEvent", function() DismissCollectionAlerts() end)
        -- Defer the first sweep 3s so ToyBox.fanfareToys is available
        -- (avoids a thousand-plus toy fallback scan on the login frame)
        C_Timer.After(3, DismissCollectionAlerts)
    end

    if on then
        unwrapFrame:RegisterEvent("NEW_MOUNT_ADDED")
        unwrapFrame:RegisterEvent("NEW_PET_ADDED")
        unwrapFrame:RegisterEvent("NEW_TOY_ADDED")
    else
        unwrapFrame:UnregisterAllEvents()
    end
end

-- Hide Screenshot Status --
-- Blizzard creates ActionStatus lazily on the first screenshot, so this hides
-- it right after Blizzard's own event handler shows it.

local screenshotFrame
local screenshotInstalled = false
local function SetupHideScreenshotStatus()
    local on = AU.db.Enabled and AU.db.HideScreenshotStatus

    if not screenshotInstalled then
        if not on then return end
        screenshotInstalled = true

        local function HideActionStatus()
            if not (AU.db.Enabled and AU.db.HideScreenshotStatus) then return end
            local actionStatus = _G.ActionStatus
            if actionStatus then actionStatus:Hide() end
        end

        screenshotFrame = CreateFrame("Frame")
        screenshotFrame:SetScript("OnEvent", function()
            if AU.db.HideScreenshotStatus then
                C_Timer.After(0, HideActionStatus)
            end
        end)
    end

    if on then
        screenshotFrame:RegisterEvent("SCREENSHOT_SUCCEEDED")
        screenshotFrame:RegisterEvent("SCREENSHOT_FAILED")
    else
        screenshotFrame:UnregisterAllEvents()
    end
end

-- Hide Error Messages --
-- Swallows red UIErrorsFrame spam while keeping a whitelist of genuinely
-- useful errors. The OnEvent override is only installed while on, so this
-- costs nothing when off and is fully reversible.

local errOrigOnEvent
local errInstalled = false
local errKeep
local function BuildErrKeepList()
    if errKeep then return end
    errKeep = {}
    for _, msg in ipairs({
        ERR_INV_FULL, ERR_QUEST_LOG_FULL, ERR_RAID_GROUP_ONLY,
        ERR_PARTY_LFG_BOOT_LIMIT, ERR_PARTY_LFG_BOOT_DUNGEON_COMPLETE,
        ERR_PARTY_LFG_BOOT_IN_COMBAT, ERR_PARTY_LFG_BOOT_IN_PROGRESS,
        ERR_PARTY_LFG_BOOT_LOOT_ROLLS, ERR_PARTY_LFG_TELEPORT_IN_COMBAT,
        ERR_PET_SPELL_DEAD, ERR_PLAYER_DEAD,
        SPELL_FAILED_TARGET_NO_POCKETS, ERR_ALREADY_PICKPOCKETED,
    }) do
        if msg then errKeep[msg] = true end
    end
end

-- The group-kick "not eligible" line is a format string: pattern match.
local function IsBootNotEligible(err)
    if type(err) ~= "string" or not ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S then return false end
    local ok, found = pcall(function()
        return err:find(string.format(ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S, ".+"))
    end)
    return (ok and found) and true or false
end

local function ErrFilteredOnEvent(self, event, id, err, ...)
    if event == "UI_ERROR_MESSAGE" then
        if errKeep[err] or IsBootNotEligible(err) then
            return errOrigOnEvent(self, event, id, err, ...)
        end
        return
    end
    return errOrigOnEvent(self, event, id, err, ...)
end

local function ApplyHideErrorMessages()
    local on = AU.db.Enabled and AU.db.HideErrorMessages
    if on and not errInstalled then
        BuildErrKeepList()
        errOrigOnEvent = UIErrorsFrame:GetScript("OnEvent")
        UIErrorsFrame:SetScript("OnEvent", ErrFilteredOnEvent)
        UIParent:UnregisterEvent("PING_SYSTEM_ERROR")
        errInstalled = true
    elseif not on and errInstalled then
        UIErrorsFrame:SetScript("OnEvent", errOrigOnEvent)
        errOrigOnEvent = nil
        UIParent:RegisterEvent("PING_SYSTEM_ERROR")
        errInstalled = false
    end
end

-- Omnium Foil character-window button --
-- Hides ExpansionLandingPageMinimapButton and proxies it as a
-- house-styled icon button on PaperDollFrame instead.
--   * Parent to CharacterStatsPane, NOT CharacterFrame -- CharacterFrame
--     stays shown across Reputation/Currency tabs and would leak the
--     button onto all of them; CharacterStatsPane follows the Character
--     tab's Stats sidebar Show/Hide for free. The anchor still targets
--     PaperDollFrame so the position is unchanged.
--   * Below max level Blizzard's own minimap-button tooltip errors (no
--     landing page data), so the whole feature is max-level gated.
--   * Click() the real minimap button rather than reimplementing the
--     toggle; reuse its OnEnter so the tooltip stays whatever Blizzard
--     says it is.

local OMNI_ICON_FILEID = 7554214
local omniCharButton
local omniMinimapHooked = false

local function OmniumAllowed()
    return _G.UnitLevel("player") >= _G.GetMaxPlayerLevel()
end

local function OmniumRefreshShown()
    if omniCharButton then
        omniCharButton:SetShown(AU.db.Enabled and AU.db.OmniumCharButton and OmniumAllowed())
    end
end

local function OmniumCreateButton()
    if omniCharButton then return omniCharButton end
    if not _G.PaperDollFrame then return nil end

    if InCombatLockdown() then
        -- Anchoring onto a Blizzard window mid-fight is not established as safe
        -- in this expansion, and getting it wrong taints. Neither button is
        -- urgent; both wait for the fight to end.
        AU:RegisterEvent("PLAYER_REGEN_ENABLED", "RetrySpawnDeferredButtons")
        return
    end

    local S = KE.Skins
    -- Parent = the stats pane (hides with it); anchor = the paperdoll
    -- (position unchanged).
    local host = _G.CharacterStatsPane or _G.PaperDollFrame
    local b = CreateFrame("Button", "KE_OmniumFoilButton", host)
    b:SetSize(26, 26)
    b:SetPoint("BOTTOMRIGHT", _G.PaperDollFrame, "BOTTOMRIGHT", -8, 8)
    b:SetFrameLevel(_G.PaperDollFrame:GetFrameLevel() + 10)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexture(OMNI_ICON_FILEID)
    b.icon = icon
    if S then
        S.Icon(icon)
        S.Backdrop(b)
        S.Hover(b)
    end

    b:SetScript("OnClick", function()
        local mm = _G.ExpansionLandingPageMinimapButton
        if mm then mm:Click() end
    end)
    b:SetScript("OnEnter", function(self)
        local mm = _G.ExpansionLandingPageMinimapButton
        local onEnter = mm and mm:GetScript("OnEnter")
        if onEnter then
            pcall(onEnter, mm)
            _G.GameTooltip:ClearAllPoints()
            _G.GameTooltip:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", 0, 4)
        end
    end)
    b:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)

    omniCharButton = b
    return b
end

local function SetupOmniumButton()
    local mm = _G.ExpansionLandingPageMinimapButton
    local active = AU.db.Enabled and AU.db.OmniumCharButton and OmniumAllowed()

    if mm and not omniMinimapHooked then
        omniMinimapHooked = true
        hooksecurefunc(mm, "Show", function(self)
            if AU.db.Enabled and AU.db.OmniumCharButton and OmniumAllowed() then self:Hide() end
        end)
    end

    if active then
        if mm then mm:Hide() end
        OmniumCreateButton()
    elseif mm then
        mm:Show()
    end
    OmniumRefreshShown()
end

function AU:RetrySpawnDeferredButtons()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    SetupOmniumButton()
    if AU._deferredTrainAllSpawn then AU._deferredTrainAllSpawn() end
end

-- Train All Button --
-- One click buys every affordable trainer skill, respecting wallet and
-- free primary profession slots.

local trainBtn
local trainAllInstalled = false
local function SetupTrainAllButton()
    local on = AU.db.Enabled and AU.db.TrainAllButton

    if not trainAllInstalled then
        if not on then return end
        trainAllInstalled = true

        local hooked = false

        local function FreeProfessionSlots()
            if not GetProfessions then return 2 end
            local a, b = GetProfessions()
            return 2 - (a and 1 or 0) - (b and 1 or 0)
        end

        local function SkillIsAffordable(i, wallet, freeSlots)
            if not GetTrainerServiceInfo or not GetTrainerServiceCost then return false, 0, false end
            local _, kind = GetTrainerServiceInfo(i)
            if kind ~= "available" then return false, 0, false end
            local cost, takesProfSlot = GetTrainerServiceCost(i)
            cost = cost or 0
            if cost > wallet then return false, 0, false end
            if takesProfSlot and freeSlots <= 0 then return false, 0, false end
            return true, cost, takesProfSlot
        end

        local function TrainableSummary()
            if not GetNumTrainerServices then return 0, 0 end
            local n, gold = 0, 0
            local wallet = GetMoney and GetMoney() or 0
            local slots  = FreeProfessionSlots()
            for i = 1, GetNumTrainerServices() do
                local ok, cost = SkillIsAffordable(i, wallet, slots)
                if ok then n = n + 1; gold = gold + cost end
            end
            return n, gold
        end

        local function RefreshButton()
            if not trainBtn then return end
            if not (AU.db.Enabled and AU.db.TrainAllButton) then
                trainBtn:Hide(); return
            end
            local n = TrainableSummary()
            trainBtn:SetEnabled(n > 0)
            trainBtn:Show()
        end

        local function SpawnButton()
            if not (AU.db.Enabled and AU.db.TrainAllButton) then return end
            if not ClassTrainerFrame or not ClassTrainerTrainButton then return end
            if trainBtn then trainBtn:Show(); RefreshButton(); return end

            if InCombatLockdown() then
                -- Anchoring onto a Blizzard window mid-fight is not established as safe
                -- in this expansion, and getting it wrong taints. Neither button is
                -- urgent; both wait for the fight to end.
                AU:RegisterEvent("PLAYER_REGEN_ENABLED", "RetrySpawnDeferredButtons")
                return
            end

            trainBtn = CreateFrame("Button", "KE_TrainAllButton", ClassTrainerFrame, "MagicButtonTemplate")
            trainBtn:SetText("Train All")
            trainBtn:SetHeight(ClassTrainerTrainButton:GetHeight() or 22)
            trainBtn:SetWidth(80)
            trainBtn:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -2, 0)

            -- Skin immediately when the Dark Theme owns Blizzard frames
            local S = KE.Skins
            if S and S.Button then
                S.StripTextures(trainBtn)
                S.Button(trainBtn)
            end

            trainBtn:SetScript("OnClick", function()
                local wallet = GetMoney and GetMoney() or 0
                local slots  = FreeProfessionSlots()
                for i = 1, GetNumTrainerServices() do
                    local ok, cost, takesProfSlot = SkillIsAffordable(i, wallet, slots)
                    if ok then
                        BuyTrainerService(i)
                        wallet = wallet - cost
                        if takesProfSlot then slots = slots - 1 end
                    end
                end
            end)

            trainBtn:SetScript("OnEnter", function(self)
                local n, gold = TrainableSummary()
                if n <= 0 then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(string.format("Learn %d skill%s for %s",
                    n, n == 1 and "" or "s",
                    C_CurrencyInfo.GetCoinTextureString(gold)), 1, 1, 1)
                GameTooltip:Show()
            end)
            trainBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            if not hooked then
                hooksecurefunc("ClassTrainerFrame_Update", RefreshButton)
                hooked = true
            end
            RefreshButton()
        end

        AU._deferredTrainAllSpawn = SpawnButton

        if EventUtil and EventUtil.ContinueOnAddOnLoaded then
            EventUtil.ContinueOnAddOnLoaded("Blizzard_TrainerUI", SpawnButton)
        end
        if C_AddOns.IsAddOnLoaded("Blizzard_TrainerUI") then SpawnButton() end
    end

    if on then
        AU._deferredTrainAllSpawn()
    else
        if trainBtn then trainBtn:Hide() end
    end
end

-- Hide Transform Items --
-- Auto-cancels cosmetic transform auras (profession gear, holiday costumes,
-- prank toys) with a per-item include/exclude picker. Zero cost when idle:
-- events only registered while the master is on AND at least one transform
-- is included. Two separate defences, in this order: the UNIT_AURA handler
-- refuses an unreadable payload through the shared gate before it reads any
-- field, the added-aura list included, and the sweep then asks the
-- aura-secrecy predicate before touching the aura index. The handler's
-- refusal runs FIRST and does not depend on that bail-out.

local TRANSFORM_CATEGORY_ORDER = { "professions", "holiday", "toys", "items" }
local TRANSFORM_CATEGORY_LABEL = {
    professions = "Profession Gear",
    holiday     = "Holiday Costumes",
    toys        = "Toys",
    items       = "Consumables & Items",
}
local TRANSFORMS = {
    -- Profession gear
    { key = "blacksmithing",  cat = "professions", label = "Blacksmithing",  ids = { 388658 } },
    { key = "jewelcrafting",  cat = "professions", label = "Jewelcrafting",  ids = { 394015 } },
    { key = "tailoring",      cat = "professions", label = "Tailoring",      ids = { 391312 } },
    { key = "engineering",    cat = "professions", label = "Engineering",    ids = { 394007 } },
    { key = "enchanting",     cat = "professions", label = "Enchanting",     ids = { 394008 } },
    { key = "alchemy",        cat = "professions", label = "Alchemy",        ids = { 394003 } },
    { key = "inscription",    cat = "professions", label = "Inscription",    ids = { 394016 } },
    { key = "leatherworking", cat = "professions", label = "Leatherworking", ids = { 394001 } },
    { key = "herbalism",      cat = "professions", label = "Herbalism",      ids = { 394005 } },
    { key = "mining",         cat = "professions", label = "Mining",         ids = { 394006 } },
    { key = "skinning",       cat = "professions", label = "Skinning",       ids = { 394011 } },
    { key = "cooking",        cat = "professions", label = "Cooking (Chef's Hat)", ids = { 391775 } },
    { key = "fishing",        cat = "professions", label = "Fishing",        ids = {} },

    -- Holiday costumes
    { key = "lantern",    cat = "holiday", label = "Weighted Jack-o'-Lantern", ids = { 44212 } },
    { key = "hallowed",   cat = "holiday", label = "Hallowed Wand", ids = {
        172010, 218132, 191703, 24732, 191210, 172015, 24735, 24736, 191698, 191700,
        172008, 24712, 24713, 191701, 191211, 24710, 24711, 191686, 191688, 24708,
        24709, 173958, 173959, 191682, 191683, 24723, 191702, 172003, 172020, 191208, 24740,
    } },
    { key = "noblebunny", cat = "holiday", label = "Noblegarden Bunny", ids = { 61734, 61716 } },
    { key = "turkey",     cat = "holiday", label = "Pilgrim's Turkey", ids = { 61781 } },

    -- Toys
    { key = "aqir",       cat = "toys", label = "Aqir Egg Cluster",          ids = { 318452 } },
    { key = "atomic",     cat = "toys", label = "Atomically Recalibrator",   ids = { 399502 } },
    { key = "atomgoblin", cat = "toys", label = "Atomically Regoblinator",   ids = { 1215363 } },
    { key = "blight",     cat = "toys", label = "Detoxified Blight Grenade", ids = { 290224 } },
    { key = "witch",      cat = "toys", label = "Lucille's Sewing Needle",   ids = { 279509 } },
    { key = "spraybots",  cat = "toys", label = "Spraybots",                 ids = { 301892, 301893, 301894 } },

    -- Consumables & items
    { key = "pickaxe",      cat = "items", label = "Cursed Pickaxe",      ids = { 454405 } },
    -- The SKELETON costume is exempt from the cancel: slow fall and the
    -- remaining mini/reissue effects still cancel.
    { key = "noggenfogger", cat = "items", label = "Noggenfogger Elixir", ids = { 16593, 1223630, 16595, 1223629 } },
    { key = "prism",        cat = "items", label = "Reflecting Prism",    ids = { 163267 } },
}

local transformCTable = {}   -- [spellID] = true for every included transform
local transformAuraFrame     -- lazy
local transformFishFrame     -- lazy
local FISHING_OUTFIT_AURA = 394009
local FISHING_CHANNEL_ID  = 131476

local function TransformItemEnabled(key)
    local t = AU.db.HideTransformItems
    if t and t[key] == false then return false end
    return true  -- included by default; picker stores only exclusions
end

local function RebuildTransformList()
    wipe(transformCTable)
    if not AU.db.HideTransforms then return end
    for _, item in ipairs(TRANSFORMS) do
        if TransformItemEnabled(item.key) then
            for _, id in ipairs(item.ids) do transformCTable[id] = true end
        end
    end
end

-- Index scans hard-error while aura restrictions are active (M+/raids, even
-- out of combat). Transforms are cosmetic; skipping the sweep there is fine
-- -- it re-runs on the next event outside.
--
-- This asked C_UnitAuras.AreAurasRestricted, which no version of the 12.x
-- reference declares, so the guard was never able to fire and the scan below
-- threw instead. KE:AreAuraIdentitiesHidden asks the restriction system the
-- documented way.

-- Sweep current buffs, canceling any included transform. Descending so
-- a cancel (which shifts later buff indices down) cannot skip a match.
local function CancelMatchingTransforms(force)
    if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then return end
    if not force and UnitAffectingCombat("player") then return end
    if KE:AreAuraIdentitiesHidden() then return end
    for i = 40, 1, -1 do
        local data = C_UnitAuras.GetBuffDataByIndex("player", i)
        if data then
            local spellID = data.spellId
            local instanceID = data.auraInstanceID
            if spellID ~= nil
                and not (issecretvalue and issecretvalue(spellID))
                and transformCTable[spellID]
                and instanceID ~= nil
                and not (issecretvalue and issecretvalue(instanceID))
                and C_UnitAuras.CancelAuraByInstanceID then
                C_UnitAuras.CancelAuraByInstanceID("player", instanceID)
            end
        end
    end
end

-- Containment alone leaves a transform stranded: while identities are hidden
-- the sweep refuses, and the aura handler only sweeps on a full update or on a
-- listed transform being ADDED. An update, a removal or an unrelated buff
-- arriving after the restriction lifts does nothing, so out of combat the
-- transform can persist until a reload. The restriction transition is the
-- reliable trigger; combat end stays as a second one because whether the
-- restriction event fires for ordinary combat is unverified. Both feed one
-- debounced sweep that re-asks every question a frame later, when the
-- restriction system answers truthfully again.
local transformSweepPending = false
local function QueueTransformSweep()
    if transformSweepPending then return end
    transformSweepPending = true
    C_Timer.After(0, function()
        transformSweepPending = false
        if not (AU.db and AU.db.Enabled and AU.db.HideTransforms) then return end
        if next(transformCTable) == nil then return end
        CancelMatchingTransforms(true)
    end)
end

local function ApplyHideTransforms()
    RebuildTransformList()
    local on = AU.db.Enabled and AU.db.HideTransforms

    if not transformAuraFrame then
        if not (on and next(transformCTable) ~= nil) then return end
        transformAuraFrame = CreateFrame("Frame")
        transformAuraFrame:SetScript("OnEvent", function(_, event, _, updateInfo)
            -- Restriction transitions and combat end both arrive here with
            -- their own payloads, so they return before anything reads the
            -- UNIT_AURA parameter -- the restriction event's third and fourth
            -- arguments are a type and a state, not an update table.
            if event == "PLAYER_REGEN_ENABLED"
                or event == "ADDON_RESTRICTION_STATE_CHANGED" then
                QueueTransformSweep()
                return
            end
            -- UNIT_AURA (player only). The shared gate covers the payload and
            -- isFullUpdate; the nil check follows it, not the other way round.
            if KE:IsUnreadableAuraPayload("player", updateInfo) then return end
            if updateInfo == nil then return end
            local isFull = updateInfo.isFullUpdate
            if isFull then
                CancelMatchingTransforms(false)
            elseif updateInfo.addedAuras then
                for _, aura in ipairs(updateInfo.addedAuras) do
                    local spellID = aura.spellId
                    if spellID and not (issecretvalue and issecretvalue(spellID)) and transformCTable[spellID] then
                        CancelMatchingTransforms(false)
                        break
                    end
                end
            end
        end)
        -- Fishing outfit: aura 394009 sticks while the fishing channel
        -- (131476) runs; clear it when the channel stops instead.
        transformFishFrame = CreateFrame("Frame")
        transformFishFrame:SetScript("OnEvent", function(_, _, _, _, spellID)
            if spellID ~= FISHING_CHANNEL_ID then return end
            if not (AU.db.HideTransforms and TransformItemEnabled("fishing")) then return end
            C_Timer.After(0.3, function()
                if not (AU.db.Enabled and AU.db.HideTransforms and TransformItemEnabled("fishing")) then return end
                if UnitAffectingCombat("player") or KE:IsAuraHiddenForSpell(FISHING_OUTFIT_AURA) then return end
                if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return end
                local aura = C_UnitAuras.GetPlayerAuraBySpellID(FISHING_OUTFIT_AURA)
                if aura and aura.auraInstanceID ~= nil
                    and not (issecretvalue and issecretvalue(aura.auraInstanceID))
                    and C_UnitAuras.CancelAuraByInstanceID then
                    C_UnitAuras.CancelAuraByInstanceID("player", aura.auraInstanceID)
                end
            end)
        end)
    end

    if on and next(transformCTable) ~= nil then
        transformAuraFrame:RegisterUnitEvent("UNIT_AURA", "player")
        transformAuraFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        transformAuraFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        CancelMatchingTransforms(false)  -- immediate sweep
    else
        transformAuraFrame:UnregisterEvent("UNIT_AURA")
        transformAuraFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        transformAuraFrame:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    end

    if on and TransformItemEnabled("fishing") then
        transformFishFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    else
        transformFishFrame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    end
end

-- Shared with the GUI picker
AU.HideTransformsData = {
    order  = TRANSFORM_CATEGORY_ORDER,
    labels = TRANSFORM_CATEGORY_LABEL,
    items  = TRANSFORMS,
}
AU.GetHideTransformItem = TransformItemEnabled
function AU:SetHideTransformItem(key, enabled)
    self.db.HideTransformItems = self.db.HideTransformItems or {}
    -- Included is the default -- store only exclusions (sparse table)
    if enabled then
        self.db.HideTransformItems[key] = nil
    else
        self.db.HideTransformItems[key] = false
    end
    ApplyHideTransforms()
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
    -- Gated deliberately. Unconditional, every
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
        -- Deliberate: if the GUI closed during the 0.1s window, the refresh
        -- is dropped (not deferred) — the page can show a stale CVar value
        -- until the user re-navigates. Accepted over marking dirty: a CVar
        -- flip while closing the GUI is rare, and this caller never touches
        -- a hidden GUI.
        if KE.GUIFrame and KE.GUIFrame:IsShown() then
            KE.GUIFrame:RefreshContent()
        end
    end)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function AU:ApplySettings()
    ApplyHideHelptips()                    -- master-independent, runs first
    if not self.db.Enabled then return end
    SetupSkipCinematics()
    self:SetupTalkingHeadHider()
    SetupHideEventToasts()
    SetupHideZoneText()
    SetupAutoSellRepair()
    SetupRepairReport()
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
    ApplyNoBossLoot()
    SetupAutoUnwrapCollections()
    SetupHideScreenshotStatus()
    ApplyHideErrorMessages()
    ApplyHideTransforms()
    SetupOmniumButton()
    SetupTrainAllButton()
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

-- Reverses every effective-state-gated feature with the master now off.
-- Each apply re-reads AU.db.Enabled itself, so this never flips a db key --
-- the player's settings survive the module being disabled and come back
-- when it is re-enabled. Hide Helptips is deliberately excluded: it is
-- master-independent and unaffected by this transition.
function AU:TeardownPorts()
    ApplyNoBossLoot()
    SetupAutoUnwrapCollections()
    SetupHideScreenshotStatus()
    ApplyHideErrorMessages()
    ApplyHideTransforms()
    SetupOmniumButton()
    SetupTrainAllButton()
end

function AU:OnDisable()
    self:UnregisterAllEvents()
    -- AceHook auto-unhooks everything on module disable; reset the SecureHook
    -- guard so re-enable actually rehooks TalkingHeadFrame. (_eventToastsHooked
    -- and friends use raw hooksecurefunc — permanent — their flags must stay.)
    self._talkingHeadHooked = false
    self:TeardownPorts()
end
