-- Tier 1: the raid cooldowns box's pure rules
-- (Modules/AuraTracking/PartyBuffs/HealerExternalsRules.lua): a spec's
-- externals and their lengths, the box rows a member owns and shows, the
-- order of the box's cells, who is inspected for the box, when the box is
-- on, when a roster change keeps the counts, and when an Edit Mode move
-- detaches the box. The rules run on DATA, never the shipped table.
local L = require("dev.spec._ke_loader")

-- Specs 10 and 11 are two healer specs of one class, spec 20 one of another,
-- spec 30 a Paladin spec with an external; spec 99 has no row. Cast 4's
-- listed length is above the box's cap. Box rows: cast 8 for any Paladin, a
-- target row whose icon swaps to talent 80; cast 5 for any Warrior, an owner
-- row with no talent rule; cast 6 for spec 20 (healer role), an owner row
-- needing likely talent 60; cast 7 for spec 50 (tank role), a target row
-- needing unlikely talent 70.
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
    },
}

local function loadRules() return L.loadHealerExternalsRules(DATA) end

local function ids(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.id end
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
        local members = {
            { token = "player", guid = "P", class = "WARRIOR", spec = 40 },
            { token = "party1", guid = "A", class = "WARRIOR", spec = 40 },
            { token = "party2", guid = "B", class = "PALADIN", spec = 30 },
            { token = "party3", guid = "C", class = "DRUID", spec = 20 },
            { token = "party4", guid = "D", class = "MAGE" },
        }
        local sources = R.Sources(members, {})
        local who = {}
        for i, s in ipairs(sources) do who[i] = s.member.token end
        assert.are.same({ "player", "party1", "party2", "party3" }, who, "you first, never a member with nothing")
        local cells = {}
        for i, e in ipairs(R.Order(sources)) do
            cells[i] = { e.id, e.owner, e.units and e.units[1] or "all", e.quiet or 0 }
        end
        local q = R.RAID_QUIET
        assert.are.same({
            { 2, "B", "all", 0 }, { 8, "B", "all", 0 }, { 3, "C", "all", 0 },
            { 5, "P", "player", q }, { 5, "A", "party1", q }, { 6, "C", "party3", q },
        }, cells, "target cells, then owner cells")
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
