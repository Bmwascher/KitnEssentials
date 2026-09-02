local L = require("dev.spec._ke_loader")

describe("preview swap decisions", function()
    it("still records the deferred reconfiguration when restricted", function()
        local P = L.loadAuraPreview()
        assert.is_true(P.PlanExit({ isHidden = true, state = true }).pendGeneral)
        assert.is_true(P.PlanExit({ isHidden = true, state = false }).pendGeneral)
    end)

    -- What the user sees on exit depends only on whether the module is on,
    -- never on the restriction.
    it("plans the same visible state restricted and unrestricted", function()
        local P = L.loadAuraPreview()
        for _, state in ipairs({ true, false }) do
            local free = P.PlanExit({ isHidden = false, state = state })
            local held = P.PlanExit({ isHidden = true,  state = state })
            assert.equal(free.containerShown, held.containerShown)
            assert.equal(free.containerEnabled, held.containerEnabled)
            assert.equal(free.anchorShown, held.anchorShown)
        end
    end)

end)
