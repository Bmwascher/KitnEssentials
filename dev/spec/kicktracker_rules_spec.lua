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
        local paired, key = KT.PairRecord(pairing, 10.5, W)
        assert.is_true(paired)
        assert.equals("A", key)
        assert.is_false(KT.PairRecord(pairing, 10.6, W))
    end)

    it("a pairing key gives back the teammate's GUID", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { key = "Player-1305-0A1B2C3D:6552", guid = "Player-1305-0A1B2C3D" },
            { key = "Player-1305-0A1B2C3D:0", guid = "Player-1305-0A1B2C3D" },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.guid, KT.PairKeyGuid(row.key), row.key)
        end
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
    it("shows every member with a kick and no member without one", function()
        local KT = L.loadKickTrackerRules()
        local kick = { id = 1766, cd = 15 }
        local rows = {
            { name = "own row", shown = true, member = { unit = "player", interruptData = kick } },
            { name = "unverified teammate", shown = true, member = { unit = "party1", interruptData = kick } },
            { name = "verified teammate", shown = true,
              member = { unit = "party1", interruptData = kick, kickVerified = true } },
            { name = "no kick", shown = false, member = { unit = "party1", kickVerified = true } },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.shown, KT.RowShown(row.member), row.name)
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

describe("KickTracker message bar times", function()
    it("caps the remaining time at the cooldown the bar is sized by", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "a message cooldown below the row's caps at the message's",
              field = "15", cd = 10, rowCd = 15, duration = 10, remaining = 10 },
            { name = "no message cooldown sizes and caps at the row's",
              field = "20", cd = nil, rowCd = 15, duration = 15, remaining = 15 },
        }
        for _, row in ipairs(rows) do
            local duration, remaining = KT.MessageBarTimes(row.field, row.cd, row.rowCd)
            assert.equals(row.duration, duration, row.name)
            assert.equals(row.remaining, remaining, row.name)
        end
    end)
end)

describe("KickTracker message to row state", function()
    it("starts, sets, readies or keeps a teammate's row, and stamps only a valid R", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "KICK starts", verb = "KICK", want = "start", stamp = false },
            { name = "HELLO without a remaining time keeps", verb = "HELLO", want = "keep", stamp = false },
            { name = "HELLO at zero readies", verb = "HELLO", remaining = 0, want = "ready", stamp = false },
            { name = "HELLO with a remaining time sets", verb = "HELLO", remaining = 4, want = "set", stamp = false },
            { name = "R sets and stamps", verb = "R", remaining = 4, want = "set", stamp = true },
            { name = "R at zero readies and stamps", verb = "R", remaining = 0, want = "ready", stamp = true },
            { name = "an absent or unreadable R keeps without a stamp", verb = "R", want = "keep", stamp = false },
            { name = "KICK inside the window after R keeps", verb = "KICK", reducedAt = 9, want = "keep", stamp = false },
            { name = "KICK after the window starts", verb = "KICK", reducedAt = 8, want = "start", stamp = false },
        }
        for _, row in ipairs(rows) do
            local action, stamp = KT.CooldownFromMessage(row.verb, row.remaining, row.reducedAt, 10, 1.5)
            assert.equals(row.want, action, row.name)
            assert.equals(row.stamp, stamp, row.name)
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
            { name = "an R naming a kick keeps (it moves only the timer)", verb = "R", isKE = true,
              sid = 47528, cd = 15, want = nil },
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

describe("KickTracker record marker", function()
    it("marks a record only while names are shown", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "record, names shown", isRecord = true, showName = true, want = "*" },
            { name = "record, names hidden", isRecord = true, showName = false, want = "" },
            { name = "member row", isRecord = false, showName = true, want = "" },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.MarkerFor(row.isRecord, row.showName), row.name)
        end
    end)
end)

