-- ╔══════════════════════════════════════════════════════════╗
-- ║  FriendlyAutoMarker.lua                                  ║
-- ║  Module: Friendly Auto Marker                            ║
-- ║  Purpose: Auto-marks the group's tank and healer with    ║
-- ║           configurable raid icons when entering a        ║
-- ║           dungeon, on M+ start, or on group composition  ║
-- ║           changes. Display-only; no on-screen frames.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class FriendlyAutoMarker: AceModule, AceEvent-3.0
local FAM = KitnEssentials:NewModule("FriendlyAutoMarker", "AceEvent-3.0")

-- LibSpecialization: passive group spec/role tracking via addon comms.
-- Spec-derived role is more reliable than UnitGroupRolesAssigned for cross-
-- realm pugs where inspect data isn't cached. Optional — falls back to
-- UnitGroupRolesAssigned when unavailable.
local LibSpec = LibStub("LibSpecialization", true)

local UnitName               = UnitName
local UnitExists             = UnitExists
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local SetRaidTarget          = SetRaidTarget
local GetInstanceInfo        = GetInstanceInfo
local IsInGroup              = IsInGroup
local IsInRaid               = IsInRaid
local C_Timer                = C_Timer
local wipe                   = wipe

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
FAM.specCache = {}  -- [playerName] = "TANK" | "HEALER" | "DAMAGER", from LibSpec

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function FAM:UpdateDB()
    self.db = KE.db.profile.FriendlyAutoMarker
end

function FAM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------
local function IsInDungeonInstance()
    local _, instanceType = GetInstanceInfo()
    return instanceType == "party" or instanceType == "raid"
end

--- GetUnitRole
--- Prefers LibSpec spec-derived role (accurate for cross-realm pugs whose
--- inspect data isn't cached) over UnitGroupRolesAssigned (LFG role check).
--- Falls back to assigned role when LibSpec hasn't reported this player yet
--- (just-joined member, or lib not loaded).
function FAM:GetUnitRole(unit)
    if not UnitExists(unit) then return "NONE" end
    if LibSpec then
        local name = UnitName(unit)
        if name and self.specCache[name] then
            return self.specCache[name]
        end
    end
    return UnitGroupRolesAssigned(unit)
end

---------------------------------------------------------------------------------
-- Core
---------------------------------------------------------------------------------
--- ApplyMarks
--- Iterates the group, finds the first tank and first healer, and marks them
--- with the configured raid target icons. Skipped silently if disabled, not
--- in a group, or (with InstanceOnly toggle) outside a dungeon. Player is
--- checked first so self-mark works without walking party slots.
function FAM:ApplyMarks()
    if not self.db or not self.db.Enabled then return end
    if self.db.InstanceOnly and not IsInDungeonInstance() then return end
    if not IsInGroup() then return end

    local markedTank = false
    local markedHealer = false
    local tankIcon = self.db.TankIcon or 6
    local healerIcon = self.db.HealerIcon or 1
    local wantTank = self.db.MarkTank ~= false
    local wantHealer = self.db.MarkHealer ~= false

    local function check(unit)
        if markedTank and markedHealer then return end
        if not UnitExists(unit) then return end
        local role = self:GetUnitRole(unit)
        if wantTank and not markedTank and role == "TANK" then
            SetRaidTarget(unit, tankIcon)
            markedTank = true
        elseif wantHealer and not markedHealer and role == "HEALER" then
            SetRaidTarget(unit, healerIcon)
            markedHealer = true
        end
    end

    check("player")

    if IsInRaid() then
        for i = 1, 40 do check("raid" .. i) end
    else
        for i = 1, 4 do check("party" .. i) end
    end
end

--- OnLibSpecGroupUpdate
--- LibSpec callback fires per-player when their spec data arrives via addon
--- comms. Cache the role and re-apply marks if the role we just learned is
--- a tank or healer (the player whose role we just learned might be the
--- one to mark).
function FAM:OnLibSpecGroupUpdate(_specID, role, _position, playerName)
    if not playerName or not role then return end
    self.specCache[playerName] = role
    if self.db and self.db.Enabled and (role == "TANK" or role == "HEALER") then
        self:ApplyMarks()
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function FAM:ApplySettings()
    if not self.db.Enabled then return end
    self:ApplyMarks()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function FAM:OnEnable()
    if not self.db.Enabled then return end

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyMarks")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "ApplyMarks")
    self:RegisterEvent("CHALLENGE_MODE_START", "ApplyMarks")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "ApplyMarks")

    if LibSpec then
        LibSpec.RegisterGroup(self, function(specID, role, position, playerName)
            FAM:OnLibSpecGroupUpdate(specID, role, position, playerName)
        end)
    end

    -- Defer initial pass so LibSpec comms have a chance to populate the cache
    -- on /reload mid-dungeon.
    C_Timer.After(2, function() FAM:ApplyMarks() end)
end

function FAM:OnDisable()
    self:UnregisterAllEvents()
    if LibSpec then LibSpec.UnregisterGroup(self) end
    wipe(self.specCache)
end
