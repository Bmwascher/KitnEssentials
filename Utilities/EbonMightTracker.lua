-- ╔══════════════════════════════════════════════════════════╗
-- ║  EbonMightTracker.lua                                    ║
-- ║  Module: Ebon Might Tracker                              ║
-- ║  Purpose: Displays Ebon Might buff duration with crit    ║
-- ║           and duped cast detection for Augmentation.    ║
-- ║  Note: Evoker only (Augmentation).                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class EbonMightTracker: AceModule, AceEvent-3.0
local EMT = KitnEssentials:NewModule("EbonMightTracker", "AceEvent-3.0")
EMT.classRestriction = "EVOKER"

local C_UnitAuras     = C_UnitAuras
local C_Spell         = C_Spell
local C_Timer         = C_Timer
local C_SpellBook     = C_SpellBook
local CreateFrame     = CreateFrame
local UnitClass       = UnitClass
local UnitExists      = UnitExists
local UnitStat        = UnitStat
local GetTime         = GetTime
local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local GetNumGroupMembers    = GetNumGroupMembers
local IsInGroup       = IsInGroup
local IsInRaid        = IsInRaid
local issecretvalue   = issecretvalue
local pcall           = pcall
local pairs           = pairs
local ipairs          = ipairs
local wipe            = wipe
local math_max        = math.max
local math_floor      = math.floor

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local EBON_MIGHT_SELF    = 395296     -- Aura on self
local EBON_MIGHT_OTHERS  = 395152     -- Aura on allies
local CHRONO_CRIT_TALENT = 431874     -- Chronowarden "canCrit" talent
local AUG_SPEC_ID        = 1473       -- Augmentation spec ID

-- Crit detection constants (from reference)
local CRIT_FACTOR           = 1.5    -- Crit multiplier
local DUPE_FACTOR           = 1.75   -- Duped multiplier
local RATIO_LOWER           = 0.95   -- Lower tolerance
local RATIO_UPPER           = 1.05   -- Upper tolerance
local MAIN_STAT_COEFFICIENT = 0.16   -- Ebon Might mainStat % coefficient
local MIN_TARGETS           = 2      -- Minimum targets divisor

local ICON_ID          = 5061347     -- Ebon Might spell icon
local REFRESH_INTERVAL = 0.5         -- Countdown update rate (seconds)

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
EMT.frame               = nil
EMT.iconFrame           = nil
EMT.iconTexture         = nil
EMT.countdownText       = nil
EMT.stateLabel          = nil
EMT.ticker              = nil
EMT.isAugSpec           = false
EMT.canCrit             = false
EMT.isPreview           = false
EMT.inGroup             = false
EMT._shown              = false
EMT.editModeRegistered  = false

-- Tracked aura state
EMT.selfAuraInstanceID  = 0
EMT.selfExpirationTime  = 0
EMT.allyAuras           = {}   -- [auraInstanceID] = { value, unit }

-- Calculated state
EMT.isCrit  = false
EMT.isDuped = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function EMT:UpdateDB()
    self.db = KE.db.profile.EbonMightTracker
end

---------------------------------------------------------------------------------
-- Spec Detection
---------------------------------------------------------------------------------
function EMT:IsValidSpec()
    local _, classToken = UnitClass("player")
    if classToken ~= "EVOKER" then return false end
    local specIndex = GetSpecialization()
    if not specIndex then return false end
    local specID = GetSpecializationInfo(specIndex)
    return specID == AUG_SPEC_ID
end

---------------------------------------------------------------------------------
-- Talent Detection
---------------------------------------------------------------------------------
function EMT:UpdateCanCrit()
    local ok, known = pcall(C_SpellBook.IsSpellKnown, CHRONO_CRIT_TALENT)
    self.canCrit = ok and known == true
end

---------------------------------------------------------------------------------
-- Data Management
---------------------------------------------------------------------------------
function EMT:ClearData()
    self.selfAuraInstanceID = 0
    self.selfExpirationTime = 0
    wipe(self.allyAuras)
    self.isCrit  = false
    self.isDuped = false
end

