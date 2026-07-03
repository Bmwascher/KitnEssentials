-- ╔══════════════════════════════════════════════════════════╗
-- ║  TargetedSpells.lua                                      ║
-- ║  Module: Targeted Spells                                 ║
-- ║  Purpose: Mirrored icon/countdown entries for enemy      ║
-- ║           nameplate casts that target the player.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class TargetedSpells: AceModule, AceEvent-3.0
local TS = KitnEssentials:NewModule("TargetedSpells", "AceEvent-3.0")

local CreateFrame = CreateFrame
local IsInInstance, GetInstanceInfo = IsInInstance, GetInstanceInfo

local DEBUG_TS = false
local function dbg(...)
    if DEBUG_TS then KE:Print("|cff88ccff[TS]|r", ...) end
end

-- Delve difficultyID — probe-confirmed in-game 2026-07-03 (Collegiate
-- Calamity delve: instanceType "scenario", difficultyID 208).
TS.DELVE_DIFFICULTY_ID = 208

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

TS.entryPool = {}
TS.activeEntries = {}   -- unit -> entry
TS.activeCount = 0
TS.contentActive = false
TS.isPreview = false

---------------------------------------------------------------------------------
-- Pure helpers (busted-covered — keep WoW-API-free)
---------------------------------------------------------------------------------

-- Decides visibility from the five content checkboxes. Non-delve scenarios
-- follow the open-world flag.
function TS.ShouldShowForInstance(db, inInstance, instanceType, difficultyID)
    if not inInstance then
        return db.ShowInOpenWorld == true
    end
    if instanceType == "party" then return db.ShowInDungeons ~= false end
    if instanceType == "raid" then return db.ShowInRaids == true end
    if instanceType == "arena" or instanceType == "pvp" then return db.ShowInPvP == true end
    if instanceType == "scenario" then
        if difficultyID == TS.DELVE_DIFFICULTY_ID then return db.ShowInDelves ~= false end
        return db.ShowInOpenWorld == true
    end
    return db.ShowInOpenWorld == true
end

-- Sort key is the plain Lua receipt time (secret cast start times cannot be
-- compared); strict less-than keeps table.sort stable-safe.
function TS.CompareEntries(a, b)
    return (a.receiptTime or 0) < (b.receiptTime or 0)
end

---------------------------------------------------------------------------------
-- DB / lifecycle
---------------------------------------------------------------------------------

function TS:UpdateDB()
    self.db = KE.db.profile.TargetedSpells
end

function TS:OnInitialize()
    self:UpdateDB()
end

function TS:OnEnable()
    self:UpdateDB()
    if not self.db or not self.db.Enabled then return end

    self:CreateAnchorFrame()
    self:ApplyPosition()

    self:RegisterEvent("UNIT_SPELLCAST_START", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_STOP", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnCastEvent")
    self:RegisterEvent("UNIT_TARGET", "OnUnitTarget")
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnNameplateAdded")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnNameplateRemoved")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckContentGate")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "CheckContentGate")

    self:CheckContentGate()
    self:RegisterEditMode()
    self:CheckCVarPrompt()   -- Task 11 (no-op stub until then)
end

function TS:OnDisable()
    self:UnregisterAllEvents()
    self:ReleaseAllEntries()
    if self.anchorFrame then self.anchorFrame:Hide() end
end

---------------------------------------------------------------------------------
-- Content gating
---------------------------------------------------------------------------------

function TS:ShouldBeActive()
    if self.isPreview then return true end
    local inInstance, instanceType = IsInInstance()
    local _, _, difficultyID = GetInstanceInfo()
    return TS.ShouldShowForInstance(self.db, inInstance, instanceType, difficultyID)
end

function TS:CheckContentGate()
    local shouldBeActive = self:ShouldBeActive()
    if shouldBeActive and not self.contentActive then
        self.contentActive = true
        dbg("gate ON")
        self:ScanExistingNameplates()
    elseif not shouldBeActive and self.contentActive then
        self.contentActive = false
        dbg("gate OFF")
        if not self.isPreview then
            self:ReleaseAllEntries()
        end
    elseif shouldBeActive then
        -- PLAYER_ENTERING_WORLD with the gate already on: rescan (a /reload
        -- mid-combat leaves in-flight casts that fire no new START events).
        self:ScanExistingNameplates()
    end
end

---------------------------------------------------------------------------------
-- Anchor frame / position / EditMode
---------------------------------------------------------------------------------

function TS:CreateAnchorFrame()
    if self.anchorFrame then return end
    local db = self.db
    local f = CreateFrame("Frame", "KE_TargetedSpells", UIParent)
    f:SetSize(db.IconSize * 2 + db.FontSize * 3, db.IconSize)
    self.anchorFrame = f
end

function TS:ApplyPosition()
    if not self.anchorFrame then return end
    local db = self.db
    KE:ApplyFramePosition(self.anchorFrame, db.Position,
        { anchorFrameType = db.anchorFrameType, ParentFrame = db.ParentFrame, Strata = db.Strata }, true)
end

function TS:RegisterEditMode()
    if not KE.EditMode or self.editModeRegistered then return end
    KE.EditMode:RegisterElement({
        key = "TargetedSpells",
        displayName = "Targeted Spells",
        frame = self.anchorFrame,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            local p = self.db.Position
            p.AnchorTo = pos.AnchorTo
            p.XOffset = pos.XOffset
            p.YOffset = pos.YOffset
            self:ApplyPosition()
        end,
        getAnchorFrom = function() return self.db.Position.AnchorFrom or "CENTER" end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
        end,
        guiPath = "TargetedSpells",
    })
    self.editModeRegistered = true
end

---------------------------------------------------------------------------------
-- Stubs completed by Tasks 8-11 (keep so the file loads and lints clean)
---------------------------------------------------------------------------------

function TS:ScanExistingNameplates() end
function TS:ReleaseAllEntries() end
function TS:OnCastEvent() end
function TS:OnUnitTarget() end
function TS:OnNameplateAdded() end
function TS:OnNameplateRemoved() end
function TS:CheckCVarPrompt() end
