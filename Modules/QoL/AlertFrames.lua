-- ╔══════════════════════════════════════════════════════════╗
-- ║  AlertFrames.lua                                         ║
-- ║  Module: Alert Frames                                    ║
-- ║  Purpose: Move the Blizzard alert/toast stack (loot,     ║
-- ║           achievements, dungeon completion) to a spot    ║
-- ║           you choose, and optionally the Event Toast     ║
-- ║           stack (recipe/level-up banners) too.           ║
-- ║                                                          ║
-- ║  TAINT NOTE: this module REPLACES the AdjustAnchors      ║
-- ║  method on Blizzard's alert subsystem tables. There is   ║
-- ║  no hook-based alternative because those functions chain ║
-- ║  return values. Any combat "action failed" report after  ║
-- ║  this ships suspects this module first.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class AlertFrames: AceModule
local AF = KitnEssentials:NewModule("AlertFrames")

-- No live teardown for the replaced AdjustAnchors methods or the permanent
-- hooksecurefunc hooks above, so a profile switch that wants this module
-- OFF must stay enabled and prompt for /reload instead of disabling live.
AF.keReloadOnDisable = true

local _G = _G
local ipairs = ipairs
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local UIParent = UIParent

-- Growth state, mutated by PostAlertMove.
local POSITION, POINT, X_OFFSET, Y_OFFSET, BASE_YOFFSET = "TOP", "BOTTOM", 0, -5, 0

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function AF:UpdateDB()
    self.db = KE.db.profile.AlertFrames
end

-- ElvUI owns this area and the controls are unreachable there, so the module does not run.
local function Suppressed()
    return KE.ShouldNotLoadModule and KE:ShouldNotLoadModule() and true or false
end

function AF:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState((self.db.Enabled and not Suppressed()) and true or false)
end

---------------------------------------------------------------------------------
-- Positioning
---------------------------------------------------------------------------------
function AF:ApplyPosition()
    if not (self.holder and self.db and self.db.Position) then return end
    KE:ApplyFramePosition(self.holder, self.db.Position, self.db)
    self:PostAlertMove()
end

-- The event toast holder anchors independently of the alert stack holder, so
-- it needs its own anchorFrameType/ParentFrame/Strata root keys rather than
-- sharing self.db's (fix round 1, CRITICAL/IMPORTANT: the GUI's Card 4 used
-- to write db.Position and db.anchorFrameType/ParentFrame/Strata -- the same
-- fields Card 2 owns -- so the two position cards silently mirrored each
-- other. Card 4 now writes EventToastAnchorFrameType/EventToastParentFrame/
-- EventToastStrata; this builds the Config shape KE:ApplyFramePosition
-- expects out of those, mirroring HealerMana's GetActiveAnchorConfig
-- (Modules/Healer/HealerMana.lua).
function AF:ApplyEventToastPosition()
    if not (self.toastHolder and self.db and self.db.EventToastPosition) then return end
    KE:ApplyFramePosition(self.toastHolder, self.db.EventToastPosition, {
        anchorFrameType = self.db.EventToastAnchorFrameType,
        ParentFrame = self.db.EventToastParentFrame,
        Strata = self.db.EventToastStrata,
    })
end

-- Replace-mode LootRoll owns the BonusRollFrame PROMPT (it anchors it to its
-- own bar stack from the same GroupLootContainer_Update post-hook), so this
-- module stands aside for it in that mode and the two hooks' install order
-- never matters. The two winnings toasts are this module's in every mode.
-- Read the RUNNING enabled state, as LootRoll's own anchor does: a profile
-- switch rebinds its db but defers the enable change to /reload.
local function LootRollReplacesRolls()
    local LR = KitnEssentials.GetModule and KitnEssentials:GetModule("LootRoll", true)
    return LR and LR.IsEnabled and LR:IsEnabled() and LR.db and LR.db.Replace and true or false
end

