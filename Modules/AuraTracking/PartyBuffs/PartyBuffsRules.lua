-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/AuraTracking/PartyBuffs/PartyBuffsRules.lua     ║
-- ║  Purpose: pure decision logic for Party Buffs.           ║
-- ║  No WoW API, no frames -- so it is testable headlessly.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local pairs = pairs
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

-- The Max Cooldown Icons and Max Active Buff Icons slider ceilings. A row
-- holds both, so no row is longer than their sum.
Rules.MAX_COOLDOWN_ICONS = 6
Rules.MAX_BUFF_ICONS = 8
Rules.MAX_PER_ROW = Rules.MAX_COOLDOWN_ICONS + Rules.MAX_BUFF_ICONS

-- Rounded as IconCount is; a value that is not a number never wraps.
function Rules.PerRow(value)
    if type(value) ~= "number" then return Rules.MAX_PER_ROW end
    return math_max(1, math_floor(value + 0.5))
end

-- Column and line of a 0-based index in a grid perLine wide.
function Rules.GridPosition(index, perLine)
    return index % perLine, math_floor(index / perLine)
end

local function Span(count, size, spacing)
    if count <= 0 then return 0 end
    return count * size + (count - 1) * spacing
end

-- The container wraps once its line plus the next icon passes this. The half
-- icon of slack keeps a fractional icon size from wrapping one icon early.
function Rules.LineSize(db, count, size)
    return Span(count, size, db.IconSpacing) + size / 2
end

-- Each category may fill the whole cap, so only the holder's clip holds the
-- cap: buff lines are at most cap wide and the holder fits the layout exactly.
-- Returns step, buffCol, buffLine, buffPerLine, width, height.
function Rules.RowLayout(db, cellCount, perRow, size)
    local spacing = db.IconSpacing
    local step = size + spacing
    local buffs = Rules.IconCount(db)
    if cellCount + buffs <= perRow then
        return step, cellCount, 0, buffs, Span(cellCount + buffs, size, spacing), Span(1, size, spacing)
    end
    local buffLine = math_ceil(cellCount / perRow)
    local perLine = math_min(buffs, perRow)
    local lines = buffLine
    if perLine > 0 then lines = lines + math_ceil(buffs / perLine) end
    local width = Span(math_max(math_min(cellCount, perRow), perLine), size, spacing)
    return step, 0, buffLine, perLine, width, Span(math_max(lines, 1), size, spacing)
end

-- The spec can move the icons per row and the corner while the tracker is
-- off, with no event to say so, so each bind compares the last layout's inputs.
-- The corner fixes every direction inside the holder (LAYOUTS); the holder's
-- own anchor is set on every bind (PB:PlaceHolder).
function Rules.NeedsLayout(slot, cellCount, perRow, corner)
    return slot.cellCount ~= cellCount or slot.layoutPerRow ~= perRow or slot.layoutCorner ~= corner
end

-- dressedSize is nil before the first dressing.
function Rules.NeedsResize(dressedSize, size)
    return dressedSize ~= size
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

-- Per side, the layouts its Grow can pick; an unset Grow gets the first.
-- point/rel place the holder on the party frame, dx/dy scale the icon gap, and
-- corner is where the container is pinned and grows away from. None grows
-- toward its frame: Left and Right run their lines outward, Above wraps up and
-- Below wraps down. lift raises the holder by that many icons: a Center
-- layout pins its top half an icon above the frame's middle, so its first
-- line centers on the frame and further lines hang below it.
Rules.LAYOUTS = {
    LEFT = {
        { grow = "CENTER", point = "TOPRIGHT",    rel = "LEFT",        dx = -1, dy = 0, corner = "TOPRIGHT",
          lift = 0.5 },
        { grow = "DOWN",   point = "TOPRIGHT",    rel = "TOPLEFT",     dx = -1, dy = 0, corner = "TOPRIGHT" },
        { grow = "UP",     point = "BOTTOMRIGHT", rel = "BOTTOMLEFT",  dx = -1, dy = 0, corner = "BOTTOMRIGHT" },
    },
    RIGHT = {
        { grow = "CENTER", point = "TOPLEFT",     rel = "RIGHT",       dx = 1,  dy = 0, corner = "TOPLEFT",
          lift = 0.5 },
        { grow = "DOWN",   point = "TOPLEFT",     rel = "TOPRIGHT",    dx = 1,  dy = 0, corner = "TOPLEFT" },
        { grow = "UP",     point = "BOTTOMLEFT",  rel = "BOTTOMRIGHT", dx = 1,  dy = 0, corner = "BOTTOMLEFT" },
    },
    ABOVE = {
        { grow = "RIGHT", point = "BOTTOMLEFT",  rel = "TOPLEFT",  dx = 1,  dy = 1, corner = "BOTTOMLEFT" },
        { grow = "LEFT",  point = "BOTTOMRIGHT", rel = "TOPRIGHT", dx = -1, dy = 1, corner = "BOTTOMRIGHT" },
    },
    BELOW = {
        { grow = "RIGHT", point = "TOPLEFT",  rel = "BOTTOMLEFT",  dx = 1,  dy = -1, corner = "TOPLEFT" },
        { grow = "LEFT",  point = "TOPRIGHT", rel = "BOTTOMRIGHT", dx = -1, dy = -1, corner = "TOPRIGHT" },
    },
    INSIDE = {
        { grow = "LEFT", point = "BOTTOMRIGHT", rel = "BOTTOMRIGHT", dx = -1, dy = 1, corner = "BOTTOMRIGHT" },
    },
}
-- A layout grows away from its corner, so the corner alone sets its directions,
-- and two layouts with one corner lay out alike inside the holder.
for _, layouts in pairs(Rules.LAYOUTS) do
    for _, layout in ipairs(layouts) do
        layout.left = layout.corner:sub(-5) == "RIGHT"
        layout.up = layout.corner:sub(1, 6) == "BOTTOM"
    end
