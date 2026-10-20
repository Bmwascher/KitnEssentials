-- ╔══════════════════════════════════════════════════════════╗
-- ║  WindMapState.lua                                        ║
-- ║  Module: Dungeon Timers (wind map state)                 ║
-- ║  Purpose: Wind direction admission, the next-wind        ║
-- ║           sequence, forecast order and card text. Plain  ║
-- ║           Lua only, no WoW API, no frames, no timers.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local pairs = pairs
local type = type
local tostring = tostring
local math_ceil = math.ceil
local math_huge = math.huge
local table_sort = table.sort

local Map = {}

-- Live records per kind. More than the provider ever publishes at once, so
-- passing it means the input can no longer be followed. From then on no
-- receipt of either kind is admitted: the cards empty as the admitted records
-- retire, and Next wind reads Syncing until the encounter ends.
local CAP = 4

-- The icon paths BigWigs sends for the four wind sides, in provider order:
-- North-West, South-West, South-East, North-East.
local ICON_DIRECTION = {
    ["Interface\\AddOns\\BigWigs\\Media\\Icons\\misc_arrowlup.tga"] = 1,
    ["Interface\\AddOns\\BigWigs\\Media\\Icons\\misc_arrowleft.tga"] = 2,
    ["Interface\\AddOns\\BigWigs\\Media\\Icons\\misc_arrowdown.tga"] = 3,
    ["Interface\\AddOns\\BigWigs\\Media\\Icons\\misc_arrowright.tga"] = 4,
}

function Map.New()
    return {
        records = {}, live = { wind = 0, spit = 0 }, seq = 0,
        held = nil, cast = nil, lost = false, unsure = false, overflow = false,
    }
end

local function isWholeCount(v)
    return type(v) == "number" and v == v and v >= 1 and v ~= math_huge and v % 1 == 0
end

-- Icon and counter come from the same provider count, so a disagreement means
-- malformed input. No side is assumed for it.
function Map.ReadDirection(icon, counter)
    if type(icon) ~= "string" or not isWholeCount(counter) then return nil end
    local index = ICON_DIRECTION[icon]
    if index == nil or (counter - 1) % 4 + 1 ~= index then return nil end
    return index
end

-- Forecast deadline, then receipt order. A due or casting occurrence keeps
-- its rank; only its card text changes.
local function ranksBefore(a, b)
    if a.deadline ~= b.deadline then return a.deadline < b.deadline end
    return a.seq < b.seq
end

function Map.Order(list)
    table_sort(list, ranksBefore)
    return list
end

local function firstWind(map, side)
    local first, tied
    for _, rec in pairs(map.records) do
        if rec.kind == "wind" and not rec.confirmed and rec.deadline ~= nil
            and (side == nil or rec.direction == side) then
            if first == nil or ranksBefore(rec, first) then
                tied = first ~= nil and first.deadline == rec.deadline
                first = rec
            elseif rec.deadline == first.deadline then
                tied = true
            end
        end
    end
    return first, tied
end

local function hasCard(map, side)
    for _, rec in pairs(map.records) do
        if rec.kind == "wind" and not rec.confirmed and rec.direction == side then return true end
    end
    return false
end

-- An ended card may still have an uncast wind. Losing its held side makes
-- later cast-to-forecast matching ambiguous.
local function noteUnsure(map)
    local held = map.held
    if held and held.published and not hasCard(map, held.direction) then map.unsure = true end
end

local function loseSequence(map)
    noteUnsure(map)
    map.lost = true
    map.held = nil
end

function Map.Admit(map, inst, generation, kind, direction)
    if map.overflow or map.live[kind] >= CAP then
        map.overflow = true
        return nil
    end
    map.seq = map.seq + 1
    local rec = { generation = generation, kind = kind, direction = direction, seq = map.seq }
    map.records[inst] = rec
    map.live[kind] = map.live[kind] + 1
    -- The provider labels each wind by its receipt count, so the first wind
    -- received is the first of the sequence; it is held from its receipt.
    if kind == "wind" and map.held == nil and not (map.lost or map.inferenceWithdrawn) then
        map.held = { direction = direction, published = true }
    end
    return rec
end

function Map.PhaseOf(stage)
    if stage == 1 then return "airborne" end
    if stage == 2 then return "grounded" end
    return nil
end

-- The encounter's own stage. It moves only the placement phase; the wind
-- sequence continues across the landing.
function Map.NoteStage(map, stage)
    if stage == nil then return end
    map.stage = stage
    map.phase = Map.PhaseOf(stage)
end

-- Boss lifecycle evidence for one encounter. It outlives the store, so a map
-- restarted mid-encounter keeps what was seen and any withdrawal.
function Map.NewEvidence(encounterId)
    return { encounterId = encounterId, seen = {}, withdrawn = false }
end

-- A lost boss may never cast the held wind, so only live published cards
-- remain usable for this encounter.
function Map.WithdrawInference(map, evidence)
    noteUnsure(map)
    map.inferenceWithdrawn = true
    map.held = nil
    if evidence then evidence.withdrawn = true end
end

