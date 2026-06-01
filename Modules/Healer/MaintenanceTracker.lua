-- ╔══════════════════════════════════════════════════════════╗
-- ║  MaintenanceTracker.lua                                  ║
-- ║  Module: Maintenance Tracker                             ║
-- ║  Purpose: Shows one icon per tracked maintenance buff    ║
-- ║           (HoT/shield) with a count of group members     ║
-- ║           who have it and the lowest remaining duration  ║
-- ║           across those instances. Spec-aware, multi-     ║
-- ║           class healer gated.                            ║
-- ║                                                          ║
-- ║  Scanning logic adapted from PowerWordToolbox v1.1.3     ║
-- ║  with multi-spell tracking added. Original credit for    ║
-- ║  the secret-value-safe scanning pattern (issecretvalue   ║
-- ║  checks before comparisons). The player's auras use a     ║
-- ║  direct by-id lookup; group members take a single sweep. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class MaintenanceTracker: AceModule, AceEvent-3.0
local MT = KitnEssentials:NewModule("MaintenanceTracker", "AceEvent-3.0")

local CreateFrame           = CreateFrame
local GetTime               = GetTime
local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local UnitClass             = UnitClass
local UnitGUID              = UnitGUID
local UnitExists            = UnitExists
local UnitIsUnit            = UnitIsUnit
local GetNumGroupMembers    = GetNumGroupMembers
local IsInRaid              = IsInRaid
local C_UnitAuras           = C_UnitAuras
local C_Spell               = C_Spell
local issecretvalue         = issecretvalue
local math_huge             = math.huge
local math_floor            = math.floor
local string_sub            = string.sub
local string_format         = string.format
local pairs                 = pairs
local ipairs                = ipairs
local wipe                  = wipe
local tostring              = tostring

------------------------------------------------------------------------
-- Spec configuration. Each spec maps to an array of spell configs;
-- specs with multiple entries render multiple icons (one per spell)
-- positioned by the user's growth direction setting.
--
-- Spell IDs here are the BUFF/HoT id applied to the target (NOT the
-- cast id). Examples: Renewing Mist's cast spell is 115151 but the HoT
-- on the target is 119611; Enveloping Mist uses 124682 for both.
------------------------------------------------------------------------
local SPEC_CONFIG = {
    [256] = {  -- Discipline Priest
        { spellID = 194384, spellName = "Atonement",       previewCount = 6 },
    },
    [270] = {  -- Mistweaver Monk
        { spellID = 124682, spellName = "Enveloping Mist", previewCount = 2 },
        { spellID = 119611, spellName = "Renewing Mist",   previewCount = 4 },
    },
    [105] = {  -- Restoration Druid
        {
            spellIDs     = { 774, 155777 },  -- Rejuvenation + Germination, one icon
            spellName    = "Rejuvenation",
            previewCount = 5,
        },
    },
    [264] = {  -- Restoration Shaman
        { spellID = 61295,  spellName = "Riptide", previewCount = 4 },
    },
    [1468] = {  -- Preservation Evoker
        { spellID = 364343, spellName = "Echo",    previewCount = 3 },
    },
}

------------------------------------------------------------------------
-- Class gate. Only PRIEST + MONK + DRUID + SHAMAN + EVOKER can be the
-- relevant specs above; on every other class the module short-circuits
-- at OnEnable and never touches a frame, event, or ticker. Zero
-- runtime cost off-class.
------------------------------------------------------------------------
local SUPPORTED_CLASSES = {
    PRIEST = true, MONK = true, DRUID = true,
    SHAMAN = true, EVOKER = true,
}
local _, playerClass = UnitClass("player")

local UPDATE_TICK = 0.1  -- 10Hz display refresh

-- Diagnostic flag. When true, ScanUnit prints which scan path ran and how
-- many buffs it registered: the player FAST path (GetPlayerAuraBySpellID)
-- vs the group single-pass. Flip to true, /reload, apply a tracked buff to
-- yourself + a party member, read the log, then flip back to false. Gated
-- so the false path compiles to nothing hot. Leave false in ship builds.
local DEBUG_MT = false

