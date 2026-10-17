-- The attach decision and the attached text size rule. Placement, fonts and
-- message timing stay an in-game check.
local L = require("dev.spec._ke_loader")

describe("Combat Texts attach decision", function()
    it("attaches only when the toggle, the module, the saved switch and the container all say yes", function()
        local CM = L.loadCombatTexts()
        local rows = {
            { name = "all four yes", toggle = true, running = true, saved = true, container = true, want = true },
            { name = "toggle off", toggle = false, running = true, saved = true, container = true, want = false },
            { name = "toggle unset", running = true, saved = true, container = true, want = false },
            { name = "module not running", toggle = true, running = false, saved = true, container = true, want = false },
            { name = "saved switch off", toggle = true, running = true, saved = false, container = true, want = false },
            { name = "no container", toggle = true, running = true, saved = true, container = false, want = false },
        }
        for _, c in ipairs(rows) do
            assert.are.equal(c.want, CM.AttachWanted(c.toggle, c.running, c.saved, c.container), c.name)
        end
    end)
end)

describe("Combat Texts attached size", function()
    it("takes the Combat Texts size only when attached with the override off", function()
        local CM = L.loadCombatTexts()
        local rows = {
            { name = "detached", attached = false, override = false, own = 24, ct = 16, want = 24 },
            { name = "attached, override off", attached = true, override = false, own = 24, ct = 16, want = 16 },
            { name = "attached, override on", attached = true, override = true, own = 24, ct = 16, want = 24 },
            { name = "attached, no Combat Texts size", attached = true, override = false, own = 24, want = 24 },
        }
        for _, c in ipairs(rows) do
            assert.are.equal(c.want, CM.ResolveAttachedSize(c.attached, c.override, c.own, c.ct), c.name)
        end
    end)
end)

-- A refused seat's change message makes every owner re-apply its placement,
-- and one owner's anchor carries a protected aura button, so the message is
-- a combat gate. The real queue and flush run against a captured timer and
-- an InCombatLockdown override.
describe("Combat Texts attach-change message", function()
    local CM, timers, sent, lockdown, enabled

    before_each(function()
        timers, sent, lockdown, enabled = {}, 0, false, true
        CM = L.loadCombatTexts({
            C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
            InCombatLockdown = function() return lockdown end,
        })
        CM.IsEnabled = function() return enabled end
        CM.SendMessage = function() sent = sent + 1 end
    end)

    it("sends one message for every refusal queued before it goes out", function()
        CM:QueueAttachChange()
        CM:QueueAttachChange()
        assert.equal(1, #timers)
        timers[1]()
        assert.equal(1, sent)
    end)

    it("holds the message until combat ends", function()
        lockdown = true
        CM:QueueAttachChange()
        assert.equal(0, #timers, "queued in combat")
        lockdown = false
        CM:FlushAttachChange()
        assert.equal(1, sent, "queued in combat")

        CM:QueueAttachChange()
        lockdown = true
        timers[1]()
        assert.equal(1, sent, "timer fired in combat")
        lockdown = false
        CM:FlushAttachChange()
        assert.equal(2, sent, "timer fired in combat")
    end)

    it("drops the message once Combat Texts is disabled", function()
        CM:QueueAttachChange()
        enabled = false
        timers[1]()
        assert.equal(0, sent)
    end)
end)
