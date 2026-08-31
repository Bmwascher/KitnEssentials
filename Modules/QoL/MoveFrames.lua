-- ╔══════════════════════════════════════════════════════════╗
-- ║  MoveFrames.lua                                          ║
-- ║  Module: Move Frames                                     ║
-- ║  Purpose: Let the player left-click and drag almost any  ║
-- ║           Blizzard window anywhere on screen.            ║
-- ║                                                          ║
-- ║  Positions are TEMPORARY BY DESIGN. Nothing is saved,    ║
-- ║  so every window returns to its normal managed spot the  ║
-- ║  next time it opens. That is the requested behaviour,    ║
-- ║  not a missing feature -- do not add persistence.        ║
-- ║                                                          ║
-- ║  ONE-WAY IN PART: disabling unhooks the drag scripts,    ║
-- ║  but the SetMovable / EnableMouse flags already written  ║
-- ║  onto Blizzard frames stay until the next /reload. The   ║
-- ║  config page says so and offers the reload.              ║
-- ║                                                          ║
-- ║  Touching a protected frame from addon code taints it.   ║
-- ║  Both mouse handlers and the frame setup return early    ║
-- ║  under InCombatLockdown() on a protected frame -- those  ║
-- ║  three guards are load-bearing, never remove one.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class MoveFrames: AceModule, AceEvent-3.0, AceHook-3.0
---@field initialized boolean?
local MF = KitnEssentials:NewModule("MoveFrames", "AceEvent-3.0", "AceHook-3.0")

local _G = _G
local pairs, type = pairs, type
local strsplit, wipe = strsplit, wipe
local table_insert = table.insert

local InCombatLockdown, RunNextFrame = InCombatLockdown, RunNextFrame

-- tDeleteItem and GenerateFlatClosure are not in the project's luacheck
-- read_globals allowlist; reach them through _G rather than widen it.
local tDeleteItem = _G.tDeleteItem
local GenerateFlatClosure = _G.GenerateFlatClosure

local C_AddOns_IsAddOnLoaded = C_AddOns.IsAddOnLoaded

local BlizzardFrames = {
    "AddonList",
    "BankFrame",
    "BonusRollFrame",
    "CatalogShopFrame",
    "ChatConfigFrame",
    "CinematicFrame",
    "ContainerFrame1",
    "ContainerFrameCombinedBags",
    "DestinyFrame",
    -- GameMenuFrame REMOVED. Making it movable means
    -- SetMovable/EnableMouse on a protected frame, which taints it, and
    -- Blizzard's Exit Game handler then calls the protected Quit() from
    -- tainted execution:
    --
    --   [KitnEssentials] Protected function violation: callback()
    --   (ADDON_ACTION_FORBIDDEN)
    --
    -- A user could not quit the game until they reloaded. Not worth a
    -- draggable menu.
    "GossipFrame",
    "GroupLootContainer",
    "GuildInviteFrame",
    "GuildRegistrarFrame",
    "HelpFrame",
    "ItemTextFrame",
    "LFDRoleCheckPopup",
    "LFGDungeonReadyDialog",
    "LFGDungeonReadyStatus",
    "LootFrame",
    "MerchantFrame",
    "ModelPreviewFrame",
    "PingSystemTutorial",
    "PVEFrame",
    "PVPReadyDialog",
    "PetitionFrame",
    "QuestFrame",
    "QuestLogPopupDetailFrame",
    "QuickKeybindFrame",
    "RaidBrowserFrame",
    "RaidParentFrame",
    "ReadyCheckFrame",
    "RecruitAFriendRecruitmentFrame",
    "RecruitAFriendRewardsFrame",
    "ReportCheatingDialog",
    "ReportFrame",
    "SettingsPanel",
    "SplashFrame",
    "TabardFrame",
    "TaxiFrame",
    "TradeFrame",
    "TutorialFrame",
    ["FriendsFrame"] = {
        "FriendsFrame.IgnoreListWindow",
    },
    ["DressUpFrame"] = {
        "DressUpFrame.CustomSetDetailsPanel",
        "DressUpFrame.SetSelectionPanel",
    },
    ["MailFrame"] = {
        "SendMailFrame",
        "MailFrameInset",
        ["OpenMailFrame"] = {
            "OpenMailFrame.OpenMailSender",
            "OpenMailFrame.OpenMailFrameInset",
        },
    },
    ["WorldMapFrame"] = {
        "QuestMapFrame",
    },
}

