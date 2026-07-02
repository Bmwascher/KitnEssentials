-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DamageMeter.lua                                     ║
-- ║  GUI: Damage Meter                                       ║
-- ║  Purpose: Configuration panel for the DamageMeter module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local pairs = pairs
local CreateFrame = CreateFrame
local math_max = math.max
local math_floor = math.floor

local activeTab = "General"

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

local ARRANGEMENT_OPTIONS = {
    { key = "Horizontal", text = "Horizontal" },
    { key = "Vertical",   text = "Vertical" },
    { key = "Custom",     text = "Custom" },
}

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

-- Schedules a full page rebuild on the next frame (used by the Windows tab's
-- Configure-For context switches and arrangement changes that change which
-- widgets appear). Defined here; first consumed when the Windows tab lands.
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

---------------------------------------------------------------------------------
-- General tab
---------------------------------------------------------------------------------
local function BuildGeneralTab(scrollChild, yOffset, db, manager)
    local DM = GetDM()

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("DamageMeter", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("DamageMeter")
        else
            KitnEssentials:DisableModule("DamageMeter")
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Damage Meter", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Damage Meter", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            manager:UpdateAll(db.Enabled ~= false)
        end,
        msgPopup = true,
        msgText = "Damage Meter",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 0.5)

    -- Lock Dock lives on the Enable row (far right) -- it's a tightly-coupled
    -- behavior toggle, not worth its own card. Greyed with the module (group "all").
    local lockCheck = GUIFrame:CreateCheckbox(row1a, "Lock Dock", {
        value = db.Locked == true,
        callback = function(checked)
            db.Locked = checked
            if DM and DM.ApplyLockState then DM:ApplyLockState() end
        end,
    })
    row1a:AddWidget(lockCheck, 0.5)
    manager:Register(lockCheck, "all")
    card1:AddRow(row1a, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 68)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " In-client meter on Blizzard's 12.0 data; replaces the built-in meter automatically while enabled.\n" ..
        KE:ColorTextByTheme("-") .. " Switch type/segment on the meter itself; the GUI sets defaults & look.",
        68, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 68, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings (the dock is the positioned frame)
    -- Position immediately follows Enable per the canonical card order.
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
        showAnchorFrameType = false,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Tip
    ----------------------------------------------------------------
    -- Three bullets, the first wraps -> ~4 body lines. The CreateText body is
    -- anchored title->bottom, so it gets (rowH - title - spacer); 92 gives ~4.5 body
    -- lines of headroom (was 76 for two bullets before the report line was added).
    local dragNoteCard = GUIFrame:CreateCard(scrollChild, "Tip", yOffset)
    manager:Register(dragNoteCard, "all")
    local dnRow = GUIFrame:CreateRow(dragNoteCard.content, 92)
    local dnText = GUIFrame:CreateText(dnRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Drag the dock in " .. KE:ColorTextByTheme("/kes edit") ..
        " (disabled while locked). Resize panes by dragging the gaps between windows.\n" ..
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("/kes dm") ..
        " toggles the dock; " .. KE:ColorTextByTheme("/kes dm reset") .. " clears all segments.\n" ..
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("/kes dm report") ..
        " posts the primary window to chat (out of combat).",
        92, "hide")
    dnRow:AddWidget(dnText, 1)
    manager:Register(dnText, "all")
    dragNoteCard:AddRow(dnRow, 92, 0)
    yOffset = dragNoteCard:GetNextOffset()

    return yOffset
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
    g:SetBackdropColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.9)
    g:SetBackdropBorderColor(1, 1, 1, 1)
    g.text = g:CreateFontString(nil, "OVERLAY")
    g.text:SetPoint("CENTER")
    KE:ApplyThemeFont(g.text, "large")
    g.text:SetTextColor(1, 1, 1, 1)
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

