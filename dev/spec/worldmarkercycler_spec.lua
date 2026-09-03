-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/worldmarkercycler_spec.lua                     ║
-- ║  World Marker Cycler: selection, reset and priming.      ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- The module's marker choice lives in snippet bodies it BUILDS as strings and
-- hands to the secure environment. These cases run those exact strings as
-- ordinary Lua, so what is under test is the module's own algorithm, never a
-- reimplementation of it. Nothing here models the raid-marker system.
--
-- The boundary, stated because it is easy to overclaim: this proves the LOGIC
-- is right. It cannot prove the restricted environment would accept the body.
-- Every construct used is identical in both, but a future edit that reached for
-- something the restricted environment forbids would pass here and fail in
-- game. Legality is a /reload check, not this file's job.

local L = require("dev.spec._ke_loader")

-- Runs an emitted "avail=newtable() avail[1]=true ..." body and returns the
-- table it built.
local function runAvailBody(body)
    local chunk = assert(loadstring(body))
    local env = { newtable = function() return {} end }
    setfenv(chunk, env)
    chunk()
    return env.avail
end

-- Runs a wrapped click body against a mutable environment standing in for the
-- secure one. Returns the macrotext the body asked for, or nil if it placed
-- nothing. The leading local declaration reproduces the wrap's own
-- "self,button,down" signature.
local function runClickBody(body, env, down)
    local chunk = assert(loadstring("local self, button, down = ...\n" .. body))
    env.next = next
    setfenv(chunk, env)
    local placed
    local selfStub = {
        SetAttribute = function(_, key, value)
            if key == "macrotext" then placed = value end
        end,
    }
    chunk(selfStub, "LeftButton", down)
    return placed
end

-- The module wraps the cycle button first and the clear button second.
local function bodies()
    local _, _, _, wrapped = L.loadWorldMarkerCycler()
    return wrapped[1].body, wrapped[2].body
end

local function availOf(taken)
    local t = {}
    for n = 1, 8 do t[n] = not taken[n] end
    return t
end

describe("WorldMarkerCycler marker selection", function()
    it("places the first free position and records it as the last placement", function()
        local cycle = bodies()
        local order = { 5, 3, 8, 1, 7, 2, 6, 4 }
        local env = { order = order, avail = availOf({ [1] = true, [2] = true }), last = 2 }

        local placed = runClickBody(cycle, env, true)

        assert.equals("/worldmarker [@cursor] 8", placed)
        assert.is_false(env.avail[3])
        assert.equals(3, env.last)
    end)

    it("advances one position past the last placement when nothing is free", function()
        local cycle = bodies()
        -- Differ only in the stored last position, so one table drives them:
        -- a fresh order table, mid-list, and the end-to-first wrap.
        local cases = {
            { last = 0, pos = 1 },
            { last = 3, pos = 4 },
            { last = 7, pos = 8 },
            { last = 8, pos = 1 },
        }
        for _, case in ipairs(cases) do
            local order = { 1, 2, 3, 4, 5, 6, 7, 8 }
            local env = { order = order, avail = availOf({
                [1] = true, [2] = true, [3] = true, [4] = true,
                [5] = true, [6] = true, [7] = true, [8] = true,
            }), last = case.last }

            local placed = runClickBody(cycle, env, true)

            assert.equals("/worldmarker [@cursor] " .. case.pos, placed, "last=" .. case.last)
            assert.equals(case.pos, env.last, "last=" .. case.last)
            assert.is_false(env.avail[case.pos], "last=" .. case.last)
        end
    end)

    it("refuses without touching state on key-up, no order, or an empty order", function()
        local cycle = bodies()
        -- One assertion, three refusal inputs: the guard's three clauses.
        local cases = {
            { name = "key-up", order = { 1, 2, 3 }, down = false },
            { name = "no order table", order = nil, down = true },
            { name = "empty order", order = {}, down = true },
        }
        for _, case in ipairs(cases) do
            local env = { order = case.order, avail = availOf({}), last = 4 }

            local placed = runClickBody(cycle, env, case.down)

            assert.is_nil(placed, case.name)
            assert.equals(4, env.last, case.name)
            assert.is_true(env.avail[1], case.name)
        end
    end)
end)

describe("WorldMarkerCycler clear reset", function()
    it("frees every position on key-down and leaves the order alone", function()
        local _, clear = bodies()
        local order = { 5, 3, 8, 1, 7, 2, 6, 4 }
        local env = { order = order, avail = availOf({
            [1] = true, [2] = true, [3] = true, [4] = true,
            [5] = true, [6] = true, [7] = true, [8] = true,
        }), last = 6 }

        runClickBody(clear, env, true)

        for n = 1, 8 do assert.is_true(env.avail[n], "position " .. n) end
        assert.same({ 5, 3, 8, 1, 7, 2, 6, 4 }, env.order)
    end)

    it("does nothing on key-up", function()
        local _, clear = bodies()
        local env = { order = { 1, 2, 3 }, avail = availOf({ [1] = true }), last = 1 }

        runClickBody(clear, env, false)

        assert.is_false(env.avail[1])
    end)
end)

describe("WorldMarkerCycler availability priming", function()
    it("flags each ORDER POSITION by the marker sitting at it, not by marker id", function()
        -- Permuted deliberately: in the default { 1, 2, ... 8 } a position and
        -- the marker id at it coincide, so an identity list cannot tell the two
        -- indexings apart and would pass either way.
        local order = { 5, 3, 8, 1, 7, 2, 6, 4 }
        local active = { [1] = true, [3] = true, [6] = true }

        local WMC, _, executed = L.loadWorldMarkerCycler({
            IsRaidMarkerActive = function(id) return active[id] == true end,
        })
        WMC.db = { OrderList = order }

        WMC:PrimeAvailability()

        local avail = runAvailBody(executed[#executed].body)
        for pos, id in ipairs(order) do
            assert.equals(not active[id], avail[pos], "position " .. pos)
        end
    end)

    it("refuses to prime in combat, emitting nothing", function()
        local WMC, _, executed = L.loadWorldMarkerCycler({
            InCombatLockdown = function() return true end,
        })
        WMC.db = { OrderList = { 1, 2, 3 } }
        local before = #executed

        WMC:PrimeAvailability()

        assert.equals(before, #executed)
    end)
end)
