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

-- Blizzard's Inspect window, or its talent view of another player, reads the
-- inspect data too: KE neither asks for an inspect nor clears one then.
function Rules.InspectInUse(inspectShown, talentsInspecting)
    return inspectShown == true or talentsInspecting == true
end

-- At most one member per call, and none while an inspect view is in use, in
-- combat, or within INSPECT_GAP seconds of the last request.
function Rules.NextInspect(state, members)
    if Rules.InspectInUse(state.inspectShown, state.talentsInspecting) or state.inCombat then return nil end
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

---------------------------------------------------------------------------------
-- Code clock and latch
---------------------------------------------------------------------------------
local math_abs = math.abs
local math_ceil = math.ceil
local pcall = pcall

-- A stamp is one of the 255 values k / 255 the latch carries exactly; 254
-- steps of u seconds make one roll period.
Rules.CODES = 254
-- Seconds past zero a plain timer stays before it is cleared.
Rules.LINGER = 4
Rules.DOOR_SAMPLES = { 0, 1, 48, 85, 127, 200, 254, 255 }
Rules.DOOR_PASSES = 16
-- A secret read passes the stamp through the client 2 times, 4 with a short
-- sensor: up to 20320 times over a 900-second cooldown's roll period. At
-- 0.5 / (1020 * 1270), just over 3.8598e-7, the drift could reach half a strip
-- line; keep the slack at 3.85e-7 or less.
Rules.DOOR_SLACK = 3e-7

function Rules.Unit(cd) return math_max(1, math_ceil(cd / Rules.CODES)) end

-- Two rolling slots, so a new use can stamp while an older one still counts.
-- A slot's c is its stamp and v its visibility; either may hold a secret.
function Rules.NewTracker(cd, hasShort)
    local u = Rules.Unit(cd)
    return {
        cd = cd, u = u, P = Rules.CODES * u, cur = 1, primed = false, hasShort = hasShort == true,
        slot = { { c = 1, v = 0, epoch = 0 }, { c = 1, v = 0, epoch = 0 } },
    }
end

-- Back to ready; the next read records without stamping.
function Rules.Clear(t, n)
    for k = 1, 2 do
        local sl = t.slot[k]
        sl.c, sl.v, sl.epoch = 1, 0, n
    end
    t.cur, t.primed, t.prev, t.prevShort = 1, false, nil, nil
end

function Rules.Roll(t, n)
    if n - t.slot[t.cur].epoch < t.P then return false end
    t.cur = 3 - t.cur
    local sl = t.slot[t.cur]
    sl.c, sl.v, sl.epoch = 1, 0, n
    return true
end

function Rules.Stamp(t, n)
    local code = math_floor((n - t.slot[t.cur].epoch) / t.u)
    if code < 0 then code = 0 elseif code > Rules.CODES then code = Rules.CODES end
    return (255 - code) / 255
end

-- Seconds left on a plain slot; negative once it has run out.
function Rules.Left(t, sl, n)
    local code = 255 - math_floor(sl.c * 255 + 0.5)
    return t.cd - ((n - sl.epoch) - t.u * code)
end

-- The low bound of a slot's bars this second; the high bound is one more.
function Rules.RangeMin(sl, u, n)
    return (254 - (n - sl.epoch) / u) / 255
end

function Rules.StartPlain(t, n)
    Rules.Roll(t, n)
    local sl, other = t.slot[t.cur], t.slot[3 - t.cur]
    sl.c, sl.v, other.v = Rules.Stamp(t, n), 1, 0
end

-- Known and up, from plain answers only. A lit short sensor means a proc
-- copy, which is not a use.
local function State(lit, short, hasShort, isSecret)
    if isSecret(lit) or isSecret(short) then return false, false end
    return true, lit == true and not (hasShort and short == true)
end

-- pick is the client's EvaluateColorValueFromBoolean. With a short sensor the
-- answer is a only while lit and the short one is not.
local function Pick(lit, short, hasShort, a, b, pick)
    if not hasShort then return pick(lit, a, b) end
    return pick(lit, pick(short, b, a), b)
end

-- One read. Plain answers decide the edge in Lua. A secret answer is only
-- passed to pick, which writes the stamp and the visibility without Lua
-- learning it. Returns true when a slot changed.
function Rules.Feed(t, lit, short, n, isSecret, pick)
    local changed = false
    local hasShort = t.hasShort
    if t.primed then
        changed = Rules.Roll(t, n)
        local litKnown, up = State(lit, short, hasShort, isSecret)
        local prevKnown, was = State(t.prev, t.prevShort, hasShort, isSecret)
        if not ((litKnown and not up) or (prevKnown and was)) then
            if litKnown and prevKnown then
                Rules.StartPlain(t, n)
            else
                local sl, other = t.slot[t.cur], t.slot[3 - t.cur]
                local prev, prevShort = t.prev, t.prevShort
                sl.c = Pick(lit, short, hasShort,
                    Pick(prev, prevShort, hasShort, sl.c, Rules.Stamp(t, n), pick), sl.c, pick)
                sl.v = Pick(lit, short, hasShort, Pick(prev, prevShort, hasShort, sl.v, 1, pick), sl.v, pick)
                other.v = Pick(lit, short, hasShort,
                    Pick(prev, prevShort, hasShort, other.v, 0, pick), other.v, pick)
            end
            changed = true
        end
    end
    t.prev, t.prevShort, t.primed = lit, short, true
    return changed
end

