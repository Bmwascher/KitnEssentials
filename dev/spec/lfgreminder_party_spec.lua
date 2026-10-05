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

describe("LFGReminder party scope and send gate", function()
    local LR
    before_each(function()
        LR = loader.loadLFGReminder()
    end)

    it("opens only in a home party outside instances, or in a finished key with chat unlocked", function()
        local function scope(over)
            local s = { on = true, homeParty = true, inRaid = false, inInstance = false,
                        instanceType = "none", keyCompleted = false, chatLocked = false }
            for k, v in pairs(over) do s[k] = v end
            return LR._PartyScopeOpen(s)
        end
        local cases = {
            { name = "open world",                  over = {},                    want = true },
            { name = "off",                         over = { on = false },        want = false },
            { name = "not in a home party",         over = { homeParty = false }, want = false },
            { name = "raid",                        over = { inRaid = true },     want = false },
            { name = "dungeon, key running",        over = { inInstance = true, instanceType = "party" }, want = false },
            { name = "finished key, unlocked",      over = { inInstance = true, instanceType = "party", keyCompleted = true }, want = true },
            { name = "finished key, chat locked",   over = { inInstance = true, instanceType = "party", keyCompleted = true, chatLocked = true }, want = false },
            { name = "raid instance with the flag", over = { inInstance = true, instanceType = "raid", keyCompleted = true }, want = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, scope(c.over), c.name)
        end
    end)

    it("refuses an own-cast send when the scope is closed or chat is locked", function()
        local cases = {
            { name = "all clear",    scope = true,  locked = false, want = nil },
            { name = "scope closed", scope = false, locked = false, want = "scope" },
            { name = "chat locked",  scope = true,  locked = true,  want = "locked" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, LR._SendRefusal(c.scope, c.locked), c.name)
        end
    end)
end)
