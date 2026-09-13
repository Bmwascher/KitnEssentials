-- luacheck: std lua51+busted
-- Scheduler and lifecycle of MythicPlusTimer_Pull.lua: request coalescing,
-- the rate limit, exclusive batch ownership, stale-delivery refusal and
-- idempotent teardown.
--
-- Stateful fake, stated per the project spec policy: these behaviours ARE
-- the ordering of KE's own deferred callbacks relative to events and
-- lifecycle calls (a request during an owned batch must become exactly one
-- follow-up after delivery; a delivery must be refused when public state
-- moved between build and settle). Ordering has no pure-predicate form, so
-- C_Timer is a queue the spec drains explicitly. The fake proves KE's
-- ordering only; native frame timing, secrecy and layout are in-game checks.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("MPT pull: scheduler and lifecycle", function()
    local MPT, listener
    local now                -- fake clock
    local afters, timers     -- queued C_Timer.After callbacks; NewTimer records
    local plates, units      -- exposed nameplate tokens; per-unit observations
    local counts             -- [token] = forces count handed to the calculator
    local criteria           -- [token] = criteria reads this build made
    local endpoint           -- what the endpoint bar's GetRight returns
    local shown, cleared     -- SetPullDisplay records / ClearPullDisplay count
    local bars               -- StatusBars the calculator created

    local function drain()
        while #afters > 0 do
            local fn = table.remove(afters, 1)
            fn()
        end
    end
    local function liveTimers()
        local n = 0
        for _, t in ipairs(timers) do if not t.cancelled then n = n + 1 end end
        return n
    end
    local function fireTimers()
        local pending = timers
        timers = {}
        for _, t in ipairs(pending) do
            if not t.cancelled then t.fn() end
        end
    end
    local function cycle()   -- the build timer, then both settle frames
        fireTimers()
        drain()
    end

    before_each(function()
        now, afters, timers = 0, {}, {}
        plates, units, counts, bars, criteria = {}, {}, {}, {}, {}
        endpoint = 49
        shown, cleared = {}, 0
        local frames = mock.install({
            GetTime = function() return now end,
            C_Timer = {
                After = function(_, fn) afters[#afters + 1] = fn end,
                NewTimer = function(delay, fn)
                    local t = { delay = delay, fn = fn, cancelled = false }
                    function t:Cancel() self.cancelled = true end
                    timers[#timers + 1] = t
                    return t
                end,
                NewTicker = function() return { Cancel = function() end } end,
            },
        })
        -- Calculator bars record SetValue; GetStatusBarTexture returns the bar
        -- itself so the chain anchors resolve; GetRight reads the spec's endpoint.
        local baseCreate = _G.CreateFrame
        _G.CreateFrame = function(kind, ...)
            local f = baseCreate(kind, ...)
            if kind == "StatusBar" then
                f.values = {}
                function f:SetValue(v) self.values[#self.values + 1] = v end
                function f:GetStatusBarTexture() return self end
                function f:GetRight() return endpoint end
                function f:Show() self.shown = true end
                function f:Hide() self.shown = false end
                bars[#bars + 1] = f
            end
            return f
        end
        local modules = helpers.installAddonShim()
        _G.UnitExists = function(u) return units[u] ~= nil end
        _G.UnitIsDeadOrGhost = function(u) return units[u].dead end
        _G.UnitCanAttack = function() return true end
        _G.UnitThreatSituation = function() return 0 end
        _G.UnitPlayerControlled = function() return false end
        _G.C_NamePlate = { GetNamePlates = function()
            local out = {}
            for i, token in ipairs(plates) do out[i] = { unitToken = token } end
            return out
        end }
        _G.C_ScenarioInfo = { GetUnitCriteriaProgressValues = function(u)
            criteria[u] = (criteria[u] or 0) + 1
            return counts[u]
        end }
        _G.C_StringUtil = { RoundToNearestString = function(v) return "r" .. tostring(v) end }
        _G.AbbreviateNumbers = function(v) return "p" .. tostring(v) end
        _G.CreateAbbreviateConfig = function() return {} end

        helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer_Pull.lua",
            { Print = function() end })
        MPT = modules["MythicPlusTimer"]
        assert(MPT and MPT.SyncPullEstimate, "real MythicPlusTimer_Pull.lua did not load")
        listener = frames[1]
        MPT.db = { Enabled = true, ShowForces = true, ShowPullOverlay = true }
        MPT.run = { active = true, completed = false,
                    forces = { total = 290, current = 204, completed = false } }
        MPT.isPreview = nil
        MPT.SetPullDisplay = function(_, count, countText, percentText)
            shown[#shown + 1] = { count, countText, percentText }
        end
        MPT.ClearPullDisplay = function() cleared = cleared + 1 end

        plates = { "nameplate1", "nameplate2" }
        units.nameplate1, units.nameplate2 = { dead = false }, { dead = false }
        counts.nameplate1, counts.nameplate2 = 20, 29
    end)

    after_each(function() mock.reset() end)

    it("a burst of requests coalesces into one rate-limited build", function()
        MPT:SyncPullEstimate()
        for _ = 1, 4 do MPT:RequestPullEstimate() end
        assert.are.equal(1, liveTimers())
        assert.are.equal(0, timers[1].delay)
        cycle()
        assert.are.equal(1, #shown)
        assert.are.same({ 49, "r49", "p49" }, shown[1])
        -- origin bar plus one bar per counted unit, each fed its count directly
        assert.are.equal(3, #bars)
        assert.are.equal(0, bars[1].values[1])
        assert.are.equal(20, bars[2].values[1])
        assert.are.equal(29, bars[3].values[1])
        -- the next request inside the interval waits out the remainder
        now = 0.03
        MPT:RequestPullEstimate()
        assert.are.equal(1, liveTimers())
        assert.is_true(math.abs(timers[1].delay - 0.07) < 1e-9)
    end)

    it("work during an owned batch never rebuilds the pool and yields one follow-up", function()
        MPT:SyncPullEstimate()
        fireTimers()                                   -- build; the batch owns the pool
        local built, fed = #bars, #bars[2].values
        MPT:RequestPullEstimate()
        listener:Fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
        MPT:SyncPullEstimate()
        assert.are.equal(0, liveTimers())
        assert.are.equal(built, #bars)
        -- the borrowed bars are untouched until the batch settles
        assert.is_true(bars[2].shown)
        assert.are.equal(fed, #bars[2].values)
        drain()                                        -- both settle frames
        assert.are.equal(1, #shown)
        assert.are.equal(1, liveTimers())              -- exactly one follow-up
        fireTimers()
        assert.are.equal(built, #bars)                 -- the follow-up reuses the pool
    end)

    it("delivery is refused when public state moved during settlement", function()
        local cases = {
            { name = "credited count changed", mut = function() MPT.run.forces.current = 220 end },
            { name = "total changed",          mut = function() MPT.run.forces.total = 300 end },
            { name = "plate left",             mut = function() plates = { "nameplate1" } end },
            { name = "plate joined", mut = function()
                plates[3] = "nameplate3"; units.nameplate3 = { dead = false }; counts.nameplate3 = 5
            end },
            { name = "token recycled", mut = function()
                listener:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
                listener:Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
            end },
            { name = "eligibility lost",       mut = function() MPT.run.forces.completed = true end },
        }
        for _, c in ipairs(cases) do
            MPT:ClearPullEstimate()
            plates = { "nameplate1", "nameplate2" }
            MPT.run = { active = true, completed = false,
                        forces = { total = 290, current = 204, completed = false } }
            shown = {}
            MPT:SyncPullEstimate()
            fireTimers()
            c.mut()
            drain()
            assert.are.equal(0, #shown, c.name)
            assert.are.equal(1, liveTimers(), c.name .. ": one follow-up scheduled")
        end
    end)

    it("a clear between build and settle makes the old delivery inert", function()
        local cases = {
            { name = "stays cleared", resync = false, shown = 0, timers = 0, registered = false },
            -- a replacement built after the clear settles alone: the old
            -- callbacks must not release its pool or schedule on its behalf
            { name = "resynced", resync = true, shown = 1, timers = 0, registered = true },
        }
        for _, c in ipairs(cases) do
            shown, timers, afters = {}, {}, {}
            MPT:ClearPullEstimate()
            MPT:SyncPullEstimate()
            fireTimers()                               -- old batch built; settle frames queued
            MPT:ClearPullEstimate()
            if c.resync then
                MPT:SyncPullEstimate()
                fireTimers()                           -- replacement built behind the old frames
            end
            drain()
            assert.are.equal(c.shown, #shown, c.name)
            assert.are.equal(c.timers, liveTimers(), c.name)
            assert.are.equal(c.registered, listener:IsEventRegistered("NAME_PLATE_UNIT_ADDED"), c.name)
        end
    end)

    it("only nameplate tokens request a build, and identical tokens deduplicate", function()
        MPT:SyncPullEstimate()
        cycle()
        listener:Fire("UNIT_FLAGS", "player")
        listener:Fire("UNIT_TARGET", "party1")
        listener:Fire("UNIT_THREAT_LIST_UPDATE", "target")
        assert.are.equal(0, liveTimers())
        listener:Fire("UNIT_FLAGS", "nameplate2")
        assert.are.equal(1, liveTimers())
        plates = { "nameplate1", "nameplate1" }
        criteria = {}
        cycle()
        assert.are.equal(2, #shown)
        -- the duplicated token is read once and fed once: origin plus ONE bar,
        -- no bar beyond the first build's three
        assert.are.equal(1, criteria.nameplate1)
        assert.are.equal(3, #bars)
        assert.are.equal(20, bars[2].values[#bars[2].values - 1])
        assert.is_false(bars[3].shown)
    end)

    it("no admitted units clears; teardown cancels, unregisters and repeats harmlessly", function()
        local empties = {
            { name = "no plates", apply = function() plates = {} end },
            { name = "no counts", apply = function() counts = {} end },
        }
        for _, e in ipairs(empties) do
            plates = { "nameplate1", "nameplate2" }
            counts.nameplate1, counts.nameplate2 = 20, 29
            MPT:ClearPullEstimate()
            shown, cleared = {}, 0
            MPT:SyncPullEstimate()
            cycle()
            assert.are.equal(1, #shown, e.name)
            e.apply()
            MPT:RequestPullEstimate()
            cycle()
            assert.are.equal(1, #shown, e.name)
            assert.is_true(cleared >= 1, e.name)
            for _, b in ipairs(bars) do assert.is_false(b.shown, e.name) end
        end

        MPT:RequestPullEstimate()
        assert.is_true(listener:IsEventRegistered("UNIT_THREAT_LIST_UPDATE"))
        local pending = timers[#timers]
        assert.is_false(pending.cancelled)
        MPT:ClearPullEstimate()
        assert.is_true(pending.cancelled)
        assert.is_false(listener:IsEventRegistered("UNIT_THREAT_LIST_UPDATE"))
        local before = cleared
        MPT:ClearPullEstimate()
        assert.are.equal(before + 1, cleared)
        MPT:RequestPullEstimate()
        assert.are.equal(0, liveTimers())
    end)
end)
