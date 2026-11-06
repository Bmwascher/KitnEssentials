-- Modules/Combat/SwingTimer/SwingTimerRules.lua -- the rules a later edit breaks
-- silently: duration refusal, bar order, slots and when a bar shows, whether a
-- weapon is known, range, melee state, the window, the hunter's stop-by and shot time, the
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

    it("keeps the last answer on a weapon through an unreadable read and restarts a swap only on a plain read", function()
        for _, row in ipairs({
            { name = "plain speed: a weapon", readable = true, read = 2.6, known = false, want = true },
            { name = "plain nil: no weapon", readable = true, read = nil, known = true, want = false },
            { name = "plain zero: no weapon", readable = true, read = 0, known = true, want = false },
            { name = "unreadable keeps known", readable = false, read = 2.6, known = true, want = true },
            { name = "unreadable keeps unknown", readable = false, read = 2.6, known = false, want = false },
            { name = "unreadable, no answer yet", readable = false, read = nil, known = nil, want = false },
        }) do
            assert.equals(row.want, Rules.WeaponKnown(row.readable, row.read, row.known), row.name)
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

    it("shares a stack height over its rows, counting no rows as one, never under the floor", function()
        for _, row in ipairs({
            { stack = 50, rows = 2, spacing = 2, want = 24 },
            { stack = 16, rows = 0, spacing = 2, want = 16 },
            { stack = 10, rows = 3, spacing = 2, want = 4 },
        }) do
            assert.equals(row.want, Rules.RowHeightFor(row.stack, row.rows, row.spacing, 4))
        end
    end)

    it("reads a fill rising or draining, clamped at both ends, and no fill as empty", function()
        for _, row in ipairs({
            { start = 10, duration = 4, drains = false, now = 11, want = 0.25 },
            { start = 10, duration = 4, drains = true, now = 11, want = 0.75 },
            { start = 10, duration = 4, drains = false, now = 9, want = 0 },
            { start = 10, duration = 4, drains = true, now = 15, want = 0 },
            { start = 10, duration = 4, drains = false, now = 15, want = 1 },
            { start = nil, duration = nil, drains = false, now = 15, want = 0 },
        }) do
            assert.near(row.want, Rules.FillAt(row.start, row.duration, row.drains, row.now), 1e-9)
        end
    end)

    it("re-times a fill from where the bar stands to its end, and gives none when it is there or the end has passed", function()
        for _, row in ipairs({
            { fraction = 1, toward = 0 },
            { fraction = 0.4, toward = 0 },
            { fraction = 0, toward = 1 },
            { fraction = 0.4, toward = 1 },
        }) do
            local start, duration, drains = Rules.FillToward(row.fraction, 20, 20.6, row.toward)
            assert.near(row.fraction, Rules.FillAt(start, duration, drains, 20), 1e-9)
            assert.near(row.toward, Rules.FillAt(start, duration, drains, 20.6), 1e-9)
        end
        local start, duration, drains = Rules.FillToward(1, 20, 20.6, 0)
        assert.near(20, start, 1e-9)
        assert.near(0.6, duration, 1e-9)
        assert.is_true(drains)
        assert.is_nil(Rules.FillToward(0, 20, 20.6, 0))
        assert.is_nil(Rules.FillToward(1, 20, 20.6, 1))
        assert.is_nil(Rules.FillToward(0.4, 20, 20, 0))
    end)

    it("starts the drain at the stop-by line, or at a stop inside the zone", function()
        for _, row in ipairs({
            { stopAt = 100, lastStop = 98, want = 100 },
            { stopAt = 100, lastStop = 100.3, want = 100.3 },
            { stopAt = 100, lastStop = nil, want = 100 },
        }) do
            assert.equals(row.want, Rules.AimStart(row.stopAt, row.lastStop))
        end
    end)
end)

describe("swing timer ranged rules", function()
    local Rules

    before_each(function()
        Rules = L.loadSwingTimerRules().SwingTimerRules
    end)

    it("places stop-by and go for a normal bow and clamps both when aim plus latency exceeds the swing", function()
        local stopBy, go = Rules.Zones(2.9, 0.5, 0.06)
        assert.near((2.9 - 0.56) / 2.9, stopBy, 1e-9)
        assert.near((2.9 - 0.06) / 2.9, go, 1e-9)
        stopBy, go = Rules.Zones(0.05, 0.5, 0.06)
        assert.equals(0, stopBy)
        assert.equals(0, go)
    end)

    it("takes the later of the swing end and the last stop plus aim plus latency", function()
        assert.equals(100, Rules.ShotTime(100, 98, 0.5, 0.06))
        assert.near(100.36, Rules.ShotTime(100, 99.8, 0.5, 0.06), 1e-9)
        assert.equals(100, Rules.ShotTime(100, nil, 0.5, 0.06))
    end)

    it("answers a due shot in the order moving, casting or out of range, aim, ready", function()
        for _, row in ipairs({
            { moving = true, casting = true, out = true, now = 5, shotAt = 6, want = "held" },
            { moving = false, casting = true, out = false, now = 5, shotAt = 6, want = "wait" },
            { moving = false, casting = false, out = true, now = 5, shotAt = 6, want = "wait" },
            { moving = false, casting = false, out = false, now = 5, shotAt = 6, want = "aim" },
            { moving = false, casting = false, out = false, now = 7, shotAt = 6, want = "ready" },
        }) do
            assert.equals(row.want, Rules.RangedAtEnd(row.moving, row.casting, row.out, row.now, row.shotAt))
        end
    end)

    it("words the reload MOVE before the zone, and STILL or STOP in it", function()
        for _, row in ipairs({
            { inZone = false, moving = false, want = "MOVE" },
            { inZone = false, moving = true, want = "MOVE" },
            { inZone = true, moving = false, want = "STILL" },
            { inZone = true, moving = true, want = "STOP" },
        }) do
            assert.equals(row.want, Rules.ReloadWord(row.inZone, row.moving))
        end
    end)

    it("places a tick inside the swing and pins one past the end as a clip", function()
        local fraction, clipped = Rules.TickFraction(105, 100, 10)
        assert.near(0.5, fraction, 1e-9)
        assert.is_false(clipped)
        fraction, clipped = Rules.TickFraction(111, 100, 10)
        assert.equals(1, fraction)
        assert.is_true(clipped)
        fraction, clipped = Rules.TickFraction(99, 100, 10)
        assert.equals(0, fraction)
        assert.is_false(clipped)
    end)
end)

