-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/Core.lua                                    ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: In-client damage/healing/threat meter with a   ║
-- ║           configurable dock, per-segment history, and    ║
-- ║           death log.                                     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DamageMeter: AceModule, AceEvent-3.0, AceConsole-3.0
local DM = KitnEssentials:NewModule("DamageMeter", "AceEvent-3.0", "AceConsole-3.0")

KE.DamageMeter = DM

local DEBUG_DM = false

-- File-level upvalues for globals used in per-tick / per-bar render paths.
local IsInInstance = IsInInstance
local C_ChallengeMode = C_ChallengeMode
local AbbreviateNumbers = AbbreviateNumbers
local issecretvalue = issecretvalue
local debugprofilestop = debugprofilestop
local wipe = wipe

-- Pre-built group unit tokens (mirrors EllesmereUI lines 298-300). UNIT_FLAGS
-- can fire dozens of times per second during a pull, and GroupInCombat is hit
-- on every one; building "raid"..i / "party"..i inline on each call would churn
-- garbage. Filled once at file load and read by index inside GroupInCombat.
local _raidUnits, _partyUnits = {}, {}
for i = 1, 40 do _raidUnits[i] = "raid" .. i end
for i = 1, 4 do _partyUnits[i] = "party" .. i end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function DM:UpdateDB()
    self.db = KE.db.profile.DamageMeter
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function DM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function DM:OnEnable()
    -- self.db is assigned in OnInitialize (always runs before OnEnable in the
    -- Ace3 lifecycle), so only the Enabled flag needs checking here.
    if not self.db.Enabled then return end

    self.enabled = true

    -- Combat-state events drive the shared ticker (see Combat-only ticker
    -- section). NEVER use RegisterUnitEvent (Ace3 doesn't expose it and 12.0
    -- discourages it for KE); UNIT_FLAGS is registered broad and filtered by
    -- the group-combat check inside the handler.
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnRegenDisabled")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
    self:RegisterEvent("ENCOUNTER_START", "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCombatForceStop")
    self:RegisterEvent("UNIT_FLAGS", "OnUnitFlags")
    self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", "OnSessionUpdated")
    self:RegisterEvent("DAMAGE_METER_RESET", "OnMeterReset")

    -- Seed window 1 with a Default context if the user has never configured one.
    -- Phase 1 is single-window only (multi-window/dock is a later phase), so just
    -- the [1] slot is ensured here. Stored under Contexts.Default; the live
    -- content context resolves to this when no per-context override exists.
    self.db.Windows = self.db.Windows or {}
    if not self.db.Windows[1] then
        self.db.Windows[1] = {
            Contexts = {
                Default = {
                    Enabled = true,
                    MeterType = Enum.DamageMeterType.DamageDone,
                    SessionType = Enum.DamageMeterSessionType.Current,
                },
            },
        }
    end

    -- Build window 1's frame tree once (CreateWindow is idempotent-friendly: it
    -- overwrites windows_rt[1], but on enable the tree won't exist yet). Position
    -- it via the shared helper so the pixel-perfect snap runs.
    local W = self.windows_rt and self.windows_rt[1]
    if not W then
        W = self:CreateWindow(1)
    end
    KE:ApplyFramePosition(W.frame, self.db.Position, self.db)

    -- Paint once immediately so the window reflects the current (out-of-combat)
    -- session on enable, then rely on the combat-gated ticker for live updates.
    self:Tick()

    if DEBUG_DM then
        KE:Print("[DM] OnEnable: module active")
    end
end

function DM:OnDisable()
    self.enabled = false

    self:UnregisterAllEvents()
    self:StopTicker()
    self._sessionPending = false
    self._inEncounter = false

    if self.dock then
        self.dock:Hide()
    end

    -- Hide every built runtime window (Phase 1: just window 1). The frame trees
    -- are kept for re-enable; only their visibility is cleared.
    if self.windows_rt then
        for _, W in pairs(self.windows_rt) do
            if W.frame then W.frame:Hide() end
        end
    end

    if DEBUG_DM then
        KE:Print("[DM] OnDisable: module inactive")
    end
