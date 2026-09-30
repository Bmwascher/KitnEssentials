-- Core/Context.lua, the shared context gate. Every case builds its own
-- instance through KE.Context.New(deps): the readers are plain injected
-- functions over a mutable world table, the frame only records what was
-- registered, and the scheduler fires handles by hand. No Blizzard
-- subsystem is faked, so the spec header needs no reason for one.
local L = require("dev.spec._ke_loader")

local SPEC_EVENT = "PLAYER_SPECIALIZATION_CHANGED"

-- The settle is the only timer, so handles are told apart by state alone and
-- no case pins its length.
local function newScheduler()
    local sched = { handles = {} }
    function sched.newTimer(sec, fn)
        local h = { sec = sec, fn = fn, cancelled = false, fired = false }
        h.Cancel = function() h.cancelled = true end
        sched.handles[#sched.handles + 1] = h
        return h
    end
    function sched.live()
        local out = {}
        for _, h in ipairs(sched.handles) do
            if not h.cancelled and not h.fired then out[#out + 1] = h end
        end
        return out
    end
    function sched.fire()
        for _, h in ipairs(sched.live()) do
            h.fired = true
            h.fn()
        end
    end
    return sched
end

local function newFrame()
    local f = { events = {}, unitEvents = {} }
    function f:RegisterEvent(event) self.events[event] = true end
    function f:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
    function f:UnregisterEvent(event)
        self.events[event] = nil
        self.unitEvents[event] = nil
    end
    function f:SetScript(_, fn) self.onEvent = fn end
    function f:Fire(event, ...) self.onEvent(self, event, ...) end
    return f
end

local function build(overrides)
    overrides = overrides or {}
    local world = {
        inInstance = false, instanceType = "none", difficultyID = 0,
        inGroup = false, inRaid = false, keyActive = false, specID = 62,
    }
    local sched = newScheduler()
    local frames = {}
    local secret = overrides.secretValues or {}
    local deps = {
        isInInstance = overrides.isInInstance
            or function() return world.inInstance, world.instanceType end,
        getInstanceInfo = function() return "Somewhere", world.instanceType, world.difficultyID end,
        isInGroup = function() return world.inGroup end,
        isInRaid = function() return world.inRaid end,
        isChallengeModeActive = function() return world.keyActive end,
        specID = function() return world.specID end,
        issecretvalue = function(v) return v ~= nil and secret[v] == true end,
        newTimer = sched.newTimer,
        createFrame = function()
            local f = newFrame()
            frames[#frames + 1] = f
            return f
        end,
        geterrorhandler = function() return function() end end,
    }
    local KE = L.loadContext()
    return KE.Context.New(deps), world, sched, frames
end

local function inParty(facts)
    if facts.inInstance == nil then return nil end
    return facts.inInstance and facts.instanceType == "party"
end

local function newSub(needs, predicate, onUnknown)
    local log = { enter = 0, leave = 0, evals = 0 }
    local options = {
        needs = needs,
        onUnknown = onUnknown or "closed",
        predicate = function(facts)
            log.evals = log.evals + 1
            return predicate(facts)
        end,
        onEnter = function() log.enter = log.enter + 1 end,
        onLeave = function() log.leave = log.leave + 1 end,
    }
    return options, log
end

describe("KE.Context", function()
    it("fires enter and leave once per change of the answer and never on an unchanged one", function()
        local ctx = build()
        local want = false
        local options, log = newSub({ "zone" }, function() return want end)
        ctx:Subscribe("A", options)
        ctx:Evaluate("A")
        assert.are.equal(0, log.enter)

        want = true
        ctx:Evaluate("A")
        ctx:Evaluate("A")
        assert.are.equal(1, log.enter)
        assert.are.equal(0, log.leave)

        want = false
        ctx:Evaluate("A")
        ctx:Evaluate("A")
        assert.are.equal(1, log.enter)
        assert.are.equal(1, log.leave)
    end)

    it("enters at subscribe when the answer already holds and leaves at unsubscribe", function()
        local ctx, world = build()
        world.inInstance, world.instanceType = true, "party"
        local options, log = newSub({ "zone" }, inParty)

        ctx:Subscribe("A", options)
        assert.are.equal(1, log.enter)
        assert.is_true(ctx:IsActive("A"))

        ctx:Unsubscribe("A")
        assert.are.equal(1, log.leave)
        assert.is_false(ctx:IsActive("A"))
    end)

    it("registers a group's events with its first subscriber and removes them after its last", function()
        local rows = {
            { group = "zone", events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" } },
            { group = "group", events = { "GROUP_ROSTER_UPDATE" } },
            { group = "key", events = { "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET" } },
            { group = "spec", events = {}, unitEvent = SPEC_EVENT },
        }
        local function assertRegistered(frame, row, stage)
            for _, event in ipairs(row.events) do
                assert.is_true(frame.events[event], row.group .. " " .. stage .. " " .. event)
            end
            if row.unitEvent then
                assert.are.equal("player", frame.unitEvents[row.unitEvent], row.group .. " " .. stage)
            end
        end
        for _, row in ipairs(rows) do
            local ctx, _, _, frames = build()
            assert.are.equal(0, #frames, row.group)

            ctx:Subscribe("A", (newSub({ row.group }, inParty)))
            assert.are.equal(1, #frames, row.group)
            local frame = frames[1]
            assertRegistered(frame, row, "first")

            ctx:Subscribe("B", (newSub({ row.group }, inParty)))
            assertRegistered(frame, row, "second")

            ctx:Unsubscribe("A")
            assertRegistered(frame, row, "one left")

            ctx:Unsubscribe("B")
            assert.is_nil(next(frame.events), row.group)
            assert.is_nil(next(frame.unitEvents), row.group)
        end
    end)

    it("takes the subscriber's own answer when a reader errors or returns a secret", function()
        -- The secret reader answers a plain boolean the injected test declares
        -- secret, so only the secrecy check can reject it: a table would
        -- already fail the type check.
        local readers = {
            errors = { fn = function() error("unreadable") end },
            secret = { fn = function() return true, "party" end, secretValues = { [true] = true } },
        }
        local rows = {
            { reader = "errors", onUnknown = "open", entered = 1 },
            { reader = "errors", onUnknown = "closed", entered = 0 },
            { reader = "secret", onUnknown = "open", entered = 1 },
            { reader = "secret", onUnknown = "closed", entered = 0 },
        }
        for _, row in ipairs(rows) do
            local label = row.reader .. " " .. row.onUnknown
            local reader = readers[row.reader]
            local ctx = build({ isInInstance = reader.fn, secretValues = reader.secretValues })
            local options, log = newSub({ "zone" }, inParty, row.onUnknown)
            ctx:Subscribe("A", options)
            assert.are.equal(row.entered, log.enter, label)
            assert.are.equal(row.entered == 1, ctx:IsActive("A"), label)
        end
    end)

    it("passes the player's own spec change to listeners and no other unit's", function()
        local ctx, _, _, frames = build()
        local calls = {}
        ctx:SubscribeSpec("S", function(event, unit) calls[#calls + 1] = { event, unit } end)
        local frame = frames[1]
        assert.are.equal("player", frame.unitEvents[SPEC_EVENT])

        frame:Fire(SPEC_EVENT, "party1")
        assert.are.equal(0, #calls)

        frame:Fire(SPEC_EVENT, "player")
        assert.are.same({ { SPEC_EVENT, "player" } }, calls)
    end)

    it("evaluates on each zone edge and gives one settled evaluation after the last", function()
        local ctx, _, sched, frames = build()
        local options, log = newSub({ "zone" }, inParty)
        ctx:Subscribe("A", options)
        local frame = frames[1]
        log.evals = 0

        frame:Fire("PLAYER_ENTERING_WORLD")
        assert.are.equal(1, log.evals)
        local first = sched.live()[1]
        assert.is_not_nil(first)

        frame:Fire("ZONE_CHANGED_NEW_AREA")
        assert.are.equal(2, log.evals)
        assert.is_true(first.cancelled)
        local settles = sched.live()
        assert.are.equal(1, #settles)
        assert.are_not.equal(first, settles[1])

        sched.fire()
        assert.are.equal(3, log.evals)
        sched.fire()
        assert.are.equal(3, log.evals)
    end)
end)
