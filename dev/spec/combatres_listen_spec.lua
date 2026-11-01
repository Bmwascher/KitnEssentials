-- When the battle res count listens for charge updates. The zone, combat,
-- encounter and shown reads that feed it are WoW state and stay an in-game check.
local L = require("dev.spec._ke_loader")

describe("CombatRes listening", function()
    it("listens while shown, in combat, inside an instance or in an encounter", function()
        local CR = L.loadCombatRes()
        local cases = {
            { name = "count shown", args = { true, false, false, false }, want = true },
            { name = "in combat", args = { false, true, false, false }, want = true },
            { name = "in an instance", args = { false, false, true, false }, want = true },
            { name = "in an encounter", args = { false, false, false, true }, want = true },
            { name = "none", args = { false, false, false, false }, want = false },
        }
        for _, c in ipairs(cases) do
            local a = c.args
            assert.are.equal(c.want, CR.ShouldListen(a[1], a[2], a[3], a[4]), c.name)
        end
    end)
end)

-- Forever: the player's own res. The reads are stubs, so the spell, item
-- and secret behavior of the client stay an in-game check.
describe("CombatRes own res on Forever", function()
    it("shows ready, the time left or nothing from the class's own res", function()
        local CR = L.loadCombatRes()
        local SPELL, ITEMS, SECRET = { spell = 1 }, { items = { 10, 11 } }, {}
        local function reads(r)
            return {
                spell = r.spell,
                spellCooldown = function() return r.spellRem, nil, r.secret end,
                holdsAny = function() return r.held == true end,
                itemCooldown = function() return r.itemRem end,
            }
        end
        for _, c in ipairs({
            { name = "no entry hides", reads = {} },
            { name = "a spell entry with no resolved spell hides", entry = SPELL, reads = { spellRem = 30 } },
            { name = "a cooling spell gives its time", entry = SPELL, reads = { spell = 2, spellRem = 30 }, want = "cooldown", rem = 30, secret = false },
            { name = "a secret cooldown keeps its flag", entry = SPELL, reads = { spell = 2, spellRem = SECRET, secret = true }, want = "cooldown", rem = SECRET, secret = true },
            { name = "a ready spell", entry = SPELL, reads = { spell = 2 }, want = "ready" },
            { name = "a stone held and cooling", entry = ITEMS, reads = { held = true, itemRem = 60 }, want = "cooldown", rem = 60, secret = false },
            { name = "no stone and a cooldown", entry = ITEMS, reads = { itemRem = 60 }, want = "cooldown", rem = 60, secret = false },
            { name = "a stone and no cooldown", entry = ITEMS, reads = { held = true }, want = "ready" },
            { name = "neither hides", entry = ITEMS, reads = {} },
            { name = "an unreadable item cooldown", entry = ITEMS, reads = { held = true, itemRem = false }, want = "unknown" },
        }) do
            local state, rem, secret = CR.OwnResState(c.entry, reads(c.reads))
            assert.equals(c.want, state, c.name)
            assert.equals(c.rem, rem, c.name)
            assert.equals(c.secret, secret, c.name)
        end
    end)

    it("previews for any class, and reads nothing while off or with no res", function()
        local CR = L.loadCombatRes()
        local ENTRY = { spell = 1 }
        for _, c in ipairs({
            { name = "a preview, off, no res", preview = true, on = false, want = "preview" },
            { name = "a preview, on, with a res", preview = true, on = true, entry = ENTRY, want = "preview" },
            { name = "off with a res refuses", on = false, entry = ENTRY },
            { name = "on with no res refuses", on = true },
            { name = "on with a res is live", on = true, entry = ENTRY, want = "live" },
        }) do
            assert.equals(c.want, CR.OwnResDisplay(c.preview == true, c.on, c.entry), c.name)
        end
    end)
end)

