-- Tier 2: TrashAuraDelta — the party harmful-aura delta sampler feeding the
-- castStartAuraDelta fingerprint (instance-ID diff cache + 1s recent ring).
-- DungeonTrash enables it per monitor session and routes UNIT_AURA /
-- GROUP_ROSTER_UPDATE here; these specs pin the cache/ring machinery alone.

local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("TrashAuraDelta", function()
    local TAD, KE, clock, world

    before_each(function()
        clock = { now = 100 }
        world = { debuffs = {} }
        mock.install({
            GetTime = function() return clock.now end,
        })
        -- Set BEFORE the module loads so the parse-time local captures it.
        _G.C_UnitAuras = {
            GetDebuffDataByIndex = function(unit, index)
                local list = world.debuffs[unit]
                local id = list and list[index]
                if id then return { auraInstanceID = id } end
                return nil
            end,
        }
        helpers.installAddonShim()
        KE = {}
        helpers.loadModule("Modules/DungeonTimers/Trash/TrashAuraDelta.lua", KE)
        TAD = KE.TrashAuraDelta
    end)

    after_each(function()
        mock.reset()
        _G.C_UnitAuras = nil
        _G.KitnEssentials = nil
    end)

    it("enable seeds baselines without ring entries", function()
        world.debuffs.player = { 11, 12 }
        TAD.SetEnabled(true)
        assert.is_true(TAD.seeded)
        assert.equals(0, #TAD.recentAdds)              -- pre-existing debuffs are not "new"
        assert.is_nil(TAD.FindRecentAdd(0, 200))
    end)

    it("a refresh records only NEW instance IDs", function()
        TAD.SetEnabled(true)
        world.debuffs.party2 = { 21 }
        clock.now = 101
        TAD.OnUnitAura("party2")
        assert.equals(1, #TAD.recentAdds)
        assert.equals(21, TAD.recentAdds[1].id)
        TAD.OnUnitAura("party2")                       -- same set again: no duplicate
        assert.equals(1, #TAD.recentAdds)
        world.debuffs.party2 = { 21, 22 }
        clock.now = 101.5
        TAD.OnUnitAura("party2")
        assert.equals(2, #TAD.recentAdds)              -- only the new ID appended
    end)

    it("FindRecentAdd honours the window and the 1s trim", function()
        TAD.SetEnabled(true)
        world.debuffs.player = { 31 }
        clock.now = 101
        TAD.OnUnitAura("player")
        assert.is_not_nil(TAD.FindRecentAdd(100.9, 101.1))
        assert.is_nil(TAD.FindRecentAdd(101.05, 101.2))  -- add sits before the window
        clock.now = 103
        assert.is_nil(TAD.FindRecentAdd(100.9, 103))     -- trimmed: older than 1s
        assert.equals(0, #TAD.recentAdds)
    end)

    it("non-tracked units and disabled state are ignored", function()
        TAD.SetEnabled(true)
        world.debuffs.nameplate1 = { 41 }
        TAD.OnUnitAura("nameplate1")                   -- plates never enter the ring
        assert.equals(0, #TAD.recentAdds)
        TAD.SetEnabled(false)
        world.debuffs.player = { 42 }
        TAD.OnUnitAura("player")
        assert.equals(0, #TAD.recentAdds)
        assert.is_nil(TAD.FindRecentAdd(0, 200))
    end)

    it("a roster change wipes and reseeds the baselines", function()
        TAD.SetEnabled(true)
        world.debuffs.party1 = { 51 }
        clock.now = 101
        TAD.OnUnitAura("party1")
        assert.equals(1, #TAD.recentAdds)
        TAD.OnRosterChanged()                          -- token re-key: everything stale
        assert.equals(0, #TAD.recentAdds)
        assert.is_true(TAD.seeded)
        clock.now = 101.2
        TAD.OnUnitAura("party1")                       -- 51 is baseline now, not new
        assert.equals(0, #TAD.recentAdds)
    end)
end)
