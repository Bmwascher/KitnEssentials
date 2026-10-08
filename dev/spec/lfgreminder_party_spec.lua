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

    it("opens in a home party outside instances, or in a party dungeon with no key running and chat unlocked", function()
        local function scope(over)
            local s = { on = true, homeParty = true, inRaid = false, inInstance = false,
                        instanceType = "none", keyRunning = false, chatLocked = false }
            for k, v in pairs(over) do s[k] = v end
            return LR._PartyScopeOpen(s)
        end
        local cases = {
            { name = "open world",          over = {},                    want = true },
            { name = "off",                 over = { on = false },        want = false },
            { name = "not in a home party", over = { homeParty = false }, want = false },
            { name = "raid",                over = { inRaid = true },     want = false },
            -- Normal, heroic, mythic 0 and a finished key all read this way.
            { name = "party dungeon, no key running, unlocked", over = { inInstance = true, instanceType = "party" }, want = true },
            { name = "running key",         over = { inInstance = true, instanceType = "party", keyRunning = true }, want = false },
            { name = "party dungeon, chat locked", over = { inInstance = true, instanceType = "party", chatLocked = true }, want = false },
            { name = "raid instance",       over = { inInstance = true, instanceType = "raid" }, want = false },
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

describe("LFGReminder party prompt", function()
    local LR
    before_each(function()
        LR = loader.loadLFGReminder()
    end)

    it("reads the spell ID from a teleport message and nothing else", function()
        local cases = {
            { name = "valid, spaced realm", text = "BV1_Bitesp-Area 52\0301286809", want = 1286809 },
            { name = "other version",       text = "BV2_Bitesp-Area 52\0301286809", want = nil },
            { name = "no separator",        text = "BV1_Bitesp-Area 521286809",     want = nil },
            { name = "non-numeric id",      text = "BV1_Bitesp-Area 52\030abc",     want = nil },
            { name = "not a string",        text = 42,                              want = nil },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, LR._ParsePortalMessage(c.text), c.name)
        end
    end)

    it("holds a dungeon until its hold is released, one dungeon at a time", function()
        LR._HoldThrottle(587)
        assert.is_true(LR._ThrottleHeld(587))
        assert.is_false(LR._ThrottleHeld(399))
        LR._ReleaseThrottle(587)
        assert.is_false(LR._ThrottleHeld(587))
    end)

    it("refuses a party prompt for each failed gate, and lets the rest through", function()
        local function gate(over)
            local s = { scopeOpen = true, unit = "party1", mapID = 587, throttled = false, lfgLive = false }
            for k, v in pairs(over) do s[k] = v end
            return LR._PartyPromptRefusal(s)
        end
        local cases = {
            { name = "all clear",                over = {},                    want = nil },
            { name = "scope closed",             over = { scopeOpen = false }, want = "scope" },
            { name = "sender not in party",      over = { unit = false },      want = "not in party" },
            { name = "not a teleport",           over = { mapID = false },     want = "not a portal" },
            { name = "dungeon held",             over = { throttled = true },  want = "throttled" },
            { name = "Group Finder prompt live", over = { lfgLive = true },    want = "group finder" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, gate(c.over), c.name)
        end
    end)
end)
