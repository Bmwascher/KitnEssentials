# [Changelog](https://github.com/Bmwascher/KitnEssentials/blob/main/CHANGELOG.md)

## v1.16.3

### Ebon Might Tracker
- **NEW:** Pandemic Highlight — glow overlay during the last 4s of an Ebon Might buff, with 4 selectable glow styles (pixel, autocast, button, proc) and a configurable color. Forces the frame visible during the refresh window even when *Only Show on Crit* is enabled, so pandemic windows are never missed
- **NEW:** Main Stat card with an *Update from Current Stat* button — saves your primary stat as the first-cast bootstrap baseline. Auto-saves on combat exit and login; the button is a manual fallback for mid-fight gear/stat changes. Arcane Intellect is factored out automatically
- Rewrote crit detection — replaced the persisted baseline classifier with a 30s rolling cast-history window (single 1.25× threshold against the rolling minimum). Crit is now locked at cast time so mid-buff stat shifts (trinket procs, AI drop, gear swaps) no longer flip the border color partway through a buff
- Dupe detection switched to a live signal driven by the duplicate totem state (`PLAYER_TOTEM_UPDATE` + totem poll) — flips the dupe color the moment the duplicate spawns or expires during an active buff, instead of inferring from aura magnitude
- Added Pandemic Color picker — Colors card now lays out as a 2×2 grid (Base / Crit / Dupe / Pandemic)
- Logic adapted from EMTracker v1.2.0 by Baumritter

### Kick Tracker
- Removed Spell ID `132409` from the interrupt list — Blizzard removed this ability from Warlocks in 12.0.5
- Module is currently non-functional in 12.0.5 due to API changes — investigating alternative detection methods for a future release

---

## v1.16.2

### Dungeon Casts
- Fixed enemy cast bars silently dropping for every player-targeted hostile cast in 12.0 — `UnitSpellTargetName` returns the target's name directly (not a unit token), but the code was passing it to `UnitName` which rejects secret strings. Target names now render correctly for all casts
- Target names for player targets display with their class color
- Long target names truncate cleanly at the region edge instead of overlapping the spell name or time column
- Fixed the time text occasionally truncating to `...` at larger font sizes — width reservation now measures your configured font + size + outline once per settings change and caches it, so any font combination fits without manual tuning

### Focus Castbar / Target Castbar
- Fixed party member name highlighting that was silently broken in 12.0. Previously only your own name would ever light up because `UnitIsSpellTarget(caster, partyUnit)` no longer returns true for teammates. The castbar now shows a single target name string (player, party member, or NPC) with class color for player targets — more informative than the old highlight-one-of-five behavior

### Dungeon Timers
- Fixed stale text warnings firing after a boss died — bars with a Timer Offset were being held through `BigWigs_OnBossDisable` even when their countdown still had several seconds left. The HOLD guard now only keeps bars alive when they're inside the extension tail (the BigWigs bar has already naturally elapsed), not when the fight ended mid-countdown

---

## v1.16.1

### Packaging
- Declared `markup-type: markdown` on the manual-changelog in `.pkgmeta` so the CurseForge changelog tab renders headers, bullets, bold, and inline code properly. Wago was already auto-detecting markdown from the `.md` extension — no regression there

### CHANGELOG
- Rewrote every release entry from the old `Additions` / `Fixes` / `Changes` sub-header format to module-name sub-headers matching v1.15.0 / v1.16.0 style. No version history changed — purely a presentation pass

---

## v1.16.0

### World Map
- **NEW:** City Map Icons for Silvermoon, Stormwind, and Orgrimmar — trainers, innkeepers, portals, vendors, and class-hall teleports. Click an icon to set a waypoint
- **NEW:** Icon Style selector (Regular item icons / Small minimap-style with glow backdrop)
- **NEW:** "Only Show Trainers for Learned Professions" filter
- Renamed module from "World Map Scaler" → "World Map"

### WarpDeplete+
- **NEW:** Per-mob nameplate % overlay with configurable font, color mode (theme/custom), and anchor
- **NEW:** Death log persists across /reload within the same M+ key
- Rewrote forces tracking to use `C_ScenarioInfo.GetUnitCriteriaProgressValues` (added 12.0.5)
- Live pull-forces overlay removed — 12.0.5 blocks SecretValue arithmetic in tainted context. Tooltip and nameplate % still work
- Fixed death tooltip and class-color path for 12.0.5 localized CLEU

### Ebon Might Tracker
- Fixed 12.0.5 crit/dupe detection — `UnitStat` returns a secret value mid-encounter, breaking the old ratio math. Replaced with a baseline classifier that learns the clean EM average per target count and persists it across /reload
- **NEW:** Chronowarden apex Dupe proc detection (spellId 1259175)
- **NEW:** Recomputes on `UNIT_FLAGS` so death/charm/afk state changes feed the classifier

### Bloodlust Tracker
- Fixed repeated sound triggers in heavy raid combat — sound plays once by default instead of looping until the bar ends (matches upstream HighOnHaste v0.5.4)
- Added `numFrames` guard preventing divide-by-zero when sprite-sheet dimensions are degenerate

### Disintegrate Ticks
- Fixed 12.0.5 tick spacing — `UnitSpellHaste` returns a secret value in encounters; haste is now back-solved from the channel's actual duration
- Synced to upstream DisintegrateTicks v2.1.1

---

## v1.15.0

### Healer Mana (new module)
- **NEW:** Shows the party healer's name, mana %, and spec or class icon — configurable font, position, color, icon size, and icon type
- **NEW:** "Hide when my spec is a healer" toggle for self-healers
- Custom Nicknames apply automatically to the display
- Preview defers to the real healer when one's in your party

### Instance Reset (new module)
- **NEW:** Announces to party/raid chat when you reset instances — configurable message

### Dungeon Timers
- **NEW:** "Load KES Presets" button — imports curated preset triggers for the selected dungeon scope (dedup on repeat clicks)
- Reset button now scope-aware — "Reset All Dungeons" or "Reset [Dungeon Name]" based on the Dungeon dropdown
- Fixed Export/Import silently dropping triggers after a deleted entry (sparse-table iteration bug in `ipairs`/`#`)