describe("KickTracker own kick from the demon", function()
    it("takes the first candidate the player or the demon knows", function()
        local KT = L.loadKickTrackerRules()
        local candidates = {
            { id = 19647, cd = 24 }, { id = 89766, cd = 30 },
            { id = 119910, cd = 24 }, { id = 119914, cd = 30 },
        }
        local rows = {
            { name = "Felguard out", known = { [89766] = true }, want = 89766 },
            { name = "Felhunter out", known = { [19647] = true }, want = 19647 },
            { name = "both known: the first wins", known = { [19647] = true, [89766] = true }, want = 19647 },
            { name = "no kick known", known = {}, want = nil },
        }
        for _, row in ipairs(rows) do
            local kick = KT.PickOwnKick(candidates, function(id) return row.known[id] == true end)
            assert.equals(row.want, kick and kick.id, row.name)
        end
    end)

    it("takes the kick the player cast while its mark is set, else the check's pick", function()
        local KT = L.loadKickTrackerRules()
        local axeToss, spellLock = { id = 89766, cd = 30 }, { id = 19647, cd = 24 }
        local rows = {
            { name = "the cast mark wins over a picked kick", picked = axeToss, cast = spellLock, want = 19647 },
            { name = "no cast mark: the picked kick", picked = axeToss, cast = nil, want = 89766 },
            { name = "neither: no kick", picked = nil, cast = nil, want = nil },
        }
        for _, row in ipairs(rows) do
            local kick = KT.OwnKickFallback(row.picked, row.cast)
            assert.equals(row.want, kick and kick.id, row.name)
        end
    end)
end)

describe("KickTracker extra kick entries", function()
    it("creates an extra entry once, updates it in place, and a different kick replaces it", function()
        local KT = L.loadKickTrackerRules()
        local member = {}
        local first = KT.ExtraKick(member, 384110, 45)
        local second = KT.ExtraKick(member, 384110, 40)
        assert.equals(first, second)
        assert.equals(1, #member.extraKicks)
        assert.equals(40, second.cd)
        local swapped = KT.ExtraKick(member, 64382, 180)
        assert.equals(1, #member.extraKicks)
        assert.equals(swapped, member.extraKicks[1])
        assert.equals(64382, swapped.id)
    end)

    it("keeps a known kick's timer, drops an unknown one, and adds a new one ready", function()
        local KT = L.loadKickTrackerRules()
        local running = { id = 384110, cd = 45, kickStart = 5, kickDuration = 45 }
        local list, changed = KT.SyncExtraKicks({ running, { id = 64382, cd = 180 } },
            { { id = 384110, cd = 45 }, { id = 999, cd = 20 } })
        assert.equals(2, #list)
        assert.equals(running, list[1])
        assert.equals(5, list[1].kickStart)
        assert.equals(999, list[2].id)
        assert.is_nil(list[2].kickStart)
        assert.is_true(changed)
    end)

    it("gives no list when no extra kick is wanted", function()
        local KT = L.loadKickTrackerRules()
        assert.is_nil((KT.SyncExtraKicks({ { id = 384110, cd = 45 } }, nil)))
    end)

    it("reports no change when the same kicks, or none, are wanted again", function()
        local KT = L.loadKickTrackerRules()
        local running = { id = 384110, cd = 45, kickStart = 5, kickDuration = 45 }
        local _, same = KT.SyncExtraKicks({ running }, { { id = 384110, cd = 45 } })
        assert.is_false(same)
        local _, none = KT.SyncExtraKicks(nil, nil)
        assert.is_false(none)
    end)

    it("wants a throw only when the throw and its required talent are both known", function()
        local KT = L.loadKickTrackerRules()
        local list = { { id = 10, cd = 45, requires = 1 }, { id = 20, cd = 180, requires = 1 } }
        local rows = {
            { name = "talent and throw known", known = { [1] = true, [10] = true }, want = { 10 } },
            { name = "throw known, talent not", known = { [10] = true, [20] = true }, want = {} },
            { name = "talent known, no throw", known = { [1] = true }, want = {} },
        }
        for _, row in ipairs(rows) do
            local got = {}
            local wanted = KT.WantedExtraKicks(list, function(id) return row.known[id] == true end)
            for _, e in ipairs(wanted or {}) do got[#got + 1] = e.id end
            assert.same(row.want, got, row.name)
        end
    end)
end)

describe("KickTracker two-kick row", function()
    it("reads Ready while any kick is up, else counts the kick back soonest", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "main ready", member = {}, id = nil, ready = true },
            { name = "main cooling alone", member = { kickStart = 5, kickDuration = 15 }, id = nil, ready = false },
            { name = "extra ready", id = 384110, ready = true,
              member = { kickStart = 5, kickDuration = 15, extraKicks = { { id = 384110 } } } },
            { name = "extra back sooner", id = 384110, ready = false,
              member = { kickStart = 5, kickDuration = 30, extraKicks = { { id = 384110, kickStart = 8, kickDuration = 24 } } } },
            { name = "main back sooner", id = nil, ready = false,
              member = { kickStart = 5, kickDuration = 15, extraKicks = { { id = 384110, kickStart = 8, kickDuration = 45 } } } },
            { name = "main expired", member = { kickStart = 0, kickDuration = 5 }, id = nil, ready = true },
            { name = "a start without a duration", member = { kickStart = 9 }, id = nil, ready = false },
        }
        for _, row in ipairs(rows) do
            local entry, ready = KT.PickRowKick(row.member, 10)
            assert.equals(row.id, entry and entry.id, row.name)
            assert.equals(row.ready, ready, row.name)
        end
    end)
end)

describe("KickTracker own-kick success match", function()
    it("matches a kick and a landing inside the window in either order", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "kick then landing", kick = 10, landed = 10.3, want = true },
            { name = "landing then kick", kick = 10.3, landed = 10, want = true },
            { name = "outside the window", kick = 10, landed = 10.6, want = false },
            { name = "no kick", kick = nil, landed = 10, want = false },
            { name = "no landing", kick = 10, landed = nil, want = false },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.OwnKickMatched(row.kick, row.landed, 0.5), row.name)
        end
    end)
end)