local BlizzardFramesOnDemand = {
    ["Blizzard_AccountStore"] = {
        "AccountStoreFrame",
    },
    ["Blizzard_AchievementUI"] = {
        ["AchievementFrame"] = {
            "AchievementFrame.Header",
            "AchievementFrame.SearchResults",
        },
    },
    ["Blizzard_AnimaDiversionUI"] = {
        ["AnimaDiversionFrame"] = {
            "AnimaDiversionFrame.ScrollContainer",
            "AnimaDiversionFrame.ReinforceProgressFrame",
        },
    },
    ["Blizzard_AlliedRacesUI"] = {
        "AlliedRacesFrame",
    },
    ["Blizzard_ArchaeologyUI"] = {
        "ArchaeologyFrame",
    },
    ["Blizzard_ArtifactUI"] = {
        "ArtifactFrame",
    },
    ["Blizzard_AuctionHouseUI"] = {
        "AuctionHouseFrame",
    },
    ["Blizzard_AzeriteEssenceUI"] = {
        "AzeriteEssenceUI",
    },
    ["Blizzard_AzeriteRespecUI"] = {
        "AzeriteRespecFrame",
    },
    ["Blizzard_AzeriteUI"] = {
        "AzeriteEmpoweredItemUI",
    },
    ["Blizzard_BehavioralMessaging"] = {
        "BehavioralMessagingDetails",
    },
    ["Blizzard_BindingUI"] = {
        "KeyBindingFrame",
    },
    ["Blizzard_BlackMarketUI"] = {
        "BlackMarketFrame",
    },
    ["Blizzard_Calendar"] = {
        ["CalendarFrame"] = {
            "CalendarCreateEventFrame",
            "CalendarCreateEventInviteListScrollFrame",
            "CalendarViewEventFrame",
            "CalendarViewEventFrame.HeaderFrame",
            "CalendarViewEventInviteListScrollFrame",
            "CalendarViewHolidayFrame",
        },
    },
    ["Blizzard_ChallengesUI"] = {
        "ChallengesKeystoneFrame",
    },
    ["Blizzard_Channels"] = {
        "ChannelFrame",
        "CreateChannelPopup",
    },
    ["Blizzard_ClickBindingUI"] = {
        ["ClickBindingFrame"] = {
            "ClickBindingFrame.ScrollBox",
        },
        "ClickBindingFrame.TutorialFrame",
    },
    ["Blizzard_ChromieTimeUI"] = {
        "ChromieTimeFrame",
    },
    ["Blizzard_Collections"] = {
        "CollectionsJournal",
    },
    ["Blizzard_Communities"] = {
        "ClubFinderGuildFinderFrame.RequestToJoinFrame",
        "ClubFinderCommunityAndGuildFinderFrame.RequestToJoinFrame",
        ["CommunitiesFrame"] = {
            "CommunitiesFrame.GuildMemberDetailFrame",
            "CommunitiesFrame.NotificationSettingsDialog",
        },
        "CommunitiesFrame.RecruitmentDialog",
        "CommunitiesSettingsDialog",
        "CommunitiesGuildLogFrame",
        "CommunitiesGuildNewsFiltersFrame",
        "CommunitiesGuildTextEditFrame",
    },
    ["Blizzard_CooldownViewer"] = {
        "CooldownViewerSettings",
    },
    ["Blizzard_Contribution"] = {
        "ContributionCollectionFrame",
    },
    ["Blizzard_CovenantPreviewUI"] = {
        "CovenantPreviewFrame",
    },
    ["Blizzard_CovenantRenown"] = {
        "CovenantRenownFrame",
    },
    ["Blizzard_CovenantSanctum"] = {
        "CovenantSanctumFrame",
    },
    ["Blizzard_DeathRecap"] = {
        "DeathRecapFrame",
    },
    ["Blizzard_DelvesCompanionConfiguration"] = {
        "DelvesCompanionConfigurationFrame",
        "DelvesCompanionAbilityListFrame",
    },
    ["Blizzard_DelvesDifficultyPicker"] = {
        "DelvesDifficultyPickerFrame",
    },
    ["Blizzard_EncounterJournal"] = {
        ["EncounterJournal"] = {
            "EncounterJournal.instanceSelect.ScrollBox",
            "EncounterJournal.encounter.info.overviewScroll",
            "EncounterJournal.encounter.info.detailsScroll",
        },
    },
    ["Blizzard_ExpansionLandingPage"] = {
        "ExpansionLandingPage",
    },
    ["Blizzard_FlightMap"] = {
        "FlightMapFrame",
    },
    ["Blizzard_GarrisonUI"] = {
        "GarrisonBuildingFrame",
        "GarrisonCapacitiveDisplayFrame",
        "GarrisonMissionFrame",
        "GarrisonMonumentFrame",
        "GarrisonRecruiterFrame",
        "GarrisonRecruitSelectFrame",
        "GarrisonShipyardFrame",
        "OrderHallMissionFrame",
        "BFAMissionFrame",
        ["CovenantMissionFrame"] = {
            "CovenantMissionFrame.MissionTab",
            "CovenantMissionFrame.MissionTab.MissionPage",
            "CovenantMissionFrame.MissionTab.MissionPage.CostFrame",
            "CovenantMissionFrame.MissionTab.MissionPage.StartMissionFrame",
            "CovenantMissionFrame.MissionTab.MissionList.MaterialFrame",
            "CovenantMissionFrame.FollowerList.listScroll",
            "CovenantMissionFrame.FollowerList.MaterialFrame",
        },
        ["GarrisonLandingPage"] = {
            "GarrisonLandingPageReportListListScrollFrame",
            "GarrisonLandingPageFollowerListListScrollFrame",
        },
    },
    ["Blizzard_GenericTraitUI"] = {
        ["GenericTraitFrame"] = {
            "GenericTraitFrame.ButtonsParent",
        },
    },
    ["Blizzard_GMChatUI"] = {
        "GMChatStatusFrame",
    },
    ["Blizzard_GuildBankUI"] = {
        "GuildBankFrame",
    },
    ["Blizzard_GuildControlUI"] = {
        "GuildControlUI",
    },
    ["Blizzard_GuildRename"] = {
        "GuildRenameFrame",
    },
    ["Blizzard_HouseList"] = {
        "HouseListFrame",
    },
    ["Blizzard_HousingBulletinBoard"] = {
        "HousingBulletinBoardFrame",
        "HousingInviteResidentFrame",
        "NeighborhoodChangeNameDialog",
    },
    ["Blizzard_HousingCharter"] = {
        "HousingCharterRequestSignatureDialog",
    },
    ["Blizzard_HousingCornerstone"] = {
        "HousingCornerstoneFrame",
        "HousingCornerstoneHouseInfoFrame",
        "HousingCornerstonePurchaseFrame",
        "HousingCornerstoneVisitorFrame",
        "ImportHouseConfirmationDialog",
        "MoveHouseConfirmationDialog",
    },
    ["Blizzard_HousingCreateNeighborhood"] = {
        "HousingCreateCharterNeighborhoodConfirmationFrame",
        "HousingCreateNeighborhoodCharterFrame",
    },
    ["Blizzard_HousingDashboard"] = {
        "HousingDashboardFrame",
    },
    ["Blizzard_HousingHouseFinder"] = {
        "HouseFinderFrame",
    },
    ["Blizzard_HousingHouseSettings"] = {
        "AbandonHouseConfirmationDialog",
        "HousingHouseSettingsFrame",
    },
    ["Blizzard_HousingModelPreview"] = {
        "HousingModelPreviewFrame",
    },
    ["Blizzard_InspectUI"] = {
        "InspectFrame",
    },
    ["Blizzard_IslandsPartyPoseUI"] = {
        "IslandsPartyPoseFrame",
    },
    ["Blizzard_IslandsQueueUI"] = {
        "IslandsQueueFrame",
    },
    ["Blizzard_ItemInteractionUI"] = {
        "ItemInteractionFrame",
    },
    ["Blizzard_ItemSocketingUI"] = {
        "ItemSocketingFrame",
    },
    ["Blizzard_ItemUpgradeUI"] = {
        "ItemUpgradeFrame",
    },
    ["Blizzard_Kiosk"] = {
        "GameKioskSessionStartedDialog",
    },
    ["Blizzard_MacroUI"] = {
        "MacroFrame",
    },
    ["Blizzard_MajorFactions"] = {
        "MajorFactionRenownFrame",
    },
    ["Blizzard_ObliterumUI"] = {
        "ObliterumForgeFrame",
    },
    ["Blizzard_MatchCelebrationPartyPoseUI"] = {
        "MatchCelebrationPartyPoseFrame",
    },
    ["Blizzard_OrderHallUI"] = {
        "OrderHallTalentFrame",
    },
    ["Blizzard_PlayerSpells"] = {
        "HeroTalentsSelectionDialog",
        ["PlayerSpellsFrame"] = {
            "PlayerSpellsFrame.TalentsFrame.ButtonsParent",
        },
    },
    ["Blizzard_PlayerChoice"] = {
        "PlayerChoiceFrame",
    },
    ["Blizzard_Professions"] = {
        "InspectRecipeFrame",
        "ProfessionsFrame.CraftingPage.SchematicForm.QualityDialog",
        "ProfessionsFrame.OrdersPage.OrderView.OrderDetails.SchematicForm.QualityDialog",
        ["ProfessionsFrame"] = {
            "ProfessionsFrame.CraftingPage.CraftingOutputLog",
            "ProfessionsFrame.CraftingPage.CraftingOutputLog.ScrollBox",
        },
    },
    ["Blizzard_ProfessionsBook"] = {
        "ProfessionsBookFrame",
    },
    ["Blizzard_ProfessionsCustomerOrders"] = {
        ["ProfessionsCustomerOrdersFrame"] = {
            "ProfessionsCustomerOrdersFrame.Form",
            "ProfessionsCustomerOrdersFrame.Form.CurrentListings",
        },
    },
    ["Blizzard_PVPMatch"] = {
        "PVPMatchResults",
    },
    ["Blizzard_PVPUI"] = {
        "PVPMatchScoreboard",
    },
    ["Blizzard_RemixArtifactUI"] = {
        ["RemixArtifactFrame"] = {
            "RemixArtifactFrame.Header",
            "RemixArtifactFrame.ButtonsParent",
        },
    },
    ["Blizzard_ScrappingMachineUI"] = {
        "ScrappingMachineFrame",
    },
    ["Blizzard_Soulbinds"] = {
        "SoulbindViewer",
    },
    ["Blizzard_StableUI"] = {
        "StableFrame",
    },
    ["Blizzard_SubscriptionInterstitialUI"] = {
        "SubscriptionInterstitialFrame",
    },
    ["Blizzard_TalentUI"] = {
        "PlayerTalentFrame",
    },
    ["Blizzard_TimeManager"] = {
        "TimeManagerFrame",
    },
    ["Blizzard_TokenUI"] = {
        "CurrencyTransferMenu",
    },
    ["Blizzard_TorghastLevelPicker"] = {
        "TorghastLevelPickerFrame",
    },
    ["Blizzard_TrainerUI"] = {
        "ClassTrainerFrame",
    },
    ["Blizzard_Transmog"] = {
        "TransmogFrame",
    },
    ["Blizzard_UIPanels_Game"] = {
        ["CharacterFrame"] = {
            "CurrencyTransferLog",
            "PaperDollFrame",
            "ReputationFrame",
            "TokenFrame",
            "TokenFramePopup",
        },
    },
    ["Blizzard_VoidStorageUI"] = {
        "VoidStorageFrame",
    },
    ["Blizzard_WarfrontsPartyPoseUI"] = {
        "WarfrontsPartyPoseFrame",
    },
    ["Blizzard_WeeklyRewards"] = {
        "WeeklyRewardsFrame",
    },
}

