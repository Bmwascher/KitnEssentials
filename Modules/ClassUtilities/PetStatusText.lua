-- ╔══════════════════════════════════════════════════════════╗
-- ║  PetStatusText.lua                                       ║
-- ║  Module: Pet Status Text                                 ║
-- ║  Purpose: Displays pet status text on screen for pet     ║
-- ║           classes (Hunter, Warlock, DK, Mage).           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class PetStatusText: AceModule, AceEvent-3.0
local PS = KitnEssentials:NewModule("PetStatusText", "AceEvent-3.0")

local UnitClass = UnitClass
local IsMounted = IsMounted
local UnitOnTaxi = UnitOnTaxi
local UnitInVehicle = UnitInVehicle
local UnitHasVehicleUI = UnitHasVehicleUI
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local UnitExists = UnitExists
local CreateFrame = CreateFrame
local GetPetActionInfo = GetPetActionInfo
local PetHasActionBar = PetHasActionBar
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local C_Timer = C_Timer
local C_SpellBook = C_SpellBook
local SpellBookBank_Player = Enum.SpellBookSpellBank.Player
local strsplit = strsplit

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
-- Tracked pet classes
local PET_CLASSES = {
    ["HUNTER"] = { summonSpellId = 883, reviveSpellId = 982, specId = nil },
    ["WARLOCK"] = { summonSpellId = 688, reviveSpellId = nil, specId = nil },
    ["DEATHKNIGHT"] = { summonSpellId = 46584, reviveSpellId = nil, specId = 252 },
    ["MAGE"] = { summonSpellId = 31687, reviveSpellId = nil, specId = 64 },
}

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
local petInfo = nil
local isGrimoireClass = false
local petDeathTracked = false

local PET_STATUS = {
    NONE = 0,
    MISSING = 1,
    DEAD = 2,
    PASSIVE = 3,
    WRONG = 4,
}

local UPDATE_DEBOUNCE = 0.15

PS.frame = nil
PS.text = nil

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------
-- Is player mounted or in vehicle
local function IsPlayerMounted()
    return IsMounted() or UnitOnTaxi("player") or UnitInVehicle("player") or UnitHasVehicleUI("player")
end

local function IsPetOnPassive()
    if not UnitExists("pet") or not PetHasActionBar() then return false end
    for slot = 1, 10 do
        local name, _, isToken, isActive = GetPetActionInfo(slot)
        if isToken and name == "PET_MODE_PASSIVE" and isActive then return true end
    end
    return false
end

-- Verified via /dump UnitGUID("pet") on. Single NPC ID — no
-- Wrathguard / talent variants in modern Demo.
local FELGUARD_NPC_IDS = {
    [17252] = true,  -- Felguard
}

-- Pet GUID format: <Type>-0-<Realm>-<Map>-<Zone>-<NpcID>-<SpawnUID>.
-- The <Type> prefix is normally "Pet-" but Sayaad (Succubus successor) uses
-- "Creature-". Position 6 is the NPC ID regardless, so the same extraction
-- works for both prefixes.
--
-- Tri-state return:
--   true  — pet GUID resolved to a known Felguard NPC ID
--   false — pet GUID resolved to a known non-Felguard NPC ID
--   nil   — cannot determine (no pet, GUID is a 12.0 secret value, or GUID
--           is malformed). The WRONG branch in CheckPetStatus only fires on
--           an explicit `false` so secret-GUID contexts don't false-positive.
--
-- KE:GetSafeUnitGUID returns nil when UnitGUID returns a secret string —
-- without this, calling strsplit on a secret value triggers
-- "attempt to perform string conversion on a secret string value (tainted)."
--
-- IMPORTANT: select(6, ...) returns position 6 AND everything after. Passing
-- that directly to tonumber() means the 7th segment (spawn UID like
-- "0104E40414") becomes the BASE argument; the "E" is parsed as scientific
-- notation, the value coerces to infinity, and tonumber crashes with
-- "integer overflow attempting to store inf." Assign to a local first to
-- truncate to a single value.
local function IsPetFelguard()
    local guid = KE:GetSafeUnitGUID("pet")
    if not guid then return nil end
    local segment = select(6, strsplit("-", guid))
    local npcID = tonumber(segment)
    if not npcID then return nil end
    return FELGUARD_NPC_IDS[npcID] == true
end

local function CheckAndUpdatePetDeathState()
    if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then
        petDeathTracked = false
        return false
    end

    if UnitExists("pet") and UnitIsDeadOrGhost("pet") then
        petDeathTracked = true
        return true
    end

    if petDeathTracked then return true end

    return false
