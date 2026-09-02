local L = require("dev.spec._ke_loader")

describe("preview swap decisions", function()
    it("still records the deferred reconfiguration when restricted", function()
        local P = L.loadAuraPreview()
        assert.is_true(P.PlanExit({ isHidden = true, state = true }).pendGeneral)
        assert.is_true(P.PlanExit({ isHidden = true, state = false }).pendGeneral)
    end)

    -- What the user sees on exit is the module state, and only that: never
    -- the restriction.
    it("plans the module state as the visible state, restricted or not", function()
        local P = L.loadAuraPreview()
        for _, state in ipairs({ true, false }) do
            local free = P.PlanExit({ isHidden = false, state = state })
            local held = P.PlanExit({ isHidden = true,  state = state })
            assert.equal(state, free.containerShown)
            assert.equal(state, free.containerEnabled)
            assert.equal(state, free.anchorShown)
            assert.equal(free.containerShown, held.containerShown)
            assert.equal(free.containerEnabled, held.containerEnabled)
            assert.equal(free.anchorShown, held.anchorShown)
        end
    end)

end)
