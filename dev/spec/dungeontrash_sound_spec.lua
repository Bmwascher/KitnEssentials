-- Tier 2: trash sounds are handed to the Dungeon Timers preset sound helper
-- (TrashOutput.lua playTrashSound). The helper's mute and channel rules are
-- pinned in dungeontimers_compat_spec, so the boss module here is a recorder
-- on the module shim. Only the cast-start cue is driven: the reveal and
-- countdown-end callers use the same function. With no helper on the shim,
-- the cue tests in dungeontrash_cache_spec pin the direct PlaySoundFile fallback.

local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("DungeonTrash — trash sounds follow the Dungeon Timers sound settings", function()
    local DTrash, KE, clock, timers

    local function fireDue()
        local i = 1
        while i <= #timers do
            local t = timers[i]
            if t.at <= clock.now then
                table.remove(timers, i)
                t.fn()
            else
                i = i + 1
            end
        end
    end

    before_each(function()
        clock = { now = 100 }
        timers = {}

        mock.install({
            GetTime = function() return clock.now end,
            C_Timer = {
                After = function(delay, fn)
                    timers[#timers + 1] = { at = clock.now + delay, fn = fn }
                end,
            },
        })
        _G.UnitIsDead = function() return false end
        _G.UnitAffectingCombat = function() return false end
        _G.GetInstanceInfo = function() return "Dungeon", "party", 8, nil, nil, nil, nil, 1 end
        _G.IsInInstance = function() return true, "party" end

        local modules = helpers.installAddonShim()
        KE = { Print = function() end }
        helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/TrashInference.lua", KE)
        helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/DungeonTrash.lua", KE)
        helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/TrashOutput.lua", KE)
        helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/TrashCache.lua", KE)
        DTrash = modules["DungeonTrash"]
        DTrash.monitoring = true

        DTrash.GetSpellDisabled = function() return false end
        DTrash.PlayerSeesTrashSpell = function() return true end
        DTrash.GetSpellDisplay = function() return "bar" end
        DTrash.GetSpellRevealAt = function() return 5 end
        DTrash.GetSpellLabel = function() return "Spell" end
        DTrash.GetSpellEffectiveColor = function() return { 1, 1, 1 } end
        DTrash.GetSpellDecimalThreshold = function() return nil end
        DTrash.GetSpellSoundOnShow = function() return nil end
        DTrash.GetSpellSoundOnHide = function() return nil end
        DTrash.ShowAlert = function() end
        DTrash.HideUnitAlerts = function() end
        DTrash.HideNameplateMarker = function() end

        DTrash.currentMapID = 1
        KE.TrashData = { [1] = { mobs = { [111] = { npcID = 111, name = "Mob",
            spells = { [10] = { first = 5, cd = { 20 }, castTime = 3 } } } } } }
    end)

    after_each(function()
        mock.reset()
        _G.UnitIsDead = nil
        _G.UnitAffectingCombat = nil
        _G.GetInstanceInfo = nil
        _G.IsInInstance = nil
        _G.PlaySoundFile = nil
        _G.KitnEssentials = nil
    end)

    it("the cast-start cue hands its sound to the Dungeon Timers helper and plays nothing itself", function()
        DTrash.db = { Enabled = true }
        KE.LSM = { Fetch = function(_, _, name) return "sound/" .. name end }
        local played, handed = {}, {}
        _G.PlaySoundFile = function(file) played[#played + 1] = file end
        _G.KitnEssentials:GetModule("DungeonTimers").PlayPresetSound = function(name)
            handed[#handed + 1] = name
        end
        DTrash.GetEffectiveSpellSoundOnCastStart = function(_, _, _, spellID)
            return "Ding" .. spellID
        end

        DTrash:OnNameplateAdded(nil, "nameplate1")
        local rt = DTrash.tracked.nameplate1
        rt.matchedNPCID = 111
        rt.anchors = { [10] = { nextStartAt = clock.now } }
        DTrash:OnCastStart(nil, "nameplate1", nil, nil, 4)
        clock.now = clock.now + 0.2
        fireDue()
        assert.same({ "Ding10" }, handed)
        assert.same({}, played)
    end)
end)
