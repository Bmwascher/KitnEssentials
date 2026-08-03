-- Tier 1/2: Modules/QoL/MoveFrames.lua's path resolver, its two frame data
-- tables, and its two public methods (IsRunning, SetMovable). The tables are
-- reached through the same debug.getupvalue seam the other loaders use, never
-- exported from the module. GetFrame is exercised against the REAL _G (the
-- module captures `local _G = _G` at load time, so a stub table swapped in
-- would not be the same object the module walks) -- tests assign directly
-- onto _G and clean up afterward.
local L = require("dev.spec._ke_loader")

-- Structure-preserving serializer, exactly as specified: a numeric key
-- holding a string is a leaf frame name; a string key holding a table is a
-- named parent, serialized as name{child,child}. table.sort makes the output
-- deterministic despite pairs() order being undefined.
local function serialize(t)
    local parts = {}
    for k, v in pairs(t) do
        if type(k) == "number" and type(v) == "string" then
            parts[#parts + 1] = v
        elseif type(k) == "string" and type(v) == "table" then
            parts[#parts + 1] = k .. "{" .. serialize(v) .. "}"
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- Collects frame names per the counting rule. skipTopStringKeys is true only
-- for the very top level of BlizzardFramesOnDemand, where string keys are
-- ADDON names rather than frame names and must not be collected.
local function collectNames(t, skipTopStringKeys, names)
    for k, v in pairs(t) do
        if type(k) == "number" and type(v) == "string" then
            names[#names + 1] = v
        elseif type(k) == "string" and type(v) == "table" then
            if not skipTopStringKeys then
                names[#names + 1] = k
            end
            collectNames(v, false, names)
        end
    end
end

-- Recursively checks that every numeric key holds a string and every string
-- key holds a table, everywhere in t.
local function structuralViolations(t, path, violations)
    for k, v in pairs(t) do
        if type(k) == "number" then
            if type(v) ~= "string" then
                violations[#violations + 1] = path .. "[" .. tostring(k) .. "] is a " .. type(v) .. ", not a string"
            end
        elseif type(k) == "string" then
            if type(v) ~= "table" then
                violations[#violations + 1] = path .. "." .. k .. " is a " .. type(v) .. ", not a table"
            else
                structuralViolations(v, path .. "." .. k, violations)
            end
        end
    end
end

-- Whether target appears anywhere in t, either as a numeric-keyed leaf string
-- or as a string key naming a nested table.
local function containsName(t, target)
    for k, v in pairs(t) do
        if type(k) == "number" and type(v) == "string" and v == target then
            return true
        elseif type(k) == "string" and type(v) == "table" then
            if k == target or containsName(v, target) then
                return true
            end
        end
    end
    return false
end

local EXPECTED_ALWAYS = table.concat({
    "AddonList,BankFrame,BonusRollFrame,CatalogShopFrame,ChatConfigFrame,",
    "CinematicFrame,ContainerFrame1,ContainerFrameCombinedBags,DestinyFra",
    "me,DressUpFrame{DressUpFrame.CustomSetDetailsPanel,DressUpFrame.SetS",
    "electionPanel},FriendsFrame{FriendsFrame.IgnoreListWindow},GossipFra",
    "me,GroupLootContainer,GuildInviteFrame,GuildRegistrarFrame,HelpFrame",
    ",ItemTextFrame,LFDRoleCheckPopup,LFGDungeonReadyDialog,LFGDungeonRea",
    "dyStatus,LootFrame,MailFrame{MailFrameInset,OpenMailFrame{OpenMailFr",
    "ame.OpenMailFrameInset,OpenMailFrame.OpenMailSender},SendMailFrame},",
    "MerchantFrame,ModelPreviewFrame,PVEFrame,PVPReadyDialog,PetitionFram",
    "e,PingSystemTutorial,QuestFrame,QuestLogPopupDetailFrame,QuickKeybin",
    "dFrame,RaidBrowserFrame,RaidParentFrame,ReadyCheckFrame,RecruitAFrie",
    "ndRecruitmentFrame,RecruitAFriendRewardsFrame,ReportCheatingDialog,R",
    "eportFrame,SettingsPanel,SplashFrame,TabardFrame,TaxiFrame,TradeFram",
    "e,TutorialFrame,WorldMapFrame{QuestMapFrame}",
}, "")

local EXPECTED_ONDEMAND = table.concat({
    "Blizzard_AccountStore{AccountStoreFrame},Blizzard_AchievementUI{Achi",
    "evementFrame{AchievementFrame.Header,AchievementFrame.SearchResults}",
    "},Blizzard_AlliedRacesUI{AlliedRacesFrame},Blizzard_AnimaDiversionUI",
    "{AnimaDiversionFrame{AnimaDiversionFrame.ReinforceProgressFrame,Anim",
    "aDiversionFrame.ScrollContainer}},Blizzard_ArchaeologyUI{Archaeology",
    "Frame},Blizzard_ArtifactUI{ArtifactFrame},Blizzard_AuctionHouseUI{Au",
    "ctionHouseFrame},Blizzard_AzeriteEssenceUI{AzeriteEssenceUI},Blizzar",
    "d_AzeriteRespecUI{AzeriteRespecFrame},Blizzard_AzeriteUI{AzeriteEmpo",
    "weredItemUI},Blizzard_BehavioralMessaging{BehavioralMessagingDetails",
    "},Blizzard_BindingUI{KeyBindingFrame},Blizzard_BlackMarketUI{BlackMa",
    "rketFrame},Blizzard_Calendar{CalendarFrame{CalendarCreateEventFrame,",
    "CalendarCreateEventInviteListScrollFrame,CalendarViewEventFrame,Cale",
    "ndarViewEventFrame.HeaderFrame,CalendarViewEventInviteListScrollFram",
    "e,CalendarViewHolidayFrame}},Blizzard_ChallengesUI{ChallengesKeyston",
    "eFrame},Blizzard_Channels{ChannelFrame,CreateChannelPopup},Blizzard_",
    "ChromieTimeUI{ChromieTimeFrame},Blizzard_ClickBindingUI{ClickBinding",
    "Frame.TutorialFrame,ClickBindingFrame{ClickBindingFrame.ScrollBox}},",
    "Blizzard_Collections{CollectionsJournal},Blizzard_Communities{ClubFi",
    "nderCommunityAndGuildFinderFrame.RequestToJoinFrame,ClubFinderGuildF",
    "inderFrame.RequestToJoinFrame,CommunitiesFrame.RecruitmentDialog,Com",
    "munitiesFrame{CommunitiesFrame.GuildMemberDetailFrame,CommunitiesFra",
    "me.NotificationSettingsDialog},CommunitiesGuildLogFrame,CommunitiesG",
    "uildNewsFiltersFrame,CommunitiesGuildTextEditFrame,CommunitiesSettin",
    "gsDialog},Blizzard_Contribution{ContributionCollectionFrame},Blizzar",
    "d_CooldownViewer{CooldownViewerSettings},Blizzard_CovenantPreviewUI{",
    "CovenantPreviewFrame},Blizzard_CovenantRenown{CovenantRenownFrame},B",
    "lizzard_CovenantSanctum{CovenantSanctumFrame},Blizzard_DeathRecap{De",
    "athRecapFrame},Blizzard_DelvesCompanionConfiguration{DelvesCompanion",
    "AbilityListFrame,DelvesCompanionConfigurationFrame},Blizzard_DelvesD",
    "ifficultyPicker{DelvesDifficultyPickerFrame},Blizzard_EncounterJourn",
    "al{EncounterJournal{EncounterJournal.encounter.info.detailsScroll,En",
    "counterJournal.encounter.info.overviewScroll,EncounterJournal.instan",
    "ceSelect.ScrollBox}},Blizzard_ExpansionLandingPage{ExpansionLandingP",
    "age},Blizzard_FlightMap{FlightMapFrame},Blizzard_GMChatUI{GMChatStat",
    "usFrame},Blizzard_GarrisonUI{BFAMissionFrame,CovenantMissionFrame{Co",
    "venantMissionFrame.FollowerList.MaterialFrame,CovenantMissionFrame.F",
    "ollowerList.listScroll,CovenantMissionFrame.MissionTab,CovenantMissi",
    "onFrame.MissionTab.MissionList.MaterialFrame,CovenantMissionFrame.Mi",
    "ssionTab.MissionPage,CovenantMissionFrame.MissionTab.MissionPage.Cos",
    "tFrame,CovenantMissionFrame.MissionTab.MissionPage.StartMissionFrame",
    "},GarrisonBuildingFrame,GarrisonCapacitiveDisplayFrame,GarrisonLandi",
    "ngPage{GarrisonLandingPageFollowerListListScrollFrame,GarrisonLandin",
    "gPageReportListListScrollFrame},GarrisonMissionFrame,GarrisonMonumen",
    "tFrame,GarrisonRecruitSelectFrame,GarrisonRecruiterFrame,GarrisonShi",
    "pyardFrame,OrderHallMissionFrame},Blizzard_GenericTraitUI{GenericTra",
    "itFrame{GenericTraitFrame.ButtonsParent}},Blizzard_GuildBankUI{Guild",
    "BankFrame},Blizzard_GuildControlUI{GuildControlUI},Blizzard_GuildRen",
    "ame{GuildRenameFrame},Blizzard_HouseList{HouseListFrame},Blizzard_Ho",
    "usingBulletinBoard{HousingBulletinBoardFrame,HousingInviteResidentFr",
    "ame,NeighborhoodChangeNameDialog},Blizzard_HousingCharter{HousingCha",
    "rterRequestSignatureDialog},Blizzard_HousingCornerstone{HousingCorne",
    "rstoneFrame,HousingCornerstoneHouseInfoFrame,HousingCornerstonePurch",
    "aseFrame,HousingCornerstoneVisitorFrame,ImportHouseConfirmationDialo",
    "g,MoveHouseConfirmationDialog},Blizzard_HousingCreateNeighborhood{Ho",
    "usingCreateCharterNeighborhoodConfirmationFrame,HousingCreateNeighbo",
    "rhoodCharterFrame},Blizzard_HousingDashboard{HousingDashboardFrame},",
    "Blizzard_HousingHouseFinder{HouseFinderFrame},Blizzard_HousingHouseS",
    "ettings{AbandonHouseConfirmationDialog,HousingHouseSettingsFrame},Bl",
    "izzard_HousingModelPreview{HousingModelPreviewFrame},Blizzard_Inspec",
    "tUI{InspectFrame},Blizzard_IslandsPartyPoseUI{IslandsPartyPoseFrame}",
    ",Blizzard_IslandsQueueUI{IslandsQueueFrame},Blizzard_ItemInteraction",
    "UI{ItemInteractionFrame},Blizzard_ItemSocketingUI{ItemSocketingFrame",
    "},Blizzard_ItemUpgradeUI{ItemUpgradeFrame},Blizzard_Kiosk{GameKioskS",
    "essionStartedDialog},Blizzard_MacroUI{MacroFrame},Blizzard_MajorFact",
    "ions{MajorFactionRenownFrame},Blizzard_MatchCelebrationPartyPoseUI{M",
    "atchCelebrationPartyPoseFrame},Blizzard_ObliterumUI{ObliterumForgeFr",
    "ame},Blizzard_OrderHallUI{OrderHallTalentFrame},Blizzard_PVPMatch{PV",
    "PMatchResults},Blizzard_PVPUI{PVPMatchScoreboard},Blizzard_PlayerCho",
    "ice{PlayerChoiceFrame},Blizzard_PlayerSpells{HeroTalentsSelectionDia",
    "log,PlayerSpellsFrame{PlayerSpellsFrame.TalentsFrame.ButtonsParent}}",
    ",Blizzard_ProfessionsBook{ProfessionsBookFrame},Blizzard_Professions",
    "CustomerOrders{ProfessionsCustomerOrdersFrame{ProfessionsCustomerOrd",
    "ersFrame.Form,ProfessionsCustomerOrdersFrame.Form.CurrentListings}},",
    "Blizzard_Professions{InspectRecipeFrame,ProfessionsFrame.CraftingPag",
    "e.SchematicForm.QualityDialog,ProfessionsFrame.OrdersPage.OrderView.",
    "OrderDetails.SchematicForm.QualityDialog,ProfessionsFrame{Profession",
    "sFrame.CraftingPage.CraftingOutputLog,ProfessionsFrame.CraftingPage.",
    "CraftingOutputLog.ScrollBox}},Blizzard_RemixArtifactUI{RemixArtifact",
    "Frame{RemixArtifactFrame.ButtonsParent,RemixArtifactFrame.Header}},B",
    "lizzard_ScrappingMachineUI{ScrappingMachineFrame},Blizzard_Soulbinds",
    "{SoulbindViewer},Blizzard_StableUI{StableFrame},Blizzard_Subscriptio",
    "nInterstitialUI{SubscriptionInterstitialFrame},Blizzard_TalentUI{Pla",
    "yerTalentFrame},Blizzard_TimeManager{TimeManagerFrame},Blizzard_Toke",
    "nUI{CurrencyTransferMenu},Blizzard_TorghastLevelPicker{TorghastLevel",
    "PickerFrame},Blizzard_TrainerUI{ClassTrainerFrame},Blizzard_Transmog",
    "{TransmogFrame},Blizzard_UIPanels_Game{CharacterFrame{CurrencyTransf",
    "erLog,PaperDollFrame,ReputationFrame,TokenFrame,TokenFramePopup}},Bl",
    "izzard_VoidStorageUI{VoidStorageFrame},Blizzard_WarfrontsPartyPoseUI",
    "{WarfrontsPartyPoseFrame},Blizzard_WeeklyRewards{WeeklyRewardsFrame}",
}, "")

describe("MoveFrames.lua", function()
    local MF, seams

    before_each(function()
        local mf, _, s = L.loadMoveFrames()
        MF, seams = mf, s
    end)

    describe("GetFrame", function()
        local getFrame

        before_each(function()
            local _, _, s2 = L.loadMoveFrames()
            getFrame = s2.getFrame
            _G.Alpha = { Beta = { Gamma = {} } }
        end)

        after_each(function()
            _G.Alpha = nil
            _G.NoSuchGlobal = nil
        end)

        it("returns a table carrying GetName unchanged", function()
            local stub = { GetName = function() end }
            assert.equal(stub, getFrame(stub))
        end)

        it("resolves a single segment", function()
            assert.equal(_G.Alpha, getFrame("Alpha"))
        end)

        it("resolves two segments", function()
            assert.equal(_G.Alpha.Beta, getFrame("Alpha.Beta"))
        end)

        it("resolves three segments", function()
            assert.equal(_G.Alpha.Beta.Gamma, getFrame("Alpha.Beta.Gamma"))
        end)

        it("returns nil without error on a broken mid-path", function()
            assert.is_nil(getFrame("Alpha.Missing.Deep"))
        end)

        it("returns nil for an absent root", function()
            assert.is_nil(getFrame("NoSuchGlobal"))
        end)

        it("returns nil for nil input", function()
            assert.is_nil(getFrame(nil))
        end)
    end)

    describe("frame-table structural integrity", function()
        it("holds only strings on numeric keys and only tables on string keys, in BlizzardFrames", function()
            local violations = {}
            structuralViolations(seams.blizzardFrames, "BlizzardFrames", violations)
            assert.same({}, violations)
        end)

        it("holds only strings on numeric keys and only tables on string keys, in BlizzardFramesOnDemand", function()
            local violations = {}
            structuralViolations(seams.blizzardFramesOnDemand, "BlizzardFramesOnDemand", violations)
            assert.same({}, violations)
        end)

        it("has no duplicate frame name in BlizzardFrames", function()
            local names = {}
            collectNames(seams.blizzardFrames, false, names)
            local seen, dupes = {}, {}
            for _, name in ipairs(names) do
                if seen[name] then
                    dupes[#dupes + 1] = name
                end
                seen[name] = true
            end
            assert.same({}, dupes)
        end)

        it("has only Blizzard_-prefixed top-level keys in BlizzardFramesOnDemand", function()
            for k in pairs(seams.blizzardFramesOnDemand) do
                assert.is_true(type(k) == "string" and k:sub(1, 9) == "Blizzard_", "unexpected top-level key: " .. tostring(k))
            end
        end)
    end)

    describe("frame-table content", function()
        it("matches the independently-derived oracle for BlizzardFrames", function()
            assert.equal(EXPECTED_ALWAYS, serialize(seams.blizzardFrames))
        end)

        it("matches the independently-derived oracle for BlizzardFramesOnDemand", function()
            assert.equal(EXPECTED_ONDEMAND, serialize(seams.blizzardFramesOnDemand))
        end)

        it("has the expected frame/addon counts (diagnostics)", function()
            local alwaysNames = {}
            collectNames(seams.blizzardFrames, false, alwaysNames)
            assert.equal(54, #alwaysNames)

            local onDemandNames = {}
            collectNames(seams.blizzardFramesOnDemand, true, onDemandNames)
            assert.equal(151, #onDemandNames)

            local addonCount = 0
            for _ in pairs(seams.blizzardFramesOnDemand) do
                addonCount = addonCount + 1
            end
            assert.equal(80, addonCount)
        end)

        it("carries the named members expected in BlizzardFrames", function()
            for _, name in ipairs({
                "MerchantFrame", "LootFrame", "GroupLootContainer", "QuickKeybindFrame",
                "SettingsPanel", "MailFrameInset", "QuestMapFrame",
            }) do
                assert.is_true(containsName(seams.blizzardFrames, name), name .. " missing from BlizzardFrames")
            end
        end)

        it("carries the named members expected under their addon key in BlizzardFramesOnDemand", function()
            local expectations = {
                Blizzard_EncounterJournal = "EncounterJournal",
                Blizzard_Communities = "CommunitiesSettingsDialog",
                Blizzard_PlayerSpells = "HeroTalentsSelectionDialog",
                Blizzard_UIPanels_Game = "CharacterFrame",
            }
            for addon, member in pairs(expectations) do
                local addonTable = seams.blizzardFramesOnDemand[addon]
                assert.is_true(addonTable ~= nil, addon .. " missing from BlizzardFramesOnDemand")
                assert.is_true(containsName(addonTable, member), member .. " missing under " .. addon)
            end
        end)

        it("never carries GameMenuFrame in either table (regression guard)", function()
            assert.is_false(containsName(seams.blizzardFrames, "GameMenuFrame"))
            assert.is_false(containsName(seams.blizzardFramesOnDemand, "GameMenuFrame"))
        end)
    end)

    describe("MF:IsRunning", function()
        it("is falsy when db is nil", function()
            MF.db = nil
            assert.is_falsy(MF:IsRunning())
        end)

        it("is falsy when db.Enabled is false", function()
            MF.db = { Enabled = false }
            assert.is_falsy(MF:IsRunning())
        end)

        it("is true when db.Enabled is true", function()
            MF.db = { Enabled = true }
            assert.is_true(MF:IsRunning())
        end)

        it("is falsy when db.Enabled is true but StopRunning is set", function()
            MF.db = { Enabled = true }
            MF.StopRunning = "BlizzMove"
            assert.is_falsy(MF:IsRunning())
        end)
    end)

    describe("MF:SetMovable", function()
        local frameStub

        before_each(function()
            frameStub = { GetName = function() end }
        end)

        it("writes nothing while IsRunning() is false", function()
            MF.db = { Enabled = false }
            MF:SetMovable(frameStub, false)
            assert.is_nil(seams.disabled[frameStub])
        end)

        it("marks a frame not-movable", function()
            MF.db = { Enabled = true }
            MF:SetMovable(frameStub, false)
            assert.is_true(seams.disabled[frameStub])
        end)

        it("marks a frame movable again", function()
            MF.db = { Enabled = true }
            MF:SetMovable(frameStub, true)
            assert.is_false(seams.disabled[frameStub])
        end)

        it("writes nothing and does not error for an unresolvable frame", function()
            MF.db = { Enabled = true }
            assert.has_no.errors(function()
                MF:SetMovable("NoSuchGlobal", false)
            end)
        end)
    end)
end)
