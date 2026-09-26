-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_meter_resets_spec.lua                       ║
-- ║  Damage Meter reset rules: instance entry, the Ask token.║
-- ╚══════════════════════════════════════════════════════════╝
--
-- WHY THIS EARNS A SPEC: both are rules KE decides for itself, and a wrong
-- answer wipes the player's meter data, or fails to, with no error. Both
-- functions are pure over plain values, so no Blizzard fake is needed.
local L = require("dev.spec._ke_loader")

local DM

before_each(function()
    DM = L.loadDMCore({})
    assert(DM and DM.InstanceEntryDecision, "loadDMCore did not expose DM.InstanceEntryDecision")
end)

describe("InstanceEntryDecision", function()
    it("resets or asks only on entering a different instance or difficulty", function()
        -- Each row is one loading screen or Delve event: the last entry recorded,
        -- then the current scope, instance and difficulty. A nil scope is the
        -- open world. Keys are "instanceID:difficultyID".
        -- want = { new key, new scope, action, moved }. "moved" ends any Ask
        -- prompt raised at the last entry.
        local cases = {
            { name = "a different instance, Auto", last = "100:1", lastScope = "party",
              scope = "party", id = 200, diff = 1, enabled = true, mode = "auto", want = { "200:1", "party", "auto", true } },
            { name = "a different instance, Ask", last = "100:1", lastScope = "party",
              scope = "raid", id = 200, diff = 14, enabled = true, mode = "ask", want = { "200:14", "raid", "ask", true } },
            { name = "the same map at a different difficulty", last = "200:1", lastScope = "party",
              scope = "party", id = 200, diff = 8, enabled = true, mode = "auto", want = { "200:8", "party", "auto", true } },
            { name = "an unknown mode asks", scope = "scenario", id = 300, diff = 1,
              enabled = true, mode = "bogus", want = { "300:1", "scenario", "ask", true } },
            { name = "the open world keeps the last key", last = "200:8", lastScope = "party",
              id = 2552, diff = 0, enabled = true, mode = "auto", want = { "200:8", "party", "none", true } },
            { name = "running back in after a death", last = "200:8", lastScope = "party",
              scope = "party", id = 200, diff = 8, enabled = true, mode = "auto", want = { "200:8", "party", "none", false } },
            { name = "an unreadable difficulty is not an entry", last = "200:8", lastScope = "party",
              scope = "party", id = 300, enabled = true, mode = "auto", want = { "200:8", "party", "none", false } },
            { name = "a running Delve's repeat event", last = "400:2", lastScope = "delve",
              scope = "delve", id = 400, diff = 2, enabled = true, mode = "auto", want = { "400:2", "delve", "none", false } },
            { name = "a Delve ending in place", last = "400:2", lastScope = "delve",
              scope = "scenario", id = 400, diff = 2, enabled = true, mode = "auto", want = { "400:2", "delveover", "none", true } },
            { name = "a repeat event after that end", last = "400:2", lastScope = "delveover",
              scope = "scenario", id = 400, diff = 2, enabled = true, mode = "auto", want = { "400:2", "delveover", "none", false } },
            { name = "a new Delve in that place", last = "400:2", lastScope = "delveover",
              scope = "delve", id = 400, diff = 2, enabled = true, mode = "auto", want = { "400:2", "delve", "auto", true } },
            { name = "leaving a running Delve forgets it", last = "400:2", lastScope = "delve",
              id = 2552, diff = 0, enabled = true, mode = "auto", want = { nil, nil, "none", true } },
            { name = "leaving a finished Delve forgets it", last = "400:2", lastScope = "delveover",
              id = 2552, diff = 0, enabled = true, mode = "auto", want = { nil, nil, "none", true } },
            { name = "the next Delve after a forgotten one", scope = "delve", id = 400, diff = 2,
              enabled = true, mode = "auto", want = { "400:2", "delve", "auto", true } },
            { name = "a login or /reload only records", scope = "party", id = 200, diff = 8,
              fresh = true, enabled = true, mode = "auto", want = { "200:8", "party", "none", true } },
            { name = "option off still tracks", last = "100:1", lastScope = "party",
              scope = "party", id = 200, diff = 8, enabled = false, mode = "auto", want = { "200:8", "party", "none", true } },
            { name = "a load whose difficulty is withheld keeps the last key and scope", last = "200:23", lastScope = "party",
              scope = "raid", id = 300, enabled = true, mode = "auto", want = { "200:23", "party", "none", false } },
            { name = "a keystone slotted, seen at a load", last = "200:23", lastScope = "party",
              scope = "party", id = 200, diff = 8, enabled = true, mode = "auto", want = { "200:8", "party", "none", true } },
            { name = "a keystone ended, seen at a load", last = "200:8", lastScope = "party",
              scope = "party", id = 200, diff = 23, enabled = true, mode = "auto", want = { "200:23", "party", "none", true } },
            { name = "a keystone slotted in place only records", last = "200:23", lastScope = "party",
              scope = "party", id = 200, diff = 8, fresh = true, enabled = true, mode = "auto", want = { "200:8", "party", "none", true } },
            { name = "a keystone ended in place only records", last = "200:8", lastScope = "party",
              scope = "party", id = 200, diff = 23, fresh = true, enabled = true, mode = "auto", want = { "200:23", "party", "none", true } },
            { name = "Mythic to Mythic Keystone in another instance is an entry", last = "200:23", lastScope = "party",
              scope = "party", id = 300, diff = 8, enabled = true, mode = "auto", want = { "300:8", "party", "auto", true } },
        }
        for _, c in ipairs(cases) do
            local key, scope, action, moved = DM.InstanceEntryDecision(c.last, c.lastScope, c.scope, c.id, c.diff,
                c.fresh == true, c.enabled, c.mode)
            assert.equals(c.want[1], key, c.name)
            assert.equals(c.want[2], scope, c.name)
            assert.equals(c.want[3], action, c.name)
            assert.equals(c.want[4], moved, c.name)
        end
    end)
end)

