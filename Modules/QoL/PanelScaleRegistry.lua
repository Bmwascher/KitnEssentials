-- ╔══════════════════════════════════════════════════════════╗
-- ║  PanelScaleRegistry.lua                                  ║
-- ║  Data: the Blizzard panel roots Panel Scaling manages    ║
-- ║  and their name, owner-addon and category indexes.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local assert = assert
local ipairs = ipairs

-- `addon` is set only when the owner loads on demand: an always-loaded
-- owner's ADDON_LOADED fires before this addon loads and is never seen, and
-- the enable pass finds those roots directly. Blizzard_GuildControlUI loads
-- on demand but at startup, as a dependency of Blizzard_Communities, so
-- GuildControlUI has none either.
local ENTRIES = {
    -- Core Panels
    { name = "CharacterFrame",                 category = "Core", label = "Character" },
    { name = "PlayerSpellsFrame",              category = "Core", label = "Spellbook and Talents",     addon = "Blizzard_PlayerSpells" },
    { name = "HeroTalentsSelectionDialog",     category = "Core", label = "Hero Talents",              addon = "Blizzard_PlayerSpells" },
    { name = "ProfessionsBookFrame",           category = "Core", label = "Professions Book",          addon = "Blizzard_ProfessionsBook" },
    { name = "ProfessionsFrame",               category = "Core", label = "Professions",               addon = "Blizzard_Professions" },
    { name = "ProfessionsCustomerOrdersFrame", category = "Core", label = "Crafting Orders",           addon = "Blizzard_ProfessionsCustomerOrders" },
    { name = "InspectRecipeFrame",             category = "Core", label = "Inspected Recipe",          addon = "Blizzard_Professions" },
    { name = "PVEFrame",                       category = "Core", label = "Group Finder" },
    { name = "EncounterJournal",               category = "Core", label = "Adventure Guide",           addon = "Blizzard_EncounterJournal" },
    { name = "CollectionsJournal",             category = "Core", label = "Collections",               addon = "Blizzard_Collections" },
    { name = "CommunitiesFrame",               category = "Core", label = "Communities" },
    { name = "AchievementFrame",               category = "Core", label = "Achievements",              addon = "Blizzard_AchievementUI" },
    { name = "CalendarFrame",                  category = "Core", label = "Calendar",                  addon = "Blizzard_Calendar" },
    { name = "ExpansionLandingPage",           category = "Core", label = "Expansion Summary" },
    { name = "WeeklyRewardsFrame",             category = "Core", label = "Great Vault",               addon = "Blizzard_WeeklyRewards" },
    { name = "SettingsPanel",                  category = "Core", label = "Game Settings" },
    { name = "FriendsFrame",                   category = "Core", label = "Friends" },
    { name = "SocialUIFrame",                  category = "Core", label = "Social" },
    { name = "RaidParentFrame",                category = "Core", label = "Raid" },
    { name = "ChatConfigFrame",                category = "Core", label = "Chat Settings" },
    { name = "ChannelFrame",                   category = "Core", label = "Chat Channels" },
    { name = "ClickBindingFrame",              category = "Core", label = "Click Casting",             addon = "Blizzard_ClickBindingUI" },
    { name = "CooldownViewerSettings",         category = "Core", label = "Cooldown Manager Settings" },
    { name = "HelpFrame",                      category = "Core", label = "Help" },
    { name = "InspectFrame",                   category = "Core", label = "Inspect",                   addon = "Blizzard_InspectUI" },
    { name = "MacroFrame",                     category = "Core", label = "Macros",                    addon = "Blizzard_MacroUI" },
    { name = "AddonList",                      category = "Core", label = "AddOn List" },
    { name = "AlliedRacesFrame",               category = "Core", label = "Allied Races",              addon = "Blizzard_AlliedRacesUI" },

    -- Services
    { name = "AuctionHouseFrame",              category = "Services", label = "Auction House",         addon = "Blizzard_AuctionHouseUI" },
    { name = "BankFrame",                      category = "Services", label = "Bank" },
    { name = "GuildBankFrame",                 category = "Services", label = "Guild Bank",            addon = "Blizzard_GuildBankUI" },
    { name = "BlackMarketFrame",               category = "Services", label = "Black Market",          addon = "Blizzard_BlackMarketUI" },
    { name = "MailFrame",                      category = "Services", label = "Mailbox" },
    { name = "OpenMailFrame",                  category = "Services", label = "Open Mail" },
    { name = "MerchantFrame",                  category = "Services", label = "Merchant" },
    { name = "TradeFrame",                     category = "Services", label = "Trade" },
    { name = "GossipFrame",                    category = "Services", label = "Gossip" },
    { name = "QuestFrame",                     category = "Services", label = "Quest Dialog" },
    { name = "QuestLogPopupDetailFrame",       category = "Services", label = "Quest Details" },
    { name = "ClassTrainerFrame",              category = "Services", label = "Trainer",               addon = "Blizzard_TrainerUI" },
    { name = "StableFrame",                    category = "Services", label = "Stable" },
    { name = "FlightMapFrame",                 category = "Services", label = "Flight Map",            addon = "Blizzard_FlightMap" },
    { name = "TaxiFrame",                      category = "Services", label = "Flight Master" },
    { name = "TransmogFrame",                  category = "Services", label = "Transmogrification",    addon = "Blizzard_Transmog" },
    { name = "ItemUpgradeFrame",               category = "Services", label = "Item Upgrade",          addon = "Blizzard_ItemUpgradeUI" },
    { name = "ItemSocketingFrame",             category = "Services", label = "Item Socketing",        addon = "Blizzard_ItemSocketingUI" },
    { name = "ItemInteractionFrame",           category = "Services", label = "Item Interaction",      addon = "Blizzard_ItemInteractionUI" },
    { name = "DressUpFrame",                   category = "Services", label = "Dressing Room" },
    { name = "TabardFrame",                    category = "Services", label = "Tabard Design" },
    { name = "GuildRegistrarFrame",            category = "Services", label = "Guild Registrar" },
    { name = "GuildControlUI",                 category = "Services", label = "Guild Control" },
    { name = "PetitionFrame",                  category = "Services", label = "Petition" },
    { name = "ItemTextFrame",                  category = "Services", label = "Item Text" },
    { name = "CurrencyTransferMenu",           category = "Services", label = "Currency Transfer" },
    { name = "ChromieTimeFrame",               category = "Services", label = "Chromie Time",          addon = "Blizzard_ChromieTimeUI" },

    -- Housing
    { name = "HousingDashboardFrame",          category = "Housing", label = "Housing Dashboard",      addon = "Blizzard_HousingDashboard" },
    { name = "HouseListFrame",                 category = "Housing", label = "House List",             addon = "Blizzard_HouseList" },
    { name = "HouseFinderFrame",               category = "Housing", label = "House Finder",           addon = "Blizzard_HousingHouseFinder" },
    { name = "HousingBulletinBoardFrame",      category = "Housing", label = "Bulletin Board",         addon = "Blizzard_HousingBulletinBoard" },
    { name = "HousingHouseSettingsFrame",      category = "Housing", label = "House Settings",         addon = "Blizzard_HousingHouseSettings" },
    { name = "HousingModelPreviewFrame",       category = "Housing", label = "Model Preview",          addon = "Blizzard_HousingModelPreview" },
    { name = "HousingCharterFrame",            category = "Housing", label = "Charter",                addon = "Blizzard_HousingCharter" },
    { name = "HousingCornerstoneFrame",        category = "Housing", label = "Cornerstone",            addon = "Blizzard_HousingCornerstone" },
    { name = "HousingCreateGuildNeighborhoodFrame",   category = "Housing", label = "Create Guild Neighborhood",   addon = "Blizzard_HousingCreateNeighborhood" },
    { name = "HousingCreateNeighborhoodCharterFrame", category = "Housing", label = "Create Neighborhood Charter", addon = "Blizzard_HousingCreateNeighborhood" },
    { name = "HousingBlueprintExportFrame",    category = "Housing", label = "Blueprint Export",       addon = "Blizzard_HousingBlueprint" },
    { name = "HousingBlueprintImportFrame",    category = "Housing", label = "Blueprint Import",       addon = "Blizzard_HousingBlueprint" },
    { name = "HousingBlueprintContentListFrame", category = "Housing", label = "Blueprint Contents",   addon = "Blizzard_HousingBlueprint" },
    { name = "HousingBlueprintRenameFrame",    category = "Housing", label = "Blueprint Rename",       addon = "Blizzard_HousingBlueprint" },
    { name = "HousingInviteResidentFrame",     category = "Housing", label = "Invite Resident",        addon = "Blizzard_HousingBulletinBoard" },
    { name = "HousingCornerstoneHouseInfoFrame", category = "Housing", label = "House Info",           addon = "Blizzard_HousingCornerstone" },
    { name = "HousingCornerstonePurchaseFrame", category = "Housing", label = "House Purchase",        addon = "Blizzard_HousingCornerstone" },
    { name = "HousingCornerstoneVisitorFrame", category = "Housing", label = "Visitor",                addon = "Blizzard_HousingCornerstone" },
    { name = "HousingCreateCharterNeighborhoodConfirmationFrame", category = "Housing", label = "Charter Confirmation", addon = "Blizzard_HousingCreateNeighborhood" },

    -- Legacy / Optional
    { name = "ArchaeologyFrame",               category = "Legacy", label = "Archaeology",             addon = "Blizzard_ArchaeologyUI" },
    { name = "ArtifactFrame",                  category = "Legacy", label = "Artifact",                addon = "Blizzard_ArtifactUI" },
    { name = "AzeriteEmpoweredItemUI",         category = "Legacy", label = "Azerite Armor",           addon = "Blizzard_AzeriteUI" },
    { name = "AzeriteEssenceUI",               category = "Legacy", label = "Heart of Azeroth",        addon = "Blizzard_AzeriteEssenceUI" },
    { name = "AzeriteRespecFrame",             category = "Legacy", label = "Azerite Reforge",         addon = "Blizzard_AzeriteRespecUI" },
    { name = "AnimaDiversionFrame",            category = "Legacy", label = "Anima Conductor",         addon = "Blizzard_AnimaDiversionUI" },
    { name = "CovenantPreviewFrame",           category = "Legacy", label = "Covenant Preview",        addon = "Blizzard_CovenantPreviewUI" },
    { name = "CovenantRenownFrame",            category = "Legacy", label = "Renown",                  addon = "Blizzard_CovenantRenown" },
    { name = "CovenantSanctumFrame",           category = "Legacy", label = "Covenant Sanctum",        addon = "Blizzard_CovenantSanctum" },
    { name = "DelvesCompanionConfigurationFrame", category = "Legacy", label = "Delve Companion" },
    { name = "DelvesCompanionAbilityListFrame", category = "Legacy", label = "Companion Abilities" },
    { name = "DelvesDifficultyPickerFrame",    category = "Legacy", label = "Delve Difficulty",        addon = "Blizzard_DelvesDifficultyPicker" },
    { name = "GenericTraitFrame",              category = "Legacy", label = "Trait Trees",             addon = "Blizzard_GenericTraitUI" },
    { name = "GarrisonBuildingFrame",          category = "Legacy", label = "Garrison Buildings",      addon = "Blizzard_GarrisonUI" },
    { name = "GarrisonLandingPage",            category = "Legacy", label = "Garrison Report",         addon = "Blizzard_GarrisonUI" },
    { name = "GarrisonMissionFrame",           category = "Legacy", label = "Garrison Missions",       addon = "Blizzard_GarrisonUI" },
    { name = "GarrisonShipyardFrame",          category = "Legacy", label = "Shipyard",                addon = "Blizzard_GarrisonUI" },
    { name = "GarrisonMonumentFrame",          category = "Legacy", label = "Garrison Monuments",      addon = "Blizzard_GarrisonUI" },
    { name = "GarrisonRecruiterFrame",         category = "Legacy", label = "Follower Recruiter",      addon = "Blizzard_GarrisonUI" },
    { name = "GarrisonRecruitSelectFrame",     category = "Legacy", label = "Recruit Selection",       addon = "Blizzard_GarrisonUI" },
    { name = "OrderHallMissionFrame",          category = "Legacy", label = "Order Hall Missions",     addon = "Blizzard_GarrisonUI" },
    { name = "OrderHallTalentFrame",           category = "Legacy", label = "Order Hall Talents",      addon = "Blizzard_OrderHallUI" },
    { name = "BFAMissionFrame",                category = "Legacy", label = "War Campaign Missions",   addon = "Blizzard_GarrisonUI" },
    { name = "CovenantMissionFrame",           category = "Legacy", label = "Adventures",              addon = "Blizzard_GarrisonUI" },
    { name = "IslandsQueueFrame",              category = "Legacy", label = "Island Expeditions",      addon = "Blizzard_IslandsQueueUI" },
    { name = "ObliterumForgeFrame",            category = "Legacy", label = "Obliterum Forge",         addon = "Blizzard_ObliterumUI" },
    { name = "RemixArtifactFrame",             category = "Legacy", label = "Remix Artifact",          addon = "Blizzard_RemixArtifactUI" },
    { name = "RuneforgeFrame",                 category = "Legacy", label = "Runecarver",              addon = "Blizzard_RuneforgeUI" },
    { name = "ScrappingMachineFrame",          category = "Legacy", label = "Scrapper",                addon = "Blizzard_ScrappingMachineUI" },
    { name = "SoulbindViewer",                 category = "Legacy", label = "Soulbinds",               addon = "Blizzard_Soulbinds" },
    { name = "TorghastLevelPickerFrame",       category = "Legacy", label = "Torghast Layer Select",   addon = "Blizzard_TorghastLevelPicker" },
}

local CATEGORIES = { "Core", "Services", "Housing", "Legacy" }

local function BuildIndexes(entries)
    local byName, byAddon, categories, labelsByCategory = {}, {}, {}, {}
    for _, category in ipairs(CATEGORIES) do
        categories[category] = {}
        labelsByCategory[category] = {}
    end
    for _, entry in ipairs(entries) do
        assert(not byName[entry.name], "duplicate panel scale root " .. entry.name)
        local bucket = categories[entry.category]
        assert(bucket, "unknown panel scale category for " .. entry.name)
        byName[entry.name] = entry
        bucket[#bucket + 1] = entry
        local labels = labelsByCategory[entry.category]
        labels[#labels + 1] = entry.label
        if entry.addon then
            local owned = byAddon[entry.addon] or {}
            owned[#owned + 1] = entry
            byAddon[entry.addon] = owned
        end
    end
    return byName, byAddon, categories, labelsByCategory
end

local byName, byAddon, categories, labelsByCategory = BuildIndexes(ENTRIES)

KE.PanelScaleRegistry = {
    entries = ENTRIES,
    byName = byName,
    byAddon = byAddon,
    categories = categories,
    labelsByCategory = labelsByCategory,
}