describe("KickTracker success reduction", function()
    it("subtracts from a cooling row, clamps at zero, and skips a ready row", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "cooling", start = 0, duration = 12, now = 4, want = 5 },
            { name = "clamped at zero", start = 0, duration = 12, now = 10, want = 0 },
            { name = "already expired", start = 0, duration = 12, now = 13, want = nil },
            { name = "not cooling", start = nil, duration = nil, now = 4, want = nil },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.ReducedRemaining(row.start, row.duration, row.now, 3), row.name)
        end
    end)
end)

describe("KickTracker message cooldown cap", function()
    it("caps at the kick's table cooldown, or 60 for an unknown kick", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "at the cap passes", cd = 180, cap = 180, want = 180 },
            { name = "above the table cd", cd = 200, cap = 180, want = 180 },
            { name = "unknown kick above 60", cd = 70, cap = nil, want = 60 },
            { name = "unknown kick below 60", cd = 20, cap = nil, want = 20 },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.WireCooldownCap(row.cd, row.cap), row.name)
        end
    end)
end)

describe("KickTracker own-kick token", function()
    it("takes only the player's own units as an own kick", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "the player", token = "player", want = true },
            { name = "the player's pet", token = "pet", want = true },
            { name = "a teammate with a plain token", token = "party1", want = false },
            { name = "a teammate's pet", token = "partypet1", want = false },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.IsOwnKickToken(row.token), row.name)
        end
    end)
end)

describe("KickTracker wire kick numbers", function()
    it("drops a KICK or R without a real spell and cooldown, and blanks bad HELLO fields", function()
        local KT = L.loadKickTrackerRules()
        local nan = 0 / 0
        local rows = {
            { name = "a real KICK passes", verb = "KICK", sid = 1766, cd = 15,
              valid = true, wantSid = 1766, wantCd = 15 },
            { name = "a KICK naming spell 0 is dropped", verb = "KICK", sid = 0, cd = 15, valid = false },
            { name = "a KICK with no spell is dropped", verb = "KICK", sid = nil, cd = 15, valid = false },
            { name = "a KICK with an infinite spell is dropped", verb = "KICK", sid = math.huge, cd = 15, valid = false },
            { name = "a KICK with a NaN cooldown is dropped", verb = "KICK", sid = 1766, cd = nan, valid = false },
            { name = "an R with a zero cooldown is dropped", verb = "R", sid = 47528, cd = 0, valid = false },
            { name = "a HELLO naming spell 0 passes with no cooldown", verb = "HELLO", sid = 0, cd = 0,
              valid = true, wantSid = 0, wantCd = nil },
            { name = "a HELLO with a zero cooldown passes without it", verb = "HELLO", sid = 1766, cd = 0,
              valid = true, wantSid = 1766, wantCd = nil },
            { name = "a HELLO with a NaN spell passes without it", verb = "HELLO", sid = nan, cd = 15,
              valid = true, wantSid = nil, wantCd = 15 },
        }
        for _, row in ipairs(rows) do
            local valid, sid, cd = KT.CleanWireKick(row.verb, row.sid, row.cd)
            assert.equals(row.valid, valid, row.name)
            if row.valid then
                assert.equals(row.wantSid, sid, row.name)
                assert.equals(row.wantCd, cd, row.name)
            end
        end
    end)
end)

