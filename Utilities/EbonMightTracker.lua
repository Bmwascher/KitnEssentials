-- ╔══════════════════════════════════════════════════════════╗
-- ║  EbonMightTracker.lua                                    ║
-- ║  Module: Ebon Might Tracker                              ║
-- ║  Purpose: Displays Ebon Might buff duration with crit    ║
-- ║           and duped cast detection for Augmentation.     ║
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
local math_floor      = math.floor

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local EBON_MIGHT_SELF    = 395296     -- Aura on self
local EBON_MIGHT_OTHERS  = 395152     -- Aura on allies
local CHRONO_CRIT_TALENT = 431874     -- Chronowarden "canCrit" talent (Double Time)
local DUPE_TALENT        = 1259175    -- "canDupe" talent (apex dupe proc)
local AUG_SPEC_ID        = 1473       -- Augmentation spec ID

-- Baseline classifier midpoints (from EbonMightTracker v1.0.6 reference).
-- Relative multiplier against learned baseline for target count. Chosen
-- midway between expected discrete tiers so bucket boundaries are stable
-- under the ±5% server-side value noise. Specifically:
--   base    = ~1.00x baseline
--   crit    = ~1.50x baseline   → MULT_CRIT at 1.25 catches anything ≥1.25
--   dupe    = ~1.75x baseline   → MULT_DUPE at 1.625 catches anything ≥1.625
--   both    = 1.5*1.75 = 2.625x → MULT_DUPE_CRIT at 2.1875 catches anything ≥2.1875
local MULT_CRIT      = 1.25
local MULT_DUPE      = 1.625
local MULT_DUPE_CRIT = 2.1875

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
EMT.canDupe             = false
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

function EMT:UpdateCanDupe()
    local ok, known = pcall(C_SpellBook.IsSpellKnown, DUPE_TALENT)
    self.canDupe = ok and known == true
end

function EMT:UpdateTalents()
    self:UpdateCanCrit()
    self:UpdateCanDupe()
end

---------------------------------------------------------------------------------
-- Aura Value Extraction
---------------------------------------------------------------------------------
-- Pick the largest positive point value from aura.points. Replaces the
-- hardcoded points[2] read — Blizzard has reshuffled the points table in
-- the past and may again. Largest positive is always the mainstat delta
-- (the other entries are usually 0 or small secondary stats).
function EMT:BestPoint(aura)
    if not aura or not aura.points then return nil end
    if issecretvalue(aura.points) then return nil end
    local best
    for _, v in pairs(aura.points) do
        if type(v) == "number" and v > 0 and (not best or v > best) then
            best = v
        end
    end
    return best
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
                        local value = self:BestPoint(auraData) or 0
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
-- Classifier (baseline-relative — 12.0.5 safe)
---------------------------------------------------------------------------------
-- 12.0.5 made UnitStat return secret values during encounters, so the
-- previous cross-API ratio (aura.points vs UnitStat*0.16) became unreliable.
-- This replacement compares ONLY aura-to-aura: the current observed average
-- mainstat bonus vs a learned baseline for the same target count. Baseline
-- is persisted in AceDB so it survives /reload and zone changes.
--
-- Bucketing (multiplier m = observed / baseline):
--   m < 1.25   → base     (also re-baseline if m < 1, so baseline self-corrects downward)
--   m < 1.625  → crit
--   m < 2.1875 → dupe
--   else        → dupe+crit
--
-- Talent gates (canCrit / canDupe) are applied AFTER classification so a
-- player without Chronowarden can never see a "crit" false positive.
function EMT:Classify(observedAvg, targetCount)
    self.isCrit  = false
    self.isDuped = false

    if targetCount <= 0 or observedAvg <= 0 then return end

    local db = self.db
    if not db then return end
    db.BaselineObserved = db.BaselineObserved or {}
    local baseline = db.BaselineObserved[targetCount]

    local isCrit, isDuped
    if not baseline or baseline <= 0 then
        -- First observation at this target count — treat as baseline.
        db.BaselineObserved[targetCount] = observedAvg
        isCrit, isDuped = false, false
    else
        local m = observedAvg / baseline
        if m < MULT_CRIT then
            -- Observed is smaller than baseline — the old baseline was a
            -- crit/dupe by mistake. Re-baseline down to current observation.
            if observedAvg < baseline then
                db.BaselineObserved[targetCount] = observedAvg
            end
            isCrit, isDuped = false, false
        elseif m < MULT_DUPE then
            isCrit, isDuped = true, false
        elseif m < MULT_DUPE_CRIT then
            isCrit, isDuped = false, true
        else
            isCrit, isDuped = true, true
        end
    end

    -- Talent gates: strip false-positives the player can't actually roll.
    if not self.canCrit then isCrit = false end
    if not self.canDupe then isDuped = false end

    self.isCrit  = isCrit
    self.isDuped = isDuped
end

-- Compute inputs to Classify from current tracked ally auras.
function EMT:RecomputeClassification()
    if not self.inGroup then
        self.isCrit, self.isDuped = false, false
        return
    end

    local sum, count = 0, 0
    for _, data in pairs(self.allyAuras) do
        local v = data.value or 0
        if v > 0 then
            sum   = sum + v
            count = count + 1
        end
    end

    if count == 0 then
        self.isCrit, self.isDuped = false, false
        return
    end

    self:Classify(sum / count, count)
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

    -- Classify crit/dupe state from tracked ally auras
    self:RecomputeClassification()
    -- Preview override: Classify needs a real group + ally aura values, which
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
                    local value = self:BestPoint(aura) or 0
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
                local value = auraData and self:BestPoint(auraData) or nil
                if value and value > 0 then
                    tracked.value = value
                    changed = true
                end
            end
        end
    end

    if updateInfo.removedAuraInstanceIDs then
        for _, instanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
            if instanceID == self.selfAuraInstanceID and unit == "player" then
                -- Self removal → wipe all state. Stricter than reference v1.0.6
                -- (which only clears selfAura and lets ally removes arrive
                -- naturally): under heavy combat Blizzard can deliver removes
                -- out of order, and a stale ally value slipping into the next
                -- Classify() would poison the baseline. Any ally removes that
                -- still arrive for IDs we already wiped are a harmless no-op.
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
    self:UpdateTalents()
    self.inGroup = IsInGroup()
    self:ScanAuras()
    self:UpdateDisplay()
end

function EMT:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    self.isAugSpec = self:IsValidSpec()
    -- Re-check talents — a spec change may load a different talent loadout
    -- that affects canCrit / canDupe even without a TRAIT_CONFIG_UPDATED.
    self:UpdateTalents()
    if not self.isAugSpec then
        self:HideTracker()
        self:ClearData()
    else
        self:ScanAuras()
        self:UpdateDisplay()
    end
end

function EMT:TRAIT_CONFIG_UPDATED()
    self:UpdateTalents()
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

-- UNIT_FLAGS fires on death, charm, afk-enter, etc. Recompute whenever a
-- tracked group member's flags change so the state reflects current alive /
-- present members. Matches reference v1.0.6 behavior.
function EMT:UNIT_FLAGS(_, unit)
    if not self.isAugSpec or self.isPreview then return end
    if not unit then return end
    if unit ~= "player" and not unit:find("^party%d") and not unit:find("^raid%d") then return end
    if unit:find("pet") then return end
    self:UpdateDisplay()
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
    self:RegisterEvent("UNIT_FLAGS")
end

function EMT:OnDisable()
    self:UnregisterAllEvents()
    self:StopTicker()
    self:HideTracker()
    self:ClearData()
end
