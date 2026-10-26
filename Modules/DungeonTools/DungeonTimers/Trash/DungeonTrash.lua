-- ╔══════════════════════════════════════════════════════════╗
-- ║  DungeonTrash.lua                                        ║
-- ║  Module: Dungeon Trash Tracker                           ║
-- ║                                                          ║
-- ║  Nameplate-driven trash-cast tracker. Owns the event     ║
-- ║  loop + per-nameplate runtime state; delegates every     ║
-- ║  decision to KE.TrashInference (pure). Detection is      ║
-- ║  behavioral inference because 12.0 makes a nameplate's   ║
-- ║  npcID (UnitGUID) and a cast's spellID secret.           ║
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
-- Cast→channel pairing window, shared with TI.ProveCastIntoChannel: a proven
-- channel phase starts this soon after its cast's own STOP, and an ambiguous
-- one-phase credit is held this long for it (see FinishCast).
local TRANSITION_PAIR_WINDOW = TI.TRANSITION_PAIR_WINDOW
-- Target-evidence window: the delay requested for its close timer. The
-- real boundary is when that callback runs; no time difference is compared.
local TARGET_CHANGE_WINDOW = 0.75
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
-- Load marker: increment it in every later commit that touches a shipped
-- .lua, .xml or .toc file.
DTrash._trashStateRevision = 2
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

-- APIs only the identity reader uses.
local UnitIsLieutenant = UnitIsLieutenant
local UnitCreatureFamily = UnitCreatureFamily

-- One guarded call's outcome for normalization: whether it ran, its value,
-- and whether that value is secret. issecretvalue is the first contact.
local function guardedValue(ok, v)
    if not ok then return false, nil, false end
    if issecretvalue and issecretvalue(v) then return true, nil, true end
    return true, v, false
end

-- Reads one identity field under its own guard and normalizes it; nil is
-- unknown. An absent API or a failed aura count is unknown, never 0. Family
-- is the presence predicate UnitCreatureFamily(unit) ~= nil, evaluated inside
-- its own pcall; the raw family value never leaves that call.
local function readField(unit, field, inMythicPlus)
    local ok, v, secret = false, nil, false
    if field == "level" then
        if UnitLevel then ok, v, secret = guardedValue(pcall(UnitLevel, unit)) end
    elseif field == "sex" then
        if UnitSex then ok, v, secret = guardedValue(pcall(UnitSex, unit)) end
    elseif field == "power" then
        if UnitPowerType then ok, v, secret = guardedValue(pcall(UnitPowerType, unit)) end
    elseif field == "classID" then
        if UnitClass then
            local called, _, _, classID = pcall(UnitClass, unit)
            ok, v, secret = guardedValue(called, classID)
        end
    elseif field == "unitClassification" then
        if UnitClassification then ok, v, secret = guardedValue(pcall(UnitClassification, unit)) end
    elseif field == "buffCount" then
        -- Aura COUNT only: the aura table is truthy even when its fields are
        -- secret, and no field is read.
        local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
        if getAura then
            ok, v = pcall(function()
                local n, i = 0, 1
                while getAura(unit, i) do n = n + 1; i = i + 1 end
                return n
            end)
            if ok and inMythicPlus and type(v) == "number" and v > 0 then v = v - 1 end  -- the affix aura
        end
    elseif field == "isLieutenant" then
        if UnitIsLieutenant then
            v = safeBool(UnitIsLieutenant, unit)
            ok = v ~= nil
        end
    elseif field == "hasCreatureFamily" then
        if TI.FAMILY_GATE and UnitCreatureFamily then
            ok, v = pcall(function() return UnitCreatureFamily(unit) ~= nil end)
            secret = (ok and issecretvalue ~= nil and issecretvalue(v)) or false
        end
    end
    return TI.NormalizeIdentityField(field, ok, v, secret)
end

-- Reads the listed snapshot fields. Returns the known ones (an empty table
-- when none is known), or nil when the unit does not exist. The reader holds
-- no schema rules: callers pass the read plan's fields.
local function readIdentity(unit, fields, inMythicPlus)
    if not (unit and fields and safeBool(UnitExists, unit) == true) then return nil end
    local out = {}
    for _, field in ipairs(fields) do
        out[field] = readField(unit, field, inMythicPlus)
    end
    return out
end

-- Unit-token first contact: secrecy before type or find.
local function normalizeNameplate(unit)
    if issecretvalue and issecretvalue(unit) then return nil end
    if type(unit) == "string" and unit:find("^nameplate%d") then return unit end
    return nil
end
-- Exported so TrashCache.lua's handlers use the same first contact.
DTrash._normalizeNameplate = normalizeNameplate

-- Merges a read of `fields` into the generation's fresh snapshot, which is
-- stored even when partial. A known field is never overwritten.
local function readInto(self, rt, fields)
    if not (fields and fields[1] ~= nil) then return end
    local fresh = readIdentity(rt.unit, fields, self:InMythicPlus())
    if fresh then rt.obs = TI.MergeIdentity(rt.obs, fresh) end
end

-- One opportunity of a plate generation's scheduled read chain: the
-- initial delayed read and at most two more. It captures the owner, never the
-- token or the runtime table, so a removed, replaced or stopped generation
-- does nothing, even when cache reuse reinstalls its table.
function DTrash:ScheduledIdentityRead(owner)
    if not TI.RecoveryOwnerHolds(owner, self.tracked, self.monitoring) then return end
    local rt = owner.runtime
    -- Combat re-check: unconditional, feeding the counting-window edge.
    -- The plate-add read can land a frame too early on a mass pull, and
    -- losing that one edge must not lose engagement.
    local inCombat = safeBool(UnitAffectingCombat, rt.unit)
    self:CombatEdge(rt, inCombat)
    if not rt.engagedAt and inCombat == true then
        self:MarkEngaged(rt)
    end
    local fields, scheduled, runs = TI.RecoveryReadPlan(
        { obs = rt.obs, pending = rt.obsPending, scheduled = owner.scheduled }, "scheduled")
    owner.scheduled = scheduled
    if not runs then return end
    readInto(self, rt, fields)
    self:ResolveMob(rt)
    -- An adoption in that pass moved the owner; the chain follows it.
    rt = owner.runtime
    local delay = SNAPSHOT_RETRIES[owner.scheduled]
    if delay and not TI.RecoverySettled(rt.obsPending) then
        C_Timer.After(delay, function() self:ScheduledIdentityRead(owner) end)
    end
end

-- An event read opportunity: the read rule only. It never starts,
-- refills or counts against the scheduled chain; the caller runs its one
-- resolve pass after it.
function DTrash:EventIdentityRead(rt)
    local fields = TI.RecoveryReadPlan({ obs = rt.obs, pending = rt.obsPending,
        scheduled = rt.owner and rt.owner.scheduled }, "event")
    readInto(self, rt, fields)
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
    self:RefreshKingsRestScope()
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
    -- forcesOnly = the synchronous scenario-edge pass: only the forces
    -- refresher runs at the event edge. Boss criteria complete
    -- LATE and a mid-burst read can transiently blank them; the index is a
    -- placement-gate input whose unknown state fails OPEN, so it is written
    -- only by the settled debounced re-read.
    if not forcesOnly then
        self.bossProgressIndex = (bossTotal > 0) and (bossKilled + 1) or nil
    end
    -- forcesPercent stays nil when unknown — NEVER 0: a nil percent makes
    -- the Academy routing skip its prune and let Layer2 disambiguate, while a
    -- literal 0 would route to the <20% npc.
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
-- the next resolve, because the Academy/Skyreach routing reads it at resolve
-- time. bossProgressIndex is written only by the deferred re-read, since boss
-- criteria complete slightly AFTER the kill (single-pending 1.0s debounce).
-- The tick re-reads zone state too: a multi-floor transition that emits no
-- ZONE_CHANGED* event (elevators/teleporters) would otherwise leave a
-- stale-but-known sub-zone failing the placement gate closed.
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

-- /kes trash detail: ordinary chat output, no debug gate. Reads only module
-- runtime state; bar IDs and other raw tokens are never printed.
local CAST_EFFECTS = {
    normal = "normal",
    uncertain = "withheld: unowned START (uncertain)",
    baseline = "withheld: baseline waiting for its end",
    closed = "withheld: closed, waiting for the next distinct identified START",
    saturated = "withheld: saturated, every later START withheld",
}
local TARGET_CAUSE = { secret = "a secret read", read = "an error or missing read" }