describe("KickTracker HELLO fields", function()
    local function split(msg)
        local out = {}
        for field in (msg .. ";"):gmatch("([^;]*);") do out[#out + 1] = field end
        return out
    end

    it("keeps fields 1-5 where older parsers read them, the answer flag in 6 and the talent-added kick in 7-8", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "no talent-added kick", extra = nil, noAnswer = false, f6 = "0", f7 = "0", f8 = "0.0" },
            { name = "a ready throw", extra = { id = 384110 }, noAnswer = false,
              f6 = "0", f7 = "384110", f8 = "0.0" },
            { name = "an expired throw reads ready", extra = { id = 384110, kickStart = 50, kickDuration = 45 },
              noAnswer = false, f6 = "0", f7 = "384110", f8 = "0.0" },
            { name = "a cooling throw", extra = { id = 64382, kickStart = 90, kickDuration = 180 },
              noAnswer = false, f6 = "0", f7 = "64382", f8 = "170.0" },
            { name = "noAnswer sets the flag", extra = nil, noAnswer = true, f6 = "1", f7 = "0", f8 = "0.0" },
        }
        for _, row in ipairs(rows) do
            local f = split(KT.EncodeHello(6552, 13.5, 12.5, row.noAnswer, row.extra, 100))
            assert.equals(8, #f, row.name)
            -- Older parsers split a fixed number of fields; Lua drops the rest.
            assert.same({ "1", "HELLO", "6552", "13.5", "12.5" }, { f[1], f[2], f[3], f[4], f[5] }, row.name)
            assert.equals(row.f6, f[6], row.name)
            assert.equals(row.f7, f[7], row.name)
            assert.equals(row.f8, f[8], row.name)
        end
    end)
end)

describe("KickTracker HELLO talent-added kick on receive", function()
    it("sets, times, replaces or clears the entry from fields 7-8 and ignores what it cannot read", function()
        local KT = L.loadKickTrackerRules()
        local throws = { [384110] = { id = 384110, cd = 45 }, [64382] = { id = 64382, cd = 180 } }
        local function getExtra(id) return throws[id] end
        local function running() return { { id = 384110, cd = 45, kickStart = 80, kickDuration = 45 } } end
        local rows = {
            { name = "field 7 absent (an older sender) leaves the entry", start = running, f7 = nil, f8 = nil,
              touched = false, id = 384110, kickStart = 80, kickDuration = 45 },
            { name = "0 clears the entry", start = running, f7 = "0", f8 = "0.0", touched = true, id = nil },
            { name = "0 with no entry changes nothing", start = nil, f7 = "0", f8 = "0.0",
              touched = false, id = nil },
            { name = "a throw with a remaining time cools at the table cd", start = nil,
              f7 = "384110", f8 = "30.0", touched = true, id = 384110, kickStart = 85, kickDuration = 45 },
            { name = "the same throw with an unreadable field 8 keeps its timer", start = running,
              f7 = "384110", f8 = "abc", touched = true, id = 384110, kickStart = 80, kickDuration = 45 },
            { name = "the same throw at 0.0 reads ready", start = running, f7 = "384110", f8 = "0.0",
              touched = true, id = 384110, kickStart = nil, kickDuration = nil },
            { name = "a different throw replaces the entry", start = running, f7 = "64382", f8 = nil,
              touched = true, id = 64382, kickStart = nil, kickDuration = nil },
            { name = "an ID that is not a throw leaves the entry", start = running, f7 = "6552", f8 = "0.0",
              touched = false, id = 384110, kickStart = 80, kickDuration = 45 },
            { name = "a fraction leaves the entry", start = running, f7 = "384110.5", f8 = "0.0",
              touched = false, id = 384110, kickStart = 80, kickDuration = 45 },
            { name = "NaN leaves the entry", start = running, f7 = "nan", f8 = "0.0",
              touched = false, id = 384110, kickStart = 80, kickDuration = 45 },
            { name = "infinity leaves the entry", start = running, f7 = "inf", f8 = "0.0",
              touched = false, id = 384110, kickStart = 80, kickDuration = 45 },
            { name = "text leaves the entry", start = running, f7 = "abc", f8 = "0.0",
              touched = false, id = 384110, kickStart = 80, kickDuration = 45 },
        }
        for _, row in ipairs(rows) do
            local member = { extraKicks = row.start and row.start() or nil }
            assert.equals(row.touched, KT.HelloExtras(member, row.f7, row.f8, getExtra, 100), row.name)
            local entry = member.extraKicks and member.extraKicks[1]
            assert.equals(row.id, entry and entry.id, row.name)
            if entry then
                assert.equals(throws[entry.id].cd, entry.cd, row.name)
                assert.equals(row.kickStart, entry.kickStart, row.name)
                assert.equals(row.kickDuration, entry.kickDuration, row.name)
            end
        end
    end)
end)

