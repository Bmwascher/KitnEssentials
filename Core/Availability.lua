-- ╔══════════════════════════════════════════════════════════╗
-- ║  Availability.lua                                        ║
-- ║  Purpose: Which features this client runs: one answer    ║
-- ║           for loading, settings, previews and refresh.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

-- The policy follows the lists the TOC loaded, never the interface version:
-- after a baseline load (Core/BaselineLoad.lua) only the baseline runs, after
-- a retail load everything does, so policy and loaded files cannot disagree.
local RETAIL = KE.BASELINE_LOAD ~= true

-- The only features of a baseline load until each category is admitted. A
-- saved Enabled flag or an imported profile never adds to the list.
local FOREVER_ALLOWED = {
    HomePage = true,
    Profiles = true,
    ProfilesMain = true,
    ProfilesSharing = true,
    ProfilesReset = true,
    -- Dark Theme: the engine, Color Picker, the skins command, the page
    -- with the tabs that configure what loads, the Addon Skins card and the
    -- role icon card. Raid Control and the Group Finder skin stay withheld.
    BlizzardFrames = true,
    ColorPicker = true,
    SkinAPI = true,
    SkinBlizzardFrames = true,
    SkinBlizzardFramesGeneral = true,
    SkinBlizzardFramesColors = true,
    SkinBlizzardFramesFonts = true,
    SkinBlizzardFramesFontsWindows = true,
    SkinBlizzardFramesSkins = true,
    SkinBlizzardFramesFrames = true,
    SkinBlizzardFramesAddons = true,
    SkinBlizzardFramesGroupFinder = true,
    -- Elements: the five modules with their own switches, and their pages.
    AlertFrames = true,
    LootFrame = true,
    LootRoll = true,
    UIWidgets = true,
    VehicleExit = true,
    SkinBlizzardFramesElements = true,
    SkinBlizzardFramesAlertFrames = true,
    SkinBlizzardFramesLootRoll = true,
    SkinBlizzardFramesLootWindow = true,
    SkinBlizzardFramesWidgets = true,
    -- Fonts and menus: Blizzard Text, On-Screen Messages, the global font
    -- sweep and Context Menus, at their retail defaults.
    BlizzardFonts = true,
    ContextMenus = true,
    SkinBlizzardMessages = true,
    SkinBlizzardFramesFontsBlizzard = true,
    SkinMessages = true,
    -- Tooltips: the module and its page. Its realm-name, guild-realm and
    -- Mythic+ options stay withheld.
    SkinTooltips = true,
    -- Chat: the module, its history and links modules, and its page.
    Chat = true,
    ChatHistory = true,
    ChatLinks = true,
    -- Damage Meter: the module, its page and the page's four tabs. Its
    -- realm-name, Mythic+ and keystone options stay withheld.
    DamageMeter = true,
    DamageMeter_Windows = true,
    DamageMeter_Appearance = true,
    DamageMeter_Behavior = true,
    DamageMeter_SpellHistory = true,
    -- Core: System Optimization, the CVars page with its General and Dev
    -- tabs, UI Scaling with its General, Core Panels and Services tabs, Panel
    -- and Map Scale, and Version Check. The Housing and Legacy tabs and the
    -- Optimize Mythic+ card stay withheld, and so does Automation, whose
    -- switch the CVars login apply waits on.
    CVars = true,
    CVarsGeneral = true,
    CVarsDev = true,
    UIScaling = true,
    UIScalingGeneral = true,
    UIScalingCore = true,
    UIScalingServices = true,
    Optimize = true,
    PanelScale = true,
    MapScale = true,
    VersionCheck = true,
    -- Character Panel: the module, its inspect half, the comparison header
    -- and the page with its three tabs. Its Mythic+, track, socket, enchant
    -- rank, widen and window button options stay withheld.
    CharacterPanel = true,
    CharacterPanelCharacter = true,
    CharacterPanelInspect = true,
    CharacterPanelExtras = true,
    InspectPanel = true,
    CompareHeader = true,
    -- Aura Tracking: six displays and their pages. Party Cooldowns stays
    -- withheld.
    BuffTracking = true,
    PlayerDebuffTracking = true,
    AuraHeaders_Buffs = true,
    AuraHeaders_Debuffs = true,
    AuraDebuffs = true,
    AuraExternals = true,
    AuraMovement = true,
    TotemTracker = true,
    -- QoL: the Quality of Life page with its Spell Alerts, Move Frames, Copy
    -- Anything and Slash Commands tabs, and Secondary Stats. Great Vault
    -- Alert, the other QoL rows and the PI Macro Builder line stay withheld.
    QualityOfLife = true,
    SpellAlerts = true,
    MoveFrames = true,
    CopyAnything = true,
    SlashCommands = true,
    SecondaryStats = true,
}

-- Ids are module names, sidebar rows, sub-tabs and optional integrations.
-- A retail load admits every id; a baseline load refuses any id not above.
---@param featureId string?
---@return boolean available
---@return string? reason
function KE:IsFeatureAvailable(featureId)
    if RETAIL then return true end
    if featureId and FOREVER_ALLOWED[featureId] then return true end
    return false, "withheld on this client"
end

