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

-- Module state. editModeRegistered tracks whether the dock mover is currently
-- registered with KE.EditMode; initialized here (mirrors NoMovementAlert,
-- RaidNotifications, EnemyCounter, etc.) so the guard in RegWithEditMode reads a
-- concrete false rather than nil on first access.
DM.editModeRegistered = false

-- File-level upvalues for globals used in per-tick / per-bar render paths.
local IsInInstance = IsInInstance
local C_ChallengeMode = C_ChallengeMode
local AbbreviateNumbers = AbbreviateNumbers
local CreateAbbreviateConfig = CreateAbbreviateConfig
local issecretvalue = issecretvalue
local debugprofilestop = debugprofilestop
local wipe = wipe
local C_CVar = C_CVar
local C_DeathRecap = C_DeathRecap
local format = string.format
local floor = math.floor

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
-- Live settings apply
--
-- The single entry point the GUI calls after any appearance/structure change.
-- Re-applies per-window geometry + visuals to the create-once pools, re-tiles the
-- dock, re-skins/re-sizes the backdrop, and paints one frame. User-driven (never
-- per combat tick), so iterating every built window's pool is acceptable cost.
---------------------------------------------------------------------------------

function DM:ApplySettings()
    if not self.db then self:UpdateDB() end
    if not self.enabled then return end

    self.windows_rt = self.windows_rt or {}
    for _, W in pairs(self.windows_rt) do
        if W.frame then
            self:ApplyWindowGeometry(W)
            self:ReapplyBarVisuals(W)
        end
    end

    self:LayoutDock()
    self:UpdateBackdrop()
    if self.Tick then self:Tick() end
end

---------------------------------------------------------------------------------
-- Blizzard meter replacement
--
-- When ReplaceBlizzard is on, suppress Blizzard's built-in damage meter via the
-- damageMeterEnabled CVar ("0" = off). When off, restore it ("1"). Guarded +
-- pcall'd: the CVar is settable in combat, but a future Blizzard rename must not
-- throw. Confirmed in the Phase 0 dry-run as the disable CVar.
---------------------------------------------------------------------------------

function DM:ApplyReplaceBlizzard()
    if not (C_CVar and C_CVar.SetCVar) then return end
    -- Always suppress Blizzard's built-in meter while KE's is enabled -- nobody
    -- wants two meters, so this is unconditional (no DB toggle). Only ever called
    -- from OnEnable; RestoreBlizzardMeter brings the built-in meter back on disable.
    pcall(C_CVar.SetCVar, "damageMeterEnabled", "0")
end

-- Called on OnDisable: always restore Blizzard's meter so disabling KE's meter
-- never leaves the player with no meter at all.
function DM:RestoreBlizzardMeter()
    if not (C_CVar and C_CVar.SetCVar) then return end
    pcall(C_CVar.SetCVar, "damageMeterEnabled", "1")
end

---------------------------------------------------------------------------------
-- EditMode registration
--
-- The dock is the positioned frame. Registered only when not Locked; the GUI Lock
-- toggle calls RegWithEditMode / UnregisterEditMode to add/remove the mover.
-- getPosition / setPosition read+write the SAME db.Position table (no drift).
---------------------------------------------------------------------------------

function DM:RegWithEditMode()
    if not KE.EditMode then return end
    if self.db and self.db.Locked then return end
    if self.editModeRegistered then return end
    self:EnsureDock()
    KE.EditMode:RegisterElement({
        key = "DamageMeter",
        displayName = "Damage Meter",
        frame = self.dock,
        getPosition = function()
            return self.db and self.db.Position
        end,
        setPosition = function(pos)
            if not self.db then return end
            self.db.Position = pos
            KE:ApplyFramePosition(self.dock, self.db.Position, self.db)
            self:RefreshDock()
        end,
        guiPath = "DamageMeter",
    })
    self.editModeRegistered = true
end

function DM:UnregisterEditMode()
    if KE.EditMode and KE.EditMode.UnregisterElement then
        KE.EditMode:UnregisterElement("DamageMeter")
    end
    self.editModeRegistered = false
end

-- GUI Lock toggle entry point: register or unregister the dock mover and refresh
-- any live overlay so the change is visible immediately in /kes edit.
function DM:ApplyLockState()
    -- Dismiss any open view-selector before (un)registering the mover so the picker
    -- doesn't sit over the bars while the dock is repositioned in EditMode.
    if self.CloseAllSelectors then self:CloseAllSelectors() end
    if self.CloseAllSegmentMenus then self:CloseAllSegmentMenus() end
    if self.db and self.db.Locked then
        self:UnregisterEditMode()
    else
        self:RegWithEditMode()
    end
    if KE.EditMode and KE.EditMode.isActive and KE.EditMode.RefreshOverlays then
        KE.EditMode:RefreshOverlays()
    end
end

---------------------------------------------------------------------------------
-- Preview Manager hooks
--
-- The dock is a persistent always-on frame (the shared backdrop shows whenever a
-- window is placed), so ShowPreview just guarantees a fresh layout + paint while
-- the GUI is open, and HidePreview is a no-op (it must NOT hide the user's real
-- dock). ShowPreview/HidePreview are idempotent per the PreviewManager cache.
---------------------------------------------------------------------------------

