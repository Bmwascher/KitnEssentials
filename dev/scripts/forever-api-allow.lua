-- forever-api-allow.lua: uses check-forever-api.lua reports that are safe on
-- the Forever client, keyed by file, then symbol, with the reason.
--
-- Add an entry only after reading the site: the reason says what keeps the
-- use from running, or from erroring, when the symbol is nil. An entry that
-- stops matching fails the check, so remove it with the code it covered.
return {
    ["Modules/QoL/Automation/Automation.lua"] = {
        ChallengesKeystoneFrame = "read after Blizzard_ChallengesUI loads, then nil-checked",
        LFDRoleCheckPopup = "SetupAutoRoleCheck returns when it is nil",
        LFGListApplicationDialog = "every read is nil-checked before use",
        LFGListFrame = "every read is `LFGListFrame and ...`",
        LFGListSearchPanelUtil_CanSelectResult = "called only from a hook that installs when LFGListSearchEntry_OnClick exists",
        LFGListSearchPanel_SignUp = "called only from a hook that installs when LFGListSearchEntry_OnClick exists",
    },
    ["Modules/QoL/QualityOfLife/MoveFrames.lua"] = {
        ChallengesKeystoneFrame = "a frame name in a list, looked up when its addon loads",
        LFDRoleCheckPopup = "a frame name in a list, skipped when the frame is absent",
    },
    ["Modules/Skinning/CharacterPanel/CharacterPanel.lua"] = {
        CharacterFrameTab1 = "an `or` chain that ends at CharacterFrame",
        CharacterFrameTab2 = "an `or` chain that ends at CharacterFrame",
        CharacterFrameTab3 = "an `or` chain that ends at CharacterFrame",
        CharacterModelFrameBackgroundOverlay = "every read is nil-checked",
    },
    ["Modules/Skinning/DarkTheme/Frames/Misc.lua"] = {
        LFDRoleCheckPopup = "skinned only when the frame exists",
    },
}
