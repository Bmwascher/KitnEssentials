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

-- LibSpecialization spec-icon cache: [sourceGUID] = spec icon fileID. Populated by
-- the LibSpec group callback (cold path) and read in Window.lua:RenderBar as the
-- middle tier between the API specIconID and the class-icon fallback. A player's
-- sourceGUID is a plain value at runtime, but the API doesn't mark it NeverSecret
-- (and a creature source's GUID IS secret in instances -- the EnemyDamageTaken view),
-- so the RenderBar read is issecretvalue-guarded before use as a key. Wiped on disable.
DM.specIconByGUID = {}

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
local math_min = math.min
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local IsInGuild = IsInGuild
local GetTime = GetTime
local GetNumGroupMembers = GetNumGroupMembers
local UnitGUID = UnitGUID
local Ambiguate = Ambiguate
local GetSpecializationInfoByID = GetSpecializationInfoByID
-- Current chat API. The bare global SendChatMessage is deprecated in 12.0, so capture the
-- namespaced C_ChatInfo.SendChatMessage once at load and call it under a non-colliding
-- local name (a local literally named SendChatMessage still trips the deprecation lint).
-- C_ChatInfo is a core namespace present before module files run.
local SendChat = C_ChatInfo and C_ChatInfo.SendChatMessage

-- LibSpecialization: passive group spec sharing over addon comms (RAID/PARTY/
-- INSTANCE_CHAT), the only group-spec channel that still works inside 12.0
-- instances. Optional load. The meter uses it to resolve a spec icon for sources
-- whose specIconID the client never filled in (common in a pug / cross-realm raid,
-- where C_DamageMeter returns specIconID nil) -- see the Spec icon resolution
-- section and the spec-icon block in Window.lua:RenderBar. Same lib HealerMana /
-- KickTracker / DungeonTimers already rely on.
local LibSpec = LibStub("LibSpecialization", true)

-- Pre-built group unit tokens. UNIT_FLAGS
-- can fire dozens of times per second during a pull, and GroupInCombat is hit
-- on every one; building "raid"..i / "party"..i inline on each call would churn
-- garbage. Filled once at file load and read by index inside GroupInCombat.
local _raidUnits, _partyUnits = {}, {}
for i = 1, 40 do _raidUnits[i] = "raid" .. i end
for i = 1, 4 do _partyUnits[i] = "party" .. i end

---------------------------------------------------------------------------------
-- Module-owned defaults (MPT pattern)
--
-- Canonical defaults for KE.db.profile.DamageMeter, seeded by DM:UpdateDB --
-- Core/Defaults.lua carries NO DamageMeter section (this table is the single
-- source of truth, mirroring MythicPlusTimer's MPT_DEFAULTS). Values equal to
-- the old AceDB-registered defaults were stripped from SavedVariables at
-- logout, so the seed below re-materializes them as real persisted values on
-- the first login with this build; user-changed values survive untouched
-- (saved[k] ~= nil is never overwritten). No Enum references needed here --
-- the Windows/Dock layout seed stays in OnEnable (it reads Enum at runtime).
---------------------------------------------------------------------------------

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do dst[k] = DeepCopy(v) end
    return dst
end

-- Recursive missing-key fill: a defaults key absent from the saved section is
-- deep-copied in; when BOTH sides are tables, recurse. This mirrors what
-- AceDB's copyDefaults did at every login while these defaults were still
-- registered in Core/Defaults.lua -- which is LOAD-BEARING for migration: the
-- v3.0.x releases shipped registered defaults, and AceDB's logout-time
-- removeDefaults stripped default-equal leaves and DELETED nested tables that
-- became empty. Real v3.0.x SavedVariables therefore carry holes like
-- Dock.Columns[1] = nil (the shipped layout's column 1 equals the default)
-- and Position tables with offsets but no anchors (EditMode drags preserve
-- anchors, so they matched the default and were stripped). A top-level-only
-- fill would skip those non-nil parent tables and window 1 / the dock anchor
-- would silently break on the first login after this build. Never overwrites
-- a non-nil leaf, so user-set values and user-restructured arrays (the
-- structural editors always write dense arrays) are untouched.
local function FillMissing(saved, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" and type(saved[k]) == "table" then
            FillMissing(saved[k], v)
        elseif saved[k] == nil then
            saved[k] = DeepCopy(v)
        end
    end
end

local DM_DEFAULTS = {
    Enabled = true,
    Locked = true,              -- when true, disables EditMode drag of the dock
    RefreshRate = 0.5,
    UIBudgetMs = 1.2,
    MaxWindows = 5,
    AlwaysShowSelf = false,     -- pin the player to the last visible slot when off-list
                                -- (role-relevant views only -- Window.lua PIN_ROLES)

    -- Visibility conditions (independent; ALL enabled conditions must pass for the
    -- meter to show). GUI preview / EditMode always force-show regardless.
    HideOutOfCombat = false,    -- show only while the player/group is in combat
    OnlyInInstances = false,    -- show only inside a dungeon / raid / arena / BG / scenario

    -- Bar appearance (flat, KE convention)
    BarHeight = 23,
    BarSpacing = 1,
    Width = 212,
    StatusBarTexture = "KitnUI",
    FontFace = "Expressway",
    FontSize = 14,              -- bar row text size
    HeaderFontSize = 14,        -- window header text size (independent of the bar text)
    FontOutline = "SLUG,OUTLINE",
    ShowRank = false,
    ShowIcon = true,
    ShowName = true,
    ShowRealm = false,          -- false: strip the "-Realm" suffix from cross-realm names
    UseNicknames = true,        -- show saved nicknames (Custom Nicknames) in place of bar names
    ClassColorName = false,
    -- Number Format (replaces the old ShowPerSec boolean): "Both" = amount | dps,
    -- "Amount" = amount only, "PerSec" = rate only.
    NumberFormat = "Both",
    ShowPercent = false,
    VisibleBars = 9,

    -- Bar fill color: "Class" (per-source class color), "Custom" (BarColor),
    -- "Theme" (the theme accent color). BarColorAlpha is the fill opacity (0..1).
    BarColorMode = "Class",
    BarColor = { 0.302, 0.549, 0.851 },   -- #4D8CD9 (used when BarColorMode = "Custom")
    BarColorAlpha = 1,
    -- Bar text color: the value column always; the name column when NOT class-tinted.
    BarTextColor = { 1, 1, 1 },
    -- Thin-line bar style: the colored fill is a thin strip (BarThinLineHeight px)
    -- pinned to the row's bottom edge instead of the full row; the icon + text
    -- stay full size.
    BarThinLine = false,
    BarThinLineHeight = 2,

    -- Header bar: the meter-type glyph beside the title (ShowTypeIcon) and the
    -- settings / reset / segment action buttons (ShowHeaderIcons + its mouseover-
    -- reveal). Independent toggles -- the glyph is informational, the buttons are
    -- the Phase 4 detail-surface controls.
    ShowTypeIcon = false,
    ShowHeaderIcons = true,
    HeaderIconsMouseover = true,
    ShowCombatClock = false,    -- fight-length clock "[M:SS]" on window 1's header
    DetailMaxRows = 40,

    -- Hover quick-peek tooltip (Phase 4b) -- hover a bar -> floating breakdown/recap
    HoverTooltip = true,
    -- Phase 4c: "smart" (auto side, away from the nearer screen edge) | "bar"
    -- (above the hovered bar) | "left" / "right" (beside the meter) | "center".
    HoverTooltipAnchor = "smart",

    -- Shared backdrop (flat); arrangement is owned by Dock below
    BackdropEnabled = true,                     -- off: windows render with no wrapping bg/border
    BackdropBorderStyle = "neutral",            -- neutral | accent | theme
    BackdropBorderColor = { 0, 0, 0, 1 },        -- solid black
    BackdropColor = { 0.031, 0.031, 0.031, 0.8 }, -- #080808 @ 80% opacity
    BackdropPadding = 1,
    Strata = "MEDIUM",
    Position = {
        AnchorFrom = "BOTTOMRIGHT",
        AnchorTo = "BOTTOMRIGHT",
        XOffset = -3,
        YOffset = 3,
    },

    -- Dock layout (structured: no flat equivalent)
    Dock = {
        Columns = {
            { WidthRatio = 1, Windows = { 1 }, RowRatios = { 1 } },
        },
    },

    -- Per-window per-context configs (structured); inherit Default unless present.
    -- [i] = { Contexts = { Default = { Enabled, MeterType, SessionType }, ... } }
    Windows = {},

    -- Internal segment-token bookkeeping for the in-world view selector
    -- (Selector.lua). _SegSerial is a persisted monotonic counter bumped at
    -- each combat-segment boundary (boss pull / new instance / keystone); a
    -- window's ViewOverride is tagged with it and clears when it changes.
    -- _SegContext (written at runtime, also persisted) is the last segment's
    -- content context, compared to tell a real context change from a
    -- /reload-in-place. Not user settings.
    _SegSerial = 0,

    HistoryRetain = 20,
    DeathCap = 50,
}

---------------------------------------------------------------------------------
-- DB Helper
--
-- Seeds KE.db.profile.DamageMeter from DM_DEFAULTS via the RECURSIVE
-- FillMissing above (NOT a top-level-only fill -- see its migration note; MPT's
-- top-level seed doesn't transfer because MPT never had AceDB-registered
-- defaults whose stripped SVs need deep refilling), then binds self.db.
-- NAME IS LOAD-BEARING: ProfileManager:RefreshAllModules duck-types
-- `module.UpdateDB` and re-runs this on every profile switch/copy/reset,
-- re-seeding the new profile's section and re-binding self.db. Do not rename.
---------------------------------------------------------------------------------

function DM:UpdateDB()
    local profile = KE.db.profile
    if type(profile.DamageMeter) ~= "table" then
        profile.DamageMeter = {}
    end
    FillMissing(profile.DamageMeter, DM_DEFAULTS)
    self.db = profile.DamageMeter

    -- Profile ops (switch/copy/reset) re-run UpdateDB without OnEnable; the repair
    -- is run-once-stamped per profile and signature-gated, so extra calls are free.
    if self.RepairSquishedDock then self:RepairSquishedDock() end
end

-- Busted seam (dev/spec/dm_defaults_spec.lua): expose the real seed helper as
-- a static so the headless spec exercises the actual body -- the migration
-- refill semantics above are exactly the class of behavior worth pinning.
-- Inert in-game (nothing reads this key; internal callers use the local).
DM.FillMissingDefaults = FillMissing

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
-- Suppress Blizzard's built-in damage meter via the damageMeterEnabled CVar
-- ("0" = off) while KE's meter is enabled; restore it ("1") on disable.
-- Unconditional (no DB toggle -- the vestigial ReplaceBlizzard default was
-- dropped in the module-owned defaults move). Guarded + pcall'd: the CVar is
-- settable in combat, but a future Blizzard rename must not throw. Confirmed
-- in the Phase 0 dry-run as the disable CVar.
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
-- Slash command: /kes dm <...>
--
-- Routed from Core/Globals.lua's /kes dispatcher to DM:HandleSlash (no standalone
-- chat command is registered). Subcommands: reset (clear all combat sessions);
-- report [count] [channel] (post the primary window's view to chat, out of combat);
-- anything else -- including bare "/kes dm" or "/kes dm toggle" -- toggles the dock.
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
    elseif arg == "report" then
        -- Everything after the "report" token is the optional "[count] [channel]" tail.
        self:ReportView((input or ""):match("^%s*%S*%s*(.-)%s*$"))
    else
        -- "" or "toggle" (or anything else) -> toggle dock visibility.
        self:ToggleDock()
    end
end

---------------------------------------------------------------------------------
-- Spec icon resolution (LibSpecialization)
--
-- C_DamageMeter sources expose specIconID, but the client leaves it nil for any
-- player whose spec it has not resolved -- in a pug / cross-realm raid that is
-- usually EVERYONE, so every bar would fall back to a class icon. LibSpecialization
-- shares specs over addon comms (the only group-spec channel that works inside 12.0
-- instances). The group callback hands us (specID, role, position, playerName); we
-- turn specID into the spec icon fileID and cache it by the player's GUID, so the
-- render path (Window.lua:RenderBar) can look it up against the (issecretvalue-
-- guarded) src.sourceGUID. The class icon stays the final fallback for sources
-- LibSpec can't resolve.
---------------------------------------------------------------------------------

-- specID -> spec icon fileID (4th return of GetSpecializationInfoByID). nil for an
-- unknown / starter (0) spec so the caller keeps the class fallback. Mirrors
-- HealerMana's GetSpecIcon.
local function GetSpecIcon(specID)
    if not specID or specID == 0 then return nil end
    local _, _, _, icon = GetSpecializationInfoByID(specID)
    return icon
end

-- Resolve a LibSpec playerName to a group member's GUID. The lib sends the name as
-- Ambiguate(sender, "none") (realm-qualified only when cross-realm) and the player's
-- own bare name in some paths; normalize both sides to the bare name (Ambiguate
-- "short") and match against the live roster. Player names from group units are
-- non-secret in 12.0 (only NON-player unit names are secret), but the roster read is
-- issecretvalue-guarded so a secret name simply skips instead of tainting the ==.
-- Cold path (fires only when comms land), so a <=40-unit scan is fine.
local function ResolveGroupGUID(playerName)
    if not playerName then return nil end
    local target = Ambiguate(playerName, "short")
    if not target or issecretvalue(target) then return nil end

    local function matchUnit(unit)
        -- UnitName's FIRST return is always the bare name (realm split into the
        -- second return) — GetUnitName(unit, false) appends FOREIGN_SERVER_LABEL
        -- ("(*)") for coalesced members and would never match the Ambiguate'd target.
        local nm = UnitName(unit)
        if nm and not issecretvalue(nm) and nm == target then
            return UnitGUID(unit)
        end
    end

    -- Self first: covers the lib's own-spec path (it reports the player's bare name).
    local guid = matchUnit("player")
    if guid then return guid end

    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, n do
            guid = matchUnit(_raidUnits[i])
            if guid then return guid end
        end
    elseif IsInGroup() then
        -- Party units exclude the player (already checked above).
        local n = GetNumGroupMembers() - 1
        for i = 1, n do
            guid = matchUnit(_partyUnits[i])
            if guid then return guid end
        end
    end
    return nil
end

-- LibSpec group callback: a member's spec/role was reported over comms. Cache the
-- spec icon by GUID so a bar whose API specIconID is nil upgrades from the class
-- fallback to the real spec icon on the next tick. Keyed by GUID (not name) because
-- the render path only has the secret-in-combat src.name but a NeverSecret GUID.
-- A respec re-fires the callback and overwrites the same GUID. role/position unused.
function DM:OnLibSpecGroupUpdate(specID, _, _, playerName)
    local icon = GetSpecIcon(specID)
    if not icon then return end
    local guid = ResolveGroupGUID(playerName)
    if guid then
        self.specIconByGUID[guid] = icon
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function DM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
    -- Slash handling lives under "/kes dm <...>" -- Core/Globals.lua's /kes dispatcher
    -- routes the "dm" subcommand to DM:HandleSlash. No standalone chat command here.
end

function DM:OnEnable()
    -- self.db is assigned in OnInitialize (always runs before OnEnable in the
    -- Ace3 lifecycle), so only the Enabled flag needs checking here.
    if not self.db.Enabled then return end

    self.enabled = true

    -- Combat-state events drive the shared ticker (see Combat-only ticker
    -- section). NEVER use RegisterUnitEvent (Ace3 doesn't expose it and 12.0
    -- discourages it for KE); UNIT_FLAGS is registered broad and filtered
    -- inside the handler (ticker state, party/raid unit token, group-combat).
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnRegenDisabled")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
    self:RegisterEvent("ENCOUNTER_START", "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCombatForceStop")
    self:RegisterEvent("UNIT_FLAGS", "OnUnitFlags")
    -- PvP match end: arenas / battlegrounds can leave the player combat-tagged inside the
    -- closed instance with no live fighting, so UnitAffectingCombat stays true and the
    -- shared ticker would poll C_DamageMeter forever. Force it down on match completion and
    -- suppress the UNIT_FLAGS auto-restart until the player zones out. See
    -- OnPvPMatchComplete + the _pvpMatchOver guard in OnUnitFlags.
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

    -- Seed the shipped default layout when the user has never configured one (fresh
    -- profile -- Windows[1] absent). Three windows: [1] Damage Done (Current) in its own
    -- column, [2] Overall Damage Done + [3] Deaths stacked in a second column. Dock.Columns
    -- is set to match (50/50 columns; the right column splits 61/39) so every seeded window
    -- is actually referenced and rendered. Enum values are read at runtime here -- Defaults.lua
    -- can't reference Enum at file-load time. Existing profiles skip this block entirely and
    -- keep their own windows + dock (so an update never rearranges a configured layout).
    self.db.Windows = self.db.Windows or {}
    if not self.db.Windows[1] then
        local function ctx(meterType, sessionType)
            return { Contexts = { Default = { Enabled = true, MeterType = meterType, SessionType = sessionType } } }
        end
        self.db.Windows[1] = ctx(Enum.DamageMeterType.DamageDone, Enum.DamageMeterSessionType.Current)
        self.db.Windows[2] = ctx(Enum.DamageMeterType.DamageDone, Enum.DamageMeterSessionType.Overall)
        self.db.Windows[3] = ctx(Enum.DamageMeterType.Deaths,     Enum.DamageMeterSessionType.Current)
        self.db.Dock = self.db.Dock or {}
        -- WidthRatio 1 = one full db.Width-wide column (LayoutDock reads it as an
        -- absolute baseW multiplier, NOT a normalized share like RowRatios — 0.5
        -- here shipped a half-width, squished dock in v3.0.0). RowRatios ARE
        -- normalized, so 0.61/0.39 correctly splits the right column 61/39.
        self.db.Dock.Columns = {
            { WidthRatio = 1, Windows = { 1 },    RowRatios = { 1 } },
            { WidthRatio = 1, Windows = { 2, 3 }, RowRatios = { 0.61, 0.39 } },
        }
    end

    -- Repair profiles seeded by the v3.0.0 build, where both columns shipped at
    -- WidthRatio 0.5 (half-width / squished). Run-once and signature-gated so a
    -- customized dock is never touched. Resolved at runtime (Dock.lua loads after
    -- Core.lua); runs whether or not the seed block above fired (existing profiles
    -- skip the seed but still need repair).
    if self.RepairSquishedDock then self:RepairSquishedDock() end

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

    -- Subscribe to LibSpecialization group spec comms so bars whose API specIconID is
    -- nil can resolve a real spec icon (see the Spec icon resolution section + the
    -- spec-icon block in Window.lua:RenderBar). Comms are automatic; the lib re-requests
    -- group specs on join/login. UnregisterGroup + wipe in OnDisable.
    if LibSpec then
        LibSpec.RegisterGroup(self, function(specID, role, position, playerName)
            DM:OnLibSpecGroupUpdate(specID, role, position, playerName)
        end)
    end

    -- Details! is a competing meter — recommend running only one.
    KE:WarnRedundantAddon("Details", "Details!", "Damage Meter", "/kes", self.db, "_detailsWarned")

    -- The KE "Details Backdrop" skin only styles the Details! addon, so it's
    -- redundant under our meter. Disable it ONCE when Details is present (a later
    -- deliberate re-enable is respected via the _detailsSkinOff flag).
    if not self.db._detailsSkinOff and C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("Details") then
        local skinDB = KE.db.profile.Skinning and KE.db.profile.Skinning.Details
        if skinDB and skinDB.Enabled then
            self.db._detailsSkinOff = true
            skinDB.Enabled = false
            KitnEssentials:DisableModule("SkinDetailsBackdrop")
            KE:Print("Disabled the KitnEssentials Details Backdrop skin - redundant with the KitnEssentials Damage Meter.")
        end
    end

    if DEBUG_DM then
        KE:Print("[DM] OnEnable: module active")
    end
end

function DM:OnDisable()
    self.enabled = false

    self:UnregisterAllEvents()
    if LibSpec then LibSpec.UnregisterGroup(self) end
    wipe(self.specIconByGUID)
    self:StopTicker()
    self._sessionPending = false
    self._inEncounter = false
    self._pvpMatchOver = false
    self._activeContext = nil
    self._ctxCheckPending = false
    self._combatStartT = nil
    self._combatEndT = nil

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
-- A single shared ticker drives every window. The ticker only runs while the
-- player or group is in combat,
-- so idle CPU is zero. DM:Tick (implemented in the render chunk) repaints every
-- window from the current sessions; it is resolved at runtime here (called as a
-- method) so this lifecycle layer doesn't depend on the render layer load order.
---------------------------------------------------------------------------------

-- Single shared-ticker body. Runs on every tick and is responsible for self-cancelling
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
    else
        -- Combat clock: arming from IDLE marks a new fight's start. Gated on the
        -- ticker being down so a mid-combat restart (the GUI's Combat Refresh
        -- slider re-calls StartTicker while running) never resets the clock.
        -- Plain GetTime numbers -- never secret. Rendered by Window.lua's
        -- UpdateCombatClock; _combatEndT (StopTicker) freezes it post-fight.
        self._combatStartT = GetTime()
        self._combatEndT = nil
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
        -- Combat clock: freeze at the fight's end BEFORE the final paint below,
        -- so that paint (and any later out-of-combat repaint -- scroll, GUI
        -- change, session settle) shows the frozen final duration instead of a
        -- still-growing one. Only stamped when a fight was actually running.
        if self._combatStartT and not self._combatEndT then
            self._combatEndT = GetTime()
        end
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
-- UnitAffectingCombat("player") rather than InCombatLockdown():
-- InCombatLockdown() returns false the moment the player
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
    -- New fight = new enemy set: drop the hover-tip Targets cache. It is keyed on the
    -- live session, a CONSTANT for the unpinned Current view, so the dirty flag alone
    -- can't force a rebuild -- without this wipe the Targets sub-section serves the PRIOR
    -- fight's enemies on the next out-of-combat hover (or stays hidden if the prior fight
    -- had none). Wiped on every combat start; guarded for load order.
    if self.InvalidateTargetsCache then self:InvalidateTargetsCache() end
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
-- of combat (continuous re-check). Only stop outright
-- when the whole group is already out of combat. While an encounter is active
-- (between ENCOUNTER_START and ENCOUNTER_END) a transient REGEN_ENABLED from a
-- boss transition is ignored -- the ENCOUNTER_END path owns the encounter stop.
function DM:OnRegenEnabled()
    -- Combat ended for the player: a hover tip showing the in-combat "secret" message
    -- should re-populate with real (now-readable) data on the next poll -- mark dirty.
    self._hoverTipDirty = true
    -- Combat end is a Targets-cache boundary too (the sub-section is out-of-combat-only):
    -- drop it so the post-fight hover rebuilds against THIS fight's enemies, not the stale
    -- constant-keyed map (wiped on both REGEN_DISABLED + ENABLED).
    if self.InvalidateTargetsCache then self:InvalidateTargetsCache() end

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
-- doesn't get mistaken for a real combat-end.
function DM:OnEncounterStart()
    if DEBUG_DM then KE:Print("[DM] ENCOUNTER_START -> encounter active") end
    self._inEncounter = true
    -- Segment boundary: a boss pull starts a new segment, so a view override from the
    -- previous boss/trash clears ("until another raid boss starts").
    self:BumpSegment()
    -- Stored-id snapshot for the kill/wipe tint: OnEncounterEnd tags only sessions
    -- stored SINCE this pull. "Tag the newest" mis-tagged a key-completing final
    -- kill -- Blizzard stores the run-level "+NN" session on top of the boss's own
    -- (live repro 2026-07-03), so the boss's outcome landed on the run row. Plain
    -- ids only (sessionID is never secret; guarded anyway). nil snapshot = the
    -- pcall'd list read failed -> OnEncounterEnd falls back to newest-only.
    local list = self:GetAvailableSessions()
    if list then
        -- Fresh table (not wipe-in-place): a pending 0.75s OnEncounterEnd closure
        -- captured the previous table by reference and must keep its own snapshot
        -- even if a chained ENCOUNTER_START re-fills this field first.
        self._preEncounterIds = {}
        for i = 1, #list do
            local id = list[i] and list[i].sessionID
            if id and not issecretvalue(id) then
                self._preEncounterIds[id] = true
            else
                -- An unreadable id would leave a HOLE the end-side walk reads as
                -- "new since the pull" and mis-tags. Drop the whole snapshot and
                -- degrade to newest-only, matching the failed-read branch below.
                self._preEncounterIds = nil
                break
            end
        end
    else
        self._preEncounterIds = nil
    end
    if DEBUG_DM then
        if self._preEncounterIds then
            local n = 0
            for _ in pairs(self._preEncounterIds) do n = n + 1 end
            KE:Print("[DM] ENCOUNTER_START snapshot: " .. n .. " pre-pull session ids")
        else
            KE:Print("[DM] ENCOUNTER_START snapshot: dropped (secret/unreadable id) -> newest-only tagging")
        end
    end
end

-- Boss kill/wipe: a hard segment boundary, but the session totals are not yet
-- finalized at the instant ENCOUNTER_END fires. Delay the stop by 0.5s so the
-- final paint reads settled totals rather than a stale/empty segment. Clears
-- the encounter-active flag immediately.
--
-- The payload's `success` (1 = kill, 0 = wipe; plain event payload, never secret)
-- feeds the segment-menu kill/wipe tint: shortly AFTER the finalize delay, every
-- session stored SINCE the pull (the OnEncounterStart snapshot) gets tagged --
-- normally just the boss's own session, but a key-completing final kill also
-- stores the run-level "+NN" session, and both belong to this kill (a last-boss
-- wipe never completes the key, so the run row can't inherit a red). Sessions
-- only append, so new ids sit contiguously at the list tail -- walk backward and
-- stop at the first pre-pull id. No snapshot (the pcall'd read failed at the
-- pull, or a mid-encounter /reload) -> fall back to tagging the newest only.
-- Runtime-only on purpose: stored sessions don't survive a /reload, so neither
-- must the map (wiped on every session reset).
function DM:OnEncounterEnd(_, _, _, _, _, success)
    if DEBUG_DM then KE:Print("[DM] ENCOUNTER_END -> delayed StopTicker (0.5s)") end
    self._inEncounter = false
    C_Timer.After(0.5, function()
        DM:StopTicker()
    end)
    local won = (success == 1)
    -- Captured now (schedule time), not re-read inside the closure: a chained
    -- ENCOUNTER_START firing before this 0.75s delay expires re-fills
    -- DM._preEncounterIds for the NEXT pull, which would otherwise steal this
    -- boss's outcome tagging out from under it.
    local snap = self._preEncounterIds
    C_Timer.After(0.75, function()
        if not DM.enabled then return end
        local list = DM:GetAvailableSessions(5)
        if not list or #list == 0 then return end
        DM._sessionOutcomes = DM._sessionOutcomes or {}
        local first = snap and 1 or #list   -- no snapshot: newest entry only
        local tagged = 0
        for i = #list, first, -1 do
            local entry = list[i]
            local nid = entry and entry.sessionID
            if not nid or issecretvalue(nid) then
                if DEBUG_DM then KE:Print("[DM] outcome walk stopped at index " .. i .. ": secret/nil session id (tagged " .. tagged .. " so far)") end
                break
            end
            if snap and snap[nid] then   -- reached pre-pull territory
                if DEBUG_DM then KE:Print("[DM] outcome walk stopped at index " .. i .. ": session " .. tostring(nid) .. " was in the pre-pull snapshot (tagged " .. tagged .. " so far)") end
                break
            end
            DM._sessionOutcomes[nid] = won
            tagged = tagged + 1
            if DEBUG_DM then
                KE:Print("[DM] outcome tagged: session " .. tostring(nid) .. " -> " .. (won and "kill" or "wipe"))
            end
        end
        if DEBUG_DM and tagged == 0 then
            KE:Print("[DM] WARNING: ENCOUNTER_END tagged 0 sessions (won=" .. tostring(won)
                .. ", hadSnapshot=" .. tostring(snap ~= nil) .. ", listSize=" .. #list
                .. ") -- boss row will stay uncolored")
        end
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
    -- A new zone is a clean slate for the combat clock too: drop the stamps BEFORE
    -- StopTicker so its built-in final paint HIDES the clock. Nil'ing after would
    -- leave the frozen last-fight time painted with no guaranteed later repaint --
    -- a same-context zoning (hearth across the world) never re-Ticks on its own
    -- (ApplyActiveContext early-returns when the context is unchanged).
    self._combatStartT = nil
    self._combatEndT = nil
    self:StopTicker()
    -- Zoning may change the content context (entered/left an instance) -- schedule a
    -- settled re-check (debounced; IsInInstance isn't reliable until the world loads).
    self:_ScheduleContextCheck()
end

-- A group member's flags changed (often: they entered combat before us). Start
-- the ticker if the group is fighting and we're not already ticking, so bars
-- populate before the player is tagged.
function DM:OnUnitFlags(_, unit)
    -- After a PvP match completes the player stays combat-tagged in the closed instance,
    -- so UNIT_FLAGS would keep re-arming the ticker against GroupInCombat. Suppress the
    -- auto-restart until a genuine new combat (OnRegenDisabled) or a zone-out
    -- (OnCombatForceStop) clears the flag -- otherwise OnPvPMatchComplete's stop is undone.
    if self._pvpMatchOver then return end
    -- Cheap bails before the <=40-unit GroupInCombat scan: UNIT_FLAGS fires dozens of
    -- times per second during a pull, and once the ticker is up this handler has nothing
    -- left to do. Only a party/raid member's flag change can mean "group entered combat
    -- before us" -- the player's own combat entry is owned by PLAYER_REGEN_DISABLED, so
    -- player/target/nameplate tokens are skipped too.
    if self._ticker then return end
    if not unit or not (unit:match("^raid%d") or unit:match("^party%d")) then return end
    if self:GroupInCombat() then
        if DEBUG_DM then KE:Print("[DM] UNIT_FLAGS -> group in combat, StartTicker") end
        self:StartTicker()
    end
end

-- A PvP match (arena / battleground) completed. The player can stay combat-tagged in the
-- closed instance with no live fighting, so UnitAffectingCombat stays true and the shared
-- ticker would poll C_DamageMeter every RefreshRate forever. Force the ticker down (the
-- final paint settles the post-match totals) and raise _pvpMatchOver so the UNIT_FLAGS
-- auto-restart stays suppressed until a real new combat or a zone-out clears it. Plain
-- event with no payload read -- never a secret.
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
    -- A reset invalidates every stored sessionID, so a window still pinned to one
    -- (W._curSessionID, set via the segment menu) would read a dead id and render
    -- blank until the user re-picks. Drop the pin on every window so it falls back to
    -- the live Current/Overall view. Mirrors the CHALLENGE_MODE_START teardown; the
    -- field is runtime-only, so a plain nil is safe to set unconditionally.
    if self.windows_rt then
        for _, W in pairs(self.windows_rt) do
            W._curSessionID = nil
        end
    end
    -- Stored sessions are gone; their kill/wipe outcome tags go with them (a future
    -- session could reuse a wiped id and inherit a stale tint otherwise).
    if self._sessionOutcomes then wipe(self._sessionOutcomes) end
    -- The frozen combat clock referenced the wiped data -- hide it (out of combat;
    -- an in-combat reset keeps the live clock since the fight itself continues).
    if not self._ticker then
        self._combatStartT = nil
        self._combatEndT = nil
    end
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

-- Precision config for AbbreviateNumbers. AbbreviateNumbers is the ONLY
-- secret-safe abbreviator; the
-- bare call rounds to whole units ("43M"), but passing this config makes it emit
-- decimals ("43.81M" / "273.8K") even on a SECRET in-combat amount -- the
-- function consumes the secret internally, so we never run string.format /
-- arithmetic on a secret (which would taint). Guarded on CreateAbbreviateConfig;
-- if absent, _abbreviateCfg stays nil and AbbreviateNumbers(n, nil) degrades to
-- the plain (no-decimal) but still secret-safe path (2 decimals at M/B, 1 at K).
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

-- Seconds are a clock quantity: never K/M/B-abbreviate them ("1Ks"). Single
-- breakpoint-1 tier = plain integer seconds through the same secret-safe path.
local _secondsCfg
do
    local opts = {
        { breakpoint = 1, abbreviation = "", significandDivisor = 1, fractionDivisor = 1, abbreviationIsGlobal = false },
    }
    if CreateAbbreviateConfig then
        _secondsCfg = { config = CreateAbbreviateConfig(opts) }
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
    -- Per-second can drop below 1 on long Overall windows (total / huge elapsed
    -- time), and AbbreviateNumbers returns sub-1 values as the raw float
    -- ("0.6100439606729"). Clamp plain rates to 1; never compare a secret (while
    -- the amounts are secret the session is in-combat-short, so a sub-1 rate
    -- can't occur). Truthiness gate first -- allowed on a secret number.
    if perSec and not issecretvalue(perSec) and perSec < 1 then perSec = 1 end

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

-- Death-time formatter for the Deaths meter type. Returns (string, isSecret).
-- deathTimeSeconds is SECRET in combat, and 12.0.5 ships no tainted-callable clock
-- formatter (SecondsFormatter / C_StringUtil.CreateSecondsFormatter / duration
-- objects are all AllowedWhenUntainted -> they throw on a secret arg from addon
-- code; no addon can work around this in 12.0.5). So the
-- M:SS arithmetic only runs on a plain value; a secret time renders as whole
-- seconds ("143s") via AbbreviateNumbers (AllowedWhenTainted) -- live data in
-- combat instead of the old "0:00" placeholder -- and flips to M:SS on the first
-- out-of-combat paint. A secret result must never be == compared; the isSecret
-- return routes the caller to the no-dirty-check path (RenderBar's vIsSecret).
local function FormatDeathTime(sec)
    if not sec then return "0:00", false end
    if issecretvalue(sec) then
        local s = AbbreviateNumbers(sec, _secondsCfg)
        if s then
            local str = s .. "s"
            return str, issecretvalue(str)
        end
        return "0:00", false
    end
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
-- Report to chat (/kes dm report [count] [channel])
--
-- Posts the PRIMARY window (idx 1)'s current view -- the same resolved meter type /
-- session / pinned segment the user sees -- as ranked chat lines. OUT OF COMBAT ONLY:
-- source names and amounts are secret in combat (and in identity-restricted instances),
-- and unlike FontString:SetText, SendChatMessage has no AllowedWhenTainted contract, so
-- feeding it a secret string would taint. Every field that would be sent is issecretvalue-
-- gated; if ANY is secret the report aborts BEFORE sending a single line (never a partial).
-- SendChatMessage is normal player chat (NOT the instance-blocked SendAddonMessage), so it
-- is allowed in dungeons/raids. Channel auto-picks RAID > PARTY > SAY; an explicit channel
-- arg overrides. Count defaults to 5, clamped 1..25.
---------------------------------------------------------------------------------

local REPORT_CHANNELS = {
    say = "SAY", party = "PARTY", raid = "RAID",
    guild = "GUILD", officer = "OFFICER", instance = "INSTANCE_CHAT",
}

-- Meter types with a meaningful per-second (amount-over-time). Interrupts / Dispels are
-- counts and Deaths are events, so a rate is noise -- omitted from the report AND from
-- the bar value (RenderWindow stashes the lookup per tick so RenderBar drops the
-- "count | rate" half for count types; the reference whitelists the same five).
local RATE_METER_TYPES = {
    [Enum.DamageMeterType.DamageDone] = true,
    [Enum.DamageMeterType.HealingDone] = true,
    [Enum.DamageMeterType.DamageTaken] = true,
    [Enum.DamageMeterType.EnemyDamageTaken] = true,
    [Enum.DamageMeterType.AvoidableDamageTaken] = true,
}
-- Cross-chunk API: the render layer (Window.lua) reads this to gate the per-second
-- half of the bar value. Non-underscore name per the DM.RANK_STRINGS convention.
DM.RATE_METER_TYPES = RATE_METER_TYPES

function DM:ReportView(rest, winIdx)
    -- winIdx selects which window to report: the header Report button passes the clicked
    -- window's index; the slash command omits it -> the primary window (1).
    winIdx = winIdx or 1
    -- Guard the captured chat API: a missing namespace is a clean no-op, not a nil call.
    if not SendChat then return end
    -- Parse "[count] [channel]" -- either/both optional, order-independent.
    local count, channel
    for tok in (rest or ""):gmatch("%S+") do
        local num = tonumber(tok)
        if num then
            count = num
        else
            local c = REPORT_CHANNELS[tok:lower()]
            if c then channel = c end
        end
    end
    count = count or 5
    if count < 1 then count = 1 elseif count > 25 then count = 25 end

    -- Resolve the primary window's effective view (configured type + any live override),
    -- its session type, and any pinned stored session -- exactly what RenderWindow shows.
    local cfg = self:ResolveWindowConfig(winIdx)
    if not cfg then
        KE:Print("Damage Meter: no window to report.")
        return
    end
    local meterType = self:EffectiveMeterType(winIdx, cfg) or Enum.DamageMeterType.DamageDone
    local sessionType = cfg.SessionType or Enum.DamageMeterSessionType.Current
    local W = self.windows_rt and self.windows_rt[winIdx]
    -- EffectiveSessionID: the pin, else the Current-empty fallback the bars show
    -- (post-encounter finalize) -- so the report always posts what's on screen.
    local session = self:GetSession(sessionType, meterType, self:EffectiveSessionID(W))
    local sources = session and session.combatSources
    if not sources or not sources[1] then
        KE:Print("Damage Meter: nothing to report yet.")
        return
    end

    -- Total (for the share %) is secret in combat; when secret we just omit the percent.
    -- Gate truthiness (NOT `~= nil`): an explicit equality compare on a secret value
    -- taints, but truthiness of a secret NUMBER is allowed -- and issecretvalue runs
    -- BEFORE the type/`> 0` checks so those only touch a proven-plain number.
    local total = session.totalAmount
    local totalUsable = total and not issecretvalue(total) and type(total) == "number" and total > 0

    -- The report value is "total (dps/s, share%)" -- a chat-safe layout that does NOT use
    -- the bar's "total | dps" pipe: a bare "|" is the chat escape-code char, so the chat
    -- API rejects "| " as an invalid escape (a FontString tolerates it; chat does not).
    -- The per-second is shown only for amount-over-time types (RATE_METER_TYPES);
    -- Interrupts / Dispels are counts where a rate is noise, and Deaths report the death
    -- time (M:SS). Each field is secret-gated before it reaches a line.
    local isDeaths = (meterType == Enum.DamageMeterType.Deaths)
    local isOverall = (sessionType == Enum.DamageMeterSessionType.Overall)
    local wantRate = RATE_METER_TYPES[meterType] == true

    -- Build the lines first; abort cleanly if any field we would send is secret (do NOT
    -- send a partial report). Everything that reaches a line is therefore plain.
    local n = math_min(count, #sources)
    local lines = {}
    for i = 1, n do
        local src = sources[i]
        local nm = src and src.name
        if not nm or issecretvalue(nm) then
            KE:Print("Damage Meter: report unavailable -- data is combat-restricted. Try again out of combat.")
            return
        end
        -- nm is plain here, so string ops are taint-safe. Honor ShowRealm: strip the
        -- realm suffix (player names never contain a hyphen, so the split is exact).
        local shown = nm
        if not (self.db and self.db.ShowRealm) then
            shown = nm:match("^([^-]+)") or nm
        end

        if isDeaths then
            -- Mirror the Deaths bar: death time (M:SS), nothing for Overall. In combat
            -- FormatDeathTime returns a SECRET seconds string ("143s"); chat lines must
            -- be plain, so abort like every other secret field -- and BEFORE the == ""
            -- compare below, which would itself throw on a secret string.
            local t = isOverall and "" or (self.FormatDeathTime(src.deathTimeSeconds))
            if issecretvalue(t) then
                KE:Print("Damage Meter: report unavailable -- data is combat-restricted. Try again out of combat.")
                return
            end
            if t == "" then
                lines[i] = format("%d. %s", i, shown)
            else
                lines[i] = format("%d. %s  %s", i, shown, t)
            end
        else
            local amt = src.totalAmount
            if not amt or issecretvalue(amt) then
                KE:Print("Damage Meter: report unavailable -- data is combat-restricted. Try again out of combat.")
                return
            end
            -- Per-second only for rate types; gate it secret like the total.
            local ps
            if wantRate then
                ps = src.amountPerSecond
                if ps and issecretvalue(ps) then
                    KE:Print("Damage Meter: report unavailable -- data is combat-restricted. Try again out of combat.")
                    return
                end
            end
            -- amt and ps are proven plain. Compose "total (dps/s, share%)" with whichever
            -- extras apply -- no "|" anywhere, so the line is chat-escape-safe.
            local totalStr = FormatAmount(amt)
            local psStr = ps and (FormatAmount(ps) .. "/s") or nil
            local pctStr = totalUsable and format("%.1f%%", (amt / total) * 100) or nil
            local extra
            if psStr and pctStr then
                extra = psStr .. ", " .. pctStr
            else
                extra = psStr or pctStr
            end
            if extra then
                lines[i] = format("%d. %s  %s (%s)", i, shown, totalStr, extra)
            else
                lines[i] = format("%d. %s  %s", i, shown, totalStr)
            end
        end
    end

    -- Channel: explicit arg wins; else RAID in a raid, PARTY in a party, SAY solo.
    if not channel then
        if IsInRaid() then
            channel = "RAID"
        elseif IsInGroup() then
            channel = "PARTY"
        else
            channel = "SAY"
        end
    end

    -- Header line + ranked rows. FormatWindowLabel is built from plain enum names.
    SendChat("KitnEssentials - " .. self:FormatWindowLabel(meterType, sessionType) .. ":", channel)
    for i = 1, #lines do
        SendChat(lines[i], channel)
    end
end

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
            -- ResetAllCombatSessions invalidates every sessionID: drop any pin so the
            -- window stops reading a now-dead stored session and falls back to live
            -- (mirrors the CHALLENGE_MODE_START / DAMAGE_METER_RESET teardown).
            w._curSessionID = nil
            if w._detailOpen and self.CloseDetail then self:CloseDetail(w) end
        end
    end
    -- Outcome tags reference the wiped session ids -- drop them with the data
    -- (mirrors OnMeterReset; covers a reset that doesn't fire the event).
    if self._sessionOutcomes then wipe(self._sessionOutcomes) end
    -- Frozen combat clock referenced the wiped data too (mirrors OnMeterReset;
    -- in-combat resets keep the live clock -- the fight itself continues).
    if not self._ticker then
        self._combatStartT = nil
        self._combatEndT = nil
    end
    -- Close any open view-selector too so the freshly-emptied bars are visible (the
    -- selector overlays the body with the same anchors, so it would block them).
    if self.CloseAllSelectors then self:CloseAllSelectors() end
    if self.CloseAllSegmentMenus then self:CloseAllSegmentMenus() end
    if self.Tick then self:Tick() end
end

-- Report channel picker for the header Report button. Opens a MenuUtil
-- context menu of the chat channels available right now; choosing one reports THIS window's
-- view there via ReportView (the secret-safe build + send). MenuUtil item callbacks fire on
-- the user's click (a hardware event), so the SendChatMessage inside ReportView is allowed.
-- Channels are gated by current membership -- Party/Instance need a group, Raid a raid,
-- Guild/Officer a guild; Say is always offered. Falls back to a direct auto-channel report
-- if the menu API is somehow unavailable.
function DM:OpenReportMenu(W)
    local winIdx = W and W.idx
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        self:ReportView(nil, winIdx)
        return
    end
    local owner = (W and W.headerBtns and W.headerBtns.report) or UIParent
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Report to")
        root:CreateButton("Say", function() self:ReportView("say", winIdx) end)
        if IsInGroup() then
            root:CreateButton("Party", function() self:ReportView("party", winIdx) end)
        end
        if IsInInstance() and IsInGroup() then
            root:CreateButton("Instance", function() self:ReportView("instance", winIdx) end)
        end
        if IsInRaid() then
            root:CreateButton("Raid", function() self:ReportView("raid", winIdx) end)
        end
        if IsInGuild() then
            root:CreateButton("Guild", function() self:ReportView("guild", winIdx) end)
            root:CreateButton("Officer", function() self:ReportView("officer", winIdx) end)
        end
    end)
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

-- "Combat" fallback when a session name is secret/empty.
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
        -- Persist the chosen SessionType into the LIVE context's OWN entry, copy-on-write.
        -- ResolveWindowConfig falls back to the shared Contexts.Default table for any
        -- context the user hasn't configured, so writing cfg.SessionType through it would
        -- bleed this pick into every other unconfigured context (and persist in SV). So
        -- materialize the per-context entry from Default first (mirrors the GUI's
        -- writeField in GUI-DamageMeter.lua), then write only this context's SessionType.
        -- When the live context IS Default, the entry already exists and this is a plain
        -- write to Default -- unchanged behavior.
        local windows = self.db and self.db.Windows
        local window = windows and windows[W.idx]
        if window and window.Contexts then
            local ctx = self:GetActiveContext()
            local def = window.Contexts.Default
            local entry = window.Contexts[ctx]
            if not entry then
                entry = {
                    Enabled = (def and def.Enabled) ~= false,
                    MeterType = (def and def.MeterType) or Enum.DamageMeterType.DamageDone,
                    SessionType = (def and def.SessionType) or Enum.DamageMeterSessionType.Current,
                }
                window.Contexts[ctx] = entry
            end
            entry.SessionType = sessionType
        end
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
-- secret boolean.
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
function DM:OnChallengeEvent(event)
    -- A keystone start/complete/reset is a hard segment boundary (covers re-running a
    -- key, where the content context stays "Mythic+" so the context compare alone
    -- wouldn't catch it). A first key start may double-bump with the context change
    -- in ApplyActiveContext -- harmless (the override clears either way).
    self:BumpSegment()

    -- Keystone START begins a fresh dungeon run. The "Overall" session
    -- (Enum.DamageMeterSessionType.Overall) is a CUMULATIVE bucket the game keeps
    -- until something calls ResetAllCombatSessions -- there is no per-key auto-reset
    -- in the C_DamageMeter contract. Without this, "Overall" (and a window pinned to a
    -- prior session) carries the PREVIOUS key's data, incl. its deaths, into the new
    -- run. Reset on START only: resetting on COMPLETED/RESET would wipe a just-finished
    -- run the user is still reviewing. Standalone meters reset at this same boundary so
    -- "Overall" means "this run".
    if event == "CHALLENGE_MODE_START" then
        if self.windows_rt then
            for _, W in pairs(self.windows_rt) do
                -- ResetAllCombatSessions invalidates every sessionID, so a window still
                -- pinned (W._curSessionID) to a prior-key session would read a dead id.
                -- Drop the pin so it falls back to the live Current/Overall session.
                -- Runtime-only field (not persisted), safe to clear unconditionally.
                W._curSessionID = nil
                -- Close a detail panel keyed to the about-to-be-wiped session (mirrors
                -- HeaderReset's teardown). Resolved at runtime; guarded for load order.
                if W._detailOpen and self.CloseDetail then self:CloseDetail(W) end
            end
        end
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            pcall(C_DamageMeter.ResetAllCombatSessions)
        end
        -- The hover-tip Targets cache cross-references the now-wiped data.
        if self.InvalidateTargetsCache then self:InvalidateTargetsCache() end
        -- Outcome tags reference the wiped session ids (mirrors OnMeterReset).
        if self._sessionOutcomes then wipe(self._sessionOutcomes) end
        -- Repaint the emptied bars now: ApplyActiveContext below early-returns when the
        -- content context is unchanged (a key RE-RUN stays "Mythic+"), so it can't be
        -- relied on to paint after the reset. BumpSegment already closed selectors/menus.
        if self.Tick then self:Tick() end
    end

    self:ApplyActiveContext()
end

---------------------------------------------------------------------------------
-- Readable header labels
--
-- The render layer builds a window's header text from cfg.MeterType /
-- cfg.SessionType, both Enum values. These tables map the enum to a display
-- string once at file load; the render path reads them by key and never builds
-- a label string per tick. DamageMeter enums are guaranteed present in 12.0, but each
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

-- Meter-type glyph shown at the LEFT of each window's header (the same dm_* set the
-- view-selector uses, Selector.lua). Keyed by Enum.DamageMeterType; the render layer
-- nil-guards the lookup so an unmapped type (Dps/Hps/Absorbs are not selectable) just
-- hides the header icon rather than concatenating nil. Plain file paths -- never secret.
do
    local I = "Interface\\AddOns\\KitnEssentials\\Media\\Icon\\"
    DM.METER_TYPE_ICONS = {
        [Enum.DamageMeterType.DamageDone]           = I .. "dm_damage.tga",
        [Enum.DamageMeterType.HealingDone]          = I .. "dm_healing.tga",
        [Enum.DamageMeterType.DamageTaken]          = I .. "dm_dmgtaken.tga",
        [Enum.DamageMeterType.AvoidableDamageTaken] = I .. "dm_avoidable.tga",
        [Enum.DamageMeterType.EnemyDamageTaken]     = I .. "dm_enemytaken.tga",
        [Enum.DamageMeterType.Interrupts]           = I .. "dm_interrupt.tga",
        [Enum.DamageMeterType.Dispels]              = I .. "dm_dispel.tga",
        [Enum.DamageMeterType.Deaths]               = I .. "dm_deaths.tga",
    }
end

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

-- The render-path session for a window: the pinned stored session when one is set,
-- else the live cfg.SessionType -- PLUS the "Current = last fight" fallback.
-- Blizzard finalizes the live Current session into storage when an encounter ends,
-- leaving Current EMPTY until the next pull, so an unpinned Current window would
-- blank out the just-killed boss the moment combat drops. Out of combat, when live
-- Current has no sources, fall back to the NEWEST stored session and remember it in
-- W._fallbackSessionID so every per-source consumer (detail panel, hover tip, chat
-- report -- via EffectiveSessionID) reads the same segment the bars show. In combat
-- the live session owns the view (no fallback -- the last fight must not bleed into
-- a fresh pull's empty first ticks). Runtime-only field, re-resolved every render,
-- so a reset/wipe of stored sessions self-heals on the next paint.
function DM:ResolveRenderSession(W, cfg, meterType)
    local session = self:CachedSession(cfg.SessionType, meterType, W._curSessionID)
    W._fallbackSessionID = nil
    if not W._curSessionID
        and cfg.SessionType == Enum.DamageMeterSessionType.Current
        and not InCombatLockdown() and not self._ticker
        and not (session and session.combatSources and #session.combatSources > 0) then
        local list = self:GetAvailableSessions(1)
        local newest = list and list[#list]
        local nid = newest and newest.sessionID
        if nid and not issecretvalue(nid) then
            local fb = self:CachedSession(cfg.SessionType, meterType, nid)
            if fb and fb.combatSources and #fb.combatSources > 0 then
                W._fallbackSessionID = nid
                session = fb
            end
        end
    end
    return session
end

-- The session id the window is EFFECTIVELY showing: the user's explicit pin, else
-- the Current-empty fallback ResolveRenderSession last applied, else nil (live).
-- Single source of truth for the detail panel / hover tip / report session reads.
function DM:EffectiveSessionID(W)
    if not W then return nil end
    return W._curSessionID or W._fallbackSessionID
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
