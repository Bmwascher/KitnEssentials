-- Specs for the Dungeon Timers BigWigs Messages summary: per-state counts,
-- the absent-provider precedence and Check now eligibility.
local loader = require("dev.spec._ke_loader")

describe("DungeonTimers provider summary", function()
    local DT_GUI

    before_each(function()
        DT_GUI = loader.loadDungeonTimersProviderSummary()
    end)

    it("counts alerts by state, skipping disabled or inapplicable ones and reading unknown through its reason", function()
        assert.same(
            { kind = "mixed", total = 4, on = 1, off = 1, notLoaded = 1, unreadable = 1, canCheck = true },
            DT_GUI.SummarizeProviderSetup({
                { status = "satisfied" },
                { status = "missing" },
                { status = "unknown", reason = "not-loaded" },
                { status = "unknown" },
                { status = "disabled" },
                { status = "not-applicable" },
            }))
        local kinds = {
            { states = { { status = "satisfied" }, { status = "disabled" } }, kind = "all-on" },
            { states = { { status = "disabled" } }, kind = "none" },
            { states = { { status = "not-applicable" } }, kind = "none" },
            { states = {}, kind = "none" },
        }
        for _, c in ipairs(kinds) do
            assert.equal(c.kind, DT_GUI.SummarizeProviderSetup(c.states).kind)
        end
    end)

    it("reports an absent provider ahead of every other state", function()
        local summary = DT_GUI.SummarizeProviderSetup({
            { status = "satisfied" },
            { status = "unknown", reason = "no-provider" },
            { status = "missing" },
        })
        assert.equal("no-provider", summary.kind)
    end)

    it("enables Check now only for an alert that is not loaded or unreadable", function()
        local cases = {
            { name = "not loaded", states = { { status = "unknown", reason = "not-loaded" } }, expected = true },
            { name = "unreadable", states = { { status = "unknown", reason = "unreadable" } }, expected = true },
            { name = "unknown without a reason", states = { { status = "unknown" } }, expected = true },
            { name = "on and off", states = { { status = "satisfied" }, { status = "missing" } }, expected = false },
            { name = "absent provider", states = { { status = "unknown", reason = "no-provider" } }, expected = false },
            { name = "disabled", states = { { status = "disabled" } }, expected = false },
        }
        for _, c in ipairs(cases) do
            assert.equal(c.expected, DT_GUI.SummarizeProviderSetup(c.states).canCheck, c.name)
        end
    end)
end)
