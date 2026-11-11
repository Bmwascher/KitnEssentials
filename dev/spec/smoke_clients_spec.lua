-- dev/spec/smoke_clients_spec.lua
local S = dofile("dev/scripts/_smoke_clients.lua")

describe("smoke client report (dev/scripts/_smoke_clients.lua)", function()
    local retail = { ["Core/Shared.lua"] = true, ["Modules/RetailOnly.lua"] = true }
    local forever = { ["Core/Shared.lua"] = true, ["Modules/ForeverOnly.lua"] = true }

    it("classifies a path by the load lists, then by whether it ships", function()
        local cases = {
            { "Core/Shared.lua", "both" },
            { "Modules/RetailOnly.lua", "retail" },
            { "Modules/ForeverOnly.lua", "forever" },
            { "dev/scripts/tool.lua", "none" },
            { ".luacheckrc", "none" },
            { "CHANGELOG.md", "none" },
            { "Media/Fonts/New.ttf", "unlisted" },
            { "Modules/Deleted.lua", "unlisted" },
        }
        for _, case in ipairs(cases) do
            assert.equals(case[2], S.classify(case[1], retail, forever), case[1])
        end
    end)

    it("names the clients a set of classes needs", function()
        local cases = {
            { { "retail", "none" }, "Retail only" },
            { { "forever" }, "Forever only" },
            { { "retail", "forever" }, "Retail and Forever" },
            { { "none", "unlisted" }, "Retail and Forever" },
            { { "none" }, "neither client (no shipped file changed)" },
            { {}, "neither client (no shipped file changed)" },
        }
        for _, case in ipairs(cases) do
            assert.equals(case[2], S.summary(case[1]), table.concat(case[1], ","))
        end
    end)
end)
