# Changelog

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