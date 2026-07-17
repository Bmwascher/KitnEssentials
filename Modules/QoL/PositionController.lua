-- ╔══════════════════════════════════════════════════════════╗
-- ║  PositionController.lua                                  ║
-- ║  Module: Position Controller                             ║
-- ║  Purpose: Two-part frame positioning module:             ║
-- ║   1. Unit Frame Anchoring — anchors ElvUI Player/Target/ ║
-- ║      Focus/Pet frames to other frames, with Essential vs ║
-- ║      Utility cooldown row collision offset.              ║
-- ║      Healer-spec auto no-op. ElvUI required.             ║
-- ║   2. CDM Racials Anchor — hooks Ayije CDM's              ║
-- ║      AnchorToPlayerFrame to reposition CDM_Racials       ║
-- ║      with custom offsets + pet-bar Y nudge.              ║
-- ║      Works with ElvUI (ElvUF_Pet) and UUF (UUF_Pet).     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class PositionController: AceModule, AceEvent-3.0
local PC = KitnEssentials:NewModule("PositionController", "AceEvent-3.0")

-- Profile state-sync opt-out: the CDM Racials half runs independent of the
-- master db.Enabled toggle (see OnInitialize) — ProfileManager must never
-- auto-disable this module on profile switch.
PC.keSelfManagedEnable = true

local _G = _G
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local GetSpecialization = GetSpecialization
local GetSpecializationRole = GetSpecializationRole
local wipe = wipe

local DEFAULT_CDM_PET_OFFSET = -15

---------------------------------------------------------------------------------
-- Capability detection
---------------------------------------------------------------------------------

local function HasElvUI()
    return _G.ElvUI ~= nil
end

-- True when the standalone ElvUI_Anchor addon is loaded. That addon performs
-- the same unit-frame anchoring this module provides, so when it's present
-- we yield to it and skip our top half entirely (the CDM Racials half below
-- continues to run regardless). Avoids two layers fighting over the same
-- SetPoint calls and ElvUI mover state.
local function HasElvUIAnchor()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("ElvUI_Anchor")
    end
    return _G.IsAddOnLoaded and _G.IsAddOnLoaded("ElvUI_Anchor")
end

-- Unit frame anchoring is ElvUI-only. The CDM Racials portion below also
-- supports UUF, hence the separate pet-frame helper.
local function IsHealerSpec()
    local specIndex = GetSpecialization()
    if not specIndex then return false end
    return GetSpecializationRole(specIndex) == "HEALER"
end

-- Returns true when unit-frame anchoring should no-op due to user being on a
-- healer spec AND the IgnoreHealerSpec gate being active. Default: gate ON.
local function IsHealerGated(db)
    if not db then return false end
    if db.IgnoreHealerSpec == false then return false end  -- explicit opt-out
    return IsHealerSpec()
end

local function GetPetFrame()
    return _G.ElvUF_Pet or _G.UUF_Pet
end

---------------------------------------------------------------------------------
-- Cooldown manager provider detection
---------------------------------------------------------------------------------
local PROVIDER_SCM   = "scm"
local PROVIDER_AYIJE = "ayije"

local PROVIDER_PARENT_FRAME = {
    [PROVIDER_SCM]   = "SCM_GroupAnchor_1",
    [PROVIDER_AYIJE] = "EssentialCooldownViewer_CDM_Container",
}

local function DetectProvider()
    if _G.SCM_GroupAnchor_1 then return PROVIDER_SCM end
    if _G.Ayije_CDM then return PROVIDER_AYIJE end
    return nil
end

---------------------------------------------------------------------------------
-- Frame reference cache (Unit Frame Anchoring)
---------------------------------------------------------------------------------
local cache = {
    essential = nil,
    utility   = nil,
    frames = {
        PlayerFrame = { uf = nil, mover = nil },
        TargetFrame = { uf = nil, mover = nil },
        FocusFrame  = { uf = nil, mover = nil },
        PetFrame    = { uf = nil, mover = nil },
    },
}

local function CacheFrames()
    cache.essential = _G.EssentialCooldownViewer
    cache.utility   = _G.UtilityCooldownViewer

    local f = cache.frames

    f.PlayerFrame.uf    = _G.ElvUF_Player
    f.PlayerFrame.mover = _G.ElvUF_PlayerMover

    f.TargetFrame.uf    = _G.ElvUF_Target
    f.TargetFrame.mover = _G.ElvUF_TargetMover

    f.FocusFrame.uf     = _G.ElvUF_Focus
    f.FocusFrame.mover  = _G.ElvUF_FocusMover

    f.PetFrame.uf       = _G.ElvUF_Pet
    f.PetFrame.mover    = _G.ElvUF_PetMover
