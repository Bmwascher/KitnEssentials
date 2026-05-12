-- ╔══════════════════════════════════════════════════════════╗
-- ║  BloodlustTracker.lua                                    ║
-- ║  Module: Bloodlust Tracker                               ║
-- ║  Purpose: Pedro overlay or icon alert on Bloodlust,      ║
-- ║           Heroism, and Time Warp.                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class BloodlustTracker: AceModule, AceEvent-3.0, AceTimer-3.0
local BLT = KitnEssentials:NewModule("BloodlustTracker", "AceEvent-3.0", "AceTimer-3.0")

local GetTime = GetTime
local CreateFrame = CreateFrame
local IsInInstance = IsInInstance
local PlaySoundFile = PlaySoundFile
local StopSound = StopSound
local issecretvalue = issecretvalue
local C_Sound = C_Sound
local C_UnitAuras = C_UnitAuras
local C_Timer = C_Timer
local pairs = pairs
local math_floor = math.floor
local math_max = math.max

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local TIMER_DURATION = 40
local BASE_FPS = 15
local FRAME_SIZE = 256
local BLOODLUST_ICON = 136012

local MEDIA_PATH = "Interface\\AddOns\\KitnEssentials\\Media\\BloodlustTracker\\"
local PEDRO_SHEET = MEDIA_PATH .. "pedro.tga"
local PEDRO_SOUND = MEDIA_PATH .. "pedro.mp3"
local PEDRO_FRAMES = 64
local PEDRO_FPS_RATIO = 0.8

local SATED_DEBUFFS = {
    [57723]  = true, -- Exhaustion (Heroism)
    [57724]  = true, -- Sated (Bloodlust)
    [80354]  = true, -- Temporal Displacement (Time Warp)
    [95809]  = true, -- Insanity (Ancient Hysteria)
    [160455] = true, -- Fatigued (Netherwinds)
    [264689] = true, -- Fatigued (Primal Rage)
    [390435] = true, -- Exhaustion (Fury of the Aspects)
}

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
BLT.frame = nil
BLT.spriteTexture = nil
BLT.iconFrame = nil
BLT.countdownText = nil
BLT.isPreview = false
BLT.testMode = false
BLT.lustActive = false
BLT._shown = false
BLT._renderedMode = nil
BLT.endTime = 0
BLT.animAccum = 0
BLT.frameIndex = 0
BLT.secondsPerFrame = 0
BLT.sheetW = 0
BLT.sheetH = 0
BLT.framesPerRow = 0
BLT.numFrames = 0
BLT.soundHandle = nil
BLT.soundLoopTimer = nil
BLT.lustTimer = nil
BLT._sheetProbeTimer = nil
BLT.inCombat = false

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------
local function FloorDiv(a, b)
    if type(a) ~= "number" or type(b) ~= "number" or b <= 0 then return 0 end
    return math_floor((a / b) + 1e-6)
end

