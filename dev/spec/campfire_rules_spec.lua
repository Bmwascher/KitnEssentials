-- Modules/QoL/Campfire/CampfireRules.lua -- the rules a later edit breaks
-- silently: which moment shows, when a fire is worth stopping at, what counts
-- as new, and which secure button is wanted. Tier 1, no mock.
local L = require("dev.spec._ke_loader")

describe("campfire rules", function()
    local Rules

    before_each(function()
        Rules = L.loadCampfireRules().CampfireRules
    end)

    local function settings(over)
        local s = {
            Shape = "ROUND", AlertEnabled = true, AlertUnderMinutes = 15, ShowUnderMinutes = 5,
            ShowAlways = false, ShowMissing = true, GrayInRestAreas = false, GrayWhileMounted = true,
            TimerInRestAreas = true, TimerWhileMounted = true, TimerInCombat = true,
        }
        for key, value in pairs(over or {}) do s[key] = value end
        return s
    end

    local function inputs(over)
        local i = { refillProven = true, settings = settings(over.settings) }
        for key, value in pairs(over) do
            if key ~= "settings" then i[key] = value end
        end
        return i
    end

    -- 40 minutes left of 60: above every threshold, with 20 minutes to gain.
    local function up(over)
        local i = { buffUp = true, left = 2400, duration = 3600 }
        for key, value in pairs(over or {}) do i[key] = value end
        return i
    end

    it("selects each row of the state table, first match first", function()
        local NOT_IN_COMBAT = { TimerInCombat = false }
        -- row, inputs, moment, shape shows, alert shows
        local cases = {
            { "1 preview", { preview = "Low", inInstance = true }, "Low", true, false },
            { "2 instance", up({ inInstance = true, seated = true, inRange = true }), "Nothing", false, false },
            { "3 combat, timer off", up({ inCombat = true, held = true, seated = true, settings = NOT_IN_COMBAT }),
                "Nothing", false, false },
            { "4 held", up({ held = true, seated = true, inRange = true }), "Held", false, false },
            { "5 seated", up({ seated = true, landing = true, inRange = true }), "Sitting", true, false },
            { "6 landed", up({ landing = true, inRange = true, left = 240 }), "Landing", true, false },
            { "7 passing", up({ inRange = true, left = 240 }), "Passing", true, true },
            { "8 time to spare", up({ inRange = true, settings = { ShowAlways = true } }), "Spare", true, false },
            { "9 running low", up({ left = 240, settings = { ShowAlways = true } }), "Low", true, false },
            { "10 buff shown", up({ settings = { ShowAlways = true } }), "Shown", true, false },
            { "11 on the road", up(), "Road", false, false },
            { "12 gone, combat", { inCombat = true, inRange = true }, "Nothing", false, false },
            { "13 fire here", { inRange = true, inRest = true, mounted = true }, "FireHere", true, true },
            { "14 dead", { dead = true, onTaxi = true, inRest = true }, "Nothing", false, false },
            { "15 flight path", { onTaxi = true }, "Nothing", false, false },
            { "16 rest area", { inRest = true }, "Nothing", false, false },
            { "17 mounted, box off", { mounted = true, settings = { GrayWhileMounted = false } }, "Nothing", false, false },
            { "18 gray off", { settings = { ShowMissing = false } }, "Nothing", false, false },
            { "19 no camp", {}, "NoCamp", true, false },
        }
        for _, case in ipairs(cases) do
            local moment, shape, alert = Rules.SelectMoment(inputs(case[2]))
            assert.equals(case[3], moment, "moment, row " .. case[1])
            assert.equals(case[4], shape, "shape, row " .. case[1])
            assert.equals(case[5], alert, "alert, row " .. case[1])
        end
    end)

    it("keeps dead and a taxi out of fire near, and dismissal and Simple out of the alert only", function()
        local SIMPLE = { Shape = "SIMPLE" }
        -- case, inputs, moment, shape shows, alert shows, fire near
        local cases = {
            { "dead, no buff", { inRange = true, dead = true }, "Nothing", false, false, false },
            { "taxi, no buff", { inRange = true, onTaxi = true }, "Nothing", false, false, false },
            { "dead, buff low", up({ inRange = true, dead = true, left = 240 }), "Low", true, false, false },
            { "taxi, buff low", up({ inRange = true, onTaxi = true, left = 240 }), "Low", true, false, false },
            { "dismissed, passing", up({ inRange = true, left = 240, dismissed = true }), "Passing", true, false, true },
            { "alert off, passing", up({ inRange = true, left = 240, settings = { AlertEnabled = false } }),
                "Passing", true, false, true },
            { "combat, passing", up({ inRange = true, left = 240, inCombat = true }), "Passing", true, false, true },
            { "dismissed, fire here", { inRange = true, dismissed = true }, "FireHere", true, false, true },
            { "simple, fire here", { inRange = true, settings = SIMPLE }, "FireHere", true, false, true },
            { "simple, passing", up({ inRange = true, left = 240, settings = SIMPLE }), "Passing", true, true, true },
        }
        for _, case in ipairs(cases) do
            local moment, shape, alert, near = Rules.SelectMoment(inputs(case[2]))
            assert.equals(case[3], moment, "moment, " .. case[1])
            assert.equals(case[4], shape, "shape, " .. case[1])
            assert.equals(case[5], alert, "alert, " .. case[1])
            assert.equals(case[6], near, "near, " .. case[1])
        end

        -- fire near, switch on, in combat, a click sits
        local clicks = {
            { true, true, false, true },
            { false, true, false, false },
            { true, false, false, false },
            { true, true, true, false },
        }
        for index, case in ipairs(clicks) do
            assert.equals(case[4], Rules.SitClickable(case[1], { ClickToSit = case[2] }, case[3]), "click, case " .. index)
        end
    end)

    it("shows time to spare from the minimum gain, only with the refill proven and above the alert", function()
        local reached = 3600 - Rules.MIN_SIT_GAIN
        -- case, inputs, moment, alert shows
        local cases = {
            { "gain reached", up({ inRange = true, left = reached }), "Spare", false },
            { "one second short", up({ inRange = true, left = reached + 1 }), "Road", false },
            { "refill unproven", up({ inRange = true, left = reached, refillProven = false }), "Road", false },
            { "refill unproven, far gain", up({ inRange = true, left = 1000, refillProven = false }), "Road", false },
            { "under the alert", up({ inRange = true, left = 600 }), "Passing", true },
        }
        for _, case in ipairs(cases) do
            local moment, _, alert = Rules.SelectMoment(inputs(case[2]))
            assert.equals(case[3], moment, "moment, " .. case[1])
            assert.equals(case[4], alert, "alert, " .. case[1])
        end
    end)

    it("counts the seconds until the gain is reached, and nothing once it is or without the refill", function()
        local reached = 3600 - Rules.MIN_SIT_GAIN
        assert.equals(100, Rules.SitGainReachedIn(reached + 100, 3600, true))
        assert.is_nil(Rules.SitGainReachedIn(reached, 3600, true))
        assert.is_nil(Rules.SitGainReachedIn(reached - 100, 3600, true))
        assert.is_nil(Rules.SitGainReachedIn(reached + 100, 3600, false))
        assert.equals(500, Rules.SitGain(3100, 3600))
    end)

    it("applies the Show In boxes, with a fire near overriding all but combat", function()
        -- case, inputs, moment, alert shows
        local cases = {
            { "gray, rest box off", { inRest = true }, "Nothing", false },
            { "gray, rest box on", { inRest = true, settings = { GrayInRestAreas = true } }, "NoCamp", false },
            { "gray, mount box off", { mounted = true, settings = { GrayWhileMounted = false } }, "Nothing", false },
            { "gray, mount box on", { mounted = true }, "NoCamp", false },
            { "gray, near beats rest", { inRange = true, inRest = true }, "FireHere", true },
            { "gray, near beats mount", { inRange = true, mounted = true, settings = { GrayWhileMounted = false } },
                "FireHere", true },
            { "low, rest box on", up({ left = 240, inRest = true }), "Low", false },
            { "low, rest box off", up({ left = 240, inRest = true, settings = { TimerInRestAreas = false } }),
                "Road", false },
            { "low, mount box on", up({ left = 240, mounted = true }), "Low", false },
            { "low, mount box off", up({ left = 240, mounted = true, settings = { TimerWhileMounted = false } }),
                "Road", false },
            { "shown, rest box off", up({ inRest = true, settings = { ShowAlways = true, TimerInRestAreas = false } }),
                "Road", false },
            { "shown, mount box off", up({ mounted = true, settings = { ShowAlways = true, TimerWhileMounted = false } }),
                "Road", false },
            { "low, near beats rest", up({ inRange = true, left = 240, inRest = true,
                refillProven = false, settings = { AlertUnderMinutes = 1, TimerInRestAreas = false } }), "Low", false },
            { "low, near beats mount", up({ inRange = true, left = 240, mounted = true,
                refillProven = false, settings = { AlertUnderMinutes = 1, TimerWhileMounted = false } }), "Low", false },
            { "alert ignores the boxes", up({ inRange = true, left = 240, inRest = true,
                settings = { TimerInRestAreas = false } }), "Passing", true },
        }
        for _, case in ipairs(cases) do
            local moment, _, alert = Rules.SelectMoment(inputs(case[2]))
            assert.equals(case[3], moment, "moment, " .. case[1])
            assert.equals(case[4], alert, "alert, " .. case[1])
        end

        -- moment out of combat, inputs: with the box off, combat alone hides each.
        local timerMoments = {
            { "Sitting", up({ seated = true }) },
            { "Sitting", up({ seated = true, inRange = true }) },
            { "Landing", up({ landing = true }) },
            { "Landing", up({ landing = true, inRange = true }) },
            { "Passing", up({ inRange = true, left = 240 }) },
            { "Spare", up({ inRange = true }) },
            { "Low", up({ left = 240 }) },
            { "Low", up({ left = 240, inRange = true, dead = true }) },
            { "Shown", up({ settings = { ShowAlways = true } }) },
        }
        for index, case in ipairs(timerMoments) do
            local over = case[2]
            over.settings = over.settings or {}
            over.settings.TimerInCombat = false
            assert.equals(case[1], (Rules.SelectMoment(inputs(over))), "out of combat, case " .. index)
            over.inCombat = true
            assert.equals("Nothing", (Rules.SelectMoment(inputs(over))), "in combat, case " .. index)
            over.held = true
            assert.equals("Nothing", (Rules.SelectMoment(inputs(over))), "held, case " .. index)
        end
    end)

    it("colors the ring by time left and counts down to the next color", function()
        -- left, key, seconds to the next step
        local cases = {
            { 1801, "good", 1 },
            { 1800, "warn", 1500 },
            { 301, "warn", 1 },
            { 300, "bad", nil },
            { 10, "bad", nil },
        }
        for _, case in ipairs(cases) do
            assert.equals(case[2], Rules.RingColorKey(case[1], false), "key, left " .. case[1])
            assert.equals(case[3], Rules.NextColorStepIn(case[1]), "step, left " .. case[1])
        end
        assert.equals("seated", Rules.RingColorKey(10, true))
    end)

    it("reads bonus lines and builds one row per feature from them", function()
        local thing = { id = 1, short = "Thing" }
        local well = { id = 2, short = "Well", period = 5, numbers = 2 }
        local index = { thing = thing, well = well }
        -- line, feature, amounts
        local lines = {
            { "Thing: +56 Stamina", thing, { 56 } },
            { "|cff00ff00Thing|r: +1,234 Armor", thing, { 1234 } },
            { "Thing: +2.5% Crit", thing, { 2.5 } },
            { "Thing\239\188\154 +7", thing, { 7 } },
            { "Well: +29 Mana every 5 sec", well, { 29, 5 } },
            { "Well: every 5 sec, +29 Mana", well, { 29, 5 } },
            { "Somebody Else: hello", nil, nil },
            { "Spell ID: 1229741", nil, nil },
            { "12 things: +3", nil, nil },
            { "no colon here", nil, nil },
        }
        for _, case in ipairs(lines) do
            local feature, amounts = Rules.ParseBonusLine(case[1], index)
            assert.equals(case[2], feature, "feature, " .. case[1])
            assert.same(case[3], amounts, "amounts, " .. case[1])
        end

        local tip = {
            { feature = thing, amounts = { 56 } },
            { feature = well, amounts = { 29, 5 } },
            { feature = well, amounts = { 99, 5 } },
            { feature = { id = 3 }, amounts = { 1 } },
        }
        local function summary(rows)
            local out = {}
            for i, row in ipairs(rows) do out[i] = { row.id, row.amounts } end
            return out
        end
        assert.same({ { 1, { 56 } }, { 2, { 29, 5 } } },
            summary(Rules.TipRows({ thing, well }, tip)), "first line of a feature wins, an unknown feature drops")
        assert.same({}, summary(Rules.TipRows({ thing, well }, {})), "nothing read")
    end)

    it("finds new and kept rows against the held set", function()
        local function row(id, amount) return { id = id, amounts = { amount } } end
        local function ids(rows)
            local out = {}
            for i, r in ipairs(rows) do out[i] = r.id end
            return out
        end
        -- case, held, now, new ids, kept ids
        local cases = {
            { "nothing held", {}, { row(1, 5), row(2, 5) }, { 1, 2 }, {} },
            { "absent is new", { row(1, 5) }, { row(1, 5), row(2, 5) }, { 2 }, { 1 } },
            { "higher is new", { row(1, 5) }, { row(1, 6) }, { 1 }, {} },
            { "same is kept", { row(1, 5) }, { row(1, 5) }, {}, { 1 } },
            { "lower is kept", { row(1, 5) }, { row(1, 4) }, {}, { 1 } },
            { "unread is kept", { row(1, 5), row(2, 5) }, { row(1, 5) }, {}, { 1, 2 } },
            { "nothing read", { row(1, 5) }, {}, {}, { 1 } },
        }
        for _, case in ipairs(cases) do
            local newRows, keptRows = Rules.NewBonuses(case[2], case[3])
            assert.same(case[4], ids(newRows), "new, " .. case[1])
            assert.same(case[5], ids(keptRows), "kept, " .. case[1])
        end
    end)

    -- A feature a class buff can cover and one none can, found so no id is pinned.
    local function coverIds()
        local covered, never
        for _, feature in ipairs(Rules.FEATURES) do
            if Rules.COVERED_BY[feature.id] then covered = covered or feature.id else never = never or feature.id end
        end
        return covered, never
    end

    local function plainRow(id)
        return { id = id, amounts = { 1 } }
    end

    it("names what covers a feature, and nothing when it is not on you or nothing can", function()
        local covered, never = coverIds()
        local onYou = { [Rules.COVERED_BY[covered][1]] = "Cover Name" }
        assert.equals("Cover Name", Rules.Coverer(covered, onYou))
        assert.is_nil(Rules.Coverer(covered, {}))
        assert.is_nil(Rules.Coverer(never, onYou))
    end)

    it("orders lines new, then plain, then covered, a covered new row as covered and dim", function()
        local rows = {
            { name = "plain" },
            { name = "covered", coverer = "X" },
            { name = "new one", isNew = true },
            { name = "covered new", isNew = true, coverer = "X" },
            { name = "new two", isNew = true },
            { name = "plain two" },
        }
        local out = {}
        for i, row in ipairs(Rules.OrderLines(rows)) do out[i] = row.name end
        assert.same({ "new one", "new two", "plain", "plain two", "covered", "covered new" }, out)

        local covered, never = coverIds()
        local onYou = { [Rules.COVERED_BY[covered][1]] = "Cover Name" }
        local function styles(dim)
            local newRows = { plainRow(never), plainRow(covered) }
            local keptRows = { plainRow(never), plainRow(covered) }
            local looks = {}
            for i, line in ipairs(Rules.BuildLines(newRows, keptRows, dim, onYou, "kept")) do looks[i] = line.style end
            return looks
        end
        assert.same({ "new", "kept", "dim", "dim" }, styles(true))
        assert.same({ "new", "new", "kept", "kept" }, styles(false))
    end)

    it("words the alert so left and added sum to the duration", function()
        -- left, duration, refill proven, text
        local cases = {
            { 720, 3600, true, "12m left, sit for +48m" },
            { 720, 5400, true, "12m left, sit for +78m" },
            { 661, 3600, true, "12m left, sit for +48m" },
            { 3600, 3600, true, "60m left" },
            { 720, 3600, false, "12m left" },
        }
        for _, case in ipairs(cases) do
            assert.equals(case[4], (Rules.AlertLine(case[1], case[2], case[3])), "left " .. case[1])
        end

        -- expiry, left, the time the minute text next changes
        local ends = { { 1000, 720, 340 }, { 1000, 661, 340 }, { 1000, 660, 400 }, { 1000, 30, 1000 } }
        for _, case in ipairs(ends) do
            assert.equals(case[3], Rules.AlertMinuteEnd(case[1], case[2]), "minute end, left " .. case[2])
        end
    end)

    it("lands on a new or longer expiry after sitting, not on the same expiry, and only for its window", function()
        -- case, previous, now, lands
        local cases = {
            { "longer after seated", { seated = true, expiry = 100 }, { expiry = 500 }, true },
            { "new after seated", { seated = true }, { expiry = 500 }, true },
            { "same expiry, stood up early or a sit with no refill", { seated = true, expiry = 100 }, { expiry = 100 }, false },
            { "no buff yet", { seated = true }, {}, false },
            { "first read, not seated", {}, { expiry = 500 }, false },
            { "longer, not seated", { expiry = 100 }, { expiry = 500 }, false },
        }
        for _, case in ipairs(cases) do
            assert.equals(case[4], Rules.IsLanding(case[2], case[3]), case[1])
        end

        -- previous read, this read, the expiry every comparison sees
        local steady = { { 100, 100.4, 100 }, { 100, 99.6, 100 }, { 100, 500, 500 }, { nil, 500, 500 } }
        for _, case in ipairs(steady) do
            assert.equals(case[3], Rules.SteadyExpiry(case[1], case[2]))
        end
        assert.is_nil(Rules.SteadyExpiry(100, nil))

        assert.is_true(Rules.LandingActive(100, 99))
        assert.is_false(Rules.LandingActive(100, 100))
        assert.is_false(Rules.LandingActive(100, 101))
        assert.is_false(Rules.LandingActive(nil, 99))
    end)

    it("picks the best carried kit and at most one button", function()
        local function countOf(id) return id == 2 and 1 or (id == 3 and 2 or 0) end
        local function usableOf(id) return id ~= 2 end
        assert.equals(3, Rules.BestKit({ 1, 2, 3 }, countOf, usableOf))
        assert.equals(2, Rules.BestKit({ 1, 2, 3 }, countOf, function() return true end))
        assert.is_nil(Rules.BestKit({ 1 }, countOf, usableOf))

        local on = { BagButton = true, KitButton = true }
        local both = { bag = true, kit = 3 }
        -- case, moment, near or seated, combat, settings, carried, rest low, button
        local cases = {
            { "bag at a fire", "Passing", true, false, on, both, false, "bag" },
            { "bag on the road", "Road", true, false, on, both, false, "bag" },
            { "bag seated", "Sitting", true, false, on, both, false, "bag" },
            { "no bag away from a fire", "Road", false, false, on, both, false, nil },
            { "bag away from a fire, rest low", "Road", false, false, on, both, true, "bag" },
            { "kit in no camp", "NoCamp", false, false, on, both, false, "kit" },
            { "kit wins over a low rest", "NoCamp", false, false, on, both, true, "kit" },
            { "bag when no kit is carried", "NoCamp", false, false, on, { bag = true }, true, "bag" },
            { "kit not at a fire", "FireHere", true, false, { KitButton = true }, both, false, nil },
            { "refused in combat", "Passing", true, true, on, both, false, nil },
            { "kit refused in combat", "NoCamp", false, true, on, both, false, nil },
            { "low rest refused in combat", "Road", false, true, on, both, true, nil },
            { "bag not carried", "Passing", true, false, on, { kit = 3 }, false, nil },
            { "kit not carried", "NoCamp", false, false, on, { bag = true }, false, nil },
            { "bag box off", "Passing", true, false, { KitButton = true }, both, false, nil },
            { "low rest, bag box off", "Road", false, false, { KitButton = true }, both, true, nil },
            { "kit box off", "NoCamp", false, false, { BagButton = true }, both, false, nil },
        }
        for _, case in ipairs(cases) do
            assert.equals(case[8], Rules.ButtonWanted(case[2], case[3], case[4], case[5], case[6], case[7]), case[1])
        end

        -- No candidate means no inventory read at all.
        local function candidates(...) return { Rules.ButtonCandidates(...) } end
        assert.same({ "bag" }, candidates("Road", true, false, on, true))
        assert.same({ "kit", "bag" }, candidates("NoCamp", false, false, on, true))
        assert.same({ "bag" }, candidates("Road", false, false, on, true))
        assert.same({}, candidates("Road", false, false, on, false))
        assert.same({}, candidates("Passing", true, false, { KitButton = true }, true))
        assert.same({}, candidates("NoCamp", false, false, { BagButton = true }, false))
        assert.same({}, candidates("NoCamp", false, true, on, true))

        assert.is_true(Rules.RestLow(nil))
        assert.is_true(Rules.RestLow(Rules.REST_LOW_AT))
        assert.is_false(Rules.RestLow(Rules.REST_LOW_AT + 1))
    end)

    it("fills a checklist dot by presence and stacks", function()
        assert.equals("on", Rules.DotState(true))
        assert.equals("part", Rules.DotState(true, 1, 3))
        assert.equals("on", Rules.DotState(true, 3, 3))
        assert.equals("off", Rules.DotState(false, 1, 3))
    end)
end)
