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
local IsInInstance = IsInInstance
local math_min = math.min
local math_ceil = math.ceil
local wipe = wipe

-- Symmetric clamp helper for the splitter drag math (plain numbers only --
-- cursor coords, pixel sizes, ratios; never a secret value).
local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

-- 1-based index of the column holding window `w` in a Columns array (nil if absent
-- or `w` is nil). Plain table walk over window storage indices -- never a secret.
local function _ColumnOf(cols, w)
    if not w then return nil end
    for c = 1, #cols do
        local wins = cols[c].Windows
        if wins then
            for r = 1, #wins do
                if wins[r] == w then return c end
            end
        end
    end
    return nil
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
local GAP = KE:PixelSnap(1)

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

---------------------------------------------------------------------------------
-- Chat size sync (Damage Meter side)
--
-- The Chat module can be told to size its panel to this meter. What is matched
-- is the backdrop CARRIER rectangle -- the rectangle the backdrop frame
-- occupies, whether or not it is painting anything. Either module's backdrop
-- can be switched off, and refusing to match an unpainted one would kill the
-- feature for a legitimate configuration; the carrier still bounds the content
-- either way.
---------------------------------------------------------------------------------

-- The carrier rectangle, or nil. Reads the extents LayoutDock already stashed
-- rather than recomputing the column walk -- two copies of that arithmetic drift
-- apart on the first change to either.
--
-- This is the rectangle the dock WOULD occupy. It is NOT a claim that the dock is
-- on screen: a visibility condition can hide the meter while its rectangle stays
-- perfectly well defined, and the hold rule depends on that separation.
--
-- nil means "no rectangle", never "a rectangle of zero size". A missing header
-- stash on the behind-bars path returns nil rather than treating it as zero:
-- UpdateBackdrop's own fallback recomputes the header instead of dropping it, so
-- zero would report a rectangle one header band taller than what is drawn.
function DM:GetBackdropRectSize()
    if not self.enabled then return nil end
    local db = self.db
    if not db then return nil end

    local w = self._dockContentW
    local h = self._dockContentH
    if not w or not h or w <= 0 or h <= 0 then return nil end

    local pad = self:_BackdropPad()
    w = w + 2 * pad
    h = h + 2 * pad

    -- Mirrors UpdateBackdrop exactly, including the enabled half: the flag is
    -- only honoured while the backdrop is on.
    if db.BackdropEnabled ~= false and db.BackdropBehindBarsOnly then
        local headerH = self._dockHeaderH
        if not headerH then return nil end
        h = h - headerH
    end
    if h <= 0 then return nil end

    return w, h
end

-- Tell Chat the rectangle changed. Guard order is load-bearing:
--
-- The Chat test comes FIRST so nothing is memoised while the toggle is off --
-- a memo written then would go stale and suppress the first real push after it
-- is turned on. db.Enabled is part of that test because Chat's own teardown
-- hides the panel but leaves it allocated, so a panel test alone cannot answer
-- "is Chat running".
--
-- The dirty check is NOT an optimisation. The splitter drag path re-lays the
-- dock out every frame while the user drags, and UpdatePanel walks every chat
-- frame in the game.
--
-- The memo is written BEFORE the call. Nothing in UpdatePanel reaches back here
-- today, so the two orders are equivalent; this way round a future re-entrant
-- path cannot loop.
function DM:PushSizeToChat()
    local CHAT = KitnEssentials:GetModule("Chat", true)
    if not (CHAT and CHAT.db and CHAT.db.Enabled and CHAT.db.MatchDamageMeterSize) then return end
    if not CHAT.panel or not CHAT.UpdatePanel then return end

    local w, h = self:GetBackdropRectSize()
    if not w or not h then return end
    if self._chatPushW == w and self._chatPushH == h then return end

    self._chatPushW, self._chatPushH = w, h
    CHAT:UpdatePanel()
end

-- Hand Chat back its own size on a genuine module disable. Not for a temporary
-- hide: a chat panel that resized on every combat transition would be
-- intolerable, and the visibility early-returns in UpdateBackdrop already hold
-- the last size for free.
--
-- The memo clear is unconditional and comes before the guards. Without it,
-- disabling and re-enabling an unchanged meter computes the same rectangle the
-- memo already holds, the dirty check suppresses the push, and Chat never comes
-- back.
--
-- Nothing recomputes a size here. The caller has already cleared self.enabled,
-- so GetBackdropRectSize answers nil and Chat's resolver falls back to the
-- user's own saved values.
function DM:ReleaseChatSize()
    self._chatPushW, self._chatPushH = nil, nil

    local CHAT = KitnEssentials:GetModule("Chat", true)
    if not (CHAT and CHAT.db and CHAT.db.Enabled and CHAT.db.MatchDamageMeterSize) then return end
    if not CHAT.panel or not CHAT.UpdatePanel then return end

    CHAT:UpdatePanel()