---------------------------------------------------------------------------------
-- Aura Scanning (full refresh)
---------------------------------------------------------------------------------
function EMT:ScanAuras()
    self:ClearData()
    if not self.isAugSpec then return end

    -- Read self aura by spell name
    local selfName = C_Spell.GetSpellName(EBON_MIGHT_SELF)
    if selfName then
        local auraData = C_UnitAuras.GetAuraDataBySpellName("player", selfName, "HELPFUL|PLAYER")
        if auraData and auraData.auraInstanceID then
            if not issecretvalue(auraData.applications) then
                self.selfAuraInstanceID = auraData.auraInstanceID
                if auraData.expirationTime and not issecretvalue(auraData.expirationTime) then
                    self.selfExpirationTime = auraData.expirationTime
                end
            end
        end
    end

    -- Read ally auras by iterating roster
    if self.inGroup then
        local othersName = C_Spell.GetSpellName(EBON_MIGHT_OTHERS)
        if othersName then
            local size = GetNumGroupMembers()
            local token = IsInRaid() and "raid" or "party"
            for i = 1, size do
                local unit = token .. i
                if UnitExists(unit) then
                    local auraData = C_UnitAuras.GetAuraDataBySpellName(unit, othersName, "HELPFUL|PLAYER")
                    if auraData and auraData.auraInstanceID and not issecretvalue(auraData.applications) then
                        local value = 0
                        if auraData.points and not issecretvalue(auraData.points) and auraData.points[2] then
                            value = auraData.points[2]
                        end
                        self.allyAuras[auraData.auraInstanceID] = {
                            value = value,
                            unit  = unit,
                        }
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Crit Calculation (ported from reference EMTracker)
---------------------------------------------------------------------------------
function EMT:CalcCrit()
    self.isCrit  = false
    self.isDuped = false

    if not self.inGroup then return end

    -- Read player main stat (first return = base stat, matching reference)
    local mainStat = UnitStat("player", 4)
    if not mainStat or mainStat <= 0 then return end

    -- Sum ally aura values; auraInstanceID keys naturally deduplicate
    local sum   = 0
    local count = 0
    for _, data in pairs(self.allyAuras) do
        sum   = sum + (data.value or 0)
        count = count + 1
    end

    if count == 0 then return end

    local avgMainStat  = sum / count
    local expected     = mainStat * MAIN_STAT_COEFFICIENT / math_max(MIN_TARGETS, count)

    -- Duped check (1.75x)
    if avgMainStat >= expected * DUPE_FACTOR * RATIO_LOWER then
        self.isDuped = true
        expected = expected * DUPE_FACTOR
    end

    -- Crit check (1.5x) — only if Chronowarden talent is known
    if self.canCrit then
        local critLower = expected * CRIT_FACTOR * RATIO_LOWER
        local critUpper = expected * CRIT_FACTOR * RATIO_UPPER
        if avgMainStat > critLower and critUpper > avgMainStat then
            self.isCrit = true
        end
    end
end

---------------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------------
-- Base state uses fully transparent borders so the icon sits flush with no
-- visible frame. Crit/dupe states override color + size to "light up".
local DEFAULT_BORDER_COLOR = { 0, 0, 0, 0 }
local BASE_BORDER_SIZE = 1
local DUPE_BORDER_SIZE = 2
local CRIT_BORDER_SIZE = 2

-- Show/hide a FontString together with its KE soft outline shadows. Calling
-- Hide() on the main FontString alone leaves the 8 shadow FontStrings visible
-- (separate objects on fontString._keSoftOutline), which appears as a ghost
-- of the hidden text.
local function SetTextElementShown(fontString, shown)
    if not fontString then return end
    if shown then
        fontString:Show()
        if fontString._keSoftOutline then
            fontString._keSoftOutline:SetShown(true)
        end
    else
        fontString:Hide()
        if fontString._keSoftOutline then
            fontString._keSoftOutline:SetShown(false)
        end
    end
end

