-- ╔══════════════════════════════════════════════════════════╗
-- ║  EbonMightHelper.lua                                     ║
-- ║  Module: Ebon Might Helper                               ║
-- ║  Purpose: Ebon Might extension warning for Augmentation  ║
-- ║           Evoker with sound alert.                       ║
-- ║  Note: Evoker only (Augmentation).                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local EM = KitnEssentials:NewModule("EbonMightHelper", "AceEvent-3.0")

local GetTime = GetTime
local select = select
local pcall = pcall
local PlaySoundFile = PlaySoundFile
local StopSound = StopSound
local UnitClass = UnitClass
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local PlayerUtil = PlayerUtil
local RunNextFrame = RunNextFrame
local GetUnitEmpowerMinHoldTime = GetUnitEmpowerMinHoldTime
local LibStub = LibStub

---------------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------------
-- Flip to true, /reload, then cast an extender (Eruption / Upheaval / Fire Breath)
-- with and without Ebon Might active. Traces the full path: extender detection ->
-- branch decision -> PlayWarningSound -> LSM fetch -> PlaySoundFile result. Tells us
-- whether the warning is failing on detection, media resolution, or playback.
local DEBUG_EM = false
local function dbg(...)
    if not DEBUG_EM then return end
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring((select(i, ...))) end
    KE:Print("|cff33ff99[EM]|r " .. table.concat(parts, " "))
end

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local ERUPTION = 395160
local UPHEAVAL_FONT = 408092
local FIRE_BREATH_FONT = 382266
local UPHEAVAL = 396286
local FIRE_BREATH = 357208
local EBON_MIGHT_CAST = 395152
local EBON_MIGHT_AURA = 395296

local AUGMENTATION = 1473
local MAX_POLL_ATTEMPTS = 5

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
EM.expirationTime = 0
EM.lastEbonMightCast = 0
EM.soundHandle = nil

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function EM:UpdateDB()
    self.db = KE.db.profile.EbonMightHelper
end

function EM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function EM:IsValidSpec()
    local specId = PlayerUtil.GetCurrentSpecID()
    return specId == AUGMENTATION
end

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------
local function IsExtender(spellId)
    return spellId == ERUPTION
        or spellId == UPHEAVAL_FONT
        or spellId == FIRE_BREATH_FONT
        or spellId == UPHEAVAL
        or spellId == FIRE_BREATH
end

local function GetCastTime(spellId)
    if spellId == ERUPTION then
        local info = C_Spell.GetSpellInfo(spellId)
        return info and info.castTime / 1000 or 0.5
    end
    return GetUnitEmpowerMinHoldTime("player") / 1000
end

local function GetEbonMightExpiration()
    local auraData = C_UnitAuras.GetPlayerAuraBySpellID(EBON_MIGHT_AURA)
    return auraData and auraData.expirationTime or 0
end

---------------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------------
function EM:PlayWarningSound()
    dbg("PlayWarningSound: file=", tostring(self.db.SoundFile), "channel=", tostring(self.db.SoundChannel))

    if self.soundHandle then
        StopSound(self.soundHandle)
        self.soundHandle = nil
    end

    local soundFile = self.db.SoundFile
    if not soundFile or soundFile == "None" then
        dbg("  -> abort: SoundFile is nil/None")
        return
    end

    local LSM = LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        dbg("  -> abort: LibSharedMedia not loaded")
        return
    end

    local path = LSM:Fetch("sound", soundFile)
    if not path then
        dbg("  -> abort: LSM:Fetch returned nil (sound '", tostring(soundFile), "' not registered)")
        return
    end

    local ok, willPlay, handle = pcall(PlaySoundFile, path, self.db.SoundChannel or "Master")
    dbg("  PlaySoundFile path=", tostring(path), "ok=", tostring(ok), "willPlay=", tostring(willPlay), "handle=", tostring(handle))
    if ok and willPlay and handle then
        self.soundHandle = handle
    end
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function EM:QueueTimingCheck(expectedCastEnd, previousExpiration, count)
    RunNextFrame(function()
        self:OnTimingCheck(expectedCastEnd, previousExpiration, count)
    end)
end

