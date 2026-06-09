-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer_Splits.lua                              ║
-- ║  Module: Mythic+ Timer — splits / personal bests        ║
-- ║  Purpose: PB storage, fallback resolver, countdown PB    ║
-- ║           preview. Reads DB + completion data only.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local MPT = KitnEssentials:GetModule("MythicPlusTimer")