-- Recolor and resize the four border strips created by KE:AddIconBorders.
-- Resize grows inward (borders are anchored to the outer corners), so larger
-- sizes eat into the icon edge slightly. At 2-3px on a 48px icon this sits
-- inside the KE:ApplyIconZoom crop region and is barely visible.
function EMT:SetBorderStyle(color, size)
    if not self.iconFrame or not self.iconFrame.borders then return end
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    local borders = self.iconFrame.borders
    for _, tex in pairs(borders) do
        if tex.SetColorTexture then
            tex:SetColorTexture(r, g, b, a)
        end
    end
    if borders.top    and borders.top.SetHeight    then borders.top:SetHeight(size)    end
    if borders.bottom and borders.bottom.SetHeight then borders.bottom:SetHeight(size) end
    if borders.left   and borders.left.SetWidth    then borders.left:SetWidth(size)    end
    if borders.right  and borders.right.SetWidth   then borders.right:SetWidth(size)   end
end

function EMT:UpdateDisplay()
    if not self.countdownText then return end

    -- Update countdown text (Icon mode shows this; Text mode hides the widget
    -- but we still update it so a mode switch mid-cast shows correct time).
    if self.selfAuraInstanceID == 0 then
        self.countdownText:SetText("0")
    else
        local remaining = math_floor(self.selfExpirationTime - GetTime())
        if remaining < 0 then remaining = 0 end
        self.countdownText:SetText(tostring(remaining))
    end

    -- Calculate crit state
    self:CalcCrit()
    -- Preview override: CalcCrit requires a real group + ally auras, which
    -- previews don't have. Force CRIT so the user can see the border + label
    -- highlighting in the GUI preview regardless of mode.
    if self.isPreview then
        self.isCrit = true
        self.isDuped = false
    end

    -- Pick text + border color + border size + state-label text based on state.
    -- Base uses BaseColor for text but default black 1px borders so borders
    -- only visually "light up" when something interesting happens.
    local textColor, borderColor, borderSize, labelText
    if self.isCrit then
        textColor = self.db.CritColor or { 1, 0, 1, 1 }
        borderColor = textColor
        borderSize = CRIT_BORDER_SIZE
        labelText = "CRIT"
    elseif self.isDuped then
        textColor = self.db.DupeColor or { 1, 0.5, 0, 1 }
        borderColor = textColor
        borderSize = DUPE_BORDER_SIZE
        labelText = "DUPE"
    else
        textColor = self.db.BaseColor or { 1, 1, 1, 1 }
        borderColor = DEFAULT_BORDER_COLOR
        borderSize = BASE_BORDER_SIZE
        labelText = ""
    end
    self.countdownText:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
    if self.stateLabel then
        self.stateLabel:SetText(labelText)
        self.stateLabel:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
    end
    self:SetBorderStyle(borderColor, borderSize)

    -- Handle OnlyShowCrit visibility
    if self.db.OnlyShowCrit and not self.isCrit then
        self:HideTracker()
    elseif self.selfAuraInstanceID > 0 then
        self:ShowTracker()
    else
        self:HideTracker()
    end
end

---------------------------------------------------------------------------------
-- Ticker Management
---------------------------------------------------------------------------------
function EMT:TickerHandling()
    if self.selfAuraInstanceID > 0 then
        if not self.ticker then
            self.ticker = C_Timer.NewTicker(REFRESH_INTERVAL, function()
                self:UpdateDisplay()
            end)
        end
    else
        if self.ticker then
            self.ticker:Cancel()
            self.ticker = nil
        end
    end
end

function EMT:StopTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

---------------------------------------------------------------------------------
-- Show / Hide (idempotent)
---------------------------------------------------------------------------------
function EMT:ShowTracker()
    if self._shown then return end
    self._shown = true
    if self.frame and not self.isPreview then
        self.frame:Show()
    end
end

