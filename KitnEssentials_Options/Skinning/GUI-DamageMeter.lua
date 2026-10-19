-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DamageMeter.lua                                     ║
-- ║  GUI: Damage Meter                                       ║
-- ║  Purpose: Configuration panel for the DamageMeter module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local CreateFrame = CreateFrame
local math_max = math.max
local math_floor = math.floor

local PAGE_ID = "DamageMeter"
local TAB_WINDOWS = "DamageMeter_Windows"
local TAB_APPEARANCE = "DamageMeter_Appearance"
local TAB_BEHAVIOR = "DamageMeter_Behavior"
local TAB_SPELLHISTORY = "DamageMeter_SpellHistory"

-- The layout map's height and the gap between its boxes.
local MAP_HEIGHT = 140
local MAP_GAP = 4
-- A split row: the label line, then the slider below it.
local SPLIT_ROW_H = 44

-- Ordered option lists for the per-context default-display rows.
-- Order mirrors the in-world view-selector grid (Selector.lua VIEW_GRID) so the GUI
-- default-type picker offers the same eight types the right-click selector does.
local METER_TYPE_OPTIONS = {
    { key = Enum.DamageMeterType.DamageDone,           text = "Damage Done" },
    { key = Enum.DamageMeterType.HealingDone,          text = "Healing Done" },
    { key = Enum.DamageMeterType.DamageTaken,          text = "Damage Taken" },
    { key = Enum.DamageMeterType.EnemyDamageTaken,     text = "Enemy Damage Taken" },
    { key = Enum.DamageMeterType.AvoidableDamageTaken, text = "Avoidable Damage Taken" },
    { key = Enum.DamageMeterType.Deaths,               text = "Deaths" },
    { key = Enum.DamageMeterType.Interrupts,           text = "Interrupts" },
    { key = Enum.DamageMeterType.Dispels,              text = "Dispels" },
}

local SEGMENT_OPTIONS = {
    { key = Enum.DamageMeterSessionType.Current, text = "Current" },
    { key = Enum.DamageMeterSessionType.Overall, text = "Overall" },
}

local CONTEXT_OPTIONS = {
    { key = "Default",      text = "Default" },
    { key = "Dungeon",      text = "Dungeon" },
    { key = "Mythic+",      text = "Mythic+" },
    { key = "Raid",         text = "Raid" },
    { key = "Arena",        text = "Arena" },
    { key = "Battleground", text = "Battleground" },
    { key = "Scenario",     text = "Scenario" },
}

-- The map boxes and split labels name a window by these texts.
local TYPE_TEXT, SEGMENT_TEXT = {}, {}
for _, option in ipairs(METER_TYPE_OPTIONS) do TYPE_TEXT[option.key] = option.text end
for _, option in ipairs(SEGMENT_OPTIONS) do SEGMENT_TEXT[option.key] = option.text end

local ARRANGEMENT_BUTTONS = {
    { key = "Horizontal", text = "Side by Side",
      tooltip = "Puts each window in its own column, left to right." },
    { key = "Vertical", text = "Stacked",
      tooltip = "Stacks every window in one column, top to bottom." },
    { key = "Custom", text = "Custom",
      tooltip = "Lit when you have arranged the windows yourself. Drag the boxes on the map to make your own layout." },
}

local SPLIT_TOOLTIP = "Moves only the split between these two; the other windows stay put. " ..
    "Same as dragging this gap on the meter."

local function Gold(text)
    return "|cffffd100" .. text .. "|r"
end

local DESCRIPTION = "A damage meter built on the game's own combat data, standing in for the " ..
    "built-in meter while it is on. Switch what it shows and which fight it shows on the meter " ..
    "itself; these settings set the defaults and the look." ..
    "\n\nMove it in " .. Gold("/kes edit") .. " and resize windows by dragging the gaps between " ..
    "them. " .. Gold("/kes dm") .. " shows or hides it, " .. Gold("/kes dm reset") ..
    " clears every segment, " .. Gold("/kes dm report") .. " posts window 1 to chat (out of combat)."

-- Resolves the live module handle (may be nil very early in load).
local function GetDM()
    return KitnEssentials and KitnEssentials:GetModule("DamageMeter", true)
end

-- Applies live config changes through the module's single apply path.
local function ApplySettings()
    local DM = GetDM()
    if DM and DM.ApplySettings then DM:ApplySettings() end
end

-- Applies backdrop-only changes (color/style/border) without a full re-layout.
local function ApplyBackdropOnly()
    local DM = GetDM()
    if DM and DM.UpdateBackdrop then DM:UpdateBackdrop() end
end

-- Schedules a full page rebuild on the next frame, for a change that adds or
-- removes widgets, so the widget whose callback asked is not torn down mid-call.
local function RebuildPage()
    if GUIFrame.RefreshContent then
        C_Timer.After(0, function() GUIFrame:RefreshContent() end)
    end
end

-- Builds an LSM media hash {name = name} for searchable dropdowns, with a safe
-- fallback when LSM is unavailable.
local function MediaList(kind, fallback)
    local out = {}
    if LSM then
        for name in pairs(LSM:HashTable(kind)) do out[name] = name end
    else
        out[fallback] = fallback
    end
    return out
end

local function ApplyModuleState(enabled)
    if not KitnEssentials then return end
    local mod = KitnEssentials:GetModule("DamageMeter", true)
    if not mod then return end
    if mod.db then mod.db.Enabled = enabled end
    if enabled then
        KitnEssentials:EnableModule("DamageMeter")
    else
        KitnEssentials:DisableModule("DamageMeter")
    end
end

local function Unavailable(scrollChild, yOffset)
    local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
    errorCard:AddLabel("Database not available")
    return errorCard:GetNextOffset()
end

---------------------------------------------------------------------------------
-- Number chips: one look for every chip on the page, from DM:GetChipStyle
---------------------------------------------------------------------------------
local function SetChipOutline(text, outline)
    local face, size = text:GetFont()
    if face then text:SetFont(face, size, outline == "NONE" and "" or outline) end
end

local function NewChip(parent, side)
    local chip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    chip:SetSize(side, side)
    chip:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    chip.text = chip:CreateFontString(nil, "OVERLAY")
    chip.text:SetPoint("CENTER")
    return chip
end

-- The font goes on before the text: SetText raises on a FontString with none.
local function PaintChip(chip, n, fontSize)
    local DM = GetDM()
    if not (DM and DM.GetChipStyle) then return end
    local r, g, b, ink, outline = DM:GetChipStyle()
    chip:SetBackdropColor(r, g, b, 1)
    chip:SetBackdropBorderColor(0, 0, 0, 1)
    KE:ApplyThemeFont(chip.text, fontSize)
    SetChipOutline(chip.text, outline)
    chip.text:SetTextColor(ink, ink, ink, 1)
    chip.text:SetText(tostring(n))
end

---------------------------------------------------------------------------------
-- Header: the module switch and the description, above the tab strip
---------------------------------------------------------------------------------
local function BuildHeader(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DamageMeter
    if not db then return Unavailable(scrollChild, yOffset), true end

    local card = GUIFrame:CreateCard(scrollChild, "Damage Meter", yOffset)
    card:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)

    -- Lone header bar: a disabled module shows its switch and nothing else. Any
    -- label would give the card a body, and collapse only hides the tabs.
    local disabled = db.Enabled == false
    if not disabled then card:AddLabel(DESCRIPTION) end

    return card:GetNextOffset(), disabled
end

---------------------------------------------------------------------------------
-- Windows tab helpers
---------------------------------------------------------------------------------

-- Reusable drag "ghost" that follows the cursor while dragging a schematic box,
-- so you can see what you grabbed. A SINGLETON (created once, parented to UIParent
-- at TOOLTIP strata so it floats above the panel and isn't clipped by the scroll
-- frame) -- created per-rebuild it would leak a frame every RefreshContent.
local schematicGhost
local function GetSchematicGhost()
    if schematicGhost then return schematicGhost end
    local g = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    g:SetSize(78, 26)
    g:SetFrameStrata("TOOLTIP")
    g:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    g.text = g:CreateFontString(nil, "OVERLAY")
    g.text:SetPoint("CENTER")
    KE:ApplyThemeFont(g.text, "large")
    -- Self-heal: if the ghost is ever left shown after the mouse button is
    -- released (e.g. a RefreshContent tore down the dragging box before its
    -- OnDragStop could fire), hide it on the next frame. Runs ONLY while the ghost
    -- is shown (a hidden frame's OnUpdate doesn't tick), so no idle cost; the
    -- normal OnDragStop path still hides it explicitly.
    g:SetScript("OnUpdate", function(self)
        if not IsMouseButtonDown("LeftButton") then self:Hide() end
    end)
    g:Hide()
    schematicGhost = g
    return g
end

-- Painted at each drag start, so a theme change since the ghost was made shows.
local function PaintSchematicGhost(ghost)
    local DM = GetDM()
    if not (DM and DM.GetChipStyle) then return end
    local r, g, b, ink, outline = DM:GetChipStyle()
    ghost:SetBackdropColor(r, g, b, 0.9)
    ghost:SetBackdropBorderColor(0, 0, 0, 1)
    SetChipOutline(ghost.text, outline)
    ghost.text:SetTextColor(ink, ink, ink, 1)
end

