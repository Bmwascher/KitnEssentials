-- The one switch deciding whether KeystoneHelper holds anything: its hook and
-- events exist only while one of the three features is on, and a client that
-- withholds the reminders counts their switches as off, so an imported one
-- cannot start a reminder. The registration itself is an in-game check.
local L = require("dev.spec._ke_loader")

describe("KeystoneHelper any-feature-on gate", function()
    it("holds with any one feature on, and not with none, no settings or only withheld reminders", function()
        local KH = L.loadKeystoneHelper()
        local cases = {
            { name = "all off", on = false,
              db = { ResetEnabled = false, RerollEnabled = false, YourKeyEnabled = false } },
            { name = "reset only", on = true, db = { ResetEnabled = true } },
            { name = "reroll only", on = true, db = { RerollEnabled = true } },
            { name = "your key only", on = true, db = { YourKeyEnabled = true } },
            { name = "no settings", on = false },
            { name = "reroll only, reminders withheld", on = false,
              db = { RerollEnabled = true }, withheld = true },
            { name = "your key only, reminders withheld", on = false,
              db = { YourKeyEnabled = true }, withheld = true },
            { name = "reset and reroll, reminders withheld", on = true,
              db = { ResetEnabled = true, RerollEnabled = true }, withheld = true },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c.on, KH.AnyFeatureOn(c.db, c.withheld), c.name)
        end
    end)
end)
