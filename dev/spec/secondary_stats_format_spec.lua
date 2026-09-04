local helpers = require("dev.spec._helpers")

describe("SecondaryStatsFormat", function()
    local KE, F
    -- Stands in for a secret value: identity-compared by the injected
    -- predicate, so no Blizzard fake is needed.
    local SECRET = {}
    local function isSecret(value) return value == SECRET end

    local function entry(overrides)
        local base = {
            label = "Crit",
            hex = "ffd100",
            valueMode = "percent",
            percent = 24.39,
            rating = 1234,
        }
        for k, v in pairs(overrides or {}) do base[k] = v end
        return base
    end

    local function opts(overrides)
        local base = {
            decimals = 2,
            separator = ":",
            showLabel = true,
            coloredValues = false,
        }
        for k, v in pairs(overrides or {}) do base[k] = v end
        return base
    end

    before_each(function()
        _G.KitnEssentials = _G.KitnEssentials or {}
        KE = helpers.loadModule("Modules/QoL/SecondaryStatsFormat.lua", {})
        F = KE.SecondaryStatsFormat
    end)

    describe("BuildRows body selection", function()
        local cases = {
            { mode = "percent", body = "%.2f%%", vals = { 24.39 } },
            { mode = "rating", body = "%.0f", vals = { 1234 } },
            { mode = "both", body = "%.0f (%.2f%%)", vals = { 1234, 24.39 } },
        }
        for _, case in ipairs(cases) do
            it("uses the " .. case.mode .. " body and pushes its values in order", function()
                local template, vals = F.BuildRows({ entry({ valueMode = case.mode }) }, opts())
                assert.equals("|cffffd100Crit:|r |cffffffff" .. case.body .. "|r", template)
                assert.same(case.vals, vals)
            end)
        end
    end)

    -- The refused half of behaviour 4: ResolveVersatility hands back nil, and
    -- this is what the row does with it. Assigned after construction, because
    -- `entry({ percent = nil })` would pass an EMPTY table -- a nil-valued key
    -- does not exist in Lua, so the override loop would see nothing.
    it("renders a question mark and pushes nothing when a needed value is absent", function()
        local absent = entry()
        absent.percent = nil
        local template, vals = F.BuildRows({ absent }, opts())
        assert.equals("|cffffd100Crit:|r |cffffffff?|r", template)
        assert.same({}, vals)
    end)

    it("puts the decimals setting into the percent specifier", function()
        local template = F.BuildRows({ entry() }, opts({ decimals = 0 }))
        assert.equals("|cffffd100Crit:|r |cffffffff%.0f%%|r", template)
    end)

    describe("EscapeText", function()
        local cases = {
            { input = "50% Crit", expected = "50%% Crit" },
            { input = "a|b", expected = "a||b" },
        }
        for _, case in ipairs(cases) do
            it("doubles the control character in " .. case.input, function()
                assert.equals(case.expected, F.EscapeText(case.input))
            end)
        end
    end)

    it("suppresses the separator along with a hidden label", function()
        local template = F.BuildRows({ entry() }, opts({ showLabel = false }))
        assert.equals("|cffffffff%.2f%%|r", template)
    end)

    describe("ResolveVersatility", function()
        it("sums two clean operands and updates the cache", function()
            local value, cached = F.ResolveVersatility(3, 2, nil, isSecret)
            assert.equals(5, value)
            assert.equals(5, cached)
        end)

        it("holds the cached total when either operand is secret", function()
            local value, cached = F.ResolveVersatility(SECRET, 2, 7, isSecret)
            assert.equals(7, value)
            assert.equals(7, cached)
        end)

        it("returns nil when an operand is secret and nothing was ever cached", function()
            local value = F.ResolveVersatility(3, SECRET, nil, isSecret)
            assert.is_nil(value)
        end)
    end)

    describe("VisibleKeys", function()
        it("drops hidden stats, honours a saved order, and appends omitted keys", function()
            local stats = {
                crit = { Shown = true }, haste = { Shown = false },
                mastery = { Shown = true }, vers = { Shown = true },
                leech = { Shown = false }, avoidance = { Shown = false },
                speed = { Shown = true },
            }
            assert.same(
                { "mastery", "crit", "vers", "speed" },
                F.VisibleKeys({ "mastery", "crit", "haste" }, stats)
            )
        end)
    end)
end)
