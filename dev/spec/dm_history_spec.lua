-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_history_spec.lua                            ║
-- ║  DamageMeter/History.lua — snapshot store (Tier 2).      ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- HONESTY BOUNDARY (see dev/README.md): C_DamageMeter / C_ChallengeMode /
-- issecretvalue are stubbed. Passing specs verify KE's store/branch logic
-- against DECLARED values, never real 12.0 taint semantics (in-game only).
local L = require("dev.spec._ke_loader")

local DM
before_each(function()
    DM = (L.loadDMHistory())
    DM.db = { HistoryRetain = 5 }
end)

describe("HistorySourceKey", function()
    it("prefers the GUID", function()
        assert.equals("Creature-0-1", DM.HistorySourceKey("Creature-0-1", 12345))
    end)
    it("falls back to a creatureID key", function()
        assert.equals("c:12345", DM.HistorySourceKey(nil, 12345))
    end)
    it("returns nil when both are nil", function()
        assert.is_nil(DM.HistorySourceKey(nil, nil))
    end)
    it("refuses secret inputs (declared)", function()
        local secretGuid = { __secret = true }
        assert.equals("c:7", DM.HistorySourceKey(secretGuid, 7))
        assert.is_nil(DM.HistorySourceKey(secretGuid, { __secret = true }))
    end)
end)

