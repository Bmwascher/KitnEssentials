-- When Healer Mana can be the Raid Cooldowns stack's place. The stack itself
-- is frame anchoring and stays an in-game check.
local L = require("dev.spec._ke_loader")

describe("HealerMana stack", function()
    it("joins only while on, in Party mode and not previewing Raid", function()
        local HM = L.loadHealerMana()
        local cases = {
            { name = "Party mode", on = true, mode = "DUNGEON", want = true },
            { name = "Party preview", on = true, mode = "DUNGEON", preview = "DUNGEON", want = true },
            { name = "off", on = false, mode = "DUNGEON", want = false },
            { name = "unread", mode = "DUNGEON", want = false },
            { name = "Raid mode", on = true, mode = "RAID", want = false },
            { name = "Raid preview", on = true, mode = "DUNGEON", preview = "RAID", want = false },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c.want, HM.JoinsStack(c.on, c.mode, c.preview), c.name)
        end
    end)
end)