-- Trading Post (PerksProgram) support: when Blizzard re-bases the alert stack
-- onto the PerksProgram footer, follow it (and grow up over it). AlertFrame
-- and PerksProgramFrame are absent from .luacheckrc's read_globals, so both
-- are reached through _G rather than widened onto the allowlist.
local function GetPerksAnchor()
    local perks = _G.PerksProgramFrame
    local footer = perks and perks.FooterFrame
    local af = _G.AlertFrame
    if footer and af and af.baseAnchorFrame == footer.RotateButtonContainer then
        return footer
    end
end

-- Pure grow-direction decision, extracted out of PostAlertMove so it is
-- directly unit-testable. centreY can be nil pre-layout (a frame not yet measured
-- reports 1x1/nil, feedback_prelayout_measurement.md); screenTop can be nil
-- for the same reason. Either nil fails safe to "grow down". hasPerksAnchor
-- always wins: Trading Post re-basing always grows up.
local function ShouldGrowUp(centreY, screenTop, hasPerksAnchor)
    if hasPerksAnchor then return true end
    if not centreY or not screenTop then return false end
    return centreY < (screenTop * 0.5)
end

function AF:PostAlertMove()
    if not self.holder then return end
    local af = _G.AlertFrame
    if not af then return end

    local perksAnchor = GetPerksAnchor()
    local _, centreY = self.holder:GetCenter()
    local screenTop = UIParent and UIParent:GetTop()
    local growUp = ShouldGrowUp(centreY, screenTop, perksAnchor ~= nil)

    -- Edit Mode has to know when the stack stops being ours to move, and this
    -- is the only place that decision is made. Refresh only on a change: this
    -- runs once per alert, and an alert-heavy moment would otherwise repaint
    -- every overlay each time.
    local rebased = perksAnchor and true or false
    if rebased ~= self.rebasedToPerks then
        self.rebasedToPerks = rebased
        if KE.EditMode then KE.EditMode:RefreshLiveState() end
    end

    if growUp then
        POSITION, POINT, X_OFFSET, Y_OFFSET = "BOTTOM", "TOP", 0, 5
        BASE_YOFFSET = perksAnchor and 40 or 0
    else
        POSITION, POINT, X_OFFSET, Y_OFFSET, BASE_YOFFSET = "TOP", "BOTTOM", 0, -5, 0
    end

    af:ClearAllPoints()
    af:SetAllPoints(perksAnchor or self.holder)

    self:PositionBonusRollToasts()
end

-- GroupLootContainer is left where Blizzard's managed layout parks it. It
-- draws nothing, and a managed frame's anchors belong to that layout pass: a
-- competing SetPoint provokes a relayout, which provokes the SetPoint, and a
-- long-lived frame in the container (the bonus-roll prompt) visibly bounces
-- between the two spots. The frames it holds are placed instead; they are
-- ordinary children, so their anchors are ours to write. GroupLootContainer
-- is absent from .luacheckrc's read_globals, so it is reached through _G.
local BONUS_ROLL_FRAMES = { "BonusRollFrame", "BonusRollLootWonFrame", "BonusRollMoneyWonFrame" }

-- The only two frames GroupLootFrame.lua hands to AddAlertFrame directly. Every
-- other alert arrives via AlertFrameQueueMixin:ShowAlert, which runs
-- UpdateAnchors first, so it is already chained by the time our hook sees it --
-- re-anchoring one of those onto the holder drops it out of the stack and it
-- renders on top of the alert before it. A name added here must also be in
-- BONUS_ROLL_FRAMES, which is what places it.
local DIRECT_ALERT_FRAMES = {
    BonusRollLootWonFrame = true,
    BonusRollMoneyWonFrame = true,
}

local function IsDirectAlertFrame(frame)
    if not (frame and frame.GetName) then return false end
    return DIRECT_ALERT_FRAMES[frame:GetName()] == true
end

local function PlacesBonusRollFrame(name, lootRollReplaces)
    return not (name == "BonusRollFrame" and lootRollReplaces)
end

