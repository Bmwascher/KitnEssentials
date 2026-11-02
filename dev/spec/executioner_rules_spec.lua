-- Modules/Combat/ClassTools/ExecutionerRules.lua -- the refusal and guard
-- rules a later edit breaks silently: which signals are refused, when the
-- real buff may correct the count, when the cancel cue waits, which cancels
-- clear the count, what Create Macro may do, how often the cue sound plays,
-- and when Only in Combat hides the display. Secret flags, times and
-- readings are passed in, so no Blizzard fake is needed.
local L = require("dev.spec._ke_loader")

describe("executioner rules", function()
    local Rules

    before_each(function()
        Rules = L.loadExecutionerRules().ExecutionerRules
    end)

    -- A state holding `stacks` and timers ending at `ends`, each 18 s long.
    local function build(stacks, ends)
        local state = Rules.New()
        state.stacks = stacks
        for i, e in ipairs(ends) do
            state.timers[i] = { ends = e, len = 18 }
        end
        return state
    end

    it("merges a signal within 0.25 s of the last counted proc", function()
        -- seconds after the first proc, expected result, expected stacks
        local cases = {
            { 0.25, "merged", 1 },
            { 0.26, "counted", 2 },
        }
        for i, case in ipairs(cases) do
            local state = Rules.New()
            assert.equals("counted", Rules.Signal(state, "cast", 100, 18), "case " .. i)
            assert.equals(case[2], Rules.Signal(state, "cast", 100 + case[1], 18), "case " .. i)
            assert.equals(case[3], state.stacks, "case " .. i)
        end
    end)

    it("counts the buff door only until a strike door has been heard", function()
        local state = Rules.New()
        -- door, time, expected result
        local cases = {
            { "buff", 100, "counted" },
            { "echo", 101, "counted" },
            { "buff", 102, "buff_ignored" },
            { "cast", 103, "counted" },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], Rules.Signal(state, case[1], case[2], 18), "case " .. i)
        end
        assert.equals(3, state.stacks)
    end)

    it("ignores the cooldown doors inside the zone-in window and never the cast door", function()
        -- door, time, ignore until, expected result
        local cases = {
            { "echo", 100, 101, "zone_in" },
            { "buff", 100, 101, "zone_in" },
            { "cast", 100, 101, "counted" },
            { "echo", 101, 101, "counted" },
        }
        for i, case in ipairs(cases) do
            local state = Rules.New()
            assert.equals(case[4], Rules.Signal(state, case[1], case[2], 18, case[3]), "case " .. i)
        end
    end)

    it("maps only the strike and buff ids to a door and never compares a secret id", function()
        -- event, spell id, id secret, expected door
        local cases = {
            { "UNIT_SPELLCAST_SUCCEEDED", 445579, false, "cast" },
            { "SPELL_UPDATE_COOLDOWN", 445579, false, "echo" },
            { "SPELL_UPDATE_COOLDOWN", 445584, false, "buff" },
            { "UNIT_SPELLCAST_SUCCEEDED", 445584, false, nil },
            { "SPELL_UPDATE_COOLDOWN", 1680, false, nil },
            { "SPELL_UPDATE_COOLDOWN", nil, false, nil },
            { "UNIT_SPELLCAST_SUCCEEDED", 445579, true, nil },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[4], Rules.DoorFor(case[1], case[2], case[3]), "case " .. i)
        end
    end)

    it("reads the real count only when it is readable and checks only at a quiet moment", function()
        local aura = {}
        -- aura hidden, aura, applications, applications secret, expected count
        local reads = {
            { true, aura, 3, false, nil },
            { false, nil, nil, false, 0 },
            { false, aura, 3, true, nil },
            { false, aura, 0, false, 1 },
            { false, aura, 4, false, 4 },
        }
        for i, case in ipairs(reads) do
            assert.equals(case[5], Rules.ReadStacks(case[1], case[2], case[3], case[4]), "read " .. i)
        end
        -- now, test until, expected allowed (last proc at 100, next expiry at 110)
        local checks = {
            { 105, 106, false },
            { 100.1, nil, false },
            { 109.9, nil, false },
            { 105, nil, true },
            { 105, 104, true },
        }
        for i, case in ipairs(checks) do
            local state = build(1, { 110 })
            state.lastProc = 100
            assert.equals(case[3], Rules.CheckAllowed(state, case[1], case[2]), "check " .. i)
        end
    end)

    it("holds the cue while Sudden Death is up only with the hold on", function()
        -- wanted, wait for Sudden Death, Sudden Death up, expected shown, expected held
        local cases = {
            { true, true, true, false, true },
            { true, false, true, true, false },
            { true, true, false, true, false },
            { false, true, true, false, false },
        }
        for i, case in ipairs(cases) do
            local shown, held = Rules.CueState(case[1], case[2], case[3])
            assert.equals(case[4], shown, "case " .. i)
            assert.equals(case[5], held, "case " .. i)
        end
    end)

    it("clears only on a cancel of the buff by id or by name, never on a secret argument", function()
        -- argument, argument secret, expected
        local cases = {
            { 445584, false, true },
            { 23920, false, false },
            { "EXECUTIONER", false, true },
            { "Execute", false, false },
            { 445584, true, false },
            { nil, false, false },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], Rules.IsBuffCancel(case[1], case[2], "executioner"), "case " .. i)
        end
    end)

    it("refuses Create Macro in combat and with both lists full, edits before creating, general list first", function()
        -- in combat, existing index, general count, character count, expected plan.
        -- Each row pits the expected plan against a lower one whose condition
        -- also holds, so every priority pair is covered once.
        local cases = {
            { true, 3, 0, 0, "combat" },          -- over edit and account
            { true, 0, 120, 0, "combat" },        -- over character
            { true, 0, 120, 30, "combat" },       -- over full
            { false, 3, 0, 0, "edit" },           -- over account
            { false, 3, 120, 0, "edit" },         -- over character
            { false, 3, 120, 30, "edit" },        -- over full
            { false, 0, 0, 0, "account" },        -- over character
            { false, 0, 119, 30, "account" },     -- over full
            { false, nil, 120, 0, "character" },  -- over full
            { false, 0, 120, 30, "full" },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[5], Rules.MacroPlan(case[1], case[2], case[3], case[4], 120, 30), "case " .. i)
        end
    end)

    it("plays the cue sound at most once per quiet window", function()
        -- last played at, now, expected
        local cases = {
            { nil, 100, true },
            { 100, 102.9, false },
            { 100, 103, true },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], Rules.SoundDue(case[1], case[2]), "case " .. i)
        end
    end)

    it("lets Only in Combat hide the display out of combat unless a test run plays", function()
        -- only in combat, fighting, testing, expected
        local cases = {
            { false, false, false, true },
            { true, false, false, false },
            { true, true, false, true },
            { true, false, true, true },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[4], Rules.CombatAllows(case[1], case[2], case[3]), "case " .. i)
        end
    end)
end)
