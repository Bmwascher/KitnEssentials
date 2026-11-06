-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrainingRead.lua                                        ║
-- ║  Purpose: What's Training's per-character store, and the ║
-- ║           read of an open trainer window.                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local T = KE.Training or {}
KE.Training = T

local Rules = KE.TrainingRules

local C_Spell, C_SpellBook, C_Timer = C_Spell, C_SpellBook, C_Timer
local Enum = Enum
local GetNumTrainerServices, GetTrainerServiceCost = GetNumTrainerServices, GetTrainerServiceCost
local GetTrainerServiceInfo = GetTrainerServiceInfo
local IsTradeskillTrainer = IsTradeskillTrainer
local pairs, type = pairs, type

local Read = {}
T.Read = Read

local queued = false

function T.Store()
    local root = KE:GetCharStore(true)
    local store = root.WhatsTraining
    if type(store) ~= "table" then
        store = {}
        root.WhatsTraining = store
    end
    store.prices = store.prices or {}
    store.skipped = store.skipped or {}
    store.kept = store.kept or {}
    return store
end

local function InBook(id)
    return C_SpellBook.IsSpellKnown(id, Enum.SpellBookSpellBank.Player) == true
end

-- Every known test of the plan, Learn's offers and the waiting words goes through
-- here, so a rank another learned spell replaced reads as known in all of them.
function T.IsKnown(id)
    return Rules.Known(id, InBook, T.classData and T.classData.replaced)
end

function T.NameOf(id)
    return C_Spell.GetSpellName(id)
end

function Read.Services()
    local services = {}
    if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceCost) then return services end
    for index = 1, GetNumTrainerServices() or 0 do
        local name, kind, icon, level = Rules.ReadService(GetTrainerServiceInfo(index))
        if name then
            local cost, isProfession = GetTrainerServiceCost(index)
            services[#services + 1] = {
                index = index, name = name, kind = kind, icon = icon, level = level or 0,
                cost = type(cost) == "number" and cost or nil, isProfession = isProfession == true,
            }
        end
    end
    return services
end

function Read.Run()
    if not T.atTrainer then return end
    local services = Read.Services()
    local byKey = T.classData and Rules.SpellsByKey(T.classData.spells, T.NameOf)
    T.atProfession = IsTradeskillTrainer ~= nil and IsTradeskillTrainer() == true
    if byKey and not T.atProfession and Rules.ReadPrices(services, byKey, T.Store().prices) then
        T.module:RebuildPlan()
    end
    T.Learn.Refresh(services, byKey)
    T.Panel.QueueDraw()
end

function Read.Queue()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        Read.Run()
    end)
end

function Read.Count()
    local count = 0
    for _ in pairs(T.Store().prices) do count = count + 1 end
    return count
end

function Read.Forget()
    T.Store().prices = {}
    T.module:RebuildPlan()
    T.Panel.QueueDraw()
end
