-- Tier 1: FM.AnnounceAllowed is a pure predicate over the values the
-- ready-check handler reads, so nothing about the client is faked beyond what
-- the file needs to load.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("FocusMarker ready-check announce gate", function()
    local FM
    local KICKING_SPEC = 71  -- Arms Warrior
    local NO_KICK_SPEC = 257 -- Holy Priest

    before_each(function()
        mock.install()
        local modules = helpers.installAddonShim()
        helpers.loadModule("Modules/Dungeons/FocusMarker.lua", { Print = function() end })
        FM = modules["FocusMarker"]
    end)

    -- args: specID, inGroup, inRaid, inCombat, chatLocked
    it("refuses when any one condition blocks", function()
        local rows = {
            { name = "no-kick spec", args = { NO_KICK_SPEC, true, false, false, false } },
            { name = "no group", args = { KICKING_SPEC, false, false, false, false } },
            { name = "raid", args = { KICKING_SPEC, true, true, false, false } },
            { name = "combat", args = { KICKING_SPEC, true, false, true, false } },
            { name = "chat locked", args = { KICKING_SPEC, true, false, false, true } },
        }
        for _, row in ipairs(rows) do
            assert.is_false(FM.AnnounceAllowed(unpack(row.args)), row.name)
        end
    end)

    it("allows when nothing blocks", function()
        local rows = {
            { name = "a kicking spec", specID = KICKING_SPEC },
            { name = "an unread spec", specID = nil },
        }
        for _, row in ipairs(rows) do
            assert.is_true(FM.AnnounceAllowed(row.specID, true, false, false, false), row.name)
        end
    end)
end)