-- State ----------------------------------------------------------------------

local disabled = {}    -- [frame] = true while movement is suppressed via SetMovable API
local moveTargets = {} -- [handle frame] = frame that actually moves

-- Combat deferral: a minimal local queue drained on PLAYER_REGEN_ENABLED.
local combatQueue = {}
local function AfterCombat(fn)
    if not InCombatLockdown() then
        fn()
        return
    end
    table_insert(combatQueue, fn)
    MF:RegisterEvent("PLAYER_REGEN_ENABLED", "DrainCombatQueue")
end

function MF:DrainCombatQueue()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local queue = combatQueue
    combatQueue = {}
    for _, fn in pairs(queue) do
        fn()
    end
end

-- Resolve "A.B.C" dotted paths or direct frame refs
local function GetFrame(frameOrName)
    local frame
    if frameOrName then
        if frameOrName.GetName then
            frame = frameOrName
        else
            frame = _G
            local path = { strsplit(".", frameOrName) }
            for i = 1, #path do
                frame = frame and frame[path[i]]
            end
        end
    end
    return frame
end

-- Movement handlers ----------------------------------------------------------

function MF:Frame_StartMoving(this, button)
    if InCombatLockdown() and this:IsProtected() then
        return
    end
    local moveTarget = moveTargets[this]
    if button == "LeftButton" and moveTarget and moveTarget:IsMovable() and not disabled[moveTarget] then
        moveTarget:StartMoving()
    end
