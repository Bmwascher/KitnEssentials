-- Wind map decisions: direction admission, the next-wind sequence, forecast
-- order and card text. Inputs are plain values; frames, event timing, secret
-- values and orientation are in-game checks.
local L = require("dev.spec._ke_loader")

-- The icon paths BigWigs sends with a wind forecast, in its side order.
local ICONS = {
    "Interface\\AddOns\\BigWigs\\Media\\Icons\\misc_arrowlup.tga",
    "Interface\\AddOns\\BigWigs\\Media\\Icons\\misc_arrowleft.tga",
    "Interface\\AddOns\\BigWigs\\Media\\Icons\\misc_arrowdown.tga",
    "Interface\\AddOns\\BigWigs\\Media\\Icons\\misc_arrowright.tga",
}
local LEAD = 5

-- One live record with its forecast deadline, as the glue fills it.
local function admit(M, map, kind, direction, deadline)
    local inst = {}
    local rec = M.Admit(map, inst, 1, kind, direction)
    if rec then rec.deadline = deadline end
    return inst, rec
end

local function ordered(M, map)
    local list = {}
    for _, rec in pairs(map.records) do list[#list + 1] = rec end
    return M.Order(list)
end

local function stateOf(M, map)
    return (M.NextWind(map))
end

local function sideOf(M, map)
    local _, side = M.NextWind(map)
    return side
end

-- A Winds cast on boss1 that starts at now and succeeds.
local function castWind(M, map, bar, now)
    M.BindCast(map, "boss1", bar, now, LEAD)
    return M.CastEnded(map, "boss1", bar, true)
end

describe("wind direction admission", function()
    it("reads the side from an icon and counter that agree", function()
        local M = L.loadWindMapState()
        local cases = {
            { icon = 1, counter = 1, side = 1 },
            { icon = 2, counter = 2, side = 2 },
            { icon = 3, counter = 3, side = 3 },
            { icon = 4, counter = 4, side = 4 },
            { icon = 1, counter = 5, side = 1 },
            { icon = 4, counter = 8, side = 4 },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.side, M.ReadDirection(ICONS[c.icon], c.counter))
        end
    end)

    it("refuses disagreeing, unknown or malformed input instead of assuming a side", function()
        local M = L.loadWindMapState()
        local cases = {
            { icon = ICONS[2], counter = 1 },
            { icon = "Interface\\Icons\\INV_Misc_QuestionMark", counter = 1 },
            { icon = ICONS[1], counter = 0 },
            { icon = ICONS[1], counter = 1.5 },
            { icon = ICONS[1], counter = nil },
            { icon = 136243, counter = 1 },
            { icon = nil, counter = 1 },
        }
        for _, c in ipairs(cases) do
            assert.is_nil(M.ReadDirection(c.icon, c.counter))
        end
    end)
end)

describe("next wind", function()
    it("waits for the first published wind, then holds its side through later, replaced and expired forecasts", function()
        local M = L.loadWindMapState()
        local map = M.New()
        assert.equals("waiting", stateOf(M, map))
        local first = admit(M, map, "wind", 1, 10)
        admit(M, map, "wind", 2, 30)
        assert.equals("direction", stateOf(M, map))
        assert.equals(1, sideOf(M, map))
        -- Canceled or expired with no provider stop: the later wind is not taken.
        M.NoteRetired(map, first, 1)
        assert.equals(1, sideOf(M, map))
        -- A same-label replacement carries the held side again.
        local again, againRec = admit(M, map, "wind", 1, 12)
        local state, side, carrier = M.NextWind(map)
        assert.equals("direction", state)
        assert.equals(1, side)
        assert.equals(againRec, carrier)
        -- Run out, stopped without a read Finished, then retired: still held.
        againRec.deadline = -5
        M.NoteStopped(map, again, 1, -5, false)
        assert.equals(1, sideOf(M, map))
        M.NoteRetired(map, again, 1)
        state, side, carrier = M.NextWind(map)
        assert.equals("direction", state)
        assert.equals(1, side)
        assert.is_nil(carrier)
    end)

    it("advances exactly one step on a confirmed success, once, whatever later forecasts say", function()
        local M = L.loadWindMapState()
        local map = M.New()
        local firstInst, first = admit(M, map, "wind", 1, 10)
        local _, second = admit(M, map, "wind", 2, 30)
        assert.equals(1, sideOf(M, map))
        M.BindCast(map, "boss1", 7, 9, LEAD)
        assert.equals(1, sideOf(M, map))
        assert.is_true(M.CastEnded(map, "boss1", 7, true))
        assert.is_true(first.confirmed)
        local state, side, carrier = M.NextWind(map)
        assert.equals("direction", state)
        assert.equals(2, side)
        assert.equals(second, carrier)
        -- The same success again, or one on another unit or bar, is not the open cast's.
        assert.is_false(M.CastEnded(map, "boss1", 7, true))
        assert.is_false(M.CastEnded(map, "boss2", 7, true))
        assert.is_false(M.CastEnded(map, "boss1", 8, true))
        -- The confirmed wind's own stop and retirement, and a later forecast, move nothing.
        M.NoteStopped(map, firstInst, 1, 10, true)
        M.NoteRetired(map, firstInst, 1)
        admit(M, map, "wind", 4, 50)
        assert.equals(2, sideOf(M, map))
    end)

    it("keeps the held wind for a cast that starts after its forecast retired, rendered or not", function()
        local M = L.loadWindMapState()
        local cases = {
            { name = "rendered, stopped", rendered = true, stop = true },
            { name = "never rendered, stopped", stop = true },
            { name = "never rendered, canceled" },
        }
        for _, c in ipairs(cases) do
            local map = M.New()
            local inst = admit(M, map, "wind", 1, 10)
            admit(M, map, "wind", 2, 30)
            if c.rendered then assert.equals(1, sideOf(M, map), c.name) end
            if c.stop then M.NoteStopped(map, inst, 1, 10, true) end
            M.NoteRetired(map, inst, 1)
            if c.rendered then assert.equals(1, sideOf(M, map), c.name) end
            M.BindCast(map, "boss1", 3, 12, LEAD)
            assert.is_true(M.CastEnded(map, "boss1", 3, true), c.name)
            local state, side, carrier = M.NextWind(map)
            assert.equals("direction", state, c.name)
            assert.equals(2, side, c.name)
            assert.is_not_nil(carrier, c.name)
        end
    end)

    it("holds the side through an interrupt or failure, before or after its forecast retired, and confirms the recast", function()
        local M = L.loadWindMapState()
        for _, retire in ipairs({ false, true }) do
            local map = M.New()
            local inst = admit(M, map, "wind", 3, 10)
            assert.equals(3, sideOf(M, map))
            M.BindCast(map, "boss1", 1, 9, LEAD)
            if retire then
                M.NoteStopped(map, inst, 1, 10, false)
                M.NoteRetired(map, inst, 1)
            end
            assert.is_true(M.CastEnded(map, "boss1", 1, false))
            assert.equals("direction", stateOf(M, map), tostring(retire))
            assert.equals(3, sideOf(M, map), tostring(retire))
            castWind(M, map, 2, 14)
            assert.equals(4, sideOf(M, map), tostring(retire))
        end
    end)

    it("leaves a cast unowned before the lead or with nothing held, and recovers at the next owned success", function()
        local M = L.loadWindMapState()
        local cases = {
            { name = "too early", winds = { { 1, 20 } } },
            { name = "none published", winds = {} },
        }
        for _, c in ipairs(cases) do
            local map = M.New()
            for _, w in ipairs(c.winds) do admit(M, map, "wind", w[1], w[2]) end
            assert.is_true(castWind(M, map, 5, 9), c.name)
            assert.equals("syncing", stateOf(M, map), c.name)
        end

        -- While lost no forecast is adopted, and two winds due together own nothing.
        local tie = M.New()
        castWind(M, tie, 5, 9)
        admit(M, tie, "wind", 2, 30)
        admit(M, tie, "wind", 3, 30)
        assert.equals("syncing", stateOf(M, tie))
        castWind(M, tie, 6, 29)
        assert.equals("syncing", stateOf(M, tie))

        -- The one wind due within the lead owns the next cast, and its success recovers.
        local map = M.New()
        castWind(M, map, 5, 9)
        admit(M, map, "wind", 2, 30)
        castWind(M, map, 6, 29)
        assert.equals("direction", stateOf(M, map))
        assert.equals(3, sideOf(M, map))

        -- A held wind whose card ended, before or after the loss, may still be the
        -- next cast, so a later cast is not tied to a later card.
        for _, endsFirst in ipairs({ true, false }) do
            local unsure = M.New()
            local inst = admit(M, unsure, "wind", 1, 10)
            if endsFirst then M.NoteRetired(unsure, inst, 1) end
            M.EndHistory(unsure)
            if not endsFirst then M.NoteRetired(unsure, inst, 1) end
            admit(M, unsure, "wind", 2, 30)
            castWind(M, unsure, 2, 29)
            assert.equals("syncing", stateOf(M, unsure), tostring(endsFirst))
        end
    end)

    it("loses the sequence on an owner shutdown, an overflow, a cast that never ended or an unknown side", function()
        local M = L.loadWindMapState()
        local cases = {
            { name = "owner shutdown", act = function(map) M.EndHistory(map) end },
            { name = "overflow", act = function(map)
                for _ = 1, 5 do admit(M, map, "spit", nil, 60) end
            end },
            { name = "a cast that never ended", act = function(map)
                M.BindCast(map, "boss1", 2, 29, LEAD)
                M.BindCast(map, "boss1", 3, 29, LEAD)
            end },
        }
        for _, c in ipairs(cases) do
            local map = M.New()
            admit(M, map, "wind", 1, 10)
            castWind(M, map, 1, 9)
            admit(M, map, "wind", 2, 30)
            assert.equals(2, sideOf(M, map), c.name)
            c.act(map)
            assert.equals("syncing", stateOf(M, map), c.name)
        end

        -- An owner shutdown closes the open cast, so its later success is not read.
        local closed = M.New()
        admit(M, closed, "wind", 1, 10)
        M.BindCast(closed, "boss1", 4, 9, LEAD)
        M.EndHistory(closed)
        assert.is_false(M.CastEnded(closed, "boss1", 4, true))
        assert.equals("syncing", stateOf(M, closed))

        local unknown = M.New()
        admit(M, unknown, "wind", nil, 10)
        assert.equals("syncing", stateOf(M, unknown))
        castWind(M, unknown, 1, 9)
        assert.equals("syncing", stateOf(M, unknown))
    end)

    it("follows only live published winds after an unreadable start, switching once", function()
        local M = L.loadWindMapState()
        local map = M.New()
        admit(M, map, "wind", 1, 10)
        castWind(M, map, 1, 9)
        local secondInst = admit(M, map, "wind", 2, 30)
        assert.equals(2, sideOf(M, map))
        assert.is_true(M.UnreadableCast(map, "boss1", 9))
        assert.equals(2, sideOf(M, map))
        M.NoteRetired(map, secondInst, 1)
        assert.equals("syncing", stateOf(M, map))
        admit(M, map, "wind", 3, 50)
        assert.is_false(M.UnreadableCast(map, "boss1", 10))
        assert.equals(3, sideOf(M, map))
    end)

    it("supersedes the open cast on an unreadable start, unless it repeats the open cast's unit and bar", function()
        local M = L.loadWindMapState()
        local superseded = M.New()
        admit(M, superseded, "wind", 1, 10)
        M.BindCast(superseded, "boss1", 4, 9, LEAD)
        assert.is_true(M.UnreadableCast(superseded, "boss1", 5))
        assert.is_false(M.CastEnded(superseded, "boss1", 4, true))
        assert.equals(1, sideOf(M, superseded))
        local repeated = M.New()
        admit(M, repeated, "wind", 1, 10)
        M.BindCast(repeated, "boss1", 4, 9, LEAD)
        assert.is_false(M.UnreadableCast(repeated, "boss1", 4))
        assert.is_true(M.CastEnded(repeated, "boss1", 4, true))
        assert.equals(2, sideOf(M, repeated))
    end)

    it("shows only live published winds once withdrawn, never a held or stepped side", function()
        local M = L.loadWindMapState()
        -- Withdrawn while the held wind's card is live: its side lasts as long as the card.
        local live = M.New()
        local liveInst = admit(M, live, "wind", 1, 10)
        assert.equals(1, sideOf(M, live))
        M.WithdrawInference(live)
        assert.equals(1, sideOf(M, live))
        M.NoteRetired(live, liveInst, 1)
        assert.equals("syncing", stateOf(M, live))

        -- Withdrawn after the card ended: the side held through the delay is dropped.
        local ended = M.New()
        local endedInst = admit(M, ended, "wind", 1, 10)
        M.NoteRetired(ended, endedInst, 1)
        assert.equals(1, sideOf(M, ended))
        M.WithdrawInference(ended)
        assert.equals("syncing", stateOf(M, ended))
        admit(M, ended, "wind", 2, 30)
        assert.equals(2, sideOf(M, ended))
        -- That ended wind may still be due, so a cast does not take the later card.
        castWind(M, ended, 1, 29)
        assert.equals(2, sideOf(M, ended))

        -- A stepped side with no card is dropped.
        local stepped = M.New()
        admit(M, stepped, "wind", 2, 10)
        castWind(M, stepped, 1, 9)
        assert.equals(3, sideOf(M, stepped))
        M.WithdrawInference(stepped)
        assert.equals("syncing", stateOf(M, stepped))

        -- A cast open across the withdrawal still hands its card over to the
        -- next published wind, and steps nothing.
        local map = M.New()
        admit(M, map, "wind", 2, 10)
        castWind(M, map, 1, 9)
        admit(M, map, "wind", 3, 30)
        admit(M, map, "wind", 4, 50)
        M.BindCast(map, "boss1", 2, 29, LEAD)
        M.WithdrawInference(map)
        assert.equals(3, sideOf(M, map))
        assert.is_true(M.CastEnded(map, "boss1", 2, true))
        assert.equals(4, sideOf(M, map))
    end)

    it("starts any store after the encounter's start withdrawn and unsure, keeping a withdrawal", function()
        local M = L.loadWindMapState()
        local evidence = M.NewEvidence(2623)
        local first = M.New()
        M.Resume(first, evidence, true)
        admit(M, first, "wind", 2, 10)
        castWind(M, first, 1, 9)
        assert.equals(3, sideOf(M, first))
        assert.is_false(M.BossLost(evidence.seen, "boss2", true, false))
        assert.is_true(M.BossLost(evidence.seen, "boss2", false, nil))
        M.WithdrawInference(first, evidence)

        -- A map toggle or a profile change recreates the store in the same
        -- pull, after a withdrawal or not, and a first start mid-encounter has no
        -- evidence at all. None saw the winds before it: a delayed North-West may
        -- still be due, so a cast never takes a later card and each card shows
        -- until it ends.
        local cases = {
            { name = "recreated after a withdrawal", evidence = evidence },
            { name = "recreated, bosses alive", evidence = M.NewEvidence(2623) },
            { name = "first start mid-encounter" },
        }
        for _, c in ipairs(cases) do
            local map = M.New()
            M.Resume(map, c.evidence)
            local swInst = admit(M, map, "wind", 2, 30)
            admit(M, map, "wind", 3, 50)
            assert.equals(2, sideOf(M, map), c.name)
            castWind(M, map, 1, 29)
            assert.equals(2, sideOf(M, map), c.name)
            M.NoteRetired(map, swInst, 1)
            assert.equals(3, sideOf(M, map), c.name)
        end
    end)
end)

describe("placement phase", function()
    it("reads stage 1 as airborne and stage 2 as grounded, anything else as unknown", function()
        local M = L.loadWindMapState()
        local cases = {
            { stage = 1, phase = "airborne" },
            { stage = 2, phase = "grounded" },
            { stage = 3, phase = nil },
            { stage = nil, phase = nil },
            { stage = 0, phase = nil },
            { stage = 1.5, phase = nil },
            { stage = "2", phase = nil },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.phase, M.PhaseOf(c.stage), tostring(c.stage))
        end
    end)

    it("moves the phase with the stage and keeps the wind sequence across the landing", function()
        local M = L.loadWindMapState()
        local map = M.New()
        M.NoteStage(map, 1)
        assert.equals("airborne", map.phase)
        admit(M, map, "wind", 1, 10)
        castWind(M, map, 1, 9)
        M.NoteStage(map, 2)
        assert.equals("grounded", map.phase)
        assert.equals(2, sideOf(M, map))
    end)
end)

describe("boss token evidence", function()
    it("counts only a readable dead boss or a readably lost token, never an unreadable one", function()
        local M = L.loadWindMapState()
        local cases = {
            { name = "present and dead", seen = false, exists = true, dead = true, lost = true },
            { name = "present and alive", seen = false, exists = true, dead = false, lost = false, marks = true },
            { name = "present, death unreadable", seen = false, exists = true, dead = nil, lost = false, marks = true },
            { name = "absent, never seen", seen = false, exists = false, lost = false },
            { name = "absent after present", seen = true, exists = false, lost = true },
            { name = "presence unreadable", seen = true, exists = nil, lost = false },
        }
        for _, c in ipairs(cases) do
            local seen = { boss2 = c.seen or nil }
            assert.equals(c.lost, M.BossLost(seen, "boss2", c.exists, c.dead), c.name)
            if c.marks then assert.is_true(seen.boss2, c.name) end
        end
    end)

    it("ends the map at the caster's loss and keeps it ended for the encounter", function()
        local M = L.loadWindMapState()
        local evidence = M.NewEvidence(2623)
        local steps = {
            { name = "alive", exists = true, dead = false, lost = false },
            { name = "unreadable", exists = nil, dead = nil, lost = false },
            { name = "dead", exists = true, dead = true, lost = true },
            { name = "read alive again", exists = true, dead = false, lost = true },
        }
        for _, s in ipairs(steps) do
            assert.equals(s.lost, M.CasterLost(evidence, "boss1", s.exists, s.dead), s.name)
        end
    end)
end)

describe("forecast order", function()
    it("ranks by forecast deadline, then receipt, whatever the card state", function()
        local M = L.loadWindMapState()
        local map = M.New()
        local _, spit = admit(M, map, "spit", nil, 12)
        local _, early = admit(M, map, "wind", 1, 5)
        local _, tied = admit(M, map, "wind", 2, 12)
        spit.castStart = 4
        local list = ordered(M, map)
        assert.equals(early, list[1])
        assert.equals(spit, list[2])
        assert.equals(tied, list[3])
    end)
end)

describe("record identity", function()
    it("ignores a stop, cast or retirement for another generation", function()
        local M = L.loadWindMapState()
        local map = M.New()
        local inst, rec = admit(M, map, "spit", nil, 6)
        M.NoteStopped(map, inst, 2, 5, true)
        M.NoteCastStart(map, inst, 2, 5)
        M.NoteRetired(map, inst, 2)
        assert.is_nil(rec.stoppedAt)
        assert.is_nil(rec.castStart)
        assert.equals(rec, map.records[inst])
    end)

    it("refuses a fifth live record of one kind and syncs", function()
        local M = L.loadWindMapState()
        local map = M.New()
        for _ = 1, 4 do
            local _, rec = admit(M, map, "spit", nil, 5)
            assert.is_not_nil(rec)
        end
        local _, refused = admit(M, map, "spit", nil, 5)
        assert.is_nil(refused)
        assert.equals("syncing", stateOf(M, map))
    end)
end)

describe("card text", function()
    it("shows the forecast count, a wait, a provider completion, a cast or a pause", function()
        local M = L.loadWindMapState()
        local cases = {
            { view = { kind = "spit", deadline = 3.2 }, text = "4" },
            { view = { kind = "spit", deadline = -1, soon = true }, text = "Soon" },
            { view = { kind = "wind", deadline = -1 }, text = "" },
            { view = { kind = "wind", deadline = -1, stoppedAt = -0.5, completedAt = -0.5 }, text = "Due" },
            { view = { kind = "wind", deadline = -1, stoppedAt = -0.5 }, text = "" },
            { view = { kind = "spit", deadline = 0.1, stoppedAt = -0.1, soon = true }, text = "Soon" },
            { view = { kind = "spit", deadline = -1, stoppedAt = -0.5, castStart = -0.2 }, text = "Casting" },
            { view = { kind = "wind", deadline = 5, paused = true }, text = "Paused" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.text, M.CardText(c.view, 0))
        end
    end)
end)
