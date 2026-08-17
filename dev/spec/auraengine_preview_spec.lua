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

    -- Reachable: a keystone, out of combat, with the config open.
    it("pends the restore instead of applying it when restricted", function()
        local P = L.loadAuraPreview()
        local plan = P.PlanExit({ isHidden = true, state = true })
        assert.is_true(plan.pendGeneral)
        assert.is_false(plan.containerShown)
    end)

    -- The user must never be left with nothing on screen where they were
    -- positioning something.
    it("restores the anchor immediately even when the container waits", function()
        local P = L.loadAuraPreview()
        local plan = P.PlanExit({ isHidden = true, state = true })
        assert.is_true(plan.anchorShown)
    end)

end)
