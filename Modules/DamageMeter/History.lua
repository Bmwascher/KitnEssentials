-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/History.lua                                 ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: Runtime-only key-history snapshot store. At    ║
-- ║          CHALLENGE_MODE_START (before KE's wipe) every   ║
-- ║          stored session × 11 meter types (+ per-source   ║
-- ║          details) is RETAINED verbatim as one bundle;    ║
-- ║          Core.lua's GetSession/GetSource serve entries   ║
-- ║          by NEGATIVE session id. Spec:                   ║
-- ║          dev/docs/superpowers/specs/                     ║
-- ║          2026-07-18-dm-snapshot-store-design.md          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DamageMeter: AceModule
local DM = KitnEssentials:GetModule("DamageMeter")

local ipairs = ipairs
local type = type
local wipe = wipe
local issecretvalue = issecretvalue
local tremove = table.remove
local tinsert = table.insert
local debugprofilestop = debugprofilestop
local UnitGUID = UnitGUID

local DEBUG_DMH = false

-- Lazy store. nextID decreases monotonically and is NEVER reused (a stale
-- window pin can never alias a newer snapshot); HistoryClear keeps it.
local function store(self)
    local h = self._history
    if not h then
        h = { bundles = {}, byID = {}, nextID = -1 }
        self._history = h
    end
    return h
end

-- Shared nil-safe source key — capture and lookup MUST use the same mapping
-- [C3]. Both fields are Nilable in the API contract; a source with neither
-- is skipped by the deep pass (its bar row still renders from byType).
-- Secret guard mirrors Detail.lua's enemy-key idiom (never key a table on a
-- possibly-secret value); capture runs OOC where these are plain, so a
-- secret here is a contract surprise and the source is simply skipped.
function DM.HistorySourceKey(sourceGUID, sourceCreatureID)
    if sourceGUID ~= nil and not issecretvalue(sourceGUID) then
        return sourceGUID
    end
    if sourceCreatureID ~= nil and not issecretvalue(sourceCreatureID) then
        return "c:" .. tostring(sourceCreatureID)
    end
    return nil
end

-- Chokepoint serves (Core.lua GetSession/GetSource negative-id branch).
-- Plain table reads — an evicted or unknown id falls out as nil, which every
-- caller already treats as "no session".
function DM:HistorySession(sessionID, dmType)
    local h = self._history
    local entry = h and h.byID[sessionID]
    local byType = entry and entry.byType
    return byType and byType[dmType] or nil
end

function DM:HistorySource(sessionID, dmType, sourceGUID, sourceCreatureID)
    local h = self._history
    local entry = h and h.byID[sessionID]
    if not entry then return nil end
    local key = DM.HistorySourceKey(sourceGUID, sourceCreatureID)
    local perSource = key ~= nil and entry.sources[key] or nil
    return perSource and perSource[dmType] or nil
end

-- Newest-first bundle list for the segment menu. nil = no history yet.
function DM:HistoryBundles()
    local h = self._history
    if not h or #h.bundles == 0 then return nil end
    return h.bundles
end

-- Full clear: header reset only (plus /reload implicitly). The
-- DAMAGE_METER_RESET event handler must NOT call this — our own key-start
-- wipe fires that event right after capture, and external resets must not
-- erase captured history either (spec: store clears only on eviction,
-- header reset, /reload).
function DM:HistoryClear()
    local h = self._history
    if not h then return end
    wipe(h.bundles)
    wipe(h.byID)
end

---------------------------------------------------------------------------------
-- Plain-name identity memo (GUID -> last plain, realm-bearing name)
--
-- DamageMeterCombatSource.name is ConditionalSecret and stamps secrecy at
-- MARSHAL time: a member who leaves the group before the key-start capture is
-- frozen into the snapshot with a permanently secret name, while their
-- enemy-side attribution (combatSpellDetails.unitName — not conditional)
-- stays plain (in-game probe 2026-07-19: 7/7 attackers plain, 0 secret).
-- Learned wherever a source name renders/marshals plain (RenderBar's plain
-- ticks + the capture deep pass); Detail.lua falls back to it for the tip
-- header and the Targets lookup when a bar's name is secret. Player GUIDs
-- only — identity restriction never applies to creatures. Runtime lifetime,
-- exactly matching the store it backs; survives HeaderReset (identity is not
-- meter data).
---------------------------------------------------------------------------------