-- Builds the layout-map schematic: one box per window, positioned proportionally
-- to mirror the in-world dock (columns left->right, stacked rows top->bottom),
-- each stamped with its on-screen display number (posOf) + the FULL panel label
-- (fullLabel(idx), matching the in-world header exactly -- e.g. "Overall Damage
-- Done"). Returns a container frame the caller AddRow's into the card. Boxes are
-- positioned in the container's OnSizeChanged (its width isn't known until AddRow
-- anchors it). The map is the ONLY arranging surface: drag a box onto another box's
-- CENTER to stack/reorder (a horizontal line shows the row gap it lands in), or drag
-- to a column's SIDE / off the map edge to peel it into its own new column (a
-- vertical line shows the column boundary it lands at). A cursor-following ghost
-- shows what you grabbed throughout.
local function BuildSchematic(card, height, cols, posOf, fullLabel)
    local T = Theme
    local container = CreateFrame("Frame", nil, card.content)
    container:SetHeight(height)

    local boxAt = {}    -- boxAt[c][r] = box frame
    local allBoxes = {} -- flat list for drag hit-testing + highlight

    -- Insertion line: a bright theme-accent bar shown where the dragged window will
    -- land -- horizontal in a row gap (stack: top of the hovered box = before, bottom
    -- = after) or vertical at a column boundary (new column). Accent (not white) so it
    -- pops against the dark gaps; the hovered box's WHITE border stays the distinct
    -- "this is the target column" cue during a stack drag.
    local dropLine = container:CreateTexture(nil, "OVERLAY")
    dropLine:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    dropLine:SetHeight(3)
    dropLine:Hide()

    -- Restore every box's resting accent border (clears any drag highlight).
    local function ResetBorders()
        for _, b in ipairs(allBoxes) do
            b:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
        end
    end

    -- Representative SURVIVING window of column c (the first window that isn't the
    -- one being dragged) -- nil if c is out of range or holds ONLY the dragged window
    -- (that column is dropped on release, so it can't anchor a new-column insert).
    -- Lets a new-column drop be identified in a way that survives the dragged
    -- window's own removal (the backend re-finds the anchor post-removal).
    local function repOf(c, dragWin)
        if c < 1 or c > #cols then return nil end
        local wins = cols[c] and cols[c].Windows
        if not wins then return nil end
        for r = 1, #wins do
            if wins[r] ~= dragWin then return wins[r] end
        end
        return nil
    end

    -- Parks the insertion line VERTICAL at content-x lineX (a column boundary),
    -- spanning the map's full height. Defined once (captures dropLine/container/
    -- height) so the per-frame DragUpdate allocates no closure while dragging.
    local function showColLine(lineX)
        dropLine:ClearAllPoints()
        dropLine:SetSize(3, height)
        dropLine:SetPoint("TOPLEFT", container, "TOPLEFT", lineX - 1.5, 0)
        dropLine:Show()
    end

    -- Per-frame drag feedback (attached as the container OnUpdate only while a box is
    -- being dragged). Moves the ghost to the cursor, then resolves ONE drop from the
    -- cursor's x-zone over the map:
    --   * CENTER of a column      -> STACK: a horizontal line shows the row gap it
    --                                lands in (above the hovered box, or below when
    --                                the cursor is in its lower half).
    --   * SIDE of a column / off  -> NEW COLUMN: a vertical line shows the column
    --     the map edge               boundary; the left/right anchor windows are
    --                                stashed so the insert survives idx's removal.
    -- The chosen drop (_dropMode + anchors) is stashed on the container for
    -- OnDragStop. No valid target -> everything clears (a drop there is a no-op).
    local function DragUpdate()
        local dragWin = container._dragWin
        if not dragWin then return end

        -- Ghost follows the cursor (UIParent space).
        local ghost = GetSchematicGhost()
        local us = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (mx / us) + 16, (my / us) - 14)

        ResetBorders()
        container._dropMode = nil
        container._dropAnchor = nil
        container._dropAfter = nil
        container._dropLeftRep = nil
        container._dropRightRep = nil

        -- Boxes share the container's effective scale; one division covers all.
        local cs = container:GetEffectiveScale()
        if cs <= 0 then cs = 1 end
        local cx, cy = mx / cs, my / cs
        local cLeft = container:GetLeft()
        if not cLeft then dropLine:Hide() return end

        -- Which column is the cursor over (by x)? Boxes in a column share its x-span,
        -- so the first box of each column gives the column's left/right edges.
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
            -- Off the left/right edge of the map -> new column at that end.
            local cRight = container:GetRight()
            if cRight and cx > cRight then
                container._dropMode = "newcol"
                -- `or repOf(#cols - 1)` covers the dragged window being SOLO in the
                -- outermost column (that column drops on release): the next-innermost
                -- column anchors the insert so the new column still lands at this end
                -- instead of defaulting to the opposite side.
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

        -- Zone within the hovered column: outer quarters -> new column on that side;
        -- middle half -> stack into the column.
        local frac = (cx - colL) / math_max(1, colR - colL)
        if frac <= 0.25 then
            container._dropMode = "newcol"
            -- `or repOf(hoverCol + 1)` covers the dragged window being SOLO in hoverCol
            -- (hoverCol drops on release): the column to its right anchors the insert,
            -- so a left-edge drop on column 1 still lands leftmost rather than defaulting
            -- to the far right.
            container._dropLeftRep = repOf(hoverCol - 1, dragWin)
            container._dropRightRep = repOf(hoverCol, dragWin) or repOf(hoverCol + 1, dragWin)
            showColLine(colL - cLeft)
        elseif frac >= 0.75 then
            container._dropMode = "newcol"
            container._dropLeftRep = repOf(hoverCol, dragWin) or repOf(hoverCol - 1, dragWin)
            container._dropRightRep = repOf(hoverCol + 1, dragWin)
            showColLine(colR - cLeft)
        else
            -- Center zone: stack into the hovered column. Find the box under cy.
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

    for c = 1, #cols do
        local wins = cols[c].Windows or {}
        boxAt[c] = {}
        for r = 1, #wins do
            local idx = wins[r]
            local box = CreateFrame("Frame", nil, container, "BackdropTemplate")
            box:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            box:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
            box:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.9)

            local num = box:CreateFontString(nil, "OVERLAY")
            KE:ApplyThemeFont(num, "large")
            num:SetPoint("CENTER", box, "CENTER", 0, 5)
            num:SetText(tostring(posOf[idx] or "?"))
            num:SetTextColor(1, 1, 1, 1)
            box.num = num

            -- Full panel label tucked directly UNDER the number (not pinned to the box
            -- bottom) so it stays close to the number and still shows in a short box;
            -- wrapped so long names like "Overall Damage Done" stay readable in tall boxes.
            local tlabel = box:CreateFontString(nil, "OVERLAY")
            KE:ApplyThemeFont(tlabel, "small")
            tlabel:SetPoint("TOP", num, "BOTTOM", 0, -1)
            tlabel:SetPoint("LEFT", box, "LEFT", 2, 0)
            tlabel:SetPoint("RIGHT", box, "RIGHT", -2, 0)
            tlabel:SetJustifyH("CENTER")
            tlabel:SetWordWrap(true)
            tlabel:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
            tlabel:SetText((fullLabel and fullLabel(idx)) or "")
            box.tlabel = tlabel

            -- Drag-to-rearrange: a cursor-following ghost shows what you grabbed and
            -- the insertion line shows where it lands; on release the dragged window
            -- drops at that spot -- either STACKED next to the hovered box
            -- (DM:MoveWindowToSlot) or peeled into a NEW COLUMN at the previewed
            -- boundary (DM:MoveWindowToNewColumn). DragUpdate decides which.
            box.winIdx = idx
            box:EnableMouse(true)
            box:RegisterForDrag("LeftButton")
            box:SetScript("OnDragStart", function(self2)
                container._dragWin = self2.winIdx
                container._dropMode = nil
                container._dropAnchor = nil
                container._dropAfter = nil
                container._dropLeftRep = nil
                container._dropRightRep = nil
                self2:SetAlpha(0.4)
                local ghost = GetSchematicGhost()
                local label = tostring(posOf[self2.winIdx] or "?")
                local nm = fullLabel and fullLabel(self2.winIdx)
                if nm and nm ~= "" then label = label .. "  " .. nm end
                ghost.text:SetText(label)
                ghost:SetWidth(math_max(60, ghost.text:GetStringWidth() + 18))
                ghost:Show()
                container:SetScript("OnUpdate", DragUpdate)
                DragUpdate()  -- position immediately, before the first frame tick
            end)
            box:SetScript("OnDragStop", function(self2)
                container:SetScript("OnUpdate", nil)
                self2:SetAlpha(1)
                GetSchematicGhost():Hide()
                dropLine:Hide()
                ResetBorders()
                local dragWin = container._dragWin
                local mode = container._dropMode
                local anchor = container._dropAnchor
                local after = container._dropAfter
                local leftRep = container._dropLeftRep
                local rightRep = container._dropRightRep
                container._dragWin = nil
                container._dropMode = nil
                container._dropAnchor = nil
                container._dropAfter = nil
                container._dropLeftRep = nil
                container._dropRightRep = nil
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

            boxAt[c][r] = box
            allBoxes[#allBoxes + 1] = box
        end
    end

    local function layout(width)
        if not width or width <= 0 then return end
        local GAP = 4
        local sumW = 0
        for c = 1, #cols do sumW = sumW + ((cols[c].WidthRatio) or 1) end
        if sumW <= 0 then sumW = math_max(1, #cols) end
        local availW = width - GAP * math_max(0, #cols - 1)
        if availW <= 0 then availW = width end
        local runX = 0
        for c = 1, #cols do
            local colW = availW * (((cols[c].WidthRatio) or 1) / sumW)
            local wins = cols[c].Windows or {}
            local ratios = cols[c].RowRatios or {}
            local sumR = 0
            for r = 1, #wins do sumR = sumR + ((ratios[r]) or 1) end
            if sumR <= 0 then sumR = math_max(1, #wins) end
            local availH = height - GAP * math_max(0, #wins - 1)
            if availH <= 0 then availH = height end
            local runY = 0
            for r = 1, #wins do
                local rowH = availH * (((ratios[r]) or 1) / sumR)
                local box = boxAt[c][r]
                if box then
                    box:ClearAllPoints()
                    box:SetPoint("TOPLEFT", container, "TOPLEFT", runX, -runY)
                    box:SetSize(math_max(1, colW), math_max(1, rowH))
                    if box.tlabel then
                        -- Show the label whenever the box is tall enough for the number
                        -- + one label line (it now sits right under the number, so this
                        -- threshold is lower than when it was pinned to the box bottom).
                        if rowH < 26 then box.tlabel:Hide() else box.tlabel:Show() end
                    end
                end
                runY = runY + rowH + GAP
            end
            runX = runX + colW + GAP
        end
    end

    container:SetScript("OnSizeChanged", function(_, w) layout(w) end)
    layout(container:GetWidth())

    -- Exposed so the Sizing sliders can re-tile the boxes LIVE as ratios change: `cols`
    -- is the live db.Dock.Columns reference, so layout() re-reads the new WidthRatio /
    -- RowRatios. Cheaper + smoother than a full page rebuild on every slider tick.
    container.Relayout = function() layout(container:GetWidth()) end
    return container
end

-- Rewrites a sizing slider's label into a LIVE, directional dual-share readout:
-- "Col 1  60% <|> 40%  Col 2" -- leftName/rightName flank the split, the `<|>`
-- glyph reads as the draggable divider (slides either way), and both panes' shares
-- show at once so "which way grows which" is unambiguous as the thumb moves. The
-- slider value is the left/top pane's 0-1 share of the pair, so the right share is
-- its complement (they always sum to 100). Hooked on OnValueChanged (UNthrottled,
-- unlike the db callback) so the label tracks the thumb every frame -- including the
-- silent neighbour cross-updates a shared-pane drag triggers. ASCII only: WoW's
-- embedded fonts lack the geometric arrow glyphs (feedback_wow_fontstring_limits).
local function WireSplitLabel(sliderRow, leftName, rightName)
    if not (sliderRow and sliderRow.label and sliderRow.slider) then return end
    local lbl = sliderRow.label
    local function refresh(val)
        val = val or sliderRow:GetValue() or 0.5
        local L = math_floor(val * 100 + 0.5)
        if L < 0 then L = 0 elseif L > 100 then L = 100 end
        lbl:SetText(leftName .. "  " .. L .. "% <|> " .. (100 - L) .. "%  " .. rightName)
    end
    sliderRow.slider:HookScript("OnValueChanged", function(_, val) refresh(val) end)
    refresh()
end

---------------------------------------------------------------------------------
-- Windows tab (structure + per-context defaults)
---------------------------------------------------------------------------------
local function BuildWindowsTab(scrollChild, yOffset, db, manager)
    local DM = GetDM()

    -- Referenced window indices in DOCK ORDER (column-then-row = on-screen reading
    -- order). The array position IS the display number: order[n] is the storage
    -- index of the n-th window left->right / top->bottom, and the in-world badge
    -- shows the same n (LayoutDock stamps it from the same DockWindowIndices order).
    -- So "Window n" in the GUI always maps to the numbered window on screen.
    local order = {}
    if DM and DM.DockWindowIndices then
        local found = DM:DockWindowIndices({})
        for i = 1, #found do order[i] = found[i] end
    end
    -- Reverse map (storage index -> display number) for the schematic boxes.
    local posOf = {}
    for n = 1, #order do posOf[order[n]] = n end

    local cols = db.Dock and db.Dock.Columns
    -- Arrangement is DERIVED from the column shape (Horizontal/Vertical/Custom);
    -- dragging boxes in the map + the per-window New Column button reach any Custom
    -- layout directly, so the old sticky "Custom" GUI override is no longer needed.
    local arrangement = (DM and DM.GetArrangement and DM:GetArrangement()) or "Custom"
    local maxWin = db.MaxWindows or 5

    -- The selected "Configure For" context (also used for the schematic's labels so
    -- the map reflects what the Default Display card is editing).
    if DM and DM.guiConfigContext == nil then DM.guiConfigContext = "Default" end
    local ctx = (DM and DM.guiConfigContext) or "Default"
    db.Windows = db.Windows or {}
    -- The FULL panel label for a window in the selected context -- identical to the
    -- in-world header (via DM:FormatWindowLabel), so the map / ghost match it.
    local function FullLabelFor(idx)
        local w = db.Windows[idx]
        if not (w and w.Contexts) then return "" end
        local cfg = w.Contexts[ctx] or w.Contexts.Default or {}
        if DM and DM.FormatWindowLabel then
            return DM:FormatWindowLabel(cfg.MeterType, cfg.SessionType)
        end
        return ""
    end

    -- The layout map, declared at tab scope so the Sizing sliders (a later card) can
    -- call schematic.Relayout() to live-update the boxes as the ratios change.
    local schematic

    ----------------------------------------------------------------
    -- Card 1: Layout (quick preset + visual map + move controls)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Layout", yOffset)
    manager:Register(card1, "all")

    -- Quick preset dropdown + Add/Remove.
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local arrDropdown = GUIFrame:CreateDropdown(row1, "Layout", {
        options = ARRANGEMENT_OPTIONS,
        value = arrangement,
        callback = function(key)
            -- Horizontal/Vertical rewrite the columns; Custom is a no-op (the
            -- structure already is whatever the moves made it).
            if DM and DM.SetArrangement then DM:SetArrangement(key) end
            RebuildPage()
        end,
    })
    row1:AddWidget(arrDropdown, 0.5)
    manager:Register(arrDropdown, "all")

    -- Add/Remove are gated by the floor/cap (NOT registered -- manager:UpdateAll
    -- would re-enable them on module-enable and defeat the cap gating). The card's
    -- mouse blocker + alpha cascade still disable them when the module is off.
    local addBtn = GUIFrame:CreateButton(row1, "Add Window", {
        callback = function()
            if DM and DM.AddWindow then DM:AddWindow() end
            RebuildPage()
        end,
    })
    row1:AddWidget(addBtn, 0.25)

    local removeBtn = GUIFrame:CreateButton(row1, "Remove Window", {
        callback = function()
            -- Remove the LAST on-screen window (highest display position).
            if DM and DM.RemoveWindow and #order > 1 then
                DM:RemoveWindow(order[#order])
            end
            RebuildPage()
        end,
    })
    row1:AddWidget(removeBtn, 0.25)
    addBtn:SetEnabled(#order < maxWin)
    removeBtn:SetEnabled(#order > 1)
    card1:AddRow(row1, Theme.rowHeight)

    -- Visual layout map (numbered boxes mirroring the in-world dock).
    if cols and #order > 0 then
        schematic = BuildSchematic(card1, 96, cols, posOf, FullLabelFor)
        card1:AddRow(schematic, 96)
    end

    -- The map is the ONLY place you arrange windows: drag onto a window's center to
    -- stack/reorder, or drag toward a column's edge (or off the map) to peel a window
    -- into its own new column. The live line preview shows the result before release
    -- (horizontal = stack, vertical = new column), so no separate buttons are needed.
    local arrNoteRow = GUIFrame:CreateRow(card1.content, 50)
    local arrNote = GUIFrame:CreateText(arrNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Drag onto a window's center to stack it; drag to a side or off the edge for a new column.\n" ..
        KE:ColorTextByTheme("-") .. " Numbers match the meter on screen (up to " .. maxWin ..
        "). Resize by dragging the gaps in the world.",
        50, "hide")
    arrNoteRow:AddWidget(arrNote, 1)
    manager:Register(arrNote, "all")
    card1:AddRow(arrNoteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Sizing (one split slider per gap -- the exact pair the in-world
    -- drag-splitter for that gap adjusts). Shown only when a gap exists.
    ----------------------------------------------------------------
    do
        local nCols = (cols and #cols) or 0
        local hasColBoundary = nCols >= 2
        local hasRowBoundary = false
        if cols then
            for c = 1, #cols do
                if cols[c].Windows and #cols[c].Windows >= 2 then hasRowBoundary = true; break end
            end
        end

        if hasColBoundary or hasRowBoundary then
            local sizeCard = GUIFrame:CreateCard(scrollChild, "Sizing", yOffset)
            manager:Register(sizeCard, "all")

            -- Slider references for live cross-update (neighbors share a pane).
            local colSliders = {}
            local rowSliders = {}

            -- Column-gap sliders: between column c and c+1, value = left share. Stored
            -- as a 0-1 fraction with isPercent so the readout shows "%". Range clamped
            -- per gap to the in-world drag-splitter floor (DM:GetColumnBoundaryRange)
            -- so a column can't be sliddered below usable size.
            for c = 1, nCols - 1 do
                local cMin, cMax = 5, 95
                if DM and DM.GetColumnBoundaryRange then cMin, cMax = DM:GetColumnBoundaryRange(c) end
                local rowS = GUIFrame:CreateRow(sizeCard.content, Theme.rowHeight)
                local slider = GUIFrame:CreateSlider(rowS, "", {
                    min = cMin / 100, max = cMax / 100, step = 0.01, isPercent = true,
                    value = ((DM and DM.GetColumnBoundaryShare and DM:GetColumnBoundaryShare(c)) or 50) / 100,
                    callback = function(val)
                        if DM and DM.SetColumnBoundaryShare then DM:SetColumnBoundaryShare(c, val * 100) end
                        if schematic and schematic.Relayout then schematic.Relayout() end
                        -- Refresh the two neighbours that share a touched column.
                        if colSliders[c - 1] and DM then
                            colSliders[c - 1]:SetValue(DM:GetColumnBoundaryShare(c - 1) / 100, true)
                        end
                        if colSliders[c + 1] and DM then
                            colSliders[c + 1]:SetValue(DM:GetColumnBoundaryShare(c + 1) / 100, true)
                        end
                    end,
                })
                WireSplitLabel(slider, "Col " .. c, "Col " .. (c + 1))
                rowS:AddWidget(slider, 1)
                manager:Register(slider, "all")
                sizeCard:AddRow(rowS, Theme.rowHeight)
                colSliders[c] = slider
            end

            -- Row-gap sliders: within each stacked column, between row r and r+1.
            if cols then
                for c = 1, #cols do
                    local wins = cols[c].Windows
                    if wins and #wins >= 2 then
                        rowSliders[c] = rowSliders[c] or {}
                        for r = 1, #wins - 1 do
                            local topNum = posOf[wins[r]] or wins[r]
                            local botNum = posOf[wins[r + 1]] or wins[r + 1]
                            local rMin, rMax = 5, 95
                            if DM and DM.GetRowBoundaryRange then rMin, rMax = DM:GetRowBoundaryRange(c, r) end
                            local rowS = GUIFrame:CreateRow(sizeCard.content, Theme.rowHeight)
                            local slider = GUIFrame:CreateSlider(rowS, "", {
                                min = rMin / 100, max = rMax / 100, step = 0.01, isPercent = true,
                                value = ((DM and DM.GetRowBoundaryShare and DM:GetRowBoundaryShare(c, r)) or 50) / 100,
                                callback = function(val)
                                    if DM and DM.SetRowBoundaryShare then DM:SetRowBoundaryShare(c, r, val * 100) end
                                    if schematic and schematic.Relayout then schematic.Relayout() end
                                    local rs = rowSliders[c]
                                    if rs and DM then
                                        if rs[r - 1] then rs[r - 1]:SetValue(DM:GetRowBoundaryShare(c, r - 1) / 100, true) end
                                        if rs[r + 1] then rs[r + 1]:SetValue(DM:GetRowBoundaryShare(c, r + 1) / 100, true) end
                                    end
                                end,
                            })
                            WireSplitLabel(slider, "Win " .. topNum, "Win " .. botNum)
                            rowS:AddWidget(slider, 1)
                            manager:Register(slider, "all")
                            sizeCard:AddRow(rowS, Theme.rowHeight)
                            rowSliders[c][r] = slider
                        end
                    end
                end
            end

            local szNoteRow = GUIFrame:CreateRow(sizeCard.content, 50)
            local szNote = GUIFrame:CreateText(szNoteRow,
                KE:ColorTextByTheme("Note"),
                KE:ColorTextByTheme("-") .. " Each slider splits just its two neighbours; the rest stay put.\n" ..
                KE:ColorTextByTheme("-") .. " Same effect as dragging that gap between windows in the world.",
                50, "hide")
            szNoteRow:AddWidget(szNote, 1)
            manager:Register(szNote, "all")
            sizeCard:AddRow(szNoteRow, 50, 0)

            yOffset = sizeCard:GetNextOffset()
        end
    end

    ----------------------------------------------------------------
    -- Card 3: Default Display (Configure For: <context>)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Default Display", yOffset)
    manager:Register(card2, "all")

    local rowCtx = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local ctxDropdown = GUIFrame:CreateDropdown(rowCtx, "Configure For", {
        options = CONTEXT_OPTIONS,
        value = ctx,
        callback = function(key)
            if DM then DM.guiConfigContext = key end
            RebuildPage()
        end,
    })
    rowCtx:AddWidget(ctxDropdown, 1)
    manager:Register(ctxDropdown, "all")
    card2:AddRow(rowCtx, Theme.rowHeight)

    local ctxNoteRow = GUIFrame:CreateRow(card2.content, 50)
    local ctxNote = GUIFrame:CreateText(ctxNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Defaults auto-apply when you enter that content. Unset contexts inherit Default.\n" ..
        KE:ColorTextByTheme("-") .. " Live type/segment changes on the meter stick until the content changes.",
        50, "hide")
    ctxNoteRow:AddWidget(ctxNote, 1)
    manager:Register(ctxNote, "all")
    card2:AddRow(ctxNoteRow, 50, 0)

    -- Column layout shared by the header + every window row (so they align):
    --   badge 0.08 | enable 0.16 | Type 0.38 | Segment 0.38.
    local COL_BADGE, COL_ENABLE, COL_TYPE, COL_SEG = 0.08, 0.16, 0.38, 0.38

    -- Small accent number chip matching the map boxes + in-world index badges, so a
    -- row visually maps to its numbered window. A plain Frame (AddWidget stretches it
    -- to its column); the chip inside is fixed-size, anchored at the control band so
    -- it lines up with the toggle/dropdowns (which sit 14px below the row top).
    local function MakeNumberBadge(parent, n)
        local f = CreateFrame("Frame", nil, parent)
        local chip = CreateFrame("Frame", nil, f, "BackdropTemplate")
        chip:SetSize(24, 24)
        chip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -14)
        chip:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        local a = Theme.accent
        chip:SetBackdropColor(a[1], a[2], a[3], 0.9)
        chip:SetBackdropBorderColor(0, 0, 0, 1)
        local t = chip:CreateFontString(nil, "OVERLAY")
        t:SetPoint("CENTER")
        KE:ApplyThemeFont(t, "normal")
        t:SetTextColor(1, 1, 1, 1)
        t:SetText(tostring(n))
        return f
    end

    -- Single header row -- carries the column labels ONCE (the per-widget labels are
    -- dropped below) so "Type"/"Segment" don't repeat on every window. FontStrings sit
    -- at the same cumulative column fractions AddWidget uses, so each lands directly
    -- above its control column. (Card alpha greys it with the module; not registered.)
    local hdrRow = CreateFrame("Frame", nil, card2.content)
    hdrRow:SetHeight(14)
    local function makeHdr(text)
        local fs = hdrRow:CreateFontString(nil, "OVERLAY")
        KE:ApplyThemeFont(fs, "small")
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        fs:SetText(text)
        return fs
    end
    local hShow, hType, hSeg = makeHdr("Show"), makeHdr("Type"), makeHdr("Segment")
    hdrRow:SetScript("OnSizeChanged", function(self, w)
        hShow:ClearAllPoints(); hShow:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", w * COL_BADGE, 0)
        hType:ClearAllPoints(); hType:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", w * (COL_BADGE + COL_ENABLE), 0)
        hSeg:ClearAllPoints();  hSeg:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", w * (COL_BADGE + COL_ENABLE + COL_TYPE), 0)
    end)
    card2:AddRow(hdrRow, 14)

    -- One row per window (numbered left->right / top->bottom by on-screen position):
    -- [number chip] [enable] [Type] [Segment]. Labels live in the header above.
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
                if DM and DM.RefreshDock then DM:RefreshDock() end
                if DM and DM.Tick then DM:Tick() end
            end

            local isLast = (n == #order)
            local rowW = GUIFrame:CreateRow(card2.content, isLast and Theme.rowHeightLast or Theme.rowHeight)

            rowW:AddWidget(MakeNumberBadge(rowW, n), COL_BADGE)

            local enChk = GUIFrame:CreateCheckbox(rowW, "", {
                value = cfg.Enabled ~= false,
                callback = function(checked) writeField("Enabled", checked) end,
            })
            rowW:AddWidget(enChk, COL_ENABLE)
            manager:Register(enChk, "all")

            local typeDd = GUIFrame:CreateDropdown(rowW, "", {
                options = METER_TYPE_OPTIONS,
                value = cfg.MeterType or Enum.DamageMeterType.DamageDone,
                callback = function(key) writeField("MeterType", key) end,
            })
            rowW:AddWidget(typeDd, COL_TYPE)
            manager:Register(typeDd, "all")

            local segDd = GUIFrame:CreateDropdown(rowW, "", {
                options = SEGMENT_OPTIONS,
                value = cfg.SessionType or Enum.DamageMeterSessionType.Current,
                callback = function(key) writeField("SessionType", key) end,
            })
            rowW:AddWidget(segDd, COL_SEG)
            manager:Register(segDd, "all")

            card2:AddRow(rowW, isLast and Theme.rowHeightLast or Theme.rowHeight, isLast and 0 or nil)
        end
    end

    yOffset = card2:GetNextOffset()
    return yOffset
end

---------------------------------------------------------------------------------
-- Appearance tab (global; applies to all windows uniformly)
---------------------------------------------------------------------------------
local function BuildAppearanceTab(scrollChild, yOffset, db, manager)
    local statusbarList = MediaList("statusbar", "Blizzard")
    local fontList = MediaList("font", "Friz Quadrata TT")

    -- Backdrop sub-widgets greyed when BackdropEnabled is off.
    manager:SetCondition("backdrop", function() return db.BackdropEnabled ~= false end)
    -- Line Thickness greyed unless Thin Line is on; the Custom fill-color picker greyed
    -- unless the Bar Color mode is Custom.
    manager:SetCondition("thinline", function() return db.BarThinLine == true end)
    manager:SetCondition("barcustomcolor", function() return db.BarColorMode == "Custom" end)

    ----------------------------------------------------------------
    -- Bars -- texture + geometry.
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Bars", yOffset)
    manager:Register(card1, "all")

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local texDropdown = GUIFrame:CreateDropdown(row1a, "Bar Texture", {
        options = statusbarList,
        value = db.StatusBarTexture or "KitnUI",
        callback = function(key) db.StatusBarTexture = key; ApplySettings() end,
        searchable = true,
    })
    row1a:AddWidget(texDropdown, 1)
    manager:Register(texDropdown, "all")
    card1:AddRow(row1a, Theme.rowHeight)

    local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local widthSlider = GUIFrame:CreateSlider(row1b, "Window Width", {
        min = 120, max = 600, step = 1,
        value = db.Width or 240,
        callback = function(val) db.Width = val; ApplySettings() end,
    })
    row1b:AddWidget(widthSlider, 0.5)
    manager:Register(widthSlider, "all")

    local visSlider = GUIFrame:CreateSlider(row1b, "Visible Bars", {
        min = 1, max = 40, step = 1,
        value = db.VisibleBars or 10,
        callback = function(val) db.VisibleBars = val; ApplySettings() end,
    })
    row1b:AddWidget(visSlider, 0.5)
    manager:Register(visSlider, "all")
    card1:AddRow(row1b, Theme.rowHeight)

    local row1c = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local heightSlider = GUIFrame:CreateSlider(row1c, "Bar Height", {
        min = 8, max = 40, step = 1,
        value = db.BarHeight or 16,
        callback = function(val) db.BarHeight = val; ApplySettings() end,
    })
    row1c:AddWidget(heightSlider, 0.5)
    manager:Register(heightSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(row1c, "Bar Spacing", {
        min = 0, max = 10, step = 1,
        value = db.BarSpacing or 2,
        callback = function(val) db.BarSpacing = val; ApplySettings() end,
    })
    row1c:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card1:AddRow(row1c, Theme.rowHeight)

    -- Separator: splits the size sliders above from the thin-line style block below.
    local row1sep = GUIFrame:CreateRow(card1.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    manager:Register(sep1, "all")
    card1:AddRow(row1sep, Theme.rowHeightSeparator)

    -- Thin-line style: the colored fill becomes a thin strip pinned to the bottom edge
    -- (a clean minimalist look). Line Thickness shares the toggle's row and greys out when
    -- the toggle is off.
    local row1d = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local thinChk = GUIFrame:CreateCheckbox(row1d, "Thin Line Bars", {
        value = db.BarThinLine == true,
        callback = function(checked)
            db.BarThinLine = checked
            ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    row1d:AddWidget(thinChk, 0.5)
    manager:Register(thinChk, "all")

    local thinHSlider = GUIFrame:CreateSlider(row1d, "Line Thickness", {
        min = 1, max = 12, step = 1,
        value = db.BarThinLineHeight or 2,
        callback = function(val) db.BarThinLineHeight = val; ApplySettings() end,
    })
    row1d:AddWidget(thinHSlider, 0.5)
    manager:Register(thinHSlider, "thinline")
    card1:AddRow(row1d, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Bar Content -- only what is DRAWN on each bar row.
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Bar Content", yOffset)
    manager:Register(card2, "all")

    -- Row 1: spec icon + class-coloured names (the two "how a row reads at a glance" toggles).
    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local iconChk = GUIFrame:CreateCheckbox(row2a, "Show Spec Icon", {
        value = db.ShowIcon ~= false,
        callback = function(checked) db.ShowIcon = checked; ApplySettings() end,
    })
    row2a:AddWidget(iconChk, 0.5)
    manager:Register(iconChk, "all")

    local classNameChk = GUIFrame:CreateCheckbox(row2a, "Class Color Names", {
        value = db.ClassColorName == true,
        callback = function(checked) db.ClassColorName = checked; ApplySettings() end,
    })
    row2a:AddWidget(classNameChk, 0.5)
    manager:Register(classNameChk, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    -- Row 2: the two name toggles (player name + realm suffix).
    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local nameChk = GUIFrame:CreateCheckbox(row2b, "Show Player Names", {
        value = db.ShowName ~= false,
        callback = function(checked) db.ShowName = checked; ApplySettings() end,
    })
    row2b:AddWidget(nameChk, 0.5)
    manager:Register(nameChk, "all")

    local realmChk = GUIFrame:CreateCheckbox(row2b, "Show Realm Names", {
        value = db.ShowRealm == true,
        callback = function(checked) db.ShowRealm = checked; ApplySettings() end,
    })
    row2b:AddWidget(realmChk, 0.5)
    manager:Register(realmChk, "all")
    card2:AddRow(row2b, Theme.rowHeight)

    -- Separator: splits the name/icon element toggles above from the number/value row below.
    local row2sep = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    local sep2 = GUIFrame:CreateSeparator(row2sep)
    row2sep:AddWidget(sep2, 1)
    manager:Register(sep2, "all")
    card2:AddRow(row2sep, Theme.rowHeightSeparator)

    -- Row 3: number format (full width -- it's the headline content control).
    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local fmtDd = GUIFrame:CreateDropdown(row2c, "Numbers", {
        options = {
            { key = "Both",   text = "Amount + DPS" },
            { key = "Amount", text = "Amount Only" },
            { key = "PerSec", text = "DPS Only" },
        },
        value = db.NumberFormat or "Both",
        callback = function(key) db.NumberFormat = key; ApplySettings() end,
    })
    row2c:AddWidget(fmtDd, 1)
    manager:Register(fmtDd, "all")
    card2:AddRow(row2c, Theme.rowHeight)

    -- Row 4: self pin + rank numbering.
    local row2d = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local selfChk = GUIFrame:CreateCheckbox(row2d, "Always Show Self", {
        value = db.AlwaysShowSelf ~= false,
        tooltip = "Pins your row to the last visible slot when you fall off-screen. Role-aware: damage views pin DPS and tanks, healing views pin healers; other views never pin.",
        callback = function(checked) db.AlwaysShowSelf = checked; ApplySettings() end,
    })
    row2d:AddWidget(selfChk, 0.5)
    manager:Register(selfChk, "all")

    local rankChk = GUIFrame:CreateCheckbox(row2d, "Show Rank Number", {
        value = db.ShowRank == true,
        callback = function(checked) db.ShowRank = checked; ApplySettings() end,
    })
    row2d:AddWidget(rankChk, 0.5)
    manager:Register(rankChk, "all")
    card2:AddRow(row2d, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Bar Colors -- fill color mode + opacity + bar text color.
    -- The Custom color picker greys out unless the fill mode is Custom.
    ----------------------------------------------------------------
    local cardColors = GUIFrame:CreateCard(scrollChild, "Bar Colors", yOffset)
    manager:Register(cardColors, "all")

    local rowCol1 = GUIFrame:CreateRow(cardColors.content, Theme.rowHeight)
    local fillModeDd = GUIFrame:CreateDropdown(rowCol1, "Fill Color", {
        options = {
            { key = "Class",  text = "Class Color" },
            { key = "Custom", text = "Custom" },
            { key = "Theme",  text = "Theme" },
        },
        value = db.BarColorMode or "Class",
        callback = function(key)
            db.BarColorMode = key
            ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)   -- re-evaluate the Custom-color grey
        end,
    })
    rowCol1:AddWidget(fillModeDd, 0.5)
    manager:Register(fillModeDd, "all")

    -- Custom fill color. The picker exposes opacity (hasOpacity); its alpha doubles as the
    -- fill opacity (kept in db.BarColorAlpha, in sync with the Fill Opacity slider below so
    -- both edit the same value). RGB is stored in db.BarColor.
    local fillColorPicker = GUIFrame:CreateColorPicker(rowCol1, "Custom Color", {
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
    rowCol1:AddWidget(fillColorPicker, 0.5)
    manager:Register(fillColorPicker, "barcustomcolor")
    cardColors:AddRow(rowCol1, Theme.rowHeight)

    local rowCol2 = GUIFrame:CreateRow(cardColors.content, Theme.rowHeightLast)
    -- Fill opacity applies to ALL modes (Class / Custom / Accent), so it stays enabled even
    -- when the Custom picker is greyed.
    local opacitySlider = GUIFrame:CreateSlider(rowCol2, "Fill Opacity", {
        min = 0, max = 1, step = 0.05, isPercent = true,
        value = db.BarColorAlpha or 1,
        callback = function(val) db.BarColorAlpha = val; ApplySettings() end,
    })
    rowCol2:AddWidget(opacitySlider, 0.5)
    manager:Register(opacitySlider, "all")

    -- Bar text color (value column always; name column when NOT class-colored). Alpha is
    -- ignored -- bar text is always opaque -- so only RGB is stored.
    local textColorPicker = GUIFrame:CreateColorPicker(rowCol2, "Text Color", {
        color = db.BarTextColor or { 1, 1, 1, 1 },
        callback = function(r, g, b) db.BarTextColor = { r, g, b }; ApplySettings() end,
    })
    rowCol2:AddWidget(textColorPicker, 0.5)
    manager:Register(textColorPicker, "all")
    cardColors:AddRow(rowCol2, Theme.rowHeightLast, 0)

    yOffset = cardColors:GetNextOffset()

    ----------------------------------------------------------------
    -- Header Icons -- two independent elements on each window header band: the
    -- meter-type glyph beside the title ("Show Type Icon") and the settings /
    -- reset / segment action buttons ("Show Action Buttons"). "Only on Mouseover"
    -- governs the action buttons and greys when they're off.
    ----------------------------------------------------------------
    manager:SetCondition("headericons", function() return db.ShowHeaderIcons ~= false end)

    local cardHeaderIcons = GUIFrame:CreateCard(scrollChild, "Header Icons", yOffset)
    manager:Register(cardHeaderIcons, "all")

    -- Action Buttons lead the row so "Only on Mouseover" (which governs them) sits in the
    -- left column directly beneath it; Type Icon is the independent right-column toggle.
    local rowHdr = GUIFrame:CreateRow(cardHeaderIcons.content, Theme.rowHeight)
    local headerIconsChk = GUIFrame:CreateCheckbox(rowHdr, "Show Action Buttons", {
        value = db.ShowHeaderIcons ~= false,
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
        callback = function(checked) db.ShowTypeIcon = checked; ApplySettings() end,
    })
    rowHdr:AddWidget(typeIconChk, 0.5)
    manager:Register(typeIconChk, "all")
    cardHeaderIcons:AddRow(rowHdr, Theme.rowHeight)

    local rowHdr2 = GUIFrame:CreateRow(cardHeaderIcons.content, Theme.rowHeight)
    local headerMouseoverChk = GUIFrame:CreateCheckbox(rowHdr2, "Only on Mouseover", {
        value = db.HeaderIconsMouseover == true,
        callback = function(checked) db.HeaderIconsMouseover = checked; ApplySettings() end,
    })
    rowHdr2:AddWidget(headerMouseoverChk, 0.5)
    manager:Register(headerMouseoverChk, "headericons")
    cardHeaderIcons:AddRow(rowHdr2, Theme.rowHeight)

    -- What each toggle controls.
    local rowHdrNote = GUIFrame:CreateRow(cardHeaderIcons.content, 54)
    local hdrNote = GUIFrame:CreateText(rowHdrNote,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Action Buttons: the settings / reset / segment icons (top-right).\n" ..
        KE:ColorTextByTheme("-") .. " Type Icon: the meter-type glyph beside the window title.",
        54, "hide")
    rowHdrNote:AddWidget(hdrNote, 1)
    manager:Register(hdrNote, "all")
    cardHeaderIcons:AddRow(rowHdrNote, 54, 0)

    yOffset = cardHeaderIcons:GetNextOffset()

    ----------------------------------------------------------------
    -- Hover Tooltip -- hovering a bar floats a top-N breakdown / death
    -- recap. The position dropdown greys when the tip is off.
    ----------------------------------------------------------------
    manager:SetCondition("hovertip", function() return db.HoverTooltip ~= false end)

    local cardHoverTip = GUIFrame:CreateCard(scrollChild, "Tooltip on Mouseover", yOffset)
    manager:Register(cardHoverTip, "all")

    local rowTip1 = GUIFrame:CreateRow(cardHoverTip.content, Theme.rowHeight)
    local hoverTipChk = GUIFrame:CreateCheckbox(rowTip1, "Show Tooltip on Mouseover", {
        value = db.HoverTooltip ~= false,
        callback = function(checked)
            db.HoverTooltip = checked
            ApplySettings()
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    rowTip1:AddWidget(hoverTipChk, 1)
    manager:Register(hoverTipChk, "all")
    cardHoverTip:AddRow(rowTip1, Theme.rowHeight)

    local rowTip2 = GUIFrame:CreateRow(cardHoverTip.content, Theme.rowHeightLast)
    local hoverAnchorDd = GUIFrame:CreateDropdown(rowTip2, "Tooltip Position", {
        options = {
            { key = "smart",  text = "Smart (auto side)" },
            { key = "bar",    text = "Above Bar" },
            { key = "left",   text = "Left of Meter" },
            { key = "right",  text = "Right of Meter" },
            { key = "center", text = "Screen Center" },
        },
        value = db.HoverTooltipAnchor or "smart",
        callback = function(key) db.HoverTooltipAnchor = key; ApplySettings() end,
    })
    rowTip2:AddWidget(hoverAnchorDd, 1)
    manager:Register(hoverAnchorDd, "hovertip")
    cardHoverTip:AddRow(rowTip2, Theme.rowHeightLast, 0)

    yOffset = cardHoverTip:GetNextOffset()

    ----------------------------------------------------------------
    -- Font
    -- Outline list excludes SOFTOUTLINE: bar text is small and soft-outline
    -- haloes on tiny text (matches the KickTracker bar-text rationale).
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Font", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local fontDropdown = GUIFrame:CreateDropdown(row3a, "Font", {
        options = fontList,
        value = db.FontFace or "Expressway",
        callback = function(key) db.FontFace = key; ApplySettings() end,
        searchable = true,
        isFontPreview = true,
    })
    row3a:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "all")

    local outlineDropdown = GUIFrame:CreateDropdown(row3a, "Font Outline", {
        options = KE:GetFontOutlineOptions(),
        value = db.FontOutline or "OUTLINE",
        callback = function(key) db.FontOutline = key; ApplySettings() end,
    })
    row3a:AddWidget(outlineDropdown, 0.5)
    manager:Register(outlineDropdown, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    -- Header text and bar text size are independent sliders. HeaderFontSize falls back
    -- to FontSize when unset, so an existing config's header keeps its current size until
    -- this slider is moved; the bar rows always read FontSize.
    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local headerSizeSlider = GUIFrame:CreateSlider(row3b, "Header Text Size", {
        min = 8, max = 24, step = 1,
        value = db.HeaderFontSize or db.FontSize or 12,
        callback = function(val) db.HeaderFontSize = val; ApplySettings() end,
    })
    row3b:AddWidget(headerSizeSlider, 0.5)
    manager:Register(headerSizeSlider, "all")

    local barSizeSlider = GUIFrame:CreateSlider(row3b, "Bar Text Size", {
        min = 8, max = 24, step = 1,
        value = db.FontSize or 12,
        callback = function(val) db.FontSize = val; ApplySettings() end,
    })
    row3b:AddWidget(barSizeSlider, 0.5)
    manager:Register(barSizeSlider, "all")
    card3:AddRow(row3b, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Backdrop
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local bgEnableChk = GUIFrame:CreateCheckbox(row4a, "Enable Backdrop", {
        value = db.BackdropEnabled ~= false,
        callback = function(checked)
            db.BackdropEnabled = checked
            ApplySettings()              -- re-pad windows + re-skin
            manager:UpdateAll(db.Enabled ~= false)
        end,
    })
    row4a:AddWidget(bgEnableChk, 0.5)
    manager:Register(bgEnableChk, "all")

    local styleDropdown = GUIFrame:CreateDropdown(row4a, "Border Style", {
        options = {
            { key = "neutral", text = "Neutral" },
            { key = "accent",  text = "Accent" },
            { key = "theme",   text = "Theme" },
        },
        value = db.BackdropBorderStyle or "neutral",
        callback = function(key) db.BackdropBorderStyle = key; ApplyBackdropOnly() end,
    })
    row4a:AddWidget(styleDropdown, 0.5)
    manager:Register(styleDropdown, "backdrop")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local bgColorPicker = GUIFrame:CreateColorPicker(row4b, "Background", {
        color = db.BackdropColor or { 0.031, 0.031, 0.031, 0.8 },
        callback = function(r, g, b, a) db.BackdropColor = { r, g, b, a }; ApplyBackdropOnly() end,
    })
    row4b:AddWidget(bgColorPicker, 0.5)
    manager:Register(bgColorPicker, "backdrop")

    local borderColorPicker = GUIFrame:CreateColorPicker(row4b, "Border", {
        color = db.BackdropBorderColor or { 0, 0, 0, 1 },
        callback = function(r, g, b, a) db.BackdropBorderColor = { r, g, b, a }; ApplyBackdropOnly() end,
    })
    row4b:AddWidget(borderColorPicker, 0.5)
    manager:Register(borderColorPicker, "backdrop")
    card4:AddRow(row4b, Theme.rowHeight)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local padSlider = GUIFrame:CreateSlider(row4c, "Padding", {
        min = 0, max = 20, step = 1,
        value = db.BackdropPadding or 1,
        callback = function(val) db.BackdropPadding = val; ApplySettings() end,
    })
    row4c:AddWidget(padSlider, 1)
    manager:Register(padSlider, "backdrop")
    card4:AddRow(row4c, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()
    return yOffset
end

---------------------------------------------------------------------------------
-- Behavior tab
---------------------------------------------------------------------------------
local function BuildBehaviorTab(scrollChild, yOffset, db, manager)
    local DM = GetDM()

    ----------------------------------------------------------------
    -- Card 1: Performance
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Performance", yOffset)
    manager:Register(card1, "all")

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local refreshSlider = GUIFrame:CreateSlider(row1a, "Combat Refresh", {
        min = 0.1, max = 1.0, step = 0.05,
        value = db.RefreshRate or 0.5,
        callback = function(val)
            db.RefreshRate = val
            -- Apply live: restart the ticker only if it's currently running.
            if DM and DM._ticker and DM.StartTicker then DM:StartTicker() end
        end,
    })
    row1a:AddWidget(refreshSlider, 0.5)
    manager:Register(refreshSlider, "all")

    local budgetSlider = GUIFrame:CreateSlider(row1a, "UI Budget (ms)", {
        min = 0.5, max = 5.0, step = 0.1,
        value = db.UIBudgetMs or 1.2,
        callback = function(val) db.UIBudgetMs = val end,
    })
    row1a:AddWidget(budgetSlider, 0.5)
    manager:Register(budgetSlider, "all")
    card1:AddRow(row1a, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 65)
    local note = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("Combat Refresh") ..
        " — how often bars repaint in combat (lower = smoother, more CPU).\n" ..
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("UI Budget") ..
        " — max ms/frame spent painting; windows over budget defer to the next frame.\n" ..
        KE:ColorTextByTheme("-") .. " Segments are automatic: " .. KE:ColorTextByTheme("Current") ..
        " is the live fight, " .. KE:ColorTextByTheme("Overall") .. " is cumulative (set per window in Windows).",
        65, "hide")
    noteRow:AddWidget(note, 1)
    manager:Register(note, "all")
    card1:AddRow(noteRow, 65, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Visibility (conditional show / hide)
    ----------------------------------------------------------------
    local cardVis = GUIFrame:CreateCard(scrollChild, "Visibility", yOffset)
    manager:Register(cardVis, "all")

    local rowVis = GUIFrame:CreateRow(cardVis.content, Theme.rowHeight)
    local oocChk = GUIFrame:CreateCheckbox(rowVis, "Hide Out of Combat", {
        value = db.HideOutOfCombat == true,
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
        callback = function(checked)
            db.OnlyInInstances = checked
            if DM and DM.UpdateBackdrop then DM:UpdateBackdrop() end
        end,
    })
    rowVis:AddWidget(instChk, 0.5)
    manager:Register(instChk, "all")
    cardVis:AddRow(rowVis, Theme.rowHeight)

    local visNoteRow = GUIFrame:CreateRow(cardVis.content, 50)
    local visNote = GUIFrame:CreateText(visNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Both combine: the meter shows only when every enabled condition is met.\n" ..
        KE:ColorTextByTheme("-") .. " Always visible while this panel is open or in " .. KE:ColorTextByTheme("/kes edit") .. ".",
        50, "hide")
    visNoteRow:AddWidget(visNote, 1)
    manager:Register(visNote, "all")
    cardVis:AddRow(visNoteRow, 50, 0)

    yOffset = cardVis:GetNextOffset()
    return yOffset
end

---------------------------------------------------------------------------------
-- Page registration
---------------------------------------------------------------------------------
GUIFrame:RegisterContent("DamageMeter", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DamageMeter
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local _, newOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = {
            { id = "General", label = "General" },
            { id = "Windows", label = "Windows" },
            { id = "Appearance", label = "Appearance" },
            { id = "Behavior", label = "Behavior" },
        },
        activeId = activeTab,
        onSwitch = function(newId) activeTab = newId end,
        fill = true,
    })
    yOffset = newOffset

    local manager = GUIFrame:CreateWidgetStateManager()

    if activeTab == "General" then
        yOffset = BuildGeneralTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Windows" then
        yOffset = BuildWindowsTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Appearance" then
        yOffset = BuildAppearanceTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Behavior" then
        yOffset = BuildBehaviorTab(scrollChild, yOffset, db, manager)
    end

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)
