-- Modules/Utilities/TimeSpiral.lua -- when the proc sound plays. One proc can
-- fire its glow event several times in one window, one per movement spell, so
-- the window rule is what keeps the sound to one per proc: an edit that drops
-- it plays the sound up to three times. Sound output, LSM and the event
-- wiring are smoke.
local L = require("dev.spec._ke_loader")

describe("TimeSpiral proc sound rule", function()
    local shouldPlay

    before_each(function()
        local TSP = L.loadTimeSpiral()
        shouldPlay = TSP.ShouldPlaySound
    end)

    it("plays when enabled with a named sound and no window open", function()
        assert.is_true(shouldPlay({ SoundEnabled = true, SoundName = "Move" }, false))
    end)

    it("stays silent on a repeat SHOW inside an open window", function()
        assert.is_false(shouldPlay({ SoundEnabled = true, SoundName = "Move" }, true))
    end)

    it("stays silent when the sound is off or none is picked", function()
        local cases = {
            { name = "off",         db = { SoundEnabled = false, SoundName = "Move" } },
            { name = "None picked", db = { SoundEnabled = true,  SoundName = "None" } },
            { name = "nothing set", db = { SoundEnabled = true } },
        }
        for _, case in ipairs(cases) do
            assert.is_false(shouldPlay(case.db, false), case.name)
        end
    end)
end)