describe("KickTracker own-kick announce", function()
    it("asks on a main or spec change, only tells on a talent-added kick change, and is silent otherwise", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "main kick changed", main = true, spec = false, extras = false, want = "ask" },
            { name = "spec changed", main = false, spec = true, extras = false, want = "ask" },
            { name = "main and extras changed: one asking HELLO", main = true, spec = false, extras = true,
              want = "ask" },
            { name = "extras alone", main = false, spec = false, extras = true, want = "tell" },
            { name = "nothing changed", main = false, spec = false, extras = false, want = nil },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.OwnKickHello(row.main, row.spec, row.extras), row.name)
        end
    end)
end)

describe("KickTracker own-kick duplicate", function()
    it("skips only the same kick inside the window", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "the same kick at the same moment (one press, two events)",
              lastID = 19647, lastAt = 10, kickID = 19647, now = 10, want = true },
            { name = "the same kick after the window (a recast)",
              lastID = 19647, lastAt = 10, kickID = 19647, now = 34, want = false },
            { name = "a different kick inside the window",
              lastID = 89766, lastAt = 10, kickID = 19647, now = 10.2, want = false },
            { name = "no memory: the first event sends",
              lastID = nil, lastAt = nil, kickID = 19647, now = 10, want = false },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.DuplicateOwnKick(row.lastID, row.lastAt, row.kickID, row.now, 0.5), row.name)
        end
    end)
end)

describe("KickTracker own kick with a hidden kicker", function()
    it("claims one hidden interrupt inside the window after the own cast, once", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "no own cast", at = nil, now = 10, want = false },
            { name = "an interrupt inside the window", at = 10, now = 10.3, want = true },
            { name = "an interrupt after the window", at = 10, now = 10.6, want = false },
        }
        for _, row in ipairs(rows) do
            local claim = { at = row.at }
            assert.equals(row.want, KT.TakeOwnClaim(claim, row.now, 0.5), row.name)
            assert.is_nil(claim.at, row.name)
        end
    end)

    it("takes the newest hidden-kicker record inside the window when the interrupt came first", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "no records", records = {}, want = nil },
            { name = "the newest hidden record inside the window",
              records = { { startTime = 9.9, hiddenKicker = true }, { startTime = 9.95, hiddenKicker = true } },
              want = 2 },
            { name = "a readable kicker's record is never taken",
              records = { { startTime = 9.8, hiddenKicker = true }, { startTime = 9.9 } }, want = 1 },
            { name = "a record older than the window is not the cast's",
              records = { { startTime = 9.5, hiddenKicker = true } }, want = nil },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.OwnRecordIndex(row.records, 10, 0.4), row.name)
        end
    end)
end)

describe("KickTracker friendly-unit refusal", function()
    it("refuses only an answer read plainly as false", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "a plain false refuses", ok = true, answer = false, secret = false, want = true },
            { name = "a plain true passes", ok = true, answer = true, secret = false, want = false },
            { name = "a failed call passes", ok = false, answer = "error text", secret = false, want = false },
            { name = "a secret answer passes", ok = true, answer = false, secret = true, want = false },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.RefusesInterruptUnit(row.ok, row.answer, row.secret), row.name)
        end
    end)
end)

describe("KickTracker same-frame duplicate", function()
    it("takes a second event on the same nameplate inside the window as the same interrupt", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "no earlier event on this nameplate, another nameplate's just before",
              last = { nameplate2 = 10 }, unit = "nameplate1", now = 10.01, want = false },
            { name = "the same nameplate inside the window, another nameplate's event between",
              last = { nameplate1 = 10, nameplate2 = 10.005 }, unit = "nameplate1", now = 10.01, want = true },
            { name = "the same nameplate past the window", last = { nameplate1 = 10 },
              unit = "nameplate1", now = 10.05, want = false },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.SameInterrupt(row.last, row.unit, row.now, 0.02), row.name)
        end
    end)
