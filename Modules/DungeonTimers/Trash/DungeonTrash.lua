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
-- ║  PHASE 2: detection + DEBUG_DTRASH logging only. Output  ║
-- ║  (central alerts, on-plate icons) is wired in Phase 3/4  ║
-- ║  at the marked seam in FinishCast.                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DungeonTrash: AceModule, AceEvent-3.0, AceTimer-3.0
local DTrash = KitnEssentials:NewModule("DungeonTrash", "AceEvent-3.0", "AceTimer-3.0")

local TI = KE.TrashInference

local GetTime = GetTime
local IsInInstance = IsInInstance
local GetInstanceInfo = GetInstanceInfo
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitLevel = UnitLevel
local UnitSex = UnitSex
local UnitPowerType = UnitPowerType
local UnitClassification = UnitClassification
local UnitShouldDisplaySpellTargetName = UnitShouldDisplaySpellTargetName
local C_UnitAuras = C_UnitAuras
local C_Timer = C_Timer
local issecretvalue = issecretvalue
local pcall = pcall
local tonumber = tonumber
local type = type
local string_format = string.format
local wipe = wipe

-- Flip to true, /reload, pull a trash pack, read the log. Reverts to false
-- after diagnosis but the instrumentation stays (KE debug-flag convention).
-- Currently ON for Phase 2 in-game detection validation.
local DEBUG_DTRASH = true

local SNAPSHOT_DELAY = 0.10       -- unit data unstable on the add frame
local TARGET_SAMPLE_DELAY = 0.10  -- fingerprint sample after cast start
local MAX_NAMEPLATES = 40

DTrash.tracked = {}   -- [unit] = runtime table
DTrash.monitoring = false
DTrash.currentMapID = nil

local function dprint(msg)
    if DEBUG_DTRASH then KE:Print("[DTrash] " .. tostring(msg)) end
end

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

-- ── Dungeon / M+ context ───────────────────────────────────────────────────

function DTrash:InMythicPlus()
    local _, _, diffID = GetInstanceInfo()
    return diffID == 8
end

-- Resolves the current dungeon's KE.TrashData key from the instance mapID
-- (GetInstanceInfo's 8th return; ExBoss's data is keyed by exactly this).
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
    self:EvaluateGate()
end

function DTrash:OnDisable()
    self:StopMonitor()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
end

-- Only run inside 5-man party instances — the event stream is dormant
-- elsewhere, so the whole engine detaches outside dungeons (CPU gate).
function DTrash:EvaluateGate()
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "party" then
        self:StartMonitor()
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
}

function DTrash:StartMonitor()
    if self.monitoring then return end
    self.monitoring = true
    for event, handler in pairs(CAST_EVENTS) do
        self:RegisterEvent(event, handler)
    end
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
    wipe(self.tracked)
    dprint("monitor stopped")
end

-- ── Nameplate tracking ─────────────────────────────────────────────────────

function DTrash:OnNameplateAdded(_, unit)
    if not normalizeNameplate(unit) then return end
    self.tracked[unit] = { unit = unit, engagedAt = GetTime() }
    C_Timer.After(SNAPSHOT_DELAY, function() self:SnapshotUnit(unit) end)
end

function DTrash:OnNameplateRemoved(_, unit)
    if not unit then return end
    self.tracked[unit] = nil
    if self.HideUnitAlerts then self:HideUnitAlerts(unit) end
    if self.HideNameplateMarker then self:HideNameplateMarker(unit) end
    -- Phase 6: TrashCache flicker recovery (hold runtime ~5s for re-add).
end

function DTrash:SnapshotUnit(unit)
    local rt = self.tracked[unit]
    if not rt then return end
    local obs = readIdentity(unit, self:InMythicPlus())
    if not obs then return end  -- secret/unknown identity → leave unresolved
    rt.obs = obs
    self:ResolveMob(rt)
end

-- Layer1: fingerprint the mob → candidates. Re-run whenever behavior flags
-- change (a seen cast/channel/interrupt refines the candidate set).
function DTrash:ResolveMob(rt)
    if not rt.obs then return end
    local dungeonKey = self:CurrentDungeonKey()
    if not dungeonKey then return end

    local obs = rt.obs
    obs.sawCastStart = rt.sawCastStart
    obs.sawChannelStart = rt.sawChannelStart
    obs.sawInterrupted = rt.sawInterrupted
    obs.sawCastIntoChannel = rt.sawCastIntoChannel

    -- Phase 6 will supply forcesPercent/bossProgressIndex/currentSubZoneMapID
    -- for the Academy routing + placement gate; nil here fails those open.
    local cands, resolved = TI.BuildCandidates(obs, {
        dungeonKey = dungeonKey,
        mapID = self.currentMapID,
        forcesValid = false,
    })
    rt.candidates = cands
    -- Layer1 (fingerprint) must NOT downgrade a Layer2 (observed cast/channel
    -- DURATION) resolution to a different mob: duration is stable, non-secret
    -- evidence and outranks fingerprint uniqueness. Once a cast confirms the mob,
    -- Layer1 may only re-affirm the same npcID, never flip it. Backstops the
    -- capability reconcile against any residual differential-flag prune.
    if resolved and (not rt.castConfirmed or resolved == rt.matchedNPCID) then
        rt.matchedNPCID = resolved
    end

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

