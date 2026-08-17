local L = require("dev.spec._ke_loader")

-- First creation is PERMITTED while the game hides aura identities; only a
-- later reconfiguration defers. The restriction gate cannot carry that half of
-- the rule, and no gate spec can reach it: creation happens in ApplySettings
-- before the gate is ever consulted.
describe("first container creation under restriction", function()
    it("creates the container even while identities are hidden", function()
        local E, KE, display = L.loadAuraEngine()
        KE.AreAuraIdentitiesHidden = function() return true end

        E.ApplySettings(display)

        assert.equals(1, KE.AuraContainer.creates)
        assert.is_not_nil(display.handle)
    end)

    it("defers a SECOND apply while identities are still hidden", function()
        local E, KE, display = L.loadAuraEngine()
        KE.AreAuraIdentitiesHidden = function() return true end

        E.ApplySettings(display)
        E.ApplySettings(display)

        assert.equals(1, KE.AuraContainer.creates)
        assert.equals(0, KE.AuraContainer.reconfigures)
        assert.is_true(display.gate:IsPending("general"))
    end)

    -- The control for the case above. Without it, the deferral could pass for
    -- the wrong reason: a build that never reconfigured at all would satisfy
    -- it just as well.
    it("reconfigures on a second apply when nothing is hidden", function()
        local E, KE, display = L.loadAuraEngine()

        E.ApplySettings(display)
        E.ApplySettings(display)

        assert.equals(1, KE.AuraContainer.creates)
        assert.equals(1, KE.AuraContainer.reconfigures)
    end)
end)
