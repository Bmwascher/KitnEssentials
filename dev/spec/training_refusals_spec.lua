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

describe("What's Training Learn", function()
    it("buys last index first, only out of combat, and never more than the button quoted", function()
        for _, row in ipairs({
            { name = "out of combat", want = { 2, 1 } },
            { name = "in combat", combat = true, want = {}, says = "combat" },
            { name = "a cost that moved", cost = { [2] = 999 }, want = { 1 } },
            { name = "a service that moved", service = { [1] = "Cleave" }, want = { 2 } },
            { name = "money that rose after the quote", money = 100, moneyNow = 300, want = { 1 } },
            { name = "money that fell after the quote", moneyNow = 100, want = { 1 } },
            { name = "no quote shown yet", noQuote = true, want = {} },
        }) do
            local KE = newKE()
            local bought = {}
            local names = { "Rend", "Shout", "No Cost" }
            local costs = { 100, 200 }
            local money = row.money or 1000
            _G.GetMoney = function() return money end
            _G.GetProfessions = function() return nil, nil end
            _G.BuyTrainerService = function(index) bought[#bought + 1] = index end
            _G.GetTrainerServiceInfo = function(index) return names[index], "available", 100001, 4 end
            _G.GetTrainerServiceCost = function(index) return costs[index], false end
            helpers.loadModule("Modules/QoL/WhatsTraining/TrainingLearn.lua", KE)
            local Learn = KE.Training.Learn
            local services = {}
            for index, name in ipairs(names) do
                services[index] = { index = index, name = name, kind = "available", level = 4, cost = costs[index] }
            end
            KE.Training.Coins = tostring
            Learn.Refresh(services)
            if not row.noQuote then Learn.Footer() end
            combat = row.combat == true
            money = row.moneyNow or money
            for index, cost in pairs(row.cost or {}) do costs[index] = cost end
            for index, name in pairs(row.service or {}) do names[index] = name end
            Learn.Buy()
            assert.same(row.want, bought, row.name)
            if row.says then assert.truthy(printed[1]:find(row.says, 1, true), row.name) end
        end
    end)
end)
