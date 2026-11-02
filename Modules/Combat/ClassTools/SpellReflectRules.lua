-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/ClassTools/SpellReflectRules.lua         ║
-- ║  Purpose: the pure rules of Spell Reflect.               ║
-- ║           No WoW API, no frames.                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs, pairs, select, type = ipairs, pairs, select, type
local math_abs, math_max = math.abs, math.max

local Rules = {}
KE.SpellReflectRules = Rules

Rules.REFLECT_ID = 23920

-- Display order; `mode` applies until the player picks another.
Rules.SPELLS = {
    { id = 1247685, mode = "ALWAYS" }, -- Thornspike
    { id = 1297017, mode = "ALWAYS" }, -- Void Blast
    { id = 1222795, mode = "ALWAYS" }, -- Envenom
    { id = 1234233, mode = "ALWAYS" }, -- Spoiled Supplies
    { id = 1296220, mode = "ALWAYS" }, -- Triple Shot
    { id = 1299154, mode = "ALWAYS" }, -- Synchronized Venom
    { id = 1290797, mode = "ALWAYS" }, -- Lightning Bite
    { id = 1305810, mode = "READY" },  -- Arc Lightning
}

local DEFAULT_MODE = {}
for _, spell in ipairs(Rules.SPELLS) do DEFAULT_MODE[spell.id] = spell.mode end

local MODES = { ALWAYS = true, READY = true, OFF = true }

Rules.REFLECT_LASTS = 5 -- seconds Spell Reflection lasts
-- The window opens this long before the hit, so a press at its start is still
-- up when the hit lands.
Rules.WINDOW = 4.5

-- Window offsets from the cast start in seconds, negative before it, for the
-- spells the one rule does not fit.
local EXCEPTIONS = {
    [1297017] = { open = -2.0, close = 2.5 },
    [1234233] = { open = 0, close = 6 },
}

Rules.STOP_SLACK = 1        -- a bar stopped this close to zero means the cast started
Rules.REFRESH_SLACK = 0.25  -- a repeat bar ending this close to the open one refreshes it
Rules.CANCEL_GRACE = 0.15   -- a message this soon after an early stop still starts the cast
Rules.WAIT_MAX = 4          -- with no cast start heard, the bar's zero stands in this long
Rules.MAX_AGE = 180
Rules.TEST_LEAD = 6

Rules.NOW_WORD = "NOW"
Rules.TEXT_LABEL = "REFLECT \194\187"
Rules.TEXT_LABEL_NOW = "REFLECT"
Rules.NOT_READY = "NO REFLECT"

function Rules.ModeOf(modes, spellId)
    local mode = type(modes) == "table" and modes[spellId] or nil
    if mode and MODES[mode] then return mode end
    return DEFAULT_MODE[spellId] or "ALWAYS"
end

-- Saved only when it differs from the spell's default.
function Rules.SetMode(modes, spellId, mode)
    if not MODES[mode] then return end
    if mode == (DEFAULT_MODE[spellId] or "ALWAYS") then
        modes[spellId] = nil
    else
        modes[spellId] = mode
    end
end

-- { [spellId] = { castLength, name, boss } } for the tracked spells whose boss
-- data row has a cast length.
function Rules.Index(encounterData)
    local out = {}
    if type(encounterData) ~= "table" then return out end
    for _, encounter in pairs(encounterData) do
        local spells = type(encounter) == "table" and encounter.spells
        if type(spells) == "table" then
            for _, spell in ipairs(Rules.SPELLS) do
                local row = spells[spell.id]
                if type(row) == "table" and type(row.castDuration) == "number" then
                    out[spell.id] = { castLength = row.castDuration, name = row.name, boss = encounter.name }
                end
            end
        end
    end
    return out
end

-- Offsets from the cast start: green from `open` until `close`.
function Rules.Window(spellId, castLength)
    local exception = EXCEPTIONS[spellId]
    if exception then return exception.open, exception.close end
    return castLength - Rules.WINDOW, castLength
end