end)

describe("KickTracker meter list keys", function()
    it("keys apart entries that share class, spec icon and local flag, and marks them shared", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "the same class, icon and flag share", shared = { true, true },
              list = { { class = "DEATHKNIGHT", icon = 135770 }, { class = "DEATHKNIGHT", icon = 135770 } } },
            { name = "another spec icon does not share", shared = { false, false },
              list = { { class = "DEATHKNIGHT", icon = 135770 }, { class = "DEATHKNIGHT", icon = 135773 } } },
            { name = "the local flag does not share", shared = { false, false },
              list = { { class = "DEATHKNIGHT", me = true }, { class = "DEATHKNIGHT", me = false } } },
            { name = "a different name still shares", shared = { true, true },
              list = { { class = "MAGE", name = "Dee" }, { class = "MAGE", name = "Eve" } } },
        }
        for _, row in ipairs(rows) do
            local list = KT.KeyMeterEntries(row.list)
            assert.are_not.equal(list[1].key, list[2].key, row.name)
            assert.same(row.shared, { list[1].shared, list[2].shared }, row.name)
        end
    end)
end)

describe("KickTracker meter list diff", function()
    it("names a lone entry, the one entry added with none removed, or the one entry that moved up", function()
        local KT = L.loadKickTrackerRules()
        local function list(...)
            local out = {}
            for i, key in ipairs({ ... }) do out[i] = { key = key } end
            return out
        end
        local shared = { { key = "DK:250", shared = true }, { key = "DK:250#2", shared = true } }
        local rows = {
            { name = "a one-entry list names its entry", old = nil, new = list("DK"), want = "DK" },
            { name = "no earlier read names nothing", old = nil, new = list("DK", "MAGE"), want = nil },
            { name = "the one added entry is named", old = list("DK"), new = list("DK", "MAGE"), want = "MAGE" },
            { name = "two added entries name nothing", old = list("DK"), new = list("DK", "MAGE", "ROGUE"), want = nil },
            { name = "a list one longer with an old entry gone names nothing", old = list("DK", "MAGE"),
              new = list("DK", "ROGUE", "HUNTER"), want = nil },
            { name = "the one entry that moved up is named as a climb", old = list("DK", "MAGE", "ROGUE"),
              new = list("ROGUE", "DK", "MAGE"), want = "ROGUE", climbed = true },
            { name = "two entries that moved up name nothing", old = list("DK", "MAGE", "ROGUE", "HUNTER"),
              new = list("MAGE", "DK", "HUNTER", "ROGUE"), want = nil },
            { name = "an entry replaced in a list of the same length names nothing", old = list("DK", "MAGE"),
              new = list("ROGUE", "DK"), want = nil },
            { name = "no entry moved names nothing", old = list("DK", "MAGE"), new = list("DK", "MAGE"), want = nil },
            { name = "a climber sharing its class, spec and flag names nothing",
              old = { { key = "DK:250", shared = true }, { key = "MAGE" }, { key = "DK:250#2", shared = true } },
              new = { { key = "DK:250", shared = true }, { key = "DK:250#2", shared = true }, { key = "MAGE" } },
              want = nil },
            { name = "an added entry sharing its class, spec and flag names nothing",
              old = list("DK:250"), new = shared, want = nil },
        }
        for _, row in ipairs(rows) do
            local entry, climbed = KT.DiffMeterList(row.old, row.new)
            assert.equals(row.want, entry and entry.key, row.name)
            assert.equals(row.climbed == true, climbed == true, row.name)
        end
    end)
end)

