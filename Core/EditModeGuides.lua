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
local pairs = pairs

-- The grid is a reference the eye reads past; the centre guides are an answer
-- it reads. The gap between these two is what keeps that true, so raising the
-- grid means checking the guides still dominate rather than just raising it.
local GRID_ALPHA = 0.35
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
    local height = UIParent:GetHeight() or 0
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
    horizontal:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, context.originY + thickness)
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

---------------------------------------------------------------------------------
-- Element Snap Guides
---------------------------------------------------------------------------------
-- The centre guides mark two fixed coordinates the user already knows. These
-- mark wherever a neighbour was matched, so unlike those they are re-pointed as
-- the drag moves. Same colour and alpha, because they mean the same thing: a
-- snap that has already been decided. The line's position says which is which.
--
-- Two persistent textures, never the grid pool. RefreshGrid resets that pool by
-- count and hides everything past the mark, so a borrowed line would vanish the
-- moment anything redrew the grid mid-drag.
local function SnapLine(frame, key)
    local tex = frame[key]
    if tex then return tex end

    tex = frame:CreateTexture(nil, "ARTWORK")
    tex:Hide()
    frame[key] = tex

    return tex
end

-- nil hides that axis. Dirty-checked on both visibility and coordinate: this
-- runs on every frame of a drag, and re-pointing an unchanged texture sixty
-- times a second is the kind of cost the perf patterns exist to refuse.
function EditMode:SetElementSnapGuides(x, y)
    local frame = self:BuildGuideFrame()
    local thickness = KE:GetPixelSize()
    local colour = KE.Theme and KE.Theme.accent or { 1, 1, 1 }

    local vertical = SnapLine(frame, "snapLineX")
    if x then
        if frame._snapAtX ~= x then
            frame._snapAtX = x
            local height = UIParent:GetHeight() or 0
            vertical:SetColorTexture(colour[1], colour[2], colour[3], CENTRE_GUIDE_ALPHA)
            vertical:ClearAllPoints()
            vertical:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", x, height)
            vertical:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", x + thickness, 0)
        end
        vertical:Show()
    else
        frame._snapAtX = nil
        vertical:Hide()
    end

    local horizontal = SnapLine(frame, "snapLineY")
    if y then
        if frame._snapAtY ~= y then
            frame._snapAtY = y
            horizontal:SetColorTexture(colour[1], colour[2], colour[3], CENTRE_GUIDE_ALPHA)
            horizontal:ClearAllPoints()
            horizontal:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, y)
            horizontal:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, y + thickness)
        end
        horizontal:Show()
    else
        frame._snapAtY = nil
        horizontal:Hide()
    end
end

-- The termination and suspension path. Clears the remembered coordinates too,
-- or the next drag's first frame would skip its own re-point as unchanged and
-- show a line where the last drag left one.
function EditMode:HideElementSnapGuides()
    local frame = self.guideFrame
    if not frame then return end
    frame._snapAtX, frame._snapAtY = nil, nil
    if frame.snapLineX then frame.snapLineX:Hide() end
    if frame.snapLineY then frame.snapLineY:Hide() end
end

-- The grid, the guides and the drag are all built from the screen's dimensions
-- and the pixel size, so one pair of events invalidates all three. This is the
-- same pair PixelPerfect watches for its own cache.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
watcher:SetScript("OnEvent", function()
    -- Refresh the pixel cache FIRST. Everything below reads the pixel size, and
    -- the cancelled drag's restore re-applies a position through the framework
    -- snap. Doing this after would leave those on the previous lattice and make
    -- correctness depend on which handler ran first.
    KE:UpdatePixelCache()

    -- A drag started in the old coordinate space. Its start cursor, its start
    -- centre and its grid origin were all captured there, so continuing would
    -- land the frame somewhere nobody asked for. Cancelling restores the saved
    -- position and costs one re-drag.
    for _, overlay in pairs(EditMode.overlayFrames) do
        if overlay.isDragging then
            EditMode:CancelDrag(overlay)
        end
    end

    -- Not gated on the tool being open. The screen can change size while it is
    -- closed, and a guide left on the old coordinate would then be wrong on the
    -- very next drag. This does build the (hidden) guide frame on the first such
    -- event even if the tool has never been opened, which is deliberate -- a
    -- gated version would miss exactly the case this exists for.
    EditMode:BuildGuideFrame()
    EditMode:RepositionCentreGuides()
    EditMode:RefreshGrid()
end)
