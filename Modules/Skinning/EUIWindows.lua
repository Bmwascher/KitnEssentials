-- ╔══════════════════════════════════════════════════════════╗
-- ║  EUIWindows.lua                                          ║
-- ║  Purpose: Decide which of our Blizzard frame skins       ║
-- ║           EllesmereUI already covers, so the two do not  ║
-- ║           backdrop the same frame twice.                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local S = KE.Skins
local ipairs, tonumber, type = ipairs, tonumber, type
local math_max = math.max

-- EllesmereUI window key -> the skin keys of ours it covers.
--
-- `since` names the EllesmereUI version that introduced the window key.
-- It exists because EllesmereUI.GetBlizzWindowStyle FAILS OPEN: an
-- unrecognised key skips the enable-key test and falls through to "eui"
-- (EllesmereUIBlizzardSkin.lua:76-84). Asking an 8.5.9 client about a key
-- that only exists from 8.6.4 therefore answers "EllesmereUI owns it" for a
-- window EllesmereUI does not touch, and our skin would go missing with no
-- error and no clue. EllesmereUI's own key list is a file-local in its
-- options file, so there is nothing to read; the version is.
--
-- An entry with no `since` has been present since at least v8.3.8.
S.WINDOW_MAP = {
    { euiKey = "charsheet",       skins = { "Character", "Currency", "Reputation" } },
    { euiKey = "inspect",         skins = { "Inspect" } },
    { euiKey = "lfg",             skins = { "LFG" } },
    { euiKey = "greatvault",      skins = { "WeeklyRewards" } },
    { euiKey = "collections",     skins = { "Collectables" } },
    { euiKey = "playerspells",    skins = { "PlayerSpells", "TalentLoadoutsEx" } },
    { euiKey = "adventureguide",  skins = { "EncounterJournal" } },
    { euiKey = "professionsbook", skins = { "SpellBook", "Archaeology" } },
    { euiKey = "guild",           skins = { "Communities" } },
    { euiKey = "calendar",        skins = { "Calendar" } },
    { euiKey = "achievements",    skins = { "Achievement" } },
    { euiKey = "mail",            skins = { "Mail" } },
    { euiKey = "catalyst",        skins = { "ItemInteraction" } },
    { euiKey = "socket",          skins = { "Socket" } },
    { euiKey = "housing",         skins = { "Housing" } },
    { euiKey = "professions",     skins = { "Professions" } },
    { euiKey = "worldmap",        skins = { "WorldMap" } },
    { euiKey = "dressup",         skins = { "DressingRoom" } },
    { euiKey = "transmog",        skins = { "Transmog" } },
    { euiKey = "merchant",        skins = { "Merchant" } },
    { euiKey = "auctionhouse",    skins = { "AuctionHouse" } },
    { euiKey = "macros",          skins = { "Macro" } },
    { euiKey = "settings",        skins = { "SettingsPanel" } },
    { euiKey = "addonlist",       skins = { "AddonManager" } },
    { euiKey = "craftorders",     skins = { "ProfessionsOrders" } },
    { euiKey = "trainer",         skins = { "Trainer" } },
    { euiKey = "gossip",          skins = { "Gossip" } },
    { euiKey = "quest",           skins = { "Quest" } },
    { euiKey = "inspectrecipe",   skins = { "Professions" } },
    { euiKey = "delves",          skins = { "Delves" } },
    { euiKey = "itemupgrade",     skins = { "ItemUpgrade" },  since = "8.6.4" },
    { euiKey = "loot",            skins = { "Loot" },         since = "8.6.4" },
    { euiKey = "loottoast",       skins = { "Alerts" },       since = "8.6.4" },
    -- `micromenu` has no row: the reference ships no micro-menu skin and
    -- A0 deleted ours. `Guild` (GuildInviteFrame) is likewise absent on
    -- purpose -- the invite popup is not the Communities window that
    -- EllesmereUI's `guild` key covers.
}

