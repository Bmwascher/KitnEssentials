local L = require("dev.spec._ke_loader")

describe("AuraHeaders stand-down", function()
    it("runs when ElvUI is absent", function()
        local M = L.loadAuraHeaders({ shouldNotLoad = false })
        assert.is_false(M:ShouldStandDown())
    end)

    it("stands down when ElvUI is loaded and the hand-off is on", function()
        local M = L.loadAuraHeaders({ shouldNotLoad = true })
        assert.is_true(M:ShouldStandDown())
    end)

    it("runs when the helper is missing entirely", function()
        local M = L.loadAuraHeaders({ noHelper = true })
        assert.is_false(M:ShouldStandDown())
    end)
end)