-- Weak-keyed dedupe rather than a field on Blizzard's frame.
local showHooked = setmetatable({}, { __mode = "k" })

-- Blizzard anchors these to the container inside GroupLootContainer_Update,
-- and a winnings toast stays in rollFrames for its whole life
-- (GroupLootContainer_ReplaceFrame puts it there before AddAlertFrame sees
-- it), so a frame placed once is dragged back on the next update. Running
-- from the post-hook makes this the last write in the same execution.
-- GroupLootContainer_AddFrame and _ReplaceFrame run Update BEFORE Show, so
-- the pass that first sees a new frame sees it hidden; the OnShow hook
-- closes that gap. bonusStackTop is what the alert chain continues from.
-- LootRoll's legacy stacker yields these frames while this module is enabled
-- (Modules/Skinning/LootRoll.lua), so they have one writer.
function AF:PositionBonusRollToasts()
    if not self.holder then return end
    local replaces = LootRollReplacesRolls()
    local base = GetPerksAnchor() or self.holder
    local anchor = base
    for _, name in ipairs(BONUS_ROLL_FRAMES) do
        local f = _G[name]
        if f and f.ClearAllPoints then
            if not showHooked[f] and f.HookScript then
                showHooked[f] = true
                f:HookScript("OnShow", function()
                    if AF:IsEnabled() then AF:PositionBonusRollToasts() end
                end)
            end
            if f:IsShown() and PlacesBonusRollFrame(name, replaces) then
                f:ClearAllPoints()
                f:SetPoint(POSITION, anchor, POINT, X_OFFSET, Y_OFFSET)
                anchor = f
            end
        end
    end
    -- Alerts already on screen sit where the last UpdateAnchors left them,
    -- so a frame placed under them overlaps until the chain is walked again.
    local top = anchor ~= base and anchor or nil
    if top ~= self.bonusStackTop then
        self.bonusStackTop = top
        local af = _G.AlertFrame
        if af and af.UpdateAnchors then af:UpdateAnchors() end
    end
end

---------------------------------------------------------------------------------
-- The three AdjustAnchors replacements (self = subsystem).
---------------------------------------------------------------------------------
local function AdjustQueuedAnchors(sys, relativeAlert)
    local base = BASE_YOFFSET
    for alert in sys.alertFramePool:EnumerateActive() do
        alert:ClearAllPoints()
        alert:SetPoint(POSITION, relativeAlert, POINT, X_OFFSET, base + Y_OFFSET)
        relativeAlert = alert
        if base ~= 0 then base = 0 end
    end
    return relativeAlert
end

local function AdjustAnchors(sys, relativeAlert)
    local alert = sys.alertFrame
    if alert:IsShown() then
        alert:ClearAllPoints()
        alert:SetPoint(POSITION, relativeAlert, POINT, X_OFFSET, Y_OFFSET)
        return alert
    end
    return relativeAlert
end

local function AdjustAnchorsNonAlert(sys, relativeAnchor)
    local anchor = sys.anchorFrame
    if anchor:IsShown() then
        anchor:ClearAllPoints()
        anchor:SetPoint(POSITION, relativeAnchor, POINT, X_OFFSET, Y_OFFSET)
        return anchor
    end
    return relativeAnchor
end

-- Blizzard has two kinds of anchorFrame subsystem and the tests below cannot
-- tell them apart. The auto-anchored kind positions itself among the other
-- alerts and is ours to place. The externally anchored kind exists only to let
-- the chain pass THROUGH a frame something else owns -- its own AdjustAnchors
-- moves nothing and just returns the frame. TalkingHeadFrame is the second
-- kind, and Edit Mode is the something else, so replacing its AdjustAnchors
-- drags it onto the toast stack every alert pass and overwrites the position
-- the player set. Matched on the mixin's own function rather than a name list,
-- so anything Blizzard registers that way later is covered without an edit.
local function IsExternallyAnchored(sys)
    local mixin = _G.AlertFrameExternallyAnchoredMixin
    return mixin ~= nil and sys.AdjustAnchors == mixin.AdjustAnchors