end

---------------------------------------------------------------------------------
-- Combat-only ticker (shared across all windows)
--
-- Mirrors EllesmereUI's StartSharedTicker/StopSharedTicker (single ticker for
-- every window). The ticker only runs while the player or group is in combat,
-- so idle CPU is zero. DM:Tick (implemented in the render chunk) repaints every
-- window from the current sessions; it is resolved at runtime here (called as a
-- method) so this lifecycle layer doesn't depend on the render layer load order.
---------------------------------------------------------------------------------

-- Single shared-ticker body (mirrors EllesmereUI's SharedRefreshTick,
-- ~lines 3937-3956). Runs on every tick and is responsible for self-cancelling
-- when the group leaves combat, so the lifecycle never depends on a one-shot
-- C_Timer.After firing at exactly the right moment.
--
-- _needsFinalRefresh is set by OnRegenEnabled when the player left combat but
-- the group is still fighting (e.g. died mid-pull): the ticker keeps polling
-- GroupInCombat each tick and only stops once everyone is out of combat,
-- painting one final frame at that point. This is the continuous re-check the
-- reference guarantees, not a single deferred re-check.
--
-- DM:Tick is implemented in the render chunk and resolved at runtime; it is
-- guarded so this lifecycle layer never throws "attempt to call a nil value"
-- if combat starts before that chunk loads (mirrors the DM.OpenDetail guard in
-- Window.lua:MakeBar).
function DM:_RunTick()
    if self._needsFinalRefresh and not self:GroupInCombat() then
        -- Group combat ended: final paint, drop the flag, stop the ticker.
        self._needsFinalRefresh = false
        if DM.Tick then DM:Tick() end
        if self._ticker then
            self._ticker:Cancel()
            self._ticker = nil
        end
        if DEBUG_DM then KE:Print("[DM] _RunTick: group left combat -> final paint + self-cancel") end
        return
    end

    -- Normal tick (player in combat, or group still fighting after player left).
    if DM.Tick then DM:Tick() end
end

-- Starts (or restarts) the shared refresh ticker. Cancel-before-start so a
-- stale ticker is never left orphaned if combat is re-entered without a clean
-- stop. RefreshRate defaults to 0.5s when the DB value is missing.
function DM:StartTicker()
    if self._ticker then
        self._ticker:Cancel()
        self._ticker = nil
    end

    local rate = (self.db and self.db.RefreshRate) or 0.5
    self._ticker = C_Timer.NewTicker(rate, function()
        DM:_RunTick()
    end)

    if DEBUG_DM then
        KE:Print("[DM] StartTicker: rate", rate)
    end
end

-- Cancels the shared ticker and paints one final frame so the bars settle on
-- the post-combat totals (out of combat the amounts declassify to plain numbers).
-- Tick is guarded: it is defined in the render chunk and resolved at runtime, so
-- a StopTicker reachable before that chunk loads (direct OnDisable call, future
-- load-order change) must not throw "attempt to call a nil value". Mirrors the
-- DM.OpenDetail forward-reference guard in Window.lua:MakeBar.
function DM:StopTicker()
    if self._ticker then
        self._ticker:Cancel()
        self._ticker = nil
    end

    self._needsFinalRefresh = false

    if DM.Tick then DM:Tick() end

    if DEBUG_DM then
        KE:Print("[DM] StopTicker: final paint")
    end
end

-- True when the player is in combat, or any group member is. UnitAffectingCombat
-- is safe to read here (not a secret return). The player fast-path uses
-- UnitAffectingCombat("player") rather than InCombatLockdown() (mirrors
-- EllesmereUI line 303): InCombatLockdown() returns false the moment the player
-- dies or feign-deaths mid-pull, but UnitAffectingCombat stays true while the
-- player is still tagged into the fight, so the ticker keeps painting. Group
-- units are read from the pre-built _raidUnits / _partyUnits tables.
function DM:GroupInCombat()
    if UnitAffectingCombat("player") then return true end

    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, n do
            if UnitAffectingCombat(_raidUnits[i]) then return true end
        end
    elseif IsInGroup() then
        -- Party units exclude the player, so iterate one fewer than the count.
        local n = GetNumGroupMembers() - 1
        for i = 1, n do
            if UnitAffectingCombat(_partyUnits[i]) then return true end
        end
    end

    return false
