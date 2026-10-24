-- Modules/DungeonTools/KicksCasts/KickTrackerRules.lua: the kick tracker's pure decisions.
-- Frames, bars, the engine timers and event wiring are checked in game.
local L = require("dev.spec._ke_loader")

describe("KickTracker row visibility", function()
    it("shows every member with a kick and no member without one", function()
        local KT = L.loadKickTrackerRules()
        local kick = { id = 1766, cd = 15 }
        local rows = {
            { name = "own row", shown = true, member = { unit = "player", interruptData = kick } },
            { name = "a teammate", shown = true, member = { unit = "party1", interruptData = kick } },
            { name = "no kick", shown = false, member = { unit = "party1" } },
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

describe("KickTracker own kick claim", function()
    it("claims one readable own interrupt inside the window after the own cast, once", function()
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

describe("KickTracker nameplate kicker", function()
    it("sorts the kicker by its token, a party pet to its owner, and anything unreadable as hidden", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "the player", ok = true, token = "player", kind = "own" },
            { name = "the player's pet", ok = true, token = "pet", kind = "own" },
            { name = "a teammate, GUID secret", ok = true, token = "party2", guidSecret = true,
              kind = "member", index = 2 },
            { name = "a teammate's pet, GUID secret", ok = true, token = "partypet3", guidSecret = true,
              kind = "member", index = 3 },
            { name = "no token, GUID plain", ok = true, token = nil, kind = "guid" },
            { name = "another plain token, GUID secret", ok = true, token = "nameplate4", guidSecret = true,
              kind = "hidden" },
            { name = "a party token outside 1-4, GUID secret", ok = true, token = "party5", guidSecret = true,
              kind = "hidden" },
            { name = "no token, GUID secret", ok = true, token = nil, guidSecret = true, kind = "hidden" },
            { name = "a secret token", ok = true, token = "party1", tokenSecret = true, kind = "hidden" },
            { name = "a failed call", ok = false, token = "error text", kind = "hidden" },
        }
        for _, row in ipairs(rows) do
            local kind, index = KT.ClassifyKicker(row.ok, row.token, row.tokenSecret == true, row.guidSecret == true)
            assert.equals(row.kind, kind, row.name)
            assert.equals(row.index, index, row.name)
        end
    end)
end)

describe("KickTracker meter counts", function()
    local function read(rows, rowsOk, n, guid)
        return { rows = rows, rowsOk = rowsOk, n = n, a = {}, guid = guid }
    end

    it("keeps a failed read's last count and rows, and shows the growth on the next good read", function()
        local KT = L.loadKickTrackerRules()
        local base = read({ "MAGE:1" }, true, { party1 = 2 }, { party1 = "P1" })
        local failed = read({}, false, {}, { party1 = "P1" })
        KT.CarryCounts(failed, base)
        assert.equals(2, failed.n.party1)
        assert.same({ "MAGE:1" }, failed.rows)
        local prev = KT.BaselineCounts(failed, base, {}, {})
        assert.is_false(KT.ListsMoved(failed.rows, failed.n, base.rows, prev))
        assert.equals(0, failed.n.party1 - prev.party1)
        local good = read({ "MAGE:1" }, true, { party1 = 3 }, { party1 = "P1" })
        KT.CarryCounts(good, failed)
        prev = KT.BaselineCounts(good, failed, {}, {})
        assert.is_false(KT.ListsMoved(good.rows, good.n, failed.rows, prev))
        assert.equals(1, good.n.party1 - prev.party1)
    end)

    it("takes a count that fell, or fewer rows, as a new fight", function()
        local KT = L.loadKickTrackerRules()
        local base = read({ "MAGE:1", "ROGUE:2" }, true, { party1 = 3 }, { party1 = "P1" })
        local rows = {
            { name = "a count that fell", read = read({ "MAGE:1", "ROGUE:2" }, true, { party1 = 1 }, { party1 = "P1" }) },
            { name = "fewer rows", read = read({ "MAGE:1" }, true, { party1 = 3 }, { party1 = "P1" }) },
        }
        for _, row in ipairs(rows) do
            local prev = KT.BaselineCounts(row.read, base, {}, {})
            assert.is_true((KT.ListsMoved(row.read.rows, row.read.n, base.rows, prev)), row.name)
        end
    end)
end)

describe("KickTracker meter slots", function()
    it("counts a pet's list growth and entries for its owner", function()
        local KT = L.loadKickTrackerRules()
        local growth, entries = {}, {}
        KT.OwnerGrowth({ party3 = 2, partypet3 = 3, pet = 1 }, { party3 = 2, partypet3 = 2, pet = 1 },
            growth, entries)
        assert.same({ party3 = 1 }, growth)
        assert.same({ party3 = 5, player = 1 }, entries)
    end)

    it("restarts a slot from its first usable read when its GUID changed or it never read under it", function()
        local KT = L.loadKickTrackerRules()
        local base = { rows = {}, n = { party1 = 4, partypet1 = 2 }, a = {},
                       guid = { party1 = "P1", partypet1 = "Pet-A", party2 = "P2" } }
        local now = { rows = {}, n = { party1 = 5, partypet1 = 1, party2 = 6 }, a = {},
                      guid = { party1 = "P1", partypet1 = "Pet-B", party2 = "P2" } }
        local prev = KT.BaselineCounts(now, base, {}, {})
        assert.equals(4, prev.party1)
        assert.equals(1, prev.partypet1)
        assert.equals(6, prev.party2)
        assert.is_false((KT.ListsMoved(now.rows, now.n, base.rows, prev)))
    end)
end)

describe("KickTracker expected counts", function()
    it("lets a readable kick's count take its own growth once, drops one past the window, and reports it", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "its own growth", e = { n = 1, at = 10 }, growth = 1, T = 10.05, left = 0, kept = false,
              readable = true },
            { name = "a hidden kick beside it", e = { n = 1, at = 10 }, growth = 2, T = 10.05, left = 1, kept = false,
              readable = true },
            { name = "two readable kicks, one grew", e = { n = 2, at = 10 }, growth = 1, T = 10.05, left = 0, kept = true,
              readable = true },
            { name = "a repeated spell that grew nothing", e = { n = 1, at = 10 }, growth = 0, T = 10.05, left = 0,
              kept = true, readable = true },
            { name = "past the window", e = { n = 1, at = 10 }, growth = 1, T = 11, left = 1, kept = false,
              readable = false },
            { name = "no readable kick", e = nil, growth = 1, T = 11, left = 1, kept = false, readable = false },
        }
        for _, row in ipairs(rows) do
            local expected = { party1 = row.e }
            local left, readable = KT.TakeGrowth(expected, "party1", row.growth, row.T, 0.25)
            assert.equals(row.left, left, row.name)
            assert.equals(row.readable, readable, row.name)
            assert.equals(row.kept, expected.party1 ~= nil, row.name)
        end
    end)
end)

describe("KickTracker meter decision", function()
    local function inputs(over)
        local e = { grew = {}, growthOf = {}, entries = {}, cooling = {}, candidates = { "party1", "party2" },
                    ownPending = false, plates = 0 }
        for k, v in pairs(over) do e[k] = v end
        return e
    end

    it("names one list that grew by one, and skips a mass interrupt and a grip", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "a teammate grew by one, one plate", who = "party1", how = "breakdown",
              e = { grew = { "party1" }, growthOf = { party1 = 1 }, plates = 1 } },
            { name = "a teammate grew by one, no plate", who = "party1", how = "breakdown",
              e = { grew = { "party1" }, growthOf = { party1 = 1 } } },
            { name = "one list grew by two", who = nil, how = "mass",
              e = { grew = { "party1" }, growthOf = { party1 = 2 } } },
            { name = "one grower and two plates", who = nil, how = "mass",
              e = { grew = { "party1" }, growthOf = { party1 = 1 }, plates = 2 } },
            { name = "the player grew with no cast pending", who = nil, how = "grip",
              e = { grew = { "player" }, growthOf = { player = 1 } } },
            { name = "the player grew with a cast pending", who = "player", how = "breakdown",
              e = { grew = { "player" }, growthOf = { player = 1 }, ownPending = true } },
            { name = "a teammate grew while cooling", who = nil, how = "grip",
              e = { grew = { "party1" }, growthOf = { party1 = 1 }, cooling = { party1 = true } } },
        }
        for _, row in ipairs(rows) do
            local who, how = KT.Decide(inputs(row.e))
            assert.equals(row.who, who, row.name)
            assert.equals(row.how, how, row.name)
        end
    end)

    it("credits every teammate whose list grew in one update, cooling or not", function()
        local KT = L.loadKickTrackerRules()
        local who, how, several = KT.Decide(inputs({ grew = { "party1", "party2" },
            growthOf = { party1 = 1, party2 = 1 }, cooling = { party2 = true }, plates = 1 }))
        assert.is_nil(who)
        assert.equals("several", how)
        assert.same({ "party1", "party2" }, several)
    end)

    it("names a row's one inspected match, and nobody for a shared key, an unread icon or the player's row", function()
        local KT = L.loadKickTrackerRules()
        local icons = { [62] = 135932, [64] = 135846 }
        local function iconOf(spec) return icons[spec] end
        local function mage(unit, spec)
            return { unit = unit, matchClass = "MAGE", specID = spec, interruptData = { id = 2139 } }
        end
        local rows = {
            { name = "one teammate of that class and spec", class = "MAGE", icon = 135932, who = "party1",
              byUnit = { party1 = mage("party1", 62), party2 = mage("party2", 64) } },
            { name = "one match whose per-GUID read does not work", class = "MAGE", icon = 135932, who = "party1",
              entries = {}, byUnit = { party1 = mage("party1", 62), party2 = mage("party2", 64) } },
            { name = "a key two teammates share", class = "MAGE", icon = 135932, who = nil,
              byUnit = { party1 = mage("party1", 62), party2 = mage("party2", 62) } },
            { name = "a spec not inspected yet", class = "MAGE", icon = 135932, who = nil,
              byUnit = { party1 = mage("party1", 0), party2 = mage("party2", 64) } },
            { name = "a row with no spec icon (unread, or a demon's)", class = "MAGE", icon = nil, who = nil,
              byUnit = { party1 = mage("party1", 62), party2 = mage("party2", 64) } },
            { name = "the player's own row", class = "MAGE", icon = 135932, me = true, who = nil,
              byUnit = { party1 = mage("party1", 62), party2 = mage("party2", 64) } },
        }
        for _, row in ipairs(rows) do
            local key = KT.RowKey(row.class, row.icon, row.me)
            local e = inputs({ rowKey = key, rowHow = "reorder", entries = row.entries or { party1 = 1, party2 = 1 },
                               rowList = KT.KeyMembers(key, row.byUnit, iconOf, {}) })
            assert.equals(row.who, (KT.Decide(e)), row.name)
        end
    end)

    it("gives the player a kick nothing else names while their cast is pending, with no success reduction", function()
        local KT = L.loadKickTrackerRules()
        local who, how = KT.Decide(inputs({ ownPending = true, entries = { party1 = 1, party2 = 1 } }))
        assert.equals("player", who)
        assert.equals("cast", how)
        local rows = {
            { how = "cast", pending = true, want = false },
            { how = "breakdown", pending = true, want = true },
            { how = "several", pending = true, want = true },
            { how = "several", pending = false, want = false },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.OwnSuccessFrom(row.how, row.pending), row.how .. " " .. tostring(row.pending))
        end
    end)

    it("names the only teammate with entries among several, and nobody when two are left", function()
        local KT = L.loadKickTrackerRules()
        local rows = {
            { name = "one with entries, one without", entries = { party1 = 2, party2 = 0 }, who = "party1", how = "order" },
            { name = "one with entries, one never read", entries = { party1 = 2 }, who = "party1", how = "order" },
            { name = "two with entries", entries = { party1 = 2, party2 = 1 }, who = nil, how = "nobody" },
        }
        for _, row in ipairs(rows) do
            local who, how = KT.Decide(inputs({ entries = row.entries }))
            assert.equals(row.who, who, row.name)
            assert.equals(row.how, how, row.name)
        end
    end)
