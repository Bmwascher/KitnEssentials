-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrainingLearn.lua                                       ║
-- ║  Purpose: What the open trainer window offers, what is   ║
-- ║           ticked, and the buy on a click.                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local T = KE.Training or {}
KE.Training = T

local Rules = KE.TrainingRules

local BuyTrainerService = BuyTrainerService
local C_PetInfo, C_Trainer = C_PetInfo, C_Trainer
local Enum = Enum
local GetMoney, GetProfessions = GetMoney, GetProfessions
local GetTrainerServiceCost, GetTrainerServiceInfo = GetTrainerServiceCost, GetTrainerServiceInfo
local InCombatLockdown = InCombatLockdown
local ipairs, wipe = ipairs, wipe

local Learn = {}
T.Learn = Learn

local NONE = {}

local open, waiting = NONE, NONE
local ticks = {}
local planned, plannedCost = NONE, 0
local quoted = NONE
local inPlan = {}

local function FreeSlots()
    if not GetProfessions then return 2 end
    local first, second = GetProfessions()
    return 2 - (first and 1 or 0) - (second and 1 or 0)
end

local function IsPetTrainer()
    if not (C_Trainer and C_Trainer.GetTrainerType and Enum.TrainerType) then return false end
    ---@diagnostic disable-next-line: wrong-flavor-api
    return C_Trainer.GetTrainerType() == Enum.TrainerType.Pet
end

local function Budget()
    if IsPetTrainer() then
        if not (C_PetInfo and C_PetInfo.GetPetTrainingPoints) then return 0 end
        ---@diagnostic disable-next-line: wrong-flavor-api
        local total, used = C_PetInfo.GetPetTrainingPoints()
        return (total or 0) - (used or 0)
    end
    return GetMoney()
end

local function Recompute()
    planned, plannedCost = Rules.BuyPlan(open, ticks, Budget(), FreeSlots())
    wipe(inPlan)
    for _, offer in ipairs(planned) do inPlan[offer.key] = true end
end

function Learn.Reset()
    wipe(ticks)
    wipe(inPlan)
    open, waiting = NONE, NONE
    planned, plannedCost, quoted = NONE, 0, NONE
end

function Learn.Refresh(services, byKey)
    local known = T.classData and Rules.KnownMap(T.classData.spells, T.IsKnown) or NONE
    open, waiting = Rules.Offers(services, { byKey = byKey, known = known, level = T.level })
    local skipped, free = T.Store().skipped, FreeSlots()
    for _, offer in ipairs(open) do
        if ticks[offer.key] == nil then ticks[offer.key] = Rules.DefaultTick(offer, skipped) end
        if not Rules.CanTick(offer, free) then ticks[offer.key] = false end
    end
    Recompute()
end

function Learn.Offers()
    return open, waiting
end

function Learn.IsTicked(offer)
    return ticks[offer.key] == true
end

function Learn.CanTick(offer)
    return Rules.CanTick(offer, FreeSlots())
end

function Learn.InPlan(offer)
    return inPlan[offer.key] == true
end

function Learn.Toggle(offer)
    if not Learn.CanTick(offer) then return end
    ticks[offer.key] = not ticks[offer.key]
    Recompute()
end

function Learn.SetAll(on)
    Rules.TickAll(open, on, T.Store().skipped, FreeSlots(), ticks)
    Recompute()
end

function Learn.AnyTicked()
    for _, offer in ipairs(open) do
        if ticks[offer.key] then return true end
    end
    return false
end

function Learn.CostText(cost)
    if not cost then return "Price unknown" end
    if IsPetTrainer() then return cost .. " training points" end
    return T.Coins(cost)
end

local function CostOf(offer)
    if not offer.cost then return 0, "none" end
    return offer.cost, "read"
end

-- The text beside the Learn button, and the button's own label and state. The
-- rows behind this label are the most a click may buy, until the next draw.
function Learn.Footer()
    local ticked = {}
    for _, offer in ipairs(open) do
        if ticks[offer.key] then ticked[#ticked + 1] = offer end
    end
    local picked, _, unknown = Rules.Sum(ticked, CostOf)
    local left = Budget() - picked
    local mark = unknown > 0 and "~" or ""
    local leaves = left >= 0 and ("Leaves " .. mark .. Learn.CostText(left)) or (mark .. Learn.CostText(-left) .. " short")
    local count = #planned
    local label, canBuy = Rules.LearnLabel(count, Learn.CostText(plannedCost), #ticked, unknown, IsPetTrainer())
    local pickedText = "Picked " .. Learn.CostText(picked)
    if unknown > 0 then pickedText = pickedText .. " + " .. unknown .. " unpriced" end
    quoted = planned
    return pickedText, leaves, label, canBuy
end

function Learn.Buy()
    -- The game refuses an addon's purchase at a Beast Training window; only its own Train button buys there.
    if IsPetTrainer() then return end
    if InCombatLockdown() then
        KE:Print("Learn does nothing in combat. Buy after the fight.")
        return
    end
    -- Planning over the quoted rows can only drop one: money that rose since the
    -- draw buys nothing the button did not state.
    local stillCovered = Rules.BuyPlan(quoted, ticks, Budget(), FreeSlots())
    for _, offer in ipairs(Rules.BuyOrder(stillCovered)) do
        local name, kind, _, level = Rules.ReadService(GetTrainerServiceInfo(offer.index))
        local cost = GetTrainerServiceCost(offer.index)
        if Rules.OfferStands(offer, name, kind, level, cost) then
            BuyTrainerService(offer.index)
        end
    end
end