### Combat
- Protection Paladin Avenger's Shield announce + fade-out restored, with `notInterruptible` nil-guard
- Balance Druid Solar Beam announce via Combat Texts

### CreatePrompt (shared widget)
- Fixed single-edit-box dialogs clipping their label (adaptive height, mirroring the v1.13.0 confirmation-prompt fix)

### Misc
- 12.0.5 interface support
- Sidebar sections default to collapsed (except Settings)
- Dungeons sidebar alphabetical

---

## v1.14.3

### Combat Castbars
- Fixed green kick-ready tick marker wiggling between pixels during enemy casts — now stays rock-steady for the life of each cast

---

## v1.14.2

### Combat Castbars (Warlock)
- Fixed Focus/Target castbar sound not muting and bar staying in "kick not ready" color after casting Axe Toss on Demonology Warlock with Felguard out

---

## v1.14.1

### Ready Check Consumables
- Fixed `ADDON_ACTION_BLOCKED` error when a ready check started or finished during combat — the consumable row now hides cleanly once combat ends

### Combat Castbars (Warlock)
- Fixed castbars showing "kick not ready" color and playing the interrupt sound even when a pet kick was available

### Internal
- Combat folder restructure — shared Focus/Target castbar logic extracted, interrupt spell data centralized, per-frame API polls moved to event-driven updates. Smoother feel, no user-visible behavior changes

---

## v1.14.0

### Ready Check Consumables (new module)
- **NEW:** Clickable consumable icon row attached to the ready check popup — tracks food, flask, main-hand & off-hand weapon enhancements (oils/stones/ammo), augment rune, healthstone, and Warlock Soulstone
- **NEW:** Click-to-use via SecureActionButton with `/stopmacro [combat]`-gated macros so clicks are combat-safe
- **NEW:** Context-aware slot visibility — off-hand enhancement hides when no OH weapon equipped, healthstone hides when no Warlock in group, class slot Warlock-only
- **NEW:** Dual-mode positioning — auto-anchor to the ready check popup for non-starters, fallback UIParent anchor for the starter (Blizzard skips the popup for whoever initiates), plus a full custom-anchor mode
- **NEW:** Close button for the ready check starter so the icon row can be dismissed without waiting for the timeout
- **NEW:** Compatibility toggles — *Use flasks only from raid cauldron* (Fleeting variants only) and *Use only unlimited augment rune* (DF/TWW unlimited only, with LibCustomGlow pixel-glow prompt when the rune is in bags but not applied)
- **NEW:** GUI configuration panel under **Utilities** → *Ready Check Consumables* with Enable / General / Visible Consumables / Position / Font / Colors cards plus a mock ready check preview popup for settings preview
- Ported from MRT's `RaidCheck.lua` and trimmed to Midnight 12.0 consumables only

### Combat Potion Ready
- Display Text moved out of the Enable card into a new *Display & Visibility* card; three visibility toggles flattened into a single 3-column row

---

## v1.13.1

### Custom Nicknames
- **NEW:** Unhalted Unit Frames support via the `[kes:nickname]` tag family
- **NEW:** Class color variants `[kes:nickname:color]` and `[kes:nickname:color:N]` (N = 1-30) for UUF
- **NEW:** `:color:short` / `:color:medium` / `:color:long` named width variants for UUF
- Available Tags card split into shared block + UUF-only subsection
- UUF path placeholder added to the Note section

### ProfileManager
- Fixed nil-call crash on profile create / switch / copy / rename / reset (root cause of "my profile disappeared" reports)

---

## v1.13.0

### Custom Nicknames (new module)
- **NEW:** Map characters (`Name-Realm`) to personal nicknames on ElvUI unit frames via a new tag family: `[kes:nickname]`, `[kes:nickname:N]` (1-30), and named variants `:short` (6), `:medium` (10), `:long` (20). Falls back to `UnitName` when no nickname is set
- **NEW:** GUI with Add/Update form (Use Current Target helper + realm auto-append), saved list grouped by nickname with click-to-edit rows
- **NEW:** Import/Export via `!KEN1!`-prefixed AceSerializer + LibDeflate payload (same pipeline as Dungeon Timers), Replace-mode toggle paired with Import, Clear All danger-zone button
- **NEW:** Live search box with filter-aware count (`N of M`), row flash on save/import, disabled Export/Clear All when empty, popup-based error surfacing for import failures

### CreatePrompt (shared widget)
- Fixed confirmation popups clipping text under the button row when the message wrapped past the default 120px dialog height — affects Dungeon Timers' *Reset All Triggers* and every other prompt with `\n\n`-separated body text. Dialog now measures the rendered FontString height and expands only when needed

---

## v1.12.3

### Bloodlust Tracker
- Fixed sound stutter during heavy raid combat — dropped poll rate 0.10s → 0.50s and added a 1.5s minimum between restarts so the loop no longer spams `PlaySoundFile` when the sound channel saturates

### Dungeon Timers
- Fixed extendTimer overwrite race — a new `BigWigs_Timer` arriving mid-extension now defers instead of silently hiding the visible extension
- Fixed extended bars getting killed by `BigWigs_StopBars` / `BigWigs_OnBossDisable` — new `StopAllBarsRespectExtend` path rides extensions through BigWigs cleanup events
- Added persistent `DEBUG_DT` flag for tracing BigWigs event flow, bar lifecycle, and extendTimer guard branches

### Cursor Circle
- Removed 3 non-functional crosshair/heart textures (Crosshair 1, Crosshair 2, Heart) from the texture dropdown

---

## v1.12.2

### Dungeon Timers
- Fixed bar previews invisible when the bar group was anchored to a non-UIParent frame (e.g. ElvUI unit frames)
- Unified anchor pattern across Dungeon Timers / Dungeon Casts / Interrupt Tracker — identical X/Y offsets now produce identical positions across the three modules

### Dungeon Casts / Interrupt Tracker
- Edit mode overlay now wraps just the anchor bar instead of the full stack — fixes misalignment with CENTER-based anchor points

---

## v1.12.1

