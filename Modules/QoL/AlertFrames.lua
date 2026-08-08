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
            if AF:IsEnabled() then AF:PositionGroupLootContainer() end
        end)
    end
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
        -- guiPath is a SIDEBAR ITEM ID, and this module has no sidebar row
        -- of its own -- its config cards live on the UI Widgets tab instead.
        -- Open Settings was silently falling through to "just open the GUI".
        -- Route through the tab that now hosts these cards (KE's sidebar
        -- id: GUI/GUIMain/GUI-MainFrame.lua). guiTab seeds
        -- GUIFrame.tabbedPageState so Open Settings lands on the right
        -- subtab (Core/EditMode.lua) -- same fix as
        -- Modules/Skinning/LootRoll.lua.
        guiPath = "SkinBlizzardFrames",
        guiTab = "SkinBlizzardFramesWidgets",
    })
    KE.EditMode:RegisterElement({
        key = "EventToasts",
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
