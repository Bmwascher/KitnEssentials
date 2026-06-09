-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer.lua                                     ║
-- ║  Module: Mythic+ Timer                                   ║
-- ║  Purpose: Self-contained keystone timer HUD (WarpDeplete ║
-- ║           look, EllesmereUI event/tick architecture).    ║
-- ║           Bootstrap, DB defaults, run lifecycle/state,   ║
-- ║           event wiring, tick driver, deaths.             ║
-- ║  Backend split: _HUD (render), _Splits (PB), _Overlay   ║
-- ║           (folded ex-WarpDepleteForces nameplate/tip).  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local MPT = KitnEssentials:NewModule("MythicPlusTimer", "AceEvent-3.0", "AceHook-3.0")

-- Shared run state (the currentRun table; reset by MPT:ResetRun).
MPT.run = MPT.run or {}

-- Frame handles (created once in MPT:BuildHUD, lives in _HUD file).
MPT.frames = MPT.frames or {}
