-- ╔══════════════════════════════════════════════════════════╗
-- ║  Curves.lua                                              ║
-- ║  Purpose: Animation curve utilities for timing-based     ║
-- ║           UI logic (duration decimal formatting).        ║
-- ║  Credit: p3lim.                                          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
KE.curves = {} --[[@as KE.Curves]]

---------------------------------------------------------------------------------
-- Curve Definitions
---------------------------------------------------------------------------------

-- Shows 1 decimal when < 3s, otherwise 0. Offset by 0.2 to prevent flash.
KE.curves.DurationDecimals = C_CurveUtil.CreateCurve()
KE.curves.DurationDecimals:SetType(Enum.LuaCurveType.Step)
KE.curves.DurationDecimals:AddPoint(0.09, 0)
KE.curves.DurationDecimals:AddPoint(0.1, 1)
KE.curves.DurationDecimals:AddPoint(2.8, 1)
KE.curves.DurationDecimals:AddPoint(2.9, 0)

-- Alpha based on health percent (1 when missing, 0 at full).
-- Used by Recuperate button -- handles secret/tainted values safely.
KE.curves.HealthMissingAlpha = C_CurveUtil.CreateCurve()
KE.curves.HealthMissingAlpha:SetType(Enum.LuaCurveType.Step)
KE.curves.HealthMissingAlpha:AddPoint(0, 1)
KE.curves.HealthMissingAlpha:AddPoint(0.999, 1)
KE.curves.HealthMissingAlpha:AddPoint(1, 0)

-- Hides absurdly long NPC casts/channels (e.g. multi-day flavor channels
-- like Extract Essence): alpha 1 while remaining <= 60s, 0 above. Evaluated
-- via LuaDurationObject:EvaluateRemainingDuration so the secret duration
-- never enters Lua; the evaluated result is itself SECRET when the duration
-- is secret (in-game confirmed 2026-07-03) — feed it only to alpha /
-- statusbar-value sinks or truth tests, never Lua arithmetic. Consumers:
-- TargetedSpells, DungeonCasts, CastbarHelpers.
KE.curves.IsLongCast = C_CurveUtil.CreateCurve()
KE.curves.IsLongCast:SetType(Enum.LuaCurveType.Linear)
KE.curves.IsLongCast:AddPoint(0, 1)
KE.curves.IsLongCast:AddPoint(60, 1)
KE.curves.IsLongCast:AddPoint(60.001, 0)
