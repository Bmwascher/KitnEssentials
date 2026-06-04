-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/Window.lua                                  ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: Per-window frame tree + create-once bar pool.  ║
-- ║           Frame construction ONLY -- the render/update   ║
-- ║           path (secret-safe SetValue + text gating) is   ║
-- ║           built in the next chunk. Each window is a      ║
-- ║           header + scroll viewport + content child, with ║
-- ║           BAR_POOL_SIZE bars pre-acquired once and laid   ║
-- ║           out top-to-bottom on the pixel grid.           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DamageMeter: AceModule
local DM = KitnEssentials:GetModule("DamageMeter")

-- File-level upvalues for globals used in construction.
local CreateFrame = CreateFrame
local UIParent = UIParent

---------------------------------------------------------------------------------
-- Constants
--
-- BAR_POOL_SIZE is the fixed number of bar rows each window pre-allocates once.
-- The render layer only ever shows up to this many (VisibleBars is clamped
-- against it), so the pool never grows after CreateWindow -- mirrors the
-- reference's static pre-allocated bar array. RANK_STRINGS caches the "N."
-- rank labels so the render path never builds them per tick.
---------------------------------------------------------------------------------

local BAR_POOL_SIZE = 40

local RANK_STRINGS = {}
for i = 1, BAR_POOL_SIZE do
    RANK_STRINGS[i] = i .. "."
end
DM._RANK_STRINGS = RANK_STRINGS
DM._BAR_POOL_SIZE = BAR_POOL_SIZE

---------------------------------------------------------------------------------
-- Bar row factory
--
-- Builds one bar row. Scripts are wired ONCE here -- the pool reuses rows, so
-- nothing in this factory may be re-run per update. The render chunk fills in
-- icon/text/value and bar fill; this only constructs the widget tree.
--
-- Layout (left -> right inside the fill):
--   [rank] [icon] name .................................... value
-- rank and icon are optional (driven by ShowRank / ShowIcon at render time;
-- both start hidden). name is left-justified after the icon; value is right-
-- justified. The icon lives in its own square frame (row.iconFrame) so the
-- standard KE 1px borders tightly bound the icon, not the whole row.
---------------------------------------------------------------------------------

local function MakeBar(parent)
    local db = DM.db

    local bar = {}

    -- Root clickable row. Pool convention: kit.row is the root frame.
    local row = CreateFrame("Button", nil, parent)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")
    bar.row = row

    -- StatusBar fill covers the whole row; native widget interpolation drives
    -- the value in combat (SetValue accepts secret values; we never do Lua
    -- arithmetic on them).
    row.fill = CreateFrame("StatusBar", nil, row)
    row.fill:SetAllPoints(row)
    row.fill:SetMinMaxValues(0, 1)
    row.fill:SetValue(0)

    -- Icon: square frame anchored left, holding the class/spec texture. The
    -- frame (not the texture) carries the pixel borders, per the KE icon
    -- standard (matches HealerMana / MaintenanceTracker).
    row.iconFrame = CreateFrame("Frame", nil, row.fill)
    row.iconFrame:SetPoint("LEFT", row.fill, "LEFT", 0, 0)
    row.icon = row.iconFrame:CreateTexture(nil, "OVERLAY")
    row.icon:SetAllPoints(row.iconFrame)
    KE:ApplyIconZoom(row.icon)
    KE:AddIconBorders(row.iconFrame)
    row.icon:Hide()

    -- Text overlays sit above the icon/borders (icon borders are OVERLAY
    -- sublevel 7; FontStrings on the fill render on top by frame order).
    local fontFace = db and db.FontFace
    local fontSize = db and db.FontSize
    local fontOutline = db and db.FontOutline

    -- Rank: far-left, left-justified (shown only when ShowRank is set).
    row.rank = row.fill:CreateFontString(nil, "OVERLAY")
    row.rank:SetJustifyH("LEFT")
    KE:ApplyFontToText(row.rank, fontFace, fontSize, fontOutline)
    row.rank:Hide()

    -- Name: left-justified, fills the space between icon and value.
    row.name = row.fill:CreateFontString(nil, "OVERLAY")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    KE:ApplyFontToText(row.name, fontFace, fontSize, fontOutline)

    -- Value: right-justified ("total | perSec" string built by the render
    -- layer; safe to concatenate even when secret).
    row.value = row.fill:CreateFontString(nil, "OVERLAY")
    row.value:SetPoint("RIGHT", row.fill, "RIGHT", -3, 0)
    row.value:SetJustifyH("RIGHT")
    KE:ApplyFontToText(row.value, fontFace, fontSize, fontOutline)

    -- Per-attribute dirty caches (mirrors the reference). Render layer fills
    -- these; declared here so the fields exist on a fresh row.
    bar._cachedColorClass = nil
    bar._cachedClass = nil
    bar._cachedSrcName = nil
    bar._cachedAmtText = nil

    -- Wire OnClick ONCE. Forward-compatible: calls DM.OpenDetail only if a
    -- later chunk defines it. No detail window exists yet.
    row:SetScript("OnClick", function(_, button)
        if DM.OpenDetail then
            DM:OpenDetail(bar, button)
        end
    end)

    row:Hide()
    return bar