-- ── Cast observation ───────────────────────────────────────────────────────

function DTrash:OnCastStart(_, unit, castGUID) self:BeginCast(unit, "cast", castGUID) end
function DTrash:OnChannelStart(_, unit, castGUID) self:BeginCast(unit, "channel", castGUID) end

-- spellID is intentionally NOT read from the event (secret in 12.0). castGUID
-- is captured only as a DEBUG probe: the faithful cast-into-channel transition
-- port (Phase 6) needs to know whether 12.0's castGUID exposes an incrementing
-- numeric cast-bar id like ExBoss relies on. It is NOT used for logic yet.
function DTrash:BeginCast(unit, kind, castGUID)
    unit = normalizeNameplate(unit)
    local rt = unit and self.tracked[unit]
    if not rt then return end
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
    rt.activeCastKind = kind
    rt.activeCastStartAt = GetTime()
    rt.activeCastSeq = (rt.activeCastSeq or 0) + 1
    rt.fpTargetExists = nil
    rt.fpTargetAPIExists = nil
    if kind == "cast" then
        rt.sawCastStart = true
    else
        rt.sawChannelStart = true
        rt.armToken = nil  -- a channel arrived; the two-phase channel path owns this
    end

    self:ResolveMob(rt)  -- behavior flag may prune candidates

    local seq = rt.activeCastSeq
    C_Timer.After(TARGET_SAMPLE_DELAY, function()
        local r = self.tracked[unit]
        if not r or r.activeCastSeq ~= seq then return end  -- stale-cast guard
        r.fpTargetExists = safeBool(UnitExists, unit .. "target")
        if UnitShouldDisplaySpellTargetName then
            r.fpTargetAPIExists = safeBool(UnitShouldDisplaySpellTargetName, unit)
        end
    end)
end

function DTrash:OnCastStop(_, unit) self:FinishCast(unit, "cast", false) end
function DTrash:OnChannelStop(_, unit, _castGUID, _spellID, interruptedBy)
    -- interruptedBy is a secret GUID for hostile casters; its mere PRESENCE
    -- means the channel was interrupted. Detect presence WITHOUT a nil-compare
    -- on a secret: issecretvalue short-circuits true for a present secret, so
    -- `~= nil` only ever runs on a confirmed non-secret value. (This path is
    -- unconditional — not gated by DEBUG — so it must be crash-proof.)
    local interrupted = (issecretvalue and issecretvalue(interruptedBy)) or (interruptedBy ~= nil)
    self:FinishCast(unit, "channel", interrupted)
end

function DTrash:OnCastInterrupted(_, unit)
    unit = normalizeNameplate(unit)
    local rt = unit and self.tracked[unit]
    if not rt then return end
    rt.sawInterrupted = true
    rt.activeCastKind = nil
    self:ResolveMob(rt)  -- interrupt flag prunes cannotInterrupt candidates now
end

-- Anchor a resolved spell's cd schedule and emit its central alert + on-plate
-- prediction. Shared by the direct cast/channel path in FinishCast and the
-- deferred one-phase fallback (a shared-castTime twin whose channel never came).
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
    rt.transitionCastStartAt = nil
    rt.armToken = nil  -- a resolution cancels any pending one-phase fallback

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
        if self.ScheduleAlert then
            self:ScheduleAlert(rt, rt.matchedNPCID, spellID, spellData, nextStart)
        end
        if self.SetNameplatePrediction then
            self:SetNameplatePrediction(rt, spellID, intervalOrigin, nextStart)
        end
    end
end

