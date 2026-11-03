-- Tier 1: the raid cooldowns box's pure rules
-- (Modules/AuraTracking/PartyBuffs/HealerExternalsRules.lua): a spec's
-- externals and their lengths, the box rows a member owns and shows, the
-- order of the box's cells, who is inspected for the box, when the box is
-- on, when a roster change keeps the counts, when an Edit Mode move
-- detaches the box, and the position table its readers and writers use. The
-- rules run on DATA, never the shipped table.
local L = require("dev.spec._ke_loader")

-- Specs 10 and 11 are two healer specs of one class, spec 20 one of another,
-- spec 30 a Paladin spec with an external; spec 99 has no row. Cast 4's
-- listed length is above the box's cap. Box rows: cast 8 for any Paladin, a
-- target row whose icon swaps to talent 80; cast 5 for any Warrior, an owner
-- row with no talent rule; cast 6 for spec 20 (healer role), an owner row
-- needing likely talent 60; cast 7 for spec 50 (tank role), a target row
-- needing unlikely talent 70; cast 9 for any Rogue, an owner row that ships
-- off.
local DATA = {
    SPELLS = {
        [1] = { kind = "external", cd = 180, buffs = { 1 } },
        [2] = { kind = "external", cd = 90, buffs = { 2 } },
        [3] = { kind = "external", cd = 120, buffs = { 3 } },
        [4] = { kind = "external", cd = 600, buffs = { 4 } },
        [5] = { kind = "external", cd = 180, buffs = { 5 } },
        [6] = { kind = "external", cd = 120, buffs = { 6 }, needs = { talents = { [60] = true }, likely = true } },
        [7] = { kind = "external", cd = 120, buffs = { 7 }, needs = { talents = { [70] = true }, likely = false } },
        [8] = { kind = "external", cd = 300, buffs = { 8, 80 },
                swap = { id = 80, talents = { [80] = true }, likely = false } },
        [9] = { kind = "external", cd = 60, buffs = { 9 }, off = true },
    },
    SPECS = {},
    HEALER_SPECS = {
        [10] = { class = "PRIEST", casts = { 1, 4 } },
        [11] = { class = "PRIEST", casts = { 2 } },
        [20] = { class = "DRUID", casts = { 3 } },
        [30] = { class = "PALADIN", casts = { 2 } },
    },
    BOX_ROWS = {
        { id = 8, class = "PALADIN", specs = { [30] = true, [31] = true }, anySpec = true, watch = "target" },
        { id = 5, class = "WARRIOR", specs = { [40] = true, [41] = true }, anySpec = true, watch = "owner" },
        { id = 6, class = "DRUID", specs = { [20] = true }, roles = { HEALER = true }, watch = "owner" },
        { id = 7, class = "SHAMAN", specs = { [50] = true }, roles = { TANK = true }, watch = "target" },
        { id = 9, class = "ROGUE", specs = { [60] = true }, anySpec = true, watch = "owner" },
    },
}

local function loadRules() return L.loadHealerExternalsRules(DATA) end

