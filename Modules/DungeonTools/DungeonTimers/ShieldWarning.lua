-- ╔══════════════════════════════════════════════════════════╗
-- ║  ShieldWarning.lua                                       ║
-- ║  Module: Dungeon Timers (shielded target warning)        ║
-- ║  Purpose: Center text while the player's target is the  ║
-- ║           boss of a shieldSwap pair that has the shield. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DungeonTimers
local DT = KitnEssentials:GetModule("DungeonTimers", true)
if not DT then return end

local Swap = KE._DungeonShieldSwapState

local pcall = pcall
local type = type
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame
local C_Spell = C_Spell
local GetInstanceInfo = GetInstanceInfo
local GetTime = GetTime
local PlaySoundFile = PlaySoundFile
local UIParent = UIParent
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitIsUnit = UnitIsUnit

local TEXT = "SHIELDED TARGET"
local FONT_SIZE = 40
local ICON_GAP = 6
local COLOR = { 1, 0.15, 0.15 }
local OFFSET_Y = 200
local FALLBACK_ICON = 134400
DT.SHIELD_WARNING_DEFAULT_SOUND = "Wrong Target"

local function WarningSettings()
    local profile = KE.db and KE.db.profile
    local db = profile and profile.DungeonTimers
    return db and db.ShieldWarning
end

local function DifficultyId()
    if not GetInstanceInfo then return nil end
    return (select(3, GetInstanceInfo()))
end

local function OnEvent()
    DT:_ShieldWarningUpdate()
end

local function NewIcon(body)
    local px = (KE.GetPixelSize and KE:GetPixelSize()) or 1
    local holder = CreateFrame("Frame", nil, body, "BackdropTemplate")
    holder:SetSize(FONT_SIZE, FONT_SIZE)
    holder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    holder:SetBackdropColor(0, 0, 0, 0.8)
    if KE.AddIconBorders then KE:AddIconBorders(holder) end
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", px, -px)
    icon:SetPoint("BOTTOMRIGHT", -px, px)
    if KE.ApplyIconZoom then KE:ApplyIconZoom(icon) end
    return holder, icon
end

local function SetWarningIcon(frame, iconId)
    local texture = (iconId and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(iconId))
        or FALLBACK_ICON
    frame.leftIcon:SetTexture(texture)
    frame.rightIcon:SetTexture(texture)
end

-- The body carries the visibility, so the text and both icons show together.
function DT:_ShieldWarningFrame()
    local frame = self._shieldWarningFrame
    if frame then return frame end
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetSize(FONT_SIZE * 12, FONT_SIZE + 8)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, OFFSET_Y)
    frame:EnableMouse(false)
    frame:Hide()
    local body = CreateFrame("Frame", nil, frame)
    body:SetAllPoints()
    local text = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(text, "Expressway", FONT_SIZE, "OUTLINE")
    text:SetPoint("CENTER", body, "CENTER", 0, 0)
    text:SetTextColor(COLOR[1], COLOR[2], COLOR[3])
    text:SetText(TEXT)
    local left, leftIcon = NewIcon(body)
    local right, rightIcon = NewIcon(body)
    left:SetPoint("RIGHT", text, "LEFT", -ICON_GAP, 0)
    right:SetPoint("LEFT", text, "RIGHT", ICON_GAP, 0)
    frame.body = body
    frame.leftIcon, frame.rightIcon = leftIcon, rightIcon
    frame:SetScript("OnEvent", OnEvent)
    self._shieldWarningFrame = frame
    return frame
end

-- nil follows the built-in sound; "None" is silent.
function DT:GetShieldWarningSound()
    local db = WarningSettings()
    local pick = db and db.Sound
    if pick == nil then return DT.SHIELD_WARNING_DEFAULT_SOUND end
    if pick == "None" then return nil end
    return pick
end

function DT:SetShieldWarningSound(key)
    local db = WarningSettings()
    if db then db.Sound = key end
end

