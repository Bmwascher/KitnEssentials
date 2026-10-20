-- Tier 1: the healer externals box's pure rules
-- (Modules/AuraTracking/PartyBuffs/HealerExternalsRules.lua): a spec's
-- externals and their lengths, who counts as a healer, who is inspected for
-- the box, when the box is on, when a roster change keeps the counts, and
-- when an Edit Mode move detaches the box. The rules run on DATA, never the
-- shipped table.
local L = require("dev.spec._ke_loader")

-- Specs 10 and 11 are two healer specs of one class, spec 20 one of another;
-- spec 99 has no row. Cast 4's listed length is above the box's cap.
local DATA = {
    SPELLS = {
        [1] = { kind = "external", cd = 180, buffs = { 1 } },
        [2] = { kind = "external", cd = 90, buffs = { 2 } },
        [3] = { kind = "external", cd = 120, buffs = { 3 } },
        [4] = { kind = "external", cd = 600, buffs = { 4 } },
    },
    HEALER_SPECS = {
        [10] = { class = "PRIEST", casts = { 1, 4 } },
        [11] = { class = "PRIEST", casts = { 2 } },
        [20] = { class = "DRUID", casts = { 3 } },
    },
}

local function loadRules() return L.loadHealerExternalsRules(DATA) end

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

describe("HealerExternalsRules.Healers", function()
    it("finds party healers by spec in party order, never you and never an unknown spec", function()
        local R = loadRules()
        local function who(list)
            local out = {}
            for i, h in ipairs(list) do out[i] = { h.member.token, h.entries[1].id } end
            return out
        end
        local cases = {
            { name = "two healers, party order", db = {},
              members = { { token = "party1", spec = 20 }, { token = "party2", spec = 11 } },
              want = { { "party1", 3 }, { "party2", 2 } } },
            { name = "you", db = {}, members = { { token = "player", spec = 11 } }, want = {} },
            { name = "spec unknown", db = {}, members = { { token = "party1" } }, want = {} },
            { name = "no row", db = {}, members = { { token = "party1", spec = 99 } }, want = {} },
            { name = "every entry off", db = { CooldownOff = { ["healer:11:2"] = true } },
              members = { { token = "party1", spec = 11 } }, want = {} },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, who(R.Healers(case.members, case.db)), case.name)
        end
    end)
end)

describe("HealerExternalsRules.Candidate", function()
    it("inspects a member whose class has a healer row unless the role says damage or tank", function()
        local R = loadRules()
        local cases = {
            { name = "healer role", class = "DRUID", role = "HEALER", want = true },
            { name = "no role", class = "PRIEST", role = "NONE", want = true },
            { name = "role unread", class = "PRIEST", want = true },
            { name = "damage", class = "PRIEST", role = "DAMAGER", want = false },
            { name = "tank", class = "DRUID", role = "TANK", want = false },
            { name = "class with no row", class = "SHAMAN", role = "HEALER", want = false },
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
