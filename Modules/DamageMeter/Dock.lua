-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/Dock.lua                                    ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: Multi-window PROPORTIONAL DOCK wrapped by ONE  ║
-- ║           auto-sizing shared backdrop. Owns frame size + ║
-- ║           placement for every window; the windows only   ║
-- ║           own their internal body/content/bar layout.    ║
-- ║           Structural-change only (NOT per tick).         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DamageMeter: AceModule
local DM = KitnEssentials:GetModule("DamageMeter")

-- File-level upvalues for globals.
local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Timer = C_Timer
local GetCursorPosition = GetCursorPosition
local math_min = math.min
local wipe = wipe

-- Symmetric clamp helper for the splitter drag math (plain numbers only --
-- cursor coords, pixel sizes, ratios; never a secret value).
local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

---------------------------------------------------------------------------------
-- In-game test scaffold
--
-- When DEBUG_DOCK_TEST is true, the dock is seeded at enable time with the
-- user's M+ layout (3 windows, 2 columns) so tiling + backdrop can be verified
-- WITHOUT a GUI. SELF-HEAL: when the flag is false but a prior seed marker is
-- present, the single-window default is restored and the marker cleared, so
-- flipping the flag off cleanly reverts. See DM:MaybeSeedDockTest below.
---------------------------------------------------------------------------------

local DEBUG_DOCK_TEST = false

-- Inter-window / inter-column gap, snapped to the pixel grid once at file load.
-- A local const (not a DB key) per the Phase 2 geometry model.
local GAP = KE:PixelSnap(4)

---------------------------------------------------------------------------------
-- Dock frame
--
-- Created once; holds the shared backdrop and parents every window. Idempotent.
---------------------------------------------------------------------------------

-- Creates self.dock once and positions it. Returns the existing dock on repeat
-- calls. The dock is a BackdropTemplate frame (required by KE:ApplyBackdrop) and
-- a plain UIParent child (non-secure) -- SetSize/SetPoint/Show/Hide on it are all
-- combat-safe with no InCombatLockdown guard.
-- Effective backdrop padding: the configured pad when the backdrop is enabled,
-- 0 when it is off (so windows sit flush with the dock edge instead of being
-- inset by phantom padding). Read by LayoutDock / UpdateBackdrop / _LayoutSplitters
-- so window placement, backdrop sizing, and splitter hit-zones agree.
function DM:_BackdropPad()
    local db = self.db
    if not db then return 0 end
    if db.BackdropEnabled == false then return 0 end
    return db.BackdropPadding or 1
end

function DM:EnsureDock()
    if self.dock then return self.dock end

    local dock = CreateFrame("Frame", "KE_DamageMeter_Dock", UIParent, "BackdropTemplate")
    self.dock = dock

    -- Position + strata via the shared helper (KE:ApplyFramePosition reads
    -- self.db.Strata internally and runs the always-on pixel snap).
    if self.db then
        KE:ApplyFramePosition(dock, self.db.Position, self.db)
    end

    return dock
end

---------------------------------------------------------------------------------
-- Window-set resolution
--
-- The set of window indices the dock references is the flattened union of every
-- column's Windows array, clamped to db.MaxWindows. Iterating columns in order,
-- then rows top->bottom, yields a STABLE order used everywhere (window creation,
-- VisibleWindows, layout) so Tick paints deterministically.
---------------------------------------------------------------------------------