local function PlayWarningSound()
    local dtdb = DT.db
    if dtdb and dtdb.MutePresetSounds then return end
    local key = DT:GetShieldWarningSound()
    local LSM = KE.LSM
    local file = key and LSM and LSM:Fetch("sound", key)
    if file then PlaySoundFile(file, (dtdb and dtdb.SoundChannel) or "Master") end
end

-- Runs after the encounter's swap state exists; the frame is made on the first
-- pull that wants it.
function DT:_ShieldWarningStart()
    self:_ShieldWarningStop()
    local swap = self._shieldSwap
    local db = WarningSettings()
    if not Swap.WarningWanted(db and db.Enabled, DifficultyId(), swap) then return end
    local frame = self:_ShieldWarningFrame()
    SetWarningIcon(frame, swap.cfg.icon)
    local units = swap.cfg.units
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    frame:RegisterUnitEvent("UNIT_FLAGS", units[1], units[2])
    self._shieldWarningActive = true
    self:_ShieldWarningUpdate()
end

-- The cue lives on the encounter's swap, so a restart within the pull keeps
-- the 3 s gap.
function DT:_ShieldWarningStop()
    self._shieldWarningActive = false
    local swap = self._shieldSwap
    if swap then Swap.NoteShown(swap.cue, false, GetTime()) end
    local frame = self._shieldWarningFrame
    if not frame then return end
    frame:UnregisterAllEvents()
    if not self._shieldWarningPreview then frame:Hide() end
end

-- The text shows only while both bosses are up: once one dies the other loses
-- the shield.
function DT:_ShieldWarningUpdate()
    local frame = self._shieldWarningFrame
    local swap = self._shieldSwap
    if not (frame and self._shieldWarningActive and swap) or self._shieldWarningPreview then return end
    local cue = swap.cue
    local units = swap.cfg.units
    for i = 1, 2 do
        local unit = units[i]
        if not UnitExists(unit) or UnitIsDead(unit) then
            frame:Hide()
            Swap.NoteShown(cue, false, GetTime())
            return
        end
    end
    -- A refused comparison errors or returns nil. A secret answer goes straight
    -- to SetAlphaFromBoolean, which accepts secrets and is not wrapped in pcall.
    local ok, same = pcall(UnitIsUnit, "target", swap.shielded)
    local secret = ok and issecretvalue(same)
    if not ok or (not secret and type(same) ~= "boolean") then
        frame:Hide()
        Swap.NoteShown(cue, false, GetTime())
        return
    end
    frame.body:SetAlphaFromBoolean(same, 1, 0)
    frame:Show()
    -- Only a readable answer can say the text just appeared.
    local shown = nil
    if not secret then shown = same end
    if Swap.NoteShown(cue, shown, GetTime()) then PlayWarningSound() end
end

function DT:ApplyShieldWarningSettings()
    if self._shieldSwap and self._activeEncounterId and self:IsEnabled() then
        self:_ShieldWarningStart()
    else
        self:_ShieldWarningStop()
    end
end

-- The settings row's preview: the real text and icons, steady, until the row
-- loses the selection or the window closes.
function DT:ShowShieldWarningPreview(encId)
    local frame = self:_ShieldWarningFrame()
    local enc = encId and KE.EncounterData and KE.EncounterData[encId]
    local swapCfg = enc and enc.shieldSwap
    SetWarningIcon(frame, type(swapCfg) == "table" and swapCfg.icon or nil)
    self._shieldWarningPreview = true
    frame.body:SetAlpha(1)
    frame:Show()
end

function DT:HideShieldWarningPreview()
    if not self._shieldWarningPreview then return end
    self._shieldWarningPreview = false
    local frame = self._shieldWarningFrame
    if not frame then return end
    if self._shieldWarningActive and self._shieldSwap then
        SetWarningIcon(frame, self._shieldSwap.cfg.icon)
        self:_ShieldWarningUpdate()
    else
        frame:Hide()
    end
end
