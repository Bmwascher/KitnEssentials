-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer_Overlay.lua                             ║
-- ║  Module: Mythic+ Timer — enemy overlay                   ║
-- ║  Purpose: Folded ex-WarpDepleteForces nameplate enemy-%  ║
-- ║           + tooltip count via                            ║
-- ║           C_ScenarioInfo.GetUnitCriteriaProgressValues.  ║
-- ║           Per-unit read is format-passthrough only       ║
-- ║           (truthy check, NO math) — secret-safe.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local MPT = KitnEssentials:GetModule("MythicPlusTimer")
