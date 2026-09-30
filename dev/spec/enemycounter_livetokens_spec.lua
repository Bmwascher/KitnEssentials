-- The live nameplate set behind the enemy count: what enters it, what leaves
-- it, and that a recount visits only its members. The unit tests the recount
-- applies are WoW calls and stay an in-game check.
local L = require("dev.spec._ke_loader")

describe("EnemyCounter live tokens", function()
    it("recounts only tokens 1-40 that were added and not removed", function()
        local EC = L.loadEnemyCounter()
        local cases = {
            { name = "added in range",
              ops = { { "nameplate3", true } }, visited = { "nameplate3" } },
            { name = "added then removed",
              ops = { { "nameplate3", true }, { "nameplate3", false } }, visited = {} },
            { name = "added above the counted range",
              ops = { { "nameplate41", true } }, visited = {} },
        }
        for _, c in ipairs(cases) do
            local set = {}
            for _, op in ipairs(c.ops) do
                EC.TrackToken(set, op[1], op[2])
            end
            local visited = {}
            local count = EC.CountLive(set, function(unit)
                visited[#visited + 1] = unit
                return true
            end)
            table.sort(visited)
            assert.are.same(c.visited, visited, c.name)
            assert.are.equal(#c.visited, count, c.name)
        end
    end)
end)