------------------------------------------------------------------------
-- Tracking state
------------------------------------------------------------------------
-- Active trackers for the current spec. Rebuilt by DetectSpec. Each
-- entry holds its own per-spell state so multiple buffs can be tracked
-- independently without cross-contamination.
--
-- Shape:
--   trackers[i] = {
--     spellIDs    = { N1, N2, ... },  -- one or more spell IDs (combined)
--     iconSpellID = N,                -- texture source
--     spellName, previewCount,
--     activeBuffs = { [guid] = { [spellID] = expirationTime, ... } },
--     expiredBuffer = {},  -- flat (guid, spellID) pairs, reused per sweep
--     display = { lastCount = -1, lastLowestStr = "", lastColorBand = -1, lastShowLowest = nil },
--   }
--
-- The per-unit sub-table makes combined-spell tracking correct:
--   * count = total number of live buff instances across all units
--     (someone with both Rejuv + Germination counts as 2)
--   * lowest = min expiration across ALL instances (signals "any HoT
--     somewhere is about to drop")
local trackers = {}
local currentSpec = nil
local isPreviewActive = false
local _onUpdateElapsed = 0  -- accumulator for the shared 10Hz OnUpdate

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
-- Fast prefix check for group unit tokens (raid1..40, party1..4,
-- player). Avoids pattern compilation overhead on every UNIT_AURA.
local function IsGroupUnit(unit)
    if unit == "player" then return true end
    local prefix = string_sub(unit, 1, 4)
    return prefix == "raid" or prefix == "part"
end

-- Validates source/expiry and registers if usable. Returns true on
-- success. spellID is passed explicitly because the fast-path API was
-- queried for a specific ID, and we don't want to read it back off the
-- aura where it might be a secret value.
local function TryRegisterAura(tracker, guid, spellID, aura)
    if issecretvalue(aura.sourceUnit) then return false end
    if not (aura.sourceUnit and UnitIsUnit(aura.sourceUnit, "player")) then return false end
    if issecretvalue(aura.expirationTime) then return false end
    local sub = tracker.activeBuffs[guid]
    if not sub then
        sub = {}
        tracker.activeBuffs[guid] = sub
    end
    sub[spellID] = aura.expirationTime
    return true
end

-- Remove one spell's entry for a guid. If the unit has no remaining
-- buffs from this tracker, drop the sub-table entirely.
local function ClearSpellForGuid(tracker, guid, spellID)
    local sub = tracker.activeBuffs[guid]
    if not sub then return end
    sub[spellID] = nil
    if next(sub) == nil then
        tracker.activeBuffs[guid] = nil
    end
end

-- Count live buff instances in this tracker (each spell on each unit
-- counts separately -- a unit with both Rejuv + Germination = 2) and
-- find the lowest remaining duration across ALL buff instances. Sweeps
-- expired entries inline. Returns (count, lowestSec). lowest=0 when
-- nothing is up.
local function GetCountAndLowest(tracker)
    local count   = 0
    local lowest  = math_huge
    local now     = GetTime()
    local active  = tracker.activeBuffs
    local expired = tracker.expiredBuffer

    for guid, sub in pairs(active) do
        for spellID, expiry in pairs(sub) do
            if not issecretvalue(expiry) then
                local remaining = expiry - now
                if remaining > 0 then
                    count = count + 1
                    if remaining < lowest then lowest = remaining end
                else
                    -- Queue (guid, spellID) for sweep. Paired in a flat
                    -- list so we don't allocate per-sweep sub-tables.
                    expired[#expired + 1] = guid
                    expired[#expired + 1] = spellID
                end
            end
        end
    end

    -- Sweep expired entries (paired guid, spellID).
    for i = 1, #expired, 2 do
        ClearSpellForGuid(tracker, expired[i], expired[i + 1])
        expired[i] = nil
        expired[i + 1] = nil
    end

    if lowest == math_huge then lowest = 0 end
    return count, lowest
end

local function ResetDisplayCache(tracker)
    local d = tracker.display
    d.lastCount      = -1
    d.lastLowestStr  = ""
    d.lastColorBand  = -1
    d.lastShowLowest = nil
end

------------------------------------------------------------------------
-- Scanning
------------------------------------------------------------------------
-- Per UNIT_AURA we reconcile one unit's tracked buffs. The player's own
-- auras are addressable directly by spellID (O(1) per tracked spell) via
-- GetPlayerAuraBySpellID. There is no per-unit by-id accessor for group
-- members in 12.0, so they take a single pass over their helpful auras —
-- one iteration regardless of how many spells are tracked.
function MT:ScanUnit(unit)
    if #trackers == 0 then return end
    if not UnitExists(unit) then return end
    if not IsGroupUnit(unit) then return end

    local guid = UnitGUID(unit)
    if not guid or issecretvalue(guid) then return end

    -- Fast path: the player's own auras fetch directly by spellID, no
    -- iteration. Only valid for "player"; falls through to the group scan
    -- below if the accessor is unavailable.
    local playerLookup = (unit == "player") and C_UnitAuras.GetPlayerAuraBySpellID
    if playerLookup then
        local found = 0
        for ti = 1, #trackers do
            local t = trackers[ti]
            local spellIDs = t.spellIDs
            for si = 1, #spellIDs do
                local spellID = spellIDs[si]
                local aura = playerLookup(spellID)
                -- TryRegisterAura re-filters on sourceUnit == player and a
                -- non-secret expiry, so an ally-cast aura of the same id is
                -- rejected here and cleared.
                if aura and TryRegisterAura(t, guid, spellID, aura) then
                    found = found + 1
                else
                    ClearSpellForGuid(t, guid, spellID)
                end
            end
        end
        if DEBUG_MT then
            KE:Print(("|cff39ff14[MT]|r player FAST path (GetPlayerAuraBySpellID): %d self-buff(s) tracked"):format(found))
        end
        return
    end

    -- Group member: drop this unit's tracked entries, then re-register
    -- whatever is currently present in a single sweep of its helpful auras.
    -- Ally-cast instances are rejected by TryRegisterAura's sourceUnit guard.
    for ti = 1, #trackers do
        trackers[ti].activeBuffs[guid] = nil
    end
    local registered = 0
    local i = 1
    while true do
        local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not a then break end
        local sid = a.spellId
        if not issecretvalue(sid) then
            for ti = 1, #trackers do
                local t = trackers[ti]
                local spellIDs = t.spellIDs
                for si = 1, #spellIDs do
                    if spellIDs[si] == sid and TryRegisterAura(t, guid, sid, a) then
                        registered = registered + 1
                    end
                end
            end
        end
        i = i + 1
    end
    if DEBUG_MT and registered > 0 then
        KE:Print(("|cff39ff14[MT]|r group single-pass %s: %d buff(s) registered"):format(unit, registered))
    end
end

function MT:ScanAllUnits()
    if #trackers == 0 then return end
    for ti = 1, #trackers do
        wipe(trackers[ti].activeBuffs)
    end

    local n = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, n do
            self:ScanUnit("raid" .. i)
        end
    else
        self:ScanUnit("player")
        for i = 1, n do
            self:ScanUnit("party" .. i)
        end
    end
end

------------------------------------------------------------------------
-- Spec detection
------------------------------------------------------------------------
function MT:DetectSpec()
    if not self.isSupported then return end

    local specIndex = GetSpecialization()
    local specID    = specIndex and GetSpecializationInfo(specIndex) or nil
    local configs   = specID and SPEC_CONFIG[specID] or nil

    if not configs then
        -- Off-spec for this module. Clear state and hide frames.
        currentSpec = nil
        wipe(trackers)
        if self.frames then
            for _, f in ipairs(self.frames) do f:Hide() end
        end
        return
    end

    -- Spec changed (or first-time detect): rebuild tracker list.
    local changed = currentSpec ~= specID
    currentSpec = specID

    if changed then
        wipe(trackers)
        for i, config in ipairs(configs) do
            -- Normalize: a config can specify `spellID = N` (single) or
            -- `spellIDs = {N1, N2, ...}` (combined under one icon).
            -- Internally everything is an array so the rest of the
            -- module has one shape to deal with.
            local spellIDs = config.spellIDs or { config.spellID }
            trackers[i] = {
                spellIDs      = spellIDs,
                iconSpellID   = config.iconSpellID or spellIDs[1],
                spellName     = config.spellName,
                previewCount  = config.previewCount or 4,
                activeBuffs   = {},
                expiredBuffer = {},
                display = {
                    lastCount      = -1,
                    lastLowestStr  = "",
                    lastColorBand  = -1,
                    lastShowLowest = nil,
                },
            }
        end

        self:RebuildFrames()
        self:ScanAllUnits()
        if self.frames and self.db.Enabled then
            for i = 1, #trackers do
                if self.frames[i] then self.frames[i]:Show() end
            end
        end
    end
end

------------------------------------------------------------------------
-- Frame creation
------------------------------------------------------------------------
-- Lazily creates/reuses one frame per active tracker. Excess frames
-- from a prior (larger) spec are hidden but kept pooled.
function MT:RebuildFrames()
    self.frames = self.frames or {}

    -- Create or reuse one frame per tracker.
    for i = 1, #trackers do
        local frame = self.frames[i]
        if not frame then
            frame = CreateFrame("Frame", "KE_MaintenanceTracker" .. i, UIParent)
            frame:Hide()

            frame.icon = frame:CreateTexture(nil, "ARTWORK")
            frame.icon:SetAllPoints()
            KE:ApplyIconZoom(frame.icon, 0.08)
            KE:AddIconBorders(frame, { 0, 0, 0, 1 })

            frame.count = frame:CreateFontString(nil, "OVERLAY")
            frame.count:SetPoint("CENTER", frame, "CENTER", 0, 0)
            frame.count:SetShadowOffset(0, 0)

            frame.lowest = frame:CreateFontString(nil, "OVERLAY")
            frame.lowest:SetPoint("TOP", frame, "BOTTOM", 0, -2)
            frame.lowest:SetShadowOffset(0, 0)

            self.frames[i] = frame
        end

        local t = trackers[i]
        frame:SetSize(self.db.IconSize, self.db.IconSize)
        frame:SetFrameStrata(self.db.Strata or "HIGH")
        local tex = C_Spell.GetSpellTexture(t.iconSpellID)
        if tex then frame.icon:SetTexture(tex) end

        KE:ApplyFontToText(frame.count, self.db.FontFace, self.db.CountFontSize, self.db.FontOutline)
        KE:ApplyFontToText(frame.lowest, self.db.FontFace, self.db.LowestFontSize, self.db.FontOutline)
        local countColor = self.db.CountColor or { 1, 1, 1, 1 }
        frame.count:SetTextColor(countColor[1], countColor[2], countColor[3], countColor[4] or 1)
        frame.count:SetText("0")
        frame.lowest:SetText("--")
        frame.lowest:SetShown(self.db.ShowLowest)
        -- Soft-outline shadows track each element's own visibility: count is
        -- always shown, lowest follows ShowLowest. A hidden parent frame keeps
        -- them from rendering regardless, so showing them here is safe even
        -- before the tracker frame is displayed.
        if frame.count._keSoftOutline then frame.count._keSoftOutline:SetShown(true) end
        if frame.lowest._keSoftOutline then frame.lowest._keSoftOutline:SetShown(self.db.ShowLowest) end
        ResetDisplayCache(t)
    end

    -- Hide any leftover frames from a prior larger spec.
    for i = #trackers + 1, #self.frames do
        self.frames[i]:Hide()
    end

    -- (Re)attach or detach the shared 10Hz OnUpdate on frames[1].
    -- Done unconditionally here so that disable→enable cycles (which nil
    -- the script in OnDisable) always restore it when trackers are present.
    if self.frames[1] then
        if #trackers > 0 then
            _onUpdateElapsed = 0
            self.frames[1]:SetScript("OnUpdate", function(_, dt)
                _onUpdateElapsed = _onUpdateElapsed + dt
                if _onUpdateElapsed < UPDATE_TICK then return end
                _onUpdateElapsed = 0
                MT:UpdateDisplay()
            end)
        else
            self.frames[1]:SetScript("OnUpdate", nil)
        end
    end

    self:ApplyPosition()
end

------------------------------------------------------------------------
-- Display
------------------------------------------------------------------------
function MT:UpdateDisplay()
    if isPreviewActive then return end
    if not self.frames or #trackers == 0 then return end

    local showLowest = self.db.ShowLowest
    local lowThr     = self.db.LowThreshold or 3
    local midThr     = self.db.MidThreshold or 6
    local lowCol     = self.db.LowDurationColor
    local midCol     = self.db.MidDurationColor
    local highCol    = self.db.HighDurationColor

    for ti = 1, #trackers do
        local t = trackers[ti]
        local frame = self.frames[ti]
        if not frame then break end

        local count, lowest = GetCountAndLowest(t)
        local d = t.display

        if count ~= d.lastCount then
            frame.count:SetText(tostring(count))
            d.lastCount = count
        end

        if showLowest ~= d.lastShowLowest then
            frame.lowest:SetShown(showLowest)
            if frame.lowest._keSoftOutline then frame.lowest._keSoftOutline:SetShown(showLowest) end
            d.lastShowLowest = showLowest
        end

        if showLowest then
            if count > 0 and lowest > 0 then
                local band
                if lowest <= lowThr then band = 1
                elseif lowest <= midThr then band = 2
                else band = 3 end

                if band ~= d.lastColorBand then
                    local color = (band == 1 and lowCol) or (band == 2 and midCol) or highCol
                    if color then
                        frame.lowest:SetTextColor(color[1], color[2], color[3], color[4] or 1)
                    end
                    d.lastColorBand = band
                end

                -- Format mirrors TimeSpiral/InnervateTracker/CastbarBase:
                -- integer when 3s+ remain, 1 decimal under 3s. Safe
                -- comparison: `lowest` is plain Lua arithmetic and
                -- `expiry` was filtered through issecretvalue() in
                -- TryRegisterAura before being stored.
                local lowestStr
                if lowest >= 3 then
                    lowestStr = string_format("%d", math_floor(lowest + 0.5))
                else
                    lowestStr = string_format("%.1f", lowest)
                end
                if lowestStr ~= d.lastLowestStr then
                    frame.lowest:SetText(lowestStr)
                    d.lastLowestStr = lowestStr
                end
            else
                if d.lastColorBand ~= 0 then
                    frame.lowest:SetTextColor(0.5, 0.5, 0.55, 1)
                    d.lastColorBand = 0
                end
                if d.lastLowestStr ~= "--" then
                    frame.lowest:SetText("--")
                    d.lastLowestStr = "--"
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Position + settings
------------------------------------------------------------------------
-- First frame uses db.Position. Subsequent frames anchor relative to
-- the previous frame, offset by Spacing in the GrowthDirection.
function MT:ApplyPosition()
    if not self.frames or #self.frames == 0 then return end
    if not self.frames[1] then return end

    local parent = KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
    if not parent then return end

    local pos = self.db.Position
    self.frames[1]:SetParent(parent)
    self.frames[1]:ClearAllPoints()
    self.frames[1]:SetPoint(pos.AnchorFrom, parent, pos.AnchorTo, pos.XOffset, pos.YOffset)
    self.frames[1]:SetFrameStrata(self.db.Strata or "HIGH")
    KE:SnapFrameToPixels(self.frames[1])

    local dir     = self.db.GrowthDirection or "RIGHT"
    local spacing = self.db.Spacing or 4
    local point, relPoint, dx, dy
    if dir == "RIGHT" then
        point, relPoint, dx, dy = "LEFT", "RIGHT", spacing, 0
    elseif dir == "LEFT" then
        point, relPoint, dx, dy = "RIGHT", "LEFT", -spacing, 0
    elseif dir == "UP" then
        point, relPoint, dx, dy = "BOTTOM", "TOP", 0, spacing
    elseif dir == "DOWN" then
        point, relPoint, dx, dy = "TOP", "BOTTOM", 0, -spacing
    else
        point, relPoint, dx, dy = "LEFT", "RIGHT", spacing, 0
    end

    for i = 2, #trackers do
        local f = self.frames[i]
        if f then
            f:ClearAllPoints()
            f:SetPoint(point, self.frames[i - 1], relPoint, dx, dy)
        end
    end
end

function MT:ApplySettings()
    self:UpdateDB()
    if not self.frames then return end

    for i = 1, #trackers do
        local frame = self.frames[i]
        if not frame then break end
        frame:SetSize(self.db.IconSize, self.db.IconSize)
        frame:SetFrameStrata(self.db.Strata or "HIGH")
        KE:ApplyFontToText(frame.count, self.db.FontFace, self.db.CountFontSize, self.db.FontOutline)
        local countColor = self.db.CountColor or { 1, 1, 1, 1 }
        frame.count:SetTextColor(countColor[1], countColor[2], countColor[3], countColor[4] or 1)
        KE:ApplyFontToText(frame.lowest, self.db.FontFace, self.db.LowestFontSize, self.db.FontOutline)
        frame.lowest:SetShown(self.db.ShowLowest)
        local tex = C_Spell.GetSpellTexture(trackers[i].iconSpellID)
        if tex then frame.icon:SetTexture(tex) end
        if frame.count._keSoftOutline then frame.count._keSoftOutline:SetShown(true) end
        if frame.lowest._keSoftOutline then frame.lowest._keSoftOutline:SetShown(self.db.ShowLowest) end
        ResetDisplayCache(trackers[i])
    end

    self:ApplyPosition()
end

------------------------------------------------------------------------
-- Preview
------------------------------------------------------------------------
function MT:ShowPreview()
    if not self.isSupported then return end
    if isPreviewActive then return end

    -- Ensure spec detection has run so trackers/frames exist.
    if #trackers == 0 then
        -- No tracked buff for the current spec — show nothing (silent no-op
        -- for supported class on an untracked spec, e.g. Holy Priest).
        return
    end

    if not self.frames then return end

    isPreviewActive = true

    local midThr = self.db.MidThreshold or 6
    local dummyDuration = midThr + 1  -- sits in the "high" (safe) band

    for i = 1, #trackers do
        local t = trackers[i]
        local frame = self.frames[i]
        if frame then
            local countStr = tostring(t.previewCount or 4)
            frame.count:SetText(countStr)
            if frame.count._keSoftOutline then frame.count._keSoftOutline:SetShown(true) end

            if self.db.ShowLowest then
                local lowestStr = string_format("%d", math_floor(dummyDuration + 0.5))
                frame.lowest:SetText(lowestStr)

                local highCol = self.db.HighDurationColor or { 1, 0.85, 0.4, 1 }
                frame.lowest:SetTextColor(highCol[1], highCol[2], highCol[3], highCol[4] or 1)
                frame.lowest:Show()
                if frame.lowest._keSoftOutline then frame.lowest._keSoftOutline:SetShown(true) end
            else
                frame.lowest:Hide()
                if frame.lowest._keSoftOutline then frame.lowest._keSoftOutline:SetShown(false) end
            end

            -- Reset all cache fields so the live path can overwrite cleanly on hide.
            ResetDisplayCache(t)

            frame:Show()
        end
    end
end

function MT:HidePreview()
    if not isPreviewActive then return end
    isPreviewActive = false

    -- Clear _last* strings so the live path doesn't stale-skip on resume.
    for i = 1, #trackers do
        ResetDisplayCache(trackers[i])
    end

    if not self.db.Enabled then
        if self.frames then
            for _, f in ipairs(self.frames) do f:Hide() end
        end
    else
        -- Resume live display
        self:UpdateDisplay()
    end
end

function MT:TogglePreview()
    if isPreviewActive then
        self:HidePreview()
    else
        self:ShowPreview()
    end
    return isPreviewActive
end

function MT:IsPreviewActive()
    return isPreviewActive
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
function MT:UNIT_AURA(_, unit)
    if #trackers == 0 then return end
    if not IsGroupUnit(unit) then return end
    self:ScanUnit(unit)
end

function MT:GROUP_ROSTER_UPDATE()
    if #trackers == 0 then return end
    self:ScanAllUnits()
end

function MT:PLAYER_ENTERING_WORLD()
    if #trackers == 0 then return end
    self:ScanAllUnits()
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
function MT:UpdateDB()
    self.db = KE.db.profile.MaintenanceTracker
end

function MT:OnInitialize()
    self:UpdateDB()
    self.isSupported = SUPPORTED_CLASSES[playerClass] == true
    self:SetEnabledState(false)
end

function MT:OnEnable()
    if not self.isSupported then return end
    if not self.db.Enabled then return end

    -- Detect spec first so trackers exist before frame build.
    self:DetectSpec()
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "DetectSpec")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "DetectSpec")

    -- Aura tracking events
    self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Show frames if the active spec is one we track.
    if #trackers > 0 then
        self:ScanAllUnits()
        for i = 1, #trackers do
            if self.frames and self.frames[i] then self.frames[i]:Show() end
        end
    end

    if KE.EditMode and self.frames and self.frames[1] then
        KE.EditMode:RegisterElement({
            key         = "MaintenanceTracker",
            displayName = "Maintenance Tracker",
            frame       = self.frames[1],
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position.AnchorFrom = pos.AnchorFrom
                self.db.Position.AnchorTo   = pos.AnchorTo
                self.db.Position.XOffset    = pos.XOffset
                self.db.Position.YOffset    = pos.YOffset
                self:ApplyPosition()
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "MaintenanceTracker",
        })
    end
end

function MT:OnDisable()
    isPreviewActive = false

    self:UnregisterAllEvents()
    if self.frames then
        if self.frames[1] then self.frames[1]:SetScript("OnUpdate", nil) end
        for _, f in ipairs(self.frames) do f:Hide() end
    end
    for ti = 1, #trackers do
        wipe(trackers[ti].activeBuffs)
        ResetDisplayCache(trackers[ti])
    end

    -- Force a full rebuild (and OnUpdate re-wire) on the next enable. We nil
    -- frames[1]'s OnUpdate above; without clearing currentSpec, a same-spec
    -- disable->enable cycle would hit DetectSpec with changed == false, skip
    -- RebuildFrames, and leave the display frozen (frames shown, never ticked).
    currentSpec = nil
    if KE.EditMode then KE.EditMode:UnregisterElement("MaintenanceTracker") end
end
