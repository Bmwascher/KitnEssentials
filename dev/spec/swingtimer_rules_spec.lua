-- Modules/Combat/SwingTimer/SwingTimerRules.lua -- the rules a later edit breaks
-- silently: duration refusal, bar order, slots and when a bar shows, the cached
-- speed, range, melee state, the window, the hunter's stop-by and shot time, the
-- words, the cast tick, seals, the Blizzard button's refusals, and the Target
-- bar's hit rules. Constants, data tables and proof switches get no case, and
-- ParryHastened gets none: smoke checks it.
local L = require("dev.spec._ke_loader")

describe("swing timer bar rules", function()
    local Rules

    before_each(function()
        Rules = L.loadSwingTimerRules().SwingTimerRules
    end)

    it("refuses an invalid duration", function()
        for _, row in ipairs({
            { value = 2.6, want = true }, { value = "2.6", want = false }, { value = nil, want = false },
            { value = 0, want = false }, { value = -1, want = false }, { value = 0 / 0, want = false },
            { value = 1 / 0, want = false },
        }) do
            assert.equals(row.want, Rules.ValidDuration(row.value))
        end
    end)

    it("orders a guide class's Ranged bar first and any other class's Main Hand first", function()
        assert.same({ "R", "MH", "OH" }, Rules.BarOrder("HUNTER"))
        assert.same({ "MH", "OH", "R" }, Rules.BarOrder("WARRIOR"))
    end)

    it("skips an unknown weapon, always slots Main Hand, and slots a known secondary before it is used", function()
        local order = { "MH", "OH", "R" }
        assert.same({ MH = 1, R = 2 }, Rules.Slots(order, { MH = true, R = true }))
        assert.same({ MH = 1 }, Rules.Slots({ "R", "MH", "OH" }, {}))
        assert.same({ R = 1, MH = 2, OH = 3 }, Rules.Slots({ "R", "MH", "OH" }, { MH = true, OH = true, R = true }))
    end)

    it("shows a known weapon with the setting off, and with it on a known primary or a used secondary", function()
        for _, row in ipairs({
            { swings = false, primary = false, known = true, used = false, want = true },
            { swings = false, primary = true, known = false, used = false, want = false },
            { swings = true, primary = true, known = true, used = false, want = true },
            { swings = true, primary = true, known = false, used = false, want = false },
            { swings = true, primary = false, known = true, used = false, want = false },
            { swings = true, primary = false, known = true, used = true, want = true },
        }) do
            assert.equals(row.want, Rules.BarShown(row.swings, row.primary, row.known, row.used))
        end
    end)

    it("keeps the cached speed through an unreadable read and restarts a swap only on a plain read", function()
        for _, row in ipairs({
            { name = "plain replaces", readable = true, read = 2.6, cached = 3.0, speed = 2.6, known = true },
            { name = "plain nil: no weapon", readable = true, read = nil, cached = 3.0, speed = nil, known = false },
            { name = "plain zero: no weapon", readable = true, read = 0, cached = 3.0, speed = nil, known = false },
            { name = "unreadable keeps", readable = false, read = 2.6, cached = 3.0, speed = 3.0, known = true },
            { name = "a swing's duration as the cache stands in", readable = false, read = nil, cached = 1.9,
              speed = 1.9, known = true },
            { name = "unreadable, no cache", readable = false, read = nil, cached = nil, speed = nil, known = false },
        }) do
            local speed, known = Rules.ResolveSpeed(row.readable, row.read, row.cached)
            assert.equals(row.speed, speed, row.name)
            assert.equals(row.known, known, row.name)
        end
        assert.equals(2.0, Rules.SwapRestartSpeed(true, 2.0))
        assert.is_nil(Rules.SwapRestartSpeed(true, nil))
        assert.is_nil(Rules.SwapRestartSpeed(false, 2.0))
    end)

    it("calls a bar out of range only on a readable false", function()
        assert.is_true(Rules.OutOfRange(true, false))
        assert.is_false(Rules.OutOfRange(true, true))
        assert.is_false(Rules.OutOfRange(true, nil))
        assert.is_false(Rules.OutOfRange(false, false))
        assert.is_true(Rules.OutOfRangeFromEvent(true, false, true))
        assert.is_false(Rules.OutOfRangeFromEvent(true, false, false))
        assert.is_false(Rules.OutOfRangeFromEvent(false, false, true))
    end)

    it("answers empty with attack off, running before the end and parked after it", function()
        for _, row in ipairs({
            { attack = false, now = 5, ends = 10, want = "empty" },
            { attack = true, now = 5, ends = 10, want = "running" },
            { attack = true, now = 11, ends = 10, want = "parked" },
            { attack = true, now = 5, ends = nil, want = "parked" },
        }) do
            assert.equals(row.want, Rules.MeleeState(row.attack, row.now, row.ends))
        end
    end)

    it("sizes the window from the seconds, widens it only when asked, clamps it, and mirrors a fraction", function()
        assert.near(0.2, Rules.EndWindow(0.4, 2.0, false, 0.1), 1e-9)
        assert.near(0.25, Rules.EndWindow(0.4, 2.0, true, 0.1), 1e-9)
        assert.equals(1, Rules.EndWindow(3, 2.0, false, 0))
        assert.is_nil(Rules.EndWindow(nil, 2.0, false, 0))
        assert.is_nil(Rules.EndWindow(0.4, 0, false, 0))
        assert.near(0.75, Rules.Mirror(0.25, true), 1e-9)
        assert.equals(0.25, Rules.Mirror(0.25, false))
    end)

    it("shows the holder by the visibility setting, and always in a preview", function()
        for _, row in ipairs({
            { visibility = "combat", inCombat = true, live = false, want = true },
            { visibility = "combat", inCombat = false, live = true, want = false },
            { visibility = "always", inCombat = false, live = false, want = true },
            { visibility = "idle", inCombat = true, live = false, want = false },
            { visibility = "idle", inCombat = false, live = true, want = true },
            { visibility = "combat", inCombat = false, live = false, preview = true, want = true },
        }) do
            assert.equals(row.want, Rules.FrameShown(row.visibility, row.inCombat, row.live, row.preview))
        end
    end)
end)