-- Toggles the large per-window index badges (a GUI preview / edit aid so the
-- "Window N" config rows map to the numbered window on screen). Sets _badgesShown
-- so a window built later (AddWindow during preview) shows its badge immediately.
-- A badge is a child of its window frame, so a hidden (disabled-context) window's
-- badge stays hidden regardless.
function DM:SetWindowBadges(show)
    self._badgesShown = show
    if not self.windows_rt then return end
    for _, W in pairs(self.windows_rt) do
        if W.indexBadge then
            if show then W.indexBadge:Show() else W.indexBadge:Hide() end
        end
    end
end

function DM:ShowPreview()
    if not self.enabled then return end
    self._hidden = false
    -- GUI open: bypass the HideOutOfCombat / OnlyInInstances conditions (ShouldShow
    -- honors _guiPreview) so a user with a hide condition enabled can still see + position
    -- the meter while configuring it. Cleared in HidePreview when the GUI closes.
    self._guiPreview = true
    self:EnsureDock()
    self:SetWindowBadges(true)
    self:RefreshDock()
    if self.Tick then self:Tick() end
end

function DM:HidePreview()
    -- The dock is persistent (must NOT hide the user's real dock); only the
    -- preview-only window badges are turned off here.
    self:SetWindowBadges(false)
    -- GUI closed: drop the preview override and re-evaluate the hide conditions so the
    -- meter re-hides if HideOutOfCombat / OnlyInInstances now say it should. UpdateBackdrop
    -- (Dock.lua) is resolved at runtime; guard for load order.
    self._guiPreview = false
    if self.UpdateBackdrop then self:UpdateBackdrop() end
end

---------------------------------------------------------------------------------
-- Slash command: /kedm
--
-- Registered via AceConsole (the module mixes in AceConsole-3.0), so no SLASH_*
-- global is declared. Subcommands: toggle (show/hide dock), reset (clear all
-- combat sessions). Bare /kedm toggles the dock.
---------------------------------------------------------------------------------

function DM:ToggleDock()
    self._hidden = not self._hidden
    self:RefreshDock()
end

function DM:HandleSlash(input)
    local arg = (input or ""):match("^%s*(%S*)"):lower()
    if arg == "reset" then
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            pcall(C_DamageMeter.ResetAllCombatSessions)
        end
        if self.Tick then self:Tick() end
        KE:Print("Damage Meter: sessions reset.")
    else
        -- "" or "toggle" (or anything else) -> toggle dock visibility.
        self:ToggleDock()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function DM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
    -- AceConsole (mixed in at NewModule) — available in OnInitialize, runs once.
    self:RegisterChatCommand("kedm", "HandleSlash")
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
    -- PvP match end: arenas / battlegrounds can leave the player combat-tagged inside the
    -- closed instance with no live fighting, so UnitAffectingCombat stays true and the
    -- shared ticker would poll C_DamageMeter forever. Force it down on match completion and
    -- suppress the UNIT_FLAGS auto-restart until the player zones out (mirrors EUI's PvP
    -- match-end stop). See OnPvPMatchComplete + the _pvpMatchOver guard in OnUnitFlags.
    self:RegisterEvent("PVP_MATCH_COMPLETE", "OnPvPMatchComplete")
    self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", "OnSessionUpdated")
    -- CURRENT_SESSION_UPDATED fires for the live segment during the post-combat
    -- finalization burst; route it through the same combat-gated, debounced
    -- handler so out-of-combat Current-window totals settle (in combat the ticker
    -- owns repaints and OnSessionUpdated early-returns, so this adds no hot work).
    self:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED", "OnSessionUpdated")
    self:RegisterEvent("DAMAGE_METER_RESET", "OnMeterReset")

    -- Content-context auto-swap (Phase 3): re-resolve each window's per-context config
    -- when the player changes content. PLAYER_ENTERING_WORLD (registered above for the
    -- ticker) + ZONE_CHANGED_NEW_AREA go through the DEBOUNCED settle path (IsInInstance
    -- isn't reliable until the world loads). The CHALLENGE_MODE_* events catch the
    -- Dungeon<->Mythic+ keystone transitions -- IsInInstance stays "party" across a
    -- keystone start (only the challenge flag flips), so PEW alone wouldn't see it --
    -- and apply IMMEDIATELY: IsChallengeModeActive is reliable the instant they fire, so
    -- debouncing them would only lag the swap (and a pending zone check could swallow it).
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnContextEvent")
    self:RegisterEvent("CHALLENGE_MODE_START", "OnChallengeEvent")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnChallengeEvent")
    self:RegisterEvent("CHALLENGE_MODE_RESET", "OnChallengeEvent")

    -- Reset the cached context so the first scheduled check always applies the live
    -- context once (a stale cache would make it think nothing changed).
    self._activeContext = nil
    self._ctxCheckPending = false

    -- Test-scaffold seed / self-heal (Dock.lua). When DEBUG_DOCK_TEST is true this
    -- seeds the demo 3-window/2-column dock; when false-but-previously-seeded it
    -- restores the single-window default and clears the marker. Runs BEFORE the
    -- window seed below so the seed sees the restored Dock.Columns. The
    -- non-underscore method is resolved at runtime (Dock.lua loads after Core.lua).
    if self.MaybeSeedDockTest then self:MaybeSeedDockTest() end

    -- Seed window 1 with a Default context if the user has never configured one.
    -- The dock references its window set from db.Dock.Columns; window 1 is the
    -- single-window default's only referenced index. Stored under Contexts.Default;
    -- the live content context resolves to this when no per-context override exists.
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

    -- Build the shared dock + every referenced window. EnsureDock creates the
    -- backdrop frame and positions it (ApplyFramePosition is now the dock's job,
    -- not a per-window call); CreateAllWindows spreads window creation one-per-
    -- frame (login hitch avoidance) and finishes with LayoutDock -> UpdateBackdrop
    -- -> Tick, so no explicit paint is needed here.
    self:EnsureDock()
    self:CreateAllWindows()

    -- Settle the initial content context shortly after enable. Covers /reload inside
    -- an instance (IsInInstance can be unreliable at OnEnable time, and the login
    -- PLAYER_ENTERING_WORLD may have fired before this handler registered).
    self:_ScheduleContextCheck()

    -- Suppress Blizzard's built-in meter when configured, and register the dock
    -- with EditMode (unless Locked). Both are idempotent / guarded.
    self:ApplyReplaceBlizzard()
    self:RegWithEditMode()

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
    self._pvpMatchOver = false
    self._activeContext = nil
    self._ctxCheckPending = false

    -- Hand the meter back to Blizzard and drop the EditMode mover.
    self:RestoreBlizzardMeter()
    self:UnregisterEditMode()

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
        -- Group combat ended: route through StopTicker (idempotent -- null-checks the
        -- ticker, clears _needsFinalRefresh, paints) so this self-cancel path runs the SAME
        -- combat-end funnel as the normal path, including RefreshVisibility. Without that,
        -- a HideOutOfCombat dock would stay visible after a died-mid-pull fight ended until
        -- the next unrelated transition happened to refresh it. Cancelling from inside the
        -- ticker's own callback is safe (the prior inline Cancel did the same).
        if DEBUG_DM then KE:Print("[DM] _RunTick: group left combat -> StopTicker (final paint + visibility)") end
        self:StopTicker()
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

    -- The ticker only runs in combat, so its start/stop are the canonical combat
    -- on/off funnel for the HideOutOfCombat visibility condition: reveal the dock here
    -- (RefreshVisibility is a no-op unless a hide condition is enabled). Resolved at
    -- runtime (Dock.lua loads after Core.lua).
    if self.RefreshVisibility then self:RefreshVisibility() end

    if DEBUG_DM then
        KE:Print("[DM] StartTicker: rate " .. tostring(rate))
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

    -- Combat fully ended (every stop path funnels through here): hide the dock if the
    -- HideOutOfCombat condition is on. No-op unless a hide condition is enabled, and
    -- self.enabled-guarded inside so an OnDisable-time stop doesn't re-show it.
    if self.RefreshVisibility then self:RefreshVisibility() end

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
    -- Genuine new combat overrides a prior PvP match-end suppression (lets the ticker
    -- re-arm if real fighting somehow resumes in the same instance).
    self._pvpMatchOver = false
    -- A hover tip that persists into combat must flip to the "secret while in combat"
    -- message on the next poll: mark it dirty (the throttled poll only re-populates on
    -- a dirty signal). Resolved-at-runtime field on DM read by the Detail.lua poll.
    self._hoverTipDirty = true
    -- Close any open (out-of-combat-only) detail panel so combat shows the live bars
    -- instead of a frozen pre-combat breakdown over a now-hidden body. CloseDetail is
    -- nil-safe and a no-op when nothing is open.
    if self.windows_rt then
        for _, W in pairs(self.windows_rt) do
            if W._detailOpen and self.CloseDetail then self:CloseDetail(W) end
            -- New fight = fresh list: scroll each pane back to the top so rank 1 shows.
            -- Otherwise a scroll offset left over from the last fight would open the new
            -- one mid-list. RenderWindow recomputes _scrollMax against the new count.
            if W.body then W.body:SetVerticalScroll(0) end
        end
    end
    -- Same for the view-selector overlay: a selector left open before the pull would
    -- keep W.body hidden for the whole fight (RenderWindow only Show()s W.frame, never
    -- W.body) -- close it so the live bars render. Mirrors the detail-close above.
    if self.CloseAllSelectors then self:CloseAllSelectors() end
    if self.CloseAllSegmentMenus then self:CloseAllSegmentMenus() end
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
    -- Combat ended for the player: a hover tip showing the in-combat "secret" message
    -- should re-populate with real (now-readable) data on the next poll -- mark dirty.
    self._hoverTipDirty = true

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
    -- Segment boundary: a boss pull starts a new segment, so a view override from the
    -- previous boss/trash clears ("until another raid boss starts").
    self:BumpSegment()
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
    -- Zoning clears any PvP match-end suppression: a new instance/world is a clean slate
    -- for the UNIT_FLAGS auto-restart (the just-left arena no longer applies).
    self._pvpMatchOver = false
    self:StopTicker()
    -- Zoning may change the content context (entered/left an instance) -- schedule a
    -- settled re-check (debounced; IsInInstance isn't reliable until the world loads).
    self:_ScheduleContextCheck()
end

-- A group member's flags changed (often: they entered combat before us). Start
-- the ticker if the group is fighting and we're not already ticking, so bars
-- populate before the player is tagged.
function DM:OnUnitFlags()
    -- After a PvP match completes the player stays combat-tagged in the closed instance,
    -- so UNIT_FLAGS would keep re-arming the ticker against GroupInCombat. Suppress the
    -- auto-restart until a genuine new combat (OnRegenDisabled) or a zone-out
    -- (OnCombatForceStop) clears the flag -- otherwise OnPvPMatchComplete's stop is undone.
    if self._pvpMatchOver then return end
    if self:GroupInCombat() and not self._ticker then
        if DEBUG_DM then KE:Print("[DM] UNIT_FLAGS -> group in combat, StartTicker") end
        self:StartTicker()
    end
end

-- A PvP match (arena / battleground) completed. The player can stay combat-tagged in the
-- closed instance with no live fighting, so UnitAffectingCombat stays true and the shared
-- ticker would poll C_DamageMeter every RefreshRate forever. Force the ticker down (the
-- final paint settles the post-match totals) and raise _pvpMatchOver so the UNIT_FLAGS
-- auto-restart stays suppressed until a real new combat or a zone-out clears it. Plain
-- event with no payload read -- never a secret. Mirrors EUI's PvP match-end stop.
function DM:OnPvPMatchComplete()
    if DEBUG_DM then KE:Print("[DM] PVP_MATCH_COMPLETE -> force StopTicker + suppress restart") end
    self._inEncounter = false
    self._pvpMatchOver = true
    self:StopTicker()
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
        -- A settling session means a hovered tip's numbers may have changed: mark dirty so
        -- the throttled hover poll re-populates once (post-combat finalize window).
        DM._hoverTipDirty = true
        if DEBUG_DM then KE:Print("[DM] DAMAGE_METER_COMBAT_SESSION_UPDATED (debounced) -> Tick") end
        if DM.Tick then DM:Tick() end
    end)
end

-- Meter data was reset: repaint immediately so cleared bars show. Tick is
-- guarded (resolved at runtime from the render chunk).
function DM:OnMeterReset()
    if DEBUG_DM then KE:Print("[DM] DAMAGE_METER_RESET -> Tick") end
    -- Drop the hover-tip Targets cache (Phase 4c / Detail.lua) -- the EnemyDamageTaken
    -- cross-reference it was built from is now stale. Resolved at runtime (Detail.lua
    -- loads after Core.lua); guarded so a load-order or version skew can't throw.
    if self.InvalidateTargetsCache then self:InvalidateTargetsCache() end
    -- The data is wiped: a hovered tip must re-populate (or clear) on the next poll.
    self._hoverTipDirty = true
    -- A reset empties the bars; close any open selector so the cleared bars show
    -- (DAMAGE_METER_RESET can fire from an external reset with a selector still open).
    if self.CloseAllSelectors then self:CloseAllSelectors() end
    if self.CloseAllSegmentMenus then self:CloseAllSegmentMenus() end
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
        if DEBUG_DM then KE:Print("[DM] GetSession FromID failed: " .. tostring(session)) end
        return nil
    end

    if not C_DamageMeter.GetCombatSessionFromType then return nil end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, dmType)
    if ok then return session end
    if DEBUG_DM then KE:Print("[DM] GetSession FromType failed: " .. tostring(session)) end
    return nil
end

-- Returns the per-source detail table for a single combat source (keyed by
-- sourceGUID), or nil on failure. Mirrors GetSession's FromID/FromType branch.
function DM:GetSource(sessionType, dmType, sourceGUID, sourceCreatureID, sessionID)
    if not C_DamageMeter then return nil end

    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionSourceFromID then return nil end
        local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionID, dmType, sourceGUID, sourceCreatureID)
        if ok then return source end
        if DEBUG_DM then KE:Print("[DM] GetSource FromID failed: " .. tostring(source)) end
        return nil
    end

    if not C_DamageMeter.GetCombatSessionSourceFromType then return nil end
    local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, dmType, sourceGUID, sourceCreatureID)
    if ok then return source end
    if DEBUG_DM then KE:Print("[DM] GetSource FromType failed: " .. tostring(source)) end
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
-- The render layer reads self.db.NumberFormat once before the bar loop and calls
-- this file-local directly, rather than re-reading the DB per bar through a
-- method wrapper.
---------------------------------------------------------------------------------

