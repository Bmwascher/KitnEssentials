-- ╔══════════════════════════════════════════════════════════╗
-- ║  TimeSpiral.lua                                          ║
-- ║  Module: Time Spiral Tracker                             ║
-- ║  Purpose: Movement spell proc tracker with glow effects  ║
-- ║           and cooldown spiral. All classes supported.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class TimeSpiral: AceModule, AceEvent-3.0
local TSP = KitnEssentials:NewModule("TimeSpiral", "AceEvent-3.0")

local LCG = LibStub("LibCustomGlow-1.0", true)

local CreateFrame = CreateFrame
local C_SpellBook = C_SpellBook
local SpellBookBank_Player = Enum.SpellBookSpellBank.Player
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local GetTime = GetTime
local pairs = pairs
local next = next

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
TSP.activeProcs = {}
TSP.durationObject = nil

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local TIME_SPIRAL_ICON = 4622479
local TIME_SPIRAL_DURATION = 10.5

-- Per-spec movement spell priority list. Each entry is { spellID, iconID }
-- in priority order. DetectPlayerSpell picks the first entry where the
-- player has the spell (via IsPlayerSpell). Specs with talent alternates
-- (Druid Dash/Tiger Dash, Mage Blink/Shimmer, Monk Roll/Chi Torpedo,
-- Shaman Gust of Wind/Spirit Walk/Spiritwalker's Grace) list multiple
-- entries so detection works regardless of which talent the player took.
-- Adapted from NorskenUI v3.5 Core/Constants.lua + KE-specific extensions.
local PRIMARY_BY_SPEC = {
    -- Death Knight
    [250]  = { { 48265, 237561 } },                                    -- Blood: Death's Advance
    [251]  = { { 48265, 237561 } },                                    -- Frost: Death's Advance
    [252]  = { { 48265, 237561 } },                                    -- Unholy: Death's Advance
    -- Demon Hunter
    [577]  = { { 195072, 1247261 } },                                  -- Havoc: Fel Rush
    [581]  = { { 189110, 1344650 } },                                  -- Vengeance: Infernal Strike
    [1480] = { { 1234796, 7554213 } },                                 -- Devourer: Shift
    -- Druid (Dash > Tiger Dash)
    [102]  = { { 1850, 132120 }, { 252216, 1817485 } },                -- Balance
    [103]  = { { 1850, 132120 }, { 252216, 1817485 } },                -- Feral
    [104]  = { { 1850, 132120 }, { 252216, 1817485 } },                -- Guardian
    [105]  = { { 1850, 132120 }, { 252216, 1817485 } },                -- Restoration
    -- Evoker
    [1467] = { { 358267, 4622463 } },                                  -- Devastation: Hover
    [1468] = { { 358267, 4622463 } },                                  -- Preservation: Hover
    [1473] = { { 358267, 4622463 } },                                  -- Augmentation: Hover
    -- Hunter
    [253]  = { { 186257, 132242 } },                                   -- Beast Mastery: Cheetah
    [254]  = { { 186257, 132242 } },                                   -- Marksmanship: Cheetah
    [255]  = { { 186257, 132242 } },                                   -- Survival: Cheetah
    -- Mage (Blink > Shimmer)
    [62]   = { { 1953, 135736 }, { 212653, 135739 } },                 -- Arcane
    [63]   = { { 1953, 135736 }, { 212653, 135739 } },                 -- Fire
    [64]   = { { 1953, 135736 }, { 212653, 135739 } },                 -- Frost
    -- Monk (Roll > Chi Torpedo)
    [268]  = { { 109132, 574574 }, { 115008, 607849 } },               -- Brewmaster
    [270]  = { { 109132, 574574 }, { 115008, 607849 } },               -- Mistweaver
    [269]  = { { 109132, 574574 }, { 115008, 607849 } },               -- Windwalker
    -- Paladin
    [65]   = { { 190784, 1360759 } },                                  -- Holy: Divine Steed
    [66]   = { { 190784, 1360759 } },                                  -- Protection: Divine Steed
    [70]   = { { 190784, 1360759 } },                                  -- Retribution: Divine Steed
    -- Priest
    [256]  = { { 73325, 463835 } },                                    -- Discipline: Leap of Faith
    [257]  = { { 73325, 463835 } },                                    -- Holy: Leap of Faith
    [258]  = { { 73325, 463835 } },                                    -- Shadow: Leap of Faith
    -- Rogue
    [259]  = { { 2983, 132307 } },                                     -- Assassination: Sprint
    [260]  = { { 2983, 132307 } },                                     -- Outlaw: Sprint
    [261]  = { { 2983, 132307 } },                                     -- Subtlety: Sprint
    -- Shaman: Gust of Wind / Spirit Walk are talent-choice (mutually
    -- exclusive); Spiritwalker's Grace is a separate talent stackable
    -- on top. Per-spec priority reflects typical spec preference, with
    -- the alternates listed as fallbacks so detection always lands on
    -- something the player actually has.
    [262]  = { { 79206, 451170 }, { 192063, 463565 }, { 58875, 132328 } }, -- Elemental: SWG > GoW > SW
    [263]  = { { 58875, 132328 }, { 192063, 463565 }, { 79206, 451170 } }, -- Enhancement: SW > GoW > SWG
    [264]  = { { 79206, 451170 }, { 192063, 463565 }, { 58875, 132328 } }, -- Restoration: SWG > GoW > SW
    -- Warlock
    [265]  = { { 48020, 237560 } },                                    -- Affliction: Demonic Circle: Teleport
    [266]  = { { 48020, 237560 } },                                    -- Demonology: Demonic Circle: Teleport
    [267]  = { { 48020, 237560 } },                                    -- Destruction: Demonic Circle: Teleport
    -- Warrior
    [71]   = { { 6544, 236171 } },                                     -- Arms: Heroic Leap
    [72]   = { { 6544, 236171 } },                                     -- Fury: Heroic Leap
    [73]   = { { 6544, 236171 } },                                     -- Protection: Heroic Leap
}

-- Built once in OnEnable from PRIMARY_BY_SPEC. Used by the
-- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE handlers as an O(1) filter, and
-- to look up the icon to swap to when an alternate spell procs.
local MOVEMENT_SPELL_FILTER -- spellID -> iconID

local FILTER_TALENTS = {
    [427640] = { [195072] = true }, -- Inertia
    [427794] = { [195072] = true }, -- Dash of Chaos
    [385899] = { [385899] = true }, -- Soulburn
}

-- C_SpellBook.IsSpellKnown alone misses some talents (especially capstone-style
-- nodes like Spiritwalker's Grace) — full check uses IsSpellInSpellBook and
-- IsSpellUsable as backstops.
local function IsTalentKnown(talentId)
    if C_SpellBook.IsSpellKnown(talentId, SpellBookBank_Player) then return true end
    if C_SpellBook.IsSpellInSpellBook(talentId, SpellBookBank_Player) then return true end

    local spellInfo = C_Spell.GetSpellInfo(talentId)
    if spellInfo and C_Spell.IsSpellUsable(talentId) then
        return true
    end
    return false
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function TSP:UpdateDB()
    self.db = KE.db.profile.TimeSpiral
end

function TSP:DetectPlayerSpell()
    local specID = GetSpecializationInfo(GetSpecialization() or 0)
    if not specID then return nil end

    local list = PRIMARY_BY_SPEC[specID]
    if not list then return nil end

    -- C_SpellBook.IsSpellKnown only — IsSpellInSpellBook / IsSpellUsable return
    -- true for any spell defined in the class spellbook regardless of whether
    -- the talent is actively selected, which would mis-detect untalented spells.
    for _, entry in ipairs(list) do
        local spellID, iconID = entry[1], entry[2]
        if C_SpellBook.IsSpellKnown(spellID, SpellBookBank_Player) then
            self.playerSpellId = spellID
            self.playerIconId = iconID
            return spellID
        end
    end
    return nil
end

function TSP:GetDisplayIcon()
    if self.playerIconId then return self.playerIconId end
    self:DetectPlayerSpell()
    return self.playerIconId or TIME_SPIRAL_ICON
end

function TSP:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function TSP:CreateFrame()
    if self.frame then return end

    local db = self.db
    local size = db.IconSize or 40

    local f = CreateFrame("Frame", "KE_TimeSpiralFrame", UIParent)
    f:SetSize(size, size)
    f:EnableMouse(false)
    f:SetMouseClickEnabled(false)
    f:Hide()

    -- Pixel borders
    KE:AddIconBorders(f)

    -- Icon texture with zoom
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    KE:ApplyIconZoom(f.icon)
    f.icon:SetTexture(self:GetDisplayIcon())

    -- Text below the icon
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(KE.FONT, 12, "")
    f.text:ClearAllPoints()
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.text:SetJustifyH("CENTER")

    -- Cooldown spiral overlay
    local cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cooldown:SetAllPoints(f)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(true)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetDrawBling(false)

    -- Timer text on top of the cooldown swipe
    local timerText = cooldown:CreateFontString(nil, "OVERLAY")
    timerText:SetFont(KE.FONT, 16, "OUTLINE")
    timerText:SetPoint("CENTER", f, "CENTER", 0, 0)
    timerText:SetText("")

    -- Store references
    self.frame = f
    self.icon = f.icon
    self.text = f.text
    self.cooldown = cooldown
    self.timerText = timerText

    self:ApplySettings()
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function TSP:FilterSpell(spellId)
    for talentId, spells in pairs(FILTER_TALENTS) do
        if spells[spellId] and IsTalentKnown(talentId) then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function TSP:ApplySettings()
    if not self.frame then return end
    local db = self.db
    local showText = db.ShowText ~= false

    -- Update frame and icon size
    self.frame:SetSize(db.IconSize, db.IconSize)

    -- Update icon texture
    self.icon:SetTexture(self:GetDisplayIcon())

    -- Update text
    self.text:SetText(db.TextLabel or "FREE")
    KE:ApplyFontToText(self.text, db.FontFace, db.FontSize, db.FontOutline)

    -- Apply text color
    local tr, tg, tb, ta = KE:ResolveColor(db.TextColor, { 1, 1, 1, 1 })
    self.text:SetTextColor(tr, tg, tb, ta)

    if showText then
        self.text:Show()
        if self.text.softOutline then
            local usingSoftOutline = (db.FontOutline == "SOFTOUTLINE")
            self.text.softOutline:SetShown(usingSoftOutline)
        end
    else
        self.text:Hide()
        if self.text.softOutline then
            self.text.softOutline:SetShown(false)
        end
    end

    -- Update timer text settings
    if self.timerText then
        local showTimer = self.db.ShowTimer ~= false
        KE:ApplyFontToText(self.timerText, self.db.TimerFontFace, self.db.TimerFontSize, self.db.TimerFontOutline)

        local tcr, tcg, tcb, tca = KE:ResolveColor(self.db.TimerTextColor, { 1, 1, 1, 1 })
        self.timerText:SetTextColor(tcr, tcg, tcb, tca)

        if showTimer then
            self.timerText:Show()
            if self.timerText.softOutline then
                local usingSoftOutline = (self.db.TimerFontOutline == "SOFTOUTLINE")
                self.timerText.softOutline:SetShown(usingSoftOutline)
            end
        else
            self.timerText:Hide()
            if self.timerText.softOutline then
                self.timerText.softOutline:SetShown(false)
            end
        end
    end

    -- Apply position
    self:ApplyPosition()

    -- Handle glow state
    if self.glowActive then
        self:StopGlow()
        self:StartGlow()
    elseif db.GlowEnabled and self.frame:IsShown() then
        self:StartGlow()
    end
end

function TSP:ApplyPosition()
    if not self.db.Enabled then return end
    if not self.frame then return end
    KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Glow Effects
---------------------------------------------------------------------------------
function TSP:StartGlow()
    if not self.frame then return end
    if not self.db.GlowEnabled then return end
    if not LCG then return end

    local color = self.db.GlowColor or { 0.95, 0.95, 0.32, 1 }
    local glowType = self.db.GlowType or "proc"

    if glowType == "pixel" then
        LCG.PixelGlow_Start(self.frame, color, 8, 0.25, 8, 2, 1, 1, false, nil)
    elseif glowType == "autocast" then
        LCG.AutoCastGlow_Start(self.frame, color, 8, 0.25, 1, 1, 1, nil)
    elseif glowType == "button" then
        LCG.ButtonGlow_Start(self.frame, color, 0)
    elseif glowType == "proc" then
        LCG.ProcGlow_Start(self.frame, {
            color = color,
            startAnim = false,
            duration = 1,
        })
    end

    self.glowActive = true
end

function TSP:StopGlow()
    if not self.frame then return end
    if not LCG then return end

    LCG.PixelGlow_Stop(self.frame)
    LCG.AutoCastGlow_Stop(self.frame)
    LCG.ButtonGlow_Stop(self.frame)
    LCG.ProcGlow_Stop(self.frame)

    self.glowActive = false
end

---------------------------------------------------------------------------------
-- Timer OnUpdate
---------------------------------------------------------------------------------
function TSP:OnUpdate()
    if not self.durationObject then return end
    if not self.timerText then return end
    if not self.db.ShowTimer then return end

    local remaining = self.durationObject:GetRemainingDuration()
    if not remaining or remaining <= 0 then
        self.timerText:SetText("")
        return
    end

    local decimals = self.durationObject:EvaluateRemainingDuration(KE.curves.DurationDecimals)
    self.timerText:SetFormattedText("%." .. decimals .. "f", remaining)

    -- Update soft outline text if it exists
    if self.timerText.softOutline and self.timerText.softOutline.main then
        self.timerText.softOutline.main:SetFormattedText("%." .. decimals .. "f", remaining)
    end
end

function TSP:ShowProc()
    if not self.frame then self:CreateFrame() end
    if not self.frame then return end
    self.procStartTime = GetTime()

    -- Set up cooldown spiral
    self.cooldown:SetCooldown(self.procStartTime, TIME_SPIRAL_DURATION)

    -- Create duration object for timer text
    self.durationObject = C_DurationUtil.CreateDuration()
    self.durationObject:SetTimeFromStart(self.procStartTime, TIME_SPIRAL_DURATION)

    -- Start glow
    self:StartGlow()

    -- Show frame
    self.frame:Show()

    -- Set up timer to hide when proc expires
    if self.hideTimer then self.hideTimer:Cancel() end
    self.hideTimer = C_Timer.NewTimer(TIME_SPIRAL_DURATION, function() self:HideProc() end)
end

function TSP:HideProc()
    if not self.frame then return end

    self:StopGlow()
    self.frame:Hide()
    self.procStartTime = nil
    self.durationObject = nil

    if self.timerText then
        self.timerText:SetText("")
        if self.timerText.softOutline and self.timerText.softOutline.main then
            self.timerText.softOutline.main:SetText("")
        end
    end

    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function TSP:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "TimeSpiral", displayName = "Time Spiral", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "TimeSpiral",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function TSP:ShowPreview()
    if not self.frame then self:CreateFrame() end
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()

    -- Show with fake cooldown
    local now = GetTime()
    self.cooldown:SetCooldown(now, TIME_SPIRAL_DURATION)

    -- Create duration object for preview timer
    self.durationObject = C_DurationUtil.CreateDuration()
    self.durationObject:SetTimeFromStart(now, TIME_SPIRAL_DURATION)

    self:StartGlow()
    self.frame:Show()
end

function TSP:HidePreview()
    self.isPreview = false
    self:StopGlow()
    self.durationObject = nil

    if self.timerText then
        self.timerText:SetText("")
        if self.timerText.softOutline and self.timerText.softOutline.main then
            self.timerText.softOutline.main:SetText("")
        end
    end

    if self.frame then
        self.frame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function TSP:OnEnable()
    if not self.db.Enabled then return end

    if not MOVEMENT_SPELL_FILTER then
        MOVEMENT_SPELL_FILTER = {}
        for _, list in pairs(PRIMARY_BY_SPEC) do
            for _, entry in ipairs(list) do
                MOVEMENT_SPELL_FILTER[entry[1]] = entry[2]
            end
        end
    end

    self:DetectPlayerSpell()
    self:CreateFrame()
    self:RegWithEditMode()
    C_Timer.After(0.5, function() self:ApplyPosition() end)

    -- Set up OnUpdate for timer text
    self.frame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdate(elapsed)
    end)

    -- Register events
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, spellId)
        if not spellId then return end
        local procIcon = MOVEMENT_SPELL_FILTER[spellId]
        if not procIcon then return end
        if self:FilterSpell(spellId) then return end

        -- Don't let a proc overwrite the icon picked by DetectPlayerSpell.
        -- Time Spiral can proc multiple movement spells simultaneously
        -- (Shaman has 3 — SWG + GoW + SW), so last-write-wins would pick
        -- whichever the engine fires last instead of the user's priority.
        -- Bootstrap exception: if detection never landed (e.g. spec data
        -- not loaded at OnEnable), use the first proc as a fallback.
        if not self.playerSpellId then
            self.playerSpellId = spellId
            self.playerIconId = procIcon
            if self.icon then
                self.icon:SetTexture(procIcon)
            end
        end

        self.activeProcs[spellId] = true
        self:ShowProc()
    end)

    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, spellId)
        if not spellId then return end
        if not MOVEMENT_SPELL_FILTER[spellId] then return end
        self.activeProcs[spellId] = nil
        if not next(self.activeProcs) then
            self:HideProc()
        end
    end)

    -- Re-detect on spec switch or talent loadout change so the icon reflects
    -- the player's current movement spell instead of staying stale.
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnTalentChange")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnTalentChange")
end

function TSP:OnTalentChange()
    -- Clear cached pick so DetectPlayerSpell walks the priority list fresh.
    self.playerSpellId = nil
    self.playerIconId = nil
    self:DetectPlayerSpell()
    if self.icon then
        self.icon:SetTexture(self:GetDisplayIcon())
    end
end

function TSP:OnDisable()
    if self.frame then
        self:StopGlow()
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    self.isPreview = false
    self.activeProcs = {}
    self.glowActive = false
    self.durationObject = nil
    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end
    self:UnregisterAllEvents()
end
