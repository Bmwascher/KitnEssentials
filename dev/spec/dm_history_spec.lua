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