-- The layout map: one box per window, placed to mirror the in-world dock
-- (columns left to right, stacked rows top to bottom), each showing its number
-- chip, type and segment. It is the only arranging surface: drag a box onto
-- another box's center to stack or reorder (a horizontal line shows the row gap
-- it lands in), or to a column's side or off the map edge to peel it into a new
-- column (a vertical line shows the boundary). A ghost follows the cursor.
local function ConstructSchematic(parent)
    local container = CreateFrame("Frame", nil, parent)
    -- Kept across uses: OnSizeChanged does not fire for a map that comes
    -- back at the width it last reported.
    container._keWidth = 0

    local boxes = {}

    local dropLine = container:CreateTexture(nil, "OVERLAY")
    dropLine:SetHeight(3)
    dropLine:Hide()

    local function ResetBorders()
        local T = Theme
        for i = 1, container._count or 0 do
            boxes[i]:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
        end
    end

    local function ClearDrop()
        container._dropMode = nil
        container._dropAnchor = nil
        container._dropAfter = nil
        container._dropLeftRep = nil
        container._dropRightRep = nil
    end

    -- The first window of column c that is not the one being dragged, or nil
    -- when c is out of range or holds only the dragged window. That column
    -- is dropped on release, so it cannot anchor a new-column insert.
    local function repOf(c, dragWin)
        local cols = container._cols
        if not cols or c < 1 or c > #cols then return nil end
        local wins = cols[c] and cols[c].Windows
        if not wins then return nil end
        for r = 1, #wins do
            if wins[r] ~= dragWin then return wins[r] end
        end
        return nil
    end

    local function showColLine(lineX)
        dropLine:ClearAllPoints()
        dropLine:SetSize(3, container._height or 0)
        dropLine:SetPoint("TOPLEFT", container, "TOPLEFT", lineX - 1.5, 0)
        dropLine:Show()
    end

    -- The container's OnUpdate, attached only while a box is being dragged.
    -- Moves the ghost to the cursor, then resolves one drop from where the
    -- cursor is over the map: the center of a column stacks into it, a
    -- column's side or beyond the map edge makes a new column. The choice is
    -- left on the container for OnDragStop.
    local function DragUpdate()
        local dragWin = container._dragWin
        local cols, boxAt = container._cols, container._boxAt
        if not (dragWin and cols and boxAt) then return end

        local ghost = GetSchematicGhost()
        local us = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (mx / us) + 16, (my / us) - 14)

        ResetBorders()
        ClearDrop()

        -- Boxes share the container's effective scale; one division covers all.
        local cs = container:GetEffectiveScale()
        if cs <= 0 then cs = 1 end
        local cx, cy = mx / cs, my / cs
        local cLeft = container:GetLeft()
        if not cLeft then dropLine:Hide() return end

        -- Boxes in a column share its x-span, so the first box of each
        -- column gives the column's left and right edges.
        local hoverCol, colL, colR
        for c = 1, #cols do
            local b = boxAt[c] and boxAt[c][1]
            if b then
                local L, R = b:GetLeft(), b:GetRight()
                if L and R and cx >= L and cx <= R then
                    hoverCol, colL, colR = c, L, R
                    break
                end
            end
        end

        if not hoverCol then
            local cRight = container:GetRight()
            if cRight and cx > cRight then
                container._dropMode = "newcol"
                -- The second term covers the dragged window being alone in
                -- the outermost column: the next column in anchors the
                -- insert, so the new column still lands at this end.
                container._dropLeftRep = repOf(#cols, dragWin) or repOf(#cols - 1, dragWin)
                showColLine(container:GetWidth())
            elseif cx < cLeft then
                container._dropMode = "newcol"
                container._dropRightRep = repOf(1, dragWin) or repOf(2, dragWin)
                showColLine(0)
            else
                dropLine:Hide()
            end
            return
        end

        -- Outer quarters of the hovered column make a new column on that
        -- side; the middle half stacks into the column.
        local frac = (cx - colL) / math_max(1, colR - colL)
        if frac <= 0.25 then
            container._dropMode = "newcol"
            container._dropLeftRep = repOf(hoverCol - 1, dragWin)
            container._dropRightRep = repOf(hoverCol, dragWin) or repOf(hoverCol + 1, dragWin)
            showColLine(colL - cLeft)
        elseif frac >= 0.75 then
            container._dropMode = "newcol"
            container._dropLeftRep = repOf(hoverCol, dragWin) or repOf(hoverCol - 1, dragWin)
            container._dropRightRep = repOf(hoverCol + 1, dragWin)
            showColLine(colR - cLeft)
        else
            local wins = cols[hoverCol].Windows or {}
            local hit, after
            for r = 1, #wins do
                local b = boxAt[hoverCol][r]
                if b and b.winIdx ~= dragWin then
                    local Tp, B = b:GetTop(), b:GetBottom()
                    if Tp and B and cy >= B and cy <= Tp then
                        hit = b
                        after = cy < (Tp + B) / 2   -- lower half -> drop AFTER this box
                        break
                    end
                end
            end
            if hit then
                hit:SetBackdropBorderColor(1, 1, 1, 1)
                container._dropMode = "stack"
                container._dropAnchor = hit.winIdx
                container._dropAfter = after
                dropLine:ClearAllPoints()
                dropLine:SetHeight(3)
                if after then
                    dropLine:SetPoint("TOPLEFT", hit, "BOTTOMLEFT", 0, -1)
                    dropLine:SetPoint("TOPRIGHT", hit, "BOTTOMRIGHT", 0, -1)
                else
                    dropLine:SetPoint("BOTTOMLEFT", hit, "TOPLEFT", 0, 1)
                    dropLine:SetPoint("BOTTOMRIGHT", hit, "TOPRIGHT", 0, 1)
                end
                dropLine:Show()
            else
                dropLine:Hide()
            end
        end
    end

    -- Gap handles: an 8 px hit frame over each 4 px gap between two boxes.
    -- Dragging one moves that split as its slider and the in-world splitter
    -- do, clamped to the same range.
    local handles = {}
    local gapDrag = {}
    -- Carries the gap drag's OnUpdate. A handle's scripts are set once, in
    -- NewHandle, and never changed: the map is pooled, so a script swapped on
    -- a handle later would outlive the page that swapped it.
    local gapDriver = CreateFrame("Frame", nil, container)

    local function PaintHandle(h)
        h.line:SetShown(h._hover or h._lit or gapDrag.handle == h)
    end

    local function StopGapDrag()
        local h = gapDrag.handle
        if not h then return end
        gapDrag.handle = nil
        gapDriver:SetScript("OnUpdate", nil)
        PaintHandle(h)
    end

    -- The pointer's place across the pair, less half the gap, is the left or
    -- top side's share. The pair's outer edges do not move during the drag: a
    -- split move keeps the pair's ratio sum.
    local function GapDragUpdate()
        local h = gapDrag.handle
        local dm = GetDM()
        if not (h and dm) then return end
        if not IsMouseButtonDown("LeftButton") then StopGapDrag() return end
        local cs = container:GetEffectiveScale()
        if cs <= 0 then cs = 1 end
        local mx, my = GetCursorPosition()
        local pct
        if h.kind == "col" then
            pct = (mx / cs - gapDrag.start - MAP_GAP / 2) / gapDrag.span * 100
        else
            pct = (gapDrag.start - my / cs - MAP_GAP / 2) / gapDrag.span * 100
        end
        if pct < gapDrag.lo then pct = gapDrag.lo elseif pct > gapDrag.hi then pct = gapDrag.hi end
        if h.kind == "col" then
            dm:SetColumnBoundaryShare(h.c, pct)
        else
            dm:SetRowBoundaryShare(h.c, h.r, pct)
        end
        container.Relayout()
    end

    local function StartGapDrag(h)
        local dm = GetDM()
        local boxAt = container._boxAt
        local col = boxAt and boxAt[h.c]
        if not (dm and col) then return end
        local a, b, start, far, lo, hi
        if h.kind == "col" then
            local nextCol = boxAt[h.c + 1]
            a, b = col[1], nextCol and nextCol[1]
            if not (a and b) then return end
            start, far = a:GetLeft(), b:GetRight()
            if not (start and far) then return end
            gapDrag.span = far - start - MAP_GAP
            lo, hi = dm:GetColumnBoundaryRange(h.c)
        else
            a, b = col[h.r], col[h.r + 1]
            if not (a and b) then return end
            start, far = a:GetTop(), b:GetBottom()
            if not (start and far) then return end
            gapDrag.span = start - far - MAP_GAP
            lo, hi = dm:GetRowBoundaryRange(h.c, h.r)
        end
        if gapDrag.span <= 0 then return end
        gapDrag.start, gapDrag.lo, gapDrag.hi = start, lo, hi
        gapDrag.handle = h
        PaintHandle(h)
        gapDriver:SetScript("OnUpdate", GapDragUpdate)
    end

    local function NewHandle()
        local h = CreateFrame("Frame", nil, container)
        h:EnableMouse(true)
        h.line = h:CreateTexture(nil, "OVERLAY")
        h.line:Hide()
        h:SetScript("OnEnter", function(self)
            self._hover = true
            PaintHandle(self)
            if container._onHover then container._onHover("gap", self, true) end
        end)
        h:SetScript("OnLeave", function(self)
            self._hover = false
            PaintHandle(self)
            if container._onHover then container._onHover("gap", self, false) end
        end)
        h:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then StartGapDrag(self) end
        end)
        h:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then StopGapDrag() end
        end)
        h:SetScript("OnHide", StopGapDrag)
        handles[#handles + 1] = h
        GUIFrame:PoolGrow(container, container, 1, 0)
        GUIFrame:PoolOwn(container, h)
        return h
    end

    -- One handle per gap, anchored to the box before it, so a relayout carries
    -- the handles along. A column handle spans the map's height; a row handle
    -- spans its column.
    function container.ConfigureHandles()
        local cols, boxAt = container._cols, container._boxAt
        local accent = Theme.accent
        local level = container:GetFrameLevel() + 4
        local n = 0
        for c = 1, #cols do
            local col, nextCol = boxAt[c], boxAt[c + 1]
            if col and col[1] and nextCol and nextCol[1] then
                n = n + 1
                local h = handles[n] or NewHandle()
                h.kind, h.c, h.r = "col", c, nil
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", col[1], "TOPRIGHT", MAP_GAP / 2 - 4, 0)
                h:SetSize(8, container._height)
                h.line:ClearAllPoints()
                h.line:SetSize(2, container._height)
                h.line:SetPoint("CENTER", h, "CENTER", 0, 0)
                h.line:SetColorTexture(accent[1], accent[2], accent[3], 1)
                h:SetFrameLevel(level)
                h._hover = false
                h:Show()
                PaintHandle(h)
            end
            if col then
                for r = 1, #col - 1 do
                    n = n + 1
                    local h = handles[n] or NewHandle()
                    h.kind, h.c, h.r = "row", c, r
                    h:ClearAllPoints()
                    h:SetPoint("TOPLEFT", col[r], "BOTTOMLEFT", 0, 4 - MAP_GAP / 2)
                    h:SetPoint("TOPRIGHT", col[r], "BOTTOMRIGHT", 0, 4 - MAP_GAP / 2)
                    h:SetHeight(8)
                    h.line:ClearAllPoints()
                    h.line:SetHeight(2)
                    h.line:SetPoint("LEFT", h, "LEFT", 0, 0)
                    h.line:SetPoint("RIGHT", h, "RIGHT", 0, 0)
                    h.line:SetColorTexture(accent[1], accent[2], accent[3], 1)
                    h:SetFrameLevel(level)
                    h._hover = false
                    h:Show()
                    PaintHandle(h)
                end
            end
        end
        for i = n + 1, #handles do handles[i]:Hide() end
    end

    -- Ends a drag with nothing moved. Also the pool's reset, so a page
    -- rebuilt under a drag leaves no ghost, line, dimmed box or gap drag.
    function container.CancelDrag()
        container:SetScript("OnUpdate", nil)
        container._dragWin = nil
        StopGapDrag()
        ClearDrop()
        dropLine:Hide()
        for i = 1, #boxes do boxes[i]:SetAlpha(1) end
        ResetBorders()
        if schematicGhost then schematicGhost:Hide() end
    end

    -- Geometric, so moving from the box onto its own remove button keeps it,
    -- whichever event arrives first. A gap handle covers the box's last 2 px
    -- and sits above it, so the pointer can be inside the box and on a handle
    -- at once; that counts as off the box.
    function container.HideRemoveUnlessOver(box)
        local over = box:IsMouseOver()
        if over then
            for i = 1, #handles do
                local h = handles[i]
                if h:IsShown() and h:IsMouseOver() then
                    over = false
                    break
                end
            end
        end
        if not over then box.removeBtn:Hide() end
    end

    local function NewBox()
        local box = CreateFrame("Frame", nil, container, "BackdropTemplate")
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })

        box.chip = NewChip(box, 20)

        local typeText = box:CreateFontString(nil, "OVERLAY")
        typeText:SetPoint("LEFT", box.chip, "RIGHT", 6, 0)
        -- Level with the chip's center, clear of the remove button.
        typeText:SetPoint("RIGHT", box, "TOPRIGHT", -24, -16)
        typeText:SetJustifyH("LEFT")
        typeText:SetWordWrap(false)
        box.typeText = typeText

        local segText = box:CreateFontString(nil, "OVERLAY")
        segText:SetPoint("TOPLEFT", box, "TOPLEFT", 32, -28)
        segText:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -28)
        segText:SetJustifyH("LEFT")
        segText:SetWordWrap(false)
        box.segText = segText

        local removeBtn = CreateFrame("Button", nil, box)
        removeBtn:SetSize(16, 16)
        removeBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, -4)
        removeBtn:SetFrameLevel(box:GetFrameLevel() + 2)
        removeBtn.text = removeBtn:CreateFontString(nil, "OVERLAY")
        removeBtn.text:SetPoint("CENTER")
        removeBtn:Hide()
        removeBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Remove window " .. tostring(box.pos or "?"), 1, 1, 1, 1, true)
            GameTooltip:Show()
            if container._onHover then container._onHover("box", box, true) end
        end)
        removeBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
            container.HideRemoveUnlessOver(box)
            if container._onHover then container._onHover("box", box, false) end
        end)
        removeBtn:SetScript("OnClick", function()
            local dm = GetDM()
            if dm and dm.RemoveWindow and box.winIdx then dm:RemoveWindow(box.winIdx) end
            RebuildPage()
        end)
        box.removeBtn = removeBtn

        -- The 2 px mark for a window the pointer is on, here or on the meter.
        local lit = CreateFrame("Frame", nil, box, "BackdropTemplate")
        lit:SetAllPoints(box)
        lit:SetFrameLevel(box:GetFrameLevel() + 1)
        lit:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        lit:Hide()
        box.lit = lit

        box:EnableMouse(true)
        box:SetScript("OnEnter", function(self)
            if self._removable and not (container._dragWin or gapDrag.handle) then self.removeBtn:Show() end
            if container._onHover then container._onHover("box", self, true) end
        end)
        box:SetScript("OnLeave", function(self)
            container.HideRemoveUnlessOver(self)
            if container._onHover then container._onHover("box", self, false) end
        end)
        box:RegisterForDrag("LeftButton")
        box:SetScript("OnDragStart", function(self)
            local posOf, infoOf = container._posOf, container._infoOf
            if not (posOf and infoOf) then return end
            container._dragWin = self.winIdx
            ClearDrop()
            self.removeBtn:Hide()
            self:SetAlpha(0.4)
            local ghost = GetSchematicGhost()
            PaintSchematicGhost(ghost)
            local label = tostring(posOf[self.winIdx] or "?")
            local _, _, full = infoOf(self.winIdx)
            if full and full ~= "" then label = label .. "  " .. full end
            ghost.text:SetText(label)
            ghost:SetWidth(math_max(60, ghost.text:GetStringWidth() + 18))
            ghost:Show()
            container:SetScript("OnUpdate", DragUpdate)
            DragUpdate()  -- position immediately, before the first frame tick
        end)
        box:SetScript("OnDragStop", function()
            local dragWin = container._dragWin
            local mode = container._dropMode
            local anchor = container._dropAnchor
            local after = container._dropAfter
            local leftRep = container._dropLeftRep
            local rightRep = container._dropRightRep
            container.CancelDrag()
            local dm = GetDM()
            if dm and dragWin then
                if mode == "stack" and anchor and anchor ~= dragWin then
                    if dm.MoveWindowToSlot then dm:MoveWindowToSlot(dragWin, anchor, after) end
                    RebuildPage()
                elseif mode == "newcol" then
                    if dm.MoveWindowToNewColumn then dm:MoveWindowToNewColumn(dragWin, leftRep, rightRep) end
                    RebuildPage()
                end
            end
        end)

        boxes[#boxes + 1] = box
        GUIFrame:PoolGrow(container, container, 1, 0)
        GUIFrame:PoolOwn(container, box)
        return box
    end

    -- A short box keeps only what fits: under 44 px no segment line, under
    -- 26 px no type either, with the chip centered.
    local function PlaceBoxContent(box, h)
        local chip = box.chip
        chip:ClearAllPoints()
        if h < 26 then
            chip:SetPoint("LEFT", box, "LEFT", 6, 0)
            box.typeText:Hide()
        else
            chip:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
            box.typeText:Show()
        end
        box.segText:SetShown(h >= 44)
    end

    local function Layout(width)
        local cols, boxAt, height = container._cols, container._boxAt, container._height
        if not (cols and boxAt and height) or not width or width <= 0 then return end
        local sumW = 0
        for c = 1, #cols do sumW = sumW + ((cols[c].WidthRatio) or 1) end
        if sumW <= 0 then sumW = math_max(1, #cols) end
        local availW = width - MAP_GAP * math_max(0, #cols - 1)
        if availW <= 0 then availW = width end
        local runX = 0
        for c = 1, #cols do
            local colW = availW * (((cols[c].WidthRatio) or 1) / sumW)
            local wins = cols[c].Windows or {}
            local ratios = cols[c].RowRatios or {}
            local sumR = 0
            for r = 1, #wins do sumR = sumR + ((ratios[r]) or 1) end
            if sumR <= 0 then sumR = math_max(1, #wins) end
            local availH = height - MAP_GAP * math_max(0, #wins - 1)
            if availH <= 0 then availH = height end
            local runY = 0
            for r = 1, #wins do
                local rowH = availH * (((ratios[r]) or 1) / sumR)
                local box = boxAt[c] and boxAt[c][r]
                if box then
                    box:ClearAllPoints()
                    box:SetPoint("TOPLEFT", container, "TOPLEFT", runX, -runY)
                    box:SetSize(math_max(1, colW), math_max(1, rowH))
                    PlaceBoxContent(box, rowH)
                end
                runY = runY + rowH + MAP_GAP
            end
            runX = runX + colW + MAP_GAP
        end
    end

    container:SetScript("OnSizeChanged", function(_, w)
        container._keWidth = w
        Layout(w)
    end)

    -- For the Sizing sliders: the columns table is the live saved one, so a
    -- relayout picks up a ratio the slider has just written.
    container.Relayout = function() Layout(container:GetWidth()) end

    -- fn(kind, frame, entering): kind "box" for a box (frame.winIdx), "gap" for a
    -- gap handle (frame.kind, frame.c, frame.r). Setting it clears every mark.
    function container.SetHover(fn)
        container._onHover = fn
        container.LightBoxes(nil)
        container.LightGap(nil)
    end

    -- set[idx] = true lights those windows' boxes; nil lights none.
    function container.LightBoxes(set)
        local accent = Theme.accent
        for i = 1, #boxes do
            local box = boxes[i]
            if set and i <= (container._count or 0) and set[box.winIdx] then
                box.lit:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
                box.lit:Show()
            else
                box.lit:Hide()
            end
        end
    end

    -- gap is a split target ({ gapKind, c, r }) or nil.
    function container.LightGap(gap)
        for i = 1, #handles do
            local h = handles[i]
            h._lit = gap ~= nil and h.kind == gap.gapKind and h.c == gap.c and h.r == gap.r
            PaintHandle(h)
        end
    end

    -- infoOf(idx) returns the window's type text, segment text and full label.
    function container.Configure(_, cols, posOf, infoOf, removable)
        local T = Theme
        container:SetHeight(MAP_HEIGHT)
        container._height = MAP_HEIGHT
        container._cols = cols
        container._posOf = posOf
        container._infoOf = infoOf
        dropLine:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        dropLine:Hide()

        local boxAt = {}
        local count = 0
        for c = 1, #cols do
            local wins = cols[c].Windows or {}
            boxAt[c] = {}
            for r = 1, #wins do
                local idx = wins[r]
                count = count + 1
                local box = boxes[count] or NewBox()
                local typeName, segName = infoOf(idx)
                box.winIdx = idx
                box.pos = posOf[idx]
                box._removable = removable
                box:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
                box:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
                box:SetAlpha(1)
                PaintChip(box.chip, posOf[idx] or "?", 14)
                KE:ApplyThemeFont(box.typeText, 13)
                box.typeText:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
                box.typeText:SetText(typeName or "")
                KE:ApplyThemeFont(box.segText, 12)
                box.segText:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
                box.segText:SetText(segName or "")
                KE:ApplyThemeFont(box.removeBtn.text, 13)
                box.removeBtn.text:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
                box.removeBtn.text:SetText("x")
                box.removeBtn:Hide()
                box:Show()
                boxAt[c][r] = box
            end
        end
        for i = count + 1, #boxes do boxes[i]:Hide() end

        container._boxAt = boxAt
        container._count = count
        container.ConfigureHandles()
        Layout(container._keWidth)
    end

    -- Re-reads each box's type and segment, after a Type or Segment pick.
    function container.RefreshInfo()
        local infoOf = container._infoOf
        if not infoOf then return end
        for i = 1, container._count or 0 do
            local box = boxes[i]
            local typeName, segName = infoOf(box.winIdx)
            box.typeText:SetText(typeName or "")
            box.segText:SetText(segName or "")
        end
    end

    container._keOwned = { container }
    return container
end

GUIFrame:NewWidgetPool("dm:schematic", ConstructSchematic, function(container)
    container.CancelDrag()
end)

-- The Default Display row chip. The outer frame takes the column width; the
-- chip sits 14 px down, level with the row's controls.
local function ConstructNumberBadge(parent)
    local f = CreateFrame("Frame", nil, parent)
    local chip = NewChip(f, 24)
    chip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -14)

    function f.Configure(_, n)
        PaintChip(chip, n, 15)
    end

    f._keOwned = { f, chip }
    return f
end

GUIFrame:NewWidgetPool("dm:badge", ConstructNumberBadge, function() end)

local WINDOW_HEADER_NAMES = { "Show", "Type", "Segment" }

-- Column labels, shown once above the window rows so "Type" and "Segment" do
-- not repeat on every row. Each sits at the cumulative column fraction
-- row:AddWidget uses, so it lands above its control column.
local function ConstructWindowHeader(parent)
    local hdr = CreateFrame("Frame", nil, parent)
    hdr._keWidth = 0

    local labels = {}
    for i = 1, 3 do
        local fs = hdr:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("LEFT")
        labels[i] = fs
    end

    local function Layout(w)
        local fractions = hdr._fractions
        if not fractions or w <= 0 then return end
        for i = 1, 3 do
            labels[i]:ClearAllPoints()
            labels[i]:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", w * fractions[i], 0)
        end
    end

    hdr:SetScript("OnSizeChanged", function(_, w)
        hdr._keWidth = w
        Layout(w)
    end)

    function hdr.Configure(_, fractions)
        hdr:SetHeight(14)
        hdr._fractions = fractions
        for i = 1, 3 do
            KE:ApplyThemeFont(labels[i], "small")
            labels[i]:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
            labels[i]:SetText(WINDOW_HEADER_NAMES[i])
        end
        Layout(hdr._keWidth)
    end

    hdr._keOwned = { hdr }
    return hdr
end

GUIFrame:NewWidgetPool("dm:hdr", ConstructWindowHeader, function() end)

---------------------------------------------------------------------------------
-- Hover link
---------------------------------------------------------------------------------
-- Pointing at a window's row or map box, or at a split's slider or map gap,
-- lights it here and outlines its windows on the meter. Pointing at a meter
-- window lights its row and box. Filled by each Windows tab build and emptied
-- by every rebuild and by leaving the page.
local HOVER_ROW_ALPHA = 0.06

local Hover = { targets = {}, gaps = {}, set = {} }

-- r is nil for a column split; AddSplit passes nil for every column gap.
---@param kind string
---@param c integer
---@param r integer|nil
---@return string
function Hover.GapKey(kind, c, r)
    if kind == "col" or not r then return "c" .. c end
    return "r" .. c .. ":" .. r
end

-- The target's windows as a set, in one reused table.
function Hover.SetOf(target)
    local set = Hover.set
    wipe(set)
    if target then
        for i = 1, #target.wins do set[target.wins[i]] = true end
    end
    return set
end

function Hover.Paint(target)
    for _, t in pairs(Hover.targets) do t.catcher:SetLit(t == target) end
    for _, t in pairs(Hover.gaps) do t.catcher:SetLit(t == target) end
    local map = Hover.schematic
    if not map then return end
    if target and target.kind == "win" then
        map.LightBoxes(Hover.SetOf(target))
    else
        map.LightBoxes(nil)
    end
    map.LightGap(target and target.kind == "gap" and target or nil)
end

function Hover.Highlight(target)
    local DM = GetDM()
    if DM and DM.HighlightWindows then
        DM:HighlightWindows(target and Hover.SetOf(target) or nil)
    end
end

-- Repeats each frame while the pointer is still on the focused frame. A frame
-- with no hover report of its own (a pooled widget's part this page does not
-- wire, a dropdown's open list) sends no leave when the pointer goes straight
-- off the element, so only this geometric test can end the focus. An enter
-- stops the repeat.
function Hover.Check()
    Hover.looping = false
    if not Hover.wanted then return end
    local frame = Hover.frame
    if Hover.focus and frame and frame:IsVisible() and frame:IsMouseOver() then
        Hover.looping = true
        C_Timer.After(0, Hover.Check)
        return
    end
    Hover.wanted = false
    if not Hover.focus then return end
    Hover.focus, Hover.frame = nil, nil
    Hover.Paint(Hover.meterTarget)
    Hover.Highlight(nil)
end

-- An enter takes the focus at once. A leave is settled by the geometric test
-- above, so a move between a row's own widgets, or from a box onto its remove
-- button, keeps the focus.
function Hover.Note(target, frame, entering)
    if not Hover.active then return end
    if entering then
        Hover.wanted = false
        Hover.frame = frame
        if Hover.focus ~= target then
            Hover.focus = target
            Hover.Paint(target)
            Hover.Highlight(target)
        end
    else
        Hover.wanted = true
        if not Hover.looping then
            Hover.looping = true
            C_Timer.After(0, Hover.Check)
        end
    end
end

-- The meter side: idx is the window under the pointer on the meter, or nil.
function Hover.OnWindowHover(idx)
    Hover.meterTarget = idx and Hover.targets[idx] or nil
    if not Hover.focus then Hover.Paint(Hover.meterTarget) end
end

function Hover.Begin(schematic)
    Hover.schematic = schematic
    Hover.active = true
end

function Hover.Clear()
    Hover.active, Hover.wanted = false, false
    Hover.focus, Hover.frame, Hover.meterTarget, Hover.schematic = nil, nil, nil, nil
    wipe(Hover.targets)
    wipe(Hover.gaps)
end

-- A row-sized frame under the row's widgets that reports the pointer on the
-- row's chip, its widgets or the gaps between them.
local function ConstructRowHover(parent)
    local f = CreateFrame("Frame", nil, parent)
    -- Motion only: clicks and the wheel reach the widgets and the scroll frame.
    f:SetMouseMotionEnabled(true)
    f:SetMouseClickEnabled(false)
    local tex = f:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(f)
    tex:SetColorTexture(1, 1, 1, HOVER_ROW_ALPHA)
    tex:Hide()

    function f.SetLit(_, on)
        tex:SetShown(on and true or false)
    end

    -- At the row's own level, so each widget above it keeps its own mouse.
    function f.Bind(_, row, target)
        f._target = target
        f:ClearAllPoints()
        f:SetAllPoints(row)
        f:SetFrameLevel(row:GetFrameLevel())
        tex:Hide()
    end

    f:SetScript("OnEnter", function(self)
        if self._target then Hover.Note(self._target, self, true) end
    end)
    f:SetScript("OnLeave", function(self)
        if self._target then Hover.Note(self._target, self, false) end
    end)

    f._keOwned = { f }
    return f
end

GUIFrame:NewWidgetPool("dm:rowhover", ConstructRowHover, function(f)
    f._target = nil
    f:SetLit(false)
end)

local function BindTarget(row, target)
    target.catcher = GUIFrame:AcquirePooled("dm:rowhover", row)
    target.catcher:Bind(row, target)
    return target
end

function Hover.AddWindow(idx, row)
    local target = BindTarget(row, { kind = "win", wins = { idx } })
    Hover.targets[idx] = target
    return target
end

function Hover.AddGap(kind, c, r, leftList, rightList, row)
    local wins = {}
    for i = 1, #leftList do wins[#wins + 1] = leftList[i] end
    for i = 1, #rightList do wins[#wins + 1] = rightList[i] end
    local target = BindTarget(row, { kind = "gap", gapKind = kind, c = c, r = r, wins = wins })
    Hover.gaps[Hover.GapKey(kind, c, r)] = target
    return target
end

-- An empty slot in a row of buttons. Pooled: a frame the page made itself and
-- put on a pooled row would retire that row.
GUIFrame:NewWidgetPool("dm:spacer", function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f._keOwned = { f }
    return f
end, function() end)

local SPLIT_CHIPS = 5

-- The line over a split slider: each side's chips, its name when it is one
-- window, and its "%, px" size, the left side read from the left edge and the
-- right side from the right.
local function ConstructSplitLabel(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(14)
    local sides = {}
    for s = 1, 2 do
        local side = { chips = {} }
        for i = 1, SPLIT_CHIPS do side.chips[i] = NewChip(f, 18) end
        side.name = f:CreateFontString(nil, "OVERLAY")
        side.size = f:CreateFontString(nil, "OVERLAY")
        sides[s] = side
    end

    local function PaintSide(side, spec, fromRight)
        local point, rel, gap = "LEFT", "RIGHT", 2
        if fromRight then point, rel, gap = "RIGHT", "LEFT", -2 end
        local prev
        for i = 1, SPLIT_CHIPS do
            local chip = side.chips[i]
            local n = spec.nums[i]
            chip:ClearAllPoints()
            if n then
                if prev then
                    chip:SetPoint(point, prev, rel, gap, 0)
                else
                    chip:SetPoint(point, f, point, 0, 0)
                end
                PaintChip(chip, n, 13)
                chip:Show()
                prev = chip
            else
                chip:Hide()
            end
        end
        local T = Theme
        local name, size = side.name, side.size
        KE:ApplyThemeFont(name, "small")
        name:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        name:SetText(spec.name or "")
        name:ClearAllPoints()
        name:SetPoint(point, prev or f, prev and rel or point, gap * 3, 0)
        KE:ApplyThemeFont(size, "small")
        size:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        size:SetText("")
        size:ClearAllPoints()
        if spec.name then
            size:SetPoint(point, name, rel, gap * 3, 0)
        else
            size:SetPoint(point, prev or f, prev and rel or point, gap * 3, 0)
        end
    end

    -- left and right are { nums = { display numbers }, name = text or nil }.
    function f.Configure(_, left, right)
        PaintSide(sides[1], left, false)
        PaintSide(sides[2], right, true)
    end

    function f.SetSizes(_, leftText, rightText)
        sides[1].size:SetText(leftText)
        sides[2].size:SetText(rightText)
    end

    -- A side named at Configure keeps its name slot; only the text changes.
    function f.SetNames(_, leftName, rightName)
        sides[1].name:SetText(leftName or "")
        sides[2].name:SetText(rightName or "")
    end

    f._keOwned = { f }
    return f
end

GUIFrame:NewWidgetPool("dm:splitlabel", ConstructSplitLabel, function() end)

-- "Meter Size", then "Whole meter" and the accent-colored dock size.
local function ConstructReadout(parent)
    local f = CreateFrame("Frame", nil, parent)
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetPoint("LEFT", f, "LEFT", 0, 0)
    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", title, "RIGHT", 12, 0)
    local value = f:CreateFontString(nil, "OVERLAY")
    value:SetPoint("LEFT", label, "RIGHT", 8, 0)
    f.title = title

    function f.Configure()
        local T = Theme
        KE:ApplyThemeFont(title, "normal")
        title:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        title:SetText("Meter Size")
        KE:ApplyThemeFont(label, "normal")
        label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        label:SetText("Whole meter")
        KE:ApplyThemeFont(value, "normal")
        value:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        value:SetText("")
    end

    function f.ShowMeterSize(_, w, h)
        if w and h then
            value:SetText(math_floor(w + 0.5) .. " x " .. math_floor(h + 0.5) .. " px")
        else
            value:SetText("")
        end
    end

    f._keOwned = { f }
    return f
end

GUIFrame:NewWidgetPool("dm:readout", ConstructReadout, function() end)

---------------------------------------------------------------------------------
-- Windows tab (structure, sizes, position and per-context defaults)
---------------------------------------------------------------------------------
-- True from a Windows tab build until the link is cleared.
local windowsLinked = false

local function BuildWindowsTab(scrollChild, yOffset, db, manager)
    local DM = GetDM()
    if not (DM and DM.GetColumnWidthPx) then return yOffset end

    -- Storage indices in on-screen order: order[n] is the window the meter
    -- numbers n, the order LayoutDock numbers the chips in.
    local order = DM.DockWindowIndices and DM:DockWindowIndices({}) or {}
    local posOf = {}
    for n = 1, #order do posOf[order[n]] = n end

    local cols = db.Dock and db.Dock.Columns
    local arrangement = (DM.GetArrangement and DM:GetArrangement()) or "Custom"
    local maxWin = db.MaxWindows or 5

    -- The map and the split labels show the context Configure For is editing.
    if DM.guiConfigContext == nil then DM.guiConfigContext = "Default" end
    local ctx = DM.guiConfigContext or "Default"
    db.Windows = db.Windows or {}

    local function InfoFor(idx)
        local w = db.Windows[idx]
        local cfg = w and w.Contexts and (w.Contexts[ctx] or w.Contexts.Default)
        if not cfg then return "", "", "" end
        local meterType = cfg.MeterType or Enum.DamageMeterType.DamageDone
        local sessionType = cfg.SessionType or Enum.DamageMeterSessionType.Current
        local full = DM.FormatWindowLabel and DM:FormatWindowLabel(meterType, sessionType) or ""
        return TYPE_TEXT[meterType] or "", SEGMENT_TEXT[sessionType] or "", full
    end

    local schematic

    ----------------------------------------------------------------
    -- Layout: three arrangement buttons and Add Window over the map
    ----------------------------------------------------------------
    local cardLayout = GUIFrame:CreateCard(scrollChild, "Layout", yOffset)
    manager:Register(cardLayout, "all")

    local rowArr = GUIFrame:CreateRow(cardLayout.content, Theme.rowHeight)
    local arrLabel = rowArr:GetLabel("small")
    arrLabel:SetPoint("TOPLEFT", rowArr, "TOPLEFT", 0, 1)
    arrLabel:SetJustifyH("LEFT")
    arrLabel:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    arrLabel:SetText("Layout")

    for _, spec in ipairs(ARRANGEMENT_BUTTONS) do
        local key = spec.key
        local btn = GUIFrame:CreateButton(rowArr, spec.text, {
            height = 24,
            tooltip = spec.tooltip,
            callback = function()
                -- Custom only shows the state; the map makes a custom layout.
                if key == "Custom" then return end
                if DM.SetArrangement then DM:SetArrangement(key) end
                RebuildPage()
            end,
        })
        btn:SetSelected(arrangement == key)
        rowArr:AddWidget(btn, 0.145, nil, 0, -14)
        manager:Register(btn, "all")
    end

    local spacer = GUIFrame:AcquirePooled("dm:spacer", rowArr)
    rowArr:AddWidget(spacer, 0.36)

    -- Not registered: manager:UpdateAll would enable it again past the cap.
    local addBtn = GUIFrame:CreateButton(rowArr, "Add Window", {
        height = 24,
        tooltip = "Adds a window as a new column on the right, up to " .. maxWin .. " windows.",
        callback = function()
            if DM.AddWindow then DM:AddWindow() end
            RebuildPage()
        end,
    })
    rowArr:AddWidget(addBtn, 0.205, nil, 0, -14)
    addBtn:SetEnabled(#order < maxWin)
    cardLayout:AddRow(rowArr, Theme.rowHeight)

    if cols and #order > 0 then
        schematic = GUIFrame:AcquirePooled("dm:schematic", cardLayout.content)
        schematic:Configure(cols, posOf, InfoFor, #order > 1)
        cardLayout:AddRow(schematic, MAP_HEIGHT)
    end
    cardLayout:AddNote("Drag a window onto another to stack it, or to an edge for a new column.")

    yOffset = cardLayout:GetNextOffset()

    ----------------------------------------------------------------
    -- Sizing: the whole meter, then one split slider per gap -- the pair
    -- the in-world splitter for that gap moves
    ----------------------------------------------------------------
    local nCols = (cols and #cols) or 0
    local colGaps, rowGaps = {}, {}
    for c = 1, nCols - 1 do colGaps[#colGaps + 1] = c end
    for c = 1, nCols do
        local wins = cols[c].Windows
        if wins then
            for r = 1, #wins - 1 do rowGaps[#rowGaps + 1] = { c = c, r = r } end
        end
    end
    local nGaps = #colGaps + #rowGaps

    local cardSize = GUIFrame:CreateCard(scrollChild, "Sizing", yOffset)
    manager:Register(cardSize, "all")

    local rowMeter = GUIFrame:CreateRow(cardSize.content, 24)
    local readout = GUIFrame:AcquirePooled("dm:readout", rowMeter)
    readout:Configure()
    rowMeter:AddWidget(readout, 0.795)
    -- Not registered, like Add Window: it stays off with no gap to even out.
    local evenBtn = GUIFrame:CreateButton(rowMeter, "Even Sizes", {
        height = 24,
        tooltip = "Makes every column the Window Width and splits every column's height evenly.",
        callback = function()
            if DM.EvenSizes then DM:EvenSizes() end
        end,
    })
    rowMeter:AddWidget(evenBtn, 0.205)
    evenBtn:SetEnabled(nGaps > 0)
    cardSize:AddRow(rowMeter, 24)

    local rowWidth = GUIFrame:CreateRow(cardSize.content, Theme.rowHeight)
    local widthSlider = GUIFrame:CreateSlider(rowWidth, "Window Width", {
        min = 120, max = 600, step = 1,
        value = db.Width or 240,
        tooltip = "The width of one column when the columns are even, in pixels.",
        callback = function(val) db.Width = val; ApplySettings() end,
    })
    rowWidth:AddWidget(widthSlider, 0.5)
    manager:Register(widthSlider, "all")

    local visSlider = GUIFrame:CreateSlider(rowWidth, "Visible Bars", {
        min = 1, max = 40, step = 1,
        value = db.VisibleBars or 10,
        tooltip = "How many bars fit the meter's height. Stacked windows share that height.",
        callback = function(val) db.VisibleBars = val; ApplySettings() end,
    })
    rowWidth:AddWidget(visSlider, 0.5)
    manager:Register(visSlider, "all")
    cardSize:AddRow(rowWidth, Theme.rowHeight)

    local barsLast = nGaps == 0
    local rowBars = GUIFrame:CreateRow(cardSize.content, barsLast and Theme.rowHeightLast or Theme.rowHeight)
    local heightSlider = GUIFrame:CreateSlider(rowBars, "Bar Height", {
        min = 8, max = 40, step = 1,
        value = db.BarHeight or 16,
        callback = function(val) db.BarHeight = val; ApplySettings() end,
    })
    rowBars:AddWidget(heightSlider, 0.5)
    manager:Register(heightSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(rowBars, "Bar Spacing", {
        min = -1, max = 10, step = 1,
        value = db.BarSpacing or 2,
        callback = function(val) db.BarSpacing = val; ApplySettings() end,
    })
    rowBars:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    cardSize:AddRow(rowBars, barsLast and Theme.rowHeightLast or Theme.rowHeight, barsLast and 0 or nil)
    if not barsLast then cardSize:AddSeparator() end

    local splits = {}

    -- The left or top side's share of the pair, in percent.
    local function ShareOf(split)
        if split.kind == "col" then return DM:GetColumnBoundaryShare(split.c) end
        return DM:GetRowBoundaryShare(split.c, split.r)
    end

    local function SizeText(pct, px)
        if px then return pct .. "%, " .. math_floor(px + 0.5) .. " px" end
        return pct .. "%"
    end

    -- Each side's px from the last layout; nil for a side not placed.
    local function ReadSplitPx(split)
        if split.kind == "col" then
            return DM:GetColumnWidthPx(split.c), DM:GetColumnWidthPx(split.c + 1)
        end
        return DM:GetWindowHeightPx(split.leftIdx), DM:GetWindowHeightPx(split.rightIdx)
    end

    -- value is the slider's 0-1 left share; the right share is its complement.
    local function PaintSplit(split, value)
        local left = math_floor((value or 0.5) * 100 + 0.5)
        if left < 0 then left = 0 elseif left > 100 then left = 100 end
        split.label:SetSizes(SizeText(left, split.leftPx), SizeText(100 - left, split.rightPx))
    end

    -- The split's range in percent. It follows the pair's pixels, so a change
    -- to Window Width, Visible Bars or a bar size moves it.
    local function RangeOf(split)
        if split.kind == "col" then return DM:GetColumnBoundaryRange(split.c) end
        return DM:GetRowBoundaryRange(split.c, split.r)
    end

    -- A single window is named; a column of several is shown by its chips alone.
    local function NameOf(list)
        if #list == 1 then return (InfoFor(list[1])) end
        return nil
    end

    local function SideOf(list)
        local nums = {}
        for i = 1, #list do nums[i] = posOf[list[i]] or list[i] end
        return { nums = nums, name = NameOf(list) }
    end

    local function AddSplit(kind, c, r, leftList, rightList, isLast)
        local split = {
            kind = kind, c = c, r = r,
            leftList = leftList, rightList = rightList,
            leftIdx = leftList[1], rightIdx = rightList[1],
        }
        local lo, hi = RangeOf(split)
        local row = GUIFrame:CreateRow(cardSize.content, SPLIT_ROW_H)
        local label = GUIFrame:AcquirePooled("dm:splitlabel", row)
        label:Configure(SideOf(leftList), SideOf(rightList))
        label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        label:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        split.label = label
        local target = Hover.AddGap(kind, c, r, leftList, rightList, row)
        split.leftPx, split.rightPx = ReadSplitPx(split)
        -- The neighbors that share a pane follow on the next layout, through
        -- OnDockLayout below.
        local slider = GUIFrame:CreateSlider(row, "", {
            min = lo / 100, max = hi / 100, step = 0.01, isPercent = true,
            value = ShareOf(split) / 100,
            tooltip = SPLIT_TOOLTIP,
            onValueChanged = function(val) PaintSplit(split, val) end,
            onHover = function(entering) Hover.Note(target, target.catcher, entering) end,
            callback = function(val)
                if kind == "col" then
                    DM:SetColumnBoundaryShare(c, val * 100)
                else
                    DM:SetRowBoundaryShare(c, r, val * 100)
                end
                if schematic then schematic.Relayout() end
            end,
        })
        split.slider = slider
        row:AddWidget(slider, 1, nil, 0, -6)
        manager:Register(slider, "all")
        cardSize:AddRow(row, SPLIT_ROW_H, isLast and 0 or nil)
        splits[#splits + 1] = split
        PaintSplit(split, slider:GetValue())
    end

    if #colGaps > 0 then
        cardSize:AddLabel("Widths")
        for i = 1, #colGaps do
            local c = colGaps[i]
            AddSplit("col", c, nil, cols[c].Windows or {}, cols[c + 1].Windows or {},
                i == #colGaps and #rowGaps == 0)
        end
    end
    if #rowGaps > 0 then
        cardSize:AddLabel("Heights")
        for i = 1, #rowGaps do
            local gap = rowGaps[i]
            local wins = cols[gap.c].Windows
            AddSplit("row", gap.c, gap.r, { wins[gap.r] }, { wins[gap.r + 1] }, i == #rowGaps)
        end
    end

    yOffset = cardSize:GetNextOffset()

    -- A Type or Segment pick renames the map boxes and the split sides at once.
    -- Placement and pixels follow through OnDockLayout below.
    local function RefreshNames()
        if schematic then schematic.RefreshInfo() end
        for i = 1, #splits do
            local split = splits[i]
            split.label:SetNames(NameOf(split.leftList), NameOf(split.rightList))
        end
    end

    ----------------------------------------------------------------
    -- Position Settings (the dock is the positioned frame)
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        positionKey = "Position",
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Default Display (Configure For: <context>)
    ----------------------------------------------------------------
    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Default Display", yOffset)
    manager:Register(cardDisplay, "all")

    local rowCtx = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    local ctxDropdown = GUIFrame:CreateDropdown(rowCtx, "Configure For", {
        options = CONTEXT_OPTIONS,
        value = ctx,
        tooltip = "Each kind of content can have its own windows, types and segments. They apply when " ..
            "you enter that content; content you have not set up uses Default.",
        callback = function(key)
            DM.guiConfigContext = key
            RebuildPage()
        end,
    })
    rowCtx:AddWidget(ctxDropdown, 1)
    manager:Register(ctxDropdown, "all")
    cardDisplay:AddRow(rowCtx, Theme.rowHeight)
    cardDisplay:AddNote("Changing type or segment on the meter itself lasts until you enter different content.")

    -- Column layout shared by the header + every window row (so they align):
    --   badge 0.08 | enable 0.16 | Type 0.38 | Segment 0.38.
    local COL_BADGE, COL_ENABLE, COL_TYPE, COL_SEG = 0.08, 0.16, 0.38, 0.38

    -- Card alpha grays the header with the module; it is not registered.
    local hdrRow = GUIFrame:AcquirePooled("dm:hdr", cardDisplay.content)
    hdrRow:Configure({ COL_BADGE, COL_BADGE + COL_ENABLE, COL_BADGE + COL_ENABLE + COL_TYPE })
    cardDisplay:AddRow(hdrRow, 14)

    -- One row per window, in on-screen order: [chip] [enable] [Type] [Segment].
    for n = 1, #order do
        local idx = order[n]
        local window = db.Windows[idx]
        if window and window.Contexts then
            local cfg = window.Contexts[ctx] or window.Contexts.Default or {}

            local function writeField(field, value)
                window.Contexts[ctx] = window.Contexts[ctx] or {
                    Enabled = (window.Contexts.Default and window.Contexts.Default.Enabled) ~= false,
                    MeterType = (window.Contexts.Default and window.Contexts.Default.MeterType)
                        or Enum.DamageMeterType.DamageDone,
                    SessionType = (window.Contexts.Default and window.Contexts.Default.SessionType)
                        or Enum.DamageMeterSessionType.Current,
                }
                window.Contexts[ctx][field] = value
                if DM.RefreshDock then DM:RefreshDock() end
                if DM.Tick then DM:Tick() end
                if field ~= "Enabled" then RefreshNames() end
            end

            local isLast = (n == #order)
            local rowW = GUIFrame:CreateRow(cardDisplay.content, isLast and Theme.rowHeightLast or Theme.rowHeight)
            local target = Hover.AddWindow(idx, rowW)
            local function RowHover(entering) Hover.Note(target, target.catcher, entering) end

            local badge = GUIFrame:AcquirePooled("dm:badge", rowW)
            badge:Configure(n)
            rowW:AddWidget(badge, COL_BADGE)

            local enChk = GUIFrame:CreateCheckbox(rowW, "", {
                value = cfg.Enabled ~= false,
                tooltip = "Shows this window in the content picked above.",
                callback = function(checked) writeField("Enabled", checked) end,
                onHover = RowHover,
            })
            rowW:AddWidget(enChk, COL_ENABLE)
            manager:Register(enChk, "all")

            local typeDd = GUIFrame:CreateDropdown(rowW, "", {
                options = METER_TYPE_OPTIONS,
                value = cfg.MeterType or Enum.DamageMeterType.DamageDone,
                callback = function(key) writeField("MeterType", key) end,
                onHover = RowHover,
            })
            rowW:AddWidget(typeDd, COL_TYPE)
            manager:Register(typeDd, "all")

            local segDd = GUIFrame:CreateDropdown(rowW, "", {
                options = SEGMENT_OPTIONS,
                value = cfg.SessionType or Enum.DamageMeterSessionType.Current,
                tooltip = "Current is the fight in progress, or the last one. Overall adds up every fight " ..
                    "since the last reset.",
                callback = function(key) writeField("SessionType", key) end,
                onHover = RowHover,
            })
            rowW:AddWidget(segDd, COL_SEG)
            manager:Register(segDd, "all")

            cardDisplay:AddRow(rowW, isLast and Theme.rowHeightLast or Theme.rowHeight, isLast and 0 or nil)
        end
    end

    yOffset = cardDisplay:GetNextOffset()

    ----------------------------------------------------------------
    -- The settings link: the readout, the split labels, ranges and values
    -- and the map follow every dock layout, an in-world splitter drag included
    ----------------------------------------------------------------
    local function OnDockLayout()
        readout:ShowMeterSize(DM:GetDockContentSize())
        for i = 1, #splits do
            local split = splits[i]
            split.leftPx, split.rightPx = ReadSplitPx(split)
            -- A silent range or value under a thumb being dragged would make it
            -- jitter; that drag writes the share itself.
            local track = split.slider.slider
            local share
            if track and track:IsDraggingThumb() then
                share = split.slider:GetValue()
            else
                local lo, hi = RangeOf(split)
                split.slider:SetMinMaxValues(lo / 100, hi / 100, true)
                share = ShareOf(split) / 100
                split.slider:SetValue(share, true)
            end
            PaintSplit(split, share)
        end
        if schematic then schematic.Relayout() end
    end
    if schematic then
        schematic.SetHover(function(kind, frame, entering)
            local target
            if kind == "box" then
                target = Hover.targets[frame.winIdx]
            else
                target = Hover.gaps[Hover.GapKey(frame.kind, frame.c, frame.r)]
            end
            if target then Hover.Note(target, frame, entering) end
        end)
    end
    Hover.Begin(schematic)
    if DM.SetSettingsLink then
        DM:SetSettingsLink({ OnDockLayout = OnDockLayout, OnWindowHover = Hover.OnWindowHover })
    end
    windowsLinked = true
    OnDockLayout()

    return yOffset
end

---------------------------------------------------------------------------------
-- Appearance tab (global; applies to all windows uniformly)
---------------------------------------------------------------------------------
local function BuildAppearanceTab(scrollChild, yOffset, db, manager)
    local statusbarList = MediaList("statusbar", "Blizzard")
    local fontList = MediaList("font", "Friz Quadrata TT")

    -- Backdrop sub-widgets grayed when BackdropEnabled is off.
    manager:SetCondition("backdrop", function() return db.BackdropEnabled ~= false end)
    -- Line Thickness grayed unless Thin Line is on; the Custom fill-color picker grayed
    -- unless the Bar Color mode is Custom.
    manager:SetCondition("thinline", function() return db.BarThinLine == true end)
    manager:SetCondition("barcustomcolor", function() return db.BarColorMode == "Custom" end)

    ----------------------------------------------------------------
    -- Bars: texture, thin-line style and fill
    ----------------------------------------------------------------
    local cardBars = GUIFrame:CreateCard(scrollChild, "Bars", yOffset)
    manager:Register(cardBars, "all")

    local rowTex = GUIFrame:CreateRow(cardBars.content, Theme.rowHeight)
    local texDropdown = GUIFrame:CreateDropdown(rowTex, "Bar Texture", {
        options = statusbarList,
        value = db.StatusBarTexture or "KitnUI",
        callback = function(key) db.StatusBarTexture = key; ApplySettings() end,
        searchable = true,
    })
    rowTex:AddWidget(texDropdown, 1)
    manager:Register(texDropdown, "all")
    cardBars:AddRow(rowTex, Theme.rowHeight)

    -- Thin-line style: the colored fill becomes a thin strip pinned to the bottom edge.
    -- Line Thickness grays out when the toggle is off.
    local rowThin = GUIFrame:CreateRow(cardBars.content, Theme.rowHeight)
    local thinChk = GUIFrame:CreateCheckbox(rowThin, "Thin Line Bars", {
        value = db.BarThinLine == true,
        callback = function(checked)
            db.BarThinLine = checked
            ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    rowThin:AddWidget(thinChk, 0.5)
    manager:Register(thinChk, "all")

    local thinHSlider = GUIFrame:CreateSlider(rowThin, "Line Thickness", {
        min = 1, max = 12, step = 1,
        value = db.BarThinLineHeight or 2,
        callback = function(val) db.BarThinLineHeight = val; ApplySettings() end,
    })
    rowThin:AddWidget(thinHSlider, 0.5)
    manager:Register(thinHSlider, "thinline")
    cardBars:AddRow(rowThin, Theme.rowHeight)

    local rowFill = GUIFrame:CreateRow(cardBars.content, Theme.rowHeight)
    local fillModeDd = GUIFrame:CreateDropdown(rowFill, "Fill Color", {
        options = {
            { key = "Class",  text = "Class Color" },
            { key = "Custom", text = "Custom" },
            { key = "Theme",  text = "Theme" },
        },
        value = db.BarColorMode or "Class",
        callback = function(key)
            db.BarColorMode = key
            ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)   -- re-evaluate the Custom-color gray
        end,
    })
    rowFill:AddWidget(fillModeDd, 0.5)
    manager:Register(fillModeDd, "all")

    -- Custom fill color. The picker exposes opacity (hasOpacity); its alpha doubles as the
    -- fill opacity (kept in db.BarColorAlpha, in sync with the Fill Opacity slider below so
    -- both edit the same value). RGB is stored in db.BarColor.
    local fillColorPicker = GUIFrame:CreateColorPicker(rowFill, "Custom Color", {
        color = {
            (db.BarColor and db.BarColor[1]) or 0.30,
            (db.BarColor and db.BarColor[2]) or 0.55,
            (db.BarColor and db.BarColor[3]) or 0.85,
            db.BarColorAlpha or 1,
        },
        callback = function(r, g, b, a)
            db.BarColor = { r, g, b }
            db.BarColorAlpha = a
            ApplySettings()
        end,
    })
    rowFill:AddWidget(fillColorPicker, 0.5)
    manager:Register(fillColorPicker, "barcustomcolor")
    cardBars:AddRow(rowFill, Theme.rowHeight)

    -- Fill opacity applies to every fill mode, so it stays enabled even when the
    -- Custom picker is grayed.
    local rowOpacity = GUIFrame:CreateRow(cardBars.content, Theme.rowHeightLast)
    local opacitySlider = GUIFrame:CreateSlider(rowOpacity, "Fill Opacity", {
        min = 0, max = 1, step = 0.05, isPercent = true,
        value = db.BarColorAlpha or 1,
        callback = function(val) db.BarColorAlpha = val; ApplySettings() end,
    })
    rowOpacity:AddWidget(opacitySlider, 0.5)
    manager:Register(opacitySlider, "all")
    cardBars:AddRow(rowOpacity, Theme.rowHeightLast, 0)

    yOffset = cardBars:GetNextOffset()

    ----------------------------------------------------------------
    -- Bar Text: what each bar row reads, and its tooltip
    ----------------------------------------------------------------
    manager:SetCondition("hovertip", function() return db.HoverTooltip ~= false end)

    local cardText = GUIFrame:CreateCard(scrollChild, "Bar Text", yOffset)
    manager:Register(cardText, "all")

    local rowNames = GUIFrame:CreateRow(cardText.content, Theme.rowHeight)
    local nameChk = GUIFrame:CreateCheckbox(rowNames, "Show Player Names", {
        value = db.ShowName ~= false,
        callback = function(checked) db.ShowName = checked; ApplySettings() end,
    })
    rowNames:AddWidget(nameChk, 0.5)
    manager:Register(nameChk, "all")

    local realmChk = GUIFrame:CreateCheckbox(rowNames, "Show Realm Names", {
        value = db.ShowRealm == true,
        callback = function(checked) db.ShowRealm = checked; ApplySettings() end,
    })
    rowNames:AddWidget(realmChk, 0.5)
    manager:Register(realmChk, "all")
    cardText:AddRow(rowNames, Theme.rowHeight)

    local rowClass = GUIFrame:CreateRow(cardText.content, Theme.rowHeight)
    local classNameChk = GUIFrame:CreateCheckbox(rowClass, "Class Color Names", {
        value = db.ClassColorName == true,
        callback = function(checked) db.ClassColorName = checked; ApplySettings() end,
    })
    rowClass:AddWidget(classNameChk, 0.5)
    manager:Register(classNameChk, "all")

    local iconChk = GUIFrame:CreateCheckbox(rowClass, "Show Spec Icon", {
        value = db.ShowIcon ~= false,
        callback = function(checked) db.ShowIcon = checked; ApplySettings() end,
    })
    rowClass:AddWidget(iconChk, 0.5)
    manager:Register(iconChk, "all")
    cardText:AddRow(rowClass, Theme.rowHeight)

    local rowRank = GUIFrame:CreateRow(cardText.content, Theme.rowHeight)
    local rankChk = GUIFrame:CreateCheckbox(rowRank, "Show Rank Number", {
        value = db.ShowRank == true,
        callback = function(checked) db.ShowRank = checked; ApplySettings() end,
    })
    rowRank:AddWidget(rankChk, 0.5)
    manager:Register(rankChk, "all")

    local selfChk = GUIFrame:CreateCheckbox(rowRank, "Always Show Self", {
        value = db.AlwaysShowSelf ~= false,
        tooltip = "Pins your row to the last visible slot when you fall off-screen. Role-aware: damage views pin DPS and tanks, healing views pin healers; other views never pin.",
        callback = function(checked) db.AlwaysShowSelf = checked; ApplySettings() end,
    })
    rowRank:AddWidget(selfChk, 0.5)
    manager:Register(selfChk, "all")
    cardText:AddRow(rowRank, Theme.rowHeight)

    local rowNumbers = GUIFrame:CreateRow(cardText.content, Theme.rowHeight)
    local fmtDd = GUIFrame:CreateDropdown(rowNumbers, "Numbers", {
        options = {
            { key = "Both",   text = "Amount + DPS" },
            { key = "Amount", text = "Amount Only" },
            { key = "PerSec", text = "DPS Only" },
        },
        value = db.NumberFormat or "Both",
        callback = function(key) db.NumberFormat = key; ApplySettings() end,
    })
    rowNumbers:AddWidget(fmtDd, 0.5)
    manager:Register(fmtDd, "all")

    -- Bar text color (value column always; name column when NOT class-colored). Alpha is
    -- ignored -- bar text is always opaque -- so only RGB is stored.
    local textColorPicker = GUIFrame:CreateColorPicker(rowNumbers, "Text Color", {
        color = db.BarTextColor or { 1, 1, 1, 1 },
        callback = function(r, g, b) db.BarTextColor = { r, g, b }; ApplySettings() end,
    })
    rowNumbers:AddWidget(textColorPicker, 0.5)
    manager:Register(textColorPicker, "all")
    cardText:AddRow(rowNumbers, Theme.rowHeight)

    local rowTip = GUIFrame:CreateRow(cardText.content, Theme.rowHeightLast)
    local hoverTipChk = GUIFrame:CreateCheckbox(rowTip, "Tooltip on Mouseover", {
        value = db.HoverTooltip ~= false,
        tooltip = "Pointing at a bar shows that player's top spells, or the death recap in the Deaths view.",
        callback = function(checked)
            db.HoverTooltip = checked
            ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    rowTip:AddWidget(hoverTipChk, 0.5)
    manager:Register(hoverTipChk, "all")

    local hoverAnchorDd = GUIFrame:CreateDropdown(rowTip, "Tooltip Position", {
        options = {
            { key = "smart",  text = "Smart (auto side)" },
            { key = "bar",    text = "Above Bar" },
            { key = "left",   text = "Left of Meter" },
            { key = "right",  text = "Right of Meter" },
            { key = "center", text = "Screen Center" },
        },
        value = db.HoverTooltipAnchor or "smart",
        tooltip = "Where that tooltip opens. Smart picks the side away from the nearer screen edge.",
        callback = function(key) db.HoverTooltipAnchor = key; ApplySettings() end,
    })
    rowTip:AddWidget(hoverAnchorDd, 0.5)
    manager:Register(hoverAnchorDd, "hovertip")
    cardText:AddRow(rowTip, Theme.rowHeightLast, 0)

    yOffset = cardText:GetNextOffset()

    ----------------------------------------------------------------
    -- Header: the action buttons, the type icon, the clock and the title.
    -- "Only on Mouseover" governs the action buttons and grays when they're off.
    ----------------------------------------------------------------
    manager:SetCondition("headericons", function() return db.ShowHeaderIcons ~= false end)

    local cardHeader = GUIFrame:CreateCard(scrollChild, "Header", yOffset)
    manager:Register(cardHeader, "all")

    local rowHdr = GUIFrame:CreateRow(cardHeader.content, Theme.rowHeight)
    local headerIconsChk = GUIFrame:CreateCheckbox(rowHdr, "Show Action Buttons", {
        value = db.ShowHeaderIcons ~= false,
        tooltip = "The settings, reset, segment and report icons at the right end of each header.",
        callback = function(checked)
            db.ShowHeaderIcons = checked
            ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    rowHdr:AddWidget(headerIconsChk, 0.5)
    manager:Register(headerIconsChk, "all")

    local typeIconChk = GUIFrame:CreateCheckbox(rowHdr, "Show Type Icon", {
        value = db.ShowTypeIcon ~= false,
        tooltip = "The meter-type icon beside each window's title.",
        callback = function(checked) db.ShowTypeIcon = checked; ApplySettings() end,
    })
    rowHdr:AddWidget(typeIconChk, 0.5)
    manager:Register(typeIconChk, "all")
    cardHeader:AddRow(rowHdr, Theme.rowHeight)

    local rowHdr2 = GUIFrame:CreateRow(cardHeader.content, Theme.rowHeight)
    local headerMouseoverChk = GUIFrame:CreateCheckbox(rowHdr2, "Only on Mouseover", {
        value = db.HeaderIconsMouseover == true,
        tooltip = "Shows the header icons only while the mouse is on that header.",
        callback = function(checked) db.HeaderIconsMouseover = checked; ApplySettings() end,
    })
    rowHdr2:AddWidget(headerMouseoverChk, 0.5)
    manager:Register(headerMouseoverChk, "headericons")

    local clockChk = GUIFrame:CreateCheckbox(rowHdr2, "Combat Clock", {
        value = db.ShowCombatClock == true,
        tooltip = "Shows the fight length [M:SS] on window 1's header while in combat; freezes and dims at the final time when the fight ends. Sits in the action-button slot and steps aside while those icons are revealed.",
        callback = function(checked) db.ShowCombatClock = checked; ApplySettings() end,
    })
    rowHdr2:AddWidget(clockChk, 0.5)
    manager:Register(clockChk, "all")
    cardHeader:AddRow(rowHdr2, Theme.rowHeight)

    -- Header text and bar text size are independent sliders. HeaderFontSize falls back
    -- to FontSize when unset, so an existing config's header keeps its current size until
    -- this slider is moved; the bar rows always read FontSize.
    local rowHdr3 = GUIFrame:CreateRow(cardHeader.content, Theme.rowHeightLast)
    local headerThemeChk = GUIFrame:CreateCheckbox(rowHdr3, "Theme Color Header", {
        value = db.HeaderThemeColor == true,
        callback = function(checked) db.HeaderThemeColor = checked; ApplySettings() end,
    })
    rowHdr3:AddWidget(headerThemeChk, 0.5)
    manager:Register(headerThemeChk, "all")

    local headerSizeSlider = GUIFrame:CreateSlider(rowHdr3, "Header Text Size", {
        min = 8, max = 24, step = 1,
        value = db.HeaderFontSize or db.FontSize or 12,
        callback = function(val) db.HeaderFontSize = val; ApplySettings() end,
    })
    rowHdr3:AddWidget(headerSizeSlider, 0.5)
    manager:Register(headerSizeSlider, "all")
    cardHeader:AddRow(rowHdr3, Theme.rowHeightLast, 0)

    yOffset = cardHeader:GetNextOffset()

    ----------------------------------------------------------------
    -- Font
    ----------------------------------------------------------------
    local cardFont = GUIFrame:CreateCard(scrollChild, "Font", yOffset)
    manager:Register(cardFont, "all")

    local rowFont = GUIFrame:CreateRow(cardFont.content, Theme.rowHeight)
    local fontDropdown = GUIFrame:CreateDropdown(rowFont, "Font", {
        options = KE:AddFollowGlobalFont(fontList),
        value = db.FontFace or KE.FONT_FOLLOW_GLOBAL,
        callback = function(key) db.FontFace = KE:StoredFontFace(key); ApplySettings() end,
        searchable = true,
        isFontPreview = true,
    })
    rowFont:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "all")

    local outlineDropdown = GUIFrame:CreateDropdown(rowFont, "Font Outline", {
        options = KE:GetFontOutlineOptions(),
        value = KE:NormalizeFontOutline(db.FontOutline or "OUTLINE"),
        callback = function(key) db.FontOutline = key; ApplySettings() end,
    })
    rowFont:AddWidget(outlineDropdown, 0.5)
    manager:Register(outlineDropdown, "all")
    cardFont:AddRow(rowFont, Theme.rowHeight)

    local rowBarSize = GUIFrame:CreateRow(cardFont.content, Theme.rowHeightLast)
    local barSizeSlider = GUIFrame:CreateSlider(rowBarSize, "Bar Text Size", {
        min = 8, max = 24, step = 1,
        value = db.FontSize or 12,
        callback = function(val) db.FontSize = val; ApplySettings() end,
    })
    rowBarSize:AddWidget(barSizeSlider, 0.5)
    manager:Register(barSizeSlider, "all")
    cardFont:AddRow(rowBarSize, Theme.rowHeightLast, 0)

    yOffset = cardFont:GetNextOffset()

    ----------------------------------------------------------------
    -- Backdrop
    ----------------------------------------------------------------
    local cardBackdrop = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    manager:Register(cardBackdrop, "all")

    local rowBd1 = GUIFrame:CreateRow(cardBackdrop.content, Theme.rowHeight)
    local bgEnableChk = GUIFrame:CreateCheckbox(rowBd1, "Enable Backdrop", {
        value = db.BackdropEnabled ~= false,
        callback = function(checked)
            db.BackdropEnabled = checked
            ApplySettings()              -- re-pad windows + re-skin
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    rowBd1:AddWidget(bgEnableChk, 0.5)
    manager:Register(bgEnableChk, "all")

    -- A saved "accent" shows as Theme, which is what it draws; the saved value
    -- changes only when another style is picked.
    local borderStyle = db.BackdropBorderStyle or "neutral"
    if borderStyle == "accent" then borderStyle = "theme" end
    local styleDropdown = GUIFrame:CreateDropdown(rowBd1, "Border Style", {
        options = {
            { key = "neutral", text = "Neutral" },
            { key = "theme",   text = "Theme" },
        },
        value = borderStyle,
        tooltip = "Neutral uses the Border color below. Theme uses your theme color.",
        callback = function(key) db.BackdropBorderStyle = key; ApplyBackdropOnly() end,
    })
    rowBd1:AddWidget(styleDropdown, 0.5)
    manager:Register(styleDropdown, "backdrop")
    cardBackdrop:AddRow(rowBd1, Theme.rowHeight)

    local rowBd2 = GUIFrame:CreateRow(cardBackdrop.content, Theme.rowHeight)
    local bgColorPicker = GUIFrame:CreateColorPicker(rowBd2, "Background", {
        color = db.BackdropColor or { 0.031, 0.031, 0.031, 0.8 },
        callback = function(r, g, b, a) db.BackdropColor = { r, g, b, a }; ApplyBackdropOnly() end,
    })
    rowBd2:AddWidget(bgColorPicker, 0.5)
    manager:Register(bgColorPicker, "backdrop")

    local borderColorPicker = GUIFrame:CreateColorPicker(rowBd2, "Border", {
        color = db.BackdropBorderColor or { 0, 0, 0, 1 },
        callback = function(r, g, b, a) db.BackdropBorderColor = { r, g, b, a }; ApplyBackdropOnly() end,
    })
    rowBd2:AddWidget(borderColorPicker, 0.5)
    manager:Register(borderColorPicker, "backdrop")
    cardBackdrop:AddRow(rowBd2, Theme.rowHeight)

    -- Behind Bars Only wraps only the bar rows: it drops the backdrop off the
    -- header band so the title floats above it.
    local rowBd3 = GUIFrame:CreateRow(cardBackdrop.content, Theme.rowHeightLast)
    local padSlider = GUIFrame:CreateSlider(rowBd3, "Padding", {
        min = 0, max = 20, step = 1,
        value = db.BackdropPadding or 1,
        callback = function(val) db.BackdropPadding = val; ApplySettings() end,
    })
    rowBd3:AddWidget(padSlider, 0.5)
    manager:Register(padSlider, "backdrop")

    local behindBarsChk = GUIFrame:CreateCheckbox(rowBd3, "Behind Bars Only", {
        value = db.BackdropBehindBarsOnly == true,
        callback = function(checked) db.BackdropBehindBarsOnly = checked; ApplyBackdropOnly() end,
    })
    rowBd3:AddWidget(behindBarsChk, 0.5)
    manager:Register(behindBarsChk, "backdrop")
    cardBackdrop:AddRow(rowBd3, Theme.rowHeightLast, 0)

    yOffset = cardBackdrop:GetNextOffset()
    return yOffset
end

---------------------------------------------------------------------------------
-- Behavior tab
---------------------------------------------------------------------------------
local function BuildBehaviorTab(scrollChild, yOffset, db, manager)
    local DM = GetDM()

    ----------------------------------------------------------------
    -- Visibility (conditional show / hide)
    ----------------------------------------------------------------
    local cardVis = GUIFrame:CreateCard(scrollChild, "Visibility", yOffset)
    manager:Register(cardVis, "all")

    local rowVis = GUIFrame:CreateRow(cardVis.content, Theme.rowHeight)
    local oocChk = GUIFrame:CreateCheckbox(rowVis, "Hide Out of Combat", {
        value = db.HideOutOfCombat == true,
        tooltip = "Shows the meter only while you or your group are in combat. With Only in Instances " ..
            "also on, both must be true.",
        callback = function(checked)
            db.HideOutOfCombat = checked
            -- Re-evaluate now; while this panel is open the preview override keeps the
            -- meter visible, so the hide takes visible effect when the GUI closes.
            if DM and DM.UpdateBackdrop then DM:UpdateBackdrop() end
        end,
    })
    rowVis:AddWidget(oocChk, 0.5)
    manager:Register(oocChk, "all")

    local instChk = GUIFrame:CreateCheckbox(rowVis, "Only in Instances", {
        value = db.OnlyInInstances == true,
        tooltip = "Shows the meter only inside a dungeon, raid, arena, battleground or scenario. With " ..
            "Hide Out of Combat also on, both must be true.",
        callback = function(checked)
            db.OnlyInInstances = checked
            if DM and DM.UpdateBackdrop then DM:UpdateBackdrop() end
        end,
    })
    rowVis:AddWidget(instChk, 0.5)
    manager:Register(instChk, "all")
    cardVis:AddRow(rowVis, Theme.rowHeight)
    cardVis:AddNote("Always shown while these settings or " .. KE:ColorTextByTheme("/kes edit") .. " are open.")

    yOffset = cardVis:GetNextOffset()

    ----------------------------------------------------------------
    -- Segments (session data lifecycle)
    ----------------------------------------------------------------
    local cardSeg = GUIFrame:CreateCard(scrollChild, "Segments", yOffset)
    manager:Register(cardSeg, "all")

    local rowSeg = GUIFrame:CreateRow(cardSeg.content, Theme.rowHeight)
    local keyResetChk = GUIFrame:CreateCheckbox(rowSeg, "Reset on Key Start", {
        value = db.ResetOnKeyStart ~= false,
        tooltip = "Clears every segment when a keystone starts, so Overall covers just that run. Off, " ..
            "history and Overall run across keys until /kes dm reset or the header reset button.",
        callback = function(checked) db.ResetOnKeyStart = checked end,
    })
    rowSeg:AddWidget(keyResetChk, 0.5)
    manager:Register(keyResetChk, "all")

    local logoutResetChk = GUIFrame:CreateCheckbox(rowSeg, "Reset on Logout", {
        value = db.ResetOnLogout == true,
        tooltip = "Clears the meter the next time you log in. A /reload keeps it.",
        callback = function(checked) db.ResetOnLogout = checked end,
    })
    rowSeg:AddWidget(logoutResetChk, 0.5)
    manager:Register(logoutResetChk, "all")
    cardSeg:AddRow(rowSeg, Theme.rowHeight)

    manager:SetCondition("instancereset", function() return db.ResetOnInstanceEntry == true end)
    local rowInst = GUIFrame:CreateRow(cardSeg.content, Theme.rowHeight)
    local instResetChk = GUIFrame:CreateCheckbox(rowInst, "Reset on Instance Entry", {
        value = db.ResetOnInstanceEntry == true,
        tooltip = "Clears the meter when you enter a different dungeon, raid, scenario or Delve, or a " ..
            "different difficulty. Running back after a death, a login or a /reload is not an entry. " ..
            "Key history is kept.",
        callback = function(checked)
            db.ResetOnInstanceEntry = checked
            if not checked and DM and DM.CloseInstancePrompt then DM:CloseInstancePrompt() end
            if DM and DM.UpdateInstanceEntryEvents then DM:UpdateInstanceEntryEvents() end
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    rowInst:AddWidget(instResetChk, 0.5)
    manager:Register(instResetChk, "all")

    local instModeDd = GUIFrame:CreateDropdown(rowInst, "Mode", {
        options = {
            { key = "auto", text = "Auto" },
            { key = "ask",  text = "Ask" },
        },
        value = db.InstanceResetMode == "auto" and "auto" or "ask",
        tooltip = "Ask shows a prompt before clearing; Auto clears at once.",
        callback = function(key) db.InstanceResetMode = key end,
    })
    rowInst:AddWidget(instModeDd, 0.5)
    manager:Register(instModeDd, "instancereset")
    cardSeg:AddRow(rowInst, Theme.rowHeight)

    local rowRetain = GUIFrame:CreateRow(cardSeg.content, Theme.rowHeight)
    -- Display-only clamp mirroring History.lua evictOverCap's read semantics exactly
    -- (non-number -> 5; <1 -> 1; >5 -> 5): a legacy profile can hold a materialized
    -- HistoryRetain = 10 (old slider max) or 20, which evictOverCap clamps to an
    -- EFFECTIVE 5 at capture time. Falling back to 5 here (instead of clamping)
    -- would desync if the mirror ever diverges. No SV write, no migration -- the
    -- stored value is untouched.
    local retainDisplay = db.HistoryRetain
    if type(retainDisplay) ~= "number" then
        retainDisplay = 5
    elseif retainDisplay < 1 then
        retainDisplay = 1
    elseif retainDisplay > 5 then
        retainDisplay = 5
    end
    local retainSlider = GUIFrame:CreateSlider(rowRetain, "Key History (keys kept)", {
        min = 1, max = 5, step = 1,
        value = retainDisplay,
        tooltip = "With Reset on Key Start on, this many past keys stay in the segment menu. Each keeps " ..
            "full detail for its Run Summary or newest pull, and totals for its other pulls.",
        callback = function(v) db.HistoryRetain = v end,
    })
    rowRetain:AddWidget(retainSlider, 1)
    manager:Register(retainSlider, "all")
    cardSeg:AddRow(rowRetain, Theme.rowHeight)
    cardSeg:AddNote("Kept keys stay in the segment menu until a reload or a reset.")

    yOffset = cardSeg:GetNextOffset()

    ----------------------------------------------------------------
    -- Performance
    ----------------------------------------------------------------
    local cardPerf = GUIFrame:CreateCard(scrollChild, "Performance", yOffset)
    manager:Register(cardPerf, "all")

    local rowPerf = GUIFrame:CreateRow(cardPerf.content, Theme.rowHeightLast)
    local refreshSlider = GUIFrame:CreateSlider(rowPerf, "Combat Refresh", {
        min = 0.1, max = 1.0, step = 0.05,
        value = db.RefreshRate or 0.5,
        tooltip = "How often the bars repaint in combat, in seconds. Lower is smoother and uses more CPU.",
        callback = function(val)
            db.RefreshRate = val
            -- Apply live: restart the ticker only if it's currently running.
            if DM and DM._ticker and DM.StartTicker then DM:StartTicker() end
        end,
    })
    rowPerf:AddWidget(refreshSlider, 0.5)
    manager:Register(refreshSlider, "all")

    local budgetSlider = GUIFrame:CreateSlider(rowPerf, "UI Budget (ms)", {
        min = 0.5, max = 5.0, step = 0.1,
        value = db.UIBudgetMs or 1.2,
        tooltip = "The most time per frame, in milliseconds, spent painting bars. Windows over the " ..
            "budget wait for the next frame.",
        callback = function(val) db.UIBudgetMs = val end,
    })
    rowPerf:AddWidget(budgetSlider, 0.5)
    manager:Register(budgetSlider, "all")
    cardPerf:AddRow(rowPerf, Theme.rowHeightLast, 0)

    yOffset = cardPerf:GetNextOffset()
    return yOffset
end

---------------------------------------------------------------------------------
-- Spell History tab
---------------------------------------------------------------------------------
local function BuildSpellHistoryTab(scrollChild, yOffset, db, manager)
    local DM = GetDM()
    local sh = db.SpellHistory
    if not sh then return yOffset end

    local function ApplyStrip()
        if DM and DM.ApplySpellHistory then DM:ApplySpellHistory() end
    end

    -- A resize can rewrite the saved offsets; the sliders are re-read in place
    -- because a page rebuild would drop the slider being dragged.
    local posCard
    local function ResizeStrip(key, value)
        if DM and DM.ResizeSpellHistory then
            DM:ResizeSpellHistory(key, value)
        else
            sh[key] = value
        end
        if posCard then posCard:RefreshOffsets() end
    end

    -- Edge and Gap apply only while attached; the Position card only while free.
    manager:SetCondition("shattached", function() return sh.Attach == true end)
    manager:SetCondition("shfree", function() return sh.Attach ~= true end)

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Spell History", yOffset)
    manager:Register(card1, "all")
    card1:AddHeaderToggle(sh.Enabled == true, function(checked)
        sh.Enabled = checked
        ApplyStrip()
    end)

    card1:AddLabel("Shows your recent casts as a row of icons, newest first, while the Damage " ..
        "Meter shows. Your spellbook spells and racials always show; the checkboxes below add " ..
        "the rest.")

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled feature shows its switch and nothing else.
    if sh.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Casts
    ----------------------------------------------------------------
    local cardCasts = GUIFrame:CreateCard(scrollChild, "Casts", yOffset)
    manager:Register(cardCasts, "all")

    manager:RegisterGroup(cardCasts:AddCheckboxGrid({
        {
            label = "Include Items and Toys",
            config = {
                value = sh.IncludeItems ~= false,
                tooltip = "Potions, trinkets and other items used from your bags or equipped gear, plus " ..
                    "toys and other abilities you press that are outside your spellbook.",
                callback = function(checked) sh.IncludeItems = checked; ApplyStrip() end,
            },
        },
        {
            label = "Include Pet Spells",
            config = {
                value = sh.IncludePet ~= false,
                tooltip = "Your pet's spells, with a green border. Spells left on autocast do not show.",
                callback = function(checked) sh.IncludePet = checked; ApplyStrip() end,
            },
        },
        {
            label = "Show Failed Casts",
            config = {
                value = sh.ShowFailed ~= false,
                tooltip = "Casts interrupted or failed after they started, grayed with a red X. Instant " ..
                    "presses that fail do not show.",
                callback = function(checked) sh.ShowFailed = checked; ApplyStrip() end,
            },
        },
    }), "all")
    cardCasts:AddNote("Effects the game casts for you without a press never show.")

    yOffset = cardCasts:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Icons
    ----------------------------------------------------------------
    local cardIcons = GUIFrame:CreateCard(scrollChild, "Icons", yOffset)
    manager:Register(cardIcons, "all")

    local rowCount = GUIFrame:CreateRow(cardIcons.content, Theme.rowHeight)
    local countSlider = GUIFrame:CreateSlider(rowCount, "Icon Count", {
        min = 1, max = 10, step = 1,
        value = sh.Count or 5,
        callback = function(val) ResizeStrip("Count", val) end,
    })
    rowCount:AddWidget(countSlider, 1)
    manager:Register(countSlider, "all")
    cardIcons:AddRow(rowCount, Theme.rowHeight)

    local rowSize = GUIFrame:CreateRow(cardIcons.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(rowSize, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = sh.IconSize or 32,
        callback = function(val) ResizeStrip("IconSize", val) end,
    })
    rowSize:AddWidget(sizeSlider, 1)
    manager:Register(sizeSlider, "all")
    cardIcons:AddRow(rowSize, Theme.rowHeight)

    local rowSpacing = GUIFrame:CreateRow(cardIcons.content, Theme.rowHeightLast)
    local spacingSlider = GUIFrame:CreateSlider(rowSpacing, "Spacing", {
        min = -1, max = 10, step = 1,
        value = sh.Spacing or 2,
        callback = function(val) ResizeStrip("Spacing", val) end,
    })
    rowSpacing:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")

    -- Attached, the direction that grows into the meter is not offered, and
    -- the value shown is the outside reading; a strip that sits inside the
    -- meter steps that way into it instead.
    local effectiveGrow = DM and DM.SpellHistoryEffectiveGrow
    local growOptions = {}
    for _, option in ipairs(GUIFrame.GrowDirectionOptions) do
        if not effectiveGrow or effectiveGrow(sh.Attach, sh.AttachEdge, option.key) == option.key then
            growOptions[#growOptions + 1] = option
        end
    end
    local growValue = sh.Grow or "LEFT"
    if effectiveGrow then growValue = effectiveGrow(sh.Attach, sh.AttachEdge, growValue) end
    local growDd = GUIFrame:CreateDropdown(rowSpacing, "Grow Direction", {
        options = growOptions,
        value = growValue,
        callback = function(key) sh.Grow = key; ApplyStrip() end,
    })
    rowSpacing:AddWidget(growDd, 0.5)
    manager:Register(growDd, "all")
    cardIcons:AddRow(rowSpacing, Theme.rowHeightLast, 0)

    yOffset = cardIcons:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Fade
    ----------------------------------------------------------------
    local cardFade = GUIFrame:CreateCard(scrollChild, "Fade", yOffset)
    manager:Register(cardFade, "all")

    local rowFade = GUIFrame:CreateRow(cardFade.content, Theme.rowHeight)
    local fadeSlider = GUIFrame:CreateSlider(rowFade, "Fade Delay (s)", {
        min = 0, max = 30, step = 1,
        value = sh.FadeDelay or 5,
        callback = function(val) sh.FadeDelay = val; ApplyStrip() end,
    })
    rowFade:AddWidget(fadeSlider, 1)
    manager:Register(fadeSlider, "all")
    cardFade:AddRow(rowFade, Theme.rowHeight)

    local rowMode = GUIFrame:CreateRow(cardFade.content, Theme.rowHeight)
    local modeDd = GUIFrame:CreateDropdown(rowMode, "Fade Mode", {
        options = {
            { key = "ICON",  text = "Per Icon" },
            { key = "STRIP", text = "Whole Strip" },
        },
        value = sh.FadeMode == "ICON" and "ICON" or "STRIP",
        callback = function(key) sh.FadeMode = key; ApplyStrip() end,
    })
    rowMode:AddWidget(modeDd, 0.5)
    manager:Register(modeDd, "all")

    local holdChk = GUIFrame:CreateCheckbox(rowMode, "Hold in Combat", {
        value = sh.HoldInCombat ~= false,
        callback = function(checked) sh.HoldInCombat = checked; ApplyStrip() end,
    })
    rowMode:AddWidget(holdChk, 0.5)
    manager:Register(holdChk, "all")
    cardFade:AddRow(rowMode, Theme.rowHeight)
    cardFade:AddNote("0 never fades: icons stay until newer casts push them out.")

    yOffset = cardFade:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Placement
    ----------------------------------------------------------------
    local cardPlace = GUIFrame:CreateCard(scrollChild, "Placement", yOffset)
    manager:Register(cardPlace, "all")

    local rowAttach = GUIFrame:CreateRow(cardPlace.content, Theme.rowHeight)
    local attachChk = GUIFrame:CreateCheckbox(rowAttach, "Attach to Meter", {
        value = sh.Attach == true,
        callback = function(checked)
            sh.Attach = checked
            ApplyStrip()
            manager:UpdateAll(db.Enabled ~= false)
            -- A frame late, so the Grow options follow and this widget is not
            -- torn down mid-call.
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end,
    })
    rowAttach:AddWidget(attachChk, 1)
    manager:Register(attachChk, "all")
    cardPlace:AddRow(rowAttach, Theme.rowHeight)

    local rowEdge = GUIFrame:CreateRow(cardPlace.content, Theme.rowHeight)
    local edgeDd = GUIFrame:CreateDropdown(rowEdge, "Edge", {
        options = {
            { key = "TOP",    text = "Top" },
            { key = "BOTTOM", text = "Bottom" },
            { key = "LEFT",   text = "Left" },
            { key = "RIGHT",  text = "Right" },
        },
        value = sh.AttachEdge or "TOP",
        callback = function(key)
            sh.AttachEdge = key
            ApplyStrip()
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end,
    })
    rowEdge:AddWidget(edgeDd, 0.5)
    manager:Register(edgeDd, "shattached")

    local gapSlider = GUIFrame:CreateSlider(rowEdge, "Gap", {
        min = 0, max = 20, step = 1,
        value = sh.AttachGap or 2,
        callback = function(val) sh.AttachGap = val; ApplyStrip() end,
    })
    rowEdge:AddWidget(gapSlider, 0.5)
    manager:Register(gapSlider, "shattached")
    cardPlace:AddRow(rowEdge, Theme.rowHeight)
    cardPlace:AddNote("Free, the strip moves in " .. KE:ColorTextByTheme("/kes edit") ..
        "; attached, it follows the meter. For any other spot, such as inside the meter, turn Attach " ..
        "off and use Anchored To in Position Settings.")

    yOffset = cardPlace:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Position Settings (free-standing only)
    ----------------------------------------------------------------
    local posOffset
    posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = sh,
        positionKey = "Position",
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplyStrip,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "shfree")
    end
    manager:Register(posCard, "shfree")
    yOffset = posOffset

    return yOffset
end

---------------------------------------------------------------------------------
-- Settings link teardown
---------------------------------------------------------------------------------
-- The Windows tab links itself to the meter on every build. Every rebuild (a tab
-- switch included), a page switch and closing the window end that link, which
-- puts every meter window back to full opacity.
local function ClearSettingsLink()
    local wasLinked = windowsLinked
    windowsLinked = false
    local DM = GetDM()
    if DM and DM.SetSettingsLink then DM:SetSettingsLink(nil) end
    Hover.Clear()
    -- GUIFrame:Show puts back the hidden page without building it, which would
    -- leave the tab unlinked. A refresh asked for while hidden is held and run
    -- by the next Show, so the tab builds and links again.
    if wasLinked and not GUIFrame:IsShown() then GUIFrame:RefreshContent() end
end

GUIFrame:RegisterContentRebuildCallback("dm:settingslink", ClearSettingsLink)
GUIFrame:RegisterContentCleanup("dm:settingslink", ClearSettingsLink)

---------------------------------------------------------------------------------
-- Page registration: the switch and description above four tabs
---------------------------------------------------------------------------------
-- Each tab reads its own db and makes its own manager. The host builds a tab
-- only while the module is on, so no manager spans two builders.
local function TabPage(builder)
    return function(scrollChild, yOffset)
        local db = KE.db and KE.db.profile.DamageMeter
        if not db then return yOffset end
        local manager = GUIFrame:CreateWidgetStateManager()
        yOffset = builder(scrollChild, yOffset, db, manager)
        manager:UpdateAll(db.Enabled ~= false)
        return yOffset
    end
end

GUIFrame:RegisterContent(TAB_WINDOWS, TabPage(BuildWindowsTab))
GUIFrame:RegisterContent(TAB_APPEARANCE, TabPage(BuildAppearanceTab))
GUIFrame:RegisterContent(TAB_BEHAVIOR, TabPage(BuildBehaviorTab))
GUIFrame:RegisterContent(TAB_SPELLHISTORY, TabPage(BuildSpellHistoryTab))

GUIFrame:RegisterTabbedContent(PAGE_ID, {
    { id = TAB_WINDOWS,      label = "Windows" },
    { id = TAB_APPEARANCE,   label = "Appearance" },
    { id = TAB_BEHAVIOR,     label = "Behavior" },
    { id = TAB_SPELLHISTORY, label = "Spell History" },
}, {
    headerBuilder = BuildHeader,
})
