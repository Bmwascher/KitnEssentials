-- ╔══════════════════════════════════════════════════════════╗
-- ║  EditModeGuides.lua                                      ║
-- ║  Purpose: Edit mode's coarse grid and centre guides —    ║
-- ║           drawing, teardown, and invalidation.           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local EditMode = KE.EditMode

local CreateFrame = CreateFrame
local UIParent = UIParent
local math_floor = math.floor

local GRID_ALPHA = 0.12

-- Textures are reused across rebuilds. Frames are never destroyed in this
-- runtime, so a rebuild that created fresh ones would leak the old set for the
-- session.
local gridPool = {}
local gridUsed = 0

local function AcquireLine(parent)
    gridUsed = gridUsed + 1
    local tex = gridPool[gridUsed]
    if not tex then
        tex = parent:CreateTexture(nil, "BACKGROUND")
        gridPool[gridUsed] = tex
    end
    tex:Show()
    return tex
end

local function ReleaseUnused()
    for i = gridUsed + 1, #gridPool do
        gridPool[i]:Hide()
    end
end

function EditMode:BuildGuideFrame()
    if self.guideFrame then return self.guideFrame end

    local frame = CreateFrame("Frame", "KE_EditModeGuides", UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("BACKGROUND")
    frame:Hide()
    self.guideFrame = frame

    return frame
end

function EditMode:RefreshGrid()
    local frame = self:BuildGuideFrame()

    gridUsed = 0

    if not self:GetGuideSetting("ShowGrid") then
        ReleaseUnused()
        return
    end

    -- Take the spacing and the origin from the same builder the drag uses.
    -- Re-deriving them here would create an invariant nothing checks: if the
    -- two expressions ever drifted, the grid would draw lines the snap does not
    -- target and every smoke step would still pass.
    local context = self:BuildSnapContext()
    local spacing = context.spacing
    if spacing <= 0 then
        ReleaseUnused()
        return
    end

    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not width or not height or width <= 0 or height <= 0 then
        ReleaseUnused()
        return
    end

    local originX, originY = context.originX, context.originY
    local thickness = KE:GetPixelSize()
    local colour = KE.Theme and KE.Theme.accent or { 1, 1, 1 }

    local steps = math_floor(originX / spacing)
    for i = -steps, steps do
        local x = originX + i * spacing
        if x >= 0 and x <= width then
            local tex = AcquireLine(frame)
            tex:ClearAllPoints()
            tex:SetColorTexture(colour[1], colour[2], colour[3], GRID_ALPHA)
            tex:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", x, height)
            tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", x + thickness, 0)
        end
    end

    steps = math_floor(originY / spacing)
    for i = -steps, steps do
        local y = originY + i * spacing
        if y >= 0 and y <= height then
            local tex = AcquireLine(frame)
            tex:ClearAllPoints()
            tex:SetColorTexture(colour[1], colour[2], colour[3], GRID_ALPHA)
            tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, y)
            tex:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, y + thickness)
        end
    end

    ReleaseUnused()
end

function EditMode:ShowGuideFrame()
    local frame = self:BuildGuideFrame()
    self:RefreshGrid()
    frame:Show()
end

function EditMode:HideGuideFrame()
    if self.guideFrame then self.guideFrame:Hide() end
end
