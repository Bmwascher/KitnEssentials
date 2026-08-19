-- ╔══════════════════════════════════════════════════════════╗
-- ║  EUIUnlockBridge.lua                                     ║
-- ║  Core: EllesmereUI unlock-mode bridge                    ║
-- ║  Purpose: publish KE movers as EUI unlock elements so     ║
-- ║           EUI elements can anchor to them.                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local Bridge = {}
KE.EUIUnlock = Bridge

-- KE stores every element position as AnchorFrom / AnchorTo / XOffset /
-- YOffset; EllesmereUI hands movers the same four values under different
-- names. Both directions default identically so a half-written profile cannot
-- park a frame at nil.
function Bridge.ToEUIPosition(pos)
    if type(pos) ~= "table" then return nil end
    return {
        point    = pos.AnchorFrom or "CENTER",
        relPoint = pos.AnchorTo or "CENTER",
        x        = pos.XOffset or 0,
        y        = pos.YOffset or 0,
    }
end

function Bridge.FromEUIPosition(point, relPoint, x, y)
    return {
        AnchorFrom = point or "CENTER",
        AnchorTo   = relPoint or "CENTER",
        XOffset    = x or 0,
        YOffset    = y or 0,
    }
end
