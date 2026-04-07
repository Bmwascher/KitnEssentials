-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Create module
---@class BloodlustTracker: AceModule, AceEvent-3.0, AceTimer-3.0
local BLT = KitnEssentials:NewModule("BloodlustTracker", "AceEvent-3.0", "AceTimer-3.0")

-- Localization
local GetTime = GetTime
local CreateFrame = CreateFrame
local UnitSpellHaste = UnitSpellHaste
local IsInInstance = IsInInstance
local PlaySoundFile = PlaySoundFile
local StopSound = StopSound
local C_Sound = C_Sound
local C_UnitAuras = C_UnitAuras
local C_Timer = C_Timer
local pairs = pairs
local math_floor = math.floor
local math_max = math.max


--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------
local TIMER_DURATION = 40
local BASE_FPS = 15
local FRAME_SIZE = 256
local HASTE_POLL_INTERVAL = 0.20
local START_RATIO_MIN = 1.27
local END_RATIO_MAX = 1.24
local BLOODLUST_ICON = 136012

local MEDIA_PATH = "Interface\\AddOns\\KitnEssentials\\Media\\BloodlustTracker\\"

local SATED_DEBUFFS = {
    [57723]  = true, -- Exhaustion (Heroism)
    [57724]  = true, -- Sated (Bloodlust)
    [80354]  = true, -- Temporal Displacement (Time Warp)
    [95809]  = true, -- Insanity (Ancient Hysteria)
    [160455] = true, -- Fatigued (Netherwinds)
    [264689] = true, -- Fatigued (Primal Rage)
    [390435] = true, -- Exhaustion (Fury of the Aspects)
}

local PRESETS = {
    pedro       = { label = "Pedro",         sheet = "pedro.tga",       sound = "pedro.mp3",       frames = 64, fpsRatio = 0.8, loop = true },
    chipi       = { label = "Chipi Chipi",   sheet = "chipi.tga",       sound = "chipi.mp3",       frames = 14, fpsRatio = 1.1, loop = true },
    ninemm      = { label = "9MM Bang",      sound = "9mm.mp3", soundOnly = true, loop = false },
    erm         = { label = "Sarah Gamer Word", sound = "ERM.mp3",       soundOnly = true, loop = false },
}

local PRESET_ORDER = { "pedro", "chipi", "ninemm", "erm" }

-- Expose for GUI
BLT.PRESETS = PRESETS
BLT.PRESET_ORDER = PRESET_ORDER

--------------------------------------------------------------------------------
-- Module state
--------------------------------------------------------------------------------
BLT.frame = nil
BLT.spriteTexture = nil
BLT.iconTexture = nil
BLT.countdownText = nil
BLT.isPreview = false
BLT.testMode = false
BLT.lustActive = false
BLT.endTime = 0

-- Animation state
BLT.animAccum = 0
BLT.frameIndex = 0
BLT.secondsPerFrame = 1 / BASE_FPS
BLT.sheetW = 0
BLT.sheetH = 0
BLT.framesPerRow = 0
BLT.sheetRows = 0
BLT.numFrames = 0

-- Sound state
BLT.soundHandle = nil
BLT.soundLoopTimer = nil
BLT.soundEndTimer = nil

-- Haste detection state
BLT.lastFactor = nil
BLT.preLustFactor = nil
BLT.pollTimer = nil
BLT.hadLustDebuff = nil
BLT.lustTimer = nil

-- Sheet probing
BLT._sheetProbeTimer = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function FloorDiv(a, b)
    if type(a) ~= "number" or type(b) ~= "number" or b <= 0 then return 0 end
    return math_floor((a / b) + 1e-6)
end

local function GetPreset(presetId)
    return PRESETS[presetId] or PRESETS.pedro
end

--------------------------------------------------------------------------------
-- Sheet probing (auto-detect grid from TGA dimensions)
--------------------------------------------------------------------------------
function BLT:ComputeSheetLayoutFromDims(sheetW, sheetH, preset)
    -- Allow presets to hardcode cols/rows for non-standard grids
    local cols, rows
    if preset.cols and preset.rows then
        cols = preset.cols
        rows = preset.rows
    else
        local frameSize = preset.frameSize or FRAME_SIZE
        cols = FloorDiv(sheetW, frameSize)
        rows = FloorDiv(sheetH, frameSize)
    end
    local capacity = cols * rows
    local numFrames = (type(preset.frames) == "number" and preset.frames > 0)
        and math.min(preset.frames, capacity) or capacity

    return sheetW, sheetH, cols, rows, numFrames
end

