-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Create module
---@class TimeSpiral: AceModule, AceEvent-3.0
local TSP = KitnEssentials:NewModule("TimeSpiral", "AceEvent-3.0")

-- Libraries
local LCG = LibStub("LibCustomGlow-1.0", true)

-- Localization
local CreateFrame = CreateFrame
local GetSpellTexture = C_Spell.GetSpellTexture
local IsPlayerSpell = IsPlayerSpell
local GetTime = GetTime
local pairs = pairs
local next = next
local UnitClass = UnitClass
local unpack = unpack

-- Module state
TSP.activeProcs = {}

-- Default Time Spiral icon texture
local TIME_SPIRAL_ICON = 4622479
local TIME_SPIRAL_DURATION = 10.5

-- Table that holds movement spells that can proc from Time Spiral
local MOVEMENT_SPELLS = {
    [48265]  = "DEATHKNIGHT", -- Death's Advance
    [195072] = "DEMONHUNTER", -- Fel Rush
    [189110] = "DEMONHUNTER", -- Infernal Strike
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

-- Filter some spells that can cause false procs
local FILTER_TALENTS = {
    [427640] = { [195072] = true }, -- Inertia
    [427794] = { [195072] = true }, -- Dash of Chaos
    [385899] = { [385899] = true }, -- Soulburn
}

-- Update db, used for profile changes
function TSP:UpdateDB()
    self.db = KE.db.profile.TimeSpiral
end

-- Detect the player's movement spell
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

-- Get the icon texture for the display
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

-- Module init
function TSP:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- Helper: apply zoom to a texture via TexCoord
local function ApplyZoom(tex, zoom)
    local texMin = 0.25 * zoom
    local texMax = 1 - 0.25 * zoom
    tex:SetTexCoord(texMin, texMax, texMin, texMax)
end

-- Helper: add pixel-perfect borders to a frame
local function AddBorders(frame, color)
    color = color or { 0, 0, 0, 1 }
    frame.borders = {}

    local function MakeBorder(point1A, rel1A, point1B, rel1B, point2A, rel2A, point2B, rel2B, w, h)
        local tex = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(unpack(color))
        tex:SetTexelSnappingBias(0)
        tex:SetSnapToPixelGrid(false)
        tex:SetPoint(point1A, frame, rel1A, 0, 0)
        tex:SetPoint(point2A, frame, rel2A, 0, 0)
        if w then tex:SetWidth(w) end
        if h then tex:SetHeight(h) end
        return tex
    end

    frame.borders.top    = MakeBorder("TOPLEFT", "TOPLEFT", nil, nil, "TOPRIGHT", "TOPRIGHT", nil, nil, nil, 1)
    frame.borders.bottom = MakeBorder("BOTTOMLEFT", "BOTTOMLEFT", nil, nil, "BOTTOMRIGHT", "BOTTOMRIGHT", nil, nil, nil, 1)
    frame.borders.left   = MakeBorder("TOPLEFT", "TOPLEFT", nil, nil, "BOTTOMLEFT", "BOTTOMLEFT", nil, nil, 1, nil)
    frame.borders.right  = MakeBorder("TOPRIGHT", "TOPRIGHT", nil, nil, "BOTTOMRIGHT", "BOTTOMRIGHT", nil, nil, 1, nil)
end

-- Create the display frame
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
    AddBorders(f, { 0, 0, 0, 1 })

    -- Icon texture with zoom
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    ApplyZoom(f.icon, 0.3)
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

    -- Store references
    self.frame = f
    self.icon = f.icon
    self.text = f.text
    self.cooldown = cooldown

    self:ApplySettings()
end

-- Check if a spell should be filtered out to avoid false procs
function TSP:FilterSpell(spellId)
    for talentId, spells in pairs(FILTER_TALENTS) do
        if spells[spellId] and IsPlayerSpell(talentId) then
            return true
        end
    end
    return false
end

-- Apply settings, called from GUI or profile switching
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

-- Apply position
function TSP:ApplyPosition()
    if not self.db.Enabled then return end
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

-- Setup and start the glow effect
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

-- Stop the glow effect
function TSP:StopGlow()
    if not self.frame then return end
    if not LCG then return end

    LCG.PixelGlow_Stop(self.frame)
    LCG.AutoCastGlow_Stop(self.frame)
    LCG.ButtonGlow_Stop(self.frame)
    LCG.ProcGlow_Stop(self.frame)

    self.glowActive = false
end

-- Show the proc indicator
function TSP:ShowProc()
    if not self.frame then self:CreateFrame() end
    if not self.frame then return end
    self.procStartTime = GetTime()

    -- Set up cooldown spiral
    self.cooldown:SetCooldown(self.procStartTime, TIME_SPIRAL_DURATION)

    -- Start glow
    self:StartGlow()

    -- Show frame
    self.frame:Show()

    -- Set up timer to hide when proc expires
    if self.hideTimer then self.hideTimer:Cancel() end
    self.hideTimer = C_Timer.NewTimer(TIME_SPIRAL_DURATION, function() self:HideProc() end)
end

-- Hide the proc indicator
function TSP:HideProc()
    if not self.frame then return end

    self:StopGlow()
    self.frame:Hide()
    self.procStartTime = nil

    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end
end

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

-- Preview
function TSP:ShowPreview()
    if not self.frame then self:CreateFrame() end
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()

    -- Show with fake cooldown
    self.cooldown:SetCooldown(GetTime(), TIME_SPIRAL_DURATION)
    self:StartGlow()
    self.frame:Show()
end

function TSP:HidePreview()
    self.isPreview = false
    self:StopGlow()
    if self.frame then
        self.frame:Hide()
    end
end

-- Module OnEnable
function TSP:OnEnable()
    if not self.db.Enabled then return end
    self:DetectPlayerSpell()
    self:CreateFrame()
    self:RegWithEditMode()
    C_Timer.After(0.5, function() self:ApplyPosition() end)

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

-- Module OnDisable
function TSP:OnDisable()
    if self.frame then
        self:StopGlow()
        self.frame:Hide()
    end
    self.isPreview = false
    self.activeProcs = {}
    self.glowActive = false
    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end
    self:UnregisterAllEvents()
end
