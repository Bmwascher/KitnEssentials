-- Modules/Combat/ClassTools/DivineArbiter.lua -- the class and spec gate and the
-- one-display lifecycle. The container, layout and timing are smoke.
local L = require("dev.spec._ke_loader")

local RETRIBUTION, HOLY, PROTECTION = 70, 65, 66

describe("DivineArbiter gate", function()
    local DA

    before_each(function()
        DA = L.loadDivineArbiter()
    end)

    it("wants only a Retribution Paladin", function()
        local cases = {
            -- Spec 70 on another class: a pass here would mean the spec check
            -- stood in for the class check.
            { name = "mage reporting spec 70", class = "MAGE",    spec = RETRIBUTION, expected = false },
            { name = "holy paladin",           class = "PALADIN", spec = HOLY,        expected = false },
            { name = "protection paladin",     class = "PALADIN", spec = PROTECTION,  expected = false },
            { name = "paladin with no spec",   class = "PALADIN", spec = nil,         expected = false },
            { name = "retribution paladin",    class = "PALADIN", spec = RETRIBUTION, expected = true },
        }
        for _, case in ipairs(cases) do
            assert.equals(case.expected, DA.WantsSpec(case.class, case.spec), case.name)
        end
    end)

    it("registers once, then suspends and resumes the same display", function()
        local cases = {
            { name = "first retribution", wanted = true, hasDisplay = false, active = false, expected = "register" },
            { name = "back on retribution", wanted = true, hasDisplay = true, active = false, expected = "resume" },
            { name = "left retribution", wanted = false, hasDisplay = true, active = true, expected = "suspend" },
            { name = "still retribution", wanted = true, hasDisplay = true, active = true, expected = nil },
            { name = "never retribution", wanted = false, hasDisplay = false, active = false, expected = nil },
            { name = "still off retribution", wanted = false, hasDisplay = true, active = false, expected = nil },
        }
        for _, case in ipairs(cases) do
            assert.equals(case.expected, DA.PlanGate(case.wanted, case.hasDisplay, case.active), case.name)
        end
    end)

    -- Work the engine queued before a suspend reads settings after the events
    -- are gone; the view is what keeps it from re-showing the container.
    it("reads as off to the engine while suspended, passing other reads and writes through", function()
        DA.db = { Enabled = true, IconSize = 40 }
        DA.active = true
        assert.equals(DA.db, DA:EngineSettings(), "active reads the saved settings")

        DA.active = false
        local view = DA:EngineSettings()
        assert.is_false(view.Enabled)
        assert.equals(40, view.IconSize)
        view.Position = { XOffset = 5 }
        assert.equals(5, DA.db.Position.XOffset)
        assert.is_true(DA.db.Enabled)
    end)
end)
