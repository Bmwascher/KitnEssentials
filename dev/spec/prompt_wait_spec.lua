-- Tier 2: Core/Widgets.lua -- KE.PromptWaits, the predicate KE:CreatePrompt
-- consults for opts.waitIfBusy: an unsolicited prompt waits while another is
-- open, in combat, and while others already wait. Then the queue operations
-- behind it. Both are tested as pure functions rather than through a fake
-- dialog, for the reason prompt_typed_gate_spec.lua gives: a stateful fake of
-- the singleton would encode its layout, not the rule.
local mock = require("dev.spec._wow_mock")
local helpers = require("dev.spec._helpers")

describe("Core/Widgets.lua prompt wait rule", function()
    local KE

    before_each(function()
        mock.install()
        KE = helpers.loadModule("Core/Widgets.lua", {})
    end)

    it("waits only when opted in and another prompt is showing, combat is on or others wait", function()
        local cases = {
            { waitIfBusy = true,  showing = true,  inCombat = false, queued = false, waits = true },
            { waitIfBusy = true,  showing = false, inCombat = false, queued = false, waits = false },
            { waitIfBusy = true,  showing = false, inCombat = true,  queued = false, waits = true },
            { waitIfBusy = true,  showing = false, inCombat = false, queued = true,  waits = true },
            { waitIfBusy = nil,   showing = true,  inCombat = false, queued = false, waits = false },
            { waitIfBusy = false, showing = false, inCombat = true,  queued = false, waits = false },
            { waitIfBusy = nil,   showing = false, inCombat = false, queued = true,  waits = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.waits, KE.PromptWaits(c.waitIfBusy, c.showing, c.inCombat, c.queued),
                ("waitIfBusy %s, showing %s, inCombat %s, queued %s"):format(
                    tostring(c.waitIfBusy), tostring(c.showing), tostring(c.inCombat), tostring(c.queued)))
        end
    end)
end)

describe("Core/Widgets.lua prompt queue", function()
    local KE
    local function ownerA() end
    local function ownerB() end
    local function ownerC() end

    before_each(function()
        mock.install()
        KE = helpers.loadModule("Core/Widgets.lua", {})
    end)

    local function owners(queue)
        local out = {}
        for i, entry in ipairs(queue) do out[i] = entry.accept end
        return out
    end

    it("opens waiting prompts in the order they waited, and an empty queue gives nil", function()
        local q = {}
        KE.PromptQueueAdd(q, { accept = ownerA }, 8)
        KE.PromptQueueAdd(q, { accept = ownerB }, 8)
        KE.PromptQueueAdd(q, { accept = ownerC }, 8)
        assert.equals(ownerA, KE.PromptQueueTake(q).accept)
        assert.equals(ownerB, KE.PromptQueueTake(q).accept)
        assert.equals(ownerC, KE.PromptQueueTake(q).accept)
        assert.is_nil(KE.PromptQueueTake(q))
    end)

    it("keeps one entry per owner with a re-raise at the back, and never merges ownerless entries", function()
        local q = {}
        KE.PromptQueueAdd(q, { accept = ownerA, text = "old" }, 8)
        KE.PromptQueueAdd(q, { accept = ownerB }, 8)
        KE.PromptQueueAdd(q, { accept = ownerA, text = "new" }, 8)
        assert.same({ ownerB, ownerA }, owners(q))
        assert.equals("new", q[2].text)

        local ownerless = {}
        KE.PromptQueueAdd(ownerless, { text = "one" }, 8)
        KE.PromptQueueAdd(ownerless, { text = "two" }, 8)
        assert.equals(2, #ownerless)
    end)

    it("removes only the named owner's entry, keeps the rest in order, and a nil owner removes nothing", function()
        local q = {}
        KE.PromptQueueAdd(q, { accept = ownerA }, 8)
        KE.PromptQueueAdd(q, { accept = ownerB }, 8)
        KE.PromptQueueAdd(q, { accept = ownerC }, 8)
        KE.PromptQueueRemove(q, ownerB)
        assert.same({ ownerA, ownerC }, owners(q))
        KE.PromptQueueRemove(q, nil)
        assert.same({ ownerA, ownerC }, owners(q))
    end)

    it("refuses a new owner at the cap, keeps every earlier entry, and still takes a same-owner re-raise", function()
        local q = {}
        assert.is_true(KE.PromptQueueAdd(q, { accept = ownerA }, 2))
        assert.is_true(KE.PromptQueueAdd(q, { accept = ownerB }, 2))
        assert.is_false(KE.PromptQueueAdd(q, { accept = ownerC }, 2))
        assert.same({ ownerA, ownerB }, owners(q))
        assert.is_true(KE.PromptQueueAdd(q, { accept = ownerA }, 2))
        assert.same({ ownerB, ownerA }, owners(q))
    end)
end)
