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
        IsWargame = "undocumented C-side; verify-in-game 2026-07 (CombatLogger.lua:156)",
        NUM_LE_FRAME_TUTORIALS = "C-side constant, not in the UI-source export; /run-verified = 163 in 12.0.7 2026-07-01 (Automation.lua:60)",
        CharacterFrameTitleText = "generated frame name ($parentTitleText — literal grep can't see it); /run-verified frame exists in 12.0.7 2026-07-01 (CharacterPanel.lua:855)",
    },
    unused_ok = {
        canaccesstable = "declared for symmetry with the secret-intrinsics family",
    },
}
