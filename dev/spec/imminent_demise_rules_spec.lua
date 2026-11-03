-- Modules/Combat/ClassTools/ImminentDemiseRules.lua -- the refusal and
-- guard rules a later edit breaks silently: which strike signals count,
-- which glows prove a third strike, and when a proof may move the count.
-- Times and secret flags are passed in, so no Blizzard fake is needed.
local L = require("dev.spec._ke_loader")

describe("imminent demise rules", function()
    local Rules

    before_each(function()
        Rules = L.loadImminentDemiseRules().ImminentDemiseRules
    end)

    local function build(count, inStep, ghost)
        local state = Rules.New()
        state.count, state.inStep, state.ghost = count, inStep, ghost
        return state
    end

    it("merges a signal within 0.25 s of the last counted strike", function()
        -- seconds after the first strike, expected result, expected count
        local cases = {
            { 0.25, "merged", 1 },
            { 0.26, "counted", 2 },
        }
        for i, case in ipairs(cases) do
            local state = Rules.New()
            assert.equals("counted", Rules.Signal(state, "echo", 100), "case " .. i)
            assert.equals(case[2], Rules.Signal(state, "echo", 100 + case[1]), "case " .. i)
            assert.equals(case[3], state.count, "case " .. i)
        end
    end)

    it("counts the buff echo only until a strike echo has been heard", function()
        local state = Rules.New()
        -- door, time, expected result
        local cases = {
            { "buff", 100, "counted" },
            { "echo", 101, "counted" },
            { "buff", 102, "buff_ignored" },
            { "echo", 103, "counted" },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], Rules.Signal(state, case[1], case[2]), "case " .. i)
        end
    end)

    it("ignores both echoes inside the zone-in window and leaves the count alone", function()
        -- door, time, ignore until, expected result, expected count
        local cases = {
            { "echo", 100, 101, "zone_in", 0 },
            { "buff", 100, 101, "zone_in", 0 },
            { "echo", 101, 101, "counted", 1 },
        }
        for i, case in ipairs(cases) do
            local state = Rules.New()
            assert.equals(case[4], Rules.Signal(state, case[1], case[2], case[3]), "case " .. i)
            assert.equals(case[5], state.count, "case " .. i)
        end
    end)

    it("takes only the four plain Execute ids as an Execute glow and never compares a secret id", function()
        -- spell id, id secret, expected
        local cases = {
            { 163201, false, true },
            { 281000, false, true },
            { 330334, false, true },
            { 5308, false, true },
            { 7384, false, false },
            { nil, false, false },
            { 163201, true, false },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], Rules.IsGlow(case[1], case[2]), "case " .. i)
        end
    end)

    it("proves a counted strike with a glow up to 0.1 s before or after it", function()
        -- glow first, seconds between glow and strike, expected outcome
        local cases = {
            { false, 0.1, "matched" },
            { true, 0.1, "matched" },
            { false, 0.11, nil },
            { true, 0.11, nil },
        }
        for i, case in ipairs(cases) do
            local state = build(2, true)
            local outcome
            if case[1] then
                assert.is_nil(Rules.Glow(state, 100), "case " .. i)
                outcome = select(2, Rules.Signal(state, "echo", 100 + case[2]))
            else
                Rules.Signal(state, "echo", 100)
                outcome = Rules.Glow(state, 100 + case[2])
            end
            assert.equals(case[3], outcome, "case " .. i)
        end
    end)

    it("takes one proof per strike when several Execute ids light in one frame", function()
        -- steps ({ "glow" or a door, time }), expected number of proofs, expected count
        local cases = {
            { { { "echo", 100 }, { "glow", 100 }, { "glow", 100 }, { "glow", 100 } }, 1, 0 },
            { { { "glow", 100 }, { "glow", 100 }, { "glow", 100 }, { "buff", 100 }, { "echo", 100 } }, 1, 0 },
            -- A later strike can be proven again.
            { { { "echo", 100 }, { "glow", 100 }, { "glow", 100 },
                { "echo", 101 }, { "glow", 101 }, { "glow", 101 } }, 2, 1 },
        }
        for i, case in ipairs(cases) do
            local state = build(2, true)
            local proofs = 0
            for _, step in ipairs(case[1]) do
                local proof
                if step[1] == "glow" then
                    proof = Rules.Glow(state, step[2])
                else
                    proof = select(2, Rules.Signal(state, step[1], step[2]))
                end
                if proof then proofs = proofs + 1 end
            end
            assert.equals(case[2], proofs, "case " .. i)
            assert.equals(case[3], state.count, "case " .. i)
        end
    end)

    it("matches at 0, tolerates one mismatch while in step and sets the count to 0 otherwise", function()
        -- count, in step, last tolerated count, expected outcome, count after,
        -- in step after, tolerated count after
        local cases = {
            { 0, false, nil, "matched", 0, true, nil },
            { 0, true, 2, "matched", 0, true, nil },
            { 1, true, nil, "ghost", 1, true, 1 },
            { 1, true, 1, "fixed", 0, true, nil },
            { 2, true, 1, "ghost", 2, true, 2 },
            { 2, false, nil, "fixed", 0, true, nil },
        }
        for i, case in ipairs(cases) do
            local state = build(case[1], case[2], case[3])
            assert.equals(case[4], Rules.Proof(state), "case " .. i)
            assert.equals(case[5], state.count, "case " .. i)
            assert.equals(case[6], state.inStep, "case " .. i)
            assert.equals(case[7], state.ghost, "case " .. i)
        end
        -- Kept state: the same mismatch twice in a row is corrected.
        local state = build(1, true, nil)
        assert.equals("ghost", Rules.Proof(state))
        assert.equals("fixed", Rules.Proof(state))
        assert.equals(0, state.count)
    end)
end)