end

function DM:EnsureDock()
    if self.dock then return self.dock end

    local dock = CreateFrame("Frame", "KE_DamageMeter_Dock", UIParent, "BackdropTemplate")
    self.dock = dock

    -- Backdrop carrier. The bg/border lives on this child rather than the dock
    -- itself so it can wrap ONLY the bar rows (db.BackdropBehindBarsOnly): its top
    -- edge insets past the header band while the dock frame still spans everything
    -- as the layout parent + EditMode mover. Held at the dock's own frame level in
    -- UpdateBackdrop -> below the child windows (dock+1), so bars/text draw over it.
    dock.skin = CreateFrame("Frame", nil, dock, "BackdropTemplate")

    -- Never render off-screen: a stale saved Position (resolution change) or an
    -- edit-mode drag could otherwise strand the whole meter outside the viewport.
    -- Same flag as the MPT HUD root; the windows are dock children, so clamping
    -- the dock covers the entire meter.
    dock:SetClampedToScreen(true)

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

    -- ----- Display-position map (column-then-row = on-screen reading order) -----
    -- Maps storage index -> its 1-based position walking columns left->right, then
    -- rows top->bottom. Both the in-world index badges (set below) and the GUI
    -- "Window N" rows read this so the number a window shows always matches its
    -- on-screen position. Built from DockWindowIndices so the GUI (which calls the
    -- same fn) and the badges agree exactly. Reused scratch -> no per-pass garbage.
    self._posScratch = self._posScratch or {}
    local order = self:DockWindowIndices(self._posScratch)
    self._winDisplayPos = self._winDisplayPos or {}
    local posMap = self._winDisplayPos
    wipe(posMap)
    for i = 1, #order do posMap[order[i]] = i end

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

                    -- Stamp the on-screen display position onto the index badge
                    -- (preview/edit aid). posMap is column-then-row order, so the
                    -- badge reads 1,2,3... left->right / top->bottom regardless of
                    -- the window's storage index.
                    if W.indexBadge and W.indexBadge.text then
                        W.indexBadge.text:SetText(tostring(posMap[idx] or idx))
                    end

                    -- Re-apply header-icon visibility now that the display position is
                    -- known: secondary windows (pos > 1) force reveal-on-hover, #1 keeps
                    -- the configured behavior. ApplyHeaderIcons reads self._winDisplayPos.
                    self:ApplyHeaderIcons(W)

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

---------------------------------------------------------------------------------
-- Visibility conditions
--
-- Optional "hide unless ..." gates layered on top of the /kes dm toggle. ShouldShow is
-- the single predicate UpdateBackdrop consults; RefreshVisibility re-runs UpdateBackdrop
-- but ONLY when a condition is enabled (so the default pays nothing on transitions) and
-- is called from the combat on/off funnel (StartTicker / StopTicker, Core.lua) + the GUI
-- preview hooks. Instance changes already flow through ApplyActiveContext -> UpdateBackdrop
-- (a context change), which re-consults ShouldShow, so OnlyInInstances needs no extra hook.
---------------------------------------------------------------------------------

-- True when the dock should be on screen given the visibility conditions. The GUI
-- preview (_guiPreview) and the EditMode overlay always force-show, so a user with a hide
-- condition enabled can still see + position the meter while configuring it. Combat is
-- read via GroupInCombat (UnitAffectingCombat -- never secret); instance via IsInInstance.
function DM:ShouldShow()
    local db = self.db
    if not db then return true end
    if self._guiPreview then return true end
    if KE.EditMode and KE.EditMode.isActive then return true end
    if db.HideOutOfCombat and not self:GroupInCombat() then return false end
    if db.OnlyInInstances and not IsInInstance() then return false end
    return true
end

-- Re-evaluate the visibility conditions by re-running UpdateBackdrop -- but ONLY when a
-- hide condition is actually enabled, so the default (no conditions) path does zero extra
-- work on every combat/zone transition. enabled-guarded so an OnDisable-time StopTicker
-- can't re-show the dock mid-teardown.
function DM:RefreshVisibility()
    if not self.enabled then return end
    local db = self.db
    if not db then return end
    if db.HideOutOfCombat or db.OnlyInInstances then
        self:UpdateBackdrop()
    end