end

-- GroupLootContainer is the one externally anchored subsystem that is
-- replaced. Blizzard's version returns the container whenever it is shown and
-- every alert behind it in the chain stacks from there -- the bottom of the
-- screen, now that the container is left to the managed layout. The frames
-- it holds sit on the alert stack instead, so the chain continues from the
-- top of those; when none is placed it passes through untouched.
local function AdjustAnchorsThroughBonusStack(_, relativeAlert)
    local top = AF.bonusStackTop
    if top and top:IsShown() then return top end
    return relativeAlert
end

local function AdjustSubSystem(sys)
    if IsExternallyAnchored(sys) then
        if sys.anchorFrame ~= nil and sys.anchorFrame == _G.GroupLootContainer then
            sys.AdjustAnchors = AdjustAnchorsThroughBonusStack
        end
        return
    end

    if sys.alertFramePool then
        sys.AdjustAnchors = AdjustQueuedAnchors
    elseif not sys.anchorFrame then
        sys.AdjustAnchors = AdjustAnchors
    else
        sys.AdjustAnchors = AdjustAnchorsNonAlert
    end
end

function AF:InstallHooks()
    if self.hooked then return end
    local af = _G.AlertFrame
    if not af then return end
    self.hooked = true

    if af.alertFrameSubSystems then
        for _, sys in ipairs(af.alertFrameSubSystems) do
            AdjustSubSystem(sys)
        end
    end
    -- Catch systems registered later (Blizzard LoD + other addons).
    hooksecurefunc(af, "AddAlertFrameSubSystem", function(_, sys)
        AdjustSubSystem(sys)
    end)

    local function Reroot()
        if AF:IsEnabled() then AF:PostAlertMove() end
    end
    hooksecurefunc(af, "UpdateAnchors", Reroot)
    if af.SetBaseAnchorFrame then hooksecurefunc(af, "SetBaseAnchorFrame", Reroot) end
    if af.ResetBaseAnchorFrame then hooksecurefunc(af, "ResetBaseAnchorFrame", Reroot) end

    local glc = _G.GroupLootContainer
    if glc then glc:EnableMouse(false) end
    -- Blizzard has just re-anchored everything in rollFrames to the container;
    -- pick the bonus-roll frames back up in the same execution.
    if type(_G.GroupLootContainer_Update) == "function" then
        hooksecurefunc("GroupLootContainer_Update", function()
            if AF:IsEnabled() then AF:PositionBonusRollToasts() end
        end)
    end

    -- BonusRollLootWonFrame / BonusRollMoneyWonFrame are added through
    -- AddAlertFrame rather than as subsystems, so AdjustSubSystem never
    -- sees them. AddAlertFrame is the shared entry point for every alert, so
    -- the filter is what keeps this off the ones a subsystem already placed.
    hooksecurefunc(af, "AddAlertFrame", function(_, frame)
        if not (AF:IsEnabled() and AF.holder and frame and frame.ClearAllPoints) then return end
        if not IsDirectAlertFrame(frame) then return end
        AF:PostAlertMove()
        AF:PositionBonusRollToasts()
    end)
end

