-- Auto Ready When Benched: the accept rule. It answers a raid ready check on
-- the player's behalf, so every refusal is a row. Pure predicate: no frames,
-- no events, no roster.

local L = require("dev.spec._ke_loader")

describe("Raid Notifications auto-ready rule", function()
    local RN

    before_each(function()
        RN = L.loadRaidNotifications()
    end)

    -- Every row starts from an accepted state and changes what it names.
    -- NONE rather than nil for "override this to nil": a nil stored in the
    -- override table is indistinguishable from an absent key.
    local BASE = { enabled = true, inRaid = true, instanceType = "none",
                   subgroup = 7, status = "waiting", lockdown = false }
    local NONE = {}

    local function decide(over)
        local args = {}
        for k, v in pairs(BASE) do args[k] = v end
        for k, v in pairs(over) do
            if v == NONE then args[k] = nil else args[k] = v end
        end
        return RN.ShouldAutoReady(args.enabled, args.inRaid, args.instanceType,
            args.subgroup, args.status, args.lockdown)
    end

    it("accepts for a benched raider outside any instance and refuses every other state", function()
        local cases = {
            { name = "group 7, open world",       over = {},                                      want = true },
            { name = "group 8, open world",       over = { subgroup = 8 },                        want = true },
            { name = "toggle off",                over = { enabled = false },                     want = false },
            { name = "not in a raid group",       over = { inRaid = false },                      want = false },
            { name = "inside a raid instance",    over = { instanceType = "raid" },               want = false },
            { name = "inside a dungeon",          over = { instanceType = "party" },              want = false },
            { name = "inside a battleground",     over = { instanceType = "pvp" },                want = false },
            { name = "no instance type",          over = { instanceType = NONE },                 want = false },
            { name = "an active subgroup",        over = { subgroup = 1 },                        want = false },
            { name = "group 6",                   over = { subgroup = 6 },                        want = false },
            { name = "not found, or secret",      over = { subgroup = NONE },                     want = false },
            { name = "already answered Ready",    over = { status = "ready" },                    want = false },
            { name = "answered Not Ready",        over = { status = "notready" },                 want = false },
            { name = "no status, or secret",      over = { status = NONE },                       want = false },
            { name = "in combat lockdown",        over = { lockdown = true },                     want = false },
        }
        for _, case in ipairs(cases) do
            assert.equals(case.want, decide(case.over), case.name)
        end
    end)
end)