function BLT:CalculateSpriteSheetLayout()
    local preset = GetPreset(self.db.Preset)
    if preset.soundOnly then return end
    if self._sheetProbeTimer then return false end

    local path = MEDIA_PATH .. preset.sheet
    local probe = UIParent:CreateTexture(nil, "BACKGROUND")
    probe:SetTexture(path)

    self._sheetProbeTimer = self:ScheduleRepeatingTimer(function()
        if probe.IsObjectLoaded and probe:IsObjectLoaded() then
            local w, h = probe:GetSize()

            -- Cleanup
            probe:SetTexture(nil)
            if self._sheetProbeTimer then
                self:CancelTimer(self._sheetProbeTimer)
                self._sheetProbeTimer = nil
            end

            -- Sanity
            if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
                w, h = FRAME_SIZE, FRAME_SIZE
            end

            local sheetW, sheetH, cols, rows, numFrames = self:ComputeSheetLayoutFromDims(w, h, preset)
            self.sheetW = sheetW
            self.sheetH = sheetH
            self.framesPerRow = cols
            self.sheetRows = rows
            self.numFrames = numFrames
        end
    end, 0.05)
end

--------------------------------------------------------------------------------
-- Update db
--------------------------------------------------------------------------------
function BLT:UpdateDB()
    self.db = KE.db.profile.BloodlustTracker
end

--------------------------------------------------------------------------------
-- Frame creation
--------------------------------------------------------------------------------
function BLT:CreateFrames()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_BloodlustTracker", UIParent)
    frame:SetSize(FRAME_SIZE, FRAME_SIZE)
    frame:Hide()

    -- Sprite texture for animated mode
    local sprite = frame:CreateTexture(nil, "ARTWORK")
    sprite:SetAllPoints()
    sprite:Hide()

    -- Icon container for basic mode (separate frame for borders)
    local iconFrame = CreateFrame("Frame", nil, frame)
    iconFrame:SetSize(self.db.BasicIconSize, self.db.BasicIconSize)
    iconFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)
    iconFrame:Hide()

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(iconFrame)
    icon:SetTexture(BLOODLUST_ICON)
    KE:ApplyIconZoom(icon)
    KE:AddIconBorders(iconFrame)

    -- Countdown text for basic mode (on iconFrame, above borders)
    local text = iconFrame:CreateFontString(nil, "OVERLAY", nil, 8)
    local fontPath = KE:GetFontPath(self.db.FontFace)
    text:SetFont(fontPath, self.db.FontSize, KE:GetFontOutline(self.db.FontOutline) or "")
    text:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    text:Hide()

    self.frame = frame
    self.spriteTexture = sprite
    self.iconFrame = iconFrame
    self.iconTexture = icon
    self.countdownText = text
end

--------------------------------------------------------------------------------
-- Soft outline helper
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Sprite animation
--------------------------------------------------------------------------------
function BLT:SetSpriteFrame(i)
    local tex = self.spriteTexture
    if not tex or not self.framesPerRow or self.framesPerRow == 0 or self.sheetW == 0 or self.sheetH == 0 then return end

    i = i % self.numFrames

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

    local preset = GetPreset(self.db.Preset)
    local frameCount = self.numFrames or preset.frames or 1
    local lastFrame = frameCount - 1

    while self.animAccum >= self.secondsPerFrame do
        self.animAccum = self.animAccum - self.secondsPerFrame

        if preset.loop then
            self.frameIndex = (self.frameIndex + 1) % frameCount
            self:SetSpriteFrame(self.frameIndex)
        else
            if self.frameIndex < lastFrame then
                self.frameIndex = self.frameIndex + 1
                self:SetSpriteFrame(self.frameIndex)
            else
                self:StopAnimation()
                if self.testMode then
                    self:SetTestMode(false)
                elseif not self.isPreview then
                    self.frame:Hide()
                end
                break
            end
        end
    end
end

function BLT:StartAnimation()
    if not self.frame then return end

    local preset = GetPreset(self.db.Preset)
    self.animAccum = 0
    self.frameIndex = 0

    if self.db.DisplayMode == "animated" and not preset.soundOnly then
        -- Animated sprite mode
        self.secondsPerFrame = 1 / math_max(1, (BASE_FPS * (preset.fpsRatio or 1)))
        local path = MEDIA_PATH .. preset.sheet
        self.spriteTexture:SetTexture(path)
        self:SetSpriteFrame(0)
        self.spriteTexture:Show()
        self.iconFrame:Hide()
        self.countdownText:Hide()
        HideSoftOutline(self.countdownText)

        self.frame:SetScript("OnUpdate", function(_, dt)
            self:AnimOnUpdate(dt)
        end)
    else
        -- Basic mode OR sound-only preset: icon + countdown
        self.spriteTexture:Hide()
        self.iconFrame:Show()
        self.countdownText:Show()
        ShowSoftOutline(self.countdownText)

        local color = self.db.CountdownColor or { 1, 1, 1, 1 }
        self.countdownText:SetTextColor(color[1], color[2], color[3], color[4] or 1)

        self.frame:SetScript("OnUpdate", function(_, dt)
            self:BasicOnUpdate(dt)
        end)
    end
