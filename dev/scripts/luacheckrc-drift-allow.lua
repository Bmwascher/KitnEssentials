-- luacheckrc-drift-allow.lua — allowlist for dev/scripts/check-luacheckrc-drift.lua
--
-- Format:
--   missing_ok — .luacheckrc entries absent from the Blizzard 12.0.x
--     reference (API docs + full UI source) that are known-good anyway:
--     undocumented C-side APIs, removed APIs kept behind deliberate
--     nil-checks, forward-compat guards. Value = rationale string,
--     printed in the report next to the entry.
--   unused_ok — entries with zero bare-global uses in Core/Modules/GUI
--     that should stay in .luacheckrc regardless. The unused group is
--     always advisory; listing an entry here just silences its line.
--
-- Add an entry ONLY after verifying the global in-game (/run probe) or
-- confirming a deliberate guard in code — cite file:line in the
-- rationale. Remove the entry when the underlying rc line goes away.
return {
    missing_ok = {
        GetMouseFocus = "removed API; deliberate nil-checked compat (GUI/GUIHelpers/GUI-FrameChooser.lua:111)",
        GetMacroIndexByName = "undocumented C-side macro API; works in 12.0.x (PIMacroBuilder/FocusMarker/GUI-TotemTracker)",
        GameMovieFinished = "undocumented C-side; pcall-guarded (Automation.lua:269)",
        C_CastingInfo = "removed namespace; nil-checked forward-compat (DungeonCasts.lua:757)",
        IsWargame = "undocumented C-side; /run-verified function (type probe) 12.0.7 2026-07-05 (CombatLogger.lua:156)",
        NUM_LE_FRAME_TUTORIALS = "C-side constant, not in the UI-source export; /run-verified = 163 in 12.0.7 2026-07-01 (Automation.lua:60)",
        CharacterFrameTitleText = "generated frame name ($parentTitleText — literal grep can't see it); /run-verified frame exists in 12.0.7 2026-07-01 (CharacterPanel.lua:855)",
        ROLL_DISENCHANT = "GlobalStrings.lua constant, not in the UI-source export (same class as NUM_LE_FRAME_TUTORIALS); deliberate `or \"Disenchant\"` fallback guards a nil global (Modules/Skinning/LootRollBars.lua:237)",
        LootSlotHasItem = "NOT verified in-game -- absent from both the 12.0.7.68887 API docs and the full Blizzard UI source scan; Blizzard's own Blizzard_UIPanels_Game/Mainline/LootFrame.lua:48 now calls GetLootSlotType instead, suggesting this was replaced in the Midnight loot rework. Ported unguarded, verbatim, per the frozen plan's Global Constraint 1/8 (no unsanctioned guard on a ported reference) -- LootFrame.lua:64 (SlotEnter). Flagged as a concern in .superpowers/sdd/2026-07-30-aes-a6-3b-loot-family/task-5-report.md for an in-game /run probe; this entry should be replaced with a real probe result, not treated as settled.",
    },
    unused_ok = {
        canaccesstable = "declared for symmetry with the secret-intrinsics family",
    },
}
