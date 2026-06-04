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
local math_min = math.min
local wipe = wipe

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

    local pad = db.BackdropPadding or 6
    local context = self:GetActiveContext()

    local columns = db.Dock and db.Dock.Columns
    if not columns then columns = {} end

    -- Track which windows the dock actually placed this pass, so any built-but-
    -- unreferenced (or disabled) window gets hidden afterward.
    self._dockPlaced = self._dockPlaced or {}
    local placed = self._dockPlaced
    wipe(placed)

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

                    placed[idx] = true
                end

                runY = runY + rowH + GAP
            end
        end

        runX = runX + colW + GAP
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

    -- Zero placed windows: nothing to wrap, hide the dock and bail. `next` on the
    -- placed-set returns nil only when LayoutDock placed no window this pass.
    local placed = self._dockPlaced
    if not (placed and next(placed) ~= nil) then
        dock:Hide()
        return
    end

    local pad = db.BackdropPadding or 6
    local dockW = self._dockContentW or 0
    local dockH = self._dockContentH or 0

    dock:SetSize(dockW + 2 * pad, dockH + 2 * pad)

    self._dockBackdropCfg = self._dockBackdropCfg or {}
    local cfg = self._dockBackdropCfg
    cfg.Enabled = true
    cfg.BorderSize = 1
    cfg.Color = db.BackdropColor
    cfg.BorderColor = self:_ResolveDockBorderColor()
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

function DM:RefreshDock()
    if self._dockRefreshPending then return end
    self._dockRefreshPending = true

    C_Timer.After(0, function()
        DM._dockRefreshPending = false
        if not DM.enabled then return end
        DM:LayoutDock()
        DM:UpdateBackdrop()
    end)
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