---------------------------------------------------------------------------------
-- Event Toasts (recipe/level-up banners)
---------------------------------------------------------------------------------
-- EventToastManagerFrame is NOT UIParent-managed, but Blizzard's own
-- UpdateAnchor(customOffsetX, customOffsetY) re-anchors it per toast
-- (ClearAllPoints + SetPoint TOP), so a one-time move would be reset.
-- Post-hook it: after their anchor pass, re-root onto our holder. Gated on
-- MoveEventToasts (default off = untouched).
function AF:InstallEventToastHook()
    if self.toastHookInstalled then return end
    local etm = _G.EventToastManagerFrame
    if not etm then return end
    self.toastHookInstalled = true
    hooksecurefunc(etm, "UpdateAnchor", function(frame)
        if not (AF:IsEnabled() and AF.db and AF.db.MoveEventToasts and AF.toastHolder) then return end
        frame:ClearAllPoints()
        frame:SetPoint("TOP", AF.toastHolder, "TOP", 0, 0)
    end)
    -- Re-root anything already positioned this session.
    if AF.db and AF.db.MoveEventToasts and etm.UpdateAnchor then
        etm:UpdateAnchor()
    end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function AF:RegisterEditMode()
    if not KE.EditMode or self.editModeRegistered then return end
    self.editModeRegistered = true
    KE.EditMode:RegisterElement({
        key = "AlertFrames",
        module = self,
        -- While the stack is rebased onto the Perks Program footer it is not
        -- ours to move.
        isEligible = function() return not self.rebasedToPerks end,
        displayName = "Alerts / Loot Toasts",
        frame = self.holder,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            self.db.Position.AnchorFrom = pos.AnchorFrom
            self.db.Position.AnchorTo = pos.AnchorTo
            self.db.Position.XOffset = pos.XOffset
            self.db.Position.YOffset = pos.YOffset
            self:ApplyPosition()
        end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
        end,
        -- guiPath is a SIDEBAR ITEM ID, and this module has no sidebar row of
        -- its own -- its config cards live on the UI Widgets tab instead, so
        -- route through the page that hosts them. guiTab is a NESTED id;
        -- GUI/GUIMain/GUI-TabbedContent.lua translates it to its owning tab.
        guiPath = "SkinBlizzardFrames",
        guiTab = "SkinBlizzardFramesWidgets",
    })
    KE.EditMode:RegisterElement({
        key = "EventToasts",
        module = self,
        -- The holder exists whether or not the toggle is on, but nothing is
        -- routed into it until it is.
        isEligible = function() return self.db.MoveEventToasts == true end,
        displayName = "Event Toasts (Recipe / Level Banners)",
        frame = self.toastHolder,
        getPosition = function() return self.db.EventToastPosition end,
        setPosition = function(pos)
            self.db.EventToastPosition.AnchorFrom = pos.AnchorFrom
            self.db.EventToastPosition.AnchorTo = pos.AnchorTo
            self.db.EventToastPosition.XOffset = pos.XOffset
            self.db.EventToastPosition.YOffset = pos.YOffset
            self:ApplyEventToastPosition()
        end,
        -- Its card deliberately does not share the alert stack's anchor keys,
        -- so the drag has to resolve the parent from its own roots.
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.EventToastAnchorFrameType,
                self.db.EventToastParentFrame)
        end,
        -- Same page as the AlertFrames element above -- see its comment.
        guiPath = "SkinBlizzardFrames",
        guiTab = "SkinBlizzardFramesWidgets",
    })
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function AF:OnEnable()
    self:UpdateDB()
    if Suppressed() then return end
    if not self.holder then
        self.holder = CreateFrame("Frame", "KE_AlertFrameHolder", UIParent)
        self.holder:SetSize(180, 20)
    end
    if not self.toastHolder then
        self.toastHolder = CreateFrame("Frame", "KE_EventToastHolder", UIParent)
        self.toastHolder:SetSize(418, 72) -- EventToast fixedWidth x minimumHeight
    end
    self:InstallHooks()
    self:InstallEventToastHook()
    self:ApplyPosition()
    self:ApplyEventToastPosition()
    self:RegisterEditMode()
end

-- No OnDisable: the AdjustAnchors replacements and hooksecurefunc hooks
-- cannot be undone (see the header taint note). Turning the module off in
-- the GUI leaves them installed but inert-guarded by AF:IsEnabled() checks
-- everywhere except the AdjustAnchors replacements themselves, which is why
-- the GUI page requires a reload to fully hand the toasts back to Blizzard.

function AF:ApplySettings()
    self:UpdateDB()
    if Suppressed() then
        if self:IsEnabled() then self:Disable() end
        return
    end
    if self:IsEnabled() then
        self:ApplyPosition()
        self:ApplyEventToastPosition()
        self:InstallEventToastHook()
    end
end
