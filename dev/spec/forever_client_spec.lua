-- Tier 1: the client decision in Core/Client.lua. The interface version alone
-- decides; each row with a number interface sets a project ID that disagrees
-- with it.
local helpers = require("dev.spec._helpers")

describe("Core/Client.lua", function()
    after_each(function()
        _G.GetBuildInfo = nil
        _G.WOW_PROJECT_ID = nil
    end)

    local function build(interface)
        return function() return "version", "build", "date", interface end
    end

    -- An interface that cannot be read is not Forever: nothing Forever-only
    -- starts on a guess.
    it("names Forever only from a readable interface in its range", function()
        for _, row in ipairs({
            { name = "Forever on project 1",  getBuildInfo = build(16001),   project = 1,  forever = true },
            { name = "Forever lower bound",   getBuildInfo = build(16000),   project = 1,  forever = true },
            { name = "retail on project 18",  getBuildInfo = build(120105),  project = 18, forever = false },
            { name = "just below Forever",    getBuildInfo = build(15999),   project = 18, forever = false },
            { name = "Forever upper bound",   getBuildInfo = build(20000),   project = 18, forever = false },
            { name = "interface as text",     getBuildInfo = build("16001"), project = 18, forever = false },
            { name = "no interface value",    getBuildInfo = build(nil),     project = 1,  forever = false },
            { name = "no GetBuildInfo",       getBuildInfo = nil,            project = 1,  forever = false },
        }) do
            _G.GetBuildInfo = row.getBuildInfo
            _G.WOW_PROJECT_ID = row.project
            local KE = helpers.loadModule("Core/Client.lua", {})
            assert.equals(row.forever, KE.IS_FOREVER, row.name)
        end
    end)
end)
