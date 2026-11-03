-- ╔══════════════════════════════════════════════════════════╗
-- ║  HealerExternalsRules.lua                                ║
-- ║  Purpose: pure rules for the raid cooldowns box.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local math_ceil = math.ceil
local math_floor = math.floor
local math_huge = math.huge
local math_max = math.max
local math_min = math.min
local pairs = pairs
local string_find = string.find
local table_sort = table.sort
local type = type

local Rules = {}
KE.HealerExternalsRules = Rules

-- A group tracker's read passes its stamp through up to two client
-- evaluations per watched unit, a charge cell's two more plus five a second
-- from its tick, so the door bound needs Unit(cd) <= 2, which holds up to 508
-- seconds. Never raise this above 508.
Rules.CD_MAX = 360

-- Seconds after a raid cooldown's plain start in which a rise only records,
-- so a caster stepping out of their zone and back in does not restart it:
-- longer than any such zone lasts, shorter than any such cooldown.
Rules.RAID_QUIET = 15

-- The roles a party member can be assigned; any other answer says nothing.
local ASSIGNED = { DAMAGER = true, TANK = true, HEALER = true }
local HEALER_ROLE = { HEALER = true }
local GROUPS = { "target", "owner" }
local IN_GROUP = { target = true, owner = true }

local function Table(value)
    if type(value) == "table" then return value end
    return {}
end

-- The party cooldowns clamp, then at most CD_MAX; nil when not a number.
function Rules.ClampSeconds(value)
    local seconds = KE.PartyCooldownsRules.ClampSeconds(value)
    if not seconds then return nil end
    return math_min(Rules.CD_MAX, seconds)
end

function Rules.Key(specID, castID) return "healer:" .. KE.PartyCooldownsRules.CooldownKey(specID, castID) end

-- A box row's switch. A class-wide row shows before the spec is known, so
-- the key names no spec.
function Rules.BoxKey(castID) return "box:" .. castID end