end

function BLT:StopAnimation()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
    end
    self.animAccum = 0
end

--------------------------------------------------------------------------------
-- Basic mode countdown
--------------------------------------------------------------------------------
function BLT:BasicOnUpdate(dt)
    self.animAccum = self.animAccum + dt
    if self.animAccum < 0.1 then return end
    self.animAccum = 0

    local remaining = self.endTime - GetTime()
    if remaining <= 0 then
        if not self.testMode then
            self:StopBloodlust()
        end
        return
    end

    self.countdownText:SetText(string.format("%d", remaining))
end

--------------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------------
function BLT:PlaySoundOnce()
    if not self.db.SoundEnabled then return end

    local preset = GetPreset(self.db.Preset)
    local soundPath = MEDIA_PATH .. preset.sound
    local willPlay, handle = PlaySoundFile(soundPath, self.db.SoundChannel or "Master")

    if willPlay and handle then
        self.soundHandle = handle
    end

    return willPlay, handle
end

function BLT:StartSoundLoop()
    if self.soundLoopTimer then
        self:CancelTimer(self.soundLoopTimer)
        self.soundLoopTimer = nil
    end
    if self.soundEndTimer then
        self:CancelTimer(self.soundEndTimer)
        self.soundEndTimer = nil
    end

    self:PlaySoundOnce()

    local preset = GetPreset(self.db.Preset)

    if not preset.loop then
        -- One-shot: poll until sound finishes
        self.soundEndTimer = self:ScheduleRepeatingTimer(function()
            local handle = self.soundHandle
            local playing = false
            if handle and C_Sound and C_Sound.IsPlaying then
                playing = C_Sound.IsPlaying(handle)
            end
            if not playing then
                if self.soundEndTimer then
                    self:CancelTimer(self.soundEndTimer)
                    self.soundEndTimer = nil
                end
                self.soundHandle = nil
                if self.testMode then
                    self:SetTestMode(false)
                end
            end
        end, 0.05)
        return
    end

    -- Looping: re-play when sound finishes
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
        if not playing then
            self:PlaySoundOnce()
        end
    end, 0.10)
end

function BLT:StopSoundLoop()
    if self.soundLoopTimer then
        self:CancelTimer(self.soundLoopTimer)
        self.soundLoopTimer = nil
    end
    if self.soundEndTimer then
        self:CancelTimer(self.soundEndTimer)
        self.soundEndTimer = nil
    end
    if self.soundHandle then
        StopSound(self.soundHandle, 150)
        self.soundHandle = nil
    end
end

--------------------------------------------------------------------------------
-- Detection: sated debuff
--------------------------------------------------------------------------------
function BLT:GetPlayerDebuffBySpellID(spellID)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    end
end

function BLT:FindLustLockoutAura()
    for spellID in pairs(SATED_DEBUFFS) do
        local aura = self:GetPlayerDebuffBySpellID(spellID)
        if aura then
            aura.spellId = aura.spellId or spellID
            return aura
        end
    end
end

function BLT:UpdateDebuffDetection(isStartupSync)
    if self.testMode then return end
    if not self:IsDetectionAllowed() then
        self.hadLustDebuff = nil
        self:SetActive(false)
        return
    end

    local aura = self:FindLustLockoutAura()
    local hasDebuff = aura ~= nil

    if aura and aura.duration and aura.duration > 0 and aura.expirationTime and aura.expirationTime > 0 then
        local startedAt = aura.expirationTime - aura.duration
        local remaining = (startedAt + TIMER_DURATION) - GetTime()

        self.hadLustDebuff = true

        if remaining > 0 then
            self:StartTimedLust(remaining)
        else
            self:SetActive(false)
        end
        return
    end

    if isStartupSync then
        self.hadLustDebuff = hasDebuff
        return
    end

    if hasDebuff and not self.hadLustDebuff then
        self:StartTimedLust(TIMER_DURATION)
    end

    self.hadLustDebuff = hasDebuff
end

