-- Modules/Dungeons/KickTrackerRules.lua: the kick tracker's pure decisions.
-- Frames, bars, the engine timers and event wiring are checked in game.
local L = require("dev.spec._ke_loader")

describe("KickTracker send decision under the chat lock", function()
    it("sends once, refuses without fan-out, and fans out only on other failures", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "locked sends nothing", locked = true, blocked = nil, results = { 0 },
              outcome = "locked", calls = {}, blockedAfter = nil },
            { name = "success sends once and clears the flag", locked = false, blocked = true, results = { 0 },
              outcome = "sent", calls = { "INSTANCE_CHAT" }, blockedAfter = nil },
            { name = "result 11 sends once and sets the flag", locked = false, blocked = nil, results = { 11 },
              outcome = "refused", calls = { "INSTANCE_CHAT" }, blockedAfter = true },
            { name = "already blocked: no fan-out after a failure", locked = false, blocked = true, results = { 9 },
              outcome = "refused", calls = { "INSTANCE_CHAT" }, blockedAfter = true },
            { name = "another failure fans out", locked = false, blocked = nil, results = { 9 },
              outcome = "fanout", calls = { "INSTANCE_CHAT", "PARTY", "WHISPER:A", "WHISPER:B" }, blockedAfter = nil },
            { name = "11 in the whispers stops them", locked = false, blocked = nil, results = { 9, 9, 11 },
              outcome = "refused", calls = { "INSTANCE_CHAT", "PARTY", "WHISPER:A" }, blockedAfter = true },
        }
        for _, row in ipairs(rows) do
            local calls, n = {}, 0
            local function send(_, _, channel, target)
                n = n + 1
                calls[#calls + 1] = target and (channel .. ":" .. target) or channel
                return true, row.results[math.min(n, #row.results)]
            end
            local state = { commBlocked = row.blocked }
            local outcome = KT.TransmitComm(state, row.locked, send, "KEKick", "msg", true, { "A", "B" })
            assert.equals(row.outcome, outcome, row.name)
            assert.same(row.calls, calls, row.name)
            assert.equals(row.blockedAfter, state.commBlocked, row.name)
        end
    end)
end)

describe("KickTracker HELLO gate", function()
    it("refuses under the lock, lets a forced HELLO past the throttle, and throttles the rest", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "locked, even forced", locked = true, last = nil, now = 100, force = true, allowed = false },
            { name = "forced inside the throttle", locked = false, last = 95, now = 100, force = true, allowed = true },
            { name = "unforced inside the throttle", locked = false, last = 95, now = 100, force = false, allowed = false },
            { name = "first HELLO", locked = false, last = nil, now = 100, force = false, allowed = true },
            { name = "unforced at the throttle", locked = false, last = 90, now = 100, force = false, allowed = true },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.allowed, KT.HelloAllowed(row.locked, row.last, row.now, row.force, 10), row.name)
        end
    end)
end)