end

---------------------------------------------------------------------------------
-- Combat-state event handlers
--
-- The ticker is combat-gated: started on entering combat, stopped once the whole
-- group has left combat. PLAYER_ENTERING_WORLD forces it down unconditionally
-- (zoning is a hard segment boundary). ENCOUNTER_END stops it too, but only
-- after a 0.5s delay so Blizzard can finalize the session totals first, and only
-- when an encounter is actually active (a mid-encounter REGEN_ENABLED from a boss
-- transition must not be treated as a real stop -- _inEncounter guards that).
---------------------------------------------------------------------------------

-- Player entered combat: spin up the shared ticker.
function DM:OnRegenDisabled()
    if DEBUG_DM then KE:Print("[DM] PLAYER_REGEN_DISABLED -> StartTicker") end
    self:StartTicker()
end

-- Player left combat. If the group is still fighting (player died mid-pull),
-- raise _needsFinalRefresh and make sure the shared ticker is running: the
-- ticker polls GroupInCombat every tick and self-cancels once everyone is out
-- of combat (continuous re-check, mirroring EllesmereUI). Only stop outright
-- when the whole group is already out of combat. While an encounter is active
-- (between ENCOUNTER_START and ENCOUNTER_END) a transient REGEN_ENABLED from a
-- boss transition is ignored -- the ENCOUNTER_END path owns the encounter stop.
function DM:OnRegenEnabled()
    if self._inEncounter then
        if DEBUG_DM then KE:Print("[DM] PLAYER_REGEN_ENABLED -> ignored (encounter active)") end
        return
    end

    if not self:GroupInCombat() then
        if DEBUG_DM then KE:Print("[DM] PLAYER_REGEN_ENABLED -> StopTicker") end
        self:StopTicker()
    else
        if DEBUG_DM then KE:Print("[DM] PLAYER_REGEN_ENABLED -> group still in combat, poll until clear") end
        self._needsFinalRefresh = true
        -- Ensure the ticker is alive so its self-poll can fire the final stop;
        -- StartTicker is cancel-before-start so this never doubles the ticker.
        if not self._ticker then
            self:StartTicker()
        end
    end
end

-- Encounter started: mark the encounter active so a mid-encounter
-- PLAYER_REGEN_ENABLED (boss transition that briefly drops the combat lock)
-- doesn't get mistaken for a real combat-end. Mirrors EllesmereUI's _inEncounter.
function DM:OnEncounterStart()
    if DEBUG_DM then KE:Print("[DM] ENCOUNTER_START -> encounter active") end
    self._inEncounter = true
end

-- Boss kill/wipe: a hard segment boundary, but the session totals are not yet
-- finalized at the instant ENCOUNTER_END fires. Delay the stop by 0.5s so the
-- final paint reads settled totals rather than a stale/empty segment (mirrors
-- EllesmereUI line ~4008). Clears the encounter-active flag immediately.
function DM:OnEncounterEnd()
    if DEBUG_DM then KE:Print("[DM] ENCOUNTER_END -> delayed StopTicker (0.5s)") end
    self._inEncounter = false
    C_Timer.After(0.5, function()
        DM:StopTicker()
    end)
end

-- Zoning: hard segment boundary, force the ticker down immediately. Also clears
-- the encounter-active flag (zoning ends any encounter).
function DM:OnCombatForceStop()
    if DEBUG_DM then KE:Print("[DM] PLAYER_ENTERING_WORLD -> force StopTicker") end
    self._inEncounter = false
    self:StopTicker()
end

-- A group member's flags changed (often: they entered combat before us). Start
-- the ticker if the group is fighting and we're not already ticking, so bars
-- populate before the player is tagged.
function DM:OnUnitFlags()
    if self:GroupInCombat() and not self._ticker then
        if DEBUG_DM then KE:Print("[DM] UNIT_FLAGS -> group in combat, StartTicker") end
        self:StartTicker()
    end
