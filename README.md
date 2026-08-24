# KitnEssentials

[![Lint](https://github.com/Bmwascher/KitnEssentials/actions/workflows/lint.yml/badge.svg)](https://github.com/Bmwascher/KitnEssentials/actions/workflows/lint.yml)
[![Test](https://github.com/Bmwascher/KitnEssentials/actions/workflows/test.yml/badge.svg)](https://github.com/Bmwascher/KitnEssentials/actions/workflows/test.yml)

Standalone combat, quality of life, dungeon, and skinning modules for **KitnUI**.

KitnEssentials adds HUD elements, aura trackers, automation, dungeon tools, and Blizzard UI skinning through a fully themed settings panel. Every module starts switched off, so a fresh install shows nothing until you turn on what you want, and each one is independently toggleable and repositionable via a built-in edit mode. ElvUI is optional throughout — nothing here requires it.

## Features

- **Dozens of modules** — combat HUD, aura tracking, automation, dungeon tools, and UI skinning
- **Dark themed GUI** — custom settings panel with sidebar navigation and 8 color themes
- **Edit mode** — drag any element to reposition, with snapping to a grid and to other elements' edges and centres, centre guides, keyboard nudging, per-category filtering, and anchor and strata controls
- **Profile system** — save, copy, and reset per-character or shared profiles
- **Global font** — set one font for every module, with per-module overrides still available
- **Sidebar search** — filter every page by name or keyword as you type
- **Minimap button** — quick access to settings, edit mode, and reload

The sections below mirror the settings panel, so anything listed here is where you will find it in game.

## Core

| Page | Description |
|---|---|
| Home Page | Welcome page and the general settings below |
| Profile Manager | Import, export, copy, and reset profiles, with per-character and global support |
| Addon Theme | 8 WoW-themed color presets, class color mode, and fully custom colors |
| System Optimization | One-click performance pass covering frame rate, memory, latency, and related console variables |

The home page also carries the general settings: minimap button, login message, Global Font, and Slug font rendering. Slug is Blizzard's GPU glyph renderer — it gives sharper text but is unavailable in some locales, so it can be turned off for everything at once.

## Combat

| Module | Description |
|---|---|
| Combat Res | Combat res charge tracker with timer |
| Combat Texts | Combat enter/exit, no target warning, interrupt announce with spell icon, and low durability warnings |
| Combat Timer | Configurable in-combat duration display |
| Cursor Effects | Cursor-following ring with GCD overlay and multiple textures, plus optional dispel and taunt cooldown countdowns at the cursor — tabbed page |
| Focus Castbar | Repositionable cast bar with kick indicators, target names, focus raid marker, important-spell glow, out-of-range dimming, color settings, and cast sound alert |
| Healer Mana | Healer mana readout with a name and spec icon per healer. Dungeon Mode shows the single party or M+ healer; Raid Mode, when enabled in raid instances, shows every raid healer stacked. Shows OFFLINE when a healer disconnects |
| No Movement Alert | Remaining-cooldown alert when your movement ability is unavailable — auto-detects your highest-priority movement spell (all classes) |
| Player Absorbs | On-screen readout of your active damage-absorb shield and heal-absorb, with optional icons, flexible layout (stacked, side-by-side, or split), and player-frame anchoring |
| Player Crosshair | Static crosshair overlay with range warning (melee, ranged, healer), cross or circle shape, optional always-on display, and an option to show it only while out of range |
| Range Display | Target range text with out-of-range color warning |

## Aura Tracking

| Module | Description |
|---|---|
| Player Buffs | Replacement player buff header with weapon-enchant support and full layout control |
| Player Debuffs | Replacement player debuff header with dispel-type coloring and full layout control |
| Advanced Debuffs | Bar-based dispellable-debuff display with cooldown swipe, native countdown text, dispel-type border color and atlas overlay, PLAYER filter, per-type include/exclude, a nameplate-only toggle, and a blocklist covering the spells the game lets addons identify by name (subsumes the older Boss Debuffs module) |
| External Tracker | External defensive cooldowns cast onto you (Pain Suppression, Ironbark, Blessing of Sacrifice, and similar) with cooldown swipe, native countdown text, configurable glow per cast, BigWigs glow integration on incoming raid hits, and a sound test |
| Missing Forms | Icon alert when you are not in the stance, form, aura, or attunement your specialization expects. Covers Warrior stances, Druid forms, Paladin auras, Priest Shadowform, and Evoker attunements, with a per-spec required choice, combat-only option, and a "show current form" mode that names what you are in instead |

## Class Utilities

| Module | Description |
|---|---|
| Evoker Suite | Disintegrate tick marks, Preservation Stasis tracker, Ebon Might crit/dupe tracker with pandemic refresh glow and ally extension warning, and Prescience Tracker (Prescience and Shifting Sands on allies) — tabbed page |
| Hunter: Mark Missing | Alert when Hunter's Mark is not applied |
| Pet Status Texts | On-screen pet status alerts for pet classes (Hunter, Warlock, Death Knight, Mage) |
| Priest: PI Macro | Dynamically builds a Power Infusion macro with trinkets, racials, and potions |
| Totem Tracker | Bar tracker for active totems with destroy buttons, configurable layout, and edit-mode integration. Tracks **all four Augmentation Evoker dupes** with independent timers — the default UI shows only two |
| Warlock: Burning Rush | Glowing icon reminder while Burning Rush is active |
| Warlock: Havoc Tracker | On-screen warning when your own Havoc is on the target you are already hitting. Destruction only |

## QoL

| Page | Description |
|---|---|
| Automation | Auto-repair with a repair cost announcement, auto-sell, auto-confirm queues, auto-slot keystone, skip cinematics, hide event toasts and zone text, merchant and auction house conveniences, and one-click Vantus Rune withdrawal from the guild bank |
| Combat Logger | Automatic combat logging for raids, dungeons, M+, PvP, arenas, and scenarios including delves, with per-content toggles, a one-click Advanced Combat Logging switch, and a Warcraft Recorder preset |
| CVars | One-click console variable panel that reads its values live from your client, including separate scale sliders for the windowed and maximized world map |
| Great Vault Alert | Shows your loot spec when opening the Great Vault, with class color and sound |
| Quality of Life | Four tools on one page: Spell Alert Opacity (per-spec opt-in grid for Blizzard's proc overlay flashes, plus an opacity slider), Move Frames (drag Blizzard windows anywhere), Copy Anything (pull spell, item, NPC, and aura IDs to the clipboard from tooltips), and Slash Commands (shorthand commands such as `/rl`, `/cd`, `/fs`, `/leave`, `/reset`, `/mute`, `/music`) |
| Utilities | Six tools on one page: Combat Potion (a "Potion Ready" cue when a combat potion is in bags and off cooldown), Raid Notifications (gateway usability, reset and loot boss reminders, Mythic bench alert, seasonal bonus rolls), Ready Check (clickable consumable icons on ready check, including Warlock Soulstone with auto-target healer), Recuperate (one-click self-heal with health-based visibility), Time Spiral (movement proc tracker with glow and countdown, all classes), and World Markers (cycle markers at the cursor with drag-to-reorder priority) |

## Dungeon Tools

| Module | Description |
|---|---|
| Keystone Helper | Keystone reminders and group tools on one tabbed page: party or raid announce on instance reset, a glowing "reroll your key" prompt after timing a key at or above your keystone's level, a "Your Key?" prompt when entering the Mythic 0 dungeon matching your keystone, plus a reworked group finder panel with filtering, a quick-create listing tool, and a reminder when you have a group listed and stop watching it |
| Death Notifications | On-screen alert when party or raid members, or your focus target, die — class portrait and color, configurable text format, and an optional voice reminder when your focus dies in combat. Covers dungeons once you switch it on; raid activation is opt-in |
| Dungeon Casts | Enemy cast bars for M+ nameplates with icon, target text, raid icons, bar stacking, and interruptible or shielded status colors |
| Enemy Counter | Number of enemies currently in combat via nameplate scanning, with editable prefix and combat-only visibility |
| Focus Marker | Auto-creates a focus targeting and raid marker macro, with optional party ready-check announce |
| Interrupt Tracker | Party interrupt cooldown bars rebuilt for 12.0.5 — live synced bars for teammates running kick-sync addons, temporary class-colored kick records for everyone else, dark mode, and healer position override |
| Targeted Spells | Mirrored icon and countdown entries for enemy casts targeting you, with important-spell glow, an interrupt indicator, per-content filters, and adjustable layout, font, and colors |

## Dungeon Timers

Curated dungeon ability timers driven by BigWigs events, with hand-tuned cast durations, a phase tracker for HP-based encounter transitions, role-based filtering, and per-spell display overrides. A separate Dungeon Trash Tracker predicts trash-pack casts from nameplate observation, with on-nameplate countdown icons and per-ability sounds.

| Page | Description |
|---|---|
| General | Master enable, BigWigs integration, and role filtering |
| Bar Settings | Bar color, texture, size, and growth |
| Text Settings | Font, outline, and label formatting |
| Nameplate Settings | Trash tracker icons, countdowns, and per-ability sounds |
| Per-dungeon pages | Algeth'ar Academy, Magisters' Terrace, Maisara Caverns, Nexus-Point Xenas, Pit of Saron, Seat of the Triumvirate, Skyreach, and Windrunner Spire |

## Skinning

| Page | Description |
|---|---|
| Dark Theme | One skinning engine across roughly fifty Blizzard windows, dialogs, context menus, and toasts, on a four-tab page: General (window colors included), Fonts, Skins (Blizzard frames, with skins for several third-party addons below them), and Elements (loot roll, loot window, UI widgets, character screen). Also carries the Color Picker additions (typed RGB and alpha entry in Blizzard's picker) and Raid Control (a group panel with ready check, a 5, 10 or 20 second countdown, difficulty, everyone-assist, world markers, a role count, group sorting, a Vantus Rune check, and a raid buff strip) |
| Vehicle Exit Button | The vehicle and taxi exit button, skinned to match, and placeable anywhere with anchor-to-frame support |
| Chat | Custom movable chat panel with tab styling, short channel names, timestamps with live clock samples, chat copy, message fading, class-colored Battle.net whispers, guild login and logout messages, and whisper sounds. Also carries Chat Links (icons in front of linked items, currencies, spells, achievements, keystones and PvP talents, numerical crafting quality, and clickable web addresses with a copy box), Chat History (per-character chat and typing recall restored after a reload, with the original timestamps), keyword highlight with an optional sound, class-colored mentions, and achievement merging |
| Damage Meter | Standalone multi-window damage and healing meter built on the 12.0 damage meter API, replacing Blizzard's built-in one. Proportional dock with shared backdrop, per-content auto-swapping layouts, eight meter types, class-colored bars with nickname support, header combat clock anchored to the game's own fight timer, spell breakdown for your own bar and death recaps for any row that stay open in combat, target details, segment history, and report-to-chat |
| Mythic+ Timer | Self-contained keystone timer HUD — count-up timer with +3/+2/+1 threshold marks, aggregate forces bar, per-boss objective list with clear times and personal-best deltas, deaths line with class-colored hover log, personal-best splits, Challenger's Peril aware cutoffs, enemy tooltip and nameplate forces overlay, keystone auto-insert, Blizzard objective-tracker hider, boss-split party chat posts, and a live preview. Six-tab config page (`/kes mt`) |
| Skyriding UI | Skyriding vigor bar with second wind tracker and whirling surge cooldown icon |
| Tooltips | Tooltip backdrop and font restyling, cursor anchoring, spell, item, and aura IDs, guild rank, Mythic rating, target line, class-colored health bar, and hide-in-combat |

## ElvUI Tags

| Tag | Description |
|---|---|
| `[kes:name-classcolor]` | Unit name with class or reaction color |
| `[kes:target:separator]` | White » separator, hidden when no target |
| `[kes:target:name-classcolor]` | Target name with class or reaction color |
| `[kes:group]` | Shows "Group: X" only while in a raid |
| `[kes:mana:percent]` | Unit's mana percentage, hidden at 100% |

## Slash Commands

`/kes` (also `/kitnessentials` and `/dunnigan`) is the base command for all of the below.

| Command | Description |
|---|---|
| `/kes` or `/kes gui` | Toggle settings GUI. In combat it queues, and the panel opens when combat ends |
| `/kes edit` or `/kes unlock` | Toggle edit mode |
| `/kes profiler` or `/kes prof` | Performance profiler (`/kes profiler help` lists its subcommands) |
| `/kes mt` | Open the Mythic+ Timer settings page (`/kes mt clearsplits` clears stored personal bests with confirmation) |
| `/kes dm` | Toggle the Damage Meter dock (`/kes dm reset` clears segment history, `/kes dm report [count] [channel]` posts the view to chat) |
| `/kes resetgui` | Reset GUI position and size |
| `/kes help` or any unrecognized command | List all commands in chat |

## Credits

Built on the **NorskenUI** framework. Both **NorskenUI** and **AtrocityEssentials** have been a steady source of ideas — thanks to both projects.

## Related Addons

- **KitnUI** — ElvUI profile installer with Dark and Color variants
- **KitnUI Lite** — Standalone profile installer for popular addons (no ElvUI required)