local function ids(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.id end
    return out
end

local MEMBERS = {
    { token = "player", guid = "P", class = "WARRIOR", spec = 40 },
    { token = "party1", guid = "A", class = "WARRIOR", spec = 40 },
    { token = "party2", guid = "B", class = "PALADIN", spec = 30 },
    { token = "party3", guid = "C", class = "DRUID", spec = 20 },
    { token = "party4", guid = "D", class = "MAGE" },
}

local function cells(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = { e.id, e.owner, e.units and e.units[1] or "all", e.quiet or 0 } end
    return out
end

describe("HealerExternalsRules.Entries", function()
    it("lists a spec's externals in table order under healer keys, with clamped lengths", function()
        local R, KE = loadRules()
        local CD = KE.PartyCooldownsRules
        local function shape(list)
            local out = {}
            for i, e in ipairs(list) do out[i] = { e.id, e.key, e.cd, e.off } end
            return out
        end
        local off = { CooldownOff = { ["healer:10:1"] = true } }
        local cases = {
            { name = "table order, listed lengths", spec = 10, db = {},
              want = { { 1, "healer:10:1", 180, false }, { 4, "healer:10:4", R.CD_MAX, false } } },
            { name = "switched off", spec = 10, db = off,
              want = { { 4, "healer:10:4", R.CD_MAX, false } } },
            { name = "switched off, editor list", spec = 10, db = off, all = true,
              want = { { 1, "healer:10:1", 180, true }, { 4, "healer:10:4", R.CD_MAX, false } } },
            { name = "no row", spec = 99, db = {}, want = {} },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, shape(R.Entries(case.spec, case.db, case.all)), case.name)
        end
        assert.is_true(CD.Unit(R.Entries(10, {})[2].cd) <= 2, "door bound")
    end)
end)

describe("HealerExternalsRules.BoxEntries", function()
    it("gives a member the rows its class and spec own, by class alone while the spec is unknown", function()
        local R = loadRules()
        local cases = {
            { name = "class-wide, spec unknown", class = "WARRIOR", want = { 5 } },
            { name = "spec row, spec unknown", class = "DRUID", want = {} },
            { name = "spec row, its spec", class = "DRUID", spec = 20, want = { 6 } },
            { name = "spec row, another spec of its class", class = "DRUID", spec = 21, want = {} },
            { name = "another class", class = "MAGE", spec = 20, want = {} },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, ids(R.BoxEntries(case.class, case.spec, {})), case.name)
        end
    end)

    it("drops a row its talent rule refuses or its switch turns off, unless every row is asked for", function()
        local R = loadRules()
        local off = { CooldownOff = { ["box:5"] = true } }
        local cases = {
            { name = "likely, unread", class = "DRUID", spec = 20, want = { 6 } },
            { name = "unlikely, unread", class = "SHAMAN", spec = 50, want = {} },
            { name = "read as taken", class = "SHAMAN", spec = 50, ranks = { [70] = 1 }, want = { 7 } },
            { name = "read as not taken", class = "DRUID", spec = 20, ranks = { [60] = 0 }, want = {} },
            { name = "no talent rule", class = "WARRIOR", spec = 40, ranks = {}, want = { 5 } },
            { name = "switched off", class = "WARRIOR", spec = 40, db = off, want = {} },
            { name = "switched off, editor list", class = "WARRIOR", spec = 40, db = off, all = true,
              want = { 5 } },
        }
        for _, case in ipairs(cases) do
            local got = R.BoxEntries(case.class, case.spec, case.db or {}, case.all, case.ranks)
            assert.are.same(case.want, ids(got), case.name)
        end
    end)
end)

describe("HealerExternalsRules.BoxEntry", function()
    it("draws a swap row's talent icon once the talent is read as taken, the cast's otherwise", function()
        local R = loadRules()
        local row = DATA.BOX_ROWS[1]
        local cases = {
            { name = "taken", ranks = { [80] = 1 }, want = 80 },
            { name = "unread", want = 8 },
            { name = "not taken", ranks = { [80] = 0 }, want = 8 },
        }
        for _, case in ipairs(cases) do
            local entry = R.BoxEntry(row, 30, {}, false, case.ranks)
            assert.are.equal(case.want, entry.show, case.name)
        end
    end)
end)

describe("HealerExternalsRules.Sources and Order", function()
    it("lists target cells member by member, you included, before owner cells, an owner cell watching its owner alone", function()
        local R = loadRules()
        local q = R.RAID_QUIET
        for _, case in ipairs({ { name = "no saved order" }, { name = "a non-table value", saved = "x" } }) do
            local sources = R.Sources(MEMBERS, {})
            local who = {}
            for i, s in ipairs(sources) do who[i] = s.member.token end
            assert.are.same({ "player", "party1", "party2", "party3" }, who, "you first, never a member with nothing")
            assert.are.same({
                { 2, "B", "all", 0 }, { 8, "B", "all", 0 }, { 3, "C", "all", 0 },
                { 5, "P", "player", q }, { 5, "A", "party1", q }, { 6, "C", "party3", q },
            }, cells(R.Order(sources, case.saved)), case.name)
        end
    end)

    it("with a saved order, sorts every cell by its cast's place across both groups, a shared cast yours first", function()
        local R = loadRules()
        local q = R.RAID_QUIET
        assert.are.same({
            { 6, "C", "party3", q }, { 5, "P", "player", q }, { 5, "A", "party1", q },
            { 2, "B", "all", 0 }, { 3, "C", "all", 0 }, { 8, "B", "all", 0 },
        }, cells(R.Order(R.Sources(MEMBERS, {}), { 6, 5 })))
    end)
end)

describe("HealerExternalsRules.CastOrder", function()
    it("lists every cast in shipped order, a saved order's known casts first, each once", function()
        local R = loadRules()
        local shipped = { 1, 4, 2, 3, 8, 5, 6, 7, 9 }
        local cases = {
            { name = "no saved order", want = shipped },
            { name = "a non-table value", saved = "x", want = shipped },
            { name = "a repeat, an unknown ID and missing casts", saved = { 7, 99, 3, 7, "a" },
              want = { 7, 3, 1, 4, 2, 8, 5, 6, 9 } },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, R.CastOrder(case.saved), case.name)
        end
    end)
end)

describe("HealerExternalsRules.Candidate", function()
    it("inspects a class-wide owner in any role, and a spec-row owner in its rows' roles or an unassigned one", function()
        local R = loadRules()
        local cases = {
            { name = "class-wide, tank", class = "WARRIOR", role = "TANK", want = true },
            { name = "class-wide, damage", class = "PALADIN", role = "DAMAGER", want = true },
            { name = "healer row, healer role", class = "DRUID", role = "HEALER", want = true },
            { name = "spec row's role", class = "SHAMAN", role = "TANK", want = true },
            { name = "role unread", class = "SHAMAN", want = true },
            { name = "no role", class = "PRIEST", role = "NONE", want = true },
            { name = "healer row, damage", class = "PRIEST", role = "DAMAGER", want = false },
            { name = "healer row, tank", class = "DRUID", role = "TANK", want = false },
            { name = "spec row, another role", class = "SHAMAN", role = "HEALER", want = false },
            { name = "class with no row", class = "MAGE", role = "HEALER", want = false },
            { name = "class unread", role = "HEALER", want = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.Candidate(case.class, case.role), case.name)
        end
    end)

    it("counts only switched-on rows, so a class with every row off is not inspected for the box", function()
        local R = loadRules()
        local function db(off) return { CooldownOff = off } end
        local cases = {
            { name = "every row off by a saved switch", class = "WARRIOR", role = "TANK",
              db = db({ ["box:5"] = true }), want = false },
            { name = "one row of two on", class = "PALADIN", db = db({ ["box:8"] = true }), want = true },
            { name = "its only row ships off", class = "ROGUE", db = db({}), want = false },
            { name = "a shipped-off row ticked", class = "ROGUE", db = db({ ["box:9"] = false }), want = true },
            { name = "healer class, every external off", class = "PRIEST", role = "HEALER",
              db = db({ ["healer:10:1"] = true, ["healer:10:4"] = true, ["healer:11:2"] = true }), want = false },
            { name = "healer class, one external on", class = "PRIEST", role = "HEALER",
              db = db({ ["healer:10:1"] = true }), want = true },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.Candidate(case.class, case.role, case.db), case.name)
        end
    end)
end)

describe("HealerExternalsRules.On", function()
    it("is on only with the switch on, the module active and not in a raid group", function()
        local R = loadRules()
        local on, off = { HealerExternals = true }, { HealerExternals = false }
        local cases = {
            { name = "on", db = on, active = true, raid = false, want = true },
            { name = "switch off", db = off, active = true, raid = false, want = false },
            { name = "gate closed", db = on, active = false, raid = false, want = false },
            { name = "raid group", db = on, active = true, raid = true, want = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.On(case.db, case.active, case.raid), case.name)
        end
    end)
end)

describe("HealerExternalsRules.MoverDetaches", function()
    it("detaches only a moved box whose starting place stands in for a missing anchor", function()
        local R = loadRules()
        local start = { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = -420, YOffset = 150 }
        local function at(x, y, from)
            return { AnchorFrom = from or "CENTER", AnchorTo = "CENTER", XOffset = x, YOffset = y }
        end
        local cases = {
            { name = "anchor present, moved", fallback = false, pos = at(0, 0), want = false },
            { name = "starting place handed back", fallback = true, pos = at(-420, 150), want = false },
            { name = "moved", fallback = true, pos = at(-320, 150), want = true },
            { name = "anchor point changed", fallback = true, pos = at(-420, 150, "TOPLEFT"), want = true },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.MoverDetaches(case.fallback, case.pos, start), case.name)
        end
    end)
end)

describe("HealerExternalsRules.PositionTable", function()
    it("hands back a saved position table, and stores a new empty one in place of any other value", function()
        local R = loadRules()
        local saved = { AnchorFrom = "TOP", AnchorTo = "TOP", XOffset = 1, YOffset = 2 }
        local cases = {
            { name = "a table", value = saved, want = saved },
            { name = "nil" },
            { name = "false", value = false },
            { name = "true", value = true },
            { name = "a number", value = 5 },
            { name = "a string", value = "CENTER" },
        }
        for _, case in ipairs(cases) do
            local db = { HealerExtPosition = case.value }
            local got = R.PositionTable(db, "HealerExtPosition")
            assert.are.equal(db.HealerExtPosition, got, case.name .. ": stored")
            if case.want then
                assert.are.equal(case.want, got, case.name)
            else
                assert.are.same({}, got, case.name)
            end
        end
    end)
end)

describe("HealerExternalsRules.KeepOnRoster", function()
    it("keeps the counts only for the same healers in the same order, each by a plain GUID", function()
        local R = loadRules()
        -- A plain and a secret GUID that compare equal, so only the secret
        -- guard can refuse the pair.
        local same = { __eq = function() return true end }
        local plain = setmetatable({}, same)
        local hidden = setmetatable({ secret = true }, same)
        local function isSecret(v) return type(v) == "table" and v.secret == true end
        local cases = {
            { name = "same healers", old = { "A", "B" }, new = { "A", "B" }, want = true },
            { name = "one changed", old = { "A", "B" }, new = { "A", "C" }, want = false },
            { name = "one added", old = { "A" }, new = { "A", "B" }, want = false },
            { name = "one removed", old = { "A", "B" }, new = { "A" }, want = false },
            { name = "order moved", old = { "A", "B" }, new = { "B", "A" }, want = false },
            { name = "hidden before", old = { hidden }, new = { plain }, want = false },
            { name = "hidden now", old = { plain }, new = { hidden }, want = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.KeepOnRoster(case.old, case.new, isSecret), case.name)
        end
    end)
end)

describe("HealerExternalsRules.PerRow", function()
    it("floors and holds a count to 1 to 12, and gives one row of 12 for anything else", function()
        local R = loadRules()
        local cases = {
            { name = "in range", value = 4, want = 4 },
            { name = "fraction", value = 4.7, want = 4 },
            { name = "below", value = 0, want = 1 },
            { name = "above", value = 20, want = 12 },
            { name = "a string", value = "4", want = 12 },
            { name = "missing", want = 12 },
            { name = "not a number", value = 0 / 0, want = 12 },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.PerRow(case.value), case.name)
        end
    end)
end)

describe("HealerExternalsRules.WrapSide", function()
    it("starts a free box's new lines on the side away from its anchor point", function()
        local R = loadRules()
        -- anchor point, grow, then the wanted wrapUp and wrapLeft.
        local cases = {
            { "BOTTOMLEFT", "RIGHT", true, false },
            { "TOPLEFT", "RIGHT", false, false },
            { "BOTTOM", "LEFT", true, false },
            { "CENTER", "LEFT", false, false },
            { "TOPRIGHT", "DOWN", false, true },
            { "BOTTOMLEFT", "UP", false, false },
            { "RIGHT", "UP", false, true },
            { nil, "RIGHT", false, false },
        }
        for _, c in ipairs(cases) do
            assert.are.same({ c[3], c[4] }, { R.WrapSide(false, c[1], c[2]) }, tostring(c[1]) .. " " .. c[2])
        end
    end)

    it("wraps a stacked box down and right, whatever its saved point", function()
        local R = loadRules()
        for _, grow in ipairs({ "RIGHT", "LEFT", "DOWN", "UP" }) do
            assert.are.same({ false, false }, { R.WrapSide(true, "BOTTOMRIGHT", grow) }, grow)
        end
    end)
end)

describe("HealerExternalsRules.GridPlace", function()
    it("steps along the grow direction and starts each new line on the wrap side", function()
        local R = loadRules()
        -- grow, wrapUp, wrapLeft, icon, then the wanted x and y; four per line, step 10.
        local cases = {
            { "RIGHT", false, false, 1, 0, 0 },
            { "RIGHT", false, false, 4, 30, 0 },
            { "RIGHT", false, false, 6, 10, -10 },
            { "RIGHT", true, false, 6, 10, 10 },
            { "LEFT", false, false, 2, -10, 0 },
            { "LEFT", false, false, 5, 0, -10 },
            { "DOWN", false, false, 2, 0, -10 },
            { "DOWN", false, false, 5, 10, 0 },
            { "DOWN", false, true, 5, -10, 0 },
            { "UP", false, false, 6, 10, 10 },
        }
        for _, c in ipairs(cases) do
            local x, y = R.GridPlace(c[4], 4, c[1], 10, c[2], c[3])
            assert.are.same({ c[5], c[6] }, { x, y }, c[1] .. " icon " .. c[4])
        end
    end)
end)

describe("HealerExternalsRules.GridInset", function()
    it("reaches from the one-icon box over the grid on the sides the grid extends to", function()
        local R = loadRules()
        -- columns, rows, extends left, extends up, then left, right, top, bottom; step 39.
        local cases = {
            { 4, 2, false, false, 0, 117, 0, 39 },
            { 4, 2, true, true, 117, 0, 39, 0 },
            { 2, 4, true, false, 39, 0, 0, 117 },
            { 1, 1, false, false, 0, 0, 0, 0 },
        }
        for i, c in ipairs(cases) do
            assert.are.same({ c[5], c[6], c[7], c[8] }, { R.GridInset(c[1], c[2], 39, c[3], c[4]) }, "case " .. i)
        end
    end)
end)

describe("HealerExternalsRules.DefaultAttachment", function()
    local function defaults()
        return {
            HealerExtAnchorFrameType = "SELECTFRAME", HealerExtParentFrame = "KitnEssentialsHealerMana",
            HealerExtPosition = { AnchorFrom = "BOTTOMLEFT", AnchorTo = "TOPLEFT", XOffset = 0, YOffset = 1 },
        }
    end

    it("reads a box whose six values equal the defaults as untouched", function()
        local R = loadRules()
        assert.is_true(R.DefaultAttachment(defaults(), defaults()))
    end)

    it("reads any changed value, a position that is not a table, or missing defaults as touched", function()
        local R = loadRules()
        local cases = {
            { name = "detached", key = "HealerExtAnchorFrameType", value = "UIPARENT" },
            { name = "another frame", key = "HealerExtParentFrame", value = "PlayerFrame" },
            { name = "parent cleared", key = "HealerExtParentFrame" },
            { name = "side bottom", field = "AnchorFrom", value = "TOPLEFT" },
            { name = "point moved", field = "AnchorTo", value = "BOTTOMLEFT" },
            { name = "x moved", field = "XOffset", value = 5 },
            { name = "y moved", field = "YOffset", value = -1 },
            { name = "position not a table", key = "HealerExtPosition", value = "TOPLEFT" },
        }
        for _, case in ipairs(cases) do
            local db = defaults()
            if case.field then
                db.HealerExtPosition[case.field] = case.value
            else
                db[case.key] = case.value
            end
            assert.is_false(R.DefaultAttachment(db, defaults()), case.name)
        end
        assert.is_false(R.DefaultAttachment(defaults(), nil), "defaults missing")
        local noPosition = defaults()
        noPosition.HealerExtPosition = nil
        assert.is_false(R.DefaultAttachment(defaults(), noPosition), "default position missing")
    end)
end)

describe("HealerExternalsRules.Stacks", function()
    it("stacks only with the setting on, the attachment untouched, the Default view and the box shown", function()
        local R = loadRules()
        local cases = {
            { name = "all met", below = true, untouched = true, context = "DEFAULT", shown = true, want = true },
            { name = "setting off", below = false, untouched = true, context = "DEFAULT", shown = true },
            { name = "box moved", below = true, untouched = false, context = "DEFAULT", shown = true },
            { name = "Healer view", below = true, untouched = true, context = "HEALER", shown = true },
            { name = "box hidden", below = true, untouched = true, context = "DEFAULT", shown = false },
        }
        for _, case in ipairs(cases) do
            local got = R.Stacks(case.below, case.untouched, case.context, case.shown)
            assert.are.equal(case.want == true, got, case.name)
        end
    end)
end)

describe("HealerExternalsRules.StackInset", function()
    it("covers the box and Healer Mana under the spot, the extra width on the box's grow side", function()
        local R = loadRules()
        -- box width, box height, spot width, right-aligned, then left, right, top, bottom; gap 1.
        local cases = {
            { 155, 38, 120, false, 0, 35, 0, 39 },
            { 155, 77, 120, true, 35, 0, 0, 78 },
            { 77, 77, 120, false, 0, 0, 0, 78 },
        }
        for i, c in ipairs(cases) do
            assert.are.same({ c[5], c[6], c[7], c[8] }, { R.StackInset(c[1], c[2], c[3], 1, c[4]) }, "case " .. i)
        end
    end)
end)