-- A mid-pull store missed earlier winds, including overdue casts whose
-- cards ended. It cannot safely resume the sequence from surviving cards.
function Map.Resume(map, evidence, fromStart)
    if fromStart and evidence ~= nil and not evidence.withdrawn then return end
    Map.WithdrawInference(map)
    if not fromStart then map.unsure = true end
end

-- One fixed boss token's reading; nil means secret or unreadable. A readable
-- present-and-dead boss, or a token read present earlier in this encounter and
-- now readably absent, is lost evidence. A token names no boss, so either
-- boss counts, and an unreadable answer changes nothing.
function Map.BossLost(seen, unit, exists, dead)
    if exists == true then
        seen[unit] = true
        return dead == true
    end
    if exists == false then return seen[unit] == true end
    return false
end

local function currentRecord(map, inst, generation)
    local rec = map.records[inst]
    if rec and rec.generation == generation then return rec end
    return nil
end

function Map.NoteCastStart(map, inst, generation, castStart)
    local rec = currentRecord(map, inst, generation)
    if rec and rec.castStart == nil then rec.castStart = castStart end
end

-- The provider's owner shut down. Its occurrences are gone and any open cast
-- is closed unread, so the sequence is lost until a confirmed wind.
function Map.EndHistory(map)
    map.cast = nil
    loseSequence(map)
end

-- An unreadable start may supersede Winds; discard its old association
-- unless the readable unit and bar prove this repeats the same cast. Boss
-- casts stay secret for the whole pull in a keystone, so no cast can step the
-- sequence again: only live published sides remain. True when this switched.
function Map.UnreadableCast(map, unit, bar)
    local open = map.cast
    if open and unit ~= nil and bar ~= nil and open.unit == unit and open.bar == bar then return false end
    map.cast = nil
    if map.inferenceWithdrawn then return false end
    Map.WithdrawInference(map)
    return true
end

-- Keep the held deadline after its card ends. Callers also sample before
-- retirement and cast start so a hidden panel does not depend on rendering.
local function settle(map)
    local held = map.held
    if held == nil then return nil end
    local carrier = firstWind(map, held.direction)
    if carrier then
        held.deadline = carrier.deadline
        held.published = true
    end
    return carrier
end

-- A finished forecast changes card text, not the held wind.
function Map.NoteStopped(map, inst, generation, now, finished)
    local rec = currentRecord(map, inst, generation)
    if not rec or rec.stoppedAt ~= nil then return end
    settle(map)
    rec.stoppedAt = now
    if finished then rec.completedAt = now end
end

-- Ending a forecast does not prove its wind happened. After sequence loss
-- or withdrawal, an unconfirmed ended wind prevents matching later cards.
function Map.NoteRetired(map, inst, generation)
    local rec = currentRecord(map, inst, generation)
    if not rec then return end
    settle(map)
    map.records[inst] = nil
    map.live[rec.kind] = map.live[rec.kind] - 1
    if rec.kind == "wind" and not rec.confirmed and (map.lost or map.inferenceWithdrawn) then
        map.unsure = true
    end
end

-- A readable start identifies Winds, not its forecast. Match the held wind
-- or one unambiguous due card; an earlier wind without a card blocks recovery.
function Map.BindCast(map, unit, bar, now, lead)
    local open = map.cast
    if open then
        if open.unit == unit and open.bar == bar then return open.direction end
        loseSequence(map)
    end
    local direction
    if map.lost or map.inferenceWithdrawn then
        local first, tied = firstWind(map)
        if first and not tied and not map.unsure and first.deadline - now <= lead then
            direction = first.direction
        end
    else
        settle(map)
        local held = map.held
        if held and held.deadline ~= nil and held.deadline - now <= lead then direction = held.direction end
    end
    map.cast = { unit = unit, bar = bar, direction = direction }
    return direction
end

-- Only an owned success advances. Failure keeps the side for a recast;
-- an unowned success means a wind passed outside the tracked sequence.
function Map.CastEnded(map, unit, bar, succeeded)
    local cast = map.cast
    if not (cast and cast.unit == unit and cast.bar == bar) then return false end
    map.cast = nil
    if not succeeded then return true end
    local direction = cast.direction
    if direction == nil then
        loseSequence(map)
        return true
    end
    local carrier = firstWind(map, direction)
    if carrier then carrier.confirmed = true end
    map.lost = false
    if not map.inferenceWithdrawn then map.held = { direction = direction % 4 + 1 } end
    return true
end

-- After withdrawal, directions last only as long as their published cards.
function Map.NextWind(map)
    if map.overflow then return "syncing" end
    if map.inferenceWithdrawn then
        local first = firstWind(map)
        if first == nil or first.direction == nil then return "syncing" end
        return "direction", first.direction, first
    end
    if map.lost then return "syncing" end
    local carrier = settle(map)
    local held = map.held
    if held == nil then return "waiting" end
    if held.direction == nil then return "syncing" end
    return "direction", held.direction, carrier
end

function Map.CardText(view, now)
    if view.paused then return "Paused" end
    if view.castStart ~= nil then return "Casting" end
    if view.completedAt ~= nil and view.kind == "wind" then return "Due" end
    local left = view.deadline - now
    if view.stoppedAt == nil and left > 0 then return tostring(math_ceil(left)) end
    if view.soon then return "Soon" end
    return ""
end

KE._DungeonWindMapState = Map