end

-- Sizes + skins the dock. If LayoutDock placed zero windows, the dock is hidden.
-- Reuses self._dockBackdropCfg so the per-call backdrop config allocates no
-- garbage on the structural path.
function DM:UpdateBackdrop()
    local db = self.db
    if not db then return end

    -- Module disabled: keep the dock hidden regardless of which caller reached here.
    -- UpdateBackdrop is the ONLY place the dock is shown, so gating disabled here makes
    -- every path respect OnDisable. The debounced RefreshDock already guards on enabled,
    -- but the direct callers do not -- HidePreview (fired when the GUI closes / the page
    -- is left) and ApplySettings both call UpdateBackdrop straight through. Without this
    -- guard, disabling the module hides the dock via OnDisable, then closing the GUI
    -- re-shows the dock + backdrop via HidePreview -> UpdateBackdrop (the reported
    -- "backdrop persists after disable" bug). Bail before EnsureDock so a disabled
    -- module never lazily builds the dock just to hide it.
    if not self.enabled then
        if self.dock then self.dock:Hide() end
        return
    end

    self:EnsureDock()
    local dock = self.dock

    -- Runtime hide (/kes dm toggle sets self._hidden). UpdateBackdrop is the only
    -- place the dock is shown, so gating here keeps it hidden across every
    -- refresh; hiding the parent dock also hides all child windows even though
    -- RenderWindow still calls Show() on them.
    if self._hidden then dock:Hide() return end

    -- Visibility conditions (HideOutOfCombat / OnlyInInstances). Single consult point;
    -- ShouldShow force-shows during GUI preview / EditMode. When a condition fails, hide
    -- the dock (and thus all child windows) without touching size/skin.
    if not self:ShouldShow() then dock:Hide() return end

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
    -- Skin the carrier child (not the dock) so "behind bars only" can drop the
    -- frame off the header band: inset the top by the header band height ONLY
    -- (not pad + header) so the top edge sits pad above the first bar — the
    -- same border + pad inset as the other three sides. Flush with the bar top
    -- instead would bury the 1px top border under the bars, which draw a frame
    -- level above the skin. The title floats above the box. Otherwise it covers
    -- the whole dock (unchanged look). Re-level each pass in case a strata
    -- change re-based the dock.
    local skin = dock.skin
    skin:SetFrameLevel(dock:GetFrameLevel())
    skin:ClearAllPoints()
    if cfg.Enabled and db.BackdropBehindBarsOnly then
        local headerH = self._dockHeaderH or KE:PixelSnap((db.FontSize or 12) + 6)
        skin:SetPoint("TOPLEFT", dock, "TOPLEFT", 0, -headerH)
        skin:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, 0)
    else
        skin:SetAllPoints(dock)
    end
    KE:ApplyBackdrop(skin, cfg)

    -- Reposition (the dock's own anchor is unchanged, but re-running re-snaps to
    -- the pixel grid after a size change and re-applies the strata).
    KE:ApplyFramePosition(dock, db.Position, db)

    dock:Show()

    -- Last, and only here: this is where the dock's outer size is actually set.
    -- The early returns above hide without recomputing it, so there is nothing
    -- new to push from any of them.
    self:PushSizeToChat()
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
    -- A structural change (AddWindow) can introduce a window that has never been
    -- rendered -- its header FontString is still empty and, out of combat, no ticker is
    -- running to paint it. Render once here, right after the layout/position pass, so the
    -- new window's header + bars populate in the same frame (no blank-header flash). Gated
    -- on a flag so ordinary RefreshDock calls (e.g. per-frame splitter drags) don't render.
    if DM._needsRenderAfterLayout then
        DM._needsRenderAfterLayout = false
        if DM.Tick then DM:Tick() end
    end
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
-- One-time width repair for the squished-dock seed
--
-- That default seed wrote WidthRatio 0.5 on both columns. LayoutDock reads
-- WidthRatio as an ABSOLUTE multiplier of db.Width (colW = baseW * ratio), not a
-- normalized share like RowRatios -- so 0.5 rendered each column at half width
-- and the dock looked squished. The seed now ships WidthRatio 1; this repairs
-- profiles already created by that build. Called from OnEnable after
-- the seed block (so it also covers existing profiles, which skip that block).
-- Stamped to run once, and gated on the EXACT untouched bad-seed signature
-- (two columns, both 0.5, windows {1} and {2,3}) so a GUI-built or dragged dock
-- never matches and is left alone.
---------------------------------------------------------------------------------
function DM:RepairSquishedDock()
    local db = self.db
    if not db or db._dockWidthRepaired then return end
    db._dockWidthRepaired = true   -- run once (also marks fresh/correct profiles)

    local cols = db.Dock and db.Dock.Columns
    if not cols or #cols ~= 2 then return end
    local c1, c2 = cols[1], cols[2]
    if not (c1 and c2) then return end

    local sig =
        c1.WidthRatio == 0.5 and c2.WidthRatio == 0.5
        and c1.Windows and c1.Windows[1] == 1 and c1.Windows[2] == nil
        and c2.Windows and c2.Windows[1] == 2 and c2.Windows[2] == 3 and c2.Windows[3] == nil
    if sig then
        c1.WidthRatio = 1
        c2.WidthRatio = 1
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
-- membership is edited by dragging in the GUI map -> MoveWindowToSlot /
-- MoveWindowToNewColumn). Equal ratios are seeded; the splitters adjust from there.
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
    -- Paint the new window after the deferred layout pass (see _DoDockRefresh) so its
    -- header doesn't stay blank until the next combat tick.
    self._needsRenderAfterLayout = true
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