function EMT:HideTracker()
    if not self._shown then return end
    self._shown = false
    if self.frame and not self.isPreview then
        self.frame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function EMT:CreateFrames()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_EbonMightTracker", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(48, 48)
    frame:Hide()

    local iconFrame = CreateFrame("Frame", nil, frame)
    iconFrame:SetAllPoints(frame)

    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(iconFrame)
    iconTex:SetTexture(ICON_ID)
    KE:ApplyIconZoom(iconTex)
    KE:AddIconBorders(iconFrame)

    local fontPath = KE:GetFontPath(self.db.FontFace)
    local wowOutline = KE:GetFontOutline(self.db.FontOutline) or ""
    local fontSize = self.db.FontSize or 22

    -- Countdown text inside the icon (Icon mode). Parent to iconFrame with
    -- sublevel 8 so it draws above the icon texture and border strips.
    -- Set font BEFORE any SetText call; calling SetText on a FontString without
    -- a font raises a 12.0 taint error.
    local countdownText = iconFrame:CreateFontString(nil, "OVERLAY", nil, 8)
    countdownText:SetFont(fontPath, fontSize, wowOutline)
    countdownText:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    countdownText:SetText("0")

    -- State label above the frame (Text mode). "CRIT" / "DUPE" / empty.
    -- Parented to the outer frame so it isn't clipped by iconFrame.
    local stateLabel = frame:CreateFontString(nil, "OVERLAY")
    stateLabel:SetFont(fontPath, fontSize, wowOutline)
    stateLabel:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    stateLabel:SetText("")
    stateLabel:Hide()

    self.frame         = frame
    self.iconFrame     = iconFrame
    self.iconTexture   = iconTex
    self.countdownText = countdownText
    self.stateLabel    = stateLabel
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function EMT:ApplySettings()
    if not self.frame then return end

    local size = self.db.IconSize or 48
    self.frame:SetSize(size, size)

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)

    if self.db.Strata then
        self.frame:SetFrameStrata(self.db.Strata)
    end

    KE:ApplyFontToText(self.countdownText, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
    KE:ApplyFontToText(self.stateLabel,    self.db.FontFace, self.db.FontSize, self.db.FontOutline)

    -- Mode-specific element visibility. Both elements always exist; we just
    -- toggle visibility so mode switches are cheap (no frame recreation).
    -- Soft outlines are a separate object (fontString._keSoftOutline) and
    -- must be shown/hidden alongside the main FontString, otherwise the
    -- 8 shadow FontStrings "ghost" behind the intended-hidden element.
    local isText = self.db.Mode == "text"
    if self.iconTexture then
        if isText then self.iconTexture:Hide() else self.iconTexture:Show() end
    end
    SetTextElementShown(self.countdownText, not isText)
    SetTextElementShown(self.stateLabel, isText)

    self:UpdateDisplay()
end

---------------------------------------------------------------------------------
-- EditMode
---------------------------------------------------------------------------------
function EMT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "EbonMightTracker",
            displayName = "Ebon Might Tracker",
            frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "EbonMightTracker",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview Support
---------------------------------------------------------------------------------
function EMT:ShowPreview()
    if not self.frame then self:CreateFrames() end
    self:RegWithEditMode()
    self.isPreview = true
    -- Sync _shown with the direct frame:Show() below so ShowTracker/HideTracker
    -- stay consistent if called while previewing.
    self._shown = true
    self.selfAuraInstanceID = 1
    self.selfExpirationTime = GetTime() + 20
    -- ApplySettings handles mode visibility + calls UpdateDisplay, which
    -- sees isPreview=true and forces CRIT visuals (border + label + color).
    self:ApplySettings()
    self.frame:Show()
end

function EMT:HidePreview()
    self.isPreview = false
    -- Reset _shown so the next real-aura ShowTracker isn't short-circuited
    -- by a stale "already shown" flag from the preview flow.
    self._shown = false
    if self.frame then self.frame:Hide() end
    -- Re-sync with actual game state. ShowPreview overwrote selfAuraInstanceID
    -- with a fake ID, so without a rescan the module would stay desynced from
    -- any real Ebon Might that was active when the preview started, until the
    -- next isFullUpdate or re-cast.
    self:ScanAuras()
    self:TickerHandling()
    self:UpdateDisplay()
end

---------------------------------------------------------------------------------
-- UNIT_AURA Handler
---------------------------------------------------------------------------------
function EMT:OnUnitAura(_, unit, updateInfo)
    if not self.db.Enabled or self.isPreview then return end
    if not self.isAugSpec then return end
    if not unit then return end

    -- Filter: only player, party, raid (not pets)
    if unit ~= "player" and not unit:find("^party%d") and not unit:find("^raid%d") then return end
    if unit:find("pet") then return end

    if not updateInfo then return end

    if updateInfo.isFullUpdate then
        self:ScanAuras()
        self:TickerHandling()
        self:UpdateDisplay()
        return
    end

    local changed = false

    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            -- aura.applications is secret-tainted; use as gate
            if not issecretvalue(aura.applications) then
                -- EM on self
                if aura.spellId == EBON_MIGHT_SELF and aura.sourceUnit == "player" and unit == "player" then
                    self.selfAuraInstanceID = aura.auraInstanceID
                    if aura.expirationTime and not issecretvalue(aura.expirationTime) then
                        self.selfExpirationTime = aura.expirationTime
                    end
                    changed = true
                    break
                end
                -- EM on ally
                if self.inGroup and aura.spellId == EBON_MIGHT_OTHERS and aura.sourceUnit == "player" then
                    local value = 0
                    if aura.points and not issecretvalue(aura.points) and aura.points[2] then
                        value = aura.points[2]
                    end
                    self.allyAuras[aura.auraInstanceID] = {
                        value = value,
                        unit  = unit,
                    }
                    changed = true
                    break
                end
            end
        end
    end

    if updateInfo.updatedAuraInstanceIDs then
        for _, instanceID in ipairs(updateInfo.updatedAuraInstanceIDs) do
            -- Self update
            if instanceID == self.selfAuraInstanceID and unit == "player" then
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instanceID)
                if auraData and auraData.expirationTime and not issecretvalue(auraData.expirationTime) then
                    self.selfExpirationTime = auraData.expirationTime
                    changed = true
                end
            end
            -- Ally update
            local tracked = self.allyAuras[instanceID]
            if tracked and tracked.unit == unit then
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, instanceID)
                if auraData and auraData.points and not issecretvalue(auraData.points) and auraData.points[2] then
                    tracked.value = auraData.points[2]
                    changed = true
                end
            end
        end
    end

    if updateInfo.removedAuraInstanceIDs then
        for _, instanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
            if instanceID == self.selfAuraInstanceID and unit == "player" then
                -- Self removal → wipe all state (ally EMs end with the self aura,
                -- matching reference behaviour and preventing stale ally data
                -- from skewing CalcCrit on the next cast).
                self:ClearData()
                changed = true
            else
                -- Ally removal. Check unit alongside instanceID — aura instance
                -- IDs are per-unit, not global, so cross-unit ID collisions in
                -- raids can cause false removals without the unit guard.
                local tracked = self.allyAuras[instanceID]
                if tracked and tracked.unit == unit then
                    self.allyAuras[instanceID] = nil
                    changed = true
                end
            end
        end
    end

    if changed then
        self:TickerHandling()
        self:UpdateDisplay()
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function EMT:PLAYER_ENTERING_WORLD()
    self.isAugSpec = self:IsValidSpec()
    self:UpdateCanCrit()
    self.inGroup = IsInGroup()
    self:ScanAuras()
    self:UpdateDisplay()