---------------------------------------------------------------------------------
-- Sheet Probing
---------------------------------------------------------------------------------
function BLT:CalculateSpriteSheetLayout()
    if self._sheetProbeTimer then return end

    local probe = UIParent:CreateTexture(nil, "BACKGROUND")
    probe:SetTexture(PEDRO_SHEET)

    self._sheetProbeTimer = self:ScheduleRepeatingTimer(function()
        if probe.IsObjectLoaded and probe:IsObjectLoaded() then
            local w, h = probe:GetSize()
            probe:SetTexture(nil)
            if self._sheetProbeTimer then
                self:CancelTimer(self._sheetProbeTimer)
                self._sheetProbeTimer = nil
            end

            if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
                w, h = FRAME_SIZE, FRAME_SIZE
            end

            self.sheetW = w
            self.sheetH = h
            self.framesPerRow = FloorDiv(w, FRAME_SIZE)
            local rows = FloorDiv(h, FRAME_SIZE)
            local capacity = self.framesPerRow * rows
            -- Guard against 0-frame sheet breaking the animation pipeline
            -- when sheet dimensions are degenerate (upstream v0.5.4 fix).
            self.numFrames = math.max(1, math.min(PEDRO_FRAMES, capacity))
        end
    end, 0.05)
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function BLT:UpdateDB()
    self.db = KE.db.profile.BloodlustTracker
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function BLT:CreateFrames()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_BloodlustTracker", UIParent)
    frame:SetSize(FRAME_SIZE, FRAME_SIZE)
    frame:Hide()

    -- Sprite texture for Pedro mode
    local sprite = frame:CreateTexture(nil, "ARTWORK")
    sprite:SetAllPoints()
    sprite:Hide()

    -- Icon container for icon mode
    local iconFrame = CreateFrame("Frame", nil, frame)
    iconFrame:SetSize(self.db.BasicIconSize or 48, self.db.BasicIconSize or 48)
    iconFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)
    iconFrame:Hide()

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(iconFrame)
    icon:SetTexture(BLOODLUST_ICON)
    KE:ApplyIconZoom(icon)
    KE:AddIconBorders(iconFrame)

    -- Countdown text for icon mode
    local text = iconFrame:CreateFontString(nil, "OVERLAY", nil, 8)
    local fontPath = KE:GetFontPath(self.db.FontFace)
    text:SetFont(fontPath, self.db.FontSize or 22, KE:GetFontOutline(self.db.FontOutline) or "")
    text:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    text:Hide()

    self.frame = frame
    self.spriteTexture = sprite
    self.iconFrame = iconFrame
    self.countdownText = text

    -- Probe sheet layout as soon as frames exist so test mode can work
    -- before the module is enabled
    self:CalculateSpriteSheetLayout()
end

---------------------------------------------------------------------------------
-- Soft Outline Helpers
---------------------------------------------------------------------------------
local function HideSoftOutline(fontString)
    if fontString and fontString._keSoftOutline then
        fontString._keSoftOutline:SetShown(false)
    end
end

local function ShowSoftOutline(fontString)
    if fontString and fontString._keSoftOutline then
        fontString._keSoftOutline:SetShown(true)
    end
end

---------------------------------------------------------------------------------
-- Sprite Animation
---------------------------------------------------------------------------------
function BLT:SetSpriteFrame(i)
    local tex = self.spriteTexture
    if not tex or not self.framesPerRow or self.framesPerRow == 0 or self.sheetW == 0 or self.sheetH == 0 then return end

    local frameCount = self.numFrames > 0 and self.numFrames or PEDRO_FRAMES
    i = i % frameCount

    local col = i % self.framesPerRow
    local row = math_floor(i / self.framesPerRow)

    local left   = (col * FRAME_SIZE) / self.sheetW
    local right  = ((col + 1) * FRAME_SIZE) / self.sheetW
    local top    = (row * FRAME_SIZE) / self.sheetH
    local bottom = ((row + 1) * FRAME_SIZE) / self.sheetH

    tex:SetTexCoord(left, right, top, bottom)
end

function BLT:AnimOnUpdate(elapsed)
    self.animAccum = self.animAccum + elapsed
    local frameCount = self.numFrames > 0 and self.numFrames or PEDRO_FRAMES
    while self.animAccum >= self.secondsPerFrame do
        self.animAccum = self.animAccum - self.secondsPerFrame
        self.frameIndex = (self.frameIndex + 1) % frameCount
        self:SetSpriteFrame(self.frameIndex)
    end
end

function BLT:StartAnimation()
    if not self.frame then return end

    self.animAccum = 0
    self.frameIndex = 0

    if self.db.Mode == "pedro" then
        self.secondsPerFrame = 1 / math_max(1, BASE_FPS * PEDRO_FPS_RATIO)
        self.spriteTexture:SetTexture(PEDRO_SHEET)
        self:SetSpriteFrame(0)
        self.spriteTexture:Show()
        self.iconFrame:Hide()
        self.countdownText:Hide()
        HideSoftOutline(self.countdownText)

        self.frame:SetScript("OnUpdate", function(_, dt) self:AnimOnUpdate(dt) end)
    else
        self.spriteTexture:Hide()
        self.iconFrame:Show()
        self.countdownText:Show()
        ShowSoftOutline(self.countdownText)
        local r, g, b, a = KE:ResolveColor(self.db.CountdownColor, { 1, 1, 1, 1 })
        self.countdownText:SetTextColor(r, g, b, a)

        self.frame:SetScript("OnUpdate", function(_, dt) self:BasicOnUpdate(dt) end)
    end