end

local function ResetPetDeathTracking()
    petDeathTracked = false
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
local function CheckPetStatus()
    if not petInfo then return PET_STATUS.NONE, nil, nil end
    if IsPlayerMounted() then return PET_STATUS.NONE, nil, nil end

    local specIndex = GetSpecialization()
    local specID = GetSpecializationInfo(specIndex)

    -- MM Hunter with Unbreakable Bond (466867) or Spotter's Mark (466872) — both replace the pet
    if specID == 254 and (C_SpellBook.IsSpellKnown(466867, SpellBookBank_Player) or C_SpellBook.IsSpellKnown(466872, SpellBookBank_Player)) then
        return PET_STATUS.NONE, nil, nil
    end

    -- Spec check for class-specific pets
    if petInfo.specId then
        if specIndex then
            if specID ~= petInfo.specId then return PET_STATUS.NONE, nil, nil end
        end
    end

    if not C_SpellBook.IsSpellKnown(petInfo.summonSpellId) then return PET_STATUS.NONE, nil, nil end

    -- Demo Warlock with non-Felguard pet. Priority above DEAD because the
    -- actionable fix is "dismiss + re-summon Felguard," not "revive."
    -- IsPetFelguard returns nil when the pet GUID is a 12.0 secret value or
    -- otherwise unresolvable — explicitly compare to false so an unknown
    -- pet identity falls through to the existing DEAD/PASSIVE/MISSING chain
    -- rather than false-positive a WRONG warning we can't actually verify.
    if specID == 266 and UnitExists("pet") and IsPetFelguard() == false then
        return PET_STATUS.WRONG, PS.db.PetWrong, PS.db.WrongColor
    end

    -- Remaining priority: Dead > Passive > Missing
    if CheckAndUpdatePetDeathState() then
        return PET_STATUS.DEAD, PS.db.PetDead, PS.db.DeadColor
    end

    if UnitExists("pet") then
        if IsPetOnPassive() then
            return PET_STATUS.PASSIVE, PS.db.PetPassive, PS.db.PassiveColor
        end
        return PET_STATUS.NONE, nil, nil
    else
        -- The MISSING verdict is earned by failing to find Grimoire of Sacrifice,
        -- which consumes the pet. That search cannot succeed while aura
        -- identities are hidden -- the call returns nothing rather than erroring
        -- -- so the failure proves nothing and the verdict would be a false
        -- accusation for the whole restricted stretch. Warlocks only: no other
        -- pet class can be holding this buff, so their warning is untouched.
        if isGrimoireClass and KE:AreAuraIdentitiesHidden() then
            return PET_STATUS.NONE, nil, nil
        end
        local sacrificeAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(196099)
        if sacrificeAura then
            return PET_STATUS.NONE, nil, nil
        end
        return PET_STATUS.MISSING, PS.db.PetMissing, PS.db.MissingColor
    end
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function PS:UpdateDB()
    self.db = KE.db.profile.PetStatusText
end

function PS:OnInitialize()
    self:UpdateDB()

    local _, class = UnitClass("player")
    petInfo = PET_CLASSES[class]
    isGrimoireClass = class == "WARLOCK"

    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function PS:CreateFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_PetStatusTextFrame", UIParent)
    frame:SetSize(200, 50)

    local text = frame:CreateFontString(nil, "OVERLAY")
    local fontPath = KE:GetFontPath(self.db.FontFace)
    -- GetFontOutline maps the stored key to a real SetFont flag; NONE and the
    -- retired SOFTOUTLINE would otherwise reach SetFont as unknown strings.
    text:SetFont(fontPath, self.db.FontSize, KE:GetFontOutline(self.db.FontOutline))
    text:SetTextColor(1, 0.82, 0, 1)
    text:ClearAllPoints()
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)

    self.frame = frame
    self.frame.text = text
    self.text = text

    local width, height = math.max(text:GetWidth(), 170), math.max(text:GetHeight(), 18)
    frame:SetSize(width + 5, height + 5)

    self.frame:Hide()
end