function Rules.PayloadReadable(isSecret, ...)
    for i = 1, select("#", ...) do
        if isSecret((select(i, ...))) then return false end
    end
    return true
end

-- entry = { id, name, open, close }.
function Rules.Start(records, entry, owner, text, duration, now)
    local ends = now + duration
    local old = records[text]
    -- A refresh also undoes a cancel: the bar came back within the grace.
    if old and not old.start and math_abs(old.ends - ends) < Rules.REFRESH_SLACK then
        old.ends, old.left, old.stopAt = ends, nil, nil
        return old
    end
    local rec = {
        id = entry.id, name = entry.name, open = entry.open, close = entry.close,
        owner = owner, ends = ends, born = now,
    }
    -- A retimed bar for a cast neither started nor canceled is the same cast:
    -- it keeps the sounds already played and a press's reach (Rules.Covered).
    if old and not old.start and not old.stopAt then
        rec.readySounded, rec.notReadySounded, rec.reach = old.readySounded, old.notReadySounded, old.reach
    end
    records[text] = rec
    return rec
end

local function OpenRecord(records, text)
    local rec = records[text]
    if rec and not rec.start then return rec end
    return nil
end

-- "start", "cancel", or nil when no open record has this text.
function Rules.Stop(records, text, now)
    local rec = OpenRecord(records, text)
    if not rec then return nil end
    local left = rec.left or (rec.ends - now)
    if left <= Rules.STOP_SLACK then
        rec.start, rec.left = now, nil
        return "start"
    end
    rec.stopAt = now
    return "cancel"
end

function Rules.Said(records, text, now)
    local rec = OpenRecord(records, text)
    if not rec then return false end
    rec.start, rec.left, rec.stopAt = now, nil, nil
    return true
end

function Rules.Pause(records, text, now, paused)
    local rec = OpenRecord(records, text)
    if not rec then return false end
    if paused and not rec.left then
        rec.left = math_max(0, rec.ends - now)
        return true
    elseif not paused and rec.left then
        rec.ends, rec.left = now + rec.left, nil
        return true
    end
    return false
end

-- Every record of one boss module, or all of them when owner is nil.
function Rules.Clear(records, owner)
    for text, rec in pairs(records) do
        if owner == nil or rec.owner == owner then records[text] = nil end
    end
end

function Rules.NewTest(entry, now)
    return {
        id = entry.id, name = entry.name, open = entry.open, close = entry.close,
        ends = now + Rules.TEST_LEAD, born = now, test = true,
    }
end

-- The one clock the display reads: seconds to the cast start, and seconds
-- since it once it started or the bar ran out.
function Rules.Countdown(rec, now)
    if rec.start then return 0, now - rec.start end
    if rec.left then return rec.left, nil end
    local toStart = rec.ends - now
    if toStart > 0 then return toStart, nil end
    return 0, -toStart
end

-- WAIT before the window, GO inside it before the cast, NOW from the cast
-- start, HELD for a bar stopped early, OVER when the record is finished.
function Rules.Phase(rec, now)
    if now - rec.born > Rules.MAX_AGE then return "OVER" end
    if rec.stopAt then
        if now - rec.stopAt > Rules.CANCEL_GRACE then return "OVER" end
        return "HELD"
    end
    local toStart, since = Rules.Countdown(rec, now)
    if since then
        local limit = (rec.start or rec.test) and rec.close or Rules.WAIT_MAX
        if since >= limit then return "OVER" end
        return "NOW"
    end
    if toStart <= -rec.open then return "GO" end
    return "WAIT"
end

-- The hit: the window's close, counted from the cast start once heard, else
-- from the bar's zero, or from now plus the time left while paused.
local function Hit(rec, now)
    local start = rec.start or (rec.left and now + rec.left) or rec.ends
    return start + rec.close
end

-- A press covers a record while the hit, wherever it has moved since, is
-- still within the press's reach.
function Rules.Covered(rec, now)
    return rec.reach ~= nil and Hit(rec, now) <= rec.reach
end

