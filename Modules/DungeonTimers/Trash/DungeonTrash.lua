-- ╔══════════════════════════════════════════════════════════╗
-- ║  DungeonTrash.lua                                        ║
-- ║  Module: Dungeon Trash Tracker                           ║
-- ║                                                          ║
-- ║  Nameplate-driven trash-cast tracker. Owns the event     ║
-- ║  loop + per-nameplate runtime state; delegates every     ║
-- ║  decision to KE.TrashInference (pure). Detection is      ║
-- ║  behavioral inference because 12.0 makes a nameplate's   ║
-- ║  npcID (UnitGUID) and a cast's spellID secret — see      ║
-- ║  dev/docs/dungeon-trash-engine-port-spec.md.             ║
-- ║                                                          ║
-- ║  SECRET-SAFETY (do not regress): the engine NEVER reads  ║
-- ║  a spellID/GUID/cast-time/aura-value for identity. Mobs  ║
-- ║  are fingerprinted from level/sex/power/class/aura-COUNT ║
-- ║  (all pcall-guarded); casts from MEASURED GetTime        ║
-- ║  durations + boolean fingerprints.                       ║
-- ║                                                          ║
-- ║  Output (central alerts, on-plate icons) lives in        ║
-- ║  TrashOutput / TrashNameplate, attached at guarded       ║
-- ║  seams (see FinishCast).                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DungeonTrash: AceModule, AceEvent-3.0, AceTimer-3.0
local DTrash = KitnEssentials:NewModule("DungeonTrash", "AceEvent-3.0", "AceTimer-3.0")

local TI = KE.TrashInference
local TAD = KE.TrashAuraDelta  -- Trash.xml: the aura-delta sampler loads first

local GetTime = GetTime
local time = time
local IsInInstance = IsInInstance
local IsEncounterInProgress = IsEncounterInProgress
local GetInstanceInfo = GetInstanceInfo
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitLevel = UnitLevel
local UnitSex = UnitSex
local UnitPowerType = UnitPowerType
local UnitClassification = UnitClassification
local UnitShouldDisplaySpellTargetName = UnitShouldDisplaySpellTargetName
local UnitAffectingCombat = UnitAffectingCombat
local UnitCanAttack = UnitCanAttack
local UnitIsDead = UnitIsDead
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
local C_Timer = C_Timer
local C_Map = C_Map
local C_Scenario = C_Scenario
local C_ScenarioInfo = C_ScenarioInfo
local GetMinimapZoneText = GetMinimapZoneText
local issecretvalue = issecretvalue
local pcall = pcall
local tonumber = tonumber
local type = type
local string_format = string.format
local wipe = wipe

-- Flip to true, /reload, pull a trash pack, read the log. Reverts to false
-- after diagnosis but the instrumentation stays (KE debug-flag convention).
local DEBUG_DTRASH = false

local SNAPSHOT_DELAY = 0.10       -- unit data unstable on the add frame
local SNAPSHOT_RETRIES = { 0.25, 0.50 }  -- bounded re-reads after a nil identity
-- Fingerprint sample after cast start; also the ± half-width of the target
-- switch/clear windows and the success buff-count delay. One value serves all
-- four on purpose.
local TARGET_SAMPLE_DELAY = 0.10
-- Target-event rings keep only the last second, front-trimmed on append.
local TARGET_EVENT_TRIM = 1.0
local MAX_NAMEPLATES = 40
-- A channel flagged channelRefreshOnInterruptible re-emits CHANNEL_START when
-- its castbar refreshes on becoming interruptible; a start within this window
-- of the INTERRUPTIBLE event (same cast seq, new castBarID) is a CONTINUATION
-- of the running channel, not a new one.
local CHANNEL_REFRESH_WINDOW = 1.00
-- Cast→channel transition proof: castbar IDs are monotonic per unit, so the
-- channel phase of a two-phase spell re-emits CHANNEL_START with the finished
-- cast's castBarID +1. The pairing is accepted only this soon after the cast
-- stop, and that bound is deliberate: leaving the pending lifetime unbounded
-- on unresolved mobs lets a stale pairing poison sawCastIntoChannel, which is
-- a Layer1 pruning input here. The same window holds an ambiguous one-phase
-- credit (see FinishCast).
local TRANSITION_PAIR_WINDOW = 0.25
-- Scenario criteria flip `completed` slightly after the boss actually dies;
-- coalesce the burst of BOSS_KILL/SCENARIO_* events into one re-read.
local SCENARIO_REFRESH_DEBOUNCE = 1.0

-- Boss encounters where the trash engine mislabels the boss and/or its adds:
-- their nameplates collide with a curated trash mob's static fingerprint (12.0
-- makes npcID/spellID secret, so a boss can't be told from trash at the plate),
-- the tracker resolves them to that trash mob and shows its spells. There is no
-- way to exclude the units at the fingerprint layer, so trash OUTPUT is
-- blacked out for the encounter's duration while fingerprinting keeps running
-- underneath. Keyed by the
-- ENCOUNTER_START encounterID.
-- This list is the LAST resort, not the boss filter: boss-tier plates are
-- rejected at the identity layer by ScoreTraitRow's "level-above" rule
-- (bosses plate one level above trash), which keeps real trash pulled into a
-- boss fight fully tracked. An entry here blacks out ALL trash output for the
-- encounter, so it is only for collisions the level rule cannot catch —
-- encounter units AT trash level — and only with the mislabel verified
-- in-game (the Magisters' Terrace boss mislabels were level-filter gaps, not
-- blocklist material — fixed at the identity layer instead).
--   [2001] = Ick & Krick (Pit of Saron): boss Ick → "Glacieth", add Shadow of
--            Krick → "Dreadpulse Lich" (both mislabels verified in-game).
local DISABLED_BOSS_ENCOUNTER_IDS = {
    [2001] = true,
}

DTrash.tracked = {}   -- [unit] = runtime table
DTrash.monitoring = false
DTrash.currentMapID = nil
DTrash.inBossEncounter = false
DTrash.bossEncounterID = nil
-- Layer1 runtime context (placement stage gate + Academy forces routing);
-- refreshed by the scenario/zone events while monitoring, nil'd on stop.
DTrash.bossProgressIndex = nil
DTrash.subZoneMapID = nil
DTrash.zoneText = nil
DTrash.forcesPercent = nil
DTrash.forcesValid = false
-- Aura-delta sampler availability for the current monitor session (set once
-- per StartMonitor; see the gate there). Threads into TI ownership checks as
-- auraDeltaLive: with the sampler dark, castStartAuraDelta-curating spells
-- keep the success-path anchor instead of a lenient nil-fingerprint advance.
DTrash._auraDeltaLive = false

local function dprint(msg)
    if DEBUG_DTRASH then KE:Print("[DTrash] " .. tostring(msg)) end
end
-- Exported so sibling files (TrashCache.lua) ride the same DEBUG_DTRASH flag.
DTrash._dprint = dprint

-- ── Secret-safe helpers ────────────────────────────────────────────────────

