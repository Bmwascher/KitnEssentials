-- ╔══════════════════════════════════════════════════════════╗
-- ║  HealerExternalsRules.lua                                ║
-- ║  Purpose: pure rules for the healer externals box.       ║
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
-- evaluations per watched unit, so the door bound needs Unit(cd) <= 2, which
-- holds up to 508 seconds. Never raise this above 508.
Rules.CD_MAX = 300

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

-- The spec's externals in table order, typed seconds over listed ones. A
-- switched-off entry is dropped unless all is set, which the editor uses to
-- list every one.
function Rules.Entries(specID, db, all)
    local data = KE.PartyCooldownsData
    local out = {}
    local row = Table(data.HEALER_SPECS)[specID]
    if not row then return out end
    db = Table(db)
    local off, seconds = Table(db.CooldownOff), Table(db.CooldownSeconds)
    for _, castID in ipairs(row.casts) do
        local spell = data.SPELLS[castID]
        local key = Rules.Key(specID, castID)
        local isOff = KE.PartyCooldownsRules.IsOff(off, key, spell)
        if spell and (all or not isOff) then
            out[#out + 1] = {
                id = castID, key = key, spell = spell, kind = spell.kind, buffs = spell.buffs,
                listed = spell.cd,
                cd = Rules.ClampSeconds(seconds[key]) or Rules.ClampSeconds(spell.cd),
                off = isOff,
            }
        end
    end
    return out
end

-- members: the party in token order, each { token, guid, spec }. Returns each
-- one whose spec has a switched-on external, as { member, entries }. You are
-- never one, and an unknown spec gives none.
function Rules.Healers(members, db)
    local out = {}
    for _, m in ipairs(members) do
        if m.token ~= "player" and m.spec ~= nil then
            local entries = Rules.Entries(m.spec, db)
            if #entries > 0 then out[#out + 1] = { member = m, entries = entries } end
        end
    end
    return out
end

-- Whether a member is worth an inspect for the box: a class with a healer
-- spec on the list, unless the role says damage or tank.
function Rules.Candidate(class, role)
    if type(class) ~= "string" or role == "DAMAGER" or role == "TANK" then return false end
    for _, row in pairs(Table(KE.PartyCooldownsData.HEALER_SPECS)) do
        if row.class == class then return true end
    end
    return false
end

-- A party only: KE counts an arena team as a raid group.
function Rules.On(db, active, inRaid)
    return Table(db).HealerExternals == true and active == true and inRaid ~= true
end

-- Whether an Edit Mode position detaches the box: only a move away from the
-- starting place while that place stands in for an anchor that is unnamed,
-- missing or refused. Edit Mode hands back the current position after a canceled drag,
-- and on a revert the position the mover started from, which is the starting
-- place if unmoved.
function Rules.MoverDetaches(fallback, pos, start)
    if fallback ~= true then return false end
    return not (pos.AnchorFrom == start.AnchorFrom and pos.AnchorTo == start.AnchorTo
        and pos.XOffset == start.XOffset and pos.YOffset == start.YOffset)
end

-- After a roster change the counts stay only for the same healers in the same
-- order, each kept by the party potions pair rule.
function Rules.KeepOnRoster(old, new, isSecret)
    if #old ~= #new then return false end
    local keep = KE.PartyPotionsRules.KeepOnRoster
    for i = 1, #old do
        if not keep(old[i], new[i], isSecret) then return false end
    end
    return true
end