describe("InstanceAskValid", function()
    it("accepts only while the question is still true", function()
        local token = { key = "200:8", gen = 3 }
        local cases = {
            -- Also the option turned off and back on with the prompt still up: the
            -- inputs are the same, and it resets (an accepted residual).
            { name = "same instance, no reset since, module and option on", key = "200:8", gen = 3, enabled = true, on = true, want = true },
            { name = "a different instance", key = "300:8", gen = 3, enabled = true, on = true, want = false },
            { name = "no readable instance", key = nil, gen = 3, enabled = true, on = true, want = false },
            -- The generation also moves when the player leaves and comes back, and
            -- when the Delve ends in place: the key compare cannot see either.
            { name = "a reset, key start or change of place since", key = "200:8", gen = 4, enabled = true, on = true, want = false },
            { name = "module disabled", key = "200:8", gen = 3, enabled = false, on = true, want = false },
            { name = "Reset on Instance Entry off at click time", key = "200:8", gen = 3, enabled = true, on = false, want = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, DM.InstanceAskValid(token, c.key, c.gen, c.enabled, c.on), c.name)
        end
    end)
end)

describe("InstanceResetAction", function()
    it("holds a still-valid reset while a capture would read secret amounts", function()
        -- InstanceAskValid's case covers every way the reset stops being valid;
        -- these rows cover the combat gate and its order against validity.
        local token = { key = "200:8", gen = 3 }
        local cases = {
            { name = "valid, not blocked", gen = 3, blocked = false, want = "wipe" },
            { name = "valid, blocked", gen = 3, blocked = true, want = "defer" },
            { name = "no longer valid, blocked", gen = 4, blocked = true, want = "none" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, DM.InstanceResetAction(token, "200:8", c.gen, true, true, c.blocked), c.name)
        end
    end)
end)

describe("LoginResetAction", function()
    it("holds Reset on Logout while a capture would read secret amounts", function()
        -- InstanceResetAction's case covers the gate's order against validity;
        -- these rows cover what keeps the login reset valid.
        local cases = {
            { name = "a login in combat", enabled = true, on = true, blocked = true, want = "defer" },
            { name = "a login or combat end, not blocked", enabled = true, on = true, blocked = false, want = "wipe" },
            { name = "Reset on Logout off by combat end", enabled = true, on = false, blocked = false, want = "none" },
            { name = "module disabled", enabled = false, on = true, blocked = false, want = "none" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, DM.LoginResetAction(c.enabled, c.on, c.blocked), c.name)
        end
    end)
end)

describe("PaintSkip", function()
    it("skips only a window whose view and data are unchanged since its last paint", function()
        local cases = {
            { name = "unchanged", pt = "DMG", ps = 5, nt = "DMG", ns = 5, open = false, want = true },
            { name = "view changed", pt = "DMG", ps = 5, nt = "HEAL", ns = 5, open = false, want = false },
            { name = "data updated", pt = "DMG", ps = 5, nt = "DMG", ns = 6, open = false, want = false },
            { name = "detail panel open", pt = "DMG", ps = 5, nt = "DMG", ns = 5, open = true, want = false },
            -- A deferred paint clears the type and leaves the old sequence.
            { name = "no paint record", pt = nil, ps = 5, nt = nil, ns = 5, open = false, want = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, DM.PaintSkip(c.pt, c.ps, c.nt, c.ns, c.open), c.name)
        end
    end)
end)
