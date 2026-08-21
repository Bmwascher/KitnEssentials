-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_feign_select_spec.lua                       ║
-- ║  Refusal rules for the Deaths-view feign filter.         ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/DamageMeter/Core.lua headlessly (L.loadDMCore) and
-- tests its two pure functions: DM.SelectFeignRow, which decides WHICH new
-- death row is the feign that was just cast, and DM.ScanFeignAmbiguity, which
-- decides which tagged ids are too ambiguous to act on.
--
-- WHY THESE EARN A SPEC: both are invented branching logic whose whole point
-- is refusing. One property governs the feature -- it must never remove a real
-- death from the list -- and these two functions are where that property is
-- decided. Every failure here is silent in game: too permissive deletes a
-- death nobody notices is missing, too restrictive shows a feign that looks
-- like an ordinary miss.
--
-- The GUARD ORDER is load-bearing too. Both functions test issecretvalue
-- before comparing an id or using it as a table key, and both resolve
-- isLocalPlayer through DM.PlainOwnRow rather than comparing the raw field.
-- The secret cases below pin that routing; without them a build that compared
-- first would pass everything else.
--
-- NOT tested here, per the project's tiered policy: the cast handler, the
-- bounded watch, the two unit predicates and the render filter. Those are
-- event timing, unit state, and a condition one line from its own assertion.
--
-- HONESTY BOUNDARY (see dev/README.md): issecretvalue is a closure over a
-- SECRET table -- values WE declare secret. A pass verifies BRANCH ROUTING
-- given declared inputs, never real 12.1 taint semantics. In-game /reload
-- remains the secret-semantics gate.
local L = require("dev.spec._ke_loader")

local SECRET = {}     -- [value] = true  marks a value "secret"
local DM

before_each(function()
    for k in pairs(SECRET) do SECRET[k] = nil end
    DM = L.loadDMCore({ issecretvalue = function(v) return SECRET[v] == true end })
    assert(DM and DM.SelectFeignRow, "loadDMCore did not expose DM.SelectFeignRow")
    assert(DM.ScanFeignAmbiguity, "loadDMCore did not expose DM.ScanFeignAmbiguity")
end)

-- One death row. isLocalPlayer defaults to false so an "own row" always has to
-- be asked for explicitly -- a test that forgot would fail rather than pass.
local function row(rid, own)
    return { deathRecapID = rid, isLocalPlayer = own == true }
end

describe("SelectFeignRow finds the feign", function()
    it("returns the single new own-row among older rows", function()
        local snap = { [1] = true, [2] = true }
        local rid, status = DM.SelectFeignRow({ row(1, true), row(2, false), row(7, true) }, snap)
        assert.equals(7, rid)
        assert.equals("found", status)
    end)

    it("ignores a new row that is not the player's own", function()
        -- Another hunter's feign, or anyone else's death: not identifiable, so
        -- not actionable. This is the whole reason the feature is own-row only.
        local rid, status = DM.SelectFeignRow({ row(9, false) }, {})
        assert.is_nil(rid)
        assert.equals("none", status)
    end)

    it("picks the own-row when a non-own row arrives at the same time", function()
        local rid, status = DM.SelectFeignRow({ row(9, false), row(10, true) }, {})
        assert.equals(10, rid)
        assert.equals("found", status)
    end)

    it("treats every row as new when there is no snapshot", function()
        local rid, status = DM.SelectFeignRow({ row(4, true) }, nil)
        assert.equals(4, rid)
        assert.equals("found", status)
    end)
end)

describe("SelectFeignRow refusals", function()
    -- "none" keeps the watch running; "ambiguous" stops it. A build that
    -- returned a bare nil for both would keep sampling through an ambiguity it
    -- had already detected, which is how an earlier design tagged real deaths.
    it("refuses TWO new own-rows as ambiguous, not as none", function()
        local rid, status = DM.SelectFeignRow({ row(5, true), row(6, true) }, {})
        assert.is_nil(rid)
        assert.equals("ambiguous", status)
    end)

    it("reports none when nothing is new", function()
        local rid, status = DM.SelectFeignRow({ row(1, true) }, { [1] = true })
        assert.is_nil(rid)
        assert.equals("none", status)
    end)

    it("refuses a recap id of zero or below", function()
        -- The render path already drops these; a row with no openable recap is
        -- not a row this feature may claim.
        assert.is_nil((DM.SelectFeignRow({ row(0, true) }, {})))
        assert.is_nil((DM.SelectFeignRow({ row(-3, true) }, {})))
    end)

    it("skips a SECRET recap id rather than comparing it", function()
        local s = { __tag = "secret-id" }
        SECRET[s] = true
        local rid, status = DM.SelectFeignRow({ row(s, true) }, {})
        assert.is_nil(rid)
        assert.equals("none", status)
    end)

    it("skips a row whose isLocalPlayer is SECRET", function()
        -- Pins that the selection goes through DM.PlainOwnRow, which answers
        -- false for a secret, rather than comparing the raw field.
        local s = { __tag = "secret-own" }
        SECRET[s] = true
        local rid, status = DM.SelectFeignRow({ { deathRecapID = 11, isLocalPlayer = s } }, {})
        assert.is_nil(rid)
        assert.equals("none", status)
    end)

    it("survives a nil source list", function()
        local rid, status = DM.SelectFeignRow(nil, {})
        assert.is_nil(rid)
        assert.equals("none", status)
    end)
end)

describe("ScanFeignAmbiguity", function()
    it("flags a tagged id carried by two own-rows", function()
        local out = {}
        DM.ScanFeignAmbiguity({ row(3, true), row(3, true) }, { [3] = true }, out)
        assert.is_true(out[3])
    end)

    it("leaves a tagged id alone when only one own-row carries it", function()
        local out = {}
        DM.ScanFeignAmbiguity({ row(3, true), row(4, true) }, { [3] = true }, out)
        assert.is_nil(out[3])
    end)

    it("does not flag when the second row is not an own-row", function()
        -- Only own-rows can ever be hidden, so only own-rows can collide.
        -- Counting someone else's row here would suppress a correct tag.
        local out = {}
        DM.ScanFeignAmbiguity({ row(3, true), row(3, false) }, { [3] = true }, out)
        assert.is_nil(out[3])
    end)

    it("ignores a repeated id that is not tagged", function()
        local out = {}
        DM.ScanFeignAmbiguity({ row(8, true), row(8, true) }, { [3] = true }, out)
        assert.is_nil(out[8])
    end)

    it("wipes out at entry, including on a call with no data", function()
        -- The render path reuses one scratch table every paint. A key that
        -- survived a data-less call would suppress a valid tag forever after.
        local out = { [99] = true }
        DM.ScanFeignAmbiguity(nil, { [3] = true }, out)
        assert.is_nil(out[99])
        out[99] = true
        DM.ScanFeignAmbiguity({ row(3, true) }, nil, out)
        assert.is_nil(out[99])
        out[99] = true
        DM.ScanFeignAmbiguity({ row(3, true) }, {}, out)
        assert.is_nil(out[99])
    end)

    it("returns nil for a nil out table rather than throwing", function()
        assert.is_nil(DM.ScanFeignAmbiguity({ row(3, true) }, { [3] = true }, nil))
    end)
end)