describe("KickTracker meter entry to member", function()
    it("matches by class and rules members out by the local flag and a plain name only", function()
        local KT = L.loadKickTrackerRules()
        local members = {
            me = { unit = "player", matchClass = "DEATHKNIGHT", shortName = "Bob", specID = 250 },
            ann = { unit = "party1", matchClass = "DEATHKNIGHT", shortName = "Ann", specID = 251 },
            cal = { unit = "party2", matchClass = "DEATHKNIGHT", shortName = "Cal", specID = 0 },
            dee = { unit = "party3", matchClass = "MAGE", shortName = "Dee", specID = 0 },
        }
        local rows = {
            { name = "the local-player flag matches only the player", entry = { class = "MAGE", me = true },
              count = 1, guid = "me" },
            { name = "a class matches its members, not the player when the flag says not",
              entry = { class = "DEATHKNIGHT", me = false }, count = 2 },
            { name = "an unreadable flag keeps the player in", entry = { class = "DEATHKNIGHT" }, count = 3 },
            { name = "a spec icon rules nobody out, though one member's known spec differs",
              entry = { class = "DEATHKNIGHT", me = false, icon = 135770 }, count = 2 },
            { name = "a plain name, realm stripped, picks one",
              entry = { class = "DEATHKNIGHT", me = false, name = "Cal-Home" }, count = 1, guid = "cal" },
            { name = "an unreadable class rules no one out", entry = { class = "MAGE", me = false },
              members = { ann = { unit = "party1", matchClass = "MAGE" }, dee = { unit = "party3" } }, count = 2 },
        }
        for _, row in ipairs(rows) do
            local count, guid = KT.MatchMeterEntry(row.entry, row.members or members)
            assert.equals(row.count, count, row.name)
            if row.count == 1 then assert.equals(row.guid, guid, row.name) end
        end
    end)
end)

describe("KickTracker meter burst sessions", function()
    it("marks a burst shared only when the Current session updates twice in it", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "Current and Overall's ID 0 once each", updates = { { id = 1 }, { id = 0 } }, want = false },
            { name = "two Current updates across a rollover repeat",
              updates = { { id = 4 }, { id = 0 }, { id = 5 }, { id = 0 } }, want = true },
            { name = "two unreadable IDs count as two Current updates",
              updates = { { secret = true }, { secret = true } }, want = true },
        }
        for _, row in ipairs(rows) do
            local seen, shared = {}, false
            for _, update in ipairs(row.updates) do
                if KT.SessionRepeats(seen, update.id, update.secret == true) then shared = true end
            end
            assert.equals(row.want, shared, row.name)
        end
    end)
end)

describe("KickTracker meter report owner", function()
    it("names the member every naming list agrees on, unless the burst was shared", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "one list names a member", named = { "ann" }, want = "ann" },
            { name = "both lists name the same member", named = { "ann", "ann" }, want = "ann" },
            { name = "two lists name different members", named = { "ann", "cal" }, want = nil },
            { name = "a shared burst names nobody, though the lists agree", named = { "ann", "ann" },
              shared = true, want = nil },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.MeterReportOwner(row.named, row.shared == true), row.name)
        end
    end)
end)