### Dungeon Timers
- **NEW:** 14 color-coded display presets (AOE, DODGE, SOAK, FRONTAL, KICK, TANK HIT, etc.) — one-click label + color for common warning types
- **NEW:** Full anchor system for bar/text groups — anchor frame type, parent frame selection, and strata
- Fixed `BigWigs_StopBar` killing timers that still have extended time remaining
- Fixed pull/break countdown triggering unrelated timers with empty spell ID filters
- Fixed position changes not applying until /reload
- Fixed bar/text previews ignoring anchor frame setting

### Dungeon Casts
- Fixed cast bar group shifting position when bar count changed — switched to 1x1 anchor pattern matching Interrupt Tracker

---

## v1.12.0

### Dungeon Casts (new module)
- **NEW:** Enemy cast bars for M+ nameplates with icon, target text, raid icons, bar stacking, and interruptible/shielded status colors. Only active in 5-player dungeons

### Dungeon Timers (new module)
- **NEW:** BigWigs-integrated per-dungeon timer system with trigger editor, bar/text display groups, role-based load conditions, and spell browser
- **NEW:** Per-trigger display overrides
- **NEW:** Import/Export system — share timer configurations per-dungeon or all-at-once via AceSerializer + LibDeflate. Reset all triggers with confirmation prompt

### GUI
- **NEW:** Section-based previews — opening the GUI only previews modules in the active sidebar section (edit mode still shows all)
- **NEW:** Panel builder system (`RegisterPanel`, `RegisterWidePanel`) for full content-area takeover on dungeon trigger editor pages
- **NEW:** Sidebar `disabledCheck` and `alwaysEnabled` support for the Dungeon Timers section

### Combat Cross / Combat Texts / Core
- Fixed C stack overflow caused by `UIFrameFadeIn` / `UIFrameFadeOut` on frames with soft outline children (also fixed in `CreateMessagePopup`)

### Boss Debuffs
- Fixed `blacklistBox` nil upvalue error when the edit box loses focus
- Moved from Encounter Tools to Combat. Encounter Tools section removed

### Interrupt Tracker
- Moved from Combat to Dungeons section
- GUI restructured into Frame Settings and Bar Appearance cards matching the Dungeon Casts pattern

### Theme
- Fixed missing `OnThemeChanged` handler in Potion Ready, Enemy Counter, Raid Notifications, No Movement Alert, and Stasis Tracker — theme color changes now update these modules immediately

### Target Castbar
- Added to the preview system (was missing)

---

## v1.11.0

### Core
- **NEW:** Centralized secret value API (`Secret.lua`) — `KE:IsSecretValue()`, `KE:IsSafeValue()`, `KE:IsFullyRestricted()`, `KE:DeferUntilUnrestricted()` and restriction state tracking for combat, M+, encounters, and PvP
- **NEW:** Protected function violation listener for debugging
- **NEW:** `KE:AddBorders()` — enhanced border helper with optional `borderParent` for frame level control and a `SetBorderColor` method

### Combat Texts
- **NEW:** "No Target" warning — persistent text displayed when in combat with no target selected. Generation-based debounce prevents flicker during rapid target changes. Disabled by default, configurable text and color
- GUI: "No Target Warning" card with enable toggle, color picker, and text input

### Time Spiral
- **NEW:** Countdown timer text overlay on the icon showing remaining proc duration with dynamic decimal formatting via `C_DurationUtil`. Configurable font, size, outline, and color
- **NEW:** Infernal Strike (1234796) added for Demon Hunter
- Improved talent detection with multi-method `IsTalentKnown` (IsPlayerSpell + IsSpellKnown + C_Spell)
- GUI: Merged "Text Settings" and "Font Settings" into a single "Label Text" card. Added "Timer Settings" card for countdown display

### Automation
- **NEW:** Hide all tutorial/helptip popups at load time
- **NEW:** Hold Shift when opening a vendor to bypass auto-sell junk
- Replaced manual bag iteration for junk selling with `C_MerchantFrame.SellAllJunkItems()`

### Hunter's Mark
- Replaced `InCombatLockdown()` gate with the new restriction state system — nameplate tracking now works during combat instead of being completely blocked
- Added `issecretvalue` guards on aura scanning (`spellId`, `sourceUnit`) to prevent false "missing mark" warnings from secret values
- Added `ENCOUNTER_START` / `ENCOUNTER_END` events for better state management

### Auras Skinning
- Fixed buff icons not being re-styled when buffs are gained or lost — added missing `BuffFrame:UpdateAuraButtons` hook
- Added `SpaceRows` call for live row layout
- Added `ExternalDefensivesFrame:UpdateAuraButtons` hook for live restyling of defensive auras

---

## v1.10.5

### Enemy Counter
- Fixed inaccurate mob count — added `UnitIsDead` filter so dead mobs with lingering nameplates are no longer counted, plus `UnitCanAttack` filter so friendly NPC nameplates are excluded. Added persistent `DEBUG_EC` flag for future diagnostics

---

## v1.10.4

### WarpDeplete+
- Fixed duplicate death entries — `UNIT_DIED` fires for every mob death and time-window dedup failed as the M+ timer advanced past the death penalty jump. Replaced with state-based per-player dedup that clears when a player is alive again (battle-rez safe). Added `UNIT_DIED` debounce so the roster scan runs at most once per 150ms
- Fixed death names not class-colored — WarpDeplete's CLEU path ships a localized class string (e.g. `"Druid"`) instead of the classFilename token (`"DRUID"`) that `GetClassColor` expects. Now always prefers a roster-based `UnitClass(unit)` lookup
- Fixed death header count not matching the tooltip list — hooked `SetDeathCount` to use `max(gameCount, listCount)`. Per-death time penalty is learned dynamically from `C_ChallengeMode.GetDeathCount()` (5s below +12, 15s with Xal'atath's Guile)
- Fixed pull-forces overlay disappearing when re-entering combat within 0.5s of a drop — the delayed `PushToWarpDeplete(0)` callback from `PLAYER_REGEN_ENABLED` now checks `UnitAffectingCombat("player")`