-- Drag-and-drop reorder: move `idx` to land next to `targetIdx` -- BEFORE it
-- (default) or AFTER it (after=true, i.e. the cursor was in the target's lower
-- half). idx is pulled from wherever it is (emptied columns dropped), then
-- inserted into targetIdx's column at the target's row (+1 when after) -- so a
-- drop reorders within a column AND moves across columns with one gesture. The
-- inserted RowRatios entry seeds at the column average (a fair ~1/(n+1) share).
-- All plain table edits on db.Dock.Columns -- never a secret. No-op when
-- idx == targetIdx.
function DM:MoveWindowToSlot(idx, targetIdx, after)
    local db = self.db
    local cols = db and db.Dock and db.Dock.Columns
    if not cols or idx == targetIdx then return end

    -- Remove idx from its current column.
    for c = #cols, 1, -1 do
        local wins = cols[c] and cols[c].Windows
        if wins then
            for r = #wins, 1, -1 do
                if wins[r] == idx then
                    table.remove(wins, r)
                    if cols[c].RowRatios then table.remove(cols[c].RowRatios, r) end
                end
            end
        end
    end

    -- Drop any column emptied by the removal, so the re-find below indexes the
    -- post-removal structure (same remove-then-drop ordering as MoveWindowToNewColumn).
    for c = #cols, 1, -1 do
        if cols[c] and cols[c].Windows and #cols[c].Windows == 0 then
            table.remove(cols, c)
        end
    end

    -- Re-find the target (still present -- it isn't idx) and insert idx before it.
    for c = 1, #cols do
        local wins = cols[c].Windows
        if wins then
            for r = 1, #wins do
                if wins[r] == targetIdx then
                    cols[c].RowRatios = cols[c].RowRatios or {}
                    local rr = cols[c].RowRatios
                    -- Seed the new row at the column's AVERAGE ratio so the dropped
                    -- window takes a fair ~1/(n+1) share and the others keep their
                    -- relative proportions -- a flat 1 against {0.4,0.6} would have
                    -- the dropped window grab ~50% of the column on landing.
                    local sum, n = 0, 0
                    for k = 1, #rr do
                        local v = rr[k]
                        if type(v) == "number" and v > 0 then sum = sum + v; n = n + 1 end
                    end
                    local seed = (n > 0) and (sum / n) or 1
                    -- Insert before the target, or after it (one row lower) when the
                    -- drop landed in the target's lower half.
                    local at = after and (r + 1) or r
                    table.insert(wins, at, idx)
                    table.insert(rr, at, seed)
                    self:RefreshDock()
                    return
                end
            end
        end
    end

    -- Target vanished (shouldn't happen): fall back to appending to column 1 so the
    -- window is never lost.
    if cols[1] then
        cols[1].Windows = cols[1].Windows or {}
        cols[1].RowRatios = cols[1].RowRatios or {}
        cols[1].Windows[#cols[1].Windows + 1] = idx
        cols[1].RowRatios[#cols[1].RowRatios + 1] = 1
        self:RefreshDock()
    end
end

-- Drag-to-edge: peel `idx` into a BRAND-NEW column. The new column lands between
-- the columns identified by `leftRep` (a representative window of the column that
-- should sit immediately LEFT of the new one) and `rightRep` (immediately RIGHT) --
-- whichever survives idx's removal decides the insert position, so a gap whose
-- neighbour column WAS idx's own (and thus drops out) still lands the new column in
-- the right place. Pass nil for an outer edge (leftRep nil = new leftmost column;
-- rightRep nil = new rightmost). All plain table edits on db.Dock.Columns -- never
-- a secret. WidthRatio seeds at 1 (the splitters adjust from there).
function DM:MoveWindowToNewColumn(idx, leftRep, rightRep)
    local db = self.db
    local cols = db and db.Dock and db.Dock.Columns
    if not cols then return end

    -- Remove idx from its current column.
    for c = #cols, 1, -1 do
        local wins = cols[c] and cols[c].Windows
        if wins then
            for r = #wins, 1, -1 do
                if wins[r] == idx then
                    table.remove(wins, r)
                    if cols[c].RowRatios then table.remove(cols[c].RowRatios, r) end
                end
            end
        end
    end

    -- Drop any column emptied by the removal, so the re-find below indexes the
    -- post-removal structure (mirrors MoveWindowToSlot's ordering).
    for c = #cols, 1, -1 do
        if cols[c] and cols[c].Windows and #cols[c].Windows == 0 then
            table.remove(cols, c)
        end
    end

    -- Land immediately LEFT of rightRep's column; else immediately RIGHT of
    -- leftRep's column; else append to the far right.
    local at
    local rc = _ColumnOf(cols, rightRep)
    if rc then
        at = rc
    else
        local lc = _ColumnOf(cols, leftRep)
        at = lc and (lc + 1) or (#cols + 1)
    end
    if at < 1 then at = 1 end
    if at > #cols + 1 then at = #cols + 1 end

    table.insert(cols, at, { WidthRatio = 1, Windows = { idx }, RowRatios = { 1 } })
    self:RefreshDock()
end

---------------------------------------------------------------------------------
-- Boundary split sizing (GUI counterpart to the drag-splitters)
--
-- One split per GAP between two adjacent panes -- the exact pair the in-world
-- drag-splitter for that gap adjusts. pct is the FIRST pane's share of just that
-- PAIR (left column of a column gap, top window of a row gap); the pair's combined
-- ratio is conserved and every OTHER pane is left untouched -- so the sliders never
-- "fight" each other the way a redistribute-across-all model did. Plain numbers
-- only (ratios / percentages); never a secret. clamp() is the file-local helper.
---------------------------------------------------------------------------------

-- Column gap between colIdx and colIdx+1. pct = left column's share of the pair.
function DM:SetColumnBoundaryShare(colIdx, pct)
    local cols = self.db and self.db.Dock and self.db.Dock.Columns
    local a = cols and cols[colIdx]
    local b = cols and cols[colIdx + 1]
    if not (a and b) then return end
    pct = clamp(pct, 5, 95) / 100
    local pair = ((a.WidthRatio) or 1) + ((b.WidthRatio) or 1)
    if pair <= 0 then pair = 2 end
    a.WidthRatio = pct * pair
    b.WidthRatio = pair - a.WidthRatio
    self:RefreshDock()
end

function DM:GetColumnBoundaryShare(colIdx)
    local cols = self.db and self.db.Dock and self.db.Dock.Columns
    local a = cols and cols[colIdx]
    local b = cols and cols[colIdx + 1]
    if not (a and b) then return 50 end
    local av, bv = (a.WidthRatio) or 1, (b.WidthRatio) or 1
    local pair = av + bv
    if pair <= 0 then return 50 end
    return (av / pair) * 100
end

-- Row gap between rowIdx and rowIdx+1 in column colIdx. pct = top window's share.
function DM:SetRowBoundaryShare(colIdx, rowIdx, pct)
    local cols = self.db and self.db.Dock and self.db.Dock.Columns
    local col = cols and cols[colIdx]
    local ratios = col and col.RowRatios
    if not ratios or not ratios[rowIdx] or not ratios[rowIdx + 1] then return end
    pct = clamp(pct, 5, 95) / 100
    local pair = ((ratios[rowIdx]) or 0) + ((ratios[rowIdx + 1]) or 0)
    if pair <= 0 then pair = 2 end
    ratios[rowIdx] = pct * pair
    ratios[rowIdx + 1] = pair - ratios[rowIdx]
    self:RefreshDock()
end

function DM:GetRowBoundaryShare(colIdx, rowIdx)
    local cols = self.db and self.db.Dock and self.db.Dock.Columns
    local col = cols and cols[colIdx]
    local ratios = col and col.RowRatios
    if not ratios or not ratios[rowIdx] or not ratios[rowIdx + 1] then return 50 end
    local a, b = (ratios[rowIdx]) or 0, (ratios[rowIdx + 1]) or 0
    local pair = a + b
    if pair <= 0 then return 50 end
    return (a / pair) * 100
end

---------------------------------------------------------------------------------
-- Boundary share RANGE (GUI slider min/max == the in-world drag-splitter floor)
--
-- The boundary sliders edit the FIRST pane's share of a conserved pair. Left
-- unbounded (5-95) a slider can shrink a pane below the same floor the drag-
-- splitter enforces (80px per column; header + one bar per row), squashing a
-- window to unusable. These return the (minPct, maxPct) for a gap's slider so the
-- pane can't be dragged below that floor. minPct is the floor expressed as a % of
-- the pair's combined px (the pair size is fixed -- a boundary move conserves it),
-- clamped to [5, 45] so the slider always keeps a usable span even when the pair
-- is too small to honor the full floor (the drag-splitter still enforces the hard
-- floor in the world). Plain numbers only -- never a secret.
---------------------------------------------------------------------------------

-- Column gap colIdx|colIdx+1: floor = 80px per column (matches SplitterOnUpdate col).
function DM:GetColumnBoundaryRange(colIdx)
    local cols = self.db and self.db.Dock and self.db.Dock.Columns
    local a = cols and cols[colIdx]
    local b = cols and cols[colIdx + 1]
    if not (a and b) then return 5, 95 end
    local baseW = (self.db and self.db.Width) or 240
    if baseW <= 0 then baseW = 240 end
    -- Prefer the pixel-snapped column widths LayoutDock recorded (exact match to the
    -- drag-splitter's pairPx in SplitterStartDrag); fall back to baseW * ratio before
    -- the first layout pass.
    local ciA = self._dockColInfo and self._dockColInfo[colIdx]
    local ciB = self._dockColInfo and self._dockColInfo[colIdx + 1]
    local pairPx = ((ciA and ciA.w) or (baseW * ((a.WidthRatio) or 1)))
                 + ((ciB and ciB.w) or (baseW * ((b.WidthRatio) or 1)))
    if pairPx <= 0 then return 5, 95 end
    local minPct = clamp(math_ceil(80 / pairPx * 100), 5, 45)
    return minPct, 100 - minPct
end

-- Row gap rowIdx|rowIdx+1 in column colIdx: floor = header + one bar (matches the
-- row SplitterStartDrag min). The column's content height is Hdock (the single
-- natural height = header + visible*stride); the pair occupies its normalized
-- share of that.
function DM:GetRowBoundaryRange(colIdx, rowIdx)
    local db = self.db
    local cols = db and db.Dock and db.Dock.Columns
    local col = cols and cols[colIdx]
    local ratios = col and col.RowRatios
    if not (ratios and ratios[rowIdx] and ratios[rowIdx + 1]) then return 5, 95 end

    -- Header band + per-bar stride: prefer the values LayoutDock stashed (exact
    -- pixel-snapped match to the splitter); recompute from db if not laid out yet.
    local headerH = self._dockHeaderH or KE:PixelSnap((db.FontSize or 12) + 6)
    local stride = self._dockStride or (KE:PixelSnap(db.BarHeight or 16) + KE:PixelSnap(db.BarSpacing or 2))
    if stride <= 0 then stride = 1 end
    local visible = math_min((db.VisibleBars or 10), self.BAR_POOL_SIZE or 40)
    local Hdock = headerH + visible * stride

    -- The rows split the column's content height MINUS the inter-row gaps (matches
    -- LayoutDock's availH), so subtract them before apportioning the pair's share.
    local nRows = #ratios
    local availH = Hdock - (nRows - 1) * GAP
    if availH < 0 then availH = 0 end

    local sumR = 0
    for r = 1, #ratios do
        local rr = ratios[r]
        if type(rr) == "number" and rr > 0 then sumR = sumR + rr end
    end
    if sumR <= 0 then return 5, 95 end

    local pairRatio = ((ratios[rowIdx]) or 0) + ((ratios[rowIdx + 1]) or 0)
    local pairPx = availH * (pairRatio / sumR)
    if pairPx <= 0 then return 5, 95 end

    local minPct = clamp(math_ceil((headerH + stride) / pairPx * 100), 5, 45)
    return minPct, 100 - minPct
end