-- The once-a-second pass: rolls, and clears a plain slot LINGER seconds past
-- zero. Returns whether a slot still shows and whether one was cleared or
-- rolled.
function Rules.Tick(t, n, isSecret)
    local changed = Rules.Roll(t, n)
    local running = false
    for k = 1, 2 do
        local sl = t.slot[k]
        if isSecret(sl.v) or sl.v ~= 0 then
            if not isSecret(sl.v) and not isSecret(sl.c) and Rules.Left(t, sl, n) <= -Rules.LINGER then
                sl.v = 0
                changed = true
            else
                running = true
            end
        end
    end
    return running, changed
end

-- Round-trips each sample through eval, alternating its two branches. Exact,
-- within DOOR_SLACK, or unreadable from here: the latch can carry a stamp.
function Rules.DoorVerdict(eval, isSecret)
    if type(eval) ~= "function" then return "error" end
    local off = 0
    for _, k in ipairs(Rules.DOOR_SAMPLES) do
        local want = k / 255
        local v = want
        for pass = 1, Rules.DOOR_PASSES do
            local ok, w
            if pass % 2 == 1 then ok, w = pcall(eval, true, v, 0) else ok, w = pcall(eval, false, 0, v) end
            if not ok then return "error" end
            if isSecret(w) then return "hidden" end
            if type(w) ~= "number" then return "error" end
            v = w
            off = math_max(off, math_abs(v - want))
        end
    end
    if off == 0 then return "exact" end
    if off <= Rules.DOOR_SLACK then return "close" end
    return "coarse"
end

function Rules.DoorOpen(verdict)
    return verdict == "exact" or verdict == "close" or verdict == "hidden"
end

-- In lines: how far the strip's bar sits below the window's bottom, and its
-- height. The strip hangs from the bar's fill edge, so the window shows the
-- seconds left.
function Rules.StripBar(cd, u)
    return -(cd - 1 + u), 255 * u
end

-- Item data loads asked for per item in a session; a load that keeps failing
-- stops here.
Rules.LOAD_TRIES = 3

-- True, and counted, while itemID has requests left.
function Rules.TakeLoadTry(tries, itemID)
    local n = tries[itemID] or 0
    if n >= Rules.LOAD_TRIES then return false end
    tries[itemID] = n + 1
    return true
end

-- The trinket icons a row may show after an exclusion call (set: the trinkets
-- asked to be left out of its while-active Trinkets group), and the set that
-- may show once the group's buttons have caught up. Accepted: the group's
-- buttons follow the new filter only on its next pass, so only icons already
-- shown that stay excluded remain, and set waits. Refused: the group holds any
-- set issued since the last accepted one, so only icons every one of them
-- leaves out remain, and nothing waits. An empty set has nothing to wait for.
function Rules.TrinketShow(show, set, accepted)
    local kept = {}
    for id in pairs(show or {}) do
        if set[id] then kept[id] = true end
    end
    if not accepted or next(set) == nil then return kept, nil end
    local pending = {}
    for id in pairs(set) do pending[id] = true end
    return kept, pending
end

-- castID -> swap, for the spec's entries whose swap applies to it; nil when
-- none does. The data never changes, so each spec's answer is built once and
-- shared; callers only read it. The inspect ticker asks every second.
local swapsBySpec = {}

function Rules.SwapsFor(specID)
    if specID == nil then return nil end
    local cached = swapsBySpec[specID]
    if cached == nil then
        local data = KE.PartyCooldownsData
        cached = false
        for _, item in ipairs(data.SPECS[specID] or {}) do
            local castID = type(item) == "table" and item[1] or item
            local spell = data.SPELLS[castID]
            local swap = spell and spell.swap
            if swap and (not swap.specs or swap.specs[specID]) then
                cached = cached or {}
                cached[castID] = swap
            end
        end
        swapsBySpec[specID] = cached
    end
    return cached or nil
end

-- A gear event within GEAR_QUIET seconds of a teammate's last trinket read
-- may come from that inspect answer itself. Past MAX_SAME_READS re-reads in a
-- row that found the same trinkets, one counts only TRY_WAIT seconds after
-- the last read.
Rules.GEAR_QUIET = 3
Rules.MAX_SAME_READS = 2

-- Whether a teammate's gear event asks for a new read. Gear cannot change
-- inside a running key.
function Rules.GearEventCounts(inKey, now, readAt, same)
    if inKey then return false end
    if not readAt then return true end
    local quiet = (same or 0) >= Rules.MAX_SAME_READS and Rules.TRY_WAIT or Rules.GEAR_QUIET
    return now - readAt >= quiet
end

-- After an inspect read of the trinket slots: whether it stands, and whether
-- it agrees with the previous read. An empty slot may be data that has not
-- arrived yet, so a read with one stands only once a second read agrees.
function Rules.TrinketReadStands(prev, items)
    local same = prev ~= nil and prev[1] == items[1] and prev[2] == items[2]
    return same or (items[1] ~= nil and items[2] ~= nil), same
end

-- Whether a spec or talent event may drop what was read of a member. Inside a
-- running key nobody's spec or talents can change, and a dropped teammate
-- waits for an out-of-combat inspect; your own are read again at once.
function Rules.BuildEventCounts(inKey, isPlayer)
    return not inKey or isPlayer == true
end

-- The game resets class cooldowns of KEY_RESET_MIN seconds or more when a key
-- starts, and no trinket. The length is the one the cell counts, talents and
-- typed seconds included.
Rules.KEY_RESET_MIN = 90

function Rules.ResetsAtKeyStart(entry)
    return entry.trinket ~= true and type(entry.cd) == "number" and entry.cd >= Rules.KEY_RESET_MIN
end

-- The library also sends unchanged on every group request: only a talent
-- string that differs from the last one is a change, and a missing one on
-- either side cannot tell, so it counts.
function Rules.TalentsMoved(prev, talents)
    return type(prev) ~= "string" or type(talents) ~= "string" or prev ~= talents
end