-- Cast completed successfully → Layer2 (narrow candidates + infer the spell)
-- → calibrate the cd schedule → (Phase 3) emit the alert.
function DTrash:FinishCast(unit, kind, interrupted)
    unit = normalizeNameplate(unit)
    local rt = unit and self.tracked[unit]
    if not rt or rt.activeCastKind ~= kind or not rt.activeCastStartAt then return end

    local now = GetTime()
    local duration = now - rt.activeCastStartAt
    local startAt = rt.activeCastStartAt
    rt.activeCastKind = nil
    if interrupted then rt.sawInterrupted = true; return end

    local observed = {
        kind = kind,
        duration = duration,
        startAt = startAt,
        fingerprints = {
            targetExists = rt.fpTargetExists,
            targetAPIExists = rt.fpTargetAPIExists,
        },
    }

    local dataByNpc = function(npc) return self:MobData(npc) end

    -- Layer2: if the mob is still ambiguous, the observed cast disambiguates.
    -- A duration-confirmed id is authoritative — mark it so Layer1 can't flip it.
    if rt.candidates and #rt.candidates > 1 then
        local kept, resolved = TI.FilterCandidates(rt.candidates, observed, dataByNpc)
        rt.candidates = kept
        if resolved then rt.matchedNPCID = resolved; rt.castConfirmed = true end
    end
    if not rt.matchedNPCID then
        dprint(unit .. " finish: mob unresolved")
        return
    end

    local mob = self:MobData(rt.matchedNPCID)
    local spellID = mob and TI.InferSucceededSpell(mob, observed, rt.anchors, now)
    if not spellID then
        -- Calibration aid: show the observed duration/kind AND the mob's curated
        -- spell durations, so an unmatched cast is instantly classifiable as
        -- "uncurated filler" vs "curated timing is off".
        if DEBUG_DTRASH then
            local want = {}
            if mob and mob.spells then
                for _, sp in pairs(mob.spells) do
                    want[#want + 1] = string_format("%s(c%.1f/ch%.1f)",
                        sp.name or "?", sp.castTime or 0, sp.channelTime or 0)
                end
            end
            dprint(string_format("%s: %s %s %.2fs UNMATCHED | curated: %s",
                unit, (mob and mob.name) or "?", kind, duration,
                table.concat(want, ", ")))
        end
        return
    end

    -- Calibrate: anchor at cast-start − first; the cd interval measures from
    -- success (or cast-start for CAST_START-mode spells).
    local spellData = mob.spells[spellID]

    -- Cast-into-channel handling. A spell curated with BOTH castTime and
    -- channelTime is observed as two phases: the cast (~castTime) then the
    -- channel (~channelTime). Emitting on the cast phase would double-fire and
    -- anchor the schedule off the channel start instead of the true cast start,
    -- so on the cast phase we DEFER — record the real start and let the channel
    -- phase emit once, anchored to it.
    --
    -- BUT a one-phase spell sharing this castTime (e.g. Crowd Dispersal, a 3s
    -- cast, vs Arcane Beam, a 3s cast + 5s channel) is indistinguishable from the
    -- two-phase cast phase until we see whether a channel follows — and with the
    -- spellID secret in 12.0 we cannot tell them apart by ID. So we ALSO arm a
    -- fallback: if no channel start clears armToken shortly, re-resolve this cast
    -- among ONE-phase spells and emit that, so the one-phase twin (which would
    -- otherwise be mistaken for the cast phase and dropped) still fires.
    local twoPhase = (spellData.castTime or 0) > 0 and (spellData.channelTime or 0) > 0
    if twoPhase and kind == "cast" then
        rt.transitionCastStartAt = startAt
        rt.sawCastIntoChannel = true
        self:ResolveMob(rt)  -- flag keeps channel-capable candidates in Layer1
        dprint(unit .. ": cast->channel armed (" .. tostring(spellData.name) .. ")")

        rt.armToken = (rt.armToken or 0) + 1
        local tok, castStartAt, castFinishNow, castObserved, npcID =
            rt.armToken, startAt, now, observed, rt.matchedNPCID
        -- 1.0s: long enough for a channel start to fire and clear armToken if this
        -- really was the two-phase spell; short enough that the one-phase twin's
        -- prediction (anchored to the true cast start) isn't visibly late.
        C_Timer.After(1.0, function()
            local r = self.tracked[unit]
            if not r or r.armToken ~= tok then return end  -- superseded, or a channel arrived
            local m = self:MobData(npcID)
            local altID = m and TI.InferSucceededSpell(m, castObserved, r.anchors, GetTime(), true)
            if altID then
                self:EmitCastResolution(r, m, altID, castStartAt, castFinishNow, castFinishNow, "cast", castObserved.duration)
            end
        end)
        return
    end
    local anchorStartAt = startAt
    local successAt = now  -- casts: STOP == success (reliable wall-clock)
    if kind == "channel" then
        -- The caster's CHANNEL_STOP fires when its cast bar closes, which for
        -- grab/beam mechanics is far short of the ability's real channelTime, so
        -- `now` (the STOP) is an unreliable success time. Reconstruct the true
        -- effect end from the reliable channel START + curated channelTime.
        -- (CAST_START-mode spells ignore successAt and anchor at the start.)
        local ct = tonumber(spellData.channelTime)
        if ct then successAt = startAt + ct end
        if twoPhase and rt.transitionCastStartAt then
            anchorStartAt = rt.transitionCastStartAt  -- anchor on the true cast start
        end
    end
    self:EmitCastResolution(rt, mob, spellID, anchorStartAt, successAt, now, kind, duration)
end

return DTrash
