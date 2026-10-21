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
Rules.STALE_TRIES = 3
Rules.TRY_WAIT = 30
-- Seconds after another addon's inspect request in which nobody is asked and
-- no answer is cleared: that request may still be reading the data.
Rules.FOREIGN_GAP = 3

local function Table(value)
    if type(value) == "table" then return value end
    return {}
end

function Rules.CooldownKey(specID, castID) return specID .. ":" .. castID end

-- A spec list item: a cast, or { cast, seconds, charges = n }.
function Rules.UnpackItem(item)
    if type(item) == "table" then return item[1], item[2], item.charges end
    return item, nil, nil
end

function Rules.TrinketKey(spellID) return "trinket:" .. spellID end

-- A length, floored and clamped, or nil when it is not a number.
function Rules.ClampSeconds(value)
    value = tonumber(value)
    if not value or value ~= value then return nil end
    return math_floor(math_max(Rules.CD_MIN, math_min(Rules.CD_MAX, value)))
end

-- One cooldown entry at its listed length, clamped, with the charges its spec
-- always gives.
local function Entry(castID, spell, key, listed, isOff, charges)
    return {
        id = castID, key = key, spell = spell, kind = spell.kind,
        buffs = spell.buffs, short = spell.short, active = spell.active,
        free = spell.free, lockout = spell.lockout,
        listed = listed,
        cd = Rules.ClampSeconds(listed),
        charges = charges,
        off = isOff,
    }
end

