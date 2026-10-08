-- Modules/Dungeons/CCTrackerRules.lua -- the rules a later edit breaks
-- silently: which ids are tracked, the filter each container gets, which
-- plates get a row, the size of the box kept on screen, what Add refuses, and
-- the preview's countdown text.
-- The shipped seed table is data and gets no case; these cases use their own.
local L = require("dev.spec._ke_loader")

local SEEDS = {
    { key = "ALL_FORMS", label = "Form (all)", group = "Mage", default = true, ids = { 1, 2, 3 } },
    { key = "SINGLE", label = "Single", group = "Others", default = true, ids = { 4 } },
    { key = "OFF", label = "Off One", group = "Druid", default = false, ids = { 5 } },
}

local function sorted(set)
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

describe("cc tracker rules", function()
    local Rules

    before_each(function()
        Rules = L.loadCCTrackerRules()
    end)

    describe("which ids are tracked", function()
        it("takes every id of a default-on seed and none of a default-off seed", function()
            local ids, count = Rules.ResolveIDs(SEEDS, {}, {})
            assert.same({ 1, 2, 3, 4 }, sorted(ids))
            assert.equals(4, count)
        end)

        it("lets an override turn a seed on or off", function()
            local cases = {
                { { OFF = { enabled = true } }, { 1, 2, 3, 4, 5 } },
                { { ALL_FORMS = { enabled = false } }, { 4 } },
            }
            for i, case in ipairs(cases) do
                local ids = Rules.ResolveIDs(SEEDS, case[1], {})
                assert.same(case[2], sorted(ids), "case " .. i)
            end
        end)

        it("adds the player's ids and counts an id seeded and added once", function()
            local ids, count = Rules.ResolveIDs(SEEDS, {}, { [4] = true, [99] = true })
            assert.same({ 1, 2, 3, 4, 99 }, sorted(ids))
            assert.equals(5, count)
        end)

        it("ignores malformed overrides and added entries, and counts 0 with nothing enabled", function()
            local groups = { ALL_FORMS = true, SINGLE = { enabled = "yes" }, OFF = {} }
            local custom = { [0] = true, [-3] = true, [2.5] = true, [1 / 0] = true, abc = true, [7] = false, [8] = "true" }
            local ids, count = Rules.ResolveIDs(SEEDS, groups, custom)
            assert.same({ 1, 2, 3, 4 }, sorted(ids))
            assert.equals(4, count)

            local none = { ALL_FORMS = { enabled = false }, SINGLE = { enabled = false } }
            local _, zero = Rules.ResolveIDs(SEEDS, none, {})
            assert.equals(0, zero)
        end)
    end)

    it("builds the filter from the source and Every Crowd Control, and the candidates from the ids", function()
        local cases = {
            { "ANYONE", false, "HARMFUL" },
            { "MINE", false, "HARMFUL|PLAYER" },
            { "ANYONE", true, "HARMFUL|CROWD_CONTROL" },
            { "MINE", true, "HARMFUL|PLAYER|CROWD_CONTROL" },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], Rules.FilterString(case[1], case[2]), "case " .. i)
        end
        local ids = { [118] = true }
        assert.is_nil(Rules.Candidates(true, ids))
        assert.same({ includeSpellIDs = ids }, Rules.Candidates(false, ids))
    end)

    it("rejects in order; an unreadable assist read rejects, other unreadable reads let through", function()
        local NIL = {}
        local KEYS = { "exists", "canAttack", "canAssist", "isDead", "isBoss" }
        local function api(changes)
            local reads = { exists = true, canAttack = true, canAssist = false, isDead = false, isBoss = false }
            for key, value in pairs(changes) do
                if value == NIL then reads[key] = nil else reads[key] = value end
            end
            local out = {}
            for _, key in ipairs(KEYS) do
                out[key] = function() return reads[key] end
            end
            return out
        end
        local cases = {
            { {}, nil },
            { { exists = false }, "no unit" },
            { { exists = NIL }, "no unit" },
            { { canAttack = false }, "not attackable" },
            { { canAssist = true }, "assistable, or unreadable" },
            { { canAssist = NIL }, "assistable, or unreadable" },
            { { isDead = true }, "dead" },
            { { isBoss = true }, "boss" },
            { { canAttack = false, isBoss = true }, "not attackable" },
            { { canAttack = NIL, isDead = NIL, isBoss = NIL }, nil },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[2], Rules.Verdict("nameplate1", api(case[1])), "case " .. i)
        end
    end)

    describe("the box kept on screen", function()
        it("sizes it from the cap, three icons and two gaps, the spacing and the name", function()
            local cases = {
                { { MaxEnemies = 15, IconSize = 40, RowSpacing = 2, NameEnabled = true, NameWidth = 150 }, 280, 628 },
                { { MaxEnemies = 3, IconSize = 40, RowSpacing = 2, NameEnabled = true, NameWidth = 150 }, 280, 124 },
                { { MaxEnemies = 1, IconSize = 30, RowSpacing = 5, NameEnabled = false, NameWidth = 150 }, 94, 30 },
            }
            for i, case in ipairs(cases) do
                local box = Rules.StackBox(case[1])
                assert.equals(case[2], box.width, "case " .. i)
                assert.equals(case[3], box.height, "case " .. i)
            end
        end)

        it("hangs the stack from the growth corner and takes the side from the saved anchor", function()
            local cases = {
                { "DOWN", "TOPLEFT", "TOPLEFT", "TOPLEFT" },
                { "DOWN", "CENTER", "TOPLEFT", "TOP" },
                { "DOWN", "RIGHT", "TOPLEFT", "TOPRIGHT" },
                { "UP", "BOTTOMRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
                { "UP", "LEFT", "BOTTOMLEFT", "BOTTOMLEFT" },
            }
            for i, case in ipairs(cases) do
                local box = Rules.StackBox({
                    MaxEnemies = 1, IconSize = 40, RowSpacing = 2, NameEnabled = true, NameWidth = 150,
                    GrowDirection = case[1], Position = { AnchorFrom = case[2] },
                })
                assert.equals(case[3], box.corner, "case " .. i)
                assert.equals(case[4], box.selfPoint, "case " .. i)
            end
        end)

        it("pads the box and insets the first row by a countdown that stands out past an icon", function()
            local db = { MaxEnemies = 2, IconSize = 16, RowSpacing = 2, NameEnabled = false }
            local cases = {
                { 48, 40, 84, 58, 16, 12 },
                { 17, 10, 54, 34, 1, 0 },
                { 12, 16, 52, 34, 0, 0 },
            }
            for i, case in ipairs(cases) do
                local box = Rules.StackBox(db, case[1], case[2])
                assert.equals(case[3], box.width, "case " .. i)
                assert.equals(case[4], box.height, "case " .. i)
                assert.equals(case[5], box.insetX, "case " .. i)
                assert.equals(case[6], box.insetY, "case " .. i)
            end
        end)

        it("extends the far end by a tall name, capped at the row spacing and less the countdown margin", function()
            local cases = {
                { 20, 8, true, 23 },
                { 2, 8, true, 19 },
                { 20, 40, true, 40 },
                { 20, 8, false, 16 },
            }
            for i, case in ipairs(cases) do
                local box = Rules.StackBox({
                    MaxEnemies = 1, IconSize = 16, RowSpacing = case[1],
                    NameEnabled = case[3], NameWidth = 150, NameFontSize = 30,
                }, 8, case[2])
                assert.equals(case[4], box.height, "case " .. i)
                assert.equals(0, box.insetX, "case " .. i)
            end
        end)

        it("caps the height at the screen's height, only above it, and never with no positive cap", function()
            local cases = {
                { 15, 768, 628 },
                { 40, 768, 768 },
                { 40, 0, 1678 },
            }
            for i, case in ipairs(cases) do
                local box = Rules.StackBox({
                    MaxEnemies = case[1], IconSize = 40, RowSpacing = 2,
                    NameEnabled = true, NameWidth = 150, MaxHeight = case[2],
                })
                assert.equals(case[3], box.height, "case " .. i)
                assert.equals(280, box.width, "case " .. i)
            end
        end)
    end)

    it("refuses what Add cannot take, in order, and accepts a new spell id", function()
        local names = { [4] = "Single", [5] = "Off One", [99] = "Added", [500] = "New" }
        local function getName(id) return names[id] end
        local custom = { [99] = true }
        local cases = {
            { "abc", nil, "Enter a whole positive number." },
            { "2.5", nil, "Enter a whole positive number." },
            { "0", nil, "Enter a whole positive number." },
            { "-4", nil, "Enter a whole positive number." },
            { "777", nil, "No spell with that id." },
            { "4", nil, "Already in the list as Single." },
            { "5", nil, "Already in the list as Off One." },
            { "99", nil, "Already added." },
            { "500", 500, nil },
        }
        for i, case in ipairs(cases) do
            local id, reason = Rules.CanAdd(case[1], SEEDS, custom, getName)
            assert.equals(case[2], id, "case " .. i)
            assert.equals(case[3], reason, "case " .. i)
        end
    end)

    it("writes a preview countdown in whole seconds, or in tenths below the threshold", function()
        local cases = {
            { 7, 10, "7.0" },
            { 7, 0, "7" },
            { 10, 10, "10" },
            { 42, 10, "42" },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], Rules.SampleTime(case[1], case[2]), "case " .. i)
        end
    end)
end)
