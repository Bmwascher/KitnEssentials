-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrainingRankSwap.lua                                    ║
-- ║  Purpose: Finds bar slots holding a lower rank, and      ║
-- ║           swaps them on a click, never in combat.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local T = KE.Training or {}
KE.Training = T

local Rules = KE.TrainingRules

local C_Spell, C_SpellBook, C_Timer = C_Spell, C_SpellBook, C_Timer
local ClearCursor = ClearCursor
local Enum = Enum
local GetActionInfo = GetActionInfo
local InCombatLockdown = InCombatLockdown
local PlaceAction = PlaceAction
local ipairs, issecretvalue = ipairs, issecretvalue
local concat = table.concat

local Swap = {}
T.Swap = Swap

local SLOTS = 180
local AFTER_LEARNING = 2
local NONE = {}

Swap.swaps = NONE

local generation = 0

local function BestRanks()
    local best = {}
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info then
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive then
                    local rank = Rules.RankNumber(item.subName)
                    local current = best[item.name]
                    if rank and (not current or rank > current.rank) then
                        best[item.name] = { id = item.spellID or item.actionID, rank = rank }
                    end
                end
            end
        end
    end
    return best
end

local function BarSlots()
    local slots = {}
    for slot = 1, SLOTS do
        local kind, id = GetActionInfo(slot)
        if not issecretvalue(kind) and not issecretvalue(id) and kind == "spell" and id then
            local name = C_Spell.GetSpellName(id)
            if name then
                slots[#slots + 1] = {
                    slot = slot, kind = kind, name = name,
                    rank = Rules.RankNumber(C_Spell.GetSpellSubtext(id)),
                }
            end
        end
    end
    return slots
end

function Swap.Scan()
    if not T.active or T.gamepad or not T.db.RankSwap then
        Swap.swaps = NONE
    else
        Swap.swaps = Rules.RankSwaps(BestRanks(), BarSlots(), T.Store().kept)
    end
    T.Panel.QueueDraw()
end

function Swap.ScanSoon()
    generation = generation + 1
    local mine = generation
    C_Timer.After(AFTER_LEARNING, function()
        if mine == generation and T.active then Swap.Scan() end
    end)
end

-- The name of each spell a swap would touch, once each, in slot order.
function Swap.Names()
    local names, seen = {}, {}
    for _, swap in ipairs(Swap.swaps) do
        if not seen[swap.name] then
            seen[swap.name] = true
            names[#names + 1] = swap.name
        end
    end
    return names
end

function Swap.Update()
    if InCombatLockdown() then
        KE:Print("Your action bars cannot change in combat. Update Bars after the fight.")
        return
    end
    -- The bars may have changed since the last scan, so this click acts on what they hold now.
    Swap.Scan()
    local count = #Swap.swaps
    if count == 0 then return end
    local names = Swap.Names()
    for _, swap in ipairs(Swap.swaps) do
        ClearCursor()
        C_Spell.PickupSpell(swap.id)
        PlaceAction(swap.slot)
        ClearCursor()
    end
    KE:Print(("Updated %d bar %s: %s."):format(count, count == 1 and "slot" or "slots", concat(names, ", ")))
    Swap.Scan()
end
