-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_format_spec.lua                             ║
-- ║  Formatter-contract spec for DamageMeter/Core.lua.       ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/DamageMeter/Core.lua headlessly (L.loadDMCore) and
-- tests the render layer's (string, isSecret) contract: FormatBarValue /
-- FormatDeathTime / FormatRecapDelta (cross-chunk exports at Core.lua /
-- :1078) plus DM:FormatWindowLabel. Unlike dm_breakdown_spec's mirror of
-- Detail.lua, these are the shipped functions -- a load-time break here is
-- the intended tripwire.
--
-- AbbreviateNumbers is a RECORDING stub: specs assert routing (which amounts
-- reach it, in what order), clamping (the number it receives), and composition
-- (the " | " join), never its output string -- asserting abbreviation output
-- would test the stub, not KE.
--
-- HONESTY BOUNDARY (see dev/README.md): issecretvalue is a closure over the
-- SECRET table -- values WE declare secret. A pass verifies BRANCH ROUTING
-- given declared-secret values, never real 12.0 taint semantics (in-game,
-- `..` on a secret string yields a secret string; interned headless strings
-- cannot carry that mark). In-game /reload remains the secret-semantics gate.
local L = require("dev.spec._ke_loader")

-- ── Controllable stubs the real file captures at load ──────────────────────────
local SECRET     = {}   -- [value] = true  marks a value "secret"
local ABBR_CALLS = {}   -- every value AbbreviateNumbers received, in order
local ABBR_NIL   = {}   -- [value] = true  -> AbbreviateNumbers returns nil

