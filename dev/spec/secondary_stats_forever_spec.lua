-- Tier 1: the Forever stat catalog's rules (Modules/QoL/SecondaryStats/
-- SecondaryStatsForever.lua): which rows a character shows, and the refusal
-- a combined figure applies to a secret or missing operand.
local helpers = require("dev.spec._helpers")

-- Stands for a secret value: arithmetic or a comparison on a table errors,
-- so a missing guard fails the case instead of passing it.
local SECRET = {}

local function loadCatalog()
    _G.KitnEssentials = _G.KitnEssentials or {}
    local KE = helpers.loadModule("Modules/QoL/SecondaryStats/SecondaryStatsForever.lua", {
        IsSecretValue = function(_, value) return value == SECRET end,
    })
    return KE.SecondaryStatsForever
end

describe("Secondary Stats on Forever: shown rows", function()
    it("shows a row with no saved choice when it is one of the class core three", function()
        local FV = loadCatalog()
        for _, row in ipairs({
            { class = "MAGE",    key = "sp",       want = true },
            { class = "PRIEST",  key = "scrit",    want = true },
            { class = "WARLOCK", key = "shit",     want = true },
            { class = "MAGE",    key = "ap",       want = false },
            { class = "MAGE",    key = "sp",       saved = {}, want = true },
            { class = "HUNTER",  key = "rhit",     want = true },
            { class = "HUNTER",  key = "mhit",     want = false },
            { class = "WARRIOR", key = "mhit",     want = true },
            { class = "WARRIOR", key = "sp",       want = false },
            { class = "DRUID",   key = "res_fire", want = false },
            { class = nil,       key = "ap",       want = true },
        }) do
            assert.equals(row.want, FV.IsShown(row.key, row.saved, row.class),
                tostring(row.class) .. " " .. row.key)
        end
    end)

    it("lets a saved choice win over the class default either way", function()
        local FV = loadCatalog()
        assert.is_false(FV.IsShown("sp", { Shown = false }, "MAGE"))
        assert.is_true(FV.IsShown("res_fire", { Shown = true }, "MAGE"))
    end)
end)

describe("Secondary Stats on Forever: combined figures", function()
    after_each(function()
        _G.UnitAttackPower = nil
        _G.GetSpellBonusDamage = nil
    end)

    it("reads nil while any operand is secret or missing, and the total or best school when none is", function()
        local FV = loadCatalog()
        for _, row in ipairs({
            { name = "attack power, clean",   key = "ap", ap = { 1000, 200, -50, n = 3 },    want = 1150 },
            { name = "attack power, secret",  key = "ap", ap = { 1000, SECRET, 0, n = 3 },   want = nil },
            { name = "attack power, missing", key = "ap", ap = { 1000, nil, 0, n = 3 },      want = nil },
            { name = "spell power, clean",    key = "sp", schools = { 10, 40, 25, 0, 5, 30 }, want = 40 },
            { name = "spell power, secret",   key = "sp", schools = { 10, 40, SECRET, 0, 5, 30 }, want = nil },
            { name = "spell power, no getter", key = "sp", want = nil },
        }) do
            _G.UnitAttackPower = row.ap and function() return unpack(row.ap, 1, row.ap.n) end or nil
            _G.GetSpellBonusDamage = row.schools and function(school) return row.schools[school - 1] end or nil
            assert.equals(row.want, FV.byKey[row.key].get(), row.name)
        end
    end)
end)