end

---------------------------------------------------------------------------------
-- Cooldown viewer collision offset (Unit Frame Anchoring)
--
-- When anchored to the Essential cooldown row, nudge the unit frame further
-- out if the Utility row beneath it is wider, to avoid overlap. Player/Focus
-- nudge left, Target nudges right. Pet has no horizontal collision concern.
---------------------------------------------------------------------------------
local ESSENTIAL_PARENTS = {
    ["EssentialCooldownViewer"]               = true,
    ["EssentialCooldownViewer_CDM_Container"] = true,
    ["SCM_GroupAnchor_1"]                     = true,
}

local function ComputeAyijeCollision(featureKey, baseX)
    local essential = cache.essential
    local utility   = cache.utility
    if not (essential and utility) then return baseX end

    local eWidth = essential:GetWidth() or 0
    local uWidth = utility:GetWidth() or 0
    if uWidth <= eWidth then return baseX end

    local extra = (uWidth - eWidth) / 2
    if featureKey == "PlayerFrame" or featureKey == "FocusFrame" then
        return baseX - extra
    elseif featureKey == "TargetFrame" then
        return baseX + extra
    end
    return baseX
end

local function ComputeSCMCollision(featureKey, baseX)
    local a1 = _G.SCM_GroupAnchor_1
    local a2 = _G.SCM_GroupAnchor_2
    if not (a1 and a1.GetWidth) then return baseX end

    local w1 = a1:GetWidth() or 0
    local w2 = (a2 and a2.GetWidth and a2:IsShown() and a2:GetWidth()) or 0
    local widest = math.max(w1, w2)
    if widest <= 0 then return baseX end

    -- A1's own edges are half of w1 from center each side. To clear the
    -- widest bar instead, push out by (widest - w1)/2 extra per side.
    local extra = (widest - w1) / 2
    local gap = math.abs(baseX)

    if featureKey == "PlayerFrame" or featureKey == "FocusFrame" then
        return -(gap + extra)
    elseif featureKey == "TargetFrame" then
        return (gap + extra)
    end
    return baseX
end

local function GetCollisionXOffset(featureKey, baseX, parentName)
    if not ESSENTIAL_PARENTS[parentName] then return baseX end
    if parentName == "SCM_GroupAnchor_1" then
        return ComputeSCMCollision(featureKey, baseX)
    else
        return ComputeAyijeCollision(featureKey, baseX)
    end
end

---------------------------------------------------------------------------------
-- Missing-parent warning cache
---------------------------------------------------------------------------------
local warnedMissingParent = {}

local function WarnMissingParent(featureKey, parentName)
    local key = featureKey .. "\0" .. parentName
    if warnedMissingParent[key] then return end
    warnedMissingParent[key] = true
    KE:Print("Position Controller: parent frame '" .. parentName ..
             "' not found, " .. featureKey .. " anchor skipped")
end

---------------------------------------------------------------------------------
-- ElvUI restore-original-position helper
---------------------------------------------------------------------------------
local function RestoreOriginalAnchor(featureKey)
    local refs = cache.frames[featureKey]
    if not refs or not refs.uf or not refs.mover then return end

    local elvui = _G.ElvUI
    if not elvui then return end
    local E = elvui[1]
    if not E or not E.SetMoverPoints then return end

    local moverName = refs.mover:GetName()
    if not moverName then return end

    E:SetMoverPoints(moverName, refs.uf)
end

local function RestoreAllAnchors()
    RestoreOriginalAnchor("PlayerFrame")
    RestoreOriginalAnchor("TargetFrame")
    RestoreOriginalAnchor("FocusFrame")
    RestoreOriginalAnchor("PetFrame")
end

---------------------------------------------------------------------------------
-- Resolve parent frame per feature
--
-- Player/Target are provider-resolved (auto-detect SCM or Ayije, ignore saved
-- ParentFrame). Focus/Pet keep their user-configured ParentFrame.
---------------------------------------------------------------------------------
local function ResolveParentFrameName(featureKey, subDB)
    if featureKey == "PlayerFrame" or featureKey == "TargetFrame" then
        local provider = DetectProvider()
        return provider and PROVIDER_PARENT_FRAME[provider] or nil
    end
    return subDB.ParentFrame
end

---------------------------------------------------------------------------------
-- ElvUI mover-system write helper
--
-- Direct :SetPoint calls on a unit frame whose mover has a saved position can
-- be reverted by ElvUI on /reload or zone change. The correct path is to write
-- the position string into E.db.movers[name] and call E:SetMoverPoints(name) so
-- ElvUI persists it as the user's saved position.
---------------------------------------------------------------------------------
local function GetE()
    local elvui = _G.ElvUI
    if not elvui then return nil end
    local E = elvui[1]
    if not E or not E.SetMoverPoints then return nil end
    return E