function DM:NotePlainName(guid, name)
    -- Truthiness first, never ==/~= — both inputs can be secret (RenderBar's
    -- guid-guard idiom); issecretvalue stays first contact after truthy.
    if not guid or issecretvalue(guid) or type(guid) ~= "string" then return end
    if not name or issecretvalue(name) or type(name) ~= "string" or name == "" then return end
    if guid:sub(1, 7) ~= "Player-" then return end
    local m = self._plainNames
    if not m then m = {}; self._plainNames = m end
    local prev = m[guid]
    -- Never downgrade: cross-realm names intermittently drop their "-Realm"
    -- suffix (the realmNames flicker, Window.lua), but the Targets map keys
    -- on the realm-BEARING det.unitName — a bare flicker tick must not
    -- overwrite the matchable form.
    if prev and prev:find("-", 1, true) and not name:find("-", 1, true) then return end
    m[guid] = name
end

function DM:PlainNameFor(guid)
    local m = self._plainNames
    if not m or not guid or issecretvalue(guid) then return nil end
    return m[guid]
end

---------------------------------------------------------------------------------
-- Pending-key metadata (feeds bundle labeling [C2][C4])
--
-- Armed ONLY at a key start where the wipe actually fired (Core.lua calls
-- this at the END of the gated reset block). A capture that finds pending
-- unarmed seals as the label-less "Earlier runs" bundle — the store's
-- contents then span more than one wipe boundary and must not be labeled
-- with any single key.
--
-- Lives in TWO places: the runtime field (the working copy, trusted
-- unconditionally — same-session continuity is its own provenance) and a
-- persisted copy (KE.db.global.DMHistoryPending, the SAME table so
-- completion repairs flow to both). The persisted copy exists solely to
-- survive /reload — the native session store is server-side and outlives
-- a reload, so without it a between-keys reload sealed a fully-labeled
-- run as "Earlier runs". It lives in the AceDB GLOBAL
-- section, never the profile: pending describes the global native store,
-- and a per-profile copy shards that state — an inactive profile could
-- retain an anchored stale record across a no-wipe boundary drop and
-- resurrect it to mislabel a multi-key store (Codex round 2, MAJOR).
-- A RESTORED copy is only ever trusted against an anchor: a session id it
-- stamped must still be in the store (HistoryCapture) or
-- CHALLENGE_MODE_COMPLETED must fire for it (HistoryOnKeyComplete — the
-- event itself proves the key is still live) — AND its charKey must match
-- the current character: the global slot is ACCOUNT-wide while the native
-- store is per-character, and an alt's small-integer session ids collide
-- with the main's trivially (Codex round 4). Every field is written
-- through a plain-value guard, so the table is SavedVariables-safe by
-- construction.
--
-- ACCEPTED residual (documented, not fixable by observation): keys run on
-- THIS character while the addon itself was disabled/absent pass boundaries
-- nobody saw — a survivor from before that gap can then label a store
-- spanning them. A logged-out character cannot pass boundaries, and the
-- /reload gap is seconds, so the arm requires deliberately playing keys
-- with KE off.
---------------------------------------------------------------------------------

-- The profile-independent persistence slot. nil until Core's AceDB init;
-- every caller treats a nil section as "no persisted copy".
local function globalDB()
    local db = KE.db
    return db and db.global or nil
end

-- Drops pending provenance everywhere it lives. Core's reset/boundary
-- paths call this whenever the native store stops matching the armed key.
function DM:HistoryDropPending()
    self._pendingBundle = nil
    local g = globalDB()
    if g then g.DMHistoryPending = nil end
end

function DM:HistoryArmPending()
    local label, level
    if C_ChallengeMode then
        local mapID = C_ChallengeMode.GetActiveChallengeMapID
            and C_ChallengeMode.GetActiveChallengeMapID()
        if mapID and C_ChallengeMode.GetMapUIInfo then
            -- First return = localized dungeon name (non-secret; same read
            -- MythicPlusTimer uses).
            local name = C_ChallengeMode.GetMapUIInfo(mapID)
            if name ~= nil and not issecretvalue(name) then label = name end
        end
        if C_ChallengeMode.GetActiveKeystoneInfo then
            -- Can read 0 at the start boundary [C4]; completion repairs it.
            local lvl = C_ChallengeMode.GetActiveKeystoneInfo()
            if type(lvl) == "number" and lvl > 0 then level = lvl end
        end
    end
    local pending = { label = label, level = level }
    -- Owner stamp: the restore paths refuse records from other characters.
    local me = UnitGUID and UnitGUID("player")
    if me ~= nil and not issecretvalue(me) then pending.charKey = me end
    self._pendingBundle = pending
    -- Persisted copy for reload survival — same table, never a clone.
    local g = globalDB()
    if g then g.DMHistoryPending = pending end
end