describe("store lookups", function()
    -- Seed the store by hand (capture is Task 2); lookups are pure.
    local function seedEntry(id)
        DM._history = DM._history or { bundles = {}, byID = {}, nextID = -1 }
        local entry = {
            id = id, byType = { [0] = { totalAmount = 100 } },
            sources = { ["guid-A"] = { [0] = { totalAmount = 60 } } },
        }
        DM._history.byID[id] = entry
        return entry
    end

    it("HistorySession serves a retained table by negative id + type", function()
        seedEntry(-1)
        assert.equals(100, DM:HistorySession(-1, 0).totalAmount)
    end)
    it("HistorySession returns nil for unknown id or type", function()
        seedEntry(-1)
        assert.is_nil(DM:HistorySession(-2, 0))
        assert.is_nil(DM:HistorySession(-1, 3))
        DM._history = nil
        assert.is_nil(DM:HistorySession(-1, 0))
    end)
    it("HistorySource resolves through the same SourceKey as capture", function()
        seedEntry(-1)
        assert.equals(60, DM:HistorySource(-1, 0, "guid-A", nil).totalAmount)
        assert.is_nil(DM:HistorySource(-1, 0, "guid-B", nil))
        assert.is_nil(DM:HistorySource(-1, 0, nil, nil))
    end)
    it("HistoryClear empties bundles and byID but keeps nextID counting", function()
        seedEntry(-3)
        DM._history.nextID = -4
        DM._history.bundles[1] = { sessions = {} }
        DM:HistoryClear()
        assert.equals(0, #DM._history.bundles)
        assert.is_nil(DM._history.byID[-3])
        assert.equals(-4, DM._history.nextID)
    end)
    it("HistoryBundles returns nil when nothing captured", function()
        assert.is_nil(DM:HistoryBundles())
    end)
end)

describe("plain-name identity memo", function()
    it("stores a player name and serves it back", function()
        DM:NotePlainName("Player-1-A", "Itsgg-Illidan")
        assert.equals("Itsgg-Illidan", DM:PlainNameFor("Player-1-A"))
    end)
    it("ignores creature GUIDs (identity restriction is player-only)", function()
        DM:NotePlainName("Creature-0-123", "Overgrown Ancient")
        assert.is_nil(DM:PlainNameFor("Creature-0-123"))
    end)
    it("refuses secret inputs (declared)", function()
        local secret = { __secret = true }
        -- Seed a live memo FIRST so the secret-guid lookup below traverses the
        -- full PlainNameFor guard, not the empty-store short-circuit (Codex
        -- delta review, F2).
        DM:NotePlainName("Player-1-S", "Seeder")
        DM:NotePlainName(secret, "Unsub-BurningLegion")
        DM:NotePlainName("Player-1-B", secret)
        assert.is_nil(DM:PlainNameFor("Player-1-B"))
        assert.is_nil(DM:PlainNameFor(secret))
        assert.equals("Seeder", DM:PlainNameFor("Player-1-S"))
    end)
    it("refuses nil and empty names", function()
        DM:NotePlainName("Player-1-C", nil)
        DM:NotePlainName("Player-1-C", "")
        DM:NotePlainName(nil, "Ghost")
        assert.is_nil(DM:PlainNameFor("Player-1-C"))
    end)
    it("never downgrades a realm-bearing name to a bare flicker form", function()
        DM:NotePlainName("Player-1-D", "Unsub")                 -- bare first sighting
        -- Bare names DO store: same-realm members are bare in det.unitName too
        -- (probe 2026-07-19) — only the realm-bearing->bare OVERWRITE is
        -- refused (Codex delta review, F3).
        assert.equals("Unsub", DM:PlainNameFor("Player-1-D"))
        DM:NotePlainName("Player-1-D", "Unsub-BurningLegion")   -- upgrade sticks
        DM:NotePlainName("Player-1-D", "Unsub")                 -- flicker tick: ignored
        assert.equals("Unsub-BurningLegion", DM:PlainNameFor("Player-1-D"))
    end)
    it("PlainNameFor is nil-safe before anything is learned", function()
        assert.is_nil(DM:PlainNameFor("Player-1-E"))
        assert.is_nil(DM:PlainNameFor(nil))
    end)
end)

-- Fake C_DamageMeter backing an 11-type store: sessions[oldID][dmType] =
-- session table, sourceDetails[oldID][dmType][guidOrCid] = source table.
local function installFakeMeter(sessions, sourceDetails)
    _G.C_DamageMeter = {
        GetAvailableCombatSessions = function()
            local list = {}
            for id in pairs(sessions) do
                list[#list + 1] = { sessionID = id, name = "S" .. id, durationSeconds = 60 + id }
            end
            table.sort(list, function(a, b) return a.sessionID < b.sessionID end)
            return list
        end,
        GetCombatSessionFromID = function(id, dmType)
            local s = sessions[id]
            return s and s[dmType] or nil
        end,
        GetCombatSessionSourceFromID = function(id, dmType, guid, cid)
            local d = sourceDetails[id]
            d = d and d[dmType]
            return d and d[guid or ("c:" .. tostring(cid))] or nil
        end,
        ResetAllCombatSessions = function() end,
    }
end

describe("HistoryCapture", function()
    -- Deliberately NO GetAvailableSessions override: capture must flow
    -- through the REAL Core.lua helper (which trims an omitted cap to 20 —
    -- its menu contract). A fake that ignored cap once masked exactly that
    -- defect (Codex round 2, F2').

    local function oneSessionStore()
        -- Session 7: type 0 has two sources (one GUID-less), type 9 empty.
        local sessions = { [7] = { [0] = {
            totalAmount = 100,
            combatSources = {
                { sourceGUID = "g1", totalAmount = 60 },
                { sourceGUID = nil, sourceCreatureID = 42, totalAmount = 40 },
                { sourceGUID = nil, sourceCreatureID = nil, totalAmount = 0 },
            } } } }
        local details = { [7] = { [0] = {
            ["g1"]   = { totalAmount = 60, combatSpells = {} },
            ["c:42"] = { totalAmount = 40, combatSpells = {} },
        } } }
        return sessions, details
    end

    it("retains byType and per-source details keyed by HistorySourceKey", function()
        installFakeMeter(oneSessionStore())
        DM._pendingBundle = { label = "Algeth'ar Academy", level = 12 }
        local bundle = DM:HistoryCapture()
        assert.is_table(bundle)
        assert.equals(1, #bundle.sessions)
        local e = bundle.sessions[1]
        assert.equals(-1, e.id)
        assert.equals(100, e.byType[0].totalAmount)
        assert.equals(60, e.sources["g1"][0].totalAmount)
        assert.equals(40, e.sources["c:42"][0].totalAmount)
        -- both-nil source skipped [C3]; bar row still renders from byType
        local n = 0
        for _ in pairs(e.sources) do n = n + 1 end
        assert.equals(2, n)
        -- served back through the store lookups
        assert.equals(100, DM:HistorySession(-1, 0).totalAmount)
        assert.equals(40, DM:HistorySource(-1, 0, nil, 42).totalAmount)
    end)

    it("takes the armed pending label and freezes per-segment outcomes [C1]", function()
        installFakeMeter(oneSessionStore())
        DM._pendingBundle = { label = "Algeth'ar Academy", level = 12,
                              outcome = false, durationMs = 1934000, summarySessionID = 7 }
        DM._sessionOutcomes = { [7] = true }
        local bundle = DM:HistoryCapture()
        assert.equals("Algeth'ar Academy", bundle.label)
        assert.equals(12, bundle.level)
        assert.is_false(bundle.outcome)          -- depleted-completed = false, from completion info
        assert.equals(1934000, bundle.durationMs)
        assert.is_true(bundle.sessions[1].outcome)   -- boss kill tag frozen per segment
        assert.is_true(bundle.sessions[1].isSummary)
        assert.is_nil(DM._pendingBundle)         -- always consumed
    end)

    it("freezes a FALSE (wipe) segment outcome — never collapsed to nil [C1]", function()
        installFakeMeter(oneSessionStore())
        DM._pendingBundle = { label = "Algeth'ar Academy" }
        DM._sessionOutcomes = { [7] = false }
        local bundle = DM:HistoryCapture()
        assert.is_false(bundle.sessions[1].outcome)
    end)

    it("captures past the helper's default 20-session menu cap [F2']", function()
        local sessions, details = {}, {}
        for id = 1, 25 do
            sessions[id] = { [0] = { totalAmount = id, combatSources = {} } }
        end
        installFakeMeter(sessions, details)
        DM._pendingBundle = nil
        local bundle = DM:HistoryCapture()
        assert.equals(25, #bundle.sessions)
    end)

    it("seals unarmed captures with no label (menu shows 'Earlier runs') [C2]", function()
        installFakeMeter(oneSessionStore())
        DM._pendingBundle = nil
        local bundle = DM:HistoryCapture()
        assert.is_nil(bundle.label)
        assert.is_nil(bundle.outcome)
        assert.is_nil(bundle.durationMs)
    end)

    it("learns current members' plain names during the deep pass", function()
        local sessions = { [7] = { [0] = {
            totalAmount = 100,
            combatSources = {
                { sourceGUID = "Player-1-A", name = "Itsgg-Illidan", totalAmount = 60 },
                { sourceGUID = "Creature-0-9", name = "Territorial Eagle", totalAmount = 40 },
                -- Departed member: the name marshaled SECRET at capture time —
                -- must never enter the memo (it was learned live, if at all).
                { sourceGUID = "Player-1-B", name = { __secret = true }, totalAmount = 20 },
            } } } }
        installFakeMeter(sessions, { [7] = { [0] = {} } })
        DM._pendingBundle = nil
        DM:HistoryCapture()
        assert.equals("Itsgg-Illidan", DM:PlainNameFor("Player-1-A"))
        assert.is_nil(DM:PlainNameFor("Creature-0-9"))
        assert.is_nil(DM:PlainNameFor("Player-1-B"))
    end)

    it("seals no bundle on an empty store but still clears pending", function()
        installFakeMeter({}, {})
        DM._pendingBundle = { label = "X" }
        assert.is_nil(DM:HistoryCapture())
        assert.is_nil(DM._pendingBundle)
        assert.is_nil(DM:HistoryBundles())
    end)

    it("evicts whole oldest bundles beyond HistoryRetain, clamped to [1,10]", function()
        DM.db.HistoryRetain = 2
        for i = 1, 3 do
            installFakeMeter(oneSessionStore())
            DM._pendingBundle = { label = "Key " .. i }
            DM:HistoryCapture()
        end
        local bundles = DM:HistoryBundles()
        assert.equals(2, #bundles)
        assert.equals("Key 3", bundles[1].label)    -- newest first
        assert.equals("Key 2", bundles[2].label)
        -- evicted bundle's ids are gone from byID; survivors still resolve
        assert.is_nil(DM:HistorySession(-1, 0))
        assert.is_not_nil(DM:HistorySession(-3, 0))
        -- legacy out-of-range value clamps at read (NO migration)
        DM.db.HistoryRetain = 20
        installFakeMeter(oneSessionStore())
        DM:HistoryCapture()
        assert.equals(3, #DM:HistoryBundles())      -- 20 clamps to 10; nothing evicted at 3
    end)
end)

describe("pending-key metadata", function()
    it("HistoryArmPending reads keystone identity", function()
        _G.C_ChallengeMode = {
            GetActiveChallengeMapID = function() return 501 end,
            GetMapUIInfo = function(id) return id == 501 and "Algeth'ar Academy" or nil end,
            GetActiveKeystoneInfo = function() return 12, {} end,
        }
        DM:HistoryArmPending()
        assert.equals("Algeth'ar Academy", DM._pendingBundle.label)
        assert.equals(12, DM._pendingBundle.level)
    end)

    it("HistoryArmPending tolerates a level-0 read [C4]", function()
        _G.C_ChallengeMode = {
            GetActiveChallengeMapID = function() return 501 end,
            GetMapUIInfo = function() return "Algeth'ar Academy" end,
            GetActiveKeystoneInfo = function() return 0, {} end,
        }
        DM:HistoryArmPending()
        assert.is_nil(DM._pendingBundle.level)
    end)

    local function completionEnv()
        _G.C_ChallengeMode = {
            GetChallengeCompletionInfo = function()
                return { mapChallengeModeID = 501, level = 12, time = 1934000, onTime = false }
            end,
            GetMapUIInfo = function() return "Algeth'ar Academy" end,
        }
        -- Queue of list snapshots: call 1 = at the event, call 2 = post-settle.
        local lists, calls = {}, 0
        DM.GetAvailableSessions = function()
            calls = calls + 1
            return lists[calls] or lists[#lists]
        end
        local fired
        local mockLib = require("dev.spec._wow_mock")
        mockLib.install({ C_Timer = { After = function(_, fn) fired = fn end,
                                      NewTicker = function() return { Cancel = function() end } end } })
        return lists, function() return fired end
    end

    it("HistoryOnKeyComplete repairs pending and picks the POST-event id as summary [C1][C4]", function()
        DM._pendingBundle = { label = "Algeth'ar Academy" }   -- level was 0 at start
        local lists, firedRef = completionEnv()
        -- At the event the store holds old trash (7) + the final BOSS (8);
        -- the "+NN" summary (9) lands after. Newest-at-event would wrongly
        -- pick 8 — the set diff must pick 9.
        lists[1] = { { sessionID = 7 }, { sessionID = 8 } }
        lists[2] = { { sessionID = 7 }, { sessionID = 8 }, { sessionID = 9 } }
        DM:HistoryOnKeyComplete()
        assert.equals(12, DM._pendingBundle.level)
        assert.is_false(DM._pendingBundle.outcome)
        assert.equals(1934000, DM._pendingBundle.durationMs)
        local fired = firedRef()
        assert.is_function(fired)
        fired()
        assert.equals(9, DM._pendingBundle.summarySessionID)
    end)

    it("falls back to the newest id when nothing new appears post-event", function()
        DM._pendingBundle = { label = "Algeth'ar Academy" }
        local lists, firedRef = completionEnv()
        lists[1] = { { sessionID = 7 }, { sessionID = 8 } }
        lists[2] = { { sessionID = 7 }, { sessionID = 8 } }
        DM:HistoryOnKeyComplete()
        firedRef()()
        assert.equals(8, DM._pendingBundle.summarySessionID)
    end)

    it("HistoryOnKeyComplete is a no-op when pending is unarmed", function()
        DM._pendingBundle = nil
        _G.C_ChallengeMode = { GetChallengeCompletionInfo = function() error("must not be called") end }
        DM:HistoryOnKeyComplete()
        assert.is_nil(DM._pendingBundle)
    end)
end)

describe("Core chokepoint branches", function()
    it("GetSession serves negative ids from the store, never the API", function()
        DM._history = { bundles = {}, byID = { [-4] = { byType = { [2] = { totalAmount = 5 } }, sources = {} } }, nextID = -5 }
        _G.C_DamageMeter = { GetCombatSessionFromID = function() error("API must not be called for snapshots") end }
        assert.equals(5, DM:GetSession(nil, 2, -4).totalAmount)
        assert.is_nil(DM:GetSession(nil, 9, -4))
        assert.is_nil(DM:GetSession(nil, 2, -99))   -- evicted/unknown -> "no session"
    end)

    it("GetSource serves negative ids via HistorySourceKey", function()
        DM._history = { bundles = {}, byID = { [-4] = { byType = {},
            sources = { ["c:42"] = { [0] = { totalAmount = 7 } } } } }, nextID = -5 }
        _G.C_DamageMeter = { GetCombatSessionSourceFromID = function() error("API must not be called") end }
        assert.equals(7, DM:GetSource(nil, 0, nil, 42, -4).totalAmount)
        assert.is_nil(DM:GetSource(nil, 0, "g9", nil, -4))
    end)
end)

describe("OnChallengeEvent wiring", function()
    local calls
    before_each(function()
        calls = {}
        -- Order-sensitive: capture must precede the API reset.
        DM.HistoryCapture = function() calls[#calls + 1] = "capture" end
        DM.HistoryArmPending = function() calls[#calls + 1] = "arm" end
        DM.HistoryOnKeyComplete = function() calls[#calls + 1] = "complete" end
        DM.BumpSegment = function() end
        DM.ApplyActiveContext = function() end
        DM.InvalidateTargetsCache = function() end
        DM.Tick = function() end
        DM.windows_rt = nil
        -- The toggle-ON test sets this one-shot flag via the real START path;
        -- the stubbed ResetAllCombatSessions never fires DAMAGE_METER_RESET to
        -- consume it, so it would otherwise leak into later tests/describes.
        DM._historyOwnReset = nil
        _G.C_DamageMeter = { ResetAllCombatSessions = function() calls[#calls + 1] = "reset" end }
    end)

    it("key start with the toggle ON: capture -> reset -> arm", function()
        DM.db = { ResetOnKeyStart = true, HistoryRetain = 5 }
        DM:OnChallengeEvent("CHALLENGE_MODE_START")
        assert.same({ "capture", "reset", "arm" }, calls)
    end)

    it("key start with the toggle ON: a failed reset call un-arms the flag [F pcall]", function()
        DM.db = { ResetOnKeyStart = true, HistoryRetain = 5 }
        _G.C_DamageMeter = { ResetAllCombatSessions = function() error("boom") end }
        DM:OnChallengeEvent("CHALLENGE_MODE_START")
        assert.is_nil(DM._historyOwnReset)
        -- No stale flag left to shield it: the NEXT (external) reset still
        -- clears pending provenance normally.
        DM._pendingBundle = { label = "Algeth'ar Academy" }
        DM:OnMeterReset()
        assert.is_nil(DM._pendingBundle)
    end)

    it("key start with the toggle OFF: no capture, pending cleared [C2]", function()
        DM.db = { ResetOnKeyStart = false }
        DM._pendingBundle = { label = "Stale" }
        DM:OnChallengeEvent("CHALLENGE_MODE_START")
        assert.same({}, calls)
        assert.is_nil(DM._pendingBundle)
    end)

    it("completion routes to HistoryOnKeyComplete", function()
        DM.db = { ResetOnKeyStart = true }
        DM:OnChallengeEvent("CHALLENGE_MODE_COMPLETED")
        assert.same({ "complete" }, calls)
    end)
end)

describe("HeaderReset clears history; OnMeterReset must NOT", function()
    before_each(function()
        DM.db = { HistoryRetain = 5 }
        DM._history = { bundles = { { sessions = {} } }, byID = {}, nextID = -2 }
        DM.InvalidateTargetsCache = function() end
        DM.CloseAllSelectors = function() end
        DM.CloseAllSegmentMenus = function() end
        DM.Tick = function() end
        -- Start flag-clean regardless of prior describes/ordering — only the
        -- "module's OWN reset" test below arms this itself.
        DM._historyOwnReset = nil
        _G.C_DamageMeter = { ResetAllCombatSessions = function() end }
    end)
    it("HeaderReset empties the store", function()
        DM:HeaderReset()
        assert.equals(0, #DM._history.bundles)
    end)
    it("OnMeterReset leaves the store alone (our own wipe fires this event)", function()
        DM:OnMeterReset()
        assert.equals(1, #DM._history.bundles)
    end)
    it("an EXTERNAL reset clears pending provenance but not bundles [F5']", function()
        DM._pendingBundle = { label = "Algeth'ar Academy", level = 12 }
        DM:OnMeterReset()
        assert.is_nil(DM._pendingBundle)
        assert.equals(1, #DM._history.bundles)
    end)
    it("the module's OWN reset preserves pending via the one-shot flag [F5']", function()
        DM._pendingBundle = { label = "Algeth'ar Academy", level = 12 }
        DM._historyOwnReset = true
        DM:OnMeterReset()
        assert.equals("Algeth'ar Academy", DM._pendingBundle.label)
        assert.is_nil(DM._historyOwnReset)   -- consumed: the next reset is external
        DM:OnMeterReset()
        assert.is_nil(DM._pendingBundle)
    end)
    it("HeaderReset clears pending provenance too [F5']", function()
        DM._pendingBundle = { label = "Algeth'ar Academy" }
        DM:HeaderReset()
        assert.is_nil(DM._pendingBundle)
    end)
end)
