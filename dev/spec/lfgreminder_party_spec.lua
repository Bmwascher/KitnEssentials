-- Modules/Dungeons/LFGReminder.lua -- the party teleport path's pure pieces:
-- mapping a teleport to its dungeon and to the player's own teleport, the
-- scope and send gates, reading a teleport message, the once-a-minute hold
-- per dungeon, and the gate that decides whether a message prompts. The mock
-- declares nothing secret, so the secret refusals are verified in game. Event
-- wiring, the popup and the send itself are smoke.
local loader = require("dev.spec._ke_loader")

describe("LFGReminder teleport lookups", function()
    local LR
    before_each(function()
        LR = loader.loadLFGReminder()
    end)

    it("maps a teleport to its dungeon, preferring this season's map for a shared spell", function()
        local cases = {
            { name = "single map",             spell = 1286809, season = nil,              want = 587 },
            { name = "shared, one in season",  spell = 1254551, season = { [583] = true }, want = 583 },
            { name = "shared, none in season", spell = 373262,  season = { [587] = true }, want = 227 },
            { name = "not a teleport",         spell = 8690,    season = nil,              want = nil },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, LR._MapForPortalSpell(c.spell, c.season), c.name)
        end
    end)

    it("picks the player's own teleport for a dungeon", function()
        local function knows(set) return function(id) return set[id] == true end end
        local cases = {
            { name = "faction pair, second known", map = 353,  known = { [464256] = true }, want = 464256 },
            { name = "none known: the first",      map = 353,  known = {},                  want = 445418 },
            { name = "unknown map",                map = 9999, known = {},                  want = nil },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, LR._PickOwnPortal(c.map, knows(c.known)), c.name)
        end
    end)
end)
