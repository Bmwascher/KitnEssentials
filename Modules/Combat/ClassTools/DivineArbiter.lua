-- ╔══════════════════════════════════════════════════════════╗
-- ║  DivineArbiter.lua                                       ║
-- ║  Module: Divine Arbiter                                  ║
-- ║  Purpose: Shows which spender consumes the Divine        ║
-- ║           Arbiter buff. Retribution Paladin only.        ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Nothing here reads an aura. Blizzard's aura container matches the two buffs
-- by spell id and draws the timer; each group paints its own fixed icon.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DivineArbiter: AceModule, AceEvent-3.0
local DA = KitnEssentials:NewModule("DivineArbiter", "AceEvent-3.0")
DA.classRestriction = "PALADIN"

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local UnitClass = UnitClass

-- Flip to true, /reload, repro, read the log.
local DEBUG_DA = false

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local RETRIBUTION_SPEC = 70

-- The icon is the spender that consumes the buff, not the one that granted it.
local STORM_BUFF   = 1306161
local VERDICT_BUFF = 1306162
local STORM_ICON   = 236250
local VERDICT_ICON = 461860

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
DA.display = nil
DA.active = false
DA.listener = nil
DA.suspendedView = nil

---------------------------------------------------------------------------------
-- Gate
---------------------------------------------------------------------------------
function DA.WantsSpec(class, specID)
    return class == "PALADIN" and specID == RETRIBUTION_SPEC
end

-- One display for the session: Register errors on a second call with the same
-- owner, so leaving the spec suspends the display and returning resumes it.
function DA.PlanGate(wanted, hasDisplay, active)
    if wanted then
        if not hasDisplay then return "register" end
        if not active then return "resume" end
        return nil
    end
    if active then return "suspend" end
    return nil
end

---------------------------------------------------------------------------------
-- Display declaration
---------------------------------------------------------------------------------
local function HelpfulFilter()
    return "HELPFUL"
end

local function Capabilities(fixedIcon)
    return {
        hasBorder = true,
        hasDispelBadge = false,
        hasDispelRing = false,
        hasGlow = true,
        hasLabel = false,
        hasTimerFont = true,
        fixedIcon = fixedIcon,
    }
end

-- No vehiclePolicy: the default hides the display in a vehicle seat, where
-- neither spender can be cast.
local DECLARATION = {
    key = "DivineArbiter",
    dbKey = "DivineArbiter",
    displayName = "Divine Arbiter",
    guiPath = "ClassTools",
    guiTab = "DivineArbiter",
    sortMethod = "AuraInstanceIDOnly",
    defaultIconsPerRow = 1,

    groups = {
        {
            key = "storm",
            buildFilter = HelpfulFilter,
            buildCandidates = function() return { includeSpellIDs = { [STORM_BUFF] = true } } end,
            capabilities = Capabilities(function() return STORM_ICON end),
        },
        {
            key = "verdict",
            buildFilter = HelpfulFilter,
            buildCandidates = function() return { includeSpellIDs = { [VERDICT_BUFF] = true } } end,
            capabilities = Capabilities(function() return VERDICT_ICON end),
        },
    },

    -- One frame per buff whatever the grid holds, so a second buff wraps
    -- below the one-icon box instead of being dropped.
    splitLimit = function()
        return { storm = 1, verdict = 1 }
    end,

    sounds = {
        spellIDs = { STORM_BUFF, VERDICT_BUFF },
        unit = "player",
        settingKeys = { enabled = "SoundEnabled", name = "SoundName" },
    },

    buildPreview = function()
        return {
            { icon = STORM_ICON, groupKey = "storm", count = 0 },
            { icon = VERDICT_ICON, groupKey = "verdict", count = 0 },
        }
    end,
}

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function DA:UpdateDB()
    self.db = KE.db.profile.DivineArbiter
end

function DA:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- Suspended, the engine reads the module as off, so work it queued before the
-- suspend (a vehicle-exit timer, a restriction drain) cannot re-show the
-- container. Other reads and writes go through to the saved settings.
function DA:EngineSettings()
    if self.active then return self.db end
    if not self.suspendedView then
        self.suspendedView = setmetatable({ Enabled = false }, {
            __index = function(_, key) return DA.db[key] end,
            __newindex = function(_, key, value) DA.db[key] = value end,
        })
    end
    return self.suspendedView
end

-- The identity is read once, so the decision and the debug line describe the
-- same sample.
function DA:EvaluateGate()
    local _, class = UnitClass("player")
    local specID = KE:GetPlayerSpecId()
    local action = DA.PlanGate(DA.WantsSpec(class, specID), self.display ~= nil, self.active == true)
    if DEBUG_DA then
        KE:Print(("[DA] gate class=%s spec=%s active=%s -> %s"):format(
            tostring(class), tostring(specID), tostring(self.active), tostring(action)))
    end

    if action == "register" then
        self.display = KE.AuraEngine.Register(self, DECLARATION, function() return self:EngineSettings() end)
        self.active = true
        KE.AuraEngine.ApplySettings(self.display)
    elseif action == "resume" then
        self.active = true
        KE.AuraEngine.SetModuleEnabled(self.display, true)
    elseif action == "suspend" then
        self.active = false
        KE.AuraEngine.SetModuleEnabled(self.display, false)
        -- Disabling alone leaves the engine's events registered, so its
        -- zone-change, vehicle and restriction handlers keep running off-spec.
        -- Dropping them leaves the state an Ace disable leaves.
        self:UnregisterAllEvents()
    end
end

-- A frame of its own: a suspend drops every event on the module, and this
-- listener is what resumes it.
function DA:EnsureListener()
    if self.listener then return self.listener end
    local listener = CreateFrame("Frame")
    listener:SetScript("OnEvent", function() DA:EvaluateGate() end)
    self.listener = listener
    return listener
end

function DA:OnEnable()
    self:UpdateDB()
    -- Class first, so a non-Paladin with the module on in a shared profile
    -- builds nothing at all.
    local _, class = UnitClass("player")
    if class ~= "PALADIN" then return end
    if not self.db or not self.db.Enabled then return end

    local listener = self:EnsureListener()
    listener:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    -- Retries a login whose spec was not readable yet.
    listener:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Now, so switching the module on with the page open shows its preview;
    -- and once more deferred, because at login the spec is not reliably
    -- readable on the frame this runs.
    self:EvaluateGate()
    C_Timer.After(0.5, function()
        if self:IsEnabled() then self:EvaluateGate() end
    end)
end

function DA:OnDisable()
    self.active = false
    KE.AuraEngine.SetModuleEnabled(self.display, false)
    if self.listener then self.listener:UnregisterAllEvents() end
end

---------------------------------------------------------------------------------
-- Settings and preview
---------------------------------------------------------------------------------
-- Off-spec a reconfiguration would restyle a hidden container for nothing; the
-- resume applies the latest settings.
function DA:ApplySettings()
    self:UpdateDB()
    if not self.active then return end
    KE.AuraEngine.ApplySettings(self.display)
end

function DA:ShowPreview()
    if not self.active then return end
    KE.AuraEngine.ShowPreview(self.display)
end

function DA:HidePreview()
    KE.AuraEngine.HidePreview(self.display)
end