--------------------------------------------------------------------------------
-- Detection: haste approximation
--------------------------------------------------------------------------------
function BLT:GetHasteFactor()
    local hastePct = UnitSpellHaste("player") or 0
    return 1 + (hastePct / 100)
end

function BLT:UpdateHasteApproxDetection()
    if self.testMode then
        self.lastFactor = self:GetHasteFactor()
        return
    end

    if not self:IsDetectionAllowed() then
        self.lastFactor = nil
        self.preLustFactor = nil
        self:SetActive(false)
        return
    end

    local cur = self:GetHasteFactor()

    if not self.lastFactor then
        self.lastFactor = cur
        return
    end

    local ratio = cur / self.lastFactor

    if not self.lustActive then
        if ratio >= START_RATIO_MIN then
            self.preLustFactor = self.lastFactor
            self:SetActive(true)
        end
    else
        if self.preLustFactor and cur <= (self.preLustFactor * END_RATIO_MAX) then
            self.preLustFactor = nil
            self:SetActive(false)
        end
    end

    self.lastFactor = cur
end

--------------------------------------------------------------------------------
-- Detection: shared
--------------------------------------------------------------------------------
function BLT:IsDetectionAllowed()
    if not self.db.InstanceOnly then return true end
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

function BLT:UpdateDetection()
    if self.db.HasteApproxEnabled then
        self:UpdateHasteApproxDetection()
    else
        self:UpdateDebuffDetection(false)
    end
end

function BLT:RefreshDetectionState()
    self:ResetDetectionState()
    if self.db.HasteApproxEnabled then
        self:UpdateHasteApproxDetection()
    else
        self:UpdateDebuffDetection(true)
    end
end

function BLT:ResetDetectionState()
    self.lastFactor = nil
    self.preLustFactor = nil
    self.hadLustDebuff = nil

    if self.lustTimer then
        self:CancelTimer(self.lustTimer)
        self.lustTimer = nil
    end

    if not self.testMode then
        self:SetActive(false)
    end
end

--------------------------------------------------------------------------------
-- Orchestration
--------------------------------------------------------------------------------
function BLT:SetActive(active)
    if not active and self.lustTimer then
        self:CancelTimer(self.lustTimer)
        self.lustTimer = nil
    end

    if active == self.lustActive then return end
    self.lustActive = active

    if active then
        if self.db.DisplayMode == "animated" then
            self:StartSoundLoop()
        end
        self.frame:Show()
        self:StartAnimation()
    else
        self:StopSoundLoop()
        self:StopAnimation()
        if self.frame and not self.isPreview then
            self.frame:Hide()
        end
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

function BLT:StartBloodlust()
    self:StartTimedLust(TIMER_DURATION)
end

function BLT:StopBloodlust()
    self.lustActive = false
    self:StopAnimation()
    self:StopSoundLoop()
    if self.lustTimer then
        self:CancelTimer(self.lustTimer)
        self.lustTimer = nil
    end
    if self.frame and not self.isPreview then
        self.frame:Hide()
    end
end

--------------------------------------------------------------------------------
-- Haste poll timer
--------------------------------------------------------------------------------
function BLT:ReschedulePollTimer()
    if self.pollTimer then
        self:CancelTimer(self.pollTimer)
        self.pollTimer = nil
    end

    if not self.db.HasteApproxEnabled then return end

    self.pollTimer = self:ScheduleRepeatingTimer("UpdateHasteApproxDetection", HASTE_POLL_INTERVAL)
end

--------------------------------------------------------------------------------
-- Test mode
--------------------------------------------------------------------------------
function BLT:SetTestMode(enabled)
    enabled = not not enabled
    if enabled == self.testMode then return end
    self.testMode = enabled

    -- Cancel any existing test timer
    if self.testTimer then
        self:CancelTimer(self.testTimer)
        self.testTimer = nil
    end

    if enabled then
        self.endTime = GetTime() + TIMER_DURATION
        self:SetActive(true)

        -- Auto-stop after 40s (needed for looping presets)
        self.testTimer = self:ScheduleTimer(function()
            self.testTimer = nil
            self:SetTestMode(false)
        end, TIMER_DURATION)
    else
        self:SetActive(false)
        self.lastFactor = self:GetHasteFactor()
        self.preLustFactor = nil
        -- Restore preview state or hide frame
        if self.isPreview then
            self:ShowPreview()
        elseif self.frame then
            self.frame:Hide()
        end
    end
end

function BLT:ToggleTestMode()
    self:SetTestMode(not self.testMode)
end

