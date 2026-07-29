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
    -- TalentLoadoutsEx is deliberately NOT listed here. Its skin styles only
    -- TalentLoadoutExMainFrame (a third-party window) and merely anchors
    -- itself beside PlayerSpellsFrame; EllesmereUI never touches that addon
    -- (grep across every vendored EUI version: zero matches), so suppressing
    -- it under this key hid our skin against a collision that does not exist.
    { euiKey = "playerspells",    skins = { "PlayerSpells" } },
    { euiKey = "adventureguide",  skins = { "EncounterJournal" } },
    { euiKey = "professionsbook", skins = { "SpellBook", "Archaeology" } },
    { euiKey = "guild",           skins = { "Communities" } },
    { euiKey = "calendar",        skins = { "Calendar" } },
    { euiKey = "achievements",    skins = { "Achievement" } },
    { euiKey = "mail",            skins = { "Mail" } },
    { euiKey = "catalyst",        skins = { "ItemInteraction" } },
    { euiKey = "socket",          skins = { "Socket" } },
    -- `addons` is SPARSE by design: populate it only where EllesmereUI
    -- declares a filter AND our key out-registers it (today: exactly the two
    -- rows below). EllesmereUI's RegisterWindow declarations are NOT a
    -- complete record of what it skins -- `inspect`, `lfg` and `greatvault`
    -- have no declaration block at all, and their coverage lives in
    -- pre-engine files (EllesmereUIBlizzardSkin.lua:61-69). Completing this
    -- field for every row from declarations alone would therefore silently
    -- un-suppress our skin underneath one of those.
    { euiKey = "housing",         skins = { "Housing" },
      -- EllesmereUIBlizzardSkin_WindowPacks.lua:5890-5892: the declared
      -- filter names exactly one addon; our key covers nine windows.
      addons = { "Blizzard_HousingDashboard" },
      partialLabel = "Housing (EllesmereUI: dashboard only)",
      partialTooltip = "EllesmereUI currently skins Housing Dashboard. While that overlap is active, this toggle controls KitnEssentials' other eight Housing windows. Your saved choice also applies to the dashboard if EllesmereUI stops covering it." },
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
    { euiKey = "inspectrecipe",   skins = { "InspectRecipe" } },
    { euiKey = "delves",          skins = { "Delves" },
      -- EllesmereUIBlizzardSkin_WindowPacks.lua:8464-8466: the declared
      -- filter names exactly one addon; our key covers three windows.
      addons = { "Blizzard_DelvesCompanionConfiguration" },
      partialLabel = "Delves (EllesmereUI: companion only)",
      partialTooltip = "EllesmereUI currently skins Companion Configuration. While that overlap is active, this toggle controls Difficulty Picker and Delves Dashboard. Your saved choice also applies to Companion Configuration if EllesmereUI stops covering it." },
    { euiKey = "itemupgrade",     skins = { "ItemUpgrade" },  since = "8.6.4" },
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
---@return table set [skinKey] = euiKey (unfiltered row) | resolved record
---                   { euiKey, addons, partialLabel, partialTooltip }
---                   (filtered row); never nil
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
                -- SPARSE on purpose: only a filtered row (one with `addons`)
                -- gets a table value. A uniform record would give every
                -- already-ported key with a row (Socket today) a table too,
                -- and those keys DO get dispatched, so the concatenation at
                -- SkinAPI.lua:2698 would hit a table the first time anyone
                -- ran /kes skins verify. Step 4 removes that crash
                -- regardless; sparse means it was never reachable at all.
                local value = entry.euiKey
                if entry.addons then
                    local addons = {}
                    for _, addonName in ipairs(entry.addons) do
                        addons[addonName] = true
                    end
                    value = {
                        euiKey = entry.euiKey,
                        addons = addons,
                        partialLabel = entry.partialLabel,
                        partialTooltip = entry.partialTooltip,
                    }
                end
                for _, skinKey in ipairs(entry.skins) do
                    set[skinKey] = value
                end
            end
        end
    end

    return set
end

-- Nothing outside this layer may ever index S.suppressed directly again --
-- go through these two accessors instead.

--- Is THIS ONE registration suppressed? Returns the owning euiKey string
--- when it is, nil when it is not.
---@param key string # skin key (S.skinIndex / S.skinStatus key)
---@param addon string? # the Blizzard addon this registration came from
---@return string? euiKey
function S.GetSuppression(key, addon)
    local entry = S.suppressed and S.suppressed[key]
    if entry == nil then return nil end
    if type(entry) == "string" then
        -- Unfiltered row: covers the whole key, including when `addon` is
        -- nil -- an early registration has no addon to match, but an
        -- unfiltered row was never scoped to one.
        return entry
    end
    if addon == nil then
        -- Filtered row: the opposite nil rule from the string case above.
        -- An early registration has no addon to match, and a filtered row
        -- only claims the addons it names -- it cannot claim "no addon".
        return nil
    end
    -- entry.addons is always set by BuildSkinSuppressionSet, but a later
    -- task or a spec seeding S.suppressed by hand could hand a filtered
    -- record with no addons table, so guard the index rather than trust it.
    if entry.addons and entry.addons[addon] then return entry.euiKey end
    return nil
end

--- How much of `key` does EllesmereUI own?
---@param key string
---@return string state # "none" | "full" | "partial"
---@return string? euiKey
---@return string? partialLabel
---@return string? partialTooltip
function S.GetSuppressionState(key)
    local entry = S.suppressed and S.suppressed[key]
    if entry == nil then return "none" end
    if type(entry) == "string" then return "full", entry end
    return "partial", entry.euiKey, entry.partialLabel, entry.partialTooltip
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
