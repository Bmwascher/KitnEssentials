-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/AuraTracking/PartyBuffs/PartyBuffsRules.lua     ║
-- ║  Purpose: pure decision logic for Party Buffs.           ║
-- ║  No WoW API, no frames -- so it is testable headlessly.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local math_ceil = math.ceil
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local type = type

local Rules = {}
KE.PartyBuffsRules = Rules

-- Array position is the on-screen order and each group's layoutIndex, so a
-- group added late still lands in its place. A list category filters plain
-- HELPFUL because a spell list can only narrow what the filter admits.
Rules.CATEGORIES = {
    { key = "external", filter = "HELPFUL", trackKey = "TrackExternal", listKey = "ListExternals",
      colorKey = "ColorExternal", excludeBlocklist = true },
    { key = "potion", filter = "HELPFUL", trackKey = "TrackPotion", listKey = "ListPotions",
      colorKey = "ColorPotion" },
    { key = "trinket", filter = "HELPFUL", trackKey = "TrackTrinket", listKey = "ListTrinkets",
      colorKey = "ColorTrinket", excludesCells = true },
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

-- The container rejects a fractional frame count, and a value typed into the
-- slider may reach the profile unrounded.
function Rules.IconCount(db)
    local count = type(db) == "table" and db.MaxPerMember
    if type(count) ~= "number" then return 0 end
    return math_floor(count + 0.5)
end

function Rules.CooldownIconCount(db)
    local count = type(db) == "table" and db.MaxCooldownIcons
    if type(count) ~= "number" then return 0 end
    return math_floor(count + 0.5)
end

function Rules.CellCount(entryCount, db)
    return math_min(entryCount, Rules.CooldownIconCount(db))
end

-- Max Cooldown Icons (6) plus Max Active Buff Icons (8): no row is longer.
Rules.MAX_PER_ROW = 14

-- Rounded as IconCount is; a value that is not a number never wraps.
function Rules.PerRow(value)
    if type(value) ~= "number" then return Rules.MAX_PER_ROW end
    return math_max(1, math_floor(value + 0.5))
end

-- Column and line of a 0-based index in a grid perLine wide.
function Rules.GridPosition(index, perLine)
    return index % perLine, math_floor(index / perLine)
end

local function Span(count, db)
    if count <= 0 then return 0 end
    return count * db.IconSize + (count - 1) * db.IconSpacing
end

-- The container wraps once its line plus the next icon passes this. The half
-- icon of slack keeps a fractional icon size from wrapping one icon early.
function Rules.LineSize(db, count)
    return Span(count, db) + db.IconSize / 2
end

-- Each category may fill the whole cap, so only the holder's clip holds the
-- cap: buff lines are at most cap wide and the holder fits the layout exactly.
-- Returns step, buffCol, buffLine, buffPerLine, width, height.
function Rules.RowLayout(db, cellCount, perRow)
    local step = db.IconSize + db.IconSpacing
    local buffs = Rules.IconCount(db)
    if cellCount + buffs <= perRow then
        return step, cellCount, 0, buffs, Span(cellCount + buffs, db), Span(1, db)
    end
    local buffLine = math_ceil(cellCount / perRow)
    local perLine = math_min(buffs, perRow)
    local lines = buffLine
    if perLine > 0 then lines = lines + math_ceil(buffs / perLine) end
    local width = Span(math_max(math_min(cellCount, perRow), perLine), db)
    return step, 0, buffLine, perLine, width, Span(math_max(lines, 1), db)
end

-- The spec can move the icons per row and the corner while the tracker is
-- off, with no event to say so, so each bind compares the last layout's inputs.
function Rules.NeedsLayout(slot, cellCount, perRow, corner)
    return slot.cellCount ~= cellCount or slot.layoutPerRow ~= perRow or slot.layoutCorner ~= corner
end

-- A refused pin may have cleared the old one, so a refusal clears the record
-- and the next pass pins again.
function Rules.NeedsPin(slot, corner, x, y)
    return slot.corner ~= corner or slot.pinX ~= x or slot.pinY ~= y
end

function Rules.RecordPin(slot, ok, corner, x, y)
    if ok then
        slot.corner, slot.pinX, slot.pinY = corner, x, y
    else
        slot.corner, slot.pinX, slot.pinY = nil, nil, nil
    end
end

-- The only producer of a group's container settings, for creation and for
-- every reconfiguration.
function Rules.BuildGroupConfig(category, db, cellBuffs)
    local auraRules = KE.AuraRules
    local candidates = {}
    if category.listKey then
        candidates.includeSpellIDs = auraRules.BuildIncludeSpellIDs(db[category.listKey])
    end
    if category.excludeBlocklist then
        candidates.excludeSpellIDs = auraRules.BuildExcludeSpellIDs(nil)
    end
    -- A trinket shown as a cooldown icon on this row is left out here.
    if category.excludesCells and cellBuffs then candidates.excludeSpellIDs = cellBuffs end
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
-- frame, family and the own-frame facts. The own frame is kept only with
-- includeSelf, and only the first: one frame can show you as player and
-- another as raid<N>.
function Rules.PickFrames(candidates, maxSlots, includeSelf)
    local bindings, seen = {}, {}
    local selfTaken = false
    if type(candidates) ~= "table" then return bindings end
    for i = 1, #candidates do
        if #bindings >= maxSlots then break end
        local candidate = candidates[i]
        if type(candidate) == "table" then
            local token = candidate.token
            if type(token) == "string" and not seen[token] and candidate.visible == true then
                local own = Rules.IsPlayerCandidate(candidate)
                if not own or (includeSelf == true and not selfTaken) then
                    seen[token] = true
                    if own then selfTaken = true end
                    bindings[#bindings + 1] = {
                        token = token, frame = candidate.frame, family = candidate.family, fixed = candidate.fixed,
                    }
                end
            end
        end
    end
    return bindings
end

-- After a roster change a row stays up only while its frame still shows its
-- token (frames can re-sort their units) and the token still names the same
-- member. A frame bound to a fixed token shows a vehicle while you ride one,
-- so its own unit is not compared.
function Rules.KeepRow(binding, frameToken, sameMember)
    if type(binding) ~= "table" or sameMember ~= true then return false end
    return binding.fixed == true or frameToken == binding.token
end

-- The slot each binding takes: back to the slot already holding its token, so
-- a frame search in a new order does not hand a member's counts to another
-- slot; the rest fill the free slots in order.
function Rules.MatchSlots(bindings, units, maxSlots)
    local placed, used = {}, {}
    for i = 1, #bindings do
        for k = 1, maxSlots do
            if not placed[k] and units[k] == bindings[i].token then
                placed[k], used[i] = bindings[i], true
                break
            end
        end
    end
    local k = 1
    for i = 1, #bindings do
        if not used[i] then
            while k <= maxSlots and placed[k] do k = k + 1 end
            if k > maxSlots then break end
            placed[k] = bindings[i]
        end
    end
    return placed
end

-- The placement fields a healer copy can override, as { default key, healer key },
-- in the order ActivePlacement returns them.
Rules.PLACEMENT_KEYS = {
    { "Side", "HealerSide" },
    { "XOffset", "HealerXOffset" },
    { "YOffset", "HealerYOffset" },
    { "Strata", "HealerStrata" },
    { "IconsPerRow", "HealerIconsPerRow" },
}

-- Side, X, Y, strata and icons per row to use. An unseeded healer key reads
-- its default counterpart, so a profile with the toggle on and no copy
-- changes nothing.
function Rules.ActivePlacement(db, useHealer)
    local healer = useHealer and db.UseHealerPlacement == true
    local function pick(pair)
        local value = healer and db[pair[2]]
        if value == nil or value == false then value = db[pair[1]] end
        return value
    end
    local keys = Rules.PLACEMENT_KEYS
    return pick(keys[1]), pick(keys[2]), pick(keys[3]), pick(keys[4]), pick(keys[5])
end

-- Preview row k's sample spell for a list category. A sample the player
-- switched off in the list gives way to the list's first switched-on spell,
-- as the live icons would never show it.
function Rules.PreviewSample(samples, k, key, list)
    local auraRules = KE.AuraRules
    local spellID = samples[(k - 1) % #samples + 1][key]
    if list and spellID and auraRules.IsIncluded(spellID, list[spellID]) then return spellID end
    return auraRules.FirstIncludeSpellID(list)
end

-- Fills absent healer keys from their defaults; an edited copy is kept.
function Rules.SeedHealerPlacement(db)
    for _, pair in ipairs(Rules.PLACEMENT_KEYS) do
        if db[pair[2]] == nil then db[pair[2]] = db[pair[1]] end
    end
end
