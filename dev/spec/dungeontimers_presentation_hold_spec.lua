-- Pure presentation ordering and source lifetime; no frame, sound or timer mocks.
local loader = require("dev.spec._ke_loader")

describe("DungeonTimers overlapping presentation hold", function()
    local State, shown, waiting

    before_each(function()
        State = loader.loadDungeonTimerState()
        shown, waiting = {}, {}
    end)

    local function isShown(instance) return shown[instance] == true end
    local function isWaiting(instance) return waiting[instance] == true end

    local function buildBinding(change)
        local contract = {
            kind = "Timer", isCooldown = true, policy = "estimated-impact",
            spanMode = "remaining-only", stopTolerance = 0.15,
            collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished",
            holdOverlapping = true,
        }
        if change then change(contract) end
        local index = State.BuildBindings({
            [1] = { timerPolicy = "explicit", spells = {
                [101] = { castDuration = 3.5, timerSource = contract },
            } },
        })
        return index.timers[1] and index.timers[1][101]
    end

    local function startPair()
        local store, binding = State.New(), buildBinding()
        State.AdmitOwner(store, "owner", 1)
        local first = State.Start(store, "owner", "first", binding, 45, 45, 0, true)
        local nextOne = State.Start(store, "owner", "next", binding, 1, 1, 45, true)
        shown[first], waiting[nextOne] = true, true
        return store, first, nextOne, binding
    end

    it("admits the opt-in and refuses malformed or incompatible contracts", function()
        assert.is_not_nil(buildBinding())
        local changes = {
            function(c) c.holdOverlapping = false end,
            function(c) c.holdOverlapping = "yes" end,
            function(c) c.anchor = nil end,
            function(c) c.castConfirm = "boss-cast-start" end,
            function(c) c.pausedStop = "retire" end,
            function(c) c.queueAfter = { parent = 102, delay = 1 } end,
            function(c) c.canceledStop = { stage = 2, within = 0.5 } end,
            function(c) c.retainEarlyFinished = true end,
            function(c) c.suppressConcurrentRestart = { from = 45, duration = 1 } end,
        }
        for i, change in ipairs(changes) do assert.is_nil(buildBinding(change), i) end
    end)

    it("keeps the displayed matching occurrence first even while paused", function()
        local store, binding = State.New(), buildBinding()
        State.AdmitOwner(store, "owner", 1)
        State.AdmitOwner(store, "other", 1)
        local outsider = State.Start(store, "other", "other owner", binding, 45, 45, 0, true)
        local tracked = State.Start(store, "owner", "tracking", binding, 45, 45, 0, false, true)
        shown[outsider], shown[tracked] = true, true
        local otherSpell = buildBinding()
        otherSpell.curationId = 102
        local unrelated = State.Start(store, "owner", "other spell", otherSpell, 45, 45, 0, true)
        local first = State.Start(store, "owner", "first", binding, 45, 45, 0, true)
        local nextOne = State.Start(store, "owner", "next", binding, 1, 1, 45, true)
        shown[first], shown[unrelated] = true, true
        State.Pause(store, "owner", "first", 44)
        assert.equal(first, State.PresentationHead(store, nextOne, isShown))
        assert.equal(unrelated, State.PresentationHead(store, unrelated, isShown))
        State.Resume(store, "owner", "first", 46)
        assert.equal(first, State.PresentationHead(store, nextOne, isShown))
    end)

    it("does not let a hidden future forecast suppress an earlier warning", function()
        local store, binding = State.New(), buildBinding()
        State.AdmitOwner(store, "owner", 1)
        local future = State.Start(store, "owner", "future", binding, 45, 45, 0, true)
        local earlier = State.Start(store, "owner", "earlier", binding, 1, 1, 2, true)
        assert.is_nil(State.PresentationHead(store, earlier, isShown))
        shown[earlier] = true
        assert.equal(earlier, State.PresentationHead(store, future, isShown))
        waiting[future] = true
        assert.equal(future, State.PresentationHead(store, earlier, isWaiting))
        shown[earlier] = nil
        assert.is_nil(State.PresentationHead(store, future, isShown))
        assert.equal(future, State.PresentationHead(store, earlier, isWaiting))
    end)

    it("holds either publication order and cancels only the waiting occurrence", function()
        for _, publishFirst in ipairs({ true, false }) do
            local store, binding = State.New(), buildBinding()
            State.AdmitOwner(store, "owner", 1)
            local first = State.Start(store, "owner", "first", binding, 45, 45, 0, true)
            shown[first] = true
            local nextOne
            if publishFirst then nextOne = State.Start(store, "owner", "next", binding, 1, 1, 45, true) end
            State.Anchor(first, 45, 1)
            if not publishFirst then nextOne = State.Start(store, "owner", "next", binding, 1, 1, 45, true) end
            assert.equal(first, State.PresentationHead(store, nextOne, isShown))
            assert.equal("retire", State.ClassifyStop(nextOne, 47.7, nil, "canceled"))
            State.Retire(store, nextOne)
            assert.equal(first, State.PresentationHead(store, first, isShown))
            assert.equal("keep", State.ClassifyExpiry(first, 48))
            State.Retire(store, first)
            assert.is_nil(State.PresentationHead(store, nextOne, isShown))
        end
    end)

    it("releases a surviving follow-up without restarting its Finished clock", function()
        local store, first, nextOne = startPair()
        State.Anchor(first, 45, 1)
        State.Pause(store, "owner", "next", 45.5)
        assert.equal("resume-and-anchor", State.ClassifyStop(nextOne, 46, nil, "finished"))
        State.Resume(store, "owner", "next", 46)
        State.Anchor(nextOne, 46, 2)
        assert.equal(first, State.PresentationHead(store, nextOne, isShown))
        State.Retire(store, first)
        assert.is_nil(State.PresentationHead(store, nextOne, isShown))
        assert.equal(nextOne, State.PresentationHead(store, nextOne, isWaiting))
        local elapsed = State.Sample(nextOne, 48.5)
        assert.equal(1, State.AnchoredRemaining(nextOne, elapsed))
        assert.equal("retire", State.ClassifyExpiry(nextOne, 49.5))
        State.Retire(store, nextOne)
        local short = State.Start(store, "owner", "short", buildBinding(), 1, 1, 50, true)
        assert.is_nil(State.PresentationHead(store, short, isShown))
        assert.equal("anchor", State.ClassifyStop(short, 51.2, nil, "finished"))
    end)

    it("replacement and teardown cannot revive a pending occurrence", function()
        local store, first, nextOne, binding = startPair()
        local replacement = State.Start(store, "owner", "next", binding, 5, 5, 46, true)
        waiting[replacement] = true
        State.Retire(store, first)
        assert.equal("retired", nextOne.state)
        assert.equal(replacement, State.PresentationHead(store, replacement, isWaiting))
        for _, retire in ipairs({
            function(s) State.RetireOwner(s, "owner") end,
            function(s) State.RetireEncounter(s, 1) end,
            function(s) State.RetireAll(s) end,
        }) do
            store, first, nextOne, binding = startPair()
            retire(store)
            assert.equal("retired", first.state)
            assert.is_nil(State.PresentationHead(store, nextOne, isWaiting))
            State.AdmitOwner(store, "owner", 1)
            local fresh = State.Start(store, "owner", "fresh", binding, 1, 1, 60, true)
            waiting[fresh] = true
            assert.is_nil(State.PresentationHead(store, nextOne, isWaiting))
            assert.equal(fresh, State.PresentationHead(store, fresh, isWaiting))
        end
    end)
end)
