-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_format_spec.lua                             ║
-- ║  Formatter-contract spec for DamageMeter/Core.lua.       ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/Skinning/DamageMeter/Core.lua headlessly (L.loadDMCore) and
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

    it("clears every stamp and the pass's previous read at a session boundary", function()
        DM._deathStamps[7] = 61
        DM._deathStamps[8] = false
        DM._deathPassAt, DM._deathPassDur, DM._deathPassSeq = 12, 7, 3
        DM:ResetDeathStamps()
        assert.is_nil(next(DM._deathStamps))
        assert.is_nil(DM._deathPassAt)
        assert.is_nil(DM._deathPassDur)
        assert.is_nil(DM._deathPassSeq)
    end)

    it("forgets the highest session ID when the module stops watching", function()
        DM._liveSessionID, DM._sessionRolled = 9, true
        DM.windows_rt = {}
        DM:DropDeathStamps()
        assert.is_nil(DM._liveSessionID)
        assert.is_nil(DM._sessionRolled)
    end)

    it("stamps each new death from the module pass, with no window present", function()
        local savedGetTime = _G.GetTime
        finally(function() _G.GetTime = savedGetTime end)
        local t, secretDur = 3010, 3011
        SECRET[t] = true
        SECRET[secretDur] = true
        local clock, dur, reads = 0, 0, 0
        local sources = { { deathRecapID = 9, deathTimeSeconds = t } }
        _G.GetTime = function() return clock end
        _G.C_DamageMeter = {
            GetSessionDurationSeconds = function() return dur end,
            GetCombatSessionFromType = function()
                reads = reads + 1
                return { combatSources = sources }
            end,
        }
        local deaths = Enum.DamageMeterType.Deaths
        local cases = {
            { name = "a pass within the bound stamps the duration",
              prevAt = 10, prevDur = 5, now = 10.5, dur = 5, moved = true, want = 5, reads = 1 },
            { name = "a whole-second step 0.5 s later still stamps",
              prevAt = 10, prevDur = 5, now = 10.5, dur = 6, moved = true, want = 6, reads = 1 },
            { name = "no previous pass marks",
              now = 10, dur = 5, moved = true, want = false, reads = 1 },
            { name = "a real-time gap past the bound marks at a 0.1 s rate",
              rate = 0.1, prevAt = 10, prevDur = 5, now = 10.9, dur = 5, moved = true, want = false, reads = 1 },
            { name = "the same gap stamps at the 0.5 s rate",
              rate = 0.5, prevAt = 10, prevDur = 5, now = 10.9, dur = 5, moved = true, want = 5, reads = 1 },
            { name = "a roll within the bound clears the old stamps and stamps the new session's duration",
              prevAt = 10, prevDur = 50, lastDur = 50, now = 10.5, dur = 2, old = true, want = 2, reads = 1 },
            { name = "a roll after a gap past the bound marks",
              prevAt = 10, prevDur = 50, lastDur = 50, now = 12, dur = 2, old = true, want = false, reads = 1 },
            -- 0 -> 0 across a roll: only the session ID can tell, and the new
            -- death reuses the old session's recap id.
            { name = "a session ID roll with an unchanged duration restamps a reused recap id",
              prevAt = 10, prevDur = 0, lastDur = 0, now = 10.5, dur = 0, reused = true, rolled = true, want = 0, reads = 1 },
            { name = "a secret duration read clears the old stamps and marks",
              prevAt = 10, prevDur = 5, lastDur = 5, now = 10.5, dur = secretDur, old = true, want = false, reads = 1 },
            { name = "an unmoved Deaths seq makes no session read",
              prevAt = 10, prevDur = 5, now = 10.5, dur = 5, moved = false, want = nil, reads = 0 },
        }
        for _, c in ipairs(cases) do
            DM.db = { RefreshRate = c.rate or 0.5 }
            DM.windows_rt = {}
            DM._sessionCache = nil
            for k in pairs(DM._deathStamps) do DM._deathStamps[k] = nil end
            if c.old then DM._deathStamps[1] = 40 end
            if c.reused then DM._deathStamps[9] = 40 end
            DM._sessionRolled = c.rolled
            DM._deathLastDur = c.lastDur
            DM._deathPassAt, DM._deathPassDur = c.prevAt, c.prevDur
            local seqNow = (DM._typeSeq[deaths] or 0) + DM._allSeq
            DM._deathPassSeq = c.moved and -1 or seqNow
            clock, dur, reads = c.now, c.dur, 0
            DM:RunDeathStampPass()
            assert.equals(c.want, DM._deathStamps[9], c.name)
            assert.equals(c.reads, reads, c.name .. ": session reads")
            if c.old then assert.is_nil(DM._deathStamps[1], c.name .. ": old stamp cleared") end
        end

        -- A boundary takes a baseline at once: the rows listed then were not
        -- seen arriving, and a death after it is stamped on the next pass.
        for k in pairs(DM._deathStamps) do DM._deathStamps[k] = nil end
        DM.db = { RefreshRate = 0.5 }
        DM._sessionCache, DM._deathLastDur = nil, nil
        clock, dur = 20, 3
        DM:RestartDeathStamps()
        assert.is_false(DM._deathStamps[9], "restart: a row listed at the boundary marks")
        sources = {
            { deathRecapID = 9, deathTimeSeconds = t },
            { deathRecapID = 10, deathTimeSeconds = t },
        }
        DM._sessionCache = nil
        DM:BumpDeathsSeq()
        clock, dur = 20.5, 4
        DM:RunDeathStampPass()
        assert.equals(4, DM._deathStamps[10], "restart: the next pass stamps a later death")
    end)

    it("flags a roll only for a session ID above every one seen", function()
        local savedICL = _G.InCombatLockdown
        finally(function() _G.InCombatLockdown = savedICL end)
        -- In combat the handler returns after the bookkeeping, before its timer.
        _G.InCombatLockdown = function() return true end
        local secretID = 3020
        SECRET[secretID] = true
        local ev = "DAMAGE_METER_COMBAT_SESSION_UPDATED"
        local cases = {
            { name = "the first ID is a baseline", id = 5, live = 5 },
            { name = "the overall session's ID 0 is never a baseline", id = 0 },
            { name = "a higher ID is a roll", seen = 5, id = 6, rolled = true, live = 6 },
            { name = "the same ID again, one event per meter type, is not", seen = 6, id = 6, live = 6 },
            { name = "the overall session's ID 0 changes nothing", seen = 6, id = 0, live = 6 },
            { name = "a lower ID is a late update", seen = 6, id = 4, live = 6 },
            { name = "a secret ID changes nothing", seen = 6, id = secretID, live = 6 },
        }
        for _, c in ipairs(cases) do
            DM._liveSessionID, DM._sessionRolled = c.seen, nil
            DM:OnSessionUpdated(ev, 1, c.id)
            assert.equals(c.rolled, DM._sessionRolled, c.name)
            assert.equals(c.live, DM._liveSessionID, c.name .. ": live ID")
        end
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
end)