--------------------------------------------------------------------------------
-- Apply settings
--------------------------------------------------------------------------------
function BLT:ApplySettings()
    if not self.frame then return end

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)

    local preset = GetPreset(self.db.Preset)
    local useSprite = self.db.DisplayMode == "animated" and not preset.soundOnly

    -- Scale only applies in animated sprite mode
    if useSprite then
        self.frame:SetScale(self.db.Scale or 0.5)
    else
        self.frame:SetScale(1)
    end

    if self.db.Strata then
        self.frame:SetFrameStrata(self.db.Strata)
    end

    -- Mode-specific settings
    if not useSprite then
        KE:ApplyFontToText(self.countdownText, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
        local color = self.db.CountdownColor or { 1, 1, 1, 1 }
        self.countdownText:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        self.iconFrame:SetSize(self.db.BasicIconSize, self.db.BasicIconSize)
        self.frame:SetSize(self.db.BasicIconSize, self.db.BasicIconSize)
    else
        self.frame:SetSize(FRAME_SIZE, FRAME_SIZE)
    end

    -- Apply sprite texture for current preset (skip for soundOnly)
    if preset.sheet then
        self.spriteTexture:SetTexture(MEDIA_PATH .. preset.sheet)
    end

    -- Re-probe sheet layout
    self:CalculateSpriteSheetLayout()

    if self.isPreview then
        self:ShowPreview()
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

--------------------------------------------------------------------------------
-- Preview
--------------------------------------------------------------------------------
function BLT:ShowPreview()
    if not self.frame then
        self:CreateFrames()
    end
    self:RegWithEditMode()

    self.isPreview = true

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)

    local preset = GetPreset(self.db.Preset)
    local useSprite = self.db.DisplayMode == "animated" and not preset.soundOnly

    if useSprite then
        self.frame:SetScale(self.db.Scale or 0.5)
    else
        self.frame:SetScale(1)
    end

    if self.db.Strata then
        self.frame:SetFrameStrata(self.db.Strata)
    end

    if useSprite then
        self.spriteTexture:SetTexture(MEDIA_PATH .. preset.sheet)
        self:SetSpriteFrame(0)
        self.spriteTexture:Show()
        self.iconFrame:Hide()
        self.countdownText:Hide()
        HideSoftOutline(self.countdownText)
    else
        self.spriteTexture:Hide()
        self.iconFrame:Show()
        KE:ApplyFontToText(self.countdownText, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
        local color = self.db.CountdownColor or { 1, 1, 1, 1 }
        self.countdownText:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        self.countdownText:SetText("40")
        self.countdownText:Show()
        ShowSoftOutline(self.countdownText)
    end

    self.frame:SetAlpha(1)
    self.frame:Show()
end

function BLT:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    -- If test is running, let it continue (testTimer will clean up)
    if self.testMode then return end
    -- If real lust is active and module enabled, keep showing
    if self.db.Enabled and self.lustActive then return end
    self.frame:Hide()
end

--------------------------------------------------------------------------------
-- Event handlers
--------------------------------------------------------------------------------
function BLT:OnAuraChange(_, unit)
    if unit ~= "player" then return end
    if self.db.HasteApproxEnabled then return end
    self:UpdateDebuffDetection(false)
end

function BLT:OnHasteChange(_, unit)
    if unit ~= "player" then return end
    self:UpdateDetection()
end

function BLT:OnCombatRatingUpdate()
    self:UpdateDetection()
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------
function BLT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function BLT:OnEnable()
    if not self.db.Enabled then return end

    self:CreateFrames()
    self:RegWithEditMode()
    self:CalculateSpriteSheetLayout()

    -- Register events
    self:RegisterEvent("UNIT_AURA", "OnAuraChange")
    self:RegisterEvent("UNIT_SPELL_HASTE", "OnHasteChange")
    self:RegisterEvent("COMBAT_RATING_UPDATE", "OnCombatRatingUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        self.lustActive = false
        self:RefreshDetectionState()
    end)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
        self:RefreshDetectionState()
    end)

    self:ReschedulePollTimer()

    C_Timer.After(0.5, function()
        self:ApplySettings()
        self:RefreshDetectionState()
    end)
end

function BLT:OnDisable()
    self:UnregisterAllEvents()
    self:StopBloodlust()

    if self.testTimer then
        self:CancelTimer(self.testTimer)
        self.testTimer = nil
    end
    if self.pollTimer then
        self:CancelTimer(self.pollTimer)
        self.pollTimer = nil
    end
    if self._sheetProbeTimer then
        self:CancelTimer(self._sheetProbeTimer)
        self._sheetProbeTimer = nil
    end

    if self.frame then self.frame:Hide() end
    self.isPreview = false
    self.testMode = false
end
