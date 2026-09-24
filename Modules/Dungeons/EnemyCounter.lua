-- ╔══════════════════════════════════════════════════════════╗
-- ║  EnemyCounter.lua                                        ║
-- ║  Module: Enemy Counter                                   ║
-- ║  Purpose: Displays the number of enemies currently in    ║
-- ║           combat via nameplate scanning.                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local EC = KitnEssentials:NewModule("EnemyCounter", "AceEvent-3.0")

-- Local references
local UnitExists = UnitExists
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsDead = UnitIsDead
local UnitCanAttack = UnitCanAttack
local tostring = tostring
local issecretvalue = issecretvalue or function() return false end

local DEBUG_EC = false
local lastDebugCount = -1

-- Talent and spec state is not reliable immediately on a spec change event.
local SPEC_SETTLE_DELAY = 2

-- Registered while the current spec is enabled, unregistered when it is not.
-- The two spec-watch events stay outside this list so the gate can reopen.
local GATED_EVENTS = {
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "UNIT_FLAGS",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

EC.frame = nil
EC.text = nil
EC.isPreview = false
EC.editModeRegistered = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function EC:UpdateDB()
    self.db = KE.db.profile.Dungeons.EnemyCounter
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------

local function GetEnemyCount()
    local count = 0
    local debugLines = DEBUG_EC and {} or nil
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local combat = UnitAffectingCombat(unit)
            local dead = UnitIsDead(unit)
            local hostile = UnitCanAttack("player", unit)
            if debugLines then
                debugLines[#debugLines + 1] = ("[EC] %s cmb=%s dead=%s hostile=%s"):format(
                    unit, tostring(combat), tostring(dead), tostring(hostile))
            end
            if combat and not dead and hostile then
                count = count + 1
            end
        end
    end
    -- Only print when count changes
    if DEBUG_EC and count ~= lastDebugCount then
        for _, line in ipairs(debugLines --[[@as table]]) do KE:Print(line) end
        KE:Print(("[EC] count=%d (was %d)"):format(count, lastDebugCount))
        lastDebugCount = count
    end
    return count
end

function EC:UpdateText()
    if not self.frame or not self.text then return end

    local count
    if self.isPreview then
        count = 5
    else
        count = GetEnemyCount()
    end

    if self.db.ShowPrefix and self.db.Prefix and self.db.Prefix ~= "" then
        self.text:SetText(self.db.Prefix .. " " .. tostring(count))
    else
        self.text:SetText(tostring(count))
    end

    -- Dynamic frame sizing (guard against GetStringWidth taint post-combat).
    -- Snap derived size to the pixel grid so the frame's right edge lands on
    -- an integer pixel (text centered inside an odd-width frame would
    -- otherwise sit at sub-pixel and halo).
    local textWidth = self.text:GetStringWidth()
    if textWidth and not issecretvalue(textWidth) then
        self.frame:SetSize(KE:PixelSnap(textWidth + 16), (self.db.FontSize or 20) + 10)
    end

    -- Visibility
    if self.isPreview then
        self.frame:Show()
    elseif self.db.CombatOnly and count == 0 then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------

function EC:CreateFrames()
    if self.frame then return end

    local f = CreateFrame("Frame", "KE_EnemyCounterFrame", UIParent)
    f:SetSize(120, 30)
    f:SetFrameStrata(self.db.Strata or "HIGH")
    self.frame = f

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    self.text = text

    f:Hide()
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------

-- The public entry, and the one a profile switch calls, so it routes through
-- the spec gate; the gate reaches the layout through ApplyLayout.
function EC:ApplySettings()
    if self.isPreview or not self:IsEnabled() then
        self:ApplyLayout()
        return
    end
    self:ApplySpecGate()
end

function EC:ApplyLayout()
    if not self.frame then return end

    local db = self.db
    self.frame:SetFrameStrata(db.Strata or "HIGH")
    KE:ApplyFramePosition(self.frame, db.Position, db)

    -- Font + color
    local r, g, b, a = KE:GetAccentColor(db.ColorMode, db.Color)
    KE:ApplyFontToText(self.text, db.FontFace, db.FontSize, db.FontOutline)
    self.text:SetTextColor(r, g, b, a or 1)

    self:UpdateText()
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------

function EC:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "EnemyCounter",
            module = self,
            displayName = "Enemy Counter",
            frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "EnemyCounter",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------

function EC:ShowPreview()
    if not self.frame then self:CreateFrames() end
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()
    self.frame:Show()
end

-- Closing the page on a spec just unticked must not leave the counter shown.
function EC:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    if not self.db.Enabled or not KE:IsSpecEnabled(self.db.EnabledSpecs, KE:GetPlayerSpecId()) then
        self.frame:Hide()
        return
    end
    self:UpdateText()
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------

function EC:NAME_PLATE_UNIT_ADDED(_, unit)
    if DEBUG_EC then KE:Print("[EC] event=NP_ADDED " .. tostring(unit)) end
    self:UpdateText()
end

function EC:NAME_PLATE_UNIT_REMOVED(_, unit)
    if DEBUG_EC then KE:Print("[EC] event=NP_REMOVED " .. tostring(unit)) end
    self:UpdateText()
end

function EC:UNIT_FLAGS(_, unit)
    if unit and unit:find("nameplate", 1, true) then
        if DEBUG_EC then KE:Print("[EC] event=UNIT_FLAGS " .. tostring(unit)) end
        self:UpdateText()
    end
end

function EC:PLAYER_REGEN_DISABLED()
    if DEBUG_EC then KE:Print("[EC] event=REGEN_DISABLED") end
    self:UpdateText()
end

function EC:PLAYER_REGEN_ENABLED()
    if DEBUG_EC then KE:Print("[EC] event=REGEN_ENABLED") end
    if self.db.CombatOnly then
        self.frame:Hide()
    else
        self:UpdateText()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function EC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function EC:OnEnable()
    if not self.db.Enabled then return end

    -- Outside the gate: a disabled spec must still hear the switch away from it.
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnSpecChanged")

    self:ApplySpecGate()
end

function EC:ApplySpecGate()
    if KE:IsSpecEnabled(self.db.EnabledSpecs, KE:GetPlayerSpecId()) then
        self:StartForSpec()
    else
        self:StopForSpec()
    end
end

function EC:StartForSpec()
    self:CreateFrames()
    self:RegWithEditMode()
    for index = 1, #GATED_EVENTS do
        self:RegisterEvent(GATED_EVENTS[index])
    end
    self:ApplyLayout()
end

function EC:StopForSpec()
    for index = 1, #GATED_EVENTS do
        self:UnregisterEvent(GATED_EVENTS[index])
    end
    -- The preview owns the frame while the settings page is open.
    if self.frame and not self.isPreview then self.frame:Hide() end
end

-- Applied now and again once the spec has settled: the immediate read can
-- still report the previous spec. One pending pass at a time, cancelled on
-- disable, so a burst of events leaves one timer and a disabled module none.
function EC:OnSpecChanged(event, unit)
    -- The spec event fires for group members too.
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then return end
    self:ApplySpecGate()
    if self.specTimer then self.specTimer:Cancel() end
    self.specTimer = C_Timer.NewTimer(SPEC_SETTLE_DELAY, function()
        self.specTimer = nil
        self:ApplySpecGate()
    end)
end

function EC:OnThemeChanged()
    if not self.db or not self.db.Enabled then return end
    if (self.db.ColorMode or "custom") == "theme" and self.text then
        local r, g, b, a = KE:GetAccentColor(self.db.ColorMode, self.db.Color)
        self.text:SetTextColor(r, g, b, a or 1)
    end
end

function EC:OnDisable()
    self:UnregisterAllEvents()
    if self.specTimer then
        self.specTimer:Cancel()
        self.specTimer = nil
    end
    if self.frame then self.frame:Hide() end
end