-- Covered holds at the boundary itself, so a wake for it lands this much past.
Rules.COVER_PAST = 0.01

-- How a step treats a record still in play: near (the cooldown watch), ticks
-- (needs the per-frame step), and otherwise the seconds until the next step it
-- needs. A paused countdown is frozen, so it waits for its age limit, or, while
-- a press covers it, for the moment the moving hit passes the press's reach; a
-- canceled record ticks until its short grace ends, paused or not.
function Rules.Schedule(rec, phase, now, lead)
    local toStart = Rules.Countdown(rec, now)
    local near = phase ~= "WAIT" or toStart <= lead
    if near and (not rec.left or rec.stopAt) then return near, true, nil end
    local due = rec.born + Rules.MAX_AGE - now
    if not rec.left and toStart - lead < due then due = toStart - lead end
    if near and rec.left and Rules.Covered(rec, now) then
        local uncover = rec.reach - Hit(rec, now) + Rules.COVER_PAST
        if uncover < due then due = uncover end
    end
    return near, false, due
end

function Rules.Allowed(mode, ready)
    if mode == "OFF" then return false end
    if mode == "READY" then return ready == true end
    return true
end

local SHOWN = { WAIT = true, GO = true, NOW = true }

-- The soonest record within lead that its mode allows; nothing while dead,
-- except a test run.
function Rules.Pick(records, now, lead, modeOf, ready, dead)
    local best, bestLeft
    for _, rec in pairs(records) do
        if (rec.test or not dead) and SHOWN[Rules.Phase(rec, now)] and not Rules.Covered(rec, now) then
            local toStart = Rules.Countdown(rec, now)
            local within = toStart <= (rec.test and Rules.TEST_LEAD or lead)
            if within and (rec.test or Rules.Allowed(modeOf(rec.id), ready)) then
                if not best or toStart < bestLeft then best, bestLeft = rec, toStart end
            end
        end
    end
    return best
end

-- Returns: show the cast-start word, the color key ("TEXT", "GO", "GRAY"),
-- the not-ready look, and the glow.
function Rules.Look(phase, ready)
    local word = phase == "NOW"
    if not ready then return word, "GRAY", true, false end
    if phase == "WAIT" then return word, "TEXT", false, false end
    return word, "GO", false, true
end

-- Text mode's big-line label and timer and the small line. Not ready, the
-- count moves to the small line.
function Rules.TextLines(word, notReady, count, name)
    local timer = word and Rules.NOW_WORD or count
    if notReady then return Rules.NOT_READY, "", name .. "  " .. timer end
    if word then return Rules.TEXT_LABEL_NOW, timer, name end
    return Rules.TEXT_LABEL, timer, name
end

-- "READY", "NOT_READY" or nil; each plays at most once per record.
function Rules.SoundFor(rec, phase, ready)
    if phase ~= "GO" and phase ~= "NOW" then return nil end
    if ready then
        if not rec.readySounded then
            rec.readySounded = true
            return "READY"
        end
    elseif not rec.readySounded and not rec.notReadySounded then
        rec.notReadySounded = true
        return "NOT_READY"
    end
    return nil
end

-- isOnGCD reads nil while the cooldown is idle, so only `true` counts.
function Rules.IsReady(isActive, isOnGCD)
    return isActive ~= true or isOnGCD == true
end

function Rules.IsPress(wasReady, isActive, isOnGCD)
    return wasReady == true and not Rules.IsReady(isActive, isOnGCD)
end

-- A press covers every record whose window is open. Its reach is the later of
-- the hit and the time Spell Reflection, pressed now, stays up, so a window
-- longer than Reflection is still covered while its hit does not move.
function Rules.MarkPressed(records, now)
    local count = 0
    for _, rec in pairs(records) do
        local phase = Rules.Phase(rec, now)
        if (phase == "GO" or phase == "NOW") and not Rules.Covered(rec, now) then
            rec.reach = math_max(Hit(rec, now), now + Rules.REFLECT_LASTS)
            count = count + 1
        end
    end
    return count
end
