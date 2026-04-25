-- ╔══════════════════════════════════════════════════════════╗
-- ║  PixelPerfect.lua                                        ║
-- ║  Purpose: Pixel-perfect UI scaling helper based on       ║
-- ║           physical screen dimensions.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local math_floor = math.floor

---------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------

function KE:GetPixelScale()
    local _, physicalHeight = GetPhysicalScreenSize()
    if physicalHeight then
        return 768 / physicalHeight
    end
    return 1
end

function KE:PixelRound(value)
    local scale = self:GetPixelScale()
    if scale == 0 then return value end
    return math_floor(value / scale + 0.5) * scale
end

-- Clamped 0.4-1.15
function KE:PixelBestSize()
    local scale = self:GetPixelScale()
    if scale < 0.4 then return 0.4 end
    if scale > 1.15 then return 1.15 end
    return scale
end

-- Snaps `frame` to integer screen pixels using its actual effective scale —
-- works regardless of UIParent's uiScale or the parent chain. Reads the
-- frame's current screen position (GetLeft/GetBottom return addon-coord
-- positions after all parent transforms), rounds to the nearest integer
-- screen pixel via the frame's effective scale, and applies the delta to
-- the anchor offset.
--
-- Why not snap the offset values directly (KE's previous approach)?
-- Rounding XOffset/YOffset only works if the frame's effective scale
-- happens to equal `768 / physicalHeight`. When it doesn't (most users
-- with non-default uiScale), the offset-rounding lands on the wrong grid
-- and actually introduces sub-pixel rendering. Adapted from NorskenUI.
function KE:SnapFrameToPixels(frame)
    if not frame then return end

    local scale = frame:GetEffectiveScale()
    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    if not (scale and left and bottom) then return end

    local snappedLeft = math_floor(left * scale + 0.5) / scale
    local snappedBottom = math_floor(bottom * scale + 0.5) / scale

    local offsetX = snappedLeft - left
    local offsetY = snappedBottom - bottom

    if offsetX == 0 and offsetY == 0 then return end

    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end

    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, (x or 0) + offsetX, (y or 0) + offsetY)
end