-- A saved switch wins; an entry never switched takes its data row's default.
function Rules.IsOff(off, key, spell)
    if off[key] ~= nil then return off[key] == true end
    return spell ~= nil and spell.off == true
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
    local off = Table(db.CooldownOff)
    local order = Table(db.CooldownOrder)[specID]
    local rank
    if type(order) == "table" then
        rank = {}
        for i, castID in ipairs(order) do
            if not rank[castID] then rank[castID] = i end
        end
    end
    for i, item in ipairs(source) do
        local castID, talented, charges = Rules.UnpackItem(item)
        local spell = data.SPELLS[castID]
        local key = Rules.CooldownKey(specID, castID)
        local isOff = Rules.IsOff(off, key, spell)
        if spell and (all or not isOff) then
            local entry = Entry(castID, spell, key, talented or spell.cd, isOff, charges)
            entry.at = rank and (rank[castID] or #order + i) or i
            out[#out + 1] = entry
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

-- Whether another addon's inspect request, made at foreignAt, may still be in
-- use.
function Rules.ForeignBusy(now, foreignAt)
    if type(foreignAt) ~= "number" then return false end
    return now - foreignAt < Rules.FOREIGN_GAP
end

-- At most one member per call, and none while an inspect view is in use, in
-- combat, within INSPECT_GAP seconds of the last request or within
-- FOREIGN_GAP seconds of another addon's. An offline member never answers,
-- and asking it would hold back everyone behind it.
function Rules.NextInspect(state, members)
    if Rules.InspectInUse(state.inspectShown, state.talentsInspecting) or state.inCombat then return nil end
    if state.lastRequest and state.now - state.lastRequest < Rules.INSPECT_GAP then return nil end
    if Rules.ForeignBusy(state.now, state.foreignAt) then return nil end
    for _, m in ipairs(members) do
        if not m.done and m.canInspect and not m.offline and not (m.waitUntil and state.now < m.waitUntil) then
            return m
        end
    end
    return nil
end

-- A request with no answer is a try; MAX_TRIES of them rest the member, or
-- STALE_TRIES when every answer it is wanted for is in hand and only stale.
function Rules.CountTry(m, now, stale)
    m.tries = (m.tries or 0) + 1
    if m.tries >= (stale and Rules.STALE_TRIES or Rules.MAX_TRIES) then
        m.tries, m.waitUntil = 0, now + Rules.TRY_WAIT
    end
end

-- An item tooltip names its use cooldown as "(2 Min Cooldown)",
-- "(1 Min 30 Sec Cooldown)" or "(90 Sec Cooldown)". The raw text can carry the
-- client's |4singular:plural; escape, which reads as its first form.
function Rules.ParseCooldownText(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|4([^:;]*):[^;]*;", "%1")
    local inner = text:match("%(([^()]-) Cooldown%)")
    if not inner then return nil end
    local total = (tonumber(inner:match("(%d+) Min")) or 0) * 60 + (tonumber(inner:match("(%d+) Sec")) or 0)
    if total <= 0 then return nil end
    return total
end

-- slots holds slot 13's and slot 14's { item, spell }; lengths, the read use
-- cooldown per item. A trinket gets a cell when its use spell is a switched-on
-- row of the Trinkets list and its length is known.
function Rules.TrinketEntries(slots, lengths, db)
    local out = {}
    db = Table(db)
    local listed = KE.AuraRules.BuildIncludeSpellIDs(db.ListTrinkets)
    for i = 1, 2 do
        local slot = slots[i]
        local spellID = slot and slot.spell
        if spellID and listed[spellID] then
            local key = Rules.TrinketKey(spellID)
            -- Every length is clamped to CD_MAX: the door bound assumes u <= 4.
            local cd = Rules.ClampSeconds(lengths[slot.item])
            if cd then
                out[#out + 1] = {
                    id = spellID, item = slot.item, key = key, kind = "trinket",
                    buffs = KE.PartyCooldownsData.TRINKET_BUFFS[spellID] or { spellID }, cd = cd, trinket = true,
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
local table_concat = table.concat
local tostring = tostring

-- A stamp is one of the 255 values k / 255 the latch carries exactly; 254
-- steps of u seconds make one roll period.
Rules.CODES = 254
-- Seconds past zero a plain timer stays before it is cleared.
Rules.LINGER = 4
Rules.DOOR_SAMPLES = { 0, 1, 48, 85, 127, 200, 254, 255 }
Rules.DOOR_PASSES = 16
-- A secret read passes the stamp through the client up to 2 times, 4 with a
-- short sensor, at up to 5 reads a second; a charge cell's read adds 2 and
-- its tick 5 a second. Over one roll period the drift stays under half a
-- strip line while DOOR_SLACK <= 8 / (64770 * passes a second * u^2):
-- 3.86e-7 for a 900-second cell with a short sensor, 3.92e-7 for a charge
-- cell with one at CHARGE_CD_MAX. A group tracker passes it up to 2 times per
-- watched unit, 2 more with charges: at 5 units and 508 seconds or less,
-- 6.18e-7, and 4.75e-7 with charges. A cell with free and lockout sensors
-- adds 2 passes a read for the fill and 3 for the veto: 6.18e-7 with charges
-- at u = 2, but 2.74e-7 at u = 3, so a free row's cd stays at 508 s or less.
Rules.DOOR_SLACK = 3e-7

function Rules.Unit(cd) return math_max(1, math_ceil(cd / Rules.CODES)) end

-- What a cell's count is kept by: its buffs, proc length, charges and code
-- unit. A new length in the same unit keeps the stamps valid, so the count
-- carries on.
function Rules.TrackerKey(e)
    return table_concat(e.buffs, ",") .. "/" .. tostring(e.short) .. "/" .. tostring(e.charges)
        .. "/" .. Rules.Unit(e.cd)
end

-- A row cell's count is kept by its entry's key, else its position, and by
-- what TrackerKey keeps it by, so a count follows its spell when another is
-- switched off.
function Rules.CellKey(e, i)
    return tostring(e.key or i) .. "/" .. Rules.TrackerKey(e)
end

-- Two rolling slots, so a new use can stamp while an older one still counts.
-- A slot's c is its stamp and v its visibility; either may hold a secret.
-- A multi tracker reads a list of answers, one per watched unit. A charge
-- tracker (charges 2) recharges one slot after the other: b is set while a
-- second use waits behind the running recharge, and a0, a1, a2 are the
-- alphas of the 0, 1 and 2 count digits.
function Rules.NewTracker(cd, hasShort, multi, charges)
    local u = Rules.Unit(cd)
    local t = {
        cd = cd, u = u, P = Rules.CODES * u, cur = 1, primed = false, hasShort = hasShort == true,
        multi = multi == true,
        slot = { { c = 1, v = 0, epoch = 0 }, { c = 1, v = 0, epoch = 0 } },
    }
    if type(charges) == "number" and charges >= 2 then
        t.charges, t.b, t.a0, t.a1, t.a2 = 2, 0, 0, 0, 1
    end
    return t
end

-- Back to ready, both charges full, with no late-fall window; the next read
-- records without stamping.
function Rules.Clear(t, n)
    for k = 1, 2 do
        local sl = t.slot[k]
        sl.c, sl.v, sl.epoch = 1, 0, n
    end
    t.cur, t.primed, t.prev, t.prevShort, t.quietTo, t.restartTo = 1, false, nil, nil, nil, nil
    t.pf, t.pl = nil, nil
    t.fallD, t.fallFrom, t.fallTo = nil, nil, nil
    if t.charges then
        t.b, t.a0, t.a1, t.a2 = 0, 0, 0, 1
        t.f1, t.f2, t.p1, t.p2, t.fRead, t.legacy, t.lb = nil, nil, nil, nil, nil, nil, nil
    end
end

function Rules.Roll(t, n)
    if n - t.slot[t.cur].epoch < t.P then return false end
    t.cur = 3 - t.cur
    local sl = t.slot[t.cur]
    sl.c, sl.v, sl.epoch = 1, 0, n
    return true
end

-- Code 0 is a fresh slot's value, which a charge tracker reads as finished,
-- so its stamps start at code 1.
function Rules.Stamp(t, n)
    local code = math_floor((n - t.slot[t.cur].epoch) / t.u)
    local low = t.charges and 1 or 0
    if code < low then code = low elseif code > Rules.CODES then code = Rules.CODES end
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

-- at dates the use before the read n; it defaults to n.
function Rules.StartPlain(t, n, at)
    Rules.Roll(t, n)
    local sl, other = t.slot[t.cur], t.slot[3 - t.cur]
    sl.c, sl.v, other.v = Rules.Stamp(t, at or n), 1, 0
end

-- A buff up at a key's start n has fallen by fallFrom. A fall from then to
-- fallTo ends a buff drunk in the key, length seconds before the fall.
function Rules.ArmFall(t, n, length)
    t.fallD, t.fallFrom, t.fallTo = length, n + length + 2, n + 2 * length + 1
end

-- A cast's own buff can reach the reads late, after a read that saw none, so
-- for these seconds after a cast stamp a rise only records. A clear ends it.
Rules.CAST_QUIET = 10

function Rules.StartCast(t, n)
    Rules.StartPlain(t, n)
    t.quietTo = n + Rules.CAST_QUIET
end

local function NeverSecret() return false end

-- A preview sample: cooling at n with t.loop seconds left; a charge sample
-- shows no charge left.
function Rules.StartLoop(t, n)
    local start = n - (t.cd - t.loop)
    -- A charge stamp starts at code 1, so a charge sample's slot starts one
    -- code unit before the use.
    Rules.Clear(t, t.charges and start - t.u or start)
    Rules.StartPlain(t, start)
    if t.charges then
        t.b = 1
        Rules.ChargeCount(t, n, NeverSecret)
    end
end

-- For each new key, the index of the same key in old, or false. Each old
-- index is given once: a repeated key matches only its first copy.
function Rules.MatchKeys(old, new)
    local at = {}
    for i = #old, 1, -1 do at[old[i]] = i end
    local match = {}
    for i, k in ipairs(new) do
        match[i] = at[k] or false
        at[k] = nil
    end
    return match
end

-- Free uses. Feed keeps the read's free and lockout answers in t.vf and t.vl
-- and the previous read's in t.pf and t.pl; a tracker without those sensors
-- has all four nil, and nothing here changes it.

-- Whether a read's use is vetoed: first whether that could be read, then the
-- answer. A use read while the free buff is up costs nothing, and so does one
-- read with a lockout rise.
function Rules.FreeVetoed(t, isSecret)
    local f, l, pl = t.vf, t.vl, t.pl
    if isSecret(f) or isSecret(l) or isSecret(pl) then return false, false end
    return true, f == true or (l == true and pl == false)
end

-- x, the value a use writes, or old where the read is vetoed, picked so a
-- secret answer is never compared.
function Rules.FreeVeto(t, x, old, pick)
    local f, l, pl = t.vf, t.vl, t.pl
    if f ~= nil then x = pick(f, old, x) end
    if l ~= nil and pl ~= nil then x = pick(l, pick(pl, x, old), x) end
    return x
end

local function Fill(f, pf, x, full, pick) return pick(f, pick(pf, x, full), x) end

-- Plain, no slot shown and, for charges, both back with no use waiting: a
-- fill would change nothing shown or counted, and picking it would only make
-- the state secret. A hidden slot's stamp counts for nothing (ChargeFin, Tick).
local function FullIdle(t, isSecret)
    local s1, s2 = t.slot[1], t.slot[2]
    if isSecret(s1.v) or isSecret(s2.v) or s1.v ~= 0 or s2.v ~= 0 then return false end
    if not t.charges then return true end
    if isSecret(t.b) or isSecret(t.a0) or isSecret(t.a1) or isSecret(t.a2) or isSecret(t.lb) then
        return false
    end
    return t.b == 0 and t.a0 == 0 and t.a1 == 0 and t.a2 == 1 and (not t.legacy or t.lb == 0)
end

-- A rise of the free buff ends every recharge: both charges are back. On
-- secret answers each value is picked, unless the cell is full and idle, and
-- none is written until every pick has run. Returns whether a value changed.
function Rules.FreeFill(t, isSecret, pick)
    local f, pf = t.vf, t.pf
    if f == nil or pf == nil then return false end
    local s1, s2 = t.slot[1], t.slot[2]
    if not isSecret(f) and not isSecret(pf) then
        if not (f == true and pf ~= true) then return false end
        s1.c, s1.v, s2.c, s2.v = 1, 0, 1, 0
        if t.charges then t.b, t.a0, t.a1, t.a2, t.legacy, t.lb = 0, 0, 0, 1, nil, nil end
        return true
    end
    if FullIdle(t, isSecret) then return false end
    local c1, v1 = Fill(f, pf, s1.c, 1, pick), Fill(f, pf, s1.v, 0, pick)
    local c2, v2 = Fill(f, pf, s2.c, 1, pick), Fill(f, pf, s2.v, 0, pick)
    if t.charges then
        local b, a0 = Fill(f, pf, t.b, 0, pick), Fill(f, pf, t.a0, 0, pick)
        local a1, a2 = Fill(f, pf, t.a1, 0, pick), Fill(f, pf, t.a2, 1, pick)
        -- A lost count stays lost: t.legacy is plain, and the cell hides the
        -- digits on it, so only its timer and cover can be picked to ready.
        local lb = t.lb
        if t.legacy then lb = Fill(f, pf, lb, 0, pick) end
        t.b, t.a0, t.a1, t.a2, t.lb = b, a0, a1, a2, lb
    end
    s1.c, s1.v, s2.c, s2.v = c1, v1, c2, v2
    return true
end

-- Known and up, from plain answers only. A lit short sensor means a proc
-- copy, which is not a use. A list is up when any of its answers is.
local function State(lit, short, hasShort, isSecret, multi)
    if multi then
        local up = false
        for j = 1, lit.n do
            if isSecret(lit[j]) then return false, false end
            if lit[j] == true then up = true end
        end
        return true, up
    end
    if isSecret(lit) or isSecret(short) then return false, false end
    return true, lit == true and not (hasShort and short == true)
end

-- pick is the client's EvaluateColorValueFromBoolean. With a short sensor the
-- answer is a only while lit and the short one is not; for a list, a while
-- any answer is lit, each answer one nested evaluation.
local function Pick(lit, short, hasShort, a, b, pick, multi)
    if multi then
        local r = b
        for j = lit.n, 1, -1 do r = pick(lit[j], a, r) end
        return r
    end
    if not hasShort then return pick(lit, a, b) end
    return pick(lit, pick(short, b, a), b)
end

-- One read. Plain answers decide the edge in Lua. A secret answer is only
-- passed to pick, which writes the stamp and the visibility without Lua
-- learning it. Inside an armed window a fall stamps fallD seconds back; in a
-- cast's quiet a rise only records, and so does a plain rise for t.quiet
-- seconds after a plain start. A charge tracker's read goes to
-- ChargeUse, past reading its finished state back and checked the read-back's
-- self-check (nil while undecided); the edge below never sees it. An error
-- there loses the count, times the read as one cooldown, per unit for a
-- group, and redraws; if that errs too, the read is held: the previous read
-- stays, so the next read finds the same use. free and lock are a free
-- cell's free and lockout answers: a free rise fills the cell first
-- (FreeFill), and a use read while free is lit or with a lockout rise
-- changes nothing (FreeVeto). Returns true when a slot changed.
function Rules.Feed(t, lit, short, n, isSecret, pick, past, checked, free, lock)
    local changed, held = false, false
    local hasShort, multi = t.hasShort, t.multi
    t.vf, t.vl = free, lock
    if t.primed then
        changed = Rules.Roll(t, n)
        if Rules.FreeFill(t, isSecret, pick) then changed = true end
        local litKnown, up = State(lit, short, hasShort, isSecret, multi)
        local prevKnown, was = State(t.prev, t.prevShort, hasShort, isSecret, multi)
        local quiet = t.quietTo ~= nil and n <= t.quietTo
        local taken, moved = false, false
        if t.charges and not quiet and t.fallD == nil then
            local ok
            ok, taken, moved = pcall(Rules.ChargeUse, t, lit, short, n, isSecret, pick, past, checked)
            if not ok then
                Rules.ChargeLose(t)
                local timed = pcall(Rules.ChargeLegacyUse, t, lit, short, n, isSecret, pick)
                taken, moved, held = true, true, not timed
            end
        end
        local restarting = litKnown and prevKnown and t.restartTo ~= nil and n <= t.restartTo
        local freeKnown, vetoed = Rules.FreeVetoed(t, isSecret)
        local rise = not taken and not quiet and not restarting and not (freeKnown and vetoed)
            and not ((litKnown and not up) or (prevKnown and was))
        local fall = not taken and t.fallD ~= nil and n >= t.fallFrom and n <= t.fallTo
            and not ((litKnown and up) or (prevKnown and not was))
        if taken then
            changed = changed or moved == true
        elseif rise or fall then
            if litKnown and prevKnown and freeKnown then
                if rise then
                    Rules.StartPlain(t, n)
                    if t.quiet then t.restartTo = n + t.quiet end
                else
                    Rules.StartPlain(t, n, n - t.fallD)
                end
            else
                -- The sides are picked by the plain flags; a side that cannot
                -- happen keeps the slot as it is.
                local sl, other = t.slot[t.cur], t.slot[3 - t.cur]
                local prev, prevShort = t.prev, t.prevShort
                local riseC, riseV, riseO = sl.c, sl.v, other.v
                if rise then
                    local V = Rules.FreeVeto
                    riseC = V(t, Pick(prev, prevShort, hasShort, sl.c, Rules.Stamp(t, n), pick, multi), sl.c, pick)
                    riseV = V(t, Pick(prev, prevShort, hasShort, sl.v, 1, pick, multi), sl.v, pick)
                    riseO = V(t, Pick(prev, prevShort, hasShort, other.v, 0, pick, multi), other.v, pick)
                end
                local fallC, fallV, fallO = sl.c, sl.v, other.v
                if fall then
                    fallC = Pick(prev, prevShort, hasShort, Rules.Stamp(t, n - t.fallD), sl.c, pick, multi)
                    fallV = Pick(prev, prevShort, hasShort, 1, sl.v, pick, multi)
                    fallO = Pick(prev, prevShort, hasShort, 0, other.v, pick, multi)
                end
                sl.c = Pick(lit, short, hasShort, riseC, fallC, pick, multi)
                sl.v = Pick(lit, short, hasShort, riseV, fallV, pick, multi)
                other.v = Pick(lit, short, hasShort, riseO, fallO, pick, multi)
            end
            changed = true
        end
    end
    if not held then t.prev, t.prevShort, t.primed, t.pf, t.pl = lit, short, true, free, lock end
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

---------------------------------------------------------------------------------
-- Charges: two, recharged one after the other
---------------------------------------------------------------------------------
-- Plain while b, both slots' stamps and visibilities, the digit alphas and the
-- lost count's cover can be read; the plain pass compares the alphas.
function Rules.ChargePlain(t, isSecret)
    if isSecret(t.b) or isSecret(t.a0) or isSecret(t.a1) or isSecret(t.a2) or isSecret(t.lb) then
        return false
    end
    for k = 1, 2 do
        local sl = t.slot[k]
        if isSecret(sl.c) or isSecret(sl.v) then return false end
    end
    return true
end

-- The stamp at or above which slot sl has run its cooldown at n, half a code
-- step off the codes.
function Rules.ChargeThreshold(t, sl, n)
    local th = (254.5 - math_floor((n - sl.epoch - t.cd) / t.u)) / 255
    if th > 254.5 / 255 then th = 254.5 / 255 end
    return th
end

-- Whether slot k has run its cooldown, or is empty, at n: first whether that
-- could be read, always plain, then the answer. On a secret stamp both come
-- from past, a read-back whose answer may be secret and only ever reaches pick.
function Rules.ChargeFin(t, k, n, isSecret, past)
    local sl = t.slot[k]
    if not isSecret(sl.c) then
        if sl.c == 1 or Rules.Left(t, sl, n) <= 0 then return true, true end
        if not isSecret(sl.v) and sl.v == 0 then return true, true end
        return true, false
    end
    if not past then return false, nil end
    return past(t, k, Rules.ChargeThreshold(t, sl, n))
end

-- Whether a second use waits, read the same way.
function Rules.ChargeHas(t, isSecret, past)
    if not isSecret(t.b) then return true, t.b > 0.5 end
    if not past then return false, nil end
    return past(t, "b", 0.5)
end

-- The digit alphas. Plain state only.
function Rules.ChargeCount(t, n, isSecret, past)
    local _, f1 = Rules.ChargeFin(t, 1, n, isSecret, past)
    local _, f2 = Rules.ChargeFin(t, 2, n, isSecret, past)
    local have = 1
    if f1 and f2 then have = 2 elseif t.b > 0.5 then have = 0 end
    t.a0, t.a1, t.a2 = have == 0 and 1 or 0, have == 1 and 1 or 0, have == 2 and 1 or 0
end

-- The count is lost: the cell shows a single timer and no digit. Its cover
-- keeps what the count showed (b, no charge left), so a cell at no charge
-- stays gray until its running recharge returns one, and a cell with a charge
-- shows none; each later use shows one cooldown from that use
-- (ChargeLegacyUse).
function Rules.ChargeLose(t)
    if t.legacy then return end
    t.legacy, t.lb = true, t.b
end

-- Back from the single timer on plain state: that timer counts as the one
-- running recharge.
function Rules.ChargeResume(t, n, isSecret)
    t.legacy, t.lb, t.b = nil, nil, 0
    Rules.ChargeCount(t, n, isSecret)
end

-- A recharge that ended with a second use waiting starts the next one at the
-- second it ended. Plain state only; returns whether it did.
function Rules.ChargeAdvance(t, n)
    if t.b <= 0.5 then return false end
    local fin
    for k = 1, 2 do
        local sl = t.slot[k]
        if sl.v ~= 0 and sl.c ~= 1 then
            local left = Rules.Left(t, sl, n)
            if left > 0 then return false end
            if not fin or n + left > fin then fin = n + left end
        end
    end
    if fin then
        local sl, other = t.slot[t.cur], t.slot[3 - t.cur]
        sl.c, sl.v, other.v = Rules.Stamp(t, fin), 1, 0
    end
    t.b = 0
    return true
end

-- A plain use. A waiting recharge whose turn has come starts first, so a use
-- on that second takes the charge it leaves; then with both charges ready the
-- use starts a recharge, else it waits behind the running one. Plain state
-- only.
function Rules.ChargeUsePlain(t, n, isSecret, past)
    Rules.Roll(t, n)
    Rules.ChargeAdvance(t, n)
    local _, f1 = Rules.ChargeFin(t, 1, n, isSecret, past)
    local _, f2 = Rules.ChargeFin(t, 2, n, isSecret, past)
    if f1 and f2 then
        local sl, other = t.slot[t.cur], t.slot[3 - t.cur]
        sl.c, sl.v, other.v, t.b = Rules.Stamp(t, n), 1, 0, 0
    else
        t.b = 1
    end
    Rules.ChargeCount(t, n, isSecret, past)
end

-- Uses in one read from plain answers: 0, 1, or 2 when two or more units of a
-- group rise at once. A group counts each unit's own rise, so a second use on
-- another unit while the first buff is up is seen. Nil while an answer is
-- secret.
local function PlainRises(t, lit, short, isSecret)
    if t.multi then
        local prev, r = t.prev, 0
        for j = 1, lit.n do
            if isSecret(lit[j]) or isSecret(prev[j]) then return nil end
            if lit[j] == true and prev[j] ~= true then r = r + 1 end
        end
        return math_min(r, 2)
    end
    local litKnown, up = State(lit, short, t.hasShort, isSecret, false)
    local prevKnown, was = State(t.prev, t.prevShort, t.hasShort, isSecret, false)
    if not (litKnown and prevKnown) then return nil end
    if up and not was then return 1 end
    return 0
end

-- Whether a read cannot hold a use, from plain answers only: a single sensor
-- not lit now, or lit in the read before; a group when every unit is. A
-- secret answer never makes its side idle, so a read that might hold a use
-- still goes on.
function Rules.ChargeIdle(t, lit, short, isSecret)
    if t.multi then
        local prev = t.prev
        for j = 1, lit.n do
            local now, before = lit[j], prev[j]
            local off = not isSecret(now) and now ~= true
            local on = not isSecret(before) and before == true
            if not (off or on) then return false end
        end
        return true
    end
    local litKnown, up = State(lit, short, t.hasShort, isSecret, false)
    local prevKnown, was = State(t.prev, t.prevShort, t.hasShort, isSecret, false)
    return (litKnown and not up) or (prevKnown and was)
end

-- old with no use in the read, new with one: a lit read after one that was
-- not.
local function OnRise(t, lit, short, old, new, pick)
    local hasShort = t.hasShort
    return Pick(lit, short, hasShort, Pick(t.prev, t.prevShort, hasShort, old, new, pick, false), old, pick, false)
end

-- x0 with no unit rising in the read, x1 with one, x2 with two or more; a unit
-- rises when lit now and not in the read before. Two evaluations per unit on
-- any path.
local function ByRises(t, lit, x0, x1, x2, pick)
    local prev, h0, h1 = t.prev, x0, x1
    for j = lit.n, 1, -1 do
        h0, h1 = pick(lit[j], pick(prev[j], h0, h1), h0), pick(lit[j], pick(prev[j], h1, x2), h1)
    end
    return h0
end

-- The value for r uses, or picked by the reads when r is not known.
local function Choose(t, lit, short, r, x0, x1, x2, pick)
    if r == 1 then return x1 elseif r == 2 then return x2 end
    if t.multi then return ByRises(t, lit, x0, x1, x2, pick) end
    return OnRise(t, lit, short, x0, x1, pick)
end

-- A use while the count is lost: one cooldown from the read that saw it, a
-- group's counted per unit, with the cover shown. Returns whether a value
-- changed; a group read with another unit count only records, as in
-- ChargeUse.
function Rules.ChargeLegacyUse(t, lit, short, n, isSecret, pick)
    if t.multi and t.prev.n ~= lit.n then return false end
    local r = PlainRises(t, lit, short, isSecret)
    if r == 0 then return false end
    local freeKnown, vetoed = Rules.FreeVetoed(t, isSecret)
    if freeKnown and vetoed then return false end
    local sl, other = t.slot[t.cur], t.slot[3 - t.cur]
    local stamp = Rules.Stamp(t, n)
    local V = Rules.FreeVeto
    local c = V(t, Choose(t, lit, short, r, sl.c, stamp, stamp, pick), sl.c, pick)
    local v = V(t, Choose(t, lit, short, r, sl.v, 1, 1, pick), sl.v, pick)
    local o = V(t, Choose(t, lit, short, r, other.v, 0, 0, pick), other.v, pick)
    local lb = V(t, Choose(t, lit, short, r, t.lb, 1, 1, pick), t.lb, pick)
    sl.c, sl.v, other.v, t.lb = c, v, o, lb
    return true
end

-- A read of a charge tracker: whether this path took it, and whether a value
-- changed. A read that cannot hold a use (ChargeIdle) only records. On hidden
-- state each new value is picked by the reads and the finished answers, and
-- none is written until every pick has run, so an error leaves the state
-- whole. With the count lost, or a finished answer unreadable, the use is
-- timed as one cooldown (ChargeLegacyUse). A group read with another unit
-- count only records; Track.ApplyGroup's hold unprimes the tracker whenever
-- the unit list changes. checked is the read-back's self-check: until it
-- decides, a read that needs a hidden value only records, so no count is lost
-- without a cast.
function Rules.ChargeUse(t, lit, short, n, isSecret, pick, past, checked)
    if t.multi and t.prev.n ~= lit.n then return true, false end
    if Rules.ChargeIdle(t, lit, short, isSecret) then return true, false end
    local plain = Rules.ChargePlain(t, isSecret)
    local resumed = plain and t.legacy == true
    if resumed then Rules.ChargeResume(t, n, isSecret) end
    if t.legacy then
        return true, Rules.ChargeLegacyUse(t, lit, short, n, isSecret, pick)
    end
    local r = PlainRises(t, lit, short, isSecret)
    if r == 0 then return true, resumed end
    local freeKnown, vetoed = Rules.FreeVetoed(t, isSecret)
    if freeKnown and vetoed then return true, resumed end
    local plainUse = plain and r and freeKnown
    if checked == nil and not plainUse then return true, resumed end
    if plainUse then
        for _ = 1, r do Rules.ChargeUsePlain(t, n, isSecret, past) end
        return true, true
    end
    local known1, f1 = Rules.ChargeFin(t, 1, n, isSecret, past)
    local known2, f2 = Rules.ChargeFin(t, 2, n, isSecret, past)
    local knownB, has = Rules.ChargeHas(t, isSecret, past)
    if not (known1 and known2 and knownB) then
        Rules.ChargeLose(t)
        Rules.ChargeLegacyUse(t, lit, short, n, isSecret, pick)
        return true, true
    end
    local sl, other = t.slot[t.cur], t.slot[3 - t.cur]
    -- From full a use starts a recharge, or, when a use waits and the running
    -- recharge has just ended, takes the charge it leaves; from one charge it
    -- takes the last. Two uses from full also take the last.
    local c = pick(f1, pick(f2, Rules.Stamp(t, n), sl.c), sl.c)
    local v = pick(f1, pick(f2, 1, sl.v), sl.v)
    local o = pick(f1, pick(f2, 0, other.v), other.v)
    local b = pick(f1, pick(f2, pick(has, 1, 0), 1), 1)
    local a1 = pick(f1, pick(f2, pick(has, 0, 1), 0), 0)
    c = Choose(t, lit, short, r, sl.c, c, c, pick)
    v = Choose(t, lit, short, r, sl.v, v, v, pick)
    o = Choose(t, lit, short, r, other.v, o, o, pick)
    local a0 = Choose(t, lit, short, r, t.a0, b, 1, pick)
    a1 = Choose(t, lit, short, r, t.a1, a1, 0, pick)
    local a2 = Choose(t, lit, short, r, t.a2, 0, 0, pick)
    b = Choose(t, lit, short, r, t.b, b, 1, pick)
    local V = Rules.FreeVeto
    c, v, o = V(t, c, sl.c, pick), V(t, v, sl.v, pick), V(t, o, other.v, pick)
    a0, a1, a2, b = V(t, a0, t.a0, pick), V(t, a1, t.a1, pick), V(t, a2, t.a2, pick), V(t, b, t.b, pick)
    sl.c, sl.v, other.v = c, v, o
    t.a0, t.a1, t.a2, t.b = a0, a1, a2, b
    return true, true
end

-- a on the second both slots are first finished, x otherwise.
local function Fall(t, a, x, pick)
    local q = pick(t.f1, pick(t.f2, a, x), x)
    return pick(t.p1, pick(t.p2, x, q), q)
end

-- The plain pass: a waiting recharge whose turn has come starts, and the digit
-- is recounted. Returns whether a value changed.
function Rules.ChargeTickPlain(t, n, isSecret, past)
    local moved = Rules.ChargeAdvance(t, n)
    local a0, a1, a2 = t.a0, t.a1, t.a2
    Rules.ChargeCount(t, n, isSecret, past)
    if a0 ~= t.a0 or a1 ~= t.a1 or a2 ~= t.a2 then moved = true end
    local _, f1 = Rules.ChargeFin(t, 1, n, isSecret, past)
    local _, f2 = Rules.ChargeFin(t, 2, n, isSecret, past)
    t.f1, t.f2, t.fRead = f1, f2, true
    return moved
end

-- The once-a-second pass, run before Rules.Tick; it rolls first, so a stamp
-- after a held second is not capped. checked is the read-back's self-check:
-- nil while undecided, then true or false. An answer that cannot be read once
-- the check has decided loses the count (ChargeLose) until the state reads
-- plain again; while it is undecided the pass waits. No value is written
-- until every pick has run. Returns whether a value changed.
function Rules.ChargeTick(t, n, isSecret, pick, past, checked)
    local rolled = Rules.Roll(t, n)
    if Rules.ChargePlain(t, isSecret) then
        local resumed = t.legacy == true
        if resumed then Rules.ChargeResume(t, n, isSecret) end
        local moved = Rules.ChargeTickPlain(t, n, isSecret, past)
        return moved or rolled or resumed
    end
    if t.legacy then return rolled end
    local known1, f1 = Rules.ChargeFin(t, 1, n, isSecret, past)
    local known2, f2 = Rules.ChargeFin(t, 2, n, isSecret, past)
    local knownB, has = Rules.ChargeHas(t, isSecret, past)
    if not (known1 and known2 and knownB) then
        if checked ~= nil then
            Rules.ChargeLose(t)
            return true
        end
        return rolled
    end
    local read = t.fRead
    t.p1, t.p2 = t.f1, t.f2
    t.f1, t.f2, t.fRead = f1, f2, true
    if not read then return rolled end
    local sl, other = t.slot[t.cur], t.slot[3 - t.cur]
    local c = Fall(t, pick(has, Rules.Stamp(t, n), sl.c), sl.c, pick)
    local v = Fall(t, pick(has, 1, sl.v), sl.v, pick)
    local o = Fall(t, pick(has, 0, other.v), other.v, pick)
    local a0 = Fall(t, 0, t.a0, pick)
    local a1 = Fall(t, pick(has, 1, 0), t.a1, pick)
    local a2 = Fall(t, pick(has, 0, 1), t.a2, pick)
    local b = Fall(t, 0, t.b, pick)
    sl.c, sl.v, other.v = c, v, o
    t.a0, t.a1, t.a2, t.b = a0, a1, a2, b
    return true
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

-- The blank kept above and below each strip label. A label's ink spills past
-- its line box, more as the font grows, and packed labels poke into their
-- neighbor's window. The client has no ink measure; a quarter of the line plus
-- one is about twice the spill seen at 12.
function Rules.StripMargin(line)
    if type(line) ~= "number" then line = 0 end
    return math_ceil(line / 4) + 1
end

-- The gray window's y offset that lands its label's line bottom a quarter of a
-- screen pixel above the grid, away from the edge where drawing can round to
-- either pixel; nil leaves the window where it is. y is the edge the caller
-- measures from (a cell's center, a potion bar's bottom), base the line
-- bottom's depth below it, scale and height the frame's effective scale and
-- the screen's physical height. An edge that cannot be read keeps the last
-- seat; before any seat, a quarter pixel is the guess.
function Rules.Seat(y, base, scale, height, seat, isSecret)
    if isSecret(scale) or type(scale) ~= "number" or scale <= 0
        or type(height) ~= "number" or height <= 0 or type(base) ~= "number" then
        return nil
    end
    local ppu = scale * height / 768
    if isSecret(y) or type(y) ~= "number" then
        if seat then return nil end
        return 0.25 / ppu
    end
    local at = (y - base) * ppu
    if seat then
        local seated = at + seat * ppu
        if math_abs(seated - math_floor(seated) - 0.25) < 0.1 then return nil end
    end
    local f = at - math_floor(at)
    return ((f < 0.75 and 0.25 or 1.25) - f) / ppu
end

-- A summon's glow window, in pixels from the bottom of the icon's inner area:
-- the step its bar moves each second, the window's bottom and top above that
-- bar's fill edge, and its width. A step is more than the glow's whole reach
-- (the widest style draws 0.3 sizes past each edge), so the window covers the
-- glow for the first active seconds and lies above it from then on.
function Rules.GlowWindow(size, px, cd, active)
    local over = math_ceil(size * 0.3)
    local step = size + 2 * over + 2
    local lead = size - px + over + (cd - 1 - active) * step
    return step, lead, lead + active * step + 1, step
end

-- Whole seconds of a summon's active phase, at least one second short of cd so
-- the gray cover still has a second to show; 0 when there is none.
function Rules.ActiveSeconds(active, cd)
    if type(active) ~= "number" or type(cd) ~= "number" then return 0 end
    return math_max(0, math_min(math_floor(active), cd - 1))
end

-- Item data loads, and tooltip reads with no cooldown line, per item in a
-- session; a load that keeps failing stops here.
Rules.LOAD_TRIES = 3

-- True, and counted, while itemID has requests left.
function Rules.TakeLoadTry(tries, itemID)
    local n = tries[itemID] or 0
    if n >= Rules.LOAD_TRIES then return false end
    tries[itemID] = n + 1
    return true
end

-- Seconds before each re-derive of a member whose trinkets are incomplete out
-- of combat: a tooltip can lack its cooldown line until the use spell's text
-- loads, and no event says when.
Rules.DERIVE_WAITS = { 2, 5, 15 }

-- The wait before the next re-derive after tries of them; nil once spent.
function Rules.NextDeriveWait(tries)
    return Rules.DERIVE_WAITS[(tries or 0) + 1]
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

-- A spec's talents: rules maps castID to the talent rule of each entry that
-- has one (its hide, else its swap, where it applies to the spec, else its
-- needs); ids and want list every talent those rules and the mods of the
-- spec's casts name, the externals box's casts and box rows included. rows is
-- set when the spec's own casts or its healer externals name a talent, box
-- when its healer externals or its box rows do; boxOnly holds the talents
-- only box rows name, which a read skips while the box is off. Nil when there
-- is none. The data never changes, so each spec's answer is built once and
-- shared; callers only read it. The inspect ticker asks every second.
local talentsBySpec = {}

local function AddTalent(out, talent)
    if talent and not out.want[talent] then
        out.want[talent] = true
        out.ids[#out.ids + 1] = talent
    end
end

-- Returns whether the spell's mods name a talent.
local function AddModTalents(out, spell)
    local named = false
    for _, mod in ipairs(spell and spell.mods or {}) do
        if mod[1] then
            AddTalent(out, mod[1])
            named = true
        end
    end
    return named
end

-- A cast's talent rule, its lockout's talents and its mods' talents. Returns
-- whether it names a talent.
local function AddCast(out, castID, spell, specID)
    local swap = spell and spell.swap
    local hide = spell and spell.hide
    local rule = spell and spell.needs
    if swap and (not swap.specs or swap.specs[specID]) then rule = swap end
    if hide and hide.specs[specID] then rule = hide end
    local named = false
    if rule then
        out.rules[castID] = rule
        for talent in pairs(rule.talents) do
            AddTalent(out, talent)
            named = true
        end
    end
    local lockout = spell and spell.lockout
    if lockout then
        for talent in pairs(lockout.talents) do
            AddTalent(out, talent)
            named = true
        end
    end
    return AddModTalents(out, spell) or named
end

function Rules.TalentsFor(specID)
    if specID == nil then return nil end
    local cached = talentsBySpec[specID]
    if cached == nil then
        local data = KE.PartyCooldownsData
        local out = { rules = {}, ids = {}, want = {}, rows = false, box = false, boxOnly = {} }
        for _, item in ipairs(data.SPECS[specID] or {}) do
            local castID = Rules.UnpackItem(item)
            if AddCast(out, castID, data.SPELLS[castID], specID) then out.rows = true end
        end
        local healer = data.HEALER_SPECS and data.HEALER_SPECS[specID]
        for _, castID in ipairs(healer and healer.casts or {}) do
            if AddModTalents(out, data.SPELLS[castID]) then out.rows, out.box = true, true end
        end
        -- ids lists each talent once, in the order first named.
        local own = #out.ids
        for _, row in ipairs(data.BOX_ROWS or {}) do
            if row.specs[specID] and AddCast(out, row.id, data.SPELLS[row.id], specID) then out.box = true end
        end
        for k = own + 1, #out.ids do out.boxOnly[out.ids[k]] = true end
        cached = #out.ids > 0 and out or false
        talentsBySpec[specID] = cached
    end
    return cached or nil
end

-- Whether a member's talents are worth a read, from TalentsFor's answer:
-- Class Cooldowns is on and the spec's own casts or healer externals name a
-- talent, or the box is on and its externals or box rows do.
function Rules.TalentsWanted(talents, trackClass, trackHealers)
    if not talents then return false end
    if trackClass == true and talents.rows then return true end
    return trackHealers == true and talents.box == true
end

-- Whether a read keeps the talent: one only box rows name waits for the box.
function Rules.TalentRead(talents, talent, boxOn)
    return boxOn == true or not talents.boxOnly[talent]
end

function Rules.TalentAllows(entry, taken, specID)
    local hide = entry.spell and entry.spell.hide
    if hide and hide.specs[specID] then
        if taken == nil then return hide.likely ~= true end
        return taken == false
    end
    local needs = entry.spell and entry.spell.needs
    if not needs then return true end
    if taken == nil then return needs.likely == true end
    return taken == true
end

-- A spell's cooldown with talents applied: flat seconds add and percents
-- multiply, each per rank, and a mod limited to another spec counts nothing.
-- Nil while any talent a length mod names is unread, and when no mod changes
-- a length: a mod that adds a charge is skipped.
function Rules.ModLength(base, mods, ranks, specID)
    local cd, mul, any = base, 1, false
    for _, mod in ipairs(mods) do
        if not mod.charges then
            any = true
            local rank = 1
            if mod[1] then
                rank = ranks and ranks[mod[1]]
                if type(rank) ~= "number" then return nil end
            end
            if mod.spec and mod.spec ~= specID then rank = 0 end
            if rank > 0 then
                cd, mul = cd + (mod.add or 0) * rank, mul * (1 + (mod.pct or 0) * rank / 100)
            end
        end
    end
    if not any then return nil end
    return math_floor(math_max(Rules.CD_MIN, math_min(Rules.CD_MAX, cd * mul)) + 0.5)
end

-- A charge cell counts at most this long: its tick and read passes need
-- Unit(cd) <= 3 under DOOR_SLACK, and Unit(cd) <= 2 with free and lockout
-- sensors.
Rules.CHARGE_CD_MAX = 3 * Rules.CODES

-- The length a cell counts: the spell's cooldown with the member's talents
-- once every one its length mods name is read, the listed length until then.
function Rules.CellLength(entry, specID, ranks, charges)
    local spell = entry.spell
    local cd = spell and spell.mods and Rules.ModLength(spell.cd, spell.mods, ranks, specID) or entry.cd
    if type(charges) == "number" and charges >= 2 then cd = math_min(cd, Rules.CHARGE_CD_MAX) end
    return cd
end

-- The most charges a cell counts: one per timer slot.
Rules.MAX_CHARGES = 2

-- The charges a cell counts: the entry's own, plus one per charge talent read
-- as taken for the spec; an unread one adds nothing.
function Rules.CellCharges(entry, specID, ranks)
    local charges = entry.charges or 1
    for _, mod in ipairs(entry.spell and entry.spell.mods or {}) do
        local rank = mod.charges and mod[1] and ranks and ranks[mod[1]]
        if type(rank) == "number" and rank > 0 and not (mod.spec and mod.spec ~= specID) then
            charges = charges + mod.charges
        end
    end
    return math_min(charges, Rules.MAX_CHARGES)
end

-- A talent rule's answer from ranks: true when any of its talents is taken,
-- false when some are read and none is, nil when none is read.
function Rules.Taken(rule, ranks)
    if not (rule and ranks) then return nil end
    local read = false
    for talent in pairs(rule.talents) do
        local rank = ranks[talent]
        if type(rank) == "number" then
            if rank > 0 then return true end
            read = true
        end
    end
    if read then return false end
    return nil
end

-- Whether a cast's talent rule is taken, from a member's ranks; nil when the
-- cast has no rule or nothing of it is read.
function Rules.CastTaken(specID, castID, ranks)
    local talents = Rules.TalentsFor(specID)
    return Rules.Taken(talents and talents.rules[castID], ranks)
end

-- Whether a cell watches its lockout: on your own row only, because the
-- lockout sensor's source filter passes only auras you or your pet applied;
-- there, the lockout talent read as taken, or unread and likely.
function Rules.LockOn(entry, ranks, own)
    local lockout = entry.lockout
    if own ~= true or not lockout then return false end
    local taken = Rules.Taken(lockout, ranks)
    if taken == nil then return lockout.likely == true end
    return taken
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

-- An inspect answer can come before the teammate's gear does, and then every
-- slot reads empty. A read with no trinket counts only when the chest or main
-- hand (others) holds an item.
function Rules.GearArrived(items, others)
    return items[1] ~= nil or items[2] ~= nil or others[1] ~= nil or others[2] ~= nil
end

-- The talent answer after three unreadable reads, and whether to read once
-- more: a member with no answer stores an empty one and is read again; a held
-- answer, the empty one included, is kept.
function Rules.AfterTalentMisses(held)
    return held or {}, held == nil
end

-- Whether a spec or talent event may drop what was read of a member. Inside a
-- running key nobody's spec or talents can change, and a dropped teammate
-- waits for an out-of-combat inspect; your own are read again at once.
function Rules.BuildEventCounts(inKey, isPlayer)
    return not inKey or isPlayer == true
end

-- The game resets class cooldowns of KEY_RESET_MIN seconds or more when a key
-- starts, and no trinket. The length is the one the cell counts, talents
-- included.
Rules.KEY_RESET_MIN = 90

function Rules.ResetsAtKeyStart(entry)
    return entry.trinket ~= true and type(entry.cd) == "number" and entry.cd >= Rules.KEY_RESET_MIN
end

-- A key start's reset of one cell: one the game resets goes back to ready,
-- both charges full; any other keeps its count. Returns whether it reset.
function Rules.KeyStartClear(t, entry, n)
    if not Rules.ResetsAtKeyStart(entry) then return false end
    Rules.Clear(t, n)
    return true
end

-- Every restriction kind can hide a sensor's answer but Chat, which limits
-- addon messages only. A kind that hid no read resets nothing: only cells on
-- hidden state are reset.
Rules.HIDING_KINDS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }

-- Whether no restriction that can hide a read is active. kinds is the
-- client's restriction-kind enum and isActive answers for one kind; an error
-- or any answer but a plain false counts as active, so a doubtful answer
-- never resets a count. A kind the enum does not list cannot be active.
function Rules.ReadsUnhidden(kinds, isActive)
    if type(kinds) ~= "table" or type(isActive) ~= "function" then return false end
    for _, name in ipairs(Rules.HIDING_KINDS) do
        local kind = kinds[name]
        if kind ~= nil then
            local ok, on = pcall(isActive, kind)
            if not ok or on ~= false then return false end
        end
    end
    return true
end

-- With no restriction left, a charge tracker counted from hidden reads keeps
-- hidden state, which no plain read can recount, so it goes back to ready,
-- both charges full. A one-charge tracker's timer runs out on its own.
-- Returns whether it reset.
function Rules.HiddenChargeClear(t, n, isSecret)
    if not t.charges or Rules.ChargePlain(t, isSecret) then return false end
    Rules.Clear(t, n)
    return true
end

-- A missing talent string on either side cannot tell, so it counts as moved.
function Rules.TalentsMoved(prev, talents)
    return type(prev) ~= "string" or type(talents) ~= "string" or prev ~= talents
end

-- The key the library files a member's answer under: addon comms name a
-- sender of another realm as name-realm and one of your realm by name alone.
function Rules.LibKey(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    if realm == nil or realm == "" then return name end
    if type(realm) ~= "string" then return nil end
    return name .. "-" .. realm
end

function Rules.RacialKey(castID) return "race:" .. castID end

-- A switched-off racial is nil unless all is set, which the editor uses to
-- list every one.
function Rules.RacialEntry(castID, db, all)
    local spell = KE.PartyCooldownsData.SPELLS[castID]
    if not spell then return nil end
    db = Table(db)
    local key = Rules.RacialKey(castID)
    local isOff = Rules.IsOff(Table(db.CooldownOff), key, spell)
    if isOff and not all then return nil end
    return Entry(castID, spell, key, spell.cd, isOff)
end

function Rules.MemberRacial(race, db)
    db = Table(db)
    if db.ShowRacials ~= true or type(race) ~= "string" then return nil end
    for _, racial in ipairs(KE.PartyCooldownsData.RACIALS or {}) do
        if racial.race == race then return Rules.RacialEntry(racial.id, db) end
    end
    return nil
end

-- Whether a teammate's spec is worth an inspect. A racial counts: it shows
-- only with a known spec. healer is the raid cooldowns box's own demand.
function Rules.SpecWanted(trackClass, trackTrinkets, showRacials, race, healer)
    if trackClass == true or trackTrinkets == true or healer == true then return true end
    if showRacials ~= true or type(race) ~= "string" then return false end
    for _, racial in ipairs(KE.PartyCooldownsData.RACIALS or {}) do
        if racial.race == race then return true end
    end
    return false
end
