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

local activeTab = "General"

-- Ordered option lists for the per-context default-display rows.
local METER_TYPE_OPTIONS = {
    { key = Enum.DamageMeterType.DamageDone,  text = "Damage Done" },
    { key = Enum.DamageMeterType.HealingDone, text = "Healing Done" },
    { key = Enum.DamageMeterType.DamageTaken, text = "Damage Taken" },
    { key = Enum.DamageMeterType.Interrupts,  text = "Interrupts" },
    { key = Enum.DamageMeterType.Dispels,     text = "Dispels" },
    { key = Enum.DamageMeterType.Deaths,      text = "Deaths" },
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

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " In-client meter on Blizzard's 12.0 data; replaces the built-in meter automatically while enabled.\n" ..
        KE:ColorTextByTheme("-") .. " Switch type/segment on the meter itself; the GUI sets defaults & look.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

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
    local dragNoteCard = GUIFrame:CreateCard(scrollChild, "Tip", yOffset)
    manager:Register(dragNoteCard, "all")
    local dnRow = GUIFrame:CreateRow(dragNoteCard.content, Theme.rowHeightLast)
    local dnText = GUIFrame:CreateText(dnRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Drag the dock in " .. KE:ColorTextByTheme("/kes edit") ..
        " (disabled while locked). Resize panes by dragging the gaps between windows.\n" ..
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("/kedm") ..
        " toggles the dock; " .. KE:ColorTextByTheme("/kedm reset") .. " clears all segments.",
        Theme.rowHeightLast, "hide")
    dnRow:AddWidget(dnText, 1)
    manager:Register(dnText, "all")
    dragNoteCard:AddRow(dnRow, Theme.rowHeightLast, 0)
    yOffset = dragNoteCard:GetNextOffset()

    return yOffset
end

---------------------------------------------------------------------------------
-- Windows tab helpers
---------------------------------------------------------------------------------

-- Locates a window's (column, row) and its column's window count. Returns
-- (colIdx, rowIdx, colLen) or nil. Plain table walk; never a secret.
local function FindWindowPos(cols, idx)
    if not cols then return nil end
    for c = 1, #cols do
        local wins = cols[c] and cols[c].Windows
        if wins then
            for r = 1, #wins do
                if wins[r] == idx then return c, r, #wins end
            end
        end
    end
    return nil
end

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
-- anchors it). Drag a box onto another to rearrange: a cursor-following ghost
-- shows what you grabbed and a white insertion line shows exactly where it will
-- drop (above the hovered box, or below it when the cursor is in its lower half).
local function BuildSchematic(card, height, cols, posOf, fullLabel)
    local T = Theme
    local container = CreateFrame("Frame", nil, card.content)
    container:SetHeight(height)

    local boxAt = {}    -- boxAt[c][r] = box frame
    local allBoxes = {} -- flat list for drag hit-testing + highlight

    -- Insertion line: a bright white bar shown at the edge where the dragged
    -- window will land (top of the hovered box = drop before it; bottom = after).
    local dropLine = container:CreateTexture(nil, "OVERLAY")
    dropLine:SetColorTexture(1, 1, 1, 1)
    dropLine:SetHeight(3)
    dropLine:Hide()

    -- Restore every box's resting accent border (clears any drag highlight).
    local function ResetBorders()
        for _, b in ipairs(allBoxes) do
            b:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
        end
    end

    -- Per-frame drag feedback (attached as the container OnUpdate only while a box
    -- is being dragged): moves the ghost to the cursor, finds the box under the
    -- cursor + which half (top = insert before, bottom = insert after), highlights
    -- it, and parks the insertion line at that edge. The chosen target is stashed
    -- on the container for OnDragStop to act on. When the cursor isn't over a valid
    -- target box, the line + target clear (a drop there is a no-op).
    local function DragUpdate()
        local dragWin = container._dragWin
        if not dragWin then return end

        -- Ghost follows the cursor (UIParent space).
        local ghost = GetSchematicGhost()
        local us = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (mx / us) + 16, (my / us) - 14)

        -- Hit-test the boxes (each box's own effective scale, the standard idiom).
        local hit, after
        for _, b in ipairs(allBoxes) do
            if b.winIdx ~= dragWin then
                local bs = b:GetEffectiveScale()
                local cx, cy = mx / bs, my / bs
                local L, R, Tp, B = b:GetLeft(), b:GetRight(), b:GetTop(), b:GetBottom()
                if L and R and Tp and B and cx >= L and cx <= R and cy >= B and cy <= Tp then
                    hit = b
                    after = cy < (Tp + B) / 2   -- lower half -> drop AFTER this box
                    break
                end
            end
        end

        ResetBorders()
        if hit then
            hit:SetBackdropBorderColor(1, 1, 1, 1)
            dropLine:ClearAllPoints()
            if after then
                -- Drop AFTER: line in the gap just below the box.
                dropLine:SetPoint("TOPLEFT", hit, "BOTTOMLEFT", 0, -1)
                dropLine:SetPoint("TOPRIGHT", hit, "BOTTOMRIGHT", 0, -1)
            else
                -- Drop BEFORE: line in the gap just above the box.
                dropLine:SetPoint("BOTTOMLEFT", hit, "TOPLEFT", 0, 1)
                dropLine:SetPoint("BOTTOMRIGHT", hit, "TOPRIGHT", 0, 1)
            end
            dropLine:Show()
            container._dropAnchor = hit.winIdx
            container._dropAfter = after
        else
            dropLine:Hide()
            container._dropAnchor = nil
            container._dropAfter = nil
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

            -- Full panel label across the bottom, wrapped (so long names like
            -- "Overall Damage Done" stay readable in a narrow box instead of being
            -- clipped); the number sits slightly above center to leave it room.
            local tlabel = box:CreateFontString(nil, "OVERLAY")
            KE:ApplyThemeFont(tlabel, "small")
            tlabel:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 2, 2)
            tlabel:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
            tlabel:SetJustifyH("CENTER")
            tlabel:SetWordWrap(true)
            tlabel:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
            tlabel:SetText((fullLabel and fullLabel(idx)) or "")
            box.tlabel = tlabel

            -- Drag-to-rearrange: a cursor-following ghost shows what you grabbed and
            -- the white insertion line shows where it lands; on release the dragged
            -- window drops at that spot (DM:MoveWindowToSlot, before/after the
            -- hovered box). The per-window "New Column" button handles the one thing
            -- drag can't: splitting a window out into its own column.
            box.winIdx = idx
            box:EnableMouse(true)
            box:RegisterForDrag("LeftButton")
            box:SetScript("OnDragStart", function(self2)
                container._dragWin = self2.winIdx
                container._dropAnchor = nil
                container._dropAfter = nil
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
                local anchor = container._dropAnchor
                local after = container._dropAfter
                container._dragWin = nil
                container._dropAnchor = nil
                container._dropAfter = nil
                if dragWin and anchor and anchor ~= dragWin then
                    local dm = GetDM()
                    if dm and dm.MoveWindowToSlot then dm:MoveWindowToSlot(dragWin, anchor, after) end
                    RebuildPage()
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
                        if rowH < 34 then box.tlabel:Hide() else box.tlabel:Show() end
                    end
                end
                runY = runY + rowH + GAP
            end
            runX = runX + colW + GAP
        end
    end

    container:SetScript("OnSizeChanged", function(_, w) layout(w) end)
    layout(container:GetWidth())
    return container
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
        local schemRow = BuildSchematic(card1, 84, cols, posOf, FullLabelFor)
        card1:AddRow(schemRow, 84)
    end

    -- One row per window: "Window n" + a "New Column" button that splits the window
    -- out into its own column -- the one rearrange drag can't do. (Drag in the map
    -- above handles reorder + stacking.) The button is NOT registered with the
    -- manager (its gating below would be clobbered by manager:UpdateAll); the card's
    -- blocker + alpha cascade still disable it when the module is off.
    for n = 1, #order do
        local idx = order[n]
        local _, _, colLen = FindWindowPos(cols, idx)
        local rowM = GUIFrame:CreateRow(card1.content, Theme.rowHeight)

        local lbl = GUIFrame:CreateText(rowM, "Window " .. n, "", Theme.rowHeight, "hide")
        rowM:AddWidget(lbl, 0.6)
        manager:Register(lbl, "all")

        local newColBtn = GUIFrame:CreateButton(rowM, "New Column", {
            callback = function()
                -- A high target index makes SetWindowColumn create a fresh rightmost
                -- column (it removes idx, drops emptied columns, then clamps the
                -- target to #cols + 1). No-op when the window is already alone.
                if DM and DM.SetWindowColumn then
                    DM:SetWindowColumn(idx, ((cols and #cols) or 0) + 1)
                end
                RebuildPage()
            end,
        })
        rowM:AddWidget(newColBtn, 0.4)
        -- Meaningful only when the window shares its column with others; a window
        -- already alone in its column would just land back where it is.
        newColBtn:SetEnabled((colLen or 1) > 1)

        card1:AddRow(rowM, Theme.rowHeight)
    end

    local arrNoteRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local arrNote = GUIFrame:CreateText(arrNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("Drag") .. " a window in the map onto another to reorder or stack it; " ..
        KE:ColorTextByTheme("New Column") .. " splits one out on its own.\n" ..
        KE:ColorTextByTheme("-") .. " Numbers match the meter on screen. Resize by dragging the gaps in the world (up to " ..
        maxWin .. " windows).",
        Theme.rowHeightLast, "hide")
    arrNoteRow:AddWidget(arrNote, 1)
    manager:Register(arrNote, "all")
    card1:AddRow(arrNoteRow, Theme.rowHeightLast, 0)

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

            -- Column-gap sliders: between column c and c+1, value = left share.
            for c = 1, nCols - 1 do
                local rowS = GUIFrame:CreateRow(sizeCard.content, Theme.rowHeight)
                local slider = GUIFrame:CreateSlider(rowS, "Col " .. c .. " / Col " .. (c + 1) .. " width", {
                    min = 5, max = 95, step = 1,
                    value = (DM and DM.GetColumnBoundaryShare and DM:GetColumnBoundaryShare(c)) or 50,
                    callback = function(val)
                        if DM and DM.SetColumnBoundaryShare then DM:SetColumnBoundaryShare(c, val) end
                        -- Refresh the two neighbours that share a touched column.
                        if colSliders[c - 1] and DM then
                            colSliders[c - 1]:SetValue(DM:GetColumnBoundaryShare(c - 1), true)
                        end
                        if colSliders[c + 1] and DM then
                            colSliders[c + 1]:SetValue(DM:GetColumnBoundaryShare(c + 1), true)
                        end
                    end,
                })
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
                            local rowS = GUIFrame:CreateRow(sizeCard.content, Theme.rowHeight)
                            local slider = GUIFrame:CreateSlider(rowS,
                                "Win " .. topNum .. " / Win " .. botNum .. " height", {
                                min = 5, max = 95, step = 1,
                                value = (DM and DM.GetRowBoundaryShare and DM:GetRowBoundaryShare(c, r)) or 50,
                                callback = function(val)
                                    if DM and DM.SetRowBoundaryShare then DM:SetRowBoundaryShare(c, r, val) end
                                    local rs = rowSliders[c]
                                    if rs and DM then
                                        if rs[r - 1] then rs[r - 1]:SetValue(DM:GetRowBoundaryShare(c, r - 1), true) end
                                        if rs[r + 1] then rs[r + 1]:SetValue(DM:GetRowBoundaryShare(c, r + 1), true) end
                                    end
                                end,
                            })
                            rowS:AddWidget(slider, 1)
                            manager:Register(slider, "all")
                            sizeCard:AddRow(rowS, Theme.rowHeight)
                            rowSliders[c][r] = slider
                        end
                    end
                end
            end

            local szNoteRow = GUIFrame:CreateRow(sizeCard.content, Theme.rowHeightLast)
            local szNote = GUIFrame:CreateText(szNoteRow,
                KE:ColorTextByTheme("Note"),
                KE:ColorTextByTheme("-") .. " Each slider splits just its two neighbours; the rest stay put.\n" ..
                KE:ColorTextByTheme("-") .. " Same effect as dragging that gap between windows in the world.",
                Theme.rowHeightLast, "hide")
            szNoteRow:AddWidget(szNote, 1)
            manager:Register(szNote, "all")
            sizeCard:AddRow(szNoteRow, Theme.rowHeightLast, 0)

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

    -- One row per window (numbered by on-screen position): Enabled · Type · Segment.
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

            local enChk = GUIFrame:CreateCheckbox(rowW, "Window " .. n, {
                value = cfg.Enabled ~= false,
                callback = function(checked) writeField("Enabled", checked) end,
            })
            rowW:AddWidget(enChk, 0.34)
            manager:Register(enChk, "all")

            local typeDd = GUIFrame:CreateDropdown(rowW, "Type", {
                options = METER_TYPE_OPTIONS,
                value = cfg.MeterType or Enum.DamageMeterType.DamageDone,
                callback = function(key) writeField("MeterType", key) end,
            })
            rowW:AddWidget(typeDd, 0.33)
            manager:Register(typeDd, "all")

            local segDd = GUIFrame:CreateDropdown(rowW, "Segment", {
                options = SEGMENT_OPTIONS,
                value = cfg.SessionType or Enum.DamageMeterSessionType.Current,
                callback = function(key) writeField("SessionType", key) end,
            })
            rowW:AddWidget(segDd, 0.33)
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

    ----------------------------------------------------------------
    -- Card 1: Bars
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

    local row1c = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
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
    card1:AddRow(row1c, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Bar Content
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Bar Content", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local iconChk = GUIFrame:CreateCheckbox(row2a, "Show Icon", {
        value = db.ShowIcon ~= false,
        callback = function(checked) db.ShowIcon = checked; ApplySettings() end,
    })
    row2a:AddWidget(iconChk, 0.5)
    manager:Register(iconChk, "all")

    local nameChk = GUIFrame:CreateCheckbox(row2a, "Show Name", {
        value = db.ShowName ~= false,
        callback = function(checked) db.ShowName = checked; ApplySettings() end,
    })
    row2a:AddWidget(nameChk, 0.5)
    manager:Register(nameChk, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local rankChk = GUIFrame:CreateCheckbox(row2b, "Show Rank", {
        value = db.ShowRank == true,
        callback = function(checked) db.ShowRank = checked; ApplySettings() end,
    })
    row2b:AddWidget(rankChk, 0.5)
    manager:Register(rankChk, "all")

    local perSecChk = GUIFrame:CreateCheckbox(row2b, "Show Per-Second", {
        value = db.ShowPerSec ~= false,
        callback = function(checked) db.ShowPerSec = checked; ApplySettings() end,
    })
    row2b:AddWidget(perSecChk, 0.5)
    manager:Register(perSecChk, "all")
    card2:AddRow(row2b, Theme.rowHeight)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local classNameChk = GUIFrame:CreateCheckbox(row2c, "Class-Color Name", {
        value = db.ClassColorName == true,
        callback = function(checked) db.ClassColorName = checked; ApplySettings() end,
    })
    row2c:AddWidget(classNameChk, 0.5)
    manager:Register(classNameChk, "all")

    local selfChk = GUIFrame:CreateCheckbox(row2c, "Always Show Self", {
        value = db.AlwaysShowSelf ~= false,
        callback = function(checked) db.AlwaysShowSelf = checked; ApplySettings() end,
    })
    row2c:AddWidget(selfChk, 0.5)
    manager:Register(selfChk, "all")
    card2:AddRow(row2c, Theme.rowHeight)

    local row2d = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local realmChk = GUIFrame:CreateCheckbox(row2d, "Show Realm Names", {
        value = db.ShowRealm == true,
        callback = function(checked) db.ShowRealm = checked; ApplySettings() end,
    })
    row2d:AddWidget(realmChk, 0.5)
    manager:Register(realmChk, "all")
    card2:AddRow(row2d, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Font
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

    local fontSizeSlider = GUIFrame:CreateSlider(row3a, "Font Size", {
        min = 8, max = 24, step = 1,
        value = db.FontSize or 12,
        callback = function(val) db.FontSize = val; ApplySettings() end,
    })
    row3a:AddWidget(fontSizeSlider, 0.5)
    manager:Register(fontSizeSlider, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local outlineDropdown = GUIFrame:CreateDropdown(row3b, "Font Outline", {
        options = KE:GetFontOutlineOptions(),
        value = db.FontOutline or "OUTLINE",
        callback = function(key) db.FontOutline = key; ApplySettings() end,
    })
    row3b:AddWidget(outlineDropdown, 1)
    manager:Register(outlineDropdown, "all")
    card3:AddRow(row3b, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Backdrop
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