end

---------------------------------------------------------------------------------
-- Window factory
--
-- Builds a fully independent window frame tree (frame + header + scroll
-- viewport + content child) and a create-once bar pool. Rows are pre-acquired
-- once and laid out top-to-bottom on the content child; the render chunk
-- shows/hides and positions the fill, never re-creating widgets.
---------------------------------------------------------------------------------

function DM:CreateWindow(winIdx)
    local W = { idx = winIdx, bars = {} }

    -- Root window frame.
    W.frame = CreateFrame("Frame", "KE_DamageMeter_Window" .. winIdx, UIParent)
    if self.db and self.db.Strata then
        W.frame:SetFrameStrata(self.db.Strata)
    end

    -- Header title FontString. The render layer sets the live text.
    W.header = W.frame:CreateFontString(nil, "OVERLAY")
    W.header:SetPoint("TOPLEFT", W.frame, "TOPLEFT", 4, -2)
    W.header:SetJustifyH("LEFT")
    KE:ApplyFontToText(
        W.header,
        self.db and self.db.FontFace,
        self.db and self.db.FontSize,
        self.db and self.db.FontOutline
    )

    -- Scroll viewport + content child. The content child holds the bar rows;
    -- the render layer scrolls the viewport for virtualization. Sized to 1,1
    -- here (the render/layout pass and OnSizeChanged drive real dimensions).
    W.body = CreateFrame("ScrollFrame", nil, W.frame)
    W.body:SetPoint("TOPLEFT", W.header, "BOTTOMLEFT", -4, -2)
    W.body:SetPoint("BOTTOMRIGHT", W.frame, "BOTTOMRIGHT", 0, 0)

    W.content = CreateFrame("Frame", nil, W.body)
    W.content:SetSize(1, 1)
    W.body:SetScrollChild(W.content)
    W.body:SetScript("OnSizeChanged", function(_, width)
        W.content:SetWidth(width)
    end)

    -- Create-once bar pool. The factory closes over W.content so every kit is
    -- parented to this window's content child; Acquire reparents back to it.
    W.pool = KE.FramePool:New(function() return MakeBar(W.content) end)

    -- Pixel-snapped row geometry so bars sit on the physical pixel grid.
    -- stride is the per-row advance (height + spacing); snapping all three
    -- keeps cumulative offsets aligned rather than drifting by sub-pixels.
    local barHeight = (self.db and self.db.BarHeight) or 16
    local barSpacing = (self.db and self.db.BarSpacing) or 0
    local snapHeight = KE:PixelSnap(barHeight)
    local snapSpacing = KE:PixelSnap(barSpacing)
    local snapStride = KE:PixelSnap(barHeight + barSpacing)

    -- Pre-acquire the full pool once and lay rows out top-to-bottom. Each row
    -- starts hidden; the render layer shows up to VisibleBars of them.
    for i = 1, BAR_POOL_SIZE do
        local bar = W.pool:Acquire(W.content)
        local row = bar.row

        row:SetHeight(snapHeight)
        row:ClearAllPoints()
        local yOff = -(i - 1) * snapStride
        row:SetPoint("TOPLEFT", W.content, "TOPLEFT", 0, yOff)
        row:SetPoint("TOPRIGHT", W.content, "TOPRIGHT", 0, yOff)

        -- Square icon sized to the (snapped) row height.
        row.iconFrame:SetSize(snapHeight, snapHeight)

        -- rank/name anchor left after the icon; resolved fully in the render
        -- chunk (which knows ShowIcon/ShowRank). Provide a sane default anchor
        -- so the row is laid out even before first render.
        row.rank:ClearAllPoints()
        row.rank:SetPoint("LEFT", row.fill, "LEFT", 3, 0)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row.iconFrame, "RIGHT", 3, 0)
        row.name:SetPoint("RIGHT", row.value, "LEFT", -3, 0)

        -- Back-reference for the render layer / OnClick (forward-compatible).
        bar.win = W
        row:Hide()
        W.bars[i] = bar
    end

    -- Snapped geometry is reused by the render/layout chunk.
    W._snapHeight = snapHeight
    W._snapSpacing = snapSpacing
    W._snapStride = snapStride

    self.windows_rt = self.windows_rt or {}
    self.windows_rt[winIdx] = W

    return W
end
