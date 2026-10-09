-- luacheckrc-drift-allow.lua — allowlist for dev/scripts/check-luacheckrc-drift.lua
--
-- Format:
--   missing_ok — .luacheckrc entries absent from the Blizzard 12.0.x
--     reference (API docs + full UI source) that are known-good anyway:
--     undocumented C-side APIs, removed APIs kept behind deliberate
--     nil-checks, forward-compat guards. Value = rationale string,
--     printed in the report next to the entry.
--   unused_ok — entries with zero bare-global uses in Core/Modules/GUI/
--     KitnEssentials_Options that should stay in .luacheckrc regardless. The unused group is
--     always advisory; listing an entry here just silences its line.
--
-- Add an entry ONLY after verifying the global in-game (/run probe) or
-- confirming a deliberate guard in code — cite the file and the function or
-- table that guards or uses it in the rationale, never a line number. Remove
-- the entry when the underlying rc line goes away.
return {
    missing_ok = {
        GetMouseFocus = "removed API; deliberate nil-checked compat (GUI/GUIHelpers/GUI-FrameChooser.lua, OnUpdateHandler)",
        GetMacroIndexByName = "undocumented C-side macro API; works in 12.0.x (PIMacroBuilder/FocusMarker/GUI-TotemTracker)",
        IsWargame = "undocumented C-side; /run-verified function (type probe) 12.0.7 2026-07-05 (Modules/QoL/CombatLogger.lua, CL:CheckArenaLogging)",
        CharacterFrameTitleText = "generated frame name ($parentTitleText — literal grep can't see it); /run-verified frame exists in 12.0.7 2026-07-01 (Modules/QoL/CharacterPanel.lua, HeaderRegions and CP:StyleCharacterTexts)",
        ROLL_DISENCHANT = "GlobalStrings.lua constant, not in the UI-source export; /run-verified = \"Disenchant\" in 12.0.7 2026-07-31 (Modules/Skinning/LootRollBars.lua, LR:RollBar_Create)",
        LootSlotHasItem = "C-side global absent from the 12.0.7 API docs AND the full UI-source scan (Blizzard's own LootFrame.lua uses GetLootSlotType instead) -- but /run-verified LIVE in 12.0.7 2026-07-31: absence from the clone is not removal for a C-side global Blizzard's UI stopped calling (Modules/Skinning/LootFrame.lua, SlotEnter)",
        EnumerateFrames = "undocumented C-side frame-chain walker; the clone only carries the unrelated ScrollBox :EnumerateFrames method; /run-verified function (type probe) 12.0.7 2026-08-04 (Modules/Diagnostics/Profiler.lua, CensusCollect)",
        PlaySoundFile = "C-side global absent from the 12.1.0 API docs AND the full UI-source scan (same class as LootSlotHasItem -- Blizzard's own UI plays sounds via PlaySound soundkit ids); /run-verified function (type probe) 12.1.0 2026-08-11 (Modules/Combat/FocusCastbar.lua, FC:PlayCastSound)",
        ERR_INV_FULL = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_QUEST_LOG_FULL = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_RAID_GROUP_ONLY = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_PARTY_LFG_BOOT_LIMIT = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_PARTY_LFG_BOOT_DUNGEON_COMPLETE = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_PARTY_LFG_BOOT_IN_COMBAT = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_PARTY_LFG_BOOT_IN_PROGRESS = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_PARTY_LFG_BOOT_LOOT_ROLLS = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_PARTY_LFG_TELEPORT_IN_COMBAT = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_PET_SPELL_DEAD = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_PLAYER_DEAD = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        SPELL_FAILED_TARGET_NO_POCKETS = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_ALREADY_PICKPOCKETED = "GlobalStrings.lua constant, not in the UI-source export (same class as ROLL_DISENCHANT); nil-guarded by the `if msg then` filter in Modules/QoL/Automation.lua, BuildErrKeepList",
        ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S = "GlobalStrings.lua format-string constant, not in the UI-source export; nil-guarded in Modules/QoL/Automation.lua, IsBootNotEligible, and its string.format is pcall-wrapped",
    },
    unused_ok = {
        canaccesstable = "declared for symmetry with the secret-intrinsics family",
    },
}