describe("swing timer color and refusal rules", function()
    local Rules

    before_each(function()
        Rules = L.loadSwingTimerRules().SwingTimerRules
    end)

    it("matches a seal by name, chooses the aura path only out of combat with auras visible", function()
        local seal = { colorKey = "TestColor" }
        local byName = { ["Test Seal"] = seal }
        assert.equals(seal, Rules.SealFromCast("Test Seal", byName))
        assert.is_nil(Rules.SealFromCast("Other Spell", byName))
        assert.is_nil(Rules.SealFromCast(nil, byName))
        assert.equals("auras", Rules.SealSource(false, false))
        assert.equals("cast", Rules.SealSource(false, true))
        assert.equals("cast", Rules.SealSource(true, false))
        assert.equals(34, Rules.SealSeconds(true, 34, 30))
        assert.equals(34, Rules.SealSeconds(false, 30, 34))
        assert.equals(Rules.SEAL_SECONDS, Rules.SealSeconds(false, nil, nil))
    end)

    it("colors a melee bar queue over seal over base, and any other bar by its base", function()
        assert.equals("Q", Rules.BarColorKey(true, "Q", "S", "B"))
        assert.equals("S", Rules.BarColorKey(true, nil, "S", "B"))
        assert.equals("B", Rules.BarColorKey(true, nil, nil, "B"))
        assert.equals("B", Rules.BarColorKey(false, "Q", "S", "B"))
    end)

    it("wants the queue event only for a class with a queued attack and the color on", function()
        for _, row in ipairs({
            { classFile = "WARRIOR", on = true, want = true },
            { classFile = "MAGE", on = true, want = false },
            { classFile = "WARRIOR", on = false, want = false },
        }) do
            assert.equals(row.want, Rules.QueueEventWanted(row.classFile, row.on))
        end
    end)

    it("shows the Blizzard button by CVar and flag, with a missing CVar as off", function()
        for _, row in ipairs({
            { cvar = true, flag = false, shown = true, action = "hide" },
            { cvar = true, flag = true, shown = true, action = "hide" },
            { cvar = false, flag = true, shown = true, action = "show" },
            { cvar = false, flag = false, shown = false, action = nil },
            { cvar = nil, flag = false, shown = false, action = nil },
            { cvar = nil, flag = true, shown = true, action = "show" },
        }) do
            local shown, action = Rules.BlizzardButton(row.cvar, row.flag)
            assert.equals(row.shown, shown)
            assert.equals(row.action, action)
        end
        assert.is_false(Rules.BlizzardFlag(true, true))
        assert.is_true(Rules.BlizzardFlag(false, true))
        assert.is_false(Rules.BlizzardFlag(false, false))
    end)

    it("refuses a Blizzard click in combat, and otherwise writes off and sets the flag, or on and clears it", function()
        assert.is_nil((Rules.BlizzardClick(true, false, true)))
        assert.is_nil((Rules.BlizzardClick(false, true, true)))
        assert.is_nil((Rules.BlizzardClick(false, false, false)))
        local value, flag = Rules.BlizzardClick(true, false, false)
        assert.equals("0", value)
        assert.is_true(flag)
        value, flag = Rules.BlizzardClick(false, true, false)
        assert.equals("1", value)
        assert.is_false(flag)
        assert.is_true(Rules.ReleaseRangeFlag(false))
        assert.is_false(Rules.ReleaseRangeFlag(true))
    end)

    it("counts a physical melee outcome unless a readable answer says it was not on the player", function()
        for _, row in ipairs({
            { action = "WOUND", school = 1, readable = true, onMe = true, want = true },
            { action = "PARRY", school = 1, readable = false, onMe = false, want = true },
            { action = "DODGE", school = 1, readable = true, onMe = false, want = false },
            { action = "WOUND", school = 4, readable = true, onMe = true, want = false },
            { action = "HEAL", school = 1, readable = true, onMe = true, want = false },
        }) do
            assert.equals(row.want, Rules.TargetHitCounts(row.action, row.school, row.readable, row.onMe))
        end
    end)

    it("learns an in-range interval and keeps the last good one otherwise", function()
        assert.near(2.4, Rules.LearnInterval(10, 12.4, 3.0), 1e-9)
        assert.equals(3.0, Rules.LearnInterval(10, 10.1, 3.0))
        assert.equals(3.0, Rules.LearnInterval(10, 16, 3.0))
        assert.is_nil(Rules.LearnInterval(nil, 12, nil))
    end)
end)
