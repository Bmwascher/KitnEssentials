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
local GetGuildBankMoney = GetGuildBankMoney
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
        -- findYourselfModeOutline does nothing on its own. Blizzard's own
        -- control writes four CVars together: the three mode flags plus
        -- findYourselfAnywhere, which is what actually switches the feature on.
        key = "findYourselfModeOutline",
        label = "Find Yourself Anywhere: |cFF8080FFOutline|r",
        desc = "Adds Outline to Your Player Character.",
        type = "boolean",
        companion = "findYourselfAnywhere",
        -- The master stays on while ANY highlight mode is on, so turning the
        -- outline off must not switch off someone's circle or icon.
        companionKeepAlive = { "findYourselfModeCircle", "findYourselfModeIcon" },
    },
    {
        key = "occludedSilhouettePlayer",
        label = "Obstruction Silhouette",
        desc = "Display a Silhouette of your Character when Obstructed.",
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

-- Reads the client rather than the stored copy, so a value changed in Blizzard's
-- own options or by a console command shows correctly. pcall because this list is
-- deliberately made of CVars Blizzard does not surface in its own options, which
-- are exactly the ones a patch is most likely to rename out from under a page the
-- user merely opened. A CVar this client does not have reads nil, and nil is what
-- tells the page to leave its row out entirely.
function AU:GetLiveCVar(def)
    local ok, raw = pcall(C_CVar.GetCVar, def.key)
    if not ok or raw == nil then return nil end
    if def.type == "boolean" then return raw == "1" end
    return tonumber(raw)
end

-- A CVar this client does not have reads nil. Rendering it anyway produces a
-- dead control sitting at its own minimum, so the row is dropped instead -- and
-- a card that loses every row is not drawn at all. A plain filter, not `goto`:
-- this runtime is Lua 5.1.
function AU:FilterLiveDefs(defs, match)
    local kept = {}
    for _, def in ipairs(defs) do
        if (not match or match(def)) and self:GetLiveCVar(def) ~= nil then
            kept[#kept + 1] = def
        end
    end
    return kept
end

-- Some CVars are only half a switch. `companion` is the master flag that has to
-- be on for this one to do anything; `companionKeepAlive` lists the sibling
-- modes that also depend on that master, so turning this one off does not take
-- theirs down with it.
function AU:ApplyCompanion(def, value)
    if not def.companion then return end
    -- The same refusal the primary gets, because a companion can go missing on
    -- its own: a patch is free to retire the master flag while leaving the mode
    -- flags in place, and every caller of this reaches SetCVar.
    local ok, raw = pcall(C_CVar.GetCVar, def.companion)
    if not ok or raw == nil then return end
    if value then
        C_CVar.SetCVar(def.companion, "1")
        return
    end
    if def.companionKeepAlive then
        for i = 1, #def.companionKeepAlive do
            if C_CVar.GetCVar(def.companionKeepAlive[i]) == "1" then return end
        end
    end
    C_CVar.SetCVar(def.companion, "0")
end

function AU:ApplyCVars()
    if not self.db.CVarsEnabled then return end
    -- Boolean CVars
    for _, def in ipairs(self.CVAR_DEFS) do
        local key = def.key
        local currentValue = self:GetLiveCVar(def)
        -- SetCVar on a name this client does not have is an error, and a stored
        -- value can outlive the CVar: a profile written on a client that had it,
        -- or a patch that renamed it. The page already drops the row; this drops
        -- the write, so both halves refuse on the same condition. The companion
        -- write is inside the guard because a master flag is worth nothing when
        -- the mode it serves is gone.
        if currentValue ~= nil then
            local dbValue = self.db[key]
            if dbValue == nil then
                self.db[key] = currentValue
            elseif dbValue ~= currentValue then
                C_CVar.SetCVar(key, ToCVarValue(dbValue, def.type))
            end
            -- Runs whether or not the primary changed, because the master can be
            -- wrong on its own. It turns the master back on for a mode enabled
            -- here; it never adopts one for a sibling mode, which the keep-alive
            -- only protects from being switched off.
            if def.companion and self.db[key] ~= nil then
                self:ApplyCompanion(def, self.db[key] == true)
            end
        end
    end
    -- Slider CVars
    for _, def in ipairs(self.CVAR_SLIDER_DEFS) do
        local key = def.key
        local currentValue = self:GetLiveCVar(def)
        if currentValue ~= nil then
            local dbValue = self.db[key]
            if dbValue == nil then
                self.db[key] = currentValue
            elseif tostring(dbValue) ~= tostring(currentValue) then
                C_CVar.SetCVar(key, tostring(dbValue))
            end
        end
    end
end

function AU:SyncFromCVars()
    -- nil, never a fabricated value. A CVar this client does not have has no
    -- value, and both defaults are real settings here: a raw read turns an
    -- absent boolean into false and an absent slider into 0, which is how a
    -- profile ends up holding a setting the client cannot back.
    for _, def in ipairs(self.CVAR_DEFS) do
        self.db[def.key] = self:GetLiveCVar(def)
    end
    for _, def in ipairs(self.CVAR_SLIDER_DEFS) do
        self.db[def.key] = self:GetLiveCVar(def)
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
-- ALL of the repair report's shared state, in one block above both consumers.
-- The auto-repair handler writes these before the report frame's own locals
-- would exist, so declaring them lower turns those writes into globals -- and
-- the arm helper below needs repairPending, which used to be declared lower
-- still.
--
-- repairOwnBranch is "guild", "player" or nil. The gold fields are armed ONLY on
-- the guild branch: the player branch is unambiguous, and a repair KE did not
-- start has no trustworthy window to measure.
--
-- repairWatchGen is the cancellation. Bumping it orphans any expiry still
-- pending from an earlier repair, so a stale timer cannot clear live state.
local repairOwnBranch, repairGuildFunds, repairExpected
local repairMoneyLast, repairMoneySpent
local repairWatchGen, repairHeldSweep = 0, nil
local repairPending, repairPendingTotal = false, 0
-- The generation the pending announcement belongs to. MERCHANT_CLOSED keeps a
-- pending total alive on purpose, so a close-and-reopen can arm a NEW watch
-- while an OLDER announcement is still in flight; without this the older
-- announcement would read the newer payer straight out of the globals.
local repairPendingGen = 0
-- Which SCHEDULED announcement is still allowed to run. repairWatchGen tracks
-- the repair; this tracks the callback. They are different things: one repair
-- can schedule several announcements -- the first bill drop arms one, and every
-- debit re-arms it -- and every one of those callbacks stays live and would
-- otherwise fire in turn, the earliest of them consuming a ledger that is still
-- filling.
local repairAnnounceEpoch = 0
-- Which MERCHANT VISIT the stored bill belongs to. repairWatchGen tracks the
-- REPAIR; this tracks the visit, and they move independently -- a visit can
-- open without arming a watch, and a watch can outlive the visit that armed it.
-- Keying the bill's cleanup on the watch generation gets both cases wrong: a
-- watch that expires first strands the bill, and a reopen that arms no watch
-- lets a stale timer wipe the new visit's baseline.
local repairMerchantGen = 0
-- FORWARD DECLARATION, and it is load-bearing. ArmRepairWatch's expiry calls
-- AnnounceRepair, but that function is defined further down beside the report
-- frame. Without this line the call would resolve as a global, read nil, and
-- error the first time a watch expired.
local AnnounceRepair

local function ReadGold()
    local gold = GetMoney()
    if KE:IsSecretValue(gold) then return nil end
    if type(gold) ~= "number" then return nil end
    return gold
end

-- Today's remaining guild allowance, bounded by what the bank actually holds.
-- GetGuildBankWithdrawMoney returns the DAILY ALLOWANCE, not the balance, and
-- returns -1 for a rank with unlimited withdrawal -- so it is a ceiling only,
-- and an unbounded one at that.
local function ReadGuildRepairFunds()
    local allowance = GetGuildBankWithdrawMoney()
    local balance = GetGuildBankMoney()
    if KE:IsSecretValue(allowance) or KE:IsSecretValue(balance) then return nil end
    if type(allowance) ~= "number" or type(balance) ~= "number" then return nil end
    if allowance < 0 or allowance > balance then return balance end
    return allowance
end

-- Whether the guild rank's withdrawal allowance covers a bill.
--
-- -1 is the sentinel for UNLIMITED withdrawal. Compared as a plain number it is
-- smaller than every bill, so the ranks with the most access were the ones sent
-- down the player branch -- the exact opposite of the setting they ticked.
--
-- Only the ALLOWANCE is tested, never the balance. A bank holding less than the
-- bill still pays what it has and the server settles the shortfall against the
-- player, so bounding this on the balance would give up partial guild coverage
-- the player already gets.
function AU:CanGuildCover(allowance, cost)
    if type(allowance) ~= "number" or type(cost) ~= "number" then return false end
    if allowance < 0 then return true end
    return allowance >= cost
end

-- How long the report window outlives the merchant. Long enough for a bill drop
-- that lands just after the frame shuts, short enough that the watch expiry
-- still owns the real cleanup.
local CLOSE_GRACE = 0.5

-- Idempotent. The held junk sale runs on the first debit, or at expiry,
-- whichever arrives first.
local function ReleaseHeldSweep()
    local sweep = repairHeldSweep
    repairHeldSweep = nil
    if sweep then sweep() end
end

-- Only the LATEST schedule may consume the ledger. Each call retires the one
-- before it, so a debit RESETS the settle window instead of adding a second
-- callback to it, and a callback left over from a window that has been flushed
-- cannot fire into the window that replaced it.
local function ScheduleAnnounce()
    repairAnnounceEpoch = repairAnnounceEpoch + 1
    local epoch = repairAnnounceEpoch
    C_Timer.After(0.5, function()
        if epoch ~= repairAnnounceEpoch then return end
        AnnounceRepair()
    end)
end

local function DisarmRepairWatch()
    repairWatchGen = repairWatchGen + 1
    repairOwnBranch, repairGuildFunds, repairExpected = nil, nil, nil
    repairMoneyLast, repairMoneySpent = nil, nil
    ReleaseHeldSweep()
end

-- Every armed watch gets its own expiry. Without it, a repair whose bill never
-- falls -- at a merchant left open -- leaves the watch armed for a later
-- hand-click to inherit, because the announce timer only arms on a positive
-- durability delta and MERCHANT_CLOSED has not fired yet.
--
-- The window is deliberately LONGER than the announce path, and the expiry
-- stands down while an announcement is pending. Both are needed: this timer is
-- set BEFORE RepairAllItems, while the announce timer is set after the bill
-- falls, so a matching 0.5s would have the expiry clear the payer before
-- AnnounceRepair ever reads it -- destroying the exact state it exists to
-- protect.
local WATCH_EXPIRY = 2

-- Every branch arms, including the player branch. It carries no gold fields --
-- there is nothing to measure -- but it must still bump the generation, or a
-- guild expiry still pending from earlier in the same merchant visit would
-- clear it; and it must still expire, or a player repair whose bill never falls
-- stays armed.
local function ArmRepairWatch(branch, expected, guildFunds, gold, sweep)
    repairWatchGen = repairWatchGen + 1
    local gen = repairWatchGen

    repairOwnBranch = branch
    -- What KE's own call was going to pay. The reporter coalesces EVERY bill
    -- drop in the window into one total, so a hand repair landing before the
    -- announcement would otherwise be added to KE's figure and inherit KE's
    -- payer. A total above this means more than KE's repair contributed, and
    -- the label is refused.
    repairExpected = expected
    repairGuildFunds = guildFunds
    repairMoneyLast = gold
    -- nil, NOT zero, when the wallet is unreadable. Zero would read as "no gold
    -- left the wallet", which is the guild-paid-everything signal -- the most
    -- confident label available, drawn from no evidence at all.
    repairMoneySpent = gold and 0 or nil
    repairHeldSweep = sweep

    C_Timer.After(WATCH_EXPIRY, function()
        if gen ~= repairWatchGen then return end

        -- A debit has landed and THIS watch's own settle window is still
        -- counting down. That window exists to stop a partial bill being split,
        -- so forcing here would do the exact thing it prevents.
        --
        -- Standing down leaks nothing, and both halves of the test are needed
        -- for that. A positive spend with an announcement pending means a
        -- schedule is live -- every debit arriving while pending re-arms one,
        -- and a schedule is retired only by its successor. The generation match
        -- means that schedule is NOT stale, so it will disarm this watch on its
        -- way out. A stale one would not, and standing down for it would leave
        -- this watch armed with nothing left to clean it up.
        if repairPending and repairPendingGen == repairWatchGen
            and (repairMoneySpent or 0) > 0 then
            return
        end

        -- Resolve ANY pending announcement, including one stamped with an
        -- OLDER generation. That one has no owner left: its own expiry
        -- self-cancelled the moment this watch armed, and nothing else ever
        -- clears repairPending. Left standing it wedges repairPending true
        -- forever, and the durability branch only schedules an announcement
        -- when repairPending is false -- so EVERY later repair in the session
        -- would go unreported until a reload.
        --
        -- Forcing a stale one through is safe: AnnounceRepair sees the
        -- generation mismatch, drops the payer, prints the plain line, and
        -- deliberately does not disarm the newer watch.
        if repairPending then AnnounceRepair(true) end

        -- A non-stale announcement already disarmed and bumped the generation,
        -- so this is skipped. A stale one did not, and this watch still needs
        -- its own cleanup.
        if gen == repairWatchGen then DisarmRepairWatch() end
    end)
end

local function SetupAutoSellRepair()
    if merchantFrame then return end
    merchantFrame = CreateFrame("Frame")
    merchantFrame:RegisterEvent("MERCHANT_SHOW")
    merchantFrame:SetScript("OnEvent", function()
        if not AU.db or not AU.db.Enabled then return end
        if KE:IsFullyRestricted() then return end

        -- Held rather than called, so the guild branch below can delay it. Nil
        -- when there is nothing to sell or the feature is off.
        local sweep
        if AU.db.AutoSellJunk and not IsShiftKeyDown()
            and C_MerchantFrame.GetNumJunkItems() > 0 then
            sweep = function() C_MerchantFrame.SellAllJunkItems() end
        end

        if AU.db.AutoRepair and CanMerchantRepair() then
            local repairCost = GetRepairAllCost()
            if not KE:IsSecretValue(repairCost)
                and repairCost and repairCost > 0 then
                -- The report preference gates the WATCH, never the branch.
                -- Gating the branch would make a reporting checkbox decide who
                -- pays for the repair: with the report off, this guild-eligible
                -- case would fall through and spend the player's own gold.
                if AU.db.UseGuildFunds and CanGuildBankRepair() then
                    local guildBankMoney = GetGuildBankWithdrawMoney()
                    if not KE:IsSecretValue(guildBankMoney)
                        and AU:CanGuildCover(guildBankMoney, repairCost) then
                        if AU.db.RepairReport then
                            -- Both readings must predate the repair, and the
                            -- sale must not land in the same money event as the
                            -- debit.
                            ArmRepairWatch("guild", repairCost,
                                ReadGuildRepairFunds(), ReadGold(), sweep)
                        elseif sweep then
                            -- Nothing to label, so nothing to hold for. Selling
                            -- now avoids stranding it: with the report off, the
                            -- frame's feature gate returns before its
                            -- PLAYER_MONEY branch, so no debit could release it.
                            sweep()
                        end
                        RepairAllItems(true)
                        return
                    end
                end

                -- Player branch: sell first, exactly as before, because the
                -- affordability check below has to see post-sale gold.
                if sweep then sweep() sweep = nil end

                local wallet = GetMoney()
                if not KE:IsSecretValue(wallet) and type(wallet) == "number"
                    and wallet >= repairCost then
                    -- No gold fields: own gold, nothing to work out. It still
                    -- arms, so it owns the generation and gets an expiry. Gated
                    -- on the report for the same reason as above -- but the
                    -- REPAIR is outside the gate either way.
                    if AU.db.RepairReport then
                        ArmRepairWatch("player", repairCost, nil, nil, nil)
                    end
                    RepairAllItems(false)
                end
            end
        end

        if sweep then sweep() end
    end)
end

-- Repair Cost Report --
-- Independent of the two auto-repair toggles above: the bill is announced
-- whoever paid it and whatever triggered it, so a hand-clicked repair, a single
-- item dragged onto the merchant, and another addon's auto-repair all report.

-- The bill is the best witness available, not proof. It falls by what a repair
-- paid, it does not move when a repair is refused for lack of funds, and it
-- still only proves a repair happened -- the payer is established separately,
-- for repairs KE started. A RISE means gear was equipped, not repaired.
--
-- Residual, and the reason "witness" is the right word rather than "proof":
-- anything that removes damaged gear at a merchant lowers the bill the same
-- way, unequipping and selling included, and is announced as a repair. Nothing
-- readable separates the two. The trade is deliberate -- watching the player's
-- money instead would lose every guild-funded repair, which is far more common
-- than either false positive.
function AU:RepairSpend(before, after)
    if type(before) ~= "number" or type(after) ~= "number" then return end
    local spent = before - after
    if spent <= 0 then return end
    return spent
end

-- Pressing the guild button does not mean the guild paid. The server pays what
-- the allowance covers and charges the player the difference, with no error and
-- no return value, so the only witness is how much gold actually left.
--
-- More gold out than the bill fell by is a refusal, not a clamp: it means
-- something else spent gold in the window, and nothing here can say how much.
--
-- The one remaining clamp decides nothing on its own -- the guild's share cannot
-- exceed the allowance, which catches income landing in the same money event as
-- the debit, netting off and understating what the player paid.
--
-- A zero allowance is NOT a cap. GetGuildBankMoney reads zero until a guild bank
-- has been opened this session, which is the same reading as a genuinely empty
-- bank, so tightening on it would credit every repair to the player.
--
-- ownSpent nil means the wallet was never readable. Refusing is the whole point:
-- treating it as zero would print the most confident possible label from the
-- least evidence.
function AU:RepairSplit(paid, ownSpent, guildFunds)
    if type(paid) ~= "number" or type(ownSpent) ~= "number" then return nil end
    if paid <= 0 then return nil end

    local own = ownSpent
    if own < 0 then own = 0 end

    -- REFUSE rather than clamp. Clamping to the bill was hiding the worst
    -- failure this function has: unrelated spending larger than the bill would
    -- clamp down to exactly the bill and print "using your own gold" for a
    -- repair the guild paid in full. More gold left than the bill fell by means
    -- something else spent it, and nothing here can say how much.
    if own > paid then return nil end

    local guildPart = paid - own
    if type(guildFunds) == "number" and guildFunds > 0 and guildPart > guildFunds then
        guildPart = guildFunds
        own = paid - guildPart
    end

    return guildPart, own
end

local repairReportFrame, repairBill

-- One repair action can surface as several durability events with the bill
-- falling in stages, and announcing each drop turns one repair into a
-- paragraph. Deltas accumulate and are announced once the bill stops moving.
-- The sum is what was paid either way, so coalescing loses nothing, and the
-- timer is deliberately left to fire after the merchant closes: the money was
-- still spent.
--
-- force is passed only by the watch expiry, which is the backstop for a repair
-- whose debit never arrives at all -- a guild bank that covered the whole bill.
--
-- NOT `local function` -- the name is forward-declared in the shared state block
-- so the expiry above can reach it. `local function` here would create a second,
-- shadowing local and leave that caller pointing at nil.
function AnnounceRepair(force)
    -- WAIT rather than guess. Measured: the debit for KE's own repair landed
    -- 60ms inside this timer, and a different wallet event in the same merchant
    -- window landed 50ms outside it. Announcing on schedule would therefore read
    -- a debit that has not landed yet, and call a part-player-funded repair
    -- fully guild-funded -- the one failure this whole task exists to prevent,
    -- and one that cannot be told apart afterwards.
    --
    -- Only KE's own guild branch waits. The player branch is unambiguous, and a
    -- repair KE did not start carries no payer to be wrong about.
    --
    -- repairPending and repairPendingTotal are deliberately NOT cleared here:
    -- this announcement has not happened yet. The first PLAYER_MONEY decrease
    -- re-enters this function, and the expiry forces it through.
    if not force and repairOwnBranch == "guild" and repairMoneySpent == 0
        and repairPendingGen == repairWatchGen then
        return
    end

    repairPending = false
    local spent = repairPendingTotal
    repairPendingTotal = 0

    local branch, ownSpent = repairOwnBranch, repairMoneySpent
    local guildFunds, expected = repairGuildFunds, repairExpected

    -- The watch moved on since this announcement was armed -- a close and
    -- reopen, or a second repair -- so whatever sits in the globals now
    -- describes a different repair than the one being announced.
    local stale = repairPendingGen ~= repairWatchGen
    if stale then branch = nil end

    -- More fell off the bill than KE's own call was paying, so a repair KE did
    -- not start is inside this total. The figure is still right; the payer is
    -- no longer knowable, and the scope is KE's own repairs only.
    --
    -- This catches the growing total, not every overlap: if KE's own repair only
    -- partly succeeded, a foreign repair can fill the gap and leave the total at
    -- or under the expected figure. Documented as accepted -- it needs a partial
    -- failure AND a hand click inside the same coalescing window.
    if branch and (type(expected) ~= "number" or spent > expected) then
        branch = nil
    end

    -- Consume everything that described THIS repair action rather than the
    -- merchant session, and orphan the pending expiry so it cannot clear state
    -- a later repair has already armed.
    --
    -- A STALE announcement disarms nothing. The globals belong to a newer watch
    -- that has not announced yet; clearing them here would strip its payer and
    -- release its held junk sale early. Its own expiry cleans it up.
    if not stale then DisarmRepairWatch() end

    -- The preference can go off INSIDE the settle window -- a profile switch
    -- as easily as a click. Everything above still has to run: skipping the
    -- consumption wedges repairPending and silences every later repair in the
    -- session. Only the printing stops here.
    --
    -- Returning also drops a payer that stopped being measurable at the
    -- moment the gate closed: the money branch shares this gate, so debits
    -- landing after the flip never reached repairMoneySpent, and a part-paid
    -- repair would read as fully guild-funded.
    if not (AU.db and AU.db.Enabled and AU.db.RepairReport) then return end

    if spent <= 0 then return end

    local money = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
        and C_CurrencyInfo.GetCoinTextureString(spent)
    if not money then return end

    if branch == "player" then
        KE:Print(string_format("Repaired for %s (your gold).", money))
        return
    end

    if branch == "guild" then
        local guildPart, ownPart = AU:RepairSplit(spent, ownSpent, guildFunds)
        if guildPart and guildPart > 0 and ownPart > 0 then
            local guildMoney = C_CurrencyInfo.GetCoinTextureString(guildPart)
            if guildMoney then
                KE:Print(string_format(
                    "Repaired for %s (guild %s, rest yours).",
                    money, guildMoney))
                return
            end
        elseif guildPart and guildPart > 0 then
            KE:Print(string_format("Repaired for %s (guild funds).", money))
            return
        elseif guildPart then
            KE:Print(string_format("Repaired for %s (your gold).", money))
            return
        end
    end

    -- Not ours, or the split could not be worked out. Say what is certain.
    KE:Print(string_format("Repaired for %s.", money))
end

-- Only the cost is read. GetRepairAllCost's second return is NOT the merchant
-- capability flag -- `CanMerchantRepair` is that, and Blizzard gates the repair
-- UI on it separately -- and the second return goes false once nothing is
-- damaged, which is precisely the reading a just-finished repair produces.
-- Gating on it made the bill unreadable at the one moment it mattered. Its
-- exact semantics are not documented, so nothing here depends on them.
--
-- issecretvalue before type(), because the type check is itself a read and a
-- secret value throws on one. Whether this return can be secret is undocumented
-- both ways; a reference addon records a user report of the comparison throwing
-- here, and a single readable in-game sample cannot rule out a situational
-- secret. Unreadable therefore means say nothing, not guess.
local function ReadRepairBill()
    local cost = GetRepairAllCost()
    if KE:IsSecretValue(cost) then return end
    if type(cost) ~= "number" then return end
    return cost
end

local function SetupRepairReport()
    if repairReportFrame then return end
    repairReportFrame = CreateFrame("Frame")
    repairReportFrame:RegisterEvent("MERCHANT_SHOW")
    repairReportFrame:RegisterEvent("MERCHANT_CLOSED")
    repairReportFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    repairReportFrame:RegisterEvent("PLAYER_MONEY")
    repairReportFrame:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_CLOSED" then
            -- A repair KE started can have its bill drop land AFTER the window
            -- shuts. Tearing the window down here loses the report for a repair
            -- that did happen, so an armed watch with nothing pending yet gets
            -- one short beat to let the drop arrive.
            --
            -- Damage taken in that beat cannot be misread as a repair: it
            -- RAISES the bill, and only a fall is ever reported.
            --
            -- The held junk sale is deliberately NOT deferred with it. It is
            -- released now, while the merchant is still closing, because a sale
            -- attempted a beat later has no merchant left to sell to.
            if repairOwnBranch and not repairPending then
                ReleaseHeldSweep()
                -- TWO generations, because the two halves below answer to
                -- different owners. The bill belongs to the merchant VISIT, so
                -- a reopen inside the grace window must keep its own fresh
                -- baseline; the watch belongs to the REPAIR, and its expiry may
                -- have retired it before this even runs.
                local wgen, mgen = repairWatchGen, repairMerchantGen
                C_Timer.After(CLOSE_GRACE, function()
                    if mgen == repairMerchantGen then repairBill = nil end
                    if wgen == repairWatchGen and not repairPending then
                        DisarmRepairWatch()
                    end
                end)
                return
            end

            repairBill = nil
            -- Only a repair that never armed an announcement is cleared here.
            -- AnnounceRepair consumes the rest itself.
            if not repairPending then DisarmRepairWatch() end
            return
        end

        if not AU.db or not AU.db.Enabled or not AU.db.RepairReport then
            repairBill = nil
            return
        end

        if event == "MERCHANT_SHOW" then
            repairMerchantGen = repairMerchantGen + 1
            repairBill = ReadRepairBill()
            return
        end

        if event == "PLAYER_MONEY" then
            -- Armed only while a guild repair KE started is settling. Only
            -- DECREASES count: the held junk sale still raises gold when it
            -- lands, and counting any change would read a sale as a payment.
            if repairMoneyLast then
                local now = ReadGold()
                if not now then
                    -- The wallet went unreadable mid-window. A skipped debit
                    -- understates the player's share exactly like an unreadable
                    -- arm, so poison the measurement rather than carry on with
                    -- a total known to be short.
                    repairMoneyLast, repairMoneySpent = nil, nil
                    return
                end
                if now < repairMoneyLast then
                    repairMoneySpent = (repairMoneySpent or 0)
                        + (repairMoneyLast - now)
                    -- The debit is booked, so nothing can net against it now.
                    ReleaseHeldSweep()
                    -- The announcement that was waiting for exactly this can
                    -- now settle -- but not this instant. This debit is charged
                    -- against the WHOLE repair, while repairPendingTotal holds
                    -- only the bill drops seen so far. Announcing here would
                    -- divide the entire player payment across a partial repair
                    -- and print a confident split for it, then print whatever
                    -- arrived afterwards as a second, unattributed line.
                    --
                    -- Re-arm the settle window instead and let the remaining
                    -- drops land first. ScheduleAnnounce RETIRES the schedule
                    -- already outstanding rather than joining it, which matters
                    -- in the measured ordering: the drops come first, so that
                    -- earlier callback is still counting down and would fire
                    -- before this one and announce the partial bill. Repeated
                    -- debits reset the window for the same reason.
                    --
                    -- The wait cannot hold the new schedule: it tests
                    -- repairMoneySpent == 0 and the value is now positive.
                    if repairPending then ScheduleAnnounce() end
                end
                repairMoneyLast = now
            end
            return
        end

        -- Durability moves for plenty of reasons away from a merchant; only a
        -- window this frame armed on can be reporting a repair.
        if repairBill == nil then return end

        local bill = ReadRepairBill()
        -- A bill that cannot be read cannot be compared against the armed one,
        -- so disarm rather than guess at what moved.
        if bill == nil then
            repairBill = nil
            return
        end

        local spent = AU:RepairSpend(repairBill, bill)
        repairBill = bill
        if not spent then return end

        -- A pending announcement stamped with a DIFFERENT watch belongs to a
        -- repair that is already finished. It must be flushed BEFORE this drop
        -- is added, because the accumulator below is shared: merged, the two
        -- amounts print as one line under the older repair's stamp, and the
        -- newer repair is left with an empty ledger and no announcement of its
        -- own. Flushing first prints the old figure alone and frees the slot,
        -- so the lines below then open a fresh window for this drop.
        --
        -- The forced call is stale by construction, so it drops the payer,
        -- prints the plain line, and leaves the live watch armed.
        if repairPending and repairPendingGen ~= repairWatchGen then
            AnnounceRepair(true)
        end

        repairPendingTotal = repairPendingTotal + spent
        if not repairPending then
            repairPending = true
            -- Stamp the watch this announcement belongs to. MERCHANT_CLOSED
            -- keeps a pending total alive on purpose, so a close-and-reopen can
            -- arm a NEW watch while this announcement is still in flight;
            -- without the stamp it would read the new payer out of the globals
            -- and pin it to an older, unrelated repair.
            repairPendingGen = repairWatchGen
            ScheduleAnnounce()
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
-- Explicit battle-res detection via boss1-in-combat + inviter-in-combat,
-- rather than
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

local math_floor = math.floor
local tonumber = tonumber

local OMNI_ICON_FILEID = 7554214
local VAULT_ICON_FILEID = 2744751
local omniCharButton
local vaultCharButton
local omniMinimapHooked = false

-- Size is its own key rather than following the gem socket slider: the two
-- rows are different shapes, and the gem default is 24 while this button has
-- always been 26, so following it would resize a button that already shipped.
local function CharBtnSize()
    local size = tonumber(AU.db and AU.db.WindowButtonSize)
    if size and size > 4 then return math_floor(size + 0.5) end
    return 26
end

-- The gap DOES follow the gem spacing -- it is the one value the two rows
-- genuinely share, and it already exists as a user-facing slider.
local function CharBtnGap()
    local cp = KE.db and KE.db.profile and KE.db.profile.CharacterPanel
    local gap = cp and tonumber(cp.SocketButtonSpacing)
    if gap and gap >= 0 then return gap end
    return 1
end

-- Slot 0 is the corner, slot 1 sits one button-width to its left. Slots are
-- fixed, so hiding one button never moves the other.
local function CharBtnOffset(slot, size, gap)
    return -(8 + slot * (size + gap))
end

-- Absolute on every call, so running it repeatedly produces the same layout
-- and a size change lands without any remembered previous state.
local function PlaceCharButton(b, slot)
    local pdf = _G.PaperDollFrame
    if not (b and pdf) then return end
    local size = CharBtnSize()
    b:SetSize(size, size)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMRIGHT", pdf, "BOTTOMRIGHT", CharBtnOffset(slot, size, CharBtnGap()), 8)
end

local function OmniumAllowed()
    return _G.UnitLevel("player") >= _G.GetMaxPlayerLevel()
end

-- `AU:IsEnabled()` and not the preference key, here and at the other gates
-- below. Ace marks the module disabled BEFORE dispatching OnDisable, and
-- AU:Disable() is reachable without the key changing, so anything reached from
-- teardown can still read a true key while the module is going down. Here that
-- would leave a disabled module's buttons on screen. Both halves move together:
-- half a function on the lifecycle predicate would hide one button and leave
-- its neighbour behind.
local function OmniumRefreshShown()
    if omniCharButton then
        omniCharButton:SetShown(AU:IsEnabled() and AU.db.OmniumCharButton and OmniumAllowed())
    end
    if vaultCharButton then
        vaultCharButton:SetShown(AU:IsEnabled() and AU.db.VaultCharButton and OmniumAllowed())
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
    PlaceCharButton(b, 0)
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

-- Great Vault, in the slot left of the Omnium Foil button. Same max-level gate
-- and same parent as its neighbour, so it inherits the stats-sidebar shown
-- state instead of tracking it.
local function VaultCreateButton()
    if vaultCharButton then return vaultCharButton end
    if not _G.PaperDollFrame then return nil end

    if InCombatLockdown() then
        -- Same reason as its neighbour: anchoring onto a Blizzard window
        -- mid-fight is not established as safe in this expansion.
        AU:RegisterEvent("PLAYER_REGEN_ENABLED", "RetrySpawnDeferredButtons")
        return
    end

    local S = KE.Skins
    local host = _G.CharacterStatsPane or _G.PaperDollFrame
    local b = CreateFrame("Button", "KE_GreatVaultButton", host)
    PlaceCharButton(b, 1)
    b:SetFrameLevel(_G.PaperDollFrame:GetFrameLevel() + 10)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexture(VAULT_ICON_FILEID)
    b.icon = icon
    if S then
        S.Icon(icon)
        S.Backdrop(b)
        S.Hover(b)
    end

    b:SetScript("OnClick", function()
        -- The panel manager refuses insecure show/hide in combat and prints the
        -- blocked-action message when it does. Refusing here keeps that message
        -- off the screen; the button is never urgent mid-fight.
        if InCombatLockdown() then return end
        -- Load-on-demand: the vault frame does not exist until something asks
        -- for it, and on a fresh login that is usually this button.
        if _G.C_AddOns and _G.C_AddOns.LoadAddOn then
            _G.C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
        end
        local f = _G.WeeklyRewardsFrame
        if not f then return end
        -- Through the panel manager, never a raw Show/Hide. This frame carries a
        -- center UIPanel area attribute, so the manager routes it to the secure
        -- delegate and stacks it against the other center panels. A raw Show
        -- puts it on screen with the manager still believing it hidden.
        if f:IsShown() then
            _G.HideUIPanel(f)
        else
            -- WeeklyRewards_ShowUI uses boolean force; the generated stub is wrong.
            ---@diagnostic disable-next-line: type-mismatch
            _G.ShowUIPanel(f, true)
        end
    end)
    b:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_NONE")
        _G.GameTooltip:ClearAllPoints()
        _G.GameTooltip:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", 0, 4)
        _G.GameTooltip:SetText(_G.GREAT_VAULT_REWARDS or "Great Vault")
        _G.GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)

    vaultCharButton = b
    return b
end

-- Re-placed on every sheet open, not only at creation: the size follows a
-- slider that has no reason to know these buttons exist.
--
-- Same combat refusal the creator uses. This runs from the sheet's OnShow, so
-- without it opening the character window mid-fight re-anchors onto a Blizzard
-- window -- the exact operation creation defers. A slider change made in combat
-- lands on the next out-of-combat open.
local function RefreshCharButtons()
    if InCombatLockdown() then return end
    -- The hook below is permanent and outlives AU:OnDisable, so without this it
    -- keeps re-anchoring buttons for a module that is switched off.
    if not AU:IsEnabled() then return end
    if omniCharButton then PlaceCharButton(omniCharButton, 0) end
    if vaultCharButton then PlaceCharButton(vaultCharButton, 1) end
end

-- The hook cannot be removed once installed, so it goes on exactly once. The
-- latch and its only reader live together here rather than being split across
-- two edits, which would leave a local nothing reads yet.
local charBtnShowHooked = false
local function EnsureCharBtnShowHook()
    if charBtnShowHooked or not _G.CharacterFrame then return end
    charBtnShowHooked = true
    _G.CharacterFrame:HookScript("OnShow", RefreshCharButtons)
end

local function SetupOmniumButton()
    local mm = _G.ExpansionLandingPageMinimapButton
    -- Lifecycle, not the key: this function is reached from OnDisable through
    -- TeardownPorts, and creating the button there can re-register
    -- PLAYER_REGEN_ENABLED on a module whose events were just unregistered.
    local active = AU:IsEnabled() and AU.db.OmniumCharButton and OmniumAllowed()

    if mm and not omniMinimapHooked then
        omniMinimapHooked = true
        hooksecurefunc(mm, "Show", function(self)
            if AU:IsEnabled() and AU.db.OmniumCharButton and OmniumAllowed() then self:Hide() end
        end)
    end

    if active then
        if mm then mm:Hide() end
        OmniumCreateButton()
    elseif mm then
        mm:Show()
    end

    -- TeardownPorts reaches this function too, so the gate stops two things
    -- happening from inside teardown: creating a button, and installing a hook
    -- that can never be removed afterwards.
    if AU:IsEnabled() then
        if AU.db.VaultCharButton and OmniumAllowed() then
            VaultCreateButton()
        end
        EnsureCharBtnShowHook()
    end

    -- OUTSIDE the gate on purpose: it stands itself down on the same predicate,
    -- so gating it here would only say the same thing twice.
    RefreshCharButtons()

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
