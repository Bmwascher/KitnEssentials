-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_format_spec.lua                             ║
-- ║  Formatter-contract spec for DamageMeter/Core.lua.       ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/DamageMeter/Core.lua headlessly (L.loadDMCore) and
-- tests the render layer's (string, isSecret) contract: FormatBarValue /
-- FormatDeathTime / FormatRecapDelta (cross-chunk exports at Core.lua).
-- Unlike dm_breakdown_spec's mirror of Detail.lua, these are the shipped
-- functions -- a load-time break here is the intended tripwire.
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

    it("default and mode=false are amount-only (the rate is ignored)", function()
        -- mode=false is the Detail breakdown/recap surfaces' path (Core.lua).
        DM.FormatBarValue(300, 50, nil)
        DM.FormatBarValue(300, 50, false)
        assert.equals(2, #ABBR_CALLS)   -- one call per invocation: the total only
        assert.equals(300, ABBR_CALLS[1])
        assert.equals(300, ABBR_CALLS[2])
    end)

    it("nil total returns ('', false) in amount, 'Both', and 'PerSec' modes", function()
        local s, sec = DM.FormatBarValue(nil, 5, "Both")
        assert.equals("", s)
        assert.is_false(sec)
        local s2, sec2 = DM.FormatBarValue(nil, nil, nil)
        assert.equals("", s2)
        assert.is_false(sec2)
        local s3, sec3 = DM.FormatBarValue(nil, nil, "PerSec")
        assert.equals("", s3)
        assert.is_false(sec3)
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

describe("Death-time stamps", function()
    it("renders a plain time as M:SS even when a stamp exists", function()
        local s, sec = DM.DeathTimeText(143, 7, { [7] = 61 })
        assert.equals("2:23", s)
        assert.is_false(sec)
    end)

    it("renders a secret time from its stamp as plain M:SS", function()
        local t = 3001
        SECRET[t] = true
        local s, sec = DM.DeathTimeText(t, 7, { [7] = 61 })
        assert.equals("1:01", s)
        assert.is_false(sec)
        assert.equals(0, #ABBR_CALLS)   -- the secret time never reached the formatter
        DM.DeathTimeText(t, 7, nil)     -- any view but the live one passes no stamps
        assert.equals(t, ABBR_CALLS[1])
    end)

    it("stamps only within the duration bound of the previous read", function()
        local cases = {
            { name = "no previous read", prev = nil, now = 10, mode = "mark" },
            { name = "no current read", prev = 10, now = nil, mode = "mark" },
            { name = "a falling duration", prev = 10, now = 4, mode = "mark" },
            { name = "a gap over the bound", prev = 10, now = 10.8, mode = "mark" },
            { name = "within the bound", prev = 10, now = 10.75, mode = "stamp" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.mode, DM.DeathStampMode(c.prev, c.now, 0.75), c.name)
        end
    end)

    it("takes the bound from the configured Combat Refresh", function()
        local t = 3006
        SECRET[t] = true
        local read = 10.3
        _G.C_DamageMeter = { GetSessionDurationSeconds = function() return read end }
        DM.db = { RefreshRate = 0.1 }
        local W = { _deathPrevDur = 10, _deathPrevSeq = 0 }
        DM.windows_rt = { W }
        DM:UpdateDeathStamps(W, true, { { deathRecapID = 7, deathTimeSeconds = t } })
        read = 10.7
        DM:UpdateDeathStamps(W, true, {
            { deathRecapID = 7, deathTimeSeconds = t },
            { deathRecapID = 8, deathTimeSeconds = t },
        })
        assert.equals(10.3, DM._deathStamps[7])   -- 0.3 s gap: within 0.1 + jitter
        assert.is_false(DM._deathStamps[8])       -- 0.4 s gap: past it
    end)

    it("clears every stamp and every window's previous read at a session boundary", function()
        DM._deathStamps[7] = 61
        DM._deathStamps[8] = false
        DM.windows_rt = { { _deathPrevDur = 7 }, { _deathPrevDur = 42 } }
        DM:ResetDeathStamps()
        assert.is_nil(next(DM._deathStamps))
        for _, W in ipairs(DM.windows_rt) do
            assert.is_nil(W._deathPrevDur)
        end
    end)

    it("writes no numeric stamp from a secret duration read, and clears the old ones", function()
        local t, d = 3002, 3003
        SECRET[t] = true
        SECRET[d] = true
        _G.C_DamageMeter = { GetSessionDurationSeconds = function() return d end }
        DM._deathStamps[5] = 40
        local W = { _deathPrevDur = 20, _deathPrevSeq = 0 }
        DM.windows_rt = { W }
        DM:UpdateDeathStamps(W, true, { { deathRecapID = 7, deathTimeSeconds = t } })
        assert.is_nil(DM._deathStamps[5])       -- a failed read counts as a roll
        assert.is_false(DM._deathStamps[7])
        assert.is_nil(W._deathPrevDur)
    end)

    it("never stamps a death first seen without a vouching read", function()
        local t1, t2 = 3004, 3005
        SECRET[t1] = true
        SECRET[t2] = true
        local stamps = {}
        local first = { deathRecapID = 7, deathTimeSeconds = t1 }
        DM.StampDeaths({ first }, stamps, "mark", 60)
        DM.StampDeaths({
            first,
            { deathRecapID = 8, deathTimeSeconds = t2 },
            { deathRecapID = 9, deathTimeSeconds = t2 },
        }, stamps, "stamp", 61)
        assert.is_false(stamps[7])
        assert.equals(61, stamps[8])
        assert.equals(61, stamps[9])
    end)

    it("clears every stamp at a tick when the Current duration falls, whatever the views", function()
        _G.C_DamageMeter = { GetSessionDurationSeconds = function() return 2 end }
        DM._deathStamps[5] = 40
        DM._deathLastDur = 50
        local W = { _deathPrevDur = 40 }
        DM.windows_rt = { W }
        DM:BeginDeathTick()
        assert.is_nil(DM._deathStamps[5])
        assert.is_nil(W._deathPrevDur)
        assert.equals(2, DM._deathLastDur)
    end)

    it("stamps only inside a tick, from a read taken in that tick or the one before", function()
        local t = 3007
        SECRET[t] = true
        _G.C_DamageMeter = { GetSessionDurationSeconds = function() return 10.2 end }
        DM._deathSeq = 5
        local cases = {
            { name = "read in the previous tick", seq = 4, rid = 7, want = 10.2 },
            { name = "read two ticks back", seq = 3, rid = 8, want = false },
            { name = "a render after the tick ended", seq = 4, rid = 9, over = true, want = nil },
        }
        for _, c in ipairs(cases) do
            DM._deathTickOver = c.over
            local W = { _deathPrevDur = 10, _deathPrevSeq = c.seq }
            DM:UpdateDeathStamps(W, true, { { deathRecapID = c.rid, deathTimeSeconds = t } })
            assert.equals(c.want, DM._deathStamps[c.rid], c.name)
        end
    end)
end)