end

-- The damage-meter session changed. In combat the ticker already covers
-- repaints, so only react out of combat. Debounce to one paint per 0.1s burst
-- (the event can fire rapidly as the API finalizes a segment).
function DM:OnSessionUpdated()
    if InCombatLockdown() then return end
    if self._sessionPending then return end

    self._sessionPending = true
    C_Timer.After(0.1, function()
        DM._sessionPending = false
        -- Re-check combat: if a fight started inside the 0.1s debounce window the
        -- secret-safe ticker path owns the repaint, so skip this out-of-combat
        -- one. Keeps in-combat painting exclusively on the ticker.
        if InCombatLockdown() then return end
        if DEBUG_DM then KE:Print("[DM] DAMAGE_METER_COMBAT_SESSION_UPDATED (debounced) -> Tick") end
        if DM.Tick then DM:Tick() end
    end)
end

-- Meter data was reset: repaint immediately so cleared bars show. Tick is
-- guarded (resolved at runtime from the render chunk).
function DM:OnMeterReset()
    if DEBUG_DM then KE:Print("[DM] DAMAGE_METER_RESET -> Tick") end
    if DM.Tick then self:Tick() end
end

---------------------------------------------------------------------------------
-- Secret-safe session getters
--
-- C_DamageMeter session/source returns carry secret values in combat
-- (totalAmount, amountPerSecond, maxAmount). The getters themselves can also
-- reject secret arguments while execution is tainted, so every API call is
-- wrapped in pcall and the result is discarded on failure. The caller renders
-- the returned tables via native widget interpolation; it must never perform
-- Lua arithmetic or comparisons on the secret fields.
---------------------------------------------------------------------------------

-- Returns the combat session table { combatSources, maxAmount, totalAmount,
-- durationSeconds } for the requested type/id, or nil on failure. When
-- sessionID is non-nil the FromID variant is used (a specific stored session);
-- otherwise the live FromType variant is used.
function DM:GetSession(sessionType, dmType, sessionID)
    if not C_DamageMeter then return nil end

    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionFromID then return nil end
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, dmType)
        if ok then return session end
        if DEBUG_DM then KE:Print("[DM] GetSession FromID failed:", session) end
        return nil
    end

    if not C_DamageMeter.GetCombatSessionFromType then return nil end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, dmType)
    if ok then return session end
    if DEBUG_DM then KE:Print("[DM] GetSession FromType failed:", session) end
    return nil
end

-- Returns the per-source detail table for a single combat source (keyed by
-- sourceGUID), or nil on failure. Mirrors GetSession's FromID/FromType branch.
function DM:GetSource(sessionType, dmType, sourceGUID, sessionID)
    if not C_DamageMeter then return nil end

    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionSourceFromID then return nil end
        local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionID, dmType, sourceGUID)
        if ok then return source end
        if DEBUG_DM then KE:Print("[DM] GetSource FromID failed:", source) end
        return nil
    end

    if not C_DamageMeter.GetCombatSessionSourceFromType then return nil end
    local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, dmType, sourceGUID)
    if ok then return source end
    if DEBUG_DM then KE:Print("[DM] GetSource FromType failed:", source) end
    return nil
end

---------------------------------------------------------------------------------
-- Value formatter
--
-- AbbreviateNumbers returns a (secret-in-combat) string, and concatenating two
-- such strings with .. is confirmed safe. So the combined "total | perSec"
-- string is built from a single value FontString's worth of data without ever
-- calling tostring on, or comparing, the raw amounts.
--
-- The formatter returns (string, isSecret). In combat the amounts are secret,
-- so the produced string is secret too; the render layer MUST NOT dirty-check
-- it with == / ~= (that throws a taint error). Out of combat the amounts are
-- plain numbers and the string is a normal string the caller can cache and
-- compare. issecretvalue on the result tells the caller which path applies.
--
-- The render layer reads self.db.ShowPerSec once before the bar loop and calls
-- this file-local directly, rather than re-reading the DB per bar through a
-- method wrapper.
---------------------------------------------------------------------------------

