-- Tier: guard logic KE invented for the inspect retry (tiered test policy):
-- which INSPECT_READY counts, the dirty-cache test, and the retry bound.
-- Event timing, tooltip data and rendering are smoke-tested, not here.
local helpers = require("dev.spec._helpers")

-- A comparison against a secret raises in the client. These stand-ins raise
-- when compared with each other: Lua 5.1 calls __eq only when both operands are
-- tables sharing the handler. `secret()` is reported secret; `probe()` shares
-- the handler but is not, so pairing one of each makes a missed secret check on
-- EITHER argument raise. A comparison with nil can never call __eq, so a `== nil`
-- test placed before the secret check cannot be made observable here; that
-- order is checked by reading the diff and by the api-validator gate.
local SECRET_MT = { __eq = function() error("a secret value was compared") end }
local secrets = setmetatable({}, { __mode = "k" })
local function secret() local v = setmetatable({}, SECRET_MT); secrets[v] = true; return v end
local function probe() return setmetatable({}, SECRET_MT) end

-- InspectPanel captures issecretvalue as a file-local at load, so the stub goes
-- in before loadModule.
local function loadIP()
    local modules = helpers.installAddonShim()
    _G.issecretvalue = function(v) return secrets[v] == true end
    helpers.loadModule("Modules/QoL/InspectPanel.lua", {})
    return modules["InspectPanel"]
end

describe("Inspect start: which INSPECT_READY counts", function()
    it("accepts only the inspect frame's own GUID", function()
        local ready = loadIP()._ReadyForFrame
        local cases = {
            { name = "the frame's own unit", guid = "Player-1", frame = "Player-1", want = true },
            { name = "another unit", guid = "Player-2", frame = "Player-1", want = false },
            { name = "a secret payload, refused before any comparison", guid = secret(), frame = probe(), want = false },
            { name = "a secret frame GUID, refused before any comparison", guid = probe(), frame = secret(), want = false },
            { name = "no readable frame GUID", guid = "Player-1", want = false },
            -- The only input the nil test decides: without it, nil == nil would pass.
            { name = "no GUID on either side", want = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, ready(c.guid, c.frame), c.name)
        end
    end)
end)

-- A pending slot must never match the dirty key: that is what makes the next
-- pass redraw a stand-in instead of leaving it on screen.
describe("Inspect slot: the dirty-cache test", function()
    it("never short-circuits a slot whose last render pended", function()
        local unchanged = loadIP()._SlotUnchanged
        local s = { itemLink = "L", enchantID = 7, ilvl = 250, gemHash = "", pending = true }
        assert.is_false(unchanged(s, "L", 7, 250, ""))
        s.pending = nil
        assert.is_true(unchanged(s, "L", 7, 250, ""))
    end)
end)

-- Clearing the dirty cache repaints every slot, but must not itself refill a
-- pending slot's retry budget within the same stamp.
describe("Inspect slot: a settings-driven cache clear", function()
    it("drops the dirty keys and keeps the pending state and retry flags", function()
        local clear = loadIP()._ClearDirtyKeys
        local s = { itemLink = "L", enchantID = 7, ilvl = 250, gemHash = "F0",
            pending = true, pendingRetries = 2, paintPasses = 1, retry = true }
        clear({ ["Player-1"] = { [1] = s } })
        assert.same({ pending = true, pendingRetries = 2, paintPasses = 1, retry = true }, s)
    end)
end)

-- The retry bound. Only sweep renders spend a retry: a same-frame burst of
-- event passes must not use up the budget before the data can land.
describe("Inspect slot: the pending retry bound", function()
    it("keeps arming through sweep renders 1-3 and settles on the fourth", function()
        local step = loadIP()._PendingStep
        local s = {}
        assert.is_true(step(s, true, true, false))
        assert.is_true(step(s, true, true, true))
        assert.is_true(step(s, true, true, true))
        assert.is_true(step(s, true, true, true))
        assert.is_false(step(s, true, true, true))
        assert.is_nil(s.pending)
    end)

    it("arms on event renders without spending a retry", function()
        local step = loadIP()._PendingStep
        local s = {}
        for _ = 1, 12 do assert.is_true(step(s, true, true, false)) end
        assert.is_nil(s.pendingRetries)
        assert.is_true(s.pending)
    end)

    it("stays pending and arms nothing before the inspect is stamped", function()
        local step = loadIP()._PendingStep
        local s = {}
        assert.is_false(step(s, true, false, false))
        assert.is_true(s.pending)
        assert.is_nil(s.pendingRetries)
    end)

    it("clears the pending flag and the retry count once the slot resolves", function()
        local step = loadIP()._PendingStep
        local s = { pending = true, pendingRetries = 2 }
        assert.is_false(step(s, nil, true, true))
        assert.is_nil(s.pending)
        assert.is_nil(s.pendingRetries)
    end)
end)
