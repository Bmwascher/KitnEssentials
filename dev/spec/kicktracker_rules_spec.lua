-- Modules/DungeonTools/KicksCasts/KickTrackerRules.lua: the kick tracker's pure decisions.
-- Frames, bars, the engine timers and event wiring are checked in game.
local L = require("dev.spec._ke_loader")

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

    it("takes the newest claimable hidden interrupt inside the window when the interrupt came first", function()
        local KT = L.loadKickTrackerRules()
        local function hidden(t, state)
            return { startTime = t, hidden = true, claimable = true, state = state or "guessed" }
        end
        local rows = {
            { name = "no interrupts", entries = {}, want = nil },
            { name = "the newest hidden interrupt inside the window",
              entries = { hidden(9.9), hidden(9.95) }, want = 2 },
            { name = "a readable kicker's interrupt is never taken",
              entries = { hidden(9.8), { startTime = 9.9, claimable = true, state = "exact" } }, want = 1 },
            { name = "an interrupt older than the window is not the cast's",
              entries = { hidden(9.5) }, want = nil },
            { name = "an interrupt the meter put on a teammate's row is passed over",
              entries = { hidden(9.8), hidden(9.9, "fold") }, want = 1 },
            { name = "a claimed interrupt is passed over",
              entries = { hidden(9.8), { startTime = 9.9, hidden = true, state = "claimed" } }, want = 1 },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.OwnInterruptIndex(row.entries, 10, 0.4), row.name)
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

describe("KickTracker meter list diff", function()
    it("names a lone entry, the one newcomer, or the one climber when none is new", function()
        local KT = L.loadKickTrackerRules()
        local function list(...)
            local out = {}
            for i, key in ipairs({ ... }) do out[i] = { key = key } end
            return out
        end
        local rows = {
            { name = "a one-entry list names its entry", old = nil, new = list("DK"), want = "DK" },
            { name = "no earlier read names nothing", old = nil, new = list("DK", "MAGE"), want = nil },
            { name = "the one newcomer is named, even beside a climber", old = list("DK", "MAGE"),
              new = list("MAGE", "DK", "ROGUE"), want = "ROGUE" },
            { name = "two newcomers name nothing", old = list("DK"), new = list("DK", "MAGE", "ROGUE"), want = nil },
            { name = "the one climber is named when none is new", old = list("DK", "MAGE", "ROGUE"),
              new = list("ROGUE", "DK", "MAGE"), want = "ROGUE" },
            { name = "two climbers name nothing", old = list("DK", "MAGE", "ROGUE", "HUNTER"),
              new = list("MAGE", "DK", "HUNTER", "ROGUE"), want = nil },
            { name = "no change names nothing", old = list("DK", "MAGE"), new = list("DK", "MAGE"), want = nil },
        }
        for _, row in ipairs(rows) do
            local entry = KT.DiffMeter(row.old, row.new)
            assert.equals(row.want, entry and entry.key, row.name)
        end
    end)
end)

describe("KickTracker meter entry to member", function()
    it("matches by the local flag, the class, a plain name and a known spec's icon", function()
        local KT = L.loadKickTrackerRules()
        local members = {
            me = { unit = "player", matchClass = "DEATHKNIGHT", shortName = "Bob", specID = 250 },
            ann = { unit = "party1", matchClass = "DEATHKNIGHT", shortName = "Ann", specID = 251 },
            cal = { unit = "party2", matchClass = "DEATHKNIGHT", shortName = "Cal", specID = 0 },
            dee = { unit = "party3", matchClass = "MAGE", shortName = "Dee", specID = 0 },
            eve = { unit = "party4", shortName = "Eve", specID = 0 },
        }
        local icons = { [250] = 135770, [251] = 135773 }
        local function iconOf(specID) return icons[specID] end
        local rows = {
            { name = "the local flag picks the player alone", entry = { class = "MAGE", me = true },
              want = { "me" } },
            { name = "a false flag rules the player out", entry = { class = "DEATHKNIGHT", me = false },
              want = { "ann", "cal" } },
            { name = "an unreadable flag keeps the player", entry = { class = "DEATHKNIGHT" },
              want = { "ann", "cal", "me" } },
            { name = "the class must match, and a member whose class does not read never does",
              entry = { class = "MAGE", me = false }, want = { "dee" } },
            { name = "a plain name, realm stripped, rules out other names",
              entry = { class = "DEATHKNIGHT", me = false, name = "Cal-Home" }, want = { "cal" } },
            { name = "a known spec with another icon rules out, an unknown spec does not",
              entry = { class = "DEATHKNIGHT", icon = 135770 }, want = { "cal", "me" } },
        }
        for _, row in ipairs(rows) do
            local out = {}
            local added = KT.MatchMember(row.entry, members, iconOf, out)
            local got = {}
            for guid in pairs(out) do got[#got + 1] = guid end
            table.sort(got)
            assert.same(row.want, got, row.name)
            assert.equals(#row.want, added, row.name)
        end
    end)
end)

describe("KickTracker meter kicker", function()
    it("names one match, narrows to several, widens over a list with no entry, and only widens a shared read", function()
        local KT = L.loadKickTrackerRules()
        local members = {
            me = { unit = "player", matchClass = "DEATHKNIGHT", specID = 0 },
            ann = { unit = "party1", matchClass = "DEATHKNIGHT", specID = 0 },
            cal = { unit = "party2", matchClass = "DEATHKNIGHT", specID = 0 },
            dee = { unit = "party3", matchClass = "MAGE", specID = 0 },
        }
        local function iconOf() return nil end
        local mage = { class = "MAGE", me = false }
        local dk = { class = "DEATHKNIGHT", me = false }
        local myDk = { class = "DEATHKNIGHT", me = true }
        local rows = {
            { name = "an entry matching one member names them",
              reads = { { entry = mage, list = { mage } }, {} }, owner = "dee", cands = { "dee" } },
            { name = "an entry matching several narrows to them, and a later list does not widen",
              reads = { { entry = dk, list = { dk } }, { list = { mage } } }, cands = { "ann", "cal" } },
            { name = "a list with no entry widens by every entry's matches",
              reads = { { list = { mage, myDk } }, {} }, cands = { "dee", "me" } },
            { name = "an Overall entry narrows over a widened Current list",
              reads = { { list = { mage } }, { entry = dk, list = { dk } } }, cands = { "ann", "cal" } },
            { name = "no match anywhere gives no candidates",
              reads = { { list = { { class = "ROGUE" } } }, {} }, cands = nil },
            { name = "a shared read names nobody and widens over both lists", shared = true,
              reads = { { entry = mage, list = { mage } }, { entry = myDk, list = { myDk } } },
              cands = { "dee", "me" } },
        }
        for _, row in ipairs(rows) do
            local owner, cands = KT.MeterKicker(row.reads, members, iconOf, row.shared == true)
            assert.equals(row.owner, owner, row.name)
            if row.cands then
                local got = {}
                for guid in pairs(cands or {}) do got[#got + 1] = guid end
                table.sort(got)
                assert.same(row.cands, got, row.name)
            else
                assert.is_nil(cands, row.name)
            end
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

describe("KickTracker interrupt and meter pairing", function()
    it("pairs oldest first within the window, drops what cannot pair, and lets an extra pair once more", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "a report within 1 s pairs with the interrupt", now = 10.1,
              pendings = { 10 }, hits = { { at = 10.05 } }, paired = { "10:10.05" }, dropped = {} },
            { name = "two interrupts and two reports pair oldest with oldest, in order", now = 10.95,
              pendings = { 10, 10.5 }, hits = { { at = 10.4 }, { at = 10.9 } },
              paired = { "10:10.4", "10.5:10.9" }, dropped = {} },
            { name = "a report more than 1 s before the oldest interrupt goes, and the next one pairs", now = 10.1,
              pendings = { 10 }, hits = { { at = 8.9 }, { at = 10 } }, paired = { "10:10" }, dropped = {} },
            { name = "an interrupt more than 1 s before the oldest report is dropped", now = 11.3,
              pendings = { 9.9, 11.2 }, hits = { { at = 11.2 } }, paired = { "11.2:11.2" }, dropped = { 9.9 } },
            { name = "an interrupt and a report past 1.5 s go unpaired", now = 12,
              pendings = { 10.4 }, hits = { { at = 10.3 } }, paired = {}, dropped = { 10.4 } },
            { name = "a report with an extra pairs a second waiting interrupt", now = 10.1,
              pendings = { 10, 10 }, hits = { { at = 10, extra = 1 } }, paired = { "10:10", "10:10" },
              dropped = {} },
        }
        for _, row in ipairs(rows) do
            local pendings = {}
            for i, t in ipairs(row.pendings) do pendings[i] = { startTime = t } end
            local paired, dropped = {}, {}
            KT.PairKicks(pendings, row.hits, row.now, 1.5, 1,
                function(entry, hit) paired[#paired + 1] = entry.startTime .. ":" .. hit.at end,
                function(entry) dropped[#dropped + 1] = entry.startTime end)
            assert.same(row.paired, paired, row.name)
            assert.same(row.dropped, dropped, row.name)
            assert.equals(0, #pendings, row.name)
            assert.equals(0, #row.hits, row.name)
        end
    end)
end)

describe("KickTracker report after its read", function()
    it("drops a report that paired, so a later interrupt cannot take its spare, and keeps one that paired nothing", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "a report that paired leaves with its spare", waiting = { 10 }, laterPairs = 0 },
            { name = "a report that paired nothing stays as one report", waiting = {}, laterPairs = 1 },
        }
        for _, row in ipairs(rows) do
            local hit = { at = 10, extra = 1 }
            local hits = { hit }
            local pendings = {}
            for i, t in ipairs(row.waiting) do pendings[i] = { startTime = t } end
            local paired = 0
            local function onPair() paired = paired + 1 end
            local function onDrop() end
            -- The read's own pass, then the read settles its report.
            KT.PairKicks(pendings, hits, 10.05, 1.5, 1, onPair, onDrop)
            KT.SettleReport(hits, hit)
            -- An interrupt 0.2 s later, before its own report arrives.
            paired = 0
            pendings[#pendings + 1] = { startTime = 10.2 }
            KT.PairKicks(pendings, hits, 10.25, 1.5, 1, onPair, onDrop)
            assert.equals(row.laterPairs, paired, row.name)
            assert.equals(0, #hits, row.name)
        end
    end)
end)

describe("KickTracker guess", function()
    it("guesses a ready candidate, then a busy one, then any ready teammate, never the player or a heard synced teammate", function()
        local KT = L.loadKickTrackerRules()
        local function members()
            return {
                me = { unit = "player", interruptData = { cd = 15 } },
                ann = { unit = "party1", interruptData = { cd = 15 } },
                bob = { unit = "party2", interruptData = { cd = 12 } },
                cal = { unit = "party3", interruptData = { cd = 15 } },
                syn = { unit = "party4", interruptData = { cd = 10 }, kickVerified = true },
            }
        end
        local rows = {
            { name = "the ready candidate with the shortest cooldown",
              cands = { ann = true, bob = true, cal = true }, heard = true, want = "bob", tier = 1 },
            { name = "equal cooldowns go by party order",
              cands = { ann = true, cal = true }, heard = true, want = "ann", tier = 1 },
            { name = "no ready candidate: the busy one back soonest",
              cands = { ann = true, cal = true }, busy = { ann = 9, cal = 5 }, heard = true, want = "cal", tier = 2 },
            { name = "no candidate row: any ready teammate",
              cands = { me = true }, heard = true, want = "bob", tier = 3 },
            { name = "no candidates: a ready teammate by cooldown, then party order",
              cands = nil, busy = { bob = 9 }, heard = true, want = "ann", tier = 1 },
            { name = "no candidates and nobody ready: nobody, never a busy row",
              cands = nil, busy = { ann = 9, bob = 9, cal = 9 }, heard = true, want = nil },
            { name = "a synced teammate whose messages arrive is never guessed",
              cands = { syn = true }, heard = true, want = "bob", tier = 3 },
            { name = "a synced teammate whose messages cannot arrive is",
              cands = { syn = true }, heard = false, want = "syn", tier = 1 },
        }
        for _, row in ipairs(rows) do
            local m = members()
            for guid, start in pairs(row.busy or {}) do
                m[guid].kickStart, m[guid].kickDuration = start, 15
            end
            local guid, tier = KT.GuessTarget(m, row.cands, 10, row.heard)
            assert.equals(row.want, guid, row.name)
            assert.equals(row.tier, tier, row.name)
        end
    end)
end)

describe("KickTracker claim of a placed kick", function()
    it("holds a waiting interrupt, hands back a guess on another row, and keeps the rest", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "a waiting interrupt is held", entry = { state = "pending" }, want = "hold" },
            { name = "a guess on another row is handed back",
              entry = { state = "guessed", guess = { guid = "ann" } }, want = "handback" },
            { name = "a guess on the claimer is kept",
              entry = { state = "guessed", guess = { guid = "syn" } }, want = nil },
            { name = "a named charge is kept", entry = { state = "fold" }, want = nil },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.ClaimEffect(row.entry, "syn"), row.name)
        end
    end)
end)

describe("KickTracker guess hand-back", function()
    it("restores the row's earlier state only while it still holds the guess", function()
        local KT = L.loadKickTrackerRules()
        local earlier = { icon = 1 }
        local guess = { guid = "ann", start = 10, charge = 7,
                        prior = { kickStart = 4, kickDuration = 15, kicked = earlier, chargeID = 3 } }
        local rows = {
            { name = "the row still holds the guess", kickStart = 10, chargeID = 7, done = true,
              wantStart = 4, wantDuration = 15, wantCharge = 3, wantEarlier = true },
            { name = "a row charged since at the same start time keeps its charge", kickStart = 10, chargeID = 8,
              done = false, wantStart = 10, wantDuration = 12, wantCharge = 8, wantEarlier = false },
            { name = "a row cleared since stays clear", kickStart = nil, chargeID = 7,
              done = false, wantStart = nil, wantDuration = 12, wantCharge = 7, wantEarlier = false },
        }
        for _, row in ipairs(rows) do
            local before = { icon = 2 }
            local member = { kickStart = row.kickStart, kickDuration = 12, kicked = before, chargeID = row.chargeID }
            assert.equals(row.done, KT.HandBackGuess(member, guess), row.name)
            assert.equals(row.wantStart, member.kickStart, row.name)
            assert.equals(row.wantDuration, member.kickDuration, row.name)
            assert.equals(row.wantCharge, member.chargeID, row.name)
            assert.equals(row.wantEarlier and earlier or before, member.kicked, row.name)
        end
    end)
end)

describe("KickTracker kick durations", function()
    local function ranksOf(t) return function(talent) return t[talent] end end

    it("applies the base, a spec base, flat seconds and a multiplier, keeping fractions", function()
        local KT = L.loadKickTrackerRules()
        local counterspell = { base = 25, modifiers = { { talent = 1, seconds = 5 } } }
        local pummel = { base = 15, modifiers = { { talent = 2, multiplier = 0.9 } } }
        local quell = { base = 20, modifiers = { { talent = 3, multiplier = 0.9 } } }
        local windShear = { base = 12, specBase = { [264] = 30 } }
        local rows = {
            { name = "Counterspell", def = counterspell, rank = {}, want = 25 },
            { name = "Counterspell with Quick Witted", def = counterspell, rank = { [1] = 1 }, want = 20 },
            { name = "Pummel with Honed Reflexes", def = pummel, rank = { [2] = 1 }, want = 13.5 },
            { name = "Quell with Interwoven Threads", def = quell, rank = { [3] = 1 }, want = 18 },
            { name = "Wind Shear, Enhancement", def = windShear, spec = 263, rank = {}, want = 12 },
            { name = "Wind Shear, Restoration", def = windShear, spec = 264, rank = {}, want = 30 },
        }
        for _, row in ipairs(rows) do
            assert.near(row.want, KT.KickDuration(row.def, row.spec, ranksOf(row.rank), false), 1e-9, row.name)
        end
    end)

    it("counts a selected talent and reads rank 0, an absent node and an unknown rank as not selected", function()
        local KT = L.loadKickTrackerRules()
        local def = { base = 25, modifiers = { { talent = 7, seconds = 5 } } }
        local rows = {
            { name = "selected", known = true, want = 20,
              snap = { ranks = { [7] = 1 }, covered = { [7] = true }, absent = {} } },
            { name = "rank 0", known = true, want = 25,
              snap = { ranks = { [7] = 0 }, covered = { [7] = true }, absent = {} } },
            { name = "absent from the tree", known = true, want = 25,
              snap = { ranks = { [7] = 0 }, covered = { [7] = true }, absent = { [7] = true } } },
            { name = "not covered by the read", known = false, want = 25,
              snap = { ranks = {}, covered = {}, absent = {} } },
            { name = "a stale read", known = false, want = 25,
              snap = { ranks = { [7] = 1 }, covered = { [7] = true }, absent = {}, stale = "spec" } },
            { name = "no snapshot", known = false, want = 25, snap = nil },
        }
        for _, row in ipairs(rows) do
            local function rankOf(talent) return KT.SnapshotRank(row.snap, talent) end
            assert.equals(row.known, KT.SnapshotRank(row.snap, 7) ~= nil, row.name)
            assert.equals(row.want, KT.KickDuration(def, nil, rankOf, false), row.name)
        end
    end)

    it("takes a success rule off a confirmed cast only, and never a primary-only rule", function()
        local KT = L.loadKickTrackerRules()
        local mindFreeze = { base = 15, success = { talent = 8, seconds = 3 } }
        local solarBeam = { base = 60, success = { talent = 9, seconds = 15, primaryOnly = true } }
        local rows = {
            { name = "a confirmed success with the talent", def = mindFreeze, rank = { [8] = 1 },
              succeeded = true, want = 12 },
            { name = "an unconfirmed cast", def = mindFreeze, rank = { [8] = 1 }, succeeded = false, want = 15 },
            { name = "a confirmed success, the talent unknown", def = mindFreeze, rank = {},
              succeeded = true, want = 15 },
            { name = "a primary-only rule", def = solarBeam, rank = { [9] = 1 }, succeeded = true, want = 60 },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.KickDuration(row.def, nil, ranksOf(row.rank), row.succeeded), row.name)
        end
    end)
end)

describe("KickTracker class fallback", function()
    it("keeps the role rule and gives the role's duration", function()
        local KT = L.loadKickTrackerRules()
        local druid = { id = 106839, cd = 60, tankCd = 15 }
        local shaman = { id = 57994, cd = 12, allRoles = true, healerCd = 30 }
        local mage = { id = 2139, cd = 25, allRoles = true }
        local priest = { id = 15487, cd = 30 }
        local rows = {
            { name = "a damage-role druid", fb = druid, role = "DAMAGER", cd = 60, rowRole = "DAMAGER" },
            { name = "a tank druid", fb = druid, role = "TANK", cd = 15, rowRole = "TANK" },
            { name = "a healer druid", fb = druid, role = "HEALER", cd = nil },
            { name = "a druid with no role", fb = druid, role = "NONE", cd = nil },
            { name = "a healer shaman", fb = shaman, role = "HEALER", cd = 30, rowRole = "HEALER" },
            { name = "an every-spec class with no role", fb = mage, role = "NONE", cd = 25, rowRole = "DAMAGER" },
            { name = "a damage-role priest", fb = priest, role = "DAMAGER", cd = 30, rowRole = "DAMAGER" },
            { name = "a healer priest", fb = priest, role = "HEALER", cd = nil },
        }
        for _, row in ipairs(rows) do
            local kick = KT.FallbackKick(row.fb, row.role)
            assert.equals(row.cd, kick and kick.cd, row.name)
            assert.equals(row.rowRole, kick and kick.role, row.name)
        end
    end)
end)

describe("KickTracker running clock", function()
    it("keeps the duration a clock started with when a teammate's talents become known", function()
        local KT = L.loadKickTrackerRules()
        local def = { base = 25, modifiers = { { talent = 7, seconds = 5 } } }
        local member = { unit = "party1", interruptData = { id = 2139, cd = 25 } }
        local function rankOf(talent) return KT.SnapshotRank(member.inspect, talent) end
        member.kickStart, member.kickDuration = 10, KT.KickDuration(def, 62, rankOf, false)
        local snap = { spec = 62, ranks = { [7] = 1 }, covered = { [7] = true }, absent = {} }
        assert.is_false(KT.LearnFacts(member, snap, { id = 2139, cd = 20 }))
        assert.equals(10, member.kickStart)
        assert.equals(25, member.kickDuration)
        assert.equals(20, KT.KickDuration(def, 62, rankOf, false))
    end)
end)