describe("KickTracker hidden-kicker resolution", function()
    it("folds only a lone interrupt with one report naming one member, else records it", function()
        local KT = L.loadKickTrackerRules()
        local kick = { id = 1766, cd = 15 }
        local members = {
            me = { unit = "player", interruptData = kick },
            ann = { unit = "party1", interruptData = kick },
            syn = { unit = "party2", interruptData = kick, kickVerified = true },
            hea = { unit = "party3" },
        }
        local rows = {
            { name = "one interrupt, one report naming a teammate: fold",
              hits = { { at = 10.1, owner = "ann" } }, want = "fold", guid = "ann" },
            { name = "a report named only by a climb: fold, unsure",
              hits = { { at = 10.1, owner = "ann", uncertain = true } }, want = "fold", guid = "ann", unsure = true },
            { name = "no report: record", hits = {}, want = "record" },
            { name = "an unnamed report: record", hits = { { at = 10.1 } }, want = "record" },
            { name = "two reports: record", hits = { { at = 9.6 }, { at = 10.1, owner = "ann" } }, want = "record" },
            { name = "another interrupt in the window: record", others = { { startTime = 10.7, state = "own" } },
              hits = { { at = 10.1, owner = "ann" } }, want = "record" },
            { name = "an echo of the same member counts once: fold",
              hits = { { at = 10.1, owner = "ann" }, { at = 10.4, owner = "ann" } }, want = "fold", guid = "ann" },
            { name = "an interrupt and a report outside the window do not count: fold",
              others = { { startTime = 8.8, state = "record" } },
              hits = { { at = 8.7 }, { at = 10.1, owner = "ann" } }, want = "fold", guid = "ann" },
            { name = "another interrupt near the report, not near this one: record",
              others = { { startTime = 11.1, state = "pending" } },
              hits = { { at = 10.8, owner = "ann" } }, want = "record" },
            { name = "a report whose window is still open: wait until it closes",
              hits = { { at = 10.5, owner = "ann" } }, want = "wait", untilAt = 11.5 },
            { name = "a report burst whose later end lies near another interrupt: record",
              others = { { startTime = 11.6, state = "pending" } },
              hits = { { at = 10.5, last = 10.7, owner = "ann" } }, want = "record" },
            { name = "the player named while the own kick cools: own", meCooling = true,
              hits = { { at = 10.1, owner = "me" } }, want = "own" },
            { name = "the player named only by a climb: record", meCooling = true,
              hits = { { at = 10.1, owner = "me", uncertain = true } }, want = "record" },
            { name = "the player named while the own kick is ready: record",
              hits = { { at = 10.1, owner = "me" } }, want = "record" },
            { name = "a synced teammate whose messages can arrive: record", heard = true,
              hits = { { at = 10.1, owner = "syn" } }, want = "record" },
            { name = "a synced teammate whose messages cannot arrive: fold", heard = false,
              hits = { { at = 10.1, owner = "syn" } }, want = "fold", guid = "syn" },
            { name = "a named member with no kick: record", hits = { { at = 10.1, owner = "hea" } }, want = "record" },
            { name = "an interrupt something already took: nil", state = "claimed",
              hits = { { at = 10.1, owner = "ann" } }, want = nil },
        }
        for _, row in ipairs(rows) do
            members.me.kickStart = row.meCooling and 9.5 or nil
            members.me.kickDuration = row.meCooling and 15 or nil
            local entry = { startTime = 10, state = row.state or "pending" }
            local entries = { entry }
            for _, other in ipairs(row.others or {}) do entries[#entries + 1] = other end
            local outcome, guid, untilAt, unsure = KT.ResolveInterrupt(entry, entries, row.hits, members,
                row.heard == true, 11.2, 1, 0.5)
            assert.equals(row.want, outcome, row.name)
            assert.equals(row.guid, guid, row.name)
            assert.equals(row.untilAt, untilAt, row.name)
            assert.equals(row.unsure, unsure, row.name)
        end
    end)
end)

describe("KickTracker uncertain kick", function()
    it("counts a Warrior and a Protection Paladin, and no other member", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "a Warrior of any spec counts",
              member = { matchClass = "WARRIOR", specID = 72 }, role = "DAMAGER", want = true },
            { name = "a Protection Paladin counts",
              member = { matchClass = "PALADIN", specID = 66 }, role = "NONE", want = true },
            { name = "a Paladin held as Retribution whose role is tank counts",
              member = { matchClass = "PALADIN", specID = 70 }, role = "TANK", want = true },
            { name = "a Retribution Paladin with a damage role does not",
              member = { matchClass = "PALADIN", specID = 70 }, role = "DAMAGER", want = false },
            { name = "a Paladin of unknown spec with a damage role does not",
              member = { matchClass = "PALADIN", specID = 0 }, role = "DAMAGER", want = false },
            { name = "a Paladin of unknown spec with no role counts",
              member = { matchClass = "PALADIN", specID = 0 }, role = "NONE", want = true },
            { name = "another class does not",
              member = { matchClass = "ROGUE", specID = 0 }, role = "NONE", want = false },
            { name = "an unreadable class counts",
              member = { specID = 0 }, role = "DAMAGER", want = true },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.UncertainKick(row.member, row.role), row.name)
        end
    end)
end)

describe("KickTracker message state drop", function()
    it("drops what only a teammate's messages keep true, so a credited cooldown drives their row", function()
        local KT = L.loadKickTrackerRules()
        local members = {
            me = { unit = "player", kickVerified = true, extraKicks = { { id = 100, cd = 30 } } },
            ann = { unit = "party1", kickVerified = true, reducedAt = 9, kickStart = 10, kickDuration = 15,
                    extraKicks = { { id = 100, cd = 30 } } },
        }
        local before = KT.PickRowKick(members.ann, 11)
        KT.DropMessageState(members)
        local rowKick, isReady = KT.PickRowKick(members.ann, 11)
        assert.is_not_nil(before)
        assert.is_nil(members.ann.kickVerified)
        assert.is_nil(members.ann.extraKicks)
        assert.is_nil(members.ann.reducedAt)
        assert.is_nil(rowKick)
        assert.is_false(isReady)
        assert.is_true(members.me.kickVerified)
        assert.equals(1, #members.me.extraKicks)
    end)
end)
