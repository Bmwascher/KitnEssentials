-- ╔══════════════════════════════════════════════════════════╗
-- ║  WarpDepleteForces.lua                                   ║
-- ║  Module: WarpDeplete Forces Tracker                      ║
-- ║  Purpose: Enemy-count tooltip + nameplate % overlay via  ║
-- ║           C_ScenarioInfo.GetUnitCriteriaProgressValues   ║
-- ║           (added 12.0.5). Also fixes WarpDeplete death   ║
-- ║           tooltip + class-color path (CLEU localized).   ║
-- ║                                                          ║
-- ║  NOTE: Live pull overlay (SetForcesPull feed) removed    ║
-- ║  2026-04-22 — blocked by 12.0.5 SecretValue arithmetic   ║
-- ║  restriction. See memory: project_warpdeplete_pull_      ║
-- ║  blocked.md for full restore path when Blizzard relaxes. ║
-- ║  Requires: WarpDeplete addon                             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local WDF = KitnEssentials:NewModule("WarpDepleteForces", "AceEvent-3.0")

-- Local references
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitCanAttack = UnitCanAttack
local UnitAffectingCombat = UnitAffectingCombat
local UnitClass = UnitClass
local C_ChallengeMode = C_ChallengeMode
local C_ScenarioInfo = C_ScenarioInfo
local C_NamePlate = C_NamePlate
local UnitName = UnitName
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local C_Timer = C_Timer
local format = string.format
local pairs = pairs
local ipairs = ipairs
local table_remove = table.remove
local wipe = wipe
local issecretvalue = issecretvalue or function() return false end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function WDF:UpdateDB()
    self.db = KE.db.profile.Dungeons.WarpDepleteForces
end

---------------------------------------------------------------------------------
-- API Gate
---------------------------------------------------------------------------------

-- Feature-gate: the module is a no-op if the 12.0.5 API is unavailable.
local HasProgressAPI = C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues
local GetProgress = HasProgressAPI and C_ScenarioInfo.GetUnitCriteriaProgressValues

local function IsInChallengeMode()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
end

---------------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------------

local function SetupTooltip()
    if not WDF.db.Tooltip or not GetProgress then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if not WDF.db or not WDF.db.Tooltip then return end
        if not IsInChallengeMode() then return end

        -- The mouseover unit token is what Blizzard's tooltip frame resolves
        -- against, so we read progress values directly off that. We mirror
        -- BigWigs' Keystones pattern here — truthy check only, no numeric
        -- comparisons (those crash on secret values). Pass values straight
        -- through to format; BigWigs does this in the same context without
        -- issue, suggesting format tolerates secret numeric args.
        local value, percent = GetProgress("mouseover")
        if not value or not percent then return end

        local themeHex = KE:GetThemeColorHex()
        -- Inline KE minimap icon to the left of "Count:". `:0:0` auto-sizes
        -- the texture to the tooltip line's text height, matching BigWigs'
        -- progressPercentTooltipText pattern.
        tooltip:AddLine(format("|TInterface\\AddOns\\KitnEssentials\\Media\\Icon\\KitnUI:0:0|t|cff%sCount:|r |cffffffff+%d | %.2f%%|r",
            themeHex, value, percent))
        tooltip:Show()
    end)
end

---------------------------------------------------------------------------------
-- Nameplate % Overlay
-- Shows each mob's forces contribution as a floating text on its nameplate.
-- Follows BigWigs' text-pool pattern (Tools/Keystones.lua) — reusable Frame +
-- FontString objects recycled when a nameplate leaves, so we don't churn
-- frames on busy pulls. All style/position updates flow through ApplySettings
-- so the GUI can live-refresh without reload.
---------------------------------------------------------------------------------

local activeTexts = {}   -- [unitToken] = textObj
local storedTexts = {}   -- object pool (popped by Acquire)
local nameplateTicker = nil