end

function MF:Frame_StopMoving(this, button)
    if InCombatLockdown() and this:IsProtected() then
        return
    end
    local moveTarget = moveTargets[this]
    if button == "LeftButton" and moveTarget then
        moveTarget:StopMovingOrSizing()
        -- No position save here: moved frames are deliberately temporary.
    end
end

function MF:HandleFrame(this, bindTo)
    local thisFrame = GetFrame(this)
    local bindingTargetFrame = GetFrame(bindTo)

    if not thisFrame or moveTargets[thisFrame] then
        return
    end

    if InCombatLockdown() and thisFrame:IsProtected() then
        AfterCombat(function()
            self:HandleFrame(this, bindTo)
            -- No reposition-from-saved-coords pass: nothing is remembered.
        end)
        return
    end

    thisFrame:SetMovable(true)
    thisFrame:SetClampedToScreen(true)
    thisFrame:EnableMouse(true)
    moveTargets[thisFrame] = bindingTargetFrame or thisFrame

    self:SecureHookScript(thisFrame, "OnMouseDown", "Frame_StartMoving")
    self:SecureHookScript(thisFrame, "OnMouseUp", "Frame_StopMoving")
    -- No SetPoint hook on the move target: that is persistence machinery.
end

function MF:HandleFramesWithTable(frameTable, parent)
    for key, value in pairs(frameTable) do
        if type(key) == "number" and type(value) == "string" then
            self:HandleFrame(value, parent)
        elseif type(key) == "string" and type(value) == "table" then
            self:HandleFrame(key, parent)
            self:HandleFramesWithTable(value, key)
        end
    end