-- Returns (string, isSecret): the abbreviated total, or "total | perSec" when
-- showPerSec is true and perSec is available. Never touches the numeric amounts
-- directly (no tostring, no comparisons). `total` is nil-guarded with a
-- truthiness gate (NOT `== nil`, which is a taint-throwing equality on a secret
-- number in combat); a secret number is truthy, so `not total` is only true for
-- a genuinely nil/empty source, which yields an empty, non-secret string.
local function FormatBarValue(total, perSec, showPerSec)
    if not total then return "", false end

    local str
    if showPerSec and perSec then
        str = AbbreviateNumbers(total) .. " | " .. AbbreviateNumbers(perSec)
    else
        str = AbbreviateNumbers(total)
    end

    return str, issecretvalue(str)
end

-- Cross-chunk API: the render layer calls this directly. Non-underscore name
-- because it is intentional public API on DM (underscore-prefix fields are
-- private-to-file by KE convention); matches DM.RANK_STRINGS / DM.BAR_POOL_SIZE
-- in Window.lua.
DM.FormatBarValue = FormatBarValue

---------------------------------------------------------------------------------
-- Content-context resolver
--
-- Mirrors KickTracker:GetActiveContext (Modules/Dungeons/KickTracker.lua) but
-- keyed off the instance type rather than the player's spec. Each window stores
-- per-context configs under Windows[i].Contexts; the live context drives which
-- one is active, falling back to Default.
---------------------------------------------------------------------------------

local CTX_BY_INSTANCE = {
    party     = "Dungeon",
    raid      = "Raid",
    arena     = "Arena",
    pvp       = "Battleground",
    scenario  = "Scenario",
    none      = "Default",
}

-- Maps a Blizzard instanceType (plus the Challenge Mode flag) to a KE context
-- key. Mythic+ is a party instance with an active keystone.
function DM:MapContext(instanceType, isChallenge)
    if instanceType == "party" and isChallenge then
        return "Mythic+"
    end
    return CTX_BY_INSTANCE[instanceType] or "Default"
end

-- Live content context derived from the current instance type and keystone
-- state. IsChallengeModeActive's return is passed through as raw truthiness
-- (no `or false` coercion) to avoid undefined behavior should it ever return a
-- secret boolean; mirrors WarpDepleteForces' IsInChallengeMode helper.
function DM:GetActiveContext()
    local instanceType = select(2, IsInInstance())
    local isChallenge = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    return self:MapContext(instanceType, isChallenge)
end

-- Resolves the active per-context config for a window: the live-context entry
-- if present, else the Default entry. Returns nil when the window or its
-- Contexts table is absent. `context` may be supplied by the render layer (it
-- resolves the active context once per tick and passes it to each window) to
-- avoid recomputing it N times; otherwise it is resolved here.
function DM:ResolveWindowConfig(winIdx, context)
    local windows = self.db and self.db.Windows
    local window = windows and windows[winIdx]
    if not window or not window.Contexts then return nil end
    context = context or self:GetActiveContext()
    return window.Contexts[context] or window.Contexts.Default
end

---------------------------------------------------------------------------------
-- Readable header labels
--
-- The render layer builds a window's header text from cfg.MeterType /
-- cfg.SessionType, both Enum values. These tables map the enum to a display
-- string once at file load; the render path reads them by key and never builds
-- a label string per tick. Mirrors EllesmereUI's DM_TYPE_NAMES /
-- SESSION_TYPE_NAMES. DamageMeter enums are guaranteed present in 12.0, but each
-- lookup is nil-guarded at the call site (RenderWindow) so a missing key falls
-- back to a sane default rather than concatenating nil.
---------------------------------------------------------------------------------

