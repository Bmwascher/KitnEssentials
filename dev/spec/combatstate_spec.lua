-- Tier 2: Core/CombatState.lua, the shared combat clock/liveness machine.
-- Driven entirely through the public event entry points, plus Freeze itself
-- for the one case that is otherwise unreachable, with every dep faked
-- and a manual scheduler whose handles record their own cancels. Specs read
-- a handful of internal fields directly (playerCombat, groupOnly, watching,
-- pvpBlocked, groupBlocked, inEncounter, finalizePending, pendingGen,
-- clearTicks); the group bound's count-restart case
-- sets inEncounter and finalizePending for one tick, and its block case
-- clears groupBlocked for one row: the class keeps no closure privacy over
-- them, and several design cases have no cheaper public accessor.
local L = require("dev.spec._ke_loader")

local function newScheduler()
    local sched = { afters = {}, tickers = {} }
    local function makeHandle(list, sec, fn)
        local h = { sec = sec, fn = fn, cancelled = false }
        h.Cancel = function() h.cancelled = true end
        list[#list + 1] = h
        return h
    end
    sched.after = function(sec, fn) return makeHandle(sched.afters, sec, fn) end
    sched.ticker = function(sec, fn) return makeHandle(sched.tickers, sec, fn) end
    return sched
end

local function lastWithSec(list, sec)
    for i = #list, 1, -1 do
        if list[i].sec == sec then return list[i] end
    end
end

-- The poll ticker is always armed at 0.25s and the clock ticker at 0.5s, so
-- the two are distinguishable by interval alone.
local function lastPoll(sched) return lastWithSec(sched.tickers, 0.25) end
local function lastClock(sched)
    for i = #sched.tickers, 1, -1 do
        if sched.tickers[i].sec ~= 0.25 then return sched.tickers[i] end
    end
end
local function lastAfter(sched) return sched.afters[#sched.afters] end

-- Records every listener callback fired, in order, so a spec can count calls,
-- read a specific call's arguments, or assert relative ORDER between two
-- event names.
local function newRecorder()
    local log = {}
    local function make(name)
        return function(a, b) log[#log + 1] = { name, a, b } end
    end
    local rec = {
        callbacks = {
            OnStart = make("OnStart"),
            OnStop = make("OnStop"),
            OnGroupClear = make("OnGroupClear"),
            OnClockTick = make("OnClockTick"),
        },
    }
    function rec.count(name)
        local n = 0
        for _, e in ipairs(log) do if e[1] == name then n = n + 1 end end
        return n
    end
    function rec.nth(name, index)
        local n = 0
        for _, e in ipairs(log) do
            if e[1] == name then
                n = n + 1
                if n == index then return e[2], e[3] end
            end
        end
    end
    function rec.order(names)
        local out = {}
        for _, e in ipairs(log) do
            if names[e[1]] then out[#out + 1] = e[1] end
        end
        return out
    end
    return rec
end

describe("CombatState machine", function()
    local KE, sched, deps, declaredSecret, events

    before_each(function()
        KE, declaredSecret = L.loadCombatState()
        sched = newScheduler()
        events = {}
        deps = {
            playerInCombat = function() return false end,
            groupInCombat = function() return false end,
            inInstance = function() return false end,
            sessionDuration = function() return false, nil end,
            playerDead = function() return false end,
            playerLockdown = function() return false end,
            encounterLive = function() return true end,
            after = sched.after,
            ticker = sched.ticker,
            setEventsActive = function(on) events[#events + 1] = on end,
        }
    end)

    -- In the game the meter is registered before any of these drives. Seeded
    -- into the table, not through RegisterListener, whose first-listener derive
    -- would read whatever deps a case set before calling this; a recorder
    -- registered later is then a second key and derives nothing.
    local function newCS()
        local cs = KE.CombatState.New(deps)
        cs.listeners.base = {}
        return cs
    end

    describe("start and freeze basics", function()
        it("a player combat start makes the machine live and reports the session's duration", function()
            local cs = newCS()
            deps.sessionDuration = function() return true, 12 end
            cs:OnRegenDisabled()
            assert.is_true(cs:IsLive())
            lastClock(sched).fn()
            assert.equals(12, cs:GetDuration())
        end)

        -- Split from the table above because it needs a different sample shape.
        -- A secret NUMBER passes type() and the > 0 comparison, so the secrecy
        -- guard is the only thing that can reject it: delete that guard and the
        -- pin moves to 7 and this fails.
        it("a secret number is rejected by the secrecy guard, not the type guard", function()
            local cs = newCS()
            deps.sessionDuration = function() return true, 5 end
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            assert.equals(5, cs:GetDuration())
            declaredSecret[7] = true
            deps.sessionDuration = function() return true, 7 end
            lastClock(sched).fn()
            assert.equals(5, cs:GetDuration())
        end)

        it("an unusable sample leaves the pin alone", function()
            local cases = {
                { name = "a failed call", raw = function() return false, 99 end },
                { name = "nil", raw = function() return true, nil end },
                { name = "a non-number", raw = function() return true, "oops" end },
                { name = "zero", raw = function() return true, 0 end },
            }
            for _, case in ipairs(cases) do
                local cs = newCS()
                deps.sessionDuration = function() return true, 5 end
                cs:OnRegenDisabled()
                lastClock(sched).fn()
                assert.equals(5, cs:GetDuration(), case.name)
                deps.sessionDuration = case.raw
                lastClock(sched).fn()
                assert.equals(5, cs:GetDuration(), case.name)
            end
        end)

        it("the freeze pins the last good duration", function()
            local cs = newCS()
            deps.sessionDuration = function() return true, 9 end
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            assert.equals(9, cs:GetDuration())
            deps.sessionDuration = function() return true, 11 end
            cs:OnPvPMatchComplete()
            assert.equals(11, cs:GetDuration())
        end)

        it("the freeze keeps the warm pin when the final read has rolled to a smaller session", function()
            local cs = newCS()
            deps.sessionDuration = function() return true, 9 end
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            assert.equals(9, cs:GetDuration())
            deps.sessionDuration = function() return true, 3 end
            cs:OnPvPMatchComplete()
            assert.equals(9, cs:GetDuration())
        end)
    end)

    describe("re-start and re-entry while live", function()
        it("a second PLAYER_REGEN_DISABLED while live fires no second OnStart, but resets the pin and bumps the generation", function()
            local cs = newCS()
            local rec = newRecorder()
            cs:RegisterListener("spec", rec.callbacks)
            deps.sessionDuration = function() return true, 9 end
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            assert.equals(9, cs:GetDuration())
            local genBefore = cs:Generation()
            cs:OnRegenDisabled()
            assert.equals(1, rec.count("OnStart"))
            assert.is_nil(cs:GetDuration())
            assert.equals(genBefore + 1, cs:Generation())
        end)

        it("ENCOUNTER_START asserts a new fight while already live: generation bumps, pin resets", function()
            local cs = newCS()
            deps.sessionDuration = function() return true, 9 end
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            local genBefore = cs:Generation()
            cs:OnEncounterStart()
            assert.equals(genBefore + 1, cs:Generation())
            assert.is_nil(cs:GetDuration())
        end)

        it("ENCOUNTER_START with the player out of combat asserts groupOnly and arms the poll", function()
            local cs = newCS()
            deps.playerInCombat = function() return false end
            cs:OnEncounterStart()
            assert.is_true(cs.groupOnly)
            assert.is_false(cs.playerCombat)
            local poll = lastPoll(sched)
            assert.is_not_nil(poll)
            assert.is_false(poll.cancelled)
        end)

        it("ENCOUNTER_START with the player in combat asserts playerCombat and clears a previously raised groupOnly, cancelling its poll", function()
            local cs = newCS()
            deps.playerInCombat = function() return false end
            cs:OnEncounterStart()
            local oldPoll = lastPoll(sched)
            deps.playerInCombat = function() return true end
            cs:OnEncounterStart()
            assert.is_true(cs.playerCombat)
            assert.is_false(cs.groupOnly)
            assert.is_true(oldPoll.cancelled)
        end)

        it("a PLAYER_ENTERING_WORLD group-only re-derivation clears a previously raised playerCombat", function()
            local cs = newCS()
            deps.sessionDuration = function() return true, 4 end
            cs:OnRegenDisabled()
            assert.is_true(cs.playerCombat)
            deps.playerInCombat = function() return false end
            deps.groupInCombat = function() return true end
            deps.inInstance = function() return true end
            cs:OnEnteringWorld()
            assert.is_true(cs.groupOnly)
            assert.is_false(cs.playerCombat)
        end)
    end)

    describe("the instance and pvpBlocked gate on a group flag", function()
        it("starts the fight only inside an instance while not pvpBlocked", function()
            local cases = {
                { name = "outside an instance", inInstance = false, pvpBlocked = false, expectLive = false },
                { name = "while pvpBlocked", inInstance = true, pvpBlocked = true, expectLive = false },
                { name = "inside an instance, unblocked", inInstance = true, pvpBlocked = false, expectLive = true },
            }
            deps.groupInCombat = function() return true end
            for _, case in ipairs(cases) do
                local cs = newCS()
                deps.inInstance = function() return case.inInstance end
                if case.pvpBlocked then cs:OnPvPMatchComplete() end
                cs:OnUnitFlags("raid1")
                assert.equals(case.expectLive, cs:IsLive(), case.name)
            end
        end)

        it("pvpBlocked is cleared by a real PLAYER_REGEN_DISABLED, which starts", function()
            local cs = newCS()
            cs:OnPvPMatchComplete()
            cs:OnRegenDisabled()
            assert.is_false(cs.pvpBlocked)
            assert.is_true(cs:IsLive())
        end)
    end)

    describe("combat drop and the encounter dwell", function()
        it("the player leaving combat with the group clear freezes immediately", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            deps.groupInCombat = function() return false end
            cs:OnRegenEnabled()
            assert.is_true(cs:IsFrozen())
            assert.is_false(cs:IsLive())
        end)

        it("the player leaving combat with the group still fighting sets groupOnly and defers to the poll, which freezes on a later clear tick", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            deps.groupInCombat = function() return true end
            cs:OnRegenEnabled()
            assert.is_true(cs.groupOnly)
            assert.is_false(cs.playerCombat)
            assert.is_false(cs:IsFrozen())
            deps.groupInCombat = function() return false end
            lastPoll(sched).fn()
            assert.is_true(cs:IsFrozen())
        end)

        it("a combat drop during an encounter does not freeze", function()
            local cs = newCS()
            deps.playerInCombat = function() return true end
            cs:OnEncounterStart()
            deps.groupInCombat = function() return false end
            cs:OnRegenEnabled()
            assert.is_false(cs:IsFrozen())
            assert.is_true(cs:IsLive())
            assert.is_true(cs.groupOnly)
        end)

        it("a group clear during an unfinished encounter freezes only after the 5 second dwell", function()
            local cs = newCS()
            deps.playerInCombat = function() return true end
            cs:OnEncounterStart()
            deps.groupInCombat = function() return false end
            cs:OnRegenEnabled()
            local poll = lastPoll(sched)
            for _ = 1, 19 do
                poll.fn()
                assert.is_false(cs:IsFrozen())
            end
            poll.fn()
            assert.is_true(cs:IsFrozen())
        end)

        it("a single non-clear tick inside the dwell resets it", function()
            local cs = newCS()
            deps.playerInCombat = function() return true end
            cs:OnEncounterStart()
            deps.groupInCombat = function() return false end
            cs:OnRegenEnabled()
            local poll = lastPoll(sched)
            for _ = 1, 15 do poll.fn() end
            deps.groupInCombat = function() return true end
            poll.fn()
            deps.groupInCombat = function() return false end
            for _ = 1, 19 do
                poll.fn()
                assert.is_false(cs:IsFrozen())
            end
            poll.fn()
            assert.is_true(cs:IsFrozen())
        end)
    end)

    describe("ENCOUNTER_END", function()
        it("a kill freezes immediately", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            cs:OnEncounterEnd(1)
            assert.is_true(cs:IsFrozen())
            assert.is_false(cs:IsLive())
        end)

        it("a non-kill defers, then freezes when the group is clear", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            cs:OnEncounterEnd(nil)
            assert.is_false(cs:IsFrozen())
            deps.groupInCombat = function() return false end
            deps.playerInCombat = function() return false end
            lastAfter(sched).fn()
            assert.is_true(cs:IsFrozen())
        end)

        it("a non-kill defers, then continues when the group is still fighting", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            cs:OnEncounterEnd(nil)
            deps.groupInCombat = function() return true end
            deps.playerInCombat = function() return true end
            lastAfter(sched).fn()
            assert.is_false(cs:IsFrozen())
            assert.is_true(cs:IsLive())
            assert.is_false(cs.finalizePending)
            -- A player rezzed inside the window keeps playerCombat; demoting
            -- them to groupOnly would arm a poll for a fight they are in.
            assert.is_true(cs.playerCombat)
            assert.is_false(cs.groupOnly)
        end)

        it("a deferred non-kill evaluation whose generation has moved does nothing", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            cs:OnEncounterEnd(nil)
            local stale = lastAfter(sched)
            cs:OnRegenDisabled()
            local gen = cs:Generation()
            local live = cs:IsLive()
            local playerCombat = cs.playerCombat
            stale.fn()
            assert.equals(gen, cs:Generation())
            assert.equals(live, cs:IsLive())
            assert.equals(playerCombat, cs.playerCombat)
        end)
    end)

    describe("freeze edge cases", function()
        it("a freeze reaching a machine that is not live fires no listener and touches nothing", function()
            local cs = newCS()
            local rec = newRecorder()
            cs:RegisterListener("spec", rec.callbacks)
            cs:Freeze("test")
            assert.equals(0, rec.count("OnStop"))
            assert.equals(0, rec.count("OnClockTick"))
            assert.is_false(cs:IsFrozen())
            assert.is_nil(cs:GetDuration())
        end)

        it("PLAYER_REGEN_ENABLED on a machine that is not live sets no groupOnly and leaves the machine startable", function()
            local cs = newCS()
            deps.groupInCombat = function() return false end
            cs:OnRegenEnabled()
            assert.is_false(cs.groupOnly)
            assert.is_false(cs:IsLive())
            cs:OnRegenDisabled()
            assert.is_true(cs:IsLive())
        end)

        it("a freeze that leaves the group still fighting leaves the machine watching", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            deps.groupInCombat = function() return true end
            cs:OnEncounterEnd(1)
            assert.is_true(cs.watching)
        end)

        it("a PVP_MATCH_COMPLETE freeze does not leave the machine watching", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            deps.groupInCombat = function() return true end
            cs:OnPvPMatchComplete()
            assert.is_false(cs.watching)
        end)
    end)

    describe("watch and poll", function()
        it("a watch tick reaching a group clear fires OnGroupClear without freezing", function()
            local cs = newCS()
            local rec = newRecorder()
            cs:RegisterListener("spec", rec.callbacks)
            deps.groupInCombat = function() return true end
            cs:OnRegenEnabled()
            assert.is_true(cs.watching)
            deps.groupInCombat = function() return false end
            lastPoll(sched).fn()
            assert.equals(1, rec.count("OnGroupClear"))
            assert.equals(0, rec.count("OnStop"))
            assert.is_false(cs.watching)
        end)

        it("a poll armed for a player promoted by the non-kill continuation cancels itself", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            cs:OnEncounterEnd(nil)
            deps.groupInCombat = function() return true end
            deps.playerInCombat = function() return true end
            lastAfter(sched).fn()
            local poll = lastPoll(sched)
            poll.fn()
            assert.is_true(poll.cancelled)
        end)

        it("a start arriving during a watch clears watching and produces a live poll", function()
            local cs = newCS()
            deps.groupInCombat = function() return true end
            cs:OnRegenEnabled()
            assert.is_true(cs.watching)
            local watchPoll = lastPoll(sched)
            deps.inInstance = function() return true end
            cs:OnUnitFlags("raid1")
            assert.is_false(cs.watching)
            assert.is_true(cs.groupOnly)
            assert.is_true(watchPoll.cancelled)
            local livePoll = lastPoll(sched)
            assert.is_false(livePoll.cancelled)
        end)

    end)

    describe("PLAYER_ENTERING_WORLD", function()
        it("starts a playerCombat fight, a groupOnly fight inside an instance, or nothing outside one", function()
            local cases = {
                { name = "player in combat", playerInCombat = true, groupInCombat = false, inInstance = false,
                    expectLive = true, expectGroupOnly = false },
                { name = "only the group in combat, inside an instance", playerInCombat = false, groupInCombat = true, inInstance = true,
                    expectLive = true, expectGroupOnly = true },
                { name = "only the group in combat, outside an instance", playerInCombat = false, groupInCombat = true, inInstance = false,
                    expectLive = false, expectGroupOnly = false },
            }
            for _, case in ipairs(cases) do
                local cs = newCS()
                local rec = newRecorder()
                cs:RegisterListener("spec", rec.callbacks)
                deps.playerInCombat = function() return case.playerInCombat end
                deps.groupInCombat = function() return case.groupInCombat end
                deps.inInstance = function() return case.inInstance end
                cs:OnEnteringWorld()
                assert.equals(case.expectLive, cs:IsLive(), case.name)
                assert.equals(case.expectGroupOnly, cs.groupOnly, case.name)
                assert.equals(case.expectLive and 1 or 0, rec.count("OnStart"), case.name)
            end
        end)

        it("out of combat freezes only when the machine was live, preserves the pin, and clears frozen", function()
            local cs = newCS()
            deps.sessionDuration = function() return true, 8 end
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            deps.playerInCombat = function() return false end
            deps.groupInCombat = function() return false end
            deps.sessionDuration = function() return false, nil end
            cs:OnEnteringWorld()
            assert.equals(8, cs:GetDuration())
            assert.is_false(cs:IsFrozen())
            assert.is_false(cs:IsLive())

            local idle = newCS()
            local rec = newRecorder()
            idle:RegisterListener("spec", rec.callbacks)
            idle:OnEnteringWorld()
            assert.equals(0, rec.count("OnStop"))
            assert.is_false(idle:IsFrozen())
        end)
    end)

    describe("listeners", function()
        it("registering the same listener key twice replaces rather than stacks", function()
            local cs = newCS()
            local firstCalls, secondCalls = 0, 0
            cs:RegisterListener("mod", { OnStart = function() firstCalls = firstCalls + 1 end })
            cs:RegisterListener("mod", { OnStart = function() secondCalls = secondCalls + 1 end })
            cs:OnRegenDisabled()
            assert.equals(0, firstCalls)
            assert.equals(1, secondCalls)
        end)
    end)

    describe("the clock ticker", function()
        it("a clock tick samples once, updates the pin, and fires OnClockTick", function()
            local cs = newCS()
            local calls = 0
            deps.sessionDuration = function() calls = calls + 1; return true, 6 end
            cs:OnRegenDisabled()
            local rec = newRecorder()
            cs:RegisterListener("spec", rec.callbacks)
            lastClock(sched).fn()
            assert.equals(1, calls)
            assert.equals(6, cs:GetDuration())
            local d = rec.nth("OnClockTick", 1)
            assert.equals(6, d)
        end)

        it("a freeze and a hard reset each cancel the clock ticker", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            local clock = lastClock(sched)
            deps.groupInCombat = function() return true end
            cs:OnPvPMatchComplete()
            assert.is_true(clock.cancelled)

            local cs2 = newCS()
            cs2:OnRegenDisabled()
            local clock2 = lastClock(sched)
            deps.playerInCombat = function() return false end
            deps.groupInCombat = function() return false end
            cs2:OnEnteringWorld()
            assert.is_true(clock2.cancelled)
        end)

        it("a freeze fires a final OnClockTick before OnStop", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            local rec = newRecorder()
            cs:RegisterListener("spec", rec.callbacks)
            cs:OnPvPMatchComplete()
            local order = rec.order({ OnClockTick = true, OnStop = true })
            assert.same({ "OnClockTick", "OnStop" }, order)
        end)
    end)

    describe("the deferred non-kill callback and finalizePending", function()
        it("PLAYER_REGEN_ENABLED arriving while finalizePending is raised does not freeze", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            cs:OnEncounterEnd(nil)
            assert.is_true(cs.finalizePending)
            cs:OnRegenEnabled()
            assert.is_false(cs:IsFrozen())
            assert.is_true(cs.groupOnly)
            assert.is_false(cs.playerCombat)
        end)

        it("a poll tick arriving while finalizePending is raised does not freeze, and the deferred callback still owns the freeze when it runs", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            cs:OnEncounterEnd(nil)
            cs:OnRegenEnabled()
            deps.groupInCombat = function() return false end
            lastPoll(sched).fn()
            assert.is_false(cs:IsFrozen())
            lastAfter(sched).fn()
            assert.is_true(cs:IsFrozen())
        end)

        it("an older deferred callback cannot clear a newer fight's pending ownership", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            cs:OnEncounterEnd(nil)
            local staleA = lastAfter(sched)
            cs:OnEncounterStart()
            cs:OnEncounterEnd(nil)
            staleA.fn()
            assert.is_true(cs.finalizePending)
            assert.is_not_nil(cs.pendingGen)
        end)

        it("terminal transitions invalidate a pending callback", function()
            local transitions = {
                { name = "a start", run = function(cs) cs:OnEncounterStart() end },
                { name = "PLAYER_ENTERING_WORLD", run = function(cs)
                    deps.playerInCombat = function() return false end
                    deps.groupInCombat = function() return false end
                    cs:OnEnteringWorld()
                end },
                { name = "PVP_MATCH_COMPLETE", run = function(cs) cs:OnPvPMatchComplete() end },
            }
            for _, case in ipairs(transitions) do
                local cs = newCS()
                cs:OnRegenDisabled()
                cs:OnEncounterEnd(nil)
                local stale = lastAfter(sched)
                local rec = newRecorder()
                cs:RegisterListener("spec", rec.callbacks)
                case.run(cs)
                local stopsAfterTransition = rec.count("OnStop")
                stale.fn()
                assert.equals(stopsAfterTransition, rec.count("OnStop"), case.name)
                assert.is_false(cs.finalizePending, case.name)
            end
        end)
    end)

    describe("Promote, and the pvp/watch interplay", function()
        it("Promote preserves pin and generation, and resets clearTicks", function()
            local cs = newCS()
            deps.playerInCombat = function() return false end
            cs:OnEncounterStart()
            deps.sessionDuration = function() return true, 4 end
            lastClock(sched).fn()
            local genBefore = cs:Generation()
            deps.groupInCombat = function() return false end
            local poll = lastPoll(sched)
            for _ = 1, 3 do poll.fn() end
            assert.equals(3, cs.clearTicks)

            cs:OnRegenDisabled()
            assert.equals(4, cs:GetDuration())
            assert.equals(genBefore, cs:Generation())
            assert.equals(0, cs.clearTicks)
        end)

        it("PVP_MATCH_COMPLETE followed by a non-live PLAYER_REGEN_ENABLED leaves the machine not watching", function()
            local cs = newCS()
            cs:OnPvPMatchComplete()
            deps.groupInCombat = function() return true end
            cs:OnRegenEnabled()
            assert.is_false(cs.watching)
        end)
    end)

    describe("the paint contract", function()
        it("a start broadcasts OnClockTick(nil) before any sample, so the meter clock does not show the previous fight's text", function()
            local cs = newCS()
            local rec = newRecorder()
            cs:RegisterListener("spec", rec.callbacks)
            local sampled = false
            deps.sessionDuration = function() sampled = true; return true, 99 end
            cs:OnRegenDisabled()
            local d = rec.nth("OnClockTick", 1)
            assert.is_nil(d)
            assert.is_false(sampled)
            -- OnStart first: a consumer clears its held state there, and a blank
            -- paint arriving before that can be routed by the stale state.
            assert.same({ "OnStart", "OnClockTick" },
                rec.order({ OnStart = true, OnClockTick = true }))
        end)

        it("GetDuration() performs zero session reads", function()
            local cs = newCS()
            local calls = 0
            deps.sessionDuration = function() calls = calls + 1; return true, 5 end
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            local callsAfterTick = calls
            for _ = 1, 5 do cs:GetDuration() end
            assert.equals(callsAfterTick, calls)
        end)
    end)

    describe("cases the design's budget lacks", function()
        it("a live-to-live start does not broadcast the nil paint", function()
            local cs = newCS()
            local rec = newRecorder()
            cs:RegisterListener("spec", rec.callbacks)
            cs:OnRegenDisabled()
            assert.equals(1, rec.count("OnStart"))
            assert.equals(1, rec.count("OnClockTick"))
            cs:OnRegenDisabled()
            assert.equals(1, rec.count("OnStart"))
            assert.equals(1, rec.count("OnClockTick"))
        end)
    end)

    describe("the group bound", function()
        -- A live group hold: the player left combat, alive, outside an
        -- encounter, with the group still reading in combat.
        local function liveHold()
            local cs = newCS()
            cs:OnRegenDisabled()
            deps.groupInCombat = function() return true end
            cs:OnRegenEnabled()
            return cs
        end

        -- A watch: the machine is not live and the group reads in combat.
        local function watchHold()
            local cs = newCS()
            deps.groupInCombat = function() return true end
            cs:OnRegenEnabled()
            return cs
        end

        local function tick(n)
            local poll = lastPoll(sched)
            for _ = 1, n do poll.fn() end
        end

        -- A feign while tagged can leave the unit flag set outside lockdown.
        local function flaggedHold()
            local cs = liveHold()
            deps.playerInCombat = function() return true end
            return cs
        end

        it("ends a hold after 20 poll ticks with the player alive and out of lockdown outside an encounter, not after 19", function()
            local cases = {
                { name = "a live group fight freezes and is not re-watched", setup = liveHold,
                    held = function(cs) return cs:IsLive() end,
                    ended = function(cs) return cs:IsFrozen() and not cs.watching end },
                { name = "a watch ends", setup = watchHold,
                    held = function(cs) return cs.watching end,
                    ended = function(cs) return not cs.watching and lastPoll(sched).cancelled end },
                { name = "the player's unit flag stays set outside lockdown", setup = flaggedHold,
                    held = function(cs) return cs:IsLive() end,
                    ended = function(cs) return cs:IsFrozen() and not cs.watching end },
            }
            for _, case in ipairs(cases) do
                deps.playerInCombat = function() return false end
                local cs = case.setup()
                tick(19)
                assert.is_true(case.held(cs), case.name)
                assert.is_false(cs.groupBlocked, case.name)
                tick(1)
                assert.is_true(case.ended(cs), case.name)
                assert.is_true(cs.groupBlocked, case.name)
            end
        end)

        -- A kill freezes at once, and the freeze re-arms a watch while the
        -- player's own lockdown still lingers.
        local function killWatch()
            deps.playerLockdown = function() return true end
            local cs = newCS()
            cs:OnRegenDisabled()
            deps.groupInCombat = function() return true end
            cs:OnEncounterEnd(1)
            return cs
        end

        local function noop() end

        it("restarts the count on a tick with the player dead, in lockdown, the mark set or a non-kill end pending; a clear read ends the hold unblocked", function()
            local cases = {
                { name = "the player is dead", setup = liveHold,
                    set = function() deps.playerDead = function() return true end end,
                    unset = function() deps.playerDead = function() return false end end,
                    expectLive = true, expectWatching = false },
                { name = "the player is in lockdown", setup = liveHold,
                    set = function() deps.playerLockdown = function() return true end end,
                    unset = function() deps.playerLockdown = function() return false end end,
                    expectLive = true, expectWatching = false },
                { name = "the encounter mark is set", setup = liveHold,
                    set = function(cs) cs.inEncounter = true end,
                    unset = function(cs) cs.inEncounter = false end,
                    expectLive = true, expectWatching = false },
                { name = "a non-kill end is pending", setup = liveHold,
                    set = function(cs) cs.finalizePending = true end,
                    unset = function(cs) cs.finalizePending = false end,
                    expectLive = true, expectWatching = false },
                { name = "the group reads clear", setup = liveHold,
                    set = function() deps.groupInCombat = function() return false end end,
                    unset = function() deps.groupInCombat = function() return true end end,
                    expectLive = false, expectWatching = false },
                { name = "a kill's watch with the lockdown lingering", setup = killWatch,
                    set = noop, unset = noop,
                    expectLive = false, expectWatching = true },
            }
            for _, case in ipairs(cases) do
                deps.playerLockdown = function() return false end
                local cs = case.setup()
                tick(19)
                case.set(cs)
                tick(1)
                case.unset(cs)
                tick(19)
                assert.equals(case.expectLive, cs:IsLive(), case.name)
                assert.equals(case.expectWatching, cs.watching, case.name)
                assert.is_false(cs.groupBlocked, case.name)
            end
        end)

        it("blocks a GROUP restart after a bound end until a clear read, a player start, an encounter start or a loading screen; a clear read reports OnGroupClear", function()
            local cases = {
                { name = "UNIT_FLAGS with the group still in combat",
                    run = function(cs) cs:OnUnitFlags("raid1") end,
                    expectBlocked = true, expectLive = false, expectGroupClear = 0 },
                { name = "GROUP_ROSTER_UPDATE with the group still in combat",
                    run = function(cs) cs:OnRosterUpdate() end,
                    expectBlocked = true, expectLive = false, expectGroupClear = 0 },
                { name = "GROUP_ROSTER_UPDATE reading the group clear",
                    run = function(cs)
                        deps.groupInCombat = function() return false end
                        cs:OnRosterUpdate()
                    end,
                    expectBlocked = false, expectLive = false, expectGroupClear = 1 },
                { name = "UNIT_FLAGS reading the group clear",
                    run = function(cs)
                        deps.groupInCombat = function() return false end
                        cs:OnUnitFlags("raid1")
                    end,
                    expectBlocked = false, expectLive = false, expectGroupClear = 1 },
                { name = "UNIT_FLAGS reading the group clear outside an instance",
                    run = function(cs)
                        deps.inInstance = function() return false end
                        deps.groupInCombat = function() return false end
                        cs:OnUnitFlags("party1")
                    end,
                    expectBlocked = false, expectLive = false, expectGroupClear = 1 },
                { name = "the player's own UNIT_FLAGS reading the group clear",
                    run = function(cs)
                        deps.groupInCombat = function() return false end
                        cs:OnUnitFlags("player")
                    end,
                    expectBlocked = false, expectLive = false, expectGroupClear = 1 },
                { name = "the player's own UNIT_FLAGS with no block starts nothing",
                    run = function(cs)
                        cs.groupBlocked = false
                        cs:OnUnitFlags("player")
                    end,
                    expectBlocked = false, expectLive = false, expectGroupClear = 0 },
                { name = "PLAYER_REGEN_DISABLED",
                    run = function(cs) cs:OnRegenDisabled() end,
                    expectBlocked = false, expectLive = true, expectGroupClear = 0 },
                { name = "ENCOUNTER_START",
                    run = function(cs) cs:OnEncounterStart() end,
                    expectBlocked = false, expectLive = true, expectGroupClear = 0 },
                { name = "PLAYER_ENTERING_WORLD",
                    run = function(cs) cs:OnEnteringWorld() end,
                    expectBlocked = false, expectLive = true, expectGroupClear = 0 },
            }
            for _, case in ipairs(cases) do
                deps.inInstance = function() return true end
                local cs = liveHold()
                tick(20)
                assert.is_true(cs.groupBlocked, case.name)
                local rec = newRecorder()
                cs:RegisterListener("spec", rec.callbacks)
                case.run(cs)
                assert.equals(case.expectBlocked, cs.groupBlocked, case.name)
                assert.equals(case.expectLive, cs:IsLive(), case.name)
                assert.equals(case.expectGroupClear, rec.count("OnGroupClear"), case.name)
            end
        end)

        it("clears an encounter mark the game no longer reports, then applies the bound", function()
            local cs = newCS()
            cs:OnEncounterStart()
            deps.groupInCombat = function() return true end
            deps.encounterLive = function() return false end
            tick(1)
            assert.is_false(cs.inEncounter)
            tick(18)
            assert.is_true(cs:IsLive())
            tick(1)
            assert.is_true(cs:IsFrozen())
        end)
    end)

    describe("the event gate", function()
        -- No listener seeded: these cases are about the first and the last one.
        local function bareCS()
            return KE.CombatState.New(deps)
        end

        it("the first listener turns the events on and starts the fight the game reports, with no OnStart or paint to it", function()
            local cases = {
                { name = "the player in combat", player = true, group = false,
                    expectLive = true, expectGroupOnly = false },
                { name = "only the group in combat, inside an instance", player = false, group = true,
                    expectLive = true, expectGroupOnly = true },
                { name = "nothing in combat", player = false, group = false,
                    expectLive = false, expectGroupOnly = false },
            }
            for _, case in ipairs(cases) do
                events = {}
                sched.tickers = {}
                deps.playerInCombat = function() return case.player end
                deps.groupInCombat = function() return case.group end
                deps.inInstance = function() return true end
                local cs = bareCS()
                assert.same({}, events, case.name)
                assert.equals(0, #sched.tickers, case.name)
                local rec = newRecorder()
                cs:RegisterListener("spec", rec.callbacks)
                assert.same({ true }, events, case.name)
                assert.equals(case.expectLive, cs:IsLive(), case.name)
                assert.equals(case.expectGroupOnly, cs.groupOnly, case.name)
                assert.equals(case.expectLive, lastClock(sched) ~= nil, case.name)
                assert.equals(0, rec.count("OnStart"), case.name)
                assert.equals(0, rec.count("OnClockTick"), case.name)
            end
        end)

        it("a later registration, a second key or the same key again, derives nothing and leaves the events alone", function()
            for _, key in ipairs({ "spec", "other" }) do
                events = {}
                deps.playerInCombat = function() return true end
                local cs = bareCS()
                cs:RegisterListener("spec", {})
                local gen, tickers = cs:Generation(), #sched.tickers
                local rec = newRecorder()
                cs:RegisterListener(key, rec.callbacks)
                assert.same({ true }, events, key)
                assert.equals(gen, cs:Generation(), key)
                assert.equals(tickers, #sched.tickers, key)
            end
        end)

        it("the last listener out turns the events off and drops to idle with no broadcast; one out of two changes nothing", function()
            local cases = {
                { name = "a group fight in an encounter",
                    setup = function(cs) cs:OnEncounterStart() end,
                    held = function(cs) return cs:IsLive() end },
                { name = "a bound end's block",
                    setup = function(cs)
                        deps.groupInCombat = function() return true end
                        cs:OnRegenDisabled()
                        cs:OnRegenEnabled()
                        local poll = lastPoll(sched)
                        for _ = 1, 20 do poll.fn() end
                    end,
                    held = function(cs) return cs.groupBlocked end },
            }
            for _, case in ipairs(cases) do
                events = {}
                deps.groupInCombat = function() return false end
                local cs = bareCS()
                local rec = newRecorder()
                cs:RegisterListener("spec", rec.callbacks)
                cs:RegisterListener("other", {})
                case.setup(cs)
                cs:UnregisterListener("other")
                assert.same({ true }, events, case.name)
                assert.is_true(case.held(cs), case.name)
                local stops = rec.count("OnStop")
                cs:UnregisterListener("spec")
                assert.same({ true, false }, events, case.name)
                for _, h in ipairs(sched.tickers) do
                    assert.is_true(h.cancelled, case.name)
                end
                assert.is_false(cs:IsLive(), case.name)
                assert.is_false(cs:IsFrozen(), case.name)
                assert.is_false(cs.watching, case.name)
                assert.is_false(cs.inEncounter, case.name)
                assert.is_false(cs.groupBlocked, case.name)
                assert.equals(stops, rec.count("OnStop"), case.name)
            end
        end)
    end)
end)
