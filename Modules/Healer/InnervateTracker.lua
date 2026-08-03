-- ╔══════════════════════════════════════════════════════════╗
-- ║  InnervateTracker.lua                                    ║
-- ║  Module: Innervate Tracker                               ║
-- ║  Purpose: Shows an icon + countdown when Druid           ║
-- ║           Innervate is active on the player. Uses        ║
-- ║           mana-cost polling because Innervate is hidden  ║
-- ║           from UNIT_AURA in Midnight expansion.          ║
-- ║                                                          ║
-- ║  Detection credit: spiritbloom.pro/blog/tracking-buffs-  ║
-- ║  in-midnight by Harrek; reference implementation in      ║
-- ║  MidnightInnervateTracker by Nost.                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class InnervateTracker: AceModule, AceEvent-3.0
local IT = KitnEssentials:NewModule("InnervateTracker", "AceEvent-3.0")

local CreateFrame       = CreateFrame
local GetTime           = GetTime
local InCombatLockdown  = InCombatLockdown
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local UnitClass         = UnitClass
local C_Spell           = C_Spell
local math_floor        = math.floor
local string_format     = string.format

local LCG = LibStub("LibCustomGlow-1.0", true)
local LSM = LibStub("LibSharedMedia-3.0", true)

local INNERVATE_ICON    = 136048   -- Druid Innervate icon
local UPDATE_THROTTLE   = 0.1     -- countdown text refresh rate (seconds)

---------------------------------------------------------------------------------
-- Class gate
-- Innervate can only meaningfully target classes with mana.
-- On non-supported classes the module short-circuits at OnEnable so the
-- polling ticker, event registrations, and frame are never created.
---------------------------------------------------------------------------------
local _, _playerClass = UnitClass("player")
local SUPPORTED = {
    DRUID   = true,
    PALADIN = true,
    PRIEST  = true,
    SHAMAN  = true,
    MONK    = true,
    EVOKER  = true,
}

---------------------------------------------------------------------------------
-- Spec → {spellID, spellID, spellID}
-- Three spells whose mana cost drops to 0 while Innervate is active.
-- Polling three spells per spec filters out single-spell free-cast procs.
---------------------------------------------------------------------------------
local SPEC_SPELLS = {
    [105]  = { 48438, 8936,   774    }, -- Resto Druid:       Wild Growth, Regrowth, Rejuvenation
    [65]   = { 20473, 19750,  82326  }, -- Holy Paladin:      Holy Shock, Flash of Light, Holy Light
    [256]  = { 17,    47540,  2061   }, -- Disc Priest:       PW:Shield, Penance, Flash Heal
    [257]  = { 33076, 527,    596    }, -- Holy Priest:       Prayer of Mending, Purify, Prayer of Healing
    [264]  = { 61295, 1064,   77472  }, -- Resto Shaman:      Riptide, Chain Heal, Healing Wave
    [270]  = { 115151,116670, 124682 }, -- Mistweaver Monk:   Renewing Mist, Vivify, Enveloping Mist
    [1468] = { 361469,355936, 360995 }, -- Preservation Evoker: Living Flame, Dream Breath, Verdant Embrace
}

-- Hardcoded because Innervate's duration cannot be read from the aura API in
-- this expansion. Update this value if Blizzard changes the buff duration.
local BUFF_DUR           = 8      -- Innervate duration (seconds)
local POLL_RATE_ACTIVE   = 0.05   -- 50ms poll while in combat / confirming
local POLL_RATE_IDLE     = 0.50   -- 500ms poll otherwise
local ZERO_CONFIRM_POLLS = 2      -- consecutive zero readings to confirm

-- Hoisted ref for the hot polling path
local C_Spell_GetSpellPowerCost = C_Spell and C_Spell.GetSpellPowerCost

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function IT:UpdateDB()
    self.db = KE.db.profile.InnervateTracker
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function IT:OnInitialize()
    self:UpdateDB()
    self.isSupported = SUPPORTED[_playerClass] == true
    self:SetEnabledState(false)
end

