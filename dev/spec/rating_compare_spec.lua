-- Which of four ratings wins, on the plain path and through the alpha fold.
-- The hidden-bar compare and secret alphas are an in-game check.
local L = require("dev.spec._ke_loader")

local function plainEval(b, ifTrue, ifFalse)
    if b then return ifTrue end
    return ifFalse
end

local ROWS = {
    { name = "crit highest", values = { 9, 1, 2, 3 }, want = 1 },
    { name = "haste highest", values = { 1, 9, 2, 3 }, want = 2 },
    { name = "mastery highest", values = { 1, 2, 9, 3 }, want = 3 },
    { name = "vers highest", values = { 1, 2, 3, 9 }, want = 4 },
    { name = "haste and vers tie", values = { 1, 7, 2, 7 }, want = 2 },
    { name = "four-way tie", values = { 5, 5, 5, 5 }, want = 1 },
}

describe("Rating compare", function()
    it("picks the highest plain rating, a tie going to the earlier stat", function()
        local RC = L.loadRatingCompare()
        for _, c in ipairs(ROWS) do
            assert.are.equal(c.want, RC.PlainPick(c.values), c.name)
        end
        assert.is_nil(RC.PlainPick({ 1, nil, 2, 3 }), "a missing rating")
    end)

    it("folds the six pair answers into alpha 1 for the plain winner only", function()
        local RC = L.loadRatingCompare()
        for _, c in ipairs(ROWS) do
            local ge = {}
            for p, pair in ipairs(RC.PAIRS) do
                ge[p] = c.values[pair[1]] >= c.values[pair[2]]
            end
            local alphas = RC.FoldAlphas(ge, plainEval, {})
            for i = 1, 4 do
                assert.are.equal(i == c.want and 1 or 0, alphas[i], c.name .. ", stat " .. i)
            end
        end
    end)
end)
