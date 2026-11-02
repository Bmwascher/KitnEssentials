-- Tier 1: the choosing and refusing rules of the Forever kick derivation
-- (dev/scripts/_forever_kicks_rules.lua). The real extracts trip no refusal,
-- so a refusal that stopped firing would leave the printed block unchanged;
-- only these rows see it. The rows are built here.
local Rules = dofile("dev/scripts/_forever_kicks_rules.lua")

describe("Forever kick derivation rules", function()
    it("tracks the first trained or talent kick, else the first kick when it has ranks", function()
        local plain, ranked = { ranks = { 1 } }, { ranks = { 1, 2 } }
        local rows = {
            { name = "a talent kick after an untrained one", families = { plain, { ranks = { 1 }, talent = true } }, want = 2 },
            { name = "a trained first kick with ranks", families = { { ranks = { 1, 2 }, trained = true }, plain }, want = 1 },
            { name = "a trained first kick with one rank: no line", families = { { ranks = { 1 }, trained = true }, ranked },
              want = nil },
            { name = "none trained or talent: the first, which has ranks", families = { ranked, plain }, want = 1 },
            { name = "none trained or talent, one rank: no line", families = { plain }, want = nil },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, Rules.TrackedIndex(row.families), row.name)
        end
    end)

    it("refuses the first kick form the class's spells do not give", function()
        local given = { [17] = true, [18] = true }
        local rows = {
            { name = "a form no spell gives", forms = { 17, 19 }, given = given, want = 19 },
            { name = "a class with no form spell", forms = { 5 }, given = nil, want = 5 },
            { name = "every form given", forms = { 17, 18 }, given = given, want = nil },
            { name = "a kick with no forms", forms = nil, given = given, want = nil },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, Rules.MissingForm(row.forms, row.given), row.name)
        end
    end)

    it("refuses a form with no SpellShapeshiftForm row, naming the first such spell", function()
        local rows, at = Rules.FormRows({ [71] = 18, [1786] = 30, [1784] = 30, [2457] = 17 },
            { [17] = true, [18] = true }, { [17] = true, [18] = true })
        assert.is_nil(rows)
        assert.equals(1784, at)
    end)
end)
