# KitnEssentials

[![Lint](https://github.com/Bmwascher/KitnEssentials/actions/workflows/lint.yml/badge.svg)](https://github.com/Bmwascher/KitnEssentials/actions/workflows/lint.yml)
[![Test](https://github.com/Bmwascher/KitnEssentials/actions/workflows/test.yml/badge.svg)](https://github.com/Bmwascher/KitnEssentials/actions/workflows/test.yml)

Standalone combat, utilities, quality of life, dungeons, and skinning modules for **KitnUI**.

KitnEssentials adds HUD elements, buff trackers, automation features, and Blizzard UI skinning through a fully themed settings panel. Every module is independently toggleable and repositionable via a built-in edit mode.

## Features

- **60+ modules** — combat HUD, buff tracking, automation, dungeon tools, and UI skinning
- **Dark themed GUI** — custom settings panel with sidebar navigation and 8 color themes
- **Edit mode** — drag any element to reposition, with anchor and strata controls
- **Profile system** — save, copy, and reset per-character or shared profiles
- **Minimap button** — quick access to settings, edit mode, and reload

## Combat

| Module | Description |
|---|---|
| Battle Res | Battle res charge tracker with timer |
| Combat Timer | Configurable in-combat duration display |
| Player Crosshair | Static crosshair overlay with range warning (melee/ranged/healer) |
| Combat Texts | Combat enter/exit, no target warning, interrupt announce with spell icon, and low durability warnings |
| Cursor Effects | Cursor-following ring with GCD overlay, multiple texture options, and an optional dispel-cooldown countdown at the cursor |
| Range Display | Target range text with out-of-range color warning |
| Advanced Debuffs | Bar-based dispellable-debuff display with cooldown swipe, native countdown text, dispel-type border color and atlas overlay, PLAYER filter, per-type include/exclude, and spell-ID blocklist (subsumes the older Boss Debuffs module) |
| External and Defensive Buffs | External defensive cooldowns cast onto you (Pain Suppression, Ironbark, etc.) with cooldown swipe, native countdown text, configurable glow per cast, BigWigs glow integration on incoming raid hits, and a Sound Test button |
| Focus & Target Castbars | Repositionable cast bars with kick indicators, target names, focus raid marker, important-spell glow, out-of-range dimming, color settings, and cast sound alert (tabbed GUI) |
| Damage Meter | Standalone multi-window damage/healing meter built on the 12.0 C_DamageMeter API (replaces Blizzard's built-in meter) — proportional dock with shared backdrop, per-content auto-swapping layouts, eight meter types, class-colored bars with nickname support, header combat clock, out-of-combat spell breakdown / death recap / target details, segment history, and report-to-chat |

## Class Utilities

| Module | Description |
|---|---|
| Evoker Suite | Disintegrate tick marks, Preservation Stasis tracker, Ebon Might crit/dupe tracker with pandemic refresh glow and ally extension warning, and Prescience Tracker (Prescience/Shifting Sands on allies) — tabbed GUI |
| Hunter: Mark Missing | Alert when Hunter's Mark is not applied |
| Pet Status Texts | On-screen pet status text alerts for pet classes (Hunter, Warlock, Death Knight, Mage) |
| Priest: PI Macro | Dynamically builds a Power Infusion macro with trinkets, racials, and potions |
| Spell Alert Opacity | Per-spec opt-in/out grid for Blizzard's proc activation overlay flashes (every class, 4-column layout), plus an opacity slider for the overlay |
| Stance Text | Your current stance/shapeshift form name as configurable on-screen text |
| Totem Tracker | Shaman-only bar tracker for active totems with destroy buttons, configurable layout, and EditMode integration |
| Warlock: Burning Rush | Glowing icon reminder while Burning Rush is active |

## Utilities

| Module | Description |
|---|---|
| Combat Potion Ready | "Potion Ready" text when a combat potion is in bags and off cooldown, with instance/combat/healer visibility toggles |
| No Movement Alert | Remaining-cooldown alert when your movement ability is unavailable — auto-detects your highest-priority movement spell (all classes) |
| Player Absorbs | On-screen text readout of your active damage-absorb shield and heal-absorb, with optional icons, flexible layout (stacked/side-by-side/split), and player-frame anchoring |
| Raid Notifications | Gateway usability, reset boss reminder, loot boss reminder, Mythic raid bench alert, and seasonal bonus rolls reminder with per-alert toggles |
| Ready Check Consumables | On ready check, attaches a row of clickable consumable icons (food, flask, weapon enhancement MH/OH, augment rune, healthstone, and Warlock Soulstone with auto-target healer) for one-click application |
| Recuperate Button | One-click self-heal with configurable raid/party visibility and health-based alpha |
| Time Spiral Tracker | Movement spell proc tracker with glow effects, cooldown spiral, and countdown timer (all classes) |
| World Marker Cycler | Cycle through world markers at cursor with drag-to-reorder priority |

## Healer

| Module | Description |
|---|---|
| Dispel Frame Glow | Colored border + top fade on ElvUI party/raid/tank frames with a dispellable debuff (including private auras), tinted by your dispel-type palette with adjustable thickness; requires ElvUI |
| Dispel on Cursor | Your dispel spell's cooldown countdown at the cursor — a healer-focused view of the Cursor Effects dispel countdown (shared settings) |
| Healer Mana | Displays the current party healer's name, spec icon, and mana % (party-only; hidden in raid); shows OFFLINE when the healer disconnects |
| Innervate Tracker | Icon + countdown while Innervate is on you, with configurable label, glow, and alert sound; detected via mana-cost polling (Innervate is hidden from the aura API in 12.0); healer-capable classes only |
| Maintenance Tracker | One icon per key maintenance buff with group-member count and lowest remaining duration, color-coded by urgency; spec-aware (Atonement, Renewing/Enveloping Mist, Rejuvenation, Riptide, Echo) with side-by-side multi-spell layout and GUI preview |

## Quality of Life

| Module | Description |
|---|---|
| Automation | Auto-repair, auto-sell, auto-confirm queue, auto-slot keystone, skip cinematics, hide event toasts/zone text, and more |
| Combat Logger | Automatic combat logging for raids, dungeons, M+, PvP, and arenas with per-content toggles |
| CVars | One-click CVar optimization panel |
| Slash Commands | Toggleable shorthand slash commands (`/rl`, `/cd`, `/fs`, `/leave`, `/reset`, `/mute`, `/music`) |
| Skyriding UI | Skyriding vigor bar with second wind tracker and whirling surge cooldown icon |
| Position Controller | Auto-anchors ElvUI Player/Target frames beside SkironCooldownManager or Ayije_CDM (auto-detected, clears the widest cooldown row); Focus/Pet anchor freely; CDM racials bar offset with pet detection (works with ElvUI and UUF). Writes through ElvUI's mover system so placements survive `/reload`. Yields to the standalone ElvUI_Anchor addon if loaded; ignores healer specs by default |
| Custom Nicknames | Map characters to personal nicknames on ElvUI and Unhalted Unit Frames via the `[kes:nickname]` tag family (plus class-color variants `[kes:nickname:color]` for UUF); includes a management GUI with search, import/export, and replace/merge modes; nicknames also display on the KitnEssentials Damage Meter |
| WindTools Game Bar | Opt-in toggle to hide WindTools' Game Bar without unloading the module |
| Great Vault Alert | Shows your loot spec when opening the Great Vault with class color and sound |
| Character Panel | Per-slot item level, enchant labels, gem icons, missing-gem cue, and item-track letters (M/H/C/V/A) on the player and inspect frames; decimal stat-pane and inspect item level; interactive Gem Socket Helper (Shift-click to replace all matching gems); auto-disables BetterCharacterPanel if loaded |
| World Map | Adjustable minimized map scale, coordinate waypoint search bar, and city map icons for Silvermoon / Stormwind / Orgrimmar |
| Vantus Rune | One-click Vantus Rune withdrawal from Guild Bank with priority and confirmation |

## Skinning

| Module | Description |
|---|---|
| General UI Clean Up | Hide unnecessary Blizzard UI elements |
| Buffs, Debuffs & Externals | Restyle aura icons and bars |
| Action Bars | Dark themed backdrops, cooldown text styling and proc glow sizing |
| Blizzard Mouseover | Highlight and tooltip behavior tweaks |
| Blizzard Texts | Font and outline changes for Blizzard text |
| Blizzard Tooltips | Tooltip backdrop and font restyling |
| Micro Menu | Micro menu bar appearance |
| Battle.net Toast | Dark theme for BNet notification toasts with custom anchor positioning |
| Details Backdrop | Details! Damage Meter backdrop styling |
| Raid Manager Panel | Raid manager panel appearance |

## Dungeons

| Module | Description |
|---|---|
| Death Notifications | On-screen alert when party/raid members or your focus target dies, with class portrait + color, configurable text format, and an optional voice (TTS) reminder when your focus dies in combat. Active in dungeons by default; raid activation is opt-in |
| Dungeon Casts | Enemy cast bars for M+ nameplates with icon, target text, raid icons, bar stacking, and interruptible/shielded status colors |
| Dungeon Timers | Curated dungeon ability timers driven by BigWigs events with hand-tuned cast durations, phase tracker for HP-based encounter transitions, role-based filtering, and per-spell display overrides |
| Enemy Counter | Displays the number of enemies currently in combat via nameplate scanning with editable prefix and combat-only visibility |
| Focus Marker | Auto-creates a focus targeting + raid marker macro, with optional party ready-check announce |
| Interrupt Tracker | Party interrupt cooldown bars rebuilt for 12.0.5 — live synced bars for teammates with kick-sync addons, temporary class-colored kick records for everyone else, dark mode, and healer position override |
| Keystone Helper | Three M+ keystone reminders: party/raid announce on instance reset, a glowing "reroll your key" prompt after timing a key at/above your keystone's level, and a "Your Key?" prompt when entering the Mythic 0 dungeon matching your owned keystone |
| Mythic+ Timer | Self-contained keystone timer HUD — count-up timer with +3/+2/+1 threshold marks, aggregate forces bar, per-boss objective list with clear times and personal-best deltas, deaths line with class-colored hover log, personal-best splits, Challenger's Peril aware cutoffs, enemy tooltip + nameplate forces overlay (replaces the standalone WarpDeplete+ overlay), keystone auto-insert, Blizzard objective-tracker hider, boss-split party chat posts, and a Rookery +12 live preview. Six-tab config page (`/kes mt`) |
| Targeted Spells | Mirrored icon + countdown entries for enemy casts targeting you — important-spell glow, interrupt X indicator, per-content filters, and adjustable layout, font, and colors |

## ElvUI Tags

| Tag | Description |
|---|---|
| `[kes:name-classcolor]` | Unit name with class/reaction color |
| `[kes:target:separator]` | White » separator, hidden when no target |
| `[kes:target:name-classcolor]` | Target name with class/reaction color |
| `[kes:group]` | Shows "Group: X" only while in a raid |
| `[kes:mana:percent]` | Unit's mana percentage, hidden at 100% |

## Settings

| Feature | Description |
|---|---|
| Addon Theme | 8 WoW-themed color presets, class color mode, and fully custom colors |
| Profile System | Import, export, and manage profiles with per-character and global support |
| Edit Mode | Drag to reposition any element, nudge tool for pixel-perfect placement |
| Minimap Button | Left-click opens settings, right-click toggles edit mode, middle-click reloads UI |
| Sidebar Search | Real-time search bar at top of sidebar to quickly filter modules by name |

## Slash Commands

`/kes` (also `/kitnessentials` and `/dunnigan`) is the base command for all of the below.

| Command | Description |
|---|---|
| `/kes` or `/kes gui` | Toggle settings GUI |
| `/kes edit` or `/kes unlock` | Toggle edit mode |
| `/kes profiler` or `/kes prof` | Performance profiler (`/kes profiler help` lists its subcommands) |
| `/kes mt` | Open the Mythic+ Timer settings page (`/kes mt clearsplits` clears stored PB records with confirmation) |
| `/kes dm` | Toggle the Damage Meter dock (`/kes dm reset` clears segment history, `/kes dm report [count] [channel]` posts the view to chat) |
| `/kes resetgui` | Reset GUI position and size |
| `/kes help` or any unrecognized command | List all commands in chat |

## Credits

Built on the **NorskenUI** framework. Both **NorskenUI** and **AtrocityEssentials** have been a steady source of ideas — thanks to both projects.

## Related Addons

- **KitnUI** — ElvUI profile installer with Dark and Color variants
- **KitnUI Lite** — Standalone profile installer for popular addons (no ElvUI required)
