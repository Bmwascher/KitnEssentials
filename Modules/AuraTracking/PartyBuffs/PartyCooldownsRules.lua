-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyCooldownsRules.lua                                 ║
-- ║  Purpose: pure decision logic for Party Cooldowns.       ║
-- ║  No WoW API, no frames -- so it is testable headlessly.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local table_sort = table.sort
local tonumber = tonumber
local type = type

local Rules = {}
KE.PartyCooldownsRules = Rules

Rules.CD_MIN, Rules.CD_MAX = 5, 900
Rules.INSPECT_GAP = 2
Rules.MAX_TRIES = 12
Rules.TRY_WAIT = 30

local function Table(value)
    if type(value) == "table" then return value end
    return {}
end

function Rules.CooldownKey(specID, castID) return specID .. ":" .. castID end

function Rules.TrinketKey(spellID) return "trinket:" .. spellID end

-- A typed length, floored and clamped, or nil when it is not a number.
function Rules.ClampSeconds(value)
    value = tonumber(value)
    if not value or value ~= value then return nil end
    return math_floor(math_max(Rules.CD_MIN, math_min(Rules.CD_MAX, value)))
end

-- The spec's entries: casts in the saved order first, the rest after them in
-- table order. A switched-off entry is dropped unless all is set, which the
-- editor uses to list every one.
function Rules.SpellList(specID, db, all)
    local data = KE.PartyCooldownsData
    local out = {}
    local source = data.SPECS[specID]
    if not source then return out end
    db = Table(db)
    local off, seconds = Table(db.CooldownOff), Table(db.CooldownSeconds)
    local order = Table(db.CooldownOrder)[specID]
    local rank
    if type(order) == "table" then
        rank = {}
        for i, castID in ipairs(order) do
            if not rank[castID] then rank[castID] = i end
        end
    end
    for i, item in ipairs(source) do
        local castID, talented = item, nil
        if type(item) == "table" then castID, talented = item[1], item[2] end
        local spell = data.SPELLS[castID]
        local key = Rules.CooldownKey(specID, castID)
        local isOff = off[key] == true
        if spell and (all or not isOff) then
            local listed = talented or spell.cd
            out[#out + 1] = {
                id = castID, key = key, spell = spell, kind = spell.kind,
                buffs = spell.buffs, short = spell.short,
                listed = listed,
                cd = Rules.ClampSeconds(seconds[key]) or Rules.ClampSeconds(listed),
                off = isOff, at = rank and (rank[castID] or #order + i) or i,
            }
        end
    end
    if rank then table_sort(out, function(a, b) return a.at < b.at end) end
    return out
end

-- The spell whose icon to draw: the talent's while it is taken, the likely
-- one while talents are unread, the cast's otherwise.
function Rules.ShowID(entry, specID, taken)
    local swap = entry.spell and entry.spell.swap
    if not swap or (swap.specs and not swap.specs[specID]) then return entry.id end
    if taken == nil then taken = swap.likely == true end
    if taken then return swap.id end
    return entry.id
end

local SOURCES = { "player", "lib", "inspect" }

-- The first source that knows the spec, in trust order, then a guess from
-- the role: only where a class fills it with one spec, and never for damage.
-- Returns the spec and the source's name.
function Rules.ResolveSpec(sources)
    for _, name in ipairs(SOURCES) do
        local specID = sources[name]
        if type(specID) == "number" and specID > 0 then return specID, name end
    end
    local role = sources.role
    if role == "TANK" or role == "HEALER" then
        local byRole = KE.PartyCooldownsData.ROLE_SPEC[sources.class or ""]
        local guess = byRole and byRole[role]
        if guess then return guess, "guess" end
    end
    return nil, nil
end

-- At most one member per call, and none while the Inspect window is open, in
-- combat, or within INSPECT_GAP seconds of the last request.
function Rules.NextInspect(state, members)
    if state.inspectShown or state.inCombat then return nil end
    if state.lastRequest and state.now - state.lastRequest < Rules.INSPECT_GAP then return nil end
    for _, m in ipairs(members) do
        if not m.done and m.canInspect and not (m.waitUntil and state.now < m.waitUntil) then
            return m
        end
    end
    return nil
end

-- A request with no answer is a try; MAX_TRIES of them rest the member.
function Rules.CountTry(m, now)
    m.tries = (m.tries or 0) + 1
    if m.tries >= Rules.MAX_TRIES then
        m.tries, m.waitUntil = 0, now + Rules.TRY_WAIT
    end
end

-- An item tooltip names its use cooldown as "(2 Min Cooldown)",
-- "(1 Min 30 Sec Cooldown)" or "(90 Sec Cooldown)".
function Rules.ParseCooldownText(text)
    if type(text) ~= "string" then return nil end
    local inner = text:match("%(([^()]-) Cooldown%)")
    if not inner then return nil end
    local total = (tonumber(inner:match("(%d+) Min")) or 0) * 60 + (tonumber(inner:match("(%d+) Sec")) or 0)
    if total <= 0 then return nil end
    return total
end

-- slots holds slot 13's and slot 14's { item, spell }; lengths, the read use
-- cooldown per item. A trinket gets a cell when its use spell is a switched-on
-- row of the Trinkets list and a length is known, the typed one first.
function Rules.TrinketEntries(slots, lengths, db)
    local out = {}
    db = Table(db)
    local listed = KE.AuraRules.BuildIncludeSpellIDs(db.ListTrinkets)
    local seconds = Table(db.CooldownSeconds)
    for i = 1, 2 do
        local slot = slots[i]
        local spellID = slot and slot.spell
        if spellID and listed[spellID] then
            local key = Rules.TrinketKey(spellID)
            -- Every length is clamped to CD_MAX: the door bound assumes u <= 4.
            local cd = Rules.ClampSeconds(seconds[key]) or Rules.ClampSeconds(lengths[slot.item])
            if cd then
                out[#out + 1] = {
                    id = spellID, item = slot.item, key = key, kind = "trinket",
                    buffs = { spellID }, cd = cd, trinket = true,
                }
            end
        end
    end
    return out
end