end

function EMT:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    self.isAugSpec = self:IsValidSpec()
    -- Re-check Chronowarden talent — a spec change may load a different
    -- talent loadout that affects canCrit even without a TRAIT_CONFIG_UPDATED.
    self:UpdateCanCrit()
    if not self.isAugSpec then
        self:HideTracker()
        self:ClearData()
    else
        self:ScanAuras()
        self:UpdateDisplay()
    end
end

function EMT:TRAIT_CONFIG_UPDATED()
    self:UpdateCanCrit()
end

function EMT:GROUP_JOINED()
    self.inGroup = true
end

function EMT:GROUP_LEFT()
    self.inGroup = false
    self:ClearData()
    self:UpdateDisplay()
end

function EMT:GROUP_ROSTER_UPDATE()
    self.inGroup = IsInGroup()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function EMT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(self.db.Enabled == true)
end

function EMT:OnEnable()
    self:UpdateDB()
    -- Hard class gate: non-Evokers get no frame, no EditMode registration, no events.
    -- Matches PrescienceTracker / BloodlustTracker pattern.
    if not self.db.Enabled then return end
    if select(2, UnitClass("player")) ~= "EVOKER" then return end

    self:CreateFrames()
    self:RegWithEditMode()
    self:ApplySettings()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED")
    self:RegisterEvent("GROUP_JOINED")
    self:RegisterEvent("GROUP_LEFT")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
end

function EMT:OnDisable()
    self:UnregisterAllEvents()
    self:StopTicker()
    self:HideTracker()
    self:ClearData()
end
