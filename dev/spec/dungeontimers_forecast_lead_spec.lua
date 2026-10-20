-- Forecast lead: a row whose provider forecast ends early counts behind it and
-- still ends at the timeline Finished. Pure state; no frame or timer mocks.
local loader = require("dev.spec._ke_loader")

describe("DungeonTimers forecast lead", function()
    local State

    before_each(function()
        State = loader.loadDungeonTimerState()
    end)

    local function buildBinding(change)
        local contract = {
            kind = "Timer", isCooldown = true, policy = "estimated-impact",
            spanMode = "remaining-only", stopTolerance = 0.15,
            collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished",
            forecastLead = 0.5,
        }
        if change then change(contract) end
        local index = State.BuildBindings({
            [1] = { timerPolicy = "explicit", spells = {
                [101] = { castDuration = 0, timerSource = contract },
            } },
        })
        return index.timers[1] and index.timers[1][101]
    end

    local function start(binding)
        local store = State.New()
        State.AdmitOwner(store, "owner", 1)
        return State.Start(store, "owner", "boulder", binding, 20, 20, 0, true)
    end

    it("admits a lead up to one second on a Finished-anchored row and refuses anything else", function()
        assert.equal(0.5, buildBinding().forecastLead)
        local changes = {
            function(c) c.forecastLead = 0 end,
            function(c) c.forecastLead = -0.5 end,
            function(c) c.forecastLead = 1.5 end,
            function(c) c.forecastLead = "0.5" end,
            function(c) c.anchor = nil end,
            function(c) c.castConfirm = "boss-cast-start" end,
            function(c) c.pausedStop = "retire" end,
            function(c) c.queueAfter = { parent = 102, delay = 1 } end,
            function(c) c.canceledStop = { stage = 2, within = 0.5 } end,
            function(c) c.retainEarlyFinished = true end,
            function(c) c.suppressConcurrentRestart = { from = 45, duration = 1 } end,
            function(c) c.holdOverlapping = true end,
            function(c) c.replacement = { from = 45, duration = 1 } end,
            function(c) c.soonOnHold = true end,
        }
        for i, change in ipairs(changes) do assert.is_nil(buildBinding(change), i) end
    end)

    it("reaches forecast zero only after the lead, so the countdown is not blanked at the provider's zero", function()
        local cases = {
            { name = "with lead", change = nil, at = 20.4, after = 20.6 },
            { name = "without lead", change = function(c) c.forecastLead = nil end, at = 19.9, after = 20.1 },
        }
        for _, c in ipairs(cases) do
            local inst = start(buildBinding(c.change))
            assert.equal("keep", State.ClassifyExpiry(inst, c.at), c.name)
            assert.equal("hold-eligible", State.ClassifyExpiry(inst, c.after), c.name)
        end
    end)

    it("anchors a Finished inside the lead on a row that owns its expiry, instead of retiring it", function()
        local binding = buildBinding()
        binding.ownsExpiry = true
        local inst = start(binding)
        assert.equal("anchor", State.ClassifyStop(inst, 20.3, nil, "finished"))
        State.Anchor(inst, 20.3, 1)
        assert.equal(0, State.AnchoredRemaining(inst, (State.Sample(inst, 20.3))))
        assert.equal("retire", State.ClassifyExpiry(inst, 20.3))
    end)
end)
