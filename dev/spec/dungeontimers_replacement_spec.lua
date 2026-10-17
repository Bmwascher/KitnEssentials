-- Pure refusal and ownership checks; native callback timing remains a client check.
local loader = require("dev.spec._ke_loader")

describe("DungeonTimers canceled forecast replacement", function()
    local State
    before_each(function() State = loader.loadDungeonTimerState() end)

    local function fixture(edit)
        local contract = {
            kind = "Timer", isCooldown = true, policy = "estimated-impact",
            spanMode = "remaining-only", stopTolerance = 0.15,
            collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished",
            replacement = { from = 65, duration = 3 },
        }
        if edit then edit(contract) end
        local bindings = State.BuildBindings({ [2] = { timerPolicy = "explicit", spells = {
            [700] = { castDuration = 5, timerSource = contract },
        } } })
        local binding = bindings.timers[2] and bindings.timers[2][700]
        if not binding then return nil end
        local store, owner = State.New(), {}
        State.AdmitOwner(store, owner, 2)
        local inst = State.Start(store, owner, "Ritual (2)", binding, 65, 65, 0, true)
        inst.timelineIdentity = 1
        return { store = store, owner = owner, inst = inst, binding = binding }
    end

    local function hold(f, remaining, identity, binding)
        return State.HoldTimerReplacement(f.store, f.owner, "Ritual (2)", binding or f.binding,
            remaining or 3, 62, identity or 2, { "retained payload" })
    end

    it("consumes only a fresh receipt at its predecessor's qualified cancellation", function()
        for _, case in ipairs({
            { name = "same tick", age = 0, accept = true },
            { name = "bounded delay", age = 0.5, accept = true },
            { name = "expired", age = 0.501 },
            { name = "backward time", age = -0.01 },
            { name = "invalid time", age = math.huge },
            { name = "finished", age = 0, state = "finished" },
            { name = "unknown state", age = 0, state = "unknown" },
            { name = "wrong event", age = 0, id = 9 },
            { name = "nonretirement", age = 0, outcome = "anchor" },
        }) do
            local f = fixture()
            assert.is_true(hold(f), case.name)
            local receipt = State.TakeTimerReplacement(f.store, f.inst, 62 + case.age,
                case.outcome or "retire", case.state or "canceled", case.id or 1)
            if case.accept then
                assert.equal("retained payload", receipt.payload[1], case.name)
                assert.equal(62, receipt.sourceClock.receivedAt, case.name)
            else
                assert.is_nil(receipt, case.name)
            end
            assert.is_nil(State.TakeTimerReplacement(f.store, f.inst, 62, "retire", "canceled", 1), case.name)
        end
    end)

    it("refuses mismatched or conflicting receipts and drops holds across controls and lifecycle changes", function()
        for _, case in ipairs({
            { name = "same identity", reject = function(f) return hold(f, 3, 1) end },
            { name = "refused identity", reject = function(f) return hold(f, 3, "refused") end },
            { name = "wrong duration", reject = function(f) return hold(f, 4) end },
            { name = "unidentified predecessor", reject = function(f) f.inst.timelineIdentity = nil; return hold(f) end },
            { name = "wrong key", reject = function(f)
                local b = {}; for k, v in pairs(f.binding) do b[k] = v end
                b.curationId = 701; return hold(f, 3, 2, b)
            end },
            { name = "unmarked", reject = function(f) f.binding.replacement = nil; return hold(f) end },
            { name = "anchored predecessor", reject = function(f) f.inst.anchorElapsed = 60; return hold(f) end },
            { name = "paused predecessor", reject = function(f) State.Pause(f.store, f.owner, "Ritual (2)", 60); return hold(f) end },
            { name = "duplicate", invalidate = function(f) assert.is_nil(hold(f)) end },
            { name = "conflicting third receipt", invalidate = function(f) assert.is_nil(hold(f, 3, 3)) end },
            { name = "pause", invalidate = function(f) State.Pause(f.store, f.owner, "Ritual (2)", 62) end },
            { name = "resume", invalidate = function(f) State.Resume(f.store, f.owner, "Ritual (2)", 62) end },
            { name = "instance retirement", invalidate = function(f) State.Retire(f.store, f.inst) end },
            { name = "owner retirement", invalidate = function(f) State.RetireOwner(f.store, f.owner) end },
            { name = "encounter retirement", invalidate = function(f) State.RetireEncounter(f.store, 2) end },
            { name = "module retirement", invalidate = function(f) State.RetireAll(f.store) end },
        }) do
            local f = fixture()
            if case.reject then
                assert.is_nil(case.reject(f), case.name)
            else
                assert.is_true(hold(f), case.name)
                case.invalidate(f)
            end
            assert.is_nil(State.TakeTimerReplacement(f.store, f.inst, 62, "retire", "canceled", 1), case.name)
        end
    end)

    it("refuses invalid and incompatible replacement contracts instead of falling back", function()
        assert.is_table(fixture())
        for _, edit in ipairs({
            function(c) c.replacement = true end,
            function(c) c.replacement.from = math.huge end,
            function(c) c.replacement.duration = 0 / 0 end,
            function(c) c.replacement.duration = 0 end,
            function(c) c.replacement.from = 3 end,
            function(c) c.anchor = nil end,
            function(c) c.castConfirm = "boss-cast-start" end,
            function(c) c.pausedStop = "retire" end,
            function(c) c.queueAfter = { parent = 1, delay = 1 } end,
            function(c) c.canceledStop = { stage = 1, within = 0.5 } end,
            function(c) c.retainEarlyFinished = true end,
            function(c) c.suppressConcurrentRestart = { from = 29, duration = 6 } end,
            function(c) c.holdOverlapping = true end,
            function(c) c.pullReceipt = true end,
        }) do
            assert.is_nil(fixture(edit))
        end
    end)
end)
