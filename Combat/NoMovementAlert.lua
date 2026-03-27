-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Create module
---@class NoMovementAlert: AceModule, AceEvent-3.0
local NMA = KitnEssentials:NewModule("NoMovementAlert", "AceEvent-3.0")

-- Localization
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local UnitClass = UnitClass
local IsPlayerSpell = IsPlayerSpell
local GetTime = GetTime
local string_format = string.format
local string_gsub = string.gsub

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local REFRESH_INTERVAL = 0.1

-- Class spell lists: priority order (first known spell wins)
-- { spellID, displayName }
local CLASS_SPELLS = {
    ["DEATHKNIGHT"] = {
        { 48265, "DA" },          -- Death's Advance
    },
    ["DEMONHUNTER"] = {
        { 195072, "RUSH" },       -- Fel Rush
        { 189110, "LEAP" },       -- Infernal Strike
        { 1234796, "SHIFT" },     -- Shift
    },
    ["DRUID"] = {
        { 252216, "DASH" },       -- Tiger Dash
        { 102401, "CHARGE" },     -- Wild Charge
    },
    ["EVOKER"] = {
        { 358267, "HOVER" },      -- Hover
    },
    ["HUNTER"] = {
        { 781, "DISENGAGE" },     -- Disengage
    },
    ["MAGE"] = {
        { 212653, "SHIMMER" },    -- Shimmer
        { 1953, "BLINK" },        -- Blink
    },
    ["MONK"] = {
        { 109132, "ROLL" },       -- Roll
        { 115008, "TORPEDO" },    -- Chi Torpedo
    },
    ["PALADIN"] = {
        { 190784, "STEED" },      -- Divine Steed
    },
    ["PRIEST"] = {
        { 121536, "FEATHER" },    -- Angelic Feather
    },
    ["ROGUE"] = {
        { 36554, "STEP" },        -- Shadowstep
        { 195457, "GRAPPLE" },    -- Grappling Hook
    },
    ["SHAMAN"] = {
        { 192063, "GUST" },       -- Gust of Wind
    },
    ["WARLOCK"] = {
        { 48020, "CIRCLE" },      -- Demonic Circle: Teleport
    },
    ["WARRIOR"] = {
        { 6544, "LEAP" },         -- Heroic Leap
    },
}

---------------------------------------------------------------------------------
-- Module state
---------------------------------------------------------------------------------
NMA.frame = nil
NMA.text = nil
NMA.isPreview = false
NMA.editModeRegistered = false
NMA.playerClass = nil
NMA.activeSpellID = nil
NMA.activeDisplayName = nil
NMA.elapsed = 0
-- Pre-parsed format template (rebuilt in ParseDisplayFormat)
NMA.fmtBefore = "NO MOVE ("
NMA.fmtAfter = ")"

---------------------------------------------------------------------------------
-- UpdateDB
---------------------------------------------------------------------------------
function NMA:UpdateDB()
    self.db = KE.db.profile.NoMovementAlert
end

---------------------------------------------------------------------------------
-- Spell Resolution
---------------------------------------------------------------------------------
local function IsSpellKnownSafe(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        if C_SpellBook.IsSpellKnown(spellID) then return true end
    end
    if IsPlayerSpell then
        return IsPlayerSpell(spellID)
    end
    return false
end

function NMA:CacheMovementSpell()
    self.activeSpellID = nil
    self.activeDisplayName = nil

    if not self.playerClass then return end
    local spells = CLASS_SPELLS[self.playerClass]
    if not spells then return end

    for _, entry in ipairs(spells) do
        if IsSpellKnownSafe(entry[1]) then
            self.activeSpellID = entry[1]
            self.activeDisplayName = entry[2]
            self:ParseDisplayFormat()
            return
        end
    end
end

-- Pre-parse display format into before/after parts around %t
-- Eliminates gsub + match from the OnUpdate hot path
function NMA:ParseDisplayFormat()
    local fmt = self.db.DisplayFormat or "NO %n (%t)"
    local name = self.activeDisplayName or "MOVE"
    local display = string_gsub(fmt, "%%n", name)
    local before, after = display:match("^(.-)%%t(.*)$")
    if before then
        self.fmtBefore = before
        self.fmtAfter = after or ""
    else
        self.fmtBefore = display
        self.fmtAfter = nil
    end
    self.lastTimeStr = nil
end

---------------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------------
function NMA:CreateFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_NoMovementAlertFrame", UIParent)
    frame:SetSize(300, 50)

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)

    -- Separate ticker frame that's always shown (OnUpdate doesn't fire on hidden frames)
    local ticker = CreateFrame("Frame", nil, UIParent)
    ticker:SetSize(1, 1)
    ticker:Show()

    self.frame = frame
    self.text = text
    self.tickerFrame = ticker
    frame:Hide()