end

function Rules.HolderOffset(layout, gap, x, y, size)
    return layout.dx * gap + x, layout.dy * gap + y + (layout.lift or 0) * size
end

-- The fields a healer copy can override, as { default key, healer key }, in
-- the order ActivePlacement returns them.
Rules.PLACEMENT_KEYS = {
    { "Side", "HealerSide" },
    { "XOffset", "HealerXOffset" },
    { "YOffset", "HealerYOffset" },
    { "IconsPerRow", "HealerIconsPerRow" },
    { "IconSize", "HealerIconSize" },
    { "Grow", "HealerGrow" },
}

-- A healer key that is nil or false reads its default counterpart. The
-- settings page shows its values through this too, so the two agree.
function Rules.PlacementValue(db, pair, healer)
    local value = healer and db[pair[2]]
    if value == nil or value == false then value = db[pair[1]] end
    return value
end

-- Side, X, Y, icons per row, icon size and grow to use. A healer key
-- with no profile default reads its default counterpart while unset; the
-- healer icons per row and icon size have profile defaults of their own.
function Rules.ActivePlacement(db, useHealer)
    local healer = useHealer and db.UseHealerPlacement == true
    local function pick(pair)
        return Rules.PlacementValue(db, pair, healer)
    end
    local keys = Rules.PLACEMENT_KEYS
    return pick(keys[1]), pick(keys[2]), pick(keys[3]), pick(keys[4]), pick(keys[5]), pick(keys[6])
end

-- The layout in effect and its side's list. An unknown side reads as LEFT, and
-- a Grow the side does not offer, unset included, as the side's first layout;
-- the stored Grow is never rewritten.
function Rules.Layout(side, grow)
    local layouts = Rules.LAYOUTS[side] or Rules.LAYOUTS.LEFT
    for i = 1, #layouts do
        if layouts[i].grow == grow then return layouts[i], layouts end
    end
    return layouts[1], layouts
end

-- Preview row k's sample spells for a list category, starting from the row's
-- own sample. Samples the list switches off and spells in skip are left out,
-- as the live icons would never show them; with none left, the list's first
-- switched-on spell not in skip stands in.
function Rules.PreviewSamples(samples, k, key, list, skip)
    local auraRules = KE.AuraRules
    local out, seen = {}, {}
    skip = skip or {}
    for j = 0, #samples - 1 do
        local spellID = samples[(k - 1 + j) % #samples + 1][key]
        if list and spellID and not seen[spellID] and not skip[spellID]
            and auraRules.IsIncluded(spellID, list[spellID]) then
            seen[spellID] = true
            out[#out + 1] = spellID
        end
    end
    if #out == 0 and list then
        local first
        for spellID, record in pairs(list) do
            if not skip[spellID] and auraRules.IsIncluded(spellID, record) and (first == nil or spellID < first) then
                first = spellID
            end
        end
        out[1] = first
    end
    return out
end

-- How many buff samples each tracked category draws, in category order: dealt
-- one at a time round the categories that still have one, so the cap splits
-- evenly and a category short of samples passes its share on.
function Rules.SplitBuffSamples(cap, available)
    local counts, left = {}, cap
    for i = 1, #available do counts[i] = 0 end
    local dealt = true
    while left > 0 and dealt do
        dealt = false
        for i = 1, #available do
            if left > 0 and counts[i] < available[i] then
                counts[i] = counts[i] + 1
                left = left - 1
                dealt = true
            end
        end
    end
    return counts
end

-- Fills absent healer keys from their default counterparts; an edited copy is
-- kept. A healer key with a profile default is never absent, so it keeps that
-- default.
function Rules.SeedHealerPlacement(db)
    for _, pair in ipairs(Rules.PLACEMENT_KEYS) do
        if db[pair[2]] == nil then db[pair[2]] = db[pair[1]] end
    end
end
