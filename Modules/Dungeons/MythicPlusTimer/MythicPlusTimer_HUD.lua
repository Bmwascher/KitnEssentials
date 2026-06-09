-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer_HUD.lua                                 ║
-- ║  Module: Mythic+ Timer — HUD renderer                    ║
-- ║  Purpose: Build/render/layout the visual HUD. Pure       ║
-- ║           function of MPT.run; no API reads here.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local MPT = KitnEssentials:GetModule("MythicPlusTimer")
