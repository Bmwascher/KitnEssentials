# Changelog

## v1.14.2
### Combat Castbars (Warlock)
- **Fixed:** Focus castbar sound never muted and the bar stayed in "kick ready" color after casting Axe Toss (Felguard) as Demonology Warlock. `CacheInterruptId` walks the spec candidates in priority order and picks the first known — Spell Lock (19647) was picked first because a Grimoire talent exposes it in the player spellbook, so the old single-ID equality check silently rejected actual Axe Toss casts (89766). Now matches against the full `KE:GetInterruptSpellSet(specID)` so any known pet-variant interrupt counts. Mirrors the set-membership pattern in `Dungeons/KickTracker.lua`.

## v1.14.1
### Ready Check Consumables
- **Fixed:** `ADDON_ACTION_BLOCKED` taint when a ready check started or finished during combat. `self.frame` is a `SecureHandlerStateTemplate`, so `Show`/`Hide`/`ClearAllPoints`/`SetParent`/`SetPoint` are combat-protected — `HideFrame` now defers the frame hide via `PLAYER_REGEN_ENABLED` (with `SetAlpha(0)` so the bar doesn't linger on-screen mid-fight), and `ShowFrame` skips entirely when combat is active.

### Combat Castbars (Warlock)
- **Fixed:** Warlock Target/Focus castbars showing "kick not ready" color and playing the interrupt sound even when a kick was available. Interrupt data was flattened to Spell Lock only; now iterates all pet-dependent candidates (Spell Lock 19647, Axe Toss 89766, Command Demon 119910) and picks the first known in the player or pet spellbook.

### Combat Castbars (internal)
- **Refactor:** Shared Target/Focus castbar logic extracted to `Combat/CastbarHelpers.lua` — ~560 net lines removed across the two modules. Interrupt spell data centralized to `Core/Interrupts.lua` as a single source of truth.
- **Perf:** OnUpdate no longer polls `C_Spell.GetSpellCooldownDuration` per frame — cooldown, tick position, and kick indicator values cached on event, read as pure math per frame.
- **Perf:** Target-name overlay driven by `UNIT_TARGET` + `GROUP_ROSTER_UPDATE` instead of a 0.1s polling loop.

### Miscellaneous
- **Perf:** `CursorCircle` unified two per-frame handlers into one. `CombatTimer` and `RangeChecker` cache config-derived values on `UpdateDB` instead of re-reading every frame.

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
- **UX:** Display Text moved out of the Enable card into a new *Display & Visibility* card; three visibility toggles flattened into a single 3-column row

## v1.13.1
### Custom Nicknames
- **NEW:** Unhalted Unit Frames support via the `[kes:nickname]` tag family
- **NEW:** Class color variants `[kes:nickname:color]` and `[kes:nickname:color:N]` (N = 1-30) for UUF
- **NEW:** `:color:short` / `:color:medium` / `:color:long` named width variants for UUF
- Available Tags card split into shared block + UUF-only subsection
- UUF path placeholder added to the Note section

### ProfileManager
- Fixed nil-call crash on profile create / switch / copy / rename / reset (root cause of "my profile disappeared" reports)

## v1.13.0
### Additions
- **Custom Nicknames**: New QoL module. Map characters (`Name-Realm`) to personal nicknames displayed on ElvUI unit frames via a new tag family: `[kes:nickname]`, `[kes:nickname:N]` (1-30), and named variants `:short` (6), `:medium` (10), `:long` (20). Falls back to `UnitName` when no nickname is set.
- **Custom Nicknames GUI**: Dedicated QoL page with Add/Update form (Use Current Target helper + realm auto-append), saved list grouped by nickname with click-to-edit rows, Import/Export via `!KEN1!`-prefixed AceSerializer+LibDeflate payload (same pipeline as Dungeon Timers), Replace-mode toggle paired with the Import button, and a Clear All danger-zone button.
- **Custom Nicknames polish**: Search box in the Saved list header with live filter and filter-aware count (`N of M`), row flash on save/import, disabled Export/Clear All when empty, and popup-based error surfacing so import failures are visible with chat hidden.

### Fixes
- **CreatePrompt** (shared widget): Fixed confirmation popups clipping their text under the button row when the message wrapped past the default 120px dialog height. Affects Dungeon Timers' *Reset All Triggers* and every other prompt with `\n\n`-separated body text — dialogs now measure the rendered FontString height and expand only when needed.

## v1.12.3
### Fixes
- **Bloodlust Tracker**: Fixed sound stutter during heavy raid combat — reduced poll rate from 0.10s to 0.50s and added a 1.5s minimum between restarts so the loop no longer spams `PlaySoundFile` when the sound channel saturates.
- **Dungeon Timers**: Fixed extendTimer overwrite race — when BigWigs sends the next cast's `BigWigs_Timer` while a previous cast's extension is still visible, the new bar now defers instead of silently hiding the visible extension.
- **Dungeon Timers**: `BigWigs_StopBars` and `BigWigs_OnBossDisable` now honor `extendTimer` via a new `StopAllBarsRespectExtend` path — extended bars ride through BigWigs cleanup events.
- **Cursor Circle**: Removed 3 non-functional crosshair/heart textures (Crosshair 1, Crosshair 2, Heart) from the texture dropdown.

### Internal
- **Dungeon Timers**: Added persistent `DEBUG_DT` flag for tracing BigWigs event flow, bar lifecycle, and extendTimer guard branches.

## v1.12.2
### Fixes
- **Dungeon Timers**: Fixed bar previews invisible when bar group is anchored to non-UIParent frames (e.g. ElvUI unit frames) — parent frame clipping no longer hides bars.
- **Dungeon Timers / Dungeon Casts / Interrupt Tracker**: Unified anchor pattern — all three modules now use the user's configured AnchorFrom for bar positioning, so identical X/Y offsets produce identical positions across modules.
- **Dungeon Casts / Interrupt Tracker**: Edit mode overlay now wraps the anchor bar instead of the full stack, fixing misalignment with CENTER-based anchor points.

## v1.12.1
### Additions
- **Dungeon Timers**: 14 color-coded display presets (AOE, DODGE, SOAK, FRONTAL, KICK, TANK HIT, etc.) — one-click label + color for common warning types.
- **Dungeon Timers**: Full anchor system for bar/text groups — anchor frame type, parent frame selection, and strata control.

### Fixes
- **Dungeon Timers**: Fixed extendTimer/timer offset — `BigWigs_StopBar` no longer kills timers that still have extended time remaining.
- **Dungeon Timers**: Fixed pull/break countdown triggering unrelated timers with empty spell ID filters.
- **Dungeon Timers**: Fixed position changes not applying until reload.
- **Dungeon Timers**: Fixed bar/text previews ignoring anchor frame setting.
- **Dungeon Casts**: Fixed cast bar group shifting position when bar count changes — switched to 1x1 anchor pattern matching Interrupt Tracker.

## v1.12.0
### Additions
- New module: **Dungeon Casts** — enemy cast bars for M+ nameplates with icon, target text, raid icons, bar stacking, and interruptible/shielded status colors. Only active in 5-player dungeons.
- New module: **Dungeon Timers** — BigWigs-integrated per-dungeon timer system with trigger editor, bar/text display groups, role-based load conditions, and spell browser. Configurable per-trigger display overrides.
- **Dungeon Timers**: Import/Export system — share timer configurations per-dungeon or all-at-once with AceSerializer + LibDeflate encoding. Reset all triggers with confirmation prompt.
- **GUI**: Section-based previews — opening the GUI now only shows previews for the active sidebar section instead of all modules simultaneously. Edit mode still shows all.
- **GUI**: Panel builder system (`RegisterPanel`, `RegisterWidePanel`) for full content area takeover on dungeon trigger editor pages.
- **GUI**: Sidebar `disabledCheck` and `alwaysEnabled` support for the Dungeon Timers section.

### Fixes
- **CombatCross**: Fixed C stack overflow caused by `UIFrameFadeIn` on frames with soft outline children.
- **CombatTexts**: Fixed C stack overflow caused by `UIFrameFadeOut` on frames with soft outline children.
- **Core**: Fixed C stack overflow in `CreateMessagePopup` — same UIFrameFade + soft outline interaction.
- **BossDebuffs**: Fixed `blacklistBox` nil upvalue error when edit box loses focus.
- **Theme**: Added missing `OnThemeChanged` handler to PotionReady, EnemyCounter, RaidNotifications, NoMovementAlert, and StasisTracker — theme color changes now update these modules immediately.
- **TargetCastbar**: Added to preview system (was missing).

### Changes
- **Interrupt Tracker**: Moved from Combat to Dungeons section. GUI restructured into Frame Settings and Bar Appearance cards matching Dungeon Casts pattern.
- **Boss Debuffs**: Moved from Encounter Tools to Combat section. Encounter Tools section removed.
- **Dungeon Timers sidebar**: Dungeons sorted alphabetically, separate collapsible section with disable state.

## v1.11.0
### Additions
- **Core**: New centralized secret value API (`Secret.lua`) — `KE:IsSecretValue()`, `KE:IsSafeValue()`, `KE:IsFullyRestricted()`, `KE:DeferUntilUnrestricted()` and restriction state tracking for combat, M+, encounters, and PvP. Protected function violation listener for debugging.
- **Combat Texts**: New "No Target" warning — persistent text displayed when in combat with no target selected. Generation-based debounce prevents flicker during rapid target changes. Disabled by default, configurable text and color.
- **Time Spiral**: Countdown timer text overlay on the icon showing remaining proc duration with dynamic decimal formatting via `C_DurationUtil`. Configurable font, size, outline, and color.
- **Time Spiral**: Added Infernal Strike (spell 1234796) for Demon Hunter.
- **Automation**: Hide all tutorial/helptip popups at load time.
- **Automation**: Hold Shift when opening a vendor to bypass auto-sell junk.

### Fixes
- **Hunter's Mark**: Replaced `InCombatLockdown()` gate with restriction state system — nameplate tracking now works during combat instead of being completely blocked. Added `issecretvalue` guards on aura scanning (`spellId`, `sourceUnit`) to prevent false "missing mark" warnings from secret values. Added `ENCOUNTER_START`/`ENCOUNTER_END` events for better state management.
- **Auras Skinning**: Added missing `BuffFrame:UpdateAuraButtons` hook — buff icons are now re-styled when buffs are gained or lost, not just on initial setup. Added `SpaceRows` call for live row layout. Added `ExternalDefensivesFrame:UpdateAuraButtons` hook for live restyling of defensive auras.
- **Automation**: Replaced manual bag iteration for junk selling with `C_MerchantFrame.SellAllJunkItems()`.
- **Time Spiral**: Improved talent detection with multi-method `IsTalentKnown` (IsPlayerSpell + IsSpellKnown + C_Spell.GetSpellInfo/IsSpellUsable).

### Changes
- **Core**: Added `KE:AddBorders()` — enhanced border helper with optional `borderParent` for frame level control and `SetBorderColor` method.
- **Combat Texts GUI**: Added "No Target Warning" card with enable toggle, color picker, and text input.
- **Time Spiral GUI**: Merged "Text Settings" and "Font Settings" into a single "Label Text" card. Added new "Timer Settings" card for countdown display configuration.

## v1.10.5
### Fixes
- **Enemy Counter**: Fixed inaccurate mob count — added `UnitIsDead` filter so dead mobs with lingering nameplates are no longer counted, and `UnitCanAttack` filter so friendly NPC nameplates are excluded. Added persistent `DEBUG_EC` flag for future diagnostics.

## v1.10.4
### Fixes
- **WarpDeplete+**: Death tracking rewrite — fixed duplicate death entries caused by `UNIT_DIED` firing for every mob death and time-window dedup failing as the M+ timer advanced past the death penalty jump. Replaced with state-based per-player dedup (`recordedDeaths`) that tracks each player's current death and clears when they're alive again (battle-rez safe). Added `UNIT_DIED` debounce so the roster scan runs at most once per 150ms instead of per mob death.
- **WarpDeplete+**: Fixed death names not class-colored — WarpDeplete's CLEU path ships a localized class string (e.g. `"Druid"`) instead of the classFilename token (`"DRUID"`) that `GetClassColor` expects. Hooked `AddDeathDetails` to always prefer a roster-based `UnitClass(unit)` lookup over the input value.
- **WarpDeplete+**: Fixed death header count not matching the tooltip list — hooked `SetDeathCount` to use `max(gameCount, listCount)` so deaths the game undercounts are still reflected in the header. Per-death time penalty is learned dynamically from `C_ChallengeMode.GetDeathCount()` reports (5s below +12, 15s with Xal'atath's Guile).
- **WarpDeplete+**: Fixed pull forces overlay disappearing when re-entering combat within 0.5s of a drop — the delayed `PushToWarpDeplete(0)` callback from `PLAYER_REGEN_ENABLED` was unconditionally clobbering the new pull's state. Added `UnitAffectingCombat("player")` guard.

### Changes
- **Ebon Might Tracker**: GUI reorganized — Mode dropdown and toggles (Only Show on Crit, Combat Only) moved from the Enable card to a separate **Display Settings** card. Color pickers (Base, Crit, Dupe) consolidated to a single horizontal row.

## v1.10.3
### Additions
- New module: **Ebon Might Tracker** (Evoker Suite) — Augmentation Evoker tracker that shows active Ebon Might duration with crit and duped cast detection via mainStat ratio math against ally aura values. Two display modes: **Icon + Countdown** (spell icon with centered countdown timer) and **Border + State Label** (iconless border with "CRIT"/"DUPE" label above). Border dynamically recolors and thickens (transparent → magenta/orange, 1px → 2px) when a crit or duped cast is detected. Only Show on Crit toggle hides the tracker except during crit casts. Standard Position/Font/Color cards, EditMode integration, class-gated to Evoker. Ported from EMTracker by Baumritter.

### Changes
- **Rename**: "Aug Buffs Tracker" → **Prescience Tracker**. The module only tracks Prescience and Shifting Sands, so the narrower name better reflects its scope and frees the "aug" namespace for the new Ebon Might Tracker. DB key `AugBuffsTracker` renamed to `PrescienceTracker` — existing profiles will reset this module's settings to defaults.
- **Evoker Suite**: Tab order and labels updated — "Disintegrate", "Stasis", "Ebon Might", "Prescience" (4 tabs, unchanged count). The Ebon Might tab now houses both the Extension Helper (sound alert) and the new Tracker (visual display) in a shared card stack.

### Fixes
- **Bloodlust Tracker**: Simplified to two modes only (Pedro animated overlay + Static Icon with countdown). Removed chipi/ninemm/erm presets, haste approximation detection, sound-only mode, and DisplayMode concept. Removed ~1.8MB of unused media files. Added Combat Only toggle, fixed edge-triggered detection to use `updateInfo.addedAuras` instead of re-scanning (prevents multi-trigger sound bug), unified anchor behavior across both modes via `SetScale(1)` + computed size.
- **Prescience Tracker**: Role icon no longer drawn behind the main buff icon — reparented to iconFrame with correct sublevel, matching the `timer` FontString pattern.
- **Prescience Tracker**: Class Color Names toggle no longer leaks widget state across GUI page rebuilds — override logic folded into `UpdateAllWidgetStates` so initial build, manual toggle, and tab switches all flow through the same code path.
- **Evoker Suite**: Tab bar no longer corrupts when rapidly switching away from the Disintegrate tab. Tab clicks are now debounced to frame boundaries via `C_Timer.After(0, ...)`, collapsing multiple rapid clicks into a single `RefreshContent` call.
- **GUI**: `scrollChild` is now sized synchronously at creation instead of via a deferred timer, eliminating a latent zero-width-parent race for tabbed pages.

## v1.10.2
### Fixes
- **WarpDeplete+**: Fixed pull forces overlay only counting alive mobs (was double-counting with WarpDeplete's own killed tracking).
- **WarpDeplete+**: Fixed death tooltip showing "No Recorded Player Deaths" in M+ (GUID is secret, bypassed with roster scan).
- **WarpDeplete+**: Fixed death names not class-colored (was using localized className instead of classFilename token).

### Changes
- **WarpDeplete+**: Renamed from "WarpDeplete Forces" to reflect expanded scope (forces + death fixes + tooltip).

## v1.10.1
### Additions
- New module: **Enemy Counter** (Dungeons) — displays the number of enemies currently in combat via nameplate scanning. Editable prefix with toggle, combat-only visibility option, standard font/color settings.
- **WarpDeplete Forces**: Unhidden sidebar entry for Dungeons section.

## v1.10.0
### Additions
- New module: **Battle.net Toast** (Skinning) — dark theme skinning for BNet notification toasts with custom anchor positioning and EditMode support. Ported from NorskenUI.
- New module: **WarpDeplete Forces** (Dungeons) — restores live pull forces tracking to WarpDeplete using fingerprint-based mob identification to bypass 12.0 Secret Values. Tooltip shows per-mob forces in M+. Covers all 8 Midnight Season 1 dungeons.
- New ElvUI tag: **[kes:group]** — shows "Group: X" only while in a raid group.

### Changes
- New sidebar section: **Dungeons** (hidden pending further testing).
- `.luacheckrc`: Added missing WoW API globals (Mixin, UnitClassification, UnitSex, UnitPowerType, C_ScenarioInfo, GetRaidRosterInfo, WarpDeplete).

## v1.9.2
### Changes
- **Code Standards**: Unicode box headers, 81-dash section dividers, and `-- Local references` cleanup across all 138+ Lua files. Removed 8 stub files (CDMGlow, CDMOverlay, Chat, Minimap). Suppressed unused `self` warnings in `.luacheckrc`.

## v1.9.1
### Fixes
- **GetStringWidth taint**: CombatRes, CombatTimer, and NoMovementAlert now guard against secret values from `GetStringWidth()` after combat — prevents crash when opening GUI post-encounter.

## v1.9.0
### Additions
- New module: **Boss Debuffs** (Encounter Tools) — shows icons for external debuffs applied to you during boss encounters. 1-5 icons with growth direction, cooldown spiral, duration text, mouseover tooltip, encounter blacklist with hover reference. Visibility modes: Boss Encounters, Instance Combat, Always in Combat.
- New module: **Racials Anchor** (QoL) — repositions Ayije CDM racials bar with custom X/Y offsets and automatic pet bar offset for pet classes. Supports ElvUI and UUF pet frames.
- New section: **Encounter Tools** — dedicated sidebar section for encounter-specific modules.
- **Icon Standard** — centralized `KE:ApplyIconZoom()` and `KE:AddIconBorders()` in Core/Widgets.lua. All icon modules now use consistent 0.3 zoom + 1px pixel-perfect borders.

### Changes
- **Sidebar**: Alphabetical ordering for Combat, Utilities, and QoL sections.
- **Sidebar renames**: Combat Res → Battle Res, Combat Cross → Player Crosshair, Dragon Riding UI → Skyriding UI.
- **Custom Buffs**: Removed section and all 4 modules (Buff Icons, Buff Bars, Externals/Defensives, Movement Buffs) — deprecated.

### Fixes
- **Edit Mode**: CombatRes, CombatTimer, and NoMovementAlert frames now size dynamically from content instead of backdrop/hardcoded values — fixes 1px or oversized edit mode borders.
- **WeakAuras detection**: `/wa` slash command now checks `WeakAuras` global instead of `IsAddOnLoaded` — works correctly with addon forks and disabled addons.
- **RaidNotifications**: Fixed "Font not set" error during profile switch by applying settings before showing preview alerts.
- **AugBuffsTracker**: Added class check in OnEnable — no longer creates frames or registers events on non-Evoker characters.
- **Icon modules**: Migrated BloodlustTracker, StasisTracker, AugBuffsTracker, RaidNotifications, TimeSpiral, Recuperate, HuntersMark to centralized icon helpers — consistent zoom and borders, text overlays at correct sublevel.

## v1.8.6
### Changes
- **Preview/Edit Mode**: Class-restricted modules (Evoker Suite, Hunter's Mark) no longer show previews on non-matching classes. Extensible system — any module can declare `classRestriction`.

## v1.8.5
### Additions
- New module: **Combat Potion Ready** — displays "Potion Ready" text when a combat potion is in bags and off cooldown. 22 potions tracked (regular + fleeting). Visibility toggles: Instance Only, Combat Only, Hide for Healer Specs. Standard color mode (class/custom/theme), SOFTOUTLINE default, anchored to UtilityCooldownViewer.

## v1.8.4
### Fixes
- **Combat Res**: Added missing `db.Enabled` gate in OnEnable — module now properly respects disabled state on login/profile switch.
- **Missing Enchants/Gems**: Added BetterCharacterPanel conflict guard — silently skips if BCP addon is loaded to prevent double text overlays.
- **Missing Enchants/Gems**: Event frame now properly unregisters events on module disable.
- **Libs/Init.xml**: Fixed `<Include>` tags on `.lua` files to correct `<Script>` tags. Standardized all paths to forward slashes.
- **Packaging**: Expanded `.pkgmeta` ignore list, split Ace3 bulk external into individual library externals, added LibCustomGlow, LibDBIcon, LibDataBroker, LibRangeCheck as externals. Added `.gitattributes` for line ending normalization.

## v1.8.3
### Additions
- New module: **Missing Enchants/Gems** — displays red warnings on the character panel for missing enchants and empty gem sockets. Expansion-aware enchant slots, tooltip-based gem socket detection ("Prismatic Socket"), combined text display ("No Enchant / No Gem"). Configurable font, size, and outline. Hide Character Panel Background toggle.
- New module: **World Map Scaler** — adjustable minimized world map scale (1.0–2.0x) and coordinate waypoint search bar with live preview. Accepts multiple input formats (/way, comma-separated, spaces). Super-tracks waypoints automatically.
- **ElvUI Tags** — 3 custom tags for ElvUI unit frames: `[kes:name-classcolor]` (unit name with class/reaction color), `[kes:target:separator]` (white » only when target exists), `[kes:target:name-classcolor]` (target name with class/reaction color). Only loads when ElvUI is present.
- **Home Page**: General Settings card with "Show Minimap Button" and "Show Command in Chat on Login" toggles.

## v1.8.2
### Additions
- **Combat Texts**: Interrupt Text — displays interrupted spell name and icon on successful kick. Spec-aware detection using zzal reference pattern (UNIT_SPELLCAST_SUCCEEDED flag + UNIT_SPELLCAST_INTERRUPTED). Works in dungeons via C_Spell.GetSpellInfo AllowedWhenTainted. Configurable text, color, and fade duration.

### Changes
- **Combat Texts**: Combined Enter/Exit Combat into single "Combat Messages" card with one enable toggle.
- **Combat Texts**: Per-type fade durations — Combat Messages and Interrupt Text each have their own slider. Removed shared Fade Duration.
- **Combat Texts**: Renamed "Interrupt Announce" to "Interrupt Text".
- **Combat Texts**: Updated defaults — enabled by default, MEDIUM strata, Y offset 125, spacing 0, gray enter/exit colors, blue interrupt color.
- **Combat Texts**: Tighter message stacking — frame height matches font size instead of hardcoded 30px.

## v1.8.1
### Additions
- **Focus Castbar**: Mute sound when kick on CD — suppresses the cast alert sound while your interrupt is on cooldown. Uses spec-aware cooldown tracking (event-based, no secret value APIs). New "Mute When Kick on CD" checkbox in Sound Settings, enabled by default.
- **CVars**: Always Compare Items toggle — disable to only show item comparison tooltips when holding Shift. New "Tooltips" card in CVars page.

### Fixes
- **Interrupt Tracker**: Replaced UNIT_AURA-based CC detection with `interruptedBy` GUID validation (ExWind v26.4.2 port). Eliminates the ~1-in-5-8 CC false positive edge case. Removed UNIT_AURA event handler entirely.
- **Focus Castbar**: Fixed interrupt spell ID not caching at login — added `SPELLS_CHANGED` event to `CacheInterruptId`. Previously the kick indicator tick mark and mute feature required a zone change before working.
- **Focus Castbar**: Rewrote interrupt data from class-keyed spell IDs to spec-keyed table matching KickTracker. Fixes stale cooldown values (DK 15→12s, Mage 24→20s, Priest 45→30s) and per-spec CD differences (Evoker 20/18s, Shaman 12/30s, Warlock 24/30s).

### Changes
- **Focus Castbar**: Updated defaults — enabled by default, 350x30, blue casting/channeling colors, red not-interruptible, green hold/tick indicators, hide non-interruptible casts, sound enabled (Interrupt, Master channel).
- **.luacheckrc**: Comprehensive WoW API globals whitelist — zero "undefined variable" warnings across entire codebase. Added References/ exclusion.

## v1.8.0
### Additions
- New module: **Great Vault Spec Alert** — Shows your loot specialization with class color and spec icon when opening the Great Vault. Configurable sound, chat message, alert duration, font, and position. Located in Quality of Life sidebar.
- New module: **Vantus Rune Withdrawer** — Adds a button to the Guild Bank to withdraw one Vantus Rune by priority (Radiant Gold > Radiant Silver). Pre-flight checks for existing rune, bag space, and withdrawal limits. Confirmation popup with countdown timer. Verified withdrawal with cross-realm failure detection. Located as a card in the Automation page.

## v1.7.3
### Fixes
- **GUI**: Smooth mousewheel scrolling — content area (40px/tick) and sidebar (30px/tick) now scroll incrementally instead of jumping top-to-bottom. Added `EnableMouseWheel` and `OnMouseWheel` handlers matching the dropdown widget pattern.
- **Aug Buffs Tracker**: Edit mode overlay now correctly matches entry bounds using KickTracker's edge-anchor resize pattern.

## v1.7.2
### Additions
- **Aug Buffs Tracker**: Name truncation — "Max Characters" slider (0 = full name) to shorten long player names.

### Changes
- **Aug Buffs Tracker**: Replaced Stack Direction + Growth Direction with a single Growth Direction dropdown (Down/Up/Right/Left). Stack Direction was redundant.

### Fixes
- **Aug Buffs Tracker**: Fixed all entries disappearing simultaneously in combat — `GROUP_ROSTER_UPDATE` was calling `ScanAllUnits` (destructive wipe + API re-scan that fails in combat). Now uses additive re-scan out of combat, skips in combat.
- **Stance Texts**: Evoker attunements now detected via shapeshift form (like Warrior) instead of buff scan, avoiding combat aura restrictions.

## v1.7.1
### Additions
- **Aug Buffs Tracker**: Growth Direction setting — entries can grow Down, Up, Left, or Right from the anchor point. Chain-anchor layout prevents frame resize from shifting entries.

### Fixes
- **Aug Buffs Tracker**: Fixed entries randomly disappearing in combat — `removedAuraInstanceIDs` now checks both instance ID and unit token before removing (aura instance IDs are per-unit, not global; cross-unit ID collisions caused false removals in raids). Additive re-scan in ticker (no wipe) for combat recovery. Secret value guards restored on `expirationTime` and `aura.points` in `AddTrackedBuff`.
- **Raid Notifications**: Removed Loot Boss save detection (unreliable encounter ID mapping).

## v1.7.0
### Additions
- **GUI Sidebar Search** — Real-time search bar at the top of the sidebar. Filters modules by name as you type, hides non-matching sections, force-expands matching sections, shows "No results found" for empty queries. Clear button (X) and ESC to reset. Search clears automatically on GUI close. Theme-aware colors.

## v1.6.9
### Additions
- New module: **Aug Buffs Tracker** — Tracks Prescience and Shifting Sands on party/raid members for Augmentation Evoker. Shows buff icon, countdown timer, role badge, and player name per tracked target. Configurable horizontal/vertical stacking, icon size, separate name/timer font settings, class-colored names, crit color for Prescience. Added as 4th tab in Evoker Suite.
- **Raid Notifications**: Loot Boss save detection — uses `C_EncounterJournal.IsEncounterComplete` to suppress "LOOT BOSS" alert when player is already saved to the boss (pre-cached on zone-in, compared on encounter end).

### Fixes
- **Aug Buffs Tracker**: Combat-safe aura handling — processes `addedAuras` event payload directly (non-secret), guards `isFullUpdate` and `updatedAuraInstanceIDs` paths against tainted API returns in combat, `issecretvalue` guards on `expirationTime` and `points` table.

## v1.6.8
### Additions
- **Stasis Tracker**: Preservation Evoker module — displays stored spell icons and a 30-second countdown bar during Stasis. Configurable icon size, spacing, growth direction (horizontal/vertical), bar side, bar color mode, and font settings.
- **Ebon Might Helper**: Augmentation Evoker module — plays a warning sound when casting an extender spell (Eruption, Fire Breath, Upheaval) that won't refresh Ebon Might. Smart polling handles mid-cast haste changes. Configurable sound and channel.
- **Evoker Suite**: Combined Disintegrate Ticks, Stasis Tracker, and Ebon Might Helper into a single tabbed GUI page under Utilities.

## v1.6.7
### Additions
- **Interrupt Tracker**: Healer position override — auto-swaps to a separate position/anchor when playing a healer spec. Core-level system (`KE:ApplyActivePosition`) available for future module opt-in. Enabled by default.

### Fixes
- **FocusCastbar / TargetCastbar**: Fixed `notInterruptible` secret boolean handling — separated casting/channeling checks to avoid `or` operator on secret values, added nil guard for `HideNotInterruptible` alpha toggle.
- **NoMovementAlert**: Removed `GetSpellCooldown` secret value debug print spam.
- Removed secret value debug prints from BloodlustTracker, CombatRes, CursorCircle, DisintegrateTicks, and DispelCursor.

## v1.6.6
### Fixes
- **Raid Notifications**: Reset Boss and Loot Boss alerts now restricted to Normal/Heroic/Mythic raids only (difficulty 14-16). Previously triggered in dungeons and M+. Uses `GetInstanceInfo()` difficulty check matching NorthernSkyRaidTools reference.

## v1.6.5
### Changes
- **GUI sidebar tab mergers** — Reduced sidebar clutter with tabbed GUI pages:
  - **Focus & Target Castbar** — Target and Focus castbar settings combined with tab switcher (Combat section).
  - **Class Status Texts** — Pet Status, Class Stance, No Movement Alert, and Dispel CD on Cursor combined into one 4-tab page (Utilities section).
  - **Macro Builders** — Focus Marker and Power Infusion macro builders combined with tab switcher (Utilities section).
- Sidebar item count: Combat 10→8, Utilities 12→8. All module backends unchanged.
- Added kick indicator note on both castbar GUI pages explaining bar color override behavior.
- Updated defaults: PetStatusText (enabled, medium strata, size 26, accent passive color), NoMovementAlert (enabled, theme color, size 16, "NO %n - %t" format), DispelCursor (enabled, cyan text #3BECFF, offset 3).
- Removed DH Shift from No Movement Alert spell list (3-charge spells incompatible with 12.0.5 secret value cooldown checks).

## v1.6.4
### Additions
- New module: **No Movement Alert** — Shows remaining cooldown when your movement ability is unavailable. Auto-detects class spell (highest priority known spell). Configurable display format with spell name and timer placeholders. Located in Utilities sidebar.
- **No Movement Alert**: Max Cooldown threshold (default 30s) — only shows alert when remaining cooldown drops below threshold, hiding long-CD spells like Dash until they're nearly ready.

### Changes
- **KickTracker**: Merged player/pet kick handlers, pool pop simplification, reusable temp tables for layout, removed redundant ApplyBarColor from OnUpdate tick.
- **FocusCastbar**: Single cooldown fetch per frame shared between kick indicator and tick position.
- **RaidNotifications**: Cached aura API at load time, skip alerts when player is dead, updated defaults (enabled by default, accent color, larger font).
- GUI text cleanup: gray `|cff888888` helper labels on settings hints, standard Note block on module descriptions.

## v1.6.2
### Changes
- **Gateway Alert** replaced by new **Raid Notifications** module. Gateway usability alert is now joined by **Reset Boss** (lust debuff reminder between pulls) and **Loot Boss** (reminder to loot after a boss kill). Per-alert toggles, shared font/color/position settings, configurable alert duration. Existing Gateway Alert settings are migrated automatically. Located in Utilities sidebar.

## v1.6.1
### Changes
- **Gateway Alert** replaced by new **Raid Notifications** module. Gateway usability alert is now joined by **Reset Boss** (lust debuff reminder between pulls) and **Loot Boss** (reminder to loot after a boss kill). Per-alert toggles, shared font/color/position settings, configurable alert duration. Existing Gateway Alert settings are migrated automatically. Located in Utilities sidebar.

## v1.6.0
### Additions
- New module: **Interrupt Tracker** — Tracks party interrupt cooldowns in real-time using status bars. Event-correlation detection (no protected API calls), class/dark color modes with drain/fill animations, channel kick detection, icon desaturation on CD, warlock pet kick support, role-based sorting. Located in Combat sidebar.
- New module: **Bloodlust Tracker** — Animated sprite overlay + sound on Bloodlust/Heroism/Time Warp. Presets: Pedro, Chipi Chipi, 9MM Bang (sound only), Sarah Gamer Word (sound only). Basic icon + countdown mode, sated debuff detection with optional haste approximation fallback, instance-only toggle. Located in Utilities sidebar.
- **Focus Castbar**: Added sound alert on focus target cast start with LSM sound picker and channel selection.
- **Gateway Alert**: Added gateway shard icons flanking the alert text (toggleable). Added color mode selector (Class/Custom/Theme).

### Changes
- **Focus Marker**: Ready check announce now silently skips for specs without an interrupt ability.

## v1.5.1
### Fixes
- Pet Status Texts: fixed preview not showing on non-pet classes until a GUI change was made. Frame now applies position and font on first preview open.

## v1.5.0
### Additions
- New module: **Class Stance Texts** — Displays customizable text labels for your current Warrior stance, Paladin aura, or Evoker attunement with per-stance colors. Located in Utilities sidebar.

### Removals
- **Missing Buffs** module removed. Buff/food/flask/enchant/poison tracking replaced by the BuffReminders addon. Stance text feature extracted into the new Class Stance Texts module.

## v1.4.3
### Fixes
- DisintegrateTicks: fix chain-cast tick placement firing too early. First tick now uses modulo of remaining time by previous hasted tick interval, matching upstream v2.0.1.

## v1.4.2
### Changes
- Minimap button tooltip: gold-colored click keywords, grey "Essentials" text for better visual hierarchy.

## v1.4.1
### Additions
- **Minimap Button** — KitnUI cat icon on minimap. Left-click opens settings, right-click toggles edit mode, middle-click reloads UI.
- Automation: **Auto Confirm Queue** toggle — auto-clicks Sign Up on LFG application dialogs (hold Ctrl to bypass).
- Automation: **Auto Slot Keystone** toggle — auto-slots your keystone when opening the M+ UI.
- Automation: **Hide Event Toasts** and **Hide Zone Text** toggles in Cinematics & Dialogs card.
- Combat Logger: **Quiet Mode** toggle — suppresses chat messages when logging starts/stops.

### Changes
- Hamburger menu dropdown delay increased from 0.1s to 0.3s for easier mouse navigation.
- PI Macro Builder: restored `SetPITarget()` global function for backward compatibility with existing `/run` macros.

### Fixes
- Code cleanup from `/simplify` review: KE:Print() usage, removed dead code in FocusMarker and WorldMarkerCycler GUI.

## v1.4.0
### Additions
- New module: **Auction House Filter** — Auto-applies Current Expansion filter and focuses search bar for Blizzard AH and Craft Orders. Replaces the old single toggle from Automation.
- New module: **Combat Logger** — Automatic combat logging for raids, dungeons, M+, PvP, arenas, and scenarios. Per-content-type toggles, 30-second delayed stop for Warcraft Recorder compatibility, ACL prompt on login.
- New module: **Power Infusion Macro Builder** — Auto-creates and manages a PI macro with trinkets, Vampiric Embrace, racial, potion/fleeting potion, and custom /use line. Extracted from Slash Commands into its own module with full GUI.

### Changes
- **DisintegrateTicks** updated to match upstream v2.0.0: haste-aware tick placement, channel chaining support, Hover mid-Disintegrate deduplication, spellId filter on channel stop.
- GUI title bar font increased to large (16px).
- GUI resize grip fix: resolved intermittent drag conflict with frame movement.
- PI Macro Builder: now auto-creates the macro (no longer requires pre-existing "PI" macro).
- Removed AH filter toggle from Automation page (replaced by new module).
- Removed PI Macro Builder card from Slash Commands page (replaced by new module).

### Fixes
- FocusMarker: replaced hardcoded print() with KE:Print(), clear lastMacroName on disable, removed dead MARKER_NAMES table.
- WorldMarkerCycler: fixed initial icon texture using wrong mapping, removed dead dragState.ghostTex.
- Code cleanup: replaced hardcoded PREFIX constants with KE:Print() across new modules, removed redundant hooksInstalled guard in AuctionHouseFilter, removed _G.SetPITarget global pollution from PIMacroBuilder.

## v1.3.1
### Changes
- Sidebar reorganization: new **Utilities** section between Combat and Quality of Life. Moved Gateway Alert, Pet Status Texts, Time Spiral Tracker, Recuperate Button, Dispel CD on Cursor, Disintegrate Castbar Ticks, World Marker Cycler, and Focus Marker Macro Builder into Utilities.
- Skinning section now auto-collapses when ElvUI is detected.
- Skinning sidebar reordered: General UI Clean Up and Buffs/Debuffs pinned at top, rest alphabetized.
- Range Checker Text renamed to **Range Display**.
- UX improvements across multiple GUI pages:
  - Color pickers paired side-by-side where previously stacked (Combat Timer, Range Display).
  - Automation page: all toggle pairs now side-by-side (Cinematics, Merchant, Quest, Social, Convenience).
  - Combat Cross: Range Warning checkboxes paired side-by-side.
  - Recuperate: Load conditions and Button Size merged into "General Settings" card, added full anchor frame controls.
  - Disintegrate Ticks: Note text split into two clear lines.
- Target Castbar: Added **Target Names** card with enable toggle, anchor, font size, and offset controls.
- Focus Castbar: Added **Target Names** enable toggle.

## v1.3.0
### Additions
- New module: **Focus Marker Macro Builder** — Auto-creates and manages a focus target + raid marker macro. Features marker icon grid selector, mark-only mode, no-raid marking, no-toggle, ready check announce, custom macro name/icon/conditionals.

### Fixes
- Target Castbar: Fixed target names using hardcoded positioning with no GUI controls.
- Focus Marker: Fixed NoToggle setting inversion causing marker spam on repeated clicks.

## v1.2.0
### Additions
- New module: **Disintegrate Castbar Ticks** — Evoker-only (Devastation/Preservation). Displays tick marks on your cast bar during Disintegrate channels with configurable "DON'T CLIP" warning for Mass Disintegrate. Supports UUF, BCDM, Ayije CDM, and Blizzard cast bars.
- New module: **World Marker Cycler** — Cycles through world markers at cursor position with customizable keybinds and drag-to-reorder marker priority. Interactive keybind capture with modifier support.

### Changes
- Sidebar renames: "Dispel on Cursor" → "Dispel CD on Cursor", "Time Spiral" → "Time Spiral Tracker".
- Time Spiral Tracker: Added note clarifying it works for all classes.
- GUI Notes: Standardized all note prefixes with accent-colored dash across all pages.
- CVars: Changed "enabled" text color from accent to green for better visibility.

## v1.1.5
### Fixes
- ActionBars: Removed pcall wrappers from cooldown text styling and SetUserPlaced calls to reduce taint spreading to Blizzard's ZoneAbility system. Note: modifying cooldown regions inherently taints them (known Blizzard-side issue shared with NorskenUI).

## v1.1.4
### Fixes
- Combat Res: Removed pcall wrappers around C_Spell.GetSpellCharges to prevent taint spreading to Blizzard's ZoneAbility system (caused CastSpellByID forbidden errors).

## v1.1.3
### Fixes
- Combat Res: Added event-driven updates (SPELL_UPDATE_CHARGES, PLAYER_REGEN_DISABLED) so the tracker shows during encounters on all classes, not just Druids.
- Tooltips: Removed EmbeddedItemTooltip from skin list to fix IsShown/SetAlpha errors on embedded widget tooltips.

## v1.1.1
### Fixes
- Sidebar: Hover and selection gradient overlays now update dynamically with theme changes.
- GUI-Theme: Fixed CreateButton callback format for Copy/Reset buttons.

## v1.1.0
### Additions
- Addon Theme system: 8 WoW-themed color presets (KitnUI, Nighthold, Firelands, Icecrown, Dreamsurge, Twilight, Sunwell, Torghast), class color mode, and full custom color mode.
- Paint icon button in header bar for quick theme access.
- Hamburger menu in header bar with Reload UI, Blizzard Edit Mode, Kitn Edit Mode, and Cooldown Manager shortcuts.

### Fixes
- GUI-Theme: Added nil guards for db.Custom color picker access.
- ActionBars: Added minimum size guard in proc glow hook to prevent errors on unsized buttons.
- DispelCursor: Added 60fps throttle to OnUpdate, proper event cleanup in OnDisable.
- AddonTheme: Added recursion guard to RefreshTheme to prevent infinite loops.
- CustomOutline: Secret value guards now cover all text/alpha comparisons.
- Sidebar: Accent bar and selection highlight colors now update dynamically with theme changes.
- CursorCircle/CombatCross: Added OnThemeChanged handlers for live theme color updates.

### Changes
- Merged Profiles and Theme into unified "Settings" sidebar section.
- Moved Cursor Circle from Quality of Life to Combat section.
- Removed Personal Defensives and Personal Movement Buffs from GUI sidebar (handled by ACDM).

## v1.0.9
### Additions
- New module: Dispel on Cursor — shows your dispel cooldown timer following your cursor, auto-detects class dispel spell.
- Cursor Circle: Added new crosshair and heart texture options, texture selector now supports multi-row grid layout.

## v1.0.8
### Fixes
- CustomOutline: Added secret/tainted value guards to all text and alpha comparisons to prevent errors on focus castbar and other secure frames.
- Tooltip skinning: Reverted to manual textures (bypass Backdrop.lua entirely) — NorskenUI's BackdropTemplate approach still triggered taint errors.

## v1.0.7
### Additions
- CombatCross: Added range warning — cross changes color when target is out of range (melee/ranged/healer spec support).
- Recuperate: Added configurable Load in Raid/Party toggles.

### Fixes
- MissingBuffs: Replaced AuraUtil.ForEachAura with direct C_UnitAuras API calls for better secret value handling.
- ActionBars: Added proc glow (SpellActivationAlert) size handling to match button size dynamically.
- Recuperate: Added health alpha curve (step: visible when missing health, hidden at full) and dead/ghost handling.

## v1.0.6
### Fixes
- Replaced BackdropTemplate with manual textures for tooltip skinning to avoid Blizzard Backdrop.lua taint errors on protected tooltips (world map POIs, quest tooltips, etc.).

## v1.0.5
### Additions
- MissingBuffs: Added food buff tracking (Well Fed, Sated, etc.).
- MissingBuffs: Added Rogue Stealth tracking with icon display.
- MissingBuffs: Added "Hide When Mounted" option for stance & spec buffs.
- MissingBuffs: Added Druid Forms "Only Show in Combat" option.

## v1.0.4
### Fixes
- Fixed secretvalue error with skinning the tooltip.

## v1.0.3
### Fixes
- Removed .png from ignore list.

## v1.0.2
### Changes
- Minor tweaks.

## v1.0.1
### Fixes
- Resolved KitnEssentials import error.

## v1.0.0
### Initial Release
- Combat modules: Combat Timer, Combat Cross, Combat Res, Combat Texts, Pet Status Texts, Gateway Alert, Target Castbar, Focus Castbar, Range Checker, TimeSpiral, Cursor Circle, Recuperate
- Custom Buffs: Buff Icons, Buff Bars, Personal Defensives, Personal Movement Buffs
- Quality of Life: Automation, Copy Anything, Dragon Riding UI, Missing Buffs, Hunters Mark Missing, Hide ActionBars, CDM Racials Anchor
- Skinning: Action Bars, Auras, Tooltips, Micro Menu, Blizzard Messages, Blizzard Mouseover, Blizzard Raid Manager, Details Backdrop, UI Cleanup
- Full GUI with theme support, edit mode, and profile management