function IT:OnEnable()
    if not self.isSupported then return end
    if not self.db.Enabled then return end

    self:CreateFrame()
    self:ApplySettings()

    -- Spec detection
    self:DetectSpec()
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "DetectSpec")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "DetectSpec")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "DetectSpec")

    -- Combat state (used to tune poll rate)
    self._inCombat = InCombatLockdown() and true or false
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnLeaveCombat")

    -- Reset poll state
    self._pollTimer   = 0
    self._zeroStreak  = 0
    self._wasZero     = false
    self._activePollRate = POLL_RATE_IDLE

    -- EditMode
    self:RegWithEditMode()
end

function IT:OnDisable()
    self:UnregisterAllEvents()
    if self.ticker then self.ticker:SetScript("OnUpdate", nil) end
    self:StopGlow()
    if self.frame and not self.isPreview then self.frame:Hide() end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function IT:CreateFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_InnervateTracker", UIParent)
    frame:SetSize(self.db.IconSize, self.db.IconSize)
    frame:SetFrameStrata(self.db.Strata or "HIGH")
    frame:Hide()
    self.frame = frame

    -- Icon
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(INNERVATE_ICON)
    KE:ApplyIconZoom(icon, 0.08)
    frame.icon = icon

    KE:AddIconBorders(frame)

    -- Label (below icon)
    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    KE:ApplyFontToText(label, self.db.FontFace, self.db.LabelFontSize, self.db.FontOutline)
    label:SetText(self.db.LabelText or "INNERVATE")
    label:SetShadowOffset(0, 0)
    if label._keSoftOutline then label._keSoftOutline:SetShown(false) end
    frame.label = label

    -- Cooldown swipe (visual duration drain)
    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(true)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetDrawBling(false)
    frame.cooldown = cooldown

    -- Timer text (on icon, above swipe)
    local timer = cooldown:CreateFontString(nil, "OVERLAY")
    timer:SetPoint("CENTER", frame, "CENTER", 0, 0)
    KE:ApplyFontToText(timer, self.db.FontFace, self.db.TimerFontSize, self.db.FontOutline)
    timer:SetText("")
    timer:SetShadowOffset(0, 0)
    if timer._keSoftOutline then timer._keSoftOutline:SetShown(false) end
    frame.timer = timer

    -- Visual OnUpdate: only runs while the frame is shown (Innervate active)
    frame._textElapsed = 0
    frame:SetScript("OnUpdate", function(f, dt)
        f._textElapsed = f._textElapsed + dt
        if f._textElapsed < UPDATE_THROTTLE then return end
        f._textElapsed = 0
        IT:UpdateTimer()
    end)

    -- Detection ticker: separate always-running hidden frame
    if not self.ticker then
        local ticker = CreateFrame("Frame")
        ticker:SetScript("OnUpdate", function(_, dt)
            IT:OnPollTick(dt)
        end)
        self.ticker = ticker
    end
end

---------------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------------
function IT:ApplyPosition()
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function IT:ApplySettings()
    self:UpdateDB()
    if not self.frame then return end

    self.frame:SetSize(self.db.IconSize, self.db.IconSize)
    self.frame:SetFrameStrata(self.db.Strata or "HIGH")

    -- Label
    KE:ApplyFontToText(self.frame.label, self.db.FontFace, self.db.LabelFontSize, self.db.FontOutline)
    self.frame.label:SetText(self.db.LabelText or "INNERVATE")
    local lc = self.db.LabelColor or { 1, 1, 1, 1 }
    self.frame.label:SetTextColor(lc[1], lc[2], lc[3], lc[4] or 1)
    if self.db.ShowLabel == false then
        self.frame.label:Hide()
        if self.frame.label._keSoftOutline then self.frame.label._keSoftOutline:SetShown(false) end
    else
        self.frame.label:Show()
        if self.frame.label._keSoftOutline then self.frame.label._keSoftOutline:SetShown(true) end
    end

    -- Timer
    KE:ApplyFontToText(self.frame.timer, self.db.FontFace, self.db.TimerFontSize, self.db.FontOutline)
    local tc = self.db.TimerColor or { 1, 1, 1, 1 }
    self.frame.timer:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
    if self.db.ShowTimer == false then
        self.frame.timer:Hide()
        if self.frame.timer._keSoftOutline then self.frame.timer._keSoftOutline:SetShown(false) end
    else
        self.frame.timer:Show()
        if self.frame.timer._keSoftOutline then self.frame.timer._keSoftOutline:SetShown(true) end
    end

    self:ApplyPosition()

    -- Re-apply glow to reflect current settings. During preview (or while a
    -- live glow is running) stop+restart so enable/disable/type/color changes
    -- show immediately; StartGlow self-gates on GlowEnabled.
    if self.isPreview or self.glowActive then
        self:StopGlow()
        self:StartGlow()
    end
