-- ============================================================
-- RacialsAnchor.lua
-- Module: Racials Anchor
-- Purpose: Hooks CDM's (Ayije_CDM) AnchorToPlayerFrame to reposition
--          CDM_RacialsContainer using custom anchor settings. Adds an
--          additional Y offset for pet classes when the pet bar is visible.
--          Supports both ElvUI (ElvUF_Pet) and UUI (UUF_Pet) pet frames.
-- Author: Bitebtw
-- ============================================================

-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class RacialsAnchor: AceModule, AceEvent-3.0
local RA = KitnEssentials:NewModule("RacialsAnchor", "AceEvent-3.0")

local _G = _G
local C_Timer = C_Timer

-- Hook state
local hooked = false
local originalAnchor = nil

-- Pet watcher state
local petWatcherAttached = false

-- Returns the pet unit frame from ElvUI or UUF, whichever is present.
local function GetPetFrame()
    return _G["ElvUF_Pet"] or _G["UUF_Pet"]
end

-- Triggers CDM to re-run its anchoring logic for CDM_RacialsContainer,
-- which then flows through our hooked function.
local function ForceRacialsReanchor()
    local CDM = _G["Ayije_CDM"]
    if CDM and CDM.InvalidateTrackerAnchorCache and CDM.ScheduleTrackerPositionRefresh then
        local container = _G["CDM_RacialsContainer"]
        if container then
            CDM.InvalidateTrackerAnchorCache(container)
            CDM.ScheduleTrackerPositionRefresh()
        end
    end
end

-- Hooks OnShow/OnHide on the pet frame so CDM re-anchors when pet
-- visibility changes.
local function AttachPetWatcher()
    if petWatcherAttached then return end
    local petFrame = GetPetFrame()
    if not petFrame then return end

    petFrame:HookScript("OnShow", ForceRacialsReanchor)
    petFrame:HookScript("OnHide", ForceRacialsReanchor)
    petWatcherAttached = true
end

-- Attempts to hook CDM's AnchorToPlayerFrame. Returns true on success.
local function TryHook()
    if hooked then return true end

    local CDM = _G["Ayije_CDM"]
    if not CDM or not CDM.AnchorToPlayerFrame then return false end

    originalAnchor = CDM.AnchorToPlayerFrame

    CDM.AnchorToPlayerFrame = function(container, anchorPoint, offsetX, offsetY, moduleName, forceRefresh, containerAnchor)
        -- Only modify the Racials container; pass everything else through untouched.
        if container and container:GetName() == "CDM_RacialsContainer" then
            local db = RA.db
            if db and db.Enabled then
                -- Override CDM's anchor args (empty string = CDM default)
                if db.AnchorTo and db.AnchorTo ~= "" then anchorPoint = db.AnchorTo end
                if db.AnchorFrom and db.AnchorFrom ~= "" then containerAnchor = db.AnchorFrom end
                offsetX = (db.XOffset or 0) + (offsetX or 0)
                offsetY = (db.YOffset or 0) + (offsetY or 0)

                -- Add pet offset when pet frame is visible
                local petFrame = GetPetFrame()
                if petFrame and petFrame:IsShown() then
                    offsetY = offsetY + (db.PetBarOffset or -1)
                end
            end
        end
        -- Always call original so CDM manages its internal state
        return originalAnchor(container, anchorPoint, offsetX, offsetY, moduleName, forceRefresh, containerAnchor)
    end

    hooked = true
    return true
end

-- Poll on OnUpdate for up to 300 frames (every 5th frame) to catch CDM
-- loading before PLAYER_ENTERING_WORLD fires.
local initAttempts = 0
local initFrame = CreateFrame("Frame")
initFrame:SetScript("OnUpdate", function(self)
    initAttempts = initAttempts + 1
    if initAttempts > 300 then
        self:SetScript("OnUpdate", nil)
        return
    end
    if initAttempts % 5 == 0 then
        if TryHook() then
            self:SetScript("OnUpdate", nil)
        end
    end
end)

----------------------------------------------------------------
-- Module lifecycle
----------------------------------------------------------------

function RA:UpdateDB()
    self.db = KE.db and KE.db.profile.RacialsAnchor
end

function RA:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function RA:OnEnable()
    self:UpdateDB()
    TryHook()
    AttachPetWatcher()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("UNIT_PET")
end

function RA:OnDisable()
    self:UnregisterAllEvents()
    -- The hook itself cannot be undone once set, but db.Enabled = false
    -- causes the hook body to fall through to originalAnchor automatically.
end

function RA:PLAYER_ENTERING_WORLD()
    if not TryHook() then
        -- CDM may not be loaded yet; try again after a short delay.
        C_Timer.After(1, function()
            TryHook()
        end)
    end
    C_Timer.After(1, AttachPetWatcher)
end

function RA:UNIT_PET(unit)
    if unit ~= "player" then return end
    C_Timer.After(1, AttachPetWatcher)
end

----------------------------------------------------------------
-- Public API (called by GUI)
----------------------------------------------------------------

function RA:ApplySettings()
    TryHook()
    AttachPetWatcher()
    ForceRacialsReanchor()
end

function RA:HasPetBar()
    local petFrame = GetPetFrame()
    return petFrame ~= nil and petFrame:IsShown() == true
end

function RA:IsPetFrame()
    return GetPetFrame() ~= nil
end