end

local function SetMoverPosition(E, moverName, point, relativeTo, relPoint, x, y)
    if not (E and moverName and E.db and E.db.movers) then return end
    E.db.movers[moverName] = string.format("%s,%s,%s,%d,%d",
        point, relativeTo, relPoint, math.floor(x + 0.5), math.floor(y + 0.5))
    E:SetMoverPoints(moverName)
end

---------------------------------------------------------------------------------
-- Apply a single feature's position to its unit frame + mover
---------------------------------------------------------------------------------
local function ApplyFeature(featureKey, subDB)
    local refs = cache.frames[featureKey]
    if not refs or not refs.uf then return end

    if not subDB or not subDB.Enabled then
        RestoreOriginalAnchor(featureKey)
        return
    end

    local parent, parentName
    if featureKey == "PlayerFrame" or featureKey == "TargetFrame" then
        parentName = ResolveParentFrameName(featureKey, subDB)
        parent = parentName and _G[parentName]
        if not parent then
            if parentName then WarnMissingParent(featureKey, parentName) end
            return
        end
    elseif subDB.anchorFrameType == "SELECTFRAME" then
        parentName = subDB.ParentFrame
        parent = parentName and _G[parentName]
        if not parent then
            if parentName then WarnMissingParent(featureKey, parentName) end
            return
        end
    else
        parent = _G.UIParent
        parentName = "UIParent"
    end

    local pos = subDB.Position
    if not pos then return end

    local fromPoint = pos.AnchorFrom or "CENTER"
    local toPoint   = pos.AnchorTo   or "CENTER"
    local x         = pos.XOffset    or 0
    local y         = pos.YOffset    or 0

    x = GetCollisionXOffset(featureKey, x, parentName)

    local E = GetE()
    local mover = refs.mover
    local moverName = mover and mover:GetName()

    if E and moverName then
        SetMoverPosition(E, moverName, fromPoint, parentName, toPoint, x, y)
    else
        refs.uf:ClearAllPoints()
        refs.uf:SetPoint(fromPoint, parent, toPoint, x, y)
        if mover then
            mover:ClearAllPoints()
            mover:SetPoint(fromPoint, parent, toPoint, x, y)
        end
    end
end

---------------------------------------------------------------------------------
-- Main layout pass + debounce
---------------------------------------------------------------------------------
local providerWarned = false

function PC:ApplyLayout()
    if InCombatLockdown() then return end
    if not HasElvUI() then return end
    if HasElvUIAnchor() then return end
    local db = self.db
    if not db or not db.Enabled then return end
    if IsHealerGated(db) then return end

    local provider = DetectProvider()
    local pAny = (db.PlayerFrame and db.PlayerFrame.Enabled) or
                 (db.TargetFrame and db.TargetFrame.Enabled)
    if not provider and pAny and not providerWarned then
        providerWarned = true
        KE:Print("Position Controller: Player/Target anchoring requires SkironCooldownManager or Ayije_CDM.")
    elseif provider then
        providerWarned = false
    end

    if provider then
        ApplyFeature("PlayerFrame", db.PlayerFrame)
        ApplyFeature("TargetFrame", db.TargetFrame)
    end
    ApplyFeature("FocusFrame", db.FocusFrame)
    ApplyFeature("PetFrame",   db.PetFrame)
end

local pending = false

function PC:QueueApply()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        PC:ApplyLayout()
    end)
end

---------------------------------------------------------------------------------
-- Hook cooldown viewer size changes
---------------------------------------------------------------------------------
local function OnViewerResized()
    PC:QueueApply()
end

function PC:HookViewerSizes()
    -- SCM provider frames
    local a1 = _G.SCM_GroupAnchor_1
    local a2 = _G.SCM_GroupAnchor_2

    if a1 and not a1._kePositionHooked then
        a1:HookScript("OnSizeChanged", OnViewerResized)
        a1:HookScript("OnShow",        OnViewerResized)
        a1:HookScript("OnHide",        OnViewerResized)
        a1._kePositionHooked = true
    end
    if a2 and not a2._kePositionHooked then
        a2:HookScript("OnSizeChanged", OnViewerResized)
        a2:HookScript("OnShow",        OnViewerResized)
        a2:HookScript("OnHide",        OnViewerResized)
        a2._kePositionHooked = true
    end

    -- Ayije provider frames (Blizzard cooldown viewers).
    if _G.Ayije_CDM then
        local essential = cache.essential
        local utility   = cache.utility
        if essential and not essential._kePositionHooked then
            essential:HookScript("OnSizeChanged", OnViewerResized)
            essential._kePositionHooked = true
        end
        if utility and not utility._kePositionHooked then
            utility:HookScript("OnSizeChanged", OnViewerResized)
            utility._kePositionHooked = true
        end
    end
