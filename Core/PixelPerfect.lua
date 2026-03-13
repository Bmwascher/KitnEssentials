-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)

local math_floor = math.floor

-- Get pixel-perfect scale
function KE:GetPixelScale()
    local physicalWidth, physicalHeight = GetPhysicalScreenSize()
    if physicalHeight then
        return 768 / physicalHeight
    end
    return 1
end

-- Round to nearest pixel
function KE:PixelRound(value)
    local scale = self:GetPixelScale()
    if scale == 0 then return value end
    return math_floor(value / scale + 0.5) * scale
end

-- Get best pixel size (clamped 0.4-1.15)
function KE:PixelBestSize()
    local scale = self:GetPixelScale()
    if scale < 0.4 then return 0.4 end
    if scale > 1.15 then return 1.15 end
    return scale
end

-- Snap a frame to pixel grid
function KE:SnapFrameToPixels(frame)
    if not frame then return end
    local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
    if not point then return end
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, self:PixelRound(xOfs or 0), self:PixelRound(yOfs or 0))
end