function DTrash:DumpPlateDetail(rt)
    local o, pending = rt.obs, rt.obsPending
    local parts = {}
    if pending == nil then
        parts[1] = "unjudged"
    elseif pending[1] == nil then
        parts[1] = "settled"
    else
        parts[1] = "pending " .. table.concat(pending, ",")
    end
    parts[2] = string_format("scheduled reads %d/%d", (rt.owner and rt.owner.scheduled) or 0,
        TI.RECOVERY_SCHEDULED_MAX)
    if o and o.isLieutenant ~= nil then parts[#parts + 1] = "lieutenant " .. tostring(o.isLieutenant) end
    if o and o.hasCreatureFamily ~= nil then parts[#parts + 1] = "family " .. tostring(o.hasCreatureFamily) end
    KE:Print("      identity: " .. table.concat(parts, ", "))

    local cs = rt.castState
    if cs then
        local w = cs.window
        local window
        if not w then
            window = "none"
        elseif w.known then
            window = string_format("known, count %d", w.count)
        else
            -- Saturation is the only unknown path that records no reason.
            window = "unknown (" .. (w.unknownWhy or "saturated") .. ")"
        end
        local latest = cs.latest
        local baseline = latest ~= nil and latest.class == "baseline" and latest.open == true
        local ended = latest and ((latest.retired and ", latest record retired")
            or (latest.canceled and ", latest record canceled")) or ""
        KE:Print(string_format("      window: %s; cast effects: %s; baseline %s%s", window,
            CAST_EFFECTS[cs.recovery] or tostring(cs.recovery), baseline and "present" or "absent", ended))
        local repeats = cs.departedRepeats or {}
        KE:Print(string_format("      departed IDs: cast %d/%d, channel %d/%d%s; departed repeats refused: cast %d, channel %d",
            #cs.history.cast, TI.DEPARTED_ID_CAP, #cs.history.channel, TI.DEPARTED_ID_CAP,
            cs.recovery == "saturated" and " (saturated)" or "", repeats.cast or 0, repeats.channel or 0))
        if latest and latest.targetState ~= nil then
            local detail = latest.targetState
            if detail == "unavailable" then
                detail = detail .. " (" .. (TARGET_CAUSE[latest.targetCause]
                    or ("no change before the " .. tostring(latest.targetCause) .. " close")) .. ")"
            end
            if latest.targetCommit then detail = detail .. ", committed at a " .. latest.targetCommit end
            detail = detail .. string_format(", %d later change(s) ignored", latest.targetIgnored or 0)
            KE:Print("      target evidence: " .. detail)
        end
        if latest and latest.open and latest.restoredAt then
            KE:Print("      open observation came through a restore at " .. latest.restoredAt)
        end
    end
    if rt.restoreSite then KE:Print("      restored at " .. rt.restoreSite) end
    if rt.restoreRefused then KE:Print("      restore refused by the admission decision") end

    local owner = rt.owner
    if self.kr and owner then
        local decision = owner.krDecision or "not a member"
        if owner.krReason then decision = decision .. " (" .. owner.krReason .. ")" end
        local cap = owner.krCapture
        local history = "none captured"
        if cap then
            history = cap.unknown and ("unknown (" .. tostring(owner.krCaptureCause) .. ")") or "complete"
            if owner.krPossibleReturns then
                history = history .. string_format(", %d possible return(s) at the ready check",
                    owner.krPossibleReturns)
            else
                history = history .. ", not judged"
            end
        end
        KE:Print(string_format("      kings' rest: %s; history %s; wave-derived %s",
            decision, history, tostring(rt.waveDerived == true)))
    end
end

-- The Sepulcher batch: phase, release reason and frozen summary.
function DTrash:DumpKingsRestBatch()
    local st = self.kr
    if not (st and self.krInRoom) then return end
    local b = st.batch
    if not b then
        KE:Print("  batch: none")
        return
    end
    local line = "  batch: " .. b.phase
    if b.reason then line = line .. " (" .. b.reason .. ")" end
    local s = b.summary
    if s then
        line = line .. string_format(" summary level90=%s level90power0=%s family=%s",
            tostring(s.groupHasLevel90), tostring(s.groupHasLevel90Power0), tostring(s.groupHasCreatureFamily))
    end
    KE:Print(line)
end

-- On-demand diagnostic dump (/kes trash). Snapshots what the tracker currently
-- believes — dungeon resolution, each tracked plate's resolved mob (or candidate
-- count), the behavior flags it has seen, and its live predictions — so an
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
        local to = readIdentity("target", TI.IdentityReadFields(), self:InMythicPlus())
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
        self:DumpPlateDetail(rt)
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
    self:DumpKingsRestBatch()

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
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "EvaluateGate")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "EvaluateGate")
    -- Lindormi's Guidance detection rides roster and role churn too.
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterChanged")
    self:RegisterEvent("PLAYER_ROLES_ASSIGNED", "OnRosterChanged")
    self:EvaluateGate()
end

function DTrash:OnDisable()
    -- A guidance check already scheduled must not prompt for a disabled module.
    self._guidanceToken = (self._guidanceToken or 0) + 1
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
    -- Reload/login recovery: ENCOUNTER_START does not replay after a /reload,
    -- so a monitor starting mid-encounter would fail OPEN on a blocklisted
    -- fight — the exact Ick & Krick case the blackout exists for. So
    -- OnEncounterStart caches the id in SavedVariables, and it is adopted
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
    if self.HideAllAlerts then self:HideAllAlerts() end
    if self.StopMarkers then self:StopMarkers() end
    -- Every plate generation ends here: its owner-bound callbacks are refused.
    for _, rt in pairs(self.tracked) do
        if rt.owner then rt.owner.live = false end
    end
    wipe(self.tracked)
    -- Every owner is dead, so no released member resolves; the history goes.
    self:StopKingsRest()
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
-- suppress ALL trash output for its duration. Fingerprinting keeps running
-- underneath; only the display sinks (ShowAlert, UpdateNameplateMarker) honor
-- this gate.

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
    self:OnScenarioCriteriaChanged()  -- an encounter edge moves boss progress
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
-- aura clearing re-arms the warning.

local GUIDANCE_AURA_ID = 1295927
local GUIDANCE_CHECK_DELAY = 5   -- world-enter settle
local GUIDANCE_ROSTER_DELAY = 1  -- roster/role churn coalesce
local GUIDANCE_WARNING_TEXT = "Dungeon Trash Tracker: a tank in your group has"
    .. " Lindormi's Guidance active - it breaks the trash cast timers."
    .. " Have them disable it at the keystone NPC."

-- The prompt's accept. It does nothing; it gives the warning an owner, so a
-- re-detection closes the copy on screen instead of queueing a second.
local function acknowledgeGuidance() end

local function showGuidanceWarning()
    KE:ClosePromptIfOwner(acknowledgeGuidance)
    KE:CreatePrompt("Dungeon Trash Tracker", GUIDANCE_WARNING_TEXT,
        false, nil, false, nil, nil, nil, nil, acknowledgeGuidance, nil,
        "Okay", nil, nil, nil, { acceptOnly = true, waitIfBusy = true })
end

-- Existence-probed + pcall'd aura presence, read by spellID. The player unit
-- has its own API.
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
    return ok and canaccessvalue(role) and role == "TANK"
end

-- The tank carrying the assist aura, if any. Player first, then party1-4.
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
    showGuidanceWarning()
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

-- ── Kings' Rest room waves ─────────────────────────────────────────────────
-- The pure core (TrashKingsRest.lua, loaded after the inference) keeps the
-- removal history and the room batch; this wiring owns its scope, timers and
-- providers. Off map 1762 no state exists and nothing here runs.
local KR = KE.TrashKingsRest
-- Exported so TrashCache.lua's admission refusal and death mark use it too.
DTrash._kingsRest = KR
-- Removal history runs on this instance map, and room batches only in this
-- room, compared with the normalized minimap text.
local KINGS_REST_MAP_ID = 1762
local KINGS_REST_DUNGEON_KEY = "KingsRest"
local KINGS_REST_ROOM = "Sepulcher of the Dahazi"