end

---------------------------------------------------------------------------------
-- EditMode
---------------------------------------------------------------------------------
function IT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key         = "InnervateTracker",
            displayName = "Innervate Tracker",
            frame       = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "HealerTools",
            guiTab = "InnervateTracker",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Innervate detection via mana cost polling
-- C_Spell.GetSpellPowerCost returns 0 on all three spec-specific heal spells
-- while Innervate is active. Three-spell confirmation filters single-spell
-- free-cast procs which only zero one spell's cost.
---------------------------------------------------------------------------------
local function GetSpellCost(spellId)
    if not C_Spell_GetSpellPowerCost then return nil end
    local costs = C_Spell_GetSpellPowerCost(spellId)
    if not costs then return nil end
    for i = 1, #costs do
        local entry = costs[i]
        if entry and entry.cost ~= nil then
            return entry.cost
        end
    end
    return nil
end

function IT:ThreeZero()
    if not self.currentSpells then return false end
    local c1 = GetSpellCost(self.currentSpells[1])
    local c2 = GetSpellCost(self.currentSpells[2])
    local c3 = GetSpellCost(self.currentSpells[3])
    return (c1 ~= nil and c1 == 0)
       and (c2 ~= nil and c2 == 0)
       and (c3 ~= nil and c3 == 0)
end

function IT:DetectSpec()
    self.currentSpells = nil
    self.currentSpecID = nil
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return end
    local specID = GetSpecializationInfo(specIndex)
    self.currentSpecID = specID
    self.currentSpells = specID and SPEC_SPELLS[specID] or nil
end

function IT:OnEnterCombat()
    self._inCombat = true
end

function IT:OnLeaveCombat()
    self._inCombat = false
end

function IT:OnPollTick(dt)
    self._pollTimer = (self._pollTimer or 0) + dt
    if self._pollTimer < (self._activePollRate or POLL_RATE_IDLE) then return end
    self._pollTimer = 0

    -- No-op on unsupported specs
    if not self.currentSpells then
        self._zeroStreak = 0
        self._wasZero = false
        self._activePollRate = POLL_RATE_IDLE
        return
    end

    local isZero = self:ThreeZero()
    if isZero then
        self._zeroStreak = (self._zeroStreak or 0) + 1
        self._activePollRate = POLL_RATE_ACTIVE
        if self._zeroStreak >= ZERO_CONFIRM_POLLS and not self._wasZero then
            self._wasZero = true
            self:OnInnervateDetected()
        end
    else
        self._zeroStreak = 0
        self._wasZero = false
        -- Stay on active poll rate during combat (Innervate could arrive any time)
        self._activePollRate = self._inCombat and POLL_RATE_ACTIVE or POLL_RATE_IDLE
    end
end

function IT:OnInnervateDetected()
    if not self.frame then
        self:CreateFrame()
        self:ApplySettings()
    end
    self.frame.icon:SetTexture(INNERVATE_ICON)
    self.endTime = GetTime() + BUFF_DUR
    self.duration = BUFF_DUR
    self.frame:Show()
    if self.frame.cooldown then
        self.frame.cooldown:SetCooldown(GetTime(), BUFF_DUR)
    end
    self:UpdateTimer()
    self:StartGlow()
    self:PlayAlertSound(self.db.actionOnShowSound)
end

function IT:HideFrame()
    if self.isPreview then return end
    local wasShown = self.frame and self.frame:IsShown()
    self.endTime = 0
    self.duration = 0
    self._lastTimerStr = nil
    if self.frame then
        self.frame.timer:SetText("")
        if self.frame.timer._keSoftOutline then self.frame.timer._keSoftOutline:SetShown(false) end
        if self.frame.cooldown and self.frame.cooldown.Clear then
            self.frame.cooldown:Clear()
        end
        self.frame:Hide()
    end
    self:StopGlow()
    if wasShown then
        self:PlayAlertSound(self.db.actionOnHideSound)
    end
end