end

function MF:HandleAddon(_, addon)
    local frameTable = BlizzardFramesOnDemand[addon]
    if not frameTable then
        return
    end

    self:HandleFramesWithTable(frameTable)

    -- Frame-specific fixes
    AfterCombat(function()
        if addon == "Blizzard_EncounterJournal" then
            local replacement = function(rewardFrame)
                if rewardFrame.data then
                    _G.EncounterJournalTooltip:ClearAllPoints()
                end
                self.hooks.AdventureJournal_Reward_OnEnter(rewardFrame)
            end
            self:RawHook("AdventureJournal_Reward_OnEnter", replacement, true)
            self:RawHookScript(_G.EncounterJournal.suggestFrame.Suggestion1.reward, "OnEnter", replacement)
            self:RawHookScript(_G.EncounterJournal.suggestFrame.Suggestion2.reward, "OnEnter", replacement)
            self:RawHookScript(_G.EncounterJournal.suggestFrame.Suggestion3.reward, "OnEnter", replacement)
        elseif addon == "Blizzard_Communities" then
            local dialog = _G.CommunitiesFrame.NotificationSettingsDialog
            if dialog then
                dialog:ClearAllPoints()
                dialog:SetAllPoints()
            end
        elseif addon == "Blizzard_PlayerChoice" and _G.PlayerChoiceFrame then
            -- These three go through AceHook, never a raw HookScript, which
            -- cannot be undone. That way module disable
            -- removes them and a re-enable does not stack a second copy.
            self:SecureHookScript(_G.PlayerChoiceFrame, "OnHide", function()
                if not InCombatLockdown() or not _G.PlayerChoiceFrame:IsProtected() then
                    _G.PlayerChoiceFrame:ClearAllPoints()
                end
            end)
        elseif addon == "Blizzard_PlayerSpells" and _G.HeroTalentsSelectionDialog and _G.PlayerSpellsFrame then
            local function startStopMoving(frame)
                if InCombatLockdown() and frame:IsProtected() then
                    return
                end
                local backup = frame:IsMovable()
                frame:SetMovable(true)
                frame:StartMoving()
                frame:StopMovingOrSizing()
                frame:SetMovable(backup)
            end

            startStopMoving(_G.HeroTalentsSelectionDialog)
            self:SecureHookScript(_G.PlayerSpellsFrame, "OnShow", function(frame)
                startStopMoving(frame)
                RunNextFrame(GenerateFlatClosure(startStopMoving, frame))
            end)
            self:SecureHookScript(_G.HeroTalentsSelectionDialog, "OnShow", function(frame)
                startStopMoving(frame)
                RunNextFrame(GenerateFlatClosure(startStopMoving, frame))
            end)
        end
    end)