end

function BLT:StopAnimation()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
    end
    self.animAccum = 0
end

---------------------------------------------------------------------------------
-- Icon Mode Countdown
---------------------------------------------------------------------------------
function BLT:BasicOnUpdate(dt)
    self.animAccum = self.animAccum + dt
    if self.animAccum < 0.1 then return end
    self.animAccum = 0

    local remaining = self.endTime - GetTime()
    if remaining <= 0 then
        self.countdownText:SetText("0")
        return
    end

    self.countdownText:SetText(string.format("%d", remaining))
end

---------------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------------
function BLT:PlaySoundOnce()
    if not self.db.SoundEnabled then return end
    local willPlay, handle = PlaySoundFile(PEDRO_SOUND, self.db.SoundChannel or "Master")
    if willPlay and handle then
        self.soundHandle = handle
        self.soundStartTime = GetTime()
    end
end

function BLT:StartSoundLoop()
    if self.soundLoopTimer then
        self:CancelTimer(self.soundLoopTimer)
        self.soundLoopTimer = nil
    end

    self:PlaySoundOnce()

    -- Poll less aggressively (0.5s) and enforce a minimum 1.5s between restarts.
    -- Raid combat saturates the sound channel and can evict sounds briefly;
    -- without a cooldown the loop would spam PlaySoundFile causing start/stop stutter.
    self.soundLoopTimer = self:ScheduleRepeatingTimer(function()
        if not self.lustActive and not self.testMode then
            self:StopSoundLoop()
            return
        end
        local handle = self.soundHandle
        local playing = false
        if handle and C_Sound and C_Sound.IsPlaying then
            playing = C_Sound.IsPlaying(handle)
        end
        if not playing and (GetTime() - (self.soundStartTime or 0)) >= 1.5 then
            self:PlaySoundOnce()
        end
    end, 0.50)
end

function BLT:StopSoundLoop()
    if self.soundLoopTimer then
        self:CancelTimer(self.soundLoopTimer)
        self.soundLoopTimer = nil
    end
    if self.soundHandle then
        StopSound(self.soundHandle, 150)
        self.soundHandle = nil
    end
    self.soundStartTime = nil
end

---------------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------------
function BLT:IsDetectionAllowed()
    if not self.db.InstanceOnly then return true end
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

-- Edge-triggered: only fires on newly added sated debuffs (matches reference)
function BLT:CheckAddedAuras(addedAuras)
    if self.isPreview or self.testMode then return end
    if not addedAuras then return end
    for _, auraInfo in pairs(addedAuras) do
        if auraInfo and auraInfo.auraInstanceID then
            local fullAuraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInfo.auraInstanceID)
            if fullAuraData and fullAuraData.spellId and not issecretvalue(fullAuraData.spellId) then
                if SATED_DEBUFFS[fullAuraData.spellId] then
                    self:StartTimedLust(TIMER_DURATION)
                    return
                end
            end
        end
    end
end

-- Reload/zone sync: scan for an existing sated debuff and show remaining time
function BLT:SyncFromExistingAura()
    if self.testMode or self.isPreview then return end
    if not self:IsDetectionAllowed() then
        -- Zoned out of instance with InstanceOnly on — hide any active display
        if self.lustActive then self:SetActive(false) end
        return
    end

    for spellID in pairs(SATED_DEBUFFS) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if aura and aura.duration and aura.duration > 0 and aura.expirationTime and aura.expirationTime > 0 then
            local startedAt = aura.expirationTime - aura.duration
            local remaining = (startedAt + TIMER_DURATION) - GetTime()
            if remaining > 0 then
                self:StartTimedLust(remaining)
            end
            return
        end
    end
end

