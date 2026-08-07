-- Luacheck configuration for KitnEssentials
std = "lua51"
max_line_length = false
exclude_files = {
    "Libs/**",
    ".wow-api-reference/**",
    "References/**",
    "dev/Annotations/**",   -- wowlua-ls ---@meta stubs (local-only, not real code)
    ".claude/**",           -- Claude Code worktrees/tooling: a parallel session's
                            -- registered worktree is a full repo copy — sweeping it
                            -- blocked a main push (2026-07-24, 233 foreign warnings)
}

-- Headless test harness (busted, not in-game). These files run under a desktop
-- Lua + busted, so allow busted's test globals and the luafilesystem module the
-- smoke spec walks the tree with. Never shipped (pkgmeta-ignored).
files["dev/spec"] = {
    std = "lua51+busted",
    read_globals = { "lfs" },
}

-- Suppress legitimate patterns:
--  212/_      — unused argument with _ name (discard)
--  212/self   — unused self in methods
--  212/event  — unused event arg in OnEvent callbacks (common WoW pattern)
--  212/msg    — unused msg arg in chat/popup callbacks
--  212/editbox — unused editbox arg in OnEnterPressed/OnTextChanged
--  212/width  — unused width/height in OnSizeChanged callbacks
--  212/height
--  432/self   — inner closure shadowing outer self (widget callback pattern)
--  431/CP     — widget callback re-fetches module fresh, shadowing outer CP
--  431/LR     — LootRoll preview callback re-fetches module fresh, shadowing outer LR
ignore = {
    "212/_", "212/self", "212/event", "212/msg", "212/editbox", "212/width", "212/height",
    "212/timeToFade", "212/endAlpha", "212/loopCallback",     -- UIFrameFade callback signature
    "212/elapsed",                                            -- OnUpdate callback signature
    "212/userInput",                                          -- OnTextChanged callback signature
    "212/r", "212/g", "212/b", "212/a",                       -- Color picker callback signature
    "212/encounterID", "212/encounterName",                   -- ENCOUNTER_START/END signature
    "212/difficultyID", "212/groupSize",
    "212/scrollChild",                                        -- RegisterContent callback signature
    "212/KE",                                                  -- bootstrap guard arg (GetModule files)
    "212/triggerId", "212/addon",                             -- DungeonTimers/Ace addon hooks
    "212/wrapOn",                                             -- KEText format helper
    "212/rel",                                                -- SetPoint(point, rel, ...) mock signature
    "432/self",
    "431/CP",                                                 -- widget callback re-fetches module fresh
    "431/LR",                                                 -- LootRoll preview callback re-fetches module fresh
}

-- Globals this addon sets
globals = {
    "KitnEssentialsDB",
    "KitnEssentialsOptimizeDB",
    "KitnCommands",
    "KitnEssentialsAPI",
    "KitnSlashLines",

    -- DEBUG_LEAK tracers (GUI-Core.lua RefreshContent) — /run-readable
    -- rebuild-loop counters for the 2026-06-12 frame-leak hunt
    "KE_GUI_REFRESH_COUNT",
    "KE_GUI_REFRESH_ITEM",
    "KE_GUI_ORPHAN_COUNT",

    -- Dev/debug handle to the private addon namespace (Core/Main.lua) —
    -- /run macro chunks can't reach select(2, ...) locals
    "KITNESSENTIALS_NS",

    -- Slash command registration (WoW convention: SlashCmdList[] + SLASH_*N)
    "SlashCmdList",
    "SLASH_KITNESSENTIALS1", "SLASH_KITNESSENTIALS2", "SLASH_KITNESSENTIALS3",
    "SLASH_KE_CDM1", "SLASH_KE_CDM2",
    "SLASH_KE_RL1",

    -- Blizzard tables/frames this addon WRITES fields on (dialog
    -- registration, skinning fade-state, EditMode shims). Listed here
    -- instead of read_globals because luacheck flags field writes on
    -- read-only globals.
    "StaticPopupDialogs",
    "SetTooltipMoney",                  -- replaced global fn (Tooltips skin)
    "AuctionHouseFrame", "ProfessionsCustomerOrdersFrame",
    "ActionStatus", "ZoneTextFrame", "SubZoneTextFrame",
    "PVPArenaTextString", "PVPInfoTextString",
    "CompactRaidFrameManager",
    "GameTooltipDefaultContainer",
}

