-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PositionCardRules.lua                               ║
-- ║  Purpose: the pure rules of the Position Settings card.  ║
-- ║           No WoW API, no frames.                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local Rules = {}
KE.PositionCardRules = Rules

-- Player Frame and Select Frame hang from a frame; every other type resolves
-- to the screen.
local FRAME_TYPES = { SELECTFRAME = true, PLAYERFRAME = true }

-- An Anchored To change between a frame and the screen, where the saved
-- points describe the other kind.
function Rules.CrossesKind(oldType, newType)
    return (FRAME_TYPES[oldType] == true) ~= (FRAME_TYPES[newType] == true)
end
