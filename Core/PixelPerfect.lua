-- ╔══════════════════════════════════════════════════════════╗
-- ║  PixelPerfect.lua                                        ║
-- ║  Purpose: Pixel-perfect UI scaling helpers based on      ║
-- ║           physical screen dimensions and UIParent's      ║
-- ║           live effective scale.                          ║
-- ║                                                          ║
-- ║  Two formulas, two purposes:                             ║
-- ║    GetPixelScale() = 768 / physH         (ideal scale)   ║
-- ║      Used to clamp scrollbar steps and similar — what    ║
-- ║      uiScale *would* be on a perfectly-pixel-aligned UI. ║
-- ║                                                          ║
-- ║    GetPixelSize()  = 768 / (physH * effScale)            ║
-- ║      Live size of 1 screen pixel in addon coords. Use    ║
-- ║      this to snap sizes/borders/offsets so they land on  ║
-- ║      the actual screen pixel grid.                       ║
-- ║                                                          ║
-- ║  Helpers are opt-in. Module authors call them where      ║
-- ║  pixel snapping is desired — the framework path          ║
-- ║  (ApplyFramePosition) does NOT auto-snap.                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local math_floor = math.floor
local math_ceil = math.ceil

---------------------------------------------------------------------------------
-- Cached state
---------------------------------------------------------------------------------

local cachedPhysH = 0
local cachedEffScale = 1
local cachedPixelSize = 1

local function recompute()
    local _, physH = GetPhysicalScreenSize()
    local effScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if not physH or physH <= 0 then return end
    if not effScale or effScale <= 0 then return end
    if physH == cachedPhysH and effScale == cachedEffScale then return end
    cachedPhysH = physH
    cachedEffScale = effScale
    cachedPixelSize = 768 / (physH * effScale)
end

function KE:UpdatePixelCache()
    recompute()
end

---------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------

-- Ideal UI scale (768 / physH). Used for scrollbar step clamping.
function KE:GetPixelScale()
    local _, physH = GetPhysicalScreenSize()
    if physH and physH > 0 then
        return 768 / physH
    end
    return 1
end

-- Live size of 1 screen pixel in addon coords (768 / (physH * effScale)).
-- Use this when snapping sizes/offsets/borders so they land on the actual
-- screen pixel grid regardless of UIParent's uiScale.
function KE:GetPixelSize()
    if cachedPhysH == 0 then recompute() end
    return cachedPixelSize
end

-- Symmetric rounding around zero. Snaps `value` to the nearest pixel
-- multiple in addon coords.
function KE:PixelSnap(value)
    if not value or value == 0 then return 0 end
    if cachedPhysH == 0 then recompute() end
    local px = value / cachedPixelSize
    if px >= 0 then
        return math_floor(px + 0.5) * cachedPixelSize
    end
    return math_ceil(px - 0.5) * cachedPixelSize
end

-- Snaps to the nearest even pixel multiple (use for borders that need
-- balanced widths around a center line).
function KE:PixelSnapEven(value)
    if not value or value == 0 then return 0 end
    if cachedPhysH == 0 then recompute() end
    local px = value / cachedPixelSize
    if px >= 0 then
        px = math_floor(px + 0.5)
    else
        px = math_ceil(px - 0.5)
    end
    if px % 2 ~= 0 then px = px + 1 end
    return px * cachedPixelSize
end

-- Floors to a half-pixel boundary (use for centered insets).
function KE:PixelHalfFloor(value)
    if not value or value == 0 then return 0 end
    if cachedPhysH == 0 then recompute() end
    local px = math_floor(value / cachedPixelSize + 0.5)
    return math_floor(px / 2) * cachedPixelSize
end

-- Backwards-compat alias. Old name; same behavior as PixelSnap.
function KE:PixelRound(value)
    return self:PixelSnap(value)
end

-- Clamped 0.4-1.15 — used as a scrollbar value step. Based on ideal scale,
-- not live pixel size, because the scrollbar consumer wants a stable step
-- not affected by the addon parent's effective scale.
function KE:PixelBestSize()
    local scale = self:GetPixelScale()
    if scale < 0.4 then return 0.4 end
    if scale > 1.15 then return 1.15 end
    return scale
end

-- Disables Blizzard's per-texture pixel-grid snapping for `tex`. Some
-- callers want full control over the texture's exact placement (e.g.
-- 1px borders) and don't want Blizzard's grid snapping kicking in.
function KE:DisableTextureSnap(tex)
    if not tex then return end
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
end

-- Snaps `frame` to the integer screen-pixel grid using its actual
-- effective scale. Reads the frame's resulting screen position, computes
-- the rounding delta, and applies it to the anchor offset.
--
-- This is the screen-position-rounding flavor — different from PixelSnap
-- which rounds an offset value before it's set. Use this when a frame
-- has already been positioned and you want to nudge it onto the pixel
-- grid (e.g. a one-off polish pass after layout).
--
-- NOT auto-called from ApplyFramePosition — user offsets pass through
-- unchanged. See feedback memory for why.
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

---------------------------------------------------------------------------------
-- Cache invalidation
---------------------------------------------------------------------------------

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function() recompute() end)

if UIParent then recompute() end