-- The core's providers, built once per observation start.
function DTrash:BuildKingsRestEnv()
    local waveRows = {}
    for _, row in ipairs(self:TrashTraitIndex()[KINGS_REST_DUNGEON_KEY] or {}) do
        local id = row.trait and row.trait.identity
        if id and id.groupHasLevel90 ~= nil then waveRows[row.npcID] = true end
    end
    return {
        holds = function(owner) return TI.RecoveryOwnerHolds(owner, self.tracked, self.monitoring) end,
        resolve = function(owner) self:ResolveMob(owner.runtime) end,
        -- The ready read: one event read opportunity, then the one resolve pass.
        refresh = function(owner)
            self:EventIdentityRead(owner.runtime)
            self:ResolveMob(owner.runtime)
        end,
        state = function(owner) return owner.runtime.obs, owner.runtime.obsPending end,
        compatible = function(obs)
            return TI.IdentityCompatibleRows(obs, KINGS_REST_DUNGEON_KEY, { traitIndex = self:TrashTraitIndex() })
        end,
        waveRows = waveRows,
        familyGate = TI.FAMILY_GATE,
    }
end

-- Map and room scope, re-derived at every zone-state refresh. Entering map
-- 1762 while monitoring starts observation; a zone-text change ends the batch
-- generation and keeps the history.
function DTrash:RefreshKingsRestScope()
    self:CurrentDungeonKey()
    if not (self.monitoring and self.currentMapID == KINGS_REST_MAP_ID) then
        self:StopKingsRest()
        return
    end
    if not self.kr then
        self.kr = KR.New()
        self.krEnv = self:BuildKingsRestEnv()
        self.krStartedAt = GetTime()
        KR.Start(self.kr, self.krStartedAt)
    elseif self.zoneText ~= self.krZoneText then
        KR.ResetBatch(self.kr, self.krEnv)
    end
    self.krZoneText = self.zoneText
    self.krInRoom = self.zoneText == KINGS_REST_ROOM
end

-- Monitor stop, disable or leaving the map: held members are released (a
-- live owner resolves normally), grants stand, and the history is wiped.
function DTrash:StopKingsRest()
    if self.kr then KR.Stop(self.kr, self.krEnv) end
    self.kr, self.krEnv, self.krZoneText, self.krInRoom = nil, nil, nil, nil
end

-- An ended plate generation, after its owner was marked dead: a held member
-- releases its batch, then the generation's removal entry is written (none
-- for its own confirmed death).
function DTrash:KingsRestGenerationEnded(rt, now)
    local st = self.kr
    if not st then return end
    KR.MemberGone(st, rt.owner, self.krEnv)
    KR.RecordRemoval(st, rt.owner, now, rt.obs, rt.matchedNPCID,
        rt.obs and self.krEnv.compatible(rt.obs))
end

-- Before a fresh runtime exists: an overdue join close at the add time, then
-- the replaced generation's release and entry.
function DTrash:KingsRestBeforeAdd(old, now)
    local st = self.kr
    if not st then return end
    KR.ApplyOverdueClose(st, now, self.krEnv)
    if old then self:KingsRestGenerationEnded(old, now) end
end

-- Enrolls a fresh generation by its add time. The first member requests the
-- batch's two timers, each guarded by this core state and the generation.
function DTrash:KingsRestEnroll(owner, now)
    local st = self.kr
    if not st then return end
    local result, gen = KR.OnAdd(st, owner, now, self.krInRoom == true, self.krEnv)
    -- Why a capture's history is unknown, for the dump: within the
    -- lookback of this observation start, or else past an overflow's endpoint.
    if owner.krCapture and owner.krCapture.unknown then
        owner.krCaptureCause = (now <= self.krStartedAt + KR.LOOKBACK) and "observation start" or "overflow"
    end
    if result ~= "opened" then return end
    C_Timer.After(KR.JOIN_WINDOW, function()
        if self.kr == st then KR.JoinClose(st, gen, self.krEnv) end
    end)
    C_Timer.After(KR.READY_DELAY, function()
        if self.kr == st then KR.ReadyCheck(st, gen, self.krEnv) end
    end)
end

-- ── Nameplate tracking ─────────────────────────────────────────────────────

function DTrash:OnNameplateAdded(_, unit)
    -- Assignment form (like every other handler): narrows the event arg to
    -- the validated string for everything below, editor type-checker included.
    unit = normalizeNameplate(unit)
    if not unit then return end
    if not isHostilePlate(unit) then
        -- A friendly or dead occupant on a still-tracked token is that
        -- generation's removal: it ends through the removal path.
        if self.tracked[unit] then self:OnNameplateRemoved(nil, unit) end
        return
    end
    local now = GetTime()
    local inCombat = safeBool(UnitAffectingCombat, unit)
    -- A fresh add on a token still tracked ends the old generation first.
    local old = self.tracked[unit]
    if old and old.owner then old.owner.live = false end
    -- Kings' Rest: an overdue join close, then the replaced generation's
    -- release and removal entry, all before the fresh runtime exists.
    self:KingsRestBeforeAdd(old, now)
    -- One owner per plate generation: the scheduled reads and every
    -- owner-bound callback check it, and it moves with a cache adoption.
    local owner = { live = true, scheduled = 0 }
    local rt = {
        unit = unit,
        owner = owner,
        -- This generation's cast ownership: observation records, departed
        -- IDs, recovery state and counting window.
        castState = TI.NewCastState(owner),
        firstSeenAt = now,
        -- engagedAt = the FIRST moment the mob shows combat evidence — NOT
        -- plate-add: render range isn't engagement, and seeding first-cast
        -- timers per visible plate lit up the whole room (a since-reverted
        -- design). Stamped once here (mid-pull render), or later by
        -- MarkEngaged's evidence sites (UNIT_FLAGS flip, in-combat
        -- UNIT_TARGET, cast start).
        engagedAt = (inCombat == true) and now or nil,
        -- Seed the target-presence state so OnUnitTarget can detect the FIRST
        -- exists→not-exists transition.
        targetStateExists = safeBool(UnitExists, unit .. "target"),
    }
    owner.runtime = rt
    self.tracked[unit] = rt
    -- The add's combat read feeds the counting-window edge.
    self:CombatEdge(rt, inCombat)
    self:NoteNameplateAddedForCache(unit)
    self:KingsRestEnroll(owner, now)
    C_Timer.After(SNAPSHOT_DELAY, function() self:ScheduledIdentityRead(owner) end)
end

function DTrash:OnNameplateRemoved(_, unit)
    unit = normalizeNameplate(unit)
    if not unit then return end
    local rt = self.tracked[unit]
    self.tracked[unit] = nil
    -- The plate generation ends: its owner-bound callbacks are refused from
    -- here on, even if the cache later reinstalls this table.
    if rt and rt.owner then rt.owner.live = false end
    -- Kings' Rest: batch release, then the removal entry, before the
    -- cache branch, so every ending is recorded whatever the cache does.
    if rt then self:KingsRestGenerationEnded(rt, GetTime()) end
    -- On-plate icons anchor to the physical plate — they always hide with it.
    if self.HideNameplateMarker then self:HideNameplateMarker(unit) end
    -- TrashCache flicker recovery: a resolved runtime is held for the restore
    -- window instead of being torn down, and its CENTRAL alerts deliberately
    -- keep counting through the window. The cache sweeps them iff no restore
    -- lands.
    if rt and self:CacheRemovedRuntime(unit, rt) then return end
    -- Scope the teardown to the departing runtime's OWN identity (alert keys
    -- embed npcID): a token recycled inside the cache window may still owe a
    -- PREVIOUS mob's counting bars to a pending restore, and an unscoped
    -- sweep here killed them. Cancels must stay runtime-scoped, never
    -- token-scoped. An unresolved runtime owns no
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

-- The per-dungeon trait index, built once per trait table.
function DTrash:TrashTraitIndex()
    local traits = KE.TrashTraits or {}
    if self._traitIndexFor ~= traits then
        self._traitIndex = TI.BuildTraitIndex(traits)
        self._traitIndexFor = traits
    end
    return self._traitIndex
end

