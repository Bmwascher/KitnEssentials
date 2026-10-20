-- The encounter stage latch and the phase rule end. Receipts are reduced to
-- the curated row and the published duration; receipt delivery, ordering and
-- health curves are in-game checks.
local L = require("dev.spec._ke_loader")

local CUE = { spellID = 381525, duration = 5, stage = 2 }

describe("stage cue match", function()
    it("matches the cue's row at a duration that rounds to the cue's, as the provider rounds", function()
        local DT = L.loadDungeonTimers()
        local cases = {
            { name = "exact", id = 381525, time = 5, stage = 2 },
            { name = "rounds up", id = 381525, time = 4.96, stage = 2 },
            { name = "rounds down", id = 381525, time = 5.04, stage = 2 },
            { name = "rounds to 4.9", id = 381525, time = 4.94, stage = nil },
            { name = "rounds to 5.1", id = 381525, time = 5.06, stage = nil },
            { name = "opening Firebreath", id = 381525, time = 1, stage = nil },
            { name = "later Firebreath", id = 381525, time = 20, stage = nil },
            { name = "opening Stormslam", id = 381512, time = 5, stage = nil },
            { name = "non-number duration", id = 381525, time = "5", stage = nil },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.stage, DT._StageCueStage(CUE, c.id, c.time), c.name)
        end
        assert.is_nil(DT._StageCueStage(nil, 381525, 5), "no cue")
    end)
end)

describe("stage latch", function()
    it("moves a known stage forward only", function()
        local DT = L.loadDungeonTimers()
        local cases = {
            { name = "landing", from = 1, stage = 2, result = 2 },
            { name = "repeat", from = 2, stage = 2, result = 2 },
            { name = "never back", from = 2, stage = 1, result = 2 },
            { name = "no starting stage", from = nil, stage = 2, result = nil },
        }
        for _, c in ipairs(cases) do
            DT._encounterStage = c.from
            DT:_NoteEncounterStage(c.stage)
            assert.equals(c.result, DT._encounterStage, c.name)
        end
    end)
end)

describe("phase rule end", function()
    it("ends a rule only once the encounter stage reaches its endsAtStage", function()
        local DT = L.loadDungeonTimers()
        local cases = {
            { name = "no stage", rule = { endsAtStage = 2 }, stage = nil, ended = false },
            { name = "earlier stage", rule = { endsAtStage = 2 }, stage = 1, ended = false },
            { name = "that stage", rule = { endsAtStage = 2 }, stage = 2, ended = true },
            { name = "later stage", rule = { endsAtStage = 2 }, stage = 3, ended = true },
            { name = "rule without endsAtStage", rule = {}, stage = 2, ended = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.ended, DT._PhaseRuleEnded(c.rule, c.stage), c.name)
        end
    end)
end)
