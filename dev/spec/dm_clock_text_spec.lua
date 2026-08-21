-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_clock_text_spec.lua                         ║
-- ║  Refusal + secrecy spec for DM.ClockText.                ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/DamageMeter/Core.lua headlessly (L.loadDMCore) and
-- tests the combat clock's one branching helper: given a duration, does it
-- render, and does it refuse the cases that must not reach the screen.
--
-- WHY THIS EARNS A SPEC: it is a refusal rule whose failures are silent in
-- both directions. Too permissive puts "[0:00]" on screen, which claims a
-- fight of no length happened. Too restrictive hides a clock that has a
-- perfectly good reading. Its test ORDER is load-bearing too -- the two
-- comparisons below the secrecy test would throw on a secret duration, and
-- nothing at runtime would say why.
--
-- The RENDERER is deliberately NOT tested. Per the project's tiered test
-- policy, frame layout and event timing are in-game concerns, and a
-- stateful FontString fake is the elaborate mock that policy calls a smell.
--
-- HONESTY BOUNDARY (see dev/README.md): issecretvalue is a closure over a
-- SECRET table -- values WE declare secret -- and AbbreviateNumbers is a
-- stub. A pass verifies BRANCH ROUTING given declared inputs, never real
-- 12.0 taint semantics. In-game /reload remains the secret-semantics gate.
local L = require("dev.spec._ke_loader")

local SECRET = {}     -- [value] = true  marks a value "secret"
local DM

local function load(overrides)
    overrides = overrides or {}
    overrides.issecretvalue = function(v) return SECRET[v] == true end
    DM = L.loadDMCore(overrides)
    assert(DM and DM.ClockText, "loadDMCore did not expose DM.ClockText")
end

before_each(function()
    for k in pairs(SECRET) do SECRET[k] = nil end
    load()
end)

describe("ClockText plain durations", function()
    it("floors rather than rounds", function()
        -- 59.6 rounds UP to a whole minute and floors to 59 seconds. A build
        -- that kept the old round-to-nearest passes every other case here.
        local text, isSecret = DM.ClockText(59.6)
        assert.equals("[0:59]", text)
        assert.is_false(isSecret)
    end)

    it("formats past a minute", function()
        assert.equals("[2:05]", (DM.ClockText(125)))
    end)

    it("formats a whole minute", function()
        assert.equals("[1:00]", (DM.ClockText(60)))
    end)
end)

describe("ClockText refusals", function()
    -- Every one of these must HIDE. Rendering "[0:00]" instead is the failure
    -- the acceptance criteria name explicitly.
    it("refuses a plain zero", function()
        assert.is_nil(DM.ClockText(0))
    end)

    it("refuses a negative duration", function()
        assert.is_nil(DM.ClockText(-1))
        assert.is_nil(DM.ClockText(-90))
    end)

    it("refuses a non-numeric duration", function()
        assert.is_nil(DM.ClockText("lots"))
        assert.is_nil(DM.ClockText({}))
    end)

    it("refuses nil and false", function()
        assert.is_nil(DM.ClockText(nil))
        assert.is_nil(DM.ClockText(false))
    end)
end)

describe("ClockText secret durations", function()
    it("renders a secret rather than refusing it", function()
        -- Declared secret, so a build that ran type(), <= or math_floor on it
        -- would take the wrong branch rather than quietly passing. The BODY of
        -- the string is the loader's AbbreviateNumbers stub, not KE, so only
        -- the brackets and the refusal are asserted.
        local s = { __tag = "secret-duration" }
        SECRET[s] = true
        local text = DM.ClockText(s)
        assert.is_string(text)
        assert.equals("[", text:sub(1, 1))
        assert.equals("]", text:sub(-1))
        -- The one output that must never come back from this branch.
        assert.are_not.equals("[0:00]", text)
    end)

    -- isSecret is deliberately NOT asserted true above. The loader's
    -- AbbreviateNumbers stub returns a PLAIN string, so the formatter reports
    -- the result as non-secret and ClockText passes that through -- which is
    -- correct: a plain abbreviation should keep its dirty check. Asserting
    -- true here would pin the mock's behaviour instead of KE's.
    it("passes the formatter's secrecy answer through", function()
        local s = { __tag = "secret-duration" }
        SECRET[s] = true
        local _, isSecret = DM.ClockText(s)
        assert.is_false(isSecret)
    end)

    it("HIDES when the abbreviation yields nothing", function()
        -- The formatter falls back to the plain literal "0:00" when
        -- AbbreviateNumbers returns nil, and that must hide rather than render.
        -- Overriding the stub is the only way to reach the branch, and it earns
        -- the tweak: nothing else can produce it, and the acceptance criteria
        -- forbid "[0:00]" outright.
        load({ AbbreviateNumbers = function() return nil end })
        local s = { __tag = "secret-duration" }
        SECRET[s] = true
        assert.is_nil(DM.ClockText(s))
    end)
end)
