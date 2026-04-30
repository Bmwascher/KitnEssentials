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
