-- Shield swap: which boss of a pair carries the shield, counted from the
-- swap messages, and the phase rules that end at a swap. Message delivery and
-- health curves are in-game checks.
local L = require("dev.spec._ke_loader")

local CFG = { message = 1310311, start = "boss2", units = { "boss1", "boss2" } }

describe("shield swap", function()
    it("moves the shield once per swap message, ignoring other keys and a repeat inside the throttle", function()
        local Swap = L.loadShieldSwapState()
        local swap = Swap.New(CFG)
        local steps = {
            { name = "pull", key = nil, at = 0, moved = false, shielded = "boss2" },
            { name = "other message", key = 1289059, at = 10, moved = false, shielded = "boss2" },
            { name = "first swap", key = 1310311, at = 66, moved = true, shielded = "boss1" },
            { name = "repeat inside the throttle", key = 1310311, at = 67.5, moved = false, shielded = "boss1" },
            { name = "second swap", key = 1310311, at = 129, moved = true, shielded = "boss2" },
        }
        for _, s in ipairs(steps) do
            if s.key then assert.equals(s.moved, Swap.OnMessage(swap, s.key, s.at), s.name) end
            assert.equals(s.shielded, swap.shielded, s.name)
        end
    end)
end)

describe("phase rule end at a swap", function()
    it("ends an endsOnShield rule only once a swap has moved the shield to its unit", function()
        local DT = L.loadDungeonTimers()
        local Swap = L.loadShieldSwapState()
        local swap = Swap.New(CFG)
        local boss1 = { unit = "boss1", endsOnShield = true }
        local boss2 = { unit = "boss2", endsOnShield = true }
        assert.is_false(DT._PhaseRuleEnded(boss2, nil, swap), "the pull's starting shield")
        Swap.OnMessage(swap, 1310311, 66)
        assert.is_true(DT._PhaseRuleEnded(boss1, nil, swap), "swapped to boss1")
        assert.is_false(DT._PhaseRuleEnded(boss2, nil, swap), "boss2 not swapped to yet")
        assert.is_false(DT._PhaseRuleEnded({ unit = "boss1" }, nil, swap), "rule without endsOnShield")
        assert.is_false(DT._PhaseRuleEnded(boss1, nil, nil), "encounter without a swap")
    end)
end)

describe("shielded target warning", function()
    it("arms only when it is on, the encounter has a swap and the difficulty is Mythic or Mythic+", function()
        local Swap = L.loadShieldSwapState()
        local swap = Swap.New(CFG)
        local cases = {
            { name = "Mythic+", enabled = true, difficulty = 8, swap = swap, wanted = true },
            { name = "Mythic", enabled = true, difficulty = 23, swap = swap, wanted = true },
            { name = "Heroic", enabled = true, difficulty = 2, swap = swap, wanted = false },
            { name = "turned off", enabled = false, difficulty = 8, swap = swap, wanted = false },
            { name = "no swap encounter", enabled = true, difficulty = 8, swap = nil, wanted = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.wanted, Swap.WarningWanted(c.enabled, c.difficulty, c.swap), c.name)
        end
    end)
end)

describe("shielded target sound", function()
    it("plays when the text appears, at most once per 3 s, and never on a hidden answer", function()
        local Swap = L.loadShieldSwapState()
        local cue = {}
        local steps = {
            { name = "appears", shown = true, at = 0, plays = true },
            { name = "stays shown", shown = true, at = 1, plays = false },
            { name = "target away", shown = false, at = 1.5, plays = false },
            { name = "back inside the gap", shown = true, at = 2, plays = false },
            { name = "target away again", shown = false, at = 3.5, plays = false },
            { name = "back after the gap", shown = true, at = 4, plays = true },
            { name = "hidden answer", shown = nil, at = 8, plays = false },
            { name = "readable again", shown = true, at = 9, plays = true },
        }
        for _, s in ipairs(steps) do
            assert.equals(s.plays, Swap.NoteShown(cue, s.shown, s.at), s.name)
        end
    end)
end)
