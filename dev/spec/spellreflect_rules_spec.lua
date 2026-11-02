-- Modules/Combat/ClassTools/SpellReflectRules.lua -- the rules a later edit
-- breaks silently: when each spell's press window opens and closes, which
-- spells the boss data covers, refusing secret payloads, which record shows,
-- how it is drawn, which sound plays, what counts as a press, and when
-- Spell Reflection reads ready. Secret flags and readings are passed in, so
-- no Blizzard fake is needed.
local L = require("dev.spec._ke_loader")

describe("spell reflect rules", function()
    local Rules

    local function E(id, open, close)
        return { id = id, name = "Spell", open = open, close = close }
    end

    local function always() return "ALWAYS" end

    before_each(function()
        Rules = L.loadSpellReflectRules().SpellReflectRules
    end)

    it("opens a rule spell's window 4.5 s before the hit and closes it at the hit", function()
        -- spell id, cast length, expected open, expected close (from the cast start)
        local cases = {
            { 1247685, 3, -1.5, 3 },
            { 1222795, 3, -1.5, 3 },
            { 1290797, 3, -1.5, 3 },
            { 1296220, 2, -2.5, 2 },
            { 1299154, 2, -2.5, 2 },
            { 1305810, 1, -3.5, 1 },
        }
        for i, case in ipairs(cases) do
            local open, close = Rules.Window(case[1], case[2])
            assert.same({ case[3], case[4] }, { open, close }, "case " .. i)
        end
    end)

    it("gives an exception spell the same window whatever the cast length, not the rule's", function()
        for _, id in ipairs({ 1297017, 1234233 }) do
            local open, close = Rules.Window(id, 2)
            local open0, close0 = Rules.Window(id, 0)
            assert.same({ open, close }, { open0, close0 }, "spell " .. id)
            assert.are_not.same({ 2 - Rules.WINDOW, 2 }, { open, close }, "spell " .. id)
        end
    end)

    it("indexes a tracked spell's cast length, name and boss only when its row has a cast length", function()
        local data = {
            [10] = { name = "Boss A", spells = {
                [1247685] = { name = "Thornspike", castDuration = 3 },
                [999] = { name = "Other", castDuration = 1 },
            } },
            [11] = { name = "Boss B", spells = {
                [1297017] = { name = "Void Blast" },
            } },
        }
        local index = Rules.Index(data)
        assert.same({ castLength = 3, name = "Thornspike", boss = "Boss A" }, index[1247685])
        assert.is_nil(index[999])
        assert.is_nil(index[1297017])
        assert.is_nil(index[1222795])
    end)

    it("refuses a payload with any field flagged secret", function()
        local SECRET = {}
        local function isSecret(value) return value == SECRET end
        local plain = { "owner", 1247685, 10, "Thornspike" }
        assert.is_true(Rules.PayloadReadable(isSecret, plain[1], plain[2], plain[3], plain[4]))
        for i = 1, #plain do
            local args = { plain[1], plain[2], plain[3], plain[4] }
            args[i] = SECRET
            assert.is_false(Rules.PayloadReadable(isSecret, args[1], args[2], args[3], args[4]), "field " .. i)
        end
    end)

    it("shows Off never, When Reflect is ready only while ready, and Always either way", function()
        -- mode, ready, shown
        local cases = {
            { "OFF", true, false },
            { "OFF", false, false },
            { "READY", true, true },
            { "READY", false, false },
            { "ALWAYS", true, true },
            { "ALWAYS", false, true },
        }
        for i, case in ipairs(cases) do
            local records = {}
            local rec = Rules.Start(records, E(1247685, -1.5, 3), "boss", "bar", 3, 100)
            local picked = Rules.Pick(records, 100, 5, function() return case[1] end, case[2], false)
            assert.equals(case[3] and rec or nil, picked, "case " .. i)
        end
    end)

    it("shows the soonest record within Lead, and nothing while dead but a test run", function()
        local records = {}
        local far = Rules.Start(records, E(1247685, -1.5, 3), "boss", "far", 8, 100)
        Rules.Start(records, E(1296220, -2.5, 2), "boss", "later", 4, 100)
        local sooner = Rules.Start(records, E(1222795, -1.5, 3), "boss", "sooner", 2, 100)
        assert.equals(sooner, Rules.Pick(records, 100, 5, always, true, false))
        assert.is_nil(Rules.Pick(records, 100, 5, always, true, true))
        records.test = Rules.NewTest(E(1297017, -2, 2.5), 100)
        assert.equals(records.test, Rules.Pick(records, 100, 5, always, true, true))
        assert.is_nil(Rules.Pick({ far = far }, 100, 5, always, true, false))
    end)

    it("draws white before the window, green in it, the word from the cast start, gray when not ready", function()
        -- phase, ready, word, color, not-ready look, glow
        local cases = {
            { "WAIT", true, false, "TEXT", false, false },
            { "GO", true, false, "GO", false, true },
            { "NOW", true, true, "GO", false, true },
            { "WAIT", false, false, "GRAY", true, false },
            { "GO", false, false, "GRAY", true, false },
            { "NOW", false, true, "GRAY", true, false },
        }
        for i, case in ipairs(cases) do
            local word, color, notReady, glow = Rules.Look(case[1], case[2])
            assert.same({ case[3], case[4], case[5], case[6] }, { word, color, notReady, glow }, "case " .. i)
        end
        -- text mode: word, not ready, label, timer, small line
        local lines = {
            { false, false, Rules.TEXT_LABEL, "2.4", "Void Blast" },
            { true, false, Rules.TEXT_LABEL_NOW, Rules.NOW_WORD, "Void Blast" },
            { false, true, Rules.NOT_READY, "", "Void Blast  2.4" },
            { true, true, Rules.NOT_READY, "", "Void Blast  " .. Rules.NOW_WORD },
        }
        for i, case in ipairs(lines) do
            local label, timer, line = Rules.TextLines(case[1], case[2], "2.4", "Void Blast")
            assert.same({ case[3], case[4], case[5] }, { label, timer, line }, "text case " .. i)
        end
    end)

    it("plays Spell Reflect once, Not Safe once when not ready, Spell Reflect when Reflect returns, and never again for a retimed bar", function()
        local rec = {}
        assert.is_nil(Rules.SoundFor(rec, "WAIT", true))
        assert.equals("READY", Rules.SoundFor(rec, "GO", true))
        assert.is_nil(Rules.SoundFor(rec, "NOW", true))
        local late = {}
        assert.equals("NOT_READY", Rules.SoundFor(late, "GO", false))
        assert.is_nil(Rules.SoundFor(late, "GO", false))
        assert.equals("READY", Rules.SoundFor(late, "NOW", true))
        assert.is_nil(Rules.SoundFor(late, "NOW", false))
        -- the same bar text 0.5 s off the open record replaces it but keeps its sounds
        local records = {}
        local first = Rules.Start(records, E(1247685, -1.5, 3), "boss", "bar", 1, 100)
        assert.equals("READY", Rules.SoundFor(first, "GO", true))
        local retimed = Rules.Start(records, E(1247685, -1.5, 3), "boss", "bar", 1.5, 100)
        assert.are_not.equals(first, retimed)
        assert.is_nil(Rules.SoundFor(retimed, "GO", true))
    end)

    it("counts a ready-to-cooling change as a press and marks only records in their window", function()
        -- ready before, isActive, isOnGCD, press
        local cases = {
            { true, true, false, true },
            { true, true, nil, true },
            { true, true, true, false },
            { true, false, nil, false },
            { false, true, false, false },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[4], Rules.IsPress(case[1], case[2], case[3]), "case " .. i)
        end
        local records = {}
        local waiting = Rules.Start(records, E(1247685, -1.5, 3), "boss", "a", 4, 100)
        local open = Rules.Start(records, E(1296220, -2.5, 2), "boss", "b", 2, 100)
        local casting = Rules.Start(records, E(1222795, -1.5, 3), "boss", "c", 1, 100)
        Rules.Said(records, "c", 100)
        assert.equals(2, Rules.MarkPressed(records, 100))
        assert.is_false(Rules.Covered(waiting, 100))
        assert.is_true(Rules.Covered(open, 100))
        assert.is_true(Rules.Covered(casting, 100))
        assert.equals(waiting, Rules.Pick(records, 100, 5, always, true, false))
    end)

    it("reads ready unless the cooldown runs beyond the global cooldown, nil counting as not true", function()
        -- isActive, isOnGCD, ready
        local cases = {
            { false, nil, true },
            { nil, nil, true },
            { true, false, false },
            { true, nil, false },
            { true, true, true },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], Rules.IsReady(case[1], case[2]), "case " .. i)
        end
    end)

    it("steps every frame for a running near record or a canceled one, else wakes at Lead or the age limit", function()
        local function make(duration, paused, canceled, pressed)
            local records = {}
            local rec = Rules.Start(records, E(1247685, -1.5, 3), "boss", "bar", duration, 100)
            if pressed then Rules.MarkPressed(records, 100) end
            if paused then Rules.Pause(records, "bar", 100, true) end
            if canceled then Rules.Stop(records, "bar", 100) end
            return rec
        end
        local age = Rules.MAX_AGE
        -- Row 7: pressed at 100 with the hit at 104, so the reach is 105; paused with
        -- 1 s left, the hit (now + 1 + 3) passes 105 one second later.
        -- seconds to the cast, paused, canceled, pressed, near, ticks, seconds to the wake (Lead 5)
        local cases = {
            { 8, false, false, false, false, false, 3 },
            { 4, false, false, false, true, true, nil },
            { 4, true, false, false, true, false, age },
            { 8, true, false, false, false, false, age },
            { 4, false, true, false, true, true, nil },
            { 4, true, true, false, true, true, nil },
            { 1, true, false, true, true, false, 1 + Rules.COVER_PAST },
        }
        for i, case in ipairs(cases) do
            local rec = make(case[1], case[2], case[3], case[4])
            local near, ticks, due = Rules.Schedule(rec, Rules.Phase(rec, 100), 100, 5)
            assert.same({ case[5], case[6], case[7] }, { near, ticks, due }, "case " .. i)
        end
    end)

    it("hides a pressed cast only while the press still reaches the hit, however the hit moves", function()
        local RULE, LONG = E(1247685, -1.5, 3), E(1234233, 0, 6)
        local function bar(records, duration, now) Rules.Start(records, RULE, "boss", "bar", duration, now) end
        -- The bar runs from 100 to 102 and the hit is 3 s after it. A press at 100.5
        -- lasts to 105.5, 0.5 s past the hit at 105.
        -- label, entry, press time, how the hit moves, time read, cue shown
        local cases = {
            { "no move", RULE, 100.5, function() end, 100.5, false },
            { "re-time +0.4", RULE, 100.5, function(r) bar(r, 1.9, 100.5) end, 100.5, false },
            { "re-time +1.0", RULE, 100.5, function(r) bar(r, 2.5, 100.5) end, 100.5, true },
            { "re-time +0.4, refresh +0.2", RULE, 100.5, function(r)
                bar(r, 1.9, 100.5)
                bar(r, 2.1, 100.5)
            end, 100.5, true },
            { "paused 1 s", RULE, 100.5, function(r)
                Rules.Pause(r, "bar", 100.5, true)
                Rules.Pause(r, "bar", 101.5, false)
            end, 101.5, true },
            { "cast start heard 1 s late", RULE, 100.5, function(r) Rules.Said(r, "bar", 103) end, 103, true },
            { "bar stopped 0.8 s after zero", RULE, 100.5, function(r) Rules.Stop(r, "bar", 102.8) end, 102.8, true },
            { "window longer than Reflection, no move", LONG, 102, function() end, 102.5, false },
        }
        for _, case in ipairs(cases) do
            local records = {}
            Rules.Start(records, case[2], "boss", "bar", 2, 100)
            Rules.MarkPressed(records, case[3])
            case[4](records)
            local shown = Rules.Pick(records, case[5], 5, always, true, false) ~= nil
            assert.equals(case[6], shown, case[1])
        end
    end)

    it("undoes a cancel when the same bar comes back within 0.25 s of its end", function()
        local records = {}
        local first = Rules.Start(records, E(1247685, -1.5, 3), "boss", "bar", 2, 100)
        Rules.Stop(records, "bar", 100.5)
        local second = Rules.Start(records, E(1247685, -1.5, 3), "boss", "bar", 1.6, 100.5)
        assert.equals(first, second)
        assert.is_nil(second.stopAt)
    end)
end)
