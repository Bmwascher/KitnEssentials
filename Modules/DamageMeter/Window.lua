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

-- File-level upvalues for globals used in the per-tick render path.
local issecretvalue = issecretvalue
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local Enum = Enum
local math_min = math.min

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

-- Cross-file constants for the render chunk. Non-underscore names because
-- they are intentional public API on DM (underscore-prefix fields are private
-- by KE convention); the render layer reads these to clamp VisibleBars and
-- label ranks without rebuilding the strings per tick.
DM.RANK_STRINGS = RANK_STRINGS
DM.BAR_POOL_SIZE = BAR_POOL_SIZE

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

-- db is passed in from CreateWindow (which already nil-guards self.db) rather
-- than read as a bare DM.db here; every downstream read still uses the `db and`
-- guard, matching the nil-safety used elsewhere in this file.
local function MakeBar(parent, db)
    local bar = {}

    -- Root clickable row. Pool convention: kit.row is the root frame.
    local row = CreateFrame("Button", nil, parent)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")
    bar.row = row

    -- StatusBar fill covers the whole row; native widget interpolation drives
    -- the value in combat (SetValue accepts secret values; we never do Lua
    -- arithmetic on them). Set the KE bar texture here so the fill is visible on
    -- first show; the render layer re-applies it when StatusBarTexture changes.
    row.fill = CreateFrame("StatusBar", nil, row)
    row.fill:SetAllPoints(row)
    row.fill:SetMinMaxValues(0, 1)
    row.fill:SetValue(0)
    row.fill:SetStatusBarTexture(KE:GetStatusbarPath(db and db.StatusBarTexture or "KitnUI"))

    -- Icon: square frame anchored left, holding the class/spec texture. The
    -- frame (not the texture) carries the pixel borders, per the KE icon
    -- standard (matches HealerMana / MaintenanceTracker). Parented to the row
    -- (not the fill) so it tracks the row's frame level, matching the reference
    -- and other KE bar modules.
    row.iconFrame = CreateFrame("Frame", nil, row)
    row.iconFrame:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon = row.iconFrame:CreateTexture(nil, "OVERLAY")
    row.icon:SetAllPoints(row.iconFrame)
    KE:ApplyIconZoom(row.icon)
    KE:AddIconBorders(row.iconFrame)
    -- Hide the whole icon FRAME (not just the texture) so the 1px borders don't
    -- linger as a black box in the top-left when ShowIcon is off. The icon texture
    -- stays shown within the frame; the render layer toggles the frame's visibility.
    row.iconFrame:Hide()

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

    -- Per-attribute dirty caches. These are the exact fields the render path
    -- (RenderBar) reads/writes; declared here so the factory documents the live
    -- bar state and the fields exist on a fresh row before first paint.
    --   _cachedColorClass -- class driving the fill SetStatusBarColor (NEVER secret)
    --   _cachedIconID     -- specIconID driving the icon SetTexture (NEVER secret);
    --                        keyed on the SPEC icon, not class, so two same-class
    --                        different-spec sources don't share a stale icon
    --   _cachedNameColorClass / _cachedNameColorOn -- name-tint dirty key
    --                        (classFilename + ClassColorName flag; both non-secret)
    --   _cachedName       -- last plain (non-secret) name string set; nil while secret
    --   _cachedVal        -- last plain (non-secret) value string set; nil while secret
    --   _cachedSlot       -- last displayed rank whose "N." label was set (may be
    --                        a pinned player's real rank, not the pool slot index)
    --   _layoutKey        -- (ShowIcon, ShowRank) combo driving the rank-gutter /
    --                        icon / name LEFT anchors; re-anchored only on change
    --   _iconShown / _nameShown / _rankShown -- cached element visibility so a
    --                        stable toggle does no per-tick Show/Hide widget call
    --   _sourceGUID / _sourceCreatureID / _deathRecapID / _classFilename -- source
    --                        identity stashed by RenderBar for DM:OpenDetail (Detail.lua);
    --                        all NeverSecret so the writes are taint-safe
    bar._cachedColorClass = nil
    bar._cachedIconID = nil
    bar._cachedNameColorClass = nil
    bar._cachedNameColorOn = nil
    bar._cachedName = nil
    bar._cachedVal = nil
    bar._cachedSlot = nil
    bar._layoutKey = nil
    bar._iconShown = false
    bar._nameShown = nil
    bar._rankShown = nil
    bar._sourceGUID = nil
    bar._sourceCreatureID = nil
    bar._deathRecapID = nil
    bar._classFilename = nil

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

    -- Parent every window to the shared dock (Phase 2). EnsureDock is idempotent
    -- and creates the dock on first call; resolved at runtime since Dock.lua
    -- loads after Window.lua. Fall back to UIParent only if the dock helper is
    -- somehow unavailable (defensive; should never happen at enable time).
    local parent = UIParent
    if self.EnsureDock then
        parent = self:EnsureDock() or UIParent
    end

    -- Root window frame.
    W.frame = CreateFrame("Frame", "KE_DamageMeter_Window" .. winIdx, parent)
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

    -- Window-index badge: a solid accent-colored chip (top-right) with a bright
    -- white number, shown ONLY during GUI preview / edit so the "Window N" rows in
    -- the config map unambiguously to the numbered window on screen; hidden during
    -- normal play so it never obscures bar data. The badge shows the window's
    -- on-screen DISPLAY POSITION (left->right, top->bottom), NOT its storage index
    -- -- LayoutDock authoritatively sets W.indexBadge.text from self._winDisplayPos
    -- on every structural pass. The text set here is only a placeholder before the
    -- first layout (the chip is hidden until then). A frame+backdrop (not a bare
    -- FontString) so the number reads clearly against any bar color behind it; the
    -- chip sits a few frame levels above the body so it isn't covered by bars.
    W.indexBadge = CreateFrame("Frame", nil, W.frame, "BackdropTemplate")
    W.indexBadge:SetSize(22, 22)
    W.indexBadge:SetPoint("TOPRIGHT", W.frame, "TOPRIGHT", -2, -2)
    W.indexBadge:SetFrameLevel(W.frame:GetFrameLevel() + 6)
    W.indexBadge:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    do
        local ar, ag, ab = KE:GetAccentColor()
        W.indexBadge:SetBackdropColor(ar or 1, ag or 0, ab or 0.55, 0.92)
    end
    W.indexBadge:SetBackdropBorderColor(0, 0, 0, 1)
    W.indexBadge.text = W.indexBadge:CreateFontString(nil, "OVERLAY")
    W.indexBadge.text:SetPoint("CENTER", W.indexBadge, "CENTER", 0, 0)
    KE:ApplyFontToText(W.indexBadge.text, self.db and self.db.FontFace, 15, "OUTLINE")
    W.indexBadge.text:SetTextColor(1, 1, 1, 1)
    W.indexBadge.text:SetText(tostring((self._winDisplayPos and self._winDisplayPos[winIdx]) or winIdx))
    if self._badgesShown then W.indexBadge:Show() else W.indexBadge:Hide() end

    -- Phase 4 header icons: settings / reset / segment, right-aligned, stepping
    -- left from the frame's TOPRIGHT. Built once here (the pool-build below never
    -- re-runs); visibility is driven by db.ShowHeaderIcons (Task 7). The frame level
    -- is bumped above the bars so the icons stay clickable over the body rows. The
    -- callbacks resolve DM methods at click time (Core.lua defines them), matching
    -- the runtime-resolve pattern used by the OnClick -> DM:OpenDetail hook above.
    local function MakeHeaderBtn(tex, tooltip, onClick, xStep)
        local b = CreateFrame("Button", nil, W.frame)
        b:SetSize(14, 14)
        b:SetPoint("TOPRIGHT", W.frame, "TOPRIGHT", -2 - xStep, -3)
        b:SetFrameLevel(W.frame:GetFrameLevel() + 5)
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetAllPoints(b)
        b.icon:SetTexture(tex)
        b.icon:SetVertexColor(0.8, 0.8, 0.8)
        b:SetScript("OnEnter", function(btn)
            btn.icon:SetVertexColor(1, 1, 1)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(btn)
            btn.icon:SetVertexColor(0.8, 0.8, 0.8)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", onClick)
        return b
    end

    W.headerBtns = {}
    W.headerBtns.settings = MakeHeaderBtn("Interface\\GossipFrame\\BinderGossipIcon",
        "Settings", function() DM:HeaderSettings(W) end, 0)
    W.headerBtns.reset = MakeHeaderBtn("Interface\\Buttons\\UI-RefreshButton",
        "Reset", function() DM:HeaderReset(W) end, 18)
    W.headerBtns.segment = MakeHeaderBtn("Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
        "Segment", function() DM:ToggleSegmentMenu(W) end, 36)

    -- Scroll viewport + content child. The content child holds the bar rows;
    -- the render layer scrolls the viewport for virtualization. Sized to 1,1
    -- here; DM:LayoutWindow (below) owns the body's anchors and the real
    -- frame/content dimensions.
    --
    -- The body is anchored to the frame top with a FIXED header-band inset (not
    -- to the header FontString's BOTTOMLEFT) so layout is deterministic and does
    -- not depend on when the render layer first calls SetText -- the header's
    -- font-driven height is zero until then, which previously collapsed the
    -- body's TOPLEFT at construction time. LayoutWindow sets the inset.
    W.body = CreateFrame("ScrollFrame", nil, W.frame)

    W.content = CreateFrame("Frame", nil, W.body)
    W.content:SetSize(1, 1)
    W.body:SetScrollChild(W.content)
    W.body:SetScript("OnSizeChanged", function(_, width)
        -- Guard against a zero/nil width during initial layout (before the
        -- window is given a real size). SetWidth(0) would collapse the content
        -- child and pull every TOPRIGHT row anchor to the left edge.
        if width and width > 0 then
            W.content:SetWidth(width)
        end
    end)

    -- Pixel-snapped row geometry so bars sit on the physical pixel grid.
    -- stride is the per-row advance (height + spacing). snapHeight and
    -- snapSpacing are already on the grid, so their sum is too -- adding them
    -- avoids re-snapping (KE:PixelSnap(barHeight + barSpacing) could round to a
    -- different grid value and drift yOff by a pixel after row 1).
    local barHeight = (self.db and self.db.BarHeight) or 16
    -- 2 matches the Defaults.lua DB default and Dock.lua's stride math (`or 2`).
    -- A 0 fallback here would make the bars build with no inter-row gap while
    -- LayoutDock computed a 2px gap, drifting the physical row stride out of sync
    -- with the virtualization math by 2px per row.
    local barSpacing = (self.db and self.db.BarSpacing) or 2
    local snapHeight = KE:PixelSnap(barHeight)
    local snapSpacing = KE:PixelSnap(barSpacing)
    local snapStride = snapHeight + snapSpacing

    -- Create-once bar rows. KE.FramePool is a render-time pool (ReleaseAll +
    -- Acquire each tick); these rows are permanent and owned by the window, so
    -- a plain build-once loop is used instead. The render layer indexes W.bars
    -- directly and toggles row visibility -- there is no pool to ReleaseAll.
    for i = 1, BAR_POOL_SIZE do
        local bar = MakeBar(W.content, self.db)
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

    -- Establish the window's internal vertical layout (header band, body anchor,
    -- content height) NOW. The dock owns the FRAME size + content WIDTH and assigns
    -- them in DM:LayoutDock (called by CreateAllWindows after every window is
    -- built), so the frame is briefly 0-wide here until that structural pass runs.
    self:LayoutWindow(W)

    self.windows_rt = self.windows_rt or {}
    self.windows_rt[winIdx] = W

    return W
end

---------------------------------------------------------------------------------
-- Window layout
--
-- Phase 2: the dock owns the window FRAME size and the content WIDTH (driven by
-- the column geometry in DM:LayoutDock). This pass owns only the window's
-- INTERNAL vertical layout: the fixed header band at the top, the body anchored
-- immediately below it, and the content child's HEIGHT (VisibleBars rows). The
-- body's BOTTOMRIGHT is anchored to the frame, so it always fills whatever frame
-- size the dock assigns -- LayoutWindow never needs the width. Idempotent +
-- dirty-gated, so RenderWindow can call it every tick to absorb GUI changes
-- (bar count / font size) at near-zero steady-state cost. The body's
-- OnSizeChanged handler remains the safety net that re-syncs content width when
-- the dock resizes the frame.
---------------------------------------------------------------------------------
function DM:LayoutWindow(W)
    local db = self.db
    local fontSize = (db and db.FontSize) or 12
    local visibleDB = (db and db.VisibleBars) or 10
    local stride = W._snapStride or 1

    -- Input-identity short-circuit. The header band and content height derive ONLY
    -- from FontSize, VisibleBars, and the snapped stride -- all plain numbers, never
    -- secret. RenderWindow calls this every tick; when none of those changed the
    -- PixelSnap / min / multiply below reproduce the identical result, so skip them.
    -- ApplyWindowGeometry updates _snapStride before calling here, so keying on it
    -- keeps a bar-size change from being short-circuited away.
    if W._lwFontSize == fontSize and W._lwVisibleBars == visibleDB and W._lwStride == stride then
        return
    end
    W._lwFontSize, W._lwVisibleBars, W._lwStride = fontSize, visibleDB, stride

    -- Fixed header band (font-size driven, snapped). The header FontString is
    -- anchored TOPLEFT inside this band; the body starts immediately below it.
    local headerH = KE:PixelSnap(fontSize + 6)

    -- Body height fits VisibleBars rows (clamped to the pool). Guard a 0 stride.
    local visible = math_min(visibleDB, BAR_POOL_SIZE)
    if stride <= 0 then stride = 1 end
    local barsH = visible * stride

    -- Re-anchor the body only when the header band changes (first call always
    -- runs; SetPoint is idempotent so re-running is harmless either way).
    if W._headerH ~= headerH then
        W._headerH = headerH
        W.body:ClearAllPoints()
        W.body:SetPoint("TOPLEFT", W.frame, "TOPLEFT", 0, -headerH)
        W.body:SetPoint("BOTTOMRIGHT", W.frame, "BOTTOMRIGHT", 0, 0)
    end

    -- Content HEIGHT only (the dock owns the width; the body's OnSizeChanged
    -- handler keeps the width synced). Set on actual change so the steady state
    -- does no per-tick SetHeight.
    if W._contentH ~= barsH then
        W._contentH = barsH
        W.content:SetHeight(barsH)
    end
end

---------------------------------------------------------------------------------
-- Live geometry re-apply
--
-- Recomputes the snapped per-row geometry from the current appearance DB and, if
-- it changed, re-applies it to every pooled row (height, top-anchored stride,
-- icon square). The create-once pool is reused — NO frames are rebuilt (rebuilding
-- would leak the old frame trees). Called by DM:ApplySettings when the user drags
-- BarHeight / BarSpacing / VisibleBars / Width in the GUI.
---------------------------------------------------------------------------------
function DM:ApplyWindowGeometry(W)
    local db = self.db
    local barHeight = (db and db.BarHeight) or 16
    local barSpacing = (db and db.BarSpacing) or 2
    local snapHeight = KE:PixelSnap(barHeight)
    local snapSpacing = KE:PixelSnap(barSpacing)
    local snapStride = snapHeight + snapSpacing

    if W._snapHeight ~= snapHeight or W._snapStride ~= snapStride then
        W._snapHeight = snapHeight
        W._snapSpacing = snapSpacing
        W._snapStride = snapStride
        for i = 1, BAR_POOL_SIZE do
            local row = W.bars[i].row
            row:SetHeight(snapHeight)
            row:ClearAllPoints()
            local yOff = -(i - 1) * snapStride
            row:SetPoint("TOPLEFT", W.content, "TOPLEFT", 0, yOff)
            row:SetPoint("TOPRIGHT", W.content, "TOPRIGHT", 0, yOff)
            row.iconFrame:SetSize(snapHeight, snapHeight)
        end
    end

    -- Header band + content height (VisibleBars) absorb font-size / bar-count
    -- changes; LayoutWindow is idempotent + dirty-gated.
    self:LayoutWindow(W)
end

-- Re-applies font (header + every bar's rank/name/value) and the status-bar
-- texture to every pooled row. The cached value/name strings are NOT secret out
-- of combat; a font swap doesn't change the string, so the next Tick repaints
-- naturally. Called by DM:ApplySettings.
function DM:ReapplyBarVisuals(W)
    local db = self.db
    local face = db and db.FontFace
    local size = db and db.FontSize
    local outline = db and db.FontOutline
    local texPath = KE:GetStatusbarPath(db and db.StatusBarTexture or "KitnUI")

    KE:ApplyFontToText(W.header, face, size, outline)
    for i = 1, BAR_POOL_SIZE do
        local row = W.bars[i].row
        row.fill:SetStatusBarTexture(texPath)
        KE:ApplyFontToText(row.rank, face, size, outline)
        KE:ApplyFontToText(row.name, face, size, outline)
        KE:ApplyFontToText(row.value, face, size, outline)
    end

    -- The detail panel (Detail.lua) is lazily built once on first bar click, so it
    -- only exists after EnsureDetail has run. When present, its rows + message line
    -- must absorb the same live font/texture change as the main bars -- same
    -- pattern as the W.bars loop above (detail rows store the bar table, so the
    -- widget tree is on entry.row). Otherwise the detail panel is the lone widget
    -- set that keeps the old appearance after a GUI font/texture change.
    if W.detail then
        if W.detail.rows then
            for _, entry in ipairs(W.detail.rows) do
                local row = entry.row
                row.fill:SetStatusBarTexture(texPath)
                KE:ApplyFontToText(row.label, face, size, outline)
                KE:ApplyFontToText(row.value, face, size, outline)
            end
        end
        if W.detail.msg then
            KE:ApplyFontToText(W.detail.msg, face, size, outline)
        end
    end
end

---------------------------------------------------------------------------------
-- Render path
--
-- RenderWindow repaints one window from its current session; RenderBar fills a
-- single row. Both run on every Tick (combat-gated), so they are written to the
-- secret-value contract:
--   * width is driven by native StatusBar interpolation (SetValue accepts secret
--     values) -- NEVER any Lua arithmetic / lerp on an amount.
--   * sources are PRE-SORTED descending by the API; the loop index IS the rank.
--     Never table.sort or compare amounts.
--   * secret-aware text: SetText(secret) is fine, but == / ~= on a secret string
--     throws. So a secret string is set unconditionally and its dirty cache set
--     nil; a plain string is dirty-checked (skip SetText when unchanged).
-- Per-attribute dirty caches mirror EllesmereUI (~lines 2779-2887).
---------------------------------------------------------------------------------

-- Repaints one window. Resolves the live per-context config, sets the header to
-- a readable "<Session> <Type>" label, pulls the cached session (memoized per
-- Tick by Core), and renders up to VisibleBars (hard-clamped to the pool size)
-- bars. Bars outside the visible scroll range are shown but not re-filled
-- (virtualization); bars beyond the source count are hidden.
function DM:RenderWindow(W)
    local cfg = self:ResolveWindowConfig(W.idx)
    if not cfg or not cfg.Enabled then
        W.frame:Hide()
        return
    end
    W.frame:Show()

    -- Deaths renders differently: the value shows the death time (M:SS) and the
    -- bar carries no damage-proportional fill. Overall deaths show no time.
    -- Both are plain enum comparisons (cfg.* are config values, never secret),
    -- stashed on W for RenderBar to read without re-resolving the config per bar.
    local isDeaths = (cfg.MeterType == Enum.DamageMeterType.Deaths)
    W._isDeaths = isDeaths
    W._isOverall = (cfg.SessionType == Enum.DamageMeterSessionType.Overall)

    -- Keep the frame/viewport sized to the live appearance DB (dirty-gated, so a
    -- steady config is free). Without a size the body collapses and bars vanish.
    self:LayoutWindow(W)

    -- Header label from the enum config (nil-guarded -> sane defaults; never
    -- concatenate a nil from a missing enum key). SessionType prefixes the type
    -- name, e.g. "Overall Damage Done"; Current is the unprefixed default.
    --
    -- The label depends only on (MeterType, SessionType); both are plain enum
    -- values. Short-circuit on that identity BEFORE the concatenation so the
    -- steady state (config unchanged) allocates zero header strings per tick --
    -- only rebuild + SetText when the resolved config actually changes.
    if cfg.MeterType ~= W._headerType or cfg.SessionType ~= W._headerSession then
        W._headerType = cfg.MeterType
        W._headerSession = cfg.SessionType
        W.header:SetText(self:FormatWindowLabel(cfg.MeterType, cfg.SessionType))
    end

    local session = self:CachedSession(cfg.SessionType, cfg.MeterType)
    local sources = session and session.combatSources
    if not sources then
        -- No session/data this segment: hide every pooled row so stale bars from
        -- a prior segment don't linger. Gate on IsShown so already-hidden rows
        -- skip the redundant widget call (mirrors EllesmereUI ~2887).
        for i = 1, self.BAR_POOL_SIZE do
            local row = W.bars[i].row
            if row:IsShown() then row:Hide() end
        end
        return
    end

    -- Deaths: the API returns death sources most-recent-first and may include
    -- feign deaths (deathRecapID <= 0 = no real recap). Reverse to chronological
    -- and drop feigns into a reused per-window scratch table (no per-tick garbage).
    -- deathRecapID is NeverSecret; the issecretvalue guard mirrors EllesmereUI.
    if isDeaths then
        W._deathScratch = W._deathScratch or {}
        local rev = W._deathScratch
        for k = #rev, 1, -1 do rev[k] = nil end
        for ri = #sources, 1, -1 do
            local s = sources[ri]
            local rid = s and s.deathRecapID
            if rid and not issecretvalue(rid) and rid > 0 then
                rev[#rev + 1] = s
            end
        end
        sources = rev
    end

    -- Clamp the bar count to VisibleBars and the pool size (40). #sources is a
    -- plain length (combatSources is a normal array; only the amount FIELDS are
    -- secret), so math.min on it is safe.
    local count = math_min(#sources, (self.db and self.db.VisibleBars) or 10, self.BAR_POOL_SIZE)

    -- Visible range. Scrolling isn't wired yet (GetVerticalScroll is always 0), so
    -- visLast is the number of rows that FULLY fit in the body -- math.floor, NOT
    -- ceil. A ceil'd partial last row would be clipped at the body edge and bleed
    -- toward the next stacked window / the gap, which reads as the two windows
    -- OVERLAPPING (the Damage/Overall-Damage report). Rows past visLast are HIDDEN,
    -- not shown-but-stale, so a pane only ever shows whole, current bars. When the
    -- body isn't sized yet (first paint) render the whole set so it isn't blank.
    local stride = W._snapStride or 1
    if stride <= 0 then stride = 1 end
    local viewH = (W.body and W.body:GetHeight()) or 0
    local visLast = count
    if viewH > 0 then
        visLast = math_min(count, math.floor(viewH / stride))
    end

    -- Always-show-self: when enabled and the player is NOT within the VISIBLE rows
    -- (1..visLast), pin the player's source into the last visible slot. isLocalPlayer
    -- is NeverSecret; a source's index in the pre-sorted combatSources IS its rank
    -- (a plain integer). No arithmetic/compare on any secret amount anywhere -- the
    -- only reads are isLocalPlayer (boolean, NeverSecret) and the loop index. Keyed
    -- on visLast (the genuinely on-screen count) not the unclamped `count`, so the
    -- pin search and the slot it lands in match what's actually shown.
    local pinSource, pinRank
    if self.db and self.db.AlwaysShowSelf and visLast >= 1 then
        local inVisible = false
        for i = 1, visLast do
            local s = sources[i]
            if s and s.isLocalPlayer then inVisible = true; break end
        end
        if not inVisible then
            for i = visLast + 1, #sources do
                local s = sources[i]
                if s and s.isLocalPlayer then
                    pinSource = s
                    pinRank = i
                    break
                end
            end
        end
    end

    -- maxAmount may be secret in combat; SetMinMaxValues accepts it, and the
    -- per-bar `or 1` fallback in RenderBar hardens against a malformed session
    -- that omits it. Read once here and pass down. Rows 1..visLast are filled +
    -- shown; everything past visLast is hidden (no stale or partial bar lingers).
    local maxAmount = session.maxAmount
    for i = 1, self.BAR_POOL_SIZE do
        local bar = W.bars[i]
        local row = bar.row
        if i <= visLast then
            -- The last visible slot shows the pinned player at their real rank when
            -- AlwaysShowSelf pinned one; otherwise the slot's own source. RenderBar's
            -- `rank` arg is the displayed rank.
            local src, rank = sources[i], i
            if pinSource and i == visLast then
                src, rank = pinSource, pinRank
            end
            self:RenderBar(W, bar, rank, src, maxAmount)
            -- Show only if not already shown (mirrors EllesmereUI ~2776).
            if not row:IsShown() then row:Show() end
        else
            -- Hide only if currently shown (mirrors EllesmereUI ~2887).
            if row:IsShown() then row:Hide() end
        end
    end
end

-- Fills one bar row from a single (pre-sorted) source. `i` is the source's rank
-- (the API already sorted descending by amount -- never re-sort). Every field
-- that can be secret in combat (totalAmount, amountPerSecond, maxAmount, the
-- formatted value string, the name) is handled on the secret contract; the
-- non-secret fields (classFilename, specIconID) drive the dirty caches.
-- W carries the per-window render state RenderWindow stashed this tick
-- (W._isDeaths / W._isOverall), read below to switch the bar fill + value to the
-- deaths treatment; a later phase (detail breakdown / sticky-player row) reads it too.
function DM:RenderBar(W, bar, i, src, maxAmount)
    if not src then return end
    local row = bar.row

    -- Stash the source identity onto the bar for DM:OpenDetail (Detail.lua). All
    -- four are NeverSecret fields, so the assignments are taint-safe. deathRecapID
    -- is only meaningful in the Deaths window (nil/<=0 elsewhere); the detail
    -- renderers pick the right one off W._isDeaths. This is the "Task 2" write
    -- that Detail.lua's OpenDetail comment anticipates.
    bar._sourceGUID = src.sourceGUID
    bar._sourceCreatureID = src.sourceCreatureID
    bar._deathRecapID = src.deathRecapID
    bar._classFilename = src.classFilename

    -- self.db is stable for the lifetime of a Tick (it is the AceDB profile
    -- table, never swapped mid-Tick), so read it once and reuse the local rather
    -- than re-guarding `self.db and self.db.X` for every appearance setting.
    local db = self.db
    if not db then return end

    -- Width: native StatusBar interpolation. SetMinMaxValues + SetValue both
    -- accept secret values; ExponentialEaseOut animates the fill on the widget
    -- side so NO Lua arithmetic ever touches the secret amount. The `or` fallback
    -- is taint-safe: a secret number is truthy (never nil), so the fallback only
    -- triggers for a genuinely absent field (a malformed source) -- SetValue(0) /
    -- SetMinMaxValues(0, 1) is a far better failure mode than passing nil to a
    -- plain-Lua arithmetic widget call. Mirrors the reference's defensive nil-or.
    if W._isDeaths then
        -- Deaths: no damage-proportional fill, but the bar is FULL (SetValue 1)
        -- so the class color set below paints the whole row behind the name +
        -- M:SS time (mirrors EllesmereUI). A 0-width fill would hide the color
        -- entirely -- the bar would be invisible. No interpolation arg: deaths
        -- bars are static, so the fill snaps full immediately.
        row.fill:SetMinMaxValues(0, 1)
        row.fill:SetValue(1)
    else
        row.fill:SetMinMaxValues(0, maxAmount or 1)
        row.fill:SetValue(src.totalAmount or 0, Enum.StatusBarInterpolation.ExponentialEaseOut)
    end

    -- Fill color (dirty-cached on classFilename, which is NEVER secret). Falls
    -- back to neutral grey for an unknown/absent class. The bar fill color only
    -- changes when the source's class changes, so it stays inside the dirty cache.
    local classFile = src.classFilename
    if bar._cachedColorClass ~= classFile then
        bar._cachedColorClass = classFile
        local c = classFile and RAID_CLASS_COLORS[classFile]
        row.fill:SetStatusBarColor(c and c.r or 0.6, c and c.g or 0.6, c and c.b or 0.6)
    end

    -- Name color, dirty-cached on (classFilename, ClassColorName) -- both non-secret.
    -- Keying on the flag as well as the class means toggling ClassColorName off
    -- still repaints on the next tick even when the class is unchanged, while the
    -- steady state does no per-tick SetTextColor. Kept as its own cache (separate
    -- from the fill-color _cachedColorClass) so the two can't mask each other.
    local nameColorOn = db.ClassColorName
    if bar._cachedNameColorClass ~= classFile or bar._cachedNameColorOn ~= nameColorOn then
        bar._cachedNameColorClass = classFile
        bar._cachedNameColorOn = nameColorOn
        if nameColorOn then
            local nc = classFile and RAID_CLASS_COLORS[classFile]
            if nc then
                row.name:SetTextColor(nc.r, nc.g, nc.b)
            else
                row.name:SetTextColor(1, 1, 1)
            end
        else
            row.name:SetTextColor(1, 1, 1)
        end
    end

    -- Spec icon, dirty-cached on specIconID (NEVER secret). Keying on the SPEC
    -- icon -- not the class -- means two same-class different-spec sources (or the
    -- player pinned into a slot a same-class teammate held) get the correct spec
    -- icon rather than a stale one. Visibility is cached in bar._iconShown so a
    -- stable ShowIcon does NO per-tick Show/Hide.
    local showIcon = db.ShowIcon
    if showIcon then
        local iconID = src.specIconID
        if bar._cachedIconID ~= iconID then
            bar._cachedIconID = iconID
            row.icon:SetTexture(iconID)
            KE:ApplyIconZoom(row.icon)
        end
        if bar._iconShown ~= true then
            bar._iconShown = true
            row.iconFrame:Show()
        end
    elseif bar._iconShown ~= false then
        bar._iconShown = false
        row.iconFrame:Hide()
    end

    -- Layout (rank-gutter / icon / name LEFT anchors), dirty-gated on the
    -- (ShowIcon, ShowRank) combination so a stable config does NO per-tick
    -- re-anchor. When ShowRank is on, the rank occupies a fixed left gutter and
    -- the icon/name start to its right -- fixing the rank-label-over-icon overlap;
    -- when off, the icon (or name) sits flush at the left edge as before.
    local showRank = db.ShowRank
    local layoutKey = (showIcon and 1 or 0) + (showRank and 2 or 0)
    if bar._layoutKey ~= layoutKey then
        bar._layoutKey = layoutKey

        -- Rank gutter: left-justified within a fixed slot (width scales with the
        -- font) so the icon/name to its right start at a deterministic x.
        local gutter = KE:PixelSnap((db.FontSize or 12) + 8)
        row.rank:ClearAllPoints()
        row.rank:SetPoint("LEFT", row.fill, "LEFT", 3, 0)
        row.rank:SetWidth(showRank and gutter or 1)

        -- Icon frame: right of the rank gutter when rank is shown, else flush left.
        row.iconFrame:ClearAllPoints()
        if showRank then
            row.iconFrame:SetPoint("LEFT", row.rank, "RIGHT", 2, 0)
        else
            row.iconFrame:SetPoint("LEFT", row, "LEFT", 0, 0)
        end

        -- Name: after the icon when shown, else after the rank gutter when rank is
        -- shown, else flush at the fill's left edge.
        row.name:ClearAllPoints()
        if showIcon then
            row.name:SetPoint("LEFT", row.iconFrame, "RIGHT", 3, 0)
        elseif showRank then
            row.name:SetPoint("LEFT", row.rank, "RIGHT", 3, 0)
        else
            row.name:SetPoint("LEFT", row.fill, "LEFT", 3, 0)
        end
        row.name:SetPoint("RIGHT", row.value, "LEFT", -3, 0)
    end

    -- Name (secret-aware). In combat src.name may be secret: SetText accepts it,
    -- but == / ~= on a secret string throws, so set it unconditionally and null
    -- the cache. Out of combat it's a plain string and dirty-checked. Visibility
    -- tracks ShowName every tick so the GUI toggle takes effect on the next paint.
    local nm = src.name
    if issecretvalue(nm) then
        -- Secret name: string ops (the realm strip below) would taint-crash, so set
        -- it unconditionally and null the cache. The realm strip is confined to the
        -- plain branch; a secret name keeps its full form (graceful, no taint). In
        -- practice the names that carry a realm are friendly group members, which
        -- are the non-secret case, so the toggle takes effect where it matters.
        row.name:SetText(nm)
        bar._cachedName = nil
    else
        -- Plain string. When ShowRealm is off (default), drop the "-Realm" suffix.
        -- A character name never contains a hyphen -- the only hyphen is the realm
        -- separator -- so matching up to the first hyphen is exact and UTF-8 safe
        -- (no multibyte sequence contains the 0x2D byte). The stripped string is
        -- what gets dirty-cached, so toggling ShowRealm repaints on the next tick.
        if nm and not db.ShowRealm then
            nm = nm:match("^[^-]+") or nm
        end
        if nm ~= bar._cachedName then
            bar._cachedName = nm
            row.name:SetText(nm)
        end
    end
    -- Visibility, transition-gated (Show/Hide only on a real flip) so a stable
    -- ShowName does no per-tick widget call -- mirrors the bar._iconShown idiom.
    if db.ShowName then
        if bar._nameShown ~= true then bar._nameShown = true; row.name:Show() end
    elseif bar._nameShown ~= false then
        bar._nameShown = false
        row.name:Hide()
    end

    -- Value (secret-aware). FormatBarValue returns (string, isSecret); the string
    -- is secret in combat (built from secret amounts). Same set-unconditionally /
    -- null-cache contract as the name. ShowPerSec (read once) gates the per-second
    -- half: when false the perSec arg short-circuits without touching the secret
    -- amountPerSecond.
    -- Deaths show the death time (M:SS) instead of amount|perSec, and Overall
    -- deaths show nothing (cumulative time across segments isn't meaningful --
    -- mirrors EllesmereUI). FormatDeathTime / FormatBarValue both return
    -- (string, isSecret): a secret string is set unconditionally with the cache
    -- nulled; a plain one is dirty-checked.
    local v, vIsSecret
    if W._isDeaths then
        if W._isOverall then
            v, vIsSecret = "", false
        else
            v, vIsSecret = self.FormatDeathTime(src.deathTimeSeconds)
        end
    else
        local showPerSec = db.ShowPerSec
        v, vIsSecret = self.FormatBarValue(
            src.totalAmount,
            showPerSec and src.amountPerSecond or nil,
            showPerSec
        )
    end
    if vIsSecret then
        row.value:SetText(v)
        bar._cachedVal = nil
    elseif v ~= bar._cachedVal then
        bar._cachedVal = v
        row.value:SetText(v)
    end

    -- Rank: "N." label, dirty-cached on the displayed rank (i, passed from the
    -- render loop). Visibility tracks ShowRank every tick.
    if db.ShowRank then
        if bar._cachedSlot ~= i then
            bar._cachedSlot = i
            -- i is the displayed rank (a plain integer — never secret). A pinned
            -- player can rank beyond the 40-entry RANK_STRINGS cache, so fall back
            -- to building the label; tostring on a plain int is taint-safe.
            row.rank:SetText(self.RANK_STRINGS[i] or (i .. "."))
        end
        -- Visibility transition-gated (see ShowName above).
        if bar._rankShown ~= true then bar._rankShown = true; row.rank:Show() end
    elseif bar._rankShown ~= false then
        bar._rankShown = false
        row.rank:Hide()
    end

    -- Percent: secret in combat; left hidden for Phase 1 (ShowPercent defaults
    -- false). An out-of-combat percent is a later phase -- do NOT compute one
    -- here (would require arithmetic on amounts that are secret in combat).
end