-- Splits a version string into numeric segments. Anything unparseable
-- yields an empty list, which sorts LOWER than every real version -- the
-- fail-closed direction, because a `since` gate we cannot evaluate must
-- leave our own skin running rather than silently drop it.
local function segments(v)
    local out = {}
    if type(v) ~= "string" then return out end
    for part in v:gmatch("%d+") do
        out[#out + 1] = tonumber(part)
    end
    return out
end

--- Numeric-segment version compare. A missing segment counts as 0, so
--- "8.6" and "8.6.0" are equal. String compare would put "8.6.10" below
--- "8.6.4"; this does not.
---@return number -1 | 0 | 1
function S.CompareVersion(a, b)
    local sa, sb = segments(a), segments(b)
    for i = 1, math_max(#sa, #sb) do
        local x, y = sa[i] or 0, sb[i] or 0
        if x < y then return -1 end
        if x > y then return 1 end
    end
    return 0
end

--- Pure. Which of our skin keys EllesmereUI already covers.
--- env.loaded    boolean  EllesmereUIBlizzardSkin loaded AND enabled
--- env.version   string   its ## Version, or nil when unreadable
--- env.getStyle  function(euiKey) -> "off" | "eui" | "modern" | nil
---@return table set [skinKey] = euiKey; never nil
function KE:BuildSkinSuppressionSet(env)
    local set = {}
    if type(env) ~= "table" then return set end
    if not env.loaded then return set end
    if type(env.getStyle) ~= "function" then return set end

    for _, entry in ipairs(S.WINDOW_MAP) do
        -- A gated entry is skipped whenever the installed EllesmereUI is
        -- older than the version that introduced the key -- and an
        -- unreadable version sorts lower than every `since`, so it skips
        -- every gated entry too.
        local gated = entry.since
            and S.CompareVersion(env.version, entry.since) < 0
        if not gated then
            local style = env.getStyle(entry.euiKey)
            if style and style ~= "off" then
                for _, skinKey in ipairs(entry.skins) do
                    set[skinKey] = entry.euiKey
                end
            end
        end
    end

    return set
end

--- Live. Reads the globals, resolves once, caches on S.suppressed.
--- EllesmereUI installs its window skins at load and needs a reload to
--- cross the on/off boundary, so one read at login cannot go stale.
function KE:ResolveSkinSuppression()
    local loaded = false
    local version
    -- IsAddOnLoaded returns TWO booleans: loadedOrLoading, then loaded. Gate
    -- on the second -- the first is true for a still-loading addon, whose
    -- tables aren't populated yet
    -- (.wow-api-reference/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnsDocumentation.lua:322-336).
    if C_AddOns and C_AddOns.IsAddOnLoaded
        and select(2, C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin")) then
        -- DisableAddOn leaves an addon loaded for the rest of the session,
        -- so "loaded" alone would keep suppressing after the user turned
        -- EllesmereUI's skin addon off. Blizzard's own > 0 comparison:
        -- .wow-api-reference/.../Blizzard_AddOnList/AddonList.lua:188.
        loaded = not (C_AddOns.GetAddOnEnableState
            and (C_AddOns.GetAddOnEnableState("EllesmereUIBlizzardSkin") or 0) <= 0)
        if loaded and C_AddOns.GetAddOnMetadata then
            version = C_AddOns.GetAddOnMetadata("EllesmereUIBlizzardSkin", "Version")
        end
    end

    local getStyle
    local EUI = _G.EllesmereUI
    if loaded and type(EUI) == "table" and type(EUI.GetBlizzWindowStyle) == "function" then
        getStyle = function(key)
            local ok, style = pcall(EUI.GetBlizzWindowStyle, key)
            return ok and style or nil
        end
    end

    S.suppressed = self:BuildSkinSuppressionSet({
        loaded = loaded, version = version, getStyle = getStyle,
    })
    return S.suppressed
end

S.suppressed = {}