-- The spec's externals in table order, at the healer's talented lengths once
-- ranks are read, capped at CD_MAX. A switched-off entry is dropped unless all
-- is set, which the editor uses to list every one.
function Rules.Entries(specID, db, all, ranks)
    local data = KE.PartyCooldownsData
    local cdRules = KE.PartyCooldownsRules
    local out = {}
    local row = Table(data.HEALER_SPECS)[specID]
    if not row then return out end
    db = Table(db)
    local off = Table(db.CooldownOff)
    for _, castID in ipairs(row.casts) do
        local spell = data.SPELLS[castID]
        local key = Rules.Key(specID, castID)
        local isOff = cdRules.IsOff(off, key, spell)
        if spell and (all or not isOff) then
            local entry = {
                id = castID, key = key, spell = spell, kind = spell.kind, buffs = spell.buffs,
                listed = spell.cd,
                cd = Rules.ClampSeconds(spell.cd),
                off = isOff, group = "target",
            }
            entry.charges = cdRules.CellCharges(entry, specID, ranks)
            entry.cd = Rules.ClampSeconds(cdRules.CellLength(entry, specID, ranks, entry.charges))
            out[#out + 1] = entry
        end
    end
    return out
end

-- Whether a member of class and spec owns the row: by spec once it is known,
-- by class alone before then for a class-wide row.
function Rules.Owns(row, class, specID)
    if class == nil or row.class ~= class then return false end
    if specID == nil then return row.anySpec == true end
    return Table(row.specs)[specID] == true
end

-- One box row's entry at the member's talented length once ranks are read,
-- and whether its talent rule is read as taken (nil while unread). show is
-- the spell whose icon the cell draws. A switched-off row is nil unless all
-- is set, which the editor uses to list every one.
function Rules.BoxEntry(row, specID, db, all, ranks)
    local cdRules = KE.PartyCooldownsRules
    local spell = KE.PartyCooldownsData.SPELLS[row.id]
    if not spell then return nil end
    local key = Rules.BoxKey(row.id)
    local isOff = cdRules.IsOff(Table(Table(db).CooldownOff), key, spell)
    if isOff and not all then return nil end
    local entry = {
        id = row.id, key = key, spell = spell, kind = spell.kind, buffs = spell.buffs,
        listed = spell.cd, cd = Rules.ClampSeconds(spell.cd), off = isOff, group = row.watch,
    }
    if row.watch == "owner" then entry.quiet = Rules.RAID_QUIET end
    entry.charges = cdRules.CellCharges(entry, specID, ranks)
    entry.cd = Rules.ClampSeconds(cdRules.CellLength(entry, specID, ranks, entry.charges))
    local taken = cdRules.CastTaken(specID, row.id, ranks)
    entry.show = cdRules.ShowID(entry, specID, taken)
    return entry, taken
end

-- The rows a member of class and spec owns, in table order. One whose talent
-- rule refuses it, read as not taken or unread and unlikely, is dropped
-- unless all is set.
function Rules.BoxEntries(class, specID, db, all, ranks)
    local cdRules = KE.PartyCooldownsRules
    local out = {}
    for _, row in ipairs(Table(KE.PartyCooldownsData.BOX_ROWS)) do
        if Rules.Owns(row, class, specID) then
            local entry, taken = Rules.BoxEntry(row, specID, db, all, ranks)
            if entry and (all or cdRules.TalentAllows(entry, taken, specID)) then out[#out + 1] = entry end
        end
    end
    return out
end

-- members: the party in token order, each { token, guid, spec, class,
-- talents }. Returns each one with a switched-on entry, as { member,
-- entries }: its spec's externals, then the box rows it owns.
function Rules.Sources(members, db)
    local out = {}
    for _, m in ipairs(members) do
        local entries = Rules.Entries(m.spec, db, false, m.talents)
        for _, e in ipairs(Rules.BoxEntries(m.class, m.spec, db, false, m.talents)) do
            entries[#entries + 1] = e
        end
        if #entries > 0 then out[#out + 1] = { member = m, entries = entries } end
    end
    return out
end

-- Every cast the box can show, in shipped order: the healer externals by
-- spec ID, then the box rows. A saved order's known casts come first, each
-- once, then any it lacks in shipped order, so a spell added in an update
-- still has a place. Anything but a table reads as the shipped order.
function Rules.CastOrder(saved)
    local data = KE.PartyCooldownsData
    local shipped, known, specs = {}, {}, {}
    for specID in pairs(Table(data.HEALER_SPECS)) do specs[#specs + 1] = specID end
    table_sort(specs)
    for _, specID in ipairs(specs) do
        for _, castID in ipairs(data.HEALER_SPECS[specID].casts) do
            if not known[castID] then shipped[#shipped + 1], known[castID] = castID, true end
        end
    end
    for _, row in ipairs(Table(data.BOX_ROWS)) do
        if not known[row.id] then shipped[#shipped + 1], known[row.id] = row.id, true end
    end
    if type(saved) ~= "table" then return shipped end
    local out, seen = {}, {}
    for _, id in ipairs(saved) do
        if known[id] and not seen[id] then out[#out + 1], seen[id] = id, true end
    end
    for _, id in ipairs(shipped) do
        if not seen[id] then out[#out + 1] = id end
    end
    return out
end

-- The box's cells. With no saved order: every target entry, source by
-- source, then every owner entry the same way. With one: every entry by its
-- cast's place in CastOrder, then by source and entry, so a cast two members
-- share shows yours first; table.sort is not stable, so the tie-break is
-- explicit. Each keeps its owner's GUID, so a count follows its owner when
-- the list shifts; an owner entry watches its owner's unit alone.
function Rules.Order(sources, saved)
    local out = {}
    if type(saved) ~= "table" then
        for _, group in ipairs(GROUPS) do
            for _, source in ipairs(sources) do
                local m = source.member
                for _, e in ipairs(source.entries) do
                    if e.group == group then
                        e.owner = m.guid
                        if group == "owner" then e.units = { m.token } end
                        out[#out + 1] = e
                    end
                end
            end
        end
        return out
    end
    local rank, seq = {}, {}
    for i, id in ipairs(Rules.CastOrder(saved)) do rank[id] = i end
    for _, source in ipairs(sources) do
        local m = source.member
        for _, e in ipairs(source.entries) do
            if IN_GROUP[e.group] then
                e.owner = m.guid
                if e.group == "owner" then e.units = { m.token } end
                out[#out + 1] = e
                seq[e] = #out
            end
        end
    end
    table_sort(out, function(a, b)
        local ra, rb = rank[a.id] or math_huge, rank[b.id] or math_huge
        if ra ~= rb then return ra < rb end
        return seq[a] < seq[b]
    end)
    return out
end

-- Whether a role leaves a row's specs possible: unread or unassigned says
-- nothing, else it must be one their specs fill.
local function RoleFits(roles, role)
    return role == nil or not ASSIGNED[role] or roles[role] == true
end

-- Whether a member is worth an inspect for the box: a class with a
-- switched-on class-wide row in any role, or a switched-on healer external or
-- spec row in a role those specs could fill. A class whose rows are all off
-- has nothing in the box, so no inspect is spent on it.
function Rules.Candidate(class, role, db)
    if type(class) ~= "string" then return false end
    local data = KE.PartyCooldownsData
    local cdRules = KE.PartyCooldownsRules
    local off = Table(Table(db).CooldownOff)
    for _, row in ipairs(Table(data.BOX_ROWS)) do
        if row.class == class and (row.anySpec == true or RoleFits(Table(row.roles), role))
            and not cdRules.IsOff(off, Rules.BoxKey(row.id), data.SPELLS[row.id]) then
            return true
        end
    end
    for specID, row in pairs(Table(data.HEALER_SPECS)) do
        if row.class == class and RoleFits(HEALER_ROLE, role) then
            for _, castID in ipairs(row.casts) do
                if not cdRules.IsOff(off, Rules.Key(specID, castID), data.SPELLS[castID]) then return true end
            end
        end
    end
    return false
end

-- Whether the box wants a member's spec and talents read. The inspect's spec
-- test and its talent test both ask this, so a row that ships off costs
-- neither.
function Rules.WantsMember(boxOn, class, role, db)
    return boxOn == true and Rules.Candidate(class, role, db)
end

-- A party only: KE counts an arena team as a raid group.
function Rules.On(db, active, inRaid)
    return Table(db).HealerExternals == true and active == true and inRaid ~= true
end

-- Whether an Edit Mode position detaches a box: only a move away from the
-- starting place while that place stands in for an anchor that is unnamed,
-- missing or refused. Edit Mode hands back the current position after a canceled drag,
-- and on a revert the position the mover started from, which is the starting
-- place if unmoved.
function Rules.MoverDetaches(fallback, pos, start)
    if fallback ~= true then return false end
    return not (pos.AnchorFrom == start.AnchorFrom and pos.AnchorTo == start.AnchorTo
        and pos.XOffset == start.XOffset and pos.YOffset == start.YOffset)
end

-- The saved position table under key, for every reader and writer of it. A
-- value that is not a table, from a bad import or a hand edit, is replaced
-- by an empty one, so no reader indexes it and a drop still saves.
function Rules.PositionTable(db, key)
    local pos = db[key]
    if type(pos) == "table" then return pos end
    pos = {}
    db[key] = pos
    return pos
end

-- The page's view wins while the box previews.
function Rules.PositionContext(useHealer, healerSpec, previewing, previewContext)
    if useHealer ~= true then return "DEFAULT" end
    if previewing == true and previewContext ~= nil then
        return previewContext == "HEALER" and "HEALER" or "DEFAULT"
    end
    return healerSpec == true and "HEALER" or "DEFAULT"
end

-- After a roster change the counts stay only for the same members in the
-- same order, each kept by the party potions pair rule.
function Rules.KeepOnRoster(old, new, isSecret)
    if #old ~= #new then return false end
    local keep = KE.PartyPotionsRules.KeepOnRoster
    for i = 1, #old do
        if not keep(old[i], new[i], isSecret) then return false end
    end
    return true
end

-- The grow directions: the step from one icon to the next, and the corner
-- icon 1 sits in.
local GRID = {
    RIGHT = { dx = 1,  dy = 0,  corner = "TOPLEFT" },
    LEFT  = { dx = -1, dy = 0,  corner = "TOPRIGHT" },
    DOWN  = { dx = 0,  dy = -1, corner = "TOPLEFT" },
    UP    = { dx = 0,  dy = 1,  corner = "BOTTOMLEFT" },
}
-- The Icons Per Row slider's top; a value that is not a number gives one row
-- of 12.
local PER_ROW_MAX = 12
local ATTACH_KEYS = { "HealerExtAnchorFrameType", "HealerExtParentFrame" }
local POSITION_FIELDS = { "AnchorFrom", "AnchorTo", "XOffset", "YOffset" }

local function Grid(grow) return GRID[grow] or GRID.RIGHT end

function Rules.PerRow(value)
    if type(value) ~= "number" or value ~= value then return PER_ROW_MAX end
    return math_max(1, math_min(PER_ROW_MAX, math_floor(value)))
end

function Rules.Corner(grow) return Grid(grow).corner end

-- Whether new rows start upward and new columns leftward. A stacked box wraps
-- down and right, away from the party frames above it; a free box starts new
-- lines on the side away from its anchor point.
function Rules.WrapSide(stacked, anchorFrom, grow)
    if stacked == true then return false, false end
    local pin = type(anchorFrom) == "string" and anchorFrom or "CENTER"
    if Grid(grow).dy == 0 then return string_find(pin, "BOTTOM", 1, true) ~= nil, false end
    return false, string_find(pin, "RIGHT", 1, true) ~= nil
end

-- Icon i's offset from icon 1.
function Rules.GridPlace(i, perRow, grow, step, wrapUp, wrapLeft)
    local g = Grid(grow)
    local along, line = (i - 1) % perRow, math_floor((i - 1) / perRow)
    if g.dy == 0 then return g.dx * along * step, (wrapUp and 1 or -1) * line * step end
    return (wrapLeft and -1 or 1) * line * step, g.dy * along * step
end

-- Columns and rows of n icons; one of each with none.
function Rules.GridShape(n, perRow, grow)
    if n < 1 then return 1, 1 end
    local long, wide = math_min(n, perRow), math_ceil(n / perRow)
    if Grid(grow).dy == 0 then return long, wide end
    return wide, long
end

-- Whether the grid reaches left of icon 1, and whether up.
function Rules.Extends(grow, wrapUp, wrapLeft)
    local g = Grid(grow)
    return g.dx < 0 or wrapLeft == true, g.dy > 0 or wrapUp == true
end

-- Edit Mode insets from a free box, which is icon 1 alone, onto the grid
-- that grows past it.
function Rules.GridInset(cols, rows, step, extendsLeft, extendsUp)
    local wide, tall = (cols - 1) * step, (rows - 1) * step
    local left, right = extendsLeft and wide or 0, extendsLeft and 0 or wide
    local top, bottom = extendsUp and tall or 0, extendsUp and 0 or tall
    return left, right, top, bottom
end

-- Whether the box's Default position is still its default attachment. AceDB
-- saves only values that differ from the defaults, so an equal value was
-- never changed or was changed back.
function Rules.DefaultAttachment(db, defaults)
    if type(db) ~= "table" or type(defaults) ~= "table" then return false end
    for _, key in ipairs(ATTACH_KEYS) do
        if defaults[key] == nil or db[key] ~= defaults[key] then return false end
    end
    local pos, want = db.HealerExtPosition, defaults.HealerExtPosition
    if type(pos) ~= "table" or type(want) ~= "table" then return false end
    for _, field in ipairs(POSITION_FIELDS) do
        if want[field] == nil or pos[field] ~= want[field] then return false end
    end
    return true
end

function Rules.Stacks(below, untouched, context, shown)
    return below == true and untouched == true and context == "DEFAULT" and shown == true
end

-- Edit Mode insets that grow the spot's box over the Raid Cooldowns box under
-- it and Healer Mana under that. Healer Mana has the spot's size, so its
-- height cancels.
function Rules.StackInset(boxW, boxH, spotW, gap, rightAligned)
    local wider = math_max(boxW, spotW) - spotW
    local bottom = boxH + gap
    if rightAligned == true then return wider, 0, 0, bottom end
    return 0, wider, 0, bottom
end