---------------------------------------------------------------------------------
-- Show / Hide Lust (idempotent — safe to call repeatedly)
---------------------------------------------------------------------------------
function BLT:ShowLust()
    if self._shown then return end
    self._shown = true
    self._renderedMode = self.db.Mode

    if self.db.Mode == "pedro" then
        -- Default: play once. Raid combat briefly evicts sounds from the audio
        -- channel, and a retry-loop interprets that as "sound stopped" and
        -- spams re-plays. Matches upstream HighOnHaste v0.5.4 fix (LOOP_SOUND=false).
        if self.db.LoopSound then
            self:StartSoundLoop()
        else
            self:PlaySoundOnce()
        end
    end
    if self.frame then self.frame:Show() end
    self:StartAnimation()
end

function BLT:HideLust()
    if not self._shown then return end
    self._shown = false
    self._renderedMode = nil

    self:StopSoundLoop()
    self:StopAnimation()
    if self.frame and not self.isPreview then
        self.frame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Orchestration
---------------------------------------------------------------------------------
function BLT:SetActive(active)
    if not active and self.lustTimer then
        self:CancelTimer(self.lustTimer)
        self.lustTimer = nil
    end

    if active == self.lustActive then return end
    self.lustActive = active

    if active then
        -- CombatOnly suppresses the initial show until combat starts
        if self.db.CombatOnly and not self.inCombat then
            return
        end
        self:ShowLust()
    else
        self:HideLust()
    end
end

-- Only relevant when CombatOnly is on — toggles visibility based on combat state
function BLT:UpdateCombatVisibility()
    if not self.db.CombatOnly then return end
    if self.isPreview or self.testMode then return end
    if not self.lustActive or not self.frame then return end

    if self.inCombat then
        self:ShowLust()
    else
        self:HideLust()
    end
end

function BLT:StartTimedLust(duration)
    duration = tonumber(duration) or TIMER_DURATION
    if duration <= 0 then
        self:SetActive(false)
        return
    end

    if self.lustTimer then
        self:CancelTimer(self.lustTimer)
        self.lustTimer = nil
    end

    self.endTime = GetTime() + duration
    self:SetActive(true)

    self.lustTimer = self:ScheduleTimer(function()
        self.lustTimer = nil
        if not self.testMode then
            self:SetActive(false)
        end
    end, duration)
end

---------------------------------------------------------------------------------
-- Test Mode
---------------------------------------------------------------------------------
function BLT:SetTestMode(enabled)
    enabled = not not enabled
    if enabled == self.testMode then return end
    self.testMode = enabled

    if self.testTimer then
        self:CancelTimer(self.testTimer)
        self.testTimer = nil
    end

    if enabled then
        -- Stop any current display first so the sound/animation don't overlap
        self:HideLust()

        -- Ensure frame is sized correctly (handles test-from-disabled-module)
        self:ApplySettings()

        -- Save any real lust endTime before stomping it
        self._testSavedEndTime = self.endTime
        self.endTime = GetTime() + TIMER_DURATION

        self:ShowLust()

        self.testTimer = self:ScheduleTimer(function()
            self.testTimer = nil
            self:SetTestMode(false)
        end, TIMER_DURATION)
    else
        -- Hide test display
        self:HideLust()

        -- Restore real lust endTime if it was saved
        if self._testSavedEndTime then
            self.endTime = self._testSavedEndTime
            self._testSavedEndTime = nil
        end

        -- Restore real display: preview first, then actual lust visibility
        if self.isPreview then
            self:ShowPreview()
        elseif self.lustActive then
            -- Real lust was running under the test — re-show
            if not self.db.CombatOnly or self.inCombat then
                self:ShowLust()
            end
        end
    end
end

