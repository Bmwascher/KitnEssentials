# Changelog

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