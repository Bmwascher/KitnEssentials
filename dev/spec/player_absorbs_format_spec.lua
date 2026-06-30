local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("PlayerAbsorbsFormat.Format", function()
    local KE
    local SECRET = setmetatable({}, { __tostring = function() return "0" end })

    local function load(opts)
        opts = opts or {}
        mock.install({
            -- Mocked WoW formatters so assertions are deterministic.
            AbbreviateNumbers = opts.AbbreviateNumbers
                or function(v) return "ABBR:" .. tostring(v) end,
            BreakUpLargeNumbers = function(v) return "FULL:" .. tostring(v) end,
            issecretvalue = function(v) return v == SECRET end,
        })
        -- C_StringUtil.TruncateWhenZero: secret-safe blank-at-zero stand-in.
        _G.C_StringUtil = { TruncateWhenZero = function() return "" end }
        -- Module-file guard `if not KitnEssentials then return end` needs the global.
        _G.KitnEssentials = _G.KitnEssentials or {}
        KE = helpers.loadModule("Modules/Utilities/PlayerAbsorbsFormat.lua", {})
    end

    before_each(function() load() end)

    it("returns empty string for a non-secret zero when hideWhenZero", function()
        assert.equals("", KE.PlayerAbsorbsFormat.Format(0, false, true))
    end)

    it("treats nil as zero and hides it", function()
        assert.equals("", KE.PlayerAbsorbsFormat.Format(nil, false, true))
    end)

    it("formats a non-secret nonzero value without abbreviation", function()
        assert.equals("FULL:1200000", KE.PlayerAbsorbsFormat.Format(1200000, false, true))
    end)

    it("abbreviates a non-secret nonzero value when abbreviate=true", function()
        assert.equals("ABBR:1200000", KE.PlayerAbsorbsFormat.Format(1200000, true, true))
    end)

    it("clamps negative non-secret values to hidden", function()
        assert.equals("", KE.PlayerAbsorbsFormat.Format(-5, false, true))
    end)

    it("uses TruncateWhenZero for a secret value when hideWhenZero and not abbreviating", function()
        -- TruncateWhenZero stub returns "" — proves the secret zero-blank path is taken.
        assert.equals("", KE.PlayerAbsorbsFormat.Format(SECRET, false, true))
    end)

    it("abbreviates a secret value when abbreviate=true (no zero-blank)", function()
        assert.equals("ABBR:" .. tostring(SECRET),
            KE.PlayerAbsorbsFormat.Format(SECRET, true, true))
    end)
end)
