local L = require("dev.spec._ke_loader")

describe("AuraHeaders stand-down", function()
    it("stands down only when the helper says ElvUI owns the frames: absent, off, or missing helper all run", function()
        for _, case in ipairs({
            { overrides = { shouldNotLoad = false }, standsDown = false },
            { overrides = { shouldNotLoad = true },  standsDown = true },
            { overrides = { noHelper = true },       standsDown = false },
        }) do
            local M = L.loadAuraHeaders(case.overrides)
            assert.equal(case.standsDown, M:ShouldStandDown())
        end
    end)
end)