-- ── Tests ───────────────────────────────────────────────────────────────────────
local DM
before_each(function()
    for k in pairs(SECRET) do SECRET[k] = nil end
    for i = #ABBR_CALLS, 1, -1 do ABBR_CALLS[i] = nil end
    for k in pairs(ABBR_NIL) do ABBR_NIL[k] = nil end
    -- Core.lua captures issecretvalue/AbbreviateNumbers into file-locals at load
    -- (Core.lua); loadDMCore installs the mock before loadModule, so these
    -- closures are what the file captures -- per-test SECRET mutation still works.
    DM = L.loadDMCore({
        issecretvalue = function(v) return SECRET[v] == true end,
        -- Models the one propagation rule the formatters rely on: the output is
        -- secret iff the input is. Only a DIRECT return of this output keeps the
        -- mark; a `..` concat produces a fresh unmarked string (headless limit).
        AbbreviateNumbers = function(v)
            ABBR_CALLS[#ABBR_CALLS + 1] = v
            if ABBR_NIL[v] then return nil end
            -- Sentinel is colon-free on purpose: FormatDeathTime asserts the
            -- secret path contains no ":" (proof the M:SS branch never ran).
            if SECRET[v] then
                SECRET["SECRETSTR"] = true
                return "SECRETSTR"
            end
            return tostring(v)
        end,
    })
    assert(DM and DM.FormatBarValue, "loadDMCore did not expose DM.FormatBarValue")
end)

describe("FormatBarValue mode routing", function()
    it("'Both' composes total | perSec through the abbreviator, total first", function()
        local s, sec = DM.FormatBarValue(200, 50, "Both")
        assert.equals(2, #ABBR_CALLS)
        assert.equals(200, ABBR_CALLS[1])
        assert.equals(50, ABBR_CALLS[2])
        assert.is_truthy(s:find(" | ", 1, true))   -- the pipe join is KE's, not the stub's
        assert.is_false(sec)
    end)

    it("'Both' with a nil rate renders the total alone (no pipe)", function()
        local s, sec = DM.FormatBarValue(200, nil, "Both")
        assert.equals(1, #ABBR_CALLS)
        assert.equals(200, ABBR_CALLS[1])
        assert.is_nil(s:find("|", 1, true))
        assert.is_false(sec)
    end)

    it("'PerSec' formats the rate only -- the total never reaches the abbreviator", function()
        local _, sec = DM.FormatBarValue(999, 55, "PerSec")
        assert.equals(1, #ABBR_CALLS)
        assert.equals(55, ABBR_CALLS[1])
        assert.is_false(sec)
    end)

    it("'PerSec' with a nil rate falls back to the total", function()
        DM.FormatBarValue(999, nil, "PerSec")
        assert.equals(1, #ABBR_CALLS)
        assert.equals(999, ABBR_CALLS[1])
    end)

    it("'PerSec' with neither rate nor total returns ('', false)", function()
        local s, sec = DM.FormatBarValue(nil, nil, "PerSec")
        assert.equals("", s)
        assert.is_false(sec)
        assert.equals(0, #ABBR_CALLS)
    end)

    it("default and mode=false are amount-only (the rate is ignored)", function()
        -- mode=false is the Detail breakdown/recap surfaces' path (Core.lua).
        DM.FormatBarValue(300, 50, nil)
        DM.FormatBarValue(300, 50, false)
        assert.equals(2, #ABBR_CALLS)   -- one call per invocation: the total only
        assert.equals(300, ABBR_CALLS[1])
        assert.equals(300, ABBR_CALLS[2])
    end)

    it("nil total returns ('', false) in amount and 'Both' modes", function()
        local s, sec = DM.FormatBarValue(nil, 5, "Both")
        assert.equals("", s)
        assert.is_false(sec)
        local s2, sec2 = DM.FormatBarValue(nil, nil, nil)
        assert.equals("", s2)
        assert.is_false(sec2)
        assert.equals(0, #ABBR_CALLS)   -- the orphan rate is never formatted
    end)
end)

describe("FormatBarValue sub-1 rate clamp", function()
    -- Overall-window rates can fall below 1 (total / huge elapsed); plain rates
    -- clamp to 1 so AbbreviateNumbers never emits a raw sub-1 float (Core.lua).
    it("clamps a plain sub-1 rate to 1 before formatting", function()
        DM.FormatBarValue(nil, 0.4, "PerSec")
        assert.equals(1, ABBR_CALLS[1])
    end)

    it("clamps inside the 'Both' composition too", function()
        DM.FormatBarValue(500, 0.4, "Both")
        assert.equals(500, ABBR_CALLS[1])
        assert.equals(1, ABBR_CALLS[2])
    end)

    it("leaves a plain rate >= 1 alone", function()
        DM.FormatBarValue(nil, 7, "PerSec")
        assert.equals(7, ABBR_CALLS[1])
    end)

    it("a declared-secret rate SKIPS the clamp compare", function()
        -- The `< 1` compare on a secret number taints in-game, so the guard must
        -- short-circuit on issecretvalue BEFORE comparing -- the secret rate
        -- reaches the abbreviator unclamped.
        local sp = 0.25
        SECRET[sp] = true
        local _, sec = DM.FormatBarValue(nil, sp, "PerSec")
        assert.equals(0.25, ABBR_CALLS[1])
        assert.is_true(sec)   -- direct return of the secret-marked abbreviation
    end)
end)

describe("FormatBarValue isSecret mirror", function()
    it("flags a direct secret abbreviation on the amount-only path", function()
        local t = 43810000
        SECRET[t] = true
        local s, sec = DM.FormatBarValue(t, nil, nil)
        assert.is_true(sec)
        assert.equals(SECRET[s] == true, sec)
    end)

    it("mirrors issecretvalue(result) -- not the inputs -- on the composed path", function()
        -- Regression tripwire for `return str, issecretvalue(total)`: with a
        -- secret total the concat result is a fresh UNMARKED string headlessly,
        -- so mirroring the result reports false while mirroring the input would
        -- report true. (In-game the concat itself stays secret -- honesty boundary.)
        local t = 99
        SECRET[t] = true
        local s, sec = DM.FormatBarValue(t, 50, "Both")
        assert.equals(SECRET[s] == true, sec)
        assert.is_false(sec)
    end)
end)

describe("FormatDeathTime", function()
    it("formats a plain time as M:SS without touching the abbreviator", function()
        local s, sec = DM.FormatDeathTime(143)
        assert.equals("2:23", s)
        assert.is_false(sec)
        assert.equals("1:01", (DM.FormatDeathTime(61)))   -- seconds zero-pad
        assert.equals("0:00", (DM.FormatDeathTime(0)))
        assert.equals(0, #ABBR_CALLS)
    end)

    it("nil renders the 0:00 placeholder", function()
        local s, sec = DM.FormatDeathTime(nil)
        assert.equals("0:00", s)
        assert.is_false(sec)
    end)

    it("a declared-secret time routes through the abbreviator + 's' suffix", function()
        -- M:SS arithmetic on a secret would taint; the secret path is
        -- AbbreviateNumbers(sec) .. "s" (Core.lua).
        local t = 143
        SECRET[t] = true
        local s, sec = DM.FormatDeathTime(t)
        assert.equals(1, #ABBR_CALLS)
        assert.equals(143, ABBR_CALLS[1])
        assert.equals("s", s:sub(-1))           -- whole-seconds "Ns" routing
        assert.is_nil(s:find(":", 1, true))     -- the M:SS branch never ran
        assert.equals(SECRET[s] == true, sec)   -- mirror; `.. "s"` drops the mark headlessly
    end)

    it("falls back to ('0:00', false) when the abbreviator yields nothing", function()
        -- The `if s then` guard at Core.lua.
        local t = 200
        SECRET[t] = true
        ABBR_NIL[t] = true
        local s, sec = DM.FormatDeathTime(t)
        assert.equals("0:00", s)
        assert.is_false(sec)
    end)
end)

describe("FormatRecapDelta", function()
    it("formats a plain delta as -N.Ns", function()
        assert.equals("-3.4s", DM.FormatRecapDelta(10, 6.6))
        assert.equals("-3.0s", DM.FormatRecapDelta(10, 7))
    end)

    it("returns '' when either timestamp is nil", function()
        assert.equals("", DM.FormatRecapDelta(nil, 5))
        assert.equals("", DM.FormatRecapDelta(10, nil))
    end)

    it("returns '' when either operand is declared secret", function()
        -- Subtraction on a secret throws in-game (Core.lua) -- both operands
        -- must be checked before the math runs.
        SECRET[6.6] = true
        assert.equals("", DM.FormatRecapDelta(10, 6.6))
        SECRET[10] = true
        assert.equals("", DM.FormatRecapDelta(10, 3))
    end)
end)

describe("DM:FormatWindowLabel", function()
    -- Enum.* values are the loader's stable per-member strings; DM keyed its
    -- label tables with the same values at load, so lookups discriminate.
    it("prefixes Overall and leaves Current bare", function()
        assert.equals("Overall Damage Done",
            DM:FormatWindowLabel(Enum.DamageMeterType.DamageDone, Enum.DamageMeterSessionType.Overall))
        assert.equals("Damage Done",
            DM:FormatWindowLabel(Enum.DamageMeterType.DamageDone, Enum.DamageMeterSessionType.Current))
    end)

    it("routes meter types through METER_TYPE_NAMES", function()
        assert.equals("Overall Deaths",
            DM:FormatWindowLabel(Enum.DamageMeterType.Deaths, Enum.DamageMeterSessionType.Overall))
        assert.equals("Healing Done",
            DM:FormatWindowLabel(Enum.DamageMeterType.HealingDone, Enum.DamageMeterSessionType.Current))
    end)

    it("falls back to 'Damage Done' for an unmapped meter type", function()
        assert.equals("Damage Done",
            DM:FormatWindowLabel("bogus", Enum.DamageMeterSessionType.Current))
        assert.equals("Overall Damage Done",
            DM:FormatWindowLabel("bogus", Enum.DamageMeterSessionType.Overall))
    end)

    it("never prefixes for an unmapped session type", function()
        assert.equals("Deaths", DM:FormatWindowLabel(Enum.DamageMeterType.Deaths, "bogus"))
    end)
end)
