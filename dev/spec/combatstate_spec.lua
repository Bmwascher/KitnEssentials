-- Tier 2: Core/CombatState.lua, the shared combat clock/liveness machine.
-- Driven entirely through the public event entry points, plus Freeze itself
-- for the one case that is otherwise unreachable, with all seven deps faked
-- and a manual scheduler whose handles record their own cancels. Specs read
-- a handful of internal fields directly (playerCombat, groupOnly, watching,
-- pvpBlocked, finalizePending, pendingGen, clearTicks, fineBase, fineAnchor):
-- the class keeps no closure privacy over them, and several design cases have
-- no cheaper public accessor.
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

-- The poll ticker is always armed at 0.25s; the clock ticker is always 0.5s
-- (coarse) or 0.1s (fine), so the two are distinguishable by interval alone.
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
    local KE, sched, deps, declaredSecret

    before_each(function()
        KE, declaredSecret = L.loadCombatState()
        sched = newScheduler()
        deps = {
            now = function() return 0 end,
            playerInCombat = function() return false end,
            groupInCombat = function() return false end,
            inInstance = function() return false end,
            sessionDuration = function() return false, nil end,
            after = sched.after,
            ticker = sched.ticker,
        }
    end)

    local function newCS()
        return KE.CombatState.New(deps)
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

    describe("PlayerJoined", function()
        it("is false for a group-flag fight with the player out of combat, and true once the player enters it", function()
            local cs = newCS()
            deps.playerInCombat = function() return false end
            cs:OnEncounterStart()
            assert.is_false(cs:PlayerJoined())
            deps.playerInCombat = function() return true end
            cs:OnRegenDisabled()
            assert.is_true(cs:PlayerJoined())
        end)

        it("resets at the next start, so a group-only fight following a joined one is not credited", function()
            local cs = newCS()
            deps.playerInCombat = function() return false end
            cs:OnEncounterStart()
            deps.playerInCombat = function() return true end
            cs:OnRegenDisabled()
            assert.is_true(cs:PlayerJoined())
            cs:OnEncounterEnd(1)
            assert.is_false(cs:IsLive())
            deps.playerInCombat = function() return false end
            deps.inInstance = function() return true end
            deps.groupInCombat = function() return true end
            cs:OnUnitFlags("raid1")
            assert.is_true(cs:IsLive())
            assert.is_false(cs:PlayerJoined())
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

    describe("clock ticker and cadence", function()
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
            local d, frac = rec.nth("OnClockTick", 1)
            assert.equals(6, d)
            assert.is_number(frac)
        end)

        it("the cadence is fine while any key wants it and coarse when none does, across two keys", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            assert.equals(0.5, lastClock(sched).sec)
            cs:SetFineCadence("A", true)
            assert.equals(0.1, lastClock(sched).sec)
            cs:SetFineCadence("B", true)
            assert.equals(0.1, lastClock(sched).sec)
            cs:SetFineCadence("A", false)
            assert.equals(0.1, lastClock(sched).sec)
            cs:SetFineCadence("B", false)
            assert.equals(0.5, lastClock(sched).sec)
        end)

        it("a cadence change replaces the ticker and samples at once", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            local before = lastClock(sched)
            deps.sessionDuration = function() return true, 4 end
            cs:SetFineCadence("A", true)
            assert.is_true(before.cancelled)
            local after = lastClock(sched)
            assert.are_not.equal(before, after)
            assert.is_false(after.cancelled)
            -- Sampled by the change itself, without firing the new ticker:
            -- waiting out its first interval leaves both surfaces stale.
            assert.equals(4, cs:GetDuration())
        end)

        it("a cadence call that changes nothing neither replaces the ticker nor samples", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            local before = lastClock(sched)
            deps.sessionDuration = function() return true, 9 end
            cs:SetFineCadence("A", false)
            assert.is_false(before.cancelled)
            assert.equals(before, lastClock(sched))
            assert.is_nil(cs:GetDuration())
        end)

        it("UnregisterListener drops that key's cadence request", function()
            local cs = newCS()
            cs:OnRegenDisabled()
            cs:RegisterListener("mod", {})
            cs:SetFineCadence("mod", true)
            assert.equals(0.1, lastClock(sched).sec)
            cs:UnregisterListener("mod")
            assert.equals(0.5, lastClock(sched).sec)
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

    describe("the tenths fraction", function()
        it("re-anchors when the sampled second changes and clamps at 0.9 within a second", function()
            local cs = newCS()
            local nowValue = 100
            deps.now = function() return nowValue end
            deps.sessionDuration = function() return true, 5 end
            cs:OnRegenDisabled()
            local clock = lastClock(sched)
            local rec = newRecorder()
            cs:RegisterListener("spec", rec.callbacks)

            clock.fn()
            local _, frac1 = rec.nth("OnClockTick", 1)
            assert.equals(0, frac1)

            nowValue = 100.95
            clock.fn()
            local _, frac2 = rec.nth("OnClockTick", 2)
            assert.equals(0.9, frac2)

            nowValue = 101.0
            deps.sessionDuration = function() return true, 6 end
            clock.fn()
            local d3, frac3 = rec.nth("OnClockTick", 3)
            assert.equals(6, d3)
            assert.equals(0, frac3)
        end)

        it("the anchor resets at every start, so a fight opening on the previous fight's last value starts at a zero fraction", function()
            local cs = newCS()
            local nowValue = 100
            deps.now = function() return nowValue end
            deps.sessionDuration = function() return true, 5 end
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            nowValue = 100.9
            lastClock(sched).fn()

            cs:OnEncounterEnd(1)
            deps.inInstance = function() return true end
            deps.groupInCombat = function() return true end
            cs:OnUnitFlags("raid1")

            local rec = newRecorder()
            cs:RegisterListener("spec", rec.callbacks)
            nowValue = 200
            deps.sessionDuration = function() return true, 5 end
            lastClock(sched).fn()
            local _, frac = rec.nth("OnClockTick", 1)
            assert.equals(0, frac)
        end)

        it("the fraction never mutates the pin: GetDuration() stays whole-second across ticks inside one sampled second", function()
            local cs = newCS()
            local nowValue = 100
            deps.now = function() return nowValue end
            deps.sessionDuration = function() return true, 7 end
            cs:OnRegenDisabled()
            local clock = lastClock(sched)
            for _, t in ipairs({ 100, 100.2, 100.5, 100.8, 100.95 }) do
                nowValue = t
                clock.fn()
                assert.equals(7, cs:GetDuration())
            end
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
        it("Promote preserves pin, generation, the tenths anchor, and resets clearTicks", function()
            local cs = newCS()
            local nowValue = 50
            deps.now = function() return nowValue end
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
            assert.equals(4, cs.fineBase)
            assert.equals(50, cs.fineAnchor)
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
        it("a start broadcasts OnClockTick(nil, 0) before any sample, so neither surface shows the previous fight's text", function()
            local cs = newCS()
            local rec = newRecorder()
            cs:RegisterListener("spec", rec.callbacks)
            local sampled = false
            deps.sessionDuration = function() sampled = true; return true, 99 end
            cs:OnRegenDisabled()
            local d, frac = rec.nth("OnClockTick", 1)
            assert.is_nil(d)
            assert.equals(0, frac)
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

    describe("the engagement span", function()
        -- The span the Combat Timer renders: the whole engagement, where the pin
        -- is only the current fight.
        local function sampling(value)
            deps.sessionDuration = function() return true, value end
        end

        it("reports the fight itself while nothing has accumulated", function()
            local cs = newCS()
            sampling(12)
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            assert.equals(12, cs:GetDuration())
            assert.equals(12, cs:GetEngagementDuration())
        end)

        it("keeps the trash time when an encounter starts mid-engagement", function()
            local cs = newCS()
            sampling(60)
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            cs:OnEncounterStart()
            sampling(5)
            lastClock(sched).fn()
            assert.equals(5, cs:GetDuration())
            assert.equals(65, cs:GetEngagementDuration())
        end)

        -- The warm-up gap: an encounter start zeroes the pin, so Duration() is
        -- nil until the next usable sample. The span must still be a number, or
        -- the clock blanks at the exact moment the boss engages.
        it("reports the accumulated span while the new fight has no reading yet", function()
            local cs = newCS()
            sampling(60)
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            cs:OnEncounterStart()
            assert.is_nil(cs:GetDuration())
            assert.equals(60, cs:GetEngagementDuration())
        end)

        -- OnEncounterEnd(1) is the freeze route, NOT a combat drop: the
        -- encounter start above leaves inEncounter raised, and
        -- PLAYER_REGEN_ENABLED then demotes to groupOnly and arms the poll
        -- instead of freezing.
        it("opens a fresh engagement on the next fight after a freeze", function()
            local cs = newCS()
            sampling(60)
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            cs:OnEncounterStart()
            sampling(5)
            lastClock(sched).fn()
            assert.equals(65, cs:GetEngagementDuration())

            cs:OnEncounterEnd(1)
            assert.is_false(cs:IsLive())

            sampling(3)
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            assert.equals(3, cs:GetEngagementDuration())
        end)

        -- A live start that is not a boss pull re-asserts the fight already
        -- running. The session it is about to re-sample is the SAME one, so
        -- folding the pin in would count those seconds twice.
        it("does not fold the pin in twice on a live start that is not an encounter", function()
            local cases = {
                {
                    name = "a second PLAYER_REGEN_DISABLED while playerCombat",
                    groupOnly = false,
                    fire = function(cs) cs:OnRegenDisabled() end,
                },
                {
                    name = "PLAYER_ENTERING_WORLD with the player in combat",
                    groupOnly = false,
                    fire = function(cs)
                        deps.playerInCombat = function() return true end
                        cs:OnEnteringWorld()
                    end,
                },
                {
                    name = "PLAYER_ENTERING_WORLD with the group in combat in an instance",
                    groupOnly = true,
                    fire = function(cs)
                        deps.groupInCombat = function() return true end
                        deps.inInstance = function() return true end
                        cs:OnEnteringWorld()
                    end,
                },
            }
            for _, case in ipairs(cases) do
                -- deps is shared across rows: reset what a row's fire may set,
                -- or row 2's playerInCombat leaks into row 3 and sends it down
                -- the PLAYER branch instead of the GROUP one it exists for.
                deps.playerInCombat = function() return false end
                deps.groupInCombat = function() return false end
                deps.inInstance = function() return false end
                local cs = newCS()
                sampling(9)
                cs:OnRegenDisabled()
                lastClock(sched).fn()
                assert.equals(9, cs:GetEngagementDuration(), case.name)
                case.fire(cs)
                -- The row reached the branch it names, rather than some other
                -- one that happens to give the same span.
                assert.equals(case.groupOnly, cs.groupOnly, case.name)
                lastClock(sched).fn()
                assert.equals(9, cs:GetEngagementDuration(), case.name)
            end
        end)

        -- The case above cannot tell the modes apart: with nothing accumulated
        -- they all give the same answer. Here the accumulator is 60 first.
        --
        -- playerInCombat MUST stay true throughout. With it false
        -- OnEncounterStart asserts groupOnly, the second OnRegenDisabled returns
        -- from Promote before reaching StartFight, the OnEnteringWorld row
        -- misses its branch, and the case passes whatever the modes are.
        it("ends the accumulated engagement on a live start that is not an encounter", function()
            local cases = {
                {
                    name = "a second PLAYER_REGEN_DISABLED while playerCombat",
                    fire = function(cs) cs:OnRegenDisabled() end,
                },
                {
                    name = "PLAYER_ENTERING_WORLD with the player in combat",
                    fire = function(cs) cs:OnEnteringWorld() end,
                },
            }
            for _, case in ipairs(cases) do
                deps.playerInCombat = function() return true end
                local cs = newCS()
                sampling(60)
                cs:OnRegenDisabled()
                lastClock(sched).fn()
                cs:OnEncounterStart()
                sampling(5)
                lastClock(sched).fn()
                assert.equals(65, cs:GetEngagementDuration(), case.name)

                case.fire(cs)
                lastClock(sched).fn()
                assert.equals(5, cs:GetEngagementDuration(), case.name)
            end
        end)

        -- Both arrival branches end the engagement. The one that starts a fight
        -- is covered by the live-start case above; this is the other one, where
        -- the fight survives the loading screen and only the span before it goes.
        it("ends the engagement on a combat-flagged arrival that promotes", function()
            local cs = newCS()
            sampling(60)
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            deps.playerInCombat = function() return false end
            cs:OnEncounterStart()
            sampling(5)
            lastClock(sched).fn()
            assert.is_true(cs.groupOnly)
            assert.equals(65, cs:GetEngagementDuration())

            deps.playerInCombat = function() return true end
            cs:OnEnteringWorld()
            assert.is_true(cs.playerCombat)
            -- The pin survives the promote, so the fight's own 5 stands alone.
            assert.equals(5, cs:GetEngagementDuration())
        end)

        -- A carry needs a fight to carry FROM. Starting an encounter on a frozen
        -- machine must not fold the last fight's pin into the new engagement.
        it("does not carry into an encounter started from a frozen machine", function()
            local cs = newCS()
            sampling(60)
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            cs:Freeze("combat")
            assert.equals(60, cs:GetEngagementDuration())

            sampling(7)
            cs:OnEncounterStart()
            lastClock(sched).fn()
            assert.equals(7, cs:GetEngagementDuration())
        end)

        -- The chat line reports the engagement, so the gate that suppresses it
        -- has to span the engagement too. A player who fought the trash and was
        -- unflagged at the boss pull still fought this engagement.
        it("carries participation across a carrying start and drops it otherwise", function()
            local cs = newCS()
            sampling(60)
            cs:OnRegenDisabled()
            lastClock(sched).fn()
            assert.is_true(cs:PlayerJoined())

            deps.playerInCombat = function() return false end
            cs:OnEncounterStart()
            assert.is_true(cs.groupOnly)
            assert.is_true(cs:PlayerJoined())

            -- A fresh engagement re-derives it: this start carries nothing.
            cs:Freeze("combat")
            deps.groupInCombat = function() return true end
            deps.inInstance = function() return true end
            cs:OnUnitFlags("party1")
            assert.is_true(cs.groupOnly)
            assert.is_false(cs:PlayerJoined())
        end)
    end)

    describe("cases the design's budget lacks", function()
        it("SetFineCadence on an idle machine starts no ticker", function()
            local cs = newCS()
            cs:SetFineCadence("mod", true)
            assert.equals(0, #sched.tickers)
        end)

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
end)
