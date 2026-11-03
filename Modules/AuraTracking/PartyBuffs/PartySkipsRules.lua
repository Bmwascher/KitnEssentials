-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartySkipsRules.lua                                     ║
-- ║  Purpose: pure rules for the skip bars.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs = ipairs

local Rules = {}
KE.PartySkipsRules = Rules

Rules.TOKENS = { "party1", "party2", "party3", "party4" }

-- The unit whose Shroud the bar reads: you on a rogue, else the first rogue in
-- party order, else nobody. classes holds the class file name for each of
-- Rules.TOKENS, false where the class is unknown or hidden.
function Rules.RogueToken(playerClass, classes)
    if playerClass == "ROGUE" then return "player" end
    for i, token in ipairs(Rules.TOKENS) do
        if classes[i] == "ROGUE" then return token end
    end
    return nil
end
