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

---@class DamageMeter: AceModule, AceEvent-3.0
local DM = KitnEssentials:NewModule("DamageMeter", "AceEvent-3.0")

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
-- those releases shipped registered defaults, and AceDB's logout-time
-- removeDefaults stripped default-equal leaves and DELETED nested tables that
-- became empty. SavedVariables written then therefore carry holes like
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

-- The font face this module used to seed. Kept only so UpdateDB can recognise
-- and clear the stale seed; nothing else may read it.
local RETIRED_FONT_FACE = "Expressway"

local DM_DEFAULTS = {
    Enabled = false,
    Locked = true,              -- when true, disables EditMode drag of the dock
    RefreshRate = 0.5,
    UIBudgetMs = 1.2,
    MaxWindows = 5,
    AlwaysShowSelf = false,     -- pin the player to the last visible slot when off-list
                                -- (role-relevant views only -- Window.lua PIN_ROLES)
    ResetOnKeyStart = true,     -- wipe all combat sessions when a keystone starts, so
                                -- "Overall" (and the segment history) covers just that
                                -- run; off = data accumulates until a manual reset

    -- Visibility conditions (independent; ALL enabled conditions must pass for the
    -- meter to show). GUI preview / EditMode always force-show regardless.
    HideOutOfCombat = false,    -- show only while the player/group is in combat
    OnlyInInstances = false,    -- show only inside a dungeon / raid / arena / BG / scenario

    -- Bar appearance (flat, KE convention)
    BarHeight = 23,
    BarSpacing = 1,
    Width = 212,
    StatusBarTexture = "KitnUI",
    FontSize = 14,              -- bar row text size
    HeaderFontSize = 14,        -- window header text size (independent of the bar text)
    HeaderThemeColor = false,   -- tint the header title with the KitnUI theme accent (else white)
    FontOutline = "OUTLINE",
    ShowRank = false,
    ShowIcon = true,
    ShowName = true,
    ShowRealm = false,          -- false: strip the "-Realm" suffix from cross-realm names
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
    BackdropBehindBarsOnly = false,             -- wrap only the bar rows; the header floats above the backdrop
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

    -- Key-history bundles kept (History.lua; GUI slider 1-5). Legacy
    -- profiles may hold the old slider max 10 or the older default 20 —
    -- clamped to [1,5] at read, never migrated.
    HistoryRetain = 5,
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

    -- Pending-key metadata needs NO handling here: its persisted copy lives
    -- in the profile-independent KE.db.global (History.lua) precisely so
    -- profile ops can't shard or strand it.

    -- Persisted-value repair: this module used to seed its own font face, and
    -- because it writes straight into the profile rather than registering
    -- AceDB defaults, that seed was never stripped on logout. Retiring the
    -- default therefore left every existing profile pinned to the old value
    -- while an unset font is supposed to follow KE's global font. Clear the
    -- retired literal once per profile; a face the user picks afterwards
    -- persists normally. Run-once-stamped because the retired literal is also
    -- a legitimate choice.
    if not self.db.FontFaceCleared then
        if self.db.FontFace == RETIRED_FONT_FACE then
            self.db.FontFace = nil
        end
        self.db.FontFaceCleared = true
    end

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
    -- The clock cache survives a plain re-gate, so it has to be dropped wherever
    -- the module RE-SCOPES what a window shows. Here BEFORE the loop below:
    -- ReapplyBarVisuals reaches ApplyHeaderIcons, which re-gates the header, so a
    -- clear placed at the LayoutDock call would already be too late.
    if self.ClearClockCache then self:ClearClockCache() end
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

-- Live theme-preset change: KE:NotifyThemeChange (AddonTheme.lua) calls this on
-- every module AFTER the accent-family colors update. DM has three theme-colored
-- surfaces -- the header title (HeaderThemeColor), Theme-mode bars (BarColorMode
-- "Theme"), and the theme-style backdrop border -- so reuse ApplySettings (the
-- module's single repaint entry) to re-read the new accent everywhere at once
-- rather than duplicating each per-surface accent read. Without this handler a
-- preset change didn't reach the meter until a /reload.
function DM:OnThemeChanged()
    if not self.enabled then return end
    self:ApplySettings()
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

    self:EnsureDock()

    if not self.editModeConfig then
        self.editModeConfig = {
            key = "DamageMeter",
            module = self,
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
        }
    end

    -- Published regardless of the lock, and never withdrawn: EUI elements
    -- anchored to the dock must keep following it after the meter is locked.
    -- isHidden therefore does NOT report the lock. It reports the two states
    -- that should cost the element its mover: no dock, or the module disabled.
    -- OnDisable hides the dock without destroying it, so existence alone is not
    -- enough.
    if KE.EUIUnlock then
        KE.EUIUnlock:Register(self.editModeConfig, {
            label = "Damage Meter",
            order = 610,
            isHidden = function()
                return not (self.db and self.db.Enabled and self.dock)
            end,
        })
    end

    if self.db and self.db.Locked then return end
    if self.editModeRegistered then return end

    KE.EditMode:RegisterElement(self.editModeConfig)
    self.editModeRegistered = true
end

function DM:UnregisterEditMode()
    if KE.EditMode and KE.EditMode.UnregisterElement then
        KE.EditMode:UnregisterElement("DamageMeter")
    end
    self.editModeRegistered = false
    -- The EllesmereUI element deliberately stays registered; see RegWithEditMode.
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

    -- Liveness and the combat clock are KE.CombatState's job (Core/CombatState.lua);
    -- BindCombatState registers this module as a listener below. The events kept
    -- here still do DM-specific bar/segment/history work of their own -- only the
    -- state decisions moved out.
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnRegenDisabled")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
    self:RegisterEvent("ENCOUNTER_START", "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCombatForceStop")
    -- Feign-death filtering. Registered broad; the handler's first two lines
    -- reject every other cast in the game.
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
    self:RegisterEvent("PLAYER_DEAD", "OnPlayerDead")
    self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", "OnSessionUpdated")
    -- CURRENT_SESSION_UPDATED fires for the live segment during the post-combat
    -- finalization burst; route it through the same combat-gated, debounced
    -- handler so out-of-combat Current-window totals settle (in combat the ticker
    -- owns repaints and OnSessionUpdated early-returns, so this adds no hot work).
    self:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED", "OnSessionUpdated")
    self:RegisterEvent("DAMAGE_METER_RESET", "OnMeterReset")

    -- Content-context auto-swap (Phase 3): re-resolve each window's per-context config
    -- when the player changes content. PLAYER_ENTERING_WORLD (registered above for
    -- OnCombatForceStop) + ZONE_CHANGED_NEW_AREA go through the DEBOUNCED settle path (IsInInstance
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
        -- here once shipped a half-width, squished dock). RowRatios ARE
        -- normalized, so 0.61/0.39 correctly splits the right column 61/39.
        self.db.Dock.Columns = {
            { WidthRatio = 1, Windows = { 1 },    RowRatios = { 1 } },
            { WidthRatio = 1, Windows = { 2, 3 }, RowRatios = { 0.61, 0.39 } },
        }
    end

    -- Repair profiles seeded by the old build, where both columns shipped at
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
    -- Reused windows keep their cached clock text across a disable/enable, and the
    -- build below lays them out -- which re-gates the header -- before the first
    -- paint. Clear here rather than inside CreateAllWindows so the call stays in
    -- this file.
    if self.ClearClockCache then self:ClearClockCache() end
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

    -- Feign filtering starts OFF and only a meter reset turns it on. Disabling
    -- the module does not reset the game's meter data, so a disable-and-enable
    -- must not be a way around the rule -- which is why this is unconditional.
    -- Nothing below raises it again: ClearFeignTags deliberately leaves it alone.
    self._feignArmable = false

    -- Register with the shared combat-state service and seed a mid-fight enable
    -- (a module enabled while a fight is already running gets no OnStart otherwise).
    self:BindCombatState()

    if DEBUG_DM then
        KE:Print("[DM] OnEnable: module active")
    end
end

function DM:OnDisable()
    self.enabled = false
    -- Hand Chat back its own size, if it was matching ours. Must follow the
    -- line above: that is what makes the rectangle query answer nil, which is
    -- the whole release mechanism. OnDisable never reaches UpdateBackdrop, so
    -- the push at the end of it cannot do this.
    -- Guarded for load order (Dock.lua).
    if self.ReleaseChatSize then self:ReleaseChatSize() end

    self:UnregisterAllEvents()
    KE.CombatState:UnregisterListener("DamageMeter")
    if LibSpec then LibSpec.UnregisterGroup(self) end
    wipe(self.specIconByGUID)
    self:StopTicker()
    self._sessionPending = false
    self._activeContext = nil
    self._ctxCheckPending = false
    self:ClearFeignTags("module disable")
    self._feignArmable = false
    -- The runtime windows survive a disable, so their cached clock text would
    -- outlive the stamps above and could be re-shown by a bare visibility re-gate.
    if self.ClearClockCache then self:ClearClockCache() end
    -- Pending provenance requires CONTINUOUS observation: a disabled module
    -- misses key boundaries (no START events), so an armed record can no
    -- longer be vouched for — one surviving disable->enable would mislabel
    -- a multi-key store. Bundles stay: they are already-captured data, not
    -- provenance. Guarded for load order (History.lua).
    if self.HistoryDropPending then self:HistoryDropPending() end

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
-- Shared combat-state listener (Core/CombatState.lua)
--
-- KE.CombatState is the single source of truth for liveness and the combat
-- clock; this module only reacts to it. Registered in OnEnable, dropped in
-- OnDisable.
---------------------------------------------------------------------------------

-- Shared by OnStart and BindCombatState's mid-fight seed so the two cannot
-- drift: a seed that ran StartTicker alone would leave a raised _clockCleared
-- in place, and the clock would stay hidden for the rest of that fight.
function DM:_CombatStartBody()
    self._clockCleared = nil
    -- A genuine start blanks the clock so the warm-up hold in UpdateCombatClock
    -- cannot keep the PREVIOUS fight's time on screen. A chain pull gets no
    -- OnStart, which is exactly when the hold is wanted.
    if self.BlankCombatClock then self:BlankCombatClock() end
    self:ClearFeignTags("combat start")
    self:StartTicker()
end

function DM:BindCombatState()
    KE.CombatState:RegisterListener("DamageMeter", {
        OnStart = function() DM:_CombatStartBody() end,
        OnStop = function(reason)
            -- A kill authorises a 0.5s delay on the PAINT only (Blizzard needs it to
            -- finalize the session totals); the clock itself already froze. Every
            -- other reason, "encounterEndDelayed" included, already spent that delay
            -- inside the machine, so the ticker stops at once. The generation guard
            -- keeps a boss pulled inside the delay from having its ticker cancelled
            -- out from under it.
            if reason == "encounterEnd" then
                local gen = KE.CombatState:Generation()
                C_Timer.After(0.5, function()
                    if not DM.enabled then return end
                    if KE.CombatState:Generation() ~= gen then return end
                    if KE.CombatState:IsLive() then return end
                    DM:StopTicker()
                end)
                return
            end
            -- A hard reset with nothing live is a clean slate for the clock: the
            -- flag skips the shared branch so the last fight's frozen time does not
            -- survive a load screen (mirrors OnMeterReset / HeaderReset).
            if reason == "reset" then
                DM._clockCleared = true
            end
            DM:StopTicker()
        end,
        OnGroupClear = function()
            if DM.RefreshVisibility then DM:RefreshVisibility() end
        end,
        -- Repaints the clock ONLY -- never DM:Tick, which would repaint every bar
        -- and total at up to 10 Hz while a tenths cadence is running.
        OnClockTick = function()
            -- Authoritative: this paint carries the service's own reading, so it
            -- overrides the warm-up hold and may blank the clock.
            if DM.RepaintCombatClock then DM:RepaintCombatClock(true) end
        end,
    })
    -- A module enabled mid-fight gets no OnStart from the service (it already
    -- fired before this module registered), so run the same body directly.
    if KE.CombatState:IsLive() then
        self:_CombatStartBody()
    end
end

---------------------------------------------------------------------------------
-- Combat-only ticker (shared across all windows)
--
-- A single shared ticker drives every window, started and stopped by the
-- combat-state listener above rather than by this module's own event handlers.
-- DM:Tick (implemented in the render chunk) repaints every window from the
-- current sessions; it is resolved at runtime here (called as a method) so this
-- lifecycle layer doesn't depend on the render layer load order.
---------------------------------------------------------------------------------

-- DM:Tick lives in the render chunk and is resolved at runtime, so the guard
-- keeps this lifecycle layer from throwing if combat starts before that chunk
-- loads (mirrors the DM.OpenDetail guard in Window.lua:MakeBar).
function DM:_RunTick()
    if DM.Tick then DM:Tick() end
end

-- Starts (or restarts) the shared refresh ticker. Cancel-before-start so a
-- stale ticker is never left orphaned if combat is re-entered without a clean
-- stop, and so the GUI's Combat Refresh slider can re-call this while a fight
-- is running without doubling the ticker. RefreshRate defaults to 0.5s when
-- the DB value is missing.
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

    if DM.Tick then DM:Tick() end

    -- Combat fully ended (every stop path funnels through here): hide the dock if the
    -- HideOutOfCombat condition is on. No-op unless a hide condition is enabled, and
    -- self.enabled-guarded inside so an OnDisable-time stop doesn't re-show it.
    if self.RefreshVisibility then self:RefreshVisibility() end

    if DEBUG_DM then
        KE:Print("[DM] StopTicker: final paint")
    end
end

-- Kept as a method: Dock.lua's ShouldShow, the feign watch and Window.lua all
-- call it, and none of the three need to know where the scan now lives.
function DM:GroupInCombat()
    return KE.CombatState:GroupInCombat()
end

---------------------------------------------------------------------------------
-- Combat-state event handlers
--
-- Liveness, the ticker, and the encounter/PvP state that used to gate it here
-- are KE.CombatState's job (Core/CombatState.lua) -- see the shared listener
-- above. What remains below is DM-specific bar/segment/history bookkeeping
-- that still needs to run on these events.
---------------------------------------------------------------------------------

-- Feign-death filtering (Deaths view)
--
-- Feign Death registers as a real death: the row carries a valid deathRecapID
-- and is indistinguishable from a death that happened. The filter tags the ROW
-- rather than the unit, because a unit key cannot separate a hunter's feign
-- from that same hunter's later real death, and because row identity is the
-- only identity readable mid-fight.
--
-- ONE PROPERTY GOVERNS EVERY REFUSAL HERE: this must never remove a real death
-- from the list. It may fail to hide a feign as often as it likes. Every guard
-- below fails toward showing a row.
--
-- Scope, and it is narrow on purpose: the player's OWN feign only, only while
-- the group is fighting, only on an unpinned Current window reading the live
-- session, and only until the player's first real death -- after which nothing
-- is filtered until the meter's data is reset. The design notes carry the
-- reasoning; the short version is that nothing in the API says which fight the
-- live session belongs to, or when a death row appears in it, so anything
-- looser can hide a real death.
local FEIGN_SPELL_ID = 5384
local FEIGN_POLL     = 0.2
local FEIGN_TICKS    = 15

-- Cancel the bounded watch. The handle may be LIVE or SPENT (a ticker that ran
-- out its iterations leaves itself in the field), and cancelling a spent one is
-- harmless -- which is why no expiry callback exists.
function DM:StopFeignWatch()
    if self._feignWatch then
        self._feignWatch:Cancel()
        self._feignWatch = nil
    end
end

-- Drop every tag and the watch. Does NOT touch _feignArmable: dropping stale
-- tags and deciding whether a fight may be watched are different questions, and
-- conflating them disables the feature entirely (a combat start wipes).
function DM:ClearFeignTags(site)
    self:StopFeignWatch()
    if self._feignTags then wipe(self._feignTags) else self._feignTags = {} end
    if self._feignSnapshot then wipe(self._feignSnapshot) else self._feignSnapshot = {} end
    if self._feignAmbig then wipe(self._feignAmbig) else self._feignAmbig = {} end
    -- The per-render session memo has to go with them. It is only cleared at the
    -- start of a render tick, and a mouse-wheel scroll renders directly without
    -- that clear -- so a tag earned now could otherwise be applied to the
    -- previous fight's cached table.
    if self._sessionCache then wipe(self._sessionCache) end
    if DEBUG_DM then KE:Print("[DM] feign tags cleared: " .. site) end
end

-- The one predicate Window.lua calls. Secrecy is tested before either table
-- index because a secret key contaminates the read. Only an own-row may ever be
-- hidden, and an id the collision scan flagged is never hidden.
function DM:FeignTagged(recapID, isLocalPlayer)
    if not self._feignTags then return false end
    if recapID == nil or issecretvalue(recapID) then return false end
    if not DM.PlainOwnRow(isLocalPlayer) then return false end
    if not self._feignTags[recapID] then return false end
    if self._feignAmbig and self._feignAmbig[recapID] then return false end
    return true
end

-- Which new row is the feign? Returns id + status so the caller can tell "none
-- yet" from "cannot tell": the watch keeps running on the first and stops on the
-- second. Collapsed into a bare nil, the watch keeps sampling through an
-- ambiguity it has already detected, and can then tag a real death.
function DM.SelectFeignRow(sources, snapshot)
    if not sources then return nil, "none" end
    local found
    for i = 1, #sources do
        local row = sources[i]
        local rid = row and row.deathRecapID
        if rid ~= nil and not issecretvalue(rid) and rid > 0
            and not (snapshot and snapshot[rid])
            and DM.PlainOwnRow(row.isLocalPlayer) then
            if found then return nil, "ambiguous" end
            found = rid
        end
    end
    if found then return found, "found" end
    return nil, "none"
end

-- Tagged ids that appear on MORE THAN ONE own-row in this list. A tag names one
-- death; if the list holds two rows carrying it, the tag cannot say which, so
-- neither is hidden. Defence in depth, not the primary defence -- it sees one
-- list at a time and cannot catch a collision that spans two.
local feignSeen = {}
function DM.ScanFeignAmbiguity(sources, tags, out)
    if not out then return nil end
    wipe(out)
    if not sources or not tags or not next(tags) then return out end
    wipe(feignSeen)
    for i = 1, #sources do
        local row = sources[i]
        local rid = row and row.deathRecapID
        if rid ~= nil and not issecretvalue(rid) and rid > 0 and tags[rid]
            and DM.PlainOwnRow(row.isLocalPlayer) then
            if feignSeen[rid] then out[rid] = true else feignSeen[rid] = true end
        end
    end
    return out
end

-- The player cast Feign Death. Snapshot the Deaths list, then poll briefly for a
-- row that was not there before. A failed session read refuses the watch: an
-- unknown starting state cannot be diffed against.
function DM:ArmFeignWatch()
    self:StopFeignWatch()
    -- Tags already earned are KEPT. The new snapshot contains the first feign's
    -- row, so it cannot be re-selected, and dropping the tag would make that row
    -- reappear.
    local session = self:GetSession(Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.Deaths)
    local sources = session and session.combatSources
    if not sources then
        if DEBUG_DM then KE:Print("[DM] feign watch refused: no session") end
        return
    end

    if self._feignSnapshot then wipe(self._feignSnapshot) else self._feignSnapshot = {} end
    local n = 0
    for i = 1, #sources do
        local row = sources[i]
        local rid = row and row.deathRecapID
        if rid ~= nil and not issecretvalue(rid) and rid > 0 then
            self._feignSnapshot[rid] = true
            n = n + 1
        end
    end
    if DEBUG_DM then KE:Print("[DM] feign watch armed, snapshot " .. n) end

    self._feignWatch = C_Timer.NewTicker(FEIGN_POLL, function()
        if not DM.enabled then
            DM:StopFeignWatch()
            return
        end
        local s = DM:GetSession(Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.Deaths)
        if not s then return end
        local rid, status = DM.SelectFeignRow(s.combatSources, DM._feignSnapshot)
        if status == "none" then return end
        if DEBUG_DM then KE:Print("[DM] feign watch status: " .. status) end
        if status == "ambiguous" then
            DM:StopFeignWatch()
            return
        end
        -- Resolve both predicates to PLAIN booleans before anything compares or
        -- prints them. The raw returns may be secret; fdOk/deadOk cannot be.
        local fd   = UnitIsFeignDeath("player")
        local dead = UnitIsDead("player")
        local fdOk   = not issecretvalue(fd) and fd == true
        local deadOk = not issecretvalue(dead) and dead == false
        if fdOk and deadOk then
            DM._feignTags[rid] = true
            if DEBUG_DM then KE:Print("[DM] feign tagged: " .. rid) end
        elseif DEBUG_DM then
            KE:Print("[DM] feign tag refused: fd=" .. tostring(fdOk) .. " dead=" .. tostring(deadOk))
        end
        DM:StopFeignWatch()
    end, FEIGN_TICKS)
end

-- UNIT_SPELLCAST_SUCCEEDED is one of the highest-frequency events in the game,
-- so the spell test is first and nothing may be added above it. The event is not
-- a restricted callback (no HasRestrictions, no CallbackEvent) and several other
-- KE modules already register it broad.
function DM:OnSpellcastSucceeded(_, unitTarget, _, spellID)
    if issecretvalue(spellID) then return end
    if spellID ~= FEIGN_SPELL_ID then return end
    -- nil must refuse, so this tests against false explicitly.
    if self._feignArmable ~= true then return end
    if issecretvalue(unitTarget) or unitTarget ~= "player" then return end
    if not self:GroupInCombat() then return end
    self:ArmFeignWatch()
end

-- A real death drops every tag AND ends eligibility until the meter's data is
-- reset. That is what bounds the one exposure the design accepts: a death that
-- lands during a live watch can be tagged before this handler runs, and this
-- handler is what un-hides it.
function DM:OnPlayerDead()
    self._feignArmable = false
    self:ClearFeignTags("player death")
end

-- Only the UI teardown a fresh fight needs; liveness is the service's call.
function DM:OnRegenDisabled()
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
    -- An open detail panel used to be closed unconditionally here. Now a panel the
    -- eligibility rule still permits stays open and keeps updating through the fight.
    -- Everything else closes, as before.
    --
    -- The order matters. A MESSAGE panel closes outright: an out-of-combat refusal
    -- left on screen is not eligible data to carry into a new fight, and unlike the
    -- tick path there is no live refusal to preserve. A DATA panel is then checked for
    -- view DRIFT -- if the effective view has changed since it opened it is showing a
    -- view that is no longer selected, so it closes rather than re-rendering into one
    -- it was never authorized for. Only then is eligibility applied, and to the CURRENT
    -- view rather than the snapshotted one: the snapshot detects drift, it never
    -- authorizes.
    if self.windows_rt then
        for _, W in pairs(self.windows_rt) do
            if W._detailOpen and self.CloseDetail then
                local keep = false
                if W._detailKind == "data" then
                    local cfg = self.ResolveWindowConfig and self:ResolveWindowConfig(W.idx)
                    local nowType = cfg and self:EffectiveMeterType(W.idx, cfg)
                    if nowType ~= nil and nowType == W._detailMeterType then
                        keep = self:DetailEligible(W._detailOwnRow, nowType)
                    end
                end
                if not keep then self:CloseDetail(W) end
            end
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
    if DEBUG_DM then KE:Print("[DM] PLAYER_REGEN_DISABLED") end
end

-- Only the cache invalidation that a combat end marks the boundary of.
function DM:OnRegenEnabled()
    -- Combat ended for the player: a hover tip showing the in-combat "secret" message
    -- should re-populate with real (now-readable) data on the next poll -- mark dirty.
    self._hoverTipDirty = true
    -- Combat end is a Targets-cache boundary too (the sub-section is out-of-combat-only):
    -- drop it so the post-fight hover rebuilds against THIS fight's enemies, not the stale
    -- constant-keyed map (wiped on both REGEN_DISABLED + ENABLED).
    if self.InvalidateTargetsCache then self:InvalidateTargetsCache() end
end

-- A hard segment boundary: segment and history bookkeeping only.
function DM:OnEncounterStart()
    if DEBUG_DM then KE:Print("[DM] ENCOUNTER_START") end
    -- Segment boundary: a boss pull starts a new segment, so a view override from the
    -- previous boss/trash clears ("until another raid boss starts").
    self:BumpSegment()
    self:ClearFeignTags("encounter start")
    -- Stored-id snapshot for the kill/wipe tint: OnEncounterEnd tags only sessions
    -- stored SINCE this pull. "Tag the newest" mis-tagged a key-completing final
    -- kill -- Blizzard stores the run-level "+NN" session on top of the boss's own
    -- (live repro), so the boss's outcome landed on the run row. Plain
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

-- Boss kill/wipe: a hard segment boundary for the outcome-tagging walk below.
--
-- The payload's `success` (1 = kill, 0 = wipe; plain event payload, never secret)
-- feeds the segment-menu kill/wipe tint: shortly AFTER the finalize delay, every
-- session stored SINCE the pull (the OnEncounterStart snapshot) gets tagged --
-- normally just the boss's own session, but a key-completing final kill also
-- stores the run-level "+NN" session, and both belong to this kill (a last-boss
-- wipe never completes the key, so the run row can't inherit a red). Sessions
-- only append, so new ids sit contiguously at the list tail -- walk backward and
-- stop at the first pre-pull id, EXCEPT the newest tail entry (the live session
-- combat just finished), which is always tagged: Blizzard can create the boss's
-- session just before ENCOUNTER_START fires, landing it in the pre-pull snapshot.
-- No snapshot (the pcall'd read failed at the pull, or a mid-encounter /reload)
-- -> fall back to tagging the newest only.
-- Runtime-only on purpose: stored sessions don't survive a /reload, so neither
-- must the map (wiped on every session reset).
function DM:OnEncounterEnd(_, _, _, _, _, success)
    if DEBUG_DM then KE:Print("[DM] ENCOUNTER_END") end
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
            -- Reached pre-pull history -> stop. EXCEPTION: the newest entry
            -- (i == #list) is the live session combat just finished, i.e. the
            -- boss. Blizzard sometimes creates that session a moment BEFORE
            -- ENCOUNTER_START fires (races the event -- in a live kill the
            -- 10-id snapshot already held the boss's own session),
            -- so it lands in the snapshot and the walk would otherwise break on
            -- it and tag nothing -> the boss row stays uncolored. Tag it anyway;
            -- older in-snapshot sessions are genuine history and still stop here.
            if snap and snap[nid] and i ~= #list then   -- reached pre-pull territory
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

-- Zoning: feign teardown and the content-context recheck.
function DM:OnCombatForceStop()
    if DEBUG_DM then KE:Print("[DM] PLAYER_ENTERING_WORLD") end
    self:ClearFeignTags("zone change")
    -- An in-combat reload must leave the live clock alone. Two frames handle
    -- this event and the game promises no order between them, so the gate is
    -- written to be correct either way: reached first, the machine's own
    -- re-derivation restarts the ticker afterwards; reached second, it is
    -- already live and this is skipped.
    if not KE.CombatState:IsLive() then
        self._clockCleared = true
        self:StopTicker()
    end
    -- Zoning may change the content context (entered/left an instance) -- schedule a
    -- settled re-check (debounced; IsInInstance isn't reliable until the world loads).
    self:_ScheduleContextCheck()
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
    self:ClearFeignTags("meter reset")
    -- The ONLY thing that enables feign filtering. A reset clears the data those
    -- rows lived in, so nothing pending can be held against a later list. Every
    -- cheaper signal -- leaving combat, an empty list, a login -- is an inference
    -- about the game's internals, and each one can hide a real death when the
    -- inference is wrong.
    self._feignArmable = true
    -- History bundles are already-captured data and survive every reset
    -- event (only eviction / HeaderReset / reload clear them). But pending
    -- PROVENANCE does not: an external reset empties the native store, so
    -- the armed key label would mislabel whatever accumulates afterwards —
    -- clear it. EXCEPT for the module's own key-start wipe (one-shot flag
    -- set just before its ResetAllCombatSessions call): consume the flag
    -- and keep pending, which OnChallengeEvent arms right after.
    if self._historyOwnReset then
        self._historyOwnReset = nil
    else
        -- Both copies (runtime + persisted; History.lua). Guarded for load order.
        if self.HistoryDropPending then self:HistoryDropPending() else self._pendingBundle = nil end
    end
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
    if not KE.CombatState:IsLive() then
        self._clockCleared = true
    end
    -- Closing an overlay re-gates the header, and the Tick that would recompute the
    -- clock comes after it, so the cache goes first or a stale duration can be
    -- re-shown in between.
    if self.ClearClockCache then self:ClearClockCache() end
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
    -- Negative id = local key-history snapshot (History.lua). The API only
    -- ever issues positive ids, so this cannot shadow a live session; the
    -- serve is a plain table read (no pcall needed). Resolved at runtime —
    -- History.lua loads after this file.
    if type(sessionID) == "number" and sessionID < 0 then
        if self.HistorySession then return self:HistorySession(sessionID, dmType) end
        return nil
    end
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

-- Resolve the raw isLocalPlayer field to a PLAIN boolean. Every caller that
-- needs the answer more than once resolves it here first, so the secrecy guard
-- exists in one place and nothing downstream ever holds the raw field.
function DM.PlainOwnRow(isLocalPlayer)
    if issecretvalue(isLocalPlayer) then return false end
    return isLocalPlayer == true
end

-- The combat test is deliberately BROADER than InCombatLockdown(). That flag drops
-- to false the moment the player dies or feign-deaths mid-pull (see GroupInCombat),
-- while the fight -- and the API's secrecy -- continues. Restricting on the union of
-- the two signals can only refuse MORE often, never less, which is the safe direction
-- for a gate whose failure mode is a thrown error mid-render.
local function DetailCombatActive()
    return InCombatLockdown() or UnitAffectingCombat("player")
end
-- Shared with Detail.lua: every detail path that asks "is combat on" must ask it the
-- same way, or the gate and the renderers will disagree about which data is secret.
DM.DetailCombatActive = DetailCombatActive

-- Scratch reused across calls: the match runs on the tick path while an ally
-- panel is open, and a fresh table per call would churn garbage there.
local matchScratch = {}

-- A spec icon we can actually discriminate on. The client leaves specIconID nil
-- for a player it has not resolved -- in a pug commonly everyone -- and reports 0
-- for a mob. Both mean "unknown", and neither may narrow anything.
local function KnownSpec(v)
    return type(v) == "number" and v ~= 0
end

-- Which group member does this row belong to? PURE over the roster index plus the
-- row's two NeverSecret fields, so the whole decision is testable without the
-- meter. Returns a plain GUID, or nil and a reason.
--
-- Spec is a TIE-BREAK, never a requirement. Class is plainly readable on both
-- sides always; spec often is not. Demanding a spec would refuse most pug rows
-- for no safety gain, because a lone member of a class is unambiguous whatever
-- their spec is.
--
-- Every uncertain case refuses. Showing one player's damage under another
-- player's name is silent and unrecoverable, so nothing here guesses.
-- rowsOfClass is how many sources of this class the session holds, excluding the
-- player's own. The roster answers "who could this row be"; only the source list
-- answers "is this row one of them". More sources than members means a
-- class-bearing entity is present that the roster cannot account for -- a
-- departed player's row that outlived their group membership -- and there is no
-- way to tell which row is which. Equal counts are the ordinary case, including
-- a legitimate two-members-two-rows tie-break, so this refuses only the surplus.
function DM.MatchRowToRoster(members, classFilename, specIconID, rowsOfClass)
    if type(members) ~= "table" then return nil, "roster" end
    if type(classFilename) ~= "string" or classFilename == "" then return nil, "noclass" end

    wipe(matchScratch)
    for i = 1, #members do
        local m = members[i]
        if m and m.class == classFilename then
            matchScratch[#matchScratch + 1] = m
        end
    end

    local n = #matchScratch
    if n == 0 then return nil, "nomatch" end

    -- Surplus rows: an entity the roster cannot account for. Tested BEFORE the
    -- lone-member fast path, because that path is exactly the one a stale leaver
    -- row would otherwise sail through.
    if type(rowsOfClass) ~= "number" then return nil, "rowcount" end
    if rowsOfClass > n then return nil, "surplus" end

    if n == 1 then return matchScratch[1].guid end

    if not KnownSpec(specIconID) then return nil, "specunknown" end

    local hit
    for i = 1, n do
        local m = matchScratch[i]
        -- A candidate whose spec is unknown could BE this row. Refusing on it is
        -- what stops a half-resolved roster from narrowing to the one member it
        -- happens to know about.
        if not KnownSpec(m.spec) then return nil, "specunknown" end
        if m.spec == specIconID then
            if hit then return nil, "ambiguous" end
            hit = m
        end
    end
    if not hit then return nil, "nomatch" end
    return hit.guid
end

-- May a detail panel open, and stay open? The single gate every detail path
-- consults -- click, hover, combat-start, and the tick refresh.
--
-- OUT OF COMBAT this is unconditionally true, and the short-circuit lives HERE
-- rather than in each caller. The tick path runs out of combat too (StopTicker's
-- final paint, OnSessionUpdated's settle repaints), so a predicate that forgot
-- it would close panels that work today -- another player's breakdown, a death
-- recap -- the moment a session settled.
--
-- IN COMBAT it admits one thing: the local player's own row, on a view whose
-- renderer can survive secret values.
--   * isLocalPlayer is the only source identity the API guarantees readable
--     mid-fight (NeverSecret). issecretvalue is tested BEFORE the comparison so
--     a wrong annotation costs the feature instead of throwing.
--   * Deaths is ADMITTED, for every row and without consulting the identity at
--     all. It is keyed on deathRecapID, which is NeverSecret, so the recap is
--     addressable for any row on screen -- a different authorization model from
--     the own-row rule, not a widening of it. Its renderer guards every field.
--   * EnemyDamageTaken is refused because its drill-down aggregates and compares
--     amounts across sources, which secret values cannot survive.
--
-- meterType MUST be the EFFECTIVE type (DM:EffectiveMeterType), never
-- cfg.MeterType. A view override changes the view without touching the config,
-- and survives until a segment boundary, so the two disagree -- while the click
-- dispatch follows the effective one. Feeding this the config value would admit
-- a click that then lands in the death recap mid-fight.
function DM:DetailEligible(isLocalPlayer, meterType)
    if not DetailCombatActive() then return true end
    -- ORDER IS LOAD-BEARING. Deaths is tested BEFORE the own-row rule because it does
    -- not consult identity: admitting it below the own-row test would open the recap
    -- for the player's own death only, which looks identical until someone clicks
    -- another player's.
    if meterType == Enum.DamageMeterType.Deaths then return true end
    if not DM.PlainOwnRow(isLocalPlayer) then return false end
    if meterType == Enum.DamageMeterType.EnemyDamageTaken then return false end
    return true
end

-- Returns the per-source detail table for a single combat source (keyed by
-- sourceGUID), or nil on failure. Mirrors GetSession's FromID/FromType branch.
--
-- isOwnRow is the LAST parameter on purpose. Three of the five call sites do not
-- pass it (the targets aggregation and enemy branch in Detail.lua, the snapshot
-- store in History.lua) and must not have to change: a mid-signature insert
-- would shift their sessionID, and the history branch below TESTS its type
-- rather than asserting it, so a shifted argument would degrade into the wrong
-- lookup instead of failing loudly.
--
-- SECOND RETURN, "refused": the identity was secret and could not legally be
-- substituted. It is a second return rather than a sentinel in the first
-- position precisely because those three call sites never opt in -- History.lua
-- tests the first return with a bare truthiness check before writing it into the
-- persisted snapshot, so a truthy marker there would be stored as if it were
-- real source data. nil is what they already handle.
function DM:GetSource(sessionType, dmType, sourceGUID, sourceCreatureID, sessionID, isOwnRow)
    -- In combat the stashed identity is secret, so the API call below cannot
    -- legally receive it (SecretArguments = AllowedWhenUntainted, and addon code
    -- is tainted). For the player's OWN row there is a legal substitute: a plain
    -- GUID for the same unit. Every other case refuses.
    if issecretvalue(sourceGUID) or issecretvalue(sourceCreatureID) then
        if isOwnRow ~= true then return nil, "refused" end
        -- A negative id is a stored History.lua snapshot, not the live API.
        -- Looking that up with a live GUID could resolve a different row
        -- entirely, so the substitution does not apply to it.
        if type(sessionID) == "number" and sessionID < 0 then return nil, "refused" end
        local plainGUID = UnitGUID("player")
        -- UnitGUID is SecretWhenUnitIdentityRestricted AND its return is
        -- nilable. A secret substitute is the illegal case this exists to
        -- avoid; a nil one would send nil for both identity arguments and
        -- resolve something unintended. Refuse on either -- and test secrecy
        -- BEFORE the nil comparison, because comparing a secret throws.
        if issecretvalue(plainGUID) or plainGUID == nil then return nil, "refused" end
        sourceGUID, sourceCreatureID = plainGUID, nil
    end

    if type(sessionID) == "number" and sessionID < 0 then
        if self.HistorySource then
            return self:HistorySource(sessionID, dmType, sourceGUID, sourceCreatureID)
        end
        return nil
    end
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

-- Combat-clock text: "[M:SS]", or nil when the clock should HIDE. Returns
-- (text, isSecret) so the caller can skip its dirty check on a secret string.
--
-- ORDER IS THE POINT OF THIS FUNCTION. Steps 3 and 4 are comparisons and type()
-- does not filter secrets, so the secrecy test has to sit above them or a secret
-- duration reaches them and throws.
--
-- Anything under a second HIDES rather than rendering "[0:00]" -- a fight of no
-- measurable length did not happen, and the game's own meter blanks its timer on
-- a zero duration.
local function ClockText(duration)
    if not duration then return nil end             -- truthiness: safe on a secret
    if issecretvalue(duration) then
        local str, strSecret = FormatDeathTime(duration)
        -- FormatDeathTime falls back to the plain literal "0:00" when the
        -- abbreviation yields nothing, and that must HIDE. strSecret alone cannot
        -- tell the two apart: a secret whose abbreviation came back PLAIN also
        -- reports false, and that is a real reading. Comparing the string is legal
        -- only because strSecret false proves it is not secret -- hence the guard
        -- on the same line, in that order. Every real abbreviation ends in "s".
        if not strSecret and str == "0:00" then return nil end
        -- strSecret, not a hardcoded true: a plain abbreviation keeps its dirty check.
        return "[" .. str .. "]", strSecret
    end
    if type(duration) ~= "number" then return nil end
    -- Under a second, not just zero or negative. FormatDeathTime floors, so 0.4
    -- would render "0:00" -- the exact string this function exists to keep off
    -- the screen. The live stopwatch passes through this range at the start of
    -- every pull.
    if duration < 1 then return nil end
    return "[" .. FormatDeathTime(duration) .. "]", false
end

-- Cross-chunk API: the render layer calls these directly. Non-underscore names
-- because they are intentional public API on DM (underscore-prefix fields are
-- private-to-file by KE convention); matches DM.RANK_STRINGS / DM.BAR_POOL_SIZE
-- in Window.lua.
DM.FormatBarValue = FormatBarValue
DM.FormatDeathTime = FormatDeathTime
DM.ClockText = ClockText

-- Marks a recap the client would not let us read, as opposed to one that simply
-- is not there. The two look identical to a caller that only tests the events,
-- and they mean different things to the user, so the distinction is a value
-- rather than a comment. Lives on the module table because every consumer is in
-- the detail renderer, a different file.
DM.RECAP_UNREADABLE = "recap-unreadable"

-- Reversed (oldest-first) recap events for a deathRecapID. C_DeathRecap is a
-- separate namespace (NOT C_DamageMeter) and none of its getters declares any
-- secrecy, but DeathRecapEventInfo is declared with an EMPTY field list, so every
-- field is treated as possibly secret by the renderers. All calls pcall'd;
-- deathRecapID is NeverSecret on the source.
--
-- EXACTLY THREE RETURN SHAPES, and callers must discriminate in this order:
--   success     (events, sinkMax, plainMax)
--   unreadable  (nil,    DM.RECAP_UNREADABLE, nil)
--   absent      (nil,    nil,     nil)
-- Test `events` FIRST and reach the second slot only in an else branch. On the
-- success shape that slot holds sinkMax, which can be a secret number, and
-- comparing a secret throws -- so a caller that tests it first crashes on the
-- one shape that worked.
--
-- The two maxima are NOT interchangeable and neither substitutes for the other:
--   sinkMax  -- for SetMinMaxValues and nothing else. The API's value when it is
--              secret, the same number when it is a plain positive, nil for a
--              failed call and for a plain zero, negative or non-number. A zero
--              would draw a full-height empty bar, which asserts a death at full
--              health; a maximum that cannot be a denominator is not a maximum.
--   plainMax -- the ONLY one arithmetic may touch. Never secret. A plain positive
--              number or nil, and nil means the percentage cannot be computed.
function DM:GetDeathRecap(recapID)
    -- Entry guards, all of them the ABSENT shape: nothing was unreadable, there is
    -- simply nothing to fetch.
    if not C_DeathRecap then return nil end
    if not recapID or issecretvalue(recapID) or recapID <= 0 then return nil end

    if C_DeathRecap.HasRecapEvents then
        local okh, has = pcall(C_DeathRecap.HasRecapEvents, recapID)
        -- Only a returned, readable false refuses. A secret answer and a failed call
        -- are both "we did not get an answer", and reading that as "no recap" would
        -- hide a recap the fetch below would have returned -- this preflight is an
        -- optimisation, and the fetch already handles a missing or empty result.
        -- issecretvalue must stay before the truthiness test: a secret boolean throws.
        if okh and not issecretvalue(has) and not has then return nil end
    end

    local ok, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not ok or not raw then return nil end
    -- canaccesstable asks "may I index this", which is NOT what issecrettable asks --
    -- that one is true whenever access would yield secrets, i.e. normally in combat,
    -- and refusing on it would refuse every in-combat recap. First contact with the
    -- return, before the length operator, because the operator is what would throw.
    -- An absent predicate means a client with no secret-table machinery to guard
    -- against, so index it the way this code always has rather than inventing a
    -- restriction the client never reported.
    if canaccesstable and not canaccesstable(raw) then return nil, DM.RECAP_UNREADABLE end
    if #raw == 0 then return nil end

    local sinkMax, plainMax
    if C_DeathRecap.GetRecapMaxHealth then
        local okm, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
        if okm and hp then
            if issecretvalue(hp) then
                sinkMax = hp
            -- type() does NOT filter secrets, so the secrecy test has to come first or
            -- a secret number reaches the comparison below and throws.
            elseif type(hp) == "number" and hp > 0 then
                sinkMax, plainMax = hp, hp
            end
        end
    end

    -- API returns newest-first; reverse to oldest-first into a per-call table. NO
    -- per-event access gate: an element access yields a table rather than a secret,
    -- the per-field guards in the renderers are what handle secret contents, and a
    -- gate here would silently drop rows from a death recap.
    local rev = {}
    for i = #raw, 1, -1 do rev[#rev + 1] = raw[i] end
    return rev, sinkMax, plainMax
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
-- "count | rate" half for count types).
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

-- Settings: open the GUI straight to the Damage Meter page.
function DM:HeaderSettings(_)
    if KE.GUIFrame and KE.GUIFrame.OpenPage then
        KE.GUIFrame:OpenPage("DamageMeter", "skinning_section")
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
    -- Key history is part of a manual reset by design (the GUI note
    -- promises "one reset clears every window and the segment history
    -- together"). Resolved at runtime; guarded for load order. NOTE:
    -- OnMeterReset deliberately does NOT clear the store — our own
    -- key-start wipe fires DAMAGE_METER_RESET right after capture.
    if self.HistoryClear then self:HistoryClear() end
    -- A mid-run manual reset also breaks pending provenance: the store no
    -- longer holds the armed key from its wipe boundary, so a later
    -- capture must seal as "Earlier runs", not under this key's label.
    -- Both copies (runtime + persisted; History.lua). Guarded for load order.
    if self.HistoryDropPending then self:HistoryDropPending() else self._pendingBundle = nil end
    -- Frozen combat clock referenced the wiped data too (mirrors OnMeterReset;
    -- in-combat resets keep the live clock -- the fight itself continues).
    if not KE.CombatState:IsLive() then
        self._clockCleared = true
    end
    -- Same ordering as the reset handler: closing an overlay re-gates the header
    -- and the Tick comes after, so drop the clock cache first.
    if self.ClearClockCache then self:ClearClockCache() end
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
-- /reload -- until the user re-picks or a segment boundary passes), KEEPS any pinned
-- session -- a session id (stored or history) serves every meter type, since
-- GetSession passes dmType through both id branches, so the switch re-reads the SAME
-- segment's new metric (the GUI meter-type path keeps pins the same way; CachedSession's
-- (sessionType, meterType, sessionID) key is memoization, not identity) -- closes the
-- detail panel (its breakdown/recap was keyed to the old view), closes the selector,
-- and repaints. meterType is a plain Enum.DamageMeterType value -- never secret.
function DM:SetWindowView(W, meterType)
    if not W then return end
    local windows = self.db and self.db.Windows
    local window = windows and windows[W.idx]
    if not window then return end
    window.ViewOverride = meterType
    window.ViewOverrideToken = self:CurrentSegmentToken()
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
    -- A context change re-scopes every window, and LayoutDock re-gates the header
    -- before the repaint below.
    if self.ClearClockCache then self:ClearClockCache() end
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
    -- run the user is still reviewing. Details-Midnight resets the server store
    -- at key start too -- it keeps cross-key history only because it snapshots
    -- each finalized fight into addon-local tables (the server store is just its
    -- live feed). KE renders the server store directly, and ResetAllCombatSessions
    -- is C_DamageMeter's ONLY mutator (12.0.7: no overall-only reset, no per-session
    -- delete; in-combat amounts are secret, so summing a per-run Overall locally is
    -- blocked). So the ResetOnKeyStart toggle (Behavior tab) picks which cost to eat:
    -- on = "Overall" means "this run" but history dies at each key start;
    -- off = sessions survive the boundary (history AND Overall span keys; pins stay
    -- valid, so none of the reset teardown below applies) until a manual reset; the
    -- run-level "+NN" session stored at key completion still gives a per-run summary
    -- after the fact. A local snapshot store would give both at once --
    -- that's a feature (new data layer), not a different gate here.
    if event == "CHALLENGE_MODE_START" then
        if self.db and self.db.ResetOnKeyStart then
            -- Snapshot the whole store BEFORE the wipe (History.lua): seals
            -- the previous key's bundle, reading _sessionOutcomes and the
            -- pending key metadata while both still describe it. Resolved
            -- at runtime; guarded for load order.
            if self.HistoryCapture then self:HistoryCapture() end
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
            local wiped = false
            if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
                -- One-shot: our own wipe fires DAMAGE_METER_RESET, whose handler must
                -- not clear the pending record this handler arms below. Armed before
                -- the call (delivery can be synchronous), un-armed if the call failed
                -- (a stale flag would eat the NEXT external reset's provenance clear).
                self._historyOwnReset = true
                wiped = pcall(C_DamageMeter.ResetAllCombatSessions)
                if not wiped then
                    self._historyOwnReset = nil
                end
            end
            -- The hover-tip Targets cache cross-references the now-wiped data.
            if self.InvalidateTargetsCache then self:InvalidateTargetsCache() end
            -- Outcome tags reference the wiped session ids (mirrors OnMeterReset).
            if self._sessionOutcomes then wipe(self._sessionOutcomes) end
            -- Repaint the emptied bars now: ApplyActiveContext below early-returns when the
            -- content context is unchanged (a key RE-RUN stays "Mythic+"), so it can't be
            -- relied on to paint after the reset. BumpSegment already closed selectors/menus.
            if self.Tick then self:Tick() end
            -- Arm the pending metadata for THIS key — only ever on a wipe
            -- boundary that actually HAPPENED; arming after a failed reset
            -- would label a store still spanning multiple keys [C2].
            if wiped and self.HistoryArmPending then self:HistoryArmPending() end
        else
            -- Key boundary WITHOUT a wipe: the store now spans multiple
            -- keys, so an armed label no longer describes it. Clear it so a
            -- later capture seals honestly as "Earlier runs" [C2] (covers
            -- flipping the toggle off and back on across runs). Both copies
            -- (runtime + persisted; History.lua). Guarded for load order.
            if self.HistoryDropPending then self:HistoryDropPending() else self._pendingBundle = nil end
        end
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        -- Freeze outcome/duration + repair keystone metadata from the
        -- authoritative completion info [C1][C4].
        if self.HistoryOnKeyComplete then self:HistoryOnKeyComplete() end
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
            self:RenderWindowAndDetail(W)
        end
    end

    if deferred then
        C_Timer.After(0, function()
            for _, W in ipairs(deferred) do
                DM:RenderWindowAndDetail(W)
            end
        end)
    end
end
