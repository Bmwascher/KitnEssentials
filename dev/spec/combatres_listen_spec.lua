-- When the battle res count listens for charge updates. The zone, combat,
-- encounter and shown reads that feed it are WoW state and stay an in-game check.
local L = require("dev.spec._ke_loader")

describe("CombatRes listening", function()
    it("listens while shown, in combat, inside an instance or in an encounter", function()
        local CR = L.loadCombatRes()
        local cases = {
            { name = "count shown", args = { true, false, false, false }, want = true },
            { name = "in combat", args = { false, true, false, false }, want = true },
            { name = "in an instance", args = { false, false, true, false }, want = true },
            { name = "in an encounter", args = { false, false, false, true }, want = true },
            { name = "none", args = { false, false, false, false }, want = false },
        }
        for _, c in ipairs(cases) do
            local a = c.args
            assert.are.equal(c.want, CR.ShouldListen(a[1], a[2], a[3], a[4]), c.name)
        end
    end)
end)