function BLT:ToggleTestMode()
    self:SetTestMode(not self.testMode)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function BLT:ApplySettings()
    if not self.frame then return end

    self.frame:SetScale(1)
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)

    if self.db.Mode == "pedro" then
        local size = FRAME_SIZE * (self.db.Scale or 0.5)
        self.frame:SetSize(size, size)
        self.spriteTexture:SetTexture(PEDRO_SHEET)
        self:CalculateSpriteSheetLayout()
    else
        KE:ApplyFontToText(self.countdownText, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
        local r, g, b, a = KE:ResolveColor(self.db.CountdownColor, { 1, 1, 1, 1 })
        self.countdownText:SetTextColor(r, g, b, a)
        self.iconFrame:SetSize(self.db.BasicIconSize, self.db.BasicIconSize)
        self.frame:SetSize(self.db.BasicIconSize, self.db.BasicIconSize)
    end

    if self.db.Strata then
        self.frame:SetFrameStrata(self.db.Strata)
    end

    if self.isPreview and not self.testMode then
        self:ShowPreview()
    elseif self._shown and self._renderedMode ~= self.db.Mode then
        -- Mode changed while showing — restart display in new mode
        self:HideLust()
        self:ShowLust()
    end
end

function BLT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "BloodlustTracker", displayName = "Bloodlust Tracker", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "BloodlustTracker",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function BLT:ShowPreview()
    if not self.frame then self:CreateFrames() end
    self:RegWithEditMode()
    self.isPreview = true

    self.frame:SetScale(1)
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)

    if self.db.Mode == "pedro" then
        local size = FRAME_SIZE * (self.db.Scale or 0.5)
        self.frame:SetSize(size, size)
        self.spriteTexture:SetTexture(PEDRO_SHEET)
        self:SetSpriteFrame(0)
        self.spriteTexture:Show()
        self.iconFrame:Hide()
        self.countdownText:Hide()
        HideSoftOutline(self.countdownText)
    else
        self.frame:SetSize(self.db.BasicIconSize, self.db.BasicIconSize)
        self.iconFrame:SetSize(self.db.BasicIconSize, self.db.BasicIconSize)
        self.spriteTexture:Hide()
        self.iconFrame:Show()
        KE:ApplyFontToText(self.countdownText, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
        local r, g, b, a = KE:ResolveColor(self.db.CountdownColor, { 1, 1, 1, 1 })
        self.countdownText:SetTextColor(r, g, b, a)
        self.countdownText:SetText("40")
        self.countdownText:Show()
        ShowSoftOutline(self.countdownText)
    end

    if self.db.Strata then
        self.frame:SetFrameStrata(self.db.Strata)
    end

    self.frame:SetAlpha(1)
    self.frame:Show()
end

function BLT:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    if self.testMode then return end
    if self.db.Enabled and self.lustActive then return end
    self.frame:Hide()
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function BLT:OnAuraChange(_, unit, updateInfo)
    if unit ~= "player" then return end
    if not updateInfo or not updateInfo.addedAuras then return end
    self:CheckAddedAuras(updateInfo.addedAuras)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function BLT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function BLT:OnEnable()
    if not self.db.Enabled then return end

    self:CreateFrames()
    self:RegWithEditMode()

    self:RegisterEvent("UNIT_AURA", "OnAuraChange")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        -- Only sync if not already tracking (handles reload + zone changes)
        if not self.lustActive then
            self:SyncFromExistingAura()
        elseif not self:IsDetectionAllowed() then
            -- Zoned out of allowed area mid-lust
            self:SetActive(false)
        end
    end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        self.inCombat = true
        self:UpdateCombatVisibility()
    end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        self.inCombat = false
        self:UpdateCombatVisibility()
    end)

    -- Initialize combat state
    self.inCombat = InCombatLockdown() and true or false

    C_Timer.After(0.5, function()
        self:ApplySettings()
        if not self.lustActive then
            self:SyncFromExistingAura()
        end
    end)
end

function BLT:OnDisable()
    self:UnregisterAllEvents()

    if self.lustTimer then
        self:CancelTimer(self.lustTimer)
        self.lustTimer = nil
    end
    if self.testTimer then
        self:CancelTimer(self.testTimer)
        self.testTimer = nil
    end
    if self._sheetProbeTimer then
        self:CancelTimer(self._sheetProbeTimer)
        self._sheetProbeTimer = nil
    end

    self:HideLust()
    self.lustActive = false
    self._shown = false
    self.isPreview = false
    self.testMode = false
    self.inCombat = false

    if self.frame then self.frame:Hide() end
end
