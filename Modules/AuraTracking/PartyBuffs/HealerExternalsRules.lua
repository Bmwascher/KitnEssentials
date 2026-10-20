-- ╔══════════════════════════════════════════════════════════╗
-- ║  HealerExternalsRules.lua                                ║
-- ║  Purpose: pure rules for the raid cooldowns box.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local math_min = math.min
local pairs = pairs
local type = type

local Rules = {}
KE.HealerExternalsRules = Rules

-- A group tracker's read passes its stamp through up to two client
-- evaluations per watched unit, a charge cell's two more plus five a second
-- from its tick, so the door bound needs Unit(cd) <= 2, which holds up to 508
-- seconds. Never raise this above 508.
Rules.CD_MAX = 300

-- Seconds after a raid cooldown's plain start in which a rise only records,
-- so a caster stepping out of their zone and back in does not restart it:
-- longer than any such zone lasts, shorter than any such cooldown.
Rules.RAID_QUIET = 15

-- The roles a party member can be assigned; any other answer says nothing.
local ASSIGNED = { DAMAGER = true, TANK = true, HEALER = true }
local HEALER_ROLE = { HEALER = true }
local GROUPS = { "target", "owner" }

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

-- The box's cells: every target entry, source by source, then every owner
-- entry the same way. Each keeps its owner's GUID, so a count follows its
-- owner when the list shifts; an owner entry watches its owner's unit alone.
function Rules.Order(sources)
    local out = {}
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

-- Whether a role leaves a row's specs possible: unread or unassigned says
-- nothing, else it must be one their specs fill.
local function RoleFits(roles, role)
    return role == nil or not ASSIGNED[role] or roles[role] == true
end

-- Whether a member is worth an inspect for the box: a class with a
-- class-wide row in any role, or one with a healer external or a spec row in
-- a role those specs could fill.
function Rules.Candidate(class, role)
    if type(class) ~= "string" then return false end
    local data = KE.PartyCooldownsData
    for _, row in ipairs(Table(data.BOX_ROWS)) do
        if row.class == class and (row.anySpec == true or RoleFits(Table(row.roles), role)) then return true end
    end
    for _, row in pairs(Table(data.HEALER_SPECS)) do
        if row.class == class and RoleFits(HEALER_ROLE, role) then return true end
    end
    return false
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
