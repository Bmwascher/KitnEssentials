-- ╔══════════════════════════════════════════════════════════╗
-- ║  ShieldSwapState.lua                                     ║
-- ║  Module: Dungeon Timers (shield swap state)              ║
-- ║  Purpose: Which boss of a pair carries the shield, by    ║
-- ║           counting the swap messages BigWigs sends.      ║
-- ║           Plain Lua only, no WoW API, no frames.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local Swap = {}

-- One swap can be announced more than once in a burst; a second message
-- inside this window is the same swap.
Swap.THROTTLE = 2

-- cfg is an encounter's shieldSwap entry: { message, start, units = { a, b } }.
function Swap.New(cfg)
    return { cfg = cfg, shielded = cfg.start, last = nil, swappedTo = {} }
end

-- True when the message moves the shield to the other boss.
function Swap.OnMessage(swap, key, now)
    if key ~= swap.cfg.message then return false end
    if swap.last and now - swap.last < Swap.THROTTLE then return false end
    swap.last = now
    local units = swap.cfg.units
    swap.shielded = swap.shielded == units[1] and units[2] or units[1]
    swap.swappedTo[swap.shielded] = true
    return true
end

-- A phase rule with endsOnShield warns of the swap to its own unit, so it
-- ends once a swap has moved the shield there. The pull's starting shield
-- does not count.
function Swap.RuleEnded(rule, swap)
    return rule.endsOnShield == true and swap ~= nil and swap.swappedTo[rule.unit or "boss1"] == true
end

KE._DungeonShieldSwapState = Swap
