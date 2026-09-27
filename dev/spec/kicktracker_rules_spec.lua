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

describe("KickTracker sender identity", function()
    it("matches by Name-Realm and falls back to a unique short name", function()
        local KT = L.loadKickTrackerRules()
        local members = {
            me = { unit = "player", shortName = "Bob", fullKey = "Bob-Home" },
            ann = { unit = "party1", shortName = "Ann", fullKey = "Ann-Home" },
            calAway = { unit = "party2", shortName = "Cal", fullKey = "Cal-Away" },
            calHome = { unit = "party3", shortName = "Cal", fullKey = "Cal-Home" },
        }
        local rows = {
            { name = "the full key picks one of two same-name teammates", key = "Cal-Home", short = "Cal", want = "calHome" },
            { name = "a key miss falls back to a unique short name", key = "Ann-Other", short = "Ann", want = "ann" },
            { name = "a key miss with two same-name teammates finds nothing", key = "Cal-Other", short = "Cal", want = nil },
            { name = "the player is never returned", key = "Bob-Home", short = "Bob", want = nil },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, (KT.MemberForSender(members, row.key, row.short)), row.name)
        end
    end)
end)

describe("KickTracker true cooldown", function()
    it("applies known flat talents, then multipliers, clamped at zero", function()
        local KT = L.loadKickTrackerRules()
        local known = { [1] = true, [2] = true }
        local function isKnown(id) return known[id] == true end
        local rows = {
            { name = "no entries", base = 20, mods = nil, want = 20 },
            { name = "a known flat talent", base = 24, mods = { { talent = 1, seconds = 5 } }, want = 19 },
            { name = "a known multiplier", base = 15, mods = { { talent = 2, multiplier = 0.9 } }, want = 13.5 },
            { name = "an unknown talent", base = 24, mods = { { talent = 3, seconds = 5 } }, want = 24 },
            { name = "flat before multiplier", base = 20,
              mods = { { talent = 2, multiplier = 0.5 }, { talent = 1, seconds = 5 } }, want = 7.5 },
            { name = "clamped at zero", base = 20, mods = { { talent = 1, seconds = 30 } }, want = 0 },
        }
        for _, row in ipairs(rows) do
            assert.near(row.want, KT.TalentedCooldown(row.base, row.mods, isKnown), 1e-9, row.name)
        end
    end)
end)

describe("KickTracker remaining-time field", function()
    it("keeps on absent or unreadable, readies at zero, and caps at the cooldown", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "absent", field = nil, cd = 30, want = nil },
            { name = "unreadable", field = "abc", cd = 30, want = nil },
            { name = "zero", field = "0", cd = 30, want = 0 },
            { name = "negative", field = "-3", cd = 30, want = 0 },
            { name = "above the cooldown", field = "45", cd = 30, want = 30 },
            { name = "in range", field = "12.5", cd = 30, want = 12.5 },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.ParseHelloRemaining(row.field, row.cd), row.name)
        end
    end)
end)

describe("KickTracker message to row state", function()
    it("starts, sets, readies or keeps a teammate's row", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "KICK starts", verb = "KICK", remaining = nil, want = "start" },
            { name = "HELLO without a remaining time keeps", verb = "HELLO", remaining = nil, want = "keep" },
            { name = "HELLO at zero readies", verb = "HELLO", remaining = 0, want = "ready" },
            { name = "HELLO with a remaining time sets", verb = "HELLO", remaining = 4, want = "set" },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.CooldownFromMessage(row.verb, row.remaining), row.name)
        end
    end)
end)

describe("KickTracker message-named kick across a refresh", function()
    it("keeps a heard teammate's message kick through any refresh, a respec included", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "never heard from: the spec default", member = { specID = 266 }, want = false },
            { name = "heard from: their message kick, a respec included",
              member = { kickFromMessage = true, specID = 266 }, want = true },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.KeepsMessageKick(row.member), row.name)
        end
    end)
end)

describe("KickTracker message to main kick", function()
    it("sets on a named kick, clears only on a KE HELLO naming spell 0, and keeps otherwise", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "KE HELLO naming 0 clears", verb = "HELLO", isKE = true, sid = 0, cd = 0, want = "clear" },
            { name = "BliZzi HELLO naming 0 keeps", verb = "HELLO", isKE = false, sid = 0, cd = 0, want = nil },
            { name = "KE KICK naming 0 keeps", verb = "KICK", isKE = true, sid = 0, cd = 0, want = nil },
            { name = "a positive spell and cooldown sets", verb = "KICK", isKE = true, sid = 1766, cd = 15, want = "set" },
            { name = "a talent-added kick keeps", verb = "KICK", isKE = true, sid = 384110, cd = 45,
              extra = true, want = nil },
            { name = "a malformed KE HELLO (no readable spell) keeps", verb = "HELLO", isKE = true,
              sid = nil, cd = nil, want = nil },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.KickFromMessage(row.verb, row.isKE, row.sid, row.cd, row.extra), row.name)
        end
    end)
end)

describe("KickTracker HELLO answer", function()
    it("answers an asking HELLO past the throttle, never a reply, and an old client's under it", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "asks for an answer: sent even inside the throttle", flag = "0", want = "force" },
            { name = "a reply: no answer", flag = "1", want = nil },
            { name = "no flag (older client): answered under the throttle", flag = nil, want = "throttled" },
            { name = "an unknown flag is read as an older client", flag = "x", want = "throttled" },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.HelloReplyMode(row.flag), row.name)
        end
    end)
end)
