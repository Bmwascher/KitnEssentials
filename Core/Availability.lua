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
    -- Dark Theme: the engine, Color Picker, the skins command, and the page
    -- with the tabs that configure what loads. Elements, Group Finder, Addon
    -- Skins, Blizzard Text and On-Screen Messages stay withheld.
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
    -- Tooltips: the module and its page. Its realm-name, guild-realm and
    -- Mythic+ options stay withheld.
    SkinTooltips = true,
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

-- Skin registration keys a baseline load runs: the admitted window skins,
-- plus Dialogs. Kept apart from the feature ids above so a skin key can
-- never collide with a module or page id.
local FOREVER_FRAME_SKINS = {
    AddonManager = true,
    Alerts = true,
    AuctionHouse = true,
    Barber = true,
    Battlenet = true,
    Binding = true,
    BlackMarket = true,
    Calendar = true,
    Channels = true,
    ChatConfig = true,
    Communities = true,
    CooldownManager = true,
    DeathRecap = true,
    Dialogs = true,
    DressingRoom = true,
    EditMode = true,
    ExtraButtons = true,
    FlightMap = true,
    GenericTrait = true,
    GMChat = true,
    Gossip = true,
    Guild = true,
    GuildBank = true,
    GuildControl = true,
    GuildRegistrar = true,
    Help = true,
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
    PvPMatch = true,
    Quest = true,
    Raid = true,
    SettingsPanel = true,
    Socket = true,
    SubscriptionInterstitial = true,
    Tabard = true,
    Taxi = true,
    TimeManager = true,
    Trade = true,
    Trainer = true,
    Transmog = true,
    TutorialFrame = true,
    WorldMap = true,
}

-- Whether a skin registered under `key` may run and show a Frame Skins row.
-- A retail load admits every key.
---@param key string?
---@return boolean available
function KE:IsFrameSkinAvailable(key)
    if RETAIL then return true end
    return key ~= nil and FOREVER_FRAME_SKINS[key] == true
end
