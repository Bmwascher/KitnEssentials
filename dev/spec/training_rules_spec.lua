-- Tier 1: What's Training's pure rules (Modules/QoL/WhatsTraining/TrainingRules.lua).
-- The generated class tables are never pinned here: every row is built in the case.
local helpers = require("dev.spec._helpers")

local Rules = helpers.loadModule("Modules/QoL/WhatsTraining/TrainingRules.lua").TrainingRules

local function never() return false end

local function paint(key, text)
    return "<" .. key .. ":" .. text .. ">"
end

local PLAN_ROWS = {
    { 10, 1, 100 },
    { 10, 2, 200, needs = 9 },
    { 10, 3, 0, quest = true },
    { 11, 4, 300 },
    { 12, 5, 0 },
    { 20, 6, 400 },
    { 20, 7, 500 },
    { 30, 8, 600 },
    { 10, 10, 700, talent = 99 },
    { 10, 11, 800 },
    { 5, 12, 900 },
    { 10, 13, 1000, races = { 2 } },
}

local function planFor(gold, prices)
    return Rules.Plan(PLAN_ROWS, {
        level = 10, race = 1, gold = gold, skipped = { [11] = true }, prices = prices or {},
        isKnown = function(id) return id == 12 end,
    })
end

local function simplePlan(rows, level, gold)
    return Rules.Plan(rows, { level = level, race = 1, gold = gold, skipped = {}, prices = {}, isKnown = never })
end

