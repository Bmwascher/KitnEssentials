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
local CENTRE_GUIDE_ALPHA = 0.85

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
    self:RepositionCentreGuides()
    frame:Show()
end

function EditMode:HideGuideFrame()
    if self.guideFrame then self.guideFrame:Hide() end
end

-- The guide reports a snap that has already been decided. It never predicts
-- one: a second prediction is a second chance to disagree with the commit.
local function CentreLine(frame, key)
    local tex = frame[key]
    if tex then return tex end

    tex = frame:CreateTexture(nil, "ARTWORK")
    tex:Hide()
    frame[key] = tex

    return tex
end

-- Positioning is separate from creation because the coordinates these lines
-- sit on can change while the tool is closed. Textures belong to their frame
-- for the session, so a stale one is re-pointed, never dropped and remade.
function EditMode:RepositionCentreGuides()
    local frame = self.guideFrame
    if not frame then return end

    local context = self:BuildSnapContext()
    local thickness = KE:GetPixelSize()
    local width, height = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    -- Colour is set here rather than at creation so a theme change is picked up
    -- the next time the tool opens, the same way the grid's is.
    local colour = KE.Theme and KE.Theme.accent or { 1, 1, 1 }

    local vertical = CentreLine(frame, "centreLineX")
    vertical:SetColorTexture(colour[1], colour[2], colour[3], CENTRE_GUIDE_ALPHA)
    vertical:ClearAllPoints()
    vertical:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", context.originX, height)
    vertical:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", context.originX + thickness, 0)

    local horizontal = CentreLine(frame, "centreLineY")
    horizontal:SetColorTexture(colour[1], colour[2], colour[3], CENTRE_GUIDE_ALPHA)
    horizontal:ClearAllPoints()
    horizontal:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, context.originY)
    horizontal:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", width, context.originY + thickness)
end

function EditMode:SetCentreGuides(onX, onY)
    local frame = self:BuildGuideFrame()
    -- The vertical line marks a snap on the X axis, and vice versa.
    CentreLine(frame, "centreLineX"):SetShown(onX and true or false)
    CentreLine(frame, "centreLineY"):SetShown(onY and true or false)
end

function EditMode:HideCentreGuides()
    local frame = self.guideFrame
    if not frame then return end
    if frame.centreLineX then frame.centreLineX:Hide() end
    if frame.centreLineY then frame.centreLineY:Hide() end
end
