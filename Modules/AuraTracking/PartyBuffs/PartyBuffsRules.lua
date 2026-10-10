-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/PartyBuffsRules.lua                      ║
-- ║  Purpose: pure decision logic for Party Buffs.           ║
-- ║  No WoW API, no frames -- so it is testable headlessly.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local math_floor = math.floor
local pairs = pairs
local type = type

local Rules = {}
KE.PartyBuffsRules = Rules

-- Array position is the on-screen order and each group's layoutIndex, so a
-- group added late still lands in its place. A list category filters plain
-- HELPFUL because a spell list can only narrow what the filter admits.
Rules.CATEGORIES = {
    { key = "external", filter = "HELPFUL", trackKey = "TrackExternal", listKey = "ListExternals",
      colorKey = "ColorExternal", excludeBlocklist = true },
    { key = "big", filter = "HELPFUL|BIG_DEFENSIVE", trackKey = "TrackBigDefensive",
      colorKey = "ColorBigDefensive", excludeBlocklist = true, excludeTrackedExternals = true },
    { key = "burst", filter = "HELPFUL", trackKey = "TrackBurst", listKey = "ListBurst",
      colorKey = "ColorBurst" },
    { key = "potion", filter = "HELPFUL", trackKey = "TrackPotion", listKey = "ListPotions",
      colorKey = "ColorPotion" },
    { key = "trinket", filter = "HELPFUL", trackKey = "TrackTrinket", listKey = "ListTrinkets",
      colorKey = "ColorTrinket" },
}
for i, category in ipairs(Rules.CATEGORIES) do
    category.index = i
end

local SHOW_IN = {
    key     = "ShowInKeys",
    dungeon = "ShowInDungeons",
    delve   = "ShowInDelves",
    world   = "ShowInWorld",
    arena   = "ShowInArenas",
}

-- Raids, battlegrounds, brawls and scenarios other than a Delve fall through
-- to nil, which no place setting can switch on.
function Rules.ClassifyContent(facts)
    if type(facts) ~= "table" then return nil end
    if facts.challengeActive == true then return "key" end
    if facts.delveActive == true then return "delve" end
    local arena = facts.arena == true or facts.instanceType == "arena"
    if arena and facts.brawl ~= true then return "arena" end
    if facts.instanceType == "party" then return "dungeon" end
    if facts.inInstance == false then return "world" end
    return nil
end

-- An arena team is a raid group, and the only raid group tracked.
function Rules.ShouldActivate(db, content, inGroup, inRaid)
    if type(db) ~= "table" or db.Enabled ~= true then return false end
    if inGroup ~= true or content == nil then return false end
    local showKey = SHOW_IN[content]
    if not showKey or db[showKey] ~= true then return false end
    if inRaid == true and content ~= "arena" then return false end
    return true
end

local function CopySet(source)
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    return copy
end

-- The container rejects a fractional frame count, and a value typed into the
-- slider may reach the profile unrounded.
function Rules.IconCount(db)
    local count = type(db) == "table" and db.MaxPerMember
    if type(count) ~= "number" then return 0 end
    return math_floor(count + 0.5)
end

-- The only producer of a group's container settings, for creation and for
-- every reconfiguration. While Externals are tracked, a spell that is both
-- tagged and listed shows once, under External.
function Rules.BuildGroupConfig(category, db)
    local auraRules = KE.AuraRules
    local candidates = {}
    if category.listKey then
        candidates.includeSpellIDs = auraRules.BuildIncludeSpellIDs(db[category.listKey])
    end
    if category.excludeBlocklist then
        local exclude = auraRules.BuildExcludeSpellIDs(nil)
        if category.excludeTrackedExternals and db.TrackExternal == true then
            -- The blocklist set is shared with other displays and must not be
            -- mutated.
            exclude = CopySet(exclude)
            for spellID in pairs(auraRules.BuildIncludeSpellIDs(db.ListExternals)) do
                exclude[spellID] = true
            end
        end
        candidates.excludeSpellIDs = exclude
    end
    local maxFrames = 0
    if db[category.trackKey] == true then maxFrames = Rules.IconCount(db) end
    return category.filter, candidates, maxFrames, category.index
end

-- displayedUnit is never read: on a compact frame it becomes the vehicle.
function Rules.CandidateToken(candidate)
    if type(candidate) ~= "table" then return nil end
    if type(candidate.unit) == "string" then return candidate.unit end
    if type(candidate.attrUnit) == "string" then return candidate.attrUnit end
    return nil
end

-- True only when a check can tell. An unreadable answer tracks the frame:
-- icons on the player's own frame are acceptable, a hidden teammate is not.
function Rules.IsPlayerCandidate(facts)
    if type(facts) ~= "table" then return false end
    local token = facts.token
    if token == "player" then return true end
    if type(facts.raidIndex) == "number" and token == "raid" .. facts.raidIndex then return true end
    return facts.compareOk == true and facts.compareSecret == false and facts.compareResult == true
end

-- Candidates arrive in family order, each carrying its token, visibility,
-- frame, family and the own-frame facts.
function Rules.PickFrames(candidates, maxSlots)
    local bindings, seen = {}, {}
    if type(candidates) ~= "table" then return bindings end
    for i = 1, #candidates do
        if #bindings >= maxSlots then break end
        local candidate = candidates[i]
        if type(candidate) == "table" then
            local token = candidate.token
            if type(token) == "string" and not seen[token] and candidate.visible == true
                and not Rules.IsPlayerCandidate(candidate) then
                seen[token] = true
                bindings[#bindings + 1] = { token = token, frame = candidate.frame, family = candidate.family }
            end
        end
    end
    return bindings
end

-- The placement fields a healer copy can override, as { default key, healer key },
-- in the order ActivePlacement returns them.
Rules.PLACEMENT_KEYS = {
    { "Side", "HealerSide" },
    { "XOffset", "HealerXOffset" },
    { "YOffset", "HealerYOffset" },
    { "Strata", "HealerStrata" },
}

-- Side, X, Y and Strata to use. An unseeded healer key reads its default
-- counterpart, so a profile with the toggle on and no copy changes nothing.
function Rules.ActivePlacement(db, useHealer)
    local healer = useHealer and db.UseHealerPlacement == true
    local function pick(pair)
        local value = healer and db[pair[2]]
        if value == nil or value == false then value = db[pair[1]] end
        return value
    end
    local keys = Rules.PLACEMENT_KEYS
    return pick(keys[1]), pick(keys[2]), pick(keys[3]), pick(keys[4])
end

-- Fills absent healer keys from their defaults; an edited copy is kept.
function Rules.SeedHealerPlacement(db)
    for _, pair in ipairs(Rules.PLACEMENT_KEYS) do
        if db[pair[2]] == nil then db[pair[2]] = db[pair[1]] end
    end
end
