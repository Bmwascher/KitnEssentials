-- Replace mode has to silence Blizzard's own roll windows, or the player gets
-- two stacks for every roll.
--
-- Why this is worth a spec: the old suppression called
-- UIParent:UnregisterEvent("START_LOOT_ROLL"). That was correct once, and in
-- 12.0 it silently stopped doing anything -- the event now routes through
-- GameEvent's private dispatcher (Blizzard_Game/Shared/EventRouting.lua), so
-- the call succeeded, reported nothing, and Blizzard kept drawing. A spec that
-- names the route catches the same class of drift next time.

local L = require("dev.spec._ke_loader")

describe("LootRoll Blizzard roll suppression", function()
    local setEnabled

    -- Records what the module asks of the routing API. Three functions, no
    -- state machine: the assertions are about which call is made, not about
    -- what Blizzard's dispatcher would then do.
    local function fakeGameEvent()
        local calls = { unregistered = {}, registered = {}, handled = 0 }
        _G.GameEvent = {
            UnregisterInternalEvent = function(event)
                calls.unregistered[#calls.unregistered + 1] = event
            end,
            RegisterInternalEvent = function(event, handler)
                calls.registered[#calls.registered + 1] = { event = event, handler = handler }
            end,
            HandleStartLootRoll = function() calls.handled = calls.handled + 1 end,
        }
        return calls
    end

    before_each(function()
        local _, _, seams = L.loadLootRollBars()
        setEnabled = seams.setBlizzardRollsEnabled
        _G.GameEvent = nil
    end)

    after_each(function()
        _G.GameEvent = nil
    end)

    it("pulls the routed handler when suppressing, not UIParent's", function()
        local calls = fakeGameEvent()
        assert.is_true(setEnabled(false))
        assert.same({ "START_LOOT_ROLL" }, calls.unregistered)
        assert.equal(0, #calls.registered)
    end)

    it("puts a handler back on restore", function()
        local calls = fakeGameEvent()
        assert.is_true(setEnabled(true))
        assert.equal(1, #calls.registered)
        assert.equal("START_LOOT_ROLL", calls.registered[1].event)
        assert.equal(0, #calls.unregistered)
    end)

    it("restores a handler that routes to Blizzard's own implementation", function()
        local calls = fakeGameEvent()
        setEnabled(true)
        calls.registered[1].handler()
        assert.equal(1, calls.handled)
    end)

    it("reports failure instead of erroring when the routing API is absent", function()
        assert.is_false(setEnabled(false))
        assert.is_false(setEnabled(true))
    end)

    it("reports failure when the routing API is present but incomplete", function()
        _G.GameEvent = { UnregisterInternalEvent = function() end }
        assert.is_false(setEnabled(false))
    end)
end)
