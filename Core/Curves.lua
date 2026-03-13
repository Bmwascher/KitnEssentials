-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
KE.curves = {}

-- Credit to p3lim

-- If the duration is < 3 seconds then we want 1 decimal point, otherwise 0
-- Offset by 0.2 because of weird calculation timings making it flash
KE.curves.DurationDecimals = C_CurveUtil.CreateCurve()
KE.curves.DurationDecimals:SetType(Enum.LuaCurveType.Step)
KE.curves.DurationDecimals:AddPoint(0.09, 0)
KE.curves.DurationDecimals:AddPoint(0.1, 1)
KE.curves.DurationDecimals:AddPoint(2.8, 1)
KE.curves.DurationDecimals:AddPoint(2.9, 0)