end)

describe("KickTracker reveal layers", function()
    it("admits a teammate with a kick row, not cooling, an entry before and after, and both totals", function()
        local KT = L.loadKickTrackerRules()
        local mate = { unit = "party1", interruptData = { id = 2139 } }
        local rows = {
            { name = "a teammate who could have kicked", member = mate, prev = 1, cur = 2, totals = true, want = true },
            { name = "the player", member = { unit = "player", interruptData = { id = 2139 } },
              prev = 1, cur = 2, totals = true, want = false },
            { name = "no kick row", member = { unit = "party1" }, prev = 1, cur = 2, totals = true, want = false },
            { name = "cooling", member = mate, cooling = true, prev = 1, cur = 2, totals = true, want = false },
            { name = "no entry before the update", member = mate, prev = 0, cur = 1, totals = true, want = false },
            { name = "no count read", member = mate, prev = 1, cur = nil, totals = true, want = false },
            { name = "a total missing", member = mate, prev = 1, cur = 2, totals = false, want = false },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, KT.AdmitGate(row.member, row.cooling == true, row.prev, row.cur, row.totals),
                row.name)
        end
    end)

    it("releases the layers started at or before a sure kick, and all of them with no time", function()
        local KT = L.loadKickTrackerRules()
        local function layers() return { { t = 5 }, { t = 10 }, { t = 15 } } end
        local freed = {}
        local function free(layer) freed[#freed + 1] = layer.t end
        local list = layers()
        KT.ReleaseUpTo(list, 10, free)
        table.sort(freed)
        assert.same({ 5, 10 }, freed)
        assert.equals(1, #list)
        assert.equals(15, list[1].t)
        list = layers()
        KT.ReleaseUpTo(list, nil, free)
        assert.equals(0, #list)
    end)
end)
