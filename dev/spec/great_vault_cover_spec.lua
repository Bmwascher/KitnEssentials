-- Reward Cover's rules for Great Vault Alert: when covers and the bad-loot
-- line show, which card wants a cover, how a reveal is keyed and pruned, when
-- the Jackpot fires, and which cover gets the last-one tease. All are pure
-- predicates; no Blizzard frame is faked.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("Great Vault reward cover rules (Modules/QoL/GreatVaultCover.lua)", function()
    local GVA

    before_each(function()
        mock.install()
        local modules = helpers.installAddonShim()
        local KE = { Print = function() end }
        helpers.loadModule("Modules/QoL/GreatVaultAlert.lua", KE)
        helpers.loadModule("Modules/QoL/GreatVaultCover.lua", KE)
        GVA = modules["GreatVaultAlert"]
    end)

    it("shows covers only while listening, enabled, cover on and claimable, and the line only with the strip and no notice", function()
        local yes = function() return true end
        local no = function() return false end
        local boom = function() error("boom") end
        local one = function() return 1 end
        local covers = {
            { name = "all true",       args = { true, true, true, yes },  want = true },
            { name = "not listening",  args = { false, true, true, yes }, want = false },
            { name = "module off",     args = { true, false, true, yes }, want = false },
            { name = "cover off",      args = { true, true, false, yes }, want = false },
            { name = "cannot claim",   args = { true, true, true, no },   want = false },
            { name = "claim errors",   args = { true, true, true, boom }, want = false },
            { name = "claim missing",  args = { true, true, true, nil },  want = false },
            { name = "claim not true", args = { true, true, true, one },  want = false },
        }
        for _, c in ipairs(covers) do
            assert.equals(c.want, GVA.CoverActive(c.args[1], c.args[2], c.args[3], c.args[4]), c.name)
        end

        local lines = {
            { name = "active, on, strip, no notice", args = { true, true, true, false },  want = true },
            { name = "inactive",                     args = { false, true, true, false }, want = false },
            { name = "setting off",                  args = { true, false, true, false }, want = false },
            { name = "no strip",                     args = { true, true, false, false }, want = false },
            { name = "notice shown",                 args = { true, true, true, true },   want = false },
        }
        for _, c in ipairs(lines) do
            assert.equals(c.want, GVA.BadLootLineShown(c.args[1], c.args[2], c.args[3], c.args[4]), c.name)
        end
    end)

    it("wants a cover only for an active, rewarded card neither revealed nor seen", function()
        local store = { c1 = true }
        local cases = {
            { name = "fresh card",        args = { true, true, "c2", store, false }, want = true },
            { name = "no key, unseen",    args = { true, true, nil, store, false },  want = true },
            { name = "no store",          args = { true, true, "c2", nil, false },   want = true },
            { name = "inactive",          args = { false, true, "c2", store, false }, want = false },
            { name = "no rewards",        args = { true, false, "c2", store, false }, want = false },
            { name = "revealed in store", args = { true, true, "c1", store, false },  want = false },
            { name = "seen this opening", args = { true, true, "c2", store, true },   want = false },
        }
        for _, c in ipairs(cases) do
            local a = c.args
            assert.equals(c.want, GVA.CardWantsCover(a[1], a[2], a[3], a[4], a[5]), c.name)
        end
    end)

    it("keys a reveal on the claim id, then the first reward with an item id", function()
        local cases = {
            { name = "claim id",   info = { claimID = 7, rewards = { { itemDBID = "x" } } }, want = "c7" },
            { name = "item id after a currency", info = { rewards = { { id = 3418 }, { itemDBID = "abc" } } }, want = "iabc" },
            { name = "neither",    info = { rewards = { { id = 3418 } } }, want = nil },
            { name = "no info",    info = nil, want = nil },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, GVA.CardKey(c.info), c.name)
        end
    end)

    it("prunes keys no longer on offer, and nothing while no key is on offer", function()
        local cases = {
            { name = "drops stale",          store = { c1 = true, c2 = true }, live = { c2 = true }, want = { c2 = true } },
            { name = "empty live keeps all", store = { c1 = true },            live = {},            want = { c1 = true } },
        }
        for _, c in ipairs(cases) do
            GVA.PruneRevealed(c.store, c.live)
            assert.same(c.want, c.store, c.name)
        end
    end)

    it("fires the Jackpot only on the strictly highest of two or more known levels", function()
        local cases = {
            { name = "strict highest",  levels = { 285, 289, 282 }, i = 2, want = true },
            { name = "tie for highest", levels = { 289, 289, 282 }, i = 1, want = false },
            { name = "lower level",     levels = { 285, 289 },      i = 1, want = false },
            { name = "unknown level",   levels = { 289, false },    i = 1, want = false },
            { name = "lone card",       levels = { 289 },           i = 1, want = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, GVA.IsJackpot(c.levels, c.i), c.name)
        end
    end)

    it("teases only when exactly one cover is still waiting", function()
        local a, b = {}, {}
        local cases = {
            { name = "one waiting",  waiting = { a },    want = a },
            { name = "none waiting", waiting = {},       want = nil },
            { name = "two waiting",  waiting = { a, b }, want = nil },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, GVA.TeaseTarget(c.waiting), c.name)
        end
    end)
end)
