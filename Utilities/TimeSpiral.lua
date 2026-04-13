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
local GetSpellTexture = C_Spell.GetSpellTexture
local IsPlayerSpell = IsPlayerSpell
local IsSpellKnown = IsSpellKnown
local GetTime = GetTime
local pairs = pairs
local next = next
local UnitClass = UnitClass

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

local MOVEMENT_SPELLS = {
    [48265]  = "DEATHKNIGHT", -- Death's Advance
    [195072]  = "DEMONHUNTER", -- Fel Rush
    [1234796] = "DEMONHUNTER", -- Infernal Strike
    [189110]  = "DEMONHUNTER", -- Shift
    [1850]   = "DRUID",       -- Dash
    [252216] = "DRUID",       -- Tiger Dash
    [358267] = "EVOKER",      -- Hover
    [186257] = "HUNTER",      -- Aspect of the Cheetah
    [1953]   = "MAGE",        -- Blink
    [212653] = "MAGE",        -- Shimmer
    [109132] = "MONK",        -- Roll
    [119085] = "MONK",        -- Chi Torpedo
    [190784] = "PALADIN",     -- Divine Steed
    [73325]  = "PRIEST",      -- Leap of Faith
    [2983]   = "ROGUE",       -- Sprint
    [192063] = "SHAMAN",      -- Gust of Wind
    [58875]  = "SHAMAN",      -- Spirit Walk
    [79206]  = "SHAMAN",      -- Spiritwalker's Grace
    [48020]  = "WARLOCK",     -- Demonic Circle: Teleport
    [6544]   = "WARRIOR",     -- Heroic Leap
}

local FILTER_TALENTS = {
    [427640] = { [195072] = true }, -- Inertia
    [427794] = { [195072] = true }, -- Dash of Chaos
    [385899] = { [385899] = true }, -- Soulburn
}

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function TSP:UpdateDB()
    self.db = KE.db.profile.TimeSpiral
end

function TSP:DetectPlayerSpell()
    local _, playerClass = UnitClass("player")
    for spellId, class in pairs(MOVEMENT_SPELLS) do
        if class == playerClass and IsPlayerSpell(spellId) then
            self.playerSpellId = spellId
            return spellId
        end
    end
    return nil
end

function TSP:GetDisplayIcon()
    if self.playerSpellId then
        local texture = GetSpellTexture(self.playerSpellId)
        if texture then
            return texture
        end
    end

    -- Try to detect the spell if we haven't yet
    local spellId = self:DetectPlayerSpell()
    if spellId then
        local texture = GetSpellTexture(spellId)
        if texture then
            return texture
        end
    end

    -- Fallback to Time Spiral icon
    return TIME_SPIRAL_ICON
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
-- Check if a talent is known using multiple detection methods
local function IsTalentKnown(talentId)
    if IsPlayerSpell(talentId) then return true end
    if IsSpellKnown(talentId) then return true end

    local spellInfo = C_Spell.GetSpellInfo(talentId)
    if spellInfo then
        local isUsable = C_Spell.IsSpellUsable(talentId)
        if isUsable then return true end
    end

    return false
end

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
    local textColor = db.TextColor or { 1, 1, 1, 1 }
    self.text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)

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

        local timerColor = self.db.TimerTextColor or { 1, 1, 1, 1 }
        self.timerText:SetTextColor(timerColor[1], timerColor[2], timerColor[3], timerColor[4] or 1)

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
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
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
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
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
        if not MOVEMENT_SPELLS[spellId] then return end
        if self:FilterSpell(spellId) then return end

        self.playerSpellId = spellId
        if self.icon then
            self.icon:SetTexture(self:GetDisplayIcon())
        end

        self.activeProcs[spellId] = true
        self:ShowProc()
    end)

    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, spellId)
        if not spellId then return end
        if not MOVEMENT_SPELLS[spellId] then return end
        self.activeProcs[spellId] = nil
        if not next(self.activeProcs) then
            self:HideProc()
        end
    end)
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
