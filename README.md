# KitnEssentials

Standalone combat, utilities, quality of life, dungeons, and skinning modules for **KitnUI**.

KitnEssentials adds HUD elements, buff trackers, automation features, and Blizzard UI skinning through a fully themed settings panel. Every module is independently toggleable and repositionable via a built-in edit mode.

## Features

- **45+ modules** — combat HUD, buff tracking, automation, dungeon tools, and UI skinning
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
| Cursor Circle | Cursor-following ring with GCD overlay, multiple texture options |
| Range Display | Target range text with out-of-range color warning |
| Boss Debuffs | External debuff icon display with cooldown spiral, duration text, encounter blacklist, and visibility gating |
| Focus & Target Castbar | Repositionable cast bars with kick indicators, target names, focus raid marker, color settings, and cast sound alert (tabbed GUI) |

## Utilities

| Module | Description |
|---|---|
| Raid Notifications | Gateway usability, reset boss reminder, loot boss reminder, Mythic raid bench alert, and seasonal bonus rolls reminder with per-alert toggles |
| Class Status Texts | Pet status, class stance, movement alert, and dispel CD — 4 class-specific text alerts in one tabbed GUI |
| Bloodlust Tracker | Animated Pedro overlay + sound or static icon with countdown on Bloodlust/Heroism/Time Warp |
| Time Spiral Tracker | Movement spell proc tracker with glow effects, cooldown spiral, and countdown timer (all classes) |
| Recuperate Button | One-click self-heal with configurable raid/party visibility and health-based alpha |
| Evoker Suite | Disintegrate tick marks, Preservation Stasis tracker, Ebon Might crit/dupe tracker with pandemic refresh glow and ally extension warning, and Prescience Tracker (Prescience/Shifting Sands on allies) — tabbed GUI |
| World Marker Cycler | Cycle through world markers at cursor with drag-to-reorder priority |
| Macro Builders | Focus Marker and Power Infusion macro builders in one tabbed GUI |
| Combat Potion Ready | "Potion Ready" text when a combat potion is in bags and off cooldown, with instance/combat/healer visibility toggles |
| Ready Check Consumables | On ready check, attaches a row of clickable consumable icons (food, flask, weapon enhancement MH/OH, augment rune, healthstone, and Warlock Soulstone with auto-target healer) for one-click application |

## Quality of Life

| Module | Description |
|---|---|
| Automation | Auto-repair, auto-sell, auto-confirm queue, auto-slot keystone, skip cinematics, hide event toasts/zone text, and more |
| Combat Logger | Automatic combat logging for raids, dungeons, M+, PvP, and arenas with per-content toggles |
| CVars | One-click CVar optimization panel |
| Slash Commands | Custom slash command utilities |
| Auction House Filter | Auto-filter AH to current expansion, auto-focus search bar, craft orders filter |
| Hunter's Mark Missing | Alert when Hunter's Mark is not applied |
| Skyriding UI | Skyriding vigor bar with second wind tracker and whirling surge cooldown icon |
| Position Controller | Anchors ElvUI Player/Target/Focus/Pet frames to other frames, plus CDM racials bar offset with pet detection (works with ElvUI and UUF). Yields to the standalone ElvUI_Anchor addon if loaded; ignores healer specs by default |
| Spell Alert Opacity | Per-spec toggle for Blizzard's proc activation overlay flashes, plus an opacity slider for the overlay |
| Custom Nicknames | Map characters to personal nicknames on ElvUI and Unhalted Unit Frames via the `[kes:nickname]` tag family (plus class-color variants `[kes:nickname:color]` for UUF); includes a management GUI with search, import/export, and replace/merge modes |
| Hide ActionBars | Hide specific action bar rows in/out of combat |
| Great Vault Alert | Shows your loot spec when opening the Great Vault with class color and sound |
| Missing Enchants/Gems | Red warnings on character panel for missing enchants and empty gem sockets |
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
| Death Notifications | On-screen alert when party/raid members or your focus target dies, with class portrait + color and configurable text format. Active in dungeons by default; raid activation is opt-in |
| Dungeon Casts | Enemy cast bars for M+ nameplates with icon, target text, raid icons, bar stacking, and interruptible/shielded status colors |
| Dungeon Timers | Curated dungeon ability timers driven by BigWigs events with hand-tuned cast durations, phase tracker for HP-based encounter transitions, role-based filtering, and per-spell display overrides |
| Enemy Counter | Displays the number of enemies currently in combat via nameplate scanning with editable prefix and combat-only visibility |
| Healer Mana Tracker | Displays the current party healer's name, spec icon, and mana % (party-only; hidden in raid); shows OFFLINE when the healer disconnects |
| Interrupt Tracker | Party interrupt cooldown bars with class colors, dark mode, channel kick detection, and healer position override (currently non-functional in 12.0.5 due to API changes — under investigation) |
| WarpDeplete+ | Restores live pull forces tracking, fixes death tooltip and class-colored names in M+, per-mob forces on tooltip mouseover, and announces instance resets to party/raid chat |

## ElvUI Tags

| Tag | Description |
|---|---|
| `[kes:name-classcolor]` | Unit name with class/reaction color |
| `[kes:target:separator]` | White » separator, hidden when no target |
| `[kes:target:name-classcolor]` | Target name with class/reaction color |
| `[kes:group]` | Shows "Group: X" only while in a raid |

## Settings

| Feature | Description |
|---|---|
| Addon Theme | 8 WoW-themed color presets, class color mode, and fully custom colors |
| Profile System | Import, export, and manage profiles with per-character and global support |
| Edit Mode | Drag to reposition any element, nudge tool for pixel-perfect placement |
| Minimap Button | Left-click opens settings, right-click toggles edit mode, middle-click reloads UI |
| Sidebar Search | Real-time search bar at top of sidebar to quickly filter modules by name |

## Slash Commands

| Command | Description |
|---|---|
| `/kes` or `/kitnessentials` | Toggle settings GUI |
| `/kes edit` | Toggle edit mode |
| `/kes resetgui` | Reset GUI position and size |

## Credits

Built on the **NorskenUI** framework. Both **NorskenUI** and **AtrocityEssentials** have been a steady source of ideas — thanks to both projects.

## Related Addons

- **KitnUI** — ElvUI profile installer with Dark and Color variants
- **KitnUI Lite** — Standalone profile installer for popular addons (no ElvUI required)