local function CreateNameplateTextObject()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(6200)
    frame:Hide()
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    return { frame = frame, fs = fs }
end

local function ApplyNameplateStyle(obj)
    local db = WDF.db
    if not db then return end
    local fontPath = KE:GetFontPath(db.NameplateFontFace) or KE.FONT
    local size = db.NameplateFontSize or 11
    local outline = db.NameplateFontOutline or "OUTLINE"
    if outline == "NONE" then outline = "" end
    obj.fs:SetFont(fontPath, size, outline)
    local r, g, b, a = KE:GetAccentColor(db.NameplateColorMode or "theme", db.NameplateColor)
    obj.fs:SetTextColor(r, g, b, a or 1)
end

local function AttachNameplateText(obj, unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return false end
    local db = WDF.db
    -- Self-anchor stays CENTER; parent anchor is user-configurable so the text
    -- can hover above/below/beside the nameplate. X/Y are the offset from
    -- that anchor, so adjusting both sliders + dropdown gives full placement.
    obj.frame:ClearAllPoints()
    obj.frame:SetParent(plate)
    obj.frame:SetPoint("CENTER", plate, db.NameplateAnchor or "CENTER",
        db.NameplateXOffset or 25, db.NameplateYOffset or 15)
    obj.frame:Show()
    return true
end

local function AcquireNameplateText()
    local obj = table_remove(storedTexts)
    if not obj then obj = CreateNameplateTextObject() end
    ApplyNameplateStyle(obj)
    return obj
end

local function ReleaseNameplateText(unit)
    local obj = activeTexts[unit]
    if not obj then return end
    obj.frame:Hide()
    obj.frame:ClearAllPoints()
    obj.frame:SetParent(UIParent)
    activeTexts[unit] = nil
    storedTexts[#storedTexts + 1] = obj
end

local function UpdateNameplateTextFor(unit)
    if not WDF.db or not WDF.db.NameplatePercent then return end
    if not GetProgress then return end
    if not IsInChallengeMode() then
        ReleaseNameplateText(unit)
        return
    end
    if not UnitExists(unit) or UnitIsDead(unit) or not UnitCanAttack("player", unit) then
        ReleaseNameplateText(unit)
        return
    end
    if WDF.db.NameplateCombatOnly then
        if not UnitAffectingCombat(unit) then
            ReleaseNameplateText(unit)
            return
        end
        -- Hide while the player is dead/ghost. Mobs may still be in combat
        -- with the rest of the party, but the overlay is visual noise while
        -- corpse-running — re-appears within 0.5s of resurrection.
        if UnitIsDeadOrGhost("player") then
            ReleaseNameplateText(unit)
            return
        end
    end

    local _, percent = GetProgress(unit)
    if not percent then
        ReleaseNameplateText(unit)
        return
    end

    local obj = activeTexts[unit]
    if not obj then
        obj = AcquireNameplateText()
        activeTexts[unit] = obj
    end
    if not AttachNameplateText(obj, unit) then
        ReleaseNameplateText(unit)
        return
    end
    obj.fs:SetText(format("%.2f%%", percent))
end

local function UpdateAllNameplateTexts()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            UpdateNameplateTextFor(unit)
        end
    end
    -- Clean up entries whose unit token is no longer present
    for unit in pairs(activeTexts) do
        if not UnitExists(unit) then
            ReleaseNameplateText(unit)
        end
    end
end

local function ReleaseAllNameplateTexts()
    for unit in pairs(activeTexts) do
        ReleaseNameplateText(unit)
    end
end

local function RefreshAllNameplateStyle()
    for _, obj in pairs(activeTexts) do ApplyNameplateStyle(obj) end
    for _, obj in pairs(storedTexts) do ApplyNameplateStyle(obj) end
end

local function RefreshAllNameplatePositions()
    for unit, obj in pairs(activeTexts) do
        AttachNameplateText(obj, unit)
    end
end

local function StartNameplateTicker()
    if nameplateTicker then return end
    if not WDF.db or not WDF.db.NameplatePercent then return end
    if not IsInChallengeMode() then return end
    nameplateTicker = C_Timer.NewTicker(0.5, UpdateAllNameplateTexts)
end

local function StopNameplateTicker()
    if nameplateTicker then
        nameplateTicker:Cancel()
        nameplateTicker = nil
    end
end

---------------------------------------------------------------------------------
-- Death Tracking Fix (state-based dedup)
-- Dedup is tracked per-player-name: once a player's current death is recorded,
-- we don't record it again until we've seen them alive (battle-rez handles
-- correctly). UNIT_DIED fires for every mob in the pull, so we also debounce
-- the roster scan to one pass per PROCESS_DEFER seconds.
-- CLEU ships a localized class string (e.g. "Druid" not "DRUID"), so we
-- ALWAYS prefer a roster lookup over the class value passed to AddDeathDetails.
---------------------------------------------------------------------------------

local PROCESS_DEFER = 0.15 -- seconds; debounce + lets CHALLENGE_MODE_DEATH_COUNT_UPDATED fire first
-- Flip to true to trace death events in chat (hook calls, dedup clears, count sync).
local DEBUG_DEATHS = false
local deathFixApplied = false
-- Per-death time penalty in seconds. Learned from the game's own reports:
-- 5s below +12, 15s on +12 and above with Xal'atath's Guile. Stays nil until
-- we see a real (count > 0) report so we never fabricate a value.
local lastDeathPenalty = nil
-- Set while our own hook self-triggers SetDeathCount, to keep that call from
-- polluting lastDeathPenalty with a pre-game-update timeLost of 0.
local suppressLearning = false
-- Set of player names whose CURRENT death we've already recorded. An entry
-- is removed when we next see that player alive (battle-rez) so their next
-- death is recorded as a new event.
local recordedDeaths = {}
-- Debounce flag so UNIT_DIED spam collapses to one ProcessDeaths per window.
local processScheduled = false
-- 0.5s ticker that clears recordedDeaths entries for players who've since
-- revived. Without this, the "die → release → run back → resurrect → die
-- again" loop leaves the first death's name pinned in recordedDeaths, so
-- the second death is filtered out when ProcessDeaths scans (no intervening
-- UNIT_DIED event triggered a scan that saw them alive).
local aliveScanTicker = nil

-- A class token is valid if GetClassColor returns a hex value for it.
local function IsValidClassToken(class)
    if not class or class == "" then return false end
    local _, _, _, hex = GetClassColor(class)
    return hex ~= nil
end

-- Look up the class token for a player by name from the party/raid roster.
-- Returns nil if the name isn't in the current group.
local function GetClassTokenForName(name)
    if not name then return nil end
    if UnitName("player") == name then
        return select(2, UnitClass("player"))
    end
    local token = IsInRaid() and "raid" or "party"
    local size = GetNumGroupMembers()
    for i = 1, size do
        local unit = token .. i
        if UnitExists(unit) and UnitName(unit) == name then
            return select(2, UnitClass(unit))
        end
    end
    return nil
end

-- Is this named player currently alive (or not in the group)?
-- Uses UnitIsDeadOrGhost so a player who released to ghost is still treated as
-- "dead" for recordedDeaths purposes — otherwise fast-release players would be
-- cleared from the dedup set and re-added on the next scan (or never recorded
-- at all if release happens inside the PROCESS_DEFER window).
local function IsPlayerNameAlive(name)
    if not name then return true end
    if UnitName("player") == name then
        return not UnitIsDeadOrGhost("player")
    end
    local token = IsInRaid() and "raid" or "party"
    local size = GetNumGroupMembers()
    for i = 1, size do
        local unit = token .. i
        if UnitExists(unit) and UnitName(unit) == name then
            return not UnitIsDeadOrGhost(unit)
        end
    end
    return true -- not found (left group); treat as alive so entry gets cleared
end

-- Called on a 0.5s ticker during M+. Iterates recordedDeaths; if the named
-- player is now alive (resurrected or brez'd), remove them so their NEXT
-- death is recognized as new. This is the fix for "die → revive → die again
-- with no other UNIT_DIED in between" — the ProcessDeaths-time cleanup only
-- runs on UNIT_DIED events, which miss pure revival transitions.
local function CleanupAliveRecorded()
    for name in pairs(recordedDeaths) do
        if IsPlayerNameAlive(name) then
            recordedDeaths[name] = nil
            if DEBUG_DEATHS then KE:Print(format("[poll-clear] %s alive again", name)) end
        end
    end
end

local function StartAliveScanTicker()
    if aliveScanTicker then return end
    aliveScanTicker = C_Timer.NewTicker(0.5, CleanupAliveRecorded)
end

local function StopAliveScanTicker()
    if aliveScanTicker then
        aliveScanTicker:Cancel()
        aliveScanTicker = nil
    end
end

-- Scan the roster and append any dead player we haven't already recorded.
local function ProcessDeaths()
    if not WarpDeplete or not WarpDeplete.state then return end
    local timer = WarpDeplete.state.timer or 0

    -- Clear recorded-death state for any player who is alive again (BRez).
    for name in pairs(recordedDeaths) do
        if IsPlayerNameAlive(name) then
            recordedDeaths[name] = nil
            if DEBUG_DEATHS then KE:Print(format("[clear] %s (now alive)", name)) end
        end
    end

    -- Player — catch dead + ghost so fast releasers still get recorded.
    if UnitIsDeadOrGhost("player") then
        local name = UnitName("player")
        if name and not recordedDeaths[name] then
            local _, classToken = UnitClass("player")
            if classToken then
                recordedDeaths[name] = true
                if DEBUG_DEATHS then
                    KE:Print(format("[proc-add] player=%s cls=%s t=%.1f", name, classToken, timer))
                end
                WarpDeplete:AddDeathDetails(timer, name, classToken)
            end
        end
    end

    -- Party/raid
    local size = GetNumGroupMembers()
    if size > 0 then
        local token = IsInRaid() and "raid" or "party"
        for i = 1, size do
            local unit = token .. i
            if UnitExists(unit) and UnitIsDeadOrGhost(unit) then
                local name = UnitName(unit)
                if name and not recordedDeaths[name] then
                    local _, classToken = UnitClass(unit)
                    if classToken then
                        recordedDeaths[name] = true
                        if DEBUG_DEATHS then
                            KE:Print(format("[proc-add] %s=%s cls=%s t=%.1f", unit, name, classToken, timer))
                        end
                        WarpDeplete:AddDeathDetails(timer, name, classToken)
                    end
                end
            end
        end
    end
end

local function SetupDeathClassFix()
    if deathFixApplied then return end
    if not WarpDeplete then return end

    -- Hook SetDeathCount: keep header in sync with max(gameCount, listCount).
    local originalSetDeathCount = WarpDeplete.SetDeathCount
    WarpDeplete.SetDeathCount = function(self, count, timeLost) -- luacheck: ignore 122
        local rawCount, rawTimeLost = count or 0, timeLost or 0
        count = rawCount
        timeLost = rawTimeLost
        if count > 0 and not suppressLearning then
            lastDeathPenalty = timeLost / count
        end
        local listCount = #self.state.deathDetails
        if listCount > count then
            count = listCount
            if lastDeathPenalty then
                timeLost = math.floor(listCount * lastDeathPenalty + 0.5)
            end
        end
        if DEBUG_DEATHS then
            KE:Print(format("[setCount] in=(%d,%.0f) list=%d out=(%d,%.0f) pen=%s supp=%s",
                rawCount, rawTimeLost, listCount, count, timeLost,
                tostring(lastDeathPenalty), suppressLearning and "Y" or "N"))
        end
        originalSetDeathCount(self, count, timeLost)
    end

    -- Hook AddDeathDetails: always prefer roster class token over whatever
    -- value was passed in (CLEU ships a localized name like "Druid" which
    -- is not what GetClassColor expects). Mark the name as recorded so our
    -- ProcessDeaths backstop doesn't re-add the same death.
    local originalAdd = WarpDeplete.AddDeathDetails
    WarpDeplete.AddDeathDetails = function(self, time, name, class) -- luacheck: ignore 122
        local originalClass = class
        local rosterClass = GetClassTokenForName(name)
        if rosterClass then
            class = rosterClass
        elseif type(class) == "string" and not IsValidClassToken(class) then
            -- Last-ditch: uppercase it in case CLEU shipped localized form.
            local up = class:upper()
            if IsValidClassToken(up) then class = up end
        end
        if DEBUG_DEATHS then
            KE:Print(format("[add] t=%.1f name=%s orig=%s roster=%s final=%s",
                time or 0, tostring(name), tostring(originalClass),
                tostring(rosterClass), tostring(class)))
        end
        originalAdd(self, time, name, class)
        if name then
            recordedDeaths[name] = true
            -- Mirror to SavedVariables so the list survives /reload. We only
            -- persist when DeathLog has a captured mapID (set on CHALLENGE_
            -- MODE_START) — ensures we don't hoard entries from non-M+ deaths.
            local log = WDF.db and WDF.db.DeathLog
            if log and log.mapID then
                log.details[#log.details + 1] = {
                    time = time, name = name, class = class,
                }
                if DEBUG_DEATHS then
                    KE:Print(format("[persist] saved %d entries", #log.details))
                end
            end
        end

        -- Sync the header count. We want max(gameCount, listCount): the game
        -- count is authoritative (persists across /reload), the listCount is
        -- our tracked detail rows. Using only listCount breaks after reload
        -- because listCount starts at 0 while the game says e.g. 11 — feeding
        -- SetDeathCount(1) when the first new death hits would yank the
        -- display from 11 to 1. Reading GetDeathCount() here keeps the header
        -- accurate without waiting for Blizzard's next event to catch up.
        local listCount = #self.state.deathDetails
        local gameCount, gameTimeLost = 0, 0
        if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
            local c, t = C_ChallengeMode.GetDeathCount()
            if c and not issecretvalue(c) then gameCount = c end
            if t and not issecretvalue(t) then gameTimeLost = t end
        end
        local finalCount = gameCount > listCount and gameCount or listCount
        local timeLost
        if lastDeathPenalty then
            timeLost = math.floor(finalCount * lastDeathPenalty + 0.5)
        else
            timeLost = gameTimeLost
        end
        suppressLearning = true
        self:SetDeathCount(finalCount, timeLost)
        suppressLearning = false
    end

    -- UNIT_DIED fires for every mob death in the pull. Debounce into a
    -- single ProcessDeaths call per window so we don't re-scan the roster
    -- hundreds of times per pull. The PROCESS_DEFER delay also gives the
    -- game time to fire CHALLENGE_MODE_DEATH_COUNT_UPDATED first so
    -- lastDeathPenalty is learned before our scan runs.
    local deathFrame = CreateFrame("Frame")
    deathFrame:RegisterEvent("UNIT_DIED")
    deathFrame:SetScript("OnEvent", function()
        if not WarpDeplete or not WarpDeplete.state then return end
        if processScheduled then return end
        processScheduled = true
        C_Timer.After(PROCESS_DEFER, function()
            processScheduled = false
            ProcessDeaths()
        end)
    end)

    deathFixApplied = true
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------

-- Clear the persisted death log — called from CHALLENGE_MODE_COMPLETED/RESET.
local function ClearDeathLog()
    local log = WDF.db and WDF.db.DeathLog
    if not log then return end
    log.mapID = nil
    log.keyLevel = nil
    if log.details then wipe(log.details) end
    wipe(recordedDeaths)
    if DEBUG_DEATHS then KE:Print("[persist] log cleared") end
end

-- Read current M+ identity. Guards against secret values returned by the
-- keystone API (observed in other 12.0.5 scenario reads).
local function GetMPlusIdentity()
    local mapID = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
        and C_ChallengeMode.GetActiveChallengeMapID()
    if mapID and issecretvalue(mapID) then mapID = nil end
    local level
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        level = C_ChallengeMode.GetActiveKeystoneInfo()
        if level and issecretvalue(level) then level = nil end
    end
    return mapID, level
end

function WDF:CHALLENGE_MODE_START()
    -- Fresh run begins — capture identity, wipe any stale saved entries.
    local mapID, level = GetMPlusIdentity()
    self.db.DeathLog.mapID = mapID
    self.db.DeathLog.keyLevel = level
    wipe(self.db.DeathLog.details)
    wipe(recordedDeaths)
    if DEBUG_DEATHS then
        KE:Print(format("[start] mapID=%s level=%s", tostring(mapID), tostring(level)))
    end

    StartAliveScanTicker()
    if self.db.NameplatePercent then
        StartNameplateTicker()
    end
end

function WDF:CHALLENGE_MODE_COMPLETED()
    ClearDeathLog()
    StopAliveScanTicker()
    StopNameplateTicker()
    ReleaseAllNameplateTexts()
end

function WDF:CHALLENGE_MODE_RESET()
    ClearDeathLog()
    StopAliveScanTicker()
    StopNameplateTicker()
    ReleaseAllNameplateTexts()
end

-- Called after a /reload: if the saved log matches the current M+ run, restore
-- the entries into WarpDeplete's runtime state and sync the header count.
-- If mapID or keyLevel differ, the log is stale → wipe.
function WDF:RestoreDeathLog()
    if not WarpDeplete or not WarpDeplete.state then return end
    if not IsInChallengeMode() then return end

    local log = self.db and self.db.DeathLog
    if not log then
        if DEBUG_DEATHS then KE:Print("[restore] DB missing") end
        return
    end

    local currentMap, currentLevel = GetMPlusIdentity()

    -- If mapID was never captured for this run (typically: addon updated
    -- mid-run, so CHALLENGE_MODE_START fired with the older non-persisting
    -- code), capture it now. Subsequent deaths will persist correctly even
    -- without a fresh START event this session.
    if not log.mapID and currentMap then
        log.mapID = currentMap
        log.keyLevel = currentLevel
        if not log.details then log.details = {} end
        if DEBUG_DEATHS then
            KE:Print(format("[restore] captured mapID=%s level=%s (was unset)",
                tostring(currentMap), tostring(currentLevel)))
        end
        return  -- nothing pre-saved to rehydrate; persistence active going forward
    end

    if not log.details or #log.details == 0 then
        if DEBUG_DEATHS then KE:Print("[restore] no saved entries to rehydrate") end
        return
    end

    if log.mapID ~= currentMap or log.keyLevel ~= currentLevel then
        if DEBUG_DEATHS then
            KE:Print(format("[restore] stale (saved=%s/%s vs now=%s/%s) — wiping",
                tostring(log.mapID), tostring(log.keyLevel),
                tostring(currentMap), tostring(currentLevel)))
        end
        ClearDeathLog()
        -- Capture the new run's identity so future deaths persist.
        log.mapID = currentMap
        log.keyLevel = currentLevel
        return
    end

    -- Same run — rehydrate WarpDeplete.state.deathDetails so the tooltip list
    -- isn't empty after reload. Also populate recordedDeaths so ProcessDeaths
    -- doesn't re-add the same entries.
    for _, entry in ipairs(log.details) do
        if entry.time and entry.name and entry.class then
            -- luacheck: ignore 122 (writing to WarpDeplete-owned state table)
            WarpDeplete.state.deathDetails[#WarpDeplete.state.deathDetails + 1] = {
                time = entry.time, name = entry.name, class = entry.class,
            }
            recordedDeaths[entry.name] = true
        end
    end

    -- Sync header. suppressLearning prevents our SetDeathCount hook from
    -- re-deriving lastDeathPenalty during this restore pump.
    local gameCount, gameTimeLost = 0, 0
    if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        local c, t = C_ChallengeMode.GetDeathCount()
        gameCount = (c and not issecretvalue(c)) and c or 0
        gameTimeLost = (t and not issecretvalue(t)) and t or 0
    end
    suppressLearning = true
    WarpDeplete:SetDeathCount(gameCount, gameTimeLost)
    suppressLearning = false

    if DEBUG_DEATHS then
        KE:Print(format("[restore] rehydrated %d entries (gameCount=%d)",
            #log.details, gameCount))
    end
end

function WDF:NAME_PLATE_UNIT_ADDED(_, unit)
    UpdateNameplateTextFor(unit)
end

function WDF:NAME_PLATE_UNIT_REMOVED(_, unit)
    ReleaseNameplateText(unit)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------

function WDF:ApplySettings()
    -- Tooltip conflict: WarpDeplete 5.1.0 ships its own "Count:" tooltip line
    -- gated by showTooltipCount + MDT. Bind our toggle as the master:
    --   our Tooltip ON  → force WD's off (only ours shows)
    --   our Tooltip OFF → force WD's on  (WD's shows if MDT is loaded)
    -- Users get exactly one "Count:" line regardless of WD's own setting.
    if WarpDeplete and WarpDeplete.db and WarpDeplete.db.profile then
        -- luacheck: ignore 122 (writing to WarpDeplete-owned config table)
        WarpDeplete.db.profile.showTooltipCount = not self.db.Tooltip
    end

    -- Nameplate % subsystem: re-wire events/ticker on toggle, and live-refresh
    -- style/position on font/color/offset changes so the GUI reflects instantly.
    if self.db.NameplatePercent then
        self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        if IsInChallengeMode() then
            StartNameplateTicker()
            UpdateAllNameplateTexts()
        end
    else
        self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
        self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
        StopNameplateTicker()
        ReleaseAllNameplateTexts()
    end
    RefreshAllNameplateStyle()
    RefreshAllNameplatePositions()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function WDF:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function WDF:OnEnable()
    -- Require WarpDeplete
    if not WarpDeplete then
        KE:Print("WarpDeplete+: WarpDeplete addon not found. Module disabled.")
        self:SetEnabledState(false)
        return
    end

    if not self.db.Enabled then return end

    if not HasProgressAPI then
        KE:Print("WarpDeplete+: C_ScenarioInfo.GetUnitCriteriaProgressValues unavailable on this client; pull forces + count tooltip disabled.")
    end

    -- Register events
    self:RegisterEvent("CHALLENGE_MODE_START")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    self:RegisterEvent("CHALLENGE_MODE_RESET")

    -- Tooltip hook
    SetupTooltip()

    -- Fix WarpDeplete death class colors (uses className instead of classFilename)
    SetupDeathClassFix()

    -- Nameplate % subsystem — wires events + seeds existing nameplates if in M+
    self:ApplySettings()

    -- Post-reload death log rehydration. Deferred so WarpDeplete has time to
    -- finish its own init (state tables populated, CHALLENGE_MODE_DEATH_COUNT_
    -- UPDATED fired) before we pump entries back into its state.
    C_Timer.After(1.5, function()
        self:RestoreDeathLog()
        -- Start the alive-cleanup ticker if we're in an active M+ (covers
        -- /reload inside a run — CHALLENGE_MODE_START won't fire again).
        if IsInChallengeMode() then
            StartAliveScanTicker()
        end
    end)
end

function WDF:OnDisable()
    self:UnregisterAllEvents()
    StopAliveScanTicker()
    StopNameplateTicker()
    ReleaseAllNameplateTexts()
end