---------------------------------------------------------------------------------
-- Glow (LibCustomGlow)
---------------------------------------------------------------------------------
function IT:StartGlow()
    if not self.frame then return end
    if not self.db.GlowEnabled then return end
    if not LCG then return end

    local db = self.db
    local glowType = db.GlowType

    if glowType == "pixel" then
        LCG.PixelGlow_Start(self.frame, db.GlowColor, db.GlowLines, db.GlowFrequency,
            db.GlowLength, db.GlowThickness, 0, 0, db.GlowBorder, nil)
    elseif glowType == "autocast" then
        LCG.AutoCastGlow_Start(self.frame, db.GlowColor, db.GlowLines,
            db.GlowFrequency, db.GlowScale, 1, 1, nil)
    elseif glowType == "button" then
        LCG.ButtonGlow_Start(self.frame, db.GlowColor, db.GlowFrequency)
    elseif glowType == "proc" then
        LCG.ProcGlow_Start(self.frame, {
            color     = db.GlowColor,
            startAnim = db.GlowStartAnim,
            duration  = db.GlowDuration,
        })
    end

    self.glowActive = true
end

function IT:StopGlow()
    if not self.frame then return end
    if not LCG then return end

    LCG.PixelGlow_Stop(self.frame)
    LCG.AutoCastGlow_Stop(self.frame)
    LCG.ButtonGlow_Stop(self.frame)
    LCG.ProcGlow_Stop(self.frame)

    self.glowActive = false
end

---------------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------------
function IT:PlayAlertSound(soundName)
    if not soundName or soundName == "None" then return end
    if not LSM then return end
    local path = LSM:Fetch("sound", soundName)
    if path then PlaySoundFile(path, "Master") end
end

---------------------------------------------------------------------------------
-- Timer countdown
-- GetTime() is NOT a secret value — last-string SetText gating is safe here.
-- Format mirrors the reference: integer when >=3s remain, 1 decimal under 3s.
---------------------------------------------------------------------------------
function IT:UpdateTimer()
    if not self.frame or not self.frame:IsShown() then return end
    -- Preview shows a static "8.0" set by ShowPreview; skip the live countdown
    -- (which would tick to 0 and then freeze) while previewing.
    if self.isPreview then return end
    if self.db.ShowTimer == false then
        if self.frame.timer:GetText() ~= "" then
            self.frame.timer:SetText("")
            if self.frame.timer._keSoftOutline then self.frame.timer._keSoftOutline:SetShown(false) end
        end
        return
    end

    local remaining = (self.endTime or 0) - GetTime()
    if remaining <= 0 then
        self:HideFrame()
        return
    end

    local s
    if remaining >= 3 then
        s = string_format("%d", math_floor(remaining + 0.5))
    else
        s = string_format("%.1f", remaining)
    end

    -- Last-string gating: GetTime-derived, not secret — safe to apply.
    if s ~= self._lastTimerStr then
        self._lastTimerStr = s
        self.frame.timer:SetText(s)
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function IT:ShowPreview()
    if not self.isSupported then return end
    if not self.frame then
        self:CreateFrame()
        self:ApplySettings()
    end
    self.isPreview = true
    self.endTime = GetTime() + BUFF_DUR  -- keeps timer running during preview
    self.frame.icon:SetTexture(INNERVATE_ICON)
    self.frame.label:SetText(self.db.LabelText or "INNERVATE")
    if self.db.ShowLabel ~= false then
        self.frame.label:Show()
        if self.frame.label._keSoftOutline then self.frame.label._keSoftOutline:SetShown(true) end
    end
    self.frame.timer:SetText("8.0")
    if self.db.ShowTimer ~= false then
        self.frame.timer:Show()
        if self.frame.timer._keSoftOutline then self.frame.timer._keSoftOutline:SetShown(true) end
    end
    self.frame:SetAlpha(1)
    self.frame:Show()
    self:StartGlow()  -- glow reflects the user's settings during preview too
end

function IT:HidePreview()
    self.isPreview = false
    self._lastTimerStr = nil
    self:StopGlow()
    if self.frame then self.frame:Hide() end
end

function IT:TogglePreview()
    if self.isPreview then
        self:HidePreview()
    else
        self:ShowPreview()
    end
    return self.isPreview
end

function IT:IsPreviewActive()
    return self.isPreview == true
end