function EM:OnTimingCheck(expectedCastEnd, previousExpiration, count)
    if not self.db.Enabled then return end

    -- Check what spell is currently being cast
    local spellId = select(9, UnitCastingInfo("player")) or select(8, UnitChannelInfo("player"))
    if not spellId then return end
    if not IsExtender(spellId) then return end

    self.expirationTime = GetEbonMightExpiration()
    dbg("timing recheck #", count, "spellId=", spellId, "EMexp=", self.expirationTime, "expectedCastEnd=", expectedCastEnd)

    -- Buff faded since the original cast
    if self.expirationTime == 0 then
        dbg("  EMexp=0 (faded) -> WARN")
        self:PlayWarningSound()
        return
    end

    local tooLate = expectedCastEnd > self.expirationTime

    -- After max attempts or timing is now safe — resolve
    if count >= MAX_POLL_ATTEMPTS or not tooLate then
        if tooLate then
            dbg("  resolved: too late -> WARN")
            self:PlayWarningSound()
        else
            dbg("  resolved: timing safe -> no warn")
        end
        return
    end

    -- No change observed, still within 2s — keep polling
    if previousExpiration == self.expirationTime and self.expirationTime - GetTime() < 2 then
        self:QueueTimingCheck(expectedCastEnd, previousExpiration, count + 1)
        return
    end

    -- Expiration changed but still too late
    if tooLate then
        self:PlayWarningSound()
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function EM:OnEvent(event, unit, ...)
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
        if unit ~= "player" then return end
        local _, spellId = ...

        -- Empower events may pass spellId at a different arg position
        if spellId and spellId < 100000 and event == "UNIT_SPELLCAST_EMPOWER_START" then
            spellId = select(3, ...)
        end

        if not spellId or not IsExtender(spellId) then return end

        local now = GetTime()
        dbg("extender cast:", event, "spellId=", spellId, "EMexp=", self.expirationTime)

        -- No Ebon Might active
        if self.expirationTime == 0 then
            -- Casting extender immediately after EM cast — buff not yet visible
            if now == self.lastEbonMightCast then
                dbg("  EMexp=0 but cast is right after EM cast -> skip warn")
                return
            end
            dbg("  EMexp=0 (no Ebon Might active) -> WARN")
            self:PlayWarningSound()
            return
        end

        local castTime = GetCastTime(spellId)
        self.expirationTime = GetEbonMightExpiration()

        local castEnd = now + castTime
        local tooLate = castEnd > self.expirationTime
        dbg("  castEnd=", castEnd, "EMexp=", self.expirationTime, "tooLate=", tooLate)

        -- If it looks too late and expiration is within 2s, poll to confirm
        if tooLate and self.expirationTime - now < 2 then
            dbg("  too late & EM within 2s -> queue timing recheck")
            self:QueueTimingCheck(castEnd, self.expirationTime, 1)
            return
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        local _, spellId = ...
        if spellId == EBON_MIGHT_CAST then
            self.lastEbonMightCast = GetTime()
        end

    elseif event == "UNIT_AURA" then
        if unit ~= "player" then return end
        self.expirationTime = GetEbonMightExpiration()

    elseif event == "LOADING_SCREEN_DISABLED" then
        if self:IsValidSpec() then
            self:RegisterSpellEvents()
            self.expirationTime = GetEbonMightExpiration()
        else
            self:UnregisterSpellEvents()
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if self:IsValidSpec() then
            self:RegisterSpellEvents()
        else
            self:UnregisterSpellEvents()
        end
    end
end

function EM:RegisterSpellEvents()
    self:RegisterEvent("UNIT_SPELLCAST_START", "OnEvent")
    self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START", "OnEvent")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnEvent")
    self:RegisterEvent("UNIT_AURA", "OnEvent")
end

function EM:UnregisterSpellEvents()
    self:UnregisterEvent("UNIT_SPELLCAST_START")
    self:UnregisterEvent("UNIT_SPELLCAST_EMPOWER_START")
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:UnregisterEvent("UNIT_AURA")
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function EM:OnEnable()
    if not self.db.Enabled then
        dbg("OnEnable: db.Enabled is false -> module idle")
        return
    end

    -- Evoker only
    if select(3, UnitClass("player")) ~= Constants.UICharacterClasses.Evoker then
        dbg("OnEnable: not an Evoker -> module idle")
        return
    end

    self:RegisterEvent("LOADING_SCREEN_DISABLED", "OnEvent")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnEvent")

    if self:IsValidSpec() then
        dbg("OnEnable: Augmentation spec -> spell events registered")
        self:RegisterSpellEvents()
        self.expirationTime = GetEbonMightExpiration()
    else
        dbg("OnEnable: not Augmentation spec -> spell events NOT registered")
    end
end

function EM:OnDisable()
    self.expirationTime = 0
    self.lastEbonMightCast = 0
    if self.soundHandle then
        StopSound(self.soundHandle)
        self.soundHandle = nil
    end
    self:UnregisterAllEvents()
end