end

function PC:ScheduleSettleReapply()
    -- Re-entry guard: rapid PLAYER_ENTERING_WORLD fires (instance hops,
    -- loading screens) would otherwise stack four C_Timer.After callbacks
    -- per fire. One in-flight settle window at a time is enough.
    if self._settleScheduled then return end
    self._settleScheduled = true
    for _, delay in ipairs({ 0.1, 0.5, 1.0, 2.0 }) do
        C_Timer.After(delay, function()
            PC:HookViewerSizes()
            PC:QueueApply()
        end)
    end
    -- Clear the gate after the longest scheduled callback would have fired.
    C_Timer.After(2.1, function() PC._settleScheduled = false end)
end

---------------------------------------------------------------------------------
-- CDM Racials hook (bottom half — works with ElvUI and UUF)
---------------------------------------------------------------------------------
local cdmHooked = false

function PC:TryInstallCDMHook()
    if cdmHooked then return true end

    local CDM = _G.Ayije_CDM
    if not CDM or not CDM.AnchorToPlayerFrame then return false end

    local originalAnchor = CDM.AnchorToPlayerFrame

    CDM.AnchorToPlayerFrame = function(container, anchorPoint, offsetX, offsetY,
                                       moduleName, forceRefresh, containerAnchor)
        if container and container:GetName() == "CDM_RacialsContainer" then
            local db = PC.db
            -- CDM Racials is independent of the master Position Controller toggle.
            -- It only checks its own enable flag.
            if db and db.CDMRacials and db.CDMRacials.Enabled then
                local cdm = db.CDMRacials
                if cdm.AnchorTo and cdm.AnchorTo ~= "" then
                    anchorPoint = cdm.AnchorTo
                end
                if cdm.AnchorFrom and cdm.AnchorFrom ~= "" then
                    containerAnchor = cdm.AnchorFrom
                end
                offsetX = (cdm.XOffset or 0) + (offsetX or 0)
                offsetY = (cdm.YOffset or 0) + (offsetY or 0)

                local petFrame = GetPetFrame()
                if petFrame and petFrame:IsShown() then
                    offsetY = offsetY + (cdm.PetBarOffset or DEFAULT_CDM_PET_OFFSET)
                end
            end
        end
        return originalAnchor(container, anchorPoint, offsetX, offsetY,
                              moduleName, forceRefresh, containerAnchor)
    end

    cdmHooked = true
    return true
end

local function ForceRacialsReanchor()
    local CDM = _G.Ayije_CDM
    if not CDM or not CDM.InvalidateTrackerAnchorCache or not CDM.ScheduleTrackerPositionRefresh then
        return
    end
    local container = _G.CDM_RacialsContainer
    if not container then return end
    CDM.InvalidateTrackerAnchorCache(container)
    CDM.ScheduleTrackerPositionRefresh()
end

local petWatcherAttached = false

function PC:AttachPetWatcher()
    if petWatcherAttached then return end
    local petFrame = GetPetFrame()
    if not petFrame then return end

    petFrame:HookScript("OnShow", ForceRacialsReanchor)
    petFrame:HookScript("OnHide", ForceRacialsReanchor)
    petWatcherAttached = true
end

---------------------------------------------------------------------------------
-- One-time migration from RacialsAnchor → PositionController.CDMRacials
---------------------------------------------------------------------------------
local function MigrateFromRacialsAnchor()
    local profile = KE.db and KE.db.profile
    if not profile then return end

    local oldRA = profile.RacialsAnchor
    local pc = profile.PositionController
    if not oldRA or not pc or not pc.CDMRacials then return end

    if pc.CDMRacials._migrated then return end
    pc.CDMRacials._migrated = true

    -- Carry over user's previous RacialsAnchor settings on first run. Only
    -- CDMRacials.Enabled flips on — leaving pc.Enabled at its default (false)
    -- so unit-frame anchoring doesn't activate with stock defaults that would
    -- relocate the user's frames unexpectedly.
    if oldRA.Enabled == true then
        pc.CDMRacials.Enabled = true
        pc.CDMRacials.AnchorFrom   = oldRA.AnchorFrom or pc.CDMRacials.AnchorFrom
        pc.CDMRacials.AnchorTo     = oldRA.AnchorTo or pc.CDMRacials.AnchorTo
        pc.CDMRacials.XOffset      = oldRA.XOffset or pc.CDMRacials.XOffset
        pc.CDMRacials.YOffset      = oldRA.YOffset or pc.CDMRacials.YOffset
        pc.CDMRacials.PetBarOffset = oldRA.PetBarOffset or pc.CDMRacials.PetBarOffset
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function PC:UpdateDB()
    self.db = KE.db.profile.PositionController