### Ebon Might Tracker
- GUI reorganized — Mode dropdown and toggles (Only Show on Crit, Combat Only) moved from the Enable card into a separate Display Settings card. Color pickers (Base, Crit, Dupe) consolidated to a single horizontal row

---

## v1.10.3

### Ebon Might Tracker (new module)
- **NEW:** Augmentation Evoker tracker — shows active Ebon Might duration with crit and duped cast detection via mainStat ratio math against ally aura values
- **NEW:** Two display modes — Icon + Countdown (spell icon with centered timer) and Border + State Label (iconless border with "CRIT"/"DUPE" label above)
- **NEW:** Border dynamically recolors and thickens on crit/dupe (transparent → magenta/orange, 1px → 2px)
- **NEW:** Only Show on Crit toggle
- Class-gated to Evoker. Ported from EMTracker by Baumritter

### Bloodlust Tracker
- Simplified to two modes (Pedro animated overlay + Static Icon with countdown). Removed chipi/ninemm/erm presets, haste-approximation detection, sound-only mode, and DisplayMode concept. Removed ~1.8MB of unused media
- **NEW:** Combat Only toggle
- Fixed multi-trigger sound bug — edge-triggered detection now uses `updateInfo.addedAuras` instead of re-scanning
- Unified anchor behavior across both modes via `SetScale(1)` + computed size