end

-- Public API ------------------------------------------------------------------

---Whether the module is active (BlizzMove/MoveAnything defer counts as off)
function MF:IsRunning()
    return self.db and self.db.Enabled == true and not self.StopRunning
end

---Temporarily suppress/allow movement of a handled frame
function MF:SetMovable(frame, movable)
    if not self:IsRunning() then
        return
    end
    local targetFrame = GetFrame(frame)
    if not targetFrame then
        return
    end
    disabled[targetFrame] = not movable
end

-- Lifecycle -------------------------------------------------------------------

function MF:UpdateDB()
    if KE.db and KE.db.profile then
        self.db = KE.db.profile.MoveFrames
    end
end

function MF:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(self.db and self.db.Enabled == true)
end

function MF:OnEnable()
    self:UpdateDB()
    if not self.db or self.db.Enabled ~= true then return end
    if self.initialized then return end

    -- Defer to dedicated movers.
    if C_AddOns_IsAddOnLoaded("BlizzMove") then
        self.StopRunning = "BlizzMove"
        return
    end
    if C_AddOns_IsAddOnLoaded("MoveAnything") then
        self.StopRunning = "MoveAnything"
        return
    end

    self.initialized = true

    -- Trade Skill Master special handling, always on and not an option: TSM
    -- replaces the merchant frame wholesale, so excluding it is strictly
    -- correct whenever TSM is present.
    if C_AddOns_IsAddOnLoaded("TradeSkillMaster") then
        tDeleteItem(BlizzardFrames, "MerchantFrame")
    end

    -- Mail inset reparent. Not an ElvUI-only fix -- the insets are parented
    -- oddly and drag the wrong frame without it.
    if _G.MailFrameInset then
        _G.OpenMailFrameInset:SetParent(_G.OpenMailFrame)
        _G.MailFrameInset:SetParent(_G.MailFrame)
    end

    -- Always-loaded Blizzard frames
    self:HandleFramesWithTable(BlizzardFrames)

    -- Legacy PVP frame guard (nil on Midnight; ported for parity)
    if _G.BattlefieldFrame and _G.PVPParentFrame then
        _G.BattlefieldFrame:SetParent(_G.PVPParentFrame)
        _G.BattlefieldFrame:ClearAllPoints()
        _G.BattlefieldFrame:SetAllPoints()
    end

    -- Load-on-demand Blizzard frames
    self:RegisterEvent("ADDON_LOADED", "HandleAddon")
    for addon in pairs(BlizzardFramesOnDemand) do
        if C_AddOns_IsAddOnLoaded(addon) then
            self:HandleAddon(nil, addon)
        end
    end

    -- Blizzard container anchoring fights the mover; clear on layout
    -- (inert while Baganator replaces the bags).
    if _G.ContainerFrameSettingsManager then
        local GetBagsShown = _G.ContainerFrameSettingsManager.GetBagsShown
        self:SecureHook(_G.ContainerFrameSettingsManager, "GetBagsShown", function()
            for _, bag in pairs(GetBagsShown(_G.ContainerFrameSettingsManager) or {}) do
                bag:ClearAllPoints()
            end
        end)
    end
end

function MF:OnDisable()
    -- AceHook unhooks everything automatically on module disable. Wipe
    -- the bookkeeping so a mid-session re-enable rebuilds the hooks
    -- (HandleFrame early-returns on populated moveTargets otherwise).
    -- SetMovable / EnableMouse state on Blizzard frames persists until
    -- reload -- the GUI flags a reload prompt on disable.
    wipe(moveTargets)
    wipe(disabled)
    wipe(combatQueue)
    self.initialized = nil
    self.StopRunning = nil
end
