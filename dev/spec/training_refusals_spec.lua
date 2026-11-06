-- Tier 1: What's Training's click guards. These cases read only whether a write
-- was asked for; what the client does with it is a smoke matter.
local helpers = require("dev.spec._helpers")

local printed, combat

local function newKE()
    printed = {}
    combat = false
    _G.InCombatLockdown = function() return combat end
    _G.C_Timer = { After = function() end }
    _G.Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 } }
    _G.issecretvalue = function() return false end
    _G.wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
    local KE = helpers.loadModule("Modules/QoL/WhatsTraining/TrainingRules.lua")
    KE.Print = function(_, message) printed[#printed + 1] = message end
    local store = { prices = {}, skipped = {}, kept = {} }
    KE.Training = {
        active = true, db = { RankSwap = true },
        Store = function() return store end,
        Panel = { QueueDraw = function() end },
    }
    return KE
end

local function swapFixture()
    local KE = newKE()
    local writes, actions = {}, { [1] = { "spell", 1 }, [2] = { "macro", 9 } }
    local ranks = { [1] = "Rank 1", [3] = "Rank 3" }
    _G.C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 1 } end,
        GetSpellBookItemInfo = function()
            return { itemType = 1, isPassive = false, name = "Rend", subName = "Rank 3", spellID = 3 }
        end,
    }
    _G.C_Spell = {
        GetSpellName = function() return "Rend" end,
        GetSpellSubtext = function(id) return ranks[id] end,
        PickupSpell = function() end,
    }
    _G.ClearCursor = function() end
    _G.GetActionInfo = function(slot)
        local action = actions[slot]
        if action then return action[1], action[2] end
    end
    _G.PlaceAction = function(slot) writes[#writes + 1] = slot end
    helpers.loadModule("Modules/QoL/WhatsTraining/TrainingRankSwap.lua", KE)
    return KE.Training.Swap, writes, actions
end

describe("What's Training Update Bars", function()
    it("writes only out of combat, and only to a slot that still holds the lower rank", function()
        for _, row in ipairs({
            { name = "out of combat", want = { 1 } },
            { name = "in combat", combat = true, want = {}, says = "combat" },
            { name = "the slot now holds a macro", moved = true, want = {} },
        }) do
            local Swap, writes, actions = swapFixture()
            Swap.Scan()
            combat = row.combat == true
            if row.moved then actions[1] = { "macro", 9 } end
            Swap.Update()
            assert.same(row.want, writes, row.name)
            if row.says then assert.truthy(printed[1]:find(row.says, 1, true), row.name) end
        end
    end)
end)