function PS:UpdatePetText()
    if not self.frame then return end
    -- The preview owns the frame while it is up; a live pet event must not
    -- repaint or hide it out from under the config panel.
    if self.isPreview then return end

    -- If the status evaluation ever throws on an API change, hide the text
    -- rather than leave the last painted state frozen on screen. A reminder
    -- that cannot evaluate must not nag.
    local ok, _, message, color = pcall(CheckPetStatus)
    if not ok then
        self.frame:Hide()
        return
    end

    if message and color then
        self.text:SetText(message)
        local r, g, b, a = KE:ResolveColor(color, { 1, 1, 1, 1 })
        self.text:SetTextColor(r, g, b, a)
        self.frame:Show()
    else
        self.frame:Hide()
    end
end

-- Pet events arrive in bursts (combat entry, mounting, a resummon), so repaints
-- are debounced. The flush is hoisted so a burst does not allocate a closure per
-- event.
local function FlushPetUpdate()
    PS._updatePending = false
    -- A flush armed just before teardown would otherwise repaint and re-Show
    -- over the hidden frame with nothing left registered to correct it.
    if not PS._tracking then return end
    PS:UpdatePetText()
end

function PS:QueueUpdate()
    if self._updatePending then return end
    self._updatePending = true
    C_Timer.After(UPDATE_DEBOUNCE, FlushPetUpdate)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function PS:ApplySettings()
    if not self.frame then return end

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
    KE:ApplyFontToText(self.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)

    if self.isPreview then
        self:ShowPreview(self.previewState)
    end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function PS:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "PetStatusText", displayName = "Pet Status Text", frame = self.frame,
            module = self,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "PetStatusText",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function PS:ShowPreview(state)
    if not self.frame then
        self:CreateFrame()
    end
    self:RegWithEditMode()

    self.isPreview = true
    self.previewState = state or "missing"

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
    KE:ApplyFontToText(self.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)

    local previewText, r, g, b, a
    if self.previewState == "dead" then
        previewText = self.db.PetDead or "PET DEAD"
        r, g, b, a = KE:ResolveColor(self.db.DeadColor, { 1, 0.2, 0.2, 1 })
    elseif self.previewState == "passive" then
        previewText = self.db.PetPassive or "PET PASSIVE"
        r, g, b, a = KE:ResolveColor(self.db.PassiveColor, { 0.3, 0.7, 1, 1 })
    elseif self.previewState == "wrong" then
        previewText = self.db.PetWrong or "WRONG PET"
        r, g, b, a = KE:ResolveColor(self.db.WrongColor, { 1, 0.4, 0, 1 })
    else
        previewText = self.db.PetMissing or "PET MISSING"
        r, g, b, a = KE:ResolveColor(self.db.MissingColor, { 1, 0.82, 0, 1 })
    end

    self.text:SetText(previewText)
    self.text:SetTextColor(r, g, b, a)

    -- CreateFrame sized the frame from an empty string, so refit to the real
    -- preview text or long custom state text clips.
    local width, height = math.max(self.text:GetWidth(), 170), math.max(self.text:GetHeight(), 18)
    self.frame:SetSize(width + 5, height + 5)

    self.frame:Show()
end

function PS:HidePreview()
    self.isPreview = false
    if self.db.Enabled then
        self:UpdatePetText()
    else
        if self.frame then self.frame:Hide() end
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
-- Zone-in needs a longer settle than the debounce: pet data is not ready
-- immediately after a load screen.
function PS:OnPlayerEnteringWorld()
    C_Timer.After(1, function()
        if self._tracking then self:QueueUpdate() end
    end)
end

function PS:OnEnable()
    if not self.db.Enabled then return end
    if not petInfo then return end

    self:CreateFrame()
    self:ApplySettings()
    self:RegWithEditMode()

    self._tracking = true
    self._updatePending = false

    self:RegisterEvent("UNIT_PET", function(_, unit)
        if unit ~= "player" then return end
        if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then
            ResetPetDeathTracking()
        end
        self:QueueUpdate()
    end)

    self:RegisterEvent("PLAYER_REGEN_ENABLED", "QueueUpdate")
    -- Combat exit is not the only release. A keystone keeps identities hidden
    -- between pulls, so without this the text stays suppressed for the whole
    -- run rather than the pull.
    self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "QueueUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("SPELLS_CHANGED", "QueueUpdate")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "QueueUpdate")
    self:RegisterEvent("UNIT_DIED", "QueueUpdate")
    -- Mounting hides the text, and without this nothing re-checks on dismount.
    self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", "QueueUpdate")
    self:RegisterEvent("PET_BAR_UPDATE", "QueueUpdate")

    self:UpdatePetText()
end

function PS:OnDisable()
    self._tracking = false
    self._updatePending = false
    self:UnregisterAllEvents()
    if self.frame then self.frame:Hide() end
end
