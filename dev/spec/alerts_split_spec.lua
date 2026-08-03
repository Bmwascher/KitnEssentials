-- Modules/Skinning/Frames/Alerts.lua -- the Alerts / LootToast key split.
--
-- The split exists so EllesmereUI's `loottoast` overlap can be suppressed
-- without un-skinning nineteen popups it never touches. That payload lives
-- entirely in WHICH KEY each pass registers under, and the suppression
-- resolver never sees a registration -- so this is the only file that can
-- catch a mis-keyed one.

local L = require("dev.spec._ke_loader")

describe("Alerts skin registration", function()
    local calls

    before_each(function() calls = L.loadAlertsSkin() end)

    it("registers exactly two passes, one per key", function()
        assert.equal(2, #calls)
        local keys = {}
        for _, c in ipairs(calls) do keys[c.key] = (keys[c.key] or 0) + 1 end
        assert.equal(1, keys.Alerts)
        assert.equal(1, keys.LootToast)
    end)

    it("gives each key a DIFFERENT function", function()
        -- One function registered twice would make the two toggles
        -- indistinguishable at runtime while this file's first test passed.
        assert.are_not.equal(calls[1].fn, calls[2].fn)
    end)
end)