describe("KickTracker pairing, either order", function()
    local W = 1.5
    local function fresh() return { claims = {}, paired = {} } end

    it("a KICK claims the only record in the window", function()
        local KT = L.loadKickTrackerRules()
        local result, index = KT.PairComm(fresh(), { { startTime = 8 }, { startTime = 9.5 } }, "A", 10, W)
        assert.equals("claimed", result)
        assert.equals(2, index)
    end)

    it("a KICK with two records in the window claims neither and opens no claim", function()
        local KT = L.loadKickTrackerRules()
        local pairing = fresh()
        assert.equals("ambiguous", (KT.PairComm(pairing, { { startTime = 9.5 }, { startTime = 9.8 } }, "A", 10, W)))
        assert.is_false(KT.PairRecord(pairing, 10.2, W))
    end)

    it("a KICK with no record opens a claim that suppresses the next record once", function()
        local KT = L.loadKickTrackerRules()
        local pairing = fresh()
        assert.equals("opened", (KT.PairComm(pairing, {}, "A", 10, W)))
        assert.is_true(KT.PairRecord(pairing, 10.5, W))
        assert.is_false(KT.PairRecord(pairing, 10.6, W))
    end)

    it("a record with two open claims is shown", function()
        local KT = L.loadKickTrackerRules()
        local pairing = fresh()
        KT.PairComm(pairing, {}, "A", 10, W)
        KT.PairComm(pairing, {}, "B", 10.2, W)
        assert.is_false(KT.PairRecord(pairing, 10.5, W))
    end)

    it("a claim older than the window suppresses nothing", function()
        local KT = L.loadKickTrackerRules()
        local pairing = fresh()
        KT.PairComm(pairing, {}, "A", 10, W)
        assert.is_false(KT.PairRecord(pairing, 11.6, W))
    end)

    it("a second KICK from the same teammate inside the window changes nothing", function()
        local KT = L.loadKickTrackerRules()
        local pairing = fresh()
        local records = { { startTime = 9.5 } }
        assert.equals("claimed", (KT.PairComm(pairing, records, "A", 10, W)))
        table.remove(records, 1)  -- the caller removes the claimed record
        assert.equals("duplicate", (KT.PairComm(pairing, records, "A", 10.3, W)))
        assert.is_false(KT.PairRecord(pairing, 10.4, W))
    end)

    it("a teammate's second, different kick inside the window pairs with its own record", function()
        local KT = L.loadKickTrackerRules()
        local pairing = fresh()
        -- Pummel's KICK first: its claim takes Pummel's record.
        assert.equals("opened", (KT.PairComm(pairing, {}, "A:6552", 10, W)))
        assert.is_true(KT.PairRecord(pairing, 10.1, W))
        -- The throw 0.3 s later is a new kick, and claims the throw's record.
        local result, index = KT.PairComm(pairing, { { startTime = 10.25 } }, "A:384110", 10.3, W)
        assert.equals("claimed", result)
        assert.equals(1, index)
    end)
end)

describe("KickTracker mode choice", function()
    it("follows the chat lock and names the switch", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "first evaluation, unlocked", old = nil, locked = false, mode = "sync", action = "start" },
            { name = "first evaluation, locked", old = nil, locked = true, mode = "feed", action = "start" },
            { name = "lock begins", old = "sync", locked = true, mode = "feed", action = "enter-feed" },
            { name = "lock lifts", old = "feed", locked = false, mode = "sync", action = "enter-sync" },
            { name = "still unlocked", old = "sync", locked = false, mode = "sync", action = nil },
            { name = "still locked", old = "feed", locked = true, mode = "feed", action = nil },
        }
        for _, row in ipairs(rows) do
            local mode, action = KT.CommModeStep(row.old, row.locked)
            assert.equals(row.mode, mode, row.name)
            assert.equals(row.action, action, row.name)
        end
    end)
end)

describe("KickTracker row visibility", function()
    it("keeps the own row in both modes and teammate rows in sync mode only", function()
        local KT = L.loadKickTrackerRules()
        local kick = { id = 1766, cd = 15 }
        local rows = {
            { name = "own row, feed", mode = "feed", shown = true,
              member = { unit = "player", interruptData = kick, kickVerified = true } },
            { name = "verified teammate, sync", mode = "sync", shown = true,
              member = { unit = "party1", interruptData = kick, kickVerified = true } },
            { name = "verified teammate, before the first evaluation", mode = nil, shown = true,
              member = { unit = "party1", interruptData = kick, kickVerified = true } },
            { name = "verified teammate, feed", mode = "feed", shown = false,
              member = { unit = "party1", interruptData = kick, kickVerified = true } },
            { name = "unverified teammate, sync", mode = "sync", shown = false,
              member = { unit = "party1", interruptData = kick } },
            { name = "no kick", mode = "sync", shown = false,
              member = { unit = "player", kickVerified = true } },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.shown, KT.RowShown(row.member, row.mode), row.name)
        end
    end)
end)

