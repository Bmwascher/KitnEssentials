local L = require("dev.spec._ke_loader")

describe("preview swap decisions", function()
    -- Entering preview leaves the ANCHOR shown so the mover and the position
    -- stay live; only the container goes away.
    it("disables and hides the container but keeps the anchor shown", function()
        local P = L.loadAuraPreview()
        local plan = P.PlanEnter()
        assert.is_false(plan.containerShown)
        assert.is_false(plan.containerEnabled)
        assert.is_true(plan.anchorShown)
    end)

    it("restores the container to the module state on exit when unrestricted", function()
        local P = L.loadAuraPreview()
        local plan = P.PlanExit({ isHidden = false, state = true })
        assert.is_true(plan.containerShown)
        assert.is_true(plan.containerEnabled)
        assert.is_false(plan.pendGeneral)
    end)

    it("restores to a DISABLED module state rather than blindly showing", function()
        local P = L.loadAuraPreview()
        local plan = P.PlanExit({ isHidden = false, state = false })
        assert.is_false(plan.containerShown)
    end)

    it("hides the anchor too when unrestricted and the module is disabled", function()
        local P = L.loadAuraPreview()
        local plan = P.PlanExit({ isHidden = false, state = false })
        assert.is_false(plan.anchorShown)
    end)

    -- Reachable: a keystone, out of combat, with the config open.
    it("restores the container on exit even while restricted", function()
        local P = L.loadAuraPreview()
        local plan = P.PlanExit({ isHidden = true, state = true })
        assert.is_true(plan.containerShown)
        assert.is_true(plan.containerEnabled)
        assert.is_true(plan.anchorShown)
    end)

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
