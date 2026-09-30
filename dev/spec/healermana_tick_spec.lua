-- When the one-second mana tick runs. The timer itself is AceTimer and stays
-- an in-game check.
local L = require("dev.spec._ke_loader")

describe("HealerMana tick", function()
    it("runs only for an enabled module with a preview or listed rows", function()
        local HM = L.loadHealerMana()
        local cases = {
            { name = "disabled", enabled = false, isPreview = true, count = 3, want = false },
            { name = "preview up", enabled = true, isPreview = true, count = 0, want = true },
            { name = "rows listed", enabled = true, isPreview = false, count = 2, want = true },
            { name = "nothing drawn", enabled = true, isPreview = false, count = 0, want = false },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c.want, HM.ShouldTick(c.enabled, c.isPreview, c.count), c.name)
        end
    end)
end)
