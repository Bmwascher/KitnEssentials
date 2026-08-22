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
-- own bar stack); the winnings toasts are nobody's either way.
local function LootRollReplacesRolls()
    local LR = KitnEssentials.GetModule and KitnEssentials:GetModule("LootRoll", true)
    return LR and LR.db and LR.db.Enabled and LR.db.Replace and true or false
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

    self:PositionGroupLootContainer()
end

-- The container renders wherever its LAST anchors point, so it only snaps
-- into the stack when AlertFrame:UpdateAnchors next runs. GroupLootContainer
-- is absent from .luacheckrc's read_globals, so it is reached through _G.
-- Nothing to yield to any more: LootRoll used to move this container and now
-- moves the roll FRAMES off it instead (Modules/Skinning/LootRoll.lua), so
-- the two no longer compete.
function AF:PositionGroupLootContainer()
    local glc = _G.GroupLootContainer
    if not (glc and self.holder) then return end
    local perksAnchor = GetPerksAnchor()
    glc:ClearAllPoints()
    glc:SetPoint(POSITION, perksAnchor or self.holder, POINT, X_OFFSET, Y_OFFSET)
end

local BONUS_ROLL_FRAMES = { "BonusRollFrame", "BonusRollLootWonFrame", "BonusRollMoneyWonFrame" }

-- The only two frames GroupLootFrame.lua hands to AddAlertFrame directly. Every
-- other alert arrives via AlertFrameQueueMixin:ShowAlert, which runs
-- UpdateAnchors first, so it is already chained by the time our hook sees it --
-- re-anchoring one of those onto the holder drops it out of the stack and it
-- renders on top of the alert before it.
local DIRECT_ALERT_FRAMES = {
    BonusRollLootWonFrame = true,
    BonusRollMoneyWonFrame = true,
}

local function IsDirectAlertFrame(frame)
    if not (frame and frame.GetName) then return false end
    return DIRECT_ALERT_FRAMES[frame:GetName()] == true
end

-- Only a frame the container is NOT holding needs placing: anything in
-- rollFrames is already stacked by the game relative to the container, which
-- PositionGroupLootContainer has just placed. Re-anchoring those piles them
-- all onto one spot.
function AF:PositionBonusRollToasts()
    if not self.holder then return end
    local glc = _G.GroupLootContainer
    local held = {}
    if glc and type(glc.rollFrames) == "table" then
        for _, f in pairs(glc.rollFrames) do held[f] = true end
    end
    local anchor = GetPerksAnchor() or self.holder
    if glc and glc:IsShown() then anchor = glc end
    for _, name in ipairs(BONUS_ROLL_FRAMES) do
        local f = _G[name]
        if f and f:IsShown() and not held[f] and f.ClearAllPoints
           and not (name == "BonusRollFrame" and LootRollReplacesRolls()) then
            f:ClearAllPoints()
            f:SetPoint(POSITION, anchor, POINT, X_OFFSET, Y_OFFSET)
            anchor = f
        end
    end
end

-- Re-apply after Blizzard's managed layout has settled. Coalesced; the
-- layout marks itself dirty and can settle on EITHER of the next two
-- frames, so both passes place -- one placement after two ticks would
-- leave a first-frame settle unanswered.
function AF:ReassertContainer()
    if self.reassertPending then return end
    self.reassertPending = true

    local frames = 0
    local function settle()
        frames = frames + 1
        if self:IsEnabled() then
            self:PositionGroupLootContainer()
            self:PositionBonusRollToasts()
        end
        if frames < 2 then
            C_Timer.After(0, settle)
        else
            self.reassertPending = false
        end
    end
    C_Timer.After(0, settle)
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

local function AdjustSubSystem(sys)
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

    -- GroupLootContainer stays exactly as Blizzard manages it. LootRoll
    -- moves the roll FRAMES off it instead of moving the container
    -- (Modules/Skinning/LootRoll.lua), so nothing here needs to reparent it.
    local glc = _G.GroupLootContainer
    if glc then glc:EnableMouse(false) end
    -- Place the container in the SAME execution that shows it.
    if type(_G.GroupLootContainer_Update) == "function" then
        hooksecurefunc("GroupLootContainer_Update", function()
            if not AF:IsEnabled() then return end
            AF:PositionGroupLootContainer()
            AF:PositionBonusRollToasts()
            AF:ReassertContainer()
        end)
    end
    -- Blizzard's managed layout settles a frame or two after the update
    -- above runs, so also re-assert on the container's own OnShow.
    if glc and not self.glcShowHooked then
        self.glcShowHooked = true
        glc:HookScript("OnShow", function() AF:ReassertContainer() end)
    end

    -- BonusRollLootWonFrame / BonusRollMoneyWonFrame are added through
    -- AddAlertFrame rather than as subsystems, so AdjustSubSystem never
    -- sees them; place them directly when Blizzard adds them. AddAlertFrame is
    -- the shared entry point for every alert, so the filter is what keeps this
    -- off the ones a subsystem already placed.
    hooksecurefunc(af, "AddAlertFrame", function(_, frame)
        if not (AF:IsEnabled() and AF.holder and frame and frame.ClearAllPoints) then return end
        if not IsDirectAlertFrame(frame) then return end
        AF:PostAlertMove()
        frame:ClearAllPoints()
        frame:SetPoint(POSITION, GetPerksAnchor() or AF.holder, POINT, X_OFFSET, Y_OFFSET)
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