-- pcall a boolean-returning API; a secret or errored return degrades to nil
-- (Layer2 treats nil fingerprints as "not sampled", never a false match).
local function safeBool(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    -- issecretvalue as first contact with the return, before the nil compare
    -- (the guard call is stricter than a plain comparison in tainted code).
    if issecretvalue and issecretvalue(v) then return nil end
    if v == nil then return nil end
    return v and true or false
end

-- Identity snapshot (the `_s` reader). The whole read is pcall-wrapped and any
-- secret field bails the entire snapshot to nil — a mob we can't fingerprint
-- is simply left unresolved rather than crashing on a later comparison.
local function readIdentity(unit, inMythicPlus)
    if not (unit and UnitExists(unit)) then return nil end
    local ok, snap = pcall(function()
        local _, _, classID = UnitClass(unit)
        local level = UnitLevel(unit)
        local sex = UnitSex(unit)
        local power = UnitPowerType(unit)
        local classif = UnitClassification(unit)
        if issecretvalue and (issecretvalue(level) or issecretvalue(sex) or issecretvalue(power)
            or issecretvalue(classID) or issecretvalue(classif)) then
            return nil
        end
        -- aura COUNT only — the aura table is truthy even when its fields are
        -- secret, and we never read a field, so counting stays secret-safe.
        local n = 0
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local i = 1
            while C_UnitAuras.GetAuraDataByIndex(unit, i) do n = n + 1; i = i + 1 end
        end
        if inMythicPlus and n > 0 then n = n - 1 end  -- subtract the affix aura
        level = tonumber(level)
        if level and level <= 0 then level = nil end
        return {
            level = level,
            sex = tonumber(sex),
            power = tonumber(power),
            classID = tonumber(classID),
            buffCount = n,
            unitClassification = classif,
        }
    end)
    if ok then return snap end
    return nil
end

local function normalizeNameplate(unit)
    if type(unit) == "string" and unit:find("^nameplate%d") then return unit end
    return nil
end

-- Hostile-plate intake gate, checked on EVERY intake path: friendly players,
-- pets, guardians and corpses must never enter the fingerprint machinery.
-- Fails OPEN — a secret/unreadable answer keeps the plate, so a real hostile is
-- never dropped on a bad read.
local function isHostilePlate(unit)
    if safeBool(UnitCanAttack, "player", unit) == false then return false end
    if safeBool(UnitIsDead, unit) == true then return false end
    return true
end

-- ── Dungeon / M+ context ───────────────────────────────────────────────────

function DTrash:InMythicPlus()
    local _, _, diffID = GetInstanceInfo()
    return diffID == 8
end

-- Resolves the current dungeon's KE.TrashData key from the instance mapID
-- (GetInstanceInfo's 8th return, which is what the data is keyed by).
-- Caches currentMapID for downstream data lookups.
function DTrash:CurrentDungeonKey()
    local mapID = select(8, GetInstanceInfo())
    self.currentMapID = mapID
    local d = mapID and KE.TrashData and KE.TrashData[mapID]
    return d and d.dungeonKey
end

function DTrash:MobData(npcID)
    local d = self.currentMapID and KE.TrashData and KE.TrashData[self.currentMapID]
    return d and d.mobs and d.mobs[npcID]
end

-- Cached C_Map.GetAreaInfo lookups for the placement gate's areaID tier. A
-- stored `false` means looked up and nameless, and is never re-queried. Passed
-- into TI as a closure so the inference stays pure and busted can stub it.
local areaNameByID = {}
local function areaNameLookup(areaID)
    local hit = areaNameByID[areaID]
    if hit ~= nil then return hit or nil end
    local ok, name = pcall(C_Map and C_Map.GetAreaInfo, areaID)
    if ok and type(name) == "string" then
        -- Same trim + collapse RefreshZoneState applies to the minimap text:
        -- the placement gate compares the two with plain equality, so both
        -- sides must go through the identical normalizer.
        name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    end
    name = (ok and type(name) == "string" and name ~= "") and name or false
    areaNameByID[areaID] = name
    return name or nil
end

-- Sub-zone context for the placement gate's map-token tier: the player's best
-- uiMapID plus the normalized minimap zone text. Both are plain in 12.0 --
-- GetBestMapForUnit is documented player/party-only and unmarked, and
-- GetMinimapZoneText is a plain cstring.
function DTrash:RefreshZoneState()
    if not self.monitoring then return end
    local ok, mapID = pcall(C_Map and C_Map.GetBestMapForUnit, "player")
    self.subZoneMapID = (ok and tonumber(mapID)) or nil
    local zoneText
    if GetMinimapZoneText then
        local okZ, text = pcall(GetMinimapZoneText)
        if okZ and type(text) == "string" then
            -- Trim + collapse inner whitespace so the compare against
            -- C_Map.GetAreaInfo names is stable.
            zoneText = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
            if zoneText == "" then zoneText = nil end
        end
    end
    self.zoneText = zoneText
end

-- Boss-progress index + M+ enemy-forces % from the scenario criteria list —
-- the placement stage gate and the Academy forces routing. Same aggregate
-- reads the shipped M+ Timer proves in-game (contract DO-NOT-GUARD set:
-- GetStepInfo's count and GetCriteriaInfo completed/isWeightedProgress/
-- quantityString/totalQuantity are plain); pcall-wrapped per KE convention.
-- A boss criterion is non-weighted with totalQuantity ≤ 1 -- a locale-
-- independent test, which also excludes count objectives (PoS "Quarry Camps",
-- totalQuantity 6). bossProgressIndex = killed + 1 ("the pack before boss N");
-- nil outside a scenario, where the placement gate then fails open.
function DTrash:RefreshScenarioState(forcesOnly)
    if not self.monitoring then return end
    local numCriteria = 0
    local getCriteria = C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo
    if getCriteria and C_Scenario and C_Scenario.GetStepInfo then
        local ok, n = pcall(function() return select(3, C_Scenario.GetStepInfo()) end)
        numCriteria = (ok and tonumber(n)) or 0
    end
    local bossTotal, bossKilled = 0, 0
    local forcesPercent
    for i = 1, numCriteria do
        local okC, info = pcall(getCriteria, i)
        if okC and type(info) == "table" then
            if info.isWeightedProgress then
                if forcesPercent == nil then
                    -- quantityString carries the absolute count with a stray
                    -- '%' (locale-safe parse — the M+ Timer's proven pattern);
                    -- percent = count / totalQuantity.
                    local current
                    local qs = info.quantityString
                    if type(qs) == "string" and qs ~= "" then
                        local normalized = qs:gsub("%%", "")
                        if normalized:find(",") and not normalized:find("%.") then
                            normalized = normalized:gsub(",", ".")
                        end
                        current = tonumber(normalized) or 0
                    else
                        current = tonumber(info.quantity) or 0
                    end
                    local total = tonumber(info.totalQuantity) or 0
                    if total > 0 then forcesPercent = (current / total) * 100 end
                end
            elseif (tonumber(info.totalQuantity) or 0) <= 1 then
                bossTotal = bossTotal + 1
                if info.completed then bossKilled = bossKilled + 1 end
            end
        end
    end
    -- forcesOnly = the synchronous scenario-edge pass (reference split: only
    -- the forces refresher runs at the event edge). Boss criteria complete
    -- LATE and a mid-burst read can transiently blank them; the index is a
    -- placement-gate input whose unknown state fails OPEN, so it is written
    -- only by the settled debounced re-read.
    if not forcesOnly then
        self.bossProgressIndex = (bossTotal > 0) and (bossKilled + 1) or nil
    end
    -- forcesPercent stays nil when unknown — NEVER 0: a nil percent makes
    -- the Academy routing skip its prune (the reference's forces-invalid branch; Layer2
    -- disambiguates), while a literal 0 would route to the <20% npc.
    self.forcesValid = (forcesPercent ~= nil) and self:InMythicPlus() or false
    self.forcesPercent = self.forcesValid and forcesPercent or nil
    if DEBUG_DTRASH then
        local sig = tostring(self.bossProgressIndex) .. "|" .. tostring(self.forcesPercent)
        if self._ctxDbg ~= sig then
            self._ctxDbg = sig
            dprint(string_format("context: bossIndex=%s forces=%s subZone=%s (%s)",
                tostring(self.bossProgressIndex),
                self.forcesPercent and string_format("%.1f%%", self.forcesPercent) or "nil",
                tostring(self.subZoneMapID), tostring(self.zoneText)))
        end
    end
end

-- Scenario edge: refresh FORCES synchronously so forcesPercent is CURRENT at
-- the next resolve (both references refresh forces immediately on every
-- scenario event — the Academy/Skyreach routing reads it at resolve time),
-- while bossProgressIndex is written only by the deferred re-read: boss
-- criteria complete slightly AFTER the kill (single-pending debounce,
-- reference-matching 1.0s — the reference's exact split). The tick re-reads
-- zone state too: a multi-floor transition that emits no ZONE_CHANGED* event
-- (elevators/teleporters) would otherwise leave a stale-but-known sub-zone
-- failing the placement gate closed (the reference refreshes zone context on
-- the same scenario events).
function DTrash:OnScenarioCriteriaChanged()
    if not self.monitoring then return end
    self:RefreshScenarioState(true)
    if self._scenarioRefreshPending then return end
    self._scenarioRefreshPending = true
    C_Timer.After(SCENARIO_REFRESH_DEBOUNCE, function()
        self._scenarioRefreshPending = false
        self:RefreshScenarioState()
        self:RefreshZoneState()
    end)
end

function DTrash:OnZoneChanged()
    self:RefreshZoneState()
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────

function DTrash:OnInitialize()
    -- Derive each trait's hasChannelSpell/hasCastSpell from its curated spells
    -- before any resolution runs: the extractor mis-flags cast-into-channel
    -- spells (hasChannelSpell=false), which makes the Layer1 channel gate prune
    -- the correct mob the moment it channels (10 mobs across 6 dungeons). Data is
    -- parsed before OnInitialize, so KE.TrashData/TrashTraits/TrashInference all
    -- exist here; the file-local TI is not bound until OnEnable, so call through
    -- KE.TrashInference.
    if KE.TrashInference and KE.TrashInference.ReconcileTraitCapabilities then
        KE.TrashInference.ReconcileTraitCapabilities(KE.TrashData, KE.TrashTraits)
    end
    self:UpdateDB()
    self:SetEnabledState(false)  -- central KE system enables per self.db.Enabled
end

-- On-demand diagnostic dump (/kes trash). Snapshots what the tracker currently
-- believes — dungeon resolution, each tracked plate's resolved mob (or candidate
-- count), the behaviour flags it has seen, and its live predictions — so an
-- in-game validation run can be pasted back in one shot instead of scrolling the
-- combat log. Reads only module runtime state + curated data (no secret values).
function DTrash:DumpState()
    local now = GetTime()
    KE:Print("|cffFF008C[DTrash]|r state dump:")
    KE:Print(string_format("  monitoring=%s  mapID=%s  dungeon=%s",
        tostring(self.monitoring), tostring(self.currentMapID),
        tostring(self:CurrentDungeonKey())))

    local dungeon = self.currentMapID and KE.TrashData and KE.TrashData[self.currentMapID]
    if dungeon then
        local mobCount = 0
        for _ in pairs(dungeon.mobs or {}) do mobCount = mobCount + 1 end
        KE:Print(string_format("  curated: %s (%d mobs)", tostring(dungeon.name), mobCount))
    else
        KE:Print("  curated: none for this map")
    end

    -- Target the mob you're diagnosing, then /kes trash — this prints its raw
    -- identity (level/sex/power/classID/buffCount/classification) so it can be
    -- compared field-by-field against the curated trait fingerprint.
    if UnitExists("target") then
        local to = readIdentity("target", self:InMythicPlus())
        KE:Print(to and string_format("  TARGET id: L%s s%s p%s c%s b%s %s",
            tostring(to.level), tostring(to.sex), tostring(to.power),
            tostring(to.classID), tostring(to.buffCount), tostring(to.unitClassification))
            or "  TARGET id: unreadable (secret?)")
    end

    local n = 0
    for unit, rt in pairs(self.tracked) do
        n = n + 1
        local who
        if rt.matchedNPCID then
            local mob = self:MobData(rt.matchedNPCID)
            who = string_format("%s (%d)", (mob and mob.name) or "?", rt.matchedNPCID)
        elseif rt.candidates then
            who = string_format("%d candidate(s)", #rt.candidates)
        else
            who = "unresolved"
        end
        local flags = {}
        if rt.sawCastStart then flags[#flags + 1] = "cast" end
        if rt.sawChannelStart then flags[#flags + 1] = "channel" end
        if rt.sawInterrupted then flags[#flags + 1] = "interrupt" end
        if rt.sawCastIntoChannel then flags[#flags + 1] = "cast>channel" end
        local o = rt.obs
        local idstr = o and string_format("L%s s%s p%s c%s b%s %s",
            tostring(o.level), tostring(o.sex), tostring(o.power),
            tostring(o.classID), tostring(o.buffCount), tostring(o.unitClassification)) or "no-id"
        KE:Print(string_format("  %s: %s <%s> [%s]", tostring(unit), who, idstr, table.concat(flags, ",")))
        if rt.predictions and next(rt.predictions) then
            local mob = rt.matchedNPCID and self:MobData(rt.matchedNPCID)
            for spellID, pred in pairs(rt.predictions) do
                local sp = mob and mob.spells and mob.spells[spellID]
                KE:Print(string_format("      %s (%d) -> next in %.1fs",
                    (sp and sp.name) or "spell", spellID, (pred.nextStart or now) - now))
            end
        end
    end
    if n == 0 then KE:Print("  no tracked nameplates") end

    -- Central alert stack: what's ACTUALLY on screen right now, in stack order,
    -- with each frame's real screen position — so a "bars jumping/overlapping"
    -- report is read from ground truth, not guessed from a screenshot. Same L =
    -- vertically stacked; differing L across one mode = scattered (a bug). Bar
    -- and text group L/T reveal whether the two stacks overlap.
    local function groupInfo(g, gname)
        if not g then KE:Print("  " .. gname .. ": nil"); return end
        KE:Print(string_format("  %s @ L=%.0f T=%.0f shown=%s posSig=%s",
            gname, g:GetLeft() or 0, g:GetTop() or 0, tostring(g:IsShown()), tostring(g._posSig)))
    end
    groupInfo(self._barGroup, "barGroup")
    groupInfo(self._textGroup, "textGroup")
    local ordered = {}
    for key, f in pairs(self.alerts or {}) do ordered[#ordered + 1] = { key = key, f = f } end
    table.sort(ordered, function(a, b) return (a.f.sortIndex or 0) < (b.f.sortIndex or 0) end)
    KE:Print(string_format("  %d active alert(s) (stack order):", #ordered))
    for _, a in ipairs(ordered) do
        local f = a.f
        KE:Print(string_format("    [%s] sort=%s shown=%s L=%.0f T=%.0f  %s",
            tostring(f._poolKey), tostring(f.sortIndex), tostring(f:IsShown()),
            f:GetLeft() or 0, f:GetTop() or 0, a.key))
    end
end

function DTrash:UpdateDB()
    if not (KE.db and KE.db.profile) then return end
    if not KE.db.profile.DungeonTrash and KE.FillProfileDefaults then
        KE:FillProfileDefaults()
    end
    self.db = KE.db.profile.DungeonTrash
end

function DTrash:OnEnable()
    self:UpdateDB()
    TI = TI or KE.TrashInference
    TAD = TAD or KE.TrashAuraDelta
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "EvaluateGate")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "EvaluateGate")
    -- Lindormi's Guidance detection rides roster/role churn too (the
    -- reference registers these two alongside PLAYER_ENTERING_WORLD).
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterChanged")
    self:RegisterEvent("PLAYER_ROLES_ASSIGNED", "OnRosterChanged")
    self:EvaluateGate()
end

function DTrash:OnDisable()
    self:StopMonitor()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    self:UnregisterEvent("GROUP_ROSTER_UPDATE")
    self:UnregisterEvent("PLAYER_ROLES_ASSIGNED")
end

-- Only run inside 5-man party instances — the event stream is dormant
-- elsewhere, so the whole engine detaches outside dungeons (CPU gate).
function DTrash:EvaluateGate()
    -- Guidance check rides every world-enter and zone edge, 5s after settle.
    self:ScheduleGuidanceCheck()
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "party" then
        self:StartMonitor()
        -- ZONE_CHANGED_NEW_AREA lands here while already monitoring (big
        -- floor transitions) — keep the placement-gate context current.
        self:RefreshZoneState()
    else
        self:StopMonitor()
    end
end

local CAST_EVENTS = {
    NAME_PLATE_UNIT_ADDED = "OnNameplateAdded",
    NAME_PLATE_UNIT_REMOVED = "OnNameplateRemoved",
    UNIT_SPELLCAST_START = "OnCastStart",
    UNIT_SPELLCAST_CHANNEL_START = "OnChannelStart",
    UNIT_SPELLCAST_STOP = "OnCastStop",
    UNIT_SPELLCAST_CHANNEL_STOP = "OnChannelStop",
    UNIT_SPELLCAST_INTERRUPTED = "OnCastInterrupted",
    -- Cast aborted without succeeding or being kicked (target died / LoS /
    -- caster CC'd): interrupt-shaped lifecycle evidence, castBarID-gated.
    -- See OnCastFailed.
    UNIT_SPELLCAST_FAILED = "OnCastFailed",
    UNIT_SPELLCAST_FAILED_QUIET = "OnCastFailed",
    -- Marks a running channel's castbar-refresh window so the re-emitted
    -- CHANNEL_START is treated as a continuation, not a new measurement
    -- (channelRefreshOnInterruptible spells — see OnCastInterruptible).
    UNIT_SPELLCAST_INTERRUPTIBLE = "OnCastInterruptible",
    -- Boss-encounter output blackout (see DISABLED_BOSS_ENCOUNTER_IDS): scoped
    -- to monitoring so it only fires inside a tracked dungeon.
    ENCOUNTER_START = "OnEncounterStart",
    ENCOUNTER_END = "OnEncounterEnd",
    -- Layer1 runtime context: scenario criteria drive bossProgressIndex +
    -- forcesPercent (debounced re-read — criteria complete slightly after the
    -- kill); zone events drive the sub-zone pair for the placement gate.
    BOSS_KILL = "OnScenarioCriteriaChanged",
    SCENARIO_UPDATE = "OnScenarioCriteriaChanged",
    SCENARIO_CRITERIA_UPDATE = "OnScenarioCriteriaChanged",
    CRITERIA_UPDATE = "OnScenarioCriteriaChanged",
    ZONE_CHANGED = "OnZoneChanged",
    ZONE_CHANGED_INDOORS = "OnZoneChanged",
    -- Target switch/clear rings for the cast-start fingerprints
    -- (castStartChangeTarget / targetClearOnCastStart) — see OnUnitTarget.
    UNIT_TARGET = "OnUnitTarget",
    -- TrashCache feeds (TrashCache.lua): death marks block flicker-caching a
    -- corpse; UNIT_FLAGS stamps the fresh-combat guard's first-combat moment.
    UNIT_HEALTH = "OnUnitHealth",
    UNIT_FLAGS = "OnUnitFlags",
    -- Player combat edges: all-plate engagement/resolution sweep — see
    -- OnPlayerCombatChanged.
    PLAYER_REGEN_DISABLED = "OnPlayerCombatChanged",
    PLAYER_REGEN_ENABLED = "OnPlayerCombatChanged",
}

function DTrash:StartMonitor()
    if self.monitoring then return end
    self.monitoring = true
    for event, handler in pairs(CAST_EVENTS) do
        self:RegisterEvent(event, handler)
    end
    -- Aura-delta sampler (castStartAuraDelta): watches HARMFUL auras landing
    -- on the PARTY (player+party1-4) — friendly units, never the plate — so
    -- it needs readable group auras: C_Secrets.ShouldAurasBeSecret() ==
    -- false, the same gate the Guidance check runs on (proven readable in
    -- party dungeons in-game). When live, UNIT_AURA feeds the ring —
    -- registered HERE, outside CAST_EVENTS, so the hot event stays fully
    -- detached whenever the sampler can't run — and castStartAuraDelta-
    -- curating spells become start-advance-owned. When dark, everything
    -- degrades to the success-path anchor via the auraDeltaLive ownership
    -- gate (TI.IsStartAdvanceOwned).
    self._auraDeltaLive = false
    if TAD and C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function"
        and C_UnitAuras and type(C_UnitAuras.GetDebuffDataByIndex) == "function" then
        local okS, secretAuras = pcall(C_Secrets.ShouldAurasBeSecret)
        if okS and secretAuras == false then
            self._auraDeltaLive = true
            TAD.SetEnabled(true)
            self:RegisterEvent("UNIT_AURA", "OnUnitAura")
        end
    end
    -- Reload/login recovery: ENCOUNTER_START does not replay after a /reload,
    -- so a monitor starting mid-encounter would fail OPEN on a blocklisted
    -- fight — the exact Ick & Krick case the blackout exists for. Mirror the
    -- reference: OnEncounterStart caches the id in SavedVariables; adopt it
    -- here only when a live query confirms an encounter is actually running
    -- (IsEncounterInProgress — same API Automation.lua relies on) and the
    -- cache is fresh enough to be this fight.
    local last = self.db and self.db.LastEncounter
    if last and last.id and IsEncounterInProgress and IsEncounterInProgress()
        and (time() - (tonumber(last.at) or 0)) < 900 then
        self.inBossEncounter = true
        self.bossEncounterID = tonumber(last.id)
        dprint("monitor resumed mid-encounter id=" .. tostring(self.bossEncounterID)
            .. (self:IsBossOutputSuppressed() and " → trash output suppressed" or ""))
    end
    -- Seed the Layer1 context immediately — scenario criteria and the player
    -- map are live-queryable, so this alone is the complete /reload recovery
    -- for the placement gate + forces routing (unlike the encounter blackout,
    -- which needed the SavedVariables cache above).
    self:RefreshZoneState()
    self:RefreshScenarioState()
    -- Adopt plates already up when we entered.
    for i = 1, MAX_NAMEPLATES do
        local u = "nameplate" .. i
        if UnitExists(u) then self:OnNameplateAdded(nil, u) end
    end
    dprint("monitor started; dungeon=" .. tostring(self:CurrentDungeonKey())
        .. " mapID=" .. tostring(self.currentMapID))
end

function DTrash:StopMonitor()
    if not self.monitoring then return end
    self.monitoring = false
    for event in pairs(CAST_EVENTS) do
        self:UnregisterEvent(event)
    end
    -- Registered outside CAST_EVENTS (live-gated); a no-op if never registered.
    self:UnregisterEvent("UNIT_AURA")
    if TAD then TAD.SetEnabled(false) end
    self._auraDeltaLive = false
    if self.HideAllAlerts then self:HideAllAlerts() end
    if self.StopMarkers then self:StopMarkers() end
    wipe(self.tracked)
    self:ResetTrashCache()
    self.inBossEncounter = false
    self.bossEncounterID = nil
    self.bossProgressIndex = nil
    self.subZoneMapID = nil
    self.zoneText = nil
    self.forcesPercent = nil
    self.forcesValid = false
    -- Leaving the instance ends the encounter context; drop the reload cache.
    if self.db then self.db.LastEncounter = nil end
    dprint("monitor stopped")
end

-- ── Boss-encounter output blackout ──────────────────────────────────────────
-- The fingerprint layer cannot tell a boss or its adds from trash (their plate
-- identity is secret in 12.0), so on a blocklisted encounter we hide and
-- suppress ALL trash output for its duration — matching the upstream
-- references. Fingerprinting keeps running underneath; only the
-- display sinks (ShowAlert, UpdateNameplateMarker) honour this gate.

function DTrash:IsBossOutputSuppressed()
    return self.inBossEncounter
        and self.bossEncounterID ~= nil
        and DISABLED_BOSS_ENCOUNTER_IDS[self.bossEncounterID] == true
end

function DTrash:OnEncounterStart(_, encounterID)
    self.inBossEncounter = true
    self.bossEncounterID = tonumber(encounterID)
    -- Cache for StartMonitor's mid-encounter /reload recovery (SavedVariables
    -- survive a reload; ENCOUNTER_START does not replay). time() epoch, not
    -- GetTime(), so freshness survives the reload too.
    if self.db then
        self.db.LastEncounter = { id = self.bossEncounterID, at = time() }
    end
    if self:IsBossOutputSuppressed() then
        -- Clear combat output already on screen; the sink gates keep new output
        -- from appearing until ENCOUNTER_END. The GUI's looping preview sample
        -- is NOT combat output — keep it alive for a user editing mid-dungeon.
        if self.HideAllAlerts then self:HideAllAlerts(true) end
        for unit in pairs(self._markers or {}) do self:HideNameplateMarker(unit) end
        dprint("encounter start id=" .. tostring(self.bossEncounterID) .. " → trash output suppressed")
    else
        dprint("encounter start id=" .. tostring(self.bossEncounterID))
    end
    self:OnScenarioCriteriaChanged()  -- reference refreshes boss progress here too
end

function DTrash:OnEncounterEnd(_, encounterID)
    self.inBossEncounter = false
    self.bossEncounterID = nil
    if self.db then self.db.LastEncounter = nil end
    dprint("encounter end id=" .. tostring(encounterID))
    self:OnScenarioCriteriaChanged()  -- a kill advances bossProgressIndex
end

-- ── Lindormi's Guidance warning ─────────────────────────────────────────────
-- Lindormi's Guidance (the keystone-NPC assist, aura 1295927 on the TANK)
-- changes what the cast/cd machinery observes mid-dungeon and makes the trash
-- timers fire wrong or not at all, so scan the tanks and tell the player to
-- turn it off at the NPC. Detection needs readable auras
-- (C_Secrets.ShouldAurasBeSecret() == false). Warn once per detection; the
-- aura clearing re-arms the warning. Warns via StaticPopup, with a chat print
-- as the no-popup-API fallback.

local GUIDANCE_AURA_ID = 1295927
local GUIDANCE_CHECK_DELAY = 5   -- world-enter settle
local GUIDANCE_ROSTER_DELAY = 1  -- roster/role churn coalesce
local GUIDANCE_POPUP_KEY = "KE_DTRASH_LINDORMI_GUIDANCE"
local GUIDANCE_WARNING_TEXT = "Dungeon Trash Tracker: a tank in your group has"
    .. " Lindormi's Guidance active - it breaks the trash cast timers."
    .. " Have them disable it at the keystone NPC."

-- Warning popup (reference: EnsureWarningPopup + ShowWarning — StaticPopup
-- first, chat print fallback). Registered lazily, and as a FIELD write only —
-- never reassign the StaticPopupDialogs global itself (that taints the _G
-- slot; see TargetedSpells' CVar prompt).
local function showGuidanceWarning()
    if type(StaticPopupDialogs) == "table" and type(StaticPopup_Show) == "function" then
        if not StaticPopupDialogs[GUIDANCE_POPUP_KEY] then
            StaticPopupDialogs[GUIDANCE_POPUP_KEY] = {
                text = GUIDANCE_WARNING_TEXT,
                button1 = "Okay",
                timeout = 0,
                whileDead = true,
                hideOnEscape = false,
                preferredIndex = 3,
            }
        end
        StaticPopup_Show(GUIDANCE_POPUP_KEY)
        return
    end
    KE:Print("|cffff3333" .. GUIDANCE_WARNING_TEXT .. "|r")
end

-- Existence-probed + pcall'd aura presence (reference: HasAuraOnPlayer /
-- HasAuraOnUnit — by-spellID reads; the player unit has its own API).
local function hasGuidanceAura(unit)
    if not (C_UnitAuras and UnitExists(unit)) then return false end
    if unit == "player" then
        if type(C_UnitAuras.GetPlayerAuraBySpellID) ~= "function" then return false end
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, GUIDANCE_AURA_ID)
        return ok and aura ~= nil
    end
    if type(C_UnitAuras.GetUnitAuraBySpellID) ~= "function" then return false end
    local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, GUIDANCE_AURA_ID)
    return ok and aura ~= nil
end

local function isTankUnit(unit)
    if not (UnitExists(unit) and UnitGroupRolesAssigned) then return false end
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    return ok and role == "TANK"
end

-- The tank carrying the assist aura, if any (reference scan order: player
-- first, then party1-4).
local function findGuidanceTank()
    if isTankUnit("player") and hasGuidanceAura("player") then return "player" end
    for i = 1, 4 do
        local unit = "party" .. i
        if isTankUnit(unit) and hasGuidanceAura(unit) then return unit end
    end
    return nil
end

function DTrash:CheckGuidanceWarning()
    if not (C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function") then return end
    local ok, shouldBeSecret = pcall(C_Secrets.ShouldAurasBeSecret)
    if not ok or shouldBeSecret ~= false then return end
    if not findGuidanceTank() then
        self._guidanceWarned = false  -- cleared → a later re-detect warns again
        return
    end
    if self._guidanceWarned then return end
    self._guidanceWarned = true
    -- Don't re-show over an already-visible copy (reference guards on
    -- StaticPopup_Visible; FindVisible is KE's allowlisted equivalent).
    if type(StaticPopup_FindVisible) ~= "function"
        or not StaticPopup_FindVisible(GUIDANCE_POPUP_KEY) then
        showGuidanceWarning()
    end
end

-- Token-guarded deferred check: every schedule
-- invalidates the previous one, so a roster-event burst collapses into a
-- single read after the last edge.
function DTrash:ScheduleGuidanceCheck(delay)
    self._guidanceToken = (self._guidanceToken or 0) + 1
    local token = self._guidanceToken
    C_Timer.After(delay or GUIDANCE_CHECK_DELAY, function()
        if self._guidanceToken ~= token then return end
        self:CheckGuidanceWarning()
    end)
end

function DTrash:OnRosterChanged()
    self:ScheduleGuidanceCheck(GUIDANCE_ROSTER_DELAY)
    -- Roster churn re-keys the party unit tokens, so the aura-delta
    -- baselines are meaningless: wipe + reseed (gated on enabled inside).
    if TAD then TAD.OnRosterChanged() end
    -- Role churn can flip PlayerSeesTrashSpell from blocked to visible, and
    -- KE's arms are one-shot (a reveal consumed at fire time never re-arms):
    -- re-arm every tracked runtime from its still-correct anchors. Idempotent
    -- — live keys are skipped, pending arms are replaced via their token.
    if self.monitoring then
        for _, rt in pairs(self.tracked) do
            self:ReArmFromAnchors(rt, true)
        end
    end
end

-- ── Nameplate tracking ─────────────────────────────────────────────────────

function DTrash:OnNameplateAdded(_, unit)
    -- Assignment form (like every other handler): narrows the event arg to
    -- the validated string for everything below, editor type-checker included.
    unit = normalizeNameplate(unit)
    if not unit then return end
    if not isHostilePlate(unit) then return end
    local now = GetTime()
    self.tracked[unit] = {
        unit = unit,
        firstSeenAt = now,
        -- engagedAt = the FIRST moment the mob shows combat evidence — NOT
        -- plate-add: render range isn't engagement, and seeding first-cast
        -- timers per visible plate lit up the whole room (a since-reverted
        -- design). Stamped once here (mid-pull render), or later by
        -- MarkEngaged's evidence sites (UNIT_FLAGS flip, in-combat
        -- UNIT_TARGET, cast start) — the reference stamps at the same sites.
        engagedAt = (safeBool(UnitAffectingCombat, unit) == true) and now or nil,
        -- Seed the target-presence state so OnUnitTarget can detect the FIRST
        -- exists→not-exists transition (reference seeds at tracking start).
        targetStateExists = safeBool(UnitExists, unit .. "target"),
    }
    self:NoteNameplateAddedForCache(unit)
    C_Timer.After(SNAPSHOT_DELAY, function() self:SnapshotUnit(unit) end)
end

function DTrash:OnNameplateRemoved(_, unit)
    if not unit then return end
    local rt = self.tracked[unit]
    self.tracked[unit] = nil
    -- On-plate icons anchor to the physical plate — they always hide with it.
    if self.HideNameplateMarker then self:HideNameplateMarker(unit) end
    -- TrashCache flicker recovery: a resolved runtime is held for the restore
    -- window instead of being torn down — and its CENTRAL alerts deliberately
    -- keep counting through the window; the
    -- cache sweeps them iff no restore lands.
    if rt and self:CacheRemovedRuntime(unit, rt) then return end
    -- Scope the teardown to the departing runtime's OWN identity (alert keys
    -- embed npcID): a token recycled inside the cache window may still owe a
    -- PREVIOUS mob's counting bars to a pending restore, and an unscoped
    -- sweep here killed them (the reference is immune — its cancels are
    -- runtime-scoped, never token-scoped). An unresolved runtime owns no
    -- alerts, so it sweeps nothing; an untracked token keeps the full-token
    -- sweep as the orphan backstop.
    if self.HideUnitAlerts then
        if rt then
            if rt.matchedNPCID then self:HideUnitAlerts(unit, rt.matchedNPCID) end
        else
            self:HideUnitAlerts(unit)
        end
    end
end

function DTrash:SnapshotUnit(unit, attempt)
    local rt = self.tracked[unit]
    if not rt then return end
    -- Combat re-check on the snapshot timer(s): the plate-add read can land a
    -- frame too early on a mass pull, and losing that one edge must not lose
    -- engagement (the references re-stamp engagedAt on every refresh; this is
    -- the timer-driven equivalent).
    if not rt.engagedAt and safeBool(UnitAffectingCombat, unit) == true then
        self:MarkEngaged(rt)
    end
    if rt.obs then return end  -- a retry already landed
    local obs = readIdentity(unit, self:InMythicPlus())
    if not obs then
        -- Transient unreadable identity (unit data can still be unstable at
        -- +0.10s on a mass pull): retry a bounded couple of times instead of
        -- leaving the plate permanently untrackable — ResolveMob dead-ends on
        -- rt.obs=nil and nothing else ever re-reads identity. (The reference
        -- re-attempts its snapshot on every subsequent refresh event; this is
        -- the timer-driven equivalent.)
        local delay = SNAPSHOT_RETRIES[attempt or 1]
        if delay then
            C_Timer.After(delay, function() self:SnapshotUnit(unit, (attempt or 1) + 1) end)
        end
        return
    end
    rt.obs = obs
    self:ResolveMob(rt)
end

-- Cancel every output artifact keyed to the runtime's CURRENT identity —
-- shared by ResolveMob's Layer1 identity flip (contradiction-driven or not)
-- and FinishCast's Layer2 flip (both must kill armed bars, deferred reveals
-- and plate icons before the identity changes). Leaves the behavior flags
-- alone: they are observation evidence and keep guarding the re-derivation.
local function resetResolvedOutput(self, rt)
    if self.HideUnitAlerts then self:HideUnitAlerts(rt.unit, rt.matchedNPCID) end
    if rt._alertTokens then wipe(rt._alertTokens) end
    if rt.predictions then wipe(rt.predictions) end
    if self.HideNameplateMarker then self:HideNameplateMarker(rt.unit) end
    rt.anchors = nil
    rt.enterSeeded = nil
end

-- Layer1: fingerprint the mob → candidates. Re-run whenever behavior flags
-- change (a seen cast/channel/interrupt refines the candidate set).
function DTrash:ResolveMob(rt)
    -- Behavior-contradiction unlock, KEEP-LOCKED form (reference parity —
    -- ObservationTest's keepLockedRuntime retains a locked in-combat runtime
    -- whenever re-derivation fails, "to avoid clearing in-flight spells and
    -- local CDs"): a HARD capability contradiction — a kicked cannotInterrupt
    -- row (the Maisara hexxer wore Rokh'zal's timers through repeated kicks),
    -- or a cast/channel from a row without that capability — no longer drops
    -- the identity up front. It only ARMS the unlock: the flip commits below
    -- iff this pass re-derives a DIFFERENT mob. When every row rejects, the
    -- identity and its output are KEPT — field case (Algeth'ar):
    -- Shadowmeld breaking a Vicious Ambush cast still latched sawInterrupted
    -- AFTER the FAILED deviation shipped, so INTERRUPTED is the remaining
    -- latch path for a melded cast; all five Academy rows are cannotInterrupt,
    -- one such latch rejected them ALL, and the old eager drop blanked the
    -- plate's timers for good. Mirrors
    -- ScoreTraitRow's behavior gates EXACTLY; placement/level/classification
    -- stay ordinary Layer1 inputs (transient context must never unlock).
    -- A runtime without a snapshot (rt.obs nil) can't re-derive, so it keeps
    -- its identity too — the deliberate cost of keep-locked (the old eager
    -- drop self-healed there; the reference does not).
    local contradicted = false
    if rt.matchedNPCID then
        local trait = KE.TrashTraits and KE.TrashTraits[rt.matchedNPCID]
        local id = trait and trait.identity
        if id and ((rt.sawInterrupted and id.cannotInterrupt == true)
            or (rt.sawCastStart and not (id.hasCastSpell or id.hasCastSkill))
            or (rt.sawChannelStart and not (id.hasChannelSpell or rt.sawCastIntoChannel))) then
            contradicted = true
        end
    end
    if not rt.obs then return end
    local dungeonKey = self:CurrentDungeonKey()
    if not dungeonKey then return end

    local obs = rt.obs
    obs.sawCastStart = rt.sawCastStart
    obs.sawChannelStart = rt.sawChannelStart
    obs.sawInterrupted = rt.sawInterrupted
    obs.sawCastIntoChannel = rt.sawCastIntoChannel

    local cands, resolved = TI.BuildCandidates(obs, {
        dungeonKey = dungeonKey,
        mapID = self.currentMapID,                 -- instance map (data key + Academy exemption)
        bossProgressIndex = self.bossProgressIndex,
        currentSubZoneMapID = self.subZoneMapID,
        currentZoneText = self.zoneText,
        resolveAreaName = areaNameLookup,
        forcesPercent = self.forcesPercent,        -- nil when unknown, never 0 (nil skips the Academy prune)
    })
    rt.candidates = cands
    -- Layer1 (fingerprint) must NOT downgrade a Layer2 (observed cast/channel
    -- DURATION) resolution to a different mob: duration is stable, non-secret
    -- evidence and outranks fingerprint uniqueness. Once a cast confirms the mob,
    -- Layer1 may only re-affirm the same npcID, never flip it — EXCEPT through
    -- a capability contradiction, which is exactly the evidence that the lock
    -- was earned by the wrong row (`contradicted` re-computes identically every
    -- pass from the sticky behavior flags, so the bypass needs no state).
    if resolved and (not rt.castConfirmed or contradicted or resolved == rt.matchedNPCID) then
        -- TrashCache restore: a VIRGIN runtime (never resolved, never
        -- restored) independently re-resolving to a flicker-cached npcID
        -- adopts the cached runtime — identity, anchors and live alerts carry
        -- over (see TrashCache.lua). The reference consults its cache at this
        -- exact point: post-resolve, pre-assignment, never at plate add.
        if rt.matchedNPCID == nil and not rt._cacheRestoredAt then
            local adopted = self:TryRestoreCachedRuntime(rt, resolved)
            if adopted then return end
        end
        -- Identity FLIP (Layer1 re-resolving mob A → B): cancel A's armed
        -- output BEFORE adopting B — the references full-cancel + rebuild
        -- whenever the resolved candidate changes, while KE's enterSeeded
        -- latch would otherwise leave A's bars, deferred reveals and plate
        -- predictions live and make B's first-cast timers permanently
        -- unseedable. Every anchor is keyed by A's spellIDs, so the whole
        -- table goes. A contradicted lock ends here: the flip result is a
        -- fresh Layer1 resolve and starts unlocked.
        if rt.matchedNPCID ~= nil and resolved ~= rt.matchedNPCID then
            resetResolvedOutput(self, rt)
            rt.castConfirmed = nil
            dprint(string_format("%s: identity flip %s -> %s — output rebuilt",
                rt.unit, tostring(rt.matchedNPCID), tostring(resolved)))
        end
        rt.matchedNPCID = resolved
        self:SeedFirstCasts(rt)  -- resolve-after-engage: no-op unless engaged and unseeded
    elseif contradicted and not resolved and not rt._contraKeepDbg then
        -- One-shot diagnostic: the contradiction is live but nothing else
        -- resolves — keep-locked keeps painting the current identity.
        rt._contraKeepDbg = true
        dprint(string_format("%s: behavior contradicts %s but no alternative resolves — identity kept",
            rt.unit, tostring(rt.matchedNPCID)))
    end
    -- The pass may have just named the mob (fresh resolve, or an interrupt's
    -- flag-prune re-resolve): consume any pending CAST_START start-advance.
    self:ApplyPendingStartAdvance(rt)

    if DEBUG_DTRASH then
        -- Only print when a plate's resolution actually changes — nameplate
        -- tokens churn constantly in a big pull, and re-printing the same
        -- 0-candidate result for every re-add drowns the meaningful lines.
        local sig = tostring(resolved) .. ":" .. #cands
        if rt._resolveDbg ~= sig then
            rt._resolveDbg = sig
            local mob = resolved and self:MobData(resolved)
            dprint(string_format("%s: %d candidate(s) resolved=%s (%s)",
                rt.unit, #cands, tostring(resolved), (mob and mob.name) or "?"))
        end
    end
end

-- Player combat edge: sweep every tracked plate. The reference re-runs full identity
-- inference for all visible plates on PLAYER_REGEN_DISABLED/ENABLED (and both
-- references' engagedAt stamp rides every in-combat refresh), catching a mob
-- whose own UNIT_FLAGS edge was lost in the pull's event storm and a plate
-- whose one snapshot was Layer1-ambiguous and never casts. castConfirmed
-- stickiness + the enterSeeded latch + MarkEngaged's once-only stamp make the
-- sweep idempotent for already-settled runtimes.
function DTrash:OnPlayerCombatChanged()
    for unit, rt in pairs(self.tracked) do
        if not rt.engagedAt and safeBool(UnitAffectingCombat, unit) == true then
            self:MarkEngaged(rt)
        end
        if rt.obs == nil then
            self:SnapshotUnit(unit)  -- re-attempt a never-read identity
        else
            self:ResolveMob(rt)
        end
    end
end

-- ── Cast observation ───────────────────────────────────────────────────────

function DTrash:OnCastStart(_, unit, castGUID, _spellID, castBarID)
    self:BeginCast(unit, "cast", castGUID, castBarID)
end
function DTrash:OnChannelStart(_, unit, castGUID, _spellID, castBarID)
    self:BeginCast(unit, "channel", castGUID, castBarID)
end

-- castBarID (last event arg — 5th on START/STOP handlers, 6th on INTERRUPTED/
-- CHANNEL_STOP after interruptedBy) is the one NON-secret cast-lifecycle token
-- 12.0 leaves us (NeverSecret per the API reference; in-game probe confirmed).
-- It identifies a castbar INSTANCE, never the spell — the whole correlation
-- model runs on it: START↔STOP matching, duplicate-START rejection, the
-- cast→channel +1 transition proof, and the channel-refresh continuation.
-- Guarded anyway: first contact is issecretvalue, and an unreadable id just
-- degrades that correlation (see activeCastMatches). Non-negative numbers
-- only.
local function safeCastBarID(v)
    if issecretvalue and issecretvalue(v) then return nil end
    local id = tonumber(v)
    if id and id >= 0 then return id end
    return nil
end

-- Does an event's castBarID correlate with the runtime's ACTIVE castbar?
-- Reference semantics (ActiveCastMatches): no active cast →
-- never; both ids readable → strict equality; both nil → correlated (degrades
-- to the kind-only gates when the client omits the arg); one nil → mismatch.
-- Callers pass an already-safeCastBarID-normalized event id.
local function activeCastMatches(rt, castBarID)
    if not rt.activeCastStartAt then return false end
    local activeID = safeCastBarID(rt.activeCastBarID)
    if activeID ~= nil and castBarID ~= nil then
        return activeID == castBarID
    end
    return activeID == nil and castBarID == nil
end

-- ── Layer2 fingerprint samplers (target rings + buff count) ────────────────
-- The curated data disambiguates some same-duration spells by cast-start
-- behavior: did the mob switch/clear its target right at cast start
-- (castStartChangeTarget / targetClearOnCastStart — the Skyreach twins' ONLY
-- discriminator), or did its own buff count change on success
-- (selfBuffCountDeltaOnSuccess — splits Phalanx Breaker's twin 5s casts).
-- UNIT_TARGET events feed two per-runtime timestamp rings; the existing
-- +0.10s cast-start sampler scans them ± the window.

-- Append a timestamp to a runtime target-event ring, trimming entries older
-- than TARGET_EVENT_TRIM off the front.
local function appendTargetEvent(rt, key, at)
    local ring = rt[key]
    if not ring then ring = {}; rt[key] = ring end
    ring[#ring + 1] = at
    local cutoff = at - TARGET_EVENT_TRIM
    while ring[1] and ring[1] < cutoff do
        table.remove(ring, 1)
    end
end

local function hasEventInWindow(ring, fromAt, toAt)
    if not ring then return false end
    for i = 1, #ring do
        local at = ring[i]
        if at >= fromAt and at <= toAt then return true end
    end
    return false
end

-- Raw helpful-aura count — the same loop readIdentity fingerprints with, sans
-- the M+ affix adjustment (the success DELTA cancels any constant offset).
local function safeBuffCount(unit)
    local ok, n = pcall(function()
        local count, i = 0, 1
        while C_UnitAuras.GetAuraDataByIndex(unit, i) do count = count + 1; i = i + 1 end
        return count
    end)
    if ok and type(n) == "number" then return n end
    return nil
end

-- Party-debuff feed for the aura-delta sampler (TrashAuraDelta.lua):
-- registered only while the monitor runs AND group auras are readable (see
-- StartMonitor). TAD does the tracked-unit filter (player+party1-4), so
-- nameplate UNIT_AURA churn exits on its first check.
function DTrash:OnUnitAura(_, unit)
    if TAD then TAD.OnUnitAura(unit) end
end

-- Needs-based aura-delta sampling (reference parity: its aura-delta check
-- is SCHEDULED only when a pending candidate spell curates
-- castStartAuraDelta — an unscheduled cast never resolves the observation,
-- so the presence-symmetric fingerprint clause stays lenient for every mob
-- that never curated the field). A blanket sample would turn every
-- coincidental party debuff near an unrelated mob's cast start into
-- disconfirming evidence against its whole spell table. Unknown identity
-- (no candidates yet) samples leniently: a wrong extra sample risks one
-- missed credit, while a missing one risks a lenient-nil CAST_START
-- advance cross-anchoring on the wrong start.
local function mobCuratesAuraDelta(mob)
    if not (mob and mob.spells) then return false end
    for _, sp in pairs(mob.spells) do
        if sp.castStartAuraDelta == true then return true end
    end
    return false
end

function DTrash:RuntimeNeedsAuraDelta(rt)
    -- UNION of matched + candidates: a Layer2-locked identity does NOT rule the
    -- curating mob
    -- out — the lock is flippable by cast evidence, Layer1 keeps refreshing
    -- rt.candidates underneath it, and the flip's start-advance needs this
    -- sample to have landed. Checking only the stale matched mob skipped
    -- the sample exactly when the flip was about to need it.
    if rt.matchedNPCID and mobCuratesAuraDelta(self:MobData(rt.matchedNPCID)) then
        return true
    end
    local cands = rt.candidates
    if not (rt.matchedNPCID or cands) then return true end
    if cands then
        for _, c in ipairs(cands) do
            if mobCuratesAuraDelta(self:MobData(c.npcID)) then return true end
        end
    end
    return false
end

-- +0.10s aura-delta sample: did a fresh HARMFUL aura land on the party
-- inside startAt ± 0.10s (reference: a RefreshGroup catch-up sweep, then
-- FindRecentAdd over [start - pre, min(start + post, now)])? Reads the
-- PARTY, never the plate token, so it stays sampleable through a flicker
-- gap. Writes a hard true/false when sampled; skipped (nil = lenient)
-- when the sampler is dark or the needs gate says no candidate curates it.
function DTrash:SampleAuraDelta(rt)
    if not (self._auraDeltaLive and TAD) then return end
    local startAt = rt.activeCastStartAt
    if not startAt or not self:RuntimeNeedsAuraDelta(rt) then return end
    TAD.RefreshGroup(false)
    local now = GetTime()
    local endAt = startAt + TARGET_SAMPLE_DELAY
    if endAt > now then endAt = now end
    rt.fpCastStartAuraDelta = TAD.FindRecentAdd(startAt - TARGET_SAMPLE_DELAY, endAt) ~= nil
end

-- Every UNIT_TARGET on a tracked, in-combat plate records a switch timestamp;
-- an exists→not-exists transition additionally records a clear (reference:
-- MarkRuntimeUnitTarget + UpdateRuntimeTargetState, which appends ONLY that
-- transition direction). targetStateExists is seeded at plate add. All reads
-- are pcall-guarded booleans; a secret/unreadable state just leaves the
-- fingerprint unsampled (nil = never a false match).
function DTrash:OnUnitTarget(_, unit)
    unit = normalizeNameplate(unit)
    local rt = unit and self.tracked[unit]
    if not rt then return end
    if safeBool(UnitAffectingCombat, unit) ~= true then return end
    local now = GetTime()
    self:MarkEngaged(rt, now)  -- in-combat target churn is engagement evidence
    appendTargetEvent(rt, "targetSwitchEvents", now)
    local prev = rt.targetStateExists
    local cur = safeBool(UnitExists, unit .. "target")
    if prev == true and cur == false then
        appendTargetEvent(rt, "targetClearEvents", now)
    end
    if cur ~= nil then rt.targetStateExists = cur end
end

-- Does the resolved mob curate a channel that refreshes its castbar on
-- becoming interruptible? 12.0 hides WHICH spell is channeling, so this is a
-- mob-level gate; in the shipped
-- data exactly one spell carries the flag (Pulsing Shriek, npc 232175).
local function mobAllowsChannelRefresh(mob)
    if not (mob and mob.spells) then return false end
    for _, sp in pairs(mob.spells) do
        if sp.channelRefreshOnInterruptible == true and (sp.channelTime or 0) > 0 then
            return true
        end
    end
    return false
end

-- A flagged channel re-emits CHANNEL_START when its castbar refreshes on the
-- interruptible flip. OnCastInterruptible stamped the window; a channel start
-- inside it, for the SAME cast seq, carrying a NEW castBarID, is that refresh —
-- swap the castBarID and keep the original start/seq so the measurement anchor
-- (and the CAST_START-mode cd origin) doesn't shift late by the pre-refresh
-- portion. Mirrors the reference's isInterruptibleChannelRefresh branch.
local function isChannelRefreshContinuation(rt, kind, castBarID)
    return kind == "channel"
        and rt.activeCastKind == "channel"
        and rt.activeCastStartAt ~= nil
        and rt.channelRefreshAt ~= nil
        and (GetTime() - rt.channelRefreshAt) <= CHANNEL_REFRESH_WINDOW
        and rt.channelRefreshSeq == rt.activeCastSeq
        and castBarID ~= nil
        and castBarID ~= rt.activeCastBarID
end

-- spellID is intentionally NOT read from the event (secret in 12.0). castGUID
-- is captured only as a DEBUG probe — it answered the correlation question
-- (castGUID IS secret for hostile casters; castBarID, the last arg, is the
-- non-secret token the correlation model now runs on); the print stays per
-- the leave-instrumentation convention.
function DTrash:BeginCast(unit, kind, castGUID, castBarID)
    unit = normalizeNameplate(unit)
    local rt = unit and self.tracked[unit]
    if not rt then return end
    castBarID = safeCastBarID(castBarID)
    -- Duplicate-START rejection (reference: BeginRuntimeCast ignores a START
    -- for the castbar instance already active): a re-fired START must not
    -- re-anchor activeCastStartAt — the shortened measured duration falls out
    -- of Layer2 tolerance and the cast silently unmatches. Non-nil equality
    -- only; a nil id can't prove sameness.
    if rt.activeCastStartAt and rt.activeCastKind == kind
        and castBarID ~= nil and castBarID == safeCastBarID(rt.activeCastBarID) then
        return
    end
    if isChannelRefreshContinuation(rt, kind, castBarID) then
        rt.activeCastBarID = castBarID
        rt.channelRefreshAt = nil
        dprint(tostring(unit) .. ": channel refresh (interruptible) — continuation, anchor kept")
        return
    end
    if DEBUG_DTRASH then
        -- Secret-safe probe: never tostring/tonumber a possibly-secret castGUID
        -- (that would throw in combat). Printing "<secret>" IS the answer we
        -- want — it tells us 12.0 blocks castGUID for barID correlation.
        -- issecretvalue MUST be first contact: castGUID is secret for hostile
        -- casters (SecretWhenUnitSpellCastRestricted), and even a `== nil`
        -- compare ahead of the guard risks a secret-boolean throw. The
        -- short-circuit keeps the nil/tostring path off any possible secret.
        local guid
        if issecretvalue and issecretvalue(castGUID) then
            guid = "<secret>"
        elseif castGUID == nil then
            guid = "nil"
        else
            guid = tostring(castGUID) .. " num=" .. tostring(tonumber(castGUID))
        end
        dprint(string_format("%s: %s start castGUID=%s", tostring(unit), kind, guid))
    end
    -- Cast→channel transition proof: this channel's castBarID is EXACTLY the
    -- just-finished cast's +1 within the pairing window → same castbar rolling
    -- cast into channel phase. Arm the transition (the channel finish anchors
    -- at the TRUE cast start), mark the pairing so a held one-phase credit for
    -- that cast discards itself (phantom twin), and set the behavior bit that
    -- keeps channel-capable candidates alive in Layer1. transitionCastStartAt
    -- lifecycle: armed here; consumed-once at channel finish; cleared on a
    -- correlated interrupt and on any UNPAIRED new start (below).
    local paired = false
    if kind == "channel" and castBarID ~= nil and rt.lastCastBarID ~= nil
        and castBarID == rt.lastCastBarID + 1
        and rt.lastCastEndAt and (GetTime() - rt.lastCastEndAt) <= TRANSITION_PAIR_WINDOW then
        paired = true
        rt.transitionCastStartAt = rt.lastCastStartAt
        rt.transitionPairedStartAt = rt.lastCastStartAt
        rt.sawCastIntoChannel = true
        dprint(tostring(unit) .. ": cast->channel proven (castBarID +1) — channel anchors at cast start")
    elseif kind == "channel" and castBarID ~= nil
        and rt.activeCastKind == "cast" and rt.activeCastStartAt ~= nil then
        -- Implied-stop pairing (reference: isCastIntoChannel pairs the
        -- incoming channel against the STILL-ACTIVE cast — no processed STOP
        -- required, no wall-clock window): a +1 channel start arriving while
        -- the cast is still active means its STOP was late, reordered or
        -- dropped. Requiring a processed STOP was a KE-only miss mode — each
        -- miss fired the twin hold's phantom one-phase credit AND anchored
        -- the channel late by castTime. The superseded cast's late STOP then
        -- fails the kind gate in FinishCast (harmless stale event).
        local activeID = safeCastBarID(rt.activeCastBarID)
        if activeID ~= nil and castBarID == activeID + 1 then
            paired = true
            rt.transitionCastStartAt = rt.activeCastStartAt
            rt.transitionPairedStartAt = rt.activeCastStartAt
            rt.sawCastIntoChannel = true
            dprint(tostring(unit) .. ": cast->channel proven (implied stop, castBarID +1) — channel anchors at cast start")
        end
    end
    if not paired then rt.transitionCastStartAt = nil end
    -- The pairing fields describe only the IMMEDIATELY preceding finished
    -- cast; any new start consumes them, paired or not.
    rt.lastCastBarID, rt.lastCastStartAt, rt.lastCastEndAt = nil, nil, nil
    rt.activeCastKind = kind
    rt.activeCastStartAt = GetTime()
    rt.activeCastSeq = (rt.activeCastSeq or 0) + 1
    rt.activeCastBarID = castBarID
    rt.channelRefreshAt = nil  -- a genuine new cast invalidates any stamped refresh window
    -- CAST_START pending start-advance (reference: BeginRuntimeCast arms it on
    -- every NON-transition start; a paired transition channel keeps the cast
    -- phase's already-applied advance). Consumed by ApplyPendingStartAdvance
    -- once the mob is resolved AND the +0.10s fingerprints are sampled — the
    -- cast's OUTCOME is irrelevant: CAST_START cds anchor at the observed
    -- START, which is the reference's ONLY anchor path for them.
    if paired then
        rt.pendingStartAdvanceAt, rt.pendingStartAdvanceKind = nil, nil
    else
        rt.pendingStartAdvanceAt = rt.activeCastStartAt
        rt.pendingStartAdvanceKind = kind
    end
    rt.startFingerprintsReady = nil
    rt.fpTargetExists = nil
    rt.fpTargetAPIExists = nil
    rt.fpCastStartChangeTarget = nil
    rt.fpTargetClearOnCastStart = nil
    rt.fpTargetIsTank = nil
    rt.fpCastStartAuraDelta = nil
    if kind == "cast" then
        rt.sawCastStart = true
    else
        rt.sawChannelStart = true
    end
    self:MarkEngaged(rt)  -- a cast IS engagement proof (the old reactive model's whole premise)

    self:ResolveMob(rt)  -- behavior flag may prune candidates

    local seq = rt.activeCastSeq
    C_Timer.After(TARGET_SAMPLE_DELAY, function()
        -- Runtime-IDENTITY gate on rt.unit (not the captured token): a
        -- TrashCache restore inside the sample window re-points rt.unit to
        -- the new plate token, and the sampler must follow the mob — the
        -- reference's samplers ride the runtime object for the same reason.
        local r = self.tracked[rt.unit]
        if r ~= rt then
            -- Flicker-gap exception (reference: pending state rides the cache
            -- snapshot and is consumed after restore): a runtime pending
            -- cache recovery stays consumable. The unit reads are SKIPPED —
            -- the old token may be empty or already recycled to another mob,
            -- and nil fingerprints are lenient — but the fingerprint wait
            -- completes so the pending start-advance can't be permanently
            -- poisoned by a 0.10s plate blink.
            if rt._cachePending == true and rt.activeCastSeq == seq then
                -- The aura-delta sample reads the PARTY, not the plate
                -- token — unlike the unit-read fingerprints above it
                -- survives the gap, and must: ownership made it the
                -- discriminator that keeps a curating spell's start-advance
                -- off its mob's OTHER cast starts.
                self:SampleAuraDelta(rt)
                rt.startFingerprintsReady = true
                self:ApplyPendingStartAdvance(rt)
            end
            return
        end
        if rt.activeCastSeq ~= seq then return end  -- stale-cast guard
        r.fpTargetExists = safeBool(UnitExists, rt.unit .. "target")
        if UnitShouldDisplaySpellTargetName then
            r.fpTargetAPIExists = safeBool(UnitShouldDisplaySpellTargetName, rt.unit)
        end
        -- targetIsTank (dormant fingerprint, mapped for future data): the
        -- mob's target is a PLAYER unit, whose role is plain — still guarded.
        local okRole, role = pcall(UnitGroupRolesAssigned, rt.unit .. "target")
        if okRole and not (issecretvalue and issecretvalue(role)) and type(role) == "string" then
            r.fpTargetIsTank = (role == "TANK")
        end
        -- Scan the target rings ± the window around the ANCHORED start (the
        -- reference's HasTargetSwitchEventInWindow / ...ClearTransitionInWindow
        -- run in this same +0.10s snapshot, window = startAt ± 0.10).
        local startAt = r.activeCastStartAt
        if startAt then
            r.fpCastStartChangeTarget = hasEventInWindow(r.targetSwitchEvents,
                startAt - TARGET_SAMPLE_DELAY, startAt + TARGET_SAMPLE_DELAY)
            r.fpTargetClearOnCastStart = hasEventInWindow(r.targetClearEvents,
                startAt - TARGET_SAMPLE_DELAY, startAt + TARGET_SAMPLE_DELAY)
        end
        self:SampleAuraDelta(r)
        -- Start fingerprints are now as sampled as they will get: the pending
        -- CAST_START start-advance may consume them (no-op until resolved) —
        -- the reference's pending-start fingerprint wait, timer-driven.
        r.startFingerprintsReady = true
        self:ApplyPendingStartAdvance(r)
    end)

    -- Observed-cast-start cue: anchored HERE, at the real cast bar — never at
    -- countdown-zero, which is only the prediction. Deferred one cue window
    -- (0.12s) INSIDE the output layer so the +0.10s sampler above lands first
    -- and the sampled start fingerprints can filter the pick — scheduled
    -- after the sampler so timer order matches delay order. Output-layer
    -- method, guarded like the other output seams (TrashOutput loads after
    -- this file).
    if self.PlayObservedCastStartCue then self:PlayObservedCastStartCue(rt, kind) end
end

function DTrash:OnCastStop(_, unit, _castGUID, _spellID, castBarID)
    self:FinishCast(unit, "cast", false, castBarID)
end
function DTrash:OnChannelStop(_, unit, _castGUID, _spellID, interruptedBy, castBarID)
    -- interruptedBy is a secret GUID for hostile casters; its mere PRESENCE
    -- means the channel was interrupted. Detect presence WITHOUT a nil-compare
    -- on a secret: issecretvalue short-circuits true for a present secret, so
    -- `~= nil` only ever runs on a confirmed non-secret value. (This path is
    -- unconditional — not gated by DEBUG — so it must be crash-proof.)
    local interrupted = (issecretvalue and issecretvalue(interruptedBy)) or (interruptedBy ~= nil)
    self:FinishCast(unit, "channel", interrupted, castBarID)
end

function DTrash:OnCastInterrupted(_, unit, _castGUID, _spellID, _interruptedBy, castBarID)
    self:MarkCastInterrupted(unit, castBarID)
end

-- FAILED / FAILED_QUIET: the cast aborted without succeeding or being kicked
-- (target died / Shadowmelded, LoS, caster CC'd mid-cast). Same castBarID-
-- gated lifecycle teardown as a kick — without it the runtime's active cast
-- dangles — but NO sawInterrupted behavior evidence. DELIBERATE DEVIATION
-- (field-verified in Algeth'ar Academy): the reference's FAILED handlers DO
-- latch the same sticky sawInterrupted a real kick sets (its Layer1 filter
-- hard-rejects cannotInterrupt rows on it), and that is field-broken — a
-- FAILED proves NOTHING about interruptibility (Riftbreath cancelled by its
-- target's Shadowmeld cannot be kicked at all), yet one abort permanently
-- rejected every Academy trait row (all five are cannotInterrupt) on that
-- plate: unresolved mobs never gained timers, and a resolved Ravager hit the
-- contradiction unlock and never re-resolved. sawInterrupted stays a
-- genuine-kick latch: UNIT_SPELLCAST_INTERRUPTED only — the interruptedBy-
-- correlated channel stop was removed from it too (the channel-phase twin of
-- this same Shadowmeld failure; see FinishCast), matching the
-- reference, whose channel-stop interrupt never reaches its Layer1 filter.
function DTrash:OnCastFailed(_, unit, _castGUID, _spellID, castBarID)
    self:MarkCastInterrupted(unit, castBarID, true)
end

-- Shared interrupt-shaped lifecycle teardown (INTERRUPTED / FAILED /
-- FAILED_QUIET). The teardown only applies when the event CORRELATES with the
-- active castbar: INTERRUPTED is known to
-- double-fire, and a late event for a PREVIOUS castbar arriving after a new
-- START would otherwise kill the live cast — its FinishCast then early-returns
-- and that cast's alert is silently lost. A mismatched INTERRUPTED still
-- counts as interrupt evidence (the flag prunes cannotInterrupt candidates
-- either way); castFailed events tear down without testifying (see
-- OnCastFailed for the documented deviation).
function DTrash:MarkCastInterrupted(unit, castBarID, castFailed)
    unit = normalizeNameplate(unit)
    local rt = unit and self.tracked[unit]
    if not rt then return end
    if not castFailed then rt.sawInterrupted = true end
    -- Interrupt evidence IS engagement evidence (references stamp engagedAt on
    -- the first sawInterrupted observation) — stamped before ResolveMob below
    -- so a resolution there can seed first-cast timers immediately.
    self:MarkEngaged(rt)
    if activeCastMatches(rt, safeCastBarID(castBarID)) then
        rt.activeCastKind = nil
        -- A kick/failure ends the active cast lifecycle, so any armed cast→
        -- channel pairing died with it: the interrupted cast/channel can no
        -- longer be the armed cast's immediate follow-up. (Reference parity:
        -- transition state clears on every resolution, including interrupts.)
        rt.transitionCastStartAt = nil
    end
    self:ResolveMob(rt)  -- interrupt flag prunes cannotInterrupt candidates now
end

-- Stamp the channel-refresh window for a running channel on a mob whose
-- curated data allows it (channelRefreshOnInterruptible). The re-emitted
-- CHANNEL_START that follows within CHANNEL_REFRESH_WINDOW (same seq, new
-- castBarID) is then treated as a continuation by BeginCast instead of
-- restarting the measurement — see isChannelRefreshContinuation. Without this
-- the flip re-anchors the channel late by the pre-refresh portion, shifting
-- the CAST_START-mode cd origin and the reconstructed successAt every cycle.
-- UNIT_SPELLCAST_INTERRUPTIBLE is a unit-only payload in 12.0 (no castGUID /
-- spellID / castBarID — UnitDocumentation confirms; the reference destructures
-- a castBarID here too, but that gate is equally dead upstream). The active-
-- channel kind/seq checks below are the real correlation.
function DTrash:OnCastInterruptible(_, unit)
    unit = normalizeNameplate(unit)
    local rt = unit and self.tracked[unit]
    if not rt then return end
    if rt.activeCastKind ~= "channel" or not rt.activeCastStartAt then return end
    local mob = rt.matchedNPCID and self:MobData(rt.matchedNPCID)
    if not mobAllowsChannelRefresh(mob) then return end
    rt.channelRefreshAt = GetTime()
    rt.channelRefreshSeq = rt.activeCastSeq
end

-- Anchor a resolved spell's cd schedule and emit its central alert + on-plate
-- prediction. Shared by the direct cast/channel path in FinishCast and the
-- transition-pairing hold (a one-phase credit deferred one pairing window).
-- anchorStartAt = the ability's start (feeds anchorAt + the CAST_START-mode cd
-- origin). successAt = when the effect actually landed, the cd origin for default
-- (success-mode) spells: for a cast that's the finish; for a CHANNEL it's the
-- channel start + curated channelTime, NOT the measured STOP — a grab/beam
-- channel's caster STOP fires far too early (see FinishCast). The true channel
-- duration is unreadable in 12.0 (secret), so the schedule never depends on the
-- measured channel length. kind/duration are debug-only (the calibration line).
function DTrash:EmitCastResolution(rt, mob, spellID, anchorStartAt, successAt, now, kind, duration)
    local spellData = mob and mob.spells and mob.spells[spellID]
    if not spellData then return end

    rt.anchors = rt.anchors or {}
    -- Round-robin the cd[] sequence across successive casts: seed the index from
    -- this spell's prior anchor (default 1), then persist the FOLLOWING index that
    -- ComputeNextCast returns so the next cast advances/wraps instead of forever
    -- re-using cd[1] (10 curated spells have multi-value cd[] and mistimed).
    local prevAnchor = rt.anchors[spellID]
    local seqIndex = (prevAnchor and prevAnchor.nextSeqIndex) or 1
    local intervalOrigin = (spellData.cdMode == "CAST_START") and anchorStartAt or successAt
    -- Roll forward so a late emit (or a schedule whose computed next is already
    -- due) advances to the next future occurrence instead of stranding on "ready".
    local nextStart, following, isFuture = TI.NextScheduledCast(spellData, intervalOrigin, seqIndex, now)
    rt.anchors[spellID] = {
        mode = "success",
        anchorAt = anchorStartAt - (spellData.first or 0),
        nextSeqIndex = following or 1,
        -- Predicted next occurrence — InferSucceededSpell's primary schedule-
        -- proximity term (the reference scores against the predicted NEXT
        -- start, never the previous one).
        nextStartAt = nextStart,
    }

    if DEBUG_DTRASH then
        local phase = (kind and duration) and string_format(" (%.2fs %s)", duration, kind) or ""
        dprint(string_format("%s: %s | %s%s -> next %s",
            tostring(rt.unit), mob.name, spellData.name, phase,
            (nextStart and isFuture) and string_format("in %.1fs", nextStart - now) or "n/a"))
    end

    -- Emit outputs, but only for a genuinely future cast — a nextStart already
    -- due/past has nothing to count down to and would strand an icon on "ready".
    -- The central alert and the on-plate icon share the isFuture gate so they
    -- stay consistent.
    if nextStart and isFuture then
        -- Key outputs on the npcID whose spell table produced spellData — the
        -- transition-pairing hold captures its mob at hold time, and a Layer1
        -- re-resolution inside the held window must not pair spell-of-A with
        -- identity-of-B (label/color/role lookups would all miss).
        local npcID = mob.npcID or rt.matchedNPCID
        if self.ScheduleAlert then
            self:ScheduleAlert(rt, npcID, spellID, spellData, nextStart)
        end
        if self.SetNameplatePrediction then
            -- `now`, not intervalOrigin: the plate swipe spans registration →
            -- nextStart (see SetNameplatePrediction; the schedule origin can
            -- be far past — or, for a reconstructed channel successAt, in the
            -- FUTURE, which drew no swipe at all).
            self:SetNameplatePrediction(rt, npcID, spellID, now, nextStart)
        end
    end
    -- A Layer2 resolution may have JUST confirmed the mob's identity: seed the
    -- first-cast timers of its OTHER spells now (this spell already carries
    -- its real anchor above, so the seeding skips it).
    self:SeedFirstCasts(rt)
end

-- Calibration aid for a measured cast that matched none of the resolved mob's
-- curated spells: show the observed duration/kind AND the curated durations,
-- so an unmatched cast is instantly classifiable as "uncurated filler" vs
-- "curated timing is off".
local function debugUnmatched(unit, mob, kind, duration)
    if not DEBUG_DTRASH then return end
    local want = {}
    if mob and mob.spells then
        for _, sp in pairs(mob.spells) do
            want[#want + 1] = string_format("%s(c%.1f/ch%.1f)",
                sp.name or "?", sp.castTime or 0, sp.channelTime or 0)
        end
    end
    dprint(string_format("%s: %s %s %.2fs UNMATCHED | curated: %s",
        tostring(unit), (mob and mob.name) or "?", kind, duration,
        table.concat(want, ", ")))
end

-- Credit a finished CHANNEL: infer WHICH channel spell it was and emit
-- (mirror of creditFinishedCast below — the channel-side selfBuffCountDelta
-- sampling can defer it one sample window; `now` is re-read for that).
local function creditFinishedChannel(self, rt, mob, observed, startAt, transitionStartAt)
    local now = GetTime()
    local spellID = TI.InferSucceededSpell(mob, observed, rt.anchors, now)
    if not spellID then
        debugUnmatched(rt.unit, mob, "channel", observed.duration)
        self:SeedFirstCasts(rt)  -- resolved mob, failed inference: see creditFinishedCast
        return
    end
    local spellData = mob.spells[spellID]
    -- Start-advance-owned CAST_START channels were anchored at their observed
    -- START; a success emit here would advance the cd[] round-robin a second
    -- time.
    -- Ownership mirrors the start path's PER-CAST rule via the fingerprint
    -- snapshot frozen into `observed` at FinishCast (churn guard): an
    -- unsampled delta means the start path never advanced, so the success
    -- credit must land — and the frozen snapshot keeps a new cast's field
    -- clear inside a deferred-credit window from faking "unsampled".
    if TI.IsStartAdvanceOwned(spellData,
        type(observed.fingerprints.castStartAuraDelta) == "boolean") then return end
    -- The caster's CHANNEL_STOP fires when its cast bar closes, which for
    -- grab/beam mechanics is far short of the ability's real channelTime, so
    -- the STOP is an unreliable success time. Reconstruct the true effect end
    -- from the reliable channel START + curated channelTime. (CAST_START-mode
    -- spells ignore successAt and anchor at the start.)
    local successAt = now
    local ct = tonumber(spellData.channelTime)
    if ct then successAt = startAt + ct end
    -- A proven transition anchors at the TRUE cast start (the reference
    -- anchors at transitionCastStartAt whenever it is set).
    local anchorStartAt = transitionStartAt or startAt
    self:EmitCastResolution(rt, mob, spellID, anchorStartAt, successAt, now, "channel", observed.duration)
end

-- Credit a finished bare CAST: infer WHICH one-phase spell it was and emit.
-- Split from FinishCast because the credit can be deferred by the transition-
-- pairing hold (see there) — the synchronous path and the held closure both
-- land here. stopAt = the cast's STOP time (its successAt); `now` is re-read
-- because the held path runs a pairing window later.
local function creditFinishedCast(self, rt, mob, observed, startAt, stopAt)
    local now = GetTime()
    -- A curated forced-sequence pick outranks inference (reference: the
    -- forced spellID is consulted before any duration/schedule scoring),
    -- validity-guarded against the mob's own spell table so a bad curated
    -- index can never emit an unknown spellID.
    local spellID = observed.forcedSpellID
    if not (spellID and mob.spells and mob.spells[spellID]) then
        -- ONE-phase spells only (reference rule: cast-kind success inference
        -- skips channel-capable spells): a completed bare cast is never
        -- credited as a two-phase ability — that spell is credited exclusively
        -- from its channel phase, anchored at the true cast start via the
        -- castBarID +1 pairing.
        spellID = TI.InferSucceededSpell(mob, observed, rt.anchors, now, true)
    end
    if not spellID then
        debugUnmatched(rt.unit, mob, "cast", observed.duration)
        -- The mob is RESOLVED even though this cast defied inference: arm the
        -- enter schedules of its not-yet-anchored spells (references arm
        -- schedules on every resolved in-combat refresh, independent of any
        -- single cast's inference outcome). No-op once seeded.
        self:SeedFirstCasts(rt)
        return
    end
    -- Start-advance-owned CAST_START spells already anchored at their START.
    -- Same per-cast ownership rule as the channel path above (churn guard, via
    -- the frozen fingerprint snapshot).
    if TI.IsStartAdvanceOwned(mob.spells and mob.spells[spellID],
        type(observed.fingerprints.castStartAuraDelta) == "boolean") then return end
    self:EmitCastResolution(rt, mob, spellID, startAt, stopAt, now, "cast", observed.duration)
end

-- Reset the target-state sampler on a unit's combat FLIP (reference:
-- ResetRuntimeTargetState on every per-unit combat transition). Entering
-- combat re-seeds the presence baseline and clears stale ring entries so the
-- first in-combat UNIT_TARGET can't log a false clear against a pre-combat
-- baseline; leaving combat (evade/wipe) nils everything so a stale
-- exists→gone can't carry across to the re-pull.
function DTrash:ResetTargetState(rt, inCombat)
    rt.targetSwitchEvents = nil
    rt.targetClearEvents = nil
    if inCombat then
        -- and/or would collapse a legitimate FALSE baseline to nil.
        rt.targetStateExists = safeBool(UnitExists, rt.unit .. "target")
    else
        rt.targetStateExists = nil
    end
end

-- Stamp the mob's TRUE engage moment exactly once and try the first-cast
-- seeding (no-op unless the mob is already resolved). The reference stamps
-- engagedAt at the same evidence sites — its in-combat snapshot check, its
-- behavior marks, and the first cast/channel start — and never clears it.
function DTrash:MarkEngaged(rt, now)
    if not rt or rt.engagedAt then return end
    rt.engagedAt = now or GetTime()
    -- First combat evidence = the OOC→IC flip: re-seed the target baseline
    -- (later flips are caught by OnUnitFlags' per-unit combat tracking).
    self:ResetTargetState(rt, true)
    self:SeedFirstCasts(rt)
end

-- Speculative first-cast seeding: the moment a
-- mob is BOTH resolved and engaged, every curated spell without an observed
-- anchor gets an "enter"-mode anchor at engagedAt and its first-cast
-- countdown (first, rolled forward if we joined late) — the reference builds
-- exactly these ("enter" anchors from defaultAnchorAt = engagedAt, scheduling
-- gated on canSchedule = UnitAffectingCombat). The whole-room seeding spam is
-- dead by construction: engagedAt is combat EVIDENCE, never render range,
-- and a runtime seeds ONCE — an unconfirmed guess dies at zero (alert
-- self-destruct, plate-icon grace prune) instead of free-running; real casts
-- take over the anchors from here.
function DTrash:SeedFirstCasts(rt)
    if rt.enterSeeded or not (rt.engagedAt and rt.matchedNPCID) then return end
    local mob = self:MobData(rt.matchedNPCID)
    if not (mob and mob.spells) then return end
    rt.enterSeeded = true
    local now = GetTime()
    rt.anchors = rt.anchors or {}
    for spellID, spellData in pairs(mob.spells) do
        if not rt.anchors[spellID] then
            local nextStart, following, isFuture = TI.NextEnterCast(spellData, rt.engagedAt, now)
            if nextStart and isFuture then
                rt.anchors[spellID] = {
                    mode = "enter",
                    -- anchorAt + first == the expected first cast: the
                    -- invariant every anchor consumer assumes (an enter
                    -- anchor scores identically to the engage fallback it
                    -- replaces until a real cast overwrites it).
                    anchorAt = rt.engagedAt,
                    nextSeqIndex = following or 1,
                    nextStartAt = nextStart,
                }
                if self.ScheduleAlert then
                    self:ScheduleAlert(rt, rt.matchedNPCID, spellID, spellData, nextStart)
                end
                if self.SetNameplatePrediction then
                    -- `now`, not engagedAt: a rolled seed (resolution joined
                    -- late) must draw a fresh full swipe, not a pre-drained
                    -- one.
                    self:SetNameplatePrediction(rt, rt.matchedNPCID, spellID, now, nextStart)
                end
            end
        end
    end
    dprint(tostring(rt.unit) .. ": first-cast seeds armed (" .. tostring(mob.name or "?") .. ")")
end

-- Re-arm a resolved runtime's future output from its anchors (extracted from
-- the TrashCache restore): every anchor whose predicted next start is still
-- future and has no live alert under its key re-schedules through the normal
-- ScheduleAlert gates; withPredictions additionally repaints the plate icon
-- (the GUI re-enable path — the marker prune DELETED its stored predictions).
-- KE's arms are one-shot, so a spell disabled mid-dungeon consumed its armed
-- output at fire time and nothing re-read the still-correct anchors; the
-- reference re-registers every schedule from persisted anchors on each config
-- revision. Timers still die at zero — no free-run: anchors are observation-
-- derived and the live-key guard keeps this idempotent.
function DTrash:ReArmFromAnchors(rt, withPredictions, now)
    local npcID = rt and rt.matchedNPCID
    if not (npcID and rt.anchors) then return end
    now = now or GetTime()
    local mob = self:MobData(npcID)
    if not (mob and mob.spells) then return end
    for spellID, anchor in pairs(rt.anchors) do
        local spellData = mob.spells[spellID]
        if spellData and anchor.nextStartAt and anchor.nextStartAt > now then
            local key = rt.unit .. ":" .. npcID .. ":" .. spellID
            if not (self.alerts and self.alerts[key]) then
                if self.ScheduleAlert then
                    self:ScheduleAlert(rt, npcID, spellID, spellData, anchor.nextStartAt)
                end
                if withPredictions and self.SetNameplatePrediction then
                    self:SetNameplatePrediction(rt, npcID, spellID, now, anchor.nextStartAt)
                end
            end
        end
    end
end

-- Consume a pending CAST_START start-advance: anchor every start-advance-owned
-- spell matching the observed start's kind + sampled fingerprints at the
-- observed START (reference: ApplyObservedStartAdvance, consumed by the sync
-- pass with interrupts EXPLICITLY unable to cancel it — its success-mode
-- inference returns nil for CAST_START, making start-advance their only
-- anchor path). Without this a KICKED CAST_START ability never re-armed its
-- next-cast countdown, and 5 of the 6 shipped CAST_START spells are exactly
-- the long interrupt-priority channels groups always kick (Pulsing Shriek,
-- Plungegrip, Fire Spit, Arcane Salvo, Shredding Talons). Gated on
-- resolution + the sampled fingerprints; consumed on the first MATCHING
-- resolution (retained otherwise — see the consume-on-match note below);
-- a new start re-arms.
-- (The reference's other interrupt advance, InferInterruptedChannelSpell, is
-- gated on cdOnInterruptedChannel-family flags that ZERO data rows carry
-- upstream or here — dormant, not ported.)
function DTrash:ApplyPendingStartAdvance(rt)
    local startAt = rt.pendingStartAdvanceAt
    if not (startAt and rt.matchedNPCID) then return end
    local mob = self:MobData(rt.matchedNPCID)
    if not (mob and mob.spells) then return end
    -- The +0.10s fingerprint wait is NEEDS-BASED (reference: fingerprint
    -- waits exist only for spells that curate one): the sampler is the sole
    -- writer of startFingerprintsReady, so gating unconditionally let a plate
    -- blink inside the sample window strand the pending forever — no cd bar
    -- until a full cycle later, on mobs (e.g. Devoted Woebringer) whose
    -- spells curate zero start fingerprints and never needed the wait.
    if not rt.startFingerprintsReady then
        if TI.NeedsStartFingerprints(mob, self._auraDeltaLive) then return end
        -- The MATCHED mob may not be the delta's consumer: when any viable
        -- candidate curates castStartAuraDelta, the sample must land before
        -- consumption — a stale Layer2-locked identity consuming the
        -- pending pre-sample would strand the curating mob's start on the
        -- later Layer2 flip (divergent-candidates review find).
        if self._auraDeltaLive and self:RuntimeNeedsAuraDelta(rt) then return end
    end
    local kind = rt.pendingStartAdvanceKind
    local fingerprints = {
        targetExists = rt.fpTargetExists,
        targetAPIExists = rt.fpTargetAPIExists,
        castStartChangeTarget = rt.fpCastStartChangeTarget,
        targetClearOnCastStart = rt.fpTargetClearOnCastStart,
        targetIsTank = rt.fpTargetIsTank,
        castStartAuraDelta = rt.fpCastStartAuraDelta,
    }
    -- Per-cast delta resolution (churn guard): ownership of a curating
    -- spell requires THIS cast's delta to have actually been SAMPLED.
    -- Candidate churn across the +0.10s window can skip the sample while
    -- the ready bit still sets, and an owned match on the lenient nil
    -- would anchor at a start the sample never discriminated. Unsampled →
    -- not owned this cast → the success path credits instead.
    local deltaSampled = type(fingerprints.castStartAuraDelta) == "boolean"
    local now = GetTime()
    -- Consume ON MATCH, not unconditionally (reference: the pending start
    -- is retained while its fingerprint needs are unresolved and re-applied
    -- per resolution pass): under a stale locked identity whose spells all
    -- reject the sampled delta, the pending must survive to the Layer2 flip
    -- that names the true consumer — FinishCast re-applies it right after
    -- the flip. Retention is bounded: the next BeginCast re-arms
    -- (overwrites) the pending and a paired transition clears it, so a
    -- never-matching start can outlive its cast by at most one lifecycle —
    -- the same window the kick-survival behavior already keeps it for.
    local consumed = false
    for spellID, spellData in pairs(mob.spells) do
        if TI.MatchesObservedCastStart(spellData, kind, fingerprints, deltaSampled) then
            consumed = true
            self:EmitCastResolution(rt, mob, spellID, startAt, startAt, now, kind, nil)
        end
    end
    if consumed then
        rt.pendingStartAdvanceAt, rt.pendingStartAdvanceKind = nil, nil
    end
end

-- Forced cast-sequence pick (reference: the Windrunner Spire trash overlay's
-- per-mob forced spell order, TrashCurated.lua's KE.TrashForcedCastSequences):
-- a mob whose bare casts are indistinguishable on every sampled axis but
-- follow a FIXED order is named by POSITION. Advances ONCE per cast sequence
-- (a re-consult for the same activeCastSeq returns the same pick), and only
-- successful finishes consult it — a kicked cast never advances the order.
-- An index past the curated list returns nil → normal inference.
local function resolveForcedCastSpell(rt, mob)
    local seqs = KE.TrashForcedCastSequences
    local list = seqs and mob and seqs[mob.npcID or rt.matchedNPCID]
    if not list then return nil end
    if rt._forcedCastSeq ~= rt.activeCastSeq then
        rt._forcedCastSeq = rt.activeCastSeq
        rt._forcedCastIndex = (rt._forcedCastIndex or 0) + 1
        rt._forcedCastSpellID = list[rt._forcedCastIndex]
    end
    return rt._forcedCastSpellID
end

-- Cast completed successfully → Layer2 (narrow candidates + infer the spell)
-- → calibrate the cd schedule → emit the alert.
function DTrash:FinishCast(unit, kind, interrupted, castBarID)
    unit = normalizeNameplate(unit)
    local rt = unit and self.tracked[unit]
    if not rt or rt.activeCastKind ~= kind or not rt.activeCastStartAt then return end
    -- Stale-stop rejection (reference: every stop sink checks
    -- ActiveCastMatches): a stop whose castBarID doesn't correlate with the
    -- ACTIVE castbar is a late/duplicate event for a previous castbar.
    -- Consuming it would mis-measure the live cast, and around the
    -- interruptible channel refresh the OLD bar's stop would end the continued
    -- channel mid-flight. Correlation rule lives in activeCastMatches.
    if not activeCastMatches(rt, safeCastBarID(castBarID)) then return end

    local now = GetTime()
    local duration = now - rt.activeCastStartAt
    local startAt = rt.activeCastStartAt
    local activeBarID = safeCastBarID(rt.activeCastBarID)
    rt.activeCastKind = nil
    -- Consume the proven cast→channel transition exactly ONCE: it pairs only
    -- with the channel BeginCast armed it for. Kicked, unmatched or absent,
    -- the pairing is spent either way — left set, a LATER unrelated channel
    -- would anchor tens of seconds in the past.
    local transitionStartAt
    if kind == "channel" then
        transitionStartAt = rt.transitionCastStartAt
        rt.transitionCastStartAt = nil
    end
    if interrupted then
        -- interruptedBy presence ends the channel WITHOUT a success credit,
        -- but it is NOT Layer1 kick evidence: the reference's channel-stop
        -- handler feeds it only into the cast lifecycle (pendingInterrupted)
        -- — its Layer1-visible sawInterrupted latches ONLY from the
        -- INTERRUPTED/FAILED events. Parity hardening alongside the
        -- keep-locked fix (see ResolveMob): a Shadowmeld breaking
        -- a channel aimed at the melder would stop it with interruptedBy
        -- present, and a latch here would reject every cannotInterrupt
        -- Academy row exactly like the FAILED latch this module already
        -- reverted (see OnCastFailed).
        return
    end
    if kind == "cast" then
        -- Pairing bookkeeping for the castBarID +1 transition proof: these
        -- fields describe the just-finished cast; BeginCast consumes them
        -- (paired or not) on the next start for this unit.
        rt.lastCastBarID = activeBarID
        rt.lastCastStartAt = startAt
        rt.lastCastEndAt = now
    end

    -- Channel-evidence discriminator input (a later upstream addition): TRUE
    -- = this channel's cast→channel transition was PROVEN (two-phase spells
    -- only). NEVER false
    -- in KE: the reference affirms a transition's ABSENCE because its pairing
    -- window is unbounded, but KE's proof rides the deliberate 0.25s pairing
    -- window + strict castBarID+1 — a missed pairing (latency; hidden castbar
    -- instances bumping the counter, e.g. per-player tether applications) is
    -- indistinguishable from a genuine bare channel. A false "false" hard-
    -- rejected Chains of Subjugation's channel every time the pairing missed
    -- (field-verified: [cast,channel] runtimes without the cast>channel
    -- bit, chains predictions overdue then grace-pruned). Unproven stays nil
    -- → lenient.
    local castIntoChannel
    if kind == "channel" and transitionStartAt then
        castIntoChannel = true
    end

    local observed = {
        kind = kind,
        duration = duration,
        startAt = startAt,
        -- Engage-anchored first-cast expectation: InferSucceededSpell's
        -- schedule-proximity fallback for a spell with no anchor yet. Falls
        -- back to first-seen when no combat evidence was ever observed —
        -- the reference's defaultAnchorAt = engagedAt or firstSeenAt chain.
        engagedAt = rt.engagedAt or rt.firstSeenAt,
        castIntoChannel = castIntoChannel,
        fingerprints = {
            targetExists = rt.fpTargetExists,
            targetAPIExists = rt.fpTargetAPIExists,
            castStartChangeTarget = rt.fpCastStartChangeTarget,
            targetClearOnCastStart = rt.fpTargetClearOnCastStart,
            targetIsTank = rt.fpTargetIsTank,
            castStartAuraDelta = rt.fpCastStartAuraDelta,
        },
    }

    local dataByNpc = function(npc) return self:MobData(npc) end
    -- Trait-duration keep tier: the mob's KNOWN-but-uncurated filler durations
    -- must keep it in the pool / verify it (see TI.TraitDurationMatches).
    local traitByNpc = function(npc) return KE.TrashTraits and KE.TrashTraits[npc] end

    -- Layer2: the observed cast disambiguates a multi-candidate set and
    -- VERIFIES a lone candidate — a level-disagreed lone survivor resolves
    -- only here, via a matching cast (the old #>1 gate made that promised
    -- deferral dead code and left such mobs permanently unresolved).
    if rt.candidates and #rt.candidates >= 1 then
        -- Confirm strength is decided by the POOL SHAPE BEFORE this cast: a
        -- VERIFIED lone survivor or a levelAgreed
        -- winner earns the castConfirmed lock — duration-confirmed identity
        -- outranks Layer1 there. A multi-pool collapse onto a level-DISAGREED
        -- sibling can be driven by NEGATIVE evidence (an uncurated filler
        -- cast fails the true mob while coincidentally matching the sibling's
        -- clustered duration), so it resolves FLIPPABLE — matchedNPCID
        -- without the lock — approximating the reference's stateless
        -- always-re-derive semantics.
        local wasLone = (#rt.candidates == 1)
        local kept, resolved = TI.FilterCandidates(rt.candidates, observed, dataByNpc, traitByNpc)
        rt.candidates = kept
        if resolved then
            local levelAgreed = false
            for _, c in ipairs(kept) do
                if c.npcID == resolved then levelAgreed = (c.levelAgreed == true); break end
            end
            -- TrashCache restore consult (mirrors ResolveMob's wiring): a
            -- level-disagreed mob's ONLY resolve path is this Layer2 confirm,
            -- so without a consult here flicker recovery was structurally
            -- unreachable for exactly those mobs —
            -- cached bars died at expiry and the fresh runtime enter-seeded
            -- bogus first-cast countdowns mid-cycle. On adoption, THIS cast's
            -- lifecycle moves onto the adopted table so the credit below (and
            -- its deferred closures) ride the restored runtime exactly like a
            -- pre-flicker cast would.
            if rt.matchedNPCID == nil and not rt._cacheRestoredAt then
                local adopted = self:TryRestoreCachedRuntime(rt, resolved)
                if adopted then
                    adopted.pendingStartAdvanceAt = rt.pendingStartAdvanceAt
                    adopted.pendingStartAdvanceKind = rt.pendingStartAdvanceKind
                    adopted.startFingerprintsReady = rt.startFingerprintsReady
                    adopted.fpTargetExists = rt.fpTargetExists
                    adopted.fpTargetAPIExists = rt.fpTargetAPIExists
                    adopted.fpCastStartChangeTarget = rt.fpCastStartChangeTarget
                    adopted.fpTargetClearOnCastStart = rt.fpTargetClearOnCastStart
                    adopted.fpTargetIsTank = rt.fpTargetIsTank
                    adopted.fpCastStartAuraDelta = rt.fpCastStartAuraDelta
                    adopted.lastCastBarID = rt.lastCastBarID
                    adopted.lastCastStartAt = rt.lastCastStartAt
                    adopted.lastCastEndAt = rt.lastCastEndAt
                    -- A fresh seq on the adopted timeline: the forced-sequence
                    -- resolver advances per NEW cast seq, and the virgin
                    -- runtime's counter could collide with the adopted one's.
                    adopted.activeCastSeq = (adopted.activeCastSeq or 0) + 1
                    -- Schedule proximity should score against the adopted
                    -- runtime's real engage history, not the post-flicker one.
                    observed.engagedAt = adopted.engagedAt or adopted.firstSeenAt or observed.engagedAt
                    rt = adopted
                end
            end
            -- Layer2 identity FLIP (locked or not — cast evidence heals cast
            -- evidence by re-deriving): run the SAME output hygiene as the
            -- Layer1 flip branch. The old npcID's alerts, deferred reveals,
            -- plate predictions and anchors are all keyed to the OLD identity
            -- and would otherwise orphan — surviving even plate removal,
            -- whose sweep is scoped to the NEW npcID — while the enterSeeded
            -- latch would block the new identity's first-cast seeding.
            if rt.matchedNPCID ~= nil and resolved ~= rt.matchedNPCID then
                resetResolvedOutput(self, rt)
                rt.castConfirmed = nil
                dprint(string_format("%s: Layer2 identity flip %s -> %s — output rebuilt",
                    unit, tostring(rt.matchedNPCID), tostring(resolved)))
            end
            rt.matchedNPCID = resolved
            -- Resolve-without-lock: an ambiguous bare channel (transition
            -- unprovable, no pure-channel affirmation on the resolved mob)
            -- never earns the lock — the reference survives the same lenient
            -- match by never locking at all. Resolve + output arm either way;
            -- Layer1 re-derivation can still heal it until a duration-gated
            -- cast or a proven transition confirms.
            if (wasLone or levelAgreed)
                and TI.ChannelEvidenceLocks(dataByNpc(resolved), observed) then
                rt.castConfirmed = true
            end
        end
    end
    if not rt.matchedNPCID then
        dprint(unit .. " finish: mob unresolved")
        return
    end
    local mob = self:MobData(rt.matchedNPCID)
    if not mob then return end
    -- The mob may have just been Layer2-confirmed above: consume any pending
    -- CAST_START start-advance BEFORE the success inference (the reference
    -- sync applies pending-start ahead of pending-finish).
    self:ApplyPendingStartAdvance(rt)

    if kind == "channel" then
        -- Success-side self-buff-count delta rides the CHANNEL stop too (the
        -- references sample it on both kinds; without this, the strict
        -- success rule would make any delta-curating channel spell
        -- permanently uncreditable). Sample-and-defer mirrors the cast path.
        if TI.NeedsSelfBuffCountDelta(mob, "channel") then
            local beforeCount = safeBuffCount(unit)
            local creditNpcID = rt.matchedNPCID
            dprint(unit .. ": channel credit deferred for self buff-count delta")
            C_Timer.After(TARGET_SAMPLE_DELAY, function()
                -- Flicker-gap exception (mirrors the sampler): a runtime
                -- pending cache recovery still consumes its earned credit —
                -- but never samples the old token (it may host another mob);
                -- the unsampled delta strictly rejects delta-curating spells.
                local live = self.tracked[rt.unit] == rt
                if not live and rt._cachePending ~= true then return end
                -- A deferred credit lands only under the identity that earned
                -- it (reference: candidateChanged wipes pending success state
                -- before consumption). A contradiction-drop or identity flip
                -- inside the window otherwise re-arms the discredited npcID's
                -- anchors and alerts right after resetResolvedOutput swept them.
                if rt.matchedNPCID ~= creditNpcID then return end
                if live and beforeCount ~= nil then
                    local after = safeBuffCount(rt.unit)
                    if type(after) == "number" then
                        observed.selfBuffCountDelta = after - beforeCount
                    end
                end
                creditFinishedChannel(self, rt, mob, observed, startAt, transitionStartAt)
            end)
            return
        end
        creditFinishedChannel(self, rt, mob, observed, startAt, transitionStartAt)
        return
    end

    -- Forced-sequence pick is resolved NOW, not inside the deferred credit:
    -- the hold/delta closures fire a window later, when a NEW start may
    -- already have bumped activeCastSeq past this cast's.
    observed.forcedSpellID = resolveForcedCastSpell(rt, mob)

    -- Bare cast finished. Two reasons can defer the credit:
    --
    -- • selfBuffCountDelta sampling (reference: the success self-buff-count
    --   snapshot — before-count at the stop, after-count +0.10s; consumption
    --   waits on it only when the mob's curated data carries the field). The
    --   delta splits Phalanx Breaker's twin 5s casts; it cancels any constant
    --   offset, so the raw count is safe.
    --
    -- • Two-phase ambiguity hold: when this duration ALSO fits one of the
    --   mob's TWO-PHASE spells, a +1 channel start about to arrive would
    --   prove this was the two-phase cast phase, and an immediate one-phase
    --   credit would be a phantom double-fire (4 curated mobs carry such a
    --   same-duration twin). Hold for one pairing window and discard if the
    --   pairing claims this cast. Deliberate, documented deviation: the
    --   reference only holds consumption for fingerprint sampling and eagerly
    --   double-credits on mobs without fingerprint needs; KE gates the hold
    --   on the actual ambiguity so the phantom twin alert never fires. The
    --   discard mechanism itself is the reference's (a paired transition
    --   silently drops the cast phase's pending success).
    local needsSelfDelta = TI.NeedsSelfBuffCountDelta(mob, "cast")
    local holdForTwin = TI.MatchesTwoPhaseCast(mob, observed)
    if not (needsSelfDelta or holdForTwin) then
        creditFinishedCast(self, rt, mob, observed, startAt, now)
        return
    end
    -- Deferred gates below key on RUNTIME IDENTITY at rt.unit (re-read at fire
    -- time), not the captured token: a TrashCache restore inside the 0.10-0.25s
    -- hold re-points rt.unit to the new plate, and the credit must follow the
    -- mob through the flicker (the reference's pending-cast queue lives on the
    -- runtime table and survives its rebind the same way).
    local beforeCount = needsSelfDelta and safeBuffCount(unit) or nil
    -- A deferred credit lands only under the identity that earned it
    -- (reference: candidateChanged wipes pending success state before
    -- consumption). Checked at fire time in both closures below.
    local creditNpcID = rt.matchedNPCID
    local function sampleSelfDelta()
        if beforeCount == nil then return end
        local after = safeBuffCount(rt.unit)
        if type(after) == "number" then
            observed.selfBuffCountDelta = after - beforeCount
        end
    end
    if holdForTwin then
        dprint(unit .. ": one-phase credit held (two-phase twin possible)")
        if needsSelfDelta then
            -- Sample at the reference's exact +0.10s even though the credit
            -- itself waits out the longer pairing window.
            C_Timer.After(TARGET_SAMPLE_DELAY, function()
                if self.tracked[rt.unit] == rt then sampleSelfDelta() end
            end)
        end
        C_Timer.After(TRANSITION_PAIR_WINDOW, function()
            -- Flicker-gap exception: a hold maturing while the plate is
            -- cache-pending still consumes (reference: pending casts ride the
            -- cache snapshot); the expiry sweep owns the cancel otherwise.
            if self.tracked[rt.unit] ~= rt and rt._cachePending ~= true then return end
            if rt.matchedNPCID ~= creditNpcID then return end
            if rt.transitionPairedStartAt == startAt then return end  -- proven two-phase; phantom discarded
            creditFinishedCast(self, rt, mob, observed, startAt, now)
        end)
        return
    end
    dprint(unit .. ": credit deferred for self buff-count delta")
    C_Timer.After(TARGET_SAMPLE_DELAY, function()
        local live = self.tracked[rt.unit] == rt
        if not live and rt._cachePending ~= true then return end
        if rt.matchedNPCID ~= creditNpcID then return end
        if live then sampleSelfDelta() end
        creditFinishedCast(self, rt, mob, observed, startAt, now)
    end)
end

return DTrash