-- Fills `out` (a caller-owned scratch table, wiped first) with the referenced
-- window indices in column-then-row order, clamped to db.MaxWindows and the
-- BAR_POOL_SIZE-window cap. Returns `out`. Duplicates are skipped (a window
-- index may only appear once). Reuses the scratch table to avoid per-call
-- garbage on the structural path.
function DM:DockWindowIndices(out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end

    local db = self.db
    local dock = db and db.Dock
    local columns = dock and dock.Columns
    if not columns then return out end

    local maxWindows = (db and db.MaxWindows) or 5

    -- Track seen indices so a window referenced by two columns isn't duplicated.
    self._dockSeen = self._dockSeen or {}
    local seen = self._dockSeen
    wipe(seen)

    for c = 1, #columns do
        local col = columns[c]
        local windows = col and col.Windows
        if windows then
            for r = 1, #windows do
                local idx = windows[r]
                if type(idx) == "number" and idx >= 1 and idx <= maxWindows and not seen[idx] then
                    seen[idx] = true
                    out[#out + 1] = idx
                end
            end
        end
    end

    return out
end

---------------------------------------------------------------------------------
-- Window creation (login-spread)
--
-- Builds every referenced window one-per-frame via a chained C_Timer.After(0)
-- loop so login never sees an all-windows-in-one-frame hitch. After the last
-- window lands, the dock is laid out, the backdrop sized, and a paint kicked.
---------------------------------------------------------------------------------

-- Creates all dock-referenced windows, one per frame. Each is built via the
-- existing DM:CreateWindow factory (which now parents to self.dock). After the
-- final window: LayoutDock -> UpdateBackdrop -> Tick. Idempotent windows
-- (already-built ones are skipped) so a re-run after a structural DB change
-- only fills gaps.
function DM:CreateAllWindows()
    self:EnsureDock()

    self._dockCreateList = self._dockCreateList or {}
    local list = self:DockWindowIndices(self._dockCreateList)

    self.windows_rt = self.windows_rt or {}

    local n = #list
    if n == 0 then
        -- Nothing referenced: still settle the (empty) dock + backdrop.
        self:LayoutDock()
        self:UpdateBackdrop()
        if self.Tick then self:Tick() end
        return
    end

    -- Snapshot the indices into a stable list the chained closure walks; the
    -- scratch table may be reused by other callers between frames.
    local indices = {}
    for i = 1, n do indices[i] = list[i] end

    local pos = 0
    local function createNext()
        if not self.enabled then return end
        pos = pos + 1
        if pos > #indices then
            -- All windows built: structural layout + backdrop + first paint.
            self:LayoutDock()
            self:UpdateBackdrop()
            if self.Tick then self:Tick() end
            return
        end

        local idx = indices[pos]
        if not self.windows_rt[idx] then
            self:CreateWindow(idx)
        end

        C_Timer.After(0, createNext)
    end

    createNext()
end

---------------------------------------------------------------------------------
-- Dock layout (structural only)
--
-- Computes the proportional tiling geometry for every referenced window and
-- SetSize + SetPoint's each window frame relative to self.dock's content origin
-- (the top-left INSIDE the backdrop padding). Per the locked geometry model,
-- every window shares the same natural full height (same font/bar settings), so
-- the dock content height is that single natural height; columns split width by
-- WidthRatio and rows split a column's height by RowRatios. NOT per tick --
-- called only on structural change (enable, context-swap, add/remove window).
---------------------------------------------------------------------------------

-- Lays out the dock. Hides windows that exist but aren't referenced (or whose
-- resolved context is disabled). Stores the computed content extents on
-- self._dockContentW / self._dockContentH for UpdateBackdrop to size the
-- backdrop. Caller (or this function) follows with UpdateBackdrop.
function DM:LayoutDock()
    local db = self.db
    if not db then return end

    self:EnsureDock()

    -- ----- Shared per-layout geometry (computed ONCE) -----
    local headerH = KE:PixelSnap((db.FontSize or 12) + 6)
    local stride  = KE:PixelSnap(db.BarHeight or 16) + KE:PixelSnap(db.BarSpacing or 2)
    if stride <= 0 then stride = 1 end
    local visible = math_min((db.VisibleBars or 10) , self.BAR_POOL_SIZE or 40)
    local Hnat    = headerH + visible * stride        -- natural full-window height
    local Hdock   = Hnat                                -- dock content height
    local baseW   = db.Width or 240                     -- per-column natural width (ratio 1)

    local pad = self:_BackdropPad()
    local context = self:GetActiveContext()

    -- Stash the header band + per-row stride so the splitter drag tick can
    -- compute the per-pane minimum (header + 1 bar) without recomputing from db.
    self._dockHeaderH = headerH
    self._dockStride  = stride

    -- Splitter boundary descriptors, rebuilt every layout pass. A reused scratch
    -- list (wiped at the top of each LayoutDock) so the structural path allocates
    -- no per-call garbage. Each entry describes ONE invisible drag hit-zone
    -- between two adjacent placed panes; _LayoutSplitters consumes it below.
    self._splitterSpecs = self._splitterSpecs or {}
    local specs = self._splitterSpecs
    wipe(specs)

    local columns = db.Dock and db.Dock.Columns
    if not columns then columns = {} end

    -- Track which windows the dock actually placed this pass, so any built-but-
    -- unreferenced (or disabled) window gets hidden afterward.
    self._dockPlaced = self._dockPlaced or {}
    local placed = self._dockPlaced
    wipe(placed)

    -- Per-column geometry record (reused scratch, wiped here). Each entry holds
    -- the column's content-space x/width and whether it placed any window this
    -- pass; the COL-boundary emit below walks adjacent entries.
    self._dockColInfo = self._dockColInfo or {}
    local colInfo = self._dockColInfo
    for i = #colInfo, 1, -1 do colInfo[i] = nil end

    -- ----- Column x positions (left -> right) -----
    -- colX_c = sum(colW_1..colW_{c-1}) + (c-1)*GAP. Walk columns once, building
    -- the running x offset; colW is recomputed per column (no extra table).
    local runX = 0
    local nCols = #columns

    for c = 1, nCols do
        local col = columns[c]
        local colW = KE:PixelSnap(baseW * ((col and col.WidthRatio) or 1))
        local colX = runX

        local rows = (col and col.Windows) or {}
        local ratios = (col and col.RowRatios) or {}
        local nRows = #rows

        -- Track the previous placed row in THIS column so a ROW boundary can be
        -- emitted between two adjacent placed rows. prevRowIdx is the RowRatios
        -- index (r) of the last placed row; prevBottom is its content-space
        -- bottom edge (rowY + rowH). prevWinIdx is the window index there.
        local prevRowIdx, prevBottom, prevWinIdx
        local colHadPlaced = false

        -- Normalize the row ratios to sum = 1 (guard sum <= 0 -> equal split).
        local ratioSum = 0
        for r = 1, nRows do
            local rr = ratios[r]
            if type(rr) == "number" and rr > 0 then
                ratioSum = ratioSum + rr
            end
        end
        local equalSplit = (ratioSum <= 0)

        -- Available height for the rows (gaps consume the rest).
        local availH = Hdock - (nRows - 1) * GAP
        if availH < 0 then availH = 0 end

        local runY = 0
        for r = 1, nRows do
            local idx = rows[r]
            if type(idx) == "number" then
                local norm
                if equalSplit then
                    norm = (nRows > 0) and (1 / nRows) or 1
                else
                    local rr = ratios[r]
                    if type(rr) == "number" and rr > 0 then
                        norm = rr / ratioSum
                    else
                        norm = 0
                    end
                end

                local rowH = KE:PixelSnap(norm * availH)
                local rowY = runY

                -- Resolve the window + its live context config. Only place a
                -- window whose resolved config is Enabled; otherwise it is left
                -- out of `placed` and hidden below.
                self.windows_rt = self.windows_rt or {}
                local W = self.windows_rt[idx]
                local cfg = self:ResolveWindowConfig(idx, context)
                if W and W.frame and cfg and cfg.Enabled then
                    -- Window rect relative to the dock CONTENT origin (top-left
                    -- inside padding): x = colX, y = -rowY, w = colW, h = rowH.
                    -- Anchored to the dock's TOPLEFT, the offset is
                    -- (pad + x, y - pad) = (pad + colX, -rowY - pad).
                    W.frame:ClearAllPoints()
                    W.frame:SetSize(colW, rowH)
                    W.frame:SetPoint("TOPLEFT", self.dock, "TOPLEFT", pad + colX, -rowY - pad)
                    W.frame:Show()

                    -- Drive the body width immediately so bars are full width on
                    -- the first paint (don't wait for OnSizeChanged). The window's
                    -- own LayoutWindow owns the body height + content height.
                    if W.content then
                        W.content:SetWidth(colW)
                    end

                    -- Stash the computed rect (content coords, px) for the
                    -- splitter drag tick to snapshot the pair's pixel sizes.
                    W._dockRect = W._dockRect or {}
                    local rc = W._dockRect
                    rc.x, rc.y, rc.w, rc.h = colX, rowY, colW, rowH

                    placed[idx] = true
                    colHadPlaced = true

                    -- ROW boundary: emit between this placed row and the previous
                    -- placed row in the same column when they are CONSECUTIVE
                    -- RowRatios entries (both panes present). The consecutive
                    -- guard keeps the drag math's RowRatios[rowIdx] /
                    -- RowRatios[rowIdx+1] pairing exact -- a skipped (disabled)
                    -- row between two placed rows would break that pairing, so no
                    -- splitter is emitted across a gap. The gap top is the
                    -- previous row's bottom (content y, measured down); the strip
                    -- spans the column width.
                    if prevRowIdx and r == prevRowIdx + 1 then
                        specs[#specs + 1] = {
                            kind   = "row",
                            colIdx = c,
                            rowIdx = prevRowIdx,
                            x      = colX,
                            y      = prevBottom,
                            w      = colW,
                            idxA   = prevWinIdx,
                            idxB   = idx,
                        }
                    end

                    prevRowIdx  = r
                    prevBottom  = rowY + rowH
                    prevWinIdx  = idx

                    -- Advance the cursor ONLY for a placed row, so a disabled or
                    -- not-yet-built row consumes zero vertical space and the next
                    -- placed row packs flush to the top instead of leaving a blank
                    -- band (and shifting later windows down). Survivors keep their
                    -- ratio-derived size -- they do not expand to reclaim the freed
                    -- space; that renormalization is deferred because it would have
                    -- to re-key the splitter pair-ratio math off placed-order rather
                    -- than structural RowRatios indices.
                    runY = runY + rowH + GAP
                end
            end
        end

        -- Record this column's content-space geometry + whether it placed any
        -- window, for the COL-boundary emit after the loop.
        colInfo[c] = colInfo[c] or {}
        local ci = colInfo[c]
        ci.x, ci.w, ci.placed = colX, colW, colHadPlaced

        runX = runX + colW + GAP
    end

    -- ----- COL boundaries -----
    -- Emit one COL hit-zone between every pair of ADJACENT columns that BOTH
    -- placed at least one window. The gap left edge is the left column's right
    -- edge (content x); the strip spans the full dock content height.
    for c = 1, nCols - 1 do
        local ciA = colInfo[c]
        local ciB = colInfo[c + 1]
        if ciA and ciB and ciA.placed and ciB.placed then
            specs[#specs + 1] = {
                kind   = "col",
                colIdx = c,
                x      = ciA.x + ciA.w,
                y      = 0,
                h      = Hdock,
            }
        end
    end

    -- ----- Total dock content extents -----
    -- dockW = sum(all colW) + (nCols-1)*GAP. runX accumulated colW + GAP per
    -- column, so subtract the trailing GAP. dockH = Hdock.
    local dockW = runX
    if nCols > 0 then dockW = dockW - GAP end
    if dockW < 0 then dockW = 0 end

    self._dockContentW = dockW
    self._dockContentH = Hdock

    -- Hide any built window the dock did NOT place this pass (unreferenced or
    -- disabled context) so a stale frame from a prior layout doesn't float.
    if self.windows_rt then
        for idx, W in pairs(self.windows_rt) do
            if not placed[idx] and W.frame then
                W.frame:Hide()
            end
        end
    end

    -- Position the drag splitters over the boundaries emitted above (also hides
    -- any pooled splitter the new layout no longer needs).
    self:_LayoutSplitters()
end

---------------------------------------------------------------------------------
-- Shared backdrop
--
-- Sizes self.dock to the content bounding box + padding on every side and
-- applies the KE backdrop with the resolved border style. Hides the dock when
-- no window is placed (no empty backdrop floating).
---------------------------------------------------------------------------------

-- Resolves the backdrop border color (r,g,b,a) from db.BackdropBorderStyle into
-- the reused self._dockBorderColor table, so KE:ApplyBackdrop reads a {r,g,b,a}
-- array. "neutral" -> db.BackdropBorderColor ; "accent" -> KE:GetAccentColor() ;
-- "theme" -> KE:GetAccentColor("theme") ; anything else falls back to neutral.
function DM:_ResolveDockBorderColor()
    local db = self.db
    self._dockBorderColor = self._dockBorderColor or {}
    local out = self._dockBorderColor

    local style = db and db.BackdropBorderStyle
    if style == "accent" then
        local r, g, b, a = KE:GetAccentColor()
        out[1], out[2], out[3], out[4] = r, g, b, a or 1
    elseif style == "theme" then
        local r, g, b, a = KE:GetAccentColor("theme")
        out[1], out[2], out[3], out[4] = r, g, b, a or 1
    else
        -- neutral (default + fallback): the configured neutral color.
        local n = db and db.BackdropBorderColor
        out[1] = (n and n[1]) or 0.47
        out[2] = (n and n[2]) or 0.47
        out[3] = (n and n[3]) or 0.51
        out[4] = (n and n[4]) or 1
    end

    return out
end

-- Sizes + skins the dock. If LayoutDock placed zero windows, the dock is hidden.
-- Reuses self._dockBackdropCfg so the per-call backdrop config allocates no
-- garbage on the structural path.
function DM:UpdateBackdrop()
    local db = self.db
    if not db then return end

    self:EnsureDock()
    local dock = self.dock

    -- Runtime hide (/kedm toggle sets self._hidden). UpdateBackdrop is the only
    -- place the dock is shown, so gating here keeps it hidden across every
    -- refresh; hiding the parent dock also hides all child windows even though
    -- RenderWindow still calls Show() on them.
    if self._hidden then dock:Hide() return end

    -- Zero placed windows: nothing to wrap, hide the dock and bail. `next` on the
    -- placed-set returns nil only when LayoutDock placed no window this pass.
    local placed = self._dockPlaced
    if not (placed and next(placed) ~= nil) then
        dock:Hide()
        return
    end

    local pad = self:_BackdropPad()
    local dockW = self._dockContentW or 0
    local dockH = self._dockContentH or 0

    dock:SetSize(dockW + 2 * pad, dockH + 2 * pad)

    -- BackdropEnabled off: clear the wrapping bg/border (KE:ApplyBackdrop with
    -- Enabled=false calls SetBackdrop(nil)) but still size/show the dock so its
    -- child windows remain visible — they simply "float" with no frame around them.
    self._dockBackdropCfg = self._dockBackdropCfg or {}
    local cfg = self._dockBackdropCfg
    if db.BackdropEnabled == false then
        cfg.Enabled = false
    else
        cfg.Enabled = true
        cfg.BorderSize = 1
        cfg.Color = db.BackdropColor
        cfg.BorderColor = self:_ResolveDockBorderColor()
    end
    KE:ApplyBackdrop(dock, cfg)

    -- Reposition (the dock's own anchor is unchanged, but re-running re-snaps to
    -- the pixel grid after a size change and re-applies the strata).
    KE:ApplyFramePosition(dock, db.Position, db)

    dock:Show()
end

---------------------------------------------------------------------------------
-- Debounced structural refresh
--
-- Single entry point other code calls when the dock STRUCTURE changes (enable,
-- context-swap, add/remove window). Coalesces N rapid calls in one frame to a
-- single LayoutDock + UpdateBackdrop via a one-shot C_Timer.After(0) guard --
-- mirrors the OnSessionUpdated debounce style in Core.lua (boolean pending flag).
---------------------------------------------------------------------------------

-- Hoisted once (captures only the DM file upvalue) so the per-frame splitter-drag
-- path -- SplitterOnUpdate -> RefreshDock every frame while dragging -- reuses one
-- function reference instead of allocating a fresh closure per frame.
local function _DoDockRefresh()
    DM._dockRefreshPending = false
    if not DM.enabled then return end
    DM:LayoutDock()
    DM:UpdateBackdrop()
end

function DM:RefreshDock()
    if self._dockRefreshPending then return end
    self._dockRefreshPending = true
    C_Timer.After(0, _DoDockRefresh)
end

---------------------------------------------------------------------------------
-- Drag splitters (invisible pane-resize hit-zones)
--
-- Between two stacked windows (a ROW splitter) and between two columns (a COL
-- splitter) sits an INVISIBLE drag hit-zone. There is NO line at rest -- only a
-- faint highlight on hover/drag. Dragging mutates the adjacent panes' ratios
-- (RowRatios / WidthRatio), clamped to a minimum pane size with the pair's
-- combined size conserved, live + persisted (the ratios live in the saved AceDB
-- db.Dock.Columns tables, so mutating in place persists automatically).
--
-- Splitters only deal with NON-secret values (cursor coords, frame sizes,
-- ratios). The render layer's secret-value contract is untouched: splitters
-- never run per Tick -- they only re-layout via the debounced RefreshDock during
-- an active drag, and are positioned on the structural LayoutDock pass.
---------------------------------------------------------------------------------

-- Hit-zone thickness (centered on each gap), snapped to the pixel grid once.
local HITW = KE:PixelSnap(8)

-- ROW drag tick: cursor DOWN (screen y decreases) grows the TOP pane. The pair's
-- combined height (and ratio sum) is conserved; each pane is clamped to a header
-- band + one bar minimum. COL drag tick: cursor RIGHT grows the LEFT column.
local function SplitterOnUpdate(s)
    if not s._dragging then return end
    local self = DM

    local db = self.db
    if not db or not db.Dock or not db.Dock.Columns then
        s._dragging = false
        s:SetScript("OnUpdate", nil)
        return
    end

    -- Degenerate pair size (a zero/negative _pairPx from a collapsed layout)
    -- would NaN the ratio math (newAPx / s._pairPx) and corrupt the saved
    -- profile. Stop the drag cleanly -- detach the OnUpdate, don't divide.
    if not s._pairPx or s._pairPx <= 0 then
        s._dragging = false
        s:SetScript("OnUpdate", nil)
        return
    end

    local mx, my = GetCursorPosition()
    local scale = s._scale or 1
    if scale <= 0 then scale = 1 end

    if s.kind == "row" then
        local col = db.Dock.Columns[s.colIdx]
        if not (col and col.RowRatios) then
            s._dragging = false
            s:SetScript("OnUpdate", nil)
            return
        end

        -- cursor DOWN -> my DECREASES -> dPx POSITIVE -> top pane grows.
        local dPx = (s._startMY - my) / scale
        local minPx = s._minPx or 1
        local newAPx = clamp(s._aPx + dPx, minPx, s._pairPx - minPx)
        local newRatioA = s._pairRatio * (newAPx / s._pairPx)

        col.RowRatios[s.rowIdx]     = newRatioA
        col.RowRatios[s.rowIdx + 1] = s._pairRatio - newRatioA
    else -- "col"
        local colA = db.Dock.Columns[s.colIdx]
        local colB = db.Dock.Columns[s.colIdx + 1]
        if not (colA and colB) then
            s._dragging = false
            s:SetScript("OnUpdate", nil)
            return
        end

        -- cursor RIGHT -> mx INCREASES -> dPx POSITIVE -> left column grows.
        local dPx = (mx - s._startMX) / scale
        local minPx = 80
        local baseW = db.Width or 240
        if baseW <= 0 then baseW = 240 end
        local newAPx = clamp(s._aPx + dPx, minPx, s._pairPx - minPx)

        colA.WidthRatio = newAPx / baseW
        colB.WidthRatio = (s._pairPx - newAPx) / baseW
    end

    -- Debounced: coalesces to one LayoutDock + UpdateBackdrop per frame, and
    -- re-runs _LayoutSplitters so this splitter tracks the moving boundary.
    self:RefreshDock()
end

local function SplitterStopDrag(s)
    if not s._dragging then return end
    s._dragging = false
    s:SetScript("OnUpdate", nil)
    if not s._hovered then
        s.hi:Hide()
    end
    -- One final settle (the ratios are already mutated in place + persisted).
    DM:RefreshDock()
end

local function SplitterStartDrag(s)
    local self = DM
    local db = self.db

    -- Defensive: splitters only exist for a multi-window config, whose db.Dock is
    -- always profile-owned. Bail if the structure isn't present (never deep-copy
    -- or rebuild db.Dock -- the ratios ARE the saved profile).
    if not (db and db.Dock and db.Dock.Columns and db.Dock.Columns[s.colIdx]) then
        s._dragging = false
        return
    end

    local scale = self.dock and self.dock:GetEffectiveScale() or 1
    if scale <= 0 then scale = 1 end
    local mx, my = GetCursorPosition()

    s._dragging = true
    s._scale    = scale
    s._startMX  = mx
    s._startMY  = my

    if s.kind == "row" then
        local col = db.Dock.Columns[s.colIdx]
        if not (col and col.RowRatios) then s._dragging = false return end

        local WA = self.windows_rt and self.windows_rt[s.idxA]
        local WB = self.windows_rt and self.windows_rt[s.idxB]
        local rcA = WA and WA._dockRect
        local rcB = WB and WB._dockRect
        if not (rcA and rcB) then s._dragging = false return end

        s._aPx = rcA.h
        s._bPx = rcB.h
        s._pairPx = s._aPx + s._bPx

        local ra = col.RowRatios[s.rowIdx]
        local rb = col.RowRatios[s.rowIdx + 1]
        s._pairRatio = ((type(ra) == "number" and ra) or 0)
            + ((type(rb) == "number" and rb) or 0)

        -- Minimum pane = header band + one bar (stashed by LayoutDock).
        local headerH = self._dockHeaderH or 0
        local stride  = self._dockStride or 1
        s._minPx = headerH + stride
        -- Degenerate guard: a pair smaller than 2*min can't honor the clamp.
        if s._pairPx < 2 * s._minPx then s._minPx = s._pairPx / 2 end
    else -- "col"
        local colA = db.Dock.Columns[s.colIdx]
        local colB = db.Dock.Columns[s.colIdx + 1]
        if not (colA and colB) then s._dragging = false return end

        -- Read the live column widths from the per-column geometry recorded by
        -- LayoutDock (content-space px). Falls back to baseW * WidthRatio.
        local baseW = db.Width or 240
        if baseW <= 0 then baseW = 240 end
        local ciA = self._dockColInfo and self._dockColInfo[s.colIdx]
        local ciB = self._dockColInfo and self._dockColInfo[s.colIdx + 1]
        s._aPx = (ciA and ciA.w) or (baseW * ((colA.WidthRatio) or 1))
        s._bPx = (ciB and ciB.w) or (baseW * ((colB.WidthRatio) or 1))
        s._pairPx = s._aPx + s._bPx
    end

    s.hi:Show()
    s:SetScript("OnUpdate", SplitterOnUpdate)
end

-- Returns a pooled splitter (building one on first need, scripts wired ONCE).
-- Each splitter is a Button parented to the dock, sitting ABOVE the windows so
-- it is grabbable, with a faint white highlight texture hidden at rest.
function DM:_AcquireSplitter()
    self._splitters = self._splitters or {}
    self._splitterActive = self._splitterActive or 0

    local n = self._splitterActive + 1
    self._splitterActive = n

    local s = self._splitters[n]
    if s then return s end

    s = CreateFrame("Button", nil, self.dock)
    s:EnableMouse(true)

    -- Faint highlight only; NO texture visible unless hovered/dragging.
    s.hi = s:CreateTexture(nil, "OVERLAY")
    s.hi:SetAllPoints()
    s.hi:SetColorTexture(1, 1, 1, 0.12)
    s.hi:Hide()

    s:SetScript("OnEnter", function(self2)
        self2._hovered = true
        self2.hi:Show()
    end)
    s:SetScript("OnLeave", function(self2)
        self2._hovered = false
        if not self2._dragging then
            self2.hi:Hide()
        end
    end)
    s:SetScript("OnMouseDown", SplitterStartDrag)
    s:SetScript("OnMouseUp", SplitterStopDrag)
    -- If the splitter is hidden mid-drag (e.g. a structural relayout removed it),
    -- end the drag cleanly so no orphaned OnUpdate keeps mutating ratios.
    s:SetScript("OnHide", SplitterStopDrag)

    self._splitters[n] = s
    return s
end

-- Positions one splitter per boundary spec emitted by LayoutDock, then hides any
-- pooled splitter beyond the active count. Splitters sit 10 frame levels above
-- the dock so they overlay the windows and remain grabbable.
function DM:_LayoutSplitters()
    local db = self.db
    if not db then return end

    local dock = self.dock
    if not dock then return end

    local specs = self._splitterSpecs
    self._splitterActive = 0
    if not specs then return end

    local pad = self:_BackdropPad()
    local level = dock:GetFrameLevel() + 10

    for i = 1, #specs do
        local spec = specs[i]
        local s = self:_AcquireSplitter()

        -- Carry the boundary identity onto the splitter for the drag handlers.
        s.kind   = spec.kind
        s.colIdx = spec.colIdx
        s.rowIdx = spec.rowIdx
        s.idxA   = spec.idxA
        s.idxB   = spec.idxB

        s:SetFrameLevel(level)
        s:ClearAllPoints()

        if spec.kind == "row" then
            -- Strip straddles the gap midline (content-y = spec.y + GAP/2),
            -- HITW thick. Top content-y = mid - HITW/2. Content -> dock offset:
            -- offsetX = pad + contentX ; offsetY = -(contentY) - pad.
            local topY = spec.y + GAP / 2 - HITW / 2
            s:SetSize(spec.w, HITW)
            s:SetPoint("TOPLEFT", dock, "TOPLEFT", pad + spec.x, -topY - pad)
        else -- "col"
            -- Strip straddles the gap midline (content-x = spec.x + GAP/2),
            -- HITW thick, spanning the full dock content height.
            local leftX = spec.x + GAP / 2 - HITW / 2
            s:SetSize(HITW, spec.h)
            s:SetPoint("TOPLEFT", dock, "TOPLEFT", pad + leftX, -(spec.y) - pad)
        end

        s:Show()
    end

    -- Hide every pooled splitter past the active count (stale boundaries).
    if self._splitters then
        for i = self._splitterActive + 1, #self._splitters do
            local s = self._splitters[i]
            if s then s:Hide() end
        end
    end
end

---------------------------------------------------------------------------------
-- Test-scaffold seed / self-heal
--
-- Called from OnEnable BEFORE the dock is built. When DEBUG_DOCK_TEST is true,
-- seeds the demo M+ dock (3 windows, 2 columns) into the saved db and marks
-- _dockTestSeeded. When the flag is false but the marker is set, restores the
-- single-window default and clears the marker (clean revert when the flag is
-- flipped off). Writing to the saved db is acceptable for a test flag given the
-- self-heal path. Returns nothing.
---------------------------------------------------------------------------------

function DM:MaybeSeedDockTest()
    local db = self.db
    if not db then return end

    if DEBUG_DOCK_TEST then
        -- Seed ONCE (guard on the marker) so dragged splitter ratios persist across
        -- /reload. For a fresh demo, flip the flag off + /reload (the self-heal below
        -- clears the marker), then back on.
        if db._dockTestSeeded then return end

        db.Dock = db.Dock or {}
        db.Dock.Columns = {
            { WidthRatio = 1, Windows = { 1 },    RowRatios = { 1 } },
            { WidthRatio = 1, Windows = { 2, 3 }, RowRatios = { 0.6, 0.4 } },
        }

        db.Windows = db.Windows or {}
        db.Windows[1] = {
            Contexts = {
                Default = {
                    Enabled = true,
                    MeterType = Enum.DamageMeterType.DamageDone,
                    SessionType = Enum.DamageMeterSessionType.Current,
                },
            },
        }
        db.Windows[2] = {
            Contexts = {
                Default = {
                    Enabled = true,
                    MeterType = Enum.DamageMeterType.HealingDone,
                    SessionType = Enum.DamageMeterSessionType.Current,
                },
            },
        }
        db.Windows[3] = {
            Contexts = {
                Default = {
                    Enabled = true,
                    MeterType = Enum.DamageMeterType.DamageTaken,
                    SessionType = Enum.DamageMeterSessionType.Current,
                },
            },
        }

        db._dockTestSeeded = true
        return
    end

    -- Flag off but a prior seed exists: revert to the single-window default and
    -- clear the marker so the next enable is clean.
    if db._dockTestSeeded then
        db.Dock = db.Dock or {}
        db.Dock.Columns = {
            { WidthRatio = 1, Windows = { 1 }, RowRatios = { 1 } },
        }
        db.Windows = db.Windows or {}
        db.Windows[2] = nil
        db.Windows[3] = nil
        db._dockTestSeeded = nil
    end
end

---------------------------------------------------------------------------------
-- Structural editing (GUI-driven)
--
-- The dock STRUCTURE is db.Dock.Columns (a flat list of columns, each holding a
-- Windows index array + WidthRatio + RowRatios). These helpers are the only
-- writers the GUI uses to add/remove windows and switch the arrangement; each
-- finishes with RefreshDock (debounced LayoutDock + UpdateBackdrop). Split ratios
-- are owned by the in-world drag splitters, never here.
---------------------------------------------------------------------------------

-- Derives the arrangement mode from the column structure (NOT stored):
--   one window per column          -> "Horizontal"
--   all windows in a single column  -> "Vertical"
--   anything else                   -> "Custom"
function DM:GetArrangement()
    local cols = self.db and self.db.Dock and self.db.Dock.Columns
    if not cols or #cols == 0 then return "Custom" end
    local nCols = #cols
    local total, multi = 0, false
    for c = 1, nCols do
        local w = cols[c] and cols[c].Windows
        local n = (w and #w) or 0
        total = total + n
        if n > 1 then multi = true end
    end
    if nCols == total and not multi then return "Horizontal" end
    if nCols == 1 then return "Vertical" end
    return "Custom"
end

-- Rewrites db.Dock.Columns for the "Horizontal" or "Vertical" mode, preserving the
-- current set of window indices (stable dock order). "Custom" is a no-op (column
-- membership is edited by SetWindowColumn). Equal ratios are seeded; the splitters
-- adjust from there.
function DM:SetArrangement(mode)
    local db = self.db
    if not db then return end
    db.Dock = db.Dock or {}

    self._arrScratch = self._arrScratch or {}
    local found = self:DockWindowIndices(self._arrScratch)
    local list = {}
    for i = 1, #found do list[i] = found[i] end
    if #list == 0 then list = { 1 } end

    if mode == "Horizontal" then
        local cols = {}
        for i = 1, #list do
            cols[i] = { WidthRatio = 1, Windows = { list[i] }, RowRatios = { 1 } }
        end
        db.Dock.Columns = cols
    elseif mode == "Vertical" then
        local wins, ratios = {}, {}
        for i = 1, #list do
            wins[i] = list[i]
            ratios[i] = 1
        end
        db.Dock.Columns = { { WidthRatio = 1, Windows = wins, RowRatios = ratios } }
    end
    -- "Custom": leave the structure as-is.

    self:RefreshDock()
end

-- Adds a new window: claims the lowest free index 1..MaxWindows, seeds a Default
-- context, appends it as a new column, builds the runtime frame, and refreshes.
-- No-op at the MaxWindows cap.
function DM:AddWindow()
    local db = self.db
    if not db then return end
    db.Windows = db.Windows or {}

    local maxWin = db.MaxWindows or 5
    local newIdx
    for i = 1, maxWin do
        if not db.Windows[i] then newIdx = i; break end
    end
    if not newIdx then return end

    db.Windows[newIdx] = {
        Contexts = {
            Default = {
                Enabled = true,
                MeterType = Enum.DamageMeterType.DamageDone,
                SessionType = Enum.DamageMeterSessionType.Current,
            },
        },
    }

    db.Dock = db.Dock or {}
    db.Dock.Columns = db.Dock.Columns or {}
    db.Dock.Columns[#db.Dock.Columns + 1] =
        { WidthRatio = 1, Windows = { newIdx }, RowRatios = { 1 } }

    if self.CreateWindow then self:CreateWindow(newIdx) end
    self:RefreshDock()
end

-- Removes the given window index from the structure and config. Refuses to remove
-- the last remaining referenced window (a meter with zero windows has nothing to
-- show). The runtime frame is left built but unreferenced; LayoutDock hides it, so
-- re-adding the index later reuses the frame (no leak).
function DM:RemoveWindow(idx)
    local db = self.db
    if not db or not db.Dock or not db.Dock.Columns then return end

    self._arrScratch = self._arrScratch or {}
    if #self:DockWindowIndices(self._arrScratch) <= 1 then return end

    local cols = db.Dock.Columns
    for c = #cols, 1, -1 do
        local col = cols[c]
        local wins = col and col.Windows
        if wins then
            for r = #wins, 1, -1 do
                if wins[r] == idx then
                    table.remove(wins, r)
                    if col.RowRatios then table.remove(col.RowRatios, r) end
                end
            end
            if #wins == 0 then table.remove(cols, c) end
        end
    end

    if db.Windows then db.Windows[idx] = nil end
    self:RefreshDock()
end

-- Moves a window index into the target column (1-based). Used by the Custom-mode
-- column pickers. Removes the index from its current column (dropping the column
-- if it empties) and appends it to the target; clamps target to the column count.
function DM:SetWindowColumn(idx, targetCol)
    local db = self.db
    if not db or not db.Dock or not db.Dock.Columns then return end
    local cols = db.Dock.Columns

    -- Remove from current column(s).
    for c = #cols, 1, -1 do
        local col = cols[c]
        local wins = col and col.Windows
        if wins then
            for r = #wins, 1, -1 do
                if wins[r] == idx then
                    table.remove(wins, r)
                    if col.RowRatios then table.remove(col.RowRatios, r) end
                end
            end
        end
    end

    -- Drop any column that emptied out from the removal above. This must happen
    -- BEFORE clamping so targetCol is clamped against the post-drop column count;
    -- otherwise a dropped lower-index column would shift the insert to targetCol-N.
    for c = #cols, 1, -1 do
        if cols[c] and cols[c].Windows and #cols[c].Windows == 0 then
            table.remove(cols, c)
        end
    end

    -- Clamp target (against the post-drop count) and ensure it exists.
    if targetCol < 1 then targetCol = 1 end
    if targetCol > #cols + 1 then targetCol = #cols + 1 end
    cols[targetCol] = cols[targetCol] or { WidthRatio = 1, Windows = {}, RowRatios = {} }
    local tcol = cols[targetCol]
    tcol.Windows = tcol.Windows or {}
    tcol.RowRatios = tcol.RowRatios or {}
    tcol.Windows[#tcol.Windows + 1] = idx
    tcol.RowRatios[#tcol.RowRatios + 1] = 1

    self:RefreshDock()
end