-- True after a baseline load. For a branch that picks a Forever value, where
-- there is no feature to admit or withhold.
---@return boolean
function KE:IsBaselineLoad()
    return not RETAIL
end

-- Which feature owns each top-level profile block, for imports and exports
-- that drop what this client does not run. A core key always stays, a nested
-- container's sub-blocks are each judged by their own key, and any other
-- block is owned by the mapped id or else by the module of its own name.
local PROFILE_CORE_KEYS = {
    ShowChatMessage = true,
    ExpandSidebarOnOpen = true,
    UseSlugFonts = true,
    GlobalFont = true,
    Minimap = true,
    UseElvUI = true,
}
local NESTED_PROFILE_BLOCKS = {
    Dungeons = true,
}
local PROFILE_BLOCK_OWNERS = {
    -- It holds the CVars page's keys beside Automation's own.
    Automation = "CVars",
    -- Each sub-block belongs to a module the skinning engine runs.
    Skinning = "SkinAPI",
    -- No module carries the name; the id is the settings row's.
    SlashCommands = "SlashCommands",
}

---@param key string
---@return string kind "core", "nested" or "feature"
---@return string? owner the owning feature id, for "feature"
---@return boolean? mapped true when the owner comes from the map
function KE:ProfileBlockOwner(key)
    if PROFILE_CORE_KEYS[key] then return "core" end
    if NESTED_PROFILE_BLOCKS[key] then return "nested" end
    local mapped = PROFILE_BLOCK_OWNERS[key]
    return "feature", mapped or key, mapped ~= nil
end

-- Entries are { id = ... } tables: sidebar rows and sub-tabs. The same list
-- comes back when nothing is withheld.
---@param entries table[]
---@return table[]
function KE:FilterAvailableEntries(entries)
    if RETAIL then return entries end
    local kept = {}
    for i = 1, #entries do
        local entry = entries[i]
        if self:IsFeatureAvailable(entry.id) then kept[#kept + 1] = entry end
    end
    return kept
end

-- Entries are { key = ... } tables: Frame Skins and Addon Skins rows. The
-- frame-skin policy answers on every load, retail included, and a new table
-- comes back.
---@param entries table[]
---@return table[]
function KE:FilterAvailableFrameSkins(entries)
    local kept = {}
    for i = 1, #entries do
        local entry = entries[i]
        if self:IsFrameSkinAvailable(entry.key) then kept[#kept + 1] = entry end
    end
    return kept
end

-- Skin registration keys a baseline load runs: the admitted window and addon
-- skins, plus Dialogs, the global font sweep, the shared dropdown list and the
-- Context Menus row. Kept apart from the feature ids above so a skin key can
-- never collide with a module or page id.
local FOREVER_FRAME_SKINS = {
    Ace3 = true,
    AddonManager = true,
    Alerts = true,
    AuctionHouse = true,
    Baganator = true,
    Barber = true,
    Battlenet = true,
    BetterFriendlist = true,
    BigWigs = true,
    Binding = true,
    BlackMarket = true,
    BugSack = true,
    Calendar = true,
    CatalogShop = true,
    Channels = true,
    Character = true,
    ChatConfig = true,
    Collectables = true,
    Communities = true,
    ContextMenus = true,
    CooldownManager = true,
    Currency = true,
    DeathRecap = true,
    Dialogs = true,
    DressingRoom = true,
    EditMode = true,
    ExtraButtons = true,
    FlightMap = true,
    GenericTrait = true,
    GlobalFonts = true,
    GMChat = true,
    Gossip = true,
    Guild = true,
    GuildBank = true,
    GuildControl = true,
    GuildRegistrar = true,
    Help = true,
    Inspect = true,
    InspectRecipe = true,
    Loot = true,
    LootToast = true,
    LossControl = true,
    Macro = true,
    Mail = true,
    Merchant = true,
    MirrorTimers = true,
    Misc = true,
    NonRaid = true,
    Petition = true,
    PlayerSpells = true,
    Professions = true,
    PvPMatch = true,
    Quest = true,
    Raid = true,
    Reputation = true,
    SettingsPanel = true,
    SharedDropDownList = true,
    Simulationcraft = true,
    Socket = true,
    Stable = true,
    SubscriptionInterstitial = true,
    Tabard = true,
    TalkingHead = true,
    Taxi = true,
    TimeManager = true,
    Trade = true,
    Trainer = true,
    Transmog = true,
    TutorialFrame = true,
    WorldMap = true,
}

-- Skin keys of windows only the Forever client has. Their files load only
-- from the camelot list, and a retail load refuses them, so their rows never
-- show on retail and a stray load there cannot run them.
local FOREVER_ONLY_FRAME_SKINS = {
    LegacySystem = true,
    PVPRank = true,
    Skills = true,
    Statistics = true,
}

-- Whether a skin registered under `key` may run and show a Frame Skins row.
-- A retail load admits every key except the Forever-only ones.
---@param key string?
---@return boolean available
function KE:IsFrameSkinAvailable(key)
    if RETAIL then return not (key and FOREVER_ONLY_FRAME_SKINS[key]) end
    return key ~= nil and (FOREVER_FRAME_SKINS[key] == true or FOREVER_ONLY_FRAME_SKINS[key] == true)
end