-- WoW API globals this addon reads
read_globals = {
    -- Lua standard extensions in WoW
    "strsplit", "strjoin", "strtrim", "format", "tinsert", "tremove",
    "wipe", "CopyTable", "tContains", "strsub", "strlen", "strupper",
    "strlower", "strmatch", "nop", "time", "date",

    -- Core math (WoW re-exports)
    "ceil", "floor", "min", "max", "abs", "sort",

    -- Frame and UI
    "CreateFrame", "CreateFont", "CreateColor", "UIParent", "Settings",
    "CreateAbbreviateConfig",
    "CreateFramePool", "CreateTexturePool",
    "BackdropTemplateMixin", "Mixin", "CreateFromMixins", "CreateAndInitFromMixin",
    "ImportDataStreamMixin",
    "MapCanvasPinMixin", "MapCanvasDataProviderMixin",
    "hooksecurefunc",
    "ShowUIPanel", "HideUIPanel", "UIParentLoadAddOn",
    "WorldFrame",
    "MouseIsOver", "GetMouseFoci", "GetMouseFocus",
    "GetPhysicalScreenSize", "GetCursorPosition",
    "RunNextFrame",
    "IsModifierKeyDown",
    "EventUtil",

    -- Tutorial / help-plate suppression
    "MainHelpPlateButtonMixin", "HelpTip", "SetCVarBitfield", "EnumerateFrames",
    "HelpPlate", "HelpPlateTooltip",

    -- Trainer
    "ClassTrainerFrame", "ClassTrainerTrainButton",
    "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetNumTrainerServices",
    "BuyTrainerService",

    -- Enums and constants
    "Enum", "Constants", "CurveConstants",
    "ACCEPT", "CANCEL", "CLOSE",
    "ENCHANTED_TOOLTIP_LINE",
    "FACTION_ALLIANCE", "FACTION_HORDE",
    "BASE_MOVEMENT_SPEED",
    "NUM_BAG_FRAMES", "NUM_CHAT_WINDOWS",
    "RAID_CLASS_COLORS", "FACTION_BAR_COLORS", "GetClassColor", "CLASS_ICON_TCOORDS",
    "STANDARD_TEXT_FONT",
    "NORMAL_FONT_COLOR", "NORMAL_FONT_COLOR_CODE",

    -- Unit functions
    "UnitHealth", "UnitHealthMax", "UnitHealthPercent",
    "UnitPower", "UnitPowerMax", "UnitPowerPercent",
    "UnitName", "UnitFullName", "UnitLevel", "UnitEffectiveLevel", "UnitClass", "UnitRace", "GetUnitName",
    "UnitPVPName", "UnitRealmRelationship", "UnitIsAFK", "UnitIsDND",
    "GetCreatureDifficultyColor",
    "UnitGUID", "UnitExists", "UnitIsDead", "UnitIsUnit", "UnitTokenFromGUID",
    "UnitGroupRolesAssigned",
    "UnitGetTotalAbsorbs",
    "AbbreviateNumbers", "AbbreviateLargeNumbers", "BreakUpLargeNumbers",
    "UnitNameFromGUID", "UnitNameUnmodified", "UnitClassFromGUID",
    "UnitIsPlayer", "UnitIsConnected", "UnitIsDeadOrGhost", "UnitIsFeignDeath",
    "UnitReaction", "UnitInPartyIsAI",
    "UnitIsBossMob", "UnitIsTapDenied", "UnitIsGroupLeader",
    "UnitHasVehicleUI", "UnitInVehicle", "UnitOnTaxi",
    "UnitAffectingCombat", "UnitCanAssist", "UnitCanAttack",
    "UnitInParty", "UnitInRaid", "UnitIsVisible",
    "UnitFactionGroup", "UnitSpellHaste", "UnitStat",
    "UnitClassification", "UnitSex", "UnitPowerType",
    "UnitPosition",
    "InCombatLockdown",

    -- Totem functions
    "GetTotemInfo", "GetTotemDuration", "GetNumTotemSlots", "MAX_TOTEMS", "STANDARD_TOTEM_PRIORITIES",

    -- Casting (12.0 Duration-based)
    "UnitCastingInfo", "UnitChannelInfo",
    "UnitCastingDuration", "UnitChannelDuration",
    "UnitEmpoweredChannelDuration",
    "UnitIsSpellTarget", "UnitSpellTargetName", "UnitSpellTargetClass",
    "PlayerIsSpellTarget",
    "UnitShouldDisplaySpellTargetName",
    "C_CastingInfo",

    -- Inspect
    "CanInspect", "NotifyInspect", "GetInspectSpecialization",

    -- Specialization
    "GetSpecialization", "GetSpecializationInfo", "GetSpecializationRole",
    "GetSpecializationInfoByID", "GetNumClasses", "GetSpecializationInfoForClassID",
    "C_CreatureInfo",

    -- Instance / Group
    "IsInInstance", "GetInstanceInfo", "GetMinimapZoneText",
    "IsInRaid", "IsInGroup", "IsInGuild", "GetNumGroupMembers", "GetRaidRosterInfo", "GetRaidDifficultyID",
    "IsWargame", "SendChatMessage", "LE_PARTY_CATEGORY_INSTANCE", "LE_PARTY_CATEGORY_HOME",

    -- Auras
    "C_UnitAuras", "AuraUtil",

    -- Spell
    "C_Spell", "C_SpellBook",
    "IsPlayerSpell", "IsSpellKnown", "IsSpellKnownOrOverridesKnown",
    "C_SpellActivationOverlay",

    -- Secret Values (12.0)
    "issecretvalue", "issecrettable", "canaccesstable", "canaccessvalue",
    "C_CurveUtil", "C_DurationUtil", "C_StringUtil",
    "C_Secrets", "C_RestrictedActions",

    -- Timer
    "C_Timer",

    -- Sound
    "PlaySoundFile", "StopSound", "PlaySound",
    "C_Sound",

    -- Text-to-Speech
    "C_VoiceChat", "C_TTSSettings",
    "TextToSpeech_GetSelectedVoice",

    -- Addon management
    "GetAddOnMemoryUsage", "UpdateAddOnMemoryUsage",
    "GetAddOnCPUUsage", "UpdateAddOnCPUUsage",
    "GetFrameCPUUsage", "ResetCPUUsage",
    "C_AddOns", "C_AddOnProfiler",

    -- CVar
    "GetCVar", "SetCVar", "C_CVar",

    -- Map / Waypoint
    "C_Map",
    "C_SuperTrack",
    "C_Texture",
    "UiMapPoint",
    "EventRegistry",
    "WorldMapFrame",

    -- Professions
    "GetProfessions", "GetProfessionInfo",

    -- Item / Container
    "C_Item", "C_Container", "Item", "ItemLocation",
    "GetItemInfo", "GetItemInfoInstant", "GetItemSpell", "GetItemCount",
    "GetInventoryItemID", "GetInventoryItemDurability", "GetInventoryItemTexture", "GetInventoryItemLink",
    "GetDetailedItemLevelInfo",
    "GetInventoryItemQuality", "GetItemQualityColor", "ITEM_QUALITY_COLORS",
    "GetItemGem", -- deprecated compat shim (C_Item.GetItemGem), Blizzard_DeprecatedItemScript
    "GetWeaponEnchantInfo",
    "RegisterAttributeDriver",
    "ClearCursor", "ResetCursor", "SetCursor",
    "NUM_BAG_SLOTS",

    -- Collections (Mounts / Pets / Toys / Heirlooms)
    "PlayerHasToy", "C_MountJournal", "C_Heirloom", "C_TransmogCollection",
    "C_PetJournal", "C_ToyBox", "C_ToyBoxInfo", "ToyBox",
    "LE_MOUNT_JOURNAL_FILTER_COLLECTED", "LE_MOUNT_JOURNAL_FILTER_UNUSABLE",
    "CollectionsMicroButton", "CollectionsMicroButton_SetAlertShown",
    "MainMenuMicroButton_HideAlert",
    "COLLECTION_UNOPENED_PLURAL", "COLLECTION_UNOPENED_SINGULAR",

    -- Auras (cancel path)
    "CancelUnitBuff",

    -- Gem Socketing
    "C_ItemSocketInfo", "SocketInventoryItem", "AcceptSockets", "CloseSocketInfo",

    -- PaperDoll layout
    "PaperDollFrame_SetLevel", "PaperDollFrame_UpdateStats",
    "PanelTemplates_TabResize",
    "InspectPaperDollItemSlotButton_Update", "InspectPaperDollFrame_SetLevel",
    "InspectPaperDollItemsFrame", "C_PaperDollInfo",

    -- Loot
    "GetLootRollItemLink", "GetLootRollItemInfo", "RollOnLoot", "ConfirmLootRoll",
    "BonusRollFrame", "BonusRollFrame_StartBonusRoll", "GetLootRollTimeLeft",
    "NEED", "GREED", "PASS", "TRANSMOGRIFY", "ROLL_DISENCHANT",
    "CloseLoot", "LootSlot", "LootSlotHasItem", "GetNumLootItems",
    "GetLootSlotInfo", "GetLootSlotLink", "IsFishingLoot",
    "CursorUpdate", "CursorOnUpdate", "UnitIsFriend", "C_TradeSkillUI",

    -- Resurrection
    "AcceptResurrect", "IsEncounterInProgress",

    -- Encounters
    "C_InstanceEncounter",

    -- Equipment Slots
    "INVSLOT_HEAD", "INVSLOT_NECK", "INVSLOT_SHOULDER", "INVSLOT_BACK", "INVSLOT_CHEST",
    "INVSLOT_WRIST", "INVSLOT_WAIST", "INVSLOT_LEGS", "INVSLOT_FEET",
    "INVSLOT_FINGER1", "INVSLOT_FINGER2", "INVSLOT_MAINHAND", "INVSLOT_OFFHAND",

    -- Level / Expansion
    "GetExpansionForLevel", "IsLevelAtEffectiveMaxLevel",

    -- Currency / Money
    "C_CurrencyInfo",
    "GetMoney", "GetCoinTextureString",

    -- Tooltip
    "GameTooltip", "GameTooltip_Hide", "GameTooltip_ShowCompareItem",
    "TooltipDataProcessor",
    "C_TooltipInfo",

    -- Static Popups
    "StaticPopup_Show", "StaticPopup_Hide", "StaticPopup_FindVisible",

    -- Error message strings (GlobalStrings.lua)
    "ERR_INV_FULL", "ERR_QUEST_LOG_FULL", "ERR_RAID_GROUP_ONLY",
    "ERR_PARTY_LFG_BOOT_LIMIT", "ERR_PARTY_LFG_BOOT_DUNGEON_COMPLETE",
    "ERR_PARTY_LFG_BOOT_IN_COMBAT", "ERR_PARTY_LFG_BOOT_IN_PROGRESS",
    "ERR_PARTY_LFG_BOOT_LOOT_ROLLS", "ERR_PARTY_LFG_TELEPORT_IN_COMBAT",
    "ERR_PET_SPELL_DEAD", "ERR_PLAYER_DEAD",
    "SPELL_FAILED_TARGET_NO_POCKETS", "ERR_ALREADY_PICKPOCKETED",
    "ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S",

    -- Context menus (Blizzard_Menu, 11.0+ taint-safe menu API)
    "MenuUtil",

    -- Fading
    "UIFrameFade", "UIFrameFadeIn", "UIFrameFadeOut", "UIFrameFadeRemoveFrame",

    -- Chat
    "C_ChatInfo",

    -- Color
    "C_ClassColor",

    -- Player Info
    "C_PlayerInfo", "GetPlayerInfoByGUID",
    "PlayerUtil",
    "GetRealmName", "GetNormalizedRealmName", "Ambiguate",

    -- Talent / Class
    "C_ClassTalents", "C_SpecializationInfo", "C_Traits",

    -- Mythic+ / Challenges
    "C_ChallengeMode", "C_MythicPlus", "C_ScenarioInfo", "C_Scenario",

    -- PvP
    "C_PvP",

    -- Blizzard UI frames (read-only from addons)
    "TotemFrame",

    -- Pet
    "GetPetActionInfo", "PetHasActionBar", "HasPetSpells",
    "C_PetBattles",

    -- Macro
    "CreateMacro", "EditMacro", "GetMacroIndexByName",
    "GetMacroSpell", "GetNumMacros", "MAX_ACCOUNT_MACROS",

    -- Keybinding
    "GetBindingKey", "SetBinding", "SaveBindings", "GetCurrentBindingSet",

    -- Secure handling
    "RegisterStateDriver", "UnregisterStateDriver",
    "SetOverrideBindingClick", "ClearOverrideBindings",
    "SecureCmdOptionParse",
    "SecureHandlerExecute", "SecureHandlerWrapScript",

    -- Shapeshifting / Stance
    "GetNumShapeshiftForms", "GetShapeshiftForm", "GetShapeshiftFormInfo",

    -- Loot / Spec
    "GetLootSpecialization", "GetAverageItemLevel",

    -- Quest
    "AcceptQuest", "CompleteQuest", "IsQuestCompletable",
    "GetQuestReward", "GetNumQuestChoices", "GetQuestID",
    "GetActiveTitle", "GetNumActiveQuests",
    "GetNumAvailableQuests", "SelectActiveQuest", "SelectAvailableQuest",
    "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard",
    "C_QuestLog", "C_QuestInfoSystem",

    -- Guild Bank
    "GetGuildBankItemLink", "GetGuildBankTabInfo",
    "GetGuildBankWithdrawMoney", "GetNumGuildBankTabs",
    "CanGuildBankRepair", "SplitGuildBankItem",
    "GetGuildInfo",

    -- Merchant
    "CanMerchantRepair", "RepairAllItems", "GetRepairAllCost",
    "C_MerchantFrame",

    -- Combat logging
    "LoggingCombat",

    -- Damage meter (12.0 in-client meter API)
    "C_DamageMeter",
    "C_DeathRecap",

    -- Gossip
    "C_GossipInfo",

    -- Cursor
    "C_Cursor",

    -- Garrison / Order Hall
    "C_Garrison",

    -- Encoding
    "C_EncodingUtil",

    -- Party
    "C_PartyInfo",
    "CancelDuel",

    -- Action bar
    "HasAction", "GetActionText", "C_ActionBar",

    -- Raid Markers
    "SetRaidTarget", "IsRaidMarkerActive",
    "GetRaidTargetIndex", "SetRaidTargetIconTexture",

    -- Misc API
    "IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown", "IsMetaKeyDown",
    "IsMouseButtonDown", "IsMounted", "IsModifiedClick",
    "ResetInstances",
    "GetServerTime", "GetTimePreciseSec", "GetLocale",
    "ReloadUI", "print",
    "GameMovieFinished", "CinematicFrame_CancelCinematic",
    "Evoker", -- Evoker-specific
    "GetUnitEmpowerMinHoldTime", "GetUnitEmpowerHoldAtMaxTime",
    "FrameStackTooltip_Toggle",
    "debugprofilestop", "debugstack", "geterrorhandler",

    -- C_UI / C_NamePlate
    "C_NamePlate",
    "C_SeasonInfo",
    "C_DateAndTime",

    -- Libraries
    "LibStub",

    -- BigWigs (optional dependency)
    "BigWigs", "BigWigsLoader",

    -- ElvUI (optional dependency)
    "ElvUI",

    -- WeakAuras (third-party, nil-checked for detection)
    "WeakAuras",

    -- Addon object
    "KitnEssentials",

    -- Time
    "GetTime", "GetWorldElapsedTime",

    -- -------------------------------------------------------
    -- Blizzard UI Frames (read for skinning / anchoring)
    -- -------------------------------------------------------
    "AchievementObjectiveTracker",
    "ActionButtonSpellAlertManager",
    "BagsBar",
    "BonusObjectiveTracker",
    "BuffFrame", "DebuffFrame",
    "CampaignQuestObjectiveTracker",
    "CharacterFrame", "CharacterModelScene", "CharacterModelFrameBackgroundOverlay",
    "CharacterStatsPane", "CharacterLevelText", "CharacterFrameTitleText",
    "CharacterFrameTab1", "CharacterFrameTab2", "CharacterFrameTab3",
    "ChallengesKeystoneFrame",
    "ChatBubbleFont",
    "ColorPickerFrame",
    "InspectFrame",
    "EditModeManagerFrame",
    "EventToastManagerFrame",
    "ExternalDefensivesFrame",
    "LFDRoleCheckPopup", "LFDRoleCheckPopupAcceptButton",
    "LFDRoleCheckPopupRoleButtonTank", "LFDRoleCheckPopupRoleButtonHealer", "LFDRoleCheckPopupRoleButtonDPS",
    "LFGListApplicationDialog",
    "ItemSocketingFrame",
    "MainMenuMicroButton",
    "MonthlyActivitiesObjectiveTracker",
    "ObjectiveTrackerFrame", "ObjectiveTrackerHeaderFont", "ObjectiveTrackerLineFont",
    "PaperDollFrame",
    "PetActionBar",
    "PlayerCastingBarFrame",
    "ProfessionsRecipeTracker",
    "QuestObjectiveTracker",
    "QueueStatusFrame",
    "ScenarioObjectiveTracker",
    "SettingsPanel",
    "StanceBar",
    "SubZoneTextString",
    "UIErrorsFrame",
    "WorldQuestObjectiveTracker",
    "ZoneTextString",

    -- -------------------------------------------------------
    -- Third-party addon frames (nil-checked for detection)
    -- -------------------------------------------------------
    "Ayije_CastBar",
    "BCDM_CastBar",
    "ElvUI_SpellBookTooltip",
    "UUF_Player_CastBar",

    -- Ready Check frames
    "ReadyCheckListenerFrame",
    "ReadyCheckFrame",
}