DM.METER_TYPE_NAMES = {
    [Enum.DamageMeterType.DamageDone]           = "Damage Done",
    [Enum.DamageMeterType.HealingDone]          = "Healing Done",
    [Enum.DamageMeterType.DamageTaken]          = "Damage Taken",
    [Enum.DamageMeterType.AvoidableDamageTaken] = "Avoidable Damage Taken",
    [Enum.DamageMeterType.EnemyDamageTaken]     = "Enemy Damage Taken",
    [Enum.DamageMeterType.Interrupts]           = "Interrupts",
    [Enum.DamageMeterType.Dispels]              = "Dispels",
    [Enum.DamageMeterType.Deaths]               = "Deaths",
}

DM.SESSION_TYPE_NAMES = {
    [Enum.DamageMeterSessionType.Current] = "Current",
    [Enum.DamageMeterSessionType.Overall] = "Overall",
}

---------------------------------------------------------------------------------
-- Render dispatch
--
-- Tick repaints every visible window from the current sessions, under a per-frame
-- UI budget. If a window's render would push the frame over budget it is deferred
-- whole (never split mid-window) to a single next-frame C_Timer.After. The
-- session cache is wiped at the head of every Tick so each frame reads fresh
-- secret-safe session tables, but identical (sessionType, dmType, sessionID)
-- lookups within one Tick hit the cache instead of re-calling the API.
---------------------------------------------------------------------------------

-- Memoizes GetSession for the duration of a single Tick. The cache key uses ONLY
-- the non-secret inputs (sessionID / sessionType / dmType are plain values, never
-- secret); the returned session table itself may carry secret fields, but those
-- are never touched here. A nil result is stored as `false` so a genuine "no
-- session" answer is cached too (avoids re-calling the API every window for an
-- empty segment); the caller treats `false` as "no session".
function DM:CachedSession(sessionType, dmType, sessionID)
    self._sessionCache = self._sessionCache or {}

    local key = (sessionID and ("id:" .. sessionID) or ("t:" .. sessionType)) .. ":" .. dmType

    local cached = self._sessionCache[key]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local session = self:GetSession(sessionType, dmType, sessionID)
    self._sessionCache[key] = session or false
    return session
end

-- Returns the array of currently-enabled runtime windows. Phase 1: only window 1,
-- and only when its resolved context config is enabled. Builds window 1's frame
-- tree on demand if it doesn't exist yet (e.g. Tick reached before OnEnable's
-- explicit create, or after a future DB-driven rebuild). Multi-window/dock is a
-- later phase; this returns at most one window.
function DM:VisibleWindows()
    self._visibleWindows = self._visibleWindows or {}
    local out = self._visibleWindows
    for i = #out, 1, -1 do out[i] = nil end

    local cfg = self:ResolveWindowConfig(1)
    if not cfg or not cfg.Enabled then
        return out
    end

    self.windows_rt = self.windows_rt or {}
    local W = self.windows_rt[1]
    if not W then
        W = self:CreateWindow(1)
    end

    out[#out + 1] = W
    return out
end

-- Repaints every visible window under a per-frame UI budget. Whole-window spill
-- only: if rendering a window would push the elapsed frame time over the budget,
-- that window (and every window after it) is deferred to the next frame rather
-- than splitting a single window's bar loop across frames. The session cache is
-- wiped here so each Tick starts from fresh API reads.
function DM:Tick()
    self._sessionCache = self._sessionCache or {}
    wipe(self._sessionCache)

    -- Pre-allocated, wiped per Tick (matches _sessionCache / _visibleWindows):
    -- in the common Phase 1 case (one window, always within budget) this table
    -- is never populated, so reusing it allocates zero garbage on the hot path.
    self._deferred = self._deferred or {}
    local deferred = self._deferred
    wipe(deferred)

    local frameStart = debugprofilestop()
    local budget = (self.db and self.db.UIBudgetMs) or 1.2

    for _, W in ipairs(self:VisibleWindows()) do
        if (debugprofilestop() - frameStart) > budget then
            deferred[#deferred + 1] = W
        else
            self:RenderWindow(W)
        end
    end

    if #deferred > 0 then
        C_Timer.After(0, function()
            for _, W in ipairs(deferred) do
                DM:RenderWindow(W)
            end
        end)
    end
end