### Prescience Tracker
- **Renamed:** "Aug Buffs Tracker" → "Prescience Tracker". Module only tracks Prescience and Shifting Sands — the narrower name fits and frees the "aug" namespace for the new Ebon Might Tracker. DB key `AugBuffsTracker` renamed to `PrescienceTracker` (existing profiles reset this module's settings to defaults)
- Fixed role icon drawing behind the main buff icon — reparented to iconFrame with correct sublevel, matching the `timer` FontString pattern
- Fixed Class Color Names toggle leaking widget state across GUI page rebuilds

### Evoker Suite
- Tab order and labels updated — Disintegrate / Stasis / Ebon Might / Prescience. The Ebon Might tab now hosts the Extension Helper (sound alert) and the new Tracker (visual display) in a shared card stack
- Fixed tab bar corrupting when rapidly switching away from the Disintegrate tab — tab clicks are now debounced via `C_Timer.After(0, ...)`, collapsing multiple rapid clicks into a single `RefreshContent`

### GUI
- Fixed latent zero-width-parent race for tabbed pages — `scrollChild` is now sized synchronously at creation instead of via a deferred timer

---

## v1.10.2

### WarpDeplete+
- **Renamed:** from "WarpDeplete Forces" to reflect expanded scope (forces + death fixes + tooltip)
- Fixed pull-forces overlay double-counting with WarpDeplete's own killed tracker — now only counts alive mobs
- Fixed death tooltip showing "No Recorded Player Deaths" in M+ (GUID is secret; bypassed with a roster scan)
- Fixed death names not class-colored (was using localized className instead of classFilename token)

---

## v1.10.1

### Enemy Counter (new module)
- **NEW:** Displays the number of enemies currently in combat via nameplate scanning. Editable prefix with toggle, combat-only visibility option, standard font/color

### WarpDeplete Forces
- Unhidden sidebar entry for the Dungeons section

---

## v1.10.0

### Battle.net Toast (new module)
- **NEW:** Dark theme skinning for BNet notification toasts with custom anchor positioning and EditMode support. Ported from NorskenUI

### WarpDeplete Forces (new module)
- **NEW:** Restores live pull forces tracking to WarpDeplete using fingerprint-based mob identification to bypass 12.0 Secret Values
- **NEW:** Tooltip shows per-mob forces in M+. All 8 Midnight Season 1 dungeons covered

### ElvUI Tags
- **NEW:** `[kes:group]` — shows "Group: X" only while in a raid group

### GUI
- **NEW:** Dungeons sidebar section (hidden pending further testing)

### Internal
- `.luacheckrc`: added missing WoW API globals (Mixin, UnitClassification, UnitSex, UnitPowerType, C_ScenarioInfo, GetRaidRosterInfo, WarpDeplete)

---

## v1.9.2

### Internal
- Code standards pass — Unicode box headers, 81-dash section dividers, and `-- Local references` cleanup across all 138+ Lua files. Removed 8 stub files (CDMGlow, CDMOverlay, Chat, Minimap). Suppressed unused `self` warnings in `.luacheckrc`

---

## v1.9.1

### Battle Res / Combat Timer / No Movement Alert
- Fixed crash when opening GUI post-encounter — all three modules now guard against secret values from `GetStringWidth()` after combat

---

## v1.9.0

### Boss Debuffs (new module)
- **NEW:** Shows icons for external debuffs applied to you during boss encounters. 1-5 icons with growth direction, cooldown spiral, duration text, mouseover tooltip, encounter blacklist with hover reference
- **NEW:** Visibility modes — Boss Encounters, Instance Combat, Always in Combat

### Racials Anchor (new module)
- **NEW:** Repositions the Ayije CDM racials bar with custom X/Y offsets and automatic pet bar offset for pet classes. Supports ElvUI and UUF pet frames

### Core
- **NEW:** Icon Standard — centralized `KE:ApplyIconZoom()` and `KE:AddIconBorders()` in `Core/Widgets.lua`. All icon modules now use consistent 0.3 zoom + 1px pixel-perfect borders

### GUI Sidebar
- **NEW:** Encounter Tools section for encounter-specific modules
- Alphabetical ordering for Combat, Utilities, and QoL sections
- Renames: Combat Res → Battle Res, Combat Cross → Player Crosshair, Dragon Riding UI → Skyriding UI

### Custom Buffs
- **Removed:** Section and all 4 modules (Buff Icons, Buff Bars, Externals/Defensives, Movement Buffs) — deprecated

### Misc
- Fixed 1px or oversized edit mode borders on Battle Res / Combat Timer / No Movement Alert — frames now size dynamically from content instead of backdrop/hardcoded values
- Fixed `/wa` slash command not respecting addon forks or disabled WeakAuras — now checks `WeakAuras` global instead of `IsAddOnLoaded`
- Fixed "Font not set" error during profile switch in Raid Notifications — settings now applied before showing preview alerts
- Fixed AugBuffsTracker creating frames on non-Evoker characters — added class check in OnEnable
- Migrated BloodlustTracker / StasisTracker / AugBuffsTracker / RaidNotifications / TimeSpiral / Recuperate / HuntersMark to the centralized icon helpers

---

## v1.8.6

### Preview / Edit Mode
- Class-restricted modules (Evoker Suite, Hunter's Mark) no longer show previews on non-matching classes. Any module can declare `classRestriction` to opt in

---

## v1.8.5

### Combat Potion Ready (new module)
- **NEW:** Displays "Potion Ready" text when a combat potion is in bags and off cooldown. 22 potions tracked (regular + fleeting)
- **NEW:** Visibility toggles — Instance Only, Combat Only, Hide for Healer Specs
- Standard color mode (class/custom/theme), SOFTOUTLINE default, anchored to `UtilityCooldownViewer`

---

## v1.8.4

### Battle Res
- Fixed module not respecting disabled state on login/profile switch — added missing `db.Enabled` gate in OnEnable

### Missing Enchants/Gems
- Fixed double text overlays when BetterCharacterPanel is loaded — silently skips if BCP is present
- Fixed event frame not unregistering events on module disable

### Packaging
- Fixed `<Include>` tags on `.lua` files in `Libs/Init.xml` (should have been `<Script>`). Standardized all paths to forward slashes
- Expanded `.pkgmeta` ignore list. Split Ace3 bulk external into individual library externals. Added LibCustomGlow, LibDBIcon, LibDataBroker, LibRangeCheck as externals. Added `.gitattributes` for line ending normalization

---

## v1.8.3

### Missing Enchants/Gems (new module)
- **NEW:** Red warnings on the character panel for missing enchants and empty gem sockets
- **NEW:** Expansion-aware enchant slots, tooltip-based gem socket detection ("Prismatic Socket"), combined text display ("No Enchant / No Gem")
- **NEW:** Configurable font, size, and outline. Hide Character Panel Background toggle

### World Map Scaler (new module)
- **NEW:** Adjustable minimized world map scale (1.0–2.0x)
- **NEW:** Coordinate waypoint search bar with live preview. Accepts multiple input formats (`/way`, comma-separated, spaces). Super-tracks waypoints automatically

### ElvUI Tags
- **NEW:** `[kes:name-classcolor]` — unit name with class/reaction color
- **NEW:** `[kes:target:separator]` — white » only when target exists
- **NEW:** `[kes:target:name-classcolor]` — target name with class/reaction color
- Tags only load when ElvUI is present

### Home Page
- **NEW:** General Settings card with "Show Minimap Button" and "Show Command in Chat on Login" toggles

---

## v1.8.2

### Combat Texts
- **NEW:** Interrupt Text — displays interrupted spell name and icon on a successful kick. Spec-aware detection using zzal reference pattern (`UNIT_SPELLCAST_SUCCEEDED` flag + `UNIT_SPELLCAST_INTERRUPTED`). Works in dungeons via `C_Spell.GetSpellInfo` AllowedWhenTainted. Configurable text, color, fade
- **Renamed:** "Interrupt Announce" → "Interrupt Text"
- Combat Enter/Exit combined into a single "Combat Messages" card with one enable toggle
- Per-type fade durations — Combat Messages and Interrupt Text each have their own slider (shared Fade Duration removed)
- Updated defaults — enabled, MEDIUM strata, Y offset 125, spacing 0, gray enter/exit colors, blue interrupt
- Tighter message stacking — frame height matches font size instead of hardcoded 30px

---

## v1.8.1

### Focus Castbar
- **NEW:** Mute sound when kick on CD — suppresses the cast alert sound while your interrupt is on cooldown. Uses spec-aware, event-based cooldown tracking (no secret value APIs)
- Fixed interrupt spell ID not caching at login — added `SPELLS_CHANGED` event to `CacheInterruptId`. Previously the kick tick and mute feature required a zone change before working
- Rewrote interrupt data from class-keyed to spec-keyed table (matching KickTracker). Fixes stale cooldown values (DK 15→12s, Mage 24→20s, Priest 45→30s) and per-spec CD differences (Evoker 20/18s, Shaman 12/30s, Warlock 24/30s)
- Updated defaults — enabled, 350x30, blue casting/channeling, red not-interruptible, green hold/tick, hide non-interruptible casts, sound on (Interrupt, Master)

### Interrupt Tracker
- Fixed ~1-in-5-8 CC false-positive in channel kick detection — replaced UNIT_AURA-based CC detection with `interruptedBy` GUID validation (ExWind v26.4.2 port). Removed the UNIT_AURA event handler entirely

### CVars
- **NEW:** "Always Compare Items" toggle — disable to show item comparison tooltips only while holding Shift

### Internal
- Comprehensive WoW API globals whitelist in `.luacheckrc` — zero "undefined variable" warnings across the codebase. Added `References/` exclusion

---

## v1.8.0

### Great Vault Spec Alert (new module)
- **NEW:** Shows your loot specialization with class color and spec icon on opening the Great Vault. Configurable sound, chat message, alert duration, font, and position

### Vantus Rune Withdrawer (new module)
- **NEW:** Guild Bank button to withdraw one Vantus Rune by priority (Radiant Gold > Radiant Silver)
- **NEW:** Pre-flight checks (existing rune, bag space, withdrawal limits), confirmation popup with countdown, cross-realm failure detection

---

## v1.7.3

### GUI
- Fixed mousewheel scrolling jumping top-to-bottom — content area (40px/tick) and sidebar (30px/tick) now scroll incrementally. Added `EnableMouseWheel` + `OnMouseWheel` handlers matching the dropdown widget pattern

### Aug Buffs Tracker
- Fixed edit mode overlay misaligned with entry bounds — now uses KickTracker's edge-anchor resize pattern

---

## v1.7.2

### Aug Buffs Tracker
- **NEW:** Name truncation — "Max Characters" slider (0 = full name) to shorten long player names
- Fixed all entries disappearing simultaneously in combat — `GROUP_ROSTER_UPDATE` was doing a destructive wipe + API re-scan that fails in combat. Now additive re-scan out of combat, skips in combat
- Replaced Stack Direction + Growth Direction with a single Growth Direction dropdown (Down/Up/Right/Left)

### Stance Texts
- Fixed Evoker attunements not detecting in combat — detection moved from buff scan to shapeshift form (like Warrior)

---

## v1.7.1

### Aug Buffs Tracker
- **NEW:** Growth Direction setting — entries grow Down, Up, Left, or Right from the anchor. Chain-anchor layout prevents frame resize from shifting entries
- Fixed entries randomly disappearing in combat — `removedAuraInstanceIDs` now checks both instance ID and unit token (aura instance IDs are per-unit; cross-unit ID collisions caused false removals in raids)
- Additive re-scan in the combat ticker (no wipe). Secret value guards restored on `expirationTime` and `aura.points` in `AddTrackedBuff`

### Raid Notifications
- **Removed:** Loot Boss save detection (unreliable encounter ID mapping)

---

## v1.7.0

### GUI
- **NEW:** Sidebar Search — real-time search bar at the top of the sidebar. Filters modules by name as you type, hides non-matching sections, force-expands matching sections, shows "No results found" for empty queries. Clear button (X) and ESC to reset. Clears automatically on GUI close. Theme-aware

---

## v1.6.9

### Aug Buffs Tracker (new module)
- **NEW:** Tracks Prescience and Shifting Sands on party/raid members for Augmentation Evoker. Buff icon, countdown timer, role badge, and player name per tracked target
- **NEW:** Horizontal/vertical stacking, icon size, separate name/timer fonts, class-colored names, crit color for Prescience
- Added as the 4th tab in Evoker Suite
- Combat-safe aura handling — processes `addedAuras` event payload directly (non-secret), guards `isFullUpdate` and `updatedAuraInstanceIDs` against tainted API returns in combat, `issecretvalue` guards on `expirationTime` and `points`

### Raid Notifications
- **NEW:** Loot Boss save detection — uses `C_EncounterJournal.IsEncounterComplete` to suppress "LOOT BOSS" when already saved to the boss (pre-cached on zone-in, compared on encounter end)

---

## v1.6.8

### Evoker Suite
- **NEW:** Stasis Tracker — Preservation Evoker module displaying stored spell icons and a 30-second countdown bar during Stasis. Configurable icon size, spacing, growth direction (horizontal/vertical), bar side, bar color mode, and font
- **NEW:** Ebon Might Helper — Augmentation module that plays a warning sound when casting an extender spell (Eruption, Fire Breath, Upheaval) that won't refresh Ebon Might. Smart polling handles mid-cast haste changes. Configurable sound and channel
- Combined Disintegrate Ticks, Stasis Tracker, and Ebon Might Helper into a single tabbed GUI page under Utilities

---

## v1.6.7

### Interrupt Tracker
- **NEW:** Healer position override — auto-swaps to a separate position/anchor when playing a healer spec. Core-level `KE:ApplyActivePosition` system available for future module opt-in. Enabled by default

### Focus Castbar / Target Castbar
- Fixed `notInterruptible` secret boolean handling — separated casting/channeling checks to avoid `or` on secret values. Added nil guard for `HideNotInterruptible` alpha toggle

### Internal
- Removed `GetSpellCooldown` debug print spam from No Movement Alert
- Removed secret-value debug prints from Bloodlust Tracker, Battle Res, Cursor Circle, Disintegrate Ticks, and Dispel Cursor

---

## v1.6.6

### Raid Notifications
- Fixed Reset Boss and Loot Boss alerts triggering in dungeons and M+ — now restricted to Normal/Heroic/Mythic raids only (difficulty 14-16). Matches NorthernSkyRaidTools reference via `GetInstanceInfo()`

---

## v1.6.5

### GUI Sidebar
- **Tab mergers** to reduce clutter:
  - Focus & Target Castbar — combined with tab switcher (Combat)
  - Class Status Texts — Pet Status, Class Stance, No Movement Alert, and Dispel CD on Cursor combined into one 4-tab page (Utilities)
  - Macro Builders — Focus Marker and Power Infusion combined (Utilities)
- Sidebar item count: Combat 10→8, Utilities 12→8. All module backends unchanged
- Added kick indicator note on both castbar GUI pages explaining bar color override behavior

### Defaults
- Updated defaults — PetStatusText (enabled, medium strata, size 26, accent passive color), NoMovementAlert (enabled, theme color, size 16, "NO %n - %t" format), DispelCursor (enabled, cyan text #3BECFF, offset 3)

### No Movement Alert
- **Removed:** Demon Hunter Shift from spell list (3-charge spells incompatible with 12.0.5 secret value cooldown checks)

---

## v1.6.4

### No Movement Alert (new module)
- **NEW:** Shows remaining cooldown when your movement ability is unavailable. Auto-detects class spell (highest priority known)
- **NEW:** Configurable display format with spell name and timer placeholders
- **NEW:** Max Cooldown threshold (default 30s) — only shows the alert when remaining cooldown drops below the threshold, hiding long-CD spells like Dash until they're nearly ready

### Internal
- KickTracker: merged player/pet kick handlers, simplified pool pop, reusable temp tables for layout, removed redundant `ApplyBarColor` from OnUpdate tick
- FocusCastbar: single cooldown fetch per frame shared between kick indicator and tick position
- RaidNotifications: cached aura API at load time, skip alerts when player is dead. Updated defaults (enabled, accent color, larger font)
- GUI text cleanup: gray `|cff888888` helper labels on settings hints, standard Note block on module descriptions

---

## v1.6.2

### Raid Notifications (replaces Gateway Alert)
- Gateway usability alert joined by **Reset Boss** (lust debuff reminder between pulls) and **Loot Boss** (reminder to loot after a boss kill). Per-alert toggles, shared font/color/position, configurable alert duration. Existing Gateway Alert settings migrate automatically

---

## v1.6.1

### Raid Notifications (replaces Gateway Alert)
- Gateway usability alert joined by **Reset Boss** and **Loot Boss** alerts. Per-alert toggles, shared font/color/position, configurable duration. Existing Gateway Alert settings migrate automatically

---

## v1.6.0

### Interrupt Tracker (new module)
- **NEW:** Tracks party interrupt cooldowns in real-time via status bars. Event-correlation detection (no protected API calls)
- **NEW:** Class/dark color modes with drain/fill animations, channel kick detection, icon desaturation on CD, Warlock pet kick support, role-based sorting

### Bloodlust Tracker (new module)
- **NEW:** Animated sprite overlay + sound on Bloodlust/Heroism/Time Warp. Presets — Pedro, Chipi Chipi, 9MM Bang (sound only), Sarah Gamer Word (sound only)
- **NEW:** Basic icon + countdown mode, sated debuff detection with optional haste-approximation fallback, Instance Only toggle

### Focus Castbar
- **NEW:** Sound alert on focus target cast start — LSM sound picker and channel selection

### Gateway Alert
- **NEW:** Gateway shard icons flanking the alert text (toggleable)
- **NEW:** Color mode selector (Class/Custom/Theme)

### Focus Marker
- Ready check announce now silently skips for specs without an interrupt ability

---

## v1.5.1

### Pet Status Texts
- Fixed preview not showing on non-pet classes until a GUI change — frame now applies position and font on first preview open

---

## v1.5.0

### Class Stance Texts (new module)
- **NEW:** Displays customizable text labels for your current Warrior stance, Paladin aura, or Evoker attunement with per-stance colors

### Missing Buffs
- **Removed:** Buff/food/flask/enchant/poison tracking replaced by the BuffReminders addon. Stance text feature extracted into the new Class Stance Texts module

---

## v1.4.3

### Disintegrate Ticks
- Fixed chain-cast tick placement firing too early — first tick now uses modulo of remaining time by previous hasted tick interval, matching upstream v2.0.1

---

## v1.4.2

### Minimap Button
- Tooltip styled with gold-colored click keywords and grey "Essentials" text for better visual hierarchy

---

## v1.4.1

### Minimap Button (new module)
- **NEW:** KitnUI cat icon on the minimap. Left-click opens settings, right-click toggles edit mode, middle-click reloads UI

### Automation
- **NEW:** Auto Confirm Queue toggle — auto-clicks Sign Up on LFG application dialogs (Ctrl bypass)
- **NEW:** Auto Slot Keystone toggle — auto-slots your keystone when opening the M+ UI
- **NEW:** Hide Event Toasts and Hide Zone Text toggles in the Cinematics & Dialogs card

### Combat Logger
- **NEW:** Quiet Mode toggle — suppresses chat messages when logging starts/stops

### GUI
- Hamburger menu dropdown delay bumped from 0.1s → 0.3s for easier mouse navigation

### PI Macro Builder
- Restored `SetPITarget()` global for backward compatibility with existing `/run` macros

### Internal
- `/simplify` pass — `KE:Print()` usage cleanup, removed dead code in FocusMarker and WorldMarkerCycler GUI

---

## v1.4.0

### Auction House Filter (new module)
- **NEW:** Auto-applies Current Expansion filter and focuses the search bar for the Blizzard AH and Craft Orders. Replaces the old single toggle from Automation

### Combat Logger (new module)
- **NEW:** Automatic combat logging for raids, dungeons, M+, PvP, arenas, and scenarios
- **NEW:** Per-content-type toggles, 30-second delayed stop for Warcraft Recorder compatibility, ACL prompt on login

### Power Infusion Macro Builder (new module)
- **NEW:** Auto-creates and manages a PI macro with trinkets, Vampiric Embrace, racial, potion/fleeting potion, and custom `/use` line. Extracted from Slash Commands into its own module with full GUI
- Now auto-creates the macro (no longer requires a pre-existing "PI" macro)

### Disintegrate Ticks
- Synced to upstream v2.0.0 — haste-aware tick placement, channel chaining support, Hover mid-Disintegrate deduplication, spellId filter on channel stop

### GUI
- Title bar font bumped to large (16px)
- Fixed intermittent resize-grip drag conflict with frame movement

### Internal
- Focus Marker / World Marker Cycler — replaced hardcoded `print()` with `KE:Print()`, clear `lastMacroName` on disable, removed dead `MARKER_NAMES` and `dragState.ghostTex` references
- Replaced hardcoded PREFIX constants with `KE:Print()` across new modules. Removed `_G.SetPITarget` global pollution from PIMacroBuilder
- Removed AH filter toggle from Automation page (replaced by new module). Removed PI Macro Builder card from Slash Commands page (replaced by new module)

---

## v1.3.1

### GUI
- **NEW:** Utilities sidebar section between Combat and Quality of Life. Moved Gateway Alert, Pet Status Texts, Time Spiral Tracker, Recuperate Button, Dispel CD on Cursor, Disintegrate Castbar Ticks, World Marker Cycler, and Focus Marker Macro Builder into Utilities
- Skinning section auto-collapses when ElvUI is detected
- Skinning sidebar reordered — General UI Clean Up and Buffs/Debuffs pinned at top, rest alphabetized
- **Renamed:** Range Checker Text → Range Display

### GUI Pages
- Color pickers paired side-by-side where previously stacked (Combat Timer, Range Display)
- Automation page — all toggle pairs now side-by-side (Cinematics, Merchant, Quest, Social, Convenience)
- Combat Cross — Range Warning checkboxes paired side-by-side
- Recuperate — Load conditions and Button Size merged into "General Settings" card. Added full anchor frame controls
- Disintegrate Ticks — Note text split into two clear lines

### Target / Focus Castbar
- **NEW:** Target Names card on Target Castbar with enable toggle, anchor, font size, and offset controls
- **NEW:** Target Names enable toggle on Focus Castbar

---

## v1.3.0

### Focus Marker Macro Builder (new module)
- **NEW:** Auto-creates and manages a focus target + raid marker macro. Marker icon grid selector, mark-only mode, no-raid marking, no-toggle, ready check announce, custom macro name/icon/conditionals

### Target Castbar
- Fixed target names using hardcoded positioning with no GUI controls

### Focus Marker
- Fixed NoToggle setting inversion causing marker spam on repeated clicks

---

## v1.2.0

### Disintegrate Castbar Ticks (new module)
- **NEW:** Evoker-only (Devastation/Preservation). Displays tick marks on your cast bar during Disintegrate channels with a configurable "DON'T CLIP" warning for Mass Disintegrate. Supports UUF, BCDM, Ayije CDM, and Blizzard cast bars

### World Marker Cycler (new module)
- **NEW:** Cycles through world markers at cursor position with customizable keybinds and drag-to-reorder marker priority. Interactive keybind capture with modifier support

### GUI Sidebar
- **Renames:** "Dispel on Cursor" → "Dispel CD on Cursor", "Time Spiral" → "Time Spiral Tracker"
- Time Spiral Tracker — added note clarifying it works for all classes
- Standardized note prefixes with accent-colored dash across all pages
- CVars "enabled" text color changed from accent to green for better visibility

---

## v1.1.5

### ActionBars
- Removed pcall wrappers from cooldown text styling and `SetUserPlaced` calls to reduce taint spreading to Blizzard's ZoneAbility system. Note — modifying cooldown regions inherently taints them (known Blizzard-side issue shared with NorskenUI)

---

## v1.1.4

### Battle Res
- Removed pcall wrappers around `C_Spell.GetSpellCharges` to prevent taint spreading to Blizzard's ZoneAbility system (was causing `CastSpellByID` forbidden errors)

---

## v1.1.3

### Battle Res
- Fixed tracker only showing on Druids during encounters — added `SPELL_UPDATE_CHARGES` and `PLAYER_REGEN_DISABLED` event-driven updates

### Tooltips
- Fixed `IsShown`/`SetAlpha` errors on embedded widget tooltips — removed `EmbeddedItemTooltip` from the skin list

---

## v1.1.1

### Sidebar / GUI Theme
- Hover and selection gradient overlays now update dynamically with theme changes
- Fixed CreateButton callback format for Copy/Reset buttons

---

## v1.1.0

### Addon Theme (new system)
- **NEW:** 8 WoW-themed color presets (KitnUI, Nighthold, Firelands, Icecrown, Dreamsurge, Twilight, Sunwell, Torghast), class color mode, and full custom color mode
- **NEW:** Paint icon button in the header bar for quick theme access
- **NEW:** Hamburger menu in the header bar with Reload UI, Blizzard Edit Mode, Kitn Edit Mode, and Cooldown Manager shortcuts

### GUI
- Merged Profiles and Theme into a unified "Settings" sidebar section
- Moved Cursor Circle from Quality of Life to Combat section
- **Removed:** Personal Defensives and Personal Movement Buffs from the GUI sidebar (now handled by ACDM)

### Misc fixes
- GUI-Theme — added nil guards for `db.Custom` color picker access
- ActionBars — minimum size guard in proc glow hook to prevent errors on unsized buttons
- DispelCursor — 60fps throttle on OnUpdate, proper event cleanup in OnDisable
- AddonTheme — recursion guard on `RefreshTheme` to prevent infinite loops
- CustomOutline — secret value guards now cover all text/alpha comparisons
- Sidebar — accent bar and selection highlight now update with theme changes
- CursorCircle / CombatCross — `OnThemeChanged` handlers for live theme color updates

---

## v1.0.9

### Dispel on Cursor (new module)
- **NEW:** Shows your dispel cooldown timer following your cursor. Auto-detects class dispel spell

### Cursor Circle
- **NEW:** Crosshair and heart texture options. Texture selector now supports a multi-row grid layout

---

## v1.0.8

### CustomOutline
- Fixed errors on focus castbar and other secure frames — added secret/tainted value guards to all text and alpha comparisons

### Tooltips
- Reverted to manual textures (bypassing `Backdrop.lua` entirely) — NorskenUI's BackdropTemplate approach still triggered taint errors

---

## v1.0.7

### Combat Cross
- **NEW:** Range warning — cross changes color when target is out of range (melee/ranged/healer spec support)

### Recuperate
- **NEW:** Configurable Load in Raid/Party toggles
- **NEW:** Health alpha curve (visible when missing health, hidden at full). Dead/ghost handling

### Missing Buffs
- Replaced `AuraUtil.ForEachAura` with direct `C_UnitAuras` API calls for better secret-value handling

### ActionBars
- Proc glow (SpellActivationAlert) size now matches button size dynamically

---

## v1.0.6

### Tooltips
- Replaced BackdropTemplate with manual textures for tooltip skinning to avoid Blizzard `Backdrop.lua` taint errors on protected tooltips (world map POIs, quest tooltips, etc.)

---

## v1.0.5

### Missing Buffs
- **NEW:** Food buff tracking (Well Fed, Sated, etc.)
- **NEW:** Rogue Stealth tracking with icon display
- **NEW:** "Hide When Mounted" option for stance & spec buffs
- **NEW:** Druid Forms "Only Show in Combat" option

---

## v1.0.4

### Tooltips
- Fixed secretvalue error when skinning the tooltip

---

## v1.0.3

### Packaging
- Removed `.png` from the ignore list

---

## v1.0.2

### Misc
- Minor tweaks

---

## v1.0.1

### Core
- Fixed KitnEssentials import error

## v1.0.0 — Initial Release

---
### Combat
- Combat Timer, Combat Cross, Combat Res, Combat Texts, Pet Status Texts, Gateway Alert, Target Castbar, Focus Castbar, Range Checker, TimeSpiral, Cursor Circle, Recuperate

### Custom Buffs
- Buff Icons, Buff Bars, Personal Defensives, Personal Movement Buffs

### Quality of Life
- Automation, Copy Anything, Dragon Riding UI, Missing Buffs, Hunters Mark Missing, Hide ActionBars, CDM Racials Anchor

### Skinning
- Action Bars, Auras, Tooltips, Micro Menu, Blizzard Messages, Blizzard Mouseover, Blizzard Raid Manager, Details Backdrop, UI Cleanup

### GUI
- Full GUI with theme support, edit mode, and profile management
