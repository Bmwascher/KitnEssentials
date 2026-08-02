local loader = require("dev.spec._ke_loader")

describe("Modules/QoL/AlertFrames.lua", function()

    describe("ShouldGrowUp", function()
        local shouldGrowUp

        before_each(function()
            local _, _, seams = loader.loadAlertFrames()
            shouldGrowUp = seams.shouldGrowUp
        end)

        it("grows up when the centre is below half the screen height and there is no perks anchor", function()
            assert.is_true(shouldGrowUp(100, 1000, false))
        end)

        it("grows down when the centre is above half the screen height and there is no perks anchor", function()
            assert.is_false(shouldGrowUp(900, 1000, false))
        end)

        it("always grows up when the Trading Post has re-based the stack, even above half screen", function()
            assert.is_true(shouldGrowUp(900, 1000, true))
        end)

        it("fails safe to grow down when the centre is nil and there is no perks anchor", function()
            assert.is_false(shouldGrowUp(nil, 1000, false))
        end)
    end)
end)