end

function PC:OnInitialize()
    MigrateFromRacialsAnchor()
    self:UpdateDB()
    -- Module always enabled when present. CDM Racials half is fully
    -- independent of the master toggle, so the module needs to stay loaded
    -- regardless of db.Enabled (which only gates the unit-frame anchoring
    -- half).
end

function PC:OnPlayerEnteringWorld()
    CacheFrames()
    if HasElvUI() then
        self:HookViewerSizes()
    end
    self:TryInstallCDMHook()
    self:AttachPetWatcher()
    self:QueueApply()
    self:ScheduleSettleReapply()
end

-- Registers events that drive unit-frame anchoring re-applies. Only meaningful
-- when ElvUI is present, master is on, and we're not gated by healer spec.
function PC:ActivateForAnchoring()
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "QueueApply")
    self:RegisterEvent("SPELLS_CHANGED", "QueueApply")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "QueueApply")
    self:QueueApply()
end

function PC:DeactivateAnchoring()
    self:UnregisterEvent("TRAIT_CONFIG_UPDATED")
    self:UnregisterEvent("SPELLS_CHANGED")
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if HasElvUI() then
        RestoreAllAnchors()
    end
end

-- Re-evaluates the unit-frame anchoring half based on current state. Called
-- from OnEnable, spec change, master toggle, and IgnoreHealerSpec toggle.
function PC:ReevaluateAnchoring()
    local db = self.db
    local shouldRun = HasElvUI()
        and not HasElvUIAnchor()
        and db and db.Enabled
        and not IsHealerGated(db)

    if shouldRun then
        self:ActivateForAnchoring()
    else
        self:DeactivateAnchoring()
    end
end

function PC:OnSpecChanged()
    self:ReevaluateAnchoring()
end

function PC:OnAddonLoaded(_, addonName)
    if addonName == "Ayije_CDM" then
        self:TryInstallCDMHook()
    elseif addonName == "ElvUI_Anchor" then
        -- ElvUI_Anchor came online after us. Stand down our anchoring half so
        -- we don't compete; restore ElvUI's profile positions on the way out.
        self:ReevaluateAnchoring()
    end
end

function PC:OnUnitPet(_, unit)
    if unit ~= "player" then return end
    self:AttachPetWatcher()
end

function PC:OnEnable()
    self:UpdateDB()

    -- These run regardless of master toggle so CDM Racials can work
    -- independently:
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("UNIT_PET", "OnUnitPet")
    -- ADDON_LOADED handler covers both deferred CDM hook install and a late
    -- ElvUI_Anchor load (so we can stand down on demand).
    self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
    self:TryInstallCDMHook()
    self:AttachPetWatcher()

    -- Unit-frame anchoring half: gated by master + ElvUI + healer toggle.
    self:ReevaluateAnchoring()
end

function PC:OnDisable()
    self:UnregisterAllEvents()
    if HasElvUI() then
        RestoreAllAnchors()
    end
end

function PC:ApplySettings()
    wipe(warnedMissingParent)
    self:UpdateDB()
    -- Re-evaluate the anchoring half (handles master toggle + healer toggle
    -- changes), then force CDM to re-anchor so racials slider changes feel
    -- immediate.
    self:ReevaluateAnchoring()
    ForceRacialsReanchor()
end

---------------------------------------------------------------------------------
-- Status helpers (consumed by GUI for live indicator notes)
---------------------------------------------------------------------------------

-- True if this spec/class has a pet frame at all (not whether it's currently
-- visible). Detection covers ElvUF and UUF.
function PC:IsPetFrame()
    return GetPetFrame() ~= nil
end

-- True if the pet frame is currently visible (pet summoned + pet bar shown).
function PC:HasPetBar()
    local petFrame = GetPetFrame()
    return petFrame ~= nil and petFrame:IsShown() == true
end

-- True if ElvUI is loaded.
function PC:HasElvUI()
    return HasElvUI()
end

-- True if the standalone ElvUI_Anchor addon is loaded — when it is, the
-- unit-frame anchoring half of this module yields to that addon to avoid
-- two layers fighting over the same anchors.
function PC:HasElvUIAnchor()
    return HasElvUIAnchor()
end