-- Co-presence evidence for one resolve pass: the npcIDs of the other tracked
-- runtimes TI.CompanionTrusted accepts. Derived from the tracked set, so a
-- removal, death, flip or stop drops an entry by itself. A generation whose
-- owner no longer holds never vouches: a replaced plate is still tracked
-- while its add processes an overdue join close. One pass over at most
-- MAX_NAMEPLATES plates, per resolve pass, never per frame.
function DTrash:TrustedCompanions(rt)
    local out = {}
    for _, other in pairs(self.tracked) do
        if other ~= rt and TI.RecoveryOwnerHolds(other.owner, self.tracked, self.monitoring)
            and TI.CompanionTrusted(other) then
            out[other.matchedNPCID] = true
        end
    end
    return out
end

-- Layer1: fingerprint the mob → candidates. Re-run whenever behavior flags
-- change (a seen cast/channel/interrupt refines the candidate set).
function DTrash:ResolveMob(rt)
    -- Behavior-contradiction unlock, KEEP-LOCKED form: a locked in-combat
    -- runtime is retained whenever re-derivation fails, so in-flight spells and
    -- local CDs are not cleared out from under the player. A HARD capability
    -- contradiction -- a kicked cannotInterrupt
    -- row (the Maisara hexxer wore Rokh'zal's timers through repeated kicks),
    -- or a cast/channel from a row without that capability — no longer drops
    -- the identity up front. It only ARMS the unlock: the flip commits below
    -- iff this pass re-derives a DIFFERENT mob. When every row rejects, the
    -- identity and its output are KEPT — field case (Algeth'ar):
    -- Shadowmeld breaking a Vicious Ambush cast still latched sawInterrupted
    -- AFTER the FAILED deviation shipped, so INTERRUPTED is the remaining
    -- latch path for a melded cast; all five Academy rows are cannotInterrupt,
    -- one such latch rejected them ALL, and the old eager drop blanked the
    -- plate's timers for good. This mirrors ScoreTraitRow's behavior gates
    -- EXACTLY; placement, level and classification stay ordinary Layer1 inputs,
    -- because transient context must never unlock.
    -- A runtime without a snapshot (rt.obs nil) can't re-derive, so it keeps
    -- its identity too -- the deliberate cost of keep-locked, where the old
    -- eager drop used to self-heal.
    local contradicted = false
    if rt.matchedNPCID then
        local trait = KE.TrashTraits and KE.TrashTraits[rt.matchedNPCID]
        local id = trait and trait.identity
        if id and TI.BehaviorContradicts(id, rt) then
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

    local cands, resolved, pending = TI.BuildCandidates(obs, {
        traitIndex = self:TrashTraitIndex(),
        dungeonKey = dungeonKey,
        mapID = self.currentMapID,                 -- instance map (data key + Academy exemption)
        bossProgressIndex = self.bossProgressIndex,
        currentSubZoneMapID = self.subZoneMapID,
        currentZoneText = self.zoneText,
        resolveAreaName = areaNameLookup,
        forcesPercent = self.forcesPercent,        -- nil when unknown, never 0 (nil skips the Academy prune)
        inBossEncounter = self.inBossEncounter == true,
        roomText = self.zoneText,                  -- the normalized minimap text
        sawPreCombatChannel = rt.sawPreCombatChannel,
        trustedCompanions = self:TrustedCompanions(rt),
    })
    rt.candidates = cands
    -- Recovery state, written by every pass that scores the snapshot
    -- and before the cache consult, so an adoption in this pass carries it.
    rt.obsPending = pending
    -- Kings' Rest: a held batch member keeps building candidates and
    -- its recovery state, but gets no identity and consults no cache.
    if KR.HoldsIdentity(rt.owner) then return end
    -- A granted contributor's candidates pass its batch's frozen summary (room
    -- rows only); the lone-survivor rule then resolves on what remains.
    local withoutSummary, summaryRemoved, unpruned = resolved, false, nil
    local summary = KR.SummaryFor(rt.owner)
    if summary then
        unpruned = cands
        cands, summaryRemoved = KR.ApplySummary(cands, summary,
            function(npcID) return KE.TrashTraits and KE.TrashTraits[npcID] end)
        rt.candidates = cands
        resolved = (#cands == 1 and cands[1].levelAgreed and not cands[1].incomplete)
            and cands[1].npcID or nil
    end
    -- Layer 2 judges this pass's list; it keeps the list the summary pruned,
    -- so a cast can tell whether its result rests on the summary.
    rt.unsummarizedCandidates = summaryRemoved and unpruned or nil
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
        -- over (see TrashCache.lua). The cache is consulted at this exact
        -- point: post-resolve, pre-assignment, never at plate add.
        if rt.matchedNPCID == nil and not rt._cacheRestoredAt then
            local adopted = self:TryRestoreCachedRuntime(rt, resolved, rt._resolveSite or "resolve")
            if adopted then
                adopted.layer1Resolved = true  -- this pass resolved it at Layer 1
                return
            end
        end
        -- Identity FLIP (Layer1 re-resolving mob A → B): cancel A's armed
        -- output BEFORE adopting B. A full cancel and rebuild is required
        -- whenever the resolved candidate changes: the enterSeeded latch would
        -- otherwise leave A's bars, deferred reveals and plate predictions live
        -- and make B's first-cast timers permanently unseedable. Every anchor
        -- is keyed by A's spellIDs, so the whole
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
    -- Layer 1 trust for co-presence: only while this pass resolves the
    -- current identity as a complete, level-agreed lone survivor.
    rt.layer1Resolved = (resolved ~= nil and resolved == rt.matchedNPCID) or nil
    -- Wave-derived: the identity rests on the summary's pruning until a
    -- pass without the summary resolves the same NPC.
    rt.waveDerived = KR.WaveDerivedAfter(rt.waveDerived, rt.matchedNPCID, withoutSummary,
        summaryRemoved and resolved ~= nil and resolved == rt.matchedNPCID) or nil
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

-- Player combat edge: sweep every tracked plate. Full identity inference re-runs
-- for all visible plates on PLAYER_REGEN_DISABLED/ENABLED, and the engagedAt
-- stamp rides every in-combat refresh, so this catches a mob
-- whose own UNIT_FLAGS edge was lost in the pull's event storm and a plate
-- whose one snapshot was Layer1-ambiguous and never casts. castConfirmed
-- stickiness + the enterSeeded latch + MarkEngaged's once-only stamp make the
-- sweep idempotent for already-settled runtimes.
function DTrash:OnPlayerCombatChanged()
    for unit, rt in pairs(self.tracked) do
        -- One combat read per plate per edge, unconditional, feeding the
        -- counting-window edge.
        local inCombat = safeBool(UnitAffectingCombat, unit)
        self:CombatEdge(rt, inCombat)
        if not rt.engagedAt and inCombat == true then
            self:MarkEngaged(rt)
        end
        -- One event read opportunity, then the one resolve pass; nothing
        -- further runs on this runtime after it.
        self:EventIdentityRead(rt)
        self:ResolveMob(rt)
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
-- 12.0 leaves us (declared NeverSecret, and probe-confirmed in game).
-- It identifies a castbar INSTANCE, never the spell: START and end
-- correlation, duplicate-START refusal and the departed-ID history run on it
-- (TI.ClassifyStart, TI.ClassifyEnd). It is opaque: compared only with ==,
-- never converted, ordered, used as a key or printed outside the debug flag.
-- Guarded anyway: first contact is issecretvalue.
local function safeCastBarID(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Mirrors the latest observation into the runtime fields the start
-- cue, the forced sequence and the dump still read. Only an eligible, open,
-- uncanceled and unretired observation shows as an active cast; samples and
-- readiness follow the latest eligible record; the pending advance shows its
-- own time and kind. The records stay the only source of truth.
function DTrash:SyncActiveCast(rt)
    local cs = rt.castState
    local rec = cs and cs.latest
    local eligible = rec ~= nil and rec.eligible == true
    local live = eligible and rec.open == true and not rec.canceled and not rec.retired
    rt.activeCastKind = live and rec.kind or nil
    rt.activeCastStartAt = live and rec.startAt or nil
    rt.activeCastBarID = live and rec.id or nil
    if eligible and rec.seq then rt.activeCastSeq = rec.seq end
    rt.transitionCastStartAt = live and rec.transitionCastStartAt or nil
    local fp = (eligible and rec.fingerprints) or nil
    rt.fpTargetExists = fp and fp.targetExists
    rt.fpTargetAPIExists = fp and fp.targetAPIExists
    rt.fpCastStartChangeTarget = fp and fp.castStartChangeTarget
    rt.fpTargetClearOnCastStart = fp and fp.targetClearOnCastStart
    rt.fpTargetIsTank = fp and fp.targetIsTank
    rt.startFingerprintsReady = (eligible and rec.fingerprintsReady) or nil
    local adv = cs and cs.pendingAdvance
    rt.pendingStartAdvanceAt = adv and adv.at or nil
    rt.pendingStartAdvanceKind = adv and adv.kind or nil
end

-- Whether any trait row of the current dungeon carries preCombatChanneling:
-- pre-combat channel presence is read only then. One pass over that
-- dungeon's rows, per out-of-combat channel START only.
function DTrash:DungeonUsesPreCombatChannel()
    local key = self:CurrentDungeonKey()
    local rows = key and self:TrashTraitIndex()[key]
    for _, row in ipairs(rows or {}) do
        local id = row.trait and row.trait.identity
        if id and id.preCombatChanneling ~= nil then return true end
    end
    return false
end

-- One counting-window edge. Only a known non-secret boolean asserts
-- anything. A close retires that window's unfinished cast work, so its
-- records leave the work list and the mirror drops a retired cast.
function DTrash:CombatEdge(rt, inCombat)
    local cs = rt and rt.castState
    if not cs or type(inCombat) ~= "boolean" then return end
    local step = TI.CombatWindowStep(cs, inCombat)
    if step == "opened" and not cs.window.known then
        -- Why this window's order is unknown, for the dump.
        cs.window.unknownWhy = (not cs.seenFalse and "first seen in combat")
            or (cs.recovery == "saturated" and "saturated") or "lifecycle crossed in"
    end
    if step ~= "closed" then return end
    local kept = {}
    for _, rec in ipairs(cs.records) do
        if rec.retired then
            self:CloseTargetEvidence(rt, rec, "retirement")
        else
            kept[#kept + 1] = rec
        end
    end
    cs.records = kept
    if cs.latest and cs.latest.retired then self:CloseTargetEvidence(rt, cs.latest, "retirement") end
    self:SyncActiveCast(rt)
end

-- ── Target evidence ────────────────────────────────────────────────────────
-- One pending-to-final state per collecting cast record. The first UNIT_TARGET
-- handled after its START commits it; its close timer, its correlated end,
-- interrupt or failure, its replacement, retirement or cancellation closes it
-- unavailable. Unavailable is never written as absent.

-- One read pair at event time, each under its own pcall with issecretvalue as
-- first contact (guardedValue). UnitCanAttack runs only on a known-present
-- target. Returns the normalized reading and, for unavailable, its cause.
local function readTargetEvidence(unit)
    local target = unit .. "target"
    local existsOk, exists, existsSecret = guardedValue(pcall(UnitExists, target))
    local attackOk, attack, attackSecret = false, nil, false
    if existsOk and exists == true then
        attackOk, attack, attackSecret = guardedValue(pcall(UnitCanAttack, "player", target))
    end
    local reading = TI.NormalizeTargetEvidence(existsOk, exists, existsSecret, attackOk, attack, attackSecret)
    local cause
    if reading == "unavailable" then cause = (existsSecret or attackSecret) and "secret" or "read" end
    return reading, cause
end

local function castRowCarriesTarget(mob)
    for _, sp in pairs(mob and mob.spells or {}) do
        if sp.targetHostile ~= nil
            and ((tonumber(sp.castTime) or 0) > 0 or type(sp.castTimeExtra) == "table") then
            return true
        end
    end
    return false
end

-- Whether a cast START on this runtime collects target evidence: the matched
-- mob or a surviving candidate has a cast row carrying targetHostile.
function DTrash:NeedsTargetEvidence(rt)
    if rt.matchedNPCID and castRowCarriesTarget(self:MobData(rt.matchedNPCID)) then return true end
    for _, c in ipairs(rt.candidates or {}) do
        if castRowCarriesTarget(self:MobData(c.npcID)) then return true end
    end
    return false
end

-- Opens a normal START's state: pending when it collects, otherwise
-- "not-collected". A collecting record and the advance it armed wait for the
-- final state; one close timer, start-phase work bound to owner and record.
function DTrash:OpenTargetEvidence(rt, rec, collect)
    TI.TargetEvidenceStep(rec, { kind = "open", collect = collect })
    local pending = rec.targetState == "pending"
    rec.targetNeeded = pending or nil
    local adv = rt.castState.pendingAdvance
    if adv and adv.record == rec then
        adv.targetNeeded, adv.targetState = rec.targetNeeded, rec.targetState
    end
    if not pending then return end
    local owner = rt.owner
    C_Timer.After(TARGET_CHANGE_WINDOW, function()
        if not TI.CastCallbackHolds(owner, self.tracked, self.monitoring, rec, "start") then return end
        self:CloseTargetEvidence(owner.runtime, rec, "timer")
    end)
end

-- A final state's consumers, run once: the pending advance this record armed
-- takes the state, a deferred cue evaluates, and the advance may apply.
function DTrash:FinishTargetEvidence(rt, rec, commit, cause)
    rec.targetCommit, rec.targetCause = commit, cause
    local adv = rt.castState and rt.castState.pendingAdvance
    if adv and adv.record == rec then adv.targetState = rec.targetState end
    if self.ResumeObservedCastStartCue then self:ResumeObservedCastStartCue(rt, rec) end
    self:ApplyPendingStartAdvance(rt)
end

-- Closes a pending window as unavailable; a final or uncollected one is left.
function DTrash:CloseTargetEvidence(rt, rec, cause)
    if rec and TI.TargetEvidenceStep(rec, { kind = "close" }) then
        self:FinishTargetEvidence(rt, rec, "close", cause)
    end
end

-- The UNIT_TARGET step: the first change handled while the latest record is
-- pending commits it. At most one read pair, only then; a change reaching a
-- final record is counted and changes nothing.
function DTrash:TargetEvidenceChange(rt)
    local cs = rt.castState
    local rec = cs and cs.latest
    if not rec then return end
    if rec.targetState ~= "pending" then
        if rec.targetCommit then rec.targetIgnored = (rec.targetIgnored or 0) + 1 end
        return
    end
    if not TI.CastCallbackHolds(rt.owner, self.tracked, self.monitoring, rec, "start") then return end
    local reading, cause = readTargetEvidence(rt.unit)
    if TI.TargetEvidenceStep(rec, { kind = "change", reading = reading }) then
        self:FinishTargetEvidence(rt, rec, "change", cause)
    end
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

-- Every UNIT_TARGET on a tracked, in-combat plate records a switch timestamp;
-- an exists→not-exists transition additionally records a clear. ONLY that
-- transition direction is appended; targetStateExists is seeded at plate add. All reads
-- are pcall-guarded booleans; a secret/unreadable state just leaves the
-- fingerprint unsampled (nil = never a false match).
function DTrash:OnUnitTarget(_, unit)
    unit = normalizeNameplate(unit)
    local rt = unit and self.tracked[unit]
    if not rt then return end
    local inCombat = safeBool(UnitAffectingCombat, unit)
    -- The edge decision comes before the early return, so a known false here
    -- closes a counting window too.
    self:CombatEdge(rt, inCombat)
    -- Target evidence: after the edge decision, not gated on combat.
    self:TargetEvidenceChange(rt)
    if inCombat ~= true then return end
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
-- portion.
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
    if not (rt and rt.castState) then return end
    castBarID = safeCastBarID(castBarID)
    local now = GetTime()
    -- Combat read first: the START that engages a mob opens its counting
    -- window in this same call, before the START is classified.
    local inCombat = safeBool(UnitAffectingCombat, unit)
    self:CombatEdge(rt, inCombat)
    local cs = rt.castState
    local prior = cs.latest
    -- Every START is classified before it has any cast effect: a
    -- duplicate is ignored, a refresh continues its channel, and only a
    -- normal START creates an eligible observation.
    local class, rec = TI.ClassifyStart(cs, kind, castBarID, now,
        isChannelRefreshContinuation(rt, kind, castBarID))
    if class == "duplicate" then
        -- A repeat of a departed ID, not of the open observation, is counted
        -- per kind for the dump; the ID itself is never kept.
        if not (prior and prior.open and prior.kind == kind and prior.id == castBarID) then
            cs.departedRepeats = cs.departedRepeats or { cast = 0, channel = 0 }
            cs.departedRepeats[kind] = cs.departedRepeats[kind] + 1
        end
        return
    end
    -- An unowned or baseline START makes the window's order unknown; the dump
    -- names the first reason. Once saturated, saturation is the reason.
    local w = cs.window
    if w and not w.known and not w.unknownWhy and cs.recovery ~= "saturated" then
        w.unknownWhy = (class == "unowned" and "unowned START")
            or (class == "baseline" and "baseline START") or nil
    end
    -- A refresh consumes its stamped window, and any other START invalidates it.
    rt.channelRefreshAt = nil
    if class == "refresh" then
        self:SyncActiveCast(rt)
        dprint(tostring(unit) .. ": channel refresh (interruptible) — continuation, anchor kept")
        return
    end
    -- The replaced observation's target-evidence window closes before this
    -- START arms anything.
    if prior and prior ~= rec then
        self:CloseTargetEvidence(rt, prior, prior.canceled and "cancellation" or "replacement")
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
        dprint(string_format("%s: %s start castGUID=%s (%s)", tostring(unit), kind, guid, class))
    end
    -- Transition proof: a normal channel is the channel phase of the
    -- cast it replaced, or of the cast whose own STOP just landed, only when
    -- TI.ProveCastIntoChannel finds an explanation. The proof marks that cast
    -- paired, so its held one-phase credit discards itself.
    local proven
    if class == "normal" and kind == "channel" and prior and prior.kind == "cast" then
        local proof = TI.ProveCastIntoChannel(prior, {
            owner = rt.owner, matchedNPCID = rt.matchedNPCID, candidates = rt.candidates,
            fingerprints = prior.fingerprints,
        }, function(npc) return self:MobData(npc) end,
        function(npc) return KE.TrashTraits and KE.TrashTraits[npc] end, now)
        if proof then
            proven = prior
            prior.paired = true
            rec.transitionCastStartAt = proof.castStartAt
            rt.sawCastIntoChannel = true
            dprint(tostring(unit) .. ": cast->channel proven — channel anchors at cast start")
        end
    end
    -- Opening order, decided once; a proven channel inherits its cast's.
    TI.AssignOrder(cs, rec, proven)
    if class == "normal" then
        rec.fingerprints = {}
        if proven then
            -- The cast phase owns this cycle's start anchor.
            cs.pendingAdvance = nil
        else
            -- Only an eligible observation arms a start advance; it carries
            -- this record's own samples.
            cs.pendingAdvance = { record = rec, provenance = "fresh", at = now, kind = kind,
                fingerprints = rec.fingerprints }
        end
    end
    -- Mob-level effects of every non-duplicate START.
    if kind == "cast" then
        rt.sawCastStart = true
    else
        rt.sawChannelStart = true
    end
    -- Pre-combat channel presence: read only on this START's own
    -- combat read being a known false, and only where a trait uses it.
    if kind == "channel" and inCombat == false and self:DungeonUsesPreCombatChannel() then
        rt.sawPreCombatChannel = true
    end
    self:SyncActiveCast(rt)
    self:MarkEngaged(rt)  -- a cast IS engagement proof (the old reactive model's whole premise)
    -- One event read opportunity, before this START's one resolve pass.
    self:EventIdentityRead(rt)

    rt._resolveSite = "start"  -- an adoption in this pass is the early site
    self:ResolveMob(rt)  -- behavior flag may prune candidates
    rt._resolveSite = nil
    -- An adoption in that pass moved this START's record with its owner; the
    -- rest runs on the owner's current runtime.
    rt = rt.owner.runtime
    self:SyncActiveCast(rt)
    if class ~= "normal" then return end

    -- Only a normal cast START collects, and only when a remaining row needs it.
    self:OpenTargetEvidence(rt, rec, kind == "cast" and self:NeedsTargetEvidence(rt))
    local owner = rt.owner
    C_Timer.After(TARGET_SAMPLE_DELAY, function()
        -- Start-phase work, bound to its owner and record: refused once a
        -- later START replaced the record or the plate generation ended. It
        -- acts on the owner's current runtime, which follows an adoption.
        if not TI.CastCallbackHolds(owner, self.tracked, self.monitoring, rec, "start") then return end
        local r = owner.runtime
        local fp = rec.fingerprints
        fp.targetExists = safeBool(UnitExists, r.unit .. "target")
        if UnitShouldDisplaySpellTargetName then
            fp.targetAPIExists = safeBool(UnitShouldDisplaySpellTargetName, r.unit)
        end
        -- targetIsTank (dormant fingerprint, mapped for future data): the
        -- mob's target is a PLAYER unit, whose role is plain — still guarded.
        local okRole, role = pcall(UnitGroupRolesAssigned, r.unit .. "target")
        if okRole and canaccessvalue(role) and type(role) == "string" then
            fp.targetIsTank = (role == "TANK")
        end
        -- Scan the target rings ± the window around the ANCHORED start — the
        -- switch and clear-transition lookups both run in this same +0.10s
        -- snapshot, window = startAt ± 0.10.
        fp.castStartChangeTarget = hasEventInWindow(r.targetSwitchEvents,
            rec.startAt - TARGET_SAMPLE_DELAY, rec.startAt + TARGET_SAMPLE_DELAY)
        fp.targetClearOnCastStart = hasEventInWindow(r.targetClearEvents,
            rec.startAt - TARGET_SAMPLE_DELAY, rec.startAt + TARGET_SAMPLE_DELAY)
        -- Start fingerprints are now as sampled as they will get; the advance
        -- this record armed carries the same samples.
        rec.fingerprintsReady = true
        local adv = r.castState.pendingAdvance
        if adv and adv.record == rec then adv.fingerprintsReady = true end
        self:SyncActiveCast(r)
        self:ApplyPendingStartAdvance(r)
    end)

    -- Observed-cast-start cue: anchored HERE, at the real cast bar — never at
    -- countdown-zero, which is only the prediction. Deferred one cue window
    -- (0.12s) INSIDE the output layer so the +0.10s sampler above lands first
    -- and the sampled start fingerprints can filter the pick — scheduled
    -- after the sampler so timer order matches delay order. Output-layer
    -- method, guarded like the other output seams (TrashOutput loads after
    -- this file).
    if self.PlayObservedCastStartCue then self:PlayObservedCastStartCue(rt, rec) end
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
-- dangles — but NO sawInterrupted behavior evidence. Latching the same sticky
-- sawInterrupted a real kick sets is field-broken (verified in Algeth'ar
-- Academy) because the Layer1 filter then
-- hard-rejects cannotInterrupt rows on it: a
-- FAILED proves NOTHING about interruptibility (Riftbreath canceled by its
-- target's Shadowmeld cannot be kicked at all), yet one abort permanently
-- rejected every Academy trait row (all five are cannotInterrupt) on that
-- plate: unresolved mobs never gained timers, and a resolved Ravager hit the
-- contradiction unlock and never re-resolved. sawInterrupted stays a
-- genuine-kick latch: UNIT_SPELLCAST_INTERRUPTED only — the interruptedBy-
-- correlated channel stop was removed from it too (the channel-phase twin of
-- this same Shadowmeld failure; see FinishCast), so a channel-stop interrupt
-- never reaches the Layer1 filter.
function DTrash:OnCastFailed(_, unit, _castGUID, _spellID, castBarID)
    self:MarkCastInterrupted(unit, castBarID, true)
end

-- Shared interrupt-shaped lifecycle end (INTERRUPTED / FAILED /
-- FAILED_QUIET). Only an event correlating with the latest observation ends
-- it: INTERRUPTED is known to double-fire, and a late event for a
-- PREVIOUS castbar arriving after a new START must not kill the live cast.
-- A refused event only voids an open cast's implied stop. Any INTERRUPTED,
-- correlated or not, latches kick evidence (the flag prunes cannotInterrupt
-- candidates either way); FAILED events latch nothing (see OnCastFailed for
-- the documented deviation).
function DTrash:MarkCastInterrupted(unit, castBarID, castFailed)
    unit = normalizeNameplate(unit)
    local rt = unit and self.tracked[unit]
    if not (rt and rt.castState) then return end
    -- The kind matters only for a STOP; an interrupt or failure correlates on
    -- the bar ID alone.
    local rec = rt.castState.latest
    local outcome, latch = TI.ClassifyEnd(rt.castState, nil, safeCastBarID(castBarID),
        castFailed and "failed" or "interrupted", GetTime())
    -- A correlated interrupt or failure closes its target-evidence window.
    if outcome == "correlated" then
        self:CloseTargetEvidence(rt, rec, castFailed and "failure" or "interrupt")
    end
    if latch then rt.sawInterrupted = true end
    -- Interrupt evidence IS engagement evidence: engagedAt is stamped on the
    -- first sawInterrupted observation — before ResolveMob below
    -- so a resolution there can seed first-cast timers immediately.
    self:MarkEngaged(rt)
    self:SyncActiveCast(rt)
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
-- spellID / castBarID — UnitDocumentation confirms), so no castBarID gate is
-- possible here. The active-channel kind/seq checks below are the real
-- correlation.
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
        -- proximity term. Scoring runs against the predicted NEXT start, never
        -- the previous one.
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
    -- A start-advance-owned CAST_START channel was already anchored at its
    -- observed START, so the success path must not credit it a second time.
    if TI.IsStartAdvanceOwned(spellData) then return end
    -- The caster's CHANNEL_STOP fires when its cast bar closes, which for
    -- grab/beam mechanics is far short of the ability's real channelTime, so
    -- the STOP is an unreliable success time. Reconstruct the true effect end
    -- from the reliable channel START + curated channelTime. (CAST_START-mode
    -- spells ignore successAt and anchor at the start.)
    local successAt = now
    local ct = tonumber(spellData.channelTime)
    if ct then successAt = startAt + ct end
    -- A proven transition anchors at the TRUE cast start: transitionCastStartAt
    -- wins whenever it is set.
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
    -- A curated forced-sequence pick outranks inference: the forced spellID is
    -- consulted before any duration/schedule scoring,
    -- validity-guarded against the mob's own spell table so a bad curated
    -- index can never emit an unknown spellID.
    local spellID = observed.forcedSpellID
    if not (spellID and mob.spells and mob.spells[spellID]) then
        -- ONE-phase spells only — cast-kind success inference skips
        -- channel-capable spells: a completed bare cast is never
        -- credited as a two-phase ability — that spell is credited exclusively
        -- from its channel phase, anchored at the true cast start via the
        -- transition proof.
        spellID = TI.InferSucceededSpell(mob, observed, rt.anchors, now, true)
    end
    if not spellID then
        debugUnmatched(rt.unit, mob, "cast", observed.duration)
        -- The mob is RESOLVED even though this cast defied inference: arm the
        -- enter schedules of its not-yet-anchored spells. Schedules arm on
        -- every resolved in-combat refresh, independent of any single cast's
        -- inference outcome. No-op once seeded.
        self:SeedFirstCasts(rt)
        return
    end
    -- Same start-advance guard as creditFinishedChannel above: don't credit twice.
    if TI.IsStartAdvanceOwned(mob.spells and mob.spells[spellID]) then return end
    self:EmitCastResolution(rt, mob, spellID, startAt, stopAt, now, "cast", observed.duration)
end

-- Reset the target-state sampler on a unit's combat FLIP — every per-unit
-- combat transition resets it. Entering
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
-- seeding (no-op unless the mob is already resolved). engagedAt is stamped at
-- every evidence site — the in-combat snapshot check, the behavior marks, and
-- the first cast/channel start — and is never cleared.
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
-- countdown (first, rolled forward if we joined late). Scheduling is gated on
-- UnitAffectingCombat. The whole-room seeding spam is
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
-- Arms are one-shot, so a spell disabled mid-dungeon consumed its armed
-- output at fire time and nothing re-read the still-correct anchors; this
-- re-registers every schedule from the persisted anchors on each config
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

-- Consume the pending CAST_START start advance: anchor the one
-- start-advance-owned spell its observed START matches, at that START.
-- Interrupts EXPLICITLY cannot cancel it: success-mode inference returns nil
-- for CAST_START, so start-advance is their only anchor path. It is gated on
-- resolution and on its own carried samples, only where the mob needs them;
-- a cached advance never borrows fresh samples. Exactly one match
-- anchors. None or several keep it until a later pass, the next
-- eligible START, or an unowned START that cancels it.
function DTrash:ApplyPendingStartAdvance(rt)
    local cs = rt.castState
    local adv = cs and cs.pendingAdvance
    if not (adv and rt.matchedNPCID) then return end
    local mob = self:MobData(rt.matchedNPCID)
    if not (mob and mob.spells) then return end
    if not TI.PendingAdvanceReady(adv, TI.NeedsStartFingerprints(mob)) then return end
    -- A fresh advance selects by its record's opening order; a cached one
    -- carries none.
    local order = (adv.provenance == "fresh" and adv.record and adv.record.order) or nil
    local spellID = TI.SelectStartAdvance(mob, adv.kind, adv.fingerprints or {}, order,
        adv.targetState, TI.ABSENT_MATCHES_FALSE)
    if not spellID then return end
    cs.pendingAdvance = nil
    self:SyncActiveCast(rt)
    self:EmitCastResolution(rt, mob, spellID, adv.at, adv.at, GetTime(), adv.kind, nil)
end

-- Forced cast-sequence pick, curated per mob in TrashCurated.lua's
-- KE.TrashForcedCastSequences:
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

-- Records that still own delayed cast work: a record joins when a
-- post-end read or a twin hold is queued for it, and leaves through
-- TI.ReleaseIdleWork once that work lands or is canceled, or at retirement.
local function trackWork(cs, rec)
    for _, r in ipairs(cs.records) do
        if r == rec then return end
    end
    cs.records[#cs.records + 1] = rec
end

-- Cast completed successfully → Layer2 (narrow candidates + infer the spell)
-- → calibrate the cd schedule → emit the alert.
function DTrash:FinishCast(unit, kind, interrupted, castBarID)
    unit = normalizeNameplate(unit)
    local rt = unit and self.tracked[unit]
    if not (rt and rt.castState) then return end
    local rec = rt.castState.latest
    local now = GetTime()
    -- Only the latest observation's own correlated end ends anything:
    -- a refused STOP voids only an open cast's implied stop, and a baseline
    -- close or a withheld end has no cast-level effect.
    local outcome = TI.ClassifyEnd(rt.castState, kind, safeCastBarID(castBarID), "stop", now)
    self:SyncActiveCast(rt)
    if outcome ~= "correlated" then return end
    -- The record's correlated end closes a pending target-evidence window
    -- before Layer 2 and credit read it.
    self:CloseTargetEvidence(rt, rec, "end")

    local startAt = rec.startAt
    local duration = now - startAt
    -- A proven transition belongs to its channel record and is spent with it.
    local transitionStartAt = (kind == "channel" and rec.transitionCastStartAt) or nil
    if interrupted then
        -- interruptedBy presence ends the channel WITHOUT a success credit,
        -- but it is NOT Layer1 kick evidence: the channel-stop feeds only the
        -- cast lifecycle, and the Layer1-visible sawInterrupted latches ONLY
        -- from the INTERRUPTED/FAILED events. A Shadowmeld breaking
        -- a channel aimed at the melder would stop it with interruptedBy
        -- present, and a latch here would reject every cannotInterrupt
        -- Academy row exactly like the FAILED latch this module already
        -- reverted (see OnCastFailed).
        return
    end

    -- Channel-evidence discriminator input: TRUE = this channel's
    -- cast→channel transition was PROVEN (two-phase spells only). NEVER
    -- false: a missed proof is indistinguishable from a genuine bare channel,
    -- and a false "false" hard-rejected Chains of Subjugation's channel every
    -- time the pairing missed. Unproven stays nil → lenient.
    local castIntoChannel
    if transitionStartAt then castIntoChannel = true end

    local fp = rec.fingerprints or {}
    local observed = {
        kind = kind,
        duration = duration,
        startAt = startAt,
        -- Engage-anchored first-cast expectation: InferSucceededSpell's
        -- schedule-proximity fallback for a spell with no anchor yet. Falls
        -- back to first-seen when no combat evidence was ever observed.
        engagedAt = rt.engagedAt or rt.firstSeenAt,
        castIntoChannel = castIntoChannel,
        -- This record's opening order selects rows within the mob.
        order = rec.order,
        targetState = rec.targetState,
        fingerprints = {
            targetExists = fp.targetExists,
            targetAPIExists = fp.targetAPIExists,
            castStartChangeTarget = fp.castStartChangeTarget,
            targetClearOnCastStart = fp.targetClearOnCastStart,
            targetIsTank = fp.targetIsTank,
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
        -- without the lock — approximating stateless always-re-derive
        -- semantics.
        local wasLone = (#rt.candidates == 1)
        local kept, resolved = TI.FilterCandidates(rt.candidates, observed, dataByNpc, traitByNpc)
        rt.candidates = kept
        -- Wave-derived: the same cast judged on the list before the
        -- summary pruned it. A result that list does not give rests on the
        -- summary, so it stays untrusted however the cast confirms it.
        local withoutSummary, summaryPruned = resolved, rt.unsummarizedCandidates ~= nil
        if summaryPruned then
            rt.unsummarizedCandidates, withoutSummary = TI.FilterCandidates(rt.unsummarizedCandidates,
                observed, dataByNpc, traitByNpc)
        end
        -- A held Kings' Rest member gets no identity, adoption or
        -- credit from a cast that ends while it is held.
        if resolved and not KR.HoldsIdentity(rt.owner) then
            local levelAgreed = false
            for _, c in ipairs(kept) do
                if c.npcID == resolved then levelAgreed = (c.levelAgreed == true); break end
            end
            -- TrashCache restore consult (mirrors ResolveMob's wiring): a
            -- level-disagreed mob's ONLY resolve path is this Layer2 confirm,
            -- so without a consult here flicker recovery was structurally
            -- unreachable for exactly those mobs. The transfer moves this
            -- record, now completed, with the fresh cast bundle, so the
            -- credit below and its deferred work land on the adopted table.
            if rt.matchedNPCID == nil and not rt._cacheRestoredAt then
                local adopted = self:TryRestoreCachedRuntime(rt, resolved, "layer2")
                if adopted then
                    -- A restore makes the order unknown. Schedule
                    -- proximity scores against the adopted runtime's real
                    -- engage history, not the post-flicker one.
                    observed.order = nil
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
                rt.layer1Resolved = nil
                dprint(string_format("%s: Layer2 identity flip %s -> %s — output rebuilt",
                    unit, tostring(rt.matchedNPCID), tostring(resolved)))
            end
            rt.matchedNPCID = resolved
            -- A result without summary involvement, or one the unpruned list
            -- also gives, clears the mark.
            rt.waveDerived = KR.WaveDerivedAfter(rt.waveDerived, resolved, withoutSummary, summaryPruned) or nil
            -- Resolve-without-lock: an ambiguous bare channel (transition
            -- unprovable, no pure-channel affirmation on the resolved mob)
            -- never earns the lock. Resolve + output arm either way;
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
    -- CAST_START start-advance BEFORE the success inference: pending-start
    -- always applies ahead of pending-finish.
    self:ApplyPendingStartAdvance(rt)

    -- Delayed work below is bound to the generation owner and this record:
    -- a removed plate's held or deferred credit is lost, and each
    -- callback acts on the owner's current runtime.
    local owner = rt.owner
    if kind == "channel" then
        -- Success-side self-buff-count delta rides the CHANNEL stop too — it
        -- is sampled on both kinds; without this, the strict
        -- success rule would make any delta-curating channel spell
        -- permanently uncreditable). Sample-and-defer mirrors the cast path.
        if TI.NeedsSelfBuffCountDelta(mob, "channel") then
            local beforeCount = safeBuffCount(unit)
            local creditNpcID = rt.matchedNPCID
            dprint(unit .. ": channel credit deferred for self buff-count delta")
            rec.postEnd = true
            trackWork(rt.castState, rec)
            C_Timer.After(TARGET_SAMPLE_DELAY, function()
                if not TI.CastCallbackHolds(owner, self.tracked, self.monitoring, rec, "postEnd") then return end
                rec.postEnd = nil
                local r = owner.runtime
                TI.ReleaseIdleWork(r.castState)
                -- A deferred credit lands only under the identity that earned
                -- it: a contradiction-drop or identity flip inside the window
                -- otherwise re-arms the discredited npcID's anchors and alerts
                -- right after resetResolvedOutput swept them.
                if r.matchedNPCID ~= creditNpcID then return end
                if beforeCount ~= nil then
                    local after = safeBuffCount(r.unit)
                    if type(after) == "number" then
                        observed.selfBuffCountDelta = after - beforeCount
                    end
                end
                creditFinishedChannel(self, r, mob, observed, startAt, transitionStartAt)
            end)
            return
        end
        creditFinishedChannel(self, rt, mob, observed, startAt, transitionStartAt)
        return
    end

    -- Forced-sequence pick is resolved NOW, not inside the deferred credit:
    -- the hold/delta closures fire a window later, when a NEW start may
    -- already have moved the active cast sequence past this cast's.
    observed.forcedSpellID = resolveForcedCastSpell(rt, mob)

    -- Bare cast finished. Two reasons can defer the credit:
    --
    -- • selfBuffCountDelta sampling: a before-count at the stop, an after-count
    --   +0.10s; consumption waits on it only when the mob's curated data
    --   carries the field. The
    --   delta splits Phalanx Breaker's twin 5s casts; it cancels any constant
    --   offset, so the raw count is safe.
    --
    -- • Two-phase ambiguity hold: when this duration ALSO fits one of the
    --   mob's TWO-PHASE spells, a proven channel phase about to arrive would
    --   show this was the two-phase cast phase, and an immediate one-phase
    --   credit would be a phantom double-fire. Hold for one pairing window
    --   and discard if a proof marks this cast paired. An unowned channel
    --   START cancels the hold.
    local needsSelfDelta = TI.NeedsSelfBuffCountDelta(mob, "cast")
    local holdForTwin = TI.MatchesTwoPhaseCast(mob, observed)
    if not (needsSelfDelta or holdForTwin) then
        creditFinishedCast(self, rt, mob, observed, startAt, now)
        return
    end
    local beforeCount = needsSelfDelta and safeBuffCount(unit) or nil
    -- A deferred credit lands only under the identity that earned it.
    local creditNpcID = rt.matchedNPCID
    rec.postEnd = needsSelfDelta or nil
    rec.twinHold = holdForTwin or nil
    trackWork(rt.castState, rec)
    local function sampleSelfDelta(r)
        rec.postEnd = nil
        if beforeCount == nil then return end
        local after = safeBuffCount(r.unit)
        if type(after) == "number" then
            observed.selfBuffCountDelta = after - beforeCount
        end
    end
    if holdForTwin then
        dprint(unit .. ": one-phase credit held (two-phase twin possible)")
        if needsSelfDelta then
            -- Sample at the same +0.10s as every other fingerprint even though
            -- the credit itself waits out the longer pairing window.
            C_Timer.After(TARGET_SAMPLE_DELAY, function()
                if TI.CastCallbackHolds(owner, self.tracked, self.monitoring, rec, "postEnd") then
                    sampleSelfDelta(owner.runtime)
                    -- A withheld channel may have canceled the hold already.
                    TI.ReleaseIdleWork(owner.runtime.castState)
                end
            end)
        end
        C_Timer.After(TRANSITION_PAIR_WINDOW, function()
            if not TI.CastCallbackHolds(owner, self.tracked, self.monitoring, rec, "twinHold") then return end
            rec.twinHold = nil
            local r = owner.runtime
            TI.ReleaseIdleWork(r.castState)
            -- A credit waiting on a canceled post-end read is canceled too.
            if rec.postEnd == "canceled" then return end
            if r.matchedNPCID ~= creditNpcID then return end
            if rec.paired then return end  -- proven two-phase; phantom discarded
            creditFinishedCast(self, r, mob, observed, startAt, now)
        end)
        return
    end
    dprint(unit .. ": credit deferred for self buff-count delta")
    C_Timer.After(TARGET_SAMPLE_DELAY, function()
        if not TI.CastCallbackHolds(owner, self.tracked, self.monitoring, rec, "postEnd") then return end
        local r = owner.runtime
        sampleSelfDelta(r)
        TI.ReleaseIdleWork(r.castState)
        if r.matchedNPCID ~= creditNpcID then return end
        creditFinishedCast(self, r, mob, observed, startAt, now)
    end)
end

return DTrash
