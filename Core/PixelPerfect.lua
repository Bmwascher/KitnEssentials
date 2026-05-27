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
-- ║  `KE:SnapFrameToPixels` is auto-called by                ║
-- ║  `KE:ApplyFramePosition` (in Globals.lua) so every       ║
-- ║  module positioned via the framework path is pixel-      ║
-- ║  snapped automatically. Additional helpers (PixelSnap    ║
-- ║  / PixelSnapEven / PixelHalfFloor) are opt-in for        ║
-- ║  module authors snapping sizes/borders.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local math_floor = math.floor
local math_ceil = math.ceil
local math_abs = math.abs

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
    local snapped
    if px >= 0 then
        snapped = math_floor(px + 0.5) * cachedPixelSize
    else
        snapped = math_ceil(px - 0.5) * cachedPixelSize
    end
    local rounded = math_floor(snapped + 0.5)
    if math_abs(snapped - rounded) < 0.001 then snapped = rounded end
    return snapped
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

-- Snap a CENTER coord so both frame edges land on physical pixel boundaries.
-- Even pixel-width frames snap center to whole pixel; odd-width frames snap
-- center to half-pixel (integer + 0.5). Prevents 1px drift on save/restore
-- of CENTER-anchored odd-width frames.
function KE:PixelSnapCenter(value, dim)
    if value == nil then return value end
    if cachedPhysH == 0 then recompute() end
    local pixelSize = cachedPixelSize
    if dim and dim > 0 then
        local dimPx = math_floor(dim / pixelSize + 0.5)
        if dimPx % 2 == 1 then
            local result = (math_floor(value / pixelSize) + 0.5) * pixelSize
            local rounded = math_floor(result) + 0.5
            if math_abs(result - rounded) < 0.001 then result = rounded end
            return result
        end
    end
    local result = math_floor(value / pixelSize + 0.5) * pixelSize
    local rounded = math_floor(result + 0.5)
    if math_abs(result - rounded) < 0.001 then result = rounded end
    return result
end

-- Pre-snap helpers — wrappers that snap numeric arguments before passing
-- to SetPoint/SetSize. Opt-in. Use when sizing borders, overlay textures,
-- or any layout where pixel-perfection matters.
function KE:PixelPoint(obj, anchor, p1, p2, p3, p4)
    if not p1 then p1 = obj:GetParent() end
    if type(p1) == "number" then p1 = self:PixelSnap(p1) end
    if type(p2) == "number" then p2 = self:PixelSnap(p2) end
    if type(p3) == "number" then p3 = self:PixelSnap(p3) end
    if type(p4) == "number" then p4 = self:PixelSnap(p4) end
    obj:SetPoint(anchor, p1, p2, p3, p4)
end

function KE:PixelSize(frame, w, h)
    frame:SetSize(self:PixelSnap(w), h and self:PixelSnap(h) or self:PixelSnap(w))
end

function KE:PixelWidth(frame, w)
    frame:SetWidth(self:PixelSnap(w))
end

function KE:PixelHeight(frame, h)
    frame:SetHeight(self:PixelSnap(h))
end

function KE:PixelInside(obj, anchor, xOff, yOff)
    anchor = anchor or obj:GetParent()
    local inset = self:PixelSnap(xOff or 1)
    local insetY = self:PixelSnap(yOff or 1)
    obj:ClearAllPoints()
    self:DisablePixelSnap(obj)
    obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -insetY)
    obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, insetY)
end

function KE:PixelOutside(obj, anchor, xOff, yOff)
    anchor = anchor or obj:GetParent()
    local outset = self:PixelSnap(xOff or 1)
    local outsetY = self:PixelSnap(yOff or 1)
    obj:ClearAllPoints()
    self:DisablePixelSnap(obj)
    obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -outset, outsetY)
    obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", outset, -outsetY)
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

-- Back-compat alias for the older method name. The full DisablePixelSnap
-- implementation lives in Core/TextureSnap.lua, which is loaded after
-- this file (see Core.xml). Prefer DisablePixelSnap in new code.
function KE:DisableTextureSnap(tex)
    self:DisablePixelSnap(tex)
end

-- Re-runs the pixel-size calculation on every registered border. Called by
-- the cache-invalidation watcher below when UI_SCALE_CHANGED or
-- DISPLAY_SIZE_CHANGED fires. Borders register themselves in
-- KE._borderRegistry via Core/Widgets.lua's _KE_RegisterBorder helper.
function KE:ResnapAllBorders()
    local registry = KE._borderRegistry
    if not registry then return end
    local px = self:GetPixelSize()
    for frame in pairs(registry) do
        if frame and frame.borders then
            local b = frame.borders
            if b.top and b.top.SetHeight then b.top:SetHeight(px) end
            if b.bottom and b.bottom.SetHeight then b.bottom:SetHeight(px) end
            if b.left and b.left.SetWidth then b.left:SetWidth(px) end
            if b.right and b.right.SetWidth then b.right:SetWidth(px) end
        end
    end
end

-- Snaps `frame` to the integer screen-pixel grid using KE's cached pixel
-- size (correctly accounts for both UIParent's effective scale and the
-- physical screen height). At perfect UI scale (768/physH), this is a
-- no-op for integer-aligned frames and a sub-1-unit nudge for frames
-- whose anchor is at a sub-pixel position (e.g. some ElvUI panels).
--
-- Called by ApplyFramePosition (in Globals.lua) after every position
-- update. Also exposed for explicit per-frame use when the framework
-- path isn't being used.
function KE:SnapFrameToPixels(frame)
    if not frame then return end
    if cachedPhysH == 0 then recompute() end

    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    if not (left and bottom) then return end

    local pixelSize = cachedPixelSize
    local snappedLeft = math_floor(left / pixelSize + 0.5) * pixelSize
    local snappedBottom = math_floor(bottom / pixelSize + 0.5) * pixelSize

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
watcher:SetScript("OnEvent", function()
    recompute()
    KE:ResnapAllBorders()
end)

if UIParent then recompute() end