describe("What's Training rules", function()
    it("BuildStep has a built table in or out of combat, waits in combat, and builds otherwise", function()
        for _, row in ipairs({
            { built = true, combat = false, want = "have" },
            { built = true, combat = true, want = "have" },
            { built = false, combat = true, want = "wait" },
            { built = false, combat = false, want = "build" },
        }) do
            assert.equals(row.want, Rules.BuildStep(row.built, row.combat))
        end
    end)

    it("ReadService finds the kind, icon and level in either value order, and the rank text fifth", function()
        for _, row in ipairs({
            { name = "standard", args = { "Rend", "available", 132155, 4, "Rank 1" }, kind = "available", icon = 132155, level = 4, rank = "Rank 1" },
            { name = "other order", args = { "Rend", 132155, "available", 4 }, kind = "available", icon = 132155, level = 4 },
            { name = "missing kind", args = { "Rend", "Rank 1", 132155, 4 }, icon = 132155, level = 4 },
            { name = "header", args = { "Spells", "header" }, kind = "header" },
            { name = "an empty rank text", args = { "Growl", "available", 132270, 1, "" }, kind = "available", icon = 132270, level = 1 },
            { name = "a kind in the fifth place", args = { "Growl", 132270, 1, 1, "available" }, kind = "available", icon = 132270, level = 1 },
        }) do
            local name, kind, icon, level, rank = Rules.ReadService(unpack(row.args))
            assert.equals(row.args[1], name, row.name)
            assert.equals(row.kind, kind, row.name)
            assert.equals(row.icon, icon, row.name)
            assert.equals(row.level, level, row.name)
            assert.equals(row.rank, rank, row.name)
        end
    end)

    it("ServiceOpen reads each kind, and a missing kind by level and known", function()
        for _, row in ipairs({
            { kind = "available", level = 10, player = 1, known = false, want = true },
            { kind = "unavailable", level = 1, player = 10, known = false, want = false },
            { kind = "used", level = 1, player = 10, known = true, want = false },
            { kind = "header", level = 1, player = 10, known = false, want = false },
            { level = 12, player = 10, known = false, want = false },
            { level = 10, player = 10, known = false, want = true },
            { level = 10, player = 10, known = true, want = false },
            { level = 0, player = 10, known = false, want = false },
        }) do
            assert.equals(row.want, Rules.ServiceOpen(row.kind, row.level, row.player, row.known))
        end
    end)

    it("ReadPrices matches by name and level, and reports whether anything changed", function()
        local names = { [1] = "Rend", [2] = "Rend", [3] = "Rend", [4] = false }
        local byKey = Rules.SpellsByKey({ { 4, 1 }, { 10, 2 }, { 10, 3 }, { 10, 4 } }, function(id) return names[id] end)
        assert.equals(2, byKey["Rend|10"][2])
        local prices = {}
        assert.is_true(Rules.ReadPrices({
            { name = "Rend", level = 10, cost = 500 },
            { name = "Other", level = 10, cost = 900 },
        }, byKey, prices))
        assert.equals(500, prices[2])
        assert.is_nil(prices[1])
        assert.is_nil(prices[3])
        assert.is_false(Rules.ReadPrices({ { name = "Rend", level = 10, cost = 500 } }, byKey, prices))
        for _, row in ipairs({
            { name = "a zero cost", service = { name = "Rend", level = 10, cost = 0 } },
            { name = "a known service", service = { name = "Rend", level = 10, cost = 900, kind = "used" } },
            { name = "no cost", service = { name = "Rend", level = 10 } },
        }) do
            local none = {}
            assert.is_false(Rules.ReadPrices({ row.service }, byKey, none), row.name)
            assert.is_nil(none[2], row.name)
            assert.is_false(Rules.ReadPrices({ row.service }, byKey, prices), row.name)
            assert.equals(500, prices[2], row.name)
        end
    end)

    it("State gives each state, a quest flag read at a trainer, and the maybe flags", function()
        local knownIds = { [900] = true, [98] = true }
        local function isKnown(id) return knownIds[id] == true end
        for _, row in ipairs({
            { name = "known", row = { 10, 1, 0 }, known = { [1] = true }, want = "known" },
            { name = "skipped", row = { 10, 1, 0 }, skipped = { [1] = true }, want = "skipped" },
            { name = "quest", row = { 10, 1, 0, quest = true }, want = "quest" },
            { name = "quest read", row = { 10, 1, 0, quest = true }, prices = { [1] = 500 }, want = "now" },
            { name = "quest maybe", row = { 10, 1, 0, quest = "maybe" }, want = "now", tag = "Quest or trainer" },
            { name = "talent not known", row = { 10, 1, 0, talent = 800 }, want = "talent" },
            { name = "talent known", row = { 10, 1, 0, talent = 900 }, want = "now" },
            { name = "talent maybe", row = { 10, 1, 0, talent = "maybe" }, want = "now", tag = "May need a talent" },
            { name = "past two levels", row = { 13, 1, 0 }, want = "later" },
            { name = "next two levels", row = { 12, 1, 0 }, want = "soon" },
            { name = "missing rank", row = { 10, 1, 0, needs = 97 }, want = "rank" },
            { name = "rank in the book", row = { 10, 1, 0, needs = 98 }, want = "now" },
            { name = "rank known by a later one", row = { 10, 1, 0, needs = 96 }, known = { [96] = true }, want = "now" },
        }) do
            assert.equals(row.want, Rules.State(row.row, 10, row.known or {}, row.skipped or {}, isKnown, row.prices), row.name)
            assert.equals(row.tag, Rules.Tag(row.row), row.name)
        end
    end)

    it("KnownMap counts a rank as known once a later rank is, or a spell that replaces it", function()
        local rows = { { 1, 1 }, { 2, 2, needs = 1 }, { 3, 3, needs = 2 }, { 4, 4, needs = 3 } }
        local known = Rules.KnownMap(rows, function(id) return id == 3 end)
        assert.is_true(known[1])
        assert.is_true(known[2])
        assert.is_true(known[3])
        assert.is_nil(known[4])

        local function book(id) return id == 40 end
        local replaced = { [4] = { 40 }, [9] = { 90, 40 } }
        for _, row in ipairs({
            { name = "in the book", id = 40, want = true },
            { name = "replaced by a spell in the book", id = 4, want = true },
            { name = "replaced by the second spell listed", id = 9, want = true },
            { name = "replaced by nothing known", id = 2, want = false },
        }) do
            assert.equals(row.want, Rules.Known(row.id, book, replaced), row.name)
        end
        assert.is_false(Rules.Known(4, book, nil))

        local function isKnown(id) return Rules.Known(id, book, replaced) end
        local byReplacement = Rules.KnownMap(rows, isKnown)
        assert.is_true(byReplacement[4])
        assert.is_true(byReplacement[1])
        assert.equals("now", Rules.State({ 10, 5, 0, needs = 9 }, 10, byReplacement, {}, isKnown))
        assert.equals("rank", Rules.State({ 10, 6, 0, needs = 2 }, 10, {}, {}, function(id)
            return Rules.Known(id, never, replaced)
        end))
    end)

    it("ForRace and ForFaction read a list, no list, a Skyborne id and each side", function()
        for _, row in ipairs({
            { races = { 1, 3 }, race = 3, want = true },
            { races = { 1, 3 }, race = 2, want = false },
            { races = { 95, 96 }, race = 96, want = true },
            { race = 2, want = true },
        }) do
            assert.equals(row.want, Rules.ForRace({ 1, 1, 0, races = row.races }, row.race))
        end
        for _, row in ipairs({
            { npc = "A", side = "A", want = true },
            { npc = "A", side = "H", want = false },
            { npc = "AH", side = "H", want = true },
            { npc = "H", want = true },
        }) do
            assert.equals(row.want, Rules.ForFaction({ 1, 0, 0, "n", "t", false, row.npc }, row.side))
        end
    end)

    it("Price orders read over inferred over seed, and race and talent rows neither give nor take", function()
        local rows = {
            { 10, 1, 100 }, { 10, 2, 100 }, { 10, 3, 100, races = { 1 } }, { 10, 4, 100, talent = 9 },
            { 20, 5, 700, races = { 1 } }, { 30, 6, 700, talent = 9 },
        }
        local prices = { [1] = 150, [5] = 90, [6] = 80 }
        local levels = Rules.LevelPrices(rows, prices)
        assert.equals(150, levels[10])
        assert.is_nil(levels[20])
        assert.is_nil(levels[30])
        for _, row in ipairs({
            { name = "read", row = rows[1], copper = 150, mark = "read" },
            { name = "inferred", row = rows[2], copper = 150, mark = "~" },
            { name = "race row keeps its seed", row = rows[3], copper = 100, mark = "~" },
            { name = "talent row keeps its seed", row = rows[4], copper = 100, mark = "~" },
            { name = "seed", row = { 40, 7, 500 }, copper = 500, mark = "~" },
            { name = "cost 0 takes no inferred price", row = { 10, 8, 0 }, copper = 0, mark = "none" },
            { name = "quest", row = { 10, 9, 0, quest = true }, copper = 0, mark = "quest" },
        }) do
            local copper, mark = Rules.Price(row.row, prices, levels)
            assert.equals(row.copper, copper, row.name)
            assert.equals(row.mark, mark, row.name)
        end
        local copper, mark = Rules.Price({ 10, 9, 0, quest = true }, { [9] = 40 }, {})
        assert.equals(40, copper)
        assert.equals("read", mark)
    end)

    it("Sum and Plan give totals, unpriced counts, running figures and the gold line's place", function()
        local copper, approx, unpriced = Rules.Sum({ 1, 2, 3, 4 }, function(id)
            if id == 1 then return 100, "read" end
            if id == 2 then return 50, "~" end
            if id == 3 then return 0, "none" end
            return 0, "quest"
        end)
        assert.equals(150, copper)
        assert.is_true(approx)
        assert.equals(1, unpriced)

        local plan = planFor(5000)
        assert.equals(100, plan.now.copper)
        assert.is_true(plan.now.approx)
        assert.equals(200, plan.rank.copper)
        assert.equals(1, #plan.quest.rows)
        assert.equals(300, plan.soon.copper)
        assert.equals(1, plan.soon.unpriced)
        assert.equals(600, plan.neededBy)
        assert.is_true(plan.neededApprox)
        assert.equals(1, plan.neededUnpriced)
        assert.equals(12, plan.neededLevel)
        assert.equals(2, #plan.later)
        assert.equals(20, plan.later[1].level)
        assert.equals(900, plan.later[1].copper)
        assert.equals(1500, plan.later[1].byThen)
        assert.is_true(plan.later[1].byThenApprox)
        assert.equals(1, plan.later[1].byThenUnpriced)
        assert.equals(2100, plan.later[2].byThen)
        assert.equals(1, #plan.talent.rows)
        assert.equals(800, plan.skipped.copper)
        assert.equals(900, plan.known.copper)
        assert.is_nil(plan.entry[13])
        assert.is_nil(plan.goldAt)

        assert.equals(1, planFor(50).goldAt.id)
        assert.equals(2, planFor(150).goldAt.id)
        assert.equals(20, planFor(1000).goldAt.level)

        local read = planFor(5000, { [1] = 150 })
        assert.equals(150, read.now.copper)
        assert.is_false(read.now.approx)

        local unnamed = Rules.Plan({ { 10, 1, 100 }, { 10, 2, 200 } }, {
            level = 10, race = 1, gold = 0, skipped = {}, prices = {}, isKnown = never,
            nameOf = function(id) return id == 1 and "Rend" or nil end,
            weapons = { { 5, 1 }, { 5, 2 } },
        })
        assert.equals(100, unnamed.now.copper)
        assert.is_nil(unnamed.entry[2])
        assert.equals(1, #unnamed.rows)
        assert.equals(1, #unnamed.weapons)
    end)

    it("TotalText carries the mark and the unpriced count, and never reads 0 for an unpriced total", function()
        local function coins(copper) return tostring(copper) end
        for _, row in ipairs({
            { copper = 100, want = "100" },
            { copper = 100, approx = true, want = "~100" },
            { copper = 100, approx = true, unpriced = 2, want = "~100 + 2 unpriced" },
            { copper = 0, unpriced = 1, want = "1 unpriced" },
            { copper = 0, want = "0" },
        }) do
            assert.equals(row.want, Rules.TotalText(row.copper, row.approx, row.unpriced, coins))
        end
    end)

    it("Milestones, Bars and ReadCount read thresholds at and above the level, and each bar's look", function()
        local plan = simplePlan({ { 35, 1, 100 }, { 45, 2, 200 }, { 55, 3, 300 } }, 10, 150)
        local stops = Rules.Milestones(plan, 10)
        assert.equals(3, #stops)
        assert.equals(100, stops[1].copper)
        assert.equals(300, stops[2].copper)
        assert.equals(600, stops[3].copper)
        assert.equals(2, #Rules.Milestones(plan, 41))
        assert.equals(2, #Rules.Milestones(plan, 50))
        assert.equals(50, Rules.Milestones(plan, 50)[1].level)
        local unpricedStop = Rules.Milestones(simplePlan({ { 35, 1, 100 }, { 36, 2, 0 } }, 10, 150), 10)[1]
        assert.equals(100, unpricedStop.copper)
        assert.is_true(unpricedStop.approx)
        assert.equals(1, unpricedStop.unpriced)

        local bars = Rules.Bars(plan, 150)
        assert.equals(3, #bars)
        assert.equals("covered", bars[1].look)
        assert.equals("short", bars[2].look)
        assert.equals(1, bars[3].height)
        assert.equals(10, Rules.Bars(simplePlan({ { 5, 1, 100 } }, 10, 0), 0)[1].level)
        for _, row in ipairs({
            { name = "only unknown, no gold", rows = { { 35, 1, 0 } }, gold = 0, want = { "unknown" } },
            { name = "known, then unknown", rows = { { 35, 1, 100 }, { 45, 2, 0 } }, gold = 150, want = { "covered", "unknown" } },
            { name = "unknown, then known in reach", rows = { { 35, 1, 0 }, { 45, 2, 100 } }, gold = 150, want = { "unknown", "unknown" } },
            { name = "unknown, then known past the gold", rows = { { 35, 1, 0 }, { 45, 2, 200 } }, gold = 150, want = { "unknown", "short" } },
            { name = "both in one bar, in reach", rows = { { 35, 1, 100 }, { 35, 2, 0 } }, gold = 150, want = { "unknown" } },
            { name = "both in one bar, past the gold", rows = { { 35, 1, 200 }, { 35, 2, 0 } }, gold = 150, want = { "short" } },
        }) do
            local looks = {}
            for index, bar in ipairs(Rules.Bars(simplePlan(row.rows, 10, row.gold), row.gold)) do looks[index] = bar.look end
            assert.same(row.want, looks, row.name)
        end
        for _, row in ipairs({
            { copper = 0, unpriced = 0, gold = 0, want = "covered" },
            { copper = 100, unpriced = 0, gold = 100, want = "covered" },
            { copper = 100, unpriced = 0, gold = 50, want = "short" },
            { copper = 100, unpriced = 1, gold = 100, want = "unknown" },
            { copper = 100, unpriced = 1, gold = 50, want = "short" },
            { copper = 0, unpriced = 1, gold = 0, want = "unknown" },
        }) do
            assert.equals(row.want, Rules.GoldLook(row.copper, row.unpriced, row.gold))
        end

        local read, total = Rules.ReadCount({ { 1, 1 }, { 1, 2 } }, { [1] = 5 })
        assert.equals(1, read)
        assert.equals(2, total)

        local gated = Rules.Plan({ { 10, 1, 100, talent = 50 }, { 10, 2, 100, talent = 60 }, { 10, 3, 100, quest = true }, { 10, 4, 100 } }, {
            level = 10, race = 1, gold = 0, skipped = {}, prices = {},
            isKnown = function(id) return id == 50 or id == 4 end,
        })
        assert.equals(1, #gated.priced)
        assert.equals(1, gated.priced[1][2])
    end)

    it("Balance says what the gold leaves or lacks, with the cost's mark and its unpriced count", function()
        local function coins(copper) return tostring(copper) end
        for _, row in ipairs({
            { name = "spare", copper = 100, gold = 150, short = false, want = "50 spare" },
            { name = "short, marked, unpriced", copper = 300, approx = true, unpriced = 3, gold = 100, short = true, want = "~200 short + 3 unpriced" },
            { name = "even, unpriced", copper = 100, unpriced = 1, gold = 100, short = false, want = "0 spare + 1 unpriced" },
        }) do
            local short, text = Rules.Balance(row.copper, row.approx, row.unpriced, row.gold, coins)
            assert.equals(row.short, short, row.name)
            assert.equals(row.want, text, row.name)
        end
    end)

    it("GoldEnd names where the gold runs out, and Ladder puts that line before the first stop it reaches", function()
        assert.is_nil(Rules.GoldEnd(simplePlan({ { 10, 1, 100 }, { 45, 2, 200 } }, 10, 1000)))
        for _, row in ipairs({
            { name = "this visit", rows = { { 10, 1, 100 } }, gold = 50, level = 10, thisVisit = true },
            { name = "a missing rank below the level", rows = { { 8, 1, 100, needs = 9 } }, gold = 50, level = 10, thisVisit = false },
            { name = "the next two levels", rows = { { 11, 1, 100 } }, gold = 50, level = 11, thisVisit = false },
            { name = "a later level", rows = { { 10, 1, 100 }, { 45, 2, 200 } }, gold = 150, level = 45, thisVisit = false },
        }) do
            local level, thisVisit = Rules.GoldEnd(simplePlan(row.rows, 10, row.gold))
            assert.equals(row.level, level, row.name)
            assert.equals(row.thisVisit, thisVisit, row.name)
        end

        local stops = { { level = 40 }, { level = 50 }, { level = 60 } }
        for _, row in ipairs({
            { name = "gold enough", want = { 40, 50, 60 } },
            { name = "in this visit", endLevel = 10, want = { "end 10", 40, 50, 60 } },
            { name = "at a stop's own level", endLevel = 40, want = { "end 40", 40, 50, 60 } },
            { name = "between stops", endLevel = 46, want = { 40, "end 46", 50, 60 } },
        }) do
            local lines = {}
            for index, line in ipairs(Rules.Ladder(stops, row.endLevel)) do
                lines[index] = line.goldEnd and ("end " .. line.goldEnd) or line.level
            end
            assert.same(row.want, lines, row.name)
        end
    end)

    it("Skip leaves totals and default ticks, covers all ranks by name, and stops", function()
        local rows = { { 10, 1, 100 }, { 10, 2, 200 }, { 10, 3, 300 } }
        local names = { "Rend", "Rend", "Cleave" }
        local function nameOf(id) return names[id] end
        local skipped = {}
        Rules.SkipAll(rows, "Rend", nameOf, skipped, true)
        assert.is_true(skipped[1])
        assert.is_true(skipped[2])
        assert.is_nil(skipped[3])
        local plan = Rules.Plan(rows, { level = 10, race = 1, gold = 0, skipped = skipped, prices = {}, isKnown = never })
        assert.equals(300, plan.now.copper)
        assert.equals(300, plan.skipped.copper)
        assert.is_false(Rules.DefaultTick({ id = 1 }, skipped))
        Rules.SkipAll(rows, "Rend", nameOf, skipped, nil)
        assert.is_nil(skipped[1])
        assert.is_true(Rules.DefaultTick({ id = 1 }, skipped))
    end)

    it("Search is plain and lowercase, with later rows included", function()
        local rows = { { 10, 1 }, { 50, 2 }, { 10, 3 } }
        local names = { "Rend", "Rend (a)", "Cleave" }
        local function nameOf(id) return names[id] end
        assert.equals(2, #Rules.Search(rows, "REN", nameOf))
        assert.equals(2, Rules.Search(rows, "(a", nameOf)[1][2])
        assert.equals(0, #Rules.Search(rows, "nothing", nameOf))
    end)

    it("RankGain finds the first number that grew, past times and distances", function()
        for _, row in ipairs({
            { name = "growing", old = "Deals 10 damage.", new = "Deals 31 damage.", want = "+21 damage" },
            { name = "a range", old = "Causes 10 to 12 Fire damage.", new = "Causes 16 to 18 Fire damage.", want = "+6 Fire damage" },
            { name = "time ignored", old = "Stuns for 3 sec and deals 5 damage.", new = "Stuns for 4 sec and deals 9 damage.", want = "+4 damage" },
            { name = "distance ignored", old = "Reach 10 yards, adds 5 armor.", new = "Reach 15 yards, adds 9 armor.", want = "+4 armor" },
            { name = "words before", old = "Increases attack power by 55.", new = "Increases attack power by 70.", want = "+15 attack power" },
            { name = "percent", old = "Reduces damage by 5% for 3 sec.", new = "Reduces damage by 8% for 3 sec.", want = "+3%" },
            { name = "thousands", old = "Deals 1,000 damage.", new = "Deals 2,000 damage.", want = "+1000 damage" },
            { name = "millions", old = "Deals 1,000,000 damage.", new = "Deals 1,250,000 damage.", want = "+250000 damage" },
            { name = "misaligned", old = "Deals 10 damage.", new = "Deals 31 damage and stuns." },
            { name = "nothing grew", old = "Deals 10 damage.", new = "Deals 10 damage." },
            { name = "not loaded", new = "Deals 10 damage." },
        }) do
            assert.equals(row.want, Rules.RankGain(row.old, row.new), row.name)
        end
    end)

    it("PanelSide picks right, left, then a pin, with the float tie on the right", function()
        for _, row in ipairs({
            { left = 100, right = 400, want = "right" },
            { left = 400, right = 100, want = "left" },
            { left = 100, right = 200, want = "pinRight" },
            { left = 300, right = 100, want = "pinLeft" },
            { left = 150.4, right = 150, want = "pinRight" },
        }) do
            assert.equals(row.want, Rules.PanelSide(row.left, row.right, 308))
        end
    end)

    it("StaysClosed holds a closing only while a trainer visit or the book window lasts", function()
        for _, row in ipairs({
            { name = "not closed", closed = false, atTrainer = true, bookWindow = true, want = false },
            { name = "at a trainer", closed = true, atTrainer = true, bookWindow = false, want = true },
            { name = "with the book window", closed = true, atTrainer = false, bookWindow = true, want = true },
            { name = "with both", closed = true, atTrainer = true, bookWindow = true, want = true },
            { name = "with neither", closed = true, atTrainer = false, bookWindow = false, want = false },
        }) do
            assert.equals(row.want, Rules.StaysClosed(row.closed, row.atTrainer, row.bookWindow), row.name)
        end
    end)

    it("AfterTrainer keeps a closing only for a book window left open, and otherwise keeps a panel with a bar line open", function()
        for _, row in ipairs({
            { name = "closed, book window, bar line", closed = true, staysOpen = true, bookWindow = true, keep = true, alone = false },
            { name = "closed, book window, no bar line", closed = true, staysOpen = false, bookWindow = true, keep = true, alone = false },
            { name = "closed, no book window, bar line", closed = true, staysOpen = true, bookWindow = false, keep = false, alone = false },
            { name = "closed, no book window, no bar line", closed = true, staysOpen = false, bookWindow = false, keep = false, alone = false },
            { name = "open, book window, bar line", closed = false, staysOpen = true, bookWindow = true, keep = false, alone = true },
            { name = "open, no book window, bar line", closed = false, staysOpen = true, bookWindow = false, keep = false, alone = true },
            { name = "open, no bar line", closed = false, staysOpen = false, bookWindow = true, keep = false, alone = false },
        }) do
            local keep, alone = Rules.AfterTrainer(row.closed, row.staysOpen, row.bookWindow)
            assert.equals(row.keep, keep, row.name)
            assert.equals(row.alone, alone, row.name)
        end
    end)

    it("PanelHost keeps a closed panel hidden, whatever else could host it", function()
        for _, row in ipairs({
            { name = "at a trainer", s = { atTrainer = true, trainerWindow = true }, want = "trainer" },
            { name = "closed at a trainer", s = { atTrainer = true, trainerWindow = true, closed = true } },
            { name = "closed at a trainer, with the book open", s = { atTrainer = true, trainerWindow = true, closed = true, bookOpen = true, openWithBook = true } },
            { name = "closed beside the book", s = { closed = true, bookOpen = true, openWithBook = true } },
            { name = "closed, the book on another tab", s = { closed = true, openWithBook = true } },
            { name = "under the gamepad interface", s = { atTrainer = true, trainerWindow = true, gamepad = true, alone = true }, want = "alone" },
            { name = "the book", s = { bookOpen = true, openWithBook = true }, want = "book" },
            { name = "the book, setting off", s = { bookOpen = true } },
            { name = "alone", s = { alone = true }, want = "alone" },
            { name = "nothing", s = {} },
        }) do
            assert.equals(row.want, Rules.PanelHost(row.s), row.name)
        end
    end)

    it("a closing outlives the book's tabs and ends with the book window or the visit", function()
        local function host(closed, spellTab)
            return Rules.PanelHost({ closed = closed, bookOpen = spellTab, openWithBook = true })
        end
        -- Closed at a trainer with the book open, the tab changed, then the trainer closed.
        local closed = Rules.StaysClosed(true, true, true)
        closed = Rules.AfterTrainer(closed, false, true)
        assert.is_nil(host(closed, false))
        assert.is_nil(host(closed, true))
        closed = Rules.StaysClosed(closed, false, false)
        assert.equals("book", host(closed, true))
        -- The book window closed during the visit: only the trainer's closing ends it.
        closed = Rules.StaysClosed(true, true, true)
        closed = Rules.StaysClosed(closed, true, false)
        assert.is_true(closed)
        closed = Rules.AfterTrainer(closed, true, false)
        assert.is_false(closed)
    end)

    it("BookButtonSetting turns the setting on for a hidden panel and flips it for a shown one", function()
        for _, row in ipairs({
            { name = "hidden, setting on", shown = false, setting = true, want = true },
            { name = "hidden, setting off", shown = false, setting = false, want = true },
            { name = "shown, setting on", shown = true, setting = true, want = false },
            { name = "shown, setting off", shown = true, setting = false, want = true },
        }) do
            assert.equals(row.want, Rules.BookButtonSetting(row.shown, row.setting), row.name)
        end
    end)

    it("one click on the Training button shows a hidden panel, whatever hid it", function()
        for _, row in ipairs({
            { name = "closed beside the book", s = { bookOpen = true, openWithBook = true, closed = true }, want = "book" },
            { name = "closed beside the book, setting off", s = { bookOpen = true, openWithBook = false, closed = true }, want = "book" },
            { name = "setting off", s = { bookOpen = true, openWithBook = false }, want = "book" },
            { name = "closed at a trainer", s = { atTrainer = true, trainerWindow = true, bookOpen = true, openWithBook = true, closed = true }, want = "trainer" },
            { name = "closed at a trainer, setting off", s = { atTrainer = true, trainerWindow = true, bookOpen = true, openWithBook = false, closed = true }, want = "trainer" },
        }) do
            row.s.openWithBook = Rules.BookButtonSetting(false, row.s.openWithBook)
            row.s.closed = false
            assert.equals(row.want, Rules.PanelHost(row.s), row.name)
        end
    end)

    it("PlaceStep gives the book no new anchor in combat", function()
        for _, row in ipairs({
            { host = "trainer", combat = true, onHost = false, want = "place" },
            { host = "alone", combat = true, onHost = false, want = "place" },
            { host = "book", combat = false, onHost = false, want = "place" },
            { host = "book", combat = false, onHost = true, want = "place" },
            { host = "book", combat = true, onHost = true, want = "keep" },
            { host = "book", combat = true, onHost = false, want = "alone" },
            { host = "alone", combat = true, onHost = true, want = "keep" },
            { host = "trainer", combat = true, onHost = true, want = "keep" },
            { host = "alone", combat = false, onHost = true, want = "place" },
        }) do
            assert.equals(row.want, Rules.PlaceStep(row.host, row.combat, row.onHost))
        end
    end)

    it("Offers, DefaultTick and CanTick read a window with or without class rows", function()
        local byKey = Rules.SpellsByKey({ { 4, 100, 0 }, { 10, 101, 0, needs = 100 } }, function() return "Rend" end)
        local open, waiting = Rules.Offers({
            { index = 1, name = "Rend", level = 4, kind = "available", icon = 1, cost = 100, rank = "Rank 1" },
            { index = 2, name = "Rend", level = 10, kind = "unavailable", cost = 200 },
            { index = 3, name = "Mining", level = 0, kind = "available", cost = 50, isProfession = true },
            { index = 4, name = "Used", level = 1, kind = "used" },
            { index = 5, name = "Head", kind = "header" },
            { index = 6, name = "No Row", level = 1, kind = "available", cost = 10 },
            { index = 7, name = "No Cost", level = 1, kind = "available" },
        }, { byKey = byKey, known = {}, level = 10 })
        assert.equals(4, #open)
        assert.is_nil(open[4].cost)
        assert.equals(1, #waiting)
        assert.equals(100, open[1].id)
        assert.equals("Rend|4", open[1].key)
        assert.equals(100, waiting[1].needs)
        assert.is_nil(open[3].id)
        assert.equals(10, open[3].cost)
        assert.equals("Rank 1", open[1].rank)
        assert.is_nil(open[3].rank)

        assert.is_true(Rules.DefaultTick(open[1], {}))
        assert.is_false(Rules.DefaultTick(open[1], { [100] = true }))
        assert.is_false(Rules.DefaultTick(open[2], {}))
        assert.is_true(Rules.DefaultTick(open[3], {}))
        assert.is_false(Rules.CanTick(open[2], 0))
        assert.is_true(Rules.CanTick(open[2], 1))
        assert.is_true(Rules.CanTick(open[1], 0))
    end)

    it("TickAll gives each open service its opening tick, or clears every one", function()
        local offers = { { key = "a", id = 1 }, { key = "b", id = 2 }, { key = "c", isProfession = true }, { key = "d" } }
        for _, row in ipairs({
            { name = "tick all", on = true, want = { a = true, b = false, c = false, d = true } },
            { name = "untick all", on = false, want = { a = false, b = false, c = false, d = false } },
        }) do
            local ticks = { a = false, b = true, c = true, d = false, other = true }
            Rules.TickAll(offers, row.on, { [2] = true }, 1, ticks)
            for key, want in pairs(row.want) do assert.equals(want, ticks[key], row.name .. ", " .. key) end
            assert.is_true(ticks.other, row.name .. ", a key no offer holds")
        end
    end)

    it("BuyPlan keeps to the budget and slots, and BuyOrder runs last index first", function()
        local offers = {
            { index = 1, key = "a", cost = 100 },
            { index = 2, key = "b", cost = 300 },
            { index = 3, key = "c", cost = 50, isProfession = true },
            { index = 4, key = "d", cost = 10 },
            { index = 5, key = "e" },
        }
        local all = { a = true, b = true, c = true, d = true, e = true }
        for _, row in ipairs({
            { name = "budget stops a row past it", ticks = all, budget = 200, slots = 1, want = { 1, 3, 4 }, cost = 160 },
            { name = "no slot", ticks = all, budget = 200, slots = 0, want = { 1, 4 }, cost = 110 },
            { name = "unticked", ticks = { b = true, c = true, d = true }, budget = 200, slots = 1, want = { 3, 4 }, cost = 60 },
            { name = "points as the budget", ticks = all, budget = 410, slots = 0, want = { 1, 2, 4 }, cost = 410 },
        }) do
            local rows, cost = Rules.BuyPlan(offers, row.ticks, row.budget, row.slots)
            assert.equals(row.cost, cost, row.name)
            assert.equals(#row.want, #rows, row.name)
            for i, index in ipairs(row.want) do assert.equals(index, rows[i].index, row.name) end
        end
        local order = Rules.BuyOrder({ { index = 1 }, { index = 3 }, { index = 4 } })
        assert.equals(4, order[1].index)
        assert.equals(1, order[3].index)
    end)

    it("OfferStands buys only the service, kind, level and cost that were quoted", function()
        local offer = { name = "Rend", kind = "available", level = 4, cost = 100 }
        for _, row in ipairs({
            { name = "Rend", kind = "available", level = 4, cost = 100, want = true },
            { name = "Cleave", kind = "available", level = 4, cost = 100, want = false },
            { name = "Rend", kind = "unavailable", level = 4, cost = 100, want = false },
            { name = "Rend", kind = "available", level = 5, cost = 100, want = false },
            { name = "Rend", kind = "available", level = 4, cost = 200, want = false },
            { name = "Rend", kind = "available", level = 4, want = false },
        }) do
            assert.equals(row.want, Rules.OfferStands(offer, row.name, row.kind, row.level, row.cost))
        end
        assert.is_false(Rules.OfferStands({ name = "Rend", kind = "available", level = 4 }, "Rend", "available", 4, nil))
    end)

    it("HasClassOffer finds a service that matched a class row, in either list", function()
        assert.is_true(Rules.HasClassOffer({ { id = 1 } }, {}))
        assert.is_true(Rules.HasClassOffer({ {} }, { { id = 1 } }))
        assert.is_false(Rules.HasClassOffer({ {} }, { {} }))
        assert.is_false(Rules.HasClassOffer({}, {}))
    end)

    it("WaitingText says what a waiting row needs, and invents no rank", function()
        local function isKnown(id) return id == 7 end
        for _, row in ipairs({
            { name = "above the level", offer = { level = 12, needs = 8 }, want = "From level 12" },
            { name = "talent not known", offer = { level = 4, talent = 8, needs = 8 }, want = "Needs a talent" },
            { name = "rank with its text", offer = { level = 4, needs = 8 }, rank = "Rank 2", want = "after Rank 2 above" },
            { name = "rank with no text", offer = { level = 4, needs = 8 }, want = "after the rank above" },
            { name = "rank known", offer = { level = 4, needs = 7 }, want = "Not available yet" },
            { name = "no class row", offer = { level = 4 }, want = "Not available yet" },
            { name = "taught by a quest", offer = { level = 4, needs = 8 }, rank = "Rank 1", earlier = "quest", want = "after Rank 1, taught by a quest" },
            { name = "a quest, no text", offer = { level = 4, needs = 8 }, earlier = "quest", want = "after a rank, taught by a quest" },
            { name = "not in this window", offer = { level = 4, needs = 8 }, rank = "Rank 1", earlier = "elsewhere", want = "after Rank 1" },
            { name = "not in this window, no text", offer = { level = 4, needs = 8 }, earlier = "elsewhere", want = "after an earlier rank" },
        }) do
            assert.equals(row.want, Rules.WaitingText(row.offer, 10, isKnown, row.rank, row.earlier), row.name)
        end
    end)

    it("the data checks take a generated shape, and refuse any field the rules could not read", function()
        local spell, weapon, npc = { 10, 1, 100 }, { 20, 2 }, { 1, 50, 50, "Ann", "Mage Trainer", "MAGE", "A" }
        local function withSpell(row) return { spells = { row }, weapons = {} } end
        local function withWeapon(row) return { spells = {}, weapons = { row } } end
        local function withNpc(row) return { capitals = {}, npcs = { row } } end
        for _, row in ipairs({
            { name = "whole", data = { spells = { spell }, weapons = { weapon } }, want = true },
            { name = "every optional spell field", data = withSpell({ 10, 1, 100, needs = 5, races = { 1 }, quest = true, talent = 9 }), want = true },
            { name = "the maybe flags", data = withSpell({ 10, 1, 100, quest = "maybe", talent = "maybe" }), want = true },
            { name = "a weapon with masters", data = withWeapon({ 20, 2, masters = { "Ann" } }), want = true },
            { name = "replaced spells", data = { spells = { spell }, weapons = {}, replaced = { [1] = { 5 } } }, want = true },
            { name = "replaced keyed by a name", data = { spells = { spell }, weapons = {}, replaced = { x = { 5 } } }, want = false },
            { name = "replaced by no spell", data = { spells = { spell }, weapons = {}, replaced = { [1] = {} } }, want = false },
            { name = "replaced by a name", data = { spells = { spell }, weapons = {}, replaced = { [1] = { "x" } } }, want = false },
            { name = "replaced not a table", data = { spells = { spell }, weapons = {}, replaced = true }, want = false },
            { name = "empty", data = {}, want = false },
            { name = "no weapons", data = { spells = { spell } }, want = false },
            { name = "a row with no cost", data = withSpell({ 10, 1 }), want = false },
            { name = "races not a list", data = withSpell({ 10, 1, 100, races = true }), want = false },
            { name = "races not ids", data = withSpell({ 10, 1, 100, races = { "x" } }), want = false },
            { name = "needs not an id", data = withSpell({ 10, 1, 100, needs = "x" }), want = false },
            { name = "quest not a flag", data = withSpell({ 10, 1, 100, quest = "x" }), want = false },
            { name = "talent not an id", data = withSpell({ 10, 1, 100, talent = {} }), want = false },
            { name = "masters not a list", data = withWeapon({ 20, 2, masters = true }), want = false },
            { name = "masters not names", data = withWeapon({ 20, 2, masters = { 1 } }), want = false },
            { name = "not a table", data = "x", want = false },
        }) do
            assert.equals(row.want, Rules.ClassDataValid(row.data), row.name)
        end
        for _, row in ipairs({
            { name = "whole", data = withNpc(npc), want = true },
            { name = "a weapon master", data = withNpc({ 1, 50, 50, "Bo", "Weapon Master", false, "H" }), want = true },
            { name = "empty", data = {}, want = false },
            { name = "a row with no side", data = withNpc({ 1, 50, 50, "Ann", "t", "MAGE" }), want = false },
            { name = "a row with no title", data = withNpc({ 1, 50, 50, "Ann", nil, "MAGE", "A" }), want = false },
            { name = "a class that is neither", data = withNpc({ 1, 50, 50, "Ann", "t", 1, "A" }), want = false },
            { name = "not a table", data = "x", want = false },
        }) do
            assert.equals(row.want, Rules.RouteDataValid(row.data), row.name)
        end
    end)

    it("LearnLabel says why nothing can be bought, and claims nothing about an unknown price", function()
        for _, row in ipairs({
            { name = "a plan", count = 2, ticked = 3, unknown = 1, want = "Learn 2 for 300" },
            { name = "nothing ticked", count = 0, ticked = 0, unknown = 0, want = "Nothing picked" },
            { name = "only unknown prices", count = 0, ticked = 2, unknown = 2, want = "No priced spell picked" },
            { name = "both, none fits", count = 0, ticked = 2, unknown = 1, want = "No priced spell you can afford" },
            { name = "priced, none fits", count = 0, ticked = 2, unknown = 0, want = "Nothing you can afford" },
        }) do
            assert.equals(row.want, Rules.LearnLabel(row.count, "300", row.ticked, row.unknown), row.name)
        end
    end)

    it("RankSwaps swaps a lower rank, and leaves a lower copy, a kept name and a non-spell slot", function()
        assert.equals(3, Rules.RankNumber("Rank 3"))
        assert.is_nil(Rules.RankNumber(""))
        assert.is_nil(Rules.RankNumber(nil))
        local swaps = Rules.RankSwaps({
            Rend = { id = 3, rank = 3 }, Cleave = { id = 12, rank = 2 }, Shout = { id = 21, rank = 2 },
        }, {
            { slot = 1, kind = "spell", name = "Rend", rank = 1 },
            { slot = 2, kind = "spell", name = "Cleave", rank = 1 },
            { slot = 3, kind = "spell", name = "Cleave", rank = 2 },
            { slot = 4, kind = "macro", name = "Rend", rank = 1 },
            { slot = 5, kind = "spell", name = "Shout", rank = 1 },
        }, { Shout = true })
        assert.equals(1, #swaps)
        assert.equals(1, swaps[1].slot)
        assert.equals(3, swaps[1].id)
        assert.equals("Rend", swaps[1].name)
    end)

    it("NearestStop goes same continent, own capital, shared capital, elsewhere, with ties by name", function()
        local zed = { 1, 10, 10, "Zed", "t", "WARRIOR", "A" }
        local abe = { 2, 20, 20, "Abe", "t", "WARRIOR", "A" }
        local own = { 3, 30, 30, "Own", "t", "WARRIOR", "A" }
        local shared = { 4, 40, 40, "Shared", "t", "WARRIOR", "AH" }
        local horde = { 5, 12, 12, "Horde", "t", "WARRIOR", "H" }
        local positions = {
            [zed] = { continent = 0, x = 10, y = 10 }, [abe] = { continent = 0, x = 20, y = 20 },
            [own] = { continent = 1, x = 30, y = 30 }, [shared] = { continent = 1, x = 40, y = 40 },
            [horde] = { continent = 0, x = 12, y = 12 },
        }
        local function worldPos(npc) return positions[npc] end
        local function isCapital(map) return map == 3 or map == 4 end
        for _, row in ipairs({
            { name = "same continent", npcs = { own, abe, zed, horde }, here = { continent = 0, x = 12, y = 12 }, want = zed },
            { name = "own capital", npcs = { abe, shared, own }, here = { continent = 2, x = 0, y = 0 }, want = own },
            { name = "no position", npcs = { abe, shared, own }, want = own },
            { name = "shared capital", npcs = { abe, shared }, want = shared },
            { name = "tie by name elsewhere", npcs = { zed, abe }, want = abe },
            { name = "tie by name on the continent", npcs = { zed, abe }, here = { continent = 0, x = 15, y = 15 }, want = abe },
            { name = "none of this side", npcs = { horde } },
        }) do
            assert.equals(row.want, Rules.NearestStop(row.npcs, "A", row.here, worldPos, isCapital), row.name)
        end
    end)

    it("ToastLine and ChatLine word every one affordable, some, a mark and one spell", function()
        local function coins(copper) return tostring(copper) end
        local two = simplePlan({ { 10, 1, 100 }, { 10, 2, 200 } }, 10, 0)
        local one = simplePlan({ { 10, 1, 100 } }, 10, 0)
        for _, row in ipairs({
            { name = "all", plan = two, gold = 300, want = "2 spells to train, ~300 in all. You can afford all of them." },
            { name = "some", plan = two, gold = 100, want = "2 spells to train, ~300 in all. You can afford 1 of them." },
            { name = "none", plan = two, gold = 50, want = "2 spells to train, ~300 in all. You cannot afford any of them yet." },
            { name = "one", plan = one, gold = 100, want = "1 spell to train, ~100 in all. You can afford it." },
            { name = "one short", plan = one, gold = 0, want = "1 spell to train, ~100 in all. You cannot afford it yet." },
        }) do
            assert.equals(row.want, Rules.ToastLine(row.plan, row.gold, coins), row.name)
        end
        local read = Rules.Plan({ { 10, 1, 100 } }, { level = 10, race = 1, gold = 0, skipped = {}, prices = { [1] = 90 }, isKnown = never })
        assert.equals("1 spell to train, 90 in all. You can afford it.", Rules.ToastLine(read, 90, coins))
        assert.equals("Level 30. 2 spells to train, ~300.", Rules.ChatLine(30, two, coins))
        local mixed = simplePlan({ { 10, 1, 100 }, { 10, 2, 0 } }, 10, 0)
        local unpriced = simplePlan({ { 10, 1, 0 } }, 10, 0)
        local unpricedTwo = simplePlan({ { 10, 1, 0 }, { 10, 2, 0 } }, 10, 0)
        local mixedTwo = simplePlan({ { 10, 1, 100 }, { 10, 2, 200 }, { 10, 3, 0 } }, 10, 0)
        for _, row in ipairs({
            { name = "priced ones covered", plan = mixed, gold = 100, want = "2 spells to train, ~100 + 1 unpriced in all. You can afford every priced one." },
            { name = "priced ones short", plan = mixed, gold = 50, want = "2 spells to train, ~100 + 1 unpriced in all. You cannot afford any priced one yet." },
            { name = "some priced ones", plan = mixedTwo, gold = 100, want = "3 spells to train, ~300 + 1 unpriced in all. You can afford 1 of the priced ones." },
            { name = "one unpriced", plan = unpriced, gold = 0, want = "1 spell to train, 1 unpriced in all. The trainer shows its price." },
            { name = "all unpriced", plan = unpricedTwo, gold = 0, want = "2 spells to train, 2 unpriced in all. The trainer shows their prices." },
        }) do
            assert.equals(row.want, Rules.ToastLine(row.plan, row.gold, coins), row.name)
        end
        for _, row in ipairs({
            { name = "dear then cheap", rows = { { 10, 1, 200 }, { 10, 2, 50 } }, gold = 100, want = "You can afford 1 of them." },
            { name = "cheap then dear", rows = { { 10, 1, 50 }, { 10, 2, 200 } }, gold = 100, want = "You can afford 1 of them." },
            { name = "a dear row first, two cheap ones fit", rows = { { 10, 1, 90 }, { 10, 2, 40 }, { 10, 3, 40 } }, gold = 100, want = "You can afford 2 of them." },
            { name = "the cheapest does not fit", rows = { { 10, 1, 200 }, { 10, 2, 150 } }, gold = 100, want = "You cannot afford any of them yet." },
        }) do
            local line = Rules.ToastLine(simplePlan(row.rows, 10, 0), row.gold, coins)
            assert.truthy(line:find(row.want, 1, true), row.name)
        end
        assert.equals("Level 30. 1 spell to train, 1 unpriced.", Rules.ChatLine(30, unpriced, coins))
        assert.equals("3<gold:g> 12<silver:s>", Rules.Coins(31200, paint))
        assert.equals("5<copper:c>", Rules.Coins(5, paint))
        assert.equals("0<copper:c>", Rules.Coins(0, paint))
    end)
end)

describe("What's Training defaults", function()
    it("adds a block on a baseline load only, switched off", function()
        local retail = helpers.loadModule("Core/Defaults.lua")
        assert.is_nil(retail:GetDefaultDB().profile.WhatsTraining)
        local baseline = helpers.loadModule("Core/Defaults.lua", { BASELINE_LOAD = true })
        assert.is_false(baseline:GetDefaultDB().profile.WhatsTraining.Enabled)
    end)
end)