end

function NMA:UpdateMovementAlert()
    if not self.activeSpellID then
        if self.frame then self.frame:Hide() end
        return
    end

    local cdInfo = C_Spell.GetSpellCooldown(self.activeSpellID)

    -- Skip if remaining cooldown exceeds threshold (hides long CDs until they're almost ready)
    -- startTime and duration are secret in 12.0.5 — launder through string.format + tonumber
    if cdInfo and cdInfo.startTime and cdInfo.duration then
        local durationNum = tonumber(string_format("%.1f", cdInfo.duration))
        if durationNum and durationNum > 0 then
            local startNum = tonumber(string_format("%.1f", cdInfo.startTime))
            if startNum then
                local remaining = (startNum + durationNum) - GetTime()
                local maxCD = self.db.MaxCooldown or 30
                if remaining > maxCD then
                    if self.frame:IsShown() then self.frame:Hide() end
                    return
                end
            end
        end
    end

    if cdInfo and cdInfo.timeUntilEndOfStartRecovery and not cdInfo.isOnGCD and cdInfo.isOnGCD ~= nil then
        -- timeUntilEndOfStartRecovery is a secret number — only string.format + concatenation work
        local timeStr = string_format("%.1f", cdInfo.timeUntilEndOfStartRecovery)

        -- timeStr is a secret string — cannot compare, just SetText every tick
        if self.fmtAfter then
            self.text:SetText(self.fmtBefore .. timeStr .. self.fmtAfter)
        else
            self.text:SetText(self.fmtBefore)
        end

        if not self.frame:IsShown() then
            self.frame:SetAlpha(1)
            self.frame:Show()
        end
    else
        if self.frame and self.frame:IsShown() then
            self.frame:Hide()
        end
    end
end

function NMA:HideAlert()
    if self.frame then self.frame:Hide() end
end

---------------------------------------------------------------------------------
-- OnUpdate
---------------------------------------------------------------------------------
function NMA:StartOnUpdate()
    if not self.tickerFrame then return end
    self.tickerFrame:SetScript("OnUpdate", function(_, dt)
        if self.isPreview then return end
        self.elapsed = self.elapsed + dt
        if self.elapsed < REFRESH_INTERVAL then return end
        self.elapsed = 0
        self:UpdateMovementAlert()
    end)
end

function NMA:StopOnUpdate()
    if self.tickerFrame then
        self.tickerFrame:SetScript("OnUpdate", nil)
    end
    self.elapsed = 0
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function NMA:ApplySettings()
    if not self.frame then return end

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
    KE:ApplyFontToText(self.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)

    local r, g, b, a = KE:GetAccentColor(self.db.ColorMode, self.db.Color)
    self.text:SetTextColor(r, g, b, a)

    -- Re-parse format in case DisplayFormat changed
    self:ParseDisplayFormat()
end

---------------------------------------------------------------------------------
-- EditMode
---------------------------------------------------------------------------------
function NMA:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "NoMovementAlert", displayName = "No Movement Alert", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "NoMovementAlert",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function NMA:ShowPreview()
    if not self.frame then
        self:CreateFrame()
    end
    self:RegWithEditMode()
    if not self.activeSpellID then
        self:CacheMovementSpell()
    end

    self.isPreview = true
    local name = self.activeDisplayName or "BLINK"
    local fmt = self.db.DisplayFormat or "NO %n (%t)"
    local display = string_gsub(fmt, "%%n", name)
    display = string_gsub(display, "%%t", "12")
    self.text:SetText(display)
    self.frame:SetAlpha(1)
    self.frame:Show()
    self:ApplySettings()
end

function NMA:HidePreview()
    self.isPreview = false
    if self.db.Enabled then
        self:UpdateMovementAlert()
    else
        self:HideAlert()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function NMA:OnInitialize()
    self:UpdateDB()
    local _, classToken = UnitClass("player")
    self.playerClass = classToken
    self:SetEnabledState(false)
end

function NMA:OnTalentChange()
    C_Timer.After(0.5, function()
        if not self.db or not self.db.Enabled then return end
        self:CacheMovementSpell()
    end)
end

function NMA:OnEnable()
    if not self.db.Enabled then return end

    self:CreateFrame()
    self:RegWithEditMode()
    self:CacheMovementSpell()

    C_Timer.After(0.5, function()
        if not self.db or not self.db.Enabled then return end
        self:ApplySettings()
    end)

    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentChange")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnTalentChange")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnTalentChange")

    self:StartOnUpdate()
end

function NMA:OnDisable()
    self:UnregisterAllEvents()
    self:StopOnUpdate()
    self:HideAlert()
    self.isPreview = false
end