-- CHALLENGE_MODE_COMPLETED: authoritative outcome/duration + metadata
-- repair [C1][C4]. GetChallengeCompletionInfo is the completion source of
-- truth (MythicPlusTimer.lua CompleteRun uses the same field for the same
-- reason: world-elapsed goes stale after depletion). A depleted-but-
-- completed key is onTime == false -> outcome false (shown as a loss) —
-- NEVER derived from _sessionOutcomes, which is per-boss kill/wipe tagging.
-- The run-level "+NN" summary session is stored by Blizzard around this
-- event, but the final BOSS session already exists by kill time and the
-- boss/summary append ORDER is not pinned — "newest at the event" could
-- target the boss. Identify by SET DIFF instead: remember the ids stored
-- at event time, then after a 1s settle (same delayed-read pattern as
-- OnEncounterEnd's outcome tagging) prefer the newest id that appeared
-- AFTER the event, falling back to the newest overall. Correct under
-- either append order; session NAMES can be secret and are never matched.
-- A restored (post-reload) record is only usable by the character that
-- wrote it: the event/anchor liveness proofs say nothing about WHOSE store
-- they ran against. nil/legacy charKey fails closed.
local function restoredBelongsHere(restored)
    local me = UnitGUID and UnitGUID("player")
    return me ~= nil and not issecretvalue(me) and restored.charKey == me
end

function DM:HistoryOnKeyComplete()
    local pending = self._pendingBundle
    if not pending then
        -- Mid-key /reload: the runtime copy died but the persisted one
        -- survived, and COMPLETED firing is proof the key it describes is
        -- still the live one — re-adopt it (same character only) so the
        -- repairs + summary pick land and the next capture labels normally.
        local g = globalDB()
        local restored = g and g.DMHistoryPending or nil
        pending = (restored and restoredBelongsHere(restored)) and restored or nil
        self._pendingBundle = pending
    end
    if not pending then return end
    local info = C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo
        and C_ChallengeMode.GetChallengeCompletionInfo()
    if info then
        if type(info.level) == "number" and info.level > 0 then
            pending.level = info.level
        end
        if info.mapChallengeModeID and C_ChallengeMode.GetMapUIInfo then
            local name = C_ChallengeMode.GetMapUIInfo(info.mapChallengeModeID)
            if name ~= nil and not issecretvalue(name) then pending.label = name end
        end
        pending.outcome = info.onTime == true
        if type(info.time) == "number" and info.time > 0 then
            pending.durationMs = info.time
        end
    end
    -- Ids already stored when the event fired (the boss session is in
    -- here; the summary lands at/after the event under either ordering).
    local known = {}
    local atEvent = self:GetAvailableSessions(1e9)
    if atEvent then
        for i = 1, #atEvent do
            local id = atEvent[i] and atEvent[i].sessionID
            if id ~= nil and not issecretvalue(id) then known[id] = true end
        end
        -- Immediate anchor for the reload-survivor check: the newest plain
        -- id already stored at the event (usually the final boss). The
        -- summary pick below lands only after the 1s settle — a /reload
        -- inside that window would otherwise leave the persisted copy
        -- anchor-less and cost the label (Codex tail review, F2).
        for i = #atEvent, 1, -1 do
            local id = atEvent[i] and atEvent[i].sessionID
            if id ~= nil and not issecretvalue(id) then
                pending.anchorSessionID = id
                break
            end
        end
    end
    C_Timer.After(1, function()
        -- Still the same pending run? (A key start inside the 1s window
        -- consumes pending via HistoryCapture; do not resurrect it.)
        if DM._pendingBundle ~= pending then return end
        local list = DM:GetAvailableSessions(1e9)
        if not list or #list == 0 then return end
        local pick
        for i = #list, 1, -1 do   -- newest -> oldest
            local id = list[i] and list[i].sessionID
            if id ~= nil and not issecretvalue(id) then
                pick = pick or id            -- newest overall = the fallback
                if not known[id] then        -- newest POST-event id wins
                    pick = id
                    break
                end
            end
        end
        if pick ~= nil then pending.summarySessionID = pick end
    end)
end

---------------------------------------------------------------------------------
-- Capture — synchronous, at CHALLENGE_MODE_START, BEFORE the wipe [C5]
---------------------------------------------------------------------------------

local METER_TYPE_MIN, METER_TYPE_MAX = 0, 10   -- Enum.DamageMeterType range

-- Whole-bundle eviction, oldest first. HistoryRetain is clamped at READ so
-- a legacy stored value (old slider max 10, older default 20) needs no
-- migration. Max 5: a deep bundle measured ~2.9MB live (2026-07-24 smoke),
-- so 5 keys ≈ 15MB runtime ceiling — 10 was ruled too heavy.
local function evictOverCap(self, h)
    local cap = self.db and self.db.HistoryRetain
    if type(cap) ~= "number" then cap = 5 end
    if cap < 1 then cap = 1 elseif cap > 5 then cap = 5 end
    while #h.bundles > cap do
        local old = tremove(h.bundles)   -- bundles is newest-first: tail = oldest
        for _, entry in ipairs(old.sessions) do
            h.byID[entry.id] = nil
        end
    end
end

-- Snapshot every stored session × all 11 meter types (+ per-source deep
-- pass) into one sealed bundle. Reads go through the module's own pcall'd
-- getters with POSITIVE ids (the API path). Returns the bundle, or nil when
-- the store was empty/unreadable. ALWAYS consumes the pending metadata —
-- BOTH copies, even on the early returns.
function DM:HistoryCapture()
    local pending = self._pendingBundle
    self._pendingBundle = nil
    -- Normally the persisted copy IS pending (same table) and is consumed
    -- with it; after a /reload it's the lone survivor — adopted below only
    -- if anchored.
    local g = globalDB()
    local restored = not pending and g and g.DMHistoryPending or nil
    if g then g.DMHistoryPending = nil end
    if restored and not restoredBelongsHere(restored) then restored = nil end

    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return nil end
    -- EXPLICIT huge cap: the helper defaults an omitted cap to 20 (its menu
    -- contract, Core.lua:1669) — an implicit call would silently drop the
    -- OLDEST segments of a long key (Codex round 2, F2').
    local list = self:GetAvailableSessions(1e9)
    if not list or #list == 0 then return nil end

    if restored then
        -- Reload survivor: trust its label ONLY if the completed key it
        -- describes is still in the native store — a session id it stamped
        -- at completion (the immediate anchor, or the settle-refined summary
        -- pick) must appear in this capture's list. No id (key never
        -- completed) or no match (store reset/replaced since) -> stay
        -- unarmed and seal honestly as "Earlier runs" [C2]. Known
        -- theoretical hole: ids carry no documented uniqueness across full
        -- client restarts, so a coincidental reuse could false-positive
        -- (probe pending) — still strictly narrower than the pre-fix
        -- always-lose-the-label behavior.
        local sid = restored.summarySessionID
        local aid = restored.anchorSessionID
        if sid ~= nil or aid ~= nil then
            for i = 1, #list do
                local id = list[i] and list[i].sessionID
                if id ~= nil and not issecretvalue(id)
                    and (id == sid or id == aid) then
                    pending = restored
                    break
                end
            end
        end
    end

    local h = store(self)
    local outcomes = self._sessionOutcomes
    local startT = debugprofilestop()

    local bundle = {
        label = pending and pending.label or nil,   -- nil = "Earlier runs" row [C2]
        level = pending and pending.level or nil,
        outcome = pending and pending.outcome,       -- nil = abandoned / unarmed
        durationMs = pending and pending.durationMs or nil,
        sessions = {},
    }

    for i = 1, #list do
        local avail = list[i]
        local oldID = avail and avail.sessionID
        if oldID ~= nil and not issecretvalue(oldID) then
            local entry = {
                id = h.nextID,
                name = avail.name,                       -- may be secret: SetText-only
                durationSeconds = avail.durationSeconds, -- may be secret: FormatDeathTime guards
                -- Frozen tint [C1]. NO `or nil` tail — a false (wipe) tag is
                -- a legitimate value and `and/or` would collapse it to nil
                -- (the and/or-collapse bug class; see the 2026-07-18 trash
                -- audit F2).
                outcome = outcomes and outcomes[oldID],
                isSummary = (pending and pending.summarySessionID == oldID) or nil,
                byType = {},
                sources = {},
            }
            h.nextID = h.nextID - 1
            for dmType = METER_TYPE_MIN, METER_TYPE_MAX do
                local session = self:GetSession(nil, dmType, oldID)
                if session then
                    entry.byType[dmType] = session
                    local srcs = session.combatSources
                    if srcs then
                        for si = 1, #srcs do
                            local src = srcs[si]
                            -- Current members marshal plain here — feed the
                            -- identity memo (self-filters secrets/creatures).
                            self:NotePlainName(src.sourceGUID, src.name)
                            local key = DM.HistorySourceKey(src.sourceGUID, src.sourceCreatureID)
                            if key ~= nil then
                                local detail = self:GetSource(nil, dmType,
                                    src.sourceGUID, src.sourceCreatureID, oldID)
                                if detail then
                                    local perSource = entry.sources[key]
                                    if not perSource then
                                        perSource = {}
                                        entry.sources[key] = perSource
                                    end
                                    perSource[dmType] = detail
                                end
                            end
                        end
                    end
                end
            end
            bundle.sessions[#bundle.sessions + 1] = entry
            h.byID[entry.id] = entry
        end
    end

    if #bundle.sessions == 0 then return nil end
    tinsert(h.bundles, 1, bundle)   -- newest first
    evictOverCap(self, h)
    if DEBUG_DMH then
        KE:Print(("[DMH] capture: %d sessions, %.1fms"):format(
            #bundle.sessions, debugprofilestop() - startT))
    end
    return bundle
end