-- Precision config for AbbreviateNumbers (verbatim port of EllesmereUI's
-- _abbreviateCfg). AbbreviateNumbers is the ONLY secret-safe abbreviator; the
-- bare call rounds to whole units ("43M"), but passing this config makes it emit
-- decimals ("43.81M" / "273.8K") even on a SECRET in-combat amount -- the
-- function consumes the secret internally, so we never run string.format /
-- arithmetic on a secret (which would taint). Guarded on CreateAbbreviateConfig;
-- if absent, _abbreviateCfg stays nil and AbbreviateNumbers(n, nil) degrades to
-- the plain (no-decimal) but still secret-safe path. Matches Details' precision:
-- 2 decimals at M/B, 1 at K.
local _abbreviateCfg
do
    local opts = {
        { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1000000,    abbreviation = "M", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1000,       abbreviation = "K", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
        { breakpoint = 1,          abbreviation = "",  significandDivisor = 1,         fractionDivisor = 1,   abbreviationIsGlobal = false },
    }
    if CreateAbbreviateConfig then
        _abbreviateCfg = { config = CreateAbbreviateConfig(opts) }
    end
end

-- Secret-safe single-amount formatter. `n` is nil-guarded with a truthiness gate
-- (NOT `== nil`, which taints on a secret number). AbbreviateNumbers(n, cfg) is
-- secret-safe and decimal-capable; the returned string is secret iff `n` is.
local function FormatAmount(n)
    if not n then return "0" end
    return AbbreviateNumbers(n, _abbreviateCfg) or "0"
end

-- Returns (string, isSecret). `mode` selects the layout (Number Format setting):
--   "Both"   -> "total | perSec"  (both; perSec half omitted if perSec is nil)
--   "PerSec" -> "perSec"          (rate only; falls back to total if no rate)
--   else     -> "total"           (amount only; also the Detail breakdown's mode=false)
-- Concatenating two AbbreviateNumbers results is documented-safe even when secret;
-- issecretvalue on the result tells the render layer whether it may dirty-check it.
-- The Detail breakdown/recap surfaces pass `false` as the mode (amount-only path).
local function FormatBarValue(total, perSec, mode)
    if mode == "PerSec" then
        -- Rate-only. A meter type without a per-second (or a nil rate) falls back to the
        -- total so the bar value is never blank.
        local n = perSec or total
        if not n then return "", false end
        local s = FormatAmount(n)
        return s, issecretvalue(s)
    end

    if not total then return "", false end

    local str
    if mode == "Both" and perSec then
        str = FormatAmount(total) .. " | " .. FormatAmount(perSec)
    else
        str = FormatAmount(total)
    end

    return str, issecretvalue(str)
end

-- Death-time formatter for the Deaths meter type (mirrors EllesmereUI FormatTimer).
-- deathTimeSeconds is secret in combat, so the M:SS arithmetic only runs on a
-- plain value -- a secret/nil time yields "0:00". Returns (string, false): the
-- result is never itself a secret, so the render layer dirty-checks it normally.
local function FormatDeathTime(sec)
    if not sec or issecretvalue(sec) then return "0:00", false end
    return format("%d:%02d", floor(sec / 60), floor(sec % 60)), false
end

-- Cross-chunk API: the render layer calls these directly. Non-underscore names
-- because they are intentional public API on DM (underscore-prefix fields are
-- private-to-file by KE convention); matches DM.RANK_STRINGS / DM.BAR_POOL_SIZE
-- in Window.lua.
DM.FormatBarValue = FormatBarValue
DM.FormatDeathTime = FormatDeathTime

-- Returns the reversed (oldest-first) recap event list + maxHealth for a deathRecapID, or
-- nil. C_DeathRecap is a separate namespace (NOT C_DamageMeter); none of its getters is
-- SecretWhenInCombat, and recap data is post-death, so these are read out of combat only
-- (OpenDetail is OOC-gated). All calls pcall'd; deathRecapID is NeverSecret on the source.
function DM:GetDeathRecap(recapID)
    if not C_DeathRecap then return nil end
    if not recapID or issecretvalue(recapID) or recapID <= 0 then return nil end
    if C_DeathRecap.HasRecapEvents then
        local okh, has = pcall(C_DeathRecap.HasRecapEvents, recapID)
        -- HasRecapEvents is AllowedWhenUntainted -> `has` can be a secret BOOLEAN in a
        -- tainted call path. A truthiness test on a secret boolean throws, so bail out
        -- (treat secret as "no recap") rather than crash on the `not has` test.
        if not okh or issecretvalue(has) or not has then return nil end
    end
    local ok, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not ok or not raw or #raw == 0 then return nil end
    local maxHP = 1
    if C_DeathRecap.GetRecapMaxHealth then
        local okm, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
        if okm and hp and type(hp) == "number" and hp > 0 then maxHP = hp end
    end
    -- API returns newest-first; reverse to oldest-first into a per-call table (recap is a
    -- rare user action, so a fresh table is fine — not a hot path).
    local rev = {}
    for i = #raw, 1, -1 do rev[#rev + 1] = raw[i] end
    return rev, maxHP
end

-- "-3.4s" style time-before-death. deathTime = the last (most recent) event's timestamp.
local function FormatRecapDelta(deathTime, ts)
    if not ts or not deathTime then return "" end
    -- Operands come from C_DeathRecap (AllowedWhenUntainted): either timestamp can be a
    -- secret number in a tainted context. Subtraction on a secret throws — bail to "".
    if issecretvalue(ts) or issecretvalue(deathTime) then return "" end
    return format("-%.1fs", deathTime - ts)
end
DM.FormatRecapDelta = FormatRecapDelta

---------------------------------------------------------------------------------
-- Header-icon callbacks (Phase 4)
--
-- Wired by the three header buttons built in Window.lua CreateWindow. The window
-- handle is passed through (unused by Settings/Reset today, but kept so a future
-- per-window action has it). ToggleSegmentMenu (the ⌚ button) is implemented in the
-- Segment / history browser section below.
---------------------------------------------------------------------------------

-- Settings: open the GUI straight to the Damage Meter page (combat section).
function DM:HeaderSettings(_)
    if KE.GUIFrame and KE.GUIFrame.OpenPage then
        KE.GUIFrame:OpenPage("DamageMeter", "combat_section")
    end
end

-- Reset: clear all combat sessions, then repaint so the bars empty immediately.
-- ResetAllCombatSessions is nil-guarded + pcall'd (12.0 API surface may shift).
function DM:HeaderReset(_)
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        pcall(C_DamageMeter.ResetAllCombatSessions)
    end
    -- Drop the hover-tip Targets cache too: the EnemyDamageTaken cross-reference it
    -- was built from is wiped (DAMAGE_METER_RESET would also catch this, but the
    -- explicit call mirrors the plan and covers a reset that doesn't fire the event).
    if self.InvalidateTargetsCache then self:InvalidateTargetsCache() end
    -- Close any open detail panel: its breakdown/recap was keyed to the data we just
    -- wiped, so drop back to the freshly-emptied bars (mirrors the combat-start close
    -- in OnRegenDisabled). All windows, since ResetAllCombatSessions is global.
    if self.windows_rt then
        for _, w in pairs(self.windows_rt) do
            if w._detailOpen and self.CloseDetail then self:CloseDetail(w) end
        end
    end
    -- Close any open view-selector too so the freshly-emptied bars are visible (the
    -- selector overlays the body with the same anchors, so it would block them).
    if self.CloseAllSelectors then self:CloseAllSelectors() end
    if self.CloseAllSegmentMenus then self:CloseAllSegmentMenus() end
    if self.Tick then self:Tick() end
end

---------------------------------------------------------------------------------
-- Segment / history browser (Phase 4)
--
-- W._curSessionID is the single per-window pinned-session field (NOT persisted --
-- stored sessions are gone after a reload): nil = the live cfg.SessionType
-- (Current/Overall), non-nil = a specific stored session read via the FromID API
-- branch in CachedSession/GetSession. The ⌚ menu lists the last ~20 available
-- combat sessions plus a Current/Overall pair, rendered by a custom hover dropdown
-- (SegmentMenu.lua) that opens upward from the icon -- replacing the Blizzard MenuUtil
-- context menu, which can't open on hover, grow upward, or carry KE's contrast styling.
-- The data helpers below stay here (backend); the presentation lives in SegmentMenu.lua.
---------------------------------------------------------------------------------

-- Last `cap` available combat sessions (newest last), or nil. The API call is
-- pcall'd (it may reject while execution is tainted); name/durationSeconds on each
-- entry are display-only and secret-guarded by SafeSessionName / FormatDeathTime at
-- render time, never compared or math'd raw. The full API list is trimmed here to
-- the last `cap` entries so the caller gets exactly the contract the name promises.
function DM:GetAvailableSessions(cap)
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return nil end
    local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or not list then return nil end
    cap = cap or 20
    if #list <= cap then return list end
    -- Keep only the newest `cap` entries (sessions are a plain array, no secrets in
    -- the indices), preserving order so the newest fights stay nearest the button.
    local trimmed = {}
    for i = #list - cap + 1, #list do
        trimmed[#trimmed + 1] = list[i]
    end
    return trimmed
end

-- "Combat" fallback when a session name is secret/empty (mirrors EllesmereUI:1881).
-- A secret string is fine to SetText but must never be == compared, so the empty
-- check is gated behind issecretvalue first.
function DM:SafeSessionName(name)
    if not name or issecretvalue(name) or name == "" then return "Combat" end
    return name
end

-- Sets the window's pinned session and repaints. sessionID nil = back to the live
-- session; for the Current/Overall picks the chosen SessionType is also persisted
-- into the window's active per-context config so it survives the next layout pass
-- (stored-session pins are runtime-only and intentionally NOT persisted). Closes any
-- open detail panel (its breakdown was keyed to the old session) and ticks once.
function DM:SelectSegment(W, sessionID, sessionType)
    W._curSessionID = sessionID
    if sessionID == nil and sessionType ~= nil then
        local cfg = self:ResolveWindowConfig(W.idx)
        if cfg then cfg.SessionType = sessionType end
    end
    if self.CloseDetail then self:CloseDetail(W) end
    if self.Tick then self:Tick() end
end

-- The ⌚ segment/history picker is rendered by SegmentMenu.lua as a custom hover
-- dropdown (DM:OpenSegmentMenu / ToggleSegmentMenu / CloseAllSegmentMenus). The data
-- helpers above (GetAvailableSessions / SafeSessionName / SelectSegment) feed it.

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

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Segment token + view override (Selector.lua)            ║
-- ╚══════════════════════════════════════════════════════════╝

-- Bump the persisted segment serial. Called at each combat-segment boundary so a
-- view override tagged with the previous serial stops matching (and clears on next
-- read). Plain integer -- never secret. Persisted, so it survives /reload.
function DM:BumpSegment()
    if not self.db then return end
    self.db._SegSerial = (self.db._SegSerial or 0) + 1
    -- A segment boundary invalidates any view override (its token no longer matches),
    -- so dismiss any open view-selector too: its highlight is now stale and the live
    -- bars should show. Resolved at runtime (Selector.lua loads after Core.lua).
    if self.CloseAllSelectors then self:CloseAllSelectors() end
    if self.CloseAllSegmentMenus then self:CloseAllSegmentMenus() end
    if DEBUG_DM then KE:Print("[DM] segment -> " .. self.db._SegSerial) end
end

-- The current segment token (plain integer). A window ViewOverride whose stored
-- token equals this is still "this segment"; any other value means a boundary passed.
function DM:CurrentSegmentToken()
    return (self.db and self.db._SegSerial) or 0
end

-- The meter type a window should actually display, honoring a live in-world view
-- override (right-click selector, Selector.lua). `cfg` is the resolved per-context
-- config (ResolveWindowConfig); cfg.MeterType is the configured/auto-swap value.
-- When the window has a ViewOverride whose token still matches the current segment,
-- the override wins WITHOUT mutating cfg (a live db reference SelectSegment writes
-- to). A stale override (token from a passed segment) is cleared lazily here and the
-- configured type is used. All plain enums/integers -- never secret -- so the
-- equality tests are taint-safe.
function DM:EffectiveMeterType(winIdx, cfg)
    local windows = self.db and self.db.Windows
    local window = windows and windows[winIdx]
    local ov = window and window.ViewOverride
    if ov == nil then
        return cfg and cfg.MeterType
    end
    if window.ViewOverrideToken == self:CurrentSegmentToken() then
        return ov
    end
    window.ViewOverride = nil
    window.ViewOverrideToken = nil
    return cfg and cfg.MeterType
end

-- In-world view pick (right-click selector, Selector.lua). Writes a per-window view
-- override tagged with the current segment token (so it persists -- including across
-- /reload -- until the user re-picks or a segment boundary passes), drops any pinned
-- history session so the new view shows live data (a pin from the old meter type
-- wouldn't map to the new type's sessions; CachedSession keys on
-- (sessionType, meterType, sessionID)), closes the detail panel (its breakdown/recap
-- was keyed to the old view), closes the selector, and repaints. meterType is a plain
-- Enum.DamageMeterType value -- never secret.
function DM:SetWindowView(W, meterType)
    if not W then return end
    local windows = self.db and self.db.Windows
    local window = windows and windows[W.idx]
    if not window then return end
    window.ViewOverride = meterType
    window.ViewOverrideToken = self:CurrentSegmentToken()
    W._curSessionID = nil
    if self.CloseDetail then self:CloseDetail(W) end
    if self.CloseSelector then self:CloseSelector(W) end
    if self.Tick then self:Tick() end
end

-- Auto-swap runtime: re-apply the live content context. If it changed since the last
-- apply, re-layout (LayoutDock re-resolves each window's per-context Enabled, and the
-- render re-reads the active Type/Segment) and repaint. The resolver above is the
-- single source of truth; this only drives WHEN it is re-read. Synchronous
-- layout->backdrop->tick (NOT the debounced RefreshDock) so the paint lands after the
-- new layout settles -- mirrors CreateAllWindows; context swaps are rare (zone /
-- keystone) so a direct layout is cheap. The enabled guard makes a late timer fired
-- after OnDisable a no-op. Plain instance/keystone reads only -- never a secret.
function DM:ApplyActiveContext()
    if not self.enabled then return end
    local ctx = self:GetActiveContext()

    -- Segment boundary on a content-context change. Compared against the PERSISTED
    -- last-segment context (db._SegContext), NOT the runtime self._activeContext --
    -- the runtime field resets to nil on /reload, so comparing it would spuriously
    -- bump every reload and clear live overrides. The persisted copy is unchanged
    -- across a reload-in-place (serial holds, override survives); a real instance /
    -- keystone change differs and bumps.
    if self.db and ctx ~= self.db._SegContext then
        self.db._SegContext = ctx
        self:BumpSegment()
    end

    if ctx == self._activeContext then return end
    if DEBUG_DM then
        KE:Print("[DM] context " .. tostring(self._activeContext) .. " -> " .. tostring(ctx))
    end
    self._activeContext = ctx
    self:LayoutDock()
    self:UpdateBackdrop()
    if self.Tick then self:Tick() end
end

-- Debounced trigger for the "context may have changed" events. PLAYER_ENTERING_WORLD /
-- ZONE_CHANGED_NEW_AREA can fire several times during one loading screen and
-- IsInInstance isn't reliable until the world settles, so coalesce to ONE delayed
-- check (1s, matching KickTracker:OnZoneChange). Challenge-mode events apply the
-- context immediately via OnChallengeEvent (no debounce) and do NOT call this function.
function DM:_ScheduleContextCheck()
    if self._ctxCheckPending then return end
    self._ctxCheckPending = true
    C_Timer.After(1, function()
        DM._ctxCheckPending = false
        DM:ApplyActiveContext()
    end)
end

-- ZONE_CHANGED_NEW_AREA handler -> debounced settle check (PLAYER_ENTERING_WORLD
-- schedules the same way via OnCombatForceStop).
function DM:OnContextEvent()
    self:_ScheduleContextCheck()
end

-- CHALLENGE_MODE_START / COMPLETED / RESET handler. The keystone flag is reliable the
-- instant these fire, so apply immediately (no debounce) -- a delay would only lag the
-- Dungeon<->Mythic+ swap, and routing through the debounce could let a pending zone
-- check swallow it. Fires at most once per keystone, so no coalescing is needed.
function DM:OnChallengeEvent()
    -- A keystone start/complete/reset is a hard segment boundary (covers re-running a
    -- key, where the content context stays "Mythic+" so the context compare alone
    -- wouldn't catch it). A first key start may double-bump with the context change
    -- in ApplyActiveContext -- harmless (the override clears either way).
    self:BumpSegment()
    self:ApplyActiveContext()
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

-- Single source of truth for a window's human label -- the EXACT string the
-- in-world header shows ("Overall Damage Done", "Damage Done", "Deaths", ...), so
-- the GUI layout map / drag ghost / move rows all match it and can't drift. The
-- "Overall" prefix is added only for the Overall session; Current is unprefixed.
-- nil-guarded: a missing meter-type key falls back to "Damage Done". Plain enum
-- table lookups + string concat -- the enum config values are never secret.
function DM:FormatWindowLabel(meterType, sessionType)
    local typeName = self.METER_TYPE_NAMES[meterType] or "Damage Done"
    local sessName = self.SESSION_TYPE_NAMES[sessionType]
    if sessName and sessionType ~= Enum.DamageMeterSessionType.Current then
        return sessName .. " " .. typeName
    end
    return typeName
end

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

-- Returns the array of currently-enabled runtime windows, in the dock's stable
-- column-then-row order (so Tick paints deterministically). A window is included
-- when it is referenced by the dock AND its resolved context config is Enabled.
-- Any referenced window whose frame tree doesn't exist yet is built on demand
-- (e.g. Tick reached before CreateAllWindows finishes, or after a structural
-- rebuild). Reuses the pre-allocated self._visibleWindows scratch table
-- (wipe + refill) so no per-tick garbage is produced.
function DM:VisibleWindows()
    self._visibleWindows = self._visibleWindows or {}
    local out = self._visibleWindows
    for i = #out, 1, -1 do out[i] = nil end

    -- Referenced window indices in stable dock order. DockWindowIndices reuses
    -- its own scratch table (self._dockVisibleList), so this allocates nothing.
    self._dockVisibleList = self._dockVisibleList or {}
    local indices = self:DockWindowIndices(self._dockVisibleList)

    -- Active context resolved once for the whole tick; passed to each window's
    -- ResolveWindowConfig to avoid recomputing it N times.
    local context = self:GetActiveContext()

    self.windows_rt = self.windows_rt or {}
    for n = 1, #indices do
        local idx = indices[n]
        local cfg = self:ResolveWindowConfig(idx, context)
        if cfg and cfg.Enabled then
            local W = self.windows_rt[idx]
            if not W then
                W = self:CreateWindow(idx)
            end
            out[#out + 1] = W
        end
    end

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

    local frameStart = debugprofilestop()
    local budget = (self.db and self.db.UIBudgetMs) or 1.2

    -- The deferred list is allocated ONLY when spillover actually occurs and is a
    -- FRESH table each time, never a reused scratch. A reused scratch is unsafe
    -- here: the C_Timer.After(0) closure below captures the list by reference, and
    -- a subsequent Tick (e.g. StopTicker -> Tick called synchronously while a
    -- prior tick's deferred closure is still pending) would wipe it out from under
    -- the pending closure, silently dropping those deferred renders. In the common
    -- Phase 1 case (one window, always within budget) `deferred` stays nil and the
    -- hot path allocates zero tables -- matching the prior guarantee.
    local deferred = nil

    for _, W in ipairs(self:VisibleWindows()) do
        if (debugprofilestop() - frameStart) > budget then
            if not deferred then deferred = {} end
            deferred[#deferred + 1] = W
        else
            self:RenderWindow(W)
        end
    end

    if deferred then
        C_Timer.After(0, function()
            for _, W in ipairs(deferred) do
                DM:RenderWindow(W)
            end
        end)
    end
end